local DataStorage = require("datastorage")
local ReadCollection = require("readcollection")
local ffiUtil = require("ffi/util")

local SmartManager = {}

local smart_file = DataStorage:getSettingsDir() .. "/smartcollections.lua"

local function read_smart_defs()
    local ok, data = pcall(dofile, smart_file)
    if ok and type(data) == "table" then
        return data
    end
    return {}
end

local function write_smart_defs(tbl)
    local f, err = io.open(smart_file, "w")
    if not f then
        return nil, err
    end
    f:write("return ")
    f:write(require("dump")(tbl))
    f:write("\n")
    f:close()
    return true
end

-- Save a static collection with the given name and paths.
function SmartManager:save_static_collection(name, paths)
    if not name or name == "" or not paths or #paths == 0 then
        return
    end

    ReadCollection:removeCollection(name)
    ReadCollection:addCollection(name)

    local files_map = {}
    local ordered = {}
    for _, p in ipairs(paths) do
        local rp = ffiUtil.realpath(p) or p
        files_map[rp] = true
        table.insert(ordered, { file = rp })
    end

    ReadCollection:addItemsMultiple(files_map, { [name] = true })
    ReadCollection:updateCollectionOrder(name, ordered)
    ReadCollection:write({ [name] = true })
end

-- Save or update a smart collection definition (filters + paths).
function SmartManager:save_smart_definition(name, filters, paths)
    if not name or name == "" then
        return
    end
    local defs = read_smart_defs()
    defs[name] = {
        filters = filters or {},
        paths = paths or {},
        last_updated = os.time(),
    }
    write_smart_defs(defs)
end

function SmartManager:get_definitions()
    return read_smart_defs()
end

return SmartManager
