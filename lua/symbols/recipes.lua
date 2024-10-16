local M = {}

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

M.LspKindCssAscii = {
    Class = { kind = "" },
    Module = { kind = "" },
}

M.VimdocKindAscii = {
    H1 = { kind = "#" },
    H2 = { kind = "##" },
    H3 = { kind = "###" },
    Tag = { kind = "*" },
}

M.MarkdownKindAscii = {
    H1 = { kind = "#" },
    H2 = { kind = "##" },
    H3 = { kind = "###" },
    H4 = { kind = "####" },
    H5 = { kind = "#####" },
    H6 = { kind = "######" },
}

M.LspKindJavascriptAscii = {
    Function = { kind = "function" },
    Constant = { kind = "const" },
    Variable = { kind = "let" },
    Property = { kind = "" },
}

M.LspKindTypescriptAscii = {
    Function = { kind = "function" },
    Constant = { kind = "const" },
    Variable = { kind = "let" },
    Property = { kind = "" },
}

M.AsciiSymbols = {
    providers = {
        lsp = {
            filetype = {
                json = { symbol_display = M.LspKindJsonAscii },
                yaml = { symbol_display = M.LspKindYamlAscii },
                lua = { symbol_display = M.LspKindLuaAscii },
                go = { symbol_display = M.LspKindGoAscii },
                python = { symbol_display = M.LspKindPythonAscii },
                sh = { symbol_display = M.LspKindBashAscii },
                css = { symbol_display = M.LspKindCssAscii },
                javascript = { symbol_display = M.LspKindJavascriptAscii },
                typescript = { symbol_display = M.LspKindTypescriptAscii },
                default = { symbol_display = {} },
            }
        },
        vimdoc = { filetype = { default = { symbol_display = M.VimdocKindAscii } } },
        markdown = { filetype = { default = { symbol_display = M.MarkdownKindAscii } } },
    }
}

M.FancySymbols = {
    providers = {
        lsp = {
            filetype = {
                default = {
                    symbol_display = {
                        File = { kind = "󰈔" },
                        Module = { kind = "󰆧" },
                        Namespace = { kind = "󰅪" },
                        Package = { kind = "󰏗" },
                        Class = { kind = "𝓒" },
                        Method = { kind = "ƒ" },
                        Property = { kind = "" },
                        Field = { kind = "󰆨" },
                        Constructor = { kind = "" },
                        Enum = { kind = "ℰ" },
                        Interface = { kind = "󰜰" },
                        Function = { kind = "" },
                        Variable = { kind = "" },
                        Constant = { kind = "" },
                        String = { kind = "𝓐" },
                        Number = { kind = "#" },
                        Boolean = { kind = "⊨" },
                        Array = { kind = "󰅪" },
                        Object = { kind = "⦿" },
                        Key = { kind = "🔐" },
                        Null = { kind = "NULL" },
                        EnumMember = { kind = "" },
                        Struct = { kind = "𝓢" },
                        Event = { kind = "🗲" },
                        Operator = { kind = "+" },
                        TypeParameter = { kind = "𝙏" },
                        Component = { kind = "󰅴" },
                        Fragment = { kind = "󰅴" },
                    }
                }
            }
        },
        vimdoc = { filetype = { default = { symbol_display = {
            H1 = { kind = "#" },
            H2 = { kind = "##" },
            H3 = { kind = "###" },
            Tag = { kind = "*" },
        }}}},
        markdown = { filetype = { default = { symbol_display = {
            H1 = { kind = "#" },
            H2 = { kind = "##" },
            H3 = { kind = "###" },
            H4 = { kind = "####" },
            H5 = { kind = "#####" },
            H6 = { kind = "######" },
        }}}},
    }
}

return M
