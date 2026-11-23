-- Editor slice: change binds on the pinned cheat sheet.
--   drag a spell / item / macro onto a row  -> bind it to that button
--   right-click a row                        -> clear the button
--   click a tab                              -> edit that layer
-- Every change goes into the active profile and is applied right away (queued in
-- combat by the Bindings applier).
local _, ns = ...

local Editor = {}
ns.Editor = Editor

---Turns what the cursor holds into a binding action. Pure.
---@param cursor { kind: string, id?: number, name?: string }|nil from ns.Wow.GetCursorAction
---@return table|nil action, string? reason
function Editor.FromCursor(cursor)
    if not cursor then
        return nil, "nothing on the cursor"
    end
    if cursor.kind == "spell" and cursor.id then
        return { type = "spell", id = cursor.id }
    elseif cursor.kind == "item" and cursor.id then
        return { type = "item", id = cursor.id }
    elseif cursor.kind == "macro" and cursor.name then
        return { type = "macro", name = cursor.name }
    end
    return nil, "cannot bind a " .. tostring(cursor.kind) .. " (spells, items and macros only)"
end

---Sets (or with nil, clears) a button in a layer of the active profile.
---@param layer string
---@param button string
---@param action table|nil
---@return boolean ok, string? err
function Editor.Assign(layer, button, action)
    if ns.db.readOnly then
        return false, "saved data is from a newer version - editing is disabled"
    end
    local profile = ns.Profiles.ActiveProfile()
    profile.layers = profile.layers or {}
    local ok, err = pcall(ns.Bindings.Model.Set, profile, layer, button, action)
    if not ok then
        return false, tostring(err)
    end
    ns.Events.Emit("PROFILE_CHANGED")
    return true
end

---Row interaction from the card. `kind` is "drop" or "clear".
---@param layer string
---@param button string
---@param kind "drop"|"clear"
function Editor.OnRow(layer, button, kind)
    if kind == "clear" then
        return Editor.Assign(layer, button, nil)
    end
    local action, reason = Editor.FromCursor(ns.Wow.GetCursorAction())
    if not action then
        ns.Wow.Print(reason)
        return false, reason
    end
    ns.Wow.ClearCursor()
    return Editor.Assign(layer, button, action)
end
