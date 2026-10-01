-- 正向转换：YAR → gRPC 方向
-- Forward conversion: YAR → gRPC
--
-- 接受 YAR 位置参数，转换为 gRPC 帧 protobuf payload。
-- 命名约定（lua-yar-grpc）：yar 在前 = 正向 = Yar→gRPC。
--
-- 纯协议转换，零 ngx.* 依赖，零 yar.client 依赖：
--   encode_request(service, method, params)  — YAR params → pb encode → gRPC frame
--   decode_response(service, method, frame)  — gRPC frame → pb decode → YAR retval
--
-- 调用方（bridge/proxy）负责实际传输：发送 frame 到 gRPC 后端，收到响应后解码。

local pb            = require("pb")
local codec         = require("yar_grpc.codec")
local grpc_converter = require("yar_grpc.grpc_converter")
local pb_converter  = require("yar_grpc.pb_converter")

---@class yar_grpc.forward
local _M = {}

--- 将 YAR 位置参数编码为 gRPC 帧
-- YAR params → pb_converter.pack_params → pb.encode → codec.encode_frame
---@param service string gRPC Service 名
---@param method string gRPC Method 名
---@param params table YAR 位置参数数组 { [1]=v1, [2]=v2, ... }
---@return string|nil frame 完整 gRPC 帧（5 字节帧头 + protobuf payload）
---@return string|nil err 编码失败时的错误信息
function _M.encode_request(service, method, params)
    local types = grpc_converter.get_type_names(service, method)

    -- 1. YAR 位置参数 → protobuf message table
    local request_table = pb_converter.pack_params(params, types.request)

    -- 2. protobuf encode（鸭子类型，pcall 隔离）
    local ok, payload = pcall(pb.encode, types.request, request_table)
    if not ok then
        return nil, "protobuf encode failed: " .. tostring(payload)
    end

    -- 3. gRPC 帧编码
    return codec.encode_frame(payload)
end

--- 将 gRPC 响应帧解码为 YAR retval
-- gRPC frame → codec.decode_frame → pb.decode → pb_converter.extract_result
---@param service string gRPC Service 名
---@param method string gRPC Method 名
---@param frame string gRPC 响应帧（5 字节帧头 + protobuf payload）
---@return any|nil retval YAR 返回值（标量 / 数组 / table）
---@return string|nil err 解码失败时的错误信息
function _M.decode_response(service, method, frame)
    local types = grpc_converter.get_type_names(service, method)

    -- 1. gRPC 帧解码
    local _, payload, _, err = codec.decode_frame(frame)
    if not payload then
        return nil, "gRPC frame decode failed: " .. tostring(err)
    end

    -- 2. protobuf decode（鸭子类型，pcall 隔离）
    local ok, response_table = pcall(pb.decode, types.response, payload)
    if not ok then
        return nil, "protobuf decode failed: " .. tostring(response_table)
    end

    -- 3. 提取 YAR retval（map_response 逆操作）
    return pb_converter.extract_result(response_table, types.response)
end

return _M
