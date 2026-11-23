-- CheatSheet slice: shows the card while a layer trigger is held (peek) or while
-- pinned, for the active profile and the resolved controller.
local _, ns = ...

ns.CheatSheet = ns.CheatSheet or {}
local CheatSheet = ns.CheatSheet

local M = ns.NewModule("CheatSheet")

CheatSheet.HOLD_DELAY = 0.25 -- a quick tap of a trigger should not flash the card
CheatSheet.DEFAULT_PIN_KEY = "SHIFT-PADRSTICK"
CheatSheet.TOGGLE_BUTTON = "GamepadGrimoireToggle"

local MOD_LAYER = { SHIFT = "shift", CTRL = "ctrl" }

---Which layer the held modifiers select. Pure.
---@param shift boolean
---@param ctrl boolean
---@param modifiers table<string, string> layer -> modifier, e.g. { LT = "SHIFT", RT = "CTRL" }
---@return string|nil layer "LT" / "RT", "BASE" when both are held, nil when none
function CheatSheet.HeldLayer(shift, ctrl, modifiers)
    local held = { shift = shift, ctrl = ctrl }
    local found
    for layer, mod in pairs(modifiers) do
        if held[MOD_LAYER[mod] or ""] then
            if found then
                return "BASE"
            end
            found = layer
        end
    end
    return found
end

---Peek / pin state machine step. Pure.
---@param s { heldLayer: string?, heldFor: number, pinnedLayer: string? }
---@param held string|nil layer currently held
---@param dt number seconds since last step
---@param pinned boolean
---@param typing boolean a text box has focus (holding Shift to type capitals)
---@return string|nil layer to show (nil = hidden)
function CheatSheet.Step(s, held, dt, pinned, typing)
    if typing then
        s.heldLayer, s.heldFor = nil, 0
        return pinned and s.pinnedLayer or nil
    end
    if held then
        if held ~= s.heldLayer then
            s.heldLayer, s.heldFor = held, 0
        end
        s.heldFor = s.heldFor + dt
        if s.heldFor >= CheatSheet.HOLD_DELAY then
            return held
        end
        return pinned and (s.pinnedLayer or "BASE") or nil
    end
    s.heldLayer, s.heldFor = nil, 0
    return pinned and (s.pinnedLayer or "BASE") or nil
end

local cards = {} -- controller id -> card
local card -- visible card
local pinned = false
local peek = { heldFor = 0 }
local shownLayer
local focus, setupMode -- set by the Setup slice while the controller setup is open

---Card size: the player's choice, else fit ~90% of the screen width (big on a
---Steam Deck, sensible on a monitor).
---@param cardWidth number
---@return number
function CheatSheet.AutoScale(cardWidth, screenWidth)
    return math.max(0.8, math.min(1.6, screenWidth * 0.9 / cardWidth))
end

local function settings()
    return ns.db.settings
end

local function currentCard()
    local profile = ns.Profiles.ActiveProfile()
    local id = ns.Controllers.Detect.Resolve(profile.controller)
    if not cards[id] then
        local built = ns.CheatSheet.View.Build(ns.Controllers.Registry.Get(id), ns.Bindings.Model.BUTTONS)
        built.onRow = function(button, kind)
            if pinned and shownLayer then
                ns.Editor.OnRow(shownLayer, button, kind)
            end
        end
        built.onTab = function(layer)
            CheatSheet.Toggle(layer)
        end
        cards[id] = built
    end
    if card and card ~= cards[id] then
        card.frame:Hide()
    end
    card = cards[id]
    card.frame:SetScale(CheatSheet.Scale())
    return card, profile
end

local function render(layer)
    if not layer then
        if card then
            card.frame:Hide()
        end
        shownLayer = nil
        return
    end
    local c = currentCard()
    c:Fill({
        layer = layer,
        layout = ns.Profiles.ActiveProfile(),
        modifiers = ns.Bindings.Model.LayerModifiers(ns.Wow.GetCVar),
        profile = ns.Profiles.ActiveName(),
        pinned = pinned,
        pinKey = settings().pinKey or CheatSheet.DEFAULT_PIN_KEY,
        focus = focus,
        setup = setupMode,
    })
    c:SetEditable(pinned)
    c.frame:Show()
    shownLayer = layer
    CheatSheet.RecordScreenRect(c)
