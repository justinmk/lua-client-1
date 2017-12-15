local uv = require('luv')
local mpack = require('mpack')
local uvutil = require('uvutil')

local notify = {}

local function ext_type_index(self, k)
  local mt = getmetatable(self)
  local x = mt[k]
  if x ~= nil then
    return x
  end
  local m = 'nvim_' .. self._type .. '_' .. k
  local f = function(s, ...) return self.nvim:request_level(2, m, s, ...) end
  mt[k] = f
  return f
end

local function ext_type_eq(self, other)
  return self.id == other.id and self.nvim == other.nvim
end

local function ext_type_tostring(self)
  return self._type .. ' ' .. tostring(self.id)
end

local Buffer = {
  _type = 'buf',
  __index= ext_type_index,
  __eq = ext_type_eq,
  __tostring = ext_type_tostring,
  notify = notify
}

local Window = {
  _type = 'win',
  __index= ext_type_index,
  __eq = ext_type_eq,
  __tostring = ext_type_tostring,
  notify = notify
}

local Tabpage = {
  _type = 'tabpage',
  __index= ext_type_index,
  __eq = ext_type_eq,
  __tostring = ext_type_tostring,
  notify = notify
}

local Error = {}
Error.__index = Error
function Error.new(message) return setmetatable({message=message}, Error) end
function Error:__tostring() return self.message end


local Nvim = {
  notify = notify
}

local function new(w, r)
  local nvim = setmetatable({
      _w = w,
      _r = r,
      _closed = false,
      _proc = false,
      handlers = {},
    }, Nvim)

  local packext, unpackext = {}, {}
  for i, mt in pairs{[0] = Buffer, [1] = Window, [2] = Tabpage} do
    packext[mt] = function(o) return i, mpack.pack(o.id) end
    unpackext[i] = function(_, s) return setmetatable({id = mpack.unpack(s), nvim = nvim}, mt) end
  end
  nvim._pack = mpack.Packer({ext = packext})
  nvim._session = mpack.Session({unpack = mpack.Unpacker({ext = unpackext})})
  uv.read_start(r, function(err, chunk) return nvim:_on_read(err, chunk) end)
  return nvim
end

local function new_child(cmd, args, env)
  local stdin, stdout = uv.new_pipe(false), uv.new_pipe(false)
  local proc, pid, nvim
  proc, pid = uv.spawn(cmd, {
    stdio = {stdin, stdout, 2},
    args = args,
    env = env,
  }, function()
    if nvim then
      nvim:close()
    end
  end)
  if not proc then
    stdin:close()
    stdout:close()
    error(pid)
  end
  nvim = new(stdin, stdout)
  nvim._proc = proc
  return nvim
end

local function new_stdio()
  local stdin, stdout = uv.new_pipe(false), uv.new_pipe(false)
  stdin:open(0)
  stdout:open(1)
  return new(stdout, stdin)
end

