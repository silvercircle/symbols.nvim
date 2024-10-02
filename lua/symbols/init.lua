local cfg = require("symbols.config")

local M = {}

---@class Pos
---@field line integer
---@field character integer

---@class Range
---@field start Pos
---@field end Pos

---@class Symbol
---@field kind string
---@field name string
---@field detail string
---@field level integer
---@field parent Symbol | nil
---@field children Symbol[]
---@field range Range
---@field selectionRange Range
---@field folded boolean

---@return Symbol
local function symbol_root()
    return {
        kind = "root",
        name = "<root>",
        detail = "",
        level = 0,
        parent = nil,
        children = {},
        range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = -1, character = -1 }
        },
        selectionRange = {
            start = { line = 0, character = 0 },
            ["end"] = { line = -1, character = -1 }
        },
        folded = false,
    }
end

---@alias RefreshSymbolsFun fun(symbols: Symbol)
---@alias KindToHlGroupFun fun(kind: string): string
---@alias KindToDisplayFun fun(kind: string): string

---@class Provider
---@field name string
---@field init (fun(cache: table, config: table)) | nil
---@field supports fun(cache: table, buf: integer): boolean
---@field async_get_symbols (fun(cache: any, buf: integer, refresh_symbols: RefreshSymbolsFun, on_fail: fun())) | nil
---@field get_symbols (fun(cache: any, buf: integer): boolean, Symbol?) | nil

---@enum LspSymbolKind
local LspSymbolKind = {
	File = 1,
	Module = 2,
	Namespace = 3,
	Package = 4,
	Class = 5,
	Method = 6,
	Property = 7,
	Field = 8,
	Constructor = 9,
	Enum = 10,
	Interface = 11,
	Function = 12,
	Variable = 13,
	Constant = 14,
	String = 15,
	Number = 16,
	Boolean = 17,
	Array = 18,
	Object = 19,
	Key = 20,
	Null = 21,
	EnumMember = 22,
	Struct = 23,
	Event = 24,
	Operator = 25,
	TypeParameter = 26,
}

---@type table<LspSymbolKind, string>
local LspSymbolKindString = {}
for k, v in pairs(LspSymbolKind) do
    LspSymbolKindString[v] = k
end


---@param symbol any
---@param parent Symbol?
---@param level integer
local function rec_tidy_lsp_symbol(symbol, parent, level)
    symbol.parent = parent
    symbol.detail = symbol.detail or ""
    symbol.children = symbol.children or {}
    symbol.kind = LspSymbolKindString[symbol.kind]
    symbol.folded = true
    symbol.level = level
    for _, child in ipairs(symbol.children) do
        rec_tidy_lsp_symbol(child, symbol, level + 1)
    end
end

---@type Provider
local LspProvider = {
    name = "lsp",
    init = function(cache, config)
        cache.request_timeout = config.timeout_ms
    end,
    supports = function(cache, buf)
        local clients = vim.lsp.get_clients({ bufnr = buf, method = "documentSymbolProvider" })
        cache.client = clients[1]
        return #clients > 0
    end,
    async_get_symbols = function(cache, buf, refresh_symbols, on_fail)
        local got_symbols = false

        local function handler(err, result, _, _)
            got_symbols = true
            if err ~= nil then
                on_fail()
                return
            end
            local root = symbol_root()
            root.children = result
            rec_tidy_lsp_symbol(root, nil, 0)
            root.folded = false
            refresh_symbols(root)
        end

        local params = { textDocument = vim.lsp.util.make_text_document_params(buf), }
        local ok, request_id = cache.client.request("textDocument/documentSymbol", params, handler)
        if not ok then on_fail() end

        vim.defer_fn(
            function()
                if got_symbols then return end
                cache.client.cancel_request(request_id)
                on_fail()
            end,
            cache.request_timeout
        )
    end,
    get_symbols = nil,
}

