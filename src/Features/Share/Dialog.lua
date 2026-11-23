-- Export / import window: a scrollable text box (share strings are far longer
-- than the 255 characters chat allows), plus Import / Close buttons.
local _, ns = ...

local Dialog = {}
ns.Share = ns.Share or {}
ns.Share.Dialog = Dialog

Dialog.NAME = "GamepadGrimoireShareDialog"

---First free profile name: "Name", "Name (2)", "Name (3)"...
---@param name string
---@param exists fun(name: string): boolean
---@return string
function Dialog.UniqueName(name, exists)
    if not exists(name) then
        return name
    end
    local i = 2
    while exists(("%s (%d)"):format(name, i)) do
        i = i + 1
    end
    return ("%s (%d)"):format(name, i)
end

---Imports a share string as a new profile.
---@param text string
---@return boolean ok, string message
function Dialog.ImportText(text)
    local ok, env = ns.Share.Codec.Import(text)
    if not ok then
        return false, tostring(env)
    end
    local name = Dialog.UniqueName(env.name, function(n)
        return ns.Profiles.Get(n) ~= nil
    end)
    local added, err = ns.Profiles.Add(name, env.profile)
    if not added then
        return false, tostring(err)
    end
    return true, ("imported profile %s - /gg profile use %s"):format(name, name)
end

local frame

local function build()
    local W = ns.Wow
    local f = W.CreateFrame("Frame", Dialog.NAME, W.UIParent, "BackdropTemplate")
    f:SetSize(560, 300)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.055, 0.06, 0.075, 0.97)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", 14, -32)
    f.hint:SetPoint("RIGHT", -14, 0)
    f.hint:SetJustifyH("LEFT")

    local scroll = W.CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -52)
    scroll:SetPoint("BOTTOMRIGHT", -34, 46)
    local box = W.CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(500)
    box:SetScript("OnEscapePressed", function()
        f:Hide()
    end)
    scroll:SetScrollChild(box)
    f.box = box

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 14, 18)
    f.status:SetPoint("RIGHT", -220, 0)
    f.status:SetJustifyH("LEFT")

    f.import = W.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.import:SetSize(96, 22)
    f.import:SetPoint("BOTTOMRIGHT", -112, 12)
    f.import:SetText("Import")
    f.import:SetScript("OnClick", function()
        local ok, msg = Dialog.ImportText(box:GetText() or "")
        f.status:SetText(ok and ("|cff5fd35f" .. msg .. "|r") or ("|cffff6060" .. msg .. "|r"))
        if ok then
            W.Print(msg)
        end
    end)

    local close = W.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(96, 22)
    close:SetPoint("BOTTOMRIGHT", -12, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function()
        f:Hide()
    end)
    W.CloseOnEscape(Dialog.NAME)
    f:Hide()
    return f
end

local function open()
    frame = frame or build()
    frame.status:SetText("")
    frame:Show()
    return frame
end

---Shows a profile's share string, selected and ready to copy.
---@param name string profile name
function Dialog.Export(name)
    local f = open()
    local text = ns.Share.Codec.Export(name, assert(ns.Profiles.Get(name), "no profile " .. tostring(name)))
    f.title:SetText("Export profile: " .. name)
    f.hint:SetText("Press Ctrl+C to copy, then share it anywhere. Import it with /gg import.")
    f.import:Hide()
    f.box:SetText(text)
    f.box:SetFocus()
    f.box:HighlightText()
    return text
end

---Opens an empty box to paste a share string into.
function Dialog.Import()
    local f = open()
    f.title:SetText("Import profile")
    f.hint:SetText("Paste a Gamepad Grimoire string (Ctrl+V) and press Import. It is added as a new profile.")
    f.import:Show()
    f.box:SetText("")
    f.box:SetFocus()
end

---@return table|nil the dialog frame (tests)
function Dialog.Frame()
    return frame
end
