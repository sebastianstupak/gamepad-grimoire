-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("CheatSheet", function()
    describe("Layout", function()
        local ns
        before_each(function()
            ns = Addon.load()
        end)

        local function compute(id)
            local def = ns.Controllers.Registry.Get(id)
            return ns.CheatSheet.Layout.Compute(def, ns.Bindings.Model.BUTTONS), def
        end

        it("fits every row and line inside the card for every controller", function()
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                local g = compute(def.id)
                assert.is_true(#g.rows >= 14, def.id .. " rows")
                for _, r in ipairs(g.rows) do
                    assert.is_true(r.x >= 0 and r.x + r.w <= g.width, def.id .. " " .. r.button .. " x")
                    assert.is_true(r.y >= 0 and r.y + r.h <= g.height, def.id .. " " .. r.button .. " y")
                    local last = r.line[#r.line]
                    assert.same({ r.anchor.x, r.anchor.y }, last)
                end
            end
        end)

        it("shows each button once, on the side of the picture it is on", function()
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                local g = compute(def.id)
                local seen = {}
                for _, r in ipairs(g.rows) do
                    assert.is_nil(seen[r.button], def.id .. " duplicate " .. r.button)
                    seen[r.button] = true
                    local centre = g.image.x + g.image.w / 2
                    if math.abs(r.anchor.x - centre) > g.image.w * 0.04 then
                        assert.equal(r.anchor.x < centre and "left" or "right", r.side, def.id .. " " .. r.button)
                    end
                end
            end
        end)

        it("orders rows top to bottom like their buttons, so leader lines do not cross", function()
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                local g = compute(def.id)
                for _, side in ipairs({ "left", "right" }) do
                    local prev
                    for _, r in ipairs(g.rows) do
                        if r.side == side then
                            if prev then
                                assert.is_true(r.y > prev.y and r.anchor.y >= prev.anchor.y, def.id .. " " .. r.button)
                            end
                            prev = r
                        end
                    end
                end
            end
        end)

        it("derives D-pad arms from a whole-pad anchor", function()
            local def = ns.Controllers.Registry.Get("xbox")
            local L = ns.CheatSheet.Layout
            local up, down = L.ButtonPoint(def, "PADDUP"), L.ButtonPoint(def, "PADDDOWN")
            local left, right = L.ButtonPoint(def, "PADDLEFT"), L.ButtonPoint(def, "PADDRIGHT")
            assert.is_true(up.y < down.y and left.x < right.x)
        end)
    end)

    describe("Glyphs", function()
        it("names buttons per family, positionally", function()
            local G = Addon.load().CheatSheet.Glyphs
            assert.equal("A", G.Label("xbox", "PAD1"))
            assert.equal("Cross", G.Label("playstation", "PAD1"))
            assert.equal("B", G.Label("nintendo", "PAD1"))
            assert.equal("L2", G.LayerTrigger("playstation", "LT"))
            assert.equal("Up", G.Label("valve", "PADDUP"))
        end)
    end)

    describe("peek and pin", function()
        local CS
        before_each(function()
            CS = Addon.load().CheatSheet
        end)

        it("maps held modifiers to layers", function()
            local mods = { LT = "SHIFT", RT = "CTRL" }
            assert.equal("LT", CS.HeldLayer(true, false, mods))
            assert.equal("RT", CS.HeldLayer(false, true, mods))
            assert.equal("BASE", CS.HeldLayer(true, true, mods))
            assert.is_nil(CS.HeldLayer(false, false, mods))
        end)

        it("shows a layer only after the trigger is held briefly", function()
            local s = { heldFor = 0 }
            assert.is_nil(CS.Step(s, "LT", 0.1, false, false))
            assert.equal("LT", CS.Step(s, "LT", 0.2, false, false))
            assert.is_nil(CS.Step(s, nil, 0.05, false, false))
        end)

        it("keeps a pinned card and ignores Shift while typing", function()
            local s = { heldFor = 0 }
            assert.equal("BASE", CS.Step(s, nil, 0.05, true, false))
            assert.is_nil(CS.Step(s, "LT", 1, false, true))
        end)
    end)

    describe("in game", function()
        local ns, wow
        before_each(function()
            ns, wow = Addon.start({
                schema = 1,
                characters = {},
                settings = {},
                profiles = {
                    Default = {
                        controller = "dualsense",
                        layers = {
                            BASE = { PAD1 = { type = "command", command = "JUMP" } },
                            LT = { PAD3 = { type = "spell", id = 172 } },
                            RT = {},
                        },
                    },
                },
            })
        end)

        local function card()
            for _, f in ipairs(wow.frames) do
                if rawget(f, "calls").SetFrameStrata and rawget(f, "shown") then
                    return f
                end
            end
        end
        local function texts(frame, out)
            out = out or {}
            for _, c in ipairs(rawget(frame, "children") or {}) do
                local t = rawget(c, "text")
                if t then
                    out[#out + 1] = t
                end
                texts(c, out)
            end
            return out
        end
        local function has(list, pattern)
            for _, t in ipairs(list) do
                if tostring(t):find(pattern) then
                    return true
                end
            end
            return false
        end

        it("binds the pin key to the toggle button", function()
            assert.same(
                { kind = "command", value = "CLICK GamepadGrimoireToggle:LeftButton" },
                wow.bindingsOf("GamepadGrimoireToggle")["SHIFT-PADRSTICK"]
            )
        end)

        it("peeks at the LT layer while the trigger is held, then hides", function()
            wow.shift = true
            wow.tick(0.4)
            local _, layer = ns.CheatSheet.State()
            assert.equal("LT", layer)
            local t = texts(card())
            assert.is_true(has(t, "Corruption"))
            assert.is_true(has(t, "Square"))
            assert.is_true(has(t, "held"))
            assert.is_true(has(t, "Pin / unpin this card"))
            local function textures(frame, out)
                out = out or {}
                for _, c in ipairs(rawget(frame, "children") or {}) do
                    local call = rawget(c, "calls").SetTexture
                    if call then
                        out[#out + 1] = call[1]
                    end
                    textures(c, out)
                end
                return out
            end
            local found = false
            for _, path in ipairs(textures(card())) do
                found = found or path == "Interface\\Icons\\INV_Misc_Book_09"
            end
            assert.is_true(found, "pin row icon path")
            wow.shift = false
            wow.tick(0.1)
            assert.is_nil(select(2, ns.CheatSheet.State()))
        end)

        it("pins the base layer from the slash command", function()
            wow.slash.handler("show")
            assert.is_true((ns.CheatSheet.State()))
            assert.is_true(has(texts(card()), "JUMP"))
            wow.slash.handler("show")
            assert.is_false((ns.CheatSheet.State()))
        end)

        it("switches picture with the controller choice", function()
            wow.slash.handler("controller xbox")
            wow.slash.handler("show")
            assert.is_true(has(texts(card()), "Xbox Series"))
        end)
    end)
end)
