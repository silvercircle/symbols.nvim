local M = {}

---@class CharConfig
---@field folded string
---@field unfolded string
---@field guide_vert string
---@field guide_middle_item string
---@field guide_last_item string

---@alias SidebarAction
---| "goto-symbol"
---| "preview"
---| "peek"
---| "parent",
---| "next-symbol-at-level",
---| "prev-symbol-at-level",
---| "show-symbol-under-cursor"
---| "toggle-show-details"
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
---| "toggle-auto-details"
---| "toggle-auto-preview"
---| "toggle-cursor-hiding"
---| "toggle-cursor-follow"
---| "help"
---| "close"

---@alias KeymapsConfig table<string, SidebarAction?>


---@alias DevAction
---| "reload"
---| "debug"
---| "show-config"

---@alias PreviewAction
---| "close"
---| "goto-code"

---@class PreviewConfig
---@field show_line_number boolean
---@field auto_size boolean
---@field auto_size_extra_lines integer
---@field fixed_size_height integer
---@field min_window_height integer
---@field max_window_height integer
---@field window_width integer
---@field keymaps table<string, PreviewAction>

---@class DevConfig
---@field enabled boolean
---@field log_level integer
---@field keymaps table<string, DevAction>

---@class AutoResizeConfig
---@field enabled boolean
---@field min_width integer
---@field max_width integer

---@alias OpenDirection
---| "left"
---| "right"
---| "try-left"
---| "try-right"

---@class SidebarConfig
---@field open_direction OpenDirection
---@field cursor_follow boolean
---@field auto_resize AutoResizeConfig
---@field fixed_width integer
---@field symbol_filter fun(ft: string, symbol: Symbol): boolean
---@field show_inline_details boolean
---@field show_details_pop_up boolean
---@field show_guide_lines boolean
---@field wrap boolean
---@field chars CharConfig
---@field preview PreviewConfig
---@field keymaps KeymapsConfig

---@class SymbolDisplayConfig
---@field kind string?
---@field highlight string

---@class LspFileTypeConfig
---@field symbol_display table<string, SymbolDisplayConfig>

---@alias ProviderKindFun fun(symbol: Symbol): string

---@class ProviderDetailsFunCtx
---@field symbol_states SymbolStates

---@alias ProviderDetailsFun fun(symbol: Symbol, ctx: ProviderDetailsFunCtx): string

---@class ProviderConfig
---@field details table<string, ProviderDetailsFun>
---@field kinds table<string, table<string, string> | ProviderKindFun>
---@field highlights table<string, table<string, string>>

---@class LspConfig : ProviderConfig
---@field timeout_ms integer

---@class TreesitterConfig : ProviderConfig

---@class ProvidersConfig
---@field lsp LspConfig
---@field treesitter TreesitterConfig

---@class Config
---@field hide_cursor boolean
---@field sidebar SidebarConfig
---@field providers ProvidersConfig
---@field dev DevConfig

