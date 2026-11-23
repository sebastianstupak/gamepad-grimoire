-- Event bus. Slices talk to each other through internal messages (Emit/On) and
-- receive game events through OnGame, so no slice reaches into another's state.
local _, ns = ...

local Events = {}
ns.Events = Events

local listeners = {} ---@type table<string, function[]>
local gameListeners = {} ---@type table<string, function[]>
local frame

---Subscribes to an internal message. Returns an unsubscribe function.
---@param message string
---@param fn function
---@return fun()
function Events.On(message, fn)
    local list = listeners[message] or {}
    listeners[message] = list
    list[#list + 1] = fn
    return function()
        for i = #list, 1, -1 do
            if list[i] == fn then
                table.remove(list, i)
            end
        end
    end
end

---@param message string
function Events.Emit(message, ...)
    local list = listeners[message]
    if not list then
        return
    end
    -- copy so listeners may unsubscribe while being called
    local snapshot = { unpack(list) }
    for i = 1, #snapshot do
        snapshot[i](...)
    end
end

local function dispatch(_, event, ...)
    local list = gameListeners[event]
    if list then
        local snapshot = { unpack(list) }
        for i = 1, #snapshot do
            snapshot[i](event, ...)
        end
    end
end

---Subscribes to a WoW game event.
---@param event string
---@param fn fun(event: string, ...)
function Events.OnGame(event, fn)
    if not frame then
        frame = ns.Wow.CreateFrame("Frame")
        frame:SetScript("OnEvent", dispatch)
    end
    local list = gameListeners[event]
    if not list then
        list = {}
        gameListeners[event] = list
        frame:RegisterEvent(event)
    end
    list[#list + 1] = fn
end
