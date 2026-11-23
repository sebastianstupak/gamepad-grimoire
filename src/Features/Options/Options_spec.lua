---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("Options (Settings > AddOns page)", function()
    local ns, wow
    before_each(function()
        ns, wow = Addon.start()
    end)

    it("registers a page in the game's settings", function()
        assert.is_true(ns.Options.registered)
        assert.are.equal("Gamepad Grimoire", wow.settingsPages[1])
    end)

    it("opens the controller setup and the cheat sheet from its buttons", function()
        local f = ns.Options.frame
        rawget(rawget(f, "setup"), "scripts").OnClick()
        assert.is_true(ns.Setup.IsOpen())
        assert.is_true(wow.settingsClosed > 0)
        ns.Setup.Close()
        rawget(rawget(f, "show"), "scripts").OnClick()
        assert.is_true((ns.CheatSheet.State()))
    end)
end)
