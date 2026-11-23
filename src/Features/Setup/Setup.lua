-- Controller setup: configure everything with the D-pad and face buttons.
-- Opened with the pin chord (LT+R3 by default) or /gg setup; closes on B or when combat
-- starts (gamepad and keyboard capture is protected in combat). The logic lives in
-- Navigator (pure); this module feeds it input and carries out its effects.
local _, ns = ...

local Setup = ns.Setup or {}
ns.Setup = Setup
local M = ns.NewModule("Setup")

local state -- Navigator state while open
local ctx -- { categories, menu }
local input -- frame that captures gamepad buttons and keys
local panel, panelCard
local wasPinned

local function N()
    return ns.Setup.Navigator
end

---@return boolean
function Setup.IsOpen()
    return state ~= nil
end

local function controllerChoices()
    local ids = { "auto" }
    for _, def in ipairs(ns.Controllers.Registry.All()) do
        ids[#ids + 1] = def.id
    end
    return ids
end

local function controllerName(choice)
    if choice == "auto" then
        local id = ns.Controllers.Detect.Resolve("auto")
        return "Automatic (" .. ns.Controllers.Registry.Get(id).name .. ")"
    end
    local def = ns.Controllers.Registry.Get(choice)
    return def and def.name or choice
end

local function buildMenu()
    local items = {}
    local active = ns.Profiles.ActiveName()
    for _, name in ipairs(ns.Profiles.List()) do
        items[#items + 1] = {
            name = (name == active and "|cffffd100> " or "Use profile: ") .. name .. (name == active and "|r" or ""),
            effect = { kind = "use", name = name },
        }
    end
    items[#items + 1] = { name = "New profile (copy of " .. active .. ")", effect = { kind = "copy" } }
    local profile = ns.Profiles.ActiveProfile()
    items[#items + 1] = {
        name = "Controller picture:  < " .. controllerName(profile.controller or "auto") .. " >",
        adjust = "controller",
        effect = { kind = "controller", delta = 1 },
    }
    local scale = ns.db.settings.scale
    items[#items + 1] = {
        name = ("Card size:  < %s >"):format(scale and ("%.1fx"):format(scale) or "automatic"),
        adjust = "scale",
        effect = { kind = "scale", delta = 0 },
    }
    items[#items + 1] = { name = "Capture my current keybinds as a new profile", effect = { kind = "capture" } }
    items[#items + 1] = { name = "Close setup", effect = { kind = "close" } }
    return items
end

local function buildContext()
    local W = ns.Wow
    ctx = {
        categories = ns.Setup.Catalog.Build(
            { spells = W.ListSpells(), macros = W.ListMacros(), items = W.ListBagItems() },
            W.BindingName
        ),
        menu = buildMenu(),
    }
end

local function ensurePanel(card)
    if panelCard ~= card then
        if panel then
            panel:Hide()
        end
        panel = ns.Setup.Panel.Build(card.frame, card.image, N().PAGE)
        panelCard = card
    end
    return panel
end

local function render()
    if not state then
        return
    end
    ns.CheatSheet.SetSetup(state.layer, N().Button(state), true)
    local card = ns.CheatSheet.Card()
    local p = ensurePanel(card)
    if state.screen == "picker" then
        local cat = ctx.categories[state.picker.category] or { name = "-", items = {} }
        local glyph = ns.CheatSheet.Glyphs.Label(card.def.family, N().Button(state))
        p:ShowList(
            ("Bind %s:   < %s >"):format(glyph, cat.name),
            cat.items,
            state.picker.index,
            state.picker.top,
            "A bind   LB / RB category   B back"
        )
    elseif state.screen == "menu" then
        p:ShowList(
            "Gamepad Grimoire",
            ctx.menu,
            state.menu.index,
            state.menu.top,
            "A choose   left / right change   B back"
        )
    else
        p:Hide()
    end
end

local function uniqueName(base)
    return ns.Share.Dialog.UniqueName(base, function(n)
        return ns.Profiles.Get(n) ~= nil
    end)
end

local function cycleController(delta)
    local profile = ns.Profiles.ActiveProfile()
    local ids = controllerChoices()
    local at = 1
    for i, id in ipairs(ids) do
        if id == (profile.controller or "auto") then
            at = i
        end
    end
    profile.controller = ids[((at - 1 + delta) % #ids) + 1]
    ns.Events.Emit("PROFILE_CHANGED")
end

local function apply(effect)
    local kind = effect.kind
    if kind == "close" then
        return Setup.Close()
    elseif kind == "assign" or kind == "clear" then
        local ok, err = ns.Editor.Assign(effect.layer, effect.button, kind == "assign" and effect.action or nil)
        if not ok then
            ns.Wow.Print(err)
        end
    elseif kind == "use" then
        ns.Profiles.Use(effect.name)
    elseif kind == "copy" then
        local name = uniqueName("Copy of " .. ns.Profiles.ActiveName())
        if ns.Profiles.Create(name, ns.Profiles.ActiveName()) then
            ns.Profiles.Use(name)
        end
    elseif kind == "capture" then
        local B = ns.Bindings.Model
        local layout = B.FromKeybinds(ns.Wow.GetBindingAction, B.LayerModifiers(ns.Wow.GetCVar))
        local name = uniqueName("Captured")
        if ns.Profiles.Create(name) then
            ns.Profiles.Get(name).layers = layout.layers
            ns.Profiles.Use(name)
        end
    elseif kind == "controller" then
        cycleController(effect.delta)
        -- the picture (and so the rows) changed: restart navigation on the new card
        state.columns = ns.CheatSheet.Card().columns
        state.index = 1
    elseif kind == "scale" then
        local s = ns.db.settings.scale or ns.CheatSheet.Scale()
        if effect.delta ~= 0 then
            ns.CheatSheet.SetScale(math.max(0.6, math.min(2.5, s + effect.delta * 0.1)))
        else
            ns.CheatSheet.SetScale(nil) -- A on the size entry: back to automatic
        end
    end
    ctx.menu = buildMenu()
end

---Feeds one gamepad button or key (WoW names: "PAD1", "PADDUP", "ENTER"...).
---@param key string
---@return boolean handled
function Setup.Press(key)
    if not state then
        return false
    end
    local abstract = N().INPUT[key]
    if not abstract then
        return false
    end
    local effect = N().Handle(state, abstract, ctx)
    if effect then
        apply(effect)
    end
    render()
    return true
end

local function capture(on)
    if not input then
        input = ns.Wow.CreateFrame("Frame", "GamepadGrimoireSetupInput", ns.Wow.UIParent)
        input:SetScript("OnGamePadButtonDown", function(_, button)
            Setup.Press(button)
        end)
        input:SetScript("OnKeyDown", function(self, key)
            -- keys the setup does not use (chat, movement...) keep working
            self:SetPropagateKeyboardInput(not Setup.Press(key))
        end)
    end
    if on then
        input:Show()
        input:EnableKeyboard(true)
        input:EnableGamePadButton(true)
    else
        input:EnableGamePadButton(false)
        input:EnableKeyboard(false)
        input:Hide()
    end
end

---Opens the controller setup on the card.
---@return boolean opened
function Setup.Open()
    if state then
        return true
    end
    if ns.Wow.InCombatLockdown() then
        ns.Wow.Print("setup is not available in combat")
        return false
    end
    wasPinned = ns.CheatSheet.State()
    local card = ns.CheatSheet.Card()
    state = N().New(card.columns)
    buildContext()
    capture(true)
    render()
    return true
end

function Setup.Close()
    if not state then
        return
    end
    state = nil
    capture(false)
    if panel then
        panel:Hide()
    end
    ns.CheatSheet.SetSetup("BASE", nil, false)
    if not wasPinned then
        ns.CheatSheet.Toggle() -- unpin again
    else
        ns.CheatSheet.Refresh()
    end
end

---@return table|nil navigator state (tests)
function Setup.State()
    return state
end

---Pin chord: open setup, or close it when open.
function Setup.Toggle()
    if state then
        Setup.Close()
    else
        Setup.Open()
    end
end

function M:OnEnable()
    ns.CheatSheet.pinAction = Setup.Toggle
    ns.Events.OnGame("PLAYER_REGEN_DISABLED", function()
        Setup.Close()
    end)
end
