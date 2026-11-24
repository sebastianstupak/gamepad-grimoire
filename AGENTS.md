# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository.
Gamepad Grimoire is a World of Warcraft addon (Lua 5.1) with Node/Python dev tooling.
Read `docs/ARCHITECTURE.md` before changing code.

## Commands

```sh
npm install            # dev tools; installs git hooks unless a global core.hooksPath exists
npm run check          # everything CI runs: format, lint, types, tests + 90% coverage, pytest
npm run format         # StyLua (src, spec) + ruff format (tools)
npm test               # busted + pytest
npm run art            # rebuild controller textures, Definitions.lua, docs/images/controllers.png
npm run e2e            # real Steam Deck end-to-end run (dev rig only, see below)
```

Lua tools run in Docker (`tools/lua.mjs`, image `gamepad-grimoire-lua:2`). Docker must be
running, or set `GG_NATIVE_LUA=1` with Lua 5.1 + busted/luacheck/luacov/LuaLS installed.

## Architecture rules (enforced)

- **Vertical slices**: one folder per feature in `src/Features/<Name>/`, with its
  `*_spec.lua` next to the code. Keep changes inside one slice where possible.
- **Only `src/Core/Wow.lua` may touch WoW globals.** Everything else uses `ns.Wow.*`.
  luacheck fails otherwise. New WoW API -> add a wrapper in `Wow.lua`, the global to
  `.luacheckrc` (Wow.lua block), a fake in `spec/helpers/wow_fake.lua`.
- **Wrap optional APIs.** Clients differ (retail, Classic, WoW: Forever). Never assign a
  global that may be nil (`W.X = GetX` broke the addon on Forever: no `GetSpecialization`).
  `src/Core/Wow_spec.lua` runs the real adapter against a minimal client - keep it green.
- **New files must be listed in `GamepadGrimoire.toc`** in load order (tests load the toc).
- **Pure logic first**: decisions in pure functions, thin modules wire them to events.
- **Untrusted input** (share strings) is never executed and always validated.
- **Combat lockdown**: binding changes queue until `PLAYER_REGEN_ENABLED`.
- Saved data changes need a `Store.SCHEMA` bump and a migration.

## Conventions

- Conventional Commits, scope = slice or area:
  `core controllers bindings profiles share commands cheatsheet diagnostics editor setup options art deps ci repo release`.
  commitlint rejects anything else (commit-msg hook + CI).
- LuaLS annotations (`---@param`, `---@return`) on public functions; `npm run typecheck`
  must report no problems.
- Spec files start with `---@diagnostic disable: redundant-parameter` (luassert's
  message argument is missing from its LuaLS definitions).
- Generated files (`Definitions.lua`, `media/controllers/*.tga`, `docs/images/controllers.png`)
  come from `npm run art`; CI fails if `Definitions.lua` is stale. Never edit them by hand.

## Pitfalls seen in this repo

- **Backslashes in Lua strings**: WoW paths need `"Interface\\Icons\\X"`. A single `\I`
  is an invalid escape that StyLua silently strips to `"InterfaceIconsX"`. Generating Lua
  from Python heredocs has eaten backslashes several times - edit such lines directly
  and assert exact paths in specs.
- **Git hooks**: never run `lefthook install` by hand. On machines with a global
  `core.hooksPath` it overwrites the global hooks; `tools/install-hooks.mjs` guards this.
- **Fake widgets**: unknown fields on fake frames return method stubs - use `rawget`
  in specs when reading plain fields (`children`, `text`, `calls`, `scripts`).
- **WoW: Forever facts** (verified in game, 1.60.1 / interface 16001): no
  `GetSpecialization` (talent groups instead), `C_EncodingUtil` compression works,
  Blizzard gamepad glyph atlases exist, Steam Input reports the controller as
  "Generic" with ids 0000:0000 (no auto-detection - players choose the picture).
- **Back buttons through Proton** (verified on the Deck): the game *lists*
  PADPADDLE1-4 for a virtual Xbox Elite, but their presses arrive as face buttons
  (P1 = B). The Deck's own L4 L5 R4 R5 go to Steam Input (keys / Steam actions),
  never to the game as paddles. Do not claim a back button works from the list alone.
- Slash command errors leave the text in the chat box and Forever hides Lua errors;
  use `/console scriptErrors 1` when testing in game.

## Controller pictures from 3D models

`tools/art/render3d.py` (`npm run render`, needs Blender) renders each model in
`MODELS` as line art (`blender_lineart.py`: flat fill, Freestyle contour and
crease lines, orthographic, tilted so shoulders show) into `tools/art/renders/`.
Models are downloaded into `tools/art/models/` (git-ignored, often large); the
renders are committed and `npm run art` turns them into textures, so CI needs no
Blender. Anchors are hand-placed fractions of the render per button - draw them
over the render to check. Backs are the device turned over (R4 on the left).
Each picture keeps its model's licence: `render3d.write_credits()` updates
`media/controllers/CREDITS.md`, which ships with the addon. Only use models whose
licence allows derivatives (CC BY / BY-SA / CC0, or Valve's CC BY-NC-SA); skip
models tagged NoAI.

## End-to-end specs (in CI)

`spec/e2e/` plays the whole addon against the fake client the way a player would,
through `spec/helpers/player.lua`: `me:chat("/gg ...")`, `me:tap("PAD1")`,
`me:holding({ "PADLTRIGGER" }, fn)`, `me:key("ESCAPE")`, `me:click("Import")`,
`me:drag(cursor, "^A$")`, then `me:sees(pattern)`, `me:chatLines()` and
`me:actions()` (what the game ran from the bindings, e.g. `"spell Corruption"`).
Input goes where the client sends it: the frame that captures it, else the override
bindings (priority first), else the player's own keybinds. One suite each for chat
commands, controller-only use, and windows / mouse. A new command, setup screen or
button belongs in these suites as well as in a unit spec.

## End-to-end test (Steam Deck rig)

`tools/e2e/deck_e2e.py` drives a real Steam Deck over SSH: installs the packaged addon,
keeps the Deck awake, switches to Gaming Mode, starts WoW via Battle.net, runs `/gg`
commands, screenshots every controller card, drives the setup with a virtual gamepad
(uinput), runs every slash command once (`chat_scenario`), logs out and checks the
saved data.
It disables DeckSetup during the run and restores `AddOns.txt` afterwards (only while
WoW is closed - WoW rewrites that file on exit). Battle.net also reads controllers
and opens windows (friends chat, file browser) on pad input: the rig hides its
windows while the virtual pad runs, and `Deck.chat` / `Deck.key` refuse to type
unless the full-screen WoW window has focus. Keep it that way: typed text must never
reach a Battle.net chat. Use `--readme` to refresh
`docs/images/cheatsheet-*.png`. Always leave the game logged out.
