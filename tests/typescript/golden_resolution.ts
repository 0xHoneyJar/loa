#!/usr/bin/env tsx
/**
 * golden_resolution.ts — cycle-099 Sprint 1D TypeScript runner.
 *
 * Reads each .yaml fixture under tests/fixtures/model-resolution/ (sorted by
 * filename), extracts `sprint_1d_query.alias`, performs alias resolution
 * against the SAME registry the bash + python runners use (parsed directly
 * from .claude/scripts/generated-model-maps.sh), and emits one canonical
 * JSON line per fixture to stdout.
 *
 * Output schema MUST be byte-identical to tests/bash/golden_resolution.sh
 * and tests/python/golden_resolution.py (cross-runtime parity per
 * SDD §7.6.2). The cross-runtime-diff CI gate
 * (.github/workflows/cross-runtime-diff.yml) byte-compares all three
 * runtimes' emitted output; mismatch fails the build.
 *
 * Sprint 1D scope: alias-lookup subset of FR-3.9. Stages 3-6 deferred to
 * Sprint 2 T2.6; runners emit a uniform `deferred_to: "sprint-2-T2.6"`
 * marker for unsupported scenarios.
 *
 * Implementation notes:
 *   - Parses generated-model-maps.sh directly (same source as bash + python)
 *     instead of importing GENERATED_MODEL_REGISTRY from config.generated.ts,
 *     because the TS registry uses canonical model IDs as keys but does not
 *     expose the alias→canonical mapping (e.g., `opus → claude-opus-4-7`).
 *     Sprint 2's T2.6 will add a TS-codegen alias map; for Sprint 1D we
 *     mirror the python parser to keep the three runtimes literally
 *     reading the SAME source-of-truth file.
 *   - Uses `yq` (cycle-099 CI dependency) to convert YAML fixtures to JSON
 *     so TypeScript can parse without adding a `yaml` package dependency
 *     to the BB skill (which currently doesn't ship one).
 *
 * Usage:
 *   tsx tests/typescript/golden_resolution.ts > typescript-resolution-output.jsonl
 */

import { execFileSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

/**
 * cypherpunk CRIT-3 (PR #735 review): env-override gate parity. Mirrors the
 * model-resolver.sh::LOA_MODEL_RESOLVER_TEST_MODE pattern. Each LOA_GOLDEN_*
 * override REQUIRES LOA_GOLDEN_TEST_MODE=1 OR BATS_TEST_DIRNAME (set by
 * bats), else the override is IGNORED.
 */
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
const GENERATED_MAPS = goldenResolvePath(
  "LOA_GOLDEN_GENERATED_MAPS",
  path.join(PROJECT_ROOT, ".claude", "scripts", "generated-model-maps.sh"),
);

interface ParsedMaps {
  modelProviders: Record<string, string>;
  modelIds: Record<string, string>;
}

/**
 * Parse `declare -A NAME=( ["k"]="v" ... )` blocks from generated-model-maps.sh.
 * Mirror of python's _parse_generated_maps. Same regex semantics so bash,
 * python, and TS all see the same key/value set.
 */
function parseGeneratedMaps(filePath: string): ParsedMaps {
  const text = fs.readFileSync(filePath, "utf-8");

  function extractArray(name: string): Record<string, string> {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    // declare -A NAME=( ... ) — use [\s\S] to match across newlines (no /s flag in older Node).
    const re = new RegExp(`declare\\s+-A\\s+${escaped}=\\s*\\(\\s*([\\s\\S]*?)\\s*\\)`);
    const m = re.exec(text);
    if (!m) {
      throw new Error(`declare -A ${name} not found in ${filePath}`);
    }
    const body = m[1];
    // cypherpunk CRIT-1 (PR #735 review): use Object.create(null) so the
    // returned record has NO prototype. Plain `{}` inherits from
    // Object.prototype, making `"toString" in result` evaluate to true even
    // for un-set keys — diverging from bash assoc-arrays + Python dicts.
    const result: Record<string, string> = Object.create(null);
    // Each entry: ["key"]="value"
    const entryRe = /\[\s*"([^"]*)"\s*\]\s*=\s*"([^"]*)"\s*/g;
    let entryM: RegExpExecArray | null;
    while ((entryM = entryRe.exec(body)) !== null) {
      // Bash associative-array semantic: duplicate keys overwrite (last wins).
      result[entryM[1]] = entryM[2];
    }
    return result;
  }

  return {
    modelProviders: extractArray("MODEL_PROVIDERS"),
    modelIds: extractArray("MODEL_IDS"),
  };
}

/**
 * Recursively sort all keys in objects (depth-first, preserving array order).
 * gp CRITICAL-1 (PR #735 review): JSON.stringify with manually-sorted top
 * keys does NOT recursively sort nested objects, while jq -S and Python's
 * sort_keys=True DO. Today's flat-string output masks the divergence; Sprint
 * 2's nested resolution_path arrays would expose it.
 *
 * Returns a new object/array; does not mutate input.
 */
function canonicalizeRecursive(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(canonicalizeRecursive);
  }
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = Object.create(null);
    const sortedKeys = Object.keys(value as Record<string, unknown>).sort();
    for (const k of sortedKeys) {
      out[k] = canonicalizeRecursive((value as Record<string, unknown>)[k]);
    }
    return out;
  }
  return value;
}