---@type Provider
local VimdocProvider = {
    name = "vimdoc",
    supports = function(cache, buf)
        local val = vim.api.nvim_get_option_value("ft", { buf = buf })
        if val ~= 'help' then
            return false
        end
        local ok, parser = pcall(vim.treesitter.get_parser, buf, "vimdoc")
        if not ok then
            return false
        end
        cache.parser = parser
        return true
    end,
    get_symbols = function(cache, _)
        local rootNode = cache.parser:parse()[1]:root()

        local queryString = [[
            [
                (h1 (heading) @h1)
                (h2 (heading) @h2)
                (h3 (heading) @h3)
                (tag text: (word) @tag)
            ]
        ]]
        local query = vim.treesitter.query.parse("vimdoc", queryString)

        local captureLevelMap = { h1 = 1, h2 = 2, h3 = 3, tag = 4 }
        local kindMap = { h1 = "H1", h2 = "H2", h3 = "H3", tag = "Tag" }

        local root = symbol_root()
        local current = root

        local function update_range_end(node, rangeEnd)
            if node.range ~= nil and node.level <= 3 then
                node.range['end'] = { character = node.range['end'], line = rangeEnd }
                node.selectionRange = node.range
            end
        end

        for id, node, _, _ in query:iter_captures(rootNode, 0) do
            local capture = query.captures[id]
            local captureLevel = captureLevelMap[capture]

            local row1, col1, row2, col2 = node:range()
            local captureString = vim.api.nvim_buf_get_text(0, row1, col1, row2, col2, {})[1]

            local prevHeadingsRangeEnd = row1 - 1
            local rangeStart = row1
            if captureLevel <= 2 then
                prevHeadingsRangeEnd = prevHeadingsRangeEnd - 1
                rangeStart = rangeStart - 1
            end

            while captureLevel <= current.level do
                update_range_end(current, prevHeadingsRangeEnd)
                current = current.parent
                assert(current ~= nil)
            end

            ---@type Symbol
            local new = {
                kind = kindMap[capture],
                name = captureString,
                detail = "",
                selectionRange = {
                    start = { character = col1, line = rangeStart },
                    ['end'] = { character = col2, line = row2 - 1 },
                },
                range = {
                    start = { character = col1, line = rangeStart },
                    ['end'] = { character = col2, line = row2 - 1 },
                },
                children = {},

                parent = current,
                level = captureLevel,
                folded = true,
            }

            table.insert(current.children, new)
            current = new
        end

        local lineCount = vim.api.nvim_buf_line_count(0)
        while current.level > 0 do
            update_range_end(current, lineCount)
            current = current.parent
            assert(current ~= nil)
        end

        return true, root
    end,
    async_get_symbols = nil,
}

---@class Sidebar
---@field deleted boolean
---@field win integer
---@field buf integer
---@field source_win integer
---@field visible boolean
---@field buf_symbols table<integer, Symbol>
---@field lines table<Symbol, integer>
---@field curr_provider Provider | nil
---@field symbol_display_config table<string, SymbolDisplayConfig>
---@field preview_win integer
---@field details_win integer
---@field char_config CharConfig
---@field show_details boolean
---@field show_details_pop_up boolean
---@field keymaps KeymapsConfig

---@return Sidebar
local function sidebar_new_obj()
    return {
        deleted = false,
        win = -1,
        buf = -1,
        source_win = -1,
        visible = false,
        buf_symbols = vim.defaulttable(symbol_root),
        lines = {},
        curr_provider = nil,
        symbol_display_config = {},
        preview_win = -1,
        details_win = -1,
        char_config = cfg.default.sidebar.chars,
        show_details = false,
        show_details_pop_up = false,
        keymaps = cfg.default.sidebar.keymaps,
    }
end

---@param sidebar Sidebar
---@return integer
local function sidebar_source_win_buf(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.source_win) then
        return vim.api.nvim_win_get_buf(sidebar.source_win)
    end
    return -1
end

---@param sidebar Sidebar
---@return Symbol
local function sidebar_current_symbols(sidebar)
    local source_buf = sidebar_source_win_buf(sidebar)
    assert(source_buf ~= -1)
    return sidebar.buf_symbols[source_buf]
end

