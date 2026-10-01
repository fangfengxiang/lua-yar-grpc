-- 反向转换：gRPC → YAR 方向
-- Reverse conversion: gRPC → YAR
--
-- 接受 gRPC 请求（protobuf payload），转换为 YAR 调用参数；接受 YAR retval，转换为 gRPC 响应。
-- 命名约定（lua-yar-grpc）：grpc 在后 = 反向 = gRPC→YAR。
--
-- 纯协议转换，零 ngx.* 依赖，零 yar.client 依赖：
--   decode_request(service, method, payload)  — pb decode → extract_params → 返回 YAR method + params
--   encode_response(service, method, retval)  — map_response → pb encode → 返回 gRPC payload
--
-- 调用方（bridge/proxy）负责实际传输：用返回的 method+params 调用 YAR 服务，收到 retval 后编码为 gRPC 响应。

local pb            = require("pb")
local errors        = require("yar_grpc.errors")
local grpc_converter = require("yar_grpc.grpc_converter")
local pb_converter  = require("yar_grpc.pb_converter")

---@class yar_grpc.reverse
local _M = {}

--- 将 gRPC 请求 payload 解码为 YAR method + 位置参数
-- pb.decode → pb_converter.extract_params → grpc_converter.method_to_yar
---@param service string gRPC Service 名
---@param method string gRPC Method 名
---@param payload string protobuf 编码的请求 payload
---@return string|nil yar_method YAR method 名（首字母小写）
---@return table|nil params YAR 位置参数数组
---@return integer|nil status gRPC 状态码（失败时）
---@return string|nil err 错误信息（失败时）
function _M.decode_request(service, method, payload)
    local types = grpc_converter.get_type_names(service, method)

    -- 1. protobuf decode 请求（鸭子类型，pcall 隔离）
    local ok, decoded = pcall(pb.decode, types.request, payload)
    if not ok then
        return nil, nil, errors.INVALID_ARGUMENT, "protobuf decode failed: " .. tostring(decoded)
    end

    -- 2. 提取位置参数（message 字段缺失时 fail-fast）
    local params, perr = pb_converter.extract_params(decoded, types.request)
    if not params then
        return nil, nil, errors.INVALID_ARGUMENT, perr
    end

    -- 3. gRPC Method → YAR method（首字母小写）
    local yar_method = grpc_converter.method_to_yar(method)
    return yar_method, params
end

--- 将 YAR retval 编码为 gRPC 响应 payload
-- pb_converter.map_response → pb.encode
---@param service string gRPC Service 名
---@param method string gRPC Method 名
---@param retval any YAR 返回值（标量 / 数组 / table）
---@return string|nil payload protobuf 编码的响应 payload
---@return string|nil err 编码失败时的错误信息
function _M.encode_response(service, method, retval)
    local types = grpc_converter.get_type_names(service, method)

    -- 1. 映射 YAR retval → protobuf Response message table
    local response_table = pb_converter.map_response(retval, types.response)

    -- 2. protobuf encode（鸭子类型，pcall 隔离）
    local ok, payload = pcall(pb.encode, types.response, response_table)
    if not ok then
        return nil, "protobuf encode failed: " .. tostring(payload)
    end

    return payload
end

return _M
