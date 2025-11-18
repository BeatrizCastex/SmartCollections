--[[--
User plugins are still loaded through main.lua, so this stub bridges the
behaviour expected by the plugin loader with our lightweight init.lua table.
--]]--

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local core = require("init")

local SmartCollections = WidgetContainer:extend{
    name = "smartcollections",
    is_doc_only = false,
}
SmartCollections.description = core.description
SmartCollections.version = core.version
SmartCollections.fullname = core.name

function SmartCollections:init()
    print("[SmartCollections] main.lua SmartCollections:init() called")
    if type(core.init) == "function" then
        core:init()
    end
    print("[SmartCollections] after core:init, menu_item", core.menu_item and "present" or "missing")
    if core.menu_item and self.ui and self.ui.menu then
        print("[SmartCollections] registering to main menu")
        self.ui.menu:registerToMainMenu(self)
    else
        print("[SmartCollections] skipping register, ui/menu/menu_item missing")
    end

    -- Auto-update smart collections once on startup.
    if core.rebuildSmartCollections then
        core:rebuildSmartCollections()
    end
end

function SmartCollections:onSmartCollectionsOpen()
    if core.run then
        core:run(self.ui)
    elseif core.menu_item and core.menu_item.callback then
        core.menu_item.callback()
    end
end

function SmartCollections:onSmartCollectionsSettingsOpen()
    if core.openSettings then
        core:openSettings(self.ui)
    end
end

function SmartCollections:addToMainMenu(menu_items)
    local item = core.menu_item
    if not item then
        print("[SmartCollections] addToMainMenu called without menu_item")
        return
    end
    print("[SmartCollections] addToMainMenu installing entry")

    -- Entry under the Search menu: opens the Smart Collections filter UI.
    menu_items.smartcollections_search = {
        text = item.text,
        sorting_hint = "search",
        callback = function()
            if core.run then
                core:run(self.ui)
            elseif item.callback then
                item.callback()
            end
        end,
    }

    -- Submenu under More tools: settings & debug helpers.
    local sub_items = {}
    if core.settings_item then
        table.insert(sub_items, {
            text = core.settings_item.text,
            callback = function()
                if core.openSettings then
                    core:openSettings(self.ui)
                end
            end,
        })
    end

    if core.debug_item then
        table.insert(sub_items, {
            text = core.debug_item.text,
            callback = function()
                if core.showCustomColumns then
                    core:showCustomColumns(self.ui)
                end
            end,
        })
    end

    if #sub_items > 0 then
        menu_items.smartcollections = {
            text = _("Smart Collections"),
            sorting_hint = "more_tools",
            sub_item_table = sub_items,
        }
    end
end

return SmartCollections
