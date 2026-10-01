-- reverse BDD（gRPC → Yar）：decode_request + encode_response 端到端
-- 验证 pb decode → extract_params → method_to_yar，以及 map_response → pb encode

local pb = require("pb")
local errors = require("yar_grpc.errors")
local reverse = require("yar_grpc.reverse")
local helper = require("spec.support.proto")

describe("yar_grpc.reverse (gRPC → Yar)", function()
    setup(function()
        helper.load_proto()
    end)

    describe("decode_request", function()
        it("decodes Add request to yar method + params", function()
            local payload = pb.encode("Calculator_AddRequest", { a = 3, b = 4 })

            local yar_method, params = reverse.decode_request("Calculator", "Add", payload)

            assert.equal("add", yar_method)
            assert.same({ 3, 4 }, params)
        end)

        it("decodes List request", function()
            local payload = pb.encode("Calculator_ListRequest", { n = 5 })

            local yar_method, params = reverse.decode_request("Calculator", "List", payload)

            assert.equal("list", yar_method)
            assert.same({ 5 }, params)
        end)

        it("decodes Echo request with string param", function()
            local payload = pb.encode("Calculator_EchoRequest", { msg = "ping" })

            local yar_method, params = reverse.decode_request("Calculator", "Echo", payload)

            assert.equal("echo", yar_method)
            assert.same({ "ping" }, params)
        end)

        it("decodes Sum request with repeated field", function()
            local payload = pb.encode("Calculator_SumRequest", { nums = { 1, 2, 3 } })

            local yar_method, params = reverse.decode_request("Calculator", "Sum", payload)

            assert.equal("sum", yar_method)
            assert.same({ { 1, 2, 3 } }, params)
        end)

        it("returns INVALID_ARGUMENT on malformed protobuf", function()
            -- 0x08 = field 1 varint 但无值字节 → pb.decode 抛 "invalid varint"
            local yar_method, params, status, err = reverse.decode_request(
                "Calculator", "Add", string.char(0x08))

            assert.is_nil(yar_method)
            assert.is_nil(params)
            assert.equal(errors.INVALID_ARGUMENT, status)
            assert.is_truthy(err)
        end)
    end)

    describe("encode_response", function()
        it("encodes scalar retval to AddResponse payload", function()
            local payload, err = reverse.encode_response("Calculator", "Add", 7)
            assert.is_nil(err)
            assert.is_truthy(payload)

            local resp = pb.decode("Calculator_AddResponse", payload)
            assert.equal(7, resp.result)
        end)

        it("encodes array retval to ListResponse payload", function()
            local payload = reverse.encode_response("Calculator", "List", { 10, 20, 30 })

            local resp = pb.decode("Calculator_ListResponse", payload)
            assert.same({ 10, 20, 30 }, resp.items)
        end)

        it("encodes table retval to EchoResponse payload", function()
            local payload = reverse.encode_response("Calculator", "Echo", { msg = "pong" })

            local resp = pb.decode("Calculator_EchoResponse", payload)
            assert.equal("pong", resp.msg)
        end)

        it("encodes nil retval to empty message", function()
            local payload = reverse.encode_response("Calculator", "Add", nil)
            assert.is_truthy(payload)
        end)
    end)

    describe("roundtrip: decode_request → encode_response", function()
        it("full roundtrip: gRPC request → YAR params → YAR retval → gRPC response", function()
            -- 1. 构造 gRPC 请求 payload
            local request_payload = pb.encode("Calculator_AddRequest", { a = 15, b = 25 })

            -- 2. 解码为 YAR method + params（gRPC → YAR 请求转换）
            local yar_method, params = reverse.decode_request("Calculator", "Add", request_payload)
            assert.equal("add", yar_method)
            assert.same({ 15, 25 }, params)

            -- 3. 模拟 YAR 服务执行：params[1] + params[2]
            local yar_retval = params[1] + params[2]

            -- 4. 编码 YAR retval 为 gRPC 响应 payload（YAR → gRPC 响应转换）
            local response_payload = reverse.encode_response("Calculator", "Add", yar_retval)

            -- 5. 验证 gRPC 响应
            local resp = pb.decode("Calculator_AddResponse", response_payload)
            assert.equal(40, resp.result)
        end)
    end)
end)
