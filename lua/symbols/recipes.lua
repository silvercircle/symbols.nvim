local M = {}

---@type CharConfig
M.SidebarCharsNice = {
    folded = "",
    unfolded = "",
}

M.LspKindJsonAscii = {
    Module = { kind = "{}" },
    Array = { kind = "[]" },
    Boolean = { kind = "b" },
    String = { kind = "\"" },
    Number = { kind = "#" },
    Variable = { kind = "?" },
}

M.LspKindYamlAscii = {
    Module = { kind = "{}" },
    Array = { kind = "[]" },
    Boolean = { kind = "b" },
    String = { kind = "\"" },
    Number = { kind = "#" },
    Variable = { kind = "?" },
}

M.LspKindLuaAscii = {
    Array = { kind = "[]" },
    Boolean = { kind = "boolean" },
    Constant = { kind = "param" },
    Function = { kind = "function" },
    Method = { kind = "function" },
    Number = { kind = "number" },
    Object = { kind = "{}" },
    Package = { kind = "" },
    String = { kind = "string" },
    Variable = { kind = "local" },
}

M.LspKindGoAscii = {
    Struct = { kind = "struct" },
    Class = { kind = "type" },
    Constant = { kind = "const" },
    Function = { kind = "func" },
    Method = { kind = "func" },
    Field = { kind = "field" },
}

M.LspKindPythonAscii = {
    Class = { kind = "class" },
    Variable = { kind = "" },
    Constant = { kind = "const" },
    Function = { kind = "def" },
    Method = { kind = "def" },
}

M.LspKindBashAscii = {
    Variable = { kind = "$" },
    Function = { kind = "function" },
}

M.AsciiSymbols = {
    lsp = {
        filetype = {
            json = { symbol_display = M.LspKindJsonAscii, },
            yaml = { symbol_display = M.LspKindYamlAscii, },
            lua = { symbol_display = M.LspKindLuaAscii, },
            go = { symbol_display = M.LspKindGoAscii, },
            python = { symbol_display = M.LspKindPythonAscii, },
            sh = { symbol_display = M.LspKindBashAscii, },
            default = {
                symbol_display = {}
            }
        }
    },
    vimdoc = {
        filetype = {
            default = {
                symbol_display = {
                    H1 = { kind = "#" },
                    H2 = { kind = "##" },
                    H3 = { kind = "###" },
                    Tag = { kind = "*" },
                }
            }
        }
    }
}

return M
