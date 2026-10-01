-- grpc_converter BDD：gRPC 命名 / path / 类型名推导
-- 只测试 gRPC 层函数（parse_grpc_path / method_to_yar / get_type_names / clear_cache）
-- pb 字段级转换测试已拆至 pb_converter_spec.lua
-- 需先加载 proto（support/proto.lua）

local grpc_converter = require("yar_grpc.grpc_converter")
local helper = require("spec.support.proto")

describe("yar_grpc.grpc_converter (gRPC naming / path)", function()
    setup(function()
        helper.load_proto()
    end)

    describe("get_type_names", function()
        it("derives request/response type names", function()
            local types = grpc_converter.get_type_names("Calculator", "Add")
            assert.equal("Calculator_AddRequest", types.request)
            assert.equal("Calculator_AddResponse", types.response)
        end)

        it("caches per service/method", function()
            local t1 = grpc_converter.get_type_names("Calculator", "Add")
            local t2 = grpc_converter.get_type_names("Calculator", "Add")
            -- 同一引用（缓存命中）
            assert.equal(t1, t2)
        end)

        it("derives for multiple methods", function()
            local add = grpc_converter.get_type_names("Calculator", "Add")
            local sum = grpc_converter.get_type_names("Calculator", "Sum")
            assert.equal("Calculator_SumRequest", sum.request)
            assert.equal("Calculator_SumResponse", sum.response)
            -- 不同 method 不同缓存条目
            assert.not_equal(add, sum)
        end)
    end)

    describe("clear_cache", function()
        it("clears type cache and delegates to pb_converter", function()
            -- 先触发缓存
            grpc_converter.get_type_names("Calculator", "Add")
            -- 清缓存不应报错
            assert.has_no_errors(function()
                grpc_converter.clear_cache()
            end)
            -- 清后仍可正常推导
            local types = grpc_converter.get_type_names("Calculator", "Add")
            assert.equal("Calculator_AddRequest", types.request)
        end)
    end)
end)
