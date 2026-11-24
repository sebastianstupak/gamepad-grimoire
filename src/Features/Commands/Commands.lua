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
    "/gg setup - controller setup (same as the pin chord, LT+R3)",
    "/gg profile - list profiles (* = active)",
    "/gg profile use <name> - switch this character to a profile",
    "/gg profile new <name> - new empty profile",
    "/gg profile copy <name> - copy the active profile",
    "/gg profile rename <old> = <new> - rename a profile",
    "/gg profile delete <name> - delete an unused profile",
    "/gg controller [auto|<id>] - picture: xbox xbox360 dualsense dualshock4 switchpro 8bitdo steamcontroller generic steamdeck rogally legiongo msiclaw",
    "/gg capture <name> - new profile from your current controller keybinds",
    "/gg export [profile] - share string of a profile (default: the active one)",
    "/gg import - paste a share string to add it as a new profile",
    "/gg show - pin / unpin the cheat sheet (or hold a trigger to peek)",
    "/gg show base|lt|rt - pin it on that layer",
    "/gg hide - hide the pinned cheat sheet",
    "/gg flip - turn the card around: front / back of the controller",
    "/gg scale <0.5-2.5|auto> - cheat sheet size",
    "/gg reload - re-apply bindings",
    "/gg diag - check this client and the addon (saved for bug reports)",
}

---@type table<string, fun(arg?: string, arg2?: string, rest?: string)>
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
    elseif sub == "delete" then
        ok, err = P.Delete(name)
    elseif sub == "rename" then
        local old, new = (name or ""):match("^(.-)%s*=%s*(.+)$")
        if not old then
            return say("usage: /gg profile rename <old> = <new>")
        end
        ok, err = P.Rename(old, new)
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

function handlers.capture(_, _, rest)
    local B = ns.Bindings.Model
    local name = rest ~= "" and rest or "Captured"
    local layout, count = B.FromKeybinds(ns.Wow.GetBindingAction, B.LayerModifiers(ns.Wow.GetCVar))
    local ok, err = ns.Profiles.Create(name)
    if not ok then
        return say("|cffff6060" .. tostring(err) .. "|r")
    end
    local profile = ns.Profiles.Get(name)
    profile.layers = layout.layers
    say(("captured %d controller binds into profile %s - /gg profile use %s"):format(count, name, name))
end

function handlers.export(_, _, rest)
    local name = rest ~= "" and rest or ns.Profiles.ActiveName()
    if not ns.Profiles.Get(name) then
        return say("no profile named " .. name)
    end
    ns.Share.Dialog.Export(name)
end

function handlers.import()
    ns.Share.Dialog.Import()
end

function handlers.show(layer)
    local L = { lt = "LT", rt = "RT", base = "BASE" }
    if layer and not L[layer] then
        return say("usage: /gg show [base|lt|rt]")
    end
    local pinned = ns.CheatSheet.Toggle(layer and L[layer])
    say(pinned and "cheat sheet pinned" or "cheat sheet hidden")
end

function handlers.hide()
    if ns.CheatSheet.State() then
        ns.CheatSheet.Toggle()
    end
    say("cheat sheet hidden")
end

function handlers.flip()
    if not ns.CheatSheet.State() then
        ns.CheatSheet.Toggle()
    end
    local side = ns.CheatSheet.Flip()
    say("cheat sheet: " .. side .. " of the controller")
end

function handlers.setup()
    ns.Setup.Toggle()
end

function handlers.scale(value)
    if value == "auto" then
        ns.CheatSheet.SetScale(nil)
        return say("cheat sheet size: automatic")
    end
    local n = tonumber(value)
    if not n or n < 0.5 or n > 2.5 then
        return say("usage: /gg scale <0.5 - 2.5|auto>")
    end
    ns.CheatSheet.SetScale(n)
    say(("cheat sheet scale %.2f"):format(n))
end

function handlers.diag()
    for _, line in ipairs(ns.Diagnostics.Format(ns.Diagnostics.Run())) do
        say(line)
    end
end

function handlers.reload()
    local status = ns.GetModule("Bindings"):Refresh()
    say("bindings " .. tostring(status))
end

---@param msg string
function Commands.Run(msg)
    local parts = Commands.Parse(msg, 3)
    local cmd = (parts[1] or "help"):lower()
    local rest = Commands.Parse(msg, 2)[2] or ""
    local h = handlers[cmd] or handlers.help
    h(parts[2] and parts[2]:lower() or nil, parts[3], rest)
end

function M:OnInitialize()
    ns.Wow.RegisterSlash({ "/gg", "/grimoire" }, Commands.Run)
end
