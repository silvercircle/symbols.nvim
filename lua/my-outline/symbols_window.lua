--- TODO
--- [ ] fold
--- [x] preview
--- [ ] allow other providers with custom symbols (e.g. H1 for markdown); maybe also custom highlights?

local lsp = require("my-outline.lsp")


local M = {}

---@class SymbolsWindow
---@field deleted boolean
---@field visible boolean
---@field tab integer
---@field win integer
---@field win_dir "left" | "right" | nil
---@field buf integer
---@field source_win integer
---@field source_win_locked boolean
---@field symbols table
M.SymbolsWindow = {}
M.SymbolsWindow.__index = M.SymbolsWindow

---@param o table?
---@param tab integer
---@param win integer
---@param win_dir "left" | "right" | nil
---@param buf integer
---@param source_win integer
---@param source_win_locked boolean
---@return SymbolsWindow
function M.SymbolsWindow._new(o, visible, tab, win, win_dir, buf, source_win, source_win_locked)
    o = o or {}
    o.deleted = false
    o.visible = visible
    o.tab = tab
    o.win = win
    o.win_dir = win_dir
    o.buf = buf
    o.source_win = source_win
    o.source_win_locked = source_win_locked
    o.symbols = {}
    return setmetatable(o, M.SymbolsWindow)
end

---@param win integer
local function set_win_options(win)
    vim.api.nvim_win_set_option(win, "spell", false)
    vim.api.nvim_win_set_option(win, "signcolumn", "no")
    vim.api.nvim_win_set_option(win, "foldcolumn", "0")
    vim.api.nvim_win_set_option(win, "number", false)
    vim.api.nvim_win_set_option(win, "relativenumber", false)
    vim.api.nvim_win_set_option(win, "winfixwidth", true)
    vim.api.nvim_win_set_option(win, "list", false)
    -- vim.api.nvim_win_set_option(win, "wrap", cfg.o.outline_window.wrap)
    -- vim.api.nvim_win_set_option(win, "winhl", cfg.o.outline_window.winhl)
    vim.api.nvim_win_set_option(win, "linebreak", true) -- only has effect when wrap=true
    vim.api.nvim_win_set_option(win, "breakindent", true) -- only has effect when wrap=true
end

local function flash_highlight(winnr, durationMs, lines)
  local bufnr = vim.api.nvim_win_get_buf(winnr)
  local line = vim.api.nvim_win_get_cursor(winnr)[1]
  local ns = vim.api.nvim_create_namespace("")
  for i=1,lines do
      vim.api.nvim_buf_add_highlight(bufnr, ns, "Visual", line - 1 + i - 1, 0, -1)
  end
  local remove_highlight = function()
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
  end
  vim.defer_fn(remove_highlight, durationMs)
end

---@param o table?
---@param split "left" | "right"
---@param buf_name string
---@param source_win_locked boolean
---@return SymbolsWindow
function M.SymbolsWindow.new_split(o, split, buf_name, source_win_locked)

    local original_win = vim.api.nvim_get_current_win()
    local source_win = original_win

    local buf
    if o ~= nil and vim.api.nvim_buf_is_valid(o.buf or -1) then
        buf = o.buf
    else
        buf = vim.api.nvim_create_buf(false, true);
        vim.api.nvim_buf_set_option(buf, "bufhidden", "hide")
        vim.api.nvim_buf_set_name(buf, buf_name)
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'Symbols')
        -- vim.bo[buf].readonly = true

        o = o or {}
        local preview_win = -1

        vim.keymap.set(
            "n",
            "K",
            function()
                local bufnr = vim.api.nvim_win_get_buf(o.source_win)
                local opts = {
                    relative = "cursor",
                    anchor = "NE",
                    width = 120,
                    height = 40,
                    row = 0,
                    col = -1,
                    border = "single",
                    style = "minimal",
                }
                preview_win = vim.api.nvim_open_win(bufnr, false, opts)

                local cursor = vim.api.nvim_win_get_cursor(0)
                local row = cursor[1]
                vim.api.nvim_win_set_cursor(preview_win, {o.symbols[row].selectionRange.start.line+1, o.symbols[row].selectionRange.start.character})
                vim.fn.win_execute(preview_win, 'normal! zz')
                local r = o.symbols[row].range
                flash_highlight(preview_win, 400, r["end"].line - r.start.line + 1)
            end,
            { silent=true, buffer=buf }
        )

        --- Use aucmd on CursorMoved instead
    --     vim.keymap.set(
    --         "n",
    --         "j",
    --         function()
    --             if vim.api.nvim_win_is_valid(preview_win) then
    --                 vim.api.nvim_win_close(preview_win, true)
    --                 preview_win = -1
    --             end
    --             vim.fn.win_execute(o.win, "normal! j")
    --         end
    --     )
    --
    --     vim.keymap.set(
    --         "n",
    --         "k",
    --         function()
    --             if vim.api.nvim_win_is_valid(preview_win) then
    --                 vim.api.nvim_win_close(preview_win, true)
    --                 preview_win = -1
    --             end
    --             vim.fn.win_execute(o.win, "normal! k")
    --         end
    --     )
    end

    if source_win_locked then
        vim.cmd("vs")
        if split == "left" then
            source_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(original_win)
        end
    else
        if split == "left" then
            vim.cmd("topleft vs")
        elseif split == "right" then
            vim.cmd("botright vs")
        end
    end

    local win = vim.api.nvim_get_current_win()
    set_win_options(win)

    local tab = vim.api.nvim_win_get_tabpage(win)

    vim.api.nvim_win_set_buf(win, buf)
    local ui = vim.api.nvim_list_uis()[1]
    local width = math.min(math.floor(0.2 * ui.width), 30)
    vim.cmd("vertical resize " .. width)

    return M.SymbolsWindow._new(o, true, tab, win, split, buf, source_win, source_win_locked)
