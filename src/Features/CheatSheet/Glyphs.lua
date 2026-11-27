-- What each button is called on each controller family. Pure data.
-- Face buttons are positional (PAD1 = bottom, PAD2 = right, PAD3 = left, PAD4 = top),
-- which is why Nintendo's letters look "swapped".
local _, ns = ...

local Glyphs = {}
ns.CheatSheet = ns.CheatSheet or {}
ns.CheatSheet.Glyphs = Glyphs

local COMMON = {
    PADDUP = "Up",
    PADDDOWN = "Down",
    PADDLEFT = "Left",
    PADDRIGHT = "Right",
    PADPADDLE1 = "P1",
    PADPADDLE2 = "P2",
    PADPADDLE3 = "P3",
    PADPADDLE4 = "P4",
}

local FAMILY = {
    xbox = {
        PAD1 = "A",
        PAD2 = "B",
        PAD3 = "X",
        PAD4 = "Y",
        PADLSHOULDER = "LB",
        PADRSHOULDER = "RB",
        PADLTRIGGER = "LT",
        PADRTRIGGER = "RT",
        PADLSTICK = "LS",
        PADRSTICK = "RS",
        PADBACK = "View",
        PADFORWARD = "Menu",
        PADSOCIAL = "Share",
        PADSYSTEM = "Guide",
    },
    playstation = {
        PAD1 = "Cross",
        PAD2 = "Circle",
        PAD3 = "Square",
        PAD4 = "Triangle",
        PADLSHOULDER = "L1",
        PADRSHOULDER = "R1",
        PADLTRIGGER = "L2",
        PADRTRIGGER = "R2",
        PADLSTICK = "L3",
        PADRSTICK = "R3",
        PADBACK = "Touchpad",
        PADFORWARD = "Options",
        PADSOCIAL = "Create",
        PADSYSTEM = "PS",
    },
    nintendo = {
        PAD1 = "B",
        PAD2 = "A",
        PAD3 = "Y",
        PAD4 = "X",
        PADLSHOULDER = "L",
        PADRSHOULDER = "R",
        PADLTRIGGER = "ZL",
        PADRTRIGGER = "ZR",
        PADLSTICK = "LS",
        PADRSTICK = "RS",
        PADBACK = "-",
        PADFORWARD = "+",
        PADSOCIAL = "Capture",
        PADSYSTEM = "Home",
    },
    valve = {
        PAD1 = "A",
        PAD2 = "B",
        PAD3 = "X",
        PAD4 = "Y",
        PADLSHOULDER = "L1",
        PADRSHOULDER = "R1",
        PADLTRIGGER = "L2",
        PADRTRIGGER = "R2",
        PADLSTICK = "L3",
        PADRSTICK = "R3",
        PADBACK = "View",
        PADFORWARD = "Menu",
        PADSOCIAL = "...",
        PADSYSTEM = "Steam",
    },
}

-- face-button colours by position (the same on every controller)
Glyphs.FACE_COLOR = {
    PAD1 = { 0.37, 0.83, 0.37 },
    PAD2 = { 1.0, 0.37, 0.37 },
    PAD3 = { 0.37, 0.66, 1.0 },
    PAD4 = { 1.0, 0.83, 0.31 },
}

---@param family string
---@param button string
---@return string
function Glyphs.Label(family, button)
    local f = FAMILY[family] or FAMILY.xbox
    return f[button] or COMMON[button] or button
end

---Label of a button on one controller definition (its own labels win: the
---Steam Deck's back buttons are L4/L5/R4/R5, not P1-P4).
---@param def table
---@param button string
---@return string
function Glyphs.For(def, button)
    return def.labels and def.labels[button] or Glyphs.Label(def.family, button)
end

---Name of the trigger that holds a layer ("LT" on Xbox, "L2" on PlayStation...).
---@param family string
---@param layer "LT"|"RT"
function Glyphs.LayerTrigger(family, layer)
    return Glyphs.Label(family, layer == "LT" and "PADLTRIGGER" or "PADRTRIGGER")
end

local MODIFIERS = { SHIFT = true, CTRL = true, ALT = true }

---Renders a WoW key chord in this controller's button names: "SHIFT-PADRSTICK"
---becomes "L2+R3" on a Steam Deck, because LT (its "L2") is what emulates Shift.
---A modifier with no emulating trigger keeps its raw name. Pure.
---@param def table controller definition
---@param modifiers table<string, string> layer -> modifier, from `LayerModifiers`
---@param key string? a WoW binding key ("NONE" / nil / "" => no chord)
---@return string? label nil when the key is off
function Glyphs.Chord(def, modifiers, key)
    if not key or key == "" or key == "NONE" then
        return nil
    end
    local triggerFor = {} -- modifier -> the trigger button that emulates it
    for layer, mod in pairs(modifiers) do
        triggerFor[mod] = layer == "LT" and "PADLTRIGGER" or "PADRTRIGGER"
    end
    local parts, button = {}, key
    while true do
        local mod, rest = button:match("^(%u+)%-(.+)$")
        if not (mod and MODIFIERS[mod]) then
            break
        end
        local trigger = triggerFor[mod]
        parts[#parts + 1] = trigger and Glyphs.For(def, trigger) or mod
        button = rest
    end
    parts[#parts + 1] = Glyphs.For(def, button)
    return table.concat(parts, "+")
end
