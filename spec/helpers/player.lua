-- A player at the game, for end-to-end specs: types in chat, presses and holds
-- controller buttons and keys, clicks what is on screen and reads it back.
-- Input goes where the game would send it (slash handlers, frames that capture
-- input, override bindings), never straight into the addon's functions.
local Addon = require("spec.helpers.addon")

local Player = {}
Player.__index = Player

---Logs in with `saved` SavedVariables and returns the player.
---@param saved? table
---@return table player
function Player.login(saved)
    local ns, wow = Addon.start(saved)
    wow.pressed = {}
    return setmetatable({ ns = ns, wow = wow, did = {}, read = 0 }, Player)
end

-- every widget below `widget`, depth first
local function walk(widget, fn)
    fn(widget)
    for _, c in ipairs(rawget(widget, "children") or {}) do
        walk(c, fn)
    end
end

local function visible(widget)
    local w = widget
    while w do
        if rawget(w, "shown") == false then
            return false
        end
        w = rawget(w, "parent")
    end
    return true
end

---Texts the player can read on screen right now.
---@return string[]
function Player:screen()
    local out, seen = {}, {}
    for _, f in ipairs(self.wow.frames) do
        walk(f, function(w)
            local t = rawget(w, "text")
            if type(t) == "string" and not seen[w] and visible(w) then
                seen[w] = true
                out[#out + 1] = tostring(t)
            end
        end)
    end
    return out
end

---@param pattern string Lua pattern
---@return boolean
function Player:sees(pattern)
    for _, t in ipairs(self:screen()) do
        if t:find(pattern) then
            return true
        end
    end
    return false
end

---Texts drawn highlighted (near-black on the gold bar): the selected entry of
---a setup list or key of the on-screen keyboard, and the card's focused row.
---@return string[]
function Player:highlighted()
    local out, seen = {}, {}
    for _, f in ipairs(self.wow.frames) do
        walk(f, function(w)
            local c = rawget(w, "calls").SetTextColor
            local dark = c and c[1] < 0.2 and c[2] < 0.2 and c[3] < 0.2
            if dark and not seen[w] and type(rawget(w, "text")) == "string" and visible(w) then
                seen[w] = true
                out[#out + 1] = rawget(w, "text")
            end
        end)
    end
    return out
end

-- true when a highlighted text matches; `exact` compares whole texts, ignoring case
function Player:isHighlighted(pattern, exact)
    for _, t in ipairs(self:highlighted()) do
        if exact and t:lower() == pattern:lower() or not exact and t:find(pattern) then
            return true
        end
    end
    return false
end

---Moves through a setup list with the D-pad until the highlighted entry matches.
function Player:scrollTo(pattern)
    for _ = 1, 40 do
        if self:isHighlighted(pattern) then
            return
        end
        self:tap("PADDDOWN")
    end
    error("never reached '" .. pattern .. "'; highlighted: " .. table.concat(self:highlighted(), " | "))
end

---Types `word` on the on-screen keyboard with the D-pad and A only.
function Player:typeOnPad(word)
    for ch in word:gmatch(".") do
        for _ = 1, 6 do
            self:tap("PADDUP") -- top row
        end
        local moved = 0
        while not self:isHighlighted(ch, true) do
            -- walk the grid: right along a row (it wraps), then down to the next
            moved = moved + 1
            assert(moved < 120, "key " .. ch .. " not found")
            if moved % 11 == 0 then
                self:tap("PADDDOWN")
            else
                self:tap("PADDRIGHT")
            end
        end
        self:tap("PAD1")
    end
end

---Chat lines printed since the last call.
---@return string[]
function Player:chatLines()
    local printed = self.wow.printed
    local out = {}
    for i = self.read + 1, #printed do
        out[#out + 1] = printed[i]
    end
    self.read = #printed
    return out
end

---Types a line in chat, e.g. "/gg profile new Raid". Returns the lines it printed.
---@param line string
---@return string[]
function Player:chat(line)
    self:chatLines()
    local cmd, rest = line:match("^(/%S+)%s*(.*)$")
    local slash = assert(self.wow.slash, "no slash command registered")
    local known = false
    for _, name in ipairs(slash.names) do
        known = known or name == cmd
    end
    assert(known, "no addon handles " .. tostring(cmd))
    slash.handler(rest)
    return self:chatLines()
end

---True when one of `lines` matches `pattern`.
function Player.any(lines, pattern)
    for _, l in ipairs(lines) do
        if tostring(l):find(pattern) then
            return true
        end
    end
    return false
end

-- the newest visible frame that captures controller buttons / keys, if any
local function capturing(wow, enable)
    for i = #wow.frames, 1, -1 do
        local f = wow.frames[i]
        local on = rawget(f, "calls")[enable]
        if on and on[1] and visible(f) then
            return f
        end
    end
end

local function modifiers(wow)
    return (wow.ctrl and "CTRL-" or "") .. (wow.shift and "SHIFT-" or "")
end

-- what the game does with a press that no frame captured: run its binding
local function runBinding(self, key)
    -- priority override bindings win, then the others, then the player's own
    local binding
    for _, set in pairs(self.wow.bindings) do
        local b = set[key]
        if b and (not binding or (b.priority and not binding.priority)) then
            binding = b
        end
    end
    if not binding and self.wow.keybinds[key] then
        binding = { kind = "command", value = self.wow.keybinds[key] }
    end
    if not binding then
        return
    end
    local click = binding.kind == "command" and binding.value:match("^CLICK ([^:]+)")
    if click then -- a button on screen, not a game action
        for _, f in ipairs(self.wow.frames) do
            if rawget(f, "name") == click then
                rawget(f, "scripts").OnClick(f, "LeftButton", true)
            end
        end
        return
    end
    self.did[#self.did + 1] = binding.kind .. " " .. tostring(binding.value)
end

-- triggers the client turns into Shift / Ctrl while held (GamePadEmulate* CVars)
local function modifierOf(wow, button)
    if wow.cvars.GamePadEmulateShift == button then
        return "shift"
    elseif wow.cvars.GamePadEmulateCtrl == button then
        return "ctrl"
    end
end

---Presses a controller button down (WoW names: PAD1, PADDUP, PADLTRIGGER...).
function Player:down(button)
    local wow = self.wow
    wow.pressed[button] = true
    local mod = modifierOf(wow, button)
    if mod then
        wow[mod] = true
    end
    local f = capturing(wow, "EnableGamePadButton")
    if f then
        local h = rawget(f, "scripts").OnGamePadButtonDown
        if h then
            h(f, button)
        end
    elseif not mod then
        runBinding(self, modifiers(wow) .. button)
    end
end

---Lets go of a controller button.
function Player:up(button)
    local wow = self.wow
    wow.pressed[button] = nil
    local mod = modifierOf(wow, button)
    if mod then
        wow[mod] = false
    end
end

---Lets the game run for `seconds` (frame updates).
function Player:wait(seconds)
    self.wow.tick(seconds)
end

---Presses and releases buttons one after another, a few frames each.
function Player:tap(...)
    for _, b in ipairs({ ... }) do
        self:down(b)
        self:wait(0.05)
        self:up(b)
        self:wait(0.05)
    end
end

---Holds `buttons` while running fn, then lets go in reverse order.
---@param buttons string[]
---@param fn fun()
function Player:holding(buttons, fn)
    for _, b in ipairs(buttons) do
        self:down(b)
    end
    fn()
    for i = #buttons, 1, -1 do
        self:up(buttons[i])
    end
end

---Presses a keyboard key. Returns true when a frame kept it, false when it reached the game.
---@return boolean kept
function Player:key(key)
    local f = capturing(self.wow, "EnableKeyboard")
    if f then
        rawget(f, "scripts").OnKeyDown(f, key)
        local propagate = rawget(f, "calls").SetPropagateKeyboardInput
        if not (propagate and propagate[1]) then
            return true
        end
    end
    runBinding(self, modifiers(self.wow) .. key)
    return false
end

-- the visible widget with a `script` handler whose text, or a label inside it, matches
local function target(self, pattern, script)
    local found
    for _, f in ipairs(self.wow.frames) do
        walk(f, function(w)
            local scripts = rawget(w, "scripts")
            if found or not (scripts and scripts[script]) or not visible(w) then
                return
            end
            walk(w, function(inner)
                local t = rawget(inner, "text")
                if not found and type(t) == "string" and t:find(pattern) and visible(inner) then
                    found = w
                end
            end)
        end)
    end
    assert(
        found,
        "nothing to " .. script .. " matching '" .. pattern .. "'; on screen: " .. table.concat(self:screen(), " | ")
    )
    return found
end

---Clicks the visible button whose text, or a label inside it, matches `pattern`.
---@param mouse? string "LeftButton" (default) or "RightButton"
function Player:click(pattern, mouse)
    local w = target(self, pattern, "OnClick")
    rawget(w, "scripts").OnClick(w, mouse or "LeftButton", true)
end

---Drags `cursor` (what the spellbook / bags / macro window hand over, e.g.
---{ kind = "spell", id = 172 }) onto the widget matching `pattern` and lets go.
function Player:drag(cursor, pattern)
    self.wow.cursor = cursor
    local w = target(self, pattern, "OnReceiveDrag")
    rawget(w, "scripts").OnReceiveDrag(w)
end

---Opens the addon's page in the game's Settings (Esc > Options > AddOns).
function Player:openSettings(name)
    local f = assert(self.wow.settingsFrames and self.wow.settingsFrames[name], "no settings page " .. name)
    f:Show()
    return f
end

---Actions the game ran from bindings since the last call, e.g. "spell Corruption".
---@return string[]
function Player:actions()
    local out = self.did
    self.did = {}
    return out
end

return Player
