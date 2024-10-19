# symbols.nvim (WIP)

Navigation sidebar that lists all the symbols found in the file. Uses LSP whenever available or treesitter for markdown and vimdoc.

## Requirements

- neovim 0.10+
- (optional) properly configured LSPs
- (optional) treesitter parsers for markdown and vimdoc (`:TSInstall markdown vimdoc`).

## Example Config

Using lazy.nvim:

```lua
{
    dir = "path/to/symbols.nvim",
    config = function()
        local r = require("symbols.recipes")
        require("symbols").setup(
            vim.tbl_deep_extend("force",
                r.FancySymbols, -- or: r.AsciiSymbols
                {
                    -- custom settings here
                    -- e.g. hide_cursor = true
                    -- for more options see: lua/symbols/config.lua
                }
            )
        )
        vim.keymap.set("n", ",s", ":Symbols<CR>")
        vim.keymap.set("n", ",S", ":SymbolsClose<CR>")
    end
}
```

## Commands

- `:Symbols` opens the sidebar
- `:SymbolsClose` clses the sidebar

## Tip

Press `?` in the sidebar to see help.

## Alternatives

[outline.nvim](https://github.com/hedyhli/outline.nvim)
[aerial.nvim](https://github.com/stevearc/aerial.nvim)
