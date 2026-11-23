-- Profiles: named binding layouts shared account-wide; each character picks one,
-- optionally a different one per specialization (switched automatically).
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles
local M = ns.NewModule("Profiles")

local MAX_NAME = 48

local function db()
    return assert(ns.db, "Profiles used before saved data was loaded")
end

local function deepCopy(v)
    if type(v) ~= "table" then
        return v
    end
    local t = {}
    for k, x in pairs(v) do
        t[deepCopy(k)] = deepCopy(x)
    end
    return t
end
Profiles.DeepCopy = deepCopy

---@param name any
---@return boolean ok, string? err
function Profiles.ValidName(name)
    if type(name) ~= "string" then
        return false, "name must be text"
    end
    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" or trimmed ~= name then
        return false, "name must not be empty or start/end with spaces"
    end
    if #name > MAX_NAME then
        return false, "name is longer than " .. MAX_NAME .. " characters"
    end
    return true
end

---@return string[] names sorted
function Profiles.List()
    local names = {}
    for name in pairs(db().profiles) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

---@return table|nil
function Profiles.Get(name)
    return db().profiles[name]
end

---Creates a profile, empty or as a copy of `from`.
---@return boolean ok, string? err
function Profiles.Create(name, from)
    local ok, err = Profiles.ValidName(name)
    if not ok then
        return false, err
    end
    if db().profiles[name] then
        return false, "a profile named " .. name .. " already exists"
    end
    local source = from and db().profiles[from]
    if from and not source then
        return false, "no profile named " .. from
    end
    db().profiles[name] = source and deepCopy(source) or { controller = "auto", layers = {} }
    return true
end

---Stores a whole profile (e.g. from an import) under a new name.
function Profiles.Add(name, profile)
    local ok, err = Profiles.Create(name)
    if ok then
        db().profiles[name] = deepCopy(profile)
    end
    return ok, err
end

local function usedBy(name)
    for _, c in pairs(db().characters) do
        if c.profile == name then
            return true
        end
        for _, p in pairs(c.specProfiles or {}) do
            if p == name then
                return true
            end
        end
    end
    return false
end

---@return boolean ok, string? err
function Profiles.Delete(name)
    if not db().profiles[name] then
        return false, "no profile named " .. tostring(name)
    end
    if name == ns.Store.DEFAULT_PROFILE then
        return false, "the Default profile cannot be deleted"
    end
    if usedBy(name) then
        return false, name .. " is in use by a character or spec"
    end
    db().profiles[name] = nil
    return true
end

---@return boolean ok, string? err
function Profiles.Rename(old, new)
    if not db().profiles[old] then
        return false, "no profile named " .. tostring(old)
    end
    if old == ns.Store.DEFAULT_PROFILE then
        return false, "the Default profile cannot be renamed"
    end
    local ok, err = Profiles.Create(new)
    if not ok then
        return false, err
    end
    db().profiles[new] = db().profiles[old]
    db().profiles[old] = nil
    for _, c in pairs(db().characters) do
        if c.profile == old then
            c.profile = new
        end
        for spec, p in pairs(c.specProfiles or {}) do
            if p == old then
                c.specProfiles[spec] = new
            end
        end
    end
    ns.Events.Emit("PROFILE_CHANGED")
    return true
end

local function character()
    return ns.Store.Character(db(), ns.Wow.CharacterKey())
end

---Profile name in effect for this character and its current spec.
---@return string
function Profiles.ActiveName()
    local c = character()
    local spec = ns.Wow.GetSpecialization()
    local name = spec and c.specProfiles[spec] or c.profile
    if not db().profiles[name] then
        name = ns.Store.DEFAULT_PROFILE
    end
    return name
end

---@return table
function Profiles.ActiveProfile()
    return db().profiles[Profiles.ActiveName()]
end

---Sets the character's profile; with `spec`, only for that specialization.
---@return boolean ok, string? err
function Profiles.Use(name, spec)
    if not db().profiles[name] then
        return false, "no profile named " .. tostring(name)
    end
    local c = character()
    if spec then
        c.specProfiles[spec] = name
    else
        c.profile = name
    end
    ns.Events.Emit("PROFILE_CHANGED")
    return true
end

function M:OnEnable()
    local last = Profiles.ActiveName()
    ns.Events.On("PROFILE_CHANGED", function()
        last = Profiles.ActiveName()
    end)
    ns.Events.OnGame("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
        if unit ~= nil and unit ~= "player" then
            return
        end
        local now = Profiles.ActiveName()
        if now ~= last then
            last = now
            ns.Events.Emit("PROFILE_CHANGED")
        end
    end)
end