function Nvim:close()
  if self._closed then
    return
  end
  self._closed = true
  self._r:read_stop()
  local waiters = {}
  local cb
  cb, waiters[#waiters+1] = uvutil.cb_wait()
  self._w:close(cb)
  cb, waiters[#waiters+1] = uvutil.cb_wait()
  self._r:close(cb)
  if self._proc then
    cb, waiters[#waiters+1] = uvutil.cb_wait()
    self._proc:close(cb)
  end
  for _, wait in pairs(waiters) do
    wait()
  end
end

function Nvim:__index(k)
  local mt = getmetatable(self)
  local x = mt[k]
  if x ~= nil then
    return x
  end
  local m = 'nvim_' .. k
  local f = function(nvim, ...) return nvim:request_level(2, m, ...) end
  mt[k] = f
  return f
end

function Nvim:buf(id) return setmetatable({id = id, nvim = self}, Buffer) end
function Nvim:win(id) return setmetatable({id = id, nvim = self}, Window) end
function Nvim:tabpage(id) return setmetatable({id = id, nvim = self}, Tabpage) end

local function errorHandler(e)
  if getmetatable(e) ~= Error then
    io.stderr:write(tostring(e), '\n', debug.traceback(), '\n')
  end
  return e
end

function Nvim:_on_request(id, method, args)
  local handler = self.handlers[method]
  if not handler then
    self._w:write(self._session:reply(id) .. self._pack("method not found") .. self._pack(mpack.NIL))
    return
  end
  uvutil.add_idle_call(coroutine.resume, {coroutine.create(function()
    local ok, result = xpcall(handler, errorHandler, unpack(args))
    local err, resp = mpack.NIL, mpack.NIL
    if ok then
      if result ~= nil then
        resp = result
      end
    else
      err = "Internal Error"
      if getmetatable(result) == Error then
	err = result.message
      end
      err = {0, err}
    end
    self._w:write(self._session:reply(id) .. self._pack(err) .. self._pack(resp))
  end)})
end

function Nvim:_on_notification(_, method, args)
  -- TODO run notifications in a single coroutine to ensure in order execution.
  local handler = self.handlers[method]
  if not handler then
    return
  end
  uvutil.add_idle_call(coroutine.resume, {coroutine.create(function() xpcall(handler, errorHandler, unpack(args)) end)})
end

function Nvim:_on_response(cb, err, result)
  if err == mpack.NIL then
    cb(true, result)
    return
  end

  if type(err) == 'table' and #err == 2 and type(err[2]) == 'string' then
    if err[1] == 0 then
      err = "exception: " .. err[2]
    elseif err[1] == 1 then
      err =  "validation: " .. err[2]
    end
  end
  cb(false, err)
end

function Nvim:_on_read(err, chunk)
  if err then
    error(err)
  end
  if not chunk then
    self:close()
    return
  end
  local pos, len = 1, #chunk
  while pos <= len do
    local mtype, id_or_cb, method_or_error, args_or_result
    mtype, id_or_cb, method_or_error, args_or_result, pos = self._session:receive(chunk, pos)
    if mtype ~= nil then
      -- get from metatable avoid calling methods constructed by __index.
      local f = getmetatable(self)['_on_' .. mtype]
      if not f then
        error('unknown mpack receive type: ' .. mtype)
      end
      f(self, id_or_cb, method_or_error, args_or_result)
    end
  end
end

-- request_cb sends a message to the peer and invokes cb on completion. If the
-- last argument is the sentinel value Nvim.notify, then a notification is
-- sent. Otherwise, a request is sent and cb is called (ok, reply or error).
function Nvim:request_cb(cb, method, ...)
  local args = {...}
  if #args > 0 and args[#args] == notify then
    self._w:write(self._session:notify() .. self._pack(method) .. self._pack(table.remove(args)))
    cb()
    return
  end
  self._w:write(self._session:request(cb) .. self._pack(method) .. self._pack(args))
end

-- request_level is like request_cb, except it waits for the reply from peer.
-- If the reply is an error, then error is called with the specified level.
function Nvim:request_level(level, method, ...)
  local cb, wait = uvutil.cb_wait()
  self:request_cb(cb, method, ...)
  local ok, result = wait()
  if not ok then
    error(result, level)
  end
  return result
end

-- request sends a message to the peer. If the last argument is the sentinel
-- value Nvim.notify, then a notification is sent. Otherwise, a request is sent
-- and the reply is returned.
function Nvim:request(method, ...)
  return self:request_level(3, method, ...)
end

function Nvim:error(message, level)
  error(Error.new(message), level)
end

-- call calls an Nvim function and returns teh result.
function Nvim:call(f, ...)
  return self:request_level(2, 'nvim_call_function', f, {...})
end

return {
  new = new,
  new_child = new_child,
  new_stdio = new_stdio,
  Nvim = Nvim,
  Buffer = Buffer,
  Window = Window,
  Tabpage = Tabpage,
}
