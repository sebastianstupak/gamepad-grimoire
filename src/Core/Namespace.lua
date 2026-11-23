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

---Calls `method` on every module that defines it, in registration order.
---@param method "OnInitialize"|"OnEnable"
function ns.CallModules(method)
    for _, m in ipairs(order) do
        if m[method] then
            m[method](m)
        end
    end
end
