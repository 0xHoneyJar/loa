#!/usr/bin/env tsx
/**
 * golden_resolution.ts — cycle-099 Sprint 2D.c TypeScript golden test runner.
 *
 * Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
 * filename) and runs the canonical-from-Python TS resolver
 * (`.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts`,
 * codegen output of the Python canonical via Jinja2 per SDD §1.5.1) against
 * `input.{framework_defaults, operator_config, runtime_state}` for each
 * (skill, role) tuple declared in `expected.resolutions[]`. Emits one
 * canonical JSON line per resolution to stdout.
 *
 * Output schema MUST match tests/python/golden_resolution.py and
 * tests/bash/golden_resolution.sh byte-for-byte. The cross-runtime-diff CI
 * gate (.github/workflows/cross-runtime-diff.yml) byte-compares all three
 * runtimes; mismatch fails the build per SDD §7.6.2.
 *
 * Sprint 2D.c scope: TS port via Python+Jinja2 codegen. Mirrors sprint-1E.c.1's
 * pattern verbatim. Activates 3-way cross-runtime parity gate (Python ↔ bash
 * ↔ TS) which was deferred in Sprint 2D.a+b.
 *
 * Implementation notes:
 *   - Imports `resolve` + `dumpCanonicalJson` from the codegen-generated
 *     resolver module. The generated TS is byte-deterministic from the
 *     canonical Python; drift gate fails CI on mismatch.
 *   - Uses `yq` (cycle-099 CI dependency) to convert YAML fixtures to JSON
 *     so TypeScript can parse without adding a `yaml` package dependency.
 *   - Per-fixture sort: by (skill, role) ascending — matches Python and bash
 *     runners' sort order so output is byte-identical.
 *
 * Usage:
 *   tsx tests/typescript/golden_resolution.ts > typescript-resolution-output.jsonl
 *
 * Env-var test escapes (each REQUIRES `LOA_GOLDEN_TEST_MODE=1` OR running
 * under bats — mirrors cycle-099 sprint-1B `LOA_MODEL_RESOLVER_TEST_MODE`):
 *
 *   LOA_GOLDEN_PROJECT_ROOT  — override project root
 *   LOA_GOLDEN_FIXTURES_DIR  — override fixtures directory
 *
 * Without TEST_MODE the override is IGNORED with a stderr warning.
 */

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

import {
  resolve,
  dumpCanonicalJson,
  type ResolutionResult,
} from "../../.claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts";

// --- Test-mode override gating (cycle-099 LOA_*_TEST_MODE pattern) -------

function goldenTestModeActive(): boolean {
  return (
    process.env.LOA_GOLDEN_TEST_MODE === "1" ||
    !!process.env.BATS_TEST_DIRNAME
  );
}

function goldenResolvePath(envVar: string, fallback: string): string {
  const val = process.env[envVar];
  if (val) {
    if (goldenTestModeActive()) {
      process.stderr.write(`[GOLDEN] override active: ${envVar}=${val}\n`);
      return val;
    }
    process.stderr.write(
      `[GOLDEN] WARNING: ${envVar} set but LOA_GOLDEN_TEST_MODE!=1 and not running under bats — IGNORED\n`,
    );
  }
  return fallback;
}

const PROJECT_ROOT_DEFAULT = path.resolve(__dirname, "..", "..");
const PROJECT_ROOT = goldenResolvePath("LOA_GOLDEN_PROJECT_ROOT", PROJECT_ROOT_DEFAULT);
const FIXTURES_DIR = goldenResolvePath(
  "LOA_GOLDEN_FIXTURES_DIR",
  path.join(PROJECT_ROOT, "tests", "fixtures", "model-resolution"),
);

// --- Main runner ---------------------------------------------------------

function main(): number {
  if (!fs.statSync(FIXTURES_DIR, { throwIfNoEntry: false })?.isDirectory()) {
    console.error(`golden_resolution.ts: fixtures dir ${FIXTURES_DIR} not present`);
    return 2;
  }

  const fixtures = fs
    .readdirSync(FIXTURES_DIR)
    .filter((f) => f.endsWith(".yaml"))
    .sort()
    .map((f) => path.join(FIXTURES_DIR, f));

  for (const fixturePath of fixtures) {
    const fixtureName = path.basename(fixturePath, ".yaml");

    // Convert YAML to JSON via yq. On parse failure, emit a uniform
    // [YAML-PARSE-FAILED] error matching Python + bash runners.
    let json: string;
    try {
      json = execFileSync("yq", ["-o", "json", ".", fixturePath], { encoding: "utf-8" });
    } catch (e) {
      process.stdout.write(dumpCanonicalJson({
        fixture: fixtureName,
        error: {
          code: "[YAML-PARSE-FAILED]",
          stage_failed: 0,
          detail: "fixture YAML failed to parse",
        },
      }) + "\n");
      continue;
    }

    let doc: unknown;
    try {
      doc = JSON.parse(json);
    } catch (e) {
      process.stdout.write(dumpCanonicalJson({
        fixture: fixtureName,
        error: {
          code: "[YAML-PARSE-FAILED]",
          stage_failed: 0,
          detail: "fixture JSON conversion failed",
        },
      }) + "\n");
      continue;
    }

    if (doc === null || typeof doc !== "object" || Array.isArray(doc)) {
      process.stdout.write(dumpCanonicalJson({
        fixture: fixtureName,
        error: {
          code: "[NO-EXPECTED-RESOLUTIONS]",
          stage_failed: 0,
          detail: "fixture lacks expected.resolutions[] block",
        },
      }) + "\n");
      continue;
    }

    const docRec = doc as Record<string, unknown>;
    const mergedConfig = (docRec.input || {}) as Record<string, unknown>;
    const expected = (docRec.expected || {}) as Record<string, unknown>;
    const resolutionsRaw = expected.resolutions;

    if (!Array.isArray(resolutionsRaw) || resolutionsRaw.length === 0) {
      process.stdout.write(dumpCanonicalJson({
        fixture: fixtureName,
        error: {
          code: "[NO-EXPECTED-RESOLUTIONS]",
          stage_failed: 0,
          detail: "fixture lacks expected.resolutions[] block",
        },
      }) + "\n");
      continue;
    }

    // Filter + sort by (skill, role) — matches Python and bash sort.
    const validResolutions = resolutionsRaw.filter(
      (r: unknown): r is Record<string, unknown> =>
        r !== null && typeof r === "object" && !Array.isArray(r) &&
        typeof (r as Record<string, unknown>).skill === "string" &&
        typeof (r as Record<string, unknown>).role === "string",
    );
    validResolutions.sort((a, b) => {
      const askill = a.skill as string;
      const bskill = b.skill as string;
      if (askill < bskill) return -1;
      if (askill > bskill) return 1;
      const arole = a.role as string;
      const brole = b.role as string;
      if (arole < brole) return -1;
      if (arole > brole) return 1;
      return 0;
    });

    for (const entry of validResolutions) {
      const skill = entry.skill as string;
      const role = entry.role as string;
      const result: ResolutionResult = resolve(mergedConfig, skill, role);
      // Decorate with fixture context tag — same as Python + bash runners.
      const decorated = { ...result, fixture: fixtureName };
      process.stdout.write(dumpCanonicalJson(decorated) + "\n");
    }
  }

  return 0;
}

process.exit(main());
