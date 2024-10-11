local cfg = require("symbols.config")

local M = {}

local global_autocmd_group = vim.api.nvim_create_augroup("Symbols", { clear = true })

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

---@class Pos
---@field line integer
---@field character integer

---@param point [integer, integer]
---@return Pos
local function to_pos(point)
    return { line = point[1] - 1, character = point[2] }
end

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
        if val ~= "help" then
            return false
        end
        local ok, parser = pcall(vim.treesitter.get_parser, buf, "vimdoc")
        if not ok then
            return false
        end
        cache.parser = parser
        return true
    end,
    async_get_symbols = nil,
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
        root.captureLevel = 0
        local current = root

        local function update_range_end(node, rangeEnd)
            if node.range ~= nil and node.captureLevel <= 3 then
                node.range["end"].line = rangeEnd
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

            while captureLevel <= current.captureLevel do
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
                    ["end"] = { character = col2, line = row2 - 1 },
                },
                range = {
                    start = { character = col1, line = rangeStart },
                    ["end"] = { character = col2, line = row2 - 1 },
                },
                children = {},

                parent = current,
                level = current.level + 1,
                folded = true,

                captureLevel = captureLevel,
            }

            table.insert(current.children, new)
            current = new
        end

        local lineCount = vim.api.nvim_buf_line_count(0)
        while current.captureLevel > 0 do
            update_range_end(current, lineCount)
            current = current.parent
            assert(current ~= nil)
        end

        return true, root
    end,
}

---@type Provider
local MarkdownProvider = {
    name = "markdown",
    init = nil,
    supports = function(cache, buf)
        local val = vim.api.nvim_get_option_value("ft", { buf = buf })
        if val ~= "markdown" then
            return false
        end
        local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
        if not ok then
            return false
        end
        cache.parser = parser
        return true
    end,
    async_get_symbols = nil,
    get_symbols = function(cache, _)
        local rootNode = cache.parser:parse()[1]:root()

        local queryString = [[
            [
                (atx_heading (atx_h1_marker) heading_content: (_) @h1)
                (atx_heading (atx_h2_marker) heading_content: (_) @h2)
                (atx_heading (atx_h3_marker) heading_content: (_) @h3)
                (atx_heading (atx_h4_marker) heading_content: (_) @h4)
                (atx_heading (atx_h5_marker) heading_content: (_) @h5)
                (atx_heading (atx_h6_marker) heading_content: (_) @h6)
            ]
        ]]
        local query = vim.treesitter.query.parse("markdown", queryString)

        local captureLevelMap = { h1 = 1, h2 = 2, h3 = 3, h4 = 4, h5 = 5, h6 = 6 }
        local kindMap = { h1 = "H1", h2 = "H2", h3 = "H3", h4 = "H4", h5 = "H5", h6 = "H6" }

        local root = symbol_root()
        local current = root

        local function update_range_end(node, rangeEnd)
            if node.range ~= nil and node.level <= 6 then
                node.range["end"].line = rangeEnd
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
            if captureLevel <= 5 then
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
                    start = { character = col1, line = rangeStart + 1 },
                    ["end"] = { character = col2, line = row2 - 1 },
                },
                range = {
                    start = { character = col1, line = rangeStart + 1 },
                    ["end"] = { character = col2, line = row2 - 1 },
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
}

---@class Preview
---@field win integer
---@field locked boolean
---@field auto_show boolean
---@field source_win integer
---@field source_buf integer
---@field keymaps_to_remove string[]

---@return Preview
local function preview_new_obj()
    return {
        win = -1,
        locked = false,
        auto_show = false,
        source_buf = -1,
        keymaps_to_remove = {},
    }
end

---@class PreviewOpenParams
---@field source_win integer
---@field source_buf integer
---@field symbol Symbol
---@field cursor integer[2]
---@field config PreviewConfig

---@param preview Preview
local function preview_close(preview)
    if vim.api.nvim_win_is_valid(preview.win) then
        vim.api.nvim_win_close(preview.win, true)
    end
    preview.locked = false
    preview.win = -1
    for _, key in ipairs(preview.keymaps_to_remove) do
        vim.keymap.del("n", key, { buffer = preview.source_buf })
    end
    preview.keymaps_to_remove = {}
    preview.source_buf = -1
