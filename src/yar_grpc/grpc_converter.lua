-- gRPC 命名 / path 转换层：gRPC Service/Method/path ↔ YAR method / pb 类型名
-- gRPC naming / path conversion layer.
--
-- 职责：gRPC path 解析、gRPC Method → YAR method 命名映射、
--       gRPC Service/Method → protobuf Request/Response 类型名推导。
-- 不含 pb 字段级转换（extract_params / pack_params / map_response / extract_result
-- 已拆至 pb_converter.lua）。
--
-- 零 ngx.* 依赖，可在裸 LuaJIT / Lua 5.1 单测。
--
-- 纯函数：
--   parse_grpc_path(path)           — 解析 /{Service}/{Method}
--   method_to_yar(method)           — gRPC Method → YAR method（首字母小写）
--   get_type_names(service, method) — 获取 Request/Response 类型名（带缓存）
--   clear_cache()                   — 清空类型名缓存 + 委托 pb_converter.clear_cache

local pb_converter = require("yar_grpc.pb_converter")

---@class yar_grpc.grpc_converter
local _M = {}

-- 模块级缓存：类型名字符串拼接结果按 service/method 缓存
local _type_cache = {}

--- 清空类型名缓存 + 委托 pb_converter 清空字段缓存（proto 重新加载后调用）
function _M.clear_cache()
    _type_cache = {}
    pb_converter.clear_cache()
end

--- 从 `/{Service}/{Method}` 解析出 Service 和 Method
---@param path string gRPC request path (e.g. /Service/Method)
---@return string|nil service
---@return string|nil method
---@return string|nil err 错误信息
function _M.parse_grpc_path(path)
    if not path or path == "" then
        return nil, nil, "invalid gRPC path: empty"
    end
    -- 去除前导 / 并匹配 {Service}/{Method} 格式
    local service, method = path:match("^/+([^/]+)/([^/]+)$")
    if not service or not method or service == "" or method == "" then
        return nil, nil, "invalid gRPC path: " .. (path or "nil")
    end
    return service, method
end

--- 将 gRPC Method 名首字母小写作为 YAR method 名
---@param method string gRPC Method 名（如 "Add"）
---@return string YAR method 名（如 "add"）
function _M.method_to_yar(method)
    if not method or #method == 0 then
        return method
    end
    local first = method:sub(1, 1):lower()
    local rest  = method:sub(2)
    return first .. rest
end

--- 获取 Request/Response 类型名（带缓存，避免每请求字符串拼接）
---@param service string gRPC Service 名
---@param method string gRPC Method 名
---@return table { request = string, response = string }
function _M.get_type_names(service, method)
    local cache_key = service .. "/" .. method
    local types = _type_cache[cache_key]
    if not types then
        types = {
            request  = service .. "_" .. method .. "Request",
            response = service .. "_" .. method .. "Response",
        }
        _type_cache[cache_key] = types
    end
    return types
end

return _M
