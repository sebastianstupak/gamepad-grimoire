-- End to end with the mouse and the screen: the Settings page, the card's mouse
-- editor (drag a spell onto a row, right-click to clear, tabs, flip), the share
-- dialog and what each setup screen tells the player.
---@diagnostic disable: redundant-parameter
local Player = require("spec.helpers.player")

describe("e2e: windows and mouse", function()
    local me
    before_each(function()
        me = Player.login(nil)
    end)

    local function pin()
        me:openSettings("Gamepad Grimoire")
        me:click("Show / hide the cheat sheet")
        assert.is_true((me.ns.CheatSheet.State()))
    end

    it("has a Settings page that explains the addon and opens the setup and the card", function()
        me:openSettings("Gamepad Grimoire")
        assert.is_true(me:sees("Bind spells, items and macros"))
        assert.is_true(me:sees("LT %+ R3 opens the controller setup"))
        me:click("Open controller setup")
        assert.is_true(me.ns.Setup.IsOpen())
        assert.is_true(me.wow.settingsClosed > 0)
        me:tap("PAD2")
        me:openSettings("Gamepad Grimoire")
        me:click("Show / hide the cheat sheet")
        assert.is_true(me:sees("PINNED"))
        me:openSettings("Gamepad Grimoire")
        me:click("Show / hide the cheat sheet")
        assert.is_false((me.ns.CheatSheet.State()))
    end)

    it("binds by dragging a spell onto a row and clears with right-click", function()
        pin()
        me:drag({ kind = "spell", id = 172 }, "^A$")
        assert.is_true(me:sees("Corruption"))
        assert.is_nil(me.wow.cursor) -- the spell left the cursor
        me:tap("PAD1")
        assert.same({ "spell Corruption" }, me:actions())
        me:click("^A$", "RightButton")
        assert.is_false(me:sees("Corruption"))
        me:tap("PAD1")
        assert.same({}, me:actions())
    end)

    it("binds items and macros by dragging, and refuses other things", function()
        pin()
        me:drag({ kind = "item", id = 5512 }, "^B$")
        me:drag({ kind = "macro", name = "Pet Attack" }, "^X$")
        me:tap("PAD2", "PAD3")
        assert.same({ "item item:5512", "macro Pet Attack" }, me:actions())
        me:chatLines()
        me:drag({ kind = "mount", id = 1 }, "^Y$")
        assert.is_true(Player.any(me:chatLines(), "cannot bind a mount"))
        me:tap("PAD4")
        assert.same({}, me:actions())
    end)

    it("edits another layer after clicking its tab", function()
        pin()
        me:click("^Hold LT$")
        me:drag({ kind = "spell", id = 686 }, "^A$")
        me:tap("PAD1")
        assert.same({}, me:actions())
        me:holding({ "PADLTRIGGER" }, function()
            me:tap("PAD1")
        end)
        assert.same({ "spell Shadow Bolt" }, me:actions())
    end)

    it("applies a drop made in combat once combat ends", function()
        pin()
        me.wow.combat = true
        me:drag({ kind = "spell", id = 348 }, "^A$")
        me:tap("PAD1")
        assert.same({}, me:actions())
        me.wow.combat = false
        me.wow.fire("PLAYER_REGEN_ENABLED")
        me:tap("PAD1")
        assert.same({ "spell Immolate" }, me:actions())
    end)

    it("turns the card around with its tab, for every controller", function()
        for _, def in ipairs(me.ns.Controllers.Registry.All()) do
            me:chat("/gg controller " .. def.id)
            if not me.ns.CheatSheet.State() then
                pin()
            end
            assert.is_true(me:sees(def.name:gsub("%p", "%%%0")), def.id)
            me:click("^Back >$")
            assert.are.equal("back", me.ns.CheatSheet.ViewName(), def.id)
            assert.is_true(me:sees("^< Front$"), def.id)
            me:click("^< Front$")
            assert.are.equal("front", me.ns.CheatSheet.ViewName(), def.id)
        end
    end)

    it("shows the share dialog: copy text, import with a reason, close and Esc", function()
        me:chat("/gg export")
        assert.is_true(me:sees("^Export profile: Default$"))
        assert.is_true(me:sees("Ctrl%+C"))
        me:click("^Close$")
        assert.is_false(me:sees("Export profile"))
        me:chat("/gg import")
        assert.is_true(me:sees("^Import profile$"))
        me.ns.Share.Dialog.Frame().box:SetText("not a share string")
        me:click("^Import$")
        assert.is_true(me:sees("not a Gamepad Grimoire string"))
        local box = me.ns.Share.Dialog.Frame().box
        rawget(box, "scripts").OnEscapePressed(box)
        assert.is_false(me:sees("Import profile"))
        assert.same({ "GamepadGrimoireShareDialog" }, me.wow.escClose)
    end)

    it("tells the player which buttons do what on every setup screen", function()
        me:chat("/gg setup")
        assert.is_true(me:sees("D%-pad move   A choose   X clear   Y menu   LB / RB layer   B close"))
        me:tap("PAD1")
        assert.is_true(me:sees("^Bind LT:"))
        assert.is_true(me:sees("A bind   LB / RB category   B back"))
        for _, spell in ipairs({ "Corruption", "Immolate", "Shadow Bolt" }) do
            assert.is_true(me:sees(spell), spell)
        end
        me:tap("PAD2", "PAD4")
        assert.is_true(me:sees("A choose   left / right change   B back"))
        assert.is_true(me:sees("^Close setup$"))
        me:scrollTo("New empty profile")
        me:tap("PAD1")
        assert.is_true(me:sees("A type   X delete   LB / RB case   Y done   B cancel"))
        for ch in ("abcdefghijklmnopqrstuvwxyz0123456789"):gmatch(".") do
            assert.is_true(me:sees("^" .. ch .. "$") or me:sees("^" .. ch:upper() .. "$"), ch)
        end
        for _, key in ipairs({ "Aa", "Space", "Del", "Done" }) do
            assert.is_true(me:sees("^" .. key .. "$"), key)
        end
        me:tap("PAD2", "PAD2", "PAD2") -- keyboard -> menu -> card -> closed
        assert.is_false(me.ns.Setup.IsOpen())
        assert.is_false(me:sees("Close setup"))
    end)
end)
