---@diagnostic disable: redundant-parameter
local ns = {}
assert(loadfile("src/Features/Setup/Navigator.lua"))("GamepadGrimoire", ns)
local N = ns.Setup.Navigator

local COLUMNS = { left = { "PADLTRIGGER", "PADLSHOULDER", "PADDUP" }, right = { "PADRTRIGGER", "PAD1" } }

local function ctx(n)
    local items = {}
    for i = 1, n or 20 do
        items[i] = { name = "Spell " .. i, action = { type = "spell", id = i } }
    end
    return {
        categories = {
            { name = "Spells", items = items },
            { name = "Game actions", items = { { name = "Jump", action = { type = "command", command = "JUMP" } } } },
        },
        menu = {
            { name = "Use profile: A", effect = { kind = "use", name = "A" } },
            { name = "Controller", adjust = "controller", effect = { kind = "controller", delta = 1 } },
            { name = "Close", effect = { kind = "close" } },
        },
    }
end

local function press(state, c, ...)
    local last
    for _, input in ipairs({ ... }) do
        last = N.Handle(state, input, c)
    end
    return last
end

describe("Setup.Navigator", function()
    it("starts on the first button of the left column, base layer", function()
        local s = N.New(COLUMNS)
        assert.are.equal("rows", s.screen)
        assert.are.equal("BASE", s.layer)
        assert.are.equal("PADLTRIGGER", N.Button(s))
    end)

    it("moves with the D-pad and stays inside the columns", function()
        local s, c = N.New(COLUMNS), ctx()
        press(s, c, "UP")
        assert.are.equal("PADLTRIGGER", N.Button(s))
        press(s, c, "DOWN", "DOWN", "DOWN", "DOWN")
        assert.are.equal("PADDUP", N.Button(s))
        press(s, c, "RIGHT") -- index clamps to the shorter right column
        assert.are.equal("PAD1", N.Button(s))
        press(s, c, "LEFT") -- same row on the other side
        assert.are.equal("PADLSHOULDER", N.Button(s))
    end)

    it("cycles layers with the shoulder buttons", function()
        local s, c = N.New(COLUMNS), ctx()
        press(s, c, "NEXT")
        assert.are.equal("LT", s.layer)
        press(s, c, "NEXT", "NEXT")
        assert.are.equal("BASE", s.layer)
        press(s, c, "PREV")
        assert.are.equal("RT", s.layer)
    end)

    it("binds a picked action to the selected button on the current layer", function()
        local s, c = N.New(COLUMNS), ctx()
        press(s, c, "DOWN", "NEXT", "ACCEPT")
        assert.are.equal("picker", s.screen)
        local effect = press(s, c, "DOWN", "DOWN", "ACCEPT")
        assert.are.same(
            { kind = "assign", layer = "LT", button = "PADLSHOULDER", action = { type = "spell", id = 3 } },
            effect
        )
        assert.are.equal("rows", s.screen)
    end)

    it("switches picker categories and pages through long lists", function()
        local s, c = N.New(COLUMNS), ctx(30)
        press(s, c, "ACCEPT", "RIGHT")
        assert.are.equal(1 + N.PAGE, s.picker.index)
        assert.are.equal(s.picker.index - N.PAGE + 1, s.picker.top)
        press(s, c, "RIGHT", "RIGHT", "RIGHT")
        assert.are.equal(30, s.picker.index)
        press(s, c, "NEXT")
        assert.are.equal(2, s.picker.category)
        assert.are.equal(1, s.picker.index)
        local effect = press(s, c, "ACCEPT")
        assert.are.same({ type = "command", command = "JUMP" }, effect.action)
    end)

    it("goes back without binding", function()
        local s, c = N.New(COLUMNS), ctx()
        local effect = press(s, c, "ACCEPT", "BACK")
        assert.is_nil(effect)
        assert.are.equal("rows", s.screen)
    end)

    it("clears the selected button", function()
        local s, c = N.New(COLUMNS), ctx()
        assert.are.same({ kind = "clear", layer = "BASE", button = "PADLTRIGGER" }, press(s, c, "CLEAR"))
    end)

    it("opens the menu, adjusts with left/right and chooses with A", function()
        local s, c = N.New(COLUMNS), ctx()
        press(s, c, "MENU")
        assert.are.equal("menu", s.screen)
        press(s, c, "DOWN")
        assert.are.same({ kind = "controller", delta = -1 }, press(s, c, "LEFT"))
        assert.are.equal("menu", s.screen) -- adjusting keeps the menu open
        press(s, c, "UP")
        assert.are.same({ kind = "use", name = "A" }, press(s, c, "ACCEPT"))
        assert.are.equal("rows", s.screen)
    end)

    it("closes from the rows screen and from the menu", function()
        local s, c = N.New(COLUMNS), ctx()
        assert.are.same({ kind = "close" }, press(s, c, "BACK"))
        s = N.New(COLUMNS)
        assert.are.same({ kind = "close" }, press(s, c, "MENU", "DOWN", "DOWN", "ACCEPT"))
    end)

    it("copes with empty lists", function()
        local s = N.New({ left = {}, right = { "PAD1" } })
        assert.are.equal("PAD1", N.Button(s))
        local c = { categories = {}, menu = {} }
        assert.is_nil(press(s, c, "ACCEPT", "DOWN", "NEXT", "ACCEPT"))
        assert.is_nil(press(s, c, "BACK", "MENU", "ACCEPT", "LEFT"))
    end)

    it("flips the card with View and selects pressed buttons", function()
        local s, c = N.New(COLUMNS), ctx()
        assert.are.same({ kind = "flip" }, press(s, c, "FLIP"))
        assert.is_true(N.Select(s, "PAD1"))
        assert.are.equal("PAD1", N.Button(s))
        assert.is_false(N.Select(s, "PADPADDLE1"))
    end)

    it("keeps the menu open for entries that stay (confirm, toggles)", function()
        local s = N.New(COLUMNS)
        local c = { categories = {}, menu = { { name = "Delete", stay = true, effect = { kind = "delete" } } } }
        assert.are.same({ kind = "delete" }, press(s, c, "MENU", "ACCEPT"))
        assert.are.equal("menu", s.screen)
    end)

    describe("on-screen keyboard", function()
        local s, c
        before_each(function()
            s, c = N.New(COLUMNS), ctx()
            N.OpenKeys(s, "", "new")
        end)

        it("types a capital first letter, then lower case", function()
            press(s, c, "ACCEPT", "RIGHT", "ACCEPT", "DOWN", "ACCEPT")
            assert.are.equal("Abl", s.keys.text)
        end)

        it("toggles case, deletes, and wraps left / right", function()
            press(s, c, "LEFT", "ACCEPT") -- wraps to "j", upper case
            press(s, c, "PREV", "ACCEPT", "CLEAR")
            assert.are.equal("J", s.keys.text)
        end)

        it("has space, delete, case and done keys on the last row", function()
            press(s, c, "ACCEPT") -- A
            for _ = 1, 5 do
                press(s, c, "DOWN")
            end
            press(s, c, "ACCEPT") -- Aa: case
            press(s, c, "RIGHT", "ACCEPT") -- Space
            press(s, c, "RIGHT", "ACCEPT") -- Del
            assert.are.equal("A", s.keys.text)
            assert.are.same({ kind = "new", text = "A" }, press(s, c, "RIGHT", "ACCEPT"))
            assert.are.equal("rows", s.screen)
        end)

        it("cancels back to the menu, and ignores an empty name", function()
            assert.is_nil(press(s, c, "BACK"))
            assert.are.equal("menu", s.screen)
            N.OpenKeys(s, "  ", "new")
            assert.is_nil(press(s, c, "MENU"))
        end)

        it("stops at the maximum length", function()
            for _ = 1, N.MAX_NAME + 5 do
                press(s, c, "ACCEPT")
            end
            assert.are.equal(N.MAX_NAME, #s.keys.text)
        end)
    end)

    it("maps gamepad buttons and keys to the same inputs", function()
        assert.are.equal(N.INPUT.PAD1, N.INPUT.ENTER)
        assert.are.equal(N.INPUT.PAD2, N.INPUT.ESCAPE)
        assert.are.equal(N.INPUT.PADDUP, N.INPUT.UP)
        assert.are.equal(N.INPUT.PADLSHOULDER, N.INPUT.Q)
    end)
end)
