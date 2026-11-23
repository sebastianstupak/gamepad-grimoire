-- /gg diag: checks the client features the addon relies on and runs a share-string
-- round trip. The report is printed and kept in saved data (db.diag), which the
-- end-to-end test reads back after logging out.
local _, ns = ...

local Diagnostics = {}
ns.Diagnostics = Diagnostics

-- Blizzard gamepad glyph atlases (one per label style) - used once confirmed
Diagnostics.ATLASES = { "Gamepad_Ltr_A_64", "Gamepad_Shp_Cross_64", "Gamepad_Gen_1_64", "Gamepad_Rev_B_64" }

local function compressionWorks()
    local c, d = ns.Wow.CompressString, ns.Wow.DecompressString
    if not (c and d) then
        return false
    end
    local sample = string.rep("Gamepad Grimoire ", 40)
    local ok, packed = pcall(c, sample)
    if not ok or type(packed) ~= "string" then
        return false
    end
    local ok2, back = pcall(d, packed)
    return ok2 and back == sample
end

---@return table report
function Diagnostics.Run()
    local S = ns.Share
    local profileName = ns.Profiles.ActiveName()
    local profile = ns.Profiles.ActiveProfile()
    local text = S.Codec.Export(profileName, profile)
    local ok, env = S.Codec.Import(text)
    local same = ok and S.Serializer.Serialize(env.profile) == S.Serializer.Serialize(profile)

    local atlases = {}
    for _, a in ipairs(Diagnostics.ATLASES) do
        atlases[a] = ns.Wow.AtlasExists(a)
    end
    local bound = 0
    for _, layer in pairs(profile.layers or {}) do
        for _ in pairs(layer) do
            bound = bound + 1
        end
    end
    local controller, reason = ns.Controllers.Detect.Resolve(profile.controller)
    local applied = ns.Bindings.Applier.last

    local report = {
        caps = ns.Wow.Capabilities(),
        compression = compressionWorks(),
        share = { ok = ok and same or false, length = #text, compressed = text:sub(1, 6) == "!GG1Z!" },
        device = ns.Wow.GetGamePadDevice() or false,
        controller = controller,
        controllerReason = reason,
        atlases = atlases,
        buttons = ns.Wow.KnownButtons(),
        profile = profileName,
        bound = bound,
        applied = applied and applied.applied or 0,
        skipped = applied and #applied.skipped or 0,
    }
    ns.db.diag = report
    return report
end

---@param r table report from Run
---@return string[] lines
function Diagnostics.Format(r)
    local function yes(v)
        return v and "|cff5fd35fyes|r" or "|cffff5f5fno|r"
    end
    local atl = {}
    for _, a in ipairs(Diagnostics.ATLASES) do
        atl[#atl + 1] = a:gsub("^Gamepad_", ""):gsub("_64$", "") .. " " .. yes(r.atlases[a])
    end
    local dev = r.device
    return {
        ("client %s (%s)  C_GamePad %s  GamePadEnable=%s"):format(
            tostring(r.caps.version),
            tostring(r.caps.build),
            yes(r.caps.gamepadApi),
            tostring(r.caps.gamepadEnabled)
        ),
        ("compression %s  share round trip %s (%d chars%s)"):format(
            yes(r.compression),
            yes(r.share.ok),
            r.share.length,
            r.share.compressed and ", compressed" or ""
        ),
        ("device %s  ->  %s (%s)"):format(
            dev
                    and ("%s %04X:%04X %s"):format(
                        tostring(dev.name),
                        dev.vendorID or 0,
                        dev.productID or 0,
                        tostring(dev.labelStyle)
                    )
                or "none",
            r.controller,
            r.controllerReason
        ),
        "glyph atlases: " .. table.concat(atl, ", "),
        "buttons the game sees: " .. (#(r.buttons or {}) > 0 and table.concat(r.buttons, " ") or "none"),
        ("profile %s: %d binds, %d applied, %d skipped"):format(r.profile, r.bound, r.applied, r.skipped),
    }
end
