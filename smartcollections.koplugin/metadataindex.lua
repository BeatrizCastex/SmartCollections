local logger = require("logger")

local MetaIndex = {
    _books = nil,
    _columns = {},
    tag_index = {},
    custom_index = {},
}

local function trim(s)
    if not s then return "" end
    return s:match("^%s*(.-)%s*$")
end

local function split_csv(val)
    if not val or val == "" then
        return {}
    end
    if type(val) == "table" then
        local out = {}
        for _, entry in ipairs(val) do
            local cleaned = trim(entry)
            if cleaned ~= "" then
                table.insert(out, cleaned)
            end
        end
        return out
    end
    local t = {}
    for part in string.gmatch(val, "[^,]+") do
        local cleaned = trim(part)
        if cleaned ~= "" then
            table.insert(t, cleaned)
        end
    end
    return t
end

local function split_hier(val)
    if not val or val == "" then
        return {}
    end
    local parts = {}
    for part in string.gmatch(val, "[^%.]+") do
        local cleaned = trim(part)
        if cleaned ~= "" then
            table.insert(parts, cleaned)
        end
    end
    return parts
end

function MetaIndex:invalidate()
    self._books = nil
    self._columns = {}
    self.tag_index = {}
    self.custom_index = {}
end

function MetaIndex:ensureLoaded()
    if self._books then
        return
    end

    local books

    -- 1) Prefer Calibre Companion metadata cache when available.
    local ok_cc, CC = pcall(require, "plugins.calibrecompanion.calibrecompanion")
    if ok_cc and CC and type(CC.getMetadataCache) == "function" then
        local raw = CC:getMetadataCache()
        books = self:normalizeFromCalibreCompanion(raw)
        logger.dbg("SmartCollections.MetaIndex: loaded metadata from Calibre Companion cache")
    end

    -- 2) If that failed or wasn't present, try to read Calibre library metadata directly
    --    from `.metadata.calibre` JSON files.
    if not books or #books == 0 then
        local ok_ds, DataStorage = pcall(require, "datastorage")
        local ok_persist, Persist = pcall(require, "persist")
        local ok_json, rapidjson = pcall(require, "rapidjson")
        if ok_ds and ok_persist and ok_json then
            local libs_cache = Persist:new{
                path = DataStorage:getDataDir() .. "/cache/calibre/libraries.lua",
            }
            local libs, err = libs_cache:load()
            if libs and type(libs) == "table" then
                local collected = {}
                for lib_path, enabled in pairs(libs) do
                    if enabled and type(lib_path) == "string" then
                        local meta_path = lib_path .. "/.metadata.calibre"
                        local data, jerr = rapidjson.load(meta_path)
                        if data and type(data) == "table" then
                            local normalized = self:normalizeFromCalibreJson(lib_path, data)
                            for _, b in ipairs(normalized) do
                                table.insert(collected, b)
                            end
                        else
                            logger.warn("SmartCollections.MetaIndex: unable to load metadata.calibre from", meta_path, jerr)
                        end
                    end
                end
                if #collected > 0 then
                    books = collected
                    logger.dbg("SmartCollections.MetaIndex: loaded metadata directly from metadata.calibre")
                end
            else
                logger.warn("SmartCollections.MetaIndex: unable to load calibre libraries cache:", err)
            end
        end
    end

    -- 3) If that still failed, try the Calibre metadata search cache.
    if not books or #books == 0 then
        local ok_ds, DataStorage = pcall(require, "datastorage")
        local ok_persist, Persist = pcall(require, "persist")
        if ok_ds and ok_persist then
            local cache_path = DataStorage:getDataDir() .. "/cache/calibre/books.dat"
            local cache = Persist:new{
                path = cache_path,
                codec = "zstd",
            }
            local exists_ok, exists = pcall(function() return cache:exists() end)
            if exists_ok and exists then
                local raw, err = cache:load()
                if raw then
                    books = self:normalizeFromCalibreCompanion(raw)
                    logger.dbg("SmartCollections.MetaIndex: loaded metadata from Calibre search cache")
                else
                    logger.warn("SmartCollections.MetaIndex: failed to load Calibre cache:", err)
                end
            end
        end
    end

    -- 4) Fallbacks when no Calibre metadata is available.
    if not books then
        -- 3a) Generic metadata helper, if provided by another plugin.
        local meta_ok, MetadataHelper = pcall(require, "metadatahelper")
        if meta_ok and MetadataHelper and type(MetadataHelper.scanLibrary) == "function" then
            local raw = MetadataHelper:scanLibrary()
            books = self:normalizeFromKoreader(raw)
            logger.dbg("SmartCollections.MetaIndex: loaded metadata via MetadataHelper scan")
        else
            -- 3b) Last-resort fallback: KOReader's ReadHistory so we at least
            --     see books the user has opened.
            local rh_ok, ReadHistory = pcall(require, "readhistory")
            if rh_ok and ReadHistory and type(ReadHistory.hist) == "table" then
                books = self:normalizeFromReadHistory(ReadHistory.hist)
                logger.dbg("SmartCollections.MetaIndex: loaded metadata from ReadHistory")
            else
                logger.warn("SmartCollections.MetaIndex: no metadata source available")
                books = {}
            end
        end
    end

    self._books = books or {}
