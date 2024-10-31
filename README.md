<!-- panvimdoc-ignore-start -->

# symbols.nvim

Sidebar with a list of symbols. Gives an overview of a file and allows quick
navigation.

**Warning** symbols.nvim is in beta. Breaking changes are expected, you may
encounter some bugs. Documentation may be confusing and behavior unpredictable.

## Features

- Listing Symbols - duh. Uses LSP servers and treesitter parsers which have to
  be configured by the user.
- Preview Window - glance at the code before committing to your next action.
  You can also edit the file in the preview window.
- Inline Details - symbol details can be displayed inline. Those details are
  given by a provider (e.g. LSP).
- Dynamic Settings - a lot of settings can be changed on the fly, without
  changing the config and reopening Neovim.
- Preserving Folds - the sidebar preserves folds on changes (at least most of
  them, most of the time).
- Independent Sidebars - each sidebar has it's own view (folds) and settings,
  even when there are multiple sidebars showing symbols for the same file.
- Custom Display Rules - symbols formatting and filtering can be configured per
  language. The goal is to provide great default configurations for many
  languages while allowing the user to make adjusments according to their
  preference.
- Mouse Support - you can use your mouse, no judgement.

<!-- panvimdoc-ignore-end -->

# Requirements

- neovim 0.10+
- LSP servers for desired languages
- treesitter parsers for markdown and vimdoc (`:TSInstall markdown vimdoc`)

## Quick Start

Using lazy.nvim:

```lua
{
    "oskarrrrrrr/symbols.nvim",
    config = function()
        local r = require("symbols.recipes")
        require("symbols").setup(r.DefaultFilters, r.AsciiSymbols, {
            -- custom settings here
            -- e.g. hide_cursor = false
        })
        vim.keymap.set("n", ",s", ":Symbols<CR>")
        vim.keymap.set("n", ",S", ":SymbolsClose<CR>")
    end
}
```

# Tips

## Help
Press `?` in the sidebar to see help.

## Preview Window
Press the preview window keymap (by default "K") once to open it, the second
time to jump to it. You can now move around the buffer and make changes. Press
"q" to close the window or jump to the sidebar if auto preview is on. Yes, this
means that by default you can't record macros in the preview window.

## Dynamic Settings
A lot of settings can be changed on the fly by using keymaps starting with "t".
For example, try out "td" to toggle inline details, "t=" to toggle sidebar auto
resizing or "tp" to toggle auto preview.

## Navigation
Sometimes you want to get to a deeply nested symbol and unfold all the symbols
on the way. To do that for the symbol under the cursor in the source window
press "gs" when in the sidebar. Other useful mappings for more advanced
navigation are:

- "\[\[" and "\]\]" to go to the previous and next symbol on the same
  level. Can be used with a count.
- "gp" to go to parent symbol, can be used with a count.
- "L"/"zO" and "H"/"zC" for recursively opening and closing folds under the
  cursor . Useful for changing only part of the tree, whereas "zr", "zR", "zm"
  and "zM" affect the whole tree.

You can navigate the sidebar with a mouse. Left click to select a symbol,
double click to toggle fold, right click to peek the symbol.

## Big Files

To work with really big files in Neovim you have to turn off LSPs, treesitter
and more. You can do that with some custom lua code or use a plugin like:
`LunarVim/bigfile.nvim`. The sidebar will not work when LSPs and treesitter are
turned off thus causing no slow downs.

What if you notice slow downs while working on a file of reasonable size?

- If you notice slow downs when moving the cursor around then try setting
  `sidebar.cursor_follow` to false.
- If you notice lagging on save then it might be the sidebar refreshing. For
  now the only solution is to stop using the plugin with large files.
- You can let me know about the problem via issues on GitHub.

# Commands

- `:Symbols[!]` A command designed to be used as your main mapping. Opens the
  Symbols sidebar and jumps to it unless called with the bang (`!`). If called
  when the sidebar is already open then jumps to it regardless of the bang.
  When called in a sidebar jumps back to the source code.
- `:SymbolsClose` Closes the sidebar.


# Configuration

To use the plugin you must run the setup function: `require("symbols").setup()`.
Setup function takes any number of config arguments which will be merged with
the default config.

There are a few predefined recipes (configs) that you can use:

- DefaultFilters - filters out excessive symbols. For example, the Lua LSP
  server provides a symbol for each `if`, `elseif`, `else` and `for` and they
  are discarded by this config.
- AsciiSymbols - symbol kind displayed as text. For instance, "Function" kind 
  might be displayed as "fun", "fn", "func" or "def" depending on the language.
- FancySymbols - symbol kind will be displated as an icon. May be more
  aesthetically plesaing but arguably less readable.

The recipes are available in `symbols.recipes` module.

## Reference

