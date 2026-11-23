-- The only file allowed to touch WoW's global API (enforced by .luacheckrc).
-- Slices call ns.Wow.*; tests inject a fake before this file runs.
-- WoW globals are only allowed here; luacheck keeps them out of every other file.
---@diagnostic disable: undefined-global
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

---Current specialization (retail) or talent group (classic-style clients such as
---WoW: Forever, which have no GetSpecialization), or nil when neither exists.
---@return number?
function W.GetSpecialization()
    if GetSpecialization then
        return GetSpecialization()
    elseif C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        return C_SpecializationInfo.GetSpecialization()
    elseif GetActiveTalentGroup then
        return GetActiveTalentGroup()
    end
    return nil
end

---Game event fired when the value of GetSpecialization() changes on this client.
W.SPEC_CHANGED_EVENT = GetSpecialization and "PLAYER_SPECIALIZATION_CHANGED" or "ACTIVE_TALENT_GROUP_CHANGED"

---Reports an error through the game's error handler without stopping the caller.
---@param err any
function W.ReportError(err)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(err)
    else
        print(err)
    end
end

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

local function mappedState()
    if not (C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetDeviceMappedState) then
        return nil
    end
    local id = C_GamePad.GetActiveDeviceID()
    return id and C_GamePad.GetDeviceMappedState(id)
end

---Binding name of mapped button `i` (1-based index into the mapped state).
local function buttonName(i)
    return C_GamePad.ButtonIndexToBinding and C_GamePad.ButtonIndexToBinding(i - 1)
end

---Gamepad buttons held right now, by binding name ("PAD1", "PADPADDLE1"...).
---Read-only polling: it never takes input away from the game.
---@return table<string, boolean>
function W.PressedButtons()
    local out = {}
    local st = mappedState()
    if st and st.buttons then
        for i, down in ipairs(st.buttons) do
            if down then
                local name = buttonName(i)
                if name then
                    out[name] = true
                end
            end
        end
    end
    return out
end

---Every button the active controller reports, in index order (for /gg diag:
---shows whether back buttons / paddles reach the game at all).
---@return string[]
function W.KnownButtons()
    local out = {}
    local st = mappedState()
    for i = 1, st and st.buttons and #st.buttons or 0 do
        out[i] = buttonName(i) or ("#" .. (i - 1))
    end
    return out
end

---@return string key "Name-Realm"
function W.CharacterKey()
    -- GetRealmName() can be "" early on (and on WoW: Forever), so fall back through
    -- UnitFullName / GetNormalizedRealmName before giving up on the realm.
    local name, realm = UnitFullName("player")
    name = name or UnitName("player") or "?"
    if not realm or realm == "" then
        realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    end
    if not realm or realm == "" then
        return name
    end
    return name .. "-" .. realm
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

---What the mouse cursor is holding (dragged from the spellbook, bags, macros...).
---@return { kind: string, id?: number, name?: string }|nil
function W.GetCursorAction()
    local kind, a, _, c = GetCursorInfo()
    if kind == "spell" then
        return { kind = "spell", id = c }
    elseif kind == "item" then
        return { kind = "item", id = a }
    elseif kind == "macro" then
        return { kind = "macro", name = (GetMacroInfo(a)) }
    elseif kind then
        return { kind = kind }
    end
end

W.ClearCursor = ClearCursor

---Lets Escape close a named frame (Blizzard's UISpecialFrames list).
---@param frameName string
function W.CloseOnEscape(frameName)
    table.insert(UISpecialFrames, frameName)
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

---Command bound to a key in the player's own (saved) keybinds, ignoring override
---bindings - including this addon's own. nil when unbound.
---@param key string
---@return string?
function W.GetBindingAction(key)
    local a = GetBindingAction(key, false)
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
    if command:find("^CLICK GamepadGrimoireToggle") then
        return "Interface\\Icons\\INV_Misc_Book_09", "Controller setup"
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

-- What the player can bind (controller setup lists) ------------------------------

local function isPassive(id)
    if C_Spell and C_Spell.IsSpellPassive then
        return C_Spell.IsSpellPassive(id)
    end
    return IsPassiveSpell and IsPassiveSpell(id) or false
end

local function byName(a, b)
    return (a.name or "") < (b.name or "")
end

---Active spells in the player's spellbook (modern C_SpellBook or the classic API).
---@return { id: number, name: string, icon: any }[]
function W.ListSpells()
    local out, seen = {}, {}
    -- one entry per spell name: classic spellbooks list every rank, and later
    -- entries are higher ranks, so the last one wins
    local function add(id)
        if id and not isPassive(id) then
            local icon, name = spellInfo(id)
            if name then
                local entry = { id = id, name = name, icon = icon }
                if seen[name] then
                    out[seen[name]] = entry
                else
                    out[#out + 1] = entry
                    seen[name] = #out
                end
            end
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
        local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and (spellType == nil or item.itemType == spellType) and not item.isPassive then
                        add(item.spellID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, count = GetSpellTabInfo(tab)
            for i = offset + 1, offset + count do
                local kind, id = GetSpellBookItemInfo(i, "spell")
                if kind == "SPELL" then
                    add(id)
                end
            end
        end
    end
    table.sort(out, byName)
    return out
end

---Account and character macros.
---@return { name: string, icon: any }[]
function W.ListMacros()
    local out = {}
    local account, character = GetNumMacros()
    local function add(i)
        local name, icon = GetMacroInfo(i)
        if name then
            out[#out + 1] = { name = name, icon = icon }
        end
    end
    for i = 1, account or 0 do
        add(i)
    end
    for i = 121, 120 + (character or 0) do
        add(i)
    end
    return out
end

---Usable items (with an on-use effect) in the backpack and bags.
---@return { id: number, name: string, icon: any }[]
function W.ListBagItems()
    local out, seen = {}, {}
    local C = C_Container
    if not (C and C.GetContainerNumSlots) then
        return out
    end
    local itemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    for bag = 0, 4 do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] and itemSpell and itemSpell(id) then
                seen[id] = true
                local icon, name = itemInfo(id)
                out[#out + 1] =
                    { id = id, name = name or info.itemName or ("item " .. id), icon = icon or info.iconFileID }
            end
        end
    end
    table.sort(out, byName)
    return out
end

---Display name of a key-binding command ("JUMP" -> "Jump").
---@param command string
---@return string
function W.BindingName(command)
    return _G["BINDING_NAME_" .. command] or command
end

---@return number width, number height of the UI in UI units
function W.ScreenSize()
    return UIParent:GetWidth(), UIParent:GetHeight()
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
