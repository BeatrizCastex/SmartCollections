local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local BookList = require("ui/widget/booklist")
local TextViewer = require("ui/widget/textviewer")
local SmartManager = require("smartmanager")
local MetaIndex = require("metadataindex")
local FilterUI = require("filterui")
local util = require("util")
local _ = require("gettext")

local ResultsView = {}

-- books: array of normalized book tables from MetaIndex
-- filters: the filters table used (for smart collections)
function ResultsView:show(books, filters)
    if not books or #books == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Smart Collections: no books matched these filters."),
        })
        return
    end

    local items = {}
    local paths = {}
    local by_path = {}

    for _, book in ipairs(books) do
        local path = book.path
        if path then
            local title = book.title
            local authors = ""
            if book.authors and #book.authors > 0 then
                authors = table.concat(book.authors, ", ")
            end
            local text
            if title and title ~= "" then
                if authors ~= "" then
                    text = string.format("%s - %s", title, authors)
                else
                    text = title
                end
            else
                text = path:gsub(".*/", "")
            end
            table.insert(items, {
                text = text,
                file = path,
            })
            table.insert(paths, path)
            by_path[path] = book
        end
    end

    if #items == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Smart Collections: matches have no usable file paths."),
        })
        return
    end

    local ReaderUI = require("apps/reader/readerui")

    local menu
    menu = BookList:new{
        title = _("Smart Collections results"),
        item_table = items,
        onMenuSelect = function(_, item)
            UIManager:close(menu)
            if item.file then
                ReaderUI:showReader(item.file)
            end
        end,
        onMenuHold = function(menu_widget, item)
            local book = by_path[item.file]
            if not book then return end

            local lines = {}
            if book.title and book.title ~= "" then
                table.insert(lines, _("Title:") .. " " .. tostring(book.title))
            end
            if book.authors and #book.authors > 0 then
                table.insert(lines, _("Author(s):") .. " " .. table.concat(book.authors, ", "))
            end
            if book.series and type(book.series) == "string" and book.series ~= "" then
                table.insert(lines, _("Series:") .. " " .. book.series)
            end
            if book.tags and #book.tags > 0 then
                table.insert(lines, _("Tags:") .. " " .. table.concat(book.tags, ", "))
            end
            local comments = book.comments
            if type(comments) == "string" then
                comments = util.htmlToPlainTextIfHtml(comments)
            end
            if comments and comments ~= "" then
                table.insert(lines, "")
                table.insert(lines, comments)
            end
            local text = table.concat(lines, "\n")

            UIManager:show(TextViewer:new{
                title = _("Smart Collections results"),
                text = text,
                text_type = "book_info",
            })
        end,
        onLeftButtonTap = function()
            ResultsView:showSaveDialog(paths, filters, books)
        end,
        title_bar_left_icon = "plus",
    }

    UIManager:show(menu)
end

function ResultsView:showSaveDialog(paths, filters, books)
    local dialog
    dialog = InputDialog:new{
        title = _("Save results as collection"),
        input = "",
        input_hint = _("Collection name"),
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
                    text = _("Refine search"),
                    callback = function()
                        UIManager:close(dialog)
                        FilterUI:open(function(new_filters)
                            new_filters = new_filters or {}
                            local refined = {}
                            for _, book in ipairs(books or {}) do
                                if MetaIndex:matches(book, new_filters) then
                                    table.insert(refined, book)
                                end
                            end
                            ResultsView:show(refined, new_filters)
                        end, filters or {}, { books = books })
                    end,
                },
            },
            {
                {
                    text = _("Save static"),
                    callback = function()
                        local name = dialog:getInputText()
                        UIManager:close(dialog)
                        if name and name ~= "" then
                            SmartManager:save_static_collection(name, paths)
                            UIManager:show(InfoMessage:new{
                                text = _("Smart Collections: static collection saved."),
                            })
                        end
                    end,
                },
                {
                    text = _("Save smart"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText()
                        UIManager:close(dialog)
                        if name and name ~= "" then
                            SmartManager:save_static_collection(name, paths)
                            SmartManager:save_smart_definition(name, filters, paths)
                            UIManager:show(InfoMessage:new{
                                text = _("Smart Collections: smart collection saved."),
                            })
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return ResultsView
