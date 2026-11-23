-- Share strings: export a profile as text, import it back safely.
--
--   !GG1!<base64>    plain
--   !GG1Z!<base64>   compressed with the client's C_EncodingUtil (when available)
--
-- Import never runs code, caps the size, validates the structure and the whole
-- binding layout, and only ever *adds* a profile (never overwrites).
local _, ns = ...

local Codec = {}
ns.Share = ns.Share or {}
ns.Share.Codec = Codec

Codec.VERSION = 1
Codec.MAX_LENGTH = 200000

local PLAIN, PACKED = "!GG1!", "!GG1Z!"

---@param name string
---@param profile table
---@return string
function Codec.Export(name, profile)
    local S = ns.Share
    local payload = S.Serializer.Serialize({ kind = "profile", v = Codec.VERSION, name = name, profile = profile })
    local compress = ns.Wow.CompressString
    if compress then
        local ok, packed = pcall(compress, payload)
        if ok and type(packed) == "string" and #packed < #payload then
            return PACKED .. S.Base64.Encode(packed)
        end
    end
    return PLAIN .. S.Base64.Encode(payload)
end

---@param text any
---@return boolean ok, table|string envelopeOrError { name, profile }
function Codec.Import(text)
    local S = ns.Share
    if type(text) ~= "string" then
        return false, "nothing to import"
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > Codec.MAX_LENGTH then
        return false, "text is too long"
    end
    local body, packed
    if text:sub(1, #PACKED) == PACKED then
        body, packed = text:sub(#PACKED + 1), true
    elseif text:sub(1, #PLAIN) == PLAIN then
        body = text:sub(#PLAIN + 1)
    else
        return false, "not a Gamepad Grimoire string"
    end
    local raw, err = S.Base64.Decode(body)
    if not raw then
        return false, err
    end
    if packed then
        local decompress = ns.Wow.DecompressString
        if not decompress then
            return false, "this game version cannot read compressed strings"
        end
        local ok, out = pcall(decompress, raw)
        if not ok or type(out) ~= "string" then
            return false, "could not decompress"
        end
        raw = out
    end
    local ok, env = S.Serializer.Deserialize(raw)
    if not ok then
        return false, "damaged string (" .. tostring(env) .. ")"
    end
    if type(env) ~= "table" or env.kind ~= "profile" then
        return false, "not a profile"
    end
    if type(env.v) ~= "number" or env.v > Codec.VERSION then
        return false, "made by a newer Gamepad Grimoire - update the addon"
    end
    local p = env.profile
    if type(p) ~= "table" or type(p.controller) ~= "string" then
        return false, "profile is missing its controller"
    end
    local valid, errors = ns.Bindings.Model.Validate(p)
    if not valid then
        return false, "invalid bindings: " .. table.concat(errors, "; ", 1, math.min(#errors, 3))
    end
    local nameOk = ns.Profiles.ValidName(env.name)
    return true, { name = nameOk and env.name or "Imported", profile = p }
end
