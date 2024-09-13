local dev = require("my-outline.dev")
local cfg = require("my-outline.cfg")

local M = {}

---@param buf integer
---@param lines string[]
local function buf_append(buf, lines)
    local line_count = vim.api.nvim_buf_line_count(buf)
    local start = line_count == 1 and 0 or line_count
    vim.api.nvim_buf_set_lines(buf, start, -1, false, lines)
end

local function show_floating_window()
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
    local text = vim.inspect(cfg.default)
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
        { silent=true, desc = "close window", buffer = buf }
    )

    vim.keymap.set(
        "n",
        "c",
        function() vim.fn.setreg("+", text) end,
        { silent=true, desc = "close window", buffer = buf }
    )
end

function M.setup()
    if dev.env() == "dev" then dev.setup() end
    vim.api.nvim_create_user_command("Test", show_floating_window, {})
end

return M
