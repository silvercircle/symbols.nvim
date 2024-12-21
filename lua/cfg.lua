local V = require("validate_v2")

local M = {}

-- VALIDATE_MARK_BEGIN TYPES --

---@class ConfigV2
---@field aaa string
---@field bbb string
---@field hide_cursor boolean
---@field x string

---@class SidebarV2
---@field cursor_follow boolean

---@class TestClass
---@field cursor_follow2 boolean

-- VALIDATE_MARK_END TYPES --

local model  = V.Class {
    name = "M.default",
    type = "ConfigV2",
    V.Field { name="aaa", type="string", default="\"'\n" },
    V.String { name="bbb", default="left" },
    V.Bool { name="hide_cursor", default=true },
    V.str("x", "abc"),
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
    aaa = "\"'\n",
    bbb = "left",
    hide_cursor = true,
    x = "abc",
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
    bbb = "left",
    hide_cursor = "true",
    x = false,
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