/**
 * cypherpunk CRIT-1 + gp HIGH-1: prototype-safe key existence check. Replace
 * `key in obj` (which walks Object.prototype) with hasOwn equivalence.
 */
function hasKey(obj: Record<string, unknown>, key: string): boolean {
  return Object.prototype.hasOwnProperty.call(obj, key);
}

/**
 * Read a fixture's `sprint_1d_query.alias` field via yq + tag.
 * gp HIGH-2 / cypherpunk CRIT-2: type-discrimination matches bash's
 * `yq | tag` semantics. Distinct return values for each failure mode so
 * the runner can emit identical error markers to bash.
 */
type AliasResult =
  | { kind: "ok"; value: string }
  | { kind: "missing" }
  | { kind: "invalid-type"; tag: string };

function extractFixtureAlias(fixturePath: string): AliasResult {
  let tagOutput: string;
  try {
    tagOutput = execFileSync(
      "yq",
      ["eval", ".sprint_1d_query.alias | tag", fixturePath],
      { encoding: "utf-8" },
    ).trim();
  } catch (e) {
    return { kind: "missing" };
  }
  if (!tagOutput || tagOutput === "!!null") {
    return { kind: "missing" };
  }
  if (tagOutput !== "!!str") {
    return { kind: "invalid-type", tag: tagOutput };
  }
  let valOutput: string;
  try {
    valOutput = execFileSync(
      "yq",
      ["eval", ".sprint_1d_query.alias", fixturePath],
      { encoding: "utf-8" },
    );
  } catch (e) {
    return { kind: "missing" };
  }
  // yq eval on a string emits the bare string + trailing newline.
  const trimmed = valOutput.replace(/\n$/, "");
  if (!trimmed) {
    return { kind: "missing" };
  }
  return { kind: "ok", value: trimmed };
}

/**
 * Emit one canonical JSON line: recursively sorted keys, no whitespace,
 * UTF-8 literal (no \\uXXXX escapes for non-ASCII).
 *
 * gp CRITICAL-1 fix: canonicalizeRecursive walks nested objects/arrays so
 * Sprint 2's resolution_path arrays maintain byte-equality across runtimes.
 * gp CRITICAL-2: JSON.stringify defaults to literal UTF-8 (matches bash
 * jq -c and Python with ensure_ascii=False).
 */
function emitCanonical(record: Record<string, unknown>): void {
  const canon = canonicalizeRecursive(record);
  process.stdout.write(JSON.stringify(canon) + "\n");
}

function main(): number {
  if (!fs.statSync(FIXTURES_DIR, { throwIfNoEntry: false })?.isDirectory()) {
    console.error(`golden_resolution.ts: fixtures dir ${FIXTURES_DIR} not present`);
    return 2;
  }
  if (!fs.statSync(GENERATED_MAPS, { throwIfNoEntry: false })?.isFile()) {
    console.error(`golden_resolution.ts: generated-maps ${GENERATED_MAPS} not present`);
    return 2;
  }

  const { modelProviders, modelIds } = parseGeneratedMaps(GENERATED_MAPS);

  const fixtures = fs
    .readdirSync(FIXTURES_DIR)
    .filter((f) => f.endsWith(".yaml"))
    .sort()
    .map((f) => path.join(FIXTURES_DIR, f));

  for (const fixturePath of fixtures) {
    const fixtureName = path.basename(fixturePath, ".yaml");
    const aliasResult = extractFixtureAlias(fixturePath);
    if (aliasResult.kind === "missing") {
      emitCanonical({
        error: "missing-sprint_1d_query-alias",
        fixture: fixtureName,
        subset_supported: false,
      });
      continue;
    }
    if (aliasResult.kind === "invalid-type") {
      emitCanonical({
        error: `invalid-alias-type:${aliasResult.tag}`,
        fixture: fixtureName,
        subset_supported: false,
      });
      continue;
    }
    const aliasInput = aliasResult.value;

    // Stage 1 explicit pin: provider:model_id
    if (aliasInput.includes(":")) {
      const colonIdx = aliasInput.indexOf(":");
      const providerPart = aliasInput.slice(0, colonIdx);
      const modelPart = aliasInput.slice(colonIdx + 1);
      if (hasKey(modelProviders, modelPart)) {
        emitCanonical({
          fixture: fixtureName,
          input_alias: aliasInput,
          resolved_model_id: modelPart,
          resolved_provider: providerPart,
          subset_supported: true,
        });
        continue;
      }
      emitCanonical({
        deferred_to: "sprint-2-T2.6",
        fixture: fixtureName,
        input_alias: aliasInput,
        subset_supported: false,
      });
      continue;
    }

    // Plain alias: resolve via MODEL_IDS / MODEL_PROVIDERS
    if (hasKey(modelIds, aliasInput)) {
      const resolvedId = modelIds[aliasInput];
      const resolvedProvider = hasKey(modelProviders, resolvedId)
        ? modelProviders[resolvedId]
        : hasKey(modelProviders, aliasInput)
          ? modelProviders[aliasInput]
          : "unknown";
      emitCanonical({
        fixture: fixtureName,
        input_alias: aliasInput,
        resolved_model_id: resolvedId,
        resolved_provider: resolvedProvider,
        subset_supported: true,
      });
    } else {
      emitCanonical({
        deferred_to: "sprint-2-T2.6",
        fixture: fixtureName,
        input_alias: aliasInput,
        subset_supported: false,
      });
    }
  }

  return 0;
}

process.exit(main());
