-- test/proto_helper.lua
-- 加载 test/calculator.proto 到 pb 全局状态（测试辅助函数）

local protoc = require("protoc")

local _M = {}

--- 加载 calculator.proto 文件（幂等，清缓存避免 stale field name）
function _M.load_proto()
    local grpc_converter = require("yar_grpc.grpc_converter")
    grpc_converter.clear_cache()

    local p = protoc.new()
    local ok = pcall(p.loadfile, p, "test/calculator.proto")
    if not ok then
        -- 回退：loadfile 不支持时用 load + 读文件
        local f = io.open("test/calculator.proto", "r")
        if not f then
            error("cannot open test/calculator.proto")
        end
        local text = f:read("*a")
        f:close()
        local ok2, err = pcall(p.load, p, text, "calculator.proto")
        if not ok2 then
            error("failed to load calculator.proto: " .. tostring(err))
        end
    end
end

return _M