---@parm sidebar Sidebar
---@param new_symbol Symbol
local function sidebar_replace_current_symbols(sidebar, new_symbol)
    local source_buf = sidebar_source_win_buf(sidebar)
    assert(source_buf ~= -1)
    sidebar.buf_symbols[source_buf] = new_symbol
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


    local lines = {
        "Sidebar(",
        "  deleted: " .. tostring(sidebar.deleted),
        "  visible: " .. tostring(sidebar.visible),
        "  tab: " .. tostring(tab),
        "  win: " .. tostring(sidebar.win),
        "  buf: " .. tostring(sidebar.buf) .. buf_name,
        "  source_win: " .. tostring(sidebar.source_win),
        "  source_win_buf: " .. tostring(source_win_buf) .. source_win_buf_name,
        "  buf_symbols: {",
    }

    for buf, root_symbol in pairs(sidebar.buf_symbols) do
        local _buf_name = vim.api.nvim_buf_get_name(buf)

        local symbols_count_string = " (no symbols)"
        local symbols_count = #root_symbol.children
        if symbols_count > 0 then
            symbols_count_string = " (" .. tostring(symbols_count) .. "+ symbols)"
        end

        local line = "    \"" .. buf .. "\" (" .. _buf_name .. ") " .. symbols_count_string
        table.insert(lines, line)
    end

    table.insert(lines, "  }")
    table.insert(lines, ")")
    return table.concat(lines, "\n")
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
    win_set_option(sidebar.win, "cursorline", true)
    win_set_option(sidebar.win, "winfixwidth", true)

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

---@param sidebar Sidebar
---@return Symbol
local function sidebar_current_symbol(sidebar)
    assert(vim.api.nvim_win_is_valid(sidebar.win))

    ---@param symbol Symbol
    ---@param num integer
    ---@return Symbol, integer
    local function _find_symbol(symbol, num)
        if num == 0 then return symbol, 0 end
        if symbol.folded then return symbol, num end
        for _, sym in ipairs(symbol.children) do
            local s
            s, num = _find_symbol(sym, num - 1)
            if num <= 0 then return s, 0 end
        end
        return symbol, num
    end

    local symbols = sidebar_current_symbols(sidebar)
    local line = vim.api.nvim_win_get_cursor(sidebar.win)[1]
    local s, _ = _find_symbol(symbols, line)
    return s
end

local SIDEBAR_HL_NS = vim.api.nvim_create_namespace("SymbolsSidebarHl")
local SIDEBAR_EXT_NS = vim.api.nvim_create_namespace("SymbolsSidebarExt")

---@class Highlight
---@field group string
---@field line integer  -- one-indexed
---@field col_start integer
---@field col_end integer

---@param buf integer
---@param hl Highlight
local function highlight_apply(buf, hl)
    vim.api.nvim_buf_add_highlight(
        buf, SIDEBAR_HL_NS, hl.group, hl.line-1, hl.col_start, hl.col_end
    )
end

---@param root_symbol Symbol
---@param symbol_display_config table<string, SymbolDisplayConfig>
---@param chars CharConfig
---@return string[], table<Symbol, integer>, Highlight[], string[]
local function process_symbols(root_symbol, symbol_display_config, chars)
    ---@type string[]
    local details = {}
    local symbol_to_line = {}

    ---@param symbol Symbol
    ---@param line integer
    local function get_symbol_to_line(symbol, line)
        if symbol.folded then return line end
        for _, sym in ipairs(symbol.children) do
            symbol_to_line[sym] = line
            table.insert(details, sym.detail)
            line = get_symbol_to_line(sym, line + 1)
        end
        return line
    end
    get_symbol_to_line(root_symbol, 1)

    local buf_lines = {}
    local highlights = {}

    ---@param symbol Symbol
    ---@param indent string
    ---@param line_nr integer
    ---@return integer
    local function get_buf_lines_and_highlights(symbol, indent, line_nr)
        if symbol.folded then return line_nr end
        for _, sym in ipairs(symbol.children) do
            local prefix
            if #sym.children == 0 then
                prefix = "  "
            elseif sym.folded then
                prefix = chars.folded .. " "
            else
                prefix = chars.unfolded .. " "
            end
            local kind_display = symbol_display_config[sym.kind].kind or sym.kind
            local line = indent .. prefix .. (kind_display ~= "" and (kind_display .. " ") or "") .. sym.name
            table.insert(buf_lines, line)
            ---@type Highlight
            local hl = {
                group = symbol_display_config[sym.kind].highlight,
                line = line_nr,
                col_start = #indent + #prefix,
                col_end = #indent + #prefix + #kind_display
            }
            table.insert(highlights, hl)
            line_nr = get_buf_lines_and_highlights(sym, indent .. "  ", line_nr + 1)
        end
        return line_nr
    end
    get_buf_lines_and_highlights(root_symbol, "", 1)

    return  buf_lines, symbol_to_line, highlights, details
