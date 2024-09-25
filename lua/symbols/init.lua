local dev = require("symbols.dev")
local lsp = require("symbols.lsp")

local M = {}

---@class Pos
---@field line integer
---@field character integer

---@class Range
---@field start Pos
---@field end Pos

---@class Symbol
---@field kind any
---@field name string
---@field detail string
---@field parent Symbol | nil
---@field children Symbol[]
---@field range Range
---@field selectionRange Range

---@return Symbol
local function symbol_root()
    return {
        kind = "",
        name = "<root>",
        detail = "",
        parent = nil,
        children = {},
        range =  { start = { 0, 0 }, ["end"] = { -1, -1 } },
        selectionRange = { start = { 0, 0 }, ["end"] = { -1, -1 } },
    }
end

---@alias RefreshSymbolsFun fun(symbols: Symbol)

---@class Provider
---@field name string
---@field supports fun(cache: table, buf: integer): boolean
---@field async_get_symbols fun(cache: any, buf: integer, refresh_symbols: RefreshSymbolsFun, on_fail: fun())

---@class Sidebar
---@field deleted boolean
---@field win integer
---@field buf integer
---@field source_win integer
---@field visible boolean
---@field root_symbol Symbol

---@param sidebar Sidebar
---@return integer
local function sidebar_source_win_buf(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.source_win) then
        return vim.api.nvim_win_get_buf(sidebar.source_win)
    end
    return -1
end

---@return string
local function sidebar_str(sidebar)
    local tab = -1
    if vim.api.nvim_win_is_valid(sidebar.win) then
        tab = vim.api.nvim_win_get_tabpage(sidebar.win)
    end

    local buf_name = ""
    if vim.api.nvim_buf_is_valid(sidebar.buf) then
        buf_name = " (" .. vim.api.nvim_buf_get_name(sidebar.buf) .. ")"
    end

    local source_win_buf = -1
    local source_win_buf_name = ""
    if vim.api.nvim_win_is_valid(sidebar.source_win) then
        source_win_buf = vim.api.nvim_win_get_buf(sidebar.source_win)
        source_win_buf_name = vim.api.nvim_buf_get_name(source_win_buf)
        if source_win_buf_name == "" then
            source_win_buf_name = " <scratch buffer>"
        else
            source_win_buf_name = " (" .. source_win_buf_name .. ")"
        end
    end

    local symbols_count_string = " (no symbols)"
    local symbols_count = #sidebar.root_symbol.children
    if symbols_count > 0 then
        symbols_count_string = " (" .. tostring(symbols_count) .. "+ symbols)"
    end

    return table.concat(
        {
            "Sidebar(",
            "  deleted: " .. tostring(sidebar.deleted),
            "  tab: " .. tostring(tab),
            "  win: " .. tostring(sidebar.win),
            "  buf: " .. tostring(sidebar.buf) .. buf_name,
            "  source_win: " .. tostring(sidebar.source_win),
            "  source_win_buf: " .. tostring(source_win_buf) .. source_win_buf_name,
            "  root_symbol: ..." .. symbols_count_string,
            ")",
        },
        "\n"
    )
end

---@return Sidebar
local function sidebar_new_obj()
    return {
        deleted = false,
        win = -1,
        buf = -1,
        source_win = -1,
        visible = false,
        root_symbol = symbol_root()
    }
end

---@param buf integer
---@param value boolean
local function buf_modifiable(buf, value)
    vim.api.nvim_set_option_value("modifiable", value, { buf = buf })
end

---@param buf integer
---@param lines string[]
local function buf_set_content(buf, lines)
    buf_modifiable(buf, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    buf_modifiable(buf, false)
end

---@param win integer
---@param name string
---@param value any
local function win_set_option(win, name, value)
    vim.api.nvim_set_option_value(name, value, { win = win })
end

---@param sidebar Sidebar
---@return integer
local function sidebar_tab(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.win) then
        return vim.api.nvim_win_get_tabpage(sidebar.win)
    end
    return -1
end

local function sidebar_open(sidebar)
    if sidebar.visible then return end

    local original_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(sidebar.source_win)
    vim.cmd("vs")
    vim.cmd("vertical resize " .. 40)
    sidebar.win = vim.api.nvim_get_current_win()

    vim.api.nvim_set_current_win(original_win)

    vim.api.nvim_win_set_buf(sidebar.win, sidebar.buf)

    win_set_option(sidebar.win, "number", false)
    win_set_option(sidebar.win, "relativenumber", false)
    win_set_option(sidebar.win, "signcolumn", "no")

    sidebar.visible = true
end

local function sidebar_close(sidebar)
    if not sidebar.visible then return end
    vim.api.nvim_win_close(sidebar.win, true)
    sidebar.win = -1
    sidebar.visible = false
end

---@param sidebar Sidebar
local function sidebar_destroy(sidebar)
    sidebar_close(sidebar)
    if vim.api.nvim_buf_is_valid(sidebar.buf) then
        vim.api.nvim_buf_delete(sidebar.buf, { force = true })
        sidebar.buf = -1
    end
    sidebar.source_win = -1
    sidebar.deleted = true
end

---@param num integer
---@param sidebar Sidebar
local function sidebar_new(sidebar, num)
    sidebar.deleted = false
    sidebar.source_win = vim.api.nvim_get_current_win()

    sidebar.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(sidebar.buf, "Symbols [" .. tostring(num) .. "]")
    vim.api.nvim_buf_set_option(sidebar.buf, "filetype", "SymbolsSidebar")

    sidebar_open(sidebar)
end

---@param sidebar Sidebar
---@param providers Provider[]
local function sidebar_refresh(sidebar, providers)
    local buf = sidebar_source_win_buf(sidebar)
    for _, provider in ipairs(providers) do
        local cache = {}
        if provider.supports(cache, buf) then
            provider.async_get_symbols(
                cache,
                buf,
                function(symbol)
                    sidebar.root_symbol = symbol
                    local lines = {}
                    for _, sym in ipairs(sidebar.root_symbol.children) do
                        local line = " [" .. lsp.SymbolKindString[sym.kind] .. "] " .. sym.name
                        table.insert(lines, line)
                    end
                    buf_set_content(sidebar.buf, lines)
                end,
                function() print(provider.name .. " failed.") end
            )
        end
    end
end

local function create_command(cmds, name, cmd, opts)
    cmds[name] = true
    vim.api.nvim_create_user_command(name, cmd, opts)
end

local function remove_commands(cmds)
    for cmd, _ in pairs(cmds) do
        vim.api.nvim_del_user_command(cmd)
    end
end

local function show_debug_in_current_window(sidebars)
    local buf = vim.api.nvim_create_buf(false, true)

    local lines = {}
    for _, sidebar in ipairs(sidebars) do
        local new_lines = vim.split(sidebar_str(sidebar), "\n")
        vim.list_extend(lines, new_lines)
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)

    buf_modifiable(buf, false)