end

---Remembers where the card is on screen, as fractions of the screen size
---(used by tools/e2e to crop screenshots; harmless otherwise).
function CheatSheet.RecordScreenRect(c)
    local f, ui = c.frame, ns.Wow.UIParent
    local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
    if not (l and t and r and b) then
        return
    end
    local k = f:GetEffectiveScale() / ui:GetEffectiveScale()
    local w, h = ui:GetWidth(), ui:GetHeight()
    ns.db.debug = ns.db.debug or {}
    ns.db.debug.cards = ns.db.debug.cards or {}
    ns.db.debug.cards[c.def.id] = {
        left = l * k / w,
        right = r * k / w,
        top = 1 - t * k / h,
        bottom = 1 - b * k / h,
    }
end

---Pin / unpin the card (also bound to the pin key).
---@param layer? string pin showing this layer (default BASE)
function CheatSheet.Toggle(layer)
    if layer then
        pinned, peek.pinnedLayer = true, layer
    else
        pinned = not pinned
        peek.pinnedLayer = nil
    end
    render(pinned and (peek.pinnedLayer or "BASE") or nil)
    return pinned
end

---@return boolean pinned, string|nil shownLayer
function CheatSheet.State()
    return pinned, shownLayer
end

---Current card scale (the player's setting, else automatic).
---@return number
function CheatSheet.Scale()
    if settings().scale then
        return settings().scale
    end
    local w = ns.Wow.ScreenSize()
    return CheatSheet.AutoScale(card and card.width or 1100, w or 1280)
end

---@param scale number|nil 0.5 .. 2.5, nil = automatic
function CheatSheet.SetScale(scale)
    settings().scale = scale
    if card then
        card.frame:SetScale(CheatSheet.Scale())
    end
end

---The card for the active profile's controller (built on demand).
function CheatSheet.Card()
    return (currentCard())
end

---Shows the card pinned on `layer` with `button` outlined (controller setup).
---@param layer string
---@param button string|nil
---@param active boolean setup mode on/off
function CheatSheet.SetSetup(layer, button, active)
    focus, setupMode = active and button or nil, active or nil
    if active then
        pinned, peek.pinnedLayer = true, layer
        render(layer)
    end
end

---Re-renders the card if it is showing.
function CheatSheet.Refresh()
    if shownLayer then
        render(shownLayer)
    end
end

local function refresh()
    if shownLayer then
        render(shownLayer)
    end
end

function M:OnEnable()
    local toggle = ns.Wow.CreateFrame("Button", CheatSheet.TOGGLE_BUTTON, ns.Wow.UIParent)
    toggle:SetScript("OnClick", function()
        -- the Setup slice turns the pin key into "open controller setup"
        if CheatSheet.pinAction then
            CheatSheet.pinAction()
        else
            CheatSheet.Toggle()
        end
    end)
    local pinKey = settings().pinKey or CheatSheet.DEFAULT_PIN_KEY
    if pinKey ~= "NONE" and not ns.Wow.InCombatLockdown() then
        -- priority binding: the pin key works whatever the profile puts there
        ns.Wow.SetOverrideBinding(toggle, true, pinKey, "CLICK " .. CheatSheet.TOGGLE_BUTTON .. ":LeftButton")
    end

    local driver = ns.Wow.CreateFrame("Frame")
    local acc = 0
    driver:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then
            return
        end
        local step = acc
        acc = 0
        local mods = ns.Bindings.Model.LayerModifiers(ns.Wow.GetCVar)
        local held = CheatSheet.HeldLayer(ns.Wow.IsShiftKeyDown(), ns.Wow.IsControlKeyDown(), mods)
        local want = CheatSheet.Step(peek, held, step, pinned, ns.Wow.IsTyping())
        if want ~= shownLayer then
            render(want)
        end
    end)

    ns.Events.On("PROFILE_CHANGED", refresh)
    ns.Events.On("BINDINGS_APPLIED", refresh)
    for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "UPDATE_BINDINGS", "PET_BAR_UPDATE" }) do
        ns.Events.OnGame(e, refresh)
    end
end
