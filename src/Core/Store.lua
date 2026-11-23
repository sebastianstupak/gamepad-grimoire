-- Saved data: shape, defaults and schema migrations. Pure (no WoW API).
local _, ns = ...

local Store = {}
ns.Store = Store

Store.SCHEMA = 2
Store.DEFAULT_PROFILE = "Default"

---Migrations, keyed by the schema version they produce. Each gets the db and
---upgrades it in place from the previous version.
---@type table<number, fun(db: table)>
Store.migrations = {
    [1] = function(db)
        db.profiles = db.profiles or {}
        db.characters = db.characters or {}
        db.settings = db.settings or {}
    end,
    -- 2: the card size is automatic unless the player chose one; drop the old 1.0 default
    [2] = function(db)
        if db.settings and db.settings.scale == 1 then
            db.settings.scale = nil
        end
    end,
}

local function defaults(db)
    if not db.profiles[Store.DEFAULT_PROFILE] then
        db.profiles[Store.DEFAULT_PROFILE] = { controller = "auto", layers = {} }
    end
end

---Loads (and upgrades) saved data. Unknown future schemas are kept untouched and
---flagged read-only rather than downgraded.
---@param saved table? the SavedVariables table (nil on first run)
---@return table db, string? warning
function Store.Load(saved)
    local db = type(saved) == "table" and saved or {}
    local from = tonumber(db.schema) or 0
    if from > Store.SCHEMA then
        db.readOnly = true
        return db,
            ("saved data is from a newer version (schema %d > %d); changes will not be saved"):format(
                from,
                Store.SCHEMA
            )
    end
    for v = from + 1, Store.SCHEMA do
        Store.migrations[v](db)
        db.schema = v
    end
    defaults(db)
    return db
end

---Per-character record ({ profile = name, specProfiles = { [spec] = name } }).
---@param db table
---@param charKey string
function Store.Character(db, charKey)
    local c = db.characters[charKey]
    if not c then
        c = { profile = Store.DEFAULT_PROFILE, specProfiles = {} }
        db.characters[charKey] = c
    end
    return c
end
