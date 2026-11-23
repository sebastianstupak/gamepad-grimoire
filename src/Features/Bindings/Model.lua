-- Binding layout model. Pure: no WoW API, fully unit-tested.
--
-- A layout maps layer -> button -> action:
--   layers.BASE.PAD1 = { type = "command", command = "JUMP" }
--   layers.LT.PAD3   = { type = "spell", id = 172 }
-- Layers LT / RT are held triggers; they become SHIFT- / CTRL- keys through the
-- client's GamePadEmulateShift / GamePadEmulateCtrl settings.
local _, ns = ...

local Model = {}
ns.Bindings = ns.Bindings or {}
ns.Bindings.Model = Model

Model.LAYERS = { "BASE", "LT", "RT" }

---Buttons the game can see (WoW binding key names).
Model.BUTTONS = {
    "PAD1",
    "PAD2",
    "PAD3",
    "PAD4",
    "PAD5",
    "PAD6",
    "PADDUP",
    "PADDDOWN",
    "PADDLEFT",
    "PADDRIGHT",
    "PADLSHOULDER",
    "PADRSHOULDER",
    "PADLTRIGGER",
    "PADRTRIGGER",
    "PADLSTICK",
    "PADRSTICK",
    "PADBACK",
    "PADFORWARD",
    "PADSOCIAL",
    "PADSYSTEM",
    "PADPADDLE1",
    "PADPADDLE2",
    "PADPADDLE3",
    "PADPADDLE4",
}

Model.ACTION_TYPES = { spell = "id", item = "id", macro = "name", command = "command" }

local isLayer, isButton = {}, {}
for _, l in ipairs(Model.LAYERS) do
    isLayer[l] = true
end
for _, b in ipairs(Model.BUTTONS) do
    isButton[b] = true
end

---@return table layout
function Model.New()
    return { layers = { BASE = {}, LT = {}, RT = {} } }
end

---@param action table?
---@return boolean ok, string? err
function Model.ValidateAction(action)
    if type(action) ~= "table" then
        return false, "action must be a table"
    end
    local field = Model.ACTION_TYPES[action.type]
    if not field then
        return false, "unknown action type: " .. tostring(action.type)
    end
    local v = action[field]
    if field == "id" then
        if type(v) ~= "number" or v <= 0 or v % 1 ~= 0 then
            return false, action.type .. " needs a positive integer id"
        end
    elseif type(v) ~= "string" or v == "" or #v > 255 then
        return false, action.type .. " needs a non-empty " .. field
    end
    return true
end

---@param layout table
---@param layer string
---@param button string
---@param action table|nil nil clears the button
function Model.Set(layout, layer, button, action)
    assert(isLayer[layer], "unknown layer: " .. tostring(layer))
    assert(isButton[button], "unknown button: " .. tostring(button))
    if action ~= nil then
        assert(Model.ValidateAction(action))
    end
    layout.layers[layer] = layout.layers[layer] or {}
    layout.layers[layer][button] = action
end

---@return table|nil
function Model.Get(layout, layer, button)
    local l = layout.layers and layout.layers[layer]
    return l and l[button]
end

---Validates untrusted data (e.g. an imported string). Returns every problem found.
---@param layout any
---@return boolean ok, string[] errors
function Model.Validate(layout)
    local errors = {}
    if type(layout) ~= "table" or type(layout.layers) ~= "table" then
        return false, { "layout.layers missing" }
    end
    for layer, buttons in pairs(layout.layers) do
        if not isLayer[layer] then
            errors[#errors + 1] = "unknown layer: " .. tostring(layer)
        elseif type(buttons) ~= "table" then
            errors[#errors + 1] = layer .. " is not a table"
        else
            for button, action in pairs(buttons) do
                if not isButton[button] then
                    errors[#errors + 1] = layer .. ": unknown button " .. tostring(button)
                else
                    local ok, err = Model.ValidateAction(action)
                    if not ok then
                        errors[#errors + 1] = layer .. "." .. button .. ": " .. err
                    end
                end
            end
        end
    end
    table.sort(errors)
    return #errors == 0, errors
end

local MODIFIER_FOR_CVAR = { GamePadEmulateShift = "SHIFT", GamePadEmulateCtrl = "CTRL", GamePadEmulateAlt = "ALT" }

---Which modifier each held-trigger layer produces, from the client's CVars.
---@param getCVar fun(name: string): string?
---@return table<string, string> e.g. { LT = "SHIFT", RT = "CTRL" }
function Model.LayerModifiers(getCVar)
    local mods = {}
    for cvar, mod in pairs(MODIFIER_FOR_CVAR) do
        local button = getCVar(cvar)
        if button == "PADLTRIGGER" then
            mods.LT = mod
        elseif button == "PADRTRIGGER" then
            mods.RT = mod
        end
    end
    return mods
end

---Builds a layout from the player's current keybinds (migration from manual
---setups or other addons). Every bound gamepad key becomes a command action.
---@param getBindingAction fun(key: string): string?
---@param modifiers table<string, string> from LayerModifiers
---@return table layout, number count
function Model.FromKeybinds(getBindingAction, modifiers)
    local layout, count = Model.New(), 0
    for _, layer in ipairs(Model.LAYERS) do
        local prefix = layer == "BASE" and "" or (modifiers[layer] and modifiers[layer] .. "-")
        if prefix then
            for _, button in ipairs(Model.BUTTONS) do
                local command = getBindingAction(prefix .. button)
                if command and command ~= "" and #command <= 255 then
                    layout.layers[layer][button] = { type = "command", command = command }
                    count = count + 1
                end
            end
        end
    end
    return layout, count
end

---Flattens a layout into concrete keys, sorted for stable output.
---A layer whose trigger emulates no modifier cannot be reached and is reported.
---@param layout table
---@param modifiers table<string, string>
---@return { key: string, action: table }[] bindings, string[] unreachable
function Model.ToBindings(layout, modifiers)
    local out, unreachable = {}, {}
    for _, layer in ipairs(Model.LAYERS) do
        local buttons = layout.layers and layout.layers[layer]
        if buttons and next(buttons) then
            local prefix = ""
            if layer ~= "BASE" then
                prefix = modifiers[layer] and (modifiers[layer] .. "-") or nil
            end
            if prefix then
                for button, action in pairs(buttons) do
                    out[#out + 1] = { key = prefix .. button, action = action }
                end
            else
                unreachable[#unreachable + 1] = layer
            end
        end
    end
    table.sort(out, function(a, b)
        return a.key < b.key
    end)
    return out, unreachable
end
