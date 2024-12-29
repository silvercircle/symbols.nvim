local V = require("validate_v2")

local M = {}

-- VALIDATE_MARK_BEGIN TYPES --

---@class ConfigV2
---@field aaa string
---@field bbb string
---@field hide_cursor boolean
---@field x string
---@field e SidebarAction
---@field n number
---@field i integer

---@class SidebarV2
---@field cursor_follow boolean

---@class TestClass
---@field cursor_follow2 boolean

-- VALIDATE_MARK_END TYPES --

SidebarAction = {
    GotoSymbol = "goto-symbol",
    PeekSymbol = "peek-symbol",
    OpenPreview = "open-preview",
}

local model  = V.Class {
    name = "M.default",
    type = "ConfigV2",
    V.str("aaa", "abc", { min_len = 3, max_len = 12 }),
    V.str("bbb", "left", { pattern = "left" }),
    V.bool("hide_cursor", true),
    V.str("x", "abc"),
    V.enum("e", SidebarAction.GotoSymbol, SidebarAction, "SidebarAction"),
    V.num("n", 123, { ge = -1, le = 1 }),
    V.int("i", 123, { ge = 0, lt = 10} ),
    V.Class {
        name = "sidebar", type = "SidebarV2",
        V.bool("cursor_follow", true),
        V.Class {
            name = "test", type = "TestClass",
            V.bool("cursor_follow2", true),
        }
    }
}

-- VALIDATE_MARK_BEGIN DEFAULT_CONFIG --

---@type ConfigV2
M.default = {
    aaa = "abc",
    bbb = "left",
    hide_cursor = true,
    x = "abc",
    e = "goto-symbol",
    n = 123,
    i = 123,
    sidebar = {
        cursor_follow = true,
        test = {
            cursor_follow2 = true,
        }
    }
}

-- VALIDATE_MARK_END DEFAULT_CONFIG --

function M.build()
    V.replace_between_marks_in_file("readme.md", V.get_mark("md", "DEFAULT_CONFIG"), model:default_code())
    V.replace_between_marks_in_file(V.this_file(), V.get_mark("lua", "DEFAULT_CONFIG"), model:default_code())
    V.replace_between_marks_in_file(V.this_file(), V.get_mark("lua", "TYPES"), model:type_annotations())
end

local config = {
    aaa = "\"'\n",
    bbb = "leftleft",
    hide_cursor = "true",
    x = false,
    e = "goto-symbo",
    n = 0.5,
    i = 8,
    sidebar = {
        cursor_follow = "Absda\n\nalfdkjaslkfjdflkasjflkasjfljaslfjasdjfd aslfkjasdljflasjdf",
        test = {
            -- cursor_follow2 = true,
        }
    }
}
local errors = model:validate(config)
for _, err in ipairs(errors) do
    vim.print(tostring(err))
end

vim.print(model:default())

return M
