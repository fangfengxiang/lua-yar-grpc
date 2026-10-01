-- test/grpc_e2e_test.lua
-- 端到端测试：gRPC 帧 ↔ YAR 协议 JSON
--
-- 场景：Calculator 服务，覆盖标量 / repeated 输入 / 数组返回 / string 四种 retval 形态
--
-- 测试 gRPC 层：forward（YAR→gRPC 帧）+ reverse（pb→YAR）+ codec（gRPC 帧编解码）
-- 与 pb_e2e_test.lua 的区别：这里走完整的 gRPC 帧管线（5 字节帧头 + pb payload）
--
-- 管线：
--   YAR → gRPC:  YAR JSON → json.unpack → forward.encode_request → gRPC 帧
--   gRPC → YAR:  gRPC 帧 → codec.decode_frame → reverse.decode_request → YAR JSON
--
-- 运行：busted test/grpc_e2e_test.lua

local pb        = require("pb")
local codec     = require("yar_grpc.codec")
local forward   = require("yar_grpc.forward")
local reverse   = require("yar_grpc.reverse")
local helper    = require("test.proto_helper")

-- lua-yar JSON packager：真实 YAR 协议 JSON 编解码
local Yar  = require("yar")
local json = Yar.get_packager(Yar.PACKAGER_JSON)

local M = {}

local function hex_dump(s)
    local out = {}
    for i = 1, #s do
        out[i] = string.format("%02x", s:byte(i))
    end
    return table.concat(out, " ")
end

-- ============================================================
-- 请求方向：YAR → gRPC 请求帧
-- ============================================================

-- 测试：YAR 协议 JSON → gRPC 请求帧（Add 标量参数）
local function test_yar_json_to_grpc_request_add()
    local yar_json = json.pack({ i = 1001, m = "add", p = { 1, 2 } })
    print("  [输入] YAR 协议 JSON: " .. yar_json)

    local unpacked = json.unpack(yar_json)
    assert(unpacked.m == "add", "method should be 'add'")
    assert(unpacked.p[1] == 1, "params[1] should be 1")
    assert(unpacked.p[2] == 2, "params[2] should be 2")

    local grpc_method = "Add"
    local frame, err = forward.encode_request("Calculator", grpc_method, unpacked.p)
    assert(frame, "encode_request failed: " .. tostring(err))

    print("  [输出] gRPC 请求帧 (hex): " .. hex_dump(frame))

    local flag, payload, _, ferr = codec.decode_frame(frame)
    assert(payload, "decode_frame failed: " .. tostring(ferr))
    assert(flag == codec.COMPRESSION_NONE, "frame should not be compressed")

    local req = pb.decode("Calculator_AddRequest", payload)
    assert(req.a == 1, "AddRequest.a should be 1")
    assert(req.b == 2, "AddRequest.b should be 2")

    print("  [验证] gRPC frame → AddRequest{a=" .. req.a .. ", b=" .. req.b .. "}")
end

-- 测试：YAR 协议 JSON → gRPC 请求帧（Sum repeated 输入）
local function test_yar_json_to_grpc_request_sum()
    local yar_json = json.pack({ i = 1002, m = "sum", p = { { 1, 2, 3 } } })
    print("  [输入] YAR 协议 JSON: " .. yar_json)

    local unpacked = json.unpack(yar_json)
    assert(unpacked.m == "sum", "method should be 'sum'")

    local frame, err = forward.encode_request("Calculator", "Sum", unpacked.p)
    assert(frame, "encode_request failed: " .. tostring(err))

    print("  [输出] gRPC 请求帧 (hex): " .. hex_dump(frame))

    local _, payload = codec.decode_frame(frame)
    local req = pb.decode("Calculator_SumRequest", payload)
    assert.same({ 1, 2, 3 }, req.nums, "SumRequest.nums should be {1,2,3}")

    print("  [验证] gRPC frame → SumRequest{nums={1,2,3}}")
end

-- 测试：YAR 协议 JSON → gRPC 请求帧（Echo string 参数）
local function test_yar_json_to_grpc_request_echo()
    local yar_json = json.pack({ i = 1003, m = "echo", p = { "ping" } })
    print("  [输入] YAR 协议 JSON: " .. yar_json)

    local unpacked = json.unpack(yar_json)
    assert(unpacked.m == "echo", "method should be 'echo'")

    local frame, err = forward.encode_request("Calculator", "Echo", unpacked.p)
    assert(frame, "encode_request failed: " .. tostring(err))

    print("  [输出] gRPC 请求帧 (hex): " .. hex_dump(frame))

    local _, payload = codec.decode_frame(frame)
    local req = pb.decode("Calculator_EchoRequest", payload)
    assert.equal("ping", req.msg, "EchoRequest.msg should be 'ping'")

    print("  [验证] gRPC frame → EchoRequest{msg='ping'}")
