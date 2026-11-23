-- Loaded last: wires saved data and starts the modules.
local ADDON_NAME, ns = ...

ns.Events.OnGame("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then
        return
    end
    local db, warning = ns.Store.Load(GamepadGrimoireDB)
    GamepadGrimoireDB = db
    ns.db = db
    if warning then
        ns.Wow.Print(warning)
    end
    ns.CallModules("OnInitialize")
end)

ns.Events.OnGame("PLAYER_LOGIN", function()
    ns.CallModules("OnEnable")
end)
