#!/usr/bin/env node
// `npm install` -> installs the lefthook git hooks, unless git is configured with a
// global/system core.hooksPath. Such setups manage hooks themselves (and usually
// dispatch to the repo's lefthook.yml); lefthook must never write into them.
import { spawnSync } from "node:child_process";

const git = spawnSync("git", ["config", "--get", "core.hooksPath"], { encoding: "utf8" });
const hooksPath = git.status === 0 ? git.stdout.trim() : "";
if (hooksPath) {
  console.log(`git core.hooksPath is set (${hooksPath}); leaving hooks to it - lefthook.yml is used from there.`);
  process.exit(0);
}
const r = spawnSync("npx", ["lefthook", "install"], { stdio: "inherit", shell: process.platform === "win32" });
process.exit(r.status ?? 1);
