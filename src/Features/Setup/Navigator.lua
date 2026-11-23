-- Controller-driven setup: a pure state machine. Inputs are abstract
-- ("UP", "ACCEPT"...) so the same logic serves gamepad and keyboard; the result is
-- an effect for Setup.lua to carry out. No WoW API here.
--
-- Screens:
--   rows    pick a button on the card    D-pad move, LB/RB layer, A pick, X clear, Y menu, B close
--   picker  pick what to bind            D-pad move, LB/RB category, A assign, B back
--   menu    profiles and options         D-pad move, A choose, left/right adjust, B back
--   keys    on-screen keyboard           D-pad move, A type, X delete, LB/RB case, Y / Done ok, B cancel
-- View (Select) flips the card between the front and back of the controller.
local _, ns = ...

local Navigator = {}
ns.Setup = ns.Setup or {}
ns.Setup.Navigator = Navigator

Navigator.LAYERS = { "BASE", "LT", "RT" }
Navigator.PAGE = 8 -- list rows visible at once (fits the picture area)

---@param columns { left: string[], right: string[] } buttons in card order
---@return table state
function Navigator.New(columns)
    return {
        screen = "rows",
        layer = "BASE",
        columns = columns,
        col = #columns.left > 0 and "left" or "right",
        index = 1,
        picker = { category = 1, index = 1, top = 1 },
        menu = { index = 1, top = 1 },
        keys = nil, -- { text, row, col, upper, purpose } while the keyboard is open
    }
end

