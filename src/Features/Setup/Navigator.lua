-- Controller-driven setup: a pure state machine. Inputs are abstract
-- ("UP", "ACCEPT"...) so the same logic serves gamepad and keyboard; the result is
-- an effect for Setup.lua to carry out. No WoW API here.
--
-- Screens:
--   rows    pick a button on the card    D-pad move, LB/RB layer, A pick, X clear, Y menu, B close
--   picker  pick what to bind            D-pad move, LB/RB category, A assign, B back
--   menu    profiles and options         D-pad move, A choose, left/right adjust, B back
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
    }
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
        if item.effect and item.effect.kind ~= "close" then
            state.screen = "rows"
        end
        return item.effect
    elseif input == "BACK" then
        state.screen = "rows"
    end
end

---Handles one input. ctx = { categories = { {name, items = { {name, action} }} },
---menu = { {name, effect?, adjust?} } }.
---@param state table
---@param input string UP DOWN LEFT RIGHT PREV NEXT ACCEPT BACK CLEAR MENU
---@param ctx table
---@return table|nil effect
function Navigator.Handle(state, input, ctx)
    if state.screen == "rows" then
        return rows(state, input)
    elseif state.screen == "picker" then
        return picker(state, input, ctx)
    elseif state.screen == "menu" then
        return menu(state, input, ctx)
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
}