end

---@param sidebar Sidebar
---@param symbol Symbol
local function move_cursor_to_symbol(sidebar, symbol)
    assert(vim.api.nvim_win_is_valid(sidebar.win))
    local line = sidebar.lines[symbol]
    vim.api.nvim_win_set_cursor(sidebar.win, { line, 0 })
end

---@param sidebar Sidebar
local function sidebar_refresh_view(sidebar)
    local provider = sidebar.curr_provider
    assert(provider ~= nil)

    local buf_lines, symbol_to_line, highlights, details = process_symbols(
        sidebar_current_symbols(sidebar),
        sidebar.symbol_display_config,
        sidebar.char_config
    )
    sidebar.lines = symbol_to_line
    buf_set_content(sidebar.buf, buf_lines)
    for _, hl in ipairs(highlights) do
        highlight_apply(sidebar.buf, hl)
    end

    if sidebar.show_details then
        for line, detail in ipairs(details) do
            vim.api.nvim_buf_set_extmark(
                sidebar.buf, SIDEBAR_EXT_NS, line-1, -1,
                {
                    virt_text = { { detail, "Comment" } },
                    virt_text_pos = "eol",
                    hl_mode = 'combine',
                }
            )
        end
    end
end

---@param sidebar Sidebar
---@param providers Provider[]
---@param config Config
local function sidebar_refresh_symbols(sidebar, providers, config)

    ---@return Symbol?
    local function _find_symbol_with_name(symbol, name)
        for _, sym in ipairs(symbol.children) do
            if sym.name == name then return sym end
        end
        return nil
    end

    ---@param old_symbol Symbol
    ---@param new_symbol Symbol
    local function preserve_folds(old_symbol, new_symbol)
        if old_symbol.level > 0 and old_symbol.folded then return end
        for _, new_sym in ipairs(new_symbol.children) do
            local old_sym = _find_symbol_with_name(old_symbol, new_sym.name)
            if old_sym ~= nil then
                new_sym.folded = old_sym.folded
                preserve_folds(old_sym, new_sym)
            end
        end
    end

    ---@param new_root Symbol
    local function _refresh_sidebar(new_root)
        local current_root = sidebar_current_symbols(sidebar)
        preserve_folds(current_root, new_root)
        sidebar_replace_current_symbols(sidebar, new_root)
        sidebar_refresh_view(sidebar)
    end

    ---@param provider Provider
    local function on_fail(provider)
        return function()
            vim.notify(provider.name .. " failed.", vim.log.levels.ERROR)
        end
    end

    local buf = sidebar_source_win_buf(sidebar)
    for _, provider in ipairs(providers) do
        local cache = {}
        if provider.init ~= nil then
            provider.init(cache, config[provider.name])
        end
        if provider.supports(cache, buf) then
            sidebar.curr_provider = provider
            local ft = vim.bo[buf].filetype
            sidebar.symbol_display_config = cfg.symbols_display_config(config, provider.name, ft)
            if provider.async_get_symbols ~= nil then
                provider.async_get_symbols(
                    cache,
                    buf,
                    _refresh_sidebar,
                    on_fail(provider)
                )
            else
                local ok, symbol = provider.get_symbols(cache, buf)
                if not ok then
                    on_fail(provider)()
                else
                    assert(symbol ~= nil)
                    _refresh_sidebar(symbol)
                end
            end
            return
        end
    end
end

---@param win integer
---@param duration_ms integer
local function flash_highlight(win, duration_ms, lines)
    local bufnr = vim.api.nvim_win_get_buf(win)
    local line = vim.api.nvim_win_get_cursor(win)[1]
    local ns = vim.api.nvim_create_namespace("")
    for i = 1, lines do
        vim.api.nvim_buf_add_highlight(bufnr, ns, "Visual", line - 1 + i - 1, 0, -1)
    end
    local remove_highlight = function()
        pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
    end
    vim.defer_fn(remove_highlight, duration_ms)
end

