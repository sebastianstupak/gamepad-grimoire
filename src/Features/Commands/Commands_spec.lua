local Addon = require("spec.helpers.addon")

describe("Commands", function()
    local ns, wow
    before_each(function()
        ns, wow = Addon.start(nil)
    end)

    local function run(msg)
        wow.printed = {}
        wow.slash.handler(msg)
        return table.concat(wow.printed, "\n")
    end

    it("registers /gg and /grimoire", function()
        assert.same({ "/gg", "/grimoire" }, wow.slash.names)
    end)

    it("keeps spaces in the last argument", function()
        assert.same({ "profile", "use", "My Raid Setup" }, ns.Commands.Parse("  profile use My Raid Setup ", 3))
        assert.same({}, ns.Commands.Parse("   ", 3))
    end)

    it("manages profiles", function()
        assert.truthy(run("profile new Raid Night"):find("done"))
        assert.truthy(run("profile use Raid Night"):find("done"))
        assert.truthy(run("profile"):find("%* Raid Night"))
        assert.truthy(run("profile use Nope"):find("no profile"))
    end)

    it("sets and reports the controller picture", function()
        assert.truthy(run("controller dualsense"):find("DualSense"))
        assert.equal("dualsense", ns.Profiles.ActiveProfile().controller)
        assert.truthy(run("controller gamecube"):find("unknown controller"))
    end)

    it("captures the player's current controller keybinds into a profile", function()
        wow.keybinds = { PAD1 = "JUMP", ["SHIFT-PAD3"] = "ACTIONBUTTON2", ["CTRL-PADDUP"] = "MACRO Rotace", Q = "X" }
        assert.truthy(run("capture My Old Binds"):find("captured 3"))
        local p = ns.Profiles.Get("My Old Binds")
        assert.same({ type = "command", command = "ACTIONBUTTON2" }, p.layers.LT.PAD3)
        assert.same({ type = "command", command = "MACRO Rotace" }, p.layers.RT.PADDUP)
    end)

    it("sets the cheat sheet scale within limits", function()
        assert.truthy(run("scale 1.3"):find("1.30"))
        assert.equal(1.3, ns.db.settings.scale)
        assert.truthy(run("scale 9"):find("usage"))
    end)

    it("prints a diagnostics report", function()
        assert.truthy(run("diag"):find("share round trip"))
    end)

    it("shows help for anything else", function()
        assert.truthy(run("wat"):find("/gg profile"))
    end)
end)
