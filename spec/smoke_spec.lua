-- smoke spec: 纯函数冒烟测试，无需 pb schema 即可运行（裸 LuaJIT/Lua5.1）
-- pb-dependent 路径（extract_params/encode 等）留待集成 spec 验证

local codec     = require("yar_grpc.codec")
local grpc_converter = require("yar_grpc.grpc_converter")
local errors    = require("yar_grpc.errors")
local deadline  = require("yar_grpc.deadline")

describe("yar_grpc.codec", function()
    it("encode_frame then decode_frame roundtrip", function()
        local payload = "\x08\x01\x10\x02"  -- fake protobuf bytes
        local frame = codec.encode_frame(payload)
        assert.equal(#payload + 5, #frame)

        local flag, decoded, size = codec.decode_frame(frame)
        assert.equal(0, flag)
        assert.equal(payload, decoded)
        assert.equal(#frame, size)
    end)

    it("decode_frame rejects incomplete header", function()
        local _, _, _, err = codec.decode_frame("ab")
        assert.is_truthy(err)
    end)

    it("decode_frame rejects incomplete payload", function()
        local frame = codec.encode_frame("hello world")
        -- 截断 payload
        local truncated = frame:sub(1, 7)
        local _, _, _, err = codec.decode_frame(truncated)
        assert.is_truthy(err)
    end)

    it("has_multiple_frames detects streaming", function()
        local f1 = codec.encode_frame("a")
        assert.is_false(codec.has_multiple_frames(f1, #f1))
        local two = f1 .. codec.encode_frame("b")
        assert.is_true(codec.has_multiple_frames(two, #f1))
    end)
end)

describe("yar_grpc.grpc_converter", function()
    it("parse_grpc_path splits /Service/Method", function()
        local svc, m, err = grpc_converter.parse_grpc_path("/Foo/Bar")
        assert.equal("Foo", svc)
        assert.equal("Bar", m)
        assert.is_nil(err)
    end)

    it("parse_grpc_path tolerates extra slashes", function()
        local svc, m = grpc_converter.parse_grpc_path("//Foo/Bar")
        assert.equal("Foo", svc)
        assert.equal("Bar", m)
    end)

    it("parse_grpc_path rejects malformed", function()
        local _, _, err = grpc_converter.parse_grpc_path("nope")
        assert.is_truthy(err)
    end)

    it("method_to_yar lowercases first letter", function()
        assert.equal("add", grpc_converter.method_to_yar("Add"))
        assert.equal("getUser", grpc_converter.method_to_yar("GetUser"))
        assert.equal("", grpc_converter.method_to_yar(""))
    end)
end)

describe("yar_grpc.deadline", function()
    it("parse_timeout parses units", function()
        assert.equal(100, deadline.parse_timeout("100m"))
        assert.equal(5000, deadline.parse_timeout("5S"))
        assert.equal(60000, deadline.parse_timeout("1M"))
        assert.equal(3600000, deadline.parse_timeout("1H"))
        assert.equal(0.001, deadline.parse_timeout("1u"))
        assert.equal(1e-6, deadline.parse_timeout("1n"))
    end)

    it("parse_timeout rejects invalid", function()
        assert.is_nil(deadline.parse_timeout(nil))
        assert.is_nil(deadline.parse_timeout(""))
        assert.is_nil(deadline.parse_timeout("100x"))
        assert.is_nil(deadline.parse_timeout("abc"))
    end)

    it("check_expired compares elapsed against deadline", function()
        -- start=0, now=0.05s = 50ms, deadline 100ms → not expired
        assert.is_false(deadline.check_expired(100, 0, 0.05))
        -- now=0.2s = 200ms > 100ms → expired
        assert.is_true(deadline.check_expired(100, 0, 0.2))
    end)

    it("check_expired nil-safe", function()
        assert.is_false(deadline.check_expired(nil, 0, 0.1))
        assert.is_false(deadline.check_expired(100, nil, 0.1))
    end)
end)

describe("yar_grpc.errors", function()
    it("map_yar_error maps structured TRANSPORT", function()
        local status, msg = errors.map_yar_error({ code = "TRANSPORT", message = "conn refused" })
        assert.equal(errors.UNAVAILABLE, status)
        assert.equal("conn refused", msg)
    end)

    it("map_yar_error maps structured TIMEOUT", function()
        local status = errors.map_yar_error({ code = "TIMEOUT" })
        assert.equal(errors.DEADLINE_EXCEEDED, status)
    end)

    it("map_yar_error maps string transport prefix", function()
        local status = errors.map_yar_error("transport: connection refused")
        assert.equal(errors.UNAVAILABLE, status)
    end)

    it("map_yar_error fallback to INTERNAL", function()
        local status, _ = errors.map_yar_error("some unknown error")
        assert.equal(errors.INTERNAL, status)
    end)

    it("map_yar_error nil returns INTERNAL", function()
        local status = errors.map_yar_error(nil)
        assert.equal(errors.INTERNAL, status)
    end)
end)
