#!/usr/bin/env node
// Fails when line coverage of src/ (from luacov.report.out) is below the threshold.
//   node tools/coverage.mjs [minPercent]
import { readFileSync } from "node:fs";

const min = Number(process.argv[2] ?? process.env.GG_MIN_COVERAGE ?? 80);
let report;
try {
  report = readFileSync("luacov.report.out", "utf8");
} catch {
  console.error("luacov.report.out not found - run `npm run coverage` first");
  process.exit(2);
}

const summary = report.slice(report.lastIndexOf("Summary"));
const rows = [...summary.matchAll(/^(\S+\.lua)\s+(\d+)\s+(\d+)\s+([\d.]+)%/gm)].map((m) => ({
  file: m[1],
  hits: Number(m[2]),
  missed: Number(m[3]),
  pct: Number(m[4]),
}));
const total = summary.match(/^Total\s+(\d+)\s+(\d+)\s+([\d.]+)%/m);
if (!total) {
  console.error("could not read the coverage summary");
  process.exit(2);
}
for (const r of rows.sort((a, b) => a.pct - b.pct)) {
  console.log(`${r.pct.toFixed(1).padStart(6)}%  ${r.file}`);
}
const pct = Number(total[3]);
console.log(`\ntotal line coverage ${pct.toFixed(2)}% (minimum ${min}%)`);
process.exit(pct >= min ? 0 : 1);
