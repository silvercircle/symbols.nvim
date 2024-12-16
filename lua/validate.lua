-- TODO:
-- [ ] "newline" field
-- [ ] formatting
--      [ ] option to quote all keys
--      [ ] option to skip first model name, useful in readme
--      [ ] option to skip 
-- [ ] better validators
--      [ ] tables
--      [x] functions
--      [ ] list
--      [ ] number range
--      [ ] integer
--      [ ] enum
--      [ ] string len (char)
-- [x] preserve order of fields
-- [x] generate default config
-- [ ] generate type hints
-- [ ] smart extend
-- [x] allow literal default values (e.g. using variables or expressions)

local V = {}

---@enum V.Type
V.Type = {
    Exp = "V.Exp",
    Field = "V.Field",
    Model = "V.Model",
}

---@class V.BaseType
---@field __validate_type V.Type

---@alias V.Validator fun(v: any): boolean, string

---@param a any
---@return string
V.type = function(a)
    local t = type(a)
    if t == "table" then
        if a["__validate_type"] ~= nil then
            return a["__validate_type"]
        end
    end
    return t
end

---@class V.Exp : V.BaseType
---@value string
local Exp = {}
Exp.__index = Exp
V.Exp = Exp

---@param v string
---@return V.Exp
function Exp:new(v)
    return setmetatable({
        __validate_type = "V.Exp",
        value = v,
    }, self)
end

---@class V.Field : V.BaseType
---@field name string
---@field default string | number | boolean | V.Exp
---@field validator V.Validator
---@field doc string
local Field = {}
Field.__index = Field
V.Field = Field

function Field:new(obj)
    obj.__validate_type = "V.Field"
    return setmetatable(obj, self)
end

---@class V.Model : V.BaseType
---@field name string
---@field fields table
---@field doc string
local Model = {}
Model.__index = Model
V.Model = Model

---@param name string
---@param fields table<string, V.Field | V.Model>
---@param doc string?
---@return V.Model
function Model:new(name, fields, doc)
    return setmetatable({
        __validate_type = "V.Model",
        name = name,
        fields = fields,
        doc = doc or "",
    }, self)
end

---@return table
function Model:default()
    local obj = {}
    for _, field in ipairs(self.fields) do
        local t = V.type(field)
        if t == V.Type.Model then
            obj[field.name] = field:default()
        elseif t == V.Type.Field then
            if V.type(field.default) == V.Type.Exp then
                local f, err = loadstring("return " .. field.default.value)
                assert(f, err)
                obj[field.name] = f()
            else
                obj[field.name] = field.default
            end
        else
            assert(false, "Unexpected type: `" .. tostring(t) .. "`")
        end
    end
    return obj
end

local function default_value_code_string(v)
    local t = V.type(v)
    if t == V.Type.Exp then return v.value end
    if t == "string" then return "\"" .. v .. "\"" end
    return tostring(v)
end

---@param lines string[]
---@param indent string
function Model:_default_code_string(lines, indent, indent_inc)
    table.insert(lines, indent .. self.name .. " = {")
    for _, field in ipairs(self.fields) do
        if #field.doc > 0 then
            local first_line = true
            local remove_indent_len = 0
            local doc_lines = vim.split(field.doc, "\n")
            for doc_line_nr, doc_line in ipairs(doc_lines) do
                if first_line then
                    local _, e = doc_line:find("^%s*")
                    remove_indent_len = e
                    first_line = false
                end
                local trimmed_line = doc_line:sub(remove_indent_len+1, -1)
                if doc_line_nr == #doc_lines and #trimmed_line == 0 then
                    -- skip
                else
                    table.insert(lines, indent .. indent_inc .. "-- " .. trimmed_line)
                end
            end
        end
        if V.type(field) == V.Type.Model then
            field:_default_code_string(lines, indent .. indent_inc, indent_inc)
        else
            local line = (
                indent .. indent_inc .. field.name ..
                " = " .. default_value_code_string(field.default) .. ","
            )
            table.insert(lines, line)
        end
    end
    table.insert(lines, indent .. "}")
end

