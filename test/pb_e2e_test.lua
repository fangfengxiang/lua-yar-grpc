-- test/pb_e2e_test.lua
-- 端到端测试：pb ↔ YAR 协议 JSON（无 gRPC 帧）
--
-- 场景：Calculator 服务，覆盖标量 / repeated 输入 / 数组返回 / string 四种 retval 形态
--
-- 只测试 pb 层：pb_converter + pb.encode/decode + YAR JSON packager
-- 不涉及 codec（gRPC 帧编解码），gRPC 帧测试在 grpc_e2e_test.lua
--
-- 管线：
--   pb → YAR:  pb.encode(Request) → pb.decode → pb_converter.extract_params
--              → grpc_converter.method_to_yar → YAR JSON
--   YAR → pb:  YAR JSON → json.unpack → pb_converter.pack_params
--              → pb.encode → pb.decode → 验证
--
-- 运行：busted test/pb_e2e_test.lua

local pb            = require("pb")
local grpc_converter = require("yar_grpc.grpc_converter")
local pb_converter  = require("yar_grpc.pb_converter")
local helper        = require("test.proto_helper")

-- lua-yar JSON packager：真实 YAR 协议 JSON 编解码
local Yar  = require("yar")
local json = Yar.get_packager(Yar.PACKAGER_JSON)

local M = {}

-- ============================================================
-- 请求方向：pb → YAR 协议 JSON
-- ============================================================

-- 测试：pb 请求 → YAR 协议 JSON（Add 标量参数）
local function test_pb_request_to_yar_json_add()
    local pb_payload = pb.encode("Calculator_AddRequest", { a = 1, b = 2 })
    assert(pb_payload, "pb.encode should succeed")

    local decoded = pb.decode("Calculator_AddRequest", pb_payload)

    local params, perr = pb_converter.extract_params(decoded, "Calculator_AddRequest")
    assert(params, "extract_params failed: " .. tostring(perr))
    assert(params[1] == 1, "params[1] should be 1")
    assert(params[2] == 2, "params[2] should be 2")

    local yar_method = grpc_converter.method_to_yar("Add")
    assert(yar_method == "add", "method should be 'add'")

    local yar_json = json.pack({ i = 1001, m = yar_method, p = params })
    assert(yar_json:match('"m":"add"'), "json should contain method 'add'")
    assert(yar_json:match('"p":%[1,2%]'), "json should contain params [1,2]")

    print("  [pb->YAR] AddRequest{a=1,b=2} -> YAR JSON: " .. yar_json)
end

-- 测试：pb 请求 → YAR 协议 JSON（Sum repeated 输入）
local function test_pb_request_to_yar_json_sum()
    local pb_payload = pb.encode("Calculator_SumRequest", { nums = { 1, 2, 3 } })
    local decoded = pb.decode("Calculator_SumRequest", pb_payload)

    local params = pb_converter.extract_params(decoded, "Calculator_SumRequest")
    assert.same({ { 1, 2, 3 } }, params, "params should be {{1,2,3}}")

    local yar_method = grpc_converter.method_to_yar("Sum")
    assert(yar_method == "sum", "method should be 'sum'")

    local yar_json = json.pack({ i = 1002, m = yar_method, p = params })
    assert(yar_json:match('"m":"sum"'), "json should contain method 'sum'")

    print("  [pb->YAR] SumRequest{nums={1,2,3}} -> YAR JSON: " .. yar_json)
end

-- 测试：pb 请求 → YAR 协议 JSON（Echo string 参数）
local function test_pb_request_to_yar_json_echo()
    local pb_payload = pb.encode("Calculator_EchoRequest", { msg = "ping" })
    local decoded = pb.decode("Calculator_EchoRequest", pb_payload)

    local params = pb_converter.extract_params(decoded, "Calculator_EchoRequest")
    assert.equal("ping", params[1], "params[1] should be 'ping'")

    local yar_method = grpc_converter.method_to_yar("Echo")
    assert(yar_method == "echo", "method should be 'echo'")

    local yar_json = json.pack({ i = 1003, m = yar_method, p = params })
    assert(yar_json:match('"m":"echo"'), "json should contain method 'echo'")

    print("  [pb->YAR] EchoRequest{msg='ping'} -> YAR JSON: " .. yar_json)
