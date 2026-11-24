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

## Tooling

The addon is Lua 5.1 (the dialect the game client runs). Lua tools run in a small
Docker image (`tools/docker/`) so they behave the same everywhere; set
`GG_NATIVE_LUA=1` to use local installs instead. Python tools install with
`pip install --require-hashes -r tools/requirements-ci.txt`.

| Area | `npm run …` |
| --- | --- |
| Format | `format` — StyLua + ruff format |
| Lint | `lint` — luacheck + ruff |
| Types | `typecheck` — lua-language-server `--check` |
| Tests | `test` — busted (unit/integration/e2e) + seeded share-string fuzzing + pytest |
| Coverage | `coverage` — luacov, fails under 90 % |
| Everything | `check` — all of the above (also the pre-push hook) |
| End to end | `e2e` — a real Steam Deck over SSH (see `tools/e2e/deck_e2e.py`) |
| Art | `art` — rebuild controller textures (Pillow, resvg) |

CI also runs zizmor, gitleaks, CodeQL, dependency review and OpenSSF Scorecard; all
GitHub Actions are pinned to commit SHAs.

## Controller art

Controllers are rendered from 3D (`tools/art/render3d.py`) or built parametrically
(`tools/art/model.py` + `params/*.json`); `python tools/art/build.py` turns the
committed renders into `media/controllers/*.tga` and
`src/Features/Controllers/Definitions.lua`. Commit those together — CI checks they match.

## Releasing

Releases are cut by pushing a tag; the
[BigWigs packager](https://github.com/BigWigsMods/packager) action
(`.github/workflows/release.yml`) zips the addon and publishes it:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

That always creates a GitHub release with the zip. To also upload to **CurseForge**:

1. Create the project on CurseForge and note its **Project ID**.
2. Add `## X-Curse-Project-ID: <id>` to `GamepadGrimoire.toc`.
3. Add a `CF_API_KEY` secret (from <https://legacy.curseforge.com/account/api-tokens>)
   to the repo's `release` environment.

Wago works the same way with `## X-Wago-ID:` and a `WAGO_API_TOKEN` secret.
