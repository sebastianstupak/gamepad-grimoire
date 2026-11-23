-- Applies bindings as *override* bindings owned by the addon: never written to the
-- player's saved keybinds, cleared on reload, reverted by ClearOverrideBindings.
-- Binding changes are forbidden in combat, so they are queued until it ends.
local _, ns = ...

local Applier = {}
ns.Bindings = ns.Bindings or {}
ns.Bindings.Applier = Applier

local owner -- the frame that owns our override bindings
local pending -- bindings waiting for combat to end
local waiting = false

local function ownerFrame()
    if not owner then
        owner = ns.Wow.CreateFrame("Frame", "GamepadGrimoireBindingOwner")
    end
    return owner
end

local function setOne(frame, key, action)
    local W = ns.Wow
    if action.type == "spell" then
        local name = W.GetSpellName(action.id)
        if not name then
            return false
        end
        W.SetOverrideBindingSpell(frame, false, key, name)
    elseif action.type == "item" then
        W.SetOverrideBindingItem(frame, false, key, "item:" .. action.id)
    elseif action.type == "macro" then
        W.SetOverrideBindingMacro(frame, false, key, action.name)
    elseif action.type == "command" then
        W.SetOverrideBinding(frame, false, key, action.command)
    else
        return false
    end
    return true
end

local function applyNow(bindings)
    local frame = ownerFrame()
    ns.Wow.ClearOverrideBindings(frame)
    local applied, skipped = 0, {}
    for _, b in ipairs(bindings) do
        if setOne(frame, b.key, b.action) then
            applied = applied + 1
        else
            skipped[#skipped + 1] = b.key
        end
    end
    ns.Events.Emit("BINDINGS_APPLIED", applied, skipped)
    return applied, skipped
end

---Applies (or queues, in combat) a full set of bindings, replacing the previous set.
---@param bindings { key: string, action: table }[]
---@return "applied"|"queued" status, number? applied, string[]? skipped
function Applier.Apply(bindings)
    if ns.Wow.InCombatLockdown() then
        pending = bindings
        if not waiting then
            waiting = true
            ns.Events.OnGame("PLAYER_REGEN_ENABLED", function()
                if pending then
                    local p = pending
                    pending = nil
                    applyNow(p)
                end
            end)
        end
        return "queued"
    end
    pending = nil
    return "applied", applyNow(bindings)
end

---Removes all of the addon's bindings (the player's own keybinds come back).
function Applier.Clear()
    return Applier.Apply({})
end