-- On-screen keyboard (profile names). Rows of keys; the last row is commands.
Navigator.KEYS = {
    { "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" },
    { "k", "l", "m", "n", "o", "p", "q", "r", "s", "t" },
    { "u", "v", "w", "x", "y", "z", "-", "_", "'", "." },
    { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
    { "Aa", "Space", "Del", "Done" },
}
Navigator.MAX_NAME = 24

---Opens the keyboard with `text` to edit; ACCEPT on Done returns
---{ kind = purpose, text = ... }.
function Navigator.OpenKeys(state, text, purpose)
    state.keys = { text = text or "", row = 1, col = 1, upper = true, purpose = purpose }
    state.screen = "keys"
end

---Moves the row cursor to `button` if it is on the current card.
---@return boolean found
function Navigator.Select(state, button)
    for _, side in ipairs({ "left", "right" }) do
        for i, b in ipairs(state.columns[side] or {}) do
            if b == button then
                state.col, state.index = side, i
                return true
            end
        end
    end
    return false
end

---@return string|nil button under the cursor on the rows screen
function Navigator.Button(state)
    local list = state.columns[state.col]
    return list and list[state.index]
end

local function clamp(i, n)
    if n < 1 then
        return 1
    end
    return math.max(1, math.min(n, i))
end

local function cycle(i, n, d)
    return ((i - 1 + d) % n) + 1
end

-- keeps the selected list entry inside the visible page
local function scroll(list)
    if list.index < list.top then
        list.top = list.index
    elseif list.index > list.top + Navigator.PAGE - 1 then
        list.top = list.index - Navigator.PAGE + 1
    end
end

local function layerStep(state, d)
    for i, l in ipairs(Navigator.LAYERS) do
        if l == state.layer then
            state.layer = Navigator.LAYERS[cycle(i, #Navigator.LAYERS, d)]
            return
        end
    end
end

local function rows(state, input)
    local list = state.columns[state.col] or {}
    if input == "UP" or input == "DOWN" then
        state.index = clamp(state.index + (input == "UP" and -1 or 1), #list)
    elseif input == "LEFT" or input == "RIGHT" then
        local want = input == "LEFT" and "left" or "right"
        if #(state.columns[want] or {}) > 0 then
            state.col = want
            state.index = clamp(state.index, #state.columns[want])
        end
    elseif input == "PREV" or input == "NEXT" then
        layerStep(state, input == "PREV" and -1 or 1)
    elseif input == "ACCEPT" then
        if Navigator.Button(state) then
            state.screen = "picker"
            state.picker.index, state.picker.top = 1, 1
        end
    elseif input == "CLEAR" then
        local b = Navigator.Button(state)
        if b then
            return { kind = "clear", layer = state.layer, button = b }
        end
    elseif input == "MENU" then
        state.screen = "menu"
        state.menu.index, state.menu.top = 1, 1
    elseif input == "FLIP" then
        return { kind = "flip" }
    elseif input == "BACK" then
        return { kind = "close" }
    end
end

local function picker(state, input, ctx)
    local cats = ctx.categories or {}
    local p = state.picker
    p.category = clamp(p.category, #cats)
    local items = cats[p.category] and cats[p.category].items or {}
    if input == "UP" or input == "DOWN" then
        p.index = clamp(p.index + (input == "UP" and -1 or 1), #items)
        scroll(p)
    elseif input == "LEFT" or input == "RIGHT" then
        p.index = clamp(p.index + (input == "LEFT" and -Navigator.PAGE or Navigator.PAGE), #items)
        scroll(p)
    elseif input == "PREV" or input == "NEXT" then
        if #cats > 0 then
            p.category = cycle(p.category, #cats, input == "PREV" and -1 or 1)
            p.index, p.top = 1, 1
        end
    elseif input == "ACCEPT" then
        local item = items[p.index]
        if item then
            state.screen = "rows"
            return { kind = "assign", layer = state.layer, button = Navigator.Button(state), action = item.action }
        end
    elseif input == "BACK" then
        state.screen = "rows"
    end
end

local function menu(state, input, ctx)
    local items = ctx.menu or {}
    local m = state.menu
    m.index = clamp(m.index, #items)
    local item = items[m.index]
    if input == "UP" or input == "DOWN" then
        m.index = clamp(m.index + (input == "UP" and -1 or 1), #items)
        scroll(m)
    elseif (input == "LEFT" or input == "RIGHT") and item and item.adjust then
        return { kind = item.adjust, delta = input == "LEFT" and -1 or 1 }
    elseif input == "ACCEPT" and item then
        if item.effect and item.effect.kind ~= "close" and not item.stay then
            state.screen = "rows"
        end
        return item.effect
    elseif input == "BACK" then
        state.screen = "rows"
    end
end

local function keyAt(k)
    local row = Navigator.KEYS[k.row]
    return row[math.min(k.col, #row)]
end

local function keys(state, input)
    local k = state.keys
    if input == "UP" or input == "DOWN" then
        k.row = clamp(k.row + (input == "UP" and -1 or 1), #Navigator.KEYS)
        k.col = clamp(k.col, #Navigator.KEYS[k.row])
    elseif input == "LEFT" or input == "RIGHT" then
        k.col = cycle(k.col, #Navigator.KEYS[k.row], input == "LEFT" and -1 or 1)
    elseif input == "PREV" or input == "NEXT" then
        k.upper = not k.upper
    elseif input == "CLEAR" then
        k.text = k.text:sub(1, -2)
    elseif input == "BACK" then
        state.keys, state.screen = nil, "menu"
    elseif input == "MENU" or (input == "ACCEPT" and keyAt(k) == "Done") then
        local text = k.text:gsub("^%s+", ""):gsub("%s+$", "")
        state.keys, state.screen = nil, "rows"
        if text ~= "" then
            return { kind = k.purpose, text = text }
        end
    elseif input == "ACCEPT" then
        local key = keyAt(k)
        if key == "Aa" then
            k.upper = not k.upper
        elseif key == "Del" then
            k.text = k.text:sub(1, -2)
        elseif #k.text < Navigator.MAX_NAME then
            local ch = key == "Space" and " " or (k.upper and key:upper() or key)
            k.text = k.text .. ch
            if k.upper and ch:match("%a") then
                k.upper = false -- capital first letter, then lower case
            end
        end
    end
end

---Handles one input. ctx = { categories = { {name, items = { {name, action} }} },
---menu = { {name, effect?, adjust?} } }.
---@param state table
---@param input string UP DOWN LEFT RIGHT PREV NEXT ACCEPT BACK CLEAR MENU FLIP
---@param ctx table
---@return table|nil effect
function Navigator.Handle(state, input, ctx)
    if state.screen == "rows" then
        return rows(state, input)
    elseif state.screen == "picker" then
        return picker(state, input, ctx)
    elseif state.screen == "menu" then
        return menu(state, input, ctx)
    elseif state.screen == "keys" then
        return keys(state, input)
    end
end

-- Gamepad buttons and keys -> abstract inputs
Navigator.INPUT = {
    PADDUP = "UP",
    PADDDOWN = "DOWN",
    PADDLEFT = "LEFT",
    PADDRIGHT = "RIGHT",
    PADLSHOULDER = "PREV",
    PADRSHOULDER = "NEXT",
    PAD1 = "ACCEPT",
    PAD2 = "BACK",
    PAD3 = "CLEAR",
    PAD4 = "MENU",
    PADFORWARD = "MENU",
    PADBACK = "FLIP",
    UP = "UP",
    DOWN = "DOWN",
    LEFT = "LEFT",
    RIGHT = "RIGHT",
    Q = "PREV",
    E = "NEXT",
    PAGEUP = "PREV",
    PAGEDOWN = "NEXT",
    ENTER = "ACCEPT",
    SPACE = "ACCEPT",
    ESCAPE = "BACK",
    BACKSPACE = "BACK",
    DELETE = "CLEAR",
    X = "CLEAR",
    TAB = "MENU",
    M = "MENU",
    V = "FLIP",
}
