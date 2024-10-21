local cfg = require("symbols.config")

local M = {}

---@type integer
local LOG_LEVEL = vim.log.levels.ERROR

---@type table<integer, string>
local LOG_LEVEL_STRING = {
    [vim.log.levels.ERROR] = "ERROR",
    [vim.log.levels.WARN] = "WARN",
    [vim.log.levels.INFO] = "INFO",
    [vim.log.levels.DEBUG] = "DEBUG",
    [vim.log.levels.TRACE] = "TRACE",
}

---@param msg string
---@param level any
local function _log(msg, level)
    if level >= LOG_LEVEL then
        local date = os.date("%Y/%m/%d %H:%M:%S")
        local _msg = table.concat({"[", date, "] ", LOG_LEVEL_STRING[level], " ", msg}, "")
        vim.notify(_msg, level)
    end
end

---@alias LogFun fun(msg: string)

local log = {
    ---@type LogFun
    error = function(msg) _log(msg, vim.log.levels.ERROR) end,
    ---@type LogFun
    warn = function(msg) _log(msg, vim.log.levels.WARN) end,
    ---@type LogFun
    info = function(msg) _log(msg, vim.log.levels.INFO) end,
    ---@type LogFun
    debug = function(msg) _log(msg, vim.log.levels.DEBUG) end,
    ---@type LogFun
    trace = function(msg) _log(msg, vim.log.levels.TRACE) end,
}

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

---@param win integer
---@return boolean
local function is_floating_win(win)
  return vim.api.nvim_win_get_config(win).relative ~= ""
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

---@return Symbol
local function Symbol_root()
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
    }
end

---@alias RefreshSymbolsFun fun(symbols: Symbol, provider_name: string, provider_config: table)
---@alias KindToHlGroupFun fun(kind: string): string
---@alias KindToDisplayFun fun(kind: string): string

---@class Provider
---@field name string
---@field init (fun(cache: table, config: table)) | nil
---@field supports fun(cache: table, buf: integer): boolean
---@field async_get_symbols (fun(cache: any, buf: integer, refresh_symbols: fun(root: Symbol), on_fail: fun())) | nil
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


---@param lsp_symbol any
---@param parent Symbol?
---@param level integer
local function rec_tidy_lsp_symbol(lsp_symbol, parent, level)
    lsp_symbol.parent = parent
    lsp_symbol.detail = lsp_symbol.detail or ""
    lsp_symbol.children = lsp_symbol.children or {}
    lsp_symbol.kind = LspSymbolKindString[lsp_symbol.kind]
    lsp_symbol.level = level
    for _, child in ipairs(lsp_symbol.children) do
        rec_tidy_lsp_symbol(child, lsp_symbol, level + 1)
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

        ---@param sym1 Symbol
        ---@param sym2 Symbol
        ---@return boolean
        local function comp_range(sym1, sym2)
            local s1 = sym1.range.start
            local s2 = sym2.range.start
            return (
                s1.line < s2.line
                or (s1.line == s2.line and s1.character < s2.character)
            )
        end

        ---@param symbol Symbol
        local function sort_symbols(symbol)
            table.sort(symbol.children, comp_range)
            for _, child in ipairs(symbol.children) do
                sort_symbols(child)
            end
        end

        local function handler(err, result, _, _)
            got_symbols = true
            if err ~= nil then
                on_fail()
                return
            end
            local root = Symbol_root()
            root.children = result
            rec_tidy_lsp_symbol(root, nil, 0)
            sort_symbols(root)
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

        local root = Symbol_root()
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

        local root = Symbol_root()
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
---@field sidebar_win integer
---@field sidebar_side "left" | "right"

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

    params.cursor[1] = params.cursor[1] - vim.fn.line("w0", params.sidebar_win) + 1

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
        height = height,
        width = width,
        border = "single",
        style = "minimal",
        zindex = 45, -- to allow other floating windows (like symbol peek) in front
    }
    if params.sidebar_side == "right" then
        opts.relative = "win"
        opts.win = params.sidebar_win
        opts.anchor = "NE"
        opts.row = params.cursor[1] - 1
        opts.col = -1
    else
        opts.relative = "win"
        opts.win = params.source_win
        opts.anchor = "NW"
        opts.row = params.cursor[1] - 1
        opts.col = 0
    end

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
---@field show_debug_info boolean