end

---@param preview Preview
local function preview_goto_symbol(preview)
    local cursor = vim.api.nvim_win_get_cursor(preview.win)
    vim.api.nvim_win_set_cursor(preview.source_win, cursor)
    vim.api.nvim_set_current_win(preview.source_win)
    vim.fn.win_execute(preview.source_win, "normal! zz")
end

---@type table<PreviewAction, fun(preview: Preview)>
local preview_actions = {
    ["close"] = preview_close,
    ["goto-code"] = preview_goto_symbol,
}

---@param preview Preview
---@param params PreviewOpenParams
local function _preview_open(preview, params)
    local config = params.config
    local range = params.symbol.range
    local selection_range = params.symbol.selectionRange

    local height = config.fixed_size_height
    if config.auto_size then
        height = config.auto_size_extra_lines + (range["end"].line - range.start.line) + 1
        height = math.max(config.min_window_height, height)
        height = math.min(config.max_window_height, height)
    end
    local max_height = vim.api.nvim_win_get_height(params.source_win) - 3
    height = math.min(max_height, height)

    local max_width = vim.api.nvim_win_get_width(params.source_win) - 2
    local width = config.window_width
    width = math.min(max_width, width)

    local opts = {
        relative = "cursor",
        anchor = "NE",
        width = width,
        height = height,
        row = 0,
        col = -params.cursor[2]-1,
        border = "single",
        style = "minimal",
    }
    preview.win = vim.api.nvim_open_win(params.source_buf, false, opts)
    if params.config.show_line_number then
        vim.wo[preview.win].number = true
    end
    vim.api.nvim_win_set_cursor(
        preview.win,
        { selection_range.start.line+1, selection_range.start.character }
    )
    vim.fn.win_execute(preview.win, "normal! zt")
    vim.api.nvim_set_option_value("cursorline", true, { win = preview.win })

    preview.source_win = params.source_win
    preview.source_buf = params.source_buf
    for keymap, action in pairs(config.keymaps) do
        local fn = function() preview_actions[action](preview) end
        vim.keymap.set("n", keymap, fn, { buffer = params.source_buf })
        table.insert(preview.keymaps_to_remove, keymap)
    end
end

---@param get_params fun(): PreviewOpenParams
---@param preview Preview
local function preview_open(preview, get_params)
    if vim.api.nvim_win_is_valid(preview.win) then
        vim.api.nvim_set_current_win(preview.win)
    else
        preview.locked = true
        local params = get_params()
        _preview_open(preview, params)
    end
end

---@param preview Preview
---@param get_open_params fun(): PreviewOpenParams
local function preview_toggle_auto_show(preview, get_open_params)
    if preview.auto_show then
        preview_close(preview)
    else
        preview_open(preview, get_open_params)
    end
    preview.auto_show = not preview.auto_show
end

---@param preview Preview
---@param get_open_params fun(): PreviewOpenParams
local function preview_on_cursor_move(preview, get_open_params)
    -- After creating the preview the CursorMoved event is triggered once.
    -- We ignore it here.
    if preview.locked then
        preview.locked = false
    else
        preview_close(preview)
        if preview.auto_show then
            preview_open(preview, get_open_params)
        end
    end
end

---@param preview Preview
local function preview_on_win_enter(preview)
    if (
        vim.api.nvim_win_is_valid(preview.win) and
        vim.api.nvim_get_current_win() ~= preview.win
    ) then
        preview_close(preview)
    end
end

---@param preview Preview
---@param win integer
local function preview_on_win_close(preview, win)
    if win == preview.win then
        preview_close(preview)
    end
end

---@class DetailsWindow
---@field auto_show boolean
---@field win integer
---@field sidebar_win integer
---@field locked boolean
---@field prev_cursor [integer, integer] | nil

---@return DetailsWindow
local function details_window_new_obj()
    return {
        auto_show = false,
        win = -1,
        sidebar_win = -1,
        locked = false,
        prev_cursor = nil,
    }
end

---@param symbol Symbol
---@return string[]
local function symbol_path(symbol)
    local path = {}
    while symbol.level > 0 do
        path[symbol.level] = symbol.name
        symbol = symbol.parent
        assert(symbol ~= nil)
    end
    return path
end

