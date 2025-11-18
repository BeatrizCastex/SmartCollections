local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local MetaIndex = require("metadataindex")
local SmartSettings = require("smartsettings")

local FilterDetails = {}

local function summarize_list(str)
    if not str or str == "" then
        return _("(none)")
    end
    -- Show only first few entries to keep it compact.
    local parts = {}
    for part in string.gmatch(str, "[^,]+") do
        local trimmed = part:gsub("^%s*", ""):gsub("%s*$", "")
        if trimmed ~= "" then
            table.insert(parts, trimmed)
            if #parts >= 2 then
                break
            end
        end
    end
    local summary = table.concat(parts, ", ")
    if str:match(".+,.+,.+") then
        summary = summary .. ", …"
    end
    return summary
end

local function summarize_custom_rule(rule)
    if not rule or type(rule) ~= "table" then
        return _("(none)")
    end
    if rule.op and rule.value then
        return string.format("%s %s", tostring(rule.op), tostring(rule.value))
    end
    local src = ""
    if rule.include then
        if type(rule.include) == "string" then
            src = rule.include
        elseif type(rule.include) == "table" then
            src = table.concat(rule.include, ", ")
        end
    elseif rule.exclude then
        if type(rule.exclude) == "string" then
            src = rule.exclude
        elseif type(rule.exclude) == "table" then
            src = table.concat(rule.exclude, ", ")
        end
    end
    if src == "" then
        return _("(none)")
    end
    return summarize_list(src)
end

