--- TODO:
--- [x] recursive
---     [x] type checking
---     [x] default value
---     [x] code gen
--- [ ] validation
--- [ ] more types
---     [ ] functions
---     [ ] list
---     [ ] enum
---     [ ] integer
---     [ ] regex
---     [ ] string len
---     [ ] table
---     [ ] list
---     [ ] union
--- [ ] smart extend
--- [ ] formatting
---     [ ] indent size
---     [ ] quote style?
---     [ ] quote keys always

local V = {}

local function Class()
    local class = {}
    setmetatable(class, { __call = function(self, ...) return self:init(...) end})
    class.__index = class
    class.is = function(self, T) return getmetatable(self) == T end
    return class
end

---@alias V.Loc (string | integer)[]

---@param loc V.Loc
---@return string
function V.loc_tostring(loc)
    local str_list = {}
    for part_idx, part in ipairs(loc) do
        if type(part) == "string" then
            if part_idx > 1 then
                table.insert(str_list, ".")
            end
            table.insert(str_list, part)
        elseif type(part) == "number" then
            table.insert(str_list, "[")
            table.insert(str_list, tostring(part))
            table.insert(str_list, "]")
        else
            assert(false, "Malformed V.Loc")
        end
    end
    return table.concat(str_list)
end

---@class V.Error
---@field input any
---@field msg string
---@field loc V.Loc
V.Error = Class()
V.Err = V.Error

function V.Error:init(obj)
    return setmetatable(obj, self)
end

function V.Error:__tostring()
    local loc_string = V.loc_tostring(self.loc)
    local t = type(self.input)
    local value_string = ""
    if t == "number" or t == "boolean"  then
        value_string = tostring(self.input)
    elseif t == "string" then
        local MAX_STR_LEN = 20
        local short_string = self.input:sub(1, MAX_STR_LEN):gsub("\n", "\\n")
        if #self.input > MAX_STR_LEN then
            short_string = short_string .. "..."
        end
        value_string = short_string
    end
    local got_string = "got a " .. type(self.input)
    if value_string ~= "" then
        got_string = got_string .. ": " .. value_string
    end
    return table.concat {
        "At `", loc_string, "` ", got_string, "\n",
        "  > ", self.msg,
    }
end

---@alias V.Validator fun(x: any): boolean, string

---@type V.Validator
function V.string_v(x)
    if type(x) == "string" then
        return true, ""
    end
    return false, "Expected a string."
end
V.str_v = V.string_v

function V.boolean_v(x)
    if type(x) == "boolean" then
        return true, ""
    end
    return false, "Expected a boolean."
end
V.bool_v = V.boolean_v

function V.table_v(x)
    if type(x) == "table" then
        return true, ""
    end
    return false, "Expected a table."
end

---@class V.Field
---@field name string
---@field type string
---@field default any
---@field default_eval boolean
---@field validators V.Validator[]
V.Field = Class()

---@return V.Field
function V.Field:init(obj)
    obj.default_eval = obj.default_eval or false
    obj.validators = obj.validators or {}
    return setmetatable(obj, self)
end

---@return V.Field
function V.String(obj)
    obj.type = obj.type or "string"
    obj.validators = obj.validators or {}
    table.insert(obj.validators, 1, V.string_v)
    return V.Field(obj)
end
V.Str = V.String

---@return V.Field
function V.string(name, default)
    return V.String { name = name, default = default }
end
V.str = V.string

---@return V.Field
function V.Boolean(obj)
    obj.type = obj.type or "boolean"
    obj.validators = obj.validators or {}
    table.insert(obj.validators, 1, V.bool_v)
    return V.Field(obj)
end
V.Bool = V.Boolean

---@return V.Field
function V.boolean(name, default)
    return V.Boolean { name = name, default = default }
end
V.bool = V.boolean

---@class V.Class
---@field name string
---@field type string
---@field doc  string
---@field validators V.Validator[]
V.Class = Class()

---@param obj table
function V.Class:init(obj)
    obj.doc = obj.doc or ""
    obj.validators = obj.validators or {}
    table.insert(obj.validators, V.table_v)
    return setmetatable(obj, self)
end

---@param field V.Field | V.Class
---@param loc V.Loc
---@param x any
---@return boolean
local function validate_field(errors, loc, field, x)
    for _, validator in ipairs(field.validators) do
        local ok, msg = validator(x)
        if not ok then
            local err = V.Error {
                input = x,
                loc = loc,
                msg = msg,
            }
            table.insert(errors, err)
            return false
        end
    end
    return true
end

local function extend_loc(loc, part)
    local new_loc = vim.deepcopy(loc)
    table.insert(new_loc, part)
    return new_loc
end

