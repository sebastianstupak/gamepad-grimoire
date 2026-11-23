-- Addon namespace and module registry.
-- Every feature slice registers one module; Bootstrap initialises them in load order.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.version = "@project-version@"

---@class GGModule
---@field name string
---@field OnInitialize? fun(self: GGModule)
---@field OnEnable? fun(self: GGModule)

local modules, order = {}, {}

---Registers a new module (one per feature slice).
---@param name string
---@return GGModule
function ns.NewModule(name)
    assert(type(name) == "string" and name ~= "", "module name required")
    assert(not modules[name], "module already registered: " .. name)
    local m = { name = name }
    modules[name] = m
    order[#order + 1] = m
    return m
end

---@param name string
---@return GGModule
function ns.GetModule(name)
    return assert(modules[name], "unknown module: " .. tostring(name))
end

---Calls `method` on every module that defines it, in registration order. A module
---that fails is reported (through ns.Wow.ReportError) and the others still start.
---@param method "OnInitialize"|"OnEnable"
---@return string[] failed names of modules whose method raised an error
function ns.CallModules(method)
    local failed = {}
    for _, m in ipairs(order) do
        if m[method] then
            local ok, err = pcall(m[method], m)
            if not ok then
                failed[#failed + 1] = m.name
                local report = ns.Wow and ns.Wow.ReportError or print
                report(("%s %s: %s"):format(m.name, method, tostring(err)))
            end
        end
    end
    return failed
end