end

-- ============================================================
-- 请求方向：gRPC 请求帧 → YAR 协议 JSON
-- ============================================================

-- 测试：gRPC 请求帧 → YAR 协议 JSON（Add）
local function test_grpc_request_to_yar_json_add()
    local pb_payload = pb.encode("Calculator_AddRequest", { a = 1, b = 2 })
    local grpc_frame = codec.encode_frame(pb_payload)

    print("  [输入] gRPC 请求帧 (hex): " .. hex_dump(grpc_frame))

    local _, payload, _, ferr = codec.decode_frame(grpc_frame)
    assert(payload, "decode_frame failed: " .. tostring(ferr))

    local yar_method, params, _, rerr = reverse.decode_request(
        "Calculator", "Add", payload)
    assert(yar_method, "decode_request failed: " .. tostring(rerr))
    assert(yar_method == "add", "method should be 'add'")
    assert(params[1] == 1, "params[1] should be 1")
    assert(params[2] == 2, "params[2] should be 2")

    local yar_json = json.pack({ i = 1001, m = yar_method, p = params })
    assert(yar_json:match('"m":"add"'), "json should contain method 'add'")
    assert(yar_json:match('"p":%[1,2%]'), "json should contain params [1,2]")

    print("  [输出] YAR 协议 JSON: " .. yar_json)
end

-- 测试：gRPC 请求帧 → YAR 协议 JSON（Sum repeated）
local function test_grpc_request_to_yar_json_sum()
    local pb_payload = pb.encode("Calculator_SumRequest", { nums = { 10, 20, 30 } })
    local grpc_frame = codec.encode_frame(pb_payload)

    print("  [输入] gRPC 请求帧 (hex): " .. hex_dump(grpc_frame))

    local _, payload = codec.decode_frame(grpc_frame)
    local yar_method, params = reverse.decode_request("Calculator", "Sum", payload)
    assert(yar_method == "sum", "method should be 'sum'")
    assert.same({ 10, 20, 30 }, params[1], "params[1] should be {10,20,30}")

    local yar_json = json.pack({ i = 1002, m = yar_method, p = params })
    assert(yar_json:match('"m":"sum"'), "json should contain method 'sum'")

    print("  [输出] YAR 协议 JSON: " .. yar_json)
end

-- ============================================================
-- 响应方向：gRPC 响应帧 → YAR retval → YAR 响应 JSON
-- ============================================================

-- 测试：gRPC 响应帧 → YAR retval（Add 标量返回）
local function test_grpc_response_to_yar_retval_add()
    local resp_payload = pb.encode("Calculator_AddResponse", { result = 3 })
    local response_frame = codec.encode_frame(resp_payload)

    print("  [输入] gRPC 响应帧 (hex): " .. hex_dump(response_frame))

    local retval, err = forward.decode_response("Calculator", "Add", response_frame)
    assert(retval, "decode_response failed: " .. tostring(err))
    assert(retval == 3, "retval should be 3, got " .. tostring(retval))

    local yar_resp_json = json.pack({ i = 1001, s = 0, r = retval, o = "" })
    assert(yar_resp_json:match('"r":3'), "response json should contain r:3")

    print("  [输出] gRPC AddResponse{result=3} → YAR retval " .. tostring(retval) ..
        " → JSON: " .. yar_resp_json)
end

-- 测试：gRPC 响应帧 → YAR retval（List 数组返回）
local function test_grpc_response_to_yar_retval_list()
    local resp_payload = pb.encode("Calculator_ListResponse", { items = { 10, 20 } })
    local response_frame = codec.encode_frame(resp_payload)

    print("  [输入] gRPC 响应帧 (hex): " .. hex_dump(response_frame))

    local retval, err = forward.decode_response("Calculator", "List", response_frame)
    assert(retval, "decode_response failed: " .. tostring(err))
    assert.same({ 10, 20 }, retval, "retval should be {10,20}")

    print("  [输出] gRPC ListResponse{items={10,20}} → YAR retval {" ..
        table.concat(retval, ",") .. "}")
end

-- ============================================================
-- 响应方向：YAR retval → gRPC 响应帧
-- ============================================================

-- 测试：YAR retval → gRPC 响应帧（Add 标量返回）
local function test_yar_retval_to_grpc_response_add()
    local yar_retval = 3

    local pb_payload = reverse.encode_response("Calculator", "Add", yar_retval)
    assert(pb_payload, "encode_response should produce pb payload")

    local grpc_frame = codec.encode_frame(pb_payload)
    assert(grpc_frame, "encode_frame should produce a gRPC frame")

    print("  [输出] gRPC 响应帧 (hex): " .. hex_dump(grpc_frame))

    local _, payload, _, ferr = codec.decode_frame(grpc_frame)
    assert(payload, "decode_frame failed: " .. tostring(ferr))

    local resp = pb.decode("Calculator_AddResponse", payload)
    assert(resp.result == 3, "AddResponse.result should be 3, got " .. tostring(resp.result))

    print("  [验证] YAR retval " .. tostring(yar_retval) ..
        " → gRPC AddResponse{result=" .. resp.result .. "}")
