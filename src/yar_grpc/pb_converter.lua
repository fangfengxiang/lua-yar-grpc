-- 纯 pb ↔ YAR 表转换层：protobuf message ↔ YAR 位置参数 / retval
-- Pure protobuf ↔ YAR table converter.
--
-- 零 gRPC 概念：不解析 gRPC path、不处理 gRPC Method 命名、不做 gRPC 帧编解码。
-- 只做 protobuf message table 与 YAR 位置参数数组 / retval 之间的映射。
-- 零 ngx.* 依赖，可在裸 LuaJIT / Lua 5.1 单测。
--
-- 纯函数：
--   extract_params(decoded, type)   — protobuf message → YAR 位置参数数组
--   pack_params(params, type)       — YAR 位置参数数组 → protobuf message table（逆操作）
--   map_response(retval, type)      — YAR retval → protobuf Response message table
--   extract_result(table, type)     — protobuf Response message → YAR retval（逆操作）
--   clear_cache()                   — 清空模块级缓存

local pb = require("pb")

---@class yar_grpc.pb_converter
local _M = {}

-- 模块级缓存：pb.fields 排序后的字段名列表（按类型名索引）
local _sorted_fields_cache = {}
-- 模块级缓存：Response 索引数组映射所需的 field 1 / repeated 字段名（按类型名索引）
local _idx_fields_cache = {}

--- 获取按 field number 升序排列的字段名列表（带缓存）
-- 供 extract_params / pack_params / extract_result 共用，消除三处重复
---@param type_name string protobuf message 类型名
---@return table field_names { [1]=name1, [2]=name2, ... }（按 number 升序）
local function get_sorted_field_names(type_name)
    local cached = _sorted_fields_cache[type_name]
    if not cached then
        local fields = {}
        for name, number in pb.fields(type_name) do
            table.insert(fields, { name = name, number = number })
        end
        table.sort(fields, function(a, b) return a.number < b.number end)
        cached = {}
        for i, f in ipairs(fields) do
            cached[i] = f.name
        end
        _sorted_fields_cache[type_name] = cached
    end
    return cached
end

--- 清空所有模块级缓存（供 init 重新加载 proto 时调用）
function _M.clear_cache()
    _sorted_fields_cache = {}
    _idx_fields_cache = {}
end

--- 按 field number 升序提取值构造位置参数数组
-- proto3 标量字段未设置时由 lua-protobuf 自动填零值（rawget 非 nil），不跳位；
-- message 类型字段未设置时 decode 为 nil，静默跳过会导致后续参数位置错位，
-- 此处 fail-fast 返回错误，由调用方映射为 INVALID_ARGUMENT(3)。
---@param decoded table pb.decode 返回的 table（field name 为 key）
---@param request_type string protobuf message 类型名
---@return table|nil params 位置参数数组 { [1]=v1, [2]=v2, ... }
---@return string|nil err message 字段缺失时的错误信息
function _M.extract_params(decoded, request_type)
    decoded = decoded or {}

    local sorted_names = get_sorted_field_names(request_type)

    local params = {}
    for _, name in ipairs(sorted_names) do
        local val = decoded[name]
        if val == nil then
            return nil, "parameter field '" .. name .. "' is required but not set"
        end
        params[#params + 1] = val
    end
    return params
end

--- 将 YAR retval 映射为 protobuf Response message table
---@param retval any YAR 返回值
---@param response_type string protobuf message 类型名
---@return table 可直接 pb.encode 的 message table
function _M.map_response(retval, response_type)
    -- nil 返回值 → 空消息（google.protobuf.Empty 或无字段消息）
    if retval == nil then
        return {}
    end

    -- 标量返回值 → 用 Response message 的第一个字段名包装（与 extract_result 对称）
    if type(retval) ~= "table" then
        local sorted_names = get_sorted_field_names(response_type)
        local key = sorted_names[1] or "result"
        return { [key] = retval }
    end

    -- 索引数组（retval[1] ~= nil）→ 优先用 field 1（仅当 repeated），其次用第一个 repeated 字段
    if retval[1] ~= nil then
        local cached = _idx_fields_cache[response_type]
        if not cached then
            local f1_name
            local f1_repeated
            local first_rep
            for name, number, _, _, label in pb.fields(response_type) do
                if number == 1 then
                    f1_name = name
                    f1_repeated = (label == "repeated" or label == "packed")
                end
                if not first_rep and (label == "repeated" or label == "packed") then
                    first_rep = name
                end
            end
            cached = { key = (f1_repeated and f1_name) or first_rep }
            _idx_fields_cache[response_type] = cached
        end
        local key = cached.key
        if key then
            return { [key] = retval }
        end
        -- 无 repeated 字段但 retval 是数组：无法安全映射，返回空表让 pb.encode 产生空消息
        return {}
    end

    -- 关联数组 → 直接作为 message table
    return retval
end

--- 将 YAR 位置参数数组还原为 protobuf message table（extract_params 的逆操作）
---@param params table YAR 位置参数数组 { [1]=v1, [2]=v2, ... }
---@param request_type string protobuf message 类型名
---@return table 可直接 pb.encode 的 message table
function _M.pack_params(params, request_type)
    params = params or {}

    local sorted_names = get_sorted_field_names(request_type)

    local message = {}
    for i, name in ipairs(sorted_names) do
        if params[i] ~= nil then
            message[name] = params[i]
        end
    end
    return message
end

--- 从 protobuf Response message 中提取 YAR retval（map_response 的逆操作）
---@param response_table table pb.decode 返回的 message table
---@param response_type string protobuf message 类型名
---@return any YAR retval（标量 / 数组 / table）
function _M.extract_result(response_table, response_type)
    response_table = response_table or {}

    local sorted_names = get_sorted_field_names(response_type)

    if #sorted_names == 0 then
        return nil
    end

    -- 单字段消息 → 解包返回标量值（对应 map_response 的标量分支）
    if #sorted_names == 1 then
        return response_table[sorted_names[1]]
    end

    -- 多字段消息 → 直接返回 table（对应 map_response 的关联数组分支）
    return response_table
end

return _M
