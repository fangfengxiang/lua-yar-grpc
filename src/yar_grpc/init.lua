-- lua-yar-grpc：gRPC ↔ YAR 协议流转换库（纯 Lua，运行时无关）
-- Pure Lua protocol stream converter between gRPC and YAR.
--
-- 定位：纯协议转换层，对标 lua-yar / dkjson / lua-MessagePack。
-- 不 import 任何 ngx.* / resty.* —— I/O（socket、读 body、写响应）由调用方负责。
-- 不创建 yar.client —— 只做 pb ↔ YAR 协议转换，传输由调用方（bridge/proxy）负责。
--
-- 模块布局（yar 在前 = 正向 = Yar→gRPC）：
--   pb_converter     pb ↔ YAR 表转换（extract_params / pack_params / map_response / extract_result）
--   codec            gRPC 帧编解码（5 字节帧头 + protobuf payload）
--   grpc_converter   gRPC path/method/类型名 ↔ YAR method（命名层，不含 pb 字段逻辑）
--   errors           gRPC/YAR 状态码映射
--   deadline         grpc-timeout header 解析与检查（now 注入）
--   forward          正向转换：YAR → gRPC（encode_request / decode_response）
--   reverse          反向转换：gRPC → YAR（decode_request / encode_response）

local pb = require("pb")

local _M = {
    _VERSION = "0.1.0",
    _NAME    = "lua-yar-grpc",
}

_M.pb_converter   = require("yar_grpc.pb_converter")
_M.codec          = require("yar_grpc.codec")
_M.grpc_converter = require("yar_grpc.grpc_converter")
_M.converter      = _M.grpc_converter  -- 向后兼容别名
_M.errors         = require("yar_grpc.errors")
_M.deadline       = require("yar_grpc.deadline")
_M.forward        = require("yar_grpc.forward")
_M.reverse        = require("yar_grpc.reverse")

--- 加载 .proto / .pb 文件到全局 pb（lua-protobuf 全局状态）
-- 便利函数：调用方装配时调用。亦可直接用 pb.loadfile / pb.load。
---@param file string .proto 或编译后的 .pb 文件路径
---@return boolean ok pb.load 返回值
---@return string|nil err io.open 失败时返回错误信息
function _M.load_pb(file)
    if not file or file == "" then
        return false, "empty file path"
    end
    -- pb.loadfile 由 lua-protobuf 提供（2.x+），优先使用
    if pb.loadfile then
        return pb.loadfile(file)
    end
    -- 回退：io.open + pb.load
    local f, err = io.open(file, "rb")
    if not f then
        return false, err or ("cannot open " .. file)
    end
    local data = f:read("*a")
    f:close()
    return pb.load(data)
end

--- 清空所有模块级缓存（proto 重新加载后调用）
function _M.clear_cache()
    _M.grpc_converter.clear_cache()
end

return _M