function Model:default_code_string(opts)
    opts = opts or {}
    local lines = {}
    self:_default_code_string(
        lines,
        "",
        opts.indent or "    "
    )
    return table.concat(lines, "\n")
end

local function _type_validator(type_name)
    return function(v)
        if type(v) == type_name then
            return true, ""
        end
        return false, string.format("Expected `%s` got `%s`", type_name, type(v))
    end
end

---@param name string
---@param default boolean
---@param doc string?
---@return V.Field
V.bool = function(name, default, doc)
    return Field:new({
        name = name,
        default = default,
        doc = doc or "",
        validator = _type_validator("boolean"),
    })
end
V.boolean = V.bool

---@parma name string
---@param default string
---@param doc string?
---@return V.Field
V.string = function(name, default, doc)
    return Field:new({
        name = name,
        default = default,
        doc = doc or "",
        validator = _type_validator("string"),
    })
end

---@parma name string
---@param default number
---@param doc string?
---@return V.Field
V.number = function(name, default, doc)
    return Field:new({
        name = name,
        default = default,
        doc = doc or "",
        validator = _type_validator("number"),
    })
end

---@parma name string
---@param default string
---@param doc string?
---@return V.Field
V.func = function(name, default, doc)
    return Field:new({
        name = name,
        default = V.Exp:new(default),
        doc = doc or "",
        validator = _type_validator("function"),
    })
end

-- V.table = function(default)
--     return { deafult = default, type = "table" }
-- end
--
-- V.list = function(default, type_or_fun)
-- end
--
-- V.enum = function(enum, default)
-- end

---@param model V.Model
---@param obj table
---@param path string
---@return string[]
local function validate(model, obj, path)
    local errors = {}
    for _, field in ipairs(model.fields) do
        if V.type(field) == V.Type.Model then
            local new_obj = obj[field.name]
            local new_path = path .. "." .. field.name
            if new_obj == nil then
                local msg = "Missing field"
                local enriched_msg = string.format("%s at `%s`", msg, new_path)
                table.insert(errors, enriched_msg)
            else
                vim.list_extend(errors, validate(field, new_obj, new_path))
            end
        else
            local ok, msg = field.validator(obj[field.name])
            if not ok then
                local enriched_msg = string.format("%s at `%s.%s`", msg, path, field.name)
                table.insert(errors, enriched_msg)
            end
        end
    end
    return errors

    -- TODO check if there are extra fields
    -- TODO suggest the closest match
    -- model:field_names()
end

---@param model V.Model
---@param obj any
---@return string[]
V.validate = function(model, obj)
    -- TODO validate model first
    -- TODO check if obj is table
    return validate(model, obj, "$")
end

local m = V.Model:new("m", {
    V.boolean("hide_cursor", true),
    V.string("open_direction", "try-left"),
    V.bool("on_open_make_windows_equal", true),
    V.bool("cursor_follow", true),
    V.Model:new("m", {
        V.boolean("optA", false),
    })
})

local o = {
    hide_cursor = false,
    open_direction = "abc",
    on_open_make_windows_equal = true,
    cursor_follow = true,
    m = {
        optA = false,
    }
}

-- local errors = V.validate(m, o)
-- if #errors > 0 then
--     for _, msg in ipairs(errors) do
--         vim.notify(msg, vim.log.levels.ERROR)
--     end
-- else
--     vim.notify("no errors", vim.log.levels.INFO)
-- end
--
-- vim.print(m:default())


