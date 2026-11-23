-- The list shown over the controller picture during setup (picker and menu).
local _, ns = ...

local Panel = {}
ns.Setup = ns.Setup or {}
ns.Setup.Panel = Panel

local ROW_H = 26

---@param parent table the card frame
---@param rect { x: number, y: number, w: number, h: number } picture area on the card
function Panel.Build(parent, rect, page)
    local W = ns.Wow
    local f = W.CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", rect.x, -rect.y)
    f:SetSize(rect.w, rect.h)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.045, 0.06, 0.97)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOP", 0, -6)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", 0, 6)

    f.rows = {}
    for i = 1, page do
        local r = W.CreateFrame("Frame", nil, f)
        r:SetSize(rect.w - 24, ROW_H - 2)
        r:SetPoint("TOPLEFT", 12, -28 - (i - 1) * ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(ROW_H - 6, ROW_H - 6)
        r.icon:SetPoint("LEFT", 4, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetPoint("RIGHT", -8, 0)
        r.text:SetJustifyH("LEFT")
        r.text:SetWordWrap(false)
        f.rows[i] = r
    end
    f:Hide()

    ---@param title string
    ---@param items { name: string, icon: any }[]
    ---@param selected number
    ---@param top number
    ---@param hint string
    function f:ShowList(title, items, selected, top, hint)
        self.title:SetText(title)
        self.hint:SetText(hint)
        for i, r in ipairs(self.rows) do
            local item = items[top + i - 1]
            if item then
                local on = top + i - 1 == selected
                r.bg:SetColorTexture(on and 0.85 or 0.13, on and 0.68 or 0.135, on and 0.2 or 0.16, on and 0.95 or 0.8)
                r.text:SetText(item.name or "?")
                r.text:SetTextColor(on and 0.08 or 0.92, on and 0.06 or 0.92, on and 0.02 or 0.95)
                if item.icon then
                    r.icon:SetTexture(item.icon)
                    r.icon:Show()
                else
                    r.icon:Hide()
                end
                r:Show()
            else
                r:Hide()
            end
        end
        if #items == 0 then
            self.rows[1].text:SetText("|cff8a8f9c(nothing here)|r")
            self.rows[1].icon:Hide()
            self.rows[1].bg:SetColorTexture(0.13, 0.135, 0.16, 0.8)
            self.rows[1]:Show()
        end
        self:Show()
    end
    return f
end
