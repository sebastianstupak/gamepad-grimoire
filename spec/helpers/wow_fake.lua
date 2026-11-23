-- In-memory stand-in for the ns.Wow adapter (src/Core/Wow.lua).
-- Records bindings, lets tests toggle combat and fire game events.
local Fake = {}

---@return table wow, table state
function Fake.new()
    local state = {
        combat = false,
        cvars = { GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADRTRIGGER" },
        spells = { [172] = "Corruption", [686] = "Shadow Bolt", [348] = "Immolate" },
        bindings = {}, -- owner -> { key -> { kind, value } }
        frames = {},
        printed = {},
        slash = nil,
        device = nil,
        spec = 1,
        charKey = "Zorelo-Umbra",
    }
    local W = {}

    function W.InCombatLockdown()
        return state.combat
    end

    function W.CreateFrame(kind, name)
        local f = { kind = kind, name = name, events = {}, scripts = {} }
        function f:RegisterEvent(e)
            self.events[e] = true
        end
        function f:UnregisterEvent(e)
            self.events[e] = nil
        end
        function f:SetScript(s, fn)
            self.scripts[s] = fn
        end
        state.frames[#state.frames + 1] = f
        return f
    end

    local function bind(owner, key, kind, value)
        state.bindings[owner] = state.bindings[owner] or {}
        state.bindings[owner][key] = { kind = kind, value = value }
    end
    function W.SetOverrideBinding(owner, _, key, command)
        bind(owner, key, "command", command)
    end
    function W.SetOverrideBindingSpell(owner, _, key, spell)
        bind(owner, key, "spell", spell)
    end
    function W.SetOverrideBindingItem(owner, _, key, item)
        bind(owner, key, "item", item)
    end
    function W.SetOverrideBindingMacro(owner, _, key, macro)
        bind(owner, key, "macro", macro)
    end
    function W.ClearOverrideBindings(owner)
        state.bindings[owner] = nil
    end

    function W.GetCVar(name)
        return state.cvars[name]
    end
    function W.GetSpellName(id)
        return state.spells[id]
    end
    function W.GetGamePadDevice()
        return state.device
    end
    function W.GetSpecialization()
        return state.spec
    end
    function W.CharacterKey()
        return state.charKey
    end
    function W.RegisterSlash(names, handler)
        state.slash = { names = names, handler = handler }
    end
    function W.Print(msg)
        state.printed[#state.printed + 1] = msg
    end

    ---Fires a game event on every frame that registered it.
    function state.fire(event, ...)
        for _, f in ipairs(state.frames) do
            if f.events[event] and f.scripts.OnEvent then
                f.scripts.OnEvent(f, event, ...)
            end
        end
    end

    return W, state
end

return Fake