local SYMBOLS_CONFIG_MODEL = V.Model:new("M.default", {
    V.Model:new("sidebar", {
        V.bool("hide_cursor", true, "Hide the cursor when in sidebar."),
        V.string("open_direction", "try-left", [[
            Side on which the sidebar will open, available options:
                try-left  Opens to the left of the current window if there are no
                          windows there. Otherwise opens to the right.
                try-right Opens to the right of the current window if there are no
                          windows there. Otherwise opens to the left.
                right     Always opens to the right of the current window.
                left      Always opens to the left of the current window.
        ]]),
        V.bool("on_open_make_windows_equal", true, [[
            Whether to run `wincmd =` after opening a sidebar.
        ]]),
        V.bool("cursor_follow", true, [[
            Whether the cursor in the sidebar should automatically follow the
            cursor in the source window. Does not unfold the symbols. You can jump
            to symbol with unfolding with "gs" by default.
        ]]),
        V.Model:new("auto_resize", {
            V.bool("enabled", true, [[
                When enabled the sidebar will be resized whenever the view changes.
                For example, after folding/unfolding symbols, after toggling inline details
                or whenever the source file is saved.
            ]]),
            V.number("min_width", 20, [[
                The sidebar will never be auto resized to a smaller width then `min_width`.
            ]]),
            V.number("max_width", 40, [[
                The sidebar will never be auto resized to a larger width then `max_width`.
            ]]),
        }),
        V.number("fixed_width", 30, "Default sidebar width."),
        V.func("symbol_filter", [[function(_, _) return true end]], [[
            Allows to filter symbols. By default all the symbols are shown.
        ]]),
        V.bool("show_inline_details", false, "Show inline details by default."),
        V.bool("show_details_pop_up", false, "Show details floating window at all times."),
        V.bool("auto_peek", false, [[
            When enabled every symbol will be automatically peeked after cursor
            movement.
        ]]),
        V.bool("close_on_goto", false, "Whether to close the sidebar on goto symbol."),
        V.bool("wrap", false, "Whether the sidebar should wrap text."),
        V.bool("show_guide_lines", false, "Whether to show the guide lines."),
        V.Model:new("chars", {
            V.string("folded", ""),
            V.string("unfolded", ""),
            V.string("guide_vert", "│"),
            V.string("guide_middle_item", "├"),
            V.string("guide_last_item", "└"),
        }),
        V.Model:new("preview", {
            V.bool("show_always", false, [[
                Whether the preview window is always opened when the sidebar is
                focused.
            ]]),
            V.bool("show_line_number", false, [[
                Whether the preview window should show line numbers.
            ]]),
            V.bool("auto_size", true, [[
                Whether to determine the preview window's height automatically.
            ]]),
            V.number("auto_size_extra_lines", 6, [[
                The total number of extra lines shown in the preview window.
            ]]),
            V.number("min_window_height", 7, [[
                Minimum window height when `auto_size` is true.
            ]]),
            V.number("max_window_height", 30, [[
                Maximum window height when `auto_size` is true.
            ]]),
            V.number("fixed_size_height", 12, [[
                Preview window size when `auto_size` is false.
            ]]),
            V.number("window_width", 100, [[
                Desired preview window width. Actuall width will be capped at
                the current width of the source window width.
            ]]),
    --         keymaps = {
    --             ["q"] = "close",
    --         },
            }, "Config for the preview window."
        ),
    })
    --     keymaps = {
    --         ["<CR>"] = "goto-symbol",
    --         ["<RightMouse>"] = "peek-symbol",
    --         ["o"] = "peek-symbol",
    --
    --         ["K"] = "open-preview",
    --         ["d"] = "open-details-window",
    --         ["gs"] = "show-symbol-under-cursor",
    --
    --         ["gp"] = "goto-parent",
    --         ["[["] = "prev-symbol-at-level",
    --         ["]]"] = "next-symbol-at-level",
    --
    --         ["l"] = "unfold",
    --         ["zo"] = "unfold",
    --         ["L"] = "unfold-recursively",
    --         ["zO"] = "unfold-recursively",
    --         ["zr"] = "unfold-one-level",
    --         ["zR"] = "unfold-all",
    --
    --         ["h"] = "fold",
    --         ["zc"] = "fold",
    --         ["H"] = "fold-recursively",
    --         ["zC"] = "fold-recursively",
    --         ["zm"] = "fold-one-level",
    --         ["zM"] = "fold-all",
    --
    --         ["s"] = "search",
    --
    --         ["td"] = "toggle-inline-details",
    --         ["tD"] = "toggle-auto-details-window",
    --         ["tp"] = "toggle-auto-preview",
    --         ["tch"] = "toggle-cursor-hiding",
    --         ["tcf"] = "toggle-cursor-follow",
    --         ["tf"] = "toggle-filters",
    --         ["to"] = "toggle-auto-peek",
    --         ["tg"] = "toggle-close-on-goto",
    --         ["t="] = "toggle-auto-resize",
    --         ["t["] = "decrease-max-width",
    --         ["t]"] = "increase-max-width",
    --
    --         ["<2-LeftMouse>"] = "toggle-fold",
    --
    --         ["q"] = "close",
    --         ["?"] = "help",
    --         ["g?"] = "help",
    --     },
    -- },
    -- providers = {
    --     lsp = {
    --         timeout_ms = 2000,
    --         details = {},
    --         kinds = { default = {} },
    --         highlights = {
    --             default = {
    --                 File = "Identifier",
    --                 Module = "Include",
    --                 Namespace = "Include",
    --                 Package = "Include",
    --                 Class = "Type",
    --                 Method = "Function",
    --                 Property = "Identifier",
    --                 Field = "Identifier",
    --                 Constructor = "Special",
    --                 Enum = "Type",
    --                 Interface = "Type",
    --                 Function = "Function",
    --                 Variable = "Constant",
    --                 Constant = "Constant",
    --                 String = "String",
    --                 Number = "Number",
    --                 Boolean = "Boolean",
    --                 Array = "Constant",
    --                 Object = "Type",
    --                 Key = "Type",
    --                 Null = "Type",
    --                 EnumMember = "Identifier",
    --                 Struct = "Structure",
    --                 Event = "Type",
    --                 Operator = "Identifier",
    --                 TypeParameter = "Identifier",
    --             }
    --         },
    --     },
    --     treesitter = {
    --         details = {},
    --         kinds = { default = {} },
    --         highlights = {
    --             markdown = {
    --                 H1 = "@markup.heading.1.markdown",
    --                 H2 = "@markup.heading.2.markdown",
    --                 H3 = "@markup.heading.3.markdown",
    --                 H4 = "@markup.heading.4.markdown",
    --                 H5 = "@markup.heading.5.markdown",
    --                 H6 = "@markup.heading.6.markdown",
    --             },
    --             help = {
    --                 H1 = "@markup.heading.1.vimdoc",
    --                 H2 = "@markup.heading.2.vimdoc",
    --                 H3 = "@markup.heading.3.vimdoc",
    --                 Tag = "@label.vimdoc",
    --             },
    --             json = {
    --                 Object = "Type",
    --                 Array = "Constant",
    --                 String = "String",
    --                 Number = "Number",
    --                 Boolean = "Boolean",
    --                 Null = "Type",
    --             },
    --             jsonl = {
    --                 Object = "Type",
    --                 Array = "Constant",
    --                 String = "String",
    --                 Number = "Number",
    --                 Boolean = "Boolean",
    --                 Null = "Type",
    --             },
    --             org = {
    --                 H1 = "@markup.heading.1.markdown",
    --                 H2 = "@markup.heading.2.markdown",
    --                 H3 = "@markup.heading.3.markdown",
    --                 H4 = "@markup.heading.4.markdown",
    --                 H5 = "@markup.heading.5.markdown",
    --                 H6 = "@markup.heading.6.markdown",
    --                 H7 = "@markup.heading.6.markdown",
    --                 H8 = "@markup.heading.6.markdown",
    --                 H9 = "@markup.heading.6.markdown",
    --                 H10 = "@markup.heading.6.markdown",
    --             },
    --             make = {
    --                 Target = "",
    --             },
    --             default = {},
    --         }
    --     },
    -- },
    -- dev = {
    --     enabled = false,
    --     log_level = vim.log.levels.ERROR,
    --     keymaps = {},
    -- }
})

-- vim.print(SYMBOLS_CONFIG_MODEL:default())
vim.print(SYMBOLS_CONFIG_MODEL:default_code_string())

-- local f, err = loadstring("return function(s) print('<<'..s..'>>') end")
-- if f ~= nil then
--     local g = f()
--     g("abc")
-- else
--     print(err)
-- end

return V
