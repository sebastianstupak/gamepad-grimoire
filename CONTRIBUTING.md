# Contributing

1. `npm install` – installs StyLua, commitlint and the lefthook git hooks.
2. Docker must be running (lint and tests run in `tools/docker`), or set
   `GG_NATIVE_LUA=1` with `luacheck` and `busted` installed for Lua 5.1.
3. Work inside one slice (`src/Features/<Name>/`) and add or update its `*_spec.lua`.
4. `npm run check` before pushing (the pre-push hook runs it too): StyLua + ruff format,
   luacheck + ruff, LuaLS type check, busted with a 90 % coverage gate, pytest.
5. Gameplay changes: run `npm run e2e` on a Steam Deck rig (see tools/e2e/deck_e2e.py).

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org), scope = slice or area:

```
feat(bindings): queue changes made during combat
fix(share): reject strings with trailing data
docs(repo): explain the Wow adapter rule
```

Allowed scopes: `core controllers bindings profiles share commands cheatsheet diagnostics editor
setup options art deps ci repo release`.

## Controller art

Edit `tools/art/restyle.py` (style, per-controller config) and run
`python tools/art/build.py`. Commit the regenerated `media/controllers/*.tga` and
`src/Features/Controllers/Definitions.lua` together; CI checks they match.
