# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-01

### Added
- 纯协议核心库首次发布。从 `lua-resty-grpc-yar-bridge` 剥离 I/O，提取运行时无关的协议转换核心。
- `yar_grpc.codec` — gRPC 帧编解码（5 字节帧头 + protobuf payload）。
- `yar_grpc.grpc_converter` — gRPC path/method ↔ YAR method / protobuf 类型名推导（命名层，不含 pb 字段逻辑）。
- `yar_grpc.errors` — gRPC/YAR 状态码映射（Yar.error 常量对齐）。
- `yar_grpc.deadline` — grpc-timeout header 解析与检查（`now` 由调用方注入，零宿主依赖）。
- `yar_grpc.forward` — 正向转换（Yar→gRPC）：`encode_request` / `decode_response`，纯协议转换，I/O 由调用方负责。
- `yar_grpc.reverse` — 反向转换（gRPC→Yar）：`decode_request` / `encode_response`，纯协议转换，I/O 由调用方负责。
- `yar_grpc.load_pb` — proto 加载便利函数（io.open + pb.load 回退）。
- luarocks `scm-1` rockspec、busted 测试骨架、CI（test + release）参照 lua-yar。

### Changed
- 正向/反向定义反转（命名 `lua-yar-grpc`，yar 在前）：原 `bridge.lua`（gRPC→Yar）→ `reverse.lua`；原 `reverse_bridge.lua`（Yar→gRPC）→ `forward.lua`。
- `reverse.set_hooks` 改为透传入口层组装的完整 hooks（timing + 用户 pcall 隔离移至入口层 host.lua）。
- `deadline.check_expired` 接受 `now` 参数注入，不再 `require` host。

### Removed
- `host` 依赖（ngx.now / ngx.ctx / ngx.var / ngx.log）从核心层全部移除，归入口层。
- `reverse_bridge.handle()`（读 ngx.req body + 写 HTTP 响应）移至入口层。
