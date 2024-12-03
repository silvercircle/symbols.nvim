vim.cmd("let &rtp.=','.getcwd()")
require("symbols").setup()

vim.cmd("set runtimepath+=deps/nvim-treesitter")
require("nvim-treesitter.configs").setup({
    ensure_installed = { "markdown", "org", "vimdoc", "json" },
    auto_install = true,
})
