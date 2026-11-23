local Addon = require("spec.helpers.addon")

describe("Diagnostics", function()
    it("reports client features, a share round trip and the binding state", function()
        local ns, wow = Addon.start(nil)
        wow.device = { name = "Xbox 360 Controller", vendorID = 0x045E, productID = 0x028E, labelStyle = "Letters" }
        local r = ns.Diagnostics.Run()
        assert.is_true(r.share.ok)
        assert.is_false(r.compression)
        assert.equal("xbox", r.controller)
        assert.is_true(r.atlases.Gamepad_Ltr_A_64)
        assert.is_false(r.atlases.Gamepad_Shp_Cross_64)
        assert.same(r, ns.db.diag)
        local lines = ns.Diagnostics.Format(r)
        assert.truthy(lines[3]:find("045E:028E"))
    end)

    it("detects working client compression", function()
        local ns = Addon.start(nil)
        ns.Wow.CompressString = function(s)
            return (s:gsub("Gamepad Grimoire ", "\1"))
        end
        ns.Wow.DecompressString = function(s)
            return (s:gsub("\1", "Gamepad Grimoire "))
        end
        assert.is_true(ns.Diagnostics.Run().compression)
    end)
end)