end

---@param sidebars Sidebar[]
---@param win integer
---@return Sidebar?
local function find_sidebar_for_win(sidebars, win)
    for _, sidebar in ipairs(sidebars) do
        if sidebar.source_win == win or sidebar.win == win then
            return sidebar
        end
    end
    return nil
end

---@param sidebars Sidebar[]
---@return Sidebar?, integer
local function find_sidebar_for_reuse(sidebars)
    for num, sidebar in ipairs(sidebars) do
        if sidebar.deleted then
            return sidebar, num
        end
    end
    return nil, -1
end

---@class LspCache
---@field client any

---@param cache table
---@param buf integer
---@return boolean
local function supports_lsp(cache, buf)
    local clients = vim.lsp.get_clients({bufnr = buf, method = "documentSymbolProvider" })
    cache.client = clients[1]
    return #clients > 0
end

---@param symbol any
---@param parent Symbol?
local function rec_tidy_lsp_symbol(symbol, parent)
    symbol.parent = parent
    symbol.detail = symbol.detail or ""
    symbol.children = symbol.children or {}
    for _, child in ipairs(symbol.children) do
        rec_tidy_lsp_symbol(child, symbol)
    end
end

---@param cache LspCache
---@param buf integer
---@param refresh_symbols RefreshSymbolsFun
local function async_get_symbols_lsp(cache, buf, refresh_symbols, on_fail)
    local function handler(err, result, ctx, config)
        if err ~= nil then
            on_fail()
            return
        end
        local root = symbol_root()
        root.children = result
        rec_tidy_lsp_symbol(root, nil)
        refresh_symbols(root)
    end

    local params = { textDocument = vim.lsp.util.make_text_document_params(buf), }
    local ok, request_id = cache.client.request("textDocument/documentSymbol", params, handler)
    if not ok then on_fail() end

    LSP_REQUEST_TIMEOUT_MS = 200
    vim.defer_fn(
        function()
            cache.client.cancel_request(request_id)
            on_fail()
        end,
        LSP_REQUEST_TIMEOUT_MS
    )
end

---@param sidebars Sidebar[]
local function on_win_close(sidebars, win)
    for _, sidebar in ipairs(sidebars) do
        if sidebar.source_win == win then
            sidebar_destroy(sidebar)
        elseif sidebar.win == win then
            sidebar_close(sidebar)
        end
    end
end

function M.setup()
    local cmds = {}

    ---@type Sidebar[]
    local sidebars = {}

    ---@type Provider[]
    local providers = {
        {
            name = "lsp",
            supports = supports_lsp,
            async_get_symbols = async_get_symbols_lsp,
        },
    }

    local function on_reload()
        remove_commands(cmds)

        for _, sidebar in ipairs(sidebars) do
            sidebar_destroy(sidebar)
        end
    end

    if dev.env() == "dev" then
        dev.setup(on_reload)

        create_command(
            cmds,
            "SymbolsDebug",
            function() show_debug_in_current_window(sidebars) end,
            {}
        )

        vim.keymap.set("n", ",d", ":SymbolsDebug<CR>")
        vim.keymap.set("n", ",s", ":Symbols<CR>")
    end

    create_command(
        cmds,
        "Symbols",
        function()
            local win = vim.api.nvim_get_current_win()
            local sidebar = find_sidebar_for_win(sidebars, win)
            if sidebar == nil then
                local num
                sidebar, num = find_sidebar_for_reuse(sidebars)
                if sidebar == nil then
                    sidebar = sidebar_new_obj()
                    table.insert(sidebars, sidebar)
                    num = #sidebars
                end
                sidebar_new(sidebar, num)
                sidebar_refresh(sidebar, providers)
            else
                sidebar_open(sidebar)
            end
        end,
        { desc = "" }
    )

    create_command(
        cmds,
        "SymbolsClose",
        function()
            local win = vim.api.nvim_get_current_win()
            local sidebar = find_sidebar_for_win(sidebars, win)
            if sidebar ~= nil then
                sidebar_close(sidebar)
            end
        end,
        { desc = "" }
    )

    vim.api.nvim_create_autocmd(
        "WinClosed",
        {
            pattern="*",
            callback=function(t)
                local win = tonumber(t.match, 10)
                on_win_close(sidebars, win)
            end
        }
    )

end

return M
