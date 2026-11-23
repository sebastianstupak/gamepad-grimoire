-- The on-screen card: controller picture, leader lines, one row per button.
-- Geometry comes from Layout (pure); this file only creates and fills frames.
local _, ns = ...

local View = {}
ns.CheatSheet = ns.CheatSheet or {}
ns.CheatSheet.View = View

local C = {
    bg = { 0.055, 0.06, 0.075, 0.94 },
    edge = { 0.36, 0.37, 0.42, 1 },
    row = { 0.13, 0.135, 0.16, 0.9 },
    badge = { 0.2, 0.21, 0.25, 1 },
    held = { 0.85, 0.68, 0.2, 1 },
    line = { 0.92, 0.92, 0.95, 0.55 },
    dim = 0.4,
}

local QUESTION_MARK = 134400 -- placeholder icon of icon-less macros

local function tex(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    if color then
        t:SetColorTexture(unpack(color))
    end
    return t
end

local function text(parent, template, justify)
    local f = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    f:SetJustifyH(justify or "LEFT")
    return f
end

local function line(parent, x1, y1, x2, y2, color)
    local l = parent:CreateLine(nil, "ARTWORK")
    l:SetThickness(1.4)
    l:SetColorTexture(unpack(color or C.line))
    l:SetStartPoint("TOPLEFT", parent, x1, -y1)
    l:SetEndPoint("TOPLEFT", parent, x2, -y2)
    return l
end

---Builds a card for one controller. Returns a table with :Fill(state).
---@param def table controller definition
---@param buttons string[]
function View.Build(def, buttons)
    local g = ns.CheatSheet.Layout.Compute(def, buttons)
    local Glyphs = ns.CheatSheet.Glyphs
    local frame = ns.Wow.CreateFrame("Frame", nil, ns.Wow.UIParent)
    frame:SetSize(g.width, g.height)
    frame:SetPoint("TOP", ns.Wow.UIParent, "TOP", 0, -90)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    local bg = tex(frame, "BACKGROUND", C.bg)
    bg:SetAllPoints()
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local e = tex(frame, "BORDER", C.edge)
        e:SetHeight(1)
        e:SetPoint(side[1])
        e:SetPoint(side[2])
    end

    local card = {
        frame = frame,
        rows = {},
        def = def,
        width = g.width,
        height = g.height,
        image = g.image,
        columns = { left = {}, right = {} }, -- buttons in on-screen order, for D-pad navigation
    }

    card.title = text(frame, "GameFontNormal")
    card.title:SetPoint("TOPLEFT", 14, -12)
    card.pinTip = text(frame, "GameFontDisableSmall", "RIGHT")
    card.pinTip:SetPoint("TOPRIGHT", -14, -14)

    card.tabs = {}
    local tabW = 118
    for i, layer in ipairs({ "BASE", "LT", "RT" }) do
        local t = ns.Wow.CreateFrame("Button", nil, frame)
        t:SetSize(tabW, 22)
        t:SetScript("OnClick", function()
            if card.onTab then
                card.onTab(layer)
            end
        end)
        t:SetPoint("TOP", frame, "TOP", (i - 2) * (tabW + 6), -10)
        t.bg = tex(t, "ARTWORK", C.row)
        t.bg:SetAllPoints()
        t.label = text(t, "GameFontHighlightSmall", "CENTER")
        t.label:SetPoint("CENTER")
        t.label:SetText(layer == "BASE" and "Base" or ("Hold " .. Glyphs.LayerTrigger(def.family, layer)))
        t.layer = layer
        card.tabs[i] = t
    end

    local img = tex(frame, "ARTWORK")
    img:SetTexture(def.texture)
    img:SetSize(g.image.w, g.image.h)
    img:SetPoint("TOPLEFT", g.image.x, -g.image.y)

    for _, r in ipairs(g.rows) do
        local row = ns.Wow.CreateFrame("Button", nil, frame)
        row:SetSize(r.w, r.h)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local function act(kind)
            if card.onRow then
                card.onRow(r.button, kind)
            end
        end
        row:SetScript("OnReceiveDrag", function()
            act("drop")
        end)
        row:SetScript("OnClick", function(_, mouse)
            act(mouse == "RightButton" and "clear" or "drop")
        end)
        row:SetPoint("TOPLEFT", r.x, -r.y)
        row.bg = tex(row, "BACKGROUND", C.row)
        row.bg:SetAllPoints()

        row.badge = tex(row, "ARTWORK", C.badge)
        row.badge:SetSize(56, r.h - 4)
        row.glyph = text(row, "GameFontNormal", "CENTER")
        row.icon = tex(row, "ARTWORK")
        row.icon:SetSize(r.h - 4, r.h - 4)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.label = text(row, "GameFontHighlight", r.side == "left" and "RIGHT" or "LEFT")
        row.label:SetWordWrap(false)
        row.label:SetWidth(r.w - 56 - (r.h - 4) - 16)

        -- badge sits next to the picture: rows read "label [icon] [badge] ---> button"
        if r.side == "left" then
            row.badge:SetPoint("RIGHT", -2, 0)
            row.icon:SetPoint("RIGHT", row.badge, "LEFT", -4, 0)
            row.label:SetPoint("RIGHT", row.icon, "LEFT", -6, 0)
        else
            row.badge:SetPoint("LEFT", 2, 0)
            row.icon:SetPoint("LEFT", row.badge, "RIGHT", 4, 0)
            row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        end
        row.glyph:SetPoint("CENTER", row.badge, "CENTER")
        row.glyph:SetText(Glyphs.Label(def.family, r.button))
        local face = Glyphs.FACE_COLOR[r.button]
        if face then
            row.glyph:SetTextColor(face[1], face[2], face[3])
        end

        row.lines = {}
        for i = 1, #r.line - 1 do
            local a, b = r.line[i], r.line[i + 1]
            row.lines[i] = line(frame, a[1], a[2], b[1], b[2])
        end
        row.dot = tex(frame, "OVERLAY", { 1, 0.85, 0.4, 1 })
        row.dot:SetSize(5, 5)
        row.dot:SetPoint("CENTER", frame, "TOPLEFT", r.anchor.x, -r.anchor.y)

        -- gold outline marks the row selected with the D-pad during setup
        row.focus = {}
        for i, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local e = tex(row, "OVERLAY", C.held)
            e:SetHeight(2)
            e:SetPoint(edge[1])
            e:SetPoint(edge[2])
            row.focus[i] = e
        end
        for i, edge in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local e = tex(row, "OVERLAY", C.held)
            e:SetWidth(2)
            e:SetPoint(edge[1])
            e:SetPoint(edge[2])
            row.focus[i + 2] = e
        end

        row.button = r.button
        row.side = r.side
        card.rows[#card.rows + 1] = row
        card.columns[r.side][#card.columns[r.side] + 1] = r.button
    end

    card.footer = text(frame, "GameFontDisableSmall", "CENTER")
    card.footer:SetPoint("BOTTOM", 0, 10)

    ---Rows and tabs take the mouse only while the card is pinned (editing).
    ---@param editable boolean
    function card:SetEditable(editable)
        for _, row in ipairs(self.rows) do
            row:EnableMouse(editable)
        end
        for _, t in ipairs(self.tabs) do
            t:EnableMouse(editable)
        end
    end

    ---@param state { layer: string, layout: table, modifiers: table, profile: string, pinned: boolean, pinKey: string?, focus: string?, setup: boolean? }
    function card:Fill(state)
        local layerOf = {} -- trigger button -> the layer it holds
        for layer in pairs(state.modifiers) do
            layerOf[layer == "LT" and "PADLTRIGGER" or "PADRTRIGGER"] = layer
        end
        self.title:SetText("Gamepad Grimoire |cff8a8f9c- " .. state.profile .. " - " .. def.name .. "|r")
        self.pinTip:SetText(state.pinned and "|cffffd100PINNED|r" or (state.pinKey and ("pin: " .. state.pinKey) or ""))
        for _, t in ipairs(self.tabs) do
            local on = t.layer == state.layer
            t.bg:SetColorTexture(unpack(on and C.held or C.row))
            t.label:SetTextColor(on and 0.08 or 0.75, on and 0.06 or 0.75, on and 0.02 or 0.78)
        end
        local layerButtons = state.layout.layers and state.layout.layers[state.layer] or {}
        local prefix = state.layer == "BASE" and "" or ((state.modifiers[state.layer] or "?") .. "-")
        for _, row in ipairs(self.rows) do
            local holds = layerOf[row.button]
            local action = layerButtons[row.button]
            local on = true
            row.icon:Hide()
            if holds then
                local held = holds == state.layer
                row.label:SetText(
                    held and "|cffffd100held|r" or ("hold: " .. Glyphs.LayerTrigger(def.family, holds) .. " layer")
                )
                row.badge:SetColorTexture(unpack(held and C.held or C.badge))
            elseif state.pinKey and prefix .. row.button == state.pinKey then
                -- the pin key is a priority binding: it wins over whatever the profile has here
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
                row.icon:Show()
                row.label:SetText("|cffc8a2ffController setup|r")
                row.badge:SetColorTexture(unpack(C.badge))
            elseif action then
                local icon, name = ns.Wow.DescribeAction(action)
                if icon and icon ~= QUESTION_MARK then
                    row.icon:SetTexture(icon)
                    row.icon:Show()
                end
                row.label:SetText(name or "?")
                row.badge:SetColorTexture(unpack(C.badge))
            else
                row.label:SetText("|cff6c707a-|r")
                row.badge:SetColorTexture(unpack(C.badge))
                on = false
            end
            local focused = state.focus == row.button
            for _, e in ipairs(row.focus) do
                e:SetShown(focused)
            end
            if focused then
                on = true
            end
            row:SetAlpha(on and 1 or C.dim)
            for _, l in ipairs(row.lines) do
                l:SetAlpha(on and 1 or C.dim)
            end
            row.dot:SetAlpha(on and 1 or C.dim)
        end
        if state.setup then
            return self.footer:SetText("D-pad move   A choose   X clear   Y menu   LB / RB layer   B close")
        elseif state.pinned then
            return self.footer:SetText("drag a spell, item or macro onto a row  -  right-click clears")
        end
        self.footer:SetText(
            "hold "
                .. Glyphs.LayerTrigger(def.family, "LT")
                .. " / "
                .. Glyphs.LayerTrigger(def.family, "RT")
                .. " to peek at a layer  -  "
                .. (state.pinKey and (state.pinKey .. " opens setup") or "/gg setup")
        )
    end

    return card
end
