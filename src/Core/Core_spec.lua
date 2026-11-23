local Addon = require("spec.helpers.addon")

describe("Core", function()
    describe("modules", function()
        it("initialises and enables modules in registration order on startup", function()
            local ns = Addon.load({ upTo = "Core/Store.lua" })
            local calls = {}
            for _, name in ipairs({ "A", "B" }) do
                local m = ns.NewModule(name)
                function m:OnInitialize()
                    calls[#calls + 1] = name .. ":init"
                end
                function m:OnEnable()
                    calls[#calls + 1] = name .. ":enable"
                end
            end
            ns.CallModules("OnInitialize")
            ns.CallModules("OnEnable")
            assert.same({ "A:init", "B:init", "A:enable", "B:enable" }, calls)
        end)

        it("rejects duplicate module names", function()
            local ns = Addon.load({ upTo = "Core/Namespace.lua" })
            ns.NewModule("X")
            assert.has_error(function()
                ns.NewModule("X")
            end)
        end)
    end)

    describe("events", function()
        it("delivers internal messages and supports unsubscribe", function()
            local ns = Addon.load({ upTo = "Core/Events.lua" })
            local got = {}
            local off = ns.Events.On("PING", function(v)
                got[#got + 1] = v
            end)
            ns.Events.Emit("PING", 1)
            off()
            ns.Events.Emit("PING", 2)
            assert.same({ 1 }, got)
        end)

        it("routes game events to subscribers", function()
            local ns, wow = Addon.load({ upTo = "Core/Events.lua" })
            local got
            ns.Events.OnGame("PLAYER_REGEN_ENABLED", function(event)
                got = event
            end)
            wow.fire("PLAYER_REGEN_ENABLED")
            assert.equal("PLAYER_REGEN_ENABLED", got)
        end)
    end)

    describe("store", function()
        it("creates the default profile on first run", function()
            local ns = Addon.load({ upTo = "Core/Store.lua" })
            local db = ns.Store.Load(nil)
            assert.equal(ns.Store.SCHEMA, db.schema)
            assert.is_table(db.profiles.Default)
        end)

        it("keeps data from a newer version untouched and read-only", function()
            local ns = Addon.load({ upTo = "Core/Store.lua" })
            local saved = { schema = 99, profiles = { X = {} } }
            local db, warning = ns.Store.Load(saved)
            assert.is_true(db.readOnly)
            assert.equal(99, db.schema)
            assert.truthy(warning)
        end)
    end)

    it("starts the whole addon against the fake client", function()
        local ns = Addon.start(nil)
        assert.is_table(ns.db)
        assert.equal("Default", ns.Store.Character(ns.db, "Zorelo-Umbra").profile)
    end)
end)