end

function M.SymbolsWindow:close()
    self.visible = false
    if vim.api.nvim_win_is_valid(self.win) then
        vim.api.nvim_win_close(self.win, true)
    end
    self.win = -1
end

function M.SymbolsWindow:delete()
    if self.deleted then return end
    self:close()
    if vim.api.nvim_buf_is_valid(self.buf) then
        vim.api.nvim_buf_delete(self.buf, { force = true } )
    end
    self.deleted = true
end

---@class SymbolsWindowCollection
---@field windows SymbolsWindow[]
M.SymbolsWindowCollection = {}
M.SymbolsWindowCollection.__index = M.SymbolsWindowCollection

---@param o table?
---@return SymbolsWindowCollection
function M.SymbolsWindowCollection._new(o)
    o = o or {}
    o.windows = {}
    setmetatable(o, M.SymbolsWindowCollection)
    return o
end

---@param source_win_locked boolean
---@return integer
function M.SymbolsWindowCollection:find(source_win_locked)
    if source_win_locked then
        local win = vim.api.nvim_get_current_win()
        for i, w in ipairs(self.windows) do
            if w.source_win_locked and w.source_win == win then
                return i
            end
        end
    else
        local tab = vim.api.nvim_win_get_tabpage(0)
        for i, w in ipairs(self.windows) do
            if not w.source_win_locked and w.tab == tab then
                return i
            end
        end
    end
    return -1
end

---@param split "left" | "right"
---@param source_win_locked boolean
function M.SymbolsWindowCollection:add(split, source_win_locked)
    local i = self:find(source_win_locked)
    if i == -1 then
        i = 1
        while self.windows[i] ~= nil and not self.windows[i].deleted do
            i = i + 1
        end
        self.windows[i] = M.SymbolsWindow.new_split(self.windows[i], split, "Symbols [" .. i .. "]", source_win_locked)
    else
        local win = self.windows[i]
        if not (win.visible and win.win_dir == split) then
            win:close()
            M.SymbolsWindow.new_split(win, split, "Symbols [" .. i .. "]", source_win_locked)
        end
    end
end

function M.SymbolsWindowCollection:quit_outer()
    local tab = vim.api.nvim_get_current_tabpage()
    for _, w in ipairs(self.windows) do
        if not w.deleted and w.visible and not w.source_win_locked and w.tab == tab then
            w:close()
        end
    end
end

function M.SymbolsWindowCollection:quit()
    local win = vim.api.nvim_get_current_win()
    for _, w in ipairs(self.windows) do
        if not w.deleted and w.visible and (w.win == win or (w.source_win_locked and w.source_win == win)) then
            w:close()
            return
        end
    end
    self:quit_outer()
end

