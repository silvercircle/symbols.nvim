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
        vim.api.nvim_buf_set_option(buf, "bufhidden", "delete")
        vim.api.nvim_buf_set_name(buf, buf_name)
        vim.api.nvim_buf_set_option(buf, "modifiable", false)
        vim.api.nvim_buf_set_option(buf, 'filetype', 'Symbols')
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

    return M.SymbolsWindow._new(o or {}, true, tab, win, split, buf, source_win, source_win_locked)
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

return M
