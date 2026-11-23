-- luassert accepts a failure message as the last argument; its LuaLS definitions do not.
---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

describe("Share", function()
    describe("Serializer", function()
        local S
        before_each(function()
            S = Addon.load({ upTo = "Share/Serializer.lua" }).Share.Serializer
        end)

        it("round-trips nested tables, strings with any bytes, numbers and booleans", function()
            local v = { a = { 1, 2.5, -3 }, s = "x:y}{;\0\255", t = true, f = false, [10] = "ten" }
            local ok, back = S.Deserialize(S.Serialize(v))
            assert.is_true(ok)
            assert.same(v, back)
        end)

        it("is deterministic (sorted keys)", function()
            assert.equal(S.Serialize({ b = 1, a = 2 }), S.Serialize({ a = 2, b = 1 }))
        end)

        it("rejects functions, nan and over-deep nesting when writing", function()
            assert.has_error(function()
                S.Serialize({ f = print })
            end)
            assert.has_error(function()
                S.Serialize(0 / 0)
            end)
            local deep = {}
            local t = deep
            for _ = 1, 40 do
                t.x = {}
                t = t.x
            end
            assert.has_error(function()
                S.Serialize(deep)
            end)
        end)

        it("fails cleanly on damaged or hostile input", function()
            for _, bad in ipairs({ "", "{", "s99:abc", "nfoo;", "X", "{n1;}", "TT", string.rep("{", 100) }) do
                local ok = S.Deserialize(bad)
                assert.is_false(ok, bad)
            end
        end)
    end)

    describe("Base64", function()
        local B
        before_each(function()
            B = Addon.load({ upTo = "Share/Base64.lua" }).Share.Base64
        end)

        it("matches RFC 4648 test vectors", function()
            local vectors = { [""] = "", f = "Zg==", fo = "Zm8=", foo = "Zm9v", foob = "Zm9vYg==", fooba = "Zm9vYmE=" }
            for plain, encoded in pairs(vectors) do
                assert.equal(encoded, B.Encode(plain))
                assert.equal(plain, B.Decode(encoded))
            end
        end)

        it("round-trips all byte values", function()
            local bytes = {}
            for i = 0, 255 do
                bytes[#bytes + 1] = string.char(i)
            end
            local s = table.concat(bytes)
            assert.equal(s, B.Decode(B.Encode(s)))
        end)

        it("rejects invalid text", function()
            assert.is_nil(B.Decode("abc"))
            assert.is_nil(B.Decode("ab$="))
            assert.is_nil(B.Decode("a=bc"))
        end)
    end)

    describe("Codec", function()
        local ns, Codec
        local function profile()
            return {
                controller = "dualsense",
                layers = { BASE = { PAD1 = { type = "command", command = "JUMP" } }, LT = {}, RT = {} },
            }
        end
        before_each(function()
            ns = Addon.start(nil)
            Codec = ns.Share.Codec
        end)

        it("exports and imports a profile", function()
            local text = Codec.Export("Affliction", profile())
            assert.truthy(text:match("^!GG1!"))
            local ok, env = Codec.Import("  " .. text .. "\n")
            assert.is_true(ok)
            assert.equal("Affliction", env.name)
            assert.same(profile(), env.profile)
        end)

        it("uses the client's compression when available", function()
            ns.Wow.CompressString = function(s)
                return (s:gsub("JUMP", "\1"))
            end
            ns.Wow.DecompressString = function(s)
                return (s:gsub("\1", "JUMP"))
            end
            local text = Codec.Export("x", profile())
            assert.truthy(text:match("^!GG1Z!"))
            local ok, env = Codec.Import(text)
            assert.is_true(ok)
            assert.same(profile(), env.profile)
        end)

        it("rejects foreign, damaged, newer and invalid strings with a reason", function()
            local S = ns.Share
            local function wrap(env)
                return "!GG1!" .. S.Base64.Encode(S.Serializer.Serialize(env))
            end
            local cases = {
                "!WA:2!abc",
                "!GG1!not base64!",
                "!GG1!" .. S.Base64.Encode("{"),
                wrap({ kind = "profile", v = 99, name = "x", profile = profile() }),
                wrap({ kind = "aura", v = 1 }),
                wrap({
                    kind = "profile",
                    v = 1,
                    name = "x",
                    profile = { controller = "xbox", layers = { BASE = { PAD1 = { type = "lua", code = "x" } } } },
                }),
                string.rep("A", Codec.MAX_LENGTH + 1),
            }
            for _, text in ipairs(cases) do
                local ok, err = Codec.Import(text)
                assert.is_false(ok)
                assert.is_string(err)
            end
        end)

        it("replaces unusable profile names", function()
            local S = ns.Share
            local text = "!GG1!"
                .. S.Base64.Encode(S.Serializer.Serialize({ kind = "profile", v = 1, name = "", profile = profile() }))
            local ok, env = Codec.Import(text)
            assert.is_true(ok)
            assert.equal("Imported", env.name)
        end)
    end)
end)

describe("Share dialog", function()
    local ns, wow, D
    before_each(function()
        ns, wow = Addon.start(nil)
        D = ns.Share.Dialog
    end)

    it("picks the first free profile name", function()
        local taken = { A = true, ["A (2)"] = true }
        local exists = function(n)
            return taken[n] == true
        end
        assert.equal("B", D.UniqueName("B", exists))
        assert.equal("A (3)", D.UniqueName("A", exists))
    end)

    it("exports the active profile into a selected text box", function()
        wow.slash.handler("export")
        local f = D.Frame()
        assert.is_true(f:IsShown())
        assert.truthy(f.box:GetText():match("^!GG1!"))
        assert.is_table(rawget(f.box, "calls").HighlightText)
        assert.same({ "GamepadGrimoireShareDialog" }, wow.escClose)
    end)

    it("imports a pasted string as a new profile without overwriting", function()
        local text = ns.Share.Codec.Export("Default", ns.Profiles.Get("Default"))
        wow.slash.handler("import")
        local f = D.Frame()
        f.box:SetText(text)
        rawget(f.import, "scripts").OnClick(f.import)
        assert.is_table(ns.Profiles.Get("Default (2)"))
        assert.truthy(rawget(f.status, "text"):find("imported profile Default %(2%)"))
    end)

    it("explains why a string cannot be imported", function()
        wow.slash.handler("import")
        local f = D.Frame()
        f.box:SetText("hello")
        rawget(f.import, "scripts").OnClick(f.import)
        assert.truthy(rawget(f.status, "text"):find("not a Gamepad Grimoire string"))
        assert.same({ "Default" }, ns.Profiles.List())
    end)
end)
