-- Slash commands: /gg and /grimoire. Parsing is pure; handlers call other slices'
-- public functions only.
local _, ns = ...

local Commands = {}
ns.Commands = Commands
local M = ns.NewModule("Commands")

local function say(msg)
    ns.Wow.Print(msg)
end

---Splits "profile use My Setup" into { "profile", "use", "My Setup" }: the last
---argument of a command keeps its spaces (profile names may contain them).
---@param msg string
---@param maxParts number
---@return string[]
function Commands.Parse(msg, maxParts)
    local parts = {}
    local rest = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    while rest ~= "" do
        if #parts == maxParts - 1 then
            parts[#parts + 1] = rest
            break
        end
        local word, after = rest:match("^(%S+)%s*(.*)$")
        parts[#parts + 1] = word
        rest = after
    end
    return parts
end

local HELP = {
    "/gg profile - list profiles (* = active)",
    "/gg profile use <name> - switch this character to a profile",
    "/gg profile new <name> - new empty profile",
    "/gg profile copy <name> - copy the active profile",
    "/gg controller [auto|xbox|dualsense|switchpro|steamdeck] - which picture to show",
    "/gg reload - re-apply bindings",
}

local handlers = {}

function handlers.help()
    for _, line in ipairs(HELP) do
        say(line)
    end
end

function handlers.profile(sub, name)
    local P = ns.Profiles
    if not sub or sub == "list" then
        local active = P.ActiveName()
        for _, n in ipairs(P.List()) do
            say((n == active and "* " or "  ") .. n)
        end
        return
    end
    local ok, err
    if sub == "use" then
        ok, err = P.Use(name)
    elseif sub == "new" then
        ok, err = P.Create(name)
    elseif sub == "copy" then
        ok, err = P.Create(name, P.ActiveName())
    else
        return handlers.help()
    end
    say(ok and ("done: " .. sub .. " " .. name) or ("|cffff6060" .. tostring(err) .. "|r"))
end

function handlers.controller(choice)
    local profile = ns.Profiles.ActiveProfile()
    if choice then
        if choice ~= "auto" and not ns.Controllers.Registry.Get(choice) then
            return say("unknown controller: " .. choice)
        end
        profile.controller = choice
        ns.Events.Emit("PROFILE_CHANGED")
    end
    local id, reason = ns.Controllers.Detect.Resolve(profile.controller)
    say("controller: " .. ns.Controllers.Registry.Get(id).name .. " (" .. reason .. ")")
end

function handlers.reload()
    local status = ns.GetModule("Bindings"):Refresh()
    say("bindings " .. tostring(status))
end

---@param msg string
function Commands.Run(msg)
    local parts = Commands.Parse(msg, 3)
    local cmd = (parts[1] or "help"):lower()
    local h = handlers[cmd] or handlers.help
    h(parts[2] and parts[2]:lower() or nil, parts[3])
end

function M:OnInitialize()
    ns.Wow.RegisterSlash({ "/gg", "/grimoire" }, Commands.Run)
end
