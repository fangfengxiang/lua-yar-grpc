# lua-yar-grpc

[English](README.md) | [简体中文](README.zh.md)

[![Lua](https://img.shields.io/badge/Lua-%3E%3D5.1-blue.svg)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)
[![LuaRocks](https://img.shields.io/luarocks/v/fangfengxiang/lua-yar-grpc)](https://luarocks.org/modules/fangfengxiang/lua-yar-grpc)
[![Test](https://github.com/fangfengxiang/lua-yar-grpc/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/fangfengxiang/lua-yar-grpc/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/fangfengxiang/lua-yar-grpc/branch/main/graph/badge.svg)](https://codecov.io/gh/fangfengxiang/lua-yar-grpc)
[![Release](https://img.shields.io/github/v/release/fangfengxiang/lua-yar-grpc)](https://github.com/fangfengxiang/lua-yar-grpc/releases)

纯 Lua 实现的 **gRPC protobuf 帧** ↔ **Yar 调用语义**（method / params / retval）转换器。运行时无关，零 `ngx.*` 依赖，可在纯 LuaJIT 中直接单测。

本库是**纯语义转换器**——只做 gRPC protobuf 帧 ↔ Yar 调用语义（方法名、位置参数、返回值结构）的转换。Yar **二进制线格式**（magic / 82 字节头 / msgpack 包体）由 [`lua-yar`](https://github.com/fangfengxiang/lua-yar) 负责；传输层（socket、body 读写）由调用方（bridge）负责。本库不创建 `yar.client`、不发起 RPC 调用、不处理传输。

## 定位

| 层 | 仓库 | 职责 |
|----|------|------|
| Yar 二进制线格式（magic / header / msgpack） | `lua-yar` | Yar 协议流打包/解包 |
| gRPC 帧 ↔ Yar 调用语义转换器（本库） | `lua-yar-grpc` | 纯 pb ↔ Yar 语义，运行时无关 |
| 桥接层 | `lua-resty-grpc-yar-bridge` | 传输、cosocket、编排 |
| 平台 | `lua-resty-php-beacon`（规划中） | OpenResty 上的服务治理 |

## 安装

```bash
luarocks install lua-yar-grpc
```

### 依赖

- [lua-protobuf](https://github.com/starwing/lua-protobuf) >= 0.3.0
- [lua-yar](https://github.com/fangfengxiang/lua-yar) >= 0.1.2

> opm 只管理 OpenResty 生态包，不会自动安装 luarocks 包——请手动执行 `luarocks install lua-yar-grpc`。

## 模块

### `yar_grpc.codec` — gRPC 帧编解码

5 字节头（1 字节压缩标志 + 4 字节大端长度）+ protobuf 负载。

```lua
local codec = require("yar_grpc.codec")
local frame = codec.encode_frame(payload)        -- string → gRPC frame
local flag, payload, size, err = codec.decode_frame(body)
```

### `yar_grpc.grpc_converter` — gRPC 命名/路径转换

gRPC 路径/方法 → YAR 方法名 / protobuf 类型名。零 pb 字段逻辑。

```lua
local grpc_converter = require("yar_grpc.grpc_converter")
local svc, m, err = grpc_converter.parse_grpc_path("/Foo/Bar")
local yar_m = grpc_converter.method_to_yar("Add")     -- "add"
local types = grpc_converter.get_type_names("Foo", "Add")
-- types.request == "Foo_AddRequest", types.response == "Foo_AddResponse"
```

### `yar_grpc.pb_converter` — pb ↔ YAR table 转换

纯 protobuf 消息 ↔ YAR 位置参数/返回值映射。零 gRPC 概念（无路径、无帧）。

```lua
local pb_converter = require("yar_grpc.pb_converter")
local params = pb_converter.extract_params(decoded, "Foo_AddRequest")
local msg = pb_converter.pack_params({ 3, 4 }, "Foo_AddRequest")
local resp = pb_converter.map_response(42, "Foo_AddResponse")
local retval = pb_converter.extract_result(resp_table, "Foo_AddResponse")
```

### `yar_grpc.errors` — 状态码映射

```lua
local errors = require("yar_grpc.errors")
local status, msg = errors.map_yar_error(err)    -- YAR Error → gRPC status
```

### `yar_grpc.deadline` — grpc-timeout 解析

`now` 由调用方注入；核心模块不持有宿主时间源。

```lua
local deadline = require("yar_grpc.deadline")
local ms = deadline.parse_timeout("100m")        -- 100
local expired = deadline.check_expired(ms, start, now)
```

### `yar_grpc.forward` — 正向转换（Yar → gRPC）

YAR 位置参数 → gRPC 帧；gRPC 响应帧 → YAR 返回值。

```lua
local forward = require("yar_grpc.forward")

-- YAR params → gRPC 帧（发往 gRPC 后端）
local frame, err = forward.encode_request("Calculator", "Add", { 3, 4 })

-- gRPC 响应帧 → YAR 返回值（返回给 YAR 调用方）
local result, err = forward.decode_response("Calculator", "Add", response_frame)
```

### `yar_grpc.reverse` — 反向转换（gRPC → Yar）

gRPC 请求负载 → YAR 方法 + 参数；YAR 返回值 → gRPC 响应负载。

```lua
local reverse = require("yar_grpc.reverse")

-- gRPC 负载 → YAR 方法 + 参数（由你自行调用 YAR 服务）
local yar_method, params, status, err = reverse.decode_request(
    "Calculator", "Add", grpc_payload)

-- YAR 返回值 → gRPC 响应负载（返回给 gRPC 调用方）
local payload, err = reverse.encode_response("Calculator", "Add", yar_retval)
```

## 使用模式

传输由调用方（bridge/proxy）负责：

```lua
local yar_grpc = require("yar_grpc")

-- 正向（YAR → gRPC）：YAR server 代理到 gRPC 后端
local frame = yar_grpc.forward.encode_request(svc, method, params)
local response = send_to_grpc_backend(frame)     -- 传输由调用方处理
local retval = yar_grpc.forward.decode_response(svc, method, response)

-- 反向（gRPC → YAR）：gRPC server 代理到 YAR 后端
local yar_method, params = yar_grpc.reverse.decode_request(svc, method, payload)
local yar_retval = yar_client:call(yar_method, params)  -- 传输由调用方处理
local grpc_payload = yar_grpc.reverse.encode_response(svc, method, yar_retval)
```

## License

[Apache-2.0](LICENSE)
