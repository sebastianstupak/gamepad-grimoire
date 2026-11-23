-- Cheat-sheet geometry. Pure: from a controller definition to card size, picture
-- placement, label rows and leader lines (pixels at scale 1, origin top-left).
--
-- Generic for every controller: buttons on the left half of the picture get rows
-- on the left, the rest on the right; rows on each side are sorted by the
-- button's height on the picture, so leader lines do not cross.
local _, ns = ...

local Layout = {}
ns.CheatSheet = ns.CheatSheet or {}
ns.CheatSheet.Layout = Layout

Layout.ROW_W, Layout.ROW_H, Layout.ROW_GAP = 236, 22, 2
Layout.IMG_W, Layout.IMG_H = 440, 220 -- textures are 2:1
Layout.PAD, Layout.HEADER, Layout.FOOTER = 12, 44, 30
Layout.ELBOW = 10 -- leader lines leave the row horizontally for this many px

-- D-pad directions when a controller only has one anchor for the whole pad
local DPAD_ARM = { PADDUP = { 0, -1 }, PADDDOWN = { 0, 1 }, PADDLEFT = { -1, 0 }, PADDRIGHT = { 1, 0 } }

---Anchor (0..1) of a button, deriving D-pad arms from a whole-pad anchor.
---@return { x: number, y: number }|nil
function Layout.ButtonPoint(def, button)
    local a = def.anchors[button]
    if a then
        return { x = a.x, y = a.y }
    end
    local arm, pad = DPAD_ARM[button], def.anchors.PADDPAD
    if arm and pad then
        return { x = pad.x + arm[1] * pad.w * 0.32, y = pad.y + arm[2] * pad.h * 0.32 }
    end
end

---Which bindable buttons this controller shows, and on which side.
---@param buttons string[] candidate buttons (Bindings.Model.BUTTONS)
---@return table[] left, table[] right rows { button, side, point }, sorted top to bottom
function Layout.Assign(def, buttons)
    local left, right, middle = {}, {}, {}
    for _, b in ipairs(buttons) do
        local p = Layout.ButtonPoint(def, b)
        if p then
            local item = { button = b, point = p }
            if math.abs(p.x - 0.5) < 0.04 then
                middle[#middle + 1] = item
            elseif p.x < 0.5 then
                item.side = "left"
                left[#left + 1] = item
            else
                item.side = "right"
                right[#right + 1] = item
            end
        end
    end
    -- centre buttons (guide, share...) balance the two columns
    for _, item in ipairs(middle) do
        if #left <= #right then
            item.side = "left"
            left[#left + 1] = item
        else
            item.side = "right"
            right[#right + 1] = item
        end
    end
    local byY = function(a, b)
        if a.point.y ~= b.point.y then
            return a.point.y < b.point.y
        end
        return a.button < b.button
    end
    table.sort(left, byY)
    table.sort(right, byY)
    return left, right
end

---Full card geometry.
---@param def table controller definition
---@param buttons string[]
function Layout.Compute(def, buttons)
    local L = Layout
    local left, right = L.Assign(def, buttons)
    local rowsN = math.max(#left, #right)
    local listH = rowsN * (L.ROW_H + L.ROW_GAP) - L.ROW_GAP
    local bodyH = math.max(listH, L.IMG_H)
    local cardW = 2 * (L.PAD + L.ROW_W) + 2 * 28 + L.IMG_W
    local cardH = L.HEADER + bodyH + L.FOOTER
    local img = { x = (cardW - L.IMG_W) / 2, y = L.HEADER + (bodyH - L.IMG_H) / 2, w = L.IMG_W, h = L.IMG_H }

    local rows = {}
    local function place(list, side)
        local top = L.HEADER + (bodyH - (#list * (L.ROW_H + L.ROW_GAP) - L.ROW_GAP)) / 2
        for i, item in ipairs(list) do
            local x = side == "left" and L.PAD or (cardW - L.PAD - L.ROW_W)
            local y = top + (i - 1) * (L.ROW_H + L.ROW_GAP)
            local ax, ay = img.x + item.point.x * img.w, img.y + item.point.y * img.h
            local sx = side == "left" and (x + L.ROW_W) or x
            local ex = side == "left" and (sx + L.ELBOW) or (sx - L.ELBOW)
            local my = y + L.ROW_H / 2
            rows[#rows + 1] = {
                button = item.button,
                side = side,
                x = x,
                y = y,
                w = L.ROW_W,
                h = L.ROW_H,
                anchor = { x = ax, y = ay },
                line = { { sx, my }, { ex, my }, { ax, ay } },
            }
        end
    end
    place(left, "left")
    place(right, "right")
    return { width = cardW, height = cardH, image = img, rows = rows }
end
