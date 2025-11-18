local UIManager = require("ui/uimanager")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local _ = require("gettext")
local FilterDetails = require("filterdetails")
local MetaIndex = require("metadataindex")

local FilterUI = {}

-- on_done(filters) will be called with a filters table suitable for MetaIndex:filterBooks.
-- filters is an optional table to prefill values; reused across main + details dialogs.
-- context may contain e.g. { books = { normalized book tables } } to compute top hints from current results.
function FilterUI:open(on_done, filters, context)
    filters = filters or {}
    context = context or {}

    local include_hint = _("fluff, fantasy, romance")
    local exclude_hint = _("angst, incomplete")
    local include_desc = _("Tags to include")
    local exclude_desc = _("Tags to exclude")

    local ok, top_tags = pcall(function()
        return MetaIndex.getTopTags and MetaIndex:getTopTags(10, context.books) or {}
    end)
    if ok and top_tags and #top_tags > 0 then
        local top_str = table.concat(top_tags, ", ")
        include_desc = _("Top tags: ") .. top_str .. "\n\n" .. include_desc
    end

    -- Tags are edited here; other fields live in the "More filters…" screen.
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Smart Collections – filter"),
        fields = {
            {
                description = include_desc,
                text = filters.include_tags or "",
                hint = include_hint,
            },
            {
                description = exclude_desc,
                text = filters.exclude_tags or "",
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
                    text = _("More filters…"),
                    callback = function()
                        local fields = dialog:getFields()
                        filters.include_tags = fields[1] or ""
                        filters.exclude_tags = fields[2] or ""
                        UIManager:close(dialog)

                        -- Open the details screen; when it returns, reopen main dialog.
                        FilterDetails:open(filters, function(updated)
                            FilterUI:open(on_done, updated, context)
                        end, context)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        filters.include_tags = fields[1] or ""
                        filters.exclude_tags = fields[2] or ""
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

return FilterUI