```lua
{
    -- Hide the cursor when in sidebar.
    hide_cursor = true,
    sidebar = {
        -- Side on which the sidebar will open, available options:
        -- try-left  Opens to the left of the current window if there are no
        --           windows there. Otherwise opens to the right.
        -- try-right Opens to the right of the current window if there are no
        --           windows there. Otherwise opens to the left.
        -- right     Always opens to the right of the current window.
        -- left      Always opens to the left of the current window.
        open_direction = "try-left",
        -- Whether to run `wincmd =` after opening a sidebar.
        on_open_make_windows_equal = true,
        -- Whether the cursor in the sidebar should automatically follow the
        -- cursor in the source window. Does not unfold the symbols. You can jump
        -- to symbol with unfolding with "gs" by default.
        cursor_follow = true,
        auto_resize = {
            -- When enabled the sidebar will be resized whenever the view changes.
            -- For example, after folding/unfolding symbols, after toggling inline details
            -- or whenever the source file is saved.
            enabled = true,
            -- The sidebar will never be auto resized to a smaller width then `min_width`.
            min_width = 20,
            -- The sidebar will never be auto resized to a larger width then `max_width`.
            max_width = 40,
        },
        -- Default sidebar width.
        fixed_width = 30,
        -- Allows to filter symbols. By default all the symbols are shown.
        symbol_filter = function(filetype, symbol) return true end,
        -- Show inline details by default.
        show_inline_details = false,
        -- Show details floating window at all times.
        show_details_pop_up = false,
        -- Whether the sidebar should wrap text.
        wrap = false,
        -- Whether to show the guide lines.
        show_guide_lines = false,
        chars = {
            folded = "",
            unfolded = "",
            guide_vert = "│",
            guide_middle_item = "├",
            guide_last_item = "└",
        },
        -- Config for the preview window.
        preview = {
            -- Whether the preview window should show line numbers.
            show_line_number = false,
            -- Whether to determine the preview window's height automatically.
            auto_size = true,
            -- The total number of extra lines shown in the preview window.
            auto_size_extra_lines = 6,
            -- Minimum window height when `auto_size` is true.
            min_window_height = 7,
            -- Maximum window height when `auto_size` is true.
            max_window_height = 30,
            -- Preview window size when `auto_size` is false.
            fixed_size_height = 12,
            -- Desired preview window width. Actuall width will be capped at
            -- the current width of the source window width.
            window_width = 100,
            -- Keymaps for actions in the preview window. Available actions:
            -- close: Closes the preview window.
            -- goto-code: Changes window to the source code and moves cursor to
            --            the same position as in the preview window.
            -- Note: goto-code is not set by default because the most natual
            -- key would be Enter but some people already have that key mapped.
            keymaps = {
                ["q"] = "close",
            },
        },
        -- Keymaps for actions in the sidebar. All available actions are used
        -- in the default keymaps.
        keymaps = {
            -- Jumps to symbol in the source window.
            ["<CR>"] = "goto-symbol",
            -- Jumps to symbol in the source window but the cursor stays in the
            -- sidebar.
            ["<RightMouse>"] = "peek-symbol",
            ["o"] = "peek-symbol",

            -- Opens a floating window with symbol preview.
            ["K"] = "open-preview",
            -- Opens a floating window with symbol details.
            ["d"] = "open-details-window",

            -- In the sidebar jumps to symbol under the cursor in the source
            -- window. Unfolds all the symbols on the way.
            ["gs"] = "show-symbol-under-cursor",
            -- Jumps to parent symbol. Can be used with a count, e.g. "3gp"
            -- will go 3 levels up.
            ["gp"] = "goto-parent",
            -- Jumps to the previous symbol at the same nesting level.
            ["[["] = "prev-symbol-at-level",
            -- Jumps to the next symbol at the same nesting level.
            ["]]"] = "next-symbol-at-level",

            -- Unfolds the symbol under the cursor.
            ["l"] = "unfold",
            ["zo"] = "unfold",
            -- Unfolds the symbol under the cursor and all its descendants.
            ["L"] = "unfold-recursively",
            ["zO"] = "unfold-recursively",
            -- Reduces folding by one level. Can be used with a count,
            -- e.g. "3zr" will unfold 3 levels.
            ["zr"] = "unfold-one-level",
            -- Unfolds all symbols in the sidebar.
            ["zR"] = "unfold-all",

            -- Folds the symbol under the cursor.
            ["h"] = "fold",
            ["zc"] = "fold",
            -- Folds the symbol under the cursor and all its descendants.
            ["H"] = "fold-recursively",
            ["zC"] = "fold-recursively",
            -- Increases folding by one level. Can be used with a count,
            -- e.g. "3zm" will fold 3 levels.
            ["zm"] = "fold-one-level",
            -- Folds all symbols in the sidebar.
            ["zM"] = "fold-all",

            -- Toggles inline details (see sidebar.show_inline_details).
            ["td"] = "toggle-inline-details",
            -- Toggles auto details floating window (see sidebar.show_details_pop_up).
            ["tD"] = "toggle-auto-details-window",
            -- Toggles auto preview floating window.
            ["tp"] = "toggle-auto-preview",
            -- Toggles cursor hiding (see sidebar.auto_resize.
            ["tc"] = "toggle-cursor-hiding",
            -- Toggles cursor following (see sidebar.cursor_follow).
            ["tf"] = "toggle-cursor-follow",
            -- Toggles automatic sidebar resizing (see sidebar.auto_resize).
            ["t="] = "toggle-auto-resize",

            -- Toggle fold of the symbol under the cursor.
            ["<2-LeftMouse>"] = "toggle-fold",

            -- Close the sidebar window.
            ["q"] = "close",

            -- Show help.
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
```

# Alternatives

- [aerial.nvim](https://github.com/stevearc/aerial.nvim)
- [outline.nvim](https://github.com/hedyhli/outline.nvim)

