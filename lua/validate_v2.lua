local V = {}

local function Class()
    local class = {}
    setmetatable(class, { __call = function(self, ...) return self:init(...) end})
    class.__index = class
    class.is = function(self, T) return getmetatable(self) == T end
    return class
end

---@class V.Field
---@field name string
---@field type string
---@field default any
---@field default_eval boolean
V.Field = Class()

---@return V.Field
function V.Field:init(obj)
    obj.default_eval = obj.default_eval or false
    return setmetatable(obj, self)
end

---@return V.Field
function V.String(obj)
    obj.type = obj.type or "string"
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
V.Class = Class()

---@param obj table
function V.Class:init(obj)
    obj.doc = obj.doc or ""
    return setmetatable(obj, self)
end

function V.Class:validate()
end

---@return string
function V.Class:type_annotations()
    local lines = {}
    table.insert(lines, "---@class " .. self.type)
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            table.insert(lines, "---@field " .. child.name .. " " .. child.type)
        end
    end
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

---@return string
function V.Class:default_code()
    local lines = {}
    table.insert(lines, "---@type " .. self.type)
    table.insert(lines, self.name .. " = {")
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            local default_value = default_value_string(child.default, child.default_eval)
            table.insert(lines, "    " .. child.name .. " = " .. default_value .. ",")
        end
    end
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

---@return table
function V.Class:default()
    local obj = {}
    for _, child in ipairs(self) do
        if child:is(V.Field) then
            obj[child.name] = child.default
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
