# lua-client

Lua-Client is a Neovim client and remote plugin host.

### Setup

1. Install this repo as a Neovim plugin using your plugin manager of choice.
1. Install the lua modules: luv mpack

### Development 

The development environment requires the following rocks: busted, luacheck

The script setup.sh sets up a development environment using [hererocks](https://github.com/mpeterv/hererocks#readme).

### Example

See [garyburd/neols](https://github.com/garyburd/neols#readme).

# Documentation

## Module neovim

### Type Nvim

The `Nvim` type is an Nvim client.

### Type Buffer, Window, Tabpage

The Buffer, Window and Tabpage types are returned by several Nvim client
methods. Applications can construct values of these types using the
`Nvim:buf(id)`, `Nvim:win(id)` and `Nvim:tabpage(id)` methods.

These types each have two fields: `id` is the integer identifier of the entity
and `nvim` is the `Nvim` client that created the entity.

### new(w, r) -> Nvim

Creates a new client given a write and read
[uv\_stream\_t](https://github.com/luvit/luv/blob/master/docs.md#uv_stream_t--stream-handle)
handles.

### new\_child(cmd, [args, [env]]) -> Nvim

Creates a child process running the command `cmd` and returns a client connected
to the child. Call `Nvim:close()` to end the child process. Use array `args` to
specify the command line arguments and table `env` to specify the environment.
The `args` array should typically include `--embed`. If `env` is not set, then
the child process environment is inherited from the current process.

### new\_stdio() -> Nvim

Create client connected to stdin and stdout of the current process.

### Nvim.handlers

The client dispatches incoming requests and notifications using this table. The
keys are method names and the values are the function to call.

### Nvim:buf(id) -> Buffer

Return a `Buffer` given the buffer's integer id. 

### Nvim:win(id) -> Window

Return a `Window` given the window's integer id.

### Nvim:tabpage(id) -> Tabpage

Return a `Tabpage` given the tabpage's integer id.

### Nvim:request(method, ...) -> result

Send RPC API request to Nvim. Normally a blocking request is sent. If the last
argument is the sentinel value `Nvim.async`, then an asynchronous
notification is sent instead and any error returned from the method is ignored. 

Nvim RPC API methods can also be called as methods on the Nvim, Buffer, Window
and Tabpage types. The following calls are identical:

    nvim:request('nvim_buf_set_var', buf, 'x', 1)
    nvim:buf_set_var(buf, 'x', 1)   -- call method with nvim_ prefix removed
    buf:set_var('x', 1)             -- call method with nvim_buf_ prefix removed.

### Nvim:call(funcname, ...) -> result

Call vim function `funcname` with args `...` and return the result. This method
is a helper for the following where `args` is an array:

    nvim:call_function(funcname, args)

### Nvim:close()

Close the connection to Nvim. If the nvim process was started by `new_child()`,
then the child process is closed.

## Module Plugin

### Type Host

Host is the remote plugin host.

### Type Plugin

Plugin represents an individual plugin.

### new_host(Nvim) -> Host

### Host:get_plugin(path) -> Plugin

### Plugin:load_script(path) -> specs, handlers

