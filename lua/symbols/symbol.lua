local M = {}

---@class Pos
---@field line integer
---@field character integer

---@param point [integer, integer]
---@return Pos
function M.Pos_from_point(point)
    return { line = point[1] - 1, character = point[2] }
end

---@class Range
---@field start Pos
---@field end Pos

---@class Symbol
---@field kind string
---@field name string
---@field detail string
---@field level integer
---@field parent Symbol | nil
---@field children Symbol[]
---@field range Range
---@field selectionRange Range

---@return Symbol
function M.Symbol_root()
    return {
        kind = "root",
        name = "<root>",
        detail = "",
        level = 0,
        parent = nil,
        children = {},
        range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = -1, character = -1 }
        },
        selectionRange = {
            start = { line = 0, character = 0 },
            ["end"] = { line = -1, character = -1 }
        },
    }
end

---@param symbol Symbol
---@return string[]
function M.Symbol_path(symbol)
    local path = {}
    while symbol.level > 0 do
        path[symbol.level] = symbol.name
        symbol = symbol.parent
        assert(symbol ~= nil)
    end
    return path
end

return M
