#!/usr/bin/env node
// Runs Lua tooling (luacheck, busted) inside the project's Docker image so it is
// identical on Windows, macOS, Linux and CI. Uses native binaries instead when
// GG_NATIVE_LUA=1 (e.g. in CI, where Lua is installed directly).
//
//   node tools/lua.mjs luacheck .
//   node tools/lua.mjs busted
//   node tools/lua.mjs --build        (re)build the image
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const IMAGE = "gamepad-grimoire-lua:1";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);

const run = (cmd, cmdArgs) => {
  const r = spawnSync(cmd, cmdArgs, { stdio: "inherit", cwd: root, shell: false });
  if (r.error) {
    console.error(r.error.message);
    process.exit(127);
  }
  return r.status ?? 1;
};

const build = () => run("docker", ["build", "-t", IMAGE, path.join(root, "tools", "docker")]);

if (args[0] === "--build") process.exit(build());
if (args.length === 0) {
  console.error("usage: node tools/lua.mjs <luacheck|busted> [args]");
  process.exit(2);
}

if (process.env.GG_NATIVE_LUA === "1") process.exit(run(args[0], args.slice(1)));

const hasImage = spawnSync("docker", ["image", "inspect", IMAGE], { stdio: "ignore" }).status === 0;
if (!hasImage && build() !== 0) process.exit(1);

// paths from git hooks are repo-relative; normalise Windows separators for the container
const toolArgs = args.map((a) => a.replaceAll("\\", "/"));
process.exit(run("docker", ["run", "--rm", "-v", `${root}:/src`, "-w", "/src", IMAGE, ...toolArgs]));
