local Addon = require("spec.helpers.addon")

describe("Bindings", function()
    describe("Model", function()
        local ns, Model
        before_each(function()
            ns = Addon.load({ upTo = "Bindings/Model.lua" })
            Model = ns.Bindings.Model
        end)

        it("sets, gets and clears actions per layer", function()
            local layout = Model.New()
            Model.Set(layout, "LT", "PAD3", { type = "spell", id = 172 })
            assert.same({ type = "spell", id = 172 }, Model.Get(layout, "LT", "PAD3"))
            Model.Set(layout, "LT", "PAD3", nil)
            assert.is_nil(Model.Get(layout, "LT", "PAD3"))
        end)

        it("rejects unknown layers, buttons and malformed actions", function()
            local layout = Model.New()
            assert.has_error(function()
                Model.Set(layout, "ALT", "PAD1", { type = "command", command = "JUMP" })
            end)
            assert.has_error(function()
                Model.Set(layout, "BASE", "KEY_Q", { type = "command", command = "JUMP" })
            end)
            assert.has_error(function()
                Model.Set(layout, "BASE", "PAD1", { type = "spell", id = -1 })
            end)
        end)

        it("reports every problem in untrusted layouts", function()
            local ok, errors = Model.Validate({
                layers = {
                    BASE = { PAD1 = { type = "spell", id = 1.5 }, NOPE = { type = "command", command = "X" } },
                    WAT = {},
                },
            })
            assert.is_false(ok)
            assert.equal(3, #errors)
        end)

        it("maps held-trigger layers to the modifiers the client emulates", function()
            local cvars = { GamePadEmulateShift = "PADLTRIGGER", GamePadEmulateCtrl = "PADRTRIGGER" }
            local mods = Model.LayerModifiers(function(k)
                return cvars[k]
            end)
            assert.same({ LT = "SHIFT", RT = "CTRL" }, mods)
        end)

        it("flattens a layout into sorted keys and reports unreachable layers", function()
            local layout = Model.New()
            Model.Set(layout, "BASE", "PAD1", { type = "command", command = "JUMP" })
            Model.Set(layout, "LT", "PAD3", { type = "spell", id = 172 })
            Model.Set(layout, "RT", "PAD2", { type = "macro", name = "Rotace" })
            local bindings, unreachable = Model.ToBindings(layout, { LT = "SHIFT" })
            assert.same({ "PAD1", "SHIFT-PAD3" }, {
                bindings[1].key,
                bindings[2].key,
            })
            assert.same({ "RT" }, unreachable)
        end)
    end)

    describe("Applier", function()
        it("applies override bindings by action type", function()
            local ns, wow = Addon.load()
            local status, applied = ns.Bindings.Applier.Apply({
                { key = "PAD1", action = { type = "command", command = "JUMP" } },
                { key = "SHIFT-PAD3", action = { type = "spell", id = 172 } },
                { key = "PAD4", action = { type = "item", id = 6948 } },
                { key = "CTRL-PAD2", action = { type = "macro", name = "Rotace" } },
            })
            assert.equal("applied", status)
            assert.equal(4, applied)
            local set = wow.bindingsOf("GamepadGrimoireBindingOwner")
            assert.same({ kind = "spell", value = "Corruption" }, set["SHIFT-PAD3"])
            assert.same({ kind = "item", value = "item:6948" }, set.PAD4)
        end)

        it("skips spells the client does not know", function()
            local ns = Addon.load()
            local _, applied, skipped = ns.Bindings.Applier.Apply({
                { key = "PAD1", action = { type = "spell", id = 999999 } },
            })
            assert.equal(0, applied)
            assert.same({ "PAD1" }, skipped)
        end)

        it("queues changes during combat and applies the latest set afterwards", function()
            local ns, wow = Addon.load()
            wow.combat = true
            local Applier = ns.Bindings.Applier
            assert.equal("queued", Applier.Apply({ { key = "PAD1", action = { type = "command", command = "A" } } }))
            assert.equal("queued", Applier.Apply({ { key = "PAD2", action = { type = "command", command = "B" } } }))
            assert.same({}, wow.bindingsOf("GamepadGrimoireBindingOwner"))
            wow.combat = false
            wow.fire("PLAYER_REGEN_ENABLED")
            local set = wow.bindingsOf("GamepadGrimoireBindingOwner")
            assert.is_nil(set.PAD1)
            assert.same({ kind = "command", value = "B" }, set.PAD2)
        end)

        it("clears everything so the player's own keybinds come back", function()
            local ns, wow = Addon.load()
            ns.Bindings.Applier.Apply({ { key = "PAD1", action = { type = "command", command = "JUMP" } } })
            ns.Bindings.Applier.Clear()
            assert.same({}, wow.bindingsOf("GamepadGrimoireBindingOwner"))
        end)
    end)

    it("applies the active profile on login and when it changes", function()
        local ns, wow = Addon.start({
            schema = 1,
            profiles = {
                Default = { controller = "auto", layers = { BASE = { PAD1 = { type = "command", command = "JUMP" } } } },
                Raid = { controller = "auto", layers = { BASE = { PAD2 = { type = "command", command = "TARGET" } } } },
            },
            characters = {},
            settings = {},
        })
        local function current()
            local set = wow.bindingsOf("GamepadGrimoireBindingOwner")
            return set
        end
        assert.is_table(current().PAD1)
        ns.Profiles.Use("Raid")
        assert.is_nil(current().PAD1)
        assert.is_table(current().PAD2)
    end)
end)
