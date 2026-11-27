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

    local function button()
        return ns.Setup.Navigator.Button(ns.Setup.State())
    end

    -- opens the menu (Y) and moves down to the first entry containing `text`
    local function menuTo(text)
        if ns.Setup.State().screen ~= "menu" then
            press("PAD4")
        end
        local m = ns.Setup.State().menu
        m.index = 1
        for _ = 1, 30 do
            local items = ns.Setup._menu()
            if items[m.index].name:find(text, 1, true) then
                return
            end
            press("PADDDOWN")
        end
        error("no menu entry " .. text)
    end

    local function type(text)
        for ch in text:gmatch(".") do
            press(ch == " " and "SPACE_KEY" or ch)
        end
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
        local first = button()
        press("PADDDOWN")
        local b = button()
        assert.are_not.equal(first, b)
        press("PAD1", "PADDDOWN", "PAD1") -- picker, second spell (Immolate), bind
        assert.are.same({ type = "spell", id = 348 }, layer("BASE")[b])
        press("PAD3") -- X clears it again
        assert.is_nil(layer("BASE")[b])
    end)

    it("binds on the LT layer and picks game actions", function()
        ns.Setup.Open()
        press("PADRSHOULDER") -- layer LT
        press("PADDDOWN", "PAD1")
        press("PADRSHOULDER", "PADRSHOULDER") -- Spells -> Macros -> Game actions
        press("PAD1")
        assert.are.same({ type = "command", command = "JUMP" }, layer("LT")[button()])
    end)

    it("jumps to the row of any other button that is pressed", function()
        ns.Setup.Open()
        press("PADRSTICK")
        assert.are.equal("PADRSTICK", button())
        press("PADLTRIGGER")
        assert.are.equal("PADLTRIGGER", button())
    end)

    it("flips to the back of the controller with View, and for back buttons", function()
        ns.Profiles.ActiveProfile().controller = "steamdeck"
        ns.Setup.Open()
        press("PADBACK") -- View / Select
        assert.are.equal("back", ns.CheatSheet.ViewName())
        assert.are.equal("steamdeck_back", ns.CheatSheet.Card().def.id)
        press("PADBACK")
        assert.are.equal("front", ns.CheatSheet.ViewName())
        press("PADPADDLE1") -- R4: on the back only
        assert.are.equal("back", ns.CheatSheet.ViewName())
        assert.are.equal("PADPADDLE1", button())
        press("PAD1", "PAD1") -- bind the first spell to R4
        assert.are.same({ type = "spell", id = 172 }, layer("BASE").PADPADDLE1)
    end)

    it("switches profiles from the menu", function()
        ns.Profiles.Create("Healer")
        ns.Setup.Open()
        menuTo("Use profile: Healer")
        press("PAD1")
        assert.are.equal("Healer", ns.Profiles.ActiveName())
    end)

    it("names new profiles with the on-screen keyboard", function()
        ns.Setup.Open()
        menuTo("New empty profile")
        press("PAD1")
        assert.are.equal("keys", ns.Setup.State().screen)
        press("PAD1") -- "A" (first key, upper case at the start)
        press("PADDRIGHT", "PAD1") -- "b"
        press("PADLSHOULDER", "PAD1") -- LB: upper case, "B"
        press("PAD3") -- X deletes it
        press("PAD4") -- Y: done
        assert.are.equal("Ab", ns.Profiles.ActiveName())
    end)

    it("types with a real keyboard too, and renames the active profile", function()
        ns.Profiles.Create("Old")
        ns.Profiles.Use("Old")
        ns.Setup.Open()
        menuTo("Rename Old")
        press("PAD1")
        for _ = 1, 3 do
            press("PAD3") -- delete "Old"
        end
        type("tank")
        press("ENTER") -- Enter on the first key types; Y / Tab finish
        press("PAD3", "TAB")
        assert.are.equal("Tank", ns.Profiles.ActiveName())
        assert.is_nil(ns.Profiles.Get("Old"))
    end)

    it("copies a profile and cancels the keyboard with B", function()
        ns.Setup.Open()
        menuTo("Copy Default")
        press("PAD1", "PAD4")
        assert.are.equal("Copy of Default", ns.Profiles.ActiveName())
        menuTo("New empty profile")
        press("PAD1", "PAD2")
        assert.are.equal("menu", ns.Setup.State().screen)
    end)

    it("deletes a profile only after pressing A twice", function()
        ns.Profiles.Create("Junk")
        ns.Profiles.Use("Junk")
        ns.Setup.Open()
        menuTo("Delete Junk")
        press("PAD1")
        assert.is_table(ns.Profiles.Get("Junk"))
        assert.are.equal("menu", ns.Setup.State().screen)
        press("PAD1")
        assert.is_nil(ns.Profiles.Get("Junk"))
        assert.are.equal("Default", ns.Profiles.ActiveName())
    end)

    it("uses a profile for the current specialization only", function()
        ns.Profiles.Create("Shadow")
        ns.Profiles.Use("Shadow")
        ns.Setup.Open()
        menuTo("for this specialization")
        press("PAD1")
        assert.are.equal("Shadow", ns.Profiles.SpecProfile(state.spec))
        press("PAD1")
        assert.is_nil(ns.Profiles.SpecProfile(state.spec))
    end)

    it("changes the controller picture and card size with left / right", function()
        ns.Setup.Open()
        menuTo("Controller picture")
        press("PADDRIGHT")
        assert.are_not.equal("auto", ns.Profiles.ActiveProfile().controller)
        menuTo("Card size")
        press("PADDRIGHT")
        assert.is_number(ns.db.settings.scale)
        press("PAD1") -- A on the size entry: automatic again
        assert.is_nil(ns.db.settings.scale)
    end)

    it("captures the current keybinds as a new profile", function()
        state.keybinds["PAD1"] = "JUMP"
        ns.Setup.Open()
        menuTo("Capture")
        press("PAD1")
        assert.are.equal("Captured", ns.Profiles.ActiveName())
        assert.are.same({ type = "command", command = "JUMP" }, layer("BASE").PAD1)
    end)

    it("lets keys it does not use through, and closes when combat starts", function()
        ns.Setup.Open()
        assert.is_false(ns.Setup.Press("F5"))
        state.fire("PLAYER_REGEN_DISABLED")
        assert.is_false(ns.Setup.IsOpen())
        assert.is_false(ns.Setup.Press("PAD1"))
    end)

    it("does not open in combat", function()
        state.combat = true
        assert.is_false(ns.Setup.Open())
    end)

    it("deleting the profile of this specialization also stops using it for the spec", function()
        ns.Profiles.Create("Shadow")
        ns.Profiles.Use("Shadow", state.spec)
        ns.Setup.Open()
        menuTo("Delete Shadow")
        press("PAD1", "PAD1")
        assert.is_nil(ns.Profiles.Get("Shadow"))
        assert.is_nil(ns.Profiles.SpecProfile(state.spec))
    end)

    it("says why a rename is refused and keeps the old name", function()
        ns.Profiles.Create("Taken")
        ns.Profiles.Create("Mine")
        ns.Profiles.Use("Mine")
        ns.Setup.Open()
        menuTo("Rename Mine")
        press("PAD1")
        for _ = 1, 4 do
            press("PAD3") -- X deletes "Mine"
        end
        type("Taken")
        press("PAD4") -- Y = done
        assert.are.equal("Mine", ns.Profiles.ActiveName())
        assert.matches("already exists", state.printed[#state.printed])
    end)

    it("reads gamepad buttons and keys from its input frame", function()
        ns.Setup.Open()
        local input
        for _, f in ipairs(state.frames) do
            if rawget(f, "name") == "GamepadGrimoireSetupInput" then
                input = f
            end
        end
        local scripts = rawget(input, "scripts")
        local before = button()
        scripts.OnGamePadButtonDown(input, "PADDDOWN")
        assert.are_not.equal(before, button())
        -- a button the setup uses is consumed, so it does not also fire the
        -- player's own binding (jump / cast) while they are editing
        assert.same({ false }, rawget(input, "calls").SetPropagateGamePadInput)
        scripts.OnKeyDown(input, "F5") -- not ours: passes through to the game
        assert.same({ true }, rawget(input, "calls").SetPropagateKeyboardInput)
        scripts.OnKeyDown(input, "ESCAPE") -- ours: kept
        assert.same({ false }, rawget(input, "calls").SetPropagateKeyboardInput)
        assert.is_false(ns.Setup.IsOpen())
    end)

    it("opening twice is harmless and closing a closed setup does nothing", function()
        assert.is_true(ns.Setup.Open())
        local s = ns.Setup.State()
        assert.is_true(ns.Setup.Open())
        assert.are.equal(s, ns.Setup.State())
        ns.Setup.Close()
        ns.Setup.Close()
        assert.is_false(ns.Setup.IsOpen())
    end)

    it("leaves a card that was already pinned on screen", function()
        ns.CheatSheet.Toggle()
        ns.Setup.Open()
        ns.Setup.Close()
        assert.is_true((ns.CheatSheet.State()))
    end)

    it("leaves flipping to the setup: held navigation buttons only light up", function()
        ns.Profiles.ActiveProfile().controller = "steamdeck"
        ns.Setup.Open()
        press("PADPADDLE3") -- L4: the setup turns the card and selects its row
        assert.are.equal("back", ns.CheatSheet.ViewName())
        ns.CheatSheet.ShowPressed({ PADPADDLE3 = true, PAD1 = true }) -- A held to open the list
        assert.are.equal("back", ns.CheatSheet.ViewName())
        assert.are.equal("PADPADDLE3", button())
    end)

    it("is available as /gg setup", function()
        ns.Commands.Run("setup")
        assert.is_true(ns.Setup.IsOpen())
        ns.Commands.Run("setup")
        assert.is_false(ns.Setup.IsOpen())
    end)
end)
