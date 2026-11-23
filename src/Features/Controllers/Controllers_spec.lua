-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("Controllers", function()
    local ns, wow
    before_each(function()
        ns, wow = Addon.load()
    end)

    describe("definitions", function()
        it("registers every supported controller with a texture and anchors", function()
            local ids = {}
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                ids[#ids + 1] = def.id
                assert.truthy(def.texture:match("^Interface\\AddOns\\GamepadGrimoire\\"), def.id)
            end
            assert.same({
                "xbox",
                "dualsense",
                "switchpro",
                "steamdeck",
                "dualshock4",
                "xbox360",
                "steamcontroller",
                "rogally",
                "legiongo",
                "msiclaw",
                "8bitdo",
                "generic",
            }, ids)
        end)

        it("has an anchor inside the picture for the core buttons of every controller", function()
            local core = { "PAD1", "PAD2", "PAD3", "PAD4", "PADLSTICK", "PADRSTICK", "PADLSHOULDER", "PADRSHOULDER" }
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                for _, b in ipairs(core) do
                    local a = ns.Controllers.Registry.Anchor(def, b)
                    assert.is_table(a, def.id .. " " .. b)
                    assert.is_true(a.x > 0 and a.x < 1 and a.y > 0 and a.y < 1, def.id .. " " .. b)
                end
                assert.is_table(ns.Controllers.Registry.Anchor(def, "PADDUP"), def.id .. " D-pad")
            end
        end)

        it("uses positional face buttons: PAD1 is the bottom one, PAD4 the top", function()
            for _, def in ipairs(ns.Controllers.Registry.All()) do
                local A = def.anchors
                assert.is_true(A.PAD1.y > A.PAD4.y, def.id)
                assert.is_true(A.PAD2.x > A.PAD3.x, def.id)
            end
        end)

        it("hides the trackpads and the quick access button", function()
            local deck = ns.Controllers.Registry.Get("steamdeck")
            assert.is_true(ns.Controllers.Registry.IsHidden(deck, "LPAD"))
            assert.is_false(ns.Controllers.Registry.IsHidden(deck, "PAD1"))
        end)

        it("has a back view for every controller, left out of the controller list", function()
            local R = ns.Controllers.Registry
            assert.are.equal(12, #R.All())
            assert.are.equal(24, #R.All(true))
            for _, def in ipairs(R.All()) do
                local back = R.BackOf(def)
                assert.is_table(back, def.id)
                assert.are.equal("back", back.view)
                assert.are.equal(def.id, back.front)
                assert.is_table(back.anchors.PADLTRIGGER, def.id .. " triggers on the back")
                assert.truthy(back.texture:match("_back$"), def.id)
            end
        end)

        it("puts the Steam Deck back grips on the back, named L4 L5 R4 R5", function()
            local R = ns.Controllers.Registry
            local deck = R.Get("steamdeck")
            local back = R.BackOf(deck)
            assert.are.equal("R4", back.labels.PADPADDLE1)
            assert.are.equal("L5", back.labels.PADPADDLE4)
            assert.is_true(back.anchors.PADPADDLE3.x < 0.5, "L4 on the left")
            assert.are.equal("back", select(2, R.ViewFor(deck, "PADPADDLE1")))
            assert.are.equal("front", select(2, R.ViewFor(deck, "PAD1")))
            assert.are.equal("front", select(2, R.ViewFor(deck, "PADDUP")))
            assert.is_nil(R.ViewFor(R.Get("switchpro"), "PADPADDLE1"))
            assert.are.equal("R4", ns.CheatSheet.Glyphs.For(back, "PADPADDLE1"))
            assert.are.equal("P1", ns.CheatSheet.Glyphs.For(R.Get("xbox"), "PADPADDLE1"))
        end)
    end)

    describe("detection", function()
        local Detect
        before_each(function()
            Detect = ns.Controllers.Detect
        end)

        it("recognises controllers by USB vendor/product", function()
            assert.equal("dualsense", (Detect.FromDevice({ vendorID = 0x054C, productID = 0x0CE6 })))
            assert.equal("dualshock4", (Detect.FromDevice({ vendorID = 0x054C, productID = 0x09CC })))
            assert.equal("switchpro", (Detect.FromDevice({ vendorID = 0x057E, productID = 0x2009 })))
            assert.equal("xbox", (Detect.FromDevice({ vendorID = 0x045E, productID = 0x028E })))
            assert.equal("steamcontroller", (Detect.FromDevice({ vendorID = 0x28DE, productID = 0x1142 })))
            assert.equal("steamdeck", (Detect.FromDevice({ vendorID = 0x28DE, productID = 0x1205 })))
            assert.equal("rogally", (Detect.FromDevice({ vendorID = 0x0B05, productID = 0x1ABE })))
            assert.equal("legiongo", (Detect.FromDevice({ vendorID = 0x17EF, productID = 0x6182 })))
            assert.equal("msiclaw", (Detect.FromDevice({ vendorID = 0x0DB0, productID = 0x1901 })))
            assert.equal("8bitdo", (Detect.FromDevice({ vendorID = 0x2DC8, productID = 0x6006 })))
            assert.equal("msiclaw", (Detect.FromDevice({ name = "MSI Claw Gamepad" })))
        end)

        it("falls back to the button label style, then the device name", function()
            assert.equal("dualsense", (Detect.FromDevice({ labelStyle = "Shapes" })))
            assert.equal("steamdeck", (Detect.FromDevice({ name = "Steam Deck Controller" })))
            assert.is_nil((Detect.FromDevice({ name = "Mystery Pad" })))
        end)

        it("prefers the player's choice, then detection, then the default", function()
            assert.equal("steamdeck", (Detect.Resolve("steamdeck")))
            wow.device = { vendorID = 0x057E, productID = 0x2009 }
            assert.equal("switchpro", (Detect.Resolve("auto")))
            wow.device = nil
            assert.equal("xbox", (Detect.Resolve("auto")))
            wow.device = { vendorID = 0x054C, productID = 0x09CC }
            assert.equal("dualshock4", (Detect.Resolve("auto")))
            -- an unknown controller -> default, with the reason kept
            wow.device = { vendorID = 0x1234, productID = 0x0001, name = "Mystery Pad" }
            local id, reason = Detect.Resolve("auto")
            assert.equal("xbox", id)
            assert.truthy(reason:find("default"))
        end)
    end)
end)
