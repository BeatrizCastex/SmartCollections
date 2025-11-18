local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")

local MetaIndex = require("metadataindex")
local SmartSettings = require("smartsettings")

local SettingsUI = {}

function SettingsUI:open()
    MetaIndex:invalidate()
    local cols = MetaIndex:getCustomColumns() or {}
    if #cols == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No Calibre custom columns detected in metadata."),
        })
        return
    end

    local enabled_map = SmartSettings:get_enabled_columns_map()
    local menu

    local function refresh()
        local items = {}
        for i, col in ipairs(cols) do
            local name = col.name
            local text = name
            if col.hierarchical then
                text = text .. " (" .. _("hierarchical") .. ")"
            end
            local is_enabled = enabled_map[name] and true or false
            table.insert(items, {
                text = text,
                mandatory = is_enabled and "✓" or "",
                callback = function()
                    enabled_map[name] = not is_enabled and true or nil
                    SmartSettings:set_enabled_columns_map(enabled_map)
                    refresh()
                end,
            })
        end

        table.insert(items, {
            text = _("Done"),
            callback = function()
                if menu then UIManager:close(menu) end
            end,
        })

        if menu then
            local current_page = menu.page or 1
            local perpage = menu.perpage or #items
            local itemnumber = (current_page - 1) * perpage + 1
            if itemnumber > #items then
                itemnumber = #items
            end
            menu:switchItemTable(_("Smart Collections – custom columns"), items, itemnumber)
        else
            menu = Menu:new{
                title = _("Smart Collections – custom columns"),
                item_table = items,
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
    end

    refresh()
end

return SettingsUI
