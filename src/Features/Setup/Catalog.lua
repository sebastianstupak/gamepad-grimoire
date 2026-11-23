-- What can be bound, grouped for the controller picker. Pure: built from plain
-- lists that Setup.lua gets from the WoW adapter.
local _, ns = ...

local Catalog = {}
ns.Setup = ns.Setup or {}
ns.Setup.Catalog = Catalog

-- Everyday game actions a controller player needs (binding command names).
Catalog.ACTIONS = {
    "JUMP",
    "INTERACTTARGET",
    "TARGETNEARESTENEMY",
    "TARGETPREVIOUSENEMY",
    "TARGETNEARESTFRIEND",
    "TARGETLASTHOSTILE",
    "TARGETSELF",
    "ASSISTTARGET",
    "TOGGLEAUTORUN",
    "SITORSTAND",
    "TOGGLESHEATH",
    "PETATTACK",
    "OPENALLBAGS",
    "TOGGLEWORLDMAP",
    "TOGGLEQUESTLOG",
    "TOGGLECHARACTER0",
    "TOGGLESPELLBOOK",
    "TOGGLETALENTS",
    "TOGGLESOCIAL",
    "TOGGLEGAMEMENU",
}

---@param lists { spells: table[], macros: table[], items: table[] }
---@param bindingName fun(command: string): string
---@return { name: string, items: { name: string, icon: any, action: table }[] }[]
function Catalog.Build(lists, bindingName)
    local cats = {}
    local function add(name, entries, toAction)
        local items = {}
        for _, e in ipairs(entries or {}) do
            items[#items + 1] = { name = e.name, icon = e.icon, action = toAction(e) }
        end
        if #items > 0 then
            cats[#cats + 1] = { name = name, items = items }
        end
    end
    add("Spells", lists.spells, function(e)
        return { type = "spell", id = e.id }
    end)
    add("Macros", lists.macros, function(e)
        return { type = "macro", name = e.name }
    end)
    add("Items", lists.items, function(e)
        return { type = "item", id = e.id }
    end)
    local actions = {}
    for _, cmd in ipairs(Catalog.ACTIONS) do
        actions[#actions + 1] = { name = bindingName(cmd), command = cmd }
    end
    add("Game actions", actions, function(e)
        return { type = "command", command = e.command }
    end)
    return cats
end
