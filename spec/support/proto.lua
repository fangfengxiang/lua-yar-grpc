-- 测试辅助：加载 Calculator proto schema 到 pb 全局状态
-- 测试辅助函数与功能文件分离（见功能/测试分离规则）

local pb = require("pb")
local protoc = require("protoc")
local grpc_converter = require("yar_grpc.grpc_converter")

local _M = {}

-- Calculator 服务：覆盖标量返回 / repeated 输入 / 数组返回 / table 返回 四种 retval 形态
-- 命名遵循 grpc_converter 约定：<Service>_<Method>Request / <Service>_<Method>Response
-- 与 test/calculator.proto 保持一致
local PROTO_TEXT = [[
syntax = "proto3";

service Calculator {
  rpc Add(Calculator_AddRequest) returns (Calculator_AddResponse);
  rpc Sum(Calculator_SumRequest) returns (Calculator_SumResponse);
  rpc List(Calculator_ListRequest) returns (Calculator_ListResponse);
  rpc Echo(Calculator_EchoRequest) returns (Calculator_EchoResponse);
}

message Calculator_AddRequest  { int32 a = 1; int32 b = 2; }
message Calculator_AddResponse { int32 result = 1; }
message Calculator_SumRequest  { repeated int32 nums = 1; }
message Calculator_SumResponse { int32 total = 1; }
message Calculator_ListRequest  { int32 n = 1; }
message Calculator_ListResponse { repeated int32 items = 1; }
message Calculator_EchoRequest  { string msg = 1; }
message Calculator_EchoResponse { string msg = 1; }
]]

--- 加载 proto schema（幂等：重复加载不报错，清缓存避免 stale field name）
function _M.load_proto()
    grpc_converter.clear_cache()

    local p = protoc.new()
    local ok, err = pcall(p.load, p, PROTO_TEXT, "test.proto")
    if not ok then
        error("failed to load test proto: " .. tostring(err))
    end
end

--- 便利：pb.encode 包装
function _M.encode(type_name, t)
    return pb.encode(type_name, t)
end

--- 便利：pb.decode 包装
function _M.decode(type_name, data)
    return pb.decode(type_name, data)
end

return _M
