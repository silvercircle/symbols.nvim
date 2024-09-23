local ANUM = function() print("abc") end

local dev = require("my-outline.dev")

local sym_win = require("my-outline.symbols_window")
local SymbolsWindowCollection = sym_win.SymbolsWindowCollection

local M = {}

---@param buf integer
---@param lines string[]
local function buf_append(buf, lines)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local start = line_count == 1 and 0 or line_count
    vim.api.nvim_buf_set_lines(buf, start, -1, false, lines)
end

local function show_floating_window(text)
    local ui = vim.api.nvim_list_uis()[1]
    local height = math.max(math.floor(0.8 * ui.height), 40)
    local width = 100
    local row = (ui.height - height) / 2
    local col = (ui.width - width) / 2

    local opts = {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "single",
        style = "minimal",
    }
    local buf = vim.api.nvim_create_buf(false, true);
    local indented_text =
        vim.iter(vim.split(text, "\n")):map(function(s) return "  " .. s end):totable()
    buf_append(buf, {"  My Outline Config | Quit[q] | Copy[c]", ""})
    buf_append(buf, indented_text)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    local win = vim.api.nvim_open_win(buf, true, opts)
    vim.api.nvim_win_set_cursor(win, {3, 3})

    vim.keymap.set(
        "n",
        "q",
        function() vim.api.nvim_win_close(win, false) end,
        { silent=true, desc = "Close window.", buffer = buf }
    )

    vim.keymap.set(
        "n",
        "c",
        function() vim.fn.setreg("+", text) end,
        { silent=true, desc = "Yank config.", buffer = buf }
    )
end

local coll = SymbolsWindowCollection._new({})

vim.api.nvim_create_autocmd(
    "WinClosed",
    {
        pattern="*",
        callback=function(t)
            local win = tonumber(t.match, 10)
            coll:on_win_close(win)
        end,
    }
)

vim.api.nvim_create_autocmd(
    "TabClosed",
    {
        pattern="*",
        callback=function(t)
            local tab = tonumber(t.match, 10)
            coll:on_tab_close(tab)
        end
    }
)

vim.api.nvim_create_autocmd(
    "BufEnter",
    {
        callback = function()
            if vim.bo.filetype == "Symbols" and vim.fn.winnr("$") == 1 then
                vim.cmd("q")
            end
        end,
    }
)

local function config_window()
    coll:add("right", false)
end

local function lsp_test()
    local bufnr = 0

    local clients = vim.lsp.get_clients({bufnr = bufnr})
    local c = clients[1]
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(bufnr),
    }

    ---@type vim.lsp.Handler
    local handler = function (err, symbol, ctx, config)
        show_floating_window(vim.inspect(symbol))
    end

    local b, i = c.request("textDocument/documentSymbol", params, handler)
    -- print(b, i)
end

local function symbols_debug()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "Symbols Window Collection [" .. os.date("%X") .. "]")
    vim.api.nvim_buf_set_option(buf, "bufhidden", "delete")
    local text = vim.split(vim.inspect(coll), "\n")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    vim.api.nvim_buf_set_option(buf, "modifiable", false)
end

function M.setup()
    if dev.env() == "dev" then dev.setup() end

    vim.api.nvim_create_user_command("Td", symbols_debug, {})

    vim.api.nvim_create_user_command("Tr", function() coll:add("right", false) end, {})
    vim.api.nvim_create_user_command("TR", function() coll:add("right", true) coll:lsp() end, {})
    vim.api.nvim_create_user_command("Tl", function() coll:add("left", false) end, {})
    vim.api.nvim_create_user_command("TL", function() coll:add("left", true) end, {})

    vim.api.nvim_create_user_command("Tq", function() coll:quit() end, {})
    vim.api.nvim_create_user_command("Tqo", function() coll:quit_outer() end, {})
    vim.api.nvim_create_user_command("Tqa", function() coll:quit_all() end, {})

    vim.api.nvim_create_user_command("Tlsp", function() coll:lsp() end, {})
end

--- TREE
--- Fields:
---  kind
---  name
---  folded
---  extra info
---  range
---  level
---  children

return M
