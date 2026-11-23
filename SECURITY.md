# Security policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub:
[Report a vulnerability](https://github.com/sebastianstupak/gamepad-grimoire/security/advisories/new).
Do not open a public issue. You should get an answer within a week.

Relevant for this addon in particular:

- **Share strings** (`!GG1!…`) are untrusted input. Import must never execute code
  (no `loadstring`), must stay bounded in size/depth, and must only ever add a profile.
  Anything that breaks one of these is a security bug.
- **Bindings / macros**: the addon must not create bindings or macros the player did
  not ask for.

## Supported versions

Only the latest release is supported.

## How the project is protected

- CI runs with read-only tokens; every third-party action is pinned to a commit SHA
  and kept current by Dependabot.
- `Security` workflow: zizmor (workflow audit), gitleaks (secrets), CodeQL (Python,
  JavaScript, workflows), dependency review on pull requests.
- OpenSSF Scorecard runs weekly.
- Secret scanning with push protection and Dependabot security updates are enabled.