---@type Config
M.default = {
    hide_cursor = false,
    sidebar = {
        open_direction = "try-left",
        cursor_follow = true,
        auto_resize = {
            enabled = true,
            min_width = 20,
            max_width = 40,
        },
        fixed_width = 30,
        symbol_filter = function(_, _) return true end,
        show_inline_details = false,
        show_details_pop_up = false,
        show_guide_lines = false,
        wrap = false,
        chars = {
            folded = "",
            unfolded = "",
            guide_vert = "│",
            guide_middle_item = "├",
            guide_last_item = "└",
        },
        preview = {
            show_line_number = false,
            auto_size = true,
            auto_size_extra_lines = 6,
            fixed_size_height = 12,
            min_window_height = 7,
            max_window_height = 30,
            window_width = 100,
            keymaps = {
                ["q"] = "close",
            },
        },
        keymaps = {
            ["<CR>"] = "goto-symbol",
            ["o"] = "peek",

            ["K"] = "preview",
            ["d"] = "toggle-show-details",
            ["gs"] = "show-symbol-under-cursor",

            ["gp"] = "parent",
            ["["] = "prev-symbol-at-level",
            ["]"] = "next-symbol-at-level",

            ["l"] = "unfold",
            ["zo"] = "unfold",
            ["L"] = "unfold-recursively",
            ["zO"] = "unfold-recursively",
            ["zr"] = "unfold-one-level",
            ["zR"] = "unfold-all",

            ["h"] = "fold",
            ["zc"] = "fold",
            ["H"] = "fold-recursively",
            ["zC"] = "fold-recursively",
            ["zm"] = "fold-one-level",
            ["zM"] = "fold-all",

            ["td"] = "toggle-details",
            ["tD"] = "toggle-auto-details",
            ["tp"] = "toggle-auto-preview",
            ["tc"] = "toggle-cursor-hiding",
            ["tf"] = "toggle-cursor-follow",

            ["<2-LeftMouse>"] = "toggle-fold",
            ["<RightMouse>"] = "goto-symbol",

            ["q"] = "close",
            ["?"] = "help",
            ["g?"] = "help",
        },
    },
    providers = {
        lsp = {
            timeout_ms = 1000,
            details = {},
            kinds = { default = {} },
            highlights = {
                default = {
                    File = "Identifier",
                    Module = "Include",
                    Namespace = "Include",
                    Package = "Include",
                    Class = "Type",
                    Method = "Function",
                    Property = "Identifier",
                    Field = "Identifier",
                    Constructor = "Special",
                    Enum = "Type",
                    Interface = "Type",
                    Function = "Function",
                    Variable = "Constant",
                    Constant = "Constant",
                    String = "String",
                    Number = "Number",
                    Boolean = "Boolean",
                    Array = "Constant",
                    Object = "Type",
                    Key = "Type",
                    Null = "Type",
                    EnumMember = "Identifier",
                    Struct = "Structure",
                    Event = "Type",
                    Operator = "Identifier",
                    TypeParameter = "Identifier",
                }
            },
        },
        treesitter = {
            details = {},
            kinds = { default = {} },
            highlights = {
                markdown = {
                    H1 = "@markup.heading.1.markdown",
                    H2 = "@markup.heading.2.markdown",
                    H3 = "@markup.heading.3.markdown",
                    H4 = "@markup.heading.4.markdown",
                    H5 = "@markup.heading.5.markdown",
                    H6 = "@markup.heading.6.markdown",
                },
                help = {
                    H1 = "@markup.heading.1.vimdoc",
                    H2 = "@markup.heading.2.vimdoc",
                    H3 = "@markup.heading.3.vimdoc",
                    Tag = "@label.vimdoc",
                },
                default = {}
            }
        },
    },
    dev = {
        enabled = false,
        log_level = vim.log.levels.ERROR,
        keymaps = {},
    }
}

---@param config table
---@return Config
function M.prepare_config(config)
    local function extend_from_default(cfg)
        for ft, _ in pairs(cfg) do
            if ft ~= "default" then
                cfg[ft] = vim.tbl_deep_extend("force", cfg.default, cfg[ft])
            end
        end
    end

    config = vim.tbl_deep_extend("force", M.default, config)
    local providers = { "lsp", "treesitter" }
    for _, provider in ipairs(providers) do
        extend_from_default(config.providers[provider].highlights)
    end

    return config
end

---@param config table
---@param filetype string
---@return table
function M.get_config_by_filetype(config, filetype)
    local ft_config = config[filetype]
    if ft_config ~= nil then return ft_config end
    return config.default
end

---@param kinds table<string, string> | ProviderKindFun
---@param symbol Symbol
---@return string
function M.kind_for_symbol(kinds, symbol)
    local kind = nil
    if type(kinds) == "function" then
        kind = kinds(symbol)
    else
        kind = kinds[symbol.kind]
    end
    return kind or symbol.kind
end

return M
