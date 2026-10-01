-- pb_converter BDD：纯 protobuf message ↔ YAR 位置参数 / retval 转换
-- 不涉及 gRPC 帧编解码、不涉及 gRPC path/Method 命名
-- 需先加载 proto（support/proto.lua）

local pb_converter = require("yar_grpc.pb_converter")
local helper = require("spec.support.proto")

describe("yar_grpc.pb_converter (pb ↔ YAR table)", function()
    setup(function()
        helper.load_proto()
    end)

    describe("extract_params", function()
        it("extracts positional params by field number order", function()
            local decoded = { a = 3, b = 4 }
            local params, err = pb_converter.extract_params(decoded, "Calculator_AddRequest")
            assert.is_nil(err)
            assert.same({ 3, 4 }, params)
        end)

        it("fails fast on missing message field", function()
            -- message 字段未设置 → decode 为 nil → 返回错误（位置错位防御）
            local params, err = pb_converter.extract_params({}, "Calculator_AddRequest")
            assert.is_nil(params)
            assert.is_truthy(err)
        end)

        it("extracts repeated field as nested array", function()
            local decoded = { nums = { 1, 2, 3 } }
            local params = pb_converter.extract_params(decoded, "Calculator_SumRequest")
            assert.same({ { 1, 2, 3 } }, params)
        end)

        it("extracts string param", function()
            local decoded = { msg = "ping" }
            local params = pb_converter.extract_params(decoded, "Calculator_EchoRequest")
            assert.same({ "ping" }, params)
        end)
    end)

    describe("pack_params", function()
        it("packs positional array back to message table", function()
            local msg = pb_converter.pack_params({ 3, 4 }, "Calculator_AddRequest")
            assert.equal(3, msg.a)
            assert.equal(4, msg.b)
        end)

        it("encodes + decodes roundtrip via pb", function()
            local msg = pb_converter.pack_params({ 3, 4 }, "Calculator_AddRequest")
            local data = helper.encode("Calculator_AddRequest", msg)
            local back = helper.decode("Calculator_AddRequest", data)
            assert.equal(3, back.a)
            assert.equal(4, back.b)
        end)

        it("packs repeated field from nested array", function()
            local msg = pb_converter.pack_params({ { 1, 2, 3 } }, "Calculator_SumRequest")
            assert.same({ 1, 2, 3 }, msg.nums)
        end)
    end)

    describe("map_response", function()
        it("wraps scalar retval into field 1", function()
            local msg = pb_converter.map_response(42, "Calculator_AddResponse")
            assert.equal(42, msg.result)
        end)

        it("wraps array retval into repeated field 1", function()
            local msg = pb_converter.map_response({ 1, 2, 3 }, "Calculator_ListResponse")
            assert.same({ 1, 2, 3 }, msg.items)
        end)

        it("returns empty table for nil retval", function()
            local msg = pb_converter.map_response(nil, "Calculator_EchoResponse")
            assert.same({}, msg)
        end)

        it("passes association-table retval as-is", function()
            local msg = pb_converter.map_response({ msg = "hi" }, "Calculator_EchoResponse")
            assert.equal("hi", msg.msg)
        end)
    end)

    describe("extract_result", function()
        it("unwraps single-field message to scalar", function()
            local t = { result = 42 }
            assert.equal(42, pb_converter.extract_result(t, "Calculator_AddResponse"))
        end)

        it("unwraps single-field repeated message to array", function()
            local t = { items = { 1, 2, 3 } }
            assert.same({ 1, 2, 3 }, pb_converter.extract_result(t, "Calculator_ListResponse"))
        end)

        it("returns table for multi-field message", function()
            local t = { msg = "hi" }
            -- 单字段消息仍 unwrap（EchoResponse 只有 msg 一个字段）
            assert.equal("hi", pb_converter.extract_result(t, "Calculator_EchoResponse"))
        end)
    end)

    describe("clear_cache", function()
        it("clears cache without error", function()
            -- 先触发缓存填充
            pb_converter.extract_params({ a = 1, b = 2 }, "Calculator_AddRequest")
            pb_converter.map_response(1, "Calculator_AddResponse")
            -- 清缓存不应报错
            pb_converter.clear_cache()
            -- 清后仍可正常工作
            local params = pb_converter.extract_params({ a = 1, b = 2 }, "Calculator_AddRequest")
            assert.same({ 1, 2 }, params)
        end)
    end)
end)
