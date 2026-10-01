# lua-yar-grpc

[English](README.md) | [简体中文](README.zh.md)

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-yar-grpc)](https://luarocks.org/modules/fangfengxiang/lua-yar-grpc)
[![Test](https://github.com/fangfengxiang/lua-yar-grpc/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-yar-grpc/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-yar-grpc/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-yar-grpc)
[![Release](https://img.shields.io/github/v/release/fangfengxiang/lua-yar-grpc)](https://github.com/fangfengxiang/lua-yar-grpc/releases)

Pure Lua converter between **gRPC protobuf frames** and **Yar call semantics** (method / params / retval). Runtime-agnostic, zero `ngx.*` dependency, unit-testable in plain LuaJIT.

This is a **pure semantics converter** — it converts gRPC protobuf frames ↔ Yar call semantics (method name, positional params, retval shape). The Yar **binary wire format** (magic / 82-byte header / msgpack body) is owned by [`lua-yar`](https://github.com/fangfengxiang/lua-yar); transport (socket, body read/write) is owned by the caller (bridge). This library does not create `yar.client`, does not make RPC calls, and does not handle transport.

## Positioning

| Layer | Repo | Role |
|-------|------|------|
| Yar binary wire format (magic / header / msgpack) | `lua-yar` | Pack/unpack Yar protocol stream |
| gRPC frame ↔ Yar call-semantics converter (this) | `lua-yar-grpc` | Pure pb ↔ Yar semantics, runtime-agnostic |
| Bridge | `lua-resty-grpc-yar-bridge` | Transport, cosocket, orchestration |
| Platform | `lua-resty-php-beacon` *(planned)* | Service governance on OpenResty |

## Installation

```bash
luarocks install lua-yar-grpc
```

### Dependencies

- [lua-protobuf](https://github.com/starwing/lua-protobuf) >= 0.3.0
- [lua-yar](https://github.com/fangfengxiang/lua-yar) >= 0.1.2

> opm manages OpenResty packages only and does not auto-install LuaRocks packages — always run `luarocks install lua-yar-grpc` manually.

## Modules

### `yar_grpc.codec` — gRPC frame codec

5-byte header (1 compression flag + 4 big-endian length) + protobuf payload.

```lua
local codec = require("yar_grpc.codec")
local frame = codec.encode_frame(payload)        -- string → gRPC frame
local flag, payload, size, err = codec.decode_frame(body)
```

### `yar_grpc.grpc_converter` — gRPC naming / path conversion

gRPC path/method → YAR method / protobuf type names. Zero pb field logic.

```lua
local grpc_converter = require("yar_grpc.grpc_converter")
local svc, m, err = grpc_converter.parse_grpc_path("/Foo/Bar")
local yar_m = grpc_converter.method_to_yar("Add")     -- "add"
local types = grpc_converter.get_type_names("Foo", "Add")
-- types.request == "Foo_AddRequest", types.response == "Foo_AddResponse"
```

### `yar_grpc.pb_converter` — pb ↔ YAR table conversion

Pure protobuf message ↔ YAR positional params / retval mapping. Zero gRPC concepts (no path, no frame).

```lua
local pb_converter = require("yar_grpc.pb_converter")
local params = pb_converter.extract_params(decoded, "Foo_AddRequest")
local msg = pb_converter.pack_params({ 3, 4 }, "Foo_AddRequest")
local resp = pb_converter.map_response(42, "Foo_AddResponse")
local retval = pb_converter.extract_result(resp_table, "Foo_AddResponse")
```

### `yar_grpc.errors` — status code mapping

```lua
local errors = require("yar_grpc.errors")
local status, msg = errors.map_yar_error(err)    -- YAR Error → gRPC status
```

### `yar_grpc.deadline` — grpc-timeout parsing

`now` is injected by the caller; the core holds no host time source.

```lua
local deadline = require("yar_grpc.deadline")
local ms = deadline.parse_timeout("100m")        -- 100
local expired = deadline.check_expired(ms, start, now)
```

### `yar_grpc.forward` — forward conversion (Yar → gRPC)

Converts YAR positional params to gRPC frames, and gRPC response frames back to YAR retval.

```lua
local forward = require("yar_grpc.forward")

-- YAR params → gRPC frame (send to gRPC backend)
local frame, err = forward.encode_request("Calculator", "Add", { 3, 4 })

-- gRPC response frame → YAR retval (return to YAR caller)
local result, err = forward.decode_response("Calculator", "Add", response_frame)
```

### `yar_grpc.reverse` — reverse conversion (gRPC → Yar)

Converts gRPC request payloads to YAR method + params, and YAR retval back to gRPC response payloads.

```lua
local reverse = require("yar_grpc.reverse")

-- gRPC payload → YAR method + params (call YAR service yourself)
local yar_method, params, status, err = reverse.decode_request(
    "Calculator", "Add", grpc_payload)

-- YAR retval → gRPC response payload (return to gRPC caller)
local payload, err = reverse.encode_response("Calculator", "Add", yar_retval)
```

## Usage pattern

The caller (bridge/proxy) is responsible for transport:

```lua
local yar_grpc = require("yar_grpc")

-- Forward (YAR → gRPC): YAR server proxying to gRPC backend
local frame = yar_grpc.forward.encode_request(svc, method, params)
local response = send_to_grpc_backend(frame)     -- caller handles transport
local retval = yar_grpc.forward.decode_response(svc, method, response)

-- Reverse (gRPC → YAR): gRPC server proxying to YAR backend
local yar_method, params = yar_grpc.reverse.decode_request(svc, method, payload)
local yar_retval = yar_client:call(yar_method, params)  -- caller handles transport
local grpc_payload = yar_grpc.reverse.encode_response(svc, method, yar_retval)
```

## License

[Apache-2.0](LICENSE)