---@param symbol Symbol
---@param value boolean
local function symbol_change_folded_rec(symbol, value)
    symbol.folded = value
    for _, sym in ipairs(symbol.children) do
        symbol_change_folded_rec(sym, value)
    end
end

---@param sidebar Sidebar
local function sidebar_goto_symbol(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    vim.api.nvim_set_current_win(sidebar.source_win)
    vim.api.nvim_win_set_cursor(
        sidebar.source_win,
        { symbol.selectionRange.start.line + 1, symbol.selectionRange.start.character }
    )
    vim.fn.win_execute(sidebar.source_win, 'normal! zt')
    local r = symbol.range
    flash_highlight(sidebar.source_win, 400, r["end"].line - r.start.line + 1)
end

---@param sidebar Sidebar
---@return integer win
local function _open_preview(sidebar)
    local source_buf = sidebar_source_win_buf(sidebar)
    local cursor = vim.api.nvim_win_get_cursor(sidebar.win)
    local symbol = sidebar_current_symbol(sidebar)
    local opts = {
        relative = "cursor",
        anchor = "NE",
        width = 80,
        height = 6 + (symbol.range["end"].line - symbol.range.start.line) + 1,
        row = 0,
        col = -cursor[2]-1,
        border = "single",
        style = "minimal",
    }
    local preview_win = vim.api.nvim_open_win(source_buf, false, opts)
    vim.api.nvim_win_set_cursor(
        preview_win, { symbol.selectionRange.start.line+1, symbol.selectionRange.start.character }
    )
    vim.fn.win_execute(preview_win, "normal! zt")
    flash_highlight(preview_win, 200, 1)
    return preview_win
end

---@param sidebar Sidebar
local function sidebar_preview(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.preview_win) then
        vim.api.nvim_set_current_win(sidebar.preview_win)
    else
        sidebar.preview_win = _open_preview(sidebar)
    end
end

---@param sidebar Sidebar
local function sidebar_show_details(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.details_win) then
        return
    end

    local details_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "delete", { buf = details_buf })
    local symbol = sidebar_current_symbol(sidebar)
    buf_set_content(details_buf, vim.split(symbol.detail, "\n"))
    local line_count = vim.api.nvim_buf_line_count(details_buf)
    local opts = {
        relative = "cursor",
        anchor = "NW",
        width = 80,
        height = line_count,
        row = 0,
        col = 0,
        border = "single",
        style = "minimal",
    }
    sidebar.details_win = vim.api.nvim_open_win(details_buf, false, opts)
    vim.wo[sidebar.details_win].wrap = true
end

