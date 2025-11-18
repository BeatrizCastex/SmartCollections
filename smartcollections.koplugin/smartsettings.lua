local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local SmartSettings = {}

local settings_path = DataStorage:getSettingsDir() .. "/smartcollections_settings.lua"

function SmartSettings:_open()
    return LuaSettings:open(settings_path)
end

-- Returns a map: { [colname] = true/false, ... }
function SmartSettings:get_enabled_columns_map()
    local store = self:_open()
    local raw = store:readSetting("enabled_custom_columns") or {}
    local map = {}
    -- Accept both map and array shapes.
    for k, v in pairs(raw) do
        if type(k) == "string" and v then
            map[k] = true
        elseif type(k) == "number" and type(v) == "string" then
            map[v] = true
        end
    end
    return map
end

function SmartSettings:set_enabled_columns_map(map)
    local store = self:_open()
    store:saveSetting("enabled_custom_columns", map or {})
    store:flush()
end

return SmartSettings

