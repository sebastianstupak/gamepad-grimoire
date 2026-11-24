-- Controller setup: configure everything with the controller, no chat needed.
-- Opened with the pin chord (LT+R3 by default) or /gg setup; closes on B or when
-- combat starts (capturing gamepad input is protected in combat). The logic lives
-- in Navigator (pure); this module feeds it input and carries out its effects.
local _, ns = ...

local Setup = ns.Setup or {}
ns.Setup = Setup
local M = ns.NewModule("Setup")

local state -- Navigator state while open
local ctx -- { categories, menu }
local input -- frame that captures gamepad buttons and keys
local panel, panelCard
local wasPinned
local pendingDelete -- profile waiting for a second A to be deleted
local status -- last message, shown on the panel

local function N()
    return ns.Setup.Navigator
end

local function say(msg)
    status = msg
    ns.Wow.Print(msg)
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
    local P = ns.Profiles
    local items = {}
    local active = P.ActiveName()
    for _, name in ipairs(P.List()) do
        items[#items + 1] = {
            name = (name == active and "|cffffd100> " or "Use profile: ") .. name .. (name == active and "|r" or ""),
            effect = { kind = "use", name = name },
        }
    end
    items[#items + 1] = { name = "New empty profile...", effect = { kind = "keys", purpose = "new", text = "" } }
    items[#items + 1] = {
        name = "Copy " .. active .. "...",
        effect = { kind = "keys", purpose = "copy", text = "Copy of " .. active },
    }
    if active ~= ns.Store.DEFAULT_PROFILE then
        items[#items + 1] = {
            name = "Rename " .. active .. "...",
            effect = { kind = "keys", purpose = "rename", text = active },
        }
        items[#items + 1] = {
            name = pendingDelete == active and ("|cffff6060Press A again to delete " .. active .. "|r")
                or ("Delete " .. active),
            effect = { kind = "delete" },
            stay = true,
        }
    end
    local spec = ns.Wow.GetSpecialization()
    if spec then
        local own = P.SpecProfile(spec) == active
        items[#items + 1] = {
            name = ("Use %s for this specialization only:  < %s >"):format(active, own and "yes" or "no"),
            effect = { kind = "spec" },
            stay = true,
        }
    end
    local profile = P.ActiveProfile()
    items[#items + 1] = {
        name = "Controller picture:  < " .. controllerName(profile.controller or "auto") .. " >",
        adjust = "controller",
        effect = { kind = "controller", delta = 1 },
        stay = true,
    }
    local scale = ns.db.settings.scale
    items[#items + 1] = {
        name = ("Card size:  < %s >"):format(scale and ("%.1fx"):format(scale) or "automatic"),
        adjust = "scale",
        effect = { kind = "scale", delta = 0 },
        stay = true,
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

local KEYS_TITLE = { new = "New profile name", copy = "Name of the copy", rename = "New name" }

local function render()
    if not state then
        return
    end
    ns.CheatSheet.SetSetup(state.layer, N().Button(state), true)
    local card = ns.CheatSheet.Card()
    local p = ensurePanel(card)
    if state.screen == "picker" then
        local cat = ctx.categories[state.picker.category] or { name = "-", items = {} }
        local glyph = ns.CheatSheet.Glyphs.For(card.def, N().Button(state) or "")
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
            status or "A choose   left / right change   B back"
        )
    elseif state.screen == "keys" then
        p:ShowKeys(KEYS_TITLE[state.keys.purpose] or "Name", state.keys, N().KEYS)
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

-- the card changed (other controller, other side): keep the cursor on it
local function syncColumns(select)
    local card = ns.CheatSheet.Card()
    state.columns = card.columns
    if not (select and N().Select(state, select)) then
        local list = state.columns[state.col] or {}
        if #list == 0 then
            state.col = state.col == "left" and "right" or "left"
            list = state.columns[state.col] or {}
        end
        state.index = math.max(1, math.min(state.index, #list))
    end
end

local function deleteActive()
    local P = ns.Profiles
    local name = P.ActiveName()
    if pendingDelete ~= name then
        pendingDelete = name
        return
    end
    pendingDelete = nil
    local spec = ns.Wow.GetSpecialization()
    if spec and P.SpecProfile(spec) == name then
        P.ClearSpec(spec)
    end
    P.Use(ns.Store.DEFAULT_PROFILE)
    local ok, err = P.Delete(name)
    if ok then
        say("deleted profile " .. name)
    else
        P.Use(name)
        say(err)
    end
end

local function named(kind, text)
    local P = ns.Profiles
    local ok, err
    if kind == "new" then
        ok, err = P.Create(text)
    elseif kind == "copy" then
        ok, err = P.Create(text, P.ActiveName())
    elseif kind == "rename" then
        ok, err = P.Rename(P.ActiveName(), text)
    end
    if not ok then
        return say(err)
    end
    P.Use(text)
    say((kind == "rename" and "renamed to " or "now using ") .. text)
end

local function apply(effect)
    local kind = effect.kind
    if kind ~= "delete" then
        pendingDelete = nil
    end
    status = nil
    if kind == "close" then
        return Setup.Close()
    elseif kind == "assign" or kind == "clear" then
        local ok, err = ns.Editor.Assign(effect.layer, effect.button, kind == "assign" and effect.action or nil)
        if not ok then
            say(err)
        end
    elseif kind == "flip" then
        ns.CheatSheet.Flip()
    elseif kind == "use" then
        ns.Profiles.Use(effect.name)
    elseif kind == "keys" then
        N().OpenKeys(state, effect.text, effect.purpose)
    elseif kind == "new" or kind == "copy" or kind == "rename" then
        named(kind, effect.text)
    elseif kind == "delete" then
        deleteActive()
    elseif kind == "spec" then
        local spec = ns.Wow.GetSpecialization()
        local P = ns.Profiles
        if spec and P.SpecProfile(spec) == P.ActiveName() then
            P.ClearSpec(spec)
        elseif spec then
            P.Use(P.ActiveName(), spec)
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
    elseif kind == "scale" then
        local s = ns.db.settings.scale or ns.CheatSheet.Scale()
        if effect.delta ~= 0 then
            ns.CheatSheet.SetScale(math.max(0.6, math.min(2.5, s + effect.delta * 0.1)))
        else
            ns.CheatSheet.SetScale(nil) -- A on the size entry: back to automatic
        end
    end
    if state then
        ctx.menu = buildMenu()
        syncColumns(N().Button(state))
    end
end

-- A button that is not a navigation button selects its own row (press L4 and
-- the cursor jumps to L4, flipping to the back of the controller if needed).
local function selectPressed(button)
    if state.screen ~= "rows" or not button:match("^PAD") then
        return false
    end
    if N().Select(state, button) then
        return true
    end
    local card = ns.CheatSheet.Card()
    local front = card.def.view == "back" and ns.Controllers.Registry.Get(card.def.front) or card.def
    local _, side = ns.Controllers.Registry.ViewFor(front, button)
    if side and side ~= ns.CheatSheet.ViewName() then
        ns.CheatSheet.Flip(side)
        syncColumns(button)
        return true
    end
    return false
end

---Feeds one gamepad button or key (WoW names: "PAD1", "PADDUP", "ENTER"...).
---@param key string
---@return boolean handled
function Setup.Press(key)
    if not state then
        return false
    end
    -- a real keyboard can type into the on-screen keyboard directly
    if state.screen == "keys" and #key == 1 and key:match("[%w%-_'.]") then
        if #state.keys.text < N().MAX_NAME then
            state.keys.text = state.keys.text .. (#state.keys.text == 0 and key:upper() or key:lower())
        end
        render()
        return true
    end
    local abstract = N().INPUT[key]
    if not abstract then
        local handled = selectPressed(key)
        if handled then
            render()
        end
        return handled
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
    pendingDelete, status = nil, nil
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

---@return table[] current menu entries (tests)
function Setup._menu()
    return ctx and ctx.menu or {}
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
