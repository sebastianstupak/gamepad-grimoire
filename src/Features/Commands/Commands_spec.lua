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

    it("shows help for anything else", function()
        assert.truthy(run("wat"):find("/gg profile"))
    end)
end)