end

-- ============================================================
-- 请求方向：YAR 协议 JSON → pb 请求
-- ============================================================

-- 测试：YAR 协议 JSON → pb 请求（Add 标量参数）
local function test_yar_json_to_pb_request_add()
    local yar_json = json.pack({ i = 1001, m = "add", p = { 1, 2 } })

    local unpacked = json.unpack(yar_json)
    assert(unpacked.m == "add", "method should be 'add'")

    local message = pb_converter.pack_params(unpacked.p, "Calculator_AddRequest")
    assert(message.a == 1, "message.a should be 1")
    assert(message.b == 2, "message.b should be 2")

    local pb_payload = pb.encode("Calculator_AddRequest", message)
    assert(pb_payload, "pb.encode should succeed")

    local decoded = pb.decode("Calculator_AddRequest", pb_payload)
    assert(decoded.a == 1, "decoded.a should be 1")
    assert(decoded.b == 2, "decoded.b should be 2")

    print("  [YAR->pb] YAR JSON -> AddRequest{a=" .. decoded.a .. ",b=" .. decoded.b .. "}")
end

-- 测试：YAR 协议 JSON → pb 请求（Sum repeated 输入）
local function test_yar_json_to_pb_request_sum()
    local yar_json = json.pack({ i = 1002, m = "sum", p = { { 10, 20, 30 } } })

    local unpacked = json.unpack(yar_json)
    assert(unpacked.m == "sum", "method should be 'sum'")

    local message = pb_converter.pack_params(unpacked.p, "Calculator_SumRequest")
    assert.same({ 10, 20, 30 }, message.nums, "message.nums should be {10,20,30}")

    local pb_payload = pb.encode("Calculator_SumRequest", message)
    local decoded = pb.decode("Calculator_SumRequest", pb_payload)
    assert.same({ 10, 20, 30 }, decoded.nums, "decoded.nums should be {10,20,30}")

    print("  [YAR->pb] YAR JSON -> SumRequest{nums={10,20,30}}")
end

-- ============================================================
-- 响应方向：pb 响应 → YAR retval
-- ============================================================

-- 测试：pb 响应 → YAR retval（Add 标量返回）
local function test_pb_response_to_yar_retval_add()
    local pb_payload = pb.encode("Calculator_AddResponse", { result = 3 })
    local decoded = pb.decode("Calculator_AddResponse", pb_payload)

    local retval = pb_converter.extract_result(decoded, "Calculator_AddResponse")
    assert(retval == 3, "retval should be 3, got " .. tostring(retval))

    local yar_resp_json = json.pack({ i = 1001, s = 0, r = retval, o = "" })
    assert(yar_resp_json:match('"r":3'), "response json should contain r:3")

    print("  [pb->YAR] AddResponse{result=3} -> YAR retval " .. tostring(retval) ..
        " -> JSON: " .. yar_resp_json)
end

-- 测试：pb 响应 → YAR retval（List 数组返回）
local function test_pb_response_to_yar_retval_list()
    local pb_payload = pb.encode("Calculator_ListResponse", { items = { 10, 20 } })
    local decoded = pb.decode("Calculator_ListResponse", pb_payload)

    local retval = pb_converter.extract_result(decoded, "Calculator_ListResponse")
    assert.same({ 10, 20 }, retval, "retval should be {10,20}")

    print("  [pb->YAR] ListResponse{items={10,20}} -> YAR retval {10,20}")
end

-- ============================================================
-- 响应方向：YAR retval → pb 响应
-- ============================================================

-- 测试：YAR retval → pb 响应（Add 标量返回）
local function test_yar_retval_to_pb_response_add()
    local yar_retval = 3

    local message = pb_converter.map_response(yar_retval, "Calculator_AddResponse")
    assert(message.result == 3, "message.result should be 3")

    local pb_payload = pb.encode("Calculator_AddResponse", message)
    assert(pb_payload, "pb.encode should succeed")

    local decoded = pb.decode("Calculator_AddResponse", pb_payload)
    assert(decoded.result == 3, "decoded.result should be 3")

    print("  [YAR->pb] YAR retval " .. tostring(yar_retval) ..
        " -> AddResponse{result=" .. decoded.result .. "}")
