local M = {}

---@param symbol Symbol
---@return boolean
local function lua_filter(symbol)
    local kind = symbol.kind
    local pkind = symbol.parent.kind
    if kind == "Constant" or kind == "Package" then
        return false
    end
    if (pkind == "Function" or pkind == "Method") and kind ~= "Function" then
        return false
    end
    return true
end

M.DefaultFilters = {
    sidebar = {
        symbol_filter = function(ft, symbol)
            if ft == "lua" then return lua_filter(symbol) end
            return true
        end,
    },
}

M.AsciiSymbols = {
    providers = {
        lsp = {
            details = {
                lua = function(symbol, ctx)
                    local state = ctx.symbol_states[symbol]
                    local kind = symbol.kind
                    local detail = symbol.detail
                    if (kind == "Function" or kind == "Method") and vim.startswith(detail, "function") then
                        return vim.split(detail, "function ")[2]
                    end
                    if kind == "Number" or kind == "String" or kind == "Boolean" then
                        return "= " .. detail
                    end
                    if kind == "Object" or kind == "Array" then
                        return (state.folded and detail) or ""
                    end
                    if kind == "Package" then
                        if vim.startswith(detail, "if") then return string.sub(detail, 4, -6) end
                        if vim.startswith(detail, "elseif") then return string.sub(detail, 8, -6) end
                        if vim.startswith(detail, "else") then return "" end
                        if vim.startswith(detail, " for") then return string.sub(detail, 6, -1) end
                        if vim.startswith(detail, "while") then return string.sub(detail, 7, -1) end
                        return detail
                    end
                    return detail
                end,
            },
            kinds = {
                json = {
                    Module = "{}",
                    Array = "[]",
                    Boolean = " b",
                    String = " \"",
                    Number = " #",
                    Variable = " ?",
                },
                yaml = {
                    Module = "{}",
                    Array = "[]",
                    Boolean = "b",
                    String = "\"",
                    Number = "#",
                    Variable = "?",
                },
                lua = function(symbol)
                    local level = symbol.level
                    local kind = symbol.kind
                    local pkind = symbol.parent.kind
                    if kind == "Function" then
                        return ((level == 1) and "fun") or "fn"
                    end
                    if (
                        (pkind == "Array" or pkind == "Object")
                        and (kind ~= "Array" and kind ~= "Object")
                    ) then
                        local obj_map = {
                            Boolean = " b",
                            Function = "fn",
                            Number = " #",
                            String = "\"\"",
                            Variable = " ?",
                        }
                        return obj_map[kind] or "  "
                    end
                    if level == 1 and kind == "Object" then return " {}" end
                    if level == 1 and kind == "Array" then return " []" end
                    local map = {
                        Array = "[]",
                        Boolean = "var",
                        Constant = "param",
                        Method = "fun",
                        Number = "var",
                        Object = "{}",
                        Package = "",
                        String = "var",
                        Variable = "var",
                    }
                    return map[symbol.kind]
                end,
                go = {
                    Struct = "struct",
                    Class = "type",
                    Constant = "const",
                    Function = "func",
                    Method = "func",
                    Field = "field",
                },
                python = {
                    Class = "class",
                    Variable = "",
                    Constant = "const",
                    Function = "def",
                    Method = "def",
                },
                sh = {
                    Variable = "$",
                    Function = "fun",
                },
                css = {
                    Class = "",
                    Module = "",
                },
                javascript = {
                    Function = "fun",
                    Constant = "const",
                    Variable = "let",
                    Property = "",
                },
                typescript = {
                    Function = "fun",
                    Constant = "const",
                    Variable = "let",
                    Property = "",
                },
                default = {
                    File = "filed",
                    Module = "module",
                    Namespace = "namespace",
                    Package = "pkg",
                    Class = "cls",
                    Method = "fun",
                    Property = "property",
                    Field = "field",
                    Constructor = "constructor",
                    Enum = "enum",
                    Interface = "interface",
                    Function = "fun",
                    Variable = "var",
                    Constant = "const",
                    String = "str",
                    Number = "num",
                    Boolean = "bool",
                    Array = "array",
                    Object = "object",
                    Key = "key",
                    Null = "null",
                    EnumMember = "enum member",
                    Struct = "struct",
                    Event = "event",
                    Operator = "operator",
                    TypeParameter = "type parameter",
                    Component = "component",
                    Fragment = "fragment",
                }
            }
        },
        treesitter = {
            kinds = {
                vimdoc = {
                    H1 = "",
                    H2 = "",
                    H3 = "",
                    Tag = "*",
                },
                markdown = {
                    H1 = "",
                    H2 = "",
                    H3 = "",
                    H4 = "",
                    H5 = "",
                    H6 = "",
                },
            }
        }
    }
}

M.FancySymbols = {
    providers = {
        lsp = {
            kinds = {
                default = {
                    File = "󰈔",
                    Module = "󰆧",
                    Namespace = "󰅪",
                    Package = "󰏗",
                    Class = "𝓒",
                    Method = "ƒ",
                    Property = "",
                    Field = "󰆨",
                    Constructor = "",
                    Enum = "ℰ",
                    Interface = "󰜰",
                    Function = "ƒ",
                    Variable = "",
                    Constant = "",
                    String = "𝓐",
                    Number = "#",
                    Boolean = "⊨",
                    Array = "󰅪",
                    Object = "⦿",
                    Key = "🔐",
                    Null = "NULL",
                    EnumMember = "",
                    Struct = "𝓢",
                    Event = "🗲",
                    Operator = "+",
                    TypeParameter = "𝙏",
                    Component = "󰅴",
                    Fragment = "󰅴",
                }
            }
        },
        treesitter = {
            kinds = {
                help = {
                    H1 = "",
                    H2 = "",
                    H3 = "",
                    Tag = "*",
                },
                markdown = {
                    H1 = "",
                    H2 = "",
                    H3 = "",
                    H4 = "",
                    H5 = "",
                    H6 = "",
                },
                default = {},
            }
        },
    }
}

return M