local function open_authors_dialog(filters, on_done)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Authors filter"),
        fields = {
            {
                description = _("Authors to include"),
                text = filters.include_authors or "",
                hint = _("Jane Austen, Charles Dickens"),
            },
            {
                description = _("Authors to exclude"),
                text = filters.exclude_authors or "",
                hint = _("Some Author"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        filters.include_authors = fields[1] or ""
                        filters.exclude_authors = fields[2] or ""
                        UIManager:close(dialog)
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function open_numeric_custom_dialog(col, filters, on_done)
    filters.custom = filters.custom or {}
    local existing = filters.custom[col.name]
    local initial = ""
    if existing and existing.op and existing.value then
        initial = string.format("%s %s", tostring(existing.op), tostring(existing.value))
    elseif existing and existing.include and type(existing.include) == "string" then
        initial = existing.include
    end

    local dialog
    dialog = InputDialog:new{
        title = _("Filter for ") .. col.name,
        input = initial,
        input_hint = _("e.g. >= 10000"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        filters.custom[col.name] = nil
                        UIManager:close(dialog)
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText() or ""
                        UIManager:close(dialog)
                        text = text:gsub("^%s*(.-)%s*$", "%1")
                        if text == "" then
                            filters.custom[col.name] = nil
                            if on_done then
                                on_done(filters)
                            end
                            return
                        end

                        local op, num_str = text:match("^([<>]=?)%s*([%d,%.%,%s]+)$")
                        if not op then
                            local bare = text:match("^=%s*([%d,%.%,%s]+)$")
                            if bare then
                                op, num_str = "=", bare
                            else
                                bare = text:match("^([%d,%.%,%s]+)$")
                                if bare then
                                    op, num_str = "=", bare
                                end
                            end
                        end

                        if op and num_str then
                            local cleaned = num_str:gsub("[,%s]", "")
                            local val = tonumber(cleaned)
                            if val then
                                filters.custom[col.name] = { op = op, value = val }
                                if on_done then
                                    on_done(filters)
                                end
                                return
                            end
                        end

                        -- Fallback: treat as simple string include on the column value.
                        filters.custom[col.name] = { include = text }
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function open_text_custom_dialog(col, filters, on_done, context)
    filters.custom = filters.custom or {}
    local existing = filters.custom[col.name] or {}
    local include_text = ""
    local exclude_text = ""
    local include_hint = _("comma separated")
    local exclude_hint = _("comma separated")
    local include_desc = _("Values to include")
    local exclude_desc = _("Values to exclude")

    local ok, top_values = pcall(function()
        local books = context and context.books or nil
        return MetaIndex.getTopCustomValues and MetaIndex:getTopCustomValues(col.name, 10, books) or {}
    end)
    if ok and top_values and #top_values > 0 then
        local top_str = table.concat(top_values, ", ")
        include_desc = _("Top values: ") .. top_str .. "\n\n" .. include_desc
    end
    if existing.include then
        if type(existing.include) == "string" then
            include_text = existing.include
        elseif type(existing.include) == "table" then
            include_text = table.concat(existing.include, ", ")
        end
    end
    if existing.exclude then
        if type(existing.exclude) == "string" then
            exclude_text = existing.exclude
        elseif type(existing.exclude) == "table" then
            exclude_text = table.concat(existing.exclude, ", ")
        end
    end

    local dialog
    dialog = MultiInputDialog:new{
        title = _("Custom column: ") .. col.name,
        fields = {
            {
                description = include_desc,
                text = include_text,
                hint = include_hint,
            },
            {
                description = exclude_desc,
                text = exclude_text,
                hint = exclude_hint,
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        UIManager:close(dialog)
                        local inc = fields[1] or ""
                        local exc = fields[2] or ""
                        if inc == "" and exc == "" then
                            filters.custom[col.name] = nil
                        else
                            filters.custom[col.name] = {
                                include = inc,
                                exclude = exc,
                            }
                        end
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function open_custom_columns_dialog(filters, on_done, context)
    MetaIndex:invalidate()
    local cols = MetaIndex:getCustomColumns() or {}
    local enabled_map = SmartSettings:get_enabled_columns_map()

    local enabled = {}
    for _, col in ipairs(cols) do
        if enabled_map[col.name] then
            table.insert(enabled, col)
        end
    end

    if #enabled == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No enabled custom columns available. Configure them in Smart Collections settings."),
        })
        return
    end

    filters.custom = filters.custom or {}

    local menu
    local function build_items()
        local items = {}
        for idx, col in ipairs(enabled) do
            local rule = filters.custom[col.name]
            local label = col.name
            if col.hierarchical then
                label = label .. " (" .. _("hierarchical") .. ")"
            end
            if col.numeric then
                label = label .. " (" .. _("numeric") .. ")"
            end
            table.insert(items, {
                text = label,
                mandatory = summarize_custom_rule(rule),
                callback = function()
                    if col.numeric then
                        open_numeric_custom_dialog(col, filters, function(updated)
                            filters = updated or filters
                            menu:switchItemTable(_("Custom columns"), build_items(), menu.item_index or 1)
                        end)
                    else
                        open_text_custom_dialog(col, filters, function(updated)
                            filters = updated or filters
                            menu:switchItemTable(_("Custom columns"), build_items(), menu.item_index or 1)
                        end, context)
                    end
                end,
            })
        end
        table.insert(items, {
            text = _("Done"),
            callback = function()
                UIManager:close(menu)
                if on_done then
                    on_done(filters)
                end
            end,
        })
        return items
    end

    menu = Menu:new{
        title = _("Custom columns"),
        item_table = build_items(),
        is_popout = false,
        onMenuSelect = function(_, item)
            if item.callback then
                item.callback()
            end
        end,
    }
    UIManager:show(menu)
end

local function open_series_dialog(filters, on_done)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Series filter"),
        fields = {
            {
                description = _("Series to include"),
                text = filters.include_series or "",
                hint = _("Anne of Green Gables, Discworld"),
            },
            {
                description = _("Series to exclude"),
                text = filters.exclude_series or "",
                hint = _("Some Series"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        filters.include_series = fields[1] or ""
                        filters.exclude_series = fields[2] or ""
                        UIManager:close(dialog)
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function open_status_dialog(filters, on_done)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Status filter"),
        fields = {
            {
                description = _("Status (comma separated)"),
                text = filters.status or "",
                hint = _("new, reading, finished, on hold"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        filters.status = fields[1] or ""
                        UIManager:close(dialog)
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

local function open_collections_dialog(filters, on_done)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Collections filter"),
        fields = {
            {
                description = _("Collections to include"),
                text = filters.include_collections or "",
                hint = _("Favorites, My Shelf"),
            },
            {
                description = _("Collections to exclude"),
                text = filters.exclude_collections or "",
                hint = _("Archive"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        filters.include_collections = fields[1] or ""
                        filters.exclude_collections = fields[2] or ""
                        UIManager:close(dialog)
                        if on_done then
                            on_done(filters)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FilterDetails:open(filters, on_done, context)
    filters = filters or {}

    local items = {
        {
            text = _("Authors…"),
            mandatory = summarize_list(filters.include_authors),
            callback = function()
                open_authors_dialog(filters)
            end,
        },
        {
            text = _("Series…"),
            mandatory = summarize_list(filters.include_series),
            callback = function()
                open_series_dialog(filters)
            end,
        },
        {
            text = _("Status…"),
            mandatory = summarize_list(filters.status),
            callback = function()
                open_status_dialog(filters)
            end,
        },
        {
            text = _("Collections…"),
            mandatory = summarize_list(filters.include_collections),
            callback = function()
                open_collections_dialog(filters)
            end,
        },
        {
            text = _("Custom columns…"),
            mandatory = filters.custom and _("(configured)") or _("(none)"),
            callback = function()
                open_custom_columns_dialog(filters, on_done, context)
            end,
        },
        {
            text = _("Done"),
            callback = function()
                UIManager:close(self.menu)
                if on_done then
                    on_done(filters)
                end
            end,
        },
    }

    local menu = Menu:new{
        title = _("More filters"),
        item_table = items,
        -- Use standard full-screen menu style (no popup rounding).
        is_popout = false,
        onMenuSelect = function(_, item)
            if item.callback then
                item.callback()
            end
        end,
    }
    self.menu = menu
    UIManager:show(menu)
end

return FilterDetails
