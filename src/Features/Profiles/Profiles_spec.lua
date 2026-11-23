local Addon = require("spec.helpers.addon")

describe("Profiles", function()
    local ns, wow, P
    before_each(function()
        ns, wow = Addon.start(nil)
        P = ns.Profiles
    end)

    it("starts with a Default profile in use", function()
        assert.same({ "Default" }, P.List())
        assert.equal("Default", P.ActiveName())
    end)

    it("creates, copies, renames and deletes profiles", function()
        assert.is_true(P.Create("Raid"))
        ns.Bindings.Model.Set(P.Get("Raid"), "BASE", "PAD1", { type = "command", command = "JUMP" })
        assert.is_true(P.Create("Raid 2", "Raid"))
        assert.is_table(P.Get("Raid 2").layers.BASE.PAD1)
        assert.is_true(P.Rename("Raid 2", "Mythic+"))
        assert.is_nil(P.Get("Raid 2"))
        assert.is_true(P.Delete("Mythic+"))
        assert.same({ "Default", "Raid" }, P.List())
    end)

    it("copies are independent", function()
        P.Create("A")
        P.Create("B", "A")
        ns.Bindings.Model.Set(P.Get("B"), "BASE", "PAD1", { type = "command", command = "JUMP" })
        assert.is_nil(P.Get("A").layers.BASE)
    end)

    it("refuses bad names, duplicates and protected deletes", function()
        assert.is_false(P.Create(""))
        assert.is_false(P.Create(" padded "))
        assert.is_false(P.Create("Default"))
        assert.is_false(P.Delete("Default"))
        P.Create("Used")
        P.Use("Used")
        assert.is_false(P.Delete("Used"))
    end)

    it("switches automatically per specialization", function()
        P.Create("Healer")
        P.Use("Healer", 3)
        assert.equal("Default", P.ActiveName())
        local changed = 0
        ns.Events.On("PROFILE_CHANGED", function()
            changed = changed + 1
        end)
        wow.spec = 3
        wow.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.equal("Healer", P.ActiveName())
        assert.equal(1, changed)
    end)

    it("renaming follows characters and specs that use the profile", function()
        P.Create("Old")
        P.Use("Old")
        P.Use("Old", 2)
        P.Rename("Old", "New")
        wow.spec = 2
        assert.equal("New", P.ActiveName())
    end)
end)
