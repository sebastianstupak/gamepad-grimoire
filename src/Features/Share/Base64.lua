-- Base64 (RFC 4648) in plain Lua 5.1 arithmetic, so it runs with or without the
-- client's bit library.
local _, ns = ...

local Base64 = {}
ns.Share = ns.Share or {}
ns.Share.Base64 = Base64

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local enc, dec = {}, {}
for i = 1, 64 do
    local ch = ALPHABET:sub(i, i)
    enc[i - 1] = ch
    dec[ch:byte()] = i - 1
end

local floor = math.floor

---@param s string
---@return string
function Base64.Encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = enc[floor(n / 262144) % 64]
        out[#out + 1] = enc[floor(n / 4096) % 64]
        out[#out + 1] = b and enc[floor(n / 64) % 64] or "="
        out[#out + 1] = c and enc[n % 64] or "="
    end
    return table.concat(out)
end

---@param s string
---@return string|nil decoded, string? err
function Base64.Decode(s)
    s = s:gsub("%s", "")
    if #s % 4 ~= 0 or s:find("[^%w%+/=]") or s:find("=[^=]") then
        return nil, "not valid base64"
    end
    local out = {}
    for i = 1, #s, 4 do
        local q = { s:byte(i, i + 3) }
        local n, pad = 0, 0
        for j = 1, 4 do
            local v = dec[q[j]]
            if v == nil then
                pad = pad + 1
                v = 0
            end
            n = n * 64 + v
        end
        local bytes = string.char(floor(n / 65536) % 256, floor(n / 256) % 256, n % 256)
        out[#out + 1] = bytes:sub(1, 3 - pad)
    end
    return table.concat(out)
end
