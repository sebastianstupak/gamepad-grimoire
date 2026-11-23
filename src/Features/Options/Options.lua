-- Page in the game's Settings > AddOns: what the addon does and buttons for the
-- controller setup and the cheat sheet (everything else lives in the setup).
local _, ns = ...

local Options = {}
ns.Options = Options
local M = ns.NewModule("Options")

Options.NAME = "Gamepad Grimoire"

local LINES = {
    "Bind spells, items and macros to your controller and see them on a picture of it.",
    "",
    "LT + R3 opens the controller setup on the card:",
    "  D-pad (or press any button) to choose a button, A to bind, X to clear,",
    "  LB / RB for layers, View for the back of the controller, Y for profiles, B to close.",
    "Hold LT or RT to peek at a layer.",
    "",
    "Keyboard: /gg setup, /gg show, /gg help",
}

local function button(parent, text, y, onClick)
    local b = ns.Wow.CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(220, 26)
    b:SetPoint("TOPLEFT", 16, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

---Builds the page (also used by tests).
---@return table frame
function Options.Build()
    local f = ns.Wow.CreateFrame("Frame", nil, ns.Wow.UIParent)
    f:Hide()
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(Options.NAME)
    local body = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 16, -48)
    body:SetJustifyH("LEFT")
    body:SetText(table.concat(LINES, "\n"))
    f.setup = button(f, "Open controller setup", -200, function()
        ns.Wow.CloseSettings()
        ns.Setup.Open()
    end)
    f.show = button(f, "Show / hide the cheat sheet", -232, function()
        ns.Wow.CloseSettings()
        ns.CheatSheet.Toggle()
    end)
    return f
end

function M:OnEnable()
    Options.frame = Options.Build()
    Options.registered = ns.Wow.RegisterSettingsPage(Options.NAME, Options.frame)
end
