-- Bindings slice wiring: whenever the active profile changes (login, profile
-- switch, spec change), turn its layout into keys and apply them.
local _, ns = ...

local M = ns.NewModule("Bindings")

function M:Refresh()
    local profile = ns.Profiles.ActiveProfile()
    if not profile then
        return
    end
    local mods = ns.Bindings.Model.LayerModifiers(ns.Wow.GetCVar)
    local bindings, unreachable = ns.Bindings.Model.ToBindings(profile, mods)
    if #unreachable > 0 then
        ns.Wow.Print(
            "layer(s) "
                .. table.concat(unreachable, ", ")
                .. " need GamePadEmulateShift/Ctrl set to that trigger - skipped"
        )
    end
    return ns.Bindings.Applier.Apply(bindings)
end

function M:OnEnable()
    ns.Events.On("PROFILE_CHANGED", function()
        M:Refresh()
    end)
    M:Refresh()
end
