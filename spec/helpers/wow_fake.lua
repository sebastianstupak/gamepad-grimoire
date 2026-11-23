-- In-memory stand-in for the ns.Wow adapter (src/Core/Wow.lua).
-- Records bindings, lets tests toggle combat / modifiers and fire game events and
-- OnUpdate ticks. Widgets accept any method: Create* returns a child widget,
-- Set*/other calls are recorded, Get*/Is* return what was set.
local Fake = {}

local widgetMeta = {}

local function newWidget(kind, name, parent, state)
    local w = { kind = kind, name = name, parent = parent, events = {}, scripts = {}, calls = {}, shown = true }
    if state then
        state.frames[#state.frames + 1] = w
    end
    return setmetatable(w, widgetMeta)
end

widgetMeta.__index = function(_, method)
    if type(method) ~= "string" then
        return nil
    end
    if method:match("^Create") then
        return function(self, _, layer)
            local child = newWidget(method:sub(7), nil, self)
            child.layer = layer
            local kids = rawget(self, "children") or {}
            rawset(self, "children", kids)
            kids[#kids + 1] = child
            return child
        end
    end
    return function(self, ...)
        local args = { ... }
        self.calls[method] = args
        if method == "SetText" then
            self.text = args[1]
        elseif method == "Show" then
            self.shown = true
        elseif method == "Hide" then
            self.shown = false
        elseif method == "SetShown" then
            self.shown = not not args[1]
        elseif method == "IsShown" then
            return self.shown
        elseif method == "GetText" then
            return self.text
        elseif method == "RegisterEvent" then
            self.events[args[1]] = true
        elseif method == "UnregisterEvent" then
            self.events[args[1]] = nil
        elseif method == "SetScript" then
            self.scripts[args[1]] = args[2]
        end
    end
end

---@return table wow, table state
function Fake.new()
    local state = {
        combat = false,
        shift = false,
        ctrl = false,
        typing = false,
        cvars = { GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADRTRIGGER", GamePadEnable = "1" },
        spells = { [172] = "Corruption", [686] = "Shadow Bolt", [348] = "Immolate" },
        keybinds = {}, -- the player's own bindings: key -> command
        bindings = {}, -- override bindings: owner -> { key -> { kind, value } }
        frames = {},
        printed = {},
        atlases = { Gamepad_Ltr_A_64 = true },
        slash = nil,
        device = nil,
        spec = 1,
        charKey = "Zorelo-Umbra",
    }
    local W = {}
    W.UIParent = newWidget("Frame", "UIParent")

    function W.InCombatLockdown()
        return state.combat
    end

    function W.CreateFrame(kind, name, parent)
        local f = newWidget(kind, name, parent, state)
        if parent then
            local kids = rawget(parent, "children") or {}
            rawset(parent, "children", kids)
            kids[#kids + 1] = f
        end
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
    W.SPEC_CHANGED_EVENT = "PLAYER_SPECIALIZATION_CHANGED"
    function W.ReportError(err)
        state.errors = state.errors or {}
        state.errors[#state.errors + 1] = err
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
    function W.IsShiftKeyDown()
        return state.shift
    end
    function W.IsControlKeyDown()
        return state.ctrl
    end
    function W.IsTyping()
        return state.typing
    end
    function W.GetCursorAction()
        return state.cursor
    end
    function W.ClearCursor()
        state.cursor = nil
    end
    function W.CloseOnEscape(name)
        state.escClose = state.escClose or {}
        state.escClose[#state.escClose + 1] = name
    end
    function W.After(_, fn)
        fn()
    end
    function W.AtlasExists(name)
        return state.atlases[name] == true
    end
    function W.GetBindingAction(key)
        return state.keybinds[key]
    end
    function W.DescribeCommand(command)
        return nil, command
    end
    function W.DescribeAction(action)
        if action.type == "spell" then
            return 136118, state.spells[action.id]
        elseif action.type == "command" then
            return W.DescribeCommand(action.command)
        end
        return nil, action.name or tostring(action.id)
    end
    function W.Capabilities()
        return { encoding = false, gamepadApi = true, gamepadEnabled = "1", build = 16001, version = "1.60.1" }
    end

    ---Fires a game event on every frame that registered it.
    function state.fire(event, ...)
        for _, f in ipairs(state.frames) do
            if f.events[event] and f.scripts.OnEvent then
                f.scripts.OnEvent(f, event, ...)
            end
        end
    end

    ---Runs OnUpdate handlers for `seconds`, in 50 ms frames.
    function state.tick(seconds)
        for _ = 1, math.floor(seconds / 0.05 + 0.5) do
            for _, f in ipairs(state.frames) do
                if f.scripts.OnUpdate then
                    f.scripts.OnUpdate(f, 0.05)
                end
            end
        end
    end

    ---Override bindings owned by the frame with this global name.
    function state.bindingsOf(name)
        for owner, set in pairs(state.bindings) do
            if rawget(owner, "name") == name then
                return set
            end
        end
        return {}
    end

    return W, state
end

return Fake
