-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("Editor", function()
    describe("FromCursor", function()
        local E
        before_each(function()
            E = Addon.load().Editor
        end)

        it("turns spells, items and macros into actions", function()
            assert.same({ type = "spell", id = 172 }, E.FromCursor({ kind = "spell", id = 172 }))
            assert.same({ type = "item", id = 6948 }, E.FromCursor({ kind = "item", id = 6948 }))
            assert.same({ type = "macro", name = "Rotace" }, E.FromCursor({ kind = "macro", name = "Rotace" }))
        end)

        it("explains what it cannot bind", function()
            local action, reason = E.FromCursor({ kind = "money" })
            assert.is_nil(action)
            assert.truthy(reason:find("money"))
            assert.is_nil((E.FromCursor(nil)))
        end)
    end)

    describe("on the pinned card", function()
        local ns, wow
        before_each(function()
            ns, wow = Addon.start(nil)
        end)

        local function cardRows()
            for _, f in ipairs(wow.frames) do
                if rawget(f, "calls").SetFrameStrata and rawget(f, "shown") then
                    local rows = {}
                    for _, c in ipairs(rawget(f, "children") or {}) do
                        if rawget(c, "kind") == "Button" and rawget(rawget(c, "scripts"), "OnReceiveDrag") then
                            rows[#rows + 1] = c
                        end
                    end
                    return rows, f
                end
            end
        end
        -- rows are created in layout order; find one by its glyph label
        local function rowFor(glyph)
            local rows = cardRows()
            for _, r in ipairs(rows) do
                for _, c in ipairs(rawget(r, "children") or {}) do
                    if rawget(c, "text") == glyph then
                        return r
                    end
                end
            end
        end

        it("binds a dragged spell to the button in the layer being shown", function()
            wow.slash.handler("controller xbox")
            wow.slash.handler("show lt")
            wow.cursor = { kind = "spell", id = 172 }
            local row = rowFor("X")
            rawget(row, "scripts").OnReceiveDrag(row)
            assert.same({ type = "spell", id = 172 }, ns.Profiles.ActiveProfile().layers.LT.PAD3)
            assert.is_nil(wow.cursor)
            assert.same(
                { kind = "spell", value = "Corruption" },
                wow.bindingsOf("GamepadGrimoireBindingOwner")["SHIFT-PAD3"]
            )
        end)

        it("clears a button on right-click", function()
            local p = ns.Profiles.ActiveProfile()
            p.controller = "xbox"
            ns.Bindings.Model.Set(p, "BASE", "PAD1", { type = "command", command = "JUMP" })
            wow.slash.handler("show")
            local row = rowFor("A")
            rawget(row, "scripts").OnClick(row, "RightButton")
            assert.is_nil(p.layers.BASE.PAD1)
            assert.is_nil(wow.bindingsOf("GamepadGrimoireBindingOwner").PAD1)
        end)

        it("only takes the mouse while pinned", function()
            wow.slash.handler("show")
            local rows = cardRows()
            assert.same({ true }, rawget(rows[1], "calls").EnableMouse)
            wow.slash.handler("show")
            wow.shift = true
            wow.tick(0.4)
            rows = cardRows()
            assert.same({ false }, rawget(rows[1], "calls").EnableMouse)
        end)

        it("refuses to edit saved data from a newer version", function()
            ns.db.readOnly = true
            local ok, err = ns.Editor.Assign("BASE", "PAD1", { type = "command", command = "JUMP" })
            assert.is_false(ok)
            assert.truthy(err:find("newer version"))
        end)
    end)
end)