end

-- 测试：YAR retval → pb 响应（List 数组返回）
local function test_yar_retval_to_pb_response_list()
    local yar_retval = { 10, 20, 30 }

    local message = pb_converter.map_response(yar_retval, "Calculator_ListResponse")
    assert.same({ 10, 20, 30 }, message.items, "message.items should be {10,20,30}")

    local pb_payload = pb.encode("Calculator_ListResponse", message)
    local decoded = pb.decode("Calculator_ListResponse", pb_payload)
    assert.same({ 10, 20, 30 }, decoded.items, "decoded.items should be {10,20,30}")

    print("  [YAR->pb] YAR retval {10,20,30} -> ListResponse{items={10,20,30}}")
end

-- 测试：YAR retval → pb 响应（Echo table 返回）
local function test_yar_retval_to_pb_response_echo()
    local yar_retval = { msg = "pong" }

    local message = pb_converter.map_response(yar_retval, "Calculator_EchoResponse")
    assert.equal("pong", message.msg, "message.msg should be 'pong'")

    local pb_payload = pb.encode("Calculator_EchoResponse", message)
    local decoded = pb.decode("Calculator_EchoResponse", pb_payload)
    assert.equal("pong", decoded.msg, "decoded.msg should be 'pong'")

    print("  [YAR->pb] YAR retval {msg='pong'} -> EchoResponse{msg='pong'}")
end

function M.run()
    helper.load_proto()

    -- pb -> YAR
    test_pb_request_to_yar_json_add()
    test_pb_request_to_yar_json_sum()
    test_pb_request_to_yar_json_echo()

    -- YAR -> pb
    test_yar_json_to_pb_request_add()
    test_yar_json_to_pb_request_sum()

    -- pb response -> YAR retval
    test_pb_response_to_yar_retval_add()
    test_pb_response_to_yar_retval_list()

    -- YAR retval -> pb response
    test_yar_retval_to_pb_response_add()
    test_yar_retval_to_pb_response_list()
    test_yar_retval_to_pb_response_echo()

    print("\npb_e2e_test: all tests passed")
end

-- busted entry
if describe then
    describe("pb e2e (pb <-> YAR JSON, no gRPC frame)", function()
        setup(function() helper.load_proto() end)

        -- pb -> YAR
        it("AddRequest{a=1,b=2} -> YAR JSON {m:'add',p:[1,2]}", test_pb_request_to_yar_json_add)
        it("SumRequest{nums={1,2,3}} -> YAR JSON {m:'sum',p:[[1,2,3]]}", test_pb_request_to_yar_json_sum)
        it("EchoRequest{msg='ping'} -> YAR JSON {m:'echo',p:['ping']}", test_pb_request_to_yar_json_echo)

        -- YAR -> pb
        it("YAR JSON {m:'add',p:[1,2]} -> AddRequest{a=1,b=2}", test_yar_json_to_pb_request_add)
        it("YAR JSON {m:'sum',p:[[10,20,30]]} -> SumRequest{nums={10,20,30}}", test_yar_json_to_pb_request_sum)

        -- pb response -> YAR retval
        it("AddResponse{result=3} -> YAR retval 3", test_pb_response_to_yar_retval_add)
        it("ListResponse{items={10,20}} -> YAR retval {10,20}", test_pb_response_to_yar_retval_list)

        -- YAR retval -> pb response
        it("YAR retval 3 -> AddResponse{result=3}", test_yar_retval_to_pb_response_add)
        it("YAR retval {10,20,30} -> ListResponse{items={10,20,30}}", test_yar_retval_to_pb_response_list)
        it("YAR retval {msg='pong'} -> EchoResponse{msg='pong'}", test_yar_retval_to_pb_response_echo)
    end)
end

return M
