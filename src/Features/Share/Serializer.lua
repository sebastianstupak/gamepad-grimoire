-- Minimal, deterministic serializer for share strings. Never executes input
-- (no loadstring); the parser is bounded in depth and size.
--
--   number  n<text>;      string  s<len>:<bytes>      booleans  T / F
--   table   { <key><value> ... }   (keys sorted, so output is stable)
local _, ns = ...

local Serializer = {}
ns.Share = ns.Share or {}
ns.Share.Serializer = Serializer

Serializer.MAX_DEPTH = 16
Serializer.MAX_NODES = 20000

local function sortKeys(t)
    local keys = {}
    for k in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta < tb
        end
        return a < b
    end)
    return keys
end

local function write(v, out, depth)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            error("cannot serialize nan/inf")
        end
        out[#out + 1] = "n" .. string.format("%.17g", v) .. ";"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "table" then
        if depth >= Serializer.MAX_DEPTH then
            error("table nested too deeply")
        end
        out[#out + 1] = "{"
        for _, k in ipairs(sortKeys(v)) do
            local kt = type(k)
            if kt ~= "string" and kt ~= "number" then
                error("unsupported key type " .. kt)
            end
            write(k, out, depth + 1)
            write(v[k], out, depth + 1)
        end
        out[#out + 1] = "}"
    else
        error("cannot serialize a " .. t)
    end
end

---@param value any
---@return string
function Serializer.Serialize(value)
    local out = {}
    write(value, out, 0)
    return table.concat(out)
end

---@param s string
---@return boolean ok, any valueOrError
function Serializer.Deserialize(s)
    if type(s) ~= "string" then
        return false, "not a string"
    end
    local pos, nodes = 1, 0

    local read
    read = function(depth)
        nodes = nodes + 1
        if nodes > Serializer.MAX_NODES then
            error("too many values")
        end
        local c = s:sub(pos, pos)
        if c == "n" then
            local stop = s:find(";", pos + 1, true)
            if not stop then
                error("bad number")
            end
            local n = tonumber(s:sub(pos + 1, stop - 1))
            if not n or n ~= n or n == math.huge or n == -math.huge then
                error("bad number")
            end
            pos = stop + 1
            return n
        elseif c == "s" then
            local colon = s:find(":", pos + 1, true)
            local len = colon and tonumber(s:sub(pos + 1, colon - 1))
            if not len or len < 0 or len % 1 ~= 0 or colon + len > #s then
                error("bad string")
            end
            local v = s:sub(colon + 1, colon + len)
            pos = colon + len + 1
            return v
        elseif c == "T" or c == "F" then
            pos = pos + 1
            return c == "T"
        elseif c == "{" then
            if depth >= Serializer.MAX_DEPTH then
                error("nested too deeply")
            end
            pos = pos + 1
            local t = {}
            while s:sub(pos, pos) ~= "}" do
                if pos > #s then
                    error("unterminated table")
                end
                local k = read(depth + 1)
                if type(k) ~= "string" and type(k) ~= "number" then
                    error("bad key")
                end
                t[k] = read(depth + 1)
            end
            pos = pos + 1
            return t
        end
        error("unexpected '" .. c .. "' at " .. pos)
    end

    local ok, v = pcall(read, 0)
    if not ok then
        return false, (tostring(v):gsub("^.-:%d+: ", ""))
    end
    if pos ~= #s + 1 then
        return false, "trailing data"
    end
    return true, v
end