end

function MetaIndex:normalizeFromCalibreCompanion(raw_list)
    local books = {}
    for _, item in ipairs(raw_list or {}) do
        local path = item.path or item.file or item.filename
        -- Calibre metadata search plugin uses rootpath + lpath instead.
        if not path and item.rootpath and item.lpath then
            path = item.rootpath .. "/" .. item.lpath
        end
        if path then
            local series = item.series
            if type(series) ~= "string" then
                series = nil
            end
            local comments = item.comments or item.description
            if type(comments) ~= "string" then
                comments = nil
            end
            local book = {
                path = path,
                title = item.title or "",
                authors = split_csv(item.authors),
                tags = split_csv(item.tags),
                series = series,
                comments = comments,
                calibre_custom = {},
                status = nil,
                collections = nil,
            }

            if item.custom_columns then
                for col, val in pairs(item.custom_columns) do
                    if type(val) == "table" then
                        local collected = {}
                        for _, part in pairs(val) do
                            table.insert(collected, tostring(part))
                        end
                        book.calibre_custom[col] = table.concat(collected, ",")
                    elseif val ~= nil then
                        book.calibre_custom[col] = tostring(val)
                    end
                    local stored = book.calibre_custom[col]
                    if type(stored) == "string" then
                        self._columns[col] = self._columns[col] or { hierarchical = false, numeric = false }
                        if stored:find("%.") then
                            self._columns[col].hierarchical = true
                        end
                        if not self._columns[col].numeric then
                            local cleaned = stored:gsub("[,%s]", "")
                            if tonumber(cleaned) then
                                self._columns[col].numeric = true
                            end
                        end
                    end
                end
            end

            self:indexBook(book)
            self:enrichWithKoreaderMetadata(book)
            table.insert(books, book)
        end
    end
    return books
end

-- Normalize entries loaded directly from `.metadata.calibre`.
-- `library_path` is the Calibre library root; each item is a raw Calibre JSON object.
function MetaIndex:normalizeFromCalibreJson(library_path, raw_list)
    local books = {}
    for _, item in ipairs(raw_list or {}) do
        local lpath = item.lpath
        local path
        if type(lpath) == "string" then
            path = library_path .. "/" .. lpath
        end
        if path then
            local authors = item.authors
            if type(authors) == "string" then
                authors = split_csv(authors)
            end
            local tags = item.tags
            if type(tags) == "string" then
                tags = split_csv(tags)
            end
            local series = item.series
            if type(series) ~= "string" then
                series = nil
            end
            local comments = item.comments
            if type(comments) ~= "string" then
                comments = nil
            end
            local book = {
                path = path,
                title = item.title or "",
                authors = authors or {},
                tags = tags or {},
                series = series,
                comments = comments,
                calibre_custom = {},
                status = nil,
                collections = nil,
            }

            -- Extract custom columns from user_metadata entries.
            if type(item.user_metadata) == "table" then
                for key, meta in pairs(item.user_metadata) do
                    if type(meta) == "table" then
                        local colname = key
                        local datatype = type(meta.datatype) == "string" and meta.datatype or nil
                        if type(meta.search_terms) == "table" and meta.search_terms[1] then
                            colname = meta.search_terms[1]
                        end
                        local val = meta["#value#"] or meta["#extra#"]
                        if val ~= nil then
                            if type(val) == "table" then
                                local collected = {}
                                for _, part in pairs(val) do
                                    table.insert(collected, tostring(part))
                                end
                                val = table.concat(collected, ",")
                            else
                                val = tostring(val)
                            end
                            book.calibre_custom[colname] = val
                            self._columns[colname] = self._columns[colname] or { hierarchical = false, numeric = false }
                            if datatype then
                                self._columns[colname].datatype = datatype
                                if datatype == "int" or datatype == "float" or datatype == "rating" then
                                    self._columns[colname].numeric = true
                                end
                            end
                            if val:find("%.") then
                                self._columns[colname].hierarchical = true
                            end
                            if not self._columns[colname].numeric then
                                local cleaned = val:gsub("[,%s]", "")
                                if tonumber(cleaned) then
                                    self._columns[colname].numeric = true
                                end
                            end
                        end
                    end
                end
            end

            self:indexBook(book)
            self:enrichWithKoreaderMetadata(book)
            table.insert(books, book)
        end
    end
    return books
