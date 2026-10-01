-- deadline spec: grpc-timeout 解析与过期检查专项测试
-- 回归背景：0.1.0 中 u/n 单位乘数误为 1（亚毫秒被放大成 1ms），
-- 0.1.1 修正为 u=0.001 / n=0.000001。本 spec 锁定换算精度与 tostring 输出契约。

local deadline = require("yar_grpc.deadline")

describe("yar_grpc.deadline.parse_timeout", function()
    it("parses integer units exactly", function()
        assert.equal(3600000, deadline.parse_timeout("1H"))
        assert.equal(60000, deadline.parse_timeout("1M"))
        assert.equal(5000, deadline.parse_timeout("5S"))
        assert.equal(100, deadline.parse_timeout("100m"))
    end)

    it("parses microseconds with 0.001 multiplier (regression: was 1)", function()
        assert.equal(0.001, deadline.parse_timeout("1u"))
        assert.equal(1, deadline.parse_timeout("1000u"))
        assert.equal(500, deadline.parse_timeout("500000u"))
    end)

    it("parses nanoseconds with 0.000001 multiplier (regression: was 1)", function()
        assert.equal(1e-6, deadline.parse_timeout("1n"))
        assert.equal(1, deadline.parse_timeout("1000000n"))
    end)

    it("keeps integer-valued results exact for tostring contract", function()
        -- bridge t/deadline.t 经 ngx.say(tostring(ms)) 断言 "ms=500"：
        -- 双精度下 500000 * 0.001 恰好舍入为 500.0。
        -- Lua 5.1/LuaJIT（OpenResty 运行时，LuaJIT 的 _VERSION 即 "Lua 5.1"）
        -- tostring 整数浮点无小数尾巴；Lua 5.3+ 恒带 ".0"，按解释器分别锁定。
        local ms_u = deadline.parse_timeout("500000u")
        local ms_n = deadline.parse_timeout("1000000n")
        assert.equal(500, ms_u)
        assert.equal(1, ms_n)
        if _VERSION == "Lua 5.1" then
            assert.equal("500", tostring(ms_u))
            assert.equal("1", tostring(ms_n))
        else
            assert.equal("500.0", tostring(ms_u))
            assert.equal("1.0", tostring(ms_n))
        end
    end)

    it("enforces gRPC 8-digit limit", function()
        assert.equal(99999999, deadline.parse_timeout("99999999m"))
        assert.is_nil(deadline.parse_timeout("100000000m"))  -- 9 位，超规范上限
    end)

    it("rejects invalid input", function()
        assert.is_nil(deadline.parse_timeout(nil))
        assert.is_nil(deadline.parse_timeout(""))
        assert.is_nil(deadline.parse_timeout("abc"))
        assert.is_nil(deadline.parse_timeout("100x"))    -- 非法单位
        assert.is_nil(deadline.parse_timeout("100"))     -- 缺单位
        assert.is_nil(deadline.parse_timeout("m"))       -- 缺数字
        assert.is_nil(deadline.parse_timeout("10.5S"))   -- 非整数
    end)
end)

describe("yar_grpc.deadline.check_expired", function()
    it("elapsed >= deadline is expired (boundary inclusive)", function()
        assert.is_true(deadline.check_expired(100, 0, 0.1))     -- 恰好 100ms，边界触发
        assert.is_false(deadline.check_expired(100, 0, 0.099))
        assert.is_true(deadline.check_expired(100, 0, 0.2))
    end)

    it("zero deadline is always expired", function()
        assert.is_true(deadline.check_expired(0, 1, 1))
    end)

    it("nil-safe on any argument", function()
        assert.is_false(deadline.check_expired(nil, 0, 0.1))
        assert.is_false(deadline.check_expired(100, nil, 0.1))
        assert.is_false(deadline.check_expired(100, 0, nil))
    end)

    it("honors sub-millisecond deadline after fix", function()
        -- 500u = 0.5ms：修复前被放大为 500ms，前置检查永不触发
        assert.is_false(deadline.check_expired(0.5, 0, 0.0004))  -- 0.4ms 未过期
        assert.is_true(deadline.check_expired(0.5, 0, 0.0006))   -- 0.6ms 已过期
    end)
end)
