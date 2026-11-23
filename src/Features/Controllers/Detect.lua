-- Picks which controller picture to show: the player's choice, else detection
-- from what the client reports, else the Xbox layout (WoW's default glyphs).
local _, ns = ...

local Detect = {}
ns.Controllers = ns.Controllers or {}
ns.Controllers.Detect = Detect

Detect.FALLBACK = "xbox"

-- USB vendor / product ids. Note: Steam Input presents every controller (the
-- Steam Deck included) as an Xbox 360 pad (045E:028E), so a Deck can only be
-- chosen manually.
local SONY, NINTENDO, MICROSOFT, VALVE = 0x054C, 0x057E, 0x045E, 0x28DE
local DUALSENSE = { [0x0CE6] = true, [0x0DF2] = true }
local STEAM_CONTROLLER = { [0x1102] = true, [0x1142] = true }
-- handhelds and others: vendor -> controller (any product of that vendor)
local BY_VENDOR = {
    [0x0B05] = "rogally", -- ASUS (ROG Ally / Ally X)
    [0x17EF] = "legiongo", -- Lenovo (Legion Go)
    [0x0DB0] = "msiclaw", -- MSI (Claw)
    [0x2DC8] = "8bitdo", -- 8BitDo
}

local LABEL_STYLE = { Shapes = "dualsense", Reverse = "switchpro", Letters = "xbox" }

---@param device { name?: string, vendorID?: number, productID?: number, labelStyle?: string }|nil
---@return string|nil id, string reason
function Detect.FromDevice(device)
    if not device then
        return nil, "no controller connected"
    end
    local v, p = device.vendorID, device.productID
    if v == SONY then
        return DUALSENSE[p] and "dualsense" or "dualshock4", "Sony controller"
    elseif v == NINTENDO then
        return "switchpro", "Nintendo controller"
    elseif v == VALVE then
        return STEAM_CONTROLLER[p] and "steamcontroller" or "steamdeck", "Valve controller"
    elseif v == MICROSOFT then
        return "xbox", "Xbox-compatible controller"
    elseif BY_VENDOR[v] then
        return BY_VENDOR[v], "USB vendor"
    end
    local byStyle = device.labelStyle and LABEL_STYLE[device.labelStyle]
    if byStyle then
        return byStyle, "button label style " .. device.labelStyle
    end
    local name = (device.name or ""):lower()
    if name:find("deck") then
        return "steamdeck", "device name"
    elseif name:find("dualsense") then
        return "dualsense", "device name"
    elseif name:find("steam controller") then
        return "steamcontroller", "device name"
    elseif name:find("ally") then
        return "rogally", "device name"
    elseif name:find("legion") then
        return "legiongo", "device name"
    elseif name:find("claw") then
        return "msiclaw", "device name"
    elseif name:find("8bitdo") then
        return "8bitdo", "device name"
    elseif name:find("pro controller") then
        return "switchpro", "device name"
    end
    return nil, "unknown controller"
end

---Resolves the controller id to use for a profile.
---@param choice string "auto" or a controller id
---@return string id, string reason
function Detect.Resolve(choice)
    local Registry = ns.Controllers.Registry
    if choice and choice ~= "auto" and Registry.Get(choice) then
        return choice, "chosen in settings"
    end
    local id, reason = Detect.FromDevice(ns.Wow.GetGamePadDevice())
    if id and Registry.Get(id) then
        return id, reason
    end
    return Detect.FALLBACK, (reason or "unknown") .. " - using default"
end