---@param errors V.Error[]
---@param loc V.Loc
---@param x any
function V.Class:_validate(errors, loc, x)
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            validate_field(errors, extend_loc(loc, child.name), child, x[child.name])
        elseif child:is(V.Class) then
            if validate_field(errors, extend_loc(loc, child.name), child, x[child.name]) then
                child:_validate(errors, extend_loc(loc, child.name), x[child.name])
            end
        end
    end
end

---@param x any
---@return V.Error[]
function V.Class:validate(x)
    local errors = {}
    local loc = {}
    if validate_field(errors, extend_loc(loc, "$"), self, x) then
        self:_validate(errors, extend_loc(loc, "$"), x)
    end
    return errors
end

---@params lines string[]
function V.Class:_type_annotations(lines)
    table.insert(lines, "---@class " .. self.type)
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            table.insert(lines, "---@field " .. child.name .. " " .. child.type)
        end
    end
    for _, child in ipairs(self) do
        if child:is(V.Class) then
            table.insert(lines, "")
            child:_type_annotations(lines)
        end
    end
end

---@return string
function V.Class:type_annotations()
    local lines = {}
    self:_type_annotations(lines)
    return table.concat(lines, "\n")
end

---@param val any
---@param eval boolean
---@return string
local function default_value_string(val, eval)
    if type(val) == "string" then
        -- TODO: handle eval
        -- TODO: handle long strings
        local res, _ = string.format("%q", val):gsub("\\\n", "\\n")
        return res
    else
        return tostring(val)
    end
end

---@param lines string[]
---@param indent string
---@param indent_inc string
function V.Class:_default_code(lines, indent, indent_inc)
    table.insert(lines, indent .. self.name .. " = {")
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            local default_value = default_value_string(child.default, child.default_eval)
            local line = indent .. indent_inc .. child.name .. " = " .. default_value .. ","
            table.insert(lines, line)
        elseif child:is(V.Class) then
            child:_default_code(lines, indent .. indent_inc, indent_inc)
        end
    end
    table.insert(lines, indent .. "}")
end

---@return string
function V.Class:default_code()
    local lines = {}
    table.insert(lines, "---@type " .. self.type)
    self:_default_code(lines, "", "    ")
    return table.concat(lines, "\n")
end

---@return table
function V.Class:default()
    local obj = {}
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            obj[child.name] = child.default
        elseif child:is(V.Class) then
            obj[child.name] = child:default()
        end
    end
    return obj
end

---@param s string
---@return string
local function escape_lua_pattern(s)
    local matches = {
        ["^"] = "%^", ["$"] = "%$", ["("] = "%(", [")"] = "%)",
        ["%"] = "%%", ["."] = "%.", ["["] = "%[", ["]"] = "%]",
        ["*"] = "%*", ["+"] = "%+", ["-"] = "%-", ["?"] = "%?",
        ["\0"] = "%z",
    }
    local esc_s, _ = s:gsub(".", matches)
    return esc_s
end

---@alias V.MarkType "lua" | "md"
---@alias V.Mark [string, string]

---@param filetype V.MarkType
---@return V.Mark
function V.get_mark(filetype, mark_name)
    if filetype == "lua" then
        return { "%-%-%s-VALIDATE_MARK_BEGIN " .. mark_name .. "%s-%-%-",
                 "%-%-%s-VALIDATE_MARK_END " .. mark_name .. "%s-%-%-" }
    elseif filetype == "md" then
        return { "%[%/%/%]%: %# %(VALIDATE_MARK_BEGIN " .. mark_name .. "%)",
                 "%[%/%/%]%: %# %(VALIDATE_MARK_END " .. mark_name .. "%)" }
    else
        assert(false, "Unexpected filetype!")
        return { "", "" }
    end
end

-- TODO report if number of subs ~= 1
---@param mark V.Mark
---@param text string
---@param insert_text string
---@return string, integer
function V.replace_between_marks_in_text(mark, text, insert_text)
    local pattern = table.concat({"(", mark[1], "\n).-(", mark[2], ")"})
    local repl = "%1\n".. insert_text .."\n\n%2"
    return text:gsub(pattern, repl)
end

function V.replace_between_marks_in_file(file_name, mark, insert_text)
    local f = assert(io.open(file_name, "r"))
    local text = f:read("*all")
    f:close()
    local new_text, subs = V.replace_between_marks_in_text(mark, text, insert_text)
    assert(subs ~= 0, "Failed to find mark in file")
    assert(subs <= 1, "Found multiple marks in file")
    local f = assert(io.open(file_name, "w"))
    f:write(new_text)
    f:close()
end

---@return string
function V.this_file()
    return debug.getinfo(2, "S").source:sub(2)
end

return V
