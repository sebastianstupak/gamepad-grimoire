-- luacheck config. The architecture rule lives here too: only the WoW adapter
-- (src/Core/Wow.lua) may touch WoW's global API; every other file talks to the
-- game through ns.Wow, which keeps the slices testable outside the client.
std = "lua51"
max_line_length = false -- StyLua owns formatting
codes = true
exclude_files = { "node_modules/", ".luarocks/", "tools/" }
ignore = {
  "212/self", -- unused self in methods
}

files["src/Core/Wow.lua"] = {
  read_globals = {
    "C_CVar", "C_EncodingUtil", "C_GamePad", "C_Spell", "ClearOverrideBindings", "CreateFrame",
    "DEFAULT_CHAT_FRAME", "GetCVar", "GetRealmName", "GetSpecialization", "GetSpellInfo",
    "InCombatLockdown", "SetOverrideBinding", "SetOverrideBindingItem", "SetOverrideBindingMacro",
    "SetOverrideBindingSpell", "UnitName",
    "C_Item", "C_Texture", "C_Timer", "GetActionInfo", "GetActionTexture", "GetBindingAction", "GetBuildInfo",
    "GetCurrentKeyBoardFocus", "GetMacroInfo", "GetPetActionInfo", "HasAction", "IsControlKeyDown",
    "IsShiftKeyDown", "UIParent", "UISpecialFrames",
  },
  globals = { "SlashCmdList" },
  -- slash command registration writes SLASH_<NAME><n> globals by design
  allow_defined_top = true,
  ignore = { "111", "112", "113" },
}

files["src/Bootstrap.lua"] = { globals = { "GamepadGrimoireDB" } }

files["spec/"] = { std = "+busted" }
files["src/**/*_spec.lua"] = { std = "+busted" }
