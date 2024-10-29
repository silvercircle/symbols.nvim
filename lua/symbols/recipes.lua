local M = {}

M.AsciiSymbols = {
    providers = {
        lsp = {
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
                    if (pkind == "Array" or pkind == "Object") and (kind ~= "Array" and kind ~= "Object") then
                        local obj_map = {
                            Boolean = " b",
                            Function = "fn",
                            Number = " #",
                            String = "\"\"",
                            Variable = " ?",
                        }
                        return obj_map[kind] or "  "
                    end
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
