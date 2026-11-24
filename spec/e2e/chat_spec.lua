-- End to end: every slash command, typed in chat by a player, checked by what
-- the player then sees in chat, on screen, and when pressing controller buttons.
---@diagnostic disable: redundant-parameter
local Player = require("spec.helpers.player")
local any = Player.any

-- SavedVariables of a player who already has two profiles
local function saved()
    return {
        schema = 2,
        profiles = {
            Default = { controller = "auto", layers = { BASE = { PAD1 = { type = "command", command = "JUMP" } } } },
            Raid = { controller = "auto", layers = { BASE = { PAD1 = { type = "spell", id = 172 } } } },
        },
        characters = {},
        settings = {},
    }
end

describe("e2e: chat commands", function()
    local me
    before_each(function()
        me = Player.login(saved())
    end)

    it("/gg and /gg help list every command; unknown ones show the help too", function()
        local help = me:chat("/gg")
        for _, cmd in ipairs({
            "setup",
            "profile use",
            "profile new",
            "profile copy",
            "profile rename",
            "profile delete",
            "controller",
            "capture",
            "export",
            "import",
            "show",
            "scale",
            "reload",
            "diag",
        }) do
            assert.is_true(any(help, "/gg " .. cmd), cmd)
        end
        assert.same(help, me:chat("/gg help"))
        assert.same(help, me:chat("/gg dance"))
        assert.same(help, me:chat("/grimoire help"))
    end)

    it("/gg profile lists profiles and marks the active one", function()
        local lines = me:chat("/gg profile")
        assert.same({ "* Default", "  Raid" }, lines)
        assert.same(lines, me:chat("/gg profile list"))
    end)

    it("/gg profile use switches the binds the controller fires", function()
        me:tap("PAD1")
        assert.same({ "command JUMP" }, me:actions())
        assert.is_true(any(me:chat("/gg profile use Raid"), "done: use Raid"))
        me:tap("PAD1")
        assert.same({ "spell Corruption" }, me:actions())
        assert.is_true(any(me:chat("/gg profile use Ghost"), "no profile named Ghost"))
    end)

    it("/gg profile new makes an empty profile and refuses duplicates", function()
        assert.is_true(any(me:chat("/gg profile new Mythic Plus"), "done: new Mythic Plus"))
        assert.is_true(any(me:chat("/gg profile"), "Mythic Plus"))
        assert.is_true(any(me:chat("/gg profile new Raid"), "already exists"))
        me:chat("/gg profile use Mythic Plus")
        me:tap("PAD1")
        assert.same({}, me:actions())
    end)

    it("/gg profile copy copies the active profile with its binds", function()
        me:chat("/gg profile use Raid")
        assert.is_true(any(me:chat("/gg profile copy Raid Alt"), "done: copy Raid Alt"))
        me:chat("/gg profile use Raid Alt")
        me:tap("PAD1")
        assert.same({ "spell Corruption" }, me:actions())
    end)

    it("/gg profile rename renames, and the character keeps using it", function()
        me:chat("/gg profile use Raid")
        assert.is_true(any(me:chat("/gg profile rename Raid = Heroic Raid"), "done"))
        assert.same({ "  Default", "* Heroic Raid" }, me:chat("/gg profile"))
        assert.is_true(any(me:chat("/gg profile rename nonsense"), "usage: /gg profile rename"))
        assert.is_true(any(me:chat("/gg profile rename Default = X"), "cannot be renamed"))
    end)

    it("/gg profile delete removes unused profiles only", function()
        me:chat("/gg profile use Raid")
        assert.is_true(any(me:chat("/gg profile delete Raid"), "in use"))
        me:chat("/gg profile use Default")
        assert.is_true(any(me:chat("/gg profile delete Raid"), "done: delete Raid"))
        assert.same({ "* Default" }, me:chat("/gg profile"))
        assert.is_true(any(me:chat("/gg profile delete Default"), "cannot be deleted"))
    end)

    it("/gg controller shows and changes the picture on the card", function()
        assert.is_true(any(me:chat("/gg controller"), "^controller: "))
        assert.is_true(any(me:chat("/gg controller dualsense"), "controller: DualSense"))
        me:chat("/gg show")
        assert.is_true(me:sees("DualSense"))
        assert.is_true(any(me:chat("/gg controller toaster"), "unknown controller: toaster"))
        for _, id in ipairs({ "steamdeck", "rogally", "legiongo", "msiclaw", "8bitdo", "generic", "auto" }) do
            assert.is_false(any(me:chat("/gg controller " .. id), "unknown"), id)
        end
    end)

    it("/gg capture turns the player's own controller keybinds into a profile", function()
        me.wow.keybinds["PAD2"] = "TOGGLEAUTORUN"
        me.wow.keybinds["SHIFT-PAD3"] = "TARGETNEARESTENEMY"
        assert.is_true(any(me:chat("/gg capture My Keys"), "captured 2 controller binds into profile My Keys"))
        me:chat("/gg profile use My Keys")
        me.wow.keybinds = {} -- the addon's binds work on their own
        me:tap("PAD2")
        me:holding({ "PADLTRIGGER" }, function()
            me:tap("PAD3")
        end)
        assert.same({ "command TOGGLEAUTORUN", "command TARGETNEARESTENEMY" }, me:actions())
        assert.is_true(any(me:chat("/gg capture My Keys"), "already exists"))
    end)

    it("/gg export shows a share string for the active or a named profile", function()
        me:chat("/gg export")
        assert.is_true(me:sees("^!GG1Z?!"))
        assert.is_true(any(me:chat("/gg export Ghost"), "no profile named Ghost"))
        me:chat("/gg export Raid")
        assert.is_true(me:sees("^!GG1Z?!"))
    end)

    it("/gg import adds a pasted profile without touching existing ones", function()
        me:chat("/gg export Raid")
        local text
        for _, t in ipairs(me:screen()) do
            text = text or (t:match("^!GG1Z?!") and t)
        end
        me:click("^Close$")
        me:chat("/gg import")
        local box = me.ns.Share.Dialog.Frame().box
        box:SetText(text)
        me:click("^Import$")
        assert.is_true(me:sees("imported profile Raid %(2%)"))
        me:chat("/gg profile use Raid (2)")
        me:tap("PAD1")
        assert.same({ "spell Corruption" }, me:actions())
    end)

    it("/gg show pins the card, on a layer if asked, and hides it again", function()
        assert.is_true(any(me:chat("/gg show"), "cheat sheet pinned"))
        assert.is_true(me:sees("Jump") or me:sees("JUMP"))
        assert.is_true(any(me:chat("/gg show"), "cheat sheet hidden"))
        assert.is_false(me:sees("JUMP"))
        assert.is_true(any(me:chat("/gg show lt"), "cheat sheet pinned"))
        assert.are.equal("LT", select(2, me.ns.CheatSheet.State()))
        assert.is_true(any(me:chat("/gg show back"), "usage: /gg show"))
    end)

    it("/gg scale sets the card size, back to automatic, and refuses nonsense", function()
        assert.is_true(any(me:chat("/gg scale 1.5"), "cheat sheet scale 1.50"))
        assert.are.equal(1.5, me.ns.CheatSheet.Scale())
        assert.is_true(any(me:chat("/gg scale auto"), "automatic"))
        assert.is_nil(me.ns.db.settings.scale)
        for _, bad in ipairs({ "9", "0.1", "big", "" }) do
            assert.is_true(any(me:chat("/gg scale " .. bad), "usage: /gg scale"), bad)
        end
    end)

    it("/gg reload applies the binds again", function()
        me.wow.bindings = {} -- something else cleared them
        me:tap("PAD1")
        assert.same({}, me:actions())
        assert.is_true(any(me:chat("/gg reload"), "^bindings "))
        me:tap("PAD1")
        assert.same({ "command JUMP" }, me:actions())
    end)

    it("/gg diag reports the client, the controller and the buttons the game sees", function()
        me.wow.knownButtons = { "PAD1", "PADPADDLE1" }
        local lines = me:chat("/gg diag")
        assert.is_true(#lines > 3)
        assert.is_true(any(lines, "buttons the game sees"))
        assert.is_true(any(lines, "PADPADDLE1"))
    end)

    it("/gg setup opens and closes the controller setup", function()
        me:chat("/gg setup")
        assert.is_true(me:sees("A bind") or me:sees("Gamepad Grimoire"))
        assert.is_true(me.ns.Setup.IsOpen())
        me:chat("/gg setup")
        assert.is_false(me.ns.Setup.IsOpen())
    end)
end)
