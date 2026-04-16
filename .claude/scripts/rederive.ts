#!/usr/bin/env npx tsx
/**
 * rederive.ts — Archivist rederivation harness (Cycle 2)
 *
 * CLI: npx tsx .claude/scripts/rederive.ts [--oracle <path>] [--candidate <path>]
 *
 * Exit codes:
 *   0 — fidelity >= 0.80 && oracle_integrity: true
 *   1 — pre-condition not met (missing seed file, bonfire absent)
 *   2 — oracle and candidate paths are identical
 *   3 — runtime failure (integrity violation, write failure, validation failure, HOME unset)
 */

import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { resolvePath, readSeedPaths } from "./lib/utils";
import { runPreflight } from "./lib/preflight";
import { initState } from "./lib/state";
import { synthesize } from "./lib/synthesize";
import { computeScore, emitReport, sha256File } from "./lib/score";
import { appendTrajectoryEvent } from "./lib/trajectory";

const DEFAULT_ORACLE = "~/hivemind/wiki/concepts/memory-architecture-synthesis.md";
const DEFAULT_CANDIDATE =
  "~/hivemind/wiki/concepts/memory-architecture-synthesis.rederived.md";
const SEED_CONTEXT = path.resolve(process.cwd(), ".run/spiral-seed-context.md");
const SCHEMA_PATH = path.resolve(process.cwd(), "schemas/page-frontmatter.v0.1.json");
const TRAJECTORY_PATH = path.resolve(process.cwd(), "grimoires/loa/trajectory.jsonl");

function parseArgs(): { oracle: string; candidate: string } {
  const args = process.argv.slice(2);
  let oracle = DEFAULT_ORACLE;
  let candidate = DEFAULT_CANDIDATE;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--oracle" && args[i + 1]) oracle = args[++i];
    if (args[i] === "--candidate" && args[i + 1]) candidate = args[++i];
  }
  return { oracle, candidate };
}

async function main() {
  const { oracle, candidate } = parseArgs();

  // Phase 1: preflight
  let allPaths: string[];
  try {
    allPaths = readSeedPaths(SEED_CONTEXT);
  } catch (err) {
    console.error(`FATAL: could not read seed context: ${err}`);
    process.exit(1);
  }

  // Filter to actual seed files: must have extension, exclude oracle/candidate
  const oracleResolved = resolvePath(oracle);
  const candidateResolved = resolvePath(candidate);
  const seedPaths = allPaths.filter((p) => {
    if (!path.extname(p)) return false;
    const resolved = resolvePath(p);
    return resolved !== oracleResolved && resolved !== candidateResolved;
  });

  runPreflight(oracle, candidate, seedPaths);

  // Phase 2: snapshot oracle sha256
  const resolvedOracle = resolvePath(oracle);
  const resolvedCandidate = resolvePath(candidate);

  let sha256Before: string;
  try {
    sha256Before = sha256File(resolvedOracle);
  } catch (err) {
    console.error(`FATAL: could not hash oracle: ${err}`);
    process.exit(3);
  }

  // Phase 3: extract oracle citations (one read only)
  const oracleContent = fs.readFileSync(resolvedOracle, "utf8");

  // Phase 4: initialize state
  initState();

  // Phase 5: wipe candidate if it exists
  if (fs.existsSync(resolvedCandidate)) {
    fs.unlinkSync(resolvedCandidate);
  }

  // Phase 6: run semantic synthesis
  const oracleExcluded = new Set([resolvedOracle]);
  try {
    synthesize(seedPaths, resolvedCandidate, oracleExcluded, SCHEMA_PATH);
  } catch (err) {
    console.error(`FATAL: synthesis failed: ${err}`);
    process.exit(3);
  }

  // Phase 7: extract candidate citations
  const candidateContent = fs.readFileSync(resolvedCandidate, "utf8");

  // Phase 8: re-snapshot oracle sha256
  let sha256After: string;
  try {
    sha256After = sha256File(resolvedOracle);
  } catch (err) {
    console.error(`FATAL: could not re-hash oracle: ${err}`);
    process.exit(3);
  }

  // Phase 9: compute score
  const result = computeScore(oracleContent, candidateContent, sha256Before, sha256After);

  // Phase 10: append trajectory event (best-effort)
  appendTrajectoryEvent(TRAJECTORY_PATH, {
    event: "forge.archivist.page_synthesized",
    timestamp: new Date().toISOString(),
    oracle_path: oracle,
    candidate_path: candidate,
    fidelity: result.fidelity,
    pass: result.pass,
    oracle_integrity: result.oracle_integrity,
    seed_count: seedPaths.length,
  });

  // Phase 11: emit report
  emitReport(result);

  // Phase 12: exit
  if (result.pass && result.oracle_integrity) {
    process.exit(0);
  } else {
    process.exit(3);
  }
}

main().catch((err) => {
  console.error(`FATAL: unhandled error: ${err}`);
  process.exit(3);
});
