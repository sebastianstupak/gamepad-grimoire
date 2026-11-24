-- End to end with the controller only: no chat, no mouse, no keyboard. Buttons
-- go where the game sends them (the setup's input frame while it is open, the
-- addon's override bindings otherwise), and results are checked by pressing
-- buttons in play and by what is on screen.
---@diagnostic disable: redundant-parameter
local Player = require("spec.helpers.player")

local function deck()
    return {
        schema = 2,
        profiles = { Default = { controller = "steamdeck", layers = {} } },
        characters = {},
        settings = {},
    }
end

describe("e2e: controller only", function()
    local me
    before_each(function()
        me = Player.login(deck())
    end)

    -- LT + R3, the pin chord
    local function chord()
        me:holding({ "PADLTRIGGER" }, function()
            me:tap("PADRSTICK")
        end)
    end

    it("opens the setup with LT + R3 and closes it with B, leaving the card as it was", function()
        assert.is_false(me:sees("A bind"))
        chord()
        assert.is_true(me.ns.Setup.IsOpen())
        assert.is_true((me.ns.CheatSheet.State()))
        me:tap("PAD2")
        assert.is_false(me.ns.Setup.IsOpen())
        assert.is_false((me.ns.CheatSheet.State()))
    end)

    it("binds a spell to a button, then that button casts it in play", function()
        chord()
        me:tap("PADRSTICK") -- jump to the R3 row by pressing R3
        me:tap("PAD1") -- open the picker
        assert.is_true(me:sees("Bind"))
        me:scrollTo("Immolate")
        me:tap("PAD1") -- bind
        me:tap("PAD2") -- close
        me:tap("PADRSTICK")
        assert.same({ "spell Immolate" }, me:actions())
    end)

    it("does not cast while the setup is open: the buttons belong to the setup", function()
        chord()
        me:tap("PADRSTICK", "PAD1", "PAD1", "PAD2")
        me:actions()
        chord()
        me:tap("PADRSTICK")
        assert.same({}, me:actions())
    end)

    it("binds on the LT layer and fires it with LT held", function()
        chord()
        me:tap("PADRSHOULDER") -- RB: next layer (LT)
        me:tap("PADLSTICK", "PAD1")
        me:scrollTo("Corruption")
        me:tap("PAD1", "PAD2")
        me:tap("PADLSTICK")
        assert.same({}, me:actions())
        me:holding({ "PADLTRIGGER" }, function()
            me:tap("PADLSTICK")
        end)
        assert.same({ "spell Corruption" }, me:actions())
    end)

    it("clears a bind with X", function()
        chord()
        me:tap("PADRSTICK", "PAD1", "PAD1")
        me:tap("PADRSTICK", "PAD3") -- X on the R3 row
        me:tap("PAD2")
        me:tap("PADRSTICK")
        assert.same({}, me:actions())
    end)

    it("binds game actions and macros from the other categories with LB / RB", function()
        me.wow.macros = { { name = "Pet Attack", icon = 1 } }
        chord()
        me:tap("PADRSTICK", "PAD1")
        me:tap("PADRSHOULDER") -- Spells -> Macros
        assert.is_true(me:sees("Macros"))
        me:tap("PAD1", "PAD2")
        me:tap("PADRSTICK")
        assert.same({ "macro Pet Attack" }, me:actions())
    end)

    it("peeks at the LT layer while LT is held, and hides it on release", function()
        chord()
        me:tap("PADRSHOULDER", "PADLSTICK", "PAD1") -- LT layer, L3 row, the list
        me:tap("PAD1", "PAD2") -- first spell: Corruption
        assert.is_false(me:sees("Corruption"))
        me:holding({ "PADLTRIGGER" }, function()
            me:wait(0.5)
            assert.is_true(me:sees("Corruption"))
        end)
        me:wait(0.2)
        assert.is_false(me:sees("Corruption"))
    end)

    it("lights up held buttons while peeking and turns the card around for the back grips", function()
        local function row(button)
            for _, r in ipairs(me.ns.CheatSheet.Card().rows) do
                if r.button == button then
                    return r
                end
            end
        end
        me:holding({ "PADLTRIGGER" }, function()
            me:wait(0.5) -- the card shows the LT layer
            me:down("PAD1")
            me:wait(0.1)
            assert.is_true(rawget(row("PAD1"), "pressed"))
            me:up("PAD1")
            me:wait(0.1)
            assert.is_false(rawget(row("PAD1"), "pressed"))
            me:down("PADPADDLE3") -- L4
            me:wait(0.1)
            assert.are.equal("back", me.ns.CheatSheet.ViewName())
            assert.is_true(me:sees("L4"))
            assert.is_true(rawget(row("PADPADDLE3"), "pressed"))
            me:up("PADPADDLE3")
        end)
    end)

    it("binds a back grip and fires it in play", function()
        chord()
        me:tap("PADPADDLE1") -- R4: flips to the back on its row
        assert.is_true(me:sees("R4"))
        me:tap("PAD1", "PAD1", "PAD2")
        me:tap("PADPADDLE1")
        assert.same({ "spell Corruption" }, me:actions())
    end)

    it("says so on the back view when the game cannot see the back buttons", function()
        -- a Steam Deck through Steam Input looks like an Xbox 360 pad: no paddles
        me.wow.knownButtons = { "PAD1", "PAD2", "PAD3", "PAD4", "PADLSHOULDER", "PADRSHOULDER", "PADBACK" }
        chord()
        assert.is_false(me:sees("does not see back buttons"))
        me:tap("PADBACK")
        assert.is_true(me:sees("does not see back buttons"))
        me.wow.knownButtons = { "PAD1", "PADPADDLE1", "PADPADDLE2" } -- an Elite / DualSense Edge
        me:tap("PADBACK", "PADBACK")
        assert.is_false(me:sees("does not see back buttons"))
    end)

    it("does not show the Steam button SteamOS keeps for itself", function()
        chord()
        assert.is_false(me:sees("^Steam$"))
        for _, r in ipairs(me.ns.CheatSheet.Card().rows) do
            assert.are_not.equal("PADSYSTEM", r.button)
        end
    end)

    it("flips the card with View and back again", function()
        chord()
        me:tap("PADBACK")
        assert.are.equal("back", me.ns.CheatSheet.ViewName())
        me:tap("PADBACK")
        assert.are.equal("front", me.ns.CheatSheet.ViewName())
    end)

    it("names a new profile on the on-screen keyboard and switches to it", function()
        chord()
        me:tap("PAD4") -- Y: menu
        me:scrollTo("New empty profile")
        me:tap("PAD1")
        assert.is_true(me:sees("Y done"))
        me:typeOnPad("pad")
        assert.is_true(me:sees("^Pad"))
        me:tap("PAD4") -- Y: done
        assert.are.equal("Pad", me.ns.Profiles.ActiveName())
    end)

    it("switches, renames and deletes profiles from the menu", function()
        me.ns.Profiles.Create("Arena")
        chord()
        me:tap("PAD4")
        me:scrollTo("Use profile: Arena")
        me:tap("PAD1")
        assert.are.equal("Arena", me.ns.Profiles.ActiveName())
        me:tap("PAD4")
        me:scrollTo("Rename Arena")
        me:tap("PAD1")
        me:typeOnPad("2")
        me:tap("PAD4")
        assert.are.equal("Arena2", me.ns.Profiles.ActiveName())
        me:tap("PAD4")
        me:scrollTo("Delete Arena2")
        me:tap("PAD1")
        assert.is_table(me.ns.Profiles.Get("Arena2")) -- first A only asks
        me:tap("PAD1")
        assert.is_nil(me.ns.Profiles.Get("Arena2"))
        assert.are.equal("Default", me.ns.Profiles.ActiveName())
    end)

    it("changes the controller picture from the menu", function()
        chord()
        me:tap("PAD4")
        me:scrollTo("Controller picture")
        assert.is_true(me:sees("Steam Deck"))
        me:tap("PADDRIGHT")
        assert.is_true(me:isHighlighted("Controller picture"))
        assert.is_false(me:isHighlighted("Steam Deck"))
        assert.are_not.equal("steamdeck", me.ns.Profiles.ActiveProfile().controller)
    end)

    it("closes the setup when combat starts and gives the buttons back to the game", function()
        chord()
        me:tap("PADRSTICK", "PAD1", "PAD1") -- R3 = Corruption
        me.wow.combat = true
        me.wow.fire("PLAYER_REGEN_DISABLED")
        assert.is_false(me.ns.Setup.IsOpen())
        me:tap("PADRSTICK")
        assert.same({ "spell Corruption" }, me:actions())
        chord() -- the pin chord cannot open it in combat
        assert.is_false(me.ns.Setup.IsOpen())
    end)

    it("lets keys it does not use reach the game while open", function()
        me.wow.keybinds["F1"] = "TARGETSELF"
        chord()
        assert.is_false(me:key("F1"))
        assert.same({ "command TARGETSELF" }, me:actions())
        assert.is_true(me:key("ESCAPE"))
        assert.is_false(me.ns.Setup.IsOpen())
    end)
end)
