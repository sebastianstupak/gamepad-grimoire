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

ns.Wow = W
