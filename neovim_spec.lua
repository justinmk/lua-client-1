expose('require uv once to prevent segfault', function()
  require('luv')
end)

local neovim = require('neovim')

describe('nvim client', function()
  local nvim
  setup(function()
    nvim = neovim.new_child('nvim', {'--embed', '-u', 'NORC'})
  end)

  teardown(function()
    if nvim then
      nvim:close()
    end
  end)

  it('can call to nvim', function()
    assert.are.equal(3, nvim:eval('1 + 2'))
  end)

  it('can handle requests from nvim', function()
    local channel = nvim:get_api_info()[1]
    local arg
    nvim.handlers = {request_test = function(a) arg = a return 'world' end}
    assert.are.equal('world', nvim:call('rpcrequest', channel, 'request_test', 'hello'))
    assert.are.equal('hello', arg)
  end)

  it('can handle notifications from nvim', function()
    local channel = nvim:get_api_info()[1]
    local arg
    nvim.handlers = {request_test = function(a) arg = a end}
    nvim:call('rpcnotify', channel, 'request_test', 'hello')
    nvim:get_api_info() -- ensure that notify was received
    assert.are.equal('hello', arg)
  end)

  --[[
  it('can receive errors from nvim', function()
    local channel = nvim:get_api_info()[1]
    local arg
    nvim.handlers['request-test'] = function(a) error(nvim.Error.new('blah')) end
    assert.has_error(function() nvim:call_function('rpcrequest', {channel, 'request-test', 'hello'}) end, 'blah')
  end)
  ]]--

  describe('buf', function()

    it('can compare eq', function()
      local bufs1 = nvim:list_bufs()
      local bufs2 = nvim:list_bufs()
      assert.are.equal(bufs1[1], bufs2[1])
    end)

    it('constructor works', function()
      local bufs = nvim:list_bufs()
      local b = nvim:buf(bufs[1].id)
      assert.are.equal(bufs[1], b)
    end)

    it('not eq win', function()
      local b = nvim:buf(1)
      local w = nvim:win(1)
      assert.are_not.equal(b, w)
    end)

    it('method works', function()
      local buf = nvim:get_current_buf()
      assert.are.equal(1, buf:line_count())
    end)

  end)

end)