end

function MetaIndex:normalizeFromKoreader(raw_list)
    local books = {}
    for _, item in ipairs(raw_list or {}) do
        local path = item.filepath or item.path or item.file
        if path then
            local tags = item.tags or item.keywords
            local authors = item.authors
            if type(tags) == "string" then
                tags = split_csv(tags)
            end
            if type(authors) == "string" then
                authors = split_csv(authors)
            end
            local series = item.series
            if type(series) ~= "string" then
                series = nil
            end
            local comments = item.comments or item.description
            if type(comments) ~= "string" then
                comments = nil
            end
            local book = {
                path = path,
                title = item.title or "",
                authors = authors or {},
                tags = tags or {},
                series = series,
                comments = comments,
                calibre_custom = {},
                status = nil,
                collections = nil,
            }
            if item.custom_columns then
                for col, val in pairs(item.custom_columns) do
                    if type(val) == "string" then
                        book.calibre_custom[col] = val
                    elseif type(val) == "table" then
                        book.calibre_custom[col] = table.concat(val, ",")
                    end
                    local stored = book.calibre_custom[col]
                    if type(stored) == "string" then
                        self._columns[col] = self._columns[col] or { hierarchical = false, numeric = false }
                        if stored:find("%.") then
                            self._columns[col].hierarchical = true
                        end
                        if not self._columns[col].numeric then
                            local cleaned = stored:gsub("[,%s]", "")
                            if tonumber(cleaned) then
                                self._columns[col].numeric = true
                            end
                        end
                    end
                end
            end
            self:indexBook(book)
            self:enrichWithKoreaderMetadata(book)
            table.insert(books, book)
        end
    end
    return books
end
function MetaIndex:normalizeFromReadHistory(hist)
    local books = {}
    for _, item in ipairs(hist or {}) do
        if item.file then
            local title = item.text
            if type(title) ~= "string" then
                title = ""
            end
            local book = {
                path = item.file,
                title = title,
                authors = {},
                tags = {},
                series = nil,
                comments = nil,
                calibre_custom = {},
                status = nil,
                collections = nil,
            }
            self:indexBook(book)
            self:enrichWithKoreaderMetadata(book)
            table.insert(books, book)
        end
    end
    return books
end

-- Enrich a normalized book entry with KOReader-specific metadata such as
-- reading status and collection membership.
function MetaIndex:enrichWithKoreaderMetadata(book)
    if not book or not book.path then
        return
    end

    -- Reading status: "new", "reading", "abandoned", "complete".
    local ok_bl, BookList = pcall(require, "ui/widget/booklist")
    if ok_bl and BookList and type(BookList.getBookStatus) == "function" then
        local ok_status, status = pcall(BookList.getBookStatus, book.path)
        if ok_status and type(status) == "string" then
            book.status = status
        end
    end

    -- Collections this book belongs to.
    local ok_rc, ReadCollection = pcall(require, "readcollection")
    if ok_rc and ReadCollection and type(ReadCollection.getCollectionsWithFile) == "function" then
        local ok_cols, cols = pcall(ReadCollection.getCollectionsWithFile, ReadCollection, book.path)
        if ok_cols and type(cols) == "table" then
            book.collections = cols
        end
    end
end

