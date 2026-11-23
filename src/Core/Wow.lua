-- The only file allowed to touch WoW's global API (enforced by .luacheckrc).
-- Slices call ns.Wow.*; tests inject a fake before this file runs.
local _, ns = ...
if ns.Wow then
    return
end

local W = {}

W.InCombatLockdown = InCombatLockdown
W.CreateFrame = CreateFrame
W.SetOverrideBinding = SetOverrideBinding
W.SetOverrideBindingSpell = SetOverrideBindingSpell
W.SetOverrideBindingItem = SetOverrideBindingItem
W.SetOverrideBindingMacro = SetOverrideBindingMacro
W.ClearOverrideBindings = ClearOverrideBindings
W.GetSpecialization = GetSpecialization

---@param name string
---@return string?
function W.GetCVar(name)
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar(name)
    end
    return GetCVar(name)
end

---@param spellID number
---@return string?
function W.GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    end
    return (GetSpellInfo(spellID))
end

---Active controller as reported by the client, or nil when none is connected.
---@return {name?: string, vendorID?: number, productID?: number, labelStyle?: string}?
function W.GetGamePadDevice()
    if not (C_GamePad and C_GamePad.GetActiveDeviceID) then
        return nil
    end
    local id = C_GamePad.GetActiveDeviceID()
    if not id then
        return nil
    end
    local raw = C_GamePad.GetDeviceRawState and C_GamePad.GetDeviceRawState(id)
    local mapped = C_GamePad.GetDeviceMappedState and C_GamePad.GetDeviceMappedState(id)
    return {
        name = raw and raw.name,
        vendorID = raw and raw.vendorID,
        productID = raw and raw.productID,
        labelStyle = mapped and mapped.labelStyle,
    }
end

---@return string key "Name-Realm"
function W.CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

---Blizzard's built-in compression (nil on clients without C_EncodingUtil).
W.CompressString = C_EncodingUtil and C_EncodingUtil.CompressString
W.DecompressString = C_EncodingUtil and C_EncodingUtil.DecompressString

---@param names string[] e.g. { "/gg", "/grimoire" }
---@param handler fun(msg: string)
function W.RegisterSlash(names, handler)
    local key = "GAMEPADGRIMOIRE"
    for i, name in ipairs(names) do
        _G["SLASH_" .. key .. i] = name
    end
    SlashCmdList[key] = handler
end

---@param msg string
function W.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffc8a2ffGamepad Grimoire|r " .. msg)
end

-- UI ------------------------------------------------------------------------

W.UIParent = UIParent
W.IsShiftKeyDown = IsShiftKeyDown
W.IsControlKeyDown = IsControlKeyDown

---@return boolean true while a text box has keyboard focus (typing in chat...)
function W.IsTyping()
    return GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() ~= nil or false
end

---@param seconds number
---@param fn function
function W.After(seconds, fn)
    C_Timer.After(seconds, fn)
end

---@param name string
---@return boolean
function W.AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
end

-- Keybinds and what is behind them --------------------------------------------

---Command bound to a key in the player's own keybinds ("" / nil when unbound).
---@param key string
---@return string?
function W.GetBindingAction(key)
    local a = GetBindingAction(key, true)
    return a ~= "" and a or nil
end

local function spellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(id)
        return i and i.iconID, i and i.name
    end
    local name, _, icon = GetSpellInfo(id)
    return icon, name
end

local function itemInfo(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return icon, name
end

local function slotInfo(slot)
    if not HasAction(slot) then
        return nil, nil
    end
    local kind, id = GetActionInfo(slot)
    local name
    if kind == "spell" then
        name = select(2, spellInfo(id))
    elseif kind == "macro" then
        name = GetMacroInfo(id)
    elseif kind == "item" then
        name = select(2, itemInfo(id))
    end
    return GetActionTexture(slot), name
end

-- first action slot of each bar binding prefix
local BAR_BASE = {
    ACTIONBUTTON = 0,
    MULTIACTIONBAR1BUTTON = 60,
    MULTIACTIONBAR2BUTTON = 48,
    MULTIACTIONBAR3BUTTON = 24,
    MULTIACTIONBAR4BUTTON = 36,
}

---Icon and display name for a binding command, resolving action-bar slots, pet
---actions, SPELL/ITEM/MACRO commands and Blizzard's binding names.
---@param command string
---@return any icon, string? name
function W.DescribeCommand(command)
    local bar, n = command:match("^(%u+%d?BUTTON)(%d+)$")
    if bar and BAR_BASE[bar] then
        return slotInfo(BAR_BASE[bar] + tonumber(n))
    end
    n = command:match("^BONUSACTIONBUTTON(%d+)$")
    if n then
        local name, tex, isToken = GetPetActionInfo(tonumber(n))
        if isToken then
            name, tex = _G[name] or name, _G[tex] or tex
        end
        return tex, name and ("Pet: " .. name)
    end
    local kind, arg = command:match("^(%u+) (.+)$")
    if kind == "SPELL" then
        return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(arg), arg
    elseif kind == "MACRO" then
        local _, icon = GetMacroInfo(arg)
        return icon, arg
    elseif kind == "ITEM" then
        return nil, arg
    end
    return nil, _G["BINDING_NAME_" .. command] or command
end

---@param action table a Bindings.Model action
---@return any icon, string? name
function W.DescribeAction(action)
    if action.type == "spell" then
        return spellInfo(action.id)
    elseif action.type == "item" then
        return itemInfo(action.id)
    elseif action.type == "macro" then
        local _, icon = GetMacroInfo(action.name)
        return icon, action.name
    elseif action.type == "command" then
        return W.DescribeCommand(action.command)
    end
end

---Facts about this client used by /gg diag (APIs that differ between versions).
function W.Capabilities()
    return {
        encoding = C_EncodingUtil ~= nil,
        gamepadApi = C_GamePad ~= nil,
        gamepadEnabled = W.GetCVar("GamePadEnable"),
        build = select(4, GetBuildInfo()),
        version = (GetBuildInfo()),
    }
end

ns.Wow = W
