# Gamepad Grimoire

[![CI](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/ci.yml/badge.svg)](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/ci.yml)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsebastianstupak%2Fgamepad-grimoire%2Fbadges%2Fcoverage.json)](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/ci.yml)
[![Tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fsebastianstupak%2Fgamepad-grimoire%2Fbadges%2Ftests.json)](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/ci.yml)
[![Security](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/security.yml/badge.svg)](https://github.com/sebastianstupak/gamepad-grimoire/actions/workflows/security.yml)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/sebastianstupak/gamepad-grimoire/badge)](https://scorecard.dev/viewer/?uri=github.com/sebastianstupak/gamepad-grimoire)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Lua 5.1](https://img.shields.io/badge/Lua-5.1-2C2D72?logo=lua)
![WoW: Forever](https://img.shields.io/badge/WoW-Forever%201.60-c8a2ff)

A World of Warcraft addon for playing with a controller: bind spells, items and
macros to every button, see your binds on a picture of *your* controller, and
share setups with friends.

> Status: early development. Verified in game on WoW: Forever 1.60.1 (Steam Deck)
> by an automated end-to-end test. Not yet released on CurseForge or Wago.

- **Any controller.** Xbox Series, Xbox 360, DualSense, DualShock 4, Switch Pro,
  8BitDo Pro 2, Steam Controller, a generic gamepad, and the Steam Deck, ROG Ally,
  Legion Go and MSI Claw handhelds, in one consistent line-art style.
- **Never touches your keybinds.** Binds are applied as override bindings owned by
  the addon; disable it and your normal keybinds are back. Changes made in combat
  wait until combat ends.
- **Set up with the controller only.** Press LT+R3: move over the buttons with the
  D-pad (or just press the button you want), A picks a spell, macro, item or game
  action for it, X clears it, LB / RB switch layers, View shows the back of the
  controller, Y opens profiles and options, B closes. Profiles are named with an
  on-screen keyboard. No keyboard or chat needed.
- **Front and back.** Back views show the Steam Deck's L4 / L5 / R4 / R5, Xbox Elite
  paddles and DualSense Edge back buttons; the card turns around when you press one.
- **Live highlight.** Held buttons light up on the card, so you can check what is where.
- **Cheat sheet.** Hold LT or RT to peek at a layer; the card sizes itself to the screen.
- **Mouse editing too.** On the open card, drag a spell, item or macro onto a row;
  right-click clears.
- **Layers.** Hold LT or RT for a second and third set of binds.
- **Profiles.** Account-wide, per character and per specialization (switches
  automatically).
- **Share strings.** Export a profile as `!GG1!...` text, import one safely (nothing
  is ever executed; everything is validated).

## Screenshots

In-game screenshots from WoW: Forever on a Steam Deck, taken by the end-to-end test
(`npm run e2e -- --readme`). The profile is a real Affliction warlock setup captured
with `/gg capture`; the same binds are shown on every supported controller.

### Steam Deck: holding LT (L2) to peek at the second layer

![Gamepad Grimoire on a Steam Deck while holding L2](docs/images/cheatsheet-peek-lt.png)

### Controller setup: pick a button, then what it does

![Controller setup, choosing a button with the D-pad](docs/images/setup-rows.png)

![Controller setup, choosing a spell for L1](docs/images/setup-picker.png)

![Controller setup menu: profiles, controller picture, card size](docs/images/setup-menu.png)

### Steam Deck: pinned

![Gamepad Grimoire, Steam Deck](docs/images/cheatsheet-steamdeck.png)

### Xbox Series

![Gamepad Grimoire, Xbox Series controller](docs/images/cheatsheet-xbox.png)

### PlayStation DualSense

![Gamepad Grimoire, DualSense controller](docs/images/cheatsheet-dualsense.png)

### Nintendo Switch Pro

![Gamepad Grimoire, Switch Pro controller](docs/images/cheatsheet-switchpro.png)

## Slash commands

Everything can be done with the controller (LT+R3 opens the setup); these are
the keyboard fallback.

| Command | What it does |
| --- | --- |
| `/gg setup` | Controller setup (same as LT+R3) |
| `/gg show [lt\|rt]` | Pin or unpin the cheat sheet (or hold LT/RT to peek) |
| `/gg profile` | List profiles (`*` marks the active one) |
| `/gg profile use <name>` | Switch this character to a profile |
| `/gg profile new <name>` | New empty profile |
| `/gg profile copy <name>` | Copy the active profile |
| `/gg profile rename <old> = <new>` | Rename a profile |
| `/gg profile delete <name>` | Delete an unused profile |
| `/gg controller <id\|auto>` | Picture to show: `xbox`, `xbox360`, `dualsense`, `dualshock4`, `switchpro`, `8bitdo`, `steamcontroller`, `generic`, `steamdeck`, `rogally`, `legiongo`, `msiclaw` |
| `/gg capture <name>` | New profile from your current controller keybinds |
| `/gg export [profile]` | Share string of a profile (copy box) |
| `/gg import` | Paste a share string to add it as a new profile |
| `/gg scale <0.5-2.5\|auto>` | Cheat sheet size (automatic by default) |
| `/gg diag` | Check this client (for bug reports) |
| `/gg reload` | Re-apply bindings |

## Roadmap

Controller support (front view, then back view where the device has buttons there):

| Device | Front picture | Back / extra buttons |
| --- | --- | --- |
| Steam Deck (LCD, OLED) | Done | Done: L4, L5, R4, R5 |
| Xbox Series X/S, Xbox One | Done | Done (triggers and bumpers) |
| Xbox Elite Series 2 | Uses the Xbox picture | Done: paddles P1 to P4 |
| Xbox 360 | Done | Done (triggers and bumpers) |
| PlayStation DualSense | Done | |
| PlayStation DualSense Edge | Uses the DualSense picture | Done: the two back buttons |
| PlayStation DualShock 4 | Done | Done (triggers and bumpers) |
| Nintendo Switch Pro | Done | Done (triggers and bumpers) |
| Nintendo Switch 2 Pro | Planned | Planned: GL / GR back buttons |
| 8BitDo Pro 2 | Done | Done: back buttons P1, P2 |
| 8BitDo Ultimate | Planned | |
| Steam Controller | Done | Done: grip buttons LG, RG |
| ROG Ally / Ally X | Done | Done: M1, M2 |
| Lenovo Legion Go | Done | Done: M2, M3, Y1, Y2 |
| MSI Claw | Done | Done: M1, M2 |
| Generic gamepad | Done | Done (triggers and bumpers) |
| Joy-Cons, Switch 2 Pro, arcade sticks | Planned | |

Features:

- Controller-only text entry for naming profiles and pasting share strings (the
  on-screen keyboard of Steam / the OS works meanwhile).
- Blizzard's own button glyphs on the card (confirmed available on WoW: Forever).
- Settings in the game's Settings panel.
- Localization.
- Retail and Classic clients in addition to WoW: Forever.
- First release on CurseForge and Wago.

## Development

The addon is Lua 5.1, the dialect the game client runs.

| Area | Tooling |
| --- | --- |
| Format | [StyLua](https://github.com/JohnnyMorganz/StyLua), [ruff](https://docs.astral.sh/ruff/) (`npm run format`) |
| Lint | [luacheck](https://github.com/lunarmodules/luacheck), ruff (`npm run lint`) |
| Types | [lua-language-server](https://luals.github.io) `--check` with LuaLS annotations (`npm run typecheck`) |
| Tests | [busted](https://lunarmodules.github.io/busted/) unit and integration tests, pytest for tools (`npm test`) |
| Coverage | [luacov](https://lunarmodules.github.io/luacov/); CI fails under 90 % (`npm run coverage`) |
| End to end | Real Steam Deck over SSH: install, play, screenshot, verify saved data (`npm run e2e`) |
| Commits | [Conventional Commits](https://www.conventionalcommits.org), checked by commitlint |
| Hooks | [lefthook](https://github.com/evilmartians/lefthook): format and lint on commit, message check, full check on push |
| Security | zizmor, gitleaks, CodeQL, dependency review, OpenSSF Scorecard; actions pinned to SHAs |
| Art | `npm run art` (Pillow and resvg) |
| Release | Tag `vX.Y.Z`, packaged by the [BigWigs packager](https://github.com/BigWigsMods/packager) |

```sh
npm install          # dev tools and git hooks
npm run check        # format, lint, types, tests and coverage (also the pre-push hook)
```

Lua tools (busted, luacov, luacheck, LuaLS) run in a small Docker image (`tools/docker/`)
so they behave the same on every OS and in CI; set `GG_NATIVE_LUA=1` to use local installs.
Python tools: `pip install --require-hashes -r tools/requirements-ci.txt` (hash-locked).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[AGENTS.md](AGENTS.md) (guide for AI coding agents) and [SECURITY.md](SECURITY.md).

## License

MIT. Controller drawings are derived from AL2009man's Gamepad-Asset-Pack (MIT).