function MetaIndex:indexBook(book)
    for _, tag in ipairs(book.tags or {}) do
        local lower = tag:lower()
        if lower:find("%.") then
            for _, part in ipairs(split_hier(lower)) do
                self:addToTagIndex(part, book.path)
            end
        else
            self:addToTagIndex(lower, book.path)
        end
    end

    for col, val in pairs(book.calibre_custom or {}) do
        if type(val) == "string" then
            local lower = val:lower()
            if lower:find("%.") then
                local parts = split_hier(lower)
                local last = parts[#parts]
                if last then
                    self:addToCustomIndex(col, last, book.path)
                end
            else
                self:addToCustomIndex(col, lower, book.path)
            end
        end
    end
end

function MetaIndex:addToTagIndex(tag, path)
    if tag == "" then
        return
    end
    self.tag_index[tag] = self.tag_index[tag] or {}
    table.insert(self.tag_index[tag], path)
end

function MetaIndex:addToCustomIndex(col, val, path)
    if val == "" then
        return
    end
    self.custom_index[col] = self.custom_index[col] or {}
    self.custom_index[col][val] = self.custom_index[col][val] or {}
    table.insert(self.custom_index[col][val], path)
end

function MetaIndex:getBooks()
    self:ensureLoaded()
    return self._books
end

-- Return a list of the most common tags (lowercased),
-- sorted by descending frequency, limited to `limit` entries.
function MetaIndex:getTopTags(limit, books)
    self:ensureLoaded()
    limit = limit or 5

    local counts = {}

    if books and #books > 0 then
        for _, book in ipairs(books) do
            for _, tag in ipairs(book.tags or {}) do
                local lower = tag:lower()
                if lower:find("%.") then
                    for _, part in ipairs(split_hier(lower)) do
                        counts[part] = (counts[part] or 0) + 1
                    end
                else
                    counts[lower] = (counts[lower] or 0) + 1
                end
            end
        end

        local arr = {}
        for tag, count in pairs(counts) do
            table.insert(arr, { tag = tag, count = count })
        end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.tag < b.tag
        end)

        local top = {}
        for i = 1, math.min(limit, #arr) do
            table.insert(top, arr[i].tag)
        end
        return top
    end

    for tag, paths in pairs(self.tag_index or {}) do
        table.insert(counts, { tag = tag, count = #paths })
    end
    table.sort(counts, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.tag < b.tag
    end)

    local top = {}
    for i = 1, math.min(limit, #counts) do
        table.insert(top, counts[i].tag)
    end
    return top
end

function MetaIndex:getCustomColumns()
    self:ensureLoaded()
    local cols = {}
    for name, meta in pairs(self._columns) do
        table.insert(cols, {
            name = name,
            hierarchical = meta.hierarchical and true or false,
            numeric = meta.numeric and true or false,
            datatype = meta.datatype,
        })
    end
    table.sort(cols, function(a, b)
        return a.name < b.name
    end)
    return cols
end

-- Return a list of the most common values for the given custom column,
-- sorted by descending frequency, limited to `limit` entries.
function MetaIndex:getTopCustomValues(colname, limit, books)
    self:ensureLoaded()
    if not colname or colname == "" then
        return {}
    end
    limit = limit or 5

    local counts = {}

    if books and #books > 0 then
        for _, book in ipairs(books) do
            local raw = book.calibre_custom and book.calibre_custom[colname]
            if type(raw) == "string" and raw ~= "" then
                local lower = raw:lower()
                if lower:find("%.") then
                    local parts = split_hier(lower)
                    local last = parts[#parts]
                    if last and last ~= "" then
                        counts[last] = (counts[last] or 0) + 1
                    end
                else
                    counts[lower] = (counts[lower] or 0) + 1
                end
            end
        end

        local arr = {}
        for val, count in pairs(counts) do
            table.insert(arr, { val = val, count = count })
        end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then
                return a.count > b.count
            end
            return a.val < b.val
        end)

        local top = {}
        for i = 1, math.min(limit, #arr) do
            table.insert(top, arr[i].val)
        end
        return top
    end

    local per_val = self.custom_index and self.custom_index[colname]
    if not per_val then
        return {}
    end

    for val, paths in pairs(per_val) do
        table.insert(counts, { val = val, count = #paths })
    end
    table.sort(counts, function(a, b)
        if a.count ~= b.count then
            return a.count > b.count
        end
        return a.val < b.val
    end)

    local top = {}
    for i = 1, math.min(limit, #counts) do
        table.insert(top, counts[i].val)
    end
    return top
end

function MetaIndex:filterBooks(filters)
    self:ensureLoaded()
    local results = {}
    for _, book in ipairs(self._books or {}) do
        if self:matches(book, filters) then
            table.insert(results, book)
        end
    end
    return results
end

local function normalize_list(list)
    if not list then
        return nil
    end
    local source = list
    if type(list) == "string" then
        source = split_csv(list)
    end
    local t = {}
    for _, entry in ipairs(source) do
        local cleaned = trim(entry)
        if cleaned ~= "" then
            table.insert(t, cleaned:lower())
        end
    end
    return #t > 0 and t or nil
end

function MetaIndex:matches(book, filters)
    if not filters then
        return true
    end

    local include_tags = normalize_list(filters.include_tags or {})
    if include_tags then
        for _, wanted in ipairs(include_tags) do
            if not self:bookHasTag(book, wanted) then
                return false
            end
        end
    end

    local exclude_tags = normalize_list(filters.exclude_tags or {})
    if exclude_tags then
        for _, banned in ipairs(exclude_tags) do
            if self:bookHasTag(book, banned) then
                return false
            end
        end
    end

    local include_authors = normalize_list(filters.include_authors or {})
    if include_authors then
        local ok = false
        for _, wanted in ipairs(include_authors) do
            if self:bookHasAuthor(book, wanted) then
                ok = true
                break
            end
        end
        if not ok then
            return false
        end
    end

    local exclude_authors = normalize_list(filters.exclude_authors or {})
    if exclude_authors then
        for _, banned in ipairs(exclude_authors) do
            if self:bookHasAuthor(book, banned) then
                return false
            end
        end
    end

    local include_series = normalize_list(filters.include_series or {})
    if include_series then
        local found = false
        local series = book.series and book.series:lower()
        if series then
            for _, s in ipairs(include_series) do
                if series == s then
                    found = true
                    break
                end
            end
        end
        if not found then
            return false
        end
    end

    local exclude_series = normalize_list(filters.exclude_series or {})
    if exclude_series then
        local series = book.series and book.series:lower()
        if series then
            for _, s in ipairs(exclude_series) do
                if series == s then
                    return false
                end
            end
        end
    end

    local status_filters = normalize_list(filters.status or {})
    if status_filters then
        local st = book.status and book.status:lower()
        local ok = false
        if st then
            for _, wanted in ipairs(status_filters) do
                if st == wanted then
                    ok = true
                    break
                end
            end
        end
        if not ok then
            return false
        end
    end

    local include_collections = normalize_list(filters.include_collections or {})
    if include_collections then
        local cols = book.collections
        if not cols or type(cols) ~= "table" then
            return false
        end
        for _, wanted in ipairs(include_collections) do
            local found = false
            for coll_name in pairs(cols) do
                if type(coll_name) == "string" and coll_name:lower() == wanted then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end
    end

    local exclude_collections = normalize_list(filters.exclude_collections or {})
    if exclude_collections then
        local cols = book.collections
        if cols and type(cols) == "table" then
            for _, banned in ipairs(exclude_collections) do
                for coll_name in pairs(cols) do
                    if type(coll_name) == "string" and coll_name:lower() == banned then
                        return false
                    end
                end
            end
        end
    end

    local custom_filters = filters.custom
    if custom_filters then
        for colname, rule in pairs(custom_filters) do
            local raw_val = book.calibre_custom and book.calibre_custom[colname]
            local val = type(raw_val) == "string" and raw_val:lower() or ""
            local meta = self._columns[colname] or {}

            -- Numeric comparison rule: expects rule.op + rule.value.
            if rule.op and rule.value then
                if val == "" then
                    return false
                end
                local cleaned = val:gsub("[,%s]", "")
                local num = tonumber(cleaned)
                local target = tonumber(rule.value)
                if not num or not target then
                    return false
                end
                local ok_cmp
                if rule.op == ">=" then
                    ok_cmp = num >= target
                elseif rule.op == "<=" then
                    ok_cmp = num <= target
                elseif rule.op == ">" then
                    ok_cmp = num > target
                elseif rule.op == "<" then
                    ok_cmp = num < target
                else
                    ok_cmp = (num == target)
                end
                if not ok_cmp then
                    return false
                end
            else
                -- Text / hierarchical matching.
                local base = val
                if meta.hierarchical and val ~= "" then
                    local parts = split_hier(val)
                    base = parts[#parts] or val
                end

                if rule.include then
                    local include_list = normalize_list(rule.include)
                    if include_list then
                        local ok = false
                        for _, wanted in ipairs(include_list) do
                            if base ~= "" and base:find(wanted, 1, true) then
                                ok = true
                                break
                            end
                        end
                        if not ok then
                            return false
                        end
                    end
                end
                if rule.exclude then
                    local exclude_list = normalize_list(rule.exclude)
                    if exclude_list then
                        for _, banned in ipairs(exclude_list) do
                            if base ~= "" and base:find(banned, 1, true) then
                                return false
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

function MetaIndex:bookHasTag(book, query)
    if not query or query == "" then
        return true
    end
    local lower_query = query:lower()
    for _, tag in ipairs(book.tags or {}) do
        local t = tag:lower()
        if t == lower_query then
            return true
        end
        if t:find("%.") then
            for _, part in ipairs(split_hier(t)) do
                if part == lower_query then
                    return true
                end
            end
        end
    end
    return false
end

function MetaIndex:bookHasAuthor(book, query)
    if not query or query == "" then
        return true
    end
    local lower_query = query:lower()
    for _, author in ipairs(book.authors or {}) do
        if author:lower():find(lower_query, 1, true) then
            return true
        end
    end
    return false
end

return MetaIndex
