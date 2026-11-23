# Architecture

Gamepad Grimoire is organised in **vertical slices**: one folder per feature under
`src/Features/`, holding that feature's logic, its game wiring and its tests.
Adding or changing a feature should touch one folder.

```
GamepadGrimoire.toc          load order (the client reads this)
src/
  Core/                      shared kernel - kept deliberately small
    Namespace.lua            ns, module registry (NewModule / CallModules)
    Wow.lua                  THE adapter to WoW's global API
    Events.lua               internal message bus + game event routing
    Store.lua                saved data, defaults, schema migrations
  Features/
    Controllers/             which controller, its picture and button anchors
      Registry.lua  Detect.lua  Definitions.lua (generated)  Controllers_spec.lua
    Bindings/                layouts -> override bindings (combat-safe)
      Model.lua  Applier.lua  Bindings.lua  Bindings_spec.lua
    Profiles/                account / character / spec profiles
    Share/                   export / import strings
    CheatSheet/              the card: Layout (pure geometry), Glyphs, View, peek/pin
    Editor/                  drag & drop / right-click editing on the pinned card
    Setup/                   controller-only setup: Navigator (pure state machine), Catalog, Panel
    Options/                 page in the game's Settings > AddOns
    Diagnostics/             /gg diag client checks, kept for the e2e test
    Commands/                /gg, /grimoire
  Bootstrap.lua              loaded last: saved data, then module start
spec/helpers/                fake WoW API + loader used by every slice's tests
tools/art/                   SVG sources -> textures + Definitions.lua
media/controllers/           generated textures
```

## Rules

1. **Only `src/Core/Wow.lua` touches WoW globals.** Everything else calls `ns.Wow.*`.
   luacheck enforces it: no other file is given WoW's globals.
2. **Pure logic first.** Each slice keeps its decisions in pure functions
   (`Bindings/Model.lua`, `Share/Serializer.lua`, `Controllers/Detect.lua`...) and a
   thin module that wires them to events. Pure parts are tested directly; wiring is
   tested by starting the whole addon against the fake client.
3. **Slices talk through public functions and messages, never each other's state.**
   Messages: `PROFILE_CHANGED`, `BINDINGS_APPLIED`.
4. **Untrusted input is validated, never executed.** Imports go through
   `Share/Serializer` (bounded parser, no `loadstring`) and `Bindings.Model.Validate`.
5. **Combat lockdown is handled at the edge.** Anything that may not run in combat
   (bindings now; frames and macros later) queues until `PLAYER_REGEN_ENABLED`.
6. **Saved data is versioned.** `Store.SCHEMA` + a migration per version; data from a
   newer version is kept read-only instead of being downgraded.

## Tests

`busted` discovers `*_spec.lua` next to the code. `spec/helpers/addon.lua` loads the
addon exactly like the client (each file receives `addonName, ns`, in `.toc` order)
with `spec/helpers/wow_fake.lua` as `ns.Wow`. `Addon.start(saved)` also fires
`ADDON_LOADED` and `PLAYER_LOGIN`, so tests can drive the addon end to end.

## Planned slices

- **Settings** – options in the game's Settings panel (scale, pin key, controller).
- **Gamepad navigation** for the editor (pick a row with the D-pad, assign from a list).
