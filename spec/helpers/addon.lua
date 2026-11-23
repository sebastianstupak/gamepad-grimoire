-- Loads addon files the way the client does: each file gets (addonName, ns).
local Fake = require("spec.helpers.wow_fake")

local Addon = {}
Addon.NAME = "GamepadGrimoire"

---Source files listed in the .toc, in load order.
---@return string[]
function Addon.tocFiles()
    local files = {}
    for line in io.lines(Addon.NAME .. ".toc") do
        line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

---Loads a fresh copy of the addon into a new namespace with a fake WoW API.
---@param opts? { files?: string[], upTo?: string } load only these files, or toc files up to (incl.) upTo
---@return table ns, table wowState
function Addon.load(opts)
    opts = opts or {}
    local wow, state = Fake.new()
    local ns = { Wow = wow }
    local files = opts.files
    if not files then
        files = {}
        for _, f in ipairs(Addon.tocFiles()) do
            files[#files + 1] = f
            if opts.upTo and f:find(opts.upTo, 1, true) then
                break
            end
        end
    end
    for _, path in ipairs(files) do
        local chunk = assert(loadfile(path))
        chunk(Addon.NAME, ns)
    end
    return ns, state
end

---Loads everything and runs the ADDON_LOADED / PLAYER_LOGIN startup.
---@param saved? table SavedVariables content
function Addon.start(saved)
    _G.GamepadGrimoireDB = saved
    local ns, state = Addon.load()
    state.fire("ADDON_LOADED", Addon.NAME)
    state.fire("PLAYER_LOGIN")
    return ns, state
end

return Addon
