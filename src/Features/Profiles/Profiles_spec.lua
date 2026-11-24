-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
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

    it("explains every refusal", function()
        local cases = {
            { { P.Create(42) }, "name must be text" },
            { { P.Create(string.rep("x", 49)) }, "name is longer than 48 characters" },
            { { P.Create("Copy", "Ghost") }, "no profile named Ghost" },
            { { P.Delete("Ghost") }, "no profile named Ghost" },
            { { P.Rename("Ghost", "X") }, "no profile named Ghost" },
            { { P.Rename("Default", "X") }, "the Default profile cannot be renamed" },
            { { P.Use("Ghost") }, "no profile named Ghost" },
        }
        for _, c in ipairs(cases) do
            assert.is_false(c[1][1])
            assert.are.equal(c[2], c[1][2])
        end
    end)

    it("keeps a profile in use by another spec from being deleted", function()
        P.Create("Tank")
        P.Use("Tank", 2)
        local ok, err = P.Delete("Tank")
        assert.is_false(ok)
        assert.matches("in use", err)
    end)

    it("refuses to rename onto an existing or invalid name and changes nothing", function()
        P.Create("A")
        P.Create("B")
        assert.is_false((P.Rename("A", "B")))
        assert.is_false((P.Rename("A", " A")))
        assert.same({ "A", "B", "Default" }, P.List())
    end)

    it("falls back to Default when the chosen profile is gone", function()
        P.Create("Gone")
        P.Use("Gone")
        ns.db.profiles.Gone = nil -- e.g. deleted on another character
        assert.equal("Default", P.ActiveName())
        assert.is_table(P.ActiveProfile())
    end)

    it("ignores spec changes of other units and changes that keep the profile", function()
        P.Create("Healer")
        P.Use("Healer", 3)
        local changed = 0
        ns.Events.On("PROFILE_CHANGED", function()
            changed = changed + 1
        end)
        wow.spec = 3
        wow.fire("PLAYER_SPECIALIZATION_CHANGED", "party1")
        assert.equal(0, changed)
        wow.spec = 2
        wow.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.equal(0, changed) -- spec 2 has no profile of its own: still Default
        wow.spec = 3
        wow.fire("PLAYER_SPECIALIZATION_CHANGED", "player")
        assert.equal(1, changed)
    end)

    it("clears a spec's own profile", function()
        P.Create("Healer")
        P.Use("Healer", 3)
        wow.spec = 3
        assert.equal("Healer", P.ActiveName())
        P.ClearSpec(3)
        assert.is_nil(P.SpecProfile(3))
        assert.equal("Default", P.ActiveName())
    end)
end)
