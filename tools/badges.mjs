#!/usr/bin/env node
// Writes shields.io endpoint badges from the last test run:
//   badges/coverage.json  from luacov.report.out
//   badges/tests.json     from busted.out ("N successes / F failures / E errors ...")
// CI publishes them to the `badges` branch; the README reads them from there.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const read = (f) => {
  try {
    return readFileSync(f, "utf8");
  } catch {
    return "";
  }
};

mkdirSync("badges", { recursive: true });
const badge = (file, label, message, color) =>
  writeFileSync(`badges/${file}`, JSON.stringify({ schemaVersion: 1, label, message, color }) + "\n");

const total = read("luacov.report.out").match(/^Total\s+\d+\s+\d+\s+([\d.]+)%/m);
if (total) {
  const pct = Number(total[1]);
  const color = pct >= 95 ? "brightgreen" : pct >= 90 ? "green" : pct >= 75 ? "yellow" : "red";
  badge("coverage.json", "coverage", `${pct.toFixed(1)}%`, color);
}

// strip ANSI colours busted adds to its summary line
const tests = read("busted.out")
  .replace(/\x1b\[[0-9;]*m/g, "")
  .match(/(\d+) successes? \/ (\d+) failures? \/ (\d+) errors?/);
if (tests) {
  const [, ok, failed, errors] = tests.map(Number);
  const bad = failed + errors;
  badge("tests.json", "tests", bad ? `${ok} passed, ${bad} failed` : `${ok} passed`, bad ? "red" : "brightgreen");
}

if (!total || !tests) {
  console.error("missing luacov.report.out or busted.out - run the coverage step first");
  process.exit(1);
}
console.log(read("badges/coverage.json").trim());
console.log(read("badges/tests.json").trim());
