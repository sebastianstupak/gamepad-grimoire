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
            assert.same({ "xbox", "dualsense", "switchpro", "steamdeck" }, ids)
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

        it("marks the Steam Deck back grips as invisible to the game", function()
            local deck = ns.Controllers.Registry.Get("steamdeck")
            assert.is_true(ns.Controllers.Registry.IsHidden(deck, "L4"))
            assert.is_false(ns.Controllers.Registry.IsHidden(deck, "PAD1"))
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
            -- DualShock 4 has no picture yet -> default, with the reason kept
            wow.device = { vendorID = 0x054C, productID = 0x09CC }
            local id, reason = Detect.Resolve("auto")
            assert.equal("xbox", id)
            assert.truthy(reason:find("default"))
        end)
    end)
end)