---@return DetailsWindow
local function details_window_new_obj()
    return {
        auto_show = false,
        win = -1,
        sidebar_win = -1,
        locked = false,
        prev_cursor = nil,
        show_debug_info = false
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
---@field sidebar_win integer
---@field sidebar_side "left" | "right"
---@field symbol Symbol
---@field symbol_state SymbolState
---@field symbol_display_config table<string, SymbolDisplayConfig>

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

    local text = {}

    if details.show_debug_info then
        ---@param range Range
        ---@return string
        local function range_string(range)
            return (
                "("
                .. "(" .. range.start.line .. ", " .. range.start.character .. "), "
                .. "(" .. range["end"].line .. ", " .. range["end"].character .. ")"
                .. ")"
            )
        end
        -- debug info
        table.insert(text, " [SYMBOL DEBUG INFO]")
        table.insert(text, "   name: " .. symbol.name)
        table.insert(text, "   kind: " .. (symbol.kind or ""))
        table.insert(text, "   level: " .. tostring(symbol.level))
        table.insert(text, "   range: " .. range_string(symbol.range))
        table.insert(text, "   selectionRange: " .. range_string(symbol.selectionRange))
        table.insert(text, "   folded: " .. tostring(params.symbol_state.folded))
        table.insert(text, "   visible: " .. tostring(params.symbol_state.visible))
        table.insert(text, "")
    end

    ---@type Highlight[]
    local highlights = {}

    local symbol_cfg = params.symbol_display_config[symbol.kind] or {}
    local display_kind = symbol_cfg.kind or ""
    if display_kind ~= "" then
        table.insert(highlights, {
            group = params.symbol_display_config[symbol.kind].highlight,
            line = #text + 1,
            col_start = 1,
            col_end = 1 + #display_kind,
        })
        display_kind = display_kind .. " "
    end
    table.insert(text, " " .. display_kind .. table.concat(symbol_path(symbol), "."))

    if symbol.detail ~= "" then
        local detail_first_line = #text + 1
        for detail_line, line in ipairs(vim.split(symbol.detail, "\n")) do
            table.insert(text, "   " .. line)
            table.insert(highlights, {
                group = "Comment",
                line = detail_first_line + detail_line - 1,
                col_start = 0,
                col_end = 3 + #line,
            })
        end
    end

    local longest_line = 0
    for _, line in ipairs(text) do
        longest_line = math.max(longest_line, #line)
    end

    buf_set_content(details_buf, text)

    for _, hl in ipairs(highlights) do
        highlight_apply(details_buf, hl)
    end

    local line_count = vim.api.nvim_buf_line_count(details_buf)

    local sidebar_width = vim.api.nvim_win_get_width(sidebar_win)
    local width = math.max(sidebar_width - 2, longest_line + 1)
    local height = line_count

    local cursor = vim.api.nvim_win_get_cursor(sidebar_win)
    cursor[1] = cursor[1] - vim.fn.line("w0", sidebar_win) + 1

    local row = cursor[1] - 3 - height
    if row < 0 then row = cursor[1] end

    local col = 0
    if params.sidebar_side == "right" and width + 2 > sidebar_width then
        col = col - (width + 2 - sidebar_width)
    end

    local opts = {
        relative = "win",
        win = params.sidebar_win,
        anchor = "NW",
        row = row,
        col = col,
        width = width,
        height = height,
        border = "single",
        style = "minimal",
    }
    details.win = vim.api.nvim_open_win(details_buf, false, opts)
    details.sidebar_win = sidebar_win
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

---@class GlobalSettings
---@field open_direction OpenDirection

---@class GlobalState
---@field cursor CursorState
---@field settings GlobalSettings

---@return GlobalState
local function GlobalState_new()
    ---@type GlobalState
    local obj = {
        cursor = {
            hide = false,
            hidden = false,
            original = vim.o.guicursor,
        },
        settings = {
            open_direction = cfg.default.sidebar.open_direction,
        },
    }
    return obj
end

---@class SymbolState
---@field folded boolean
---@field visible boolean
---@field visible_children integer

---@return SymbolState
local function SymbolState_new()
    return {
        folded = true,
        visible = true,
        visible_children = 0,
    }
end

---@alias SymbolStates table<Symbol, SymbolState>

---@param root Symbol
---@return Symbols
local function SymbolStates_build(root)
    local states = {}

    local function traverse(symbol)
        states[symbol] = SymbolState_new()
        for _, child in ipairs(symbol.children) do
            traverse(child)
        end
    end

    traverse(root)
    return states
end

---@alias SymbolFilter fun(ft: string, symbol: Symbol): boolean

---@class Symbols
---@field provider string
---@field provider_config table
---@field buf integer
---@field root Symbol
---@field states SymbolStates

---@return Symbols
local function Symbols_new()
    local root = Symbol_root()
    local symbols = {
        provider = "",
        buf = -1,
        root = root,
        states = {
            [root] = SymbolState_new()
        },
    }
    symbols.states[root].folded = false
    return symbols
end

---@param symbols Symbols
---@param symbol_filter SymbolFilter
local function Symbols_apply_filter(symbols, symbol_filter)
    local ft = vim.api.nvim_get_option_value("filetype", { buf = symbols.buf })

    ---@param symbol Symbol
    local function apply(symbol)
        local state = symbols.states[symbol]
        if symbol.level == 0 then
            state.visible = true
        else
            state.visible = symbol_filter(ft, symbol)
        end
        state.visible_children = 0
        for _, child in ipairs(symbol.children) do
            apply(child)
            if symbols.states[child].visible then
                state.visible_children = state.visible_children + 1
            end
        end

    end

    apply(symbols.root)
end

---@class SymbolsCacheEntry
---@field root Symbol
---@field fresh boolean
---@field update_in_progress boolean
---@field post_update_callbacks RefreshSymbolsFun[]
---@field updated osdate
---@field provider_name string

---@return SymbolsCacheEntry
local function SymbolsCacheEntry_new()
    return {
        root = Symbol_root(),
        fresh = false,
        update_in_progress = false,
        post_update_callbacks = {},
        updated = nil,
        provider_name = ""
    }
end

---@alias SymbolsCache table<integer, SymbolsCacheEntry>

---@return SymbolsCache
local function SymbolsCache_new()
    return vim.defaulttable(SymbolsCacheEntry_new)
end

---@class SymbolsRetriever
---@field providers Provider[]
---@field providers_config ProvidersConfig
---@field cache SymbolsCache

---@param providers Provider[]
---@param providers_config ProvidersConfig
---@return SymbolsRetriever
local function SymbolsRetriever_new(providers, providers_config)
    return {
        providers = providers,
        providers_config = providers_config,
        cache = SymbolsCache_new()
    }
end

---@param retriever SymbolsRetriever
---@param buf integer
---@param on_retrieve fun(symbol: Symbol, provider_name: string, provider_config: table)
local function SymbolsRetriever_retrieve(retriever, buf, on_retrieve)
    ---@param provider Provider
    local function on_fail(provider)
        return function()
            local entry = retriever.cache[buf]
            entry.update_in_progress = false
            entry.post_update_callbacks = {}
            log.error(provider.name .. " failed")
        end
    end

    ---@param provider_name string
    ---@param cached boolean
    ---@return fun(root: Symbol)
    local _on_retrieve = function(provider_name, cached)
        ---@param root Symbol
        return function(root)
            local entry = retriever.cache[buf]
            entry.root = root
            entry.fresh = true
            if not cached then
                local date = os.date("*t")
                assert(type(date) ~= "string")
                entry.updated = date
            end
            entry.provider_name = provider_name

            for _, callback in ipairs(entry.post_update_callbacks) do
                callback(root, provider_name, retriever.providers_config[provider_name])
            end

            entry.update_in_progress = false
            entry.post_update_callbacks = {}
        end
    end

    local entry = retriever.cache[buf]

    if entry.fresh then
        table.insert(entry.post_update_callbacks, on_retrieve)
        _on_retrieve(entry.provider_name, true)(entry.root)
        return
    end

    if entry.update_in_progress then
        -- TODO: do not add multiple callbacks for the same sidebar
        table.insert(entry.post_update_callbacks, on_retrieve)
        return
    end

    for _, provider in ipairs(retriever.providers) do
        local cache = {}
        if provider.init ~= nil then
            local config = retriever.providers_config[provider.name]
            provider.init(cache, config)
        end
        if provider.supports(cache, buf) then
            table.insert(entry.post_update_callbacks, on_retrieve)
            if provider.async_get_symbols ~= nil then
                provider.async_get_symbols(
                    cache,
                    buf,
                    _on_retrieve(provider.name, false),
                    on_fail(provider)
                )
            else
                local ok, symbol = provider.get_symbols(cache, buf)
                if not ok then
                    on_fail(provider)()
                else
                    assert(symbol ~= nil)
                    _on_retrieve(provider.name, false)(symbol)
                end
            end
            entry.update_in_progress = true
            return
        end
    end
end

---@class WinSettings
---@field number boolean | nil
---@field relativenumber boolean | nil
---@field signcolumn string | nil
---@field cursorline boolean | nil
---@field winfixwidth boolean | nil
---@field wrap boolean | nil

---@return WinSettings
local function WinSettings_new()
    return {
        number = nil,
        relativenumber = nil,
        signcolumn = nil,
        cursorline = nil,
        winfixwidth = nil,
        wrap = nil,
    }
end

---@param win integer
---@return WinSettings
local function WinSettings_get(win)

    ---@param opt string
    local function get_opt(opt)
        return vim.api.nvim_get_option_value(opt, { win = win })
    end

    return {
        number = get_opt("number"),
        relativenumber = get_opt("relativenumber"),
        signcolumn = get_opt("signcolumn"),
        cursorline = get_opt("cursorline"),
        winfixwidth = get_opt("winfixwidth"),
        wrap = get_opt("wrap")
    }
end

---@param win integer
---@param settings WinSettings
local function WinSettings_apply(win, settings)

    ---@param name string
    ---@param value any
    local function set_opt(name, value)
        vim.api.nvim_set_option_value(name, value, { win = win })
    end

    for opt_name, opt_value in pairs(settings) do
        if opt_value ~= nil then
            set_opt(opt_name, opt_value)
        end
    end
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

---@class Sidebar
---@field gs GlobalState
---@field deleted boolean
---@field win integer
---@field win_dir "left" | "right"
---@field win_settings WinSettings
---@field buf integer
---@field source_win integer
---@field visible boolean
---@field symbols_retriever SymbolsRetriever
---@field buf_symbols table<integer, Symbols>
---@field lines table<Symbol, integer>
---@field symbol_display_config table<string, SymbolDisplayConfig>
---@field preview_config PreviewConfig
---@field preview Preview
---@field details DetailsWindow
---@field char_config CharConfig
---@field show_inline_details boolean
---@field show_guide_lines boolean
---@field wrap boolean
---@field auto_resize AutoResizeConfig
---@field fixed_width integer
---@field keymaps KeymapsConfig
---@field symbol_filter SymbolFilter

---@return Sidebar
local function sidebar_new_obj()
    return {
        gs = GlobalState_new(),
        deleted = false,
        win = -1,
        win_dir = "right",
        win_settings = WinSettings_new(),
        buf = -1,
        source_win = -1,
        visible = false,
        symbols_cache = SymbolsCache_new(),
        buf_symbols = vim.defaulttable(Symbols_new),
        lines = {},
        symbol_display_config = {},
        preview = preview_new_obj(),
        details = details_window_new_obj(),
        char_config = cfg.default.sidebar.chars,
        show_inline_details = false,
        show_guide_lines = false,
        wrap = false,
        auto_resize = vim.deepcopy(cfg.default.sidebar.auto_resize, true),
        fixed_width = cfg.default.sidebar.fixed_width,
        keymaps = cfg.default.sidebar.keymaps,
        symbol_state = {},
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
---@return Symbols
local function sidebar_current_symbols(sidebar)
    local source_buf = sidebar_source_win_buf(sidebar)
    assert(source_buf ~= -1)
    local symbols = sidebar.buf_symbols[source_buf]
    symbols.buf = source_buf
    return symbols
end

---@parm sidebar Sidebar
---@param symbols Symbols
local function sidebar_replace_current_symbols(sidebar, symbols)
    assert(symbols.buf ~= -1, "symbols.buf has to be set")
    sidebar.buf_symbols[symbols.buf] = symbols
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

---@param sidebar Sidebar
---@param buf_lines string[] | nil
local function sidebar_refresh_size(sidebar, buf_lines)
    if sidebar.visible then
        if buf_lines == nil then
            buf_lines = vim.api.nvim_buf_get_lines(sidebar.buf, 0, -1, false)
        end
        local vert_resize = sidebar.fixed_width
        if sidebar.auto_resize.enabled then
            local max_line_len = 0
            for _, line in ipairs(buf_lines) do
                max_line_len = math.max(max_line_len, #line)
            end
            vert_resize = max_line_len + 1
            vert_resize = math.max(sidebar.auto_resize.min_width, vert_resize)
            vert_resize = math.min(sidebar.auto_resize.max_width, vert_resize)
        end
        local original_win = vim.api.nvim_get_current_win()
        vim.api.nvim_set_current_win(sidebar.win)
        vim.cmd("vertical resize " .. tostring(vert_resize))
        vim.api.nvim_set_current_win(original_win)
    end
end

---@param dir OpenDirection
---@return "left" | "right"
local function find_split_direction(dir)
    if dir == "left" or dir == "right" then
        return dir
    end

    -- TODO: ignore floating windows?
    local wins = vim.api.nvim_tabpage_list_wins(0)
    local curr_win = vim.api.nvim_get_current_win()
    if dir == "try-left" then
        return (wins[1] == curr_win and "left") or "right"
    elseif dir == "try-right" then
        return (wins[#wins] == curr_win and "right") or "left"
    end

    assert(false, "invalid dir")
end

---@param sidebar Sidebar
---@return integer, "left" | "right"
local function sidebar_open_bare_win(sidebar)
    local dir = find_split_direction(sidebar.gs.settings.open_direction)
    local width = sidebar.fixed_width
    local dir_cmd = (dir == "left" and "leftabove") or "rightbelow"
    vim.cmd("vertical " .. dir_cmd .. " " .. tostring(width) .. "split")
    return vim.api.nvim_get_current_win(), dir
end

local function sidebar_open(sidebar)
    if sidebar.visible then return end

    local original_win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(sidebar.source_win)
    sidebar.win, sidebar.win_dir = sidebar_open_bare_win(sidebar)
    vim.api.nvim_set_current_win(original_win)
    vim.api.nvim_win_set_buf(sidebar.win, sidebar.buf)

    sidebar.win_settings = WinSettings_get(sidebar.win)
    WinSettings_apply(
        sidebar.win,
        {
            number = false,
            relativenumber = false,
            signcolumn = "no",
            cursorline = true,
            winfixwidth = true,
            wrap = sidebar.wrap,
        }
    )

    sidebar.visible = true
    sidebar_refresh_size(sidebar, nil)
    vim.cmd("wincmd =")
end

---@param sidebar Sidebar
local function sidebar_preview_close(sidebar)
    preview_close(sidebar.preview)
end

--- Restore window state to default. Useful when opening a file in the sidebar window.
---@param sidebar Sidebar
local function sidebar_win_restore(sidebar)
    sidebar_preview_close(sidebar)
    details_close(sidebar.details)
    WinSettings_apply(sidebar.win, sidebar.win_settings)
    reset_cursor(sidebar.gs.cursor)
    sidebar.visible = false
    sidebar.win = -1
    vim.cmd("wincmd =")
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
---@return Symbol, SymbolState
local function sidebar_current_symbol(sidebar)
    assert(vim.api.nvim_win_is_valid(sidebar.win))

    local symbols = sidebar_current_symbols(sidebar)

    ---@param symbol Symbol
    ---@param num integer
    ---@return Symbol, integer
    local function _find_symbol(symbol, num)
        if num == 0 then return symbol, 0 end
        if symbols.states[symbol].folded then
            return symbol, num
        end
        for _, sym in ipairs(symbol.children) do
            if symbols.states[sym].visible then
                local s
                s, num = _find_symbol(sym, num - 1)
                if num <= 0 then return s, 0 end
            end
        end
        return symbol, num
    end

    local line = vim.api.nvim_win_get_cursor(sidebar.win)[1]
    local s, _ = _find_symbol(symbols.root, line)
    return s, symbols.states[s]
end

---@param symbols Symbols
---@return table<Symbol, integer>
local function get_line_for_each_symbol(symbols)
    local lines = {}

    ---@param symbol Symbol
    ---@param line integer
    local function get_lines(symbol, line)
        if symbols.states[symbol].folded then return line end
        for _, child in ipairs(symbol.children) do
            if symbols.states[child].visible then
                lines[child] = line
                line = get_lines(child, line + 1)
            end
        end
        return line
    end

    get_lines(symbols.root, 1)

    return lines
end

---@param symbols Symbols
---@param chars CharConfig
---@param show_guide_lines boolean
---@return string[], Highlight[]
local function sidebar_get_buf_lines_and_highlights(symbols, chars, show_guide_lines)
    ---@return boolean
    local function check_if_any_folded()
        for _, symbol in ipairs(symbols.root.children) do
            if symbols.states[symbol].visible_children > 0 then
                return true
            end
        end
        return false
    end
    local any_folded = check_if_any_folded()

    local buf_lines = {}
    local highlights = {}

    local ft = vim.api.nvim_get_option_value("filetype", { buf = symbols.buf })
    local symbol_display_config = cfg.symbols_display_config(symbols.provider_config, symbols.provider, ft)

    ---@param symbol Symbol
    ---@param indent string
    ---@param line_nr integer
    ---@return integer
    local function get_buf_lines_and_highlights(symbol, indent, line_nr)
        if symbols.states[symbol].folded then return line_nr end
        for sym_i, sym in ipairs(symbol.children) do
            local state = symbols.states[sym]
            if state.visible then
                local prefix
                if state.visible_children == 0 then
                    if show_guide_lines and sym.level > 1 then
                        if sym_i == #symbol.children then
                            prefix = chars.guide_last_item .. " "
                        else
                            prefix = chars.guide_middle_item .. " "
                        end
                    else
                        if any_folded then
                            prefix = "  "
                        else
                            prefix = " "
                        end
                    end
                elseif state.folded then
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
        end
        return line_nr
    end

    get_buf_lines_and_highlights(symbols.root, "", 1)
    return buf_lines, highlights
end

---@param sidebar Sidebar
---@param symbol Symbol
local function move_cursor_to_symbol(sidebar, symbol)
    assert(vim.api.nvim_win_is_valid(sidebar.win))
    local line = sidebar.lines[symbol]
    vim.api.nvim_win_set_cursor(sidebar.win, { line, 0 })
end

---@param symbols Symbols
---@return string[]
local function sidebar_get_inline_details(symbols)
    local details = {}

    ---@param symbol Symbol
    local function get_details(symbol)
        if symbols.states[symbol].folded then return end
        for _, child in ipairs(symbol.children) do
            if symbols.states[child].visible then
                table.insert(details, child.detail)
                get_details(child)
            end
        end
    end

    get_details(symbols.root)
    return details
end

---@param buf integer
---@param details string[]
local function sidebar_add_inline_details(buf, details)
    for line, detail in ipairs(details) do
        vim.api.nvim_buf_set_extmark(
            buf, SIDEBAR_EXT_NS, line-1, -1,
            {
                virt_text = { { detail, "Comment" } },
                virt_text_pos = "eol",
                hl_mode = "combine",
            }
        )
    end
end

---@param sidebar Sidebar
local function sidebar_refresh_view(sidebar)
    local symbols = sidebar_current_symbols(sidebar)

    local buf_lines, highlights = sidebar_get_buf_lines_and_highlights(
        symbols, sidebar.char_config, sidebar.show_guide_lines
    )

    sidebar.lines = get_line_for_each_symbol(symbols)

    buf_set_content(sidebar.buf, buf_lines)

    for _, hl in ipairs(highlights) do
        highlight_apply(sidebar.buf, hl)
    end

    if sidebar.show_inline_details then
        local details = sidebar_get_inline_details(symbols)
        sidebar_add_inline_details(sidebar.buf, details)
    end

    sidebar_refresh_size(sidebar, buf_lines)
end

---@param sidebar Sidebar
local function sidebar_refresh_symbols(sidebar)
    ---@return Symbol?
    local function _find_symbol_with_name(symbol, name)
        for _, sym in ipairs(symbol.children) do
            if sym.name == name then return sym end
        end
        return nil
    end

    ---@param old_symbols Symbols
    ---@param new_symbols Symbols
    local function preserve_folds(old_symbols, new_symbols)
        ---@param old Symbol
        ---@param new Symbol
        local function _preserve_folds(old, new)
            if old.level > 0 and old_symbols.states[old].folded then return end
            for _, new_sym in ipairs(new.children) do
                local old_sym = _find_symbol_with_name(old, new_sym.name)
                if old_sym ~= nil then
                    new_symbols.states[new_sym].folded = old_symbols.states[old_sym].folded
                    _preserve_folds(old_sym, new_sym)
                end
            end
        end

        _preserve_folds(old_symbols.root, new_symbols.root)
        new_symbols.states[new_symbols.root].folded = false
    end

    ---@param new_root Symbol
    local function _refresh_sidebar(new_root, provider, provider_config)
        local current_symbols = sidebar_current_symbols(sidebar)
        local new_symbols = Symbols_new()
        new_symbols.provider = provider
        new_symbols.provider_config = provider_config
        new_symbols.buf = sidebar_source_win_buf(sidebar)
        new_symbols.root = new_root
        new_symbols.states = SymbolStates_build(new_root)
        preserve_folds(current_symbols, new_symbols)
        Symbols_apply_filter(new_symbols, sidebar.symbol_filter)
        sidebar_replace_current_symbols(sidebar, new_symbols)
        sidebar_refresh_view(sidebar)
    end

    local buf = sidebar_source_win_buf(sidebar)
    SymbolsRetriever_retrieve(sidebar.symbols_retriever, buf, _refresh_sidebar)
end

---@param symbols Symbols
---@param start_symbol Symbol
---@param value boolean
---@return integer
local function symbol_change_folded_rec(symbols, start_symbol, value)

    ---@param symbol Symbol
    local function _change_folded_rec(symbol)
        local symbol_state = symbols.states[symbol]
        local changes = (symbol_state.folded ~= value and #symbol.children > 0 and 1) or 0
        symbol_state.folded = value
        for _, sym in ipairs(symbol.children) do
            changes = changes + _change_folded_rec(sym)
        end
        return changes
    end

    return _change_folded_rec(start_symbol)
end

---@param sidebar Sidebar
local function sidebar_goto_symbol(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    vim.api.nvim_set_current_win(sidebar.source_win)
    vim.api.nvim_win_set_cursor(
        sidebar.source_win,
        { symbol.selectionRange.start.line + 1, symbol.selectionRange.start.character }
    )
    vim.fn.win_execute(sidebar.source_win, "normal! zz")
    local r = symbol.range
    flash_highlight(sidebar.source_win, 400, 1)
end

---@param sidebar Sidebar
local function _sidebar_preview_open_params(sidebar)
    ---@return PreviewOpenParams
    return function()
        ---@type PreviewOpenParams
        local obj = {
            source_win = sidebar.source_win,
            source_buf = sidebar_source_win_buf(sidebar),
            cursor = vim.api.nvim_win_get_cursor(sidebar.win),
            symbol = sidebar_current_symbol(sidebar),
            config = sidebar.preview_config,
            sidebar_win = sidebar.win,
            sidebar_side = sidebar.win_dir,
        }
        return obj
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
        local symbol, symbol_state = sidebar_current_symbol(sidebar)
        return {
            sidebar_win = sidebar.win,
            sidebar_side = sidebar.win_dir,
            symbol = symbol,
            symbol_state = symbol_state,
            symbol_display_config = sidebar.symbol_display_config,
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
    local _, state = sidebar_current_symbol(sidebar)
    state.folded = false
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold(sidebar)
    local symbol, state = sidebar_current_symbol(sidebar)
    if symbol.level > 1 and (state.folded or #symbol.children == 0) then
        symbol = symbol.parent
        assert(symbol ~= nil)
    end
    state.folded = true
    sidebar_refresh_view(sidebar)
    move_cursor_to_symbol(sidebar, symbol)
end

---@param sidebar Sidebar
local function sidebar_unfold_recursively(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    local symbol, _ = sidebar_current_symbol(sidebar)
    symbol_change_folded_rec(symbols, symbol, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_recursively(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    local symbol = sidebar_current_symbol(sidebar)
    local changes = symbol_change_folded_rec(symbols, symbol, true)
    if changes == 0 then
        while(symbol.level > 1) do
            symbol = symbol.parent
            assert(symbol ~= nil)
        end
        symbol_change_folded_rec(symbols, symbol, true)
    end
    sidebar_refresh_view(sidebar)
    move_cursor_to_symbol(sidebar, symbol)
end


---@param symbols Symbols
---@param level integer
---@param value boolean
local function _change_fold_at_level(symbols, level, value)
    local function change_fold(symbol)
        local state = symbols.states[symbol]
        if symbol.level == level then state.folded = value end
        if symbol.level >= level then return end
        for _, sym in ipairs(symbol.children) do
            change_fold(sym)
        end
    end

    change_fold(symbols.root)
end

---@param sidebar Sidebar
local function sidebar_unfold_one_level(sidebar)

    local symbols = sidebar_current_symbols(sidebar)

    ---@param symbol Symbol
    ---@return integer
    local function find_level_to_unfold(symbol)
        local MAX_LEVEL = 100000

        if symbol.level ~= 0 and symbols.states[symbol].folded then
            return symbol.level
        end

        local min_level = MAX_LEVEL
        for _, sym in ipairs(symbol.children) do
            min_level = math.min(min_level, find_level_to_unfold(sym))
        end

        return min_level
    end

    local level = find_level_to_unfold(symbols.root)
    _change_fold_at_level(symbols, level, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_one_level(sidebar)
    local symbols = sidebar_current_symbols(sidebar)

    ---@param symbol Symbol
    ---@return integer
    local function find_level_to_fold(symbol)
        local max_level = (symbols.states[symbol].folded and 1) or symbol.level
        for _, sym in ipairs(symbol.children) do
            if #sym.children > 0 then
                max_level = math.max(max_level, find_level_to_fold(sym))
            end
        end
        return max_level
    end

    local level = find_level_to_fold(symbols.root)
    _change_fold_at_level(symbols, level, true)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_unfold_all(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    symbol_change_folded_rec(symbols, symbols.root, false)
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_fold_all(sidebar)
    local symbols = sidebar_current_symbols(sidebar)
    symbol_change_folded_rec(symbols, symbols.root, true)
    symbols.states[symbols.root].folded = false
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_toggle_fold(sidebar)
    local symbol, state = sidebar_current_symbol(sidebar)
    if #symbol.children == 0 then return end
    state.folded = not state.folded
    sidebar_refresh_view(sidebar)
end

---@param sidebar Sidebar
local function sidebar_toggle_details(sidebar)
    sidebar.show_inline_details = not sidebar.show_inline_details
    sidebar_refresh_view(sidebar)
end

local function sidebar_toggle_auto_details(sidebar)
    details_toggle_auto_show(sidebar.details, _sidebar_details_open_params(sidebar))
end

---@param sidebar Sidebar
local function sidebar_toggle_auto_preview(sidebar)
    preview_toggle_auto_show(sidebar.preview, _sidebar_preview_open_params(sidebar))
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
local function sidebar_on_scroll(sidebar)
    if sidebar.details.win ~= -1 then
        details_close(sidebar.details)
        local params = _sidebar_details_open_params(sidebar)()
        details_open(sidebar.details, params)
    end
    if sidebar.preview.win ~= -1 then
        preview_close(sidebar.preview)
        local params = _sidebar_preview_open_params(sidebar)
        preview_open(sidebar.preview, params)
    end
end

---@param sidebar Sidebar
---@param symbols_retriever SymbolsRetriever
---@param num integer
---@param config SidebarConfig
---@param gs GlobalState
---@param debug boolean
local function sidebar_new(sidebar, symbols_retriever, num, config, gs, debug)
    sidebar.deleted = false
    sidebar.source_win = vim.api.nvim_get_current_win()
    sidebar.symbols_retriever = symbols_retriever

    sidebar.gs = gs
    sidebar.preview_config = config.preview
    sidebar.show_inline_details = config.show_inline_details
    sidebar.details.auto_show = config.show_details_pop_up
    sidebar.show_guide_lines = config.show_guide_lines
    sidebar.char_config = config.chars
    sidebar.keymaps = config.keymaps
    sidebar.wrap = config.wrap
    sidebar.auto_resize = vim.deepcopy(config.auto_resize, true)
    sidebar.fixed_width = config.fixed_width
    sidebar.symbol_filter = config.symbol_filter

    sidebar.details.show_debug_info = debug

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
        { "WinScrolled" },
        {
            callback = function() sidebar_on_scroll(sidebar) end,
            buffer = sidebar.buf,
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
    for _, cmd in ipairs(cmds) do
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
    LOG_LEVEL = config.dev.log_level

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

        log.info("symbols.nvim reloaded")
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
        ["show-config"] = show_config,
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
    local symbols = sidebar_current_symbols(sidebar)

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
        if not symbols.states[symbol].folded then
            for _, child in ipairs(symbol.children) do
                lines = lines + count_lines(child)
            end
        end
        return lines
    end

    if target.level == 0 then return end
    local lines = 0
    local current = symbols.root
    while current ~= target do
        symbols.states[current].folded = false
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
    local gs = GlobalState_new()
    gs.cursor.hide = _config.hide_cursor
    gs.settings.open_direction = _config.sidebar.open_direction

    ---@type Provider[]
    local providers = {
        LspProvider,
        VimdocProvider,
        MarkdownProvider,
    }

    local symbols_retriever = SymbolsRetriever_new(providers, _config.providers)

    ---@type Sidebar[]
    local sidebars = {}

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
                sidebar_new(sidebar, symbols_retriever, num, _config.sidebar, gs, _config.dev.enabled)
            end
            sidebar_open(sidebar)
            sidebar_refresh_symbols(sidebar)
        end,
        { desc = "" }
    )

    create_command(
        cmds,
        "SymbolsDebugToggle",
        function()
            _config.dev.enabled = not _config.dev.enabled
            for _, sidebar in ipairs(sidebars) do
                sidebar.details.show_debug_info = _config.dev.enabled
            end
            if _config.dev.enabled then
                LOG_LEVEL = _config.dev.log_level
            else
                LOG_LEVEL = vim.log.levels.ERROR
            end
        end,
        {}
    )

    local string_to_log_level = {
        error = vim.log.levels.ERROR,
        warning = vim.log.levels.WARN,
        info = vim.log.levels.INFO,
        debug = vim.log.levels.DEBUG,
        trace = vim.log.levels.TRACE,
        off = vim.log.levels.off,
    }
    local log_levels = vim.tbl_keys(string_to_log_level)

    create_command(
        cmds,
        "SymbolsDebugLevel",
        function(e)
            local arg = e.fargs[1]
            local new_log_level = string_to_log_level[arg]
            if new_log_level == nil then
                log.error("Invalid log level: " .. arg)
            else
                LOG_LEVEL = new_log_level
            end
        end,
        {
            nargs = 1,
            complete = function(arg, _)
                local suggestions = {}
                for _, log_level in ipairs(log_levels) do
                    if vim.startswith(log_level, arg) then
                        table.insert(suggestions, log_level)
                    end
                end
                return suggestions
            end
        }
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
                local symbols = sidebar_current_symbols(sidebar)
                local pos = to_pos(vim.api.nvim_win_get_cursor(sidebar.source_win))
                local symbol = symbol_at_pos(symbols.root, pos)
                sidebar_set_cursor_at_symbol(sidebar, symbol)
            end
        end,
        {}
    )

    create_command(
        cmds,
        "SymbolsGoTo",
        function() end,
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
        { "BufWritePost", "FileChangedShellPost" },
        {
            group = global_autocmd_group,
            pattern = "*",
            callback = function(t)
                local source_buf = t.buf
                symbols_retriever.cache[source_buf].fresh = false
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
                        sidebar_refresh_symbols(sidebar)
                    end
                end
            end
        }
    )

    vim.api.nvim_create_autocmd(
        { "BufHidden" },
        {
            group = global_autocmd_group,
            pattern = "*",
            callback = function(t)
                local buf = tonumber(t.buf)
                for _, sidebar in ipairs(sidebars) do
                    if sidebar.buf == buf then
                        sidebar_win_restore(sidebar)
                        return
                    end
                end
            end
        }
    )
end

return M
