-- luacheck 配置（对标 lua-yar .luacheckrc）
-- 纯 Lua 库：std lua51（不引入 ngx 全局），无 OpenResty cosocket 全局
std = "lua51"
cache = true

-- 允许 luacheckrc 顶部定义的全局与标准库
globals = {}

-- 忽略目录
exclude_files = {
    ".luarocks",
    "lua_modules",
    "spec/support",
}

-- 文件覆盖：src 强约束，spec 放宽
files["src/yar_grpc/"] = {
    -- 纯核心不允许未声明全局、不允许 ngx
    ignore = {},
    std = "lua51",
    read_globals = {"pb"},
}

files["spec/"] = {
    -- busted 测试允许 busted BDD 全局
    globals = {"describe", "it", "pending", "before_each", "after_each", "setup", "teardown", "finally", "assert", "stub", "mock", "spy", "freeze", "refute", "match"},
}

files["test/"] = {
    -- e2e 测试允许 busted BDD 全局（通过 busted 运行时）
    globals = {"describe", "it", "pending", "before_each", "after_each", "setup", "teardown", "finally", "assert", "stub", "mock", "spy", "freeze", "refute", "match"},
}

-- 忽略 max line length（protobuf message 表长行常见）
ignore = {
    "212",  -- argument overshadowing self
    "311",  -- line too long
}

-- 允许 module 表赋值
self_redundant = false
