local M = {}

---@class CharConfig
---@field folded string
---@field unfolded string

---@alias SidebarAction
---| "goto-symbol"
---| "preview"
---| "show-details"
---| "toggle-fold"
---| "unfold"
---| "unfold-recursively"
---| "unfold-one-level"
---| "unfold-all"
---| "fold"
---| "fold-recursively"
---| "fold-one-level"
---| "fold-all"
---| "toggle-details"
---| "toggle-auto-preview"
---| "toggle-cursor-hiding"
---| "help"
---| "close"

---@alias KeymapsConfig table<string, SidebarAction?>

---@class SymbolDisplayConfig
---@field kind string?
---@field highlight string

---@class LspFileTypeConfig
---@field symbol_display table<string, SymbolDisplayConfig>

---@class LspConfig
---@field timeout_ms integer
---@field filetype table<string, LspFileTypeConfig>

---@alias DevAction
---| "reload"
---| "debug"
---| "show-config"

---@class PreviewConfig
---@field show_line_number boolean
---@field auto_size boolean
---@field auto_size_extra_lines integer
---@field fixed_size_height integer
---@field min_window_height integer
---@field max_window_height integer
---@field window_width integer

---@class DevConfig
---@field enabled boolean
---@field keymaps table<string, DevAction>

---@class SidebarConfig
---@field show_details boolean
---@field chars CharConfig
---@field preview PreviewConfig
---@field keymaps KeymapsConfig

---@class Config
---@field hide_cursor boolean
---@field sidebar SidebarConfig
---@field lsp LspConfig
---@field dev DevConfig

---@type Config
M.default = {
    hide_cursor = false,
    sidebar = {
        show_details = false,
        chars = {
            folded = "+",
            unfolded = "-",
        },
        preview = {
            show_line_number = false,
            auto_size = true,
            auto_size_extra_lines = 6,
            fixed_size_height = 12,
            min_window_height = 7,
            max_window_height = 30,
            window_width = 100,
        },
        keymaps = {
            ["<CR>"] = "goto-symbol",
            ["K"] = "preview",
            ["d"] = "show-details",

            ["l"] = "unfold",
            ["L"] = "unfold-recursively",
            ["zr"] = "unfold-one-level",
            ["zR"] = "unfold-all",

            ["h"] = "fold",
            ["H"] = "fold-recursively",
            ["zm"] = "fold-one-level",
            ["zM"] = "fold-all",

            ["td"] = "toggle-details",
            ["tp"] = "toggle-auto-preview",
            ["tc"] = "toggle-cursor-hiding",

            ["<2-LeftMouse>"] = "toggle-fold",
            ["<RightMouse>"] = "goto-symbol",

            ["q"] = "close",
            ["?"] = "help",
        },
    },
    lsp = {
        timeout_ms = 500,
        filetype = {
            default = {
                symbol_display = {
                    File = { highlight = "Identifier" },
                    Module = { highlight = "Include" },
                    Namespace = { highlight = "Include" },
                    Package = { highlight = "Include" },
                    Class = { highlight = "Type" },
                    Method = { highlight = "Function" },
                    Property = { highlight = "Identifier" },
                    Field = { highlight = "Identifier" },
                    Constructor = { highlight = "Special" },
                    Enum = { highlight = "Type" },
                    Interface = { highlight = "Type" },
                    Function = { highlight = "Function" },
                    Variable = { highlight = "Constant" },
                    Constant = { highlight = "Constant" },
                    String = { highlight = "String" },
                    Number = { highlight = "Number" },
                    Boolean = { highlight = "Boolean" },
                    Array = { highlight = "Constant" },
                    Object = { highlight = "Type" },
                    Key = { highlight = "Type" },
                    Null = { highlight = "Type" },
                    EnumMember = { highlight = "Identifier" },
                    Struct = { highlight = "Structure" },
                    Event = { highlight = "Type" },
                    Operator = { highlight = "Identifier" },
                    TypeParameter = { highlight = "Identifier" },
                },
            }
        }
    },
    vimdoc = {
        filetype = {
            default = {
                symbol_display = {
                    H1 = { highlight = "@markup.heading.1.vimdoc" },
                    H2 = { highlight = "@markup.heading.2.vimdoc" },
                    H3 = { highlight = "@markup.heading.3.vimdoc" },
                    Tag = { highlight = "@label.vimdoc" },
                }
            }
        }
    },
    markdown = {
        filetype = {
            default = {
                symbol_display = {
                    H1 = { highlight = "@markup.heading.1.markdown" },
                    H2 = { highlight = "@markup.heading.2.markdown" },
                    H3 = { highlight = "@markup.heading.3.markdown" },
                }
            }
        },
    },
    dev = {
        enabled = false,
        keymaps = {},
    }
}

---@return Config
function M.prepare_config(config)
    config = vim.tbl_deep_extend("force", M.default, config)

    local providers = { "lsp", "vimdoc" }
    for _, provider in ipairs(providers) do
        local default_config = config[provider].filetype.default
        for ft, ft_config in pairs(config[provider].filetype) do
            if ft ~= "default" then
                ft_config.symbol_display = vim.tbl_deep_extend(
                    "force",
                    default_config.symbol_display,
                    ft_config.symbol_display or {}
                )
            end
        end
    end

    return config
end

---@param config Config
---@param provider_name string
---@param filetype string
---@return table<string, SymbolDisplayConfig>
function M.symbols_display_config(config, provider_name, filetype)
    local ft_config = config[provider_name].filetype[filetype]
    if ft_config ~= nil and ft_config.symbol_display ~= nil then
        return ft_config.symbol_display
    end
    return config[provider_name].filetype.default.symbol_display
end

return M
