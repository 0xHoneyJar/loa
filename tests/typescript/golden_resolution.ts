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

const PROJECT_ROOT =
  process.env.LOA_GOLDEN_PROJECT_ROOT ??
  path.resolve(__dirname, "..", "..");
const FIXTURES_DIR =
  process.env.LOA_GOLDEN_FIXTURES_DIR ??
  path.join(PROJECT_ROOT, "tests", "fixtures", "model-resolution");
const GENERATED_MAPS =
  process.env.LOA_GOLDEN_GENERATED_MAPS ??
  path.join(PROJECT_ROOT, ".claude", "scripts", "generated-model-maps.sh");

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
    const result: Record<string, string> = {};
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
 * Read a fixture's `sprint_1d_query.alias` field via yq → JSON.
 * Returns null if missing or not a string.
 */
function extractFixtureAlias(fixturePath: string): string | null {
  let json: string;
  try {
    json = execFileSync("yq", ["-o", "json", "-I", "0", ".sprint_1d_query.alias // null", fixturePath], {
      encoding: "utf-8",
    });
  } catch (e) {
    return null;
  }
  const parsed: unknown = JSON.parse(json.trim() || "null");
  if (typeof parsed !== "string" || parsed.length === 0) {
    return null;
  }
  return parsed;
}

/**
 * Emit one canonical JSON line: keys sorted, no whitespace, no trailing
 * newline (println adds the LF).
 */
function emitCanonical(record: Record<string, unknown>): void {
  const sortedKeys = Object.keys(record).sort();
  const sortedRecord: Record<string, unknown> = {};
  for (const k of sortedKeys) {
    sortedRecord[k] = record[k];
  }
  // JSON.stringify does NOT canonicalize key order; we passed a key-sorted
  // object so default stringify produces the same byte sequence as
  // python's json.dumps(sort_keys=True, separators=(",", ":")) and bash's
  // jq -S -c.
  process.stdout.write(JSON.stringify(sortedRecord) + "\n");
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
    const aliasInput = extractFixtureAlias(fixturePath);
    if (!aliasInput) {
      emitCanonical({
        error: "missing-sprint_1d_query-alias",
        fixture: fixtureName,
        subset_supported: false,
      });
      continue;
    }

    // Stage 1 explicit pin: provider:model_id
    if (aliasInput.includes(":")) {
      const colonIdx = aliasInput.indexOf(":");
      const providerPart = aliasInput.slice(0, colonIdx);
      const modelPart = aliasInput.slice(colonIdx + 1);
      if (modelPart in modelProviders) {
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
    if (aliasInput in modelIds) {
      const resolvedId = modelIds[aliasInput];
      const resolvedProvider =
        modelProviders[resolvedId] ?? modelProviders[aliasInput] ?? "unknown";
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
