local lsp = require("symbols.lsp")
local cfg = require("symbols.cfg")

local CHAR_FOLDED = ""
local CHAR_UNFOLDED = ""

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
        range = { start = { line = 0, character = 0 }, ["end"] = { line = -1, character = -1 } },
        selectionRange = { start = { line = 0, character = 0 }, ["end"] = { line = -1, character = -1 } },
        folded = false,
    }
end

---@alias RefreshSymbolsFun fun(symbols: Symbol)
---@alias KindToHlGroupFun fun(kind: string): string
---@alias KindToDisplayFun fun(kind: string): string

---@class Provider
---@field name string
---@field kind_to_hl_group KindToHlGroupFun
---@field kind_to_display KindToDisplayFun
---@field supports fun(cache: table, buf: integer): boolean
---@field async_get_symbols (fun(cache: any, buf: integer, refresh_symbols: RefreshSymbolsFun, on_fail: fun())) | nil
---@field get_symbols (fun(cache: any, buf: integer): boolean, Symbol?) | nil

---@param symbol any
---@param parent Symbol?
---@param level integer
local function rec_tidy_lsp_symbol(symbol, parent, level)
    symbol.parent = parent
    symbol.detail = symbol.detail or ""
    symbol.children = symbol.children or {}
    symbol.kind = lsp.SymbolKindString[symbol.kind]
    symbol.folded = true
    symbol.level = level
    for _, child in ipairs(symbol.children) do
        rec_tidy_lsp_symbol(child, symbol, level + 1)
    end
end

---@type Provider
local LspProvider = {
    name = "lsp",
    kind_to_hl_group = function(kind)
        ---@type table<string, string>
        local map  = {
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
            Component = "Function",
            Fragment = "Constant",
        }
        return map[kind]
    end,
    kind_to_display = function(kind) return kind end,
    supports = function(cache, buf)
        local clients = vim.lsp.get_clients({ bufnr = buf, method = "documentSymbolProvider" })
        cache.client = clients[1]
        return #clients > 0
    end,
    async_get_symbols = function(cache, buf, refresh_symbols, on_fail)
        local function handler(err, result, _, _)
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

        LSP_REQUEST_TIMEOUT_MS = 500
        vim.defer_fn(
            function()
                cache.client.cancel_request(request_id)
                on_fail()
            end,
            LSP_REQUEST_TIMEOUT_MS
        )
    end,
    get_symbols = nil,
}

