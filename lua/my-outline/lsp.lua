local M = {}

---@enum LspSymbolKind
M.SymbolKind = {
	File = 1,
	Module = 2,
	Namespace = 3,
	Package = 4,
	Class = 5,
	Method = 6,
	Property = 7,
	Field = 8,
	Constructor = 9,
	Enum = 10,
	Interface = 11,
	Function = 12,
	Variable = 13,
	Constant = 14,
	String = 15,
	Number = 16,
	Boolean = 17,
	Array = 18,
	Object = 19,
	Key = 20,
	Null = 21,
	EnumMember = 22,
	Struct = 23,
	Event = 24,
	Operator = 25,
	TypeParameter = 26,
}

---@type table<LspSymbolKind, string>
M.SymbolKindString = {}
for k, v in pairs(M.SymbolKind) do
    M.SymbolKindString[v] = k
end

---@class Pos
---@field line integer
---@field character integer

---@class Range
---@field start Pos
---@field end Pos

---@class Symbol
---@field detail string
---@field kind LspSymbolKind
---@field name string
---@field range Range
---@field selectionRange Range

---@alias vim.lsp.Handler fun(err: table | nil, result: Symbol[] | nil, ctx: table, config: table)

return M
