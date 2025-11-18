local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local Dispatcher = require("dispatcher")

local FilterUI = require("filterui")
local MetaIndex = require("metadataindex")
local ResultsView = require("resultsview")
local SmartManager = require("smartmanager")

local Plugin = {
    name = "Smart Collections",
    version = "0.1",
    description = "Advanced metadata filtering + auto-updating shelves",
}

-- Expose a Dispatcher action so Smart Collections can be bound
-- to gestures/hotkeys without modifying KOReader core files.
Dispatcher:registerAction("smartcollections_filter", {
    category = "none",
    event = "SmartCollectionsOpen",
    title = _("Smart Collections filter"),
    general = true,
    filemanager = true,
})

Dispatcher:registerAction("smartcollections_settings", {
    category = "none",
    event = "SmartCollectionsSettingsOpen",
    title = _("Smart Collections settings"),
    general = true,
    filemanager = true,
})

function Plugin:init()
    print("[SmartCollections] init.lua init() running")
    self.menu_item = {
        text = _("Smart Collections"),
    }

    -- Optional debug helper: show discovered Calibre custom columns.
    self.debug_item = {
        text = _("Smart Collections: show custom columns"),
    }
    -- Settings entry: choose which custom columns are filterable.
    self.settings_item = {
        text = _("Smart Collections: settings"),
    }
end

-- Entry point from the FileManager UI.
function Plugin:run(ui)
    FilterUI:open(function(filters)
        MetaIndex:invalidate()
        local books = MetaIndex:filterBooks(filters or {})
        ResultsView:show(books, filters or {})
    end, nil, nil)
end

-- Rebuild all smart collections by re-running their saved filters.
function Plugin:rebuildSmartCollections()
    local defs = SmartManager:get_definitions()
    if not defs or next(defs) == nil then
        return
    end

    MetaIndex:invalidate()
    for name, def in pairs(defs) do
        local ok, books = pcall(function()
            return MetaIndex:filterBooks(def.filters or {})
        end)
        if ok and books and #books > 0 then
            local paths = {}
            for _, book in ipairs(books) do
                if book.path then
                    table.insert(paths, book.path)
                end
            end
            if #paths > 0 then
                SmartManager:save_static_collection(name, paths)
                SmartManager:save_smart_definition(name, def.filters or {}, paths)
            end
        end
    end
end

function Plugin:showCustomColumns()
    MetaIndex:invalidate()
    local cols = MetaIndex:getCustomColumns() or {}
    local lines = {}
    for i, col in ipairs(cols) do
        local label = col.name or "?"
        if col.hierarchical then
            label = label .. " (" .. _("hierarchical") .. ")"
        end
        if col.numeric then
            label = label .. " (" .. _("numeric") .. ")"
        end
        table.insert(lines, label)
    end
    local msg
    if #lines == 0 then
        msg = _("No Calibre custom columns detected in metadata.")
    else
        msg = _("Calibre custom columns detected:\n") .. table.concat(lines, "\n")
    end
    UIManager:show(InfoMessage:new{
        text = msg,
    })
end

function Plugin:openSettings()
    local ok, SettingsUI = pcall(require, "settingsui")
    if not ok or not SettingsUI or type(SettingsUI.open) ~= "function" then
        UIManager:show(InfoMessage:new{
            text = _("Smart Collections: settings UI not available."),
        })
        return
    end
    SettingsUI:open()
end

return Plugin