---@type Provider
local VimdocProvider = {
    name = "vimdoc",
    kind_to_hl_group = function(kind)
        ---@type table<string, string>
        local map = {
            H1 = "@markup.heading.1.vimdoc",
            H2 = "@markup.heading.2.vimdoc",
            H3 = "@markup.heading.3.vimdoc",
            Tag = "@label.vimdoc",
        }
        return map[kind]
    end,
    kind_to_display = function(kind)
        ---@type type<string, string>
        local map = {
            H1 = "#",
            H2 = "##",
            H3 = "###",
            Tag = "*",
        }
        return map[kind]
    end,
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
                -- Treesitter includes the last newline in the end range which spans
                -- until the next heading, so we -1
                -- TODO: This fix can be removed when we let highlight_hovered_item
                -- account for current column position in addition to the line.
                -- FIXME: By the way the end character should be the EOL
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
---@field root_symbol Symbol
---@field lines table<Symbol, integer>
---@field curr_provider Provider | nil
---@field custom_settings table<string, KindToDisplayFun>

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
            "  visible: " .. tostring(sidebar.visible),
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
        root_symbol = symbol_root(),
        lines = {},
        curr_provider = nil,
        custom_settings = {}
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
    win_set_option(sidebar.win, "cursorline", true)

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

    local line = vim.api.nvim_win_get_cursor(sidebar.win)[1]
    local s, _ = _find_symbol(sidebar.root_symbol, line)
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
---@param kind_to_hl_group KindToHlGroupFun
---@param kind_to_display KindToDisplayFun
---@param custom_kind_to_display KindToDisplayFun
---@return string[], table<Symbol, integer>, Highlight[], string[]
local function process_symbols(root_symbol, kind_to_hl_group, kind_to_display, custom_kind_to_display)
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
                prefix = CHAR_FOLDED .. " "
            else
                prefix = CHAR_UNFOLDED .. " "
            end
            local kind_display = custom_kind_to_display(kind_to_display(sym.kind))
            local line = indent .. prefix .. (kind_display ~= "" and (kind_display .. " ") or "") .. sym.name
            table.insert(buf_lines, line)
            ---@type Highlight
            local hl = {
                group = kind_to_hl_group(sym.kind),
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

    local source_buf = sidebar_source_win_buf(sidebar)
    local ft = vim.bo[source_buf].filetype

    local buf_lines, symbol_to_line, highlights, details = process_symbols(
        sidebar.root_symbol,
        provider.kind_to_hl_group,
        provider.kind_to_display,
        sidebar.custom_settings[ft] or (function(kind) return kind end)
    )
    sidebar.lines = symbol_to_line
    buf_set_content(sidebar.buf, buf_lines)
    for _, hl in ipairs(highlights) do
        highlight_apply(sidebar.buf, hl)
    end

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

---@param sidebar Sidebar
---@param providers Provider[]
---@param custom_settings table<string, table<string, KindToDisplayFun>>
local function sidebar_refresh_symbols(sidebar, providers, custom_settings)

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
        preserve_folds(sidebar.root_symbol, new_root)
        sidebar.root_symbol = new_root
        sidebar_refresh_view(sidebar)
    end

    ---@param provider Provider
    local function on_fail(provider)
        return function() print(provider.name .. " failed.") end
    end

    local buf = sidebar_source_win_buf(sidebar)
    for _, provider in ipairs(providers) do
        local cache = {}
        if provider.supports(cache, buf) then
            sidebar.curr_provider = provider
            sidebar.custom_settings = custom_settings[provider.name] or {}
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
---@return integer win
local function open_preview(sidebar)
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

---@param num integer
---@param sidebar Sidebar
local function sidebar_new(sidebar, num)
    sidebar.deleted = false
    sidebar.source_win = vim.api.nvim_get_current_win()

    sidebar.buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(sidebar.buf, "Symbols [" .. tostring(num) .. "]")
    vim.api.nvim_buf_set_option(sidebar.buf, "filetype", "SymbolsSidebar")

    vim.keymap.set("n", "l", function()
        local symbol = sidebar_current_symbol(sidebar)
        if symbol == nil then return end
        symbol.folded = false
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "L", function()
        local symbol = sidebar_current_symbol(sidebar)
        if symbol == nil then return end
        symbol_change_folded_rec(symbol, false)
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "h", function()
        local symbol = sidebar_current_symbol(sidebar)
        assert(symbol ~= nil)
        if symbol.level > 1 and (symbol.folded or #symbol.children == 0) then
            symbol = symbol.parent
        end
        symbol.folded = true
        sidebar_refresh_view(sidebar)
        move_cursor_to_symbol(sidebar, symbol)
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "H", function()
        local symbol = sidebar_current_symbol(sidebar)
        assert(symbol ~= nil)
        while(symbol.level ~= 1) do
            symbol = symbol.parent
        end
        symbol_change_folded_rec(symbol, true)
        sidebar_refresh_view(sidebar)
        move_cursor_to_symbol(sidebar, symbol)
    end, { buffer = sidebar.buf })

    local function goto_symbol()
        local symbol = sidebar_current_symbol(sidebar)
        assert(symbol ~= nil)
        vim.api.nvim_set_current_win(sidebar.source_win)
        vim.api.nvim_win_set_cursor(
            sidebar.source_win,
            { symbol.selectionRange.start.line + 1, symbol.selectionRange.start.character }
        )
        vim.fn.win_execute(sidebar.source_win, 'normal! zt')
        local r = symbol.range
        flash_highlight(sidebar.source_win, 400, r["end"].line - r.start.line + 1)
    end

    vim.keymap.set("n", "<CR>", goto_symbol, { buffer = sidebar.buf })
    vim.keymap.set("n", "<RightMouse>", goto_symbol, { buffer = sidebar.buf })

    vim.keymap.set("n", "zR", function()
        symbol_change_folded_rec(sidebar.root_symbol, false)
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "zM", function()
        symbol_change_folded_rec(sidebar.root_symbol, true)
        sidebar.root_symbol.folded = false
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

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

    local function find_level_to_fold(symbol)
        local max_level = (symbol.folded and 1) or symbol.level
        for _, sym in ipairs(symbol.children) do
            max_level = math.max(max_level, find_level_to_fold(sym))
        end
        return max_level
    end

    local function change_fold_at_level(symbol, level, value)
        if symbol.level == level then symbol.folded = value end
        if symbol.level >= level then return end
        for _, sym in ipairs(symbol.children) do
            change_fold_at_level(sym, level, value)
        end
    end

    vim.keymap.set("n", "zr", function()
        local level = find_level_to_unfold(sidebar.root_symbol)
        change_fold_at_level(sidebar.root_symbol, level, false)
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "zm", function()
        local level = find_level_to_fold(sidebar.root_symbol)
        change_fold_at_level(sidebar.root_symbol, level, true)
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    local current_preview_win = -1
    local details_win = -1

    vim.api.nvim_create_autocmd(
        "CursorMoved",
        {
            callback = function()
                if vim.api.nvim_win_is_valid(current_preview_win) then
                    vim.api.nvim_win_close(current_preview_win, true)
                    current_preview_win = -1
                end
                if vim.api.nvim_win_is_valid(details_win) then
                    vim.api.nvim_win_close(details_win, true)
                    details_win = -1
                end
            end,
            buffer = sidebar.buf,
        }
    )

    vim.keymap.set("n", "K", function()
        if vim.api.nvim_win_is_valid(current_preview_win) then
            vim.api.nvim_set_current_win(current_preview_win)
        else
            current_preview_win = open_preview(sidebar)
        end
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "d", function()
        if vim.api.nvim_win_is_valid(details_win) then return end

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
        details_win = vim.api.nvim_open_win(details_buf, false, opts)
        vim.wo[details_win].wrap = true
        -- vim.api.nvim_win_set_cursor(
        --     preview_win, { symbol.selectionRange.start.line+1, symbol.selectionRange.start.character }
        -- )
    end, { buffer = sidebar.buf })

    vim.keymap.set("n", "<2-LeftMouse>", function()
        local symbol = sidebar_current_symbol(sidebar)
        if #symbol.children == 0 then return end
        symbol.folded = not symbol.folded
        sidebar_refresh_view(sidebar)
    end, { buffer = sidebar.buf })

    sidebar_open(sidebar)
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
---@param source_buf integer
---@return Sidebar?
local function find_sidebar_by_source_buf(sidebars, source_buf)
    for _, sidebar in ipairs(sidebars) do
        if (
            not sidebar.deleted and
             sidebar_source_win_buf(sidebar) == source_buf
        ) then
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

---@function config table
function M.setup(config)
    ---@type Config
    local _config = vim.tbl_deep_extend("force", {}, cfg.default, config)

    local cmds = {}

    ---@type Sidebar[]
    local sidebars = {}

    ---@type Provider[]
    local providers = {
        LspProvider,
        VimdocProvider,
    }

    ---@type table<string, table<string, KindToDisplayFun>>
    local custom_kind_to_display = {
        lsp = {
            json = function(kind)
                ---@type table<string, string>
                local map = {
                    Module = "{}",
                    Array = "[]",
                    Boolean = "b",
                    String = "\"",
                    Number = "#",
                    Variable = "?",
                }
                return map[kind]
            end,
            yaml = function(kind)
                ---@type table<string, string>
                local map = {
                    Module = "{}",
                    Array = "[]",
                    Boolean = "b",
                    String = "\"",
                    Number = "#",
                    Variable = "?",
                }
                return map[kind]
            end,
            lua = function(kind)
                ---@type table<string, string>
                local map = {
                    Array = "[]",
                    Boolean = "boolean",
                    Constant = "param",
                    Function = "function",
                    Method = "function",
                    Number = "number",
                    Object = "{}",
                    Package = "",
                    String = "string",
                    Variable = "local",
                }
                return map[kind] or kind
            end,
            go = function(kind)
                ---@type table<string, string>
                local map = {
                    Struct = "struct",
                    Class = "type",
                    Constant = "const",
                    Function = "func",
                    Method = "func",
                    Field = "field",
                }
                return map[kind] or kind
            end,
            python = function(kind)
                ---@type table<string, string>
                local map = {
                    Class = "class",
                    Variable = "",
                    Constant = "const",
                    Function = "def",
                    Method = "def",
                }
                return map[kind] or kind
            end

        }
    }

    local AUTOCMD_GROUP = vim.api.nvim_create_augroup("Symbols", { clear = true })

    if _config.dev.enabled then
        local dev = require("symbols.dev")

        local function reload()
            remove_commands(cmds)
            vim.api.nvim_del_augroup_by_id(AUTOCMD_GROUP)
            for _, sidebar in ipairs(sidebars) do
                sidebar_destroy(sidebar)
            end
            dev.reload_plugin(config)
            print("symbols.nvim reloaded")
        end

        local function debug()
            show_debug_in_current_window(sidebars)
        end

        ---@type table<DevAction, fun()>
        local dev_action_to_fun = {
            reload = reload,
            debug = debug,
        }

        for key, action in pairs(_config.dev.keymaps) do
            vim.keymap.set("n", key, dev_action_to_fun[action])
        end
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
            else
                sidebar_open(sidebar)
            end
            sidebar_refresh_symbols(sidebar, providers, custom_kind_to_display)
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
            group = AUTOCMD_GROUP,
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
            group = AUTOCMD_GROUP,
            pattern = "*",
            callback = function(t)
                local buf = t.buf
                local sidebar = find_sidebar_by_source_buf(sidebars, buf)
                if sidebar == nil then return end
                sidebar_refresh_symbols(sidebar, providers, custom_kind_to_display)
            end
        }
    )
end

return M
