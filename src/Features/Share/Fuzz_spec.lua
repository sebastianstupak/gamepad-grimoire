-- Share strings come from other players: the parser must never throw, and
-- anything it accepts must be a valid layout. Seeded, so failures reproduce.
---@diagnostic disable: redundant-parameter
local Addon = require("spec.helpers.addon")

-- small LCG: same sequence on every platform (math.random is libc-dependent)
local function rng(seed)
    local x = seed
    return function(n)
        x = (x * 1103515245 + 12345) % 2147483648
        return x % n + 1
    end
end

local function randomBytes(r, len)
    local t = {}
    for i = 1, len do
        t[i] = string.char(r(256) - 1)
    end
    return table.concat(t)
end

-- one random edit: replace, insert or delete a byte, or cut the string short
local function mutate(r, s)
    local i = r(#s + 1)
    local op = r(4)
    if op == 1 then
        return s:sub(1, i - 1) .. string.char(r(256) - 1) .. s:sub(i + 1)
    elseif op == 2 then
        return s:sub(1, i - 1) .. string.char(r(256) - 1) .. s:sub(i)
    elseif op == 3 then
        return s:sub(1, i - 1) .. s:sub(i + 1)
    end
    return s:sub(1, i)
end

local function profile()
    return {
        controller = "steamdeck",
        layers = {
            BASE = { PAD1 = { type = "command", command = "JUMP" }, PADPADDLE1 = { type = "spell", id = 172 } },
            LT = { PAD2 = { type = "macro", name = "Pet Attack" } },
            RT = { PAD3 = { type = "item", id = 5512 } },
        },
    }
end

describe("Share (hostile input)", function()
    local ns, S
    before_each(function()
        ns = Addon.start(nil)
        S = ns.Share
    end)

    -- calls fn and fails the test if it throws instead of returning
    local function noThrow(label, fn, ...)
        local results = { pcall(fn, ...) }
        assert(results[1], label .. " threw: " .. tostring(results[2]))
        return unpack(results, 2)
    end

    describe("Serializer.Deserialize", function()
        it("never throws on random bytes", function()
            local r = rng(1)
            for n = 1, 2000 do
                local ok, v = noThrow("bytes #" .. n, S.Serializer.Deserialize, randomBytes(r, r(64) - 1))
                assert.is_boolean(ok)
                if not ok then
                    assert.is_string(v)
                end
            end
        end)

        it("never throws on mutated valid data, and keeps keys to strings and numbers", function()
            local r = rng(2)
            local good = S.Serializer.Serialize(profile())
            for n = 1, 3000 do
                local s = good
                for _ = 1, r(4) do
                    s = mutate(r, s)
                end
                local ok, v = noThrow("mutation #" .. n, S.Serializer.Deserialize, s)
                if ok and type(v) == "table" then
                    for k in pairs(v) do
                        assert.is_true(type(k) == "string" or type(k) == "number")
                    end
                end
            end
        end)

        it("names what is wrong", function()
            local cases = {
                { nil, "not a string" },
                { "n12", "bad number" },
                { "ninf;", "bad number" },
                { "n1e999;", "bad number" },
                { "s-1:", "bad string" },
                { "s1.5:ab", "bad string" },
                { "{TT}", "bad key" },
                { "{", "unterminated table" },
                { "{s1:a", "unexpected end of data" },
                { "", "unexpected end of data" },
                { "TT", "trailing data" },
                { "?", "unexpected '?' at 1" },
            }
            for _, c in ipairs(cases) do
                local ok, err = S.Serializer.Deserialize(c[1])
                assert.is_false(ok)
                assert.are.equal(c[2], err)
            end
        end)

        it("caps depth and the number of values", function()
            local ok, err = S.Serializer.Deserialize(string.rep("{", S.Serializer.MAX_DEPTH + 1))
            assert.is_false(ok)
            assert.are.equal("nested too deeply", err)
            ok, err = S.Serializer.Deserialize("{" .. string.rep("n1;T", S.Serializer.MAX_NODES / 2 + 1) .. "}")
            assert.is_false(ok)
            assert.are.equal("too many values", err)
        end)
    end)

    describe("Base64.Decode", function()
        it("never throws and returns a string or nil", function()
            local r = rng(3)
            local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=$ \n"
            for n = 1, 2000 do
                local t = {}
                for i = 1, r(40) - 1 do
                    local c = r(#alphabet)
                    t[i] = alphabet:sub(c, c)
                end
                local out = noThrow("base64 #" .. n, S.Base64.Decode, table.concat(t))
                assert.is_true(out == nil or type(out) == "string")
            end
        end)
    end)

    describe("Codec.Import", function()
        it("never throws on damaged strings, and whatever it accepts is a valid layout", function()
            local r = rng(4)
            local good = S.Codec.Export("Deck", profile())
            local accepted = 0
            for n = 1, 3000 do
                local text = good
                for _ = 1, r(3) do
                    text = mutate(r, text)
                end
                local ok, result = noThrow("import #" .. n, S.Codec.Import, text)
                local env = result --[[@as table]]
                if ok then
                    accepted = accepted + 1
                    assert.is_true((ns.Bindings.Model.Validate(env.profile)))
                    assert.is_string(env.profile.controller)
                    assert.is_true((ns.Profiles.ValidName(env.name)))
                else
                    assert.is_string(env)
                end
            end
            -- some edits are harmless (e.g. trailing whitespace), most are not
            assert.is_true(accepted < 3000)
        end)

        it("rejects input that is not text", function()
            for _, v in ipairs({ 42, true, {} }) do
                local ok, err = S.Codec.Import(v)
                assert.is_false(ok)
                assert.are.equal("nothing to import", err)
            end
        end)

        it("explains compressed strings it cannot read", function()
            local packed = "!GG1Z!" .. S.Base64.Encode("whatever")
            local function decompressWith(f)
                ns.Wow.DecompressString = f
            end
            decompressWith(nil)
            local ok, err = S.Codec.Import(packed)
            assert.is_false(ok)
            assert.matches("cannot read compressed", err)
            decompressWith(function()
                error("corrupt stream")
            end)
            ok, err = S.Codec.Import(packed)
            assert.is_false(ok)
            assert.are.equal("could not decompress", err)
            decompressWith(function()
                return nil
            end)
            ok, err = S.Codec.Import(packed)
            assert.is_false(ok)
            assert.are.equal("could not decompress", err)
        end)

        it("needs a controller in the profile", function()
            local env = { kind = "profile", v = 1, name = "x", profile = { layers = {} } }
            local ok, err = S.Codec.Import("!GG1!" .. S.Base64.Encode(S.Serializer.Serialize(env)))
            assert.is_false(ok)
            assert.are.equal("profile is missing its controller", err)
        end)

        it("keeps an imported profile with an unknown controller usable", function()
            local p = profile()
            p.controller = "toaster"
            local ok, env = S.Codec.Import(S.Codec.Export("Odd", p))
            assert.is_true(ok)
            assert.is_true((ns.Profiles.Add(env.name, env.profile)))
            assert.is_true((ns.Profiles.Use("Odd")))
            ns.CheatSheet.Toggle()
            assert.is_true((ns.CheatSheet.State()))
            assert.is_table(ns.CheatSheet.Card())
        end)
    end)
end)
