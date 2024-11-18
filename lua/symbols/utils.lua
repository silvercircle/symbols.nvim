local M = {}

M.MAX_INT = 2147483647

---@param tbl table
---@return table
function M.reverse_map(tbl)
    local rev = {}
    for k, v in pairs(tbl) do
        assert(rev[v] == nil, "to reverse a map values must be unique")
        rev[v] = k
    end
    return rev
end

return M
