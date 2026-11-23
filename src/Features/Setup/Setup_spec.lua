---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("Setup (controller-only configuration)", function()
    local ns, state

    before_each(function()
        ns, state = Addon.start()
        state.macros = { { name = "Pet Attack Macro", icon = 1 } }
    end)

    local function press(...)
        for _, key in ipairs({ ... }) do
            assert.is_true(ns.Setup.Press(key), key)
        end
    end

    local function layer(name)
        return ns.Profiles.ActiveProfile().layers[name] or {}
    end

    it("opens and closes with the pin chord and leaves the card as it was", function()
        local toggle
        for _, f in ipairs(state.frames) do
            if rawget(f, "name") == "GamepadGrimoireToggle" then
                toggle = f
            end
        end
        rawget(toggle, "scripts").OnClick(toggle)
        assert.is_true(ns.Setup.IsOpen())
        assert.is_true((ns.CheatSheet.State()))
        press("PAD2")
        assert.is_false(ns.Setup.IsOpen())
        assert.is_false((ns.CheatSheet.State()))
    end)

    it("binds a spell to a button with the D-pad and A only", function()
        ns.Setup.Open()
        local first = ns.Setup.Navigator.Button(ns.Setup.State())
        -- first row is the LT trigger: move to the next one (L1)
        press("PADDDOWN")
        local button = ns.Setup.Navigator.Button(ns.Setup.State())
        assert.are_not.equal(first, button)
        press("PAD1", "PADDDOWN", "PAD1") -- picker, second spell (Immolate), bind
        assert.are.same({ type = "spell", id = 348 }, layer("BASE")[button])
        press("PAD3") -- X clears it again
        assert.is_nil(layer("BASE")[button])
    end)

    it("binds on the LT layer and picks game actions", function()
        ns.Setup.Open()
        press("PADRSHOULDER") -- layer LT
        press("PADDDOWN", "PAD1")
        press("PADRSHOULDER", "PADRSHOULDER") -- Spells -> Macros -> Game actions
        press("PAD1")
        local button = ns.Setup.Navigator.Button(ns.Setup.State())
        assert.are.same({ type = "command", command = "JUMP" }, layer("LT")[button])
    end)

    it("switches and copies profiles from the menu", function()
        ns.Profiles.Create("Healer")
        ns.Setup.Open()
        press("PAD4") -- menu: Default, Healer, New profile, ...
        press("PADDDOWN", "PAD1")
        assert.are.equal("Healer", ns.Profiles.ActiveName())
        press("PAD4", "PADDDOWN", "PADDDOWN", "PAD1")
        assert.are.equal("Copy of Healer", ns.Profiles.ActiveName())
    end)

    it("changes the controller picture and card size with left / right", function()
        ns.Setup.Open()
        press("PAD4", "PADDDOWN", "PADDDOWN", "PADDRIGHT") -- controller entry
        assert.are_not.equal("auto", ns.Profiles.ActiveProfile().controller)
        press("PADDDOWN", "PADDRIGHT")
        assert.is_number(ns.db.settings.scale)
        press("PAD1") -- A on the size entry: automatic again
        assert.is_nil(ns.db.settings.scale)
    end)

    it("captures the current keybinds as a new profile", function()
        state.keybinds["PAD1"] = "JUMP"
        ns.Setup.Open()
        press("PAD4")
        for _ = 1, 4 do
            press("PADDDOWN")
        end
        press("PAD1")
        assert.are.equal("Captured", ns.Profiles.ActiveName())
        assert.are.same({ type = "command", command = "JUMP" }, layer("BASE").PAD1)
    end)

    it("lets keys it does not use through, and closes when combat starts", function()
        ns.Setup.Open()
        assert.is_false(ns.Setup.Press("W"))
        state.fire("PLAYER_REGEN_DISABLED")
        assert.is_false(ns.Setup.IsOpen())
        assert.is_false(ns.Setup.Press("PAD1"))
    end)

    it("does not open in combat", function()
        state.combat = true
        assert.is_false(ns.Setup.Open())
    end)

    it("is available as /gg setup", function()
        ns.Commands.Run("setup")
        assert.is_true(ns.Setup.IsOpen())
        ns.Commands.Run("setup")
        assert.is_false(ns.Setup.IsOpen())
    end)
end)
