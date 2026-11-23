-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
-- Contract test for the REAL adapter (src/Core/Wow.lua), which unit tests otherwise
-- replace with the fake. It runs the adapter against a minimal client that only has
-- the long-standing API: everything the slices use must exist, and optional APIs
-- (specs, C_GamePad, C_EncodingUtil, atlases...) must degrade instead of erroring.
-- Found in game: WoW: Forever has no GetSpecialization.
local Fake = require("spec.helpers.wow_fake")

local function minimalClient()
    local frames = {}
    local env = {
        CreateFrame = function()
            local f = {}
            function f.RegisterEvent() end
            function f.SetScript() end
            frames[#frames + 1] = f
            return f
        end,
        InCombatLockdown = function()
            return false
        end,
        SetOverrideBinding = function() end,
        SetOverrideBindingSpell = function() end,
        SetOverrideBindingItem = function() end,
        SetOverrideBindingMacro = function() end,
        ClearOverrideBindings = function() end,
        GetCVar = function()
            return "1"
        end,
        GetSpellInfo = function()
            return "Corruption", nil, 136118
        end,
        UnitName = function()
            return "Zorelo"
        end,
        UnitFullName = function()
            return "Zorelo", nil
        end,
        GetRealmName = function()
            return ""
        end,
        GetBindingAction = function()
            return ""
        end,
        GetBuildInfo = function()
            return "1.60.1", "71037", "Nov 18 2026", 16001
        end,
        HasAction = function()
            return false
        end,
        GetMacroInfo = function()
            return nil
        end,
        GetCursorInfo = function()
            return nil
        end,
        ClearCursor = function() end,
        IsShiftKeyDown = function()
            return false
        end,
        IsControlKeyDown = function()
            return false
        end,
        SlashCmdList = {},
        UISpecialFrames = {},
        UIParent = {},
        DEFAULT_CHAT_FRAME = { AddMessage = function() end },
        print = function() end,
    }
    env._G = env
    setmetatable(env, { __index = _G })
    return env
end

local function loadAdapter(env)
    local chunk = assert(loadfile("src/Core/Wow.lua"))
    setfenv(chunk, env)
    local ns = {}
    chunk("GamepadGrimoire", ns)
    return ns.Wow
end

describe("WoW adapter contract", function()
    local W
    before_each(function()
        W = loadAdapter(minimalClient())
    end)

    it("provides every function the fake provides (the slices' whole API)", function()
        local fake = Fake.new()
        local optional = { CompressString = true, DecompressString = true }
        for name, v in pairs(fake) do
            if type(v) == "function" and not optional[name] then
                assert.is_function(W[name], "adapter lacks " .. name)
            end
        end
        assert.is_string(W.SPEC_CHANGED_EVENT)
    end)

    it("degrades when optional client APIs are missing", function()
        assert.is_nil(W.GetSpecialization())
        assert.equal("ACTIVE_TALENT_GROUP_CHANGED", W.SPEC_CHANGED_EVENT)
        assert.is_nil(W.GetGamePadDevice())
        assert.is_false(W.AtlasExists("Gamepad_Ltr_A_64"))
        assert.is_false(W.IsTyping())
        assert.is_nil(W.CompressString)
        assert.is_nil(W.GetBindingAction("PAD1"))
        assert.is_nil(W.GetCursorAction())
        assert.equal("Zorelo", W.CharacterKey())
        local caps = W.Capabilities()
        assert.is_false(caps.encoding)
        assert.equal(16001, caps.build)
        assert.has_no_error(function()
            W.ReportError("x")
        end)
    end)

    it("uses retail specializations when the client has them", function()
        local env = minimalClient()
        env.GetSpecialization = function()
            return 2
        end
        env.GetRealmName = function()
            return "Umbra"
        end
        W = loadAdapter(env)
        assert.equal(2, W.GetSpecialization())
        assert.equal("PLAYER_SPECIALIZATION_CHANGED", W.SPEC_CHANGED_EVENT)
        assert.equal("Zorelo-Umbra", W.CharacterKey())
    end)
end)