function M.SymbolsWindowCollection:quit_all()
    local tab = vim.api.nvim_get_current_tabpage()
    for _, w in ipairs(self.windows) do
        if not w.deleted and w.tab == tab then
            w:close()
        end
    end
end

---@param win integer
function M.SymbolsWindowCollection:on_win_close(win)
    for _, w in ipairs(self.windows) do
        if not w.deleted then
            if w.source_win_locked and w.source_win == win then
                w:delete()
            end
            if w.win == win then
                w:close()
            end
        end
    end
end

---@param tab integer
function M.SymbolsWindowCollection:on_tab_close(tab)
    for _, w in ipairs(self.windows) do
        if w.tab == tab then
            w:delete()
        end
    end
end

function M.SymbolsWindowCollection:lsp()
    local curr_win = vim.api.nvim_get_current_win()

    local w = nil
    for _, win in ipairs(self.windows) do
        if win.source_win_locked and win.win == curr_win then
            w = win
        end
    end
    if w == nil then return end

    local buf = vim.api.nvim_win_get_buf(w.source_win)

    local clients = vim.lsp.get_clients({bufnr = buf})
    local c = clients[1]
    local params = {
        textDocument = vim.lsp.util.make_text_document_params(buf),
    }

    local function current_node()
        local line = vim.api.nvim_win_get_cursor(w.win)[1]

        local function get_node(s, n)
            if s.wrapped or n == 0 then
                return s, n
            end
            for _, ch in ipairs(s.children or {}) do
                local ss
                ss, n = get_node(ch, n-1)
                print(ch.name, ss.name, n)
                if n == 0 then
                    return ss, n
                end
            end

            return s, n
        end

        if w.symbols == nil then
            return nil
        end

        local s, _ = get_node(w.symbols, line)
        return s
    end

    local function refresh_view()
        vim.api.nvim_set_option_value("modifiable", true, { buf = w.buf })

        local lines = {}
        local function print_symbol(sss, indent)
            for _, s in ipairs(sss.children or {}) do
                if s.children ~= nil and #(s.children) > 0 then
                    local line = indent .. " > " .. "[" .. lsp.SymbolKindString[s.kind] .. "] " .. s.name
                    table.insert(lines, line)
                    if not s.wrapped then
                        print_symbol(s, indent .. "   ")
                    end
                else
                    local line = indent .. " [" .. lsp.SymbolKindString[s.kind] .. "] " .. s.name
                    table.insert(lines, line)
                end
            end
        end
        print_symbol(w.symbols, "")

        vim.api.nvim_buf_set_lines(w.buf, 0, -1, false, lines)
        vim.api.nvim_set_option_value("modifiable", false, { buf = w.buf })
    end

    vim.keymap.set(
        "n",
        "l",
        function()
            local n = current_node()
            if n ~= nil then
                print(n.name)
                n.wrapped = false
                refresh_view()
            end
        end
    )
    vim.keymap.set(
        "n",
        "h",
        function()
            local n = current_node()
            if n ~= nil then
                print(n.name)
                n.wrapped = true
                refresh_view()
            end
        end
    )

    vim.api.nvim_create_autocmd(
        "CursorMoved",
        {
            callback = function(_)
                local n, _ = current_node()
                if n == nil then
                    print("node nil")
                else
                    print(n.name)
                end
            end,
            buffer = w.buf,
        }
    )

    vim.keymap.set(
        "n",
        "<CR>",
        function()
            local n = current_node()
            if n == nil then return end

            vim.api.nvim_set_current_win(w.source_win)
            vim.api.nvim_win_set_cursor(w.source_win, {n.selectionRange.start.line+1, n.selectionRange.start.character})
            vim.fn.win_execute(w.source_win, 'normal! zz')
            local r = n.range
            flash_highlight(w.source_win, 400, r["end"].line - r.start.line + 1)
        end,
        { silent=true, buffer=w.buf }
    )

    local handler = function (err, symbol, ctx, config)
        w.symbols = { name = "root", wrapped = false, children = symbol }
        local function set_parents(s, parent)
            s.parent = parent
            s.wrapped = true
            for _, ss in ipairs(s.children or {}) do
                set_parents(ss, s)
            end
        end
        set_parents(w.symbols, nil)
        w.symbols.wrapped = false

        refresh_view()
        vim.api.nvim_win_set_cursor(w.source_win, {1, 0})
    end

    local b, i = c.request("textDocument/documentSymbol", params, handler)
end

return M