---@class DetailsOpenParams
---@field details DetailsWindow
---@field sidebar_win integer
---@field symbol Symbol

---@param details DetailsWindow
---@param params DetailsOpenParams
local function details_open(details, params)
    local sidebar_win = params.sidebar_win
    local symbol = params.symbol

    if vim.api.nvim_win_is_valid(details.win) then
        return
    end

    local details_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "delete", { buf = details_buf })

    ---@param range Range
    ---@return string
    local function range_string(range)
        return (
            "( "
            .. "(" .. range.start.line .. ", " .. range.start.character .. "), "
            .. "(" .. range["end"].line .. ", " .. range["end"].character .. ")"
            .. " )"
        )
    end

    local text = {
        "[" .. symbol.kind .. "] level: " .. tostring(symbol.level),
        "range: " .. range_string(symbol.range),
        "selectionRange: " .. range_string(symbol.selectionRange),
        "",
        table.concat(symbol_path(symbol), "."),
    }

    if symbol.detail ~= "" then
        vim.list_extend(text, vim.split(symbol.detail, "\n"))
    end

    local longest_line = 0
    for _, line in ipairs(text) do
        longest_line = math.max(longest_line, #line)
    end

    buf_set_content(details_buf, text)
    local line_count = vim.api.nvim_buf_line_count(details_buf)

    local sidebar_width = vim.api.nvim_win_get_width(sidebar_win)
    local width = math.max(sidebar_width - 2, longest_line + 1)
    local height = line_count

    local cursor = vim.api.nvim_win_get_cursor(sidebar_win)
    local row = -2 - height
    local anchor = "NW"
    if cursor[1] - 1 + row < 0 then
        row = -1 * row + 1
        anchor = "SW"
    end

    local col = 0
    if width + 2 > sidebar_width then
        col = col - (width + 2 - sidebar_width)
    end

    local opts = {
        relative = "cursor",
        anchor = anchor,
        width = width,
        height = height,
        row = row,
        col = col,
        border = "single",
        style = "minimal",
    }
    details.win = vim.api.nvim_open_win(details_buf, false, opts)
    details.sidebar_win = sidebar_win

    if cursor[2] == 0 then
        details.locked = false
        details.prev_cursor = nil
    else
        -- details.locked = true
        -- vim.api.nvim_win_set_cursor(sidebar_win, { cursor[1], 0 })
        -- details.prev_cursor = cursor
    end

    vim.wo[details.win].wrap = true
end

---@param details DetailsWindow
---@param get_open_params fun(): DetailsOpenParams
local function details_on_cursor_move(details, get_open_params)
    if details.locked then
        if details.prev_cursor ~= nil then
            vim.api.nvim_win_set_cursor(details.sidebar_win, details.prev_cursor)
            details.prev_cursor = nil
        end
        details.locked = false
    else
        if vim.api.nvim_win_is_valid(details.win) then
            vim.api.nvim_win_close(details.win, true)
            details.win = -1
        end
        if details.auto_show then
            details_open(details, get_open_params())
        end
    end
end

---@param details DetailsWindow
local function details_close(details)
    if vim.api.nvim_win_is_valid(details.win) then
        vim.api.nvim_win_close(details.win, true)
    end
    details.win = -1
    details.locked = false
end

---@param details DetailsWindow
---@param get_open_params fun(): DetailsOpenParams
local function details_toggle_auto_show(details, get_open_params)
    if details.auto_show then
        details_close(details)
    else
        details_open(details, get_open_params())
    end
    details.auto_show = not details.auto_show
end

---@param details DetailsWindow
---@param get_open_params fun(): DetailsOpenParams
local function details_on_win_enter(details, get_open_params)
    if vim.api.nvim_win_is_valid(details.win) then
        local curr_win = vim.api.nvim_get_current_win()
        if curr_win == details.sidebar_win then
            if details.auto_show then
                details_open(details, get_open_params())
            end
        else
            details_close(details)
        end
    end
end

---@class CursorState
---@field hide boolean
---@field hidden boolean
---@field original string

---@class GlobalState
---@field cursor CursorState

---@return GlobalState
local function global_state_new()
    return {
        cursor = {
            hide = false,
            hidden = false,
            origina = vim.o.guicursor,
        }
    }
end

---@class Sidebar
---@field gs GlobalState
---@field deleted boolean
---@field win integer
---@field buf integer
---@field source_win integer
---@field visible boolean
---@field buf_symbols table<integer, Symbol>
---@field lines table<Symbol, integer>
---@field curr_provider Provider | nil
---@field symbol_display_config table<string, SymbolDisplayConfig>
---@field preview_config PreviewConfig
---@field preview Preview
---@field details DetailsWindow
---@field char_config CharConfig
---@field show_details boolean
---@field show_details_pop_up boolean
---@field show_guide_lines boolean
---@field keymaps KeymapsConfig

---@return Sidebar
local function sidebar_new_obj()
    return {
        gs = global_state_new(),
        deleted = false,
        win = -1,
        buf = -1,
        source_win = -1,
        visible = false,
        buf_symbols = vim.defaulttable(symbol_root),
        lines = {},
        curr_provider = nil,
        symbol_display_config = {},
        preview = preview_new_obj(),
        details = details_window_new_obj(),
        char_config = cfg.default.sidebar.chars,
        show_details = false,
        show_details_pop_up = false,
        show_guide_lines = false,
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

---@param root Symbol
---@param pos Pos
---@return Symbol
local function symbol_at_pos(root, pos)

    ---@param range Range
    ---@param _pos Pos
    ---@return boolean
    local function in_range_line(range, _pos)
        return range.start.line <= _pos.line and _pos.line <= range["end"].line
    end

    ---@param range Range
    ---@param _pos Pos
    ---@return boolean
    local function in_range_character(range, _pos)
        return range.start.character <= _pos.character and _pos.character <= range["end"].character
    end

    ---@param range Range
    ---@param _pos Pos
    ---@return boolean
    local function range_before_pos(range, _pos)
        return (
            range["end"].line < _pos.line
            or (
                range["end"].line == _pos.line
                and range["end"].character < _pos.line
            )
        )
    end

    local current = root
    local partial_match = true
    while #current.children > 0 and partial_match do
        partial_match = false
        local prev = current
        for _, symbol in ipairs(current.children) do
            if range_before_pos(symbol.range, pos) then
                prev = symbol
            end
            if not partial_match and in_range_line(symbol.range, pos) then
                current = symbol
                partial_match = true
            end
            if partial_match then
                if in_range_line(symbol.range, pos) then
                    if in_range_character(symbol.range, pos) then
                        current = symbol
                        break
                    end
                else
                    break
                end
            end
        end
        if not partial_match then current = prev end
    end
    return current
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

---@param sidebar Sidebar
local function sidebar_preview_close(sidebar)
    preview_close(sidebar.preview)
end

local function sidebar_close(sidebar)
    if not sidebar.visible then return end
    sidebar_preview_close(sidebar)
    details_close(sidebar.details)
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
---@param show_guide_lines boolean
---@return string[], table<Symbol, integer>, Highlight[], string[]
local function process_symbols(root_symbol, symbol_display_config, chars, show_guide_lines)
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
        for sym_i, sym in ipairs(symbol.children) do
            local prefix
            if #sym.children == 0 then
                if show_guide_lines and sym.level > 1 then
                    if sym_i == #symbol.children then
                        prefix = chars.guide_last_item .. " "
                    else
                        prefix = chars.guide_middle_item .. " "
                    end
                else
                    prefix = "  "
                end
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
            local new_indent
            if show_guide_lines and sym.level > 1 and sym_i ~= #symbol.children then
                new_indent = indent .. chars.guide_vert .. " "
            else
                new_indent = indent .. "  "
            end
            line_nr = get_buf_lines_and_highlights(sym, new_indent, line_nr + 1)
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
        sidebar.char_config,
        sidebar.show_guide_lines
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

---@param symbol Symbol
---@param value boolean
---@return integer
local function symbol_change_folded_rec(symbol, value)
    local changes = (symbol.folded ~= value and #symbol.children > 0 and 1) or 0
    symbol.folded = value
    for _, sym in ipairs(symbol.children) do
        changes = changes + symbol_change_folded_rec(sym, value)
    end
    return changes
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
local function _sidebar_preview_open_params(sidebar)
    ---@return PreviewOpenParams
    return function()
        return {
            source_win = sidebar.source_win,
            source_buf = sidebar_source_win_buf(sidebar),
            cursor = vim.api.nvim_win_get_cursor(sidebar.win),
            symbol = sidebar_current_symbol(sidebar),
            config = sidebar.preview_config,
        }
    end
end

---@param sidebar Sidebar
local function sidebar_preview_open(sidebar)
    preview_open(sidebar.preview, _sidebar_preview_open_params(sidebar))
end

---@param sidebar Sidebar
---@return fun(): DetailsOpenParams
local function _sidebar_details_open_params(sidebar)
    return function()
        return {
            symbol = sidebar_current_symbol(sidebar),
            sidebar_win = sidebar.win,
        }
    end
end

---@param sidebar Sidebar
local function sidebar_toggle_show_details(sidebar)
    if vim.api.nvim_win_is_valid(sidebar.details.win) then
        details_close(sidebar.details)
    else
        details_open(sidebar.details, _sidebar_details_open_params(sidebar)())
    end
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
    local changes = symbol_change_folded_rec(symbol, true)
    if changes == 0 then
        while(symbol.level > 1) do
            symbol = symbol.parent
            assert(symbol ~= nil)
        end
        symbol_change_folded_rec(symbol, true)
    end
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

local function sidebar_toggle_auto_details(sidebar)
    details_toggle_auto_show(sidebar.details, _sidebar_details_open_params(sidebar))
end

---@param sidebar Sidebar
local function sidebar_toggle_auto_preview(sidebar)
    preview_toggle_auto_show(sidebar.preview, _sidebar_preview_open_params(sidebar))
end

---@param cursor CursorState
local function hide_cursor(cursor)
    if not cursor.hidden then
        local cur = vim.o.guicursor:match("n.-:(.-)[-,]")
        vim.opt.guicursor:append("n:" .. cur .. "-Cursorline")
        cursor.hidden = true
    end
end

---@param cursor CursorState
local function reset_cursor(cursor)
    vim.o.guicursor = cursor.original
    cursor.hidden = false
end

---@param sidebar Sidebar
local function sidebar_toggle_cursor_hiding(sidebar)
    local cursor = sidebar.gs.cursor
    if cursor.hide then
        reset_cursor(cursor)
    else
        hide_cursor(cursor)
    end
    cursor.hide = not cursor.hide
end

local help_options_order = {
    "goto-symbol",
    "preview",
    "toggle-show-details",
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
    "toggle-auto-details",
    "toggle-auto-preview",
    "toggle-cursor-hiding",
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
    ["preview"] = sidebar_preview_open,
    ["toggle-show-details"] = sidebar_toggle_show_details,

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
    ["toggle-auto-details"] = sidebar_toggle_auto_details,
    ["toggle-auto-preview"] = sidebar_toggle_auto_preview,
    ["toggle-cursor-hiding"] = sidebar_toggle_cursor_hiding,

    ["help"] = sidebar_help,
    ["close"] = sidebar_close,
}

---@param sidebar Sidebar
local function sidebar_on_cursor_move(sidebar)
    preview_on_cursor_move(sidebar.preview, _sidebar_preview_open_params(sidebar))
    details_on_cursor_move(sidebar.details, _sidebar_details_open_params(sidebar))
end

---@param sidebar Sidebar
---@param num integer
---@param config SidebarConfig
---@param gs GlobalState
local function sidebar_new(sidebar, num, config, gs)
    sidebar.deleted = false
    sidebar.source_win = vim.api.nvim_get_current_win()

    sidebar.gs = gs
    sidebar.preview_config = config.preview
    sidebar.show_details = config.show_details
    sidebar.show_guide_lines = config.show_guide_lines
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
            nested = true,
        }
    )

    vim.api.nvim_create_autocmd(
        { "WinEnter" },
        {
            group = global_autocmd_group,
            callback = function()
                preview_on_win_enter(sidebar.preview)
                details_on_win_enter(sidebar.details, _sidebar_details_open_params(sidebar))
            end,
        }
    )

    vim.api.nvim_create_autocmd(
        { "WinClosed" },
        {
            group = global_autocmd_group,
            callback = function(e)
                local win = tonumber(e.match, 10)
                preview_on_win_close(sidebar.preview, win)
            end,
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
---@param autocmd_group string
---@param sidebars Sidebar[]
---@config Config
---@param gs GlobalState
local function setup_dev(cmds, autocmd_group, sidebars, config, gs)
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

        reset_cursor(gs.cursor)

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

---@param sidebars Sidebar[]
---@param cursor CursorState
local function on_win_enter_hide_cursor(sidebars, cursor)
    local win = vim.api.nvim_get_current_win()
    for _, sidebar in ipairs(sidebars) do
        if sidebar.win == win then
            hide_cursor(cursor)
            return
        end
    end
end

---@param sidebar Sidebar
---@param target Symbol
local function sidebar_set_cursor_at_symbol(sidebar, target)

    ---@param outer_range Range
    ---@param inner_range Range
    ---@return boolean
    local function range_contains(outer_range, inner_range)
        return (
            (
                outer_range.start.line < inner_range.start.line
                or (
                    outer_range.start.line == inner_range.start.line
                    and outer_range.start.character <= inner_range.start.character
                )
            ) and (
                inner_range["end"].line < outer_range["end"].line
                or (
                    outer_range["end"].line == inner_range["end"].line
                    and inner_range["end"].character <= outer_range["end"].character
                )
            )
        )
    end

    ---@param symbol Symbol
    ---@return integer
    local function count_lines(symbol)
        local lines = 1
        if not symbol.folded then
            for _, child in ipairs(symbol.children) do
                lines = lines + count_lines(child)
            end
        end
        return lines
    end

    if target.level == 0 then return end
    local current = sidebar_current_symbols(sidebar)
    local lines = 0
    while current ~= target do
        current.folded = false
        local found = false
        for _, child in ipairs(current.children) do
            if range_contains(child.range, target.range) then
                lines = lines + 1
                current = child
                found = true
                break
            else
                lines = lines + count_lines(child)
            end
        end
        if not found then break end
    end

    if lines == 0 then lines = 1 end
    sidebar_refresh_view(sidebar)
    vim.api.nvim_win_set_cursor(sidebar.win, { lines, 0 })
end

function M.setup(config)
    local _config = cfg.prepare_config(config)

    local cmds = {}

    ---@type GlobalState
    local gs = {
        cursor = {
            hide = _config.hide_cursor,
            hidden = false,
            original = vim.o.guicursor,
        }
    }

    ---@type Sidebar[]
    local sidebars = {}

    ---@type Provider[]
    local providers = {
        LspProvider,
        VimdocProvider,
        MarkdownProvider,
    }

    if _config.dev.enabled then
        setup_dev(cmds, global_autocmd_group, sidebars, _config, gs)
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
                sidebar_new(sidebar, num, _config.sidebar, gs)
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

    create_command(
        cmds,
        "SymbolsCurrent",
        function()
            local win = vim.api.nvim_get_current_win()
            local sidebar = find_sidebar_for_win(sidebars, win)
            if sidebar ~= nil then
                local root = sidebar_current_symbols(sidebar)
                local pos = to_pos(vim.api.nvim_win_get_cursor(sidebar.source_win))
                local symbol = symbol_at_pos(root, pos)
                sidebar_set_cursor_at_symbol(sidebar, symbol)
            end
        end,
        {}
    )

    create_command(
        cmds,
        "SymbolsGoTo",
        function()

        end,
        {}
    )

    vim.api.nvim_create_autocmd(
        "WinEnter",
        {
            group = global_autocmd_group,
            pattern = "*",
            callback = function()
                if gs.cursor.hide then
                    on_win_enter_hide_cursor(sidebars, gs.cursor)
                end
            end
        }
    )

    vim.api.nvim_create_autocmd(
        "WinLeave",
        {
            group = global_autocmd_group,
            pattern = "*",
            callback = function()
                if gs.cursor.hide or gs.cursor.hidden then
                    reset_cursor(gs.cursor)
                end
            end
        }
    )

    vim.api.nvim_create_autocmd(
        "WinClosed",
        {
            group = global_autocmd_group,
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
            group = global_autocmd_group,
            pattern = "*",
            callback = function(t)
                local source_buf = t.buf
                for _, sidebar in ipairs(sidebars) do
                    if sidebar_source_win_buf(sidebar) == source_buf then
                        sidebar_refresh_symbols(sidebar, providers, _config)
                    end
                end
            end
        }
    )
end

return M