end

-- 测试：YAR retval → gRPC 响应帧（List 数组返回）
local function test_yar_retval_to_grpc_response_list()
    local yar_retval = { 10, 20, 30 }

    local pb_payload = reverse.encode_response("Calculator", "List", yar_retval)
    assert(pb_payload, "encode_response should produce pb payload")

    local grpc_frame = codec.encode_frame(pb_payload)
    assert(grpc_frame, "encode_frame should produce a gRPC frame")

    print("  [输出] gRPC 响应帧 (hex): " .. hex_dump(grpc_frame))

    local _, payload = codec.decode_frame(grpc_frame)
    local resp = pb.decode("Calculator_ListResponse", payload)
    assert.same({ 10, 20, 30 }, resp.items, "ListResponse.items should be {10,20,30}")

    print("  [验证] YAR retval {10,20,30} → gRPC ListResponse{items={10,20,30}}")
end

-- 测试：YAR retval → gRPC 响应帧（Echo table 返回）
local function test_yar_retval_to_grpc_response_echo()
    local yar_retval = { msg = "pong" }

    local pb_payload = reverse.encode_response("Calculator", "Echo", yar_retval)
    assert(pb_payload, "encode_response should produce pb payload")

    local grpc_frame = codec.encode_frame(pb_payload)
    assert(grpc_frame, "encode_frame should produce a gRPC frame")

    print("  [输出] gRPC 响应帧 (hex): " .. hex_dump(grpc_frame))

    local _, payload = codec.decode_frame(grpc_frame)
    local resp = pb.decode("Calculator_EchoResponse", payload)
    assert.equal("pong", resp.msg, "EchoResponse.msg should be 'pong'")

    print("  [验证] YAR retval {msg='pong'} → gRPC EchoResponse{msg='pong'}")
end

function M.run()
    helper.load_proto()

    -- 请求方向：YAR → gRPC
    test_yar_json_to_grpc_request_add()
    test_yar_json_to_grpc_request_sum()
    test_yar_json_to_grpc_request_echo()

    -- 请求方向：gRPC → YAR
    test_grpc_request_to_yar_json_add()
    test_grpc_request_to_yar_json_sum()

    -- 响应方向：gRPC → YAR
    test_grpc_response_to_yar_retval_add()
    test_grpc_response_to_yar_retval_list()

    -- 响应方向：YAR → gRPC
    test_yar_retval_to_grpc_response_add()
    test_yar_retval_to_grpc_response_list()
    test_yar_retval_to_grpc_response_echo()

    print("\ngrpc_e2e_test: all tests passed")
end

-- busted 入口
if describe then
    describe("grpc e2e (gRPC frame ↔ YAR JSON)", function()
        setup(function() helper.load_proto() end)

        -- 请求方向：YAR → gRPC
        it("YAR JSON {m:'add',p:[1,2]} → gRPC frame{AddRequest a=1,b=2}",
            test_yar_json_to_grpc_request_add)
        it("YAR JSON {m:'sum',p:[[1,2,3]]} → gRPC frame{SumRequest nums=[1,2,3]}",
            test_yar_json_to_grpc_request_sum)
        it("YAR JSON {m:'echo',p:['ping']} → gRPC frame{EchoRequest msg='ping'}",
            test_yar_json_to_grpc_request_echo)

        -- 请求方向：gRPC → YAR
        it("gRPC frame{AddRequest a=1,b=2} → YAR JSON {m:'add',p:[1,2]}",
            test_grpc_request_to_yar_json_add)
        it("gRPC frame{SumRequest nums=[10,20,30]} → YAR JSON {m:'sum',p:[[10,20,30]]}",
            test_grpc_request_to_yar_json_sum)

        -- 响应方向：gRPC → YAR
        it("gRPC frame{AddResponse result=3} → YAR retval 3",
            test_grpc_response_to_yar_retval_add)
        it("gRPC frame{ListResponse items=[10,20]} → YAR retval {10,20}",
            test_grpc_response_to_yar_retval_list)

        -- 响应方向：YAR → gRPC
        it("YAR retval 3 → gRPC frame{AddResponse result=3}",
            test_yar_retval_to_grpc_response_add)
        it("YAR retval {10,20,30} → gRPC frame{ListResponse items=[10,20,30]}",
            test_yar_retval_to_grpc_response_list)
        it("YAR retval {msg='pong'} → gRPC frame{EchoResponse msg='pong'}",
            test_yar_retval_to_grpc_response_echo)
    end)
end

return M