---@param sidebar Sidebar
local function sidebar_unfold(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    symbol.folded = false
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold(sidebar)
        local symbol = sidebar_current_symbol(sidebar)
        if symbol.level > 1 and (symbol.folded or #symbol.children == 0) then
            symbol = symbol.parent
            assert(symbol ~= nil)
        end
        symbol.folded = true
        sidebar_refresh_view(sidebar)
        move_cursor_to_symbol(sidebar, symbol)
    end

---@param sidebar Sidebar
local function sidebar_unfold_recursively(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    symbol_change_folded_rec(symbol, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_recursively(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    while(symbol.level > 1) do
        symbol = symbol.parent
        assert(symbol ~= nil)
    end
    symbol_change_folded_rec(symbol, true)
    sidebar_refresh_view(sidebar)
    move_cursor_to_symbol(sidebar, symbol)
end


local function _change_fold_at_level(symbol, level, value)
    if symbol.level == level then symbol.folded = value end
    if symbol.level >= level then return end
    for _, sym in ipairs(symbol.children) do
        _change_fold_at_level(sym, level, value)
    end
end

---@param sidebar Sidebar
local function sidebar_unfold_one_level(sidebar)

    ---@param symbol Symbol
    ---@return integer
    local function find_level_to_unfold(symbol)
        local MAX_LEVEL = 100000

        if symbol.level ~= 0 and symbol.folded then
            return symbol.level
        end

        local min_level = MAX_LEVEL
        for _, sym in ipairs(symbol.children) do
            min_level = math.min(min_level, find_level_to_unfold(sym))
        end

        return min_level
    end

    local symbols = sidebar_current_symbols(sidebar)
    local level = find_level_to_unfold(symbols)
    _change_fold_at_level(symbols, level, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_one_level(sidebar)

    ---@param symbol Symbol
    ---@return integer
    local function find_level_to_fold(symbol)
        local max_level = (symbol.folded and 1) or symbol.level
        for _, sym in ipairs(symbol.children) do
            max_level = math.max(max_level, find_level_to_fold(sym))
        end
        return max_level
    end

    local symbols = sidebar_current_symbols(sidebar)
    local level = find_level_to_fold(symbols)
    _change_fold_at_level(symbols, level, true)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_unfold_all(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    symbol_change_folded_rec(symbols, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_all(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    symbol_change_folded_rec(symbols, true)
    symbols.folded = false
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_toggle_fold(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    if #symbol.children == 0 then return end
    symbol.folded = not symbol.folded
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_toggle_details(sidebar)
    sidebar.show_details = not sidebar.show_details
    sidebar_refresh_view(sidebar)
end

local help_options_order = {
    "goto-symbol",
    "preview",
    "show-details",
    "toggle-fold",
    "unfold",
    "fold",
    "unfold-recursively",
    "fold-recursively",
    "unfold-one-level",
    "fold-one-level",
    "unfold-all",
    "fold-all",
    "toggle-details",
    "help",
    "close",
}
---@type table<integer, SidebarAction>
local action_order = {}
for num, action in ipairs(help_options_order) do
    action_order[action] = num
end

---@param sidebar Sidebar
local function sidebar_help(sidebar)
    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "delete", { buf = help_buf })
    vim.api.nvim_buf_set_option(sidebar.buf, "filetype", "SymbolsHelp")

    local keymaps = {}
    for i=1,#help_options_order do keymaps[i] = {} end

    for key, action in pairs(sidebar.keymaps) do
        local ord = action_order[action]
        table.insert(keymaps[ord], key)
    end

    local keys_str = {}
    local max_key_len = 0
    for ord, keys in ipairs(keymaps) do
        keys_str[ord] = vim.iter(keys):join(" / ")
        max_key_len = math.max(max_key_len, #keys_str[ord])
    end

    local lines = {"", "Keymaps", ""}

    for num=1,#help_options_order do
        local padding = string.rep(" ", max_key_len - #keys_str[num] + 2)
        table.insert(lines, "  " .. keys_str[num] .. padding .. help_options_order[num])
    end

    local max_width = 0
    for line_no=1,#lines do
        lines[line_no] = " " .. lines[line_no]
        max_width = math.max(max_width, #lines[line_no])
    end

    buf_set_content(help_buf, lines)
    buf_modifiable(help_buf, false)

    local width = max_width + 1
    local height = #lines + 1

    local ui = vim.api.nvim_list_uis()[1]
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)

    local opts = {
        title = "Symbols Help",
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "single",
        style = "minimal",
    }
    local help_win = vim.api.nvim_open_win(help_buf, false, opts)
    win_set_option(help_win, "cursorline", true)
    vim.api.nvim_set_current_win(help_win)
    vim.api.nvim_win_set_cursor(help_win, { 2, 0 })

    vim.keymap.set(
        "n", "q",
        function() vim.api.nvim_win_close(help_win, true) end,
        { buffer = help_buf }
    )

    vim.api.nvim_create_autocmd(
        "BufLeave",
        {
            callback = function() vim.api.nvim_win_close(help_win, true) end,
            buffer = help_buf,
        }
    )
end

---@type table<SidebarAction, fun(sidebar: Sidebar)>
local sidebar_actions = {
    ["goto-symbol"] = sidebar_goto_symbol,
    ["preview"] = sidebar_preview,
    ["show-details"] = sidebar_show_details,

    ["unfold"] = sidebar_unfold,
    ["unfold-recursively"] = sidebar_unfold_recursively,
    ["unfold-one-level"] = sidebar_unfold_one_level,
    ["unfold-all"] = sidebar_unfold_all,

    ["fold"] = sidebar_fold,
    ["fold-recursively"] = sidebar_fold_recursively,
    ["fold-one-level"] = sidebar_fold_one_level,
    ["fold-all"] = sidebar_fold_all,

    ["toggle-fold"] = sidebar_toggle_fold,
    ["toggle-details"] = sidebar_toggle_details,

    ["help"] = sidebar_help,
    ["close"] = sidebar_close,
}

---@param sidebar Sidebar
local function sidebar_on_cursor_move(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.preview_win) then
        vim.api.nvim_win_close(sidebar.preview_win, true)
        sidebar.preview_win = -1
    end
    if vim.api.nvim_win_is_valid(sidebar.details_win) then
        vim.api.nvim_win_close(sidebar.details_win, true)
        sidebar.details_win = -1
    end
end

---@param sidebar Sidebar
---@param num integer
---@param config SidebarConfig
local function sidebar_new(sidebar, num, config)
    sidebar.deleted = false
    sidebar.source_win = vim.api.nvim_get_current_win()

    sidebar.show_details = config.show_details
    sidebar.char_config = config.chars
    sidebar.keymaps = config.keymaps

    sidebar.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(sidebar.buf, "Symbols [" .. tostring(num) .. "]")
    vim.api.nvim_buf_set_option(sidebar.buf, "filetype", "SymbolsSidebar")

    for key, action in pairs(config.keymaps) do
        vim.keymap.set(
            "n", key,
            function() sidebar_actions[action](sidebar) end,
            { buffer = sidebar.buf }
        )
    end

    vim.api.nvim_create_autocmd(
        { "CursorMoved" },
        {
            callback = function() sidebar_on_cursor_move(sidebar) end,
            buffer = sidebar.buf,
        }
    )
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
        local new_lines = vim.split(sidebar_str(sidebar), "\n") vim.list_extend(lines, new_lines) end

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
---@param source_buf integer
---@return Sidebar?
local function find_sidebar_by_source_buf(sidebars, source_buf)
    for _, sidebar in ipairs(sidebars) do
        if sidebar_source_win_buf(sidebar) == source_buf then
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

---@param cmds string[]
local function setup_dev(cmds, autocmd_group, sidebars, config)
    ---@param pkg string
    local function unload_package(pkg)
        local esc_pkg = pkg:gsub("([^%w])", "%%%1")
        for module_name, _ in pairs(package.loaded) do
            if string.find(module_name, esc_pkg) then
                package.loaded[module_name] = nil
            end
        end
    end

    local function reload()
        remove_commands(cmds)
        vim.api.nvim_del_augroup_by_id(autocmd_group)
        for _, sidebar in ipairs(sidebars) do
            sidebar_destroy(sidebar)
        end

        unload_package("symbols")
        require("symbols").setup(config)

        vim.notify("symbols.nvim reloaded", vim.log.levels.INFO)
    end

    local function debug()
        show_debug_in_current_window(sidebars)
    end

    local function show_config()
        local buf = vim.api.nvim_create_buf(false, true)
        local text = vim.inspect(config)
        local lines = vim.split(text, "\n")
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
        buf_modifiable(buf, false)
    end

    ---@type table<DevAction, fun()>
    local dev_action_to_fun = {
        reload = reload,
        debug = debug,
        ["show-config"] = show_config
    }

    for key, action in pairs(config.dev.keymaps) do
        vim.keymap.set("n", key, dev_action_to_fun[action])
    end
end

function M.setup(config)
    local _config = cfg.prepare_config(config)

    local cmds = {}

    ---@type Sidebar[]
    local sidebars = {}

    ---@type Provider[]
    local providers = {
        LspProvider,
        VimdocProvider,
    }

    local autocmd_group = vim.api.nvim_create_augroup("Symbols", { clear = true })

    if _config.dev.enabled then
        setup_dev(cmds, autocmd_group, sidebars, _config)
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
                sidebar_new(sidebar, num, _config.sidebar)
            end
            sidebar_open(sidebar)
            sidebar_refresh_symbols(sidebar, providers, _config)
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
            group = autocmd_group,
            pattern = "*",
            callback = function(t)
                local win = tonumber(t.match, 10)
                on_win_close(sidebars, win)
            end
        }
    )

    vim.api.nvim_create_autocmd(
        { "LspAttach", "BufWinEnter", "BufWritePost", "FileChangedShellPost" },
        {
            group = autocmd_group,
            pattern = "*",
            callback = function(t)
                local buf = t.buf
                local sidebar = find_sidebar_by_source_buf(sidebars, buf)
                if sidebar == nil then return end
                sidebar_refresh_symbols(sidebar, providers, _config)
            end
        }
    )
end

return M
