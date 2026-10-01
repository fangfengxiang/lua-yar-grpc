-- forward BDD（Yar → gRPC）：encode_request + decode_response 端到端
-- 验证 YAR 位置参数 → pb encode → gRPC 帧，以及 gRPC 响应帧 → pb decode → YAR retval

local pb = require("pb")
local codec = require("yar_grpc.codec")
local forward = require("yar_grpc.forward")
local helper = require("spec.support.proto")

describe("yar_grpc.forward (Yar → gRPC)", function()
    setup(function()
        helper.load_proto()
    end)

    describe("encode_request", function()
        it("encodes Add params to gRPC frame", function()
            local frame, err = forward.encode_request("Calculator", "Add", { 3, 4 })
            assert.is_nil(err)
            assert.is_truthy(frame)

            -- 解码验证：帧头 + payload
            local flag, payload = codec.decode_frame(frame)
            assert.equal(0, flag)
            local req = pb.decode("Calculator_AddRequest", payload)
            assert.equal(3, req.a)
            assert.equal(4, req.b)
        end)

        it("encodes Sum with repeated input", function()
            local frame, err = forward.encode_request("Calculator", "Sum", { { 1, 2, 3 } })
            assert.is_nil(err)
            assert.is_truthy(frame)

            local _, payload = codec.decode_frame(frame)
            local req = pb.decode("Calculator_SumRequest", payload)
            assert.same({ 1, 2, 3 }, req.nums)
        end)

        it("encodes Echo with string param", function()
            local frame = forward.encode_request("Calculator", "Echo", { "ping" })
            assert.is_truthy(frame)

            local _, payload = codec.decode_frame(frame)
            local req = pb.decode("Calculator_EchoRequest", payload)
            assert.equal("ping", req.msg)
        end)
    end)

    describe("decode_response", function()
        it("decodes AddResponse to scalar retval", function()
            -- 构造 gRPC 响应帧：AddResponse {result=7}
            local resp = pb.encode("Calculator_AddResponse", { result = 7 })
            local frame = codec.encode_frame(resp)

            local result, err = forward.decode_response("Calculator", "Add", frame)
            assert.is_nil(err)
            assert.equal(7, result)
        end)

        it("decodes SumResponse to scalar retval", function()
            local resp = pb.encode("Calculator_SumResponse", { total = 6 })
            local frame = codec.encode_frame(resp)

            local result = forward.decode_response("Calculator", "Sum", frame)
            assert.equal(6, result)
        end)

        it("decodes ListResponse to array retval", function()
            local resp = pb.encode("Calculator_ListResponse", { items = { 10, 20 } })
            local frame = codec.encode_frame(resp)

            local result = forward.decode_response("Calculator", "List", frame)
            assert.same({ 10, 20 }, result)
        end)

        it("returns error on malformed gRPC frame", function()
            local result, err = forward.decode_response("Calculator", "Add", "xx")
            assert.is_nil(result)
            assert.is_truthy(err)
        end)

        it("returns error on empty input", function()
            local result, err = forward.decode_response("Calculator", "Add", "")
            assert.is_nil(result)
            assert.is_truthy(err)
        end)
    end)

    describe("roundtrip: encode_request → decode_response", function()
        it("full roundtrip preserves data integrity", function()
            -- 构造一个模拟 gRPC 后端：收到请求帧，解码，返回响应帧
            local request_frame = forward.encode_request("Calculator", "Add", { 10, 20 })
            assert.is_truthy(request_frame)

            -- 模拟 gRPC 后端处理
            local _, payload = codec.decode_frame(request_frame)
            local req = pb.decode("Calculator_AddRequest", payload)
            local resp = pb.encode("Calculator_AddResponse", { result = req.a + req.b })
            local response_frame = codec.encode_frame(resp)

            -- 解码响应
            local result = forward.decode_response("Calculator", "Add", response_frame)
            assert.equal(30, result)
        end)
    end)
end)
