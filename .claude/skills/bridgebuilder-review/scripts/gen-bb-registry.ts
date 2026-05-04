#!/usr/bin/env -S npx tsx
/**
 * gen-bb-registry.ts — cycle-099 Sprint 1 (T1.1)
 *
 * Reads .claude/defaults/model-config.yaml and emits two committed artifacts
 * into the bridgebuilder-review skill:
 *
 *   - resources/core/truncation.generated.ts  (TOKEN_BUDGETS map)
 *   - resources/config.generated.ts           (MODEL_REGISTRY map)
 *
 * Per cycle-099 SDD §1.4.3 + §5.3. Replaces the hand-maintained
 * TOKEN_BUDGETS map in resources/core/truncation.ts as part of the
 * 13-registry-drift-surface consolidation work (PRD G-3 zero-drift).
 *
 * Sprint-1A scope: codegen produces the artifacts byte-deterministically.
 * Wiring the BB skill to import from the generated files (replacing the
 * hardcoded TOKEN_BUDGETS) is sprint-1B (drift gate + adapter migration).
 *
 * Runtime: works under npx tsx or bun. Uses only node:* APIs. YAML parsing
 * delegated to yq (mikefarah/yq v4+) — same toolchain pattern as the
 * cycle-095 gen-adapter-maps.sh, no new TS deps.
 *
 * CLI:
 *   gen-bb-registry                           emit to default paths
 *   gen-bb-registry --check                   exit 3 if generated files differ
 *   gen-bb-registry --output-dir <path>       emit to <path>/{core,}
 *   gen-bb-registry --source-yaml <path>      override source yaml (testing)
 *   gen-bb-registry --help                    print usage
 *
 * Exit codes:
 *   0  success (or --check passed)
 *   1  generic error
 *   3  drift detected (--check mode)
 *   78 config error (yaml missing / unparseable / missing fields)
 */

import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------------------
// Path resolution: script lives at <repo>/.claude/skills/bridgebuilder-review/scripts/
// ---------------------------------------------------------------------------

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const BB_SKILL_ROOT = resolve(SCRIPT_DIR, "..");
const REPO_ROOT = resolve(BB_SKILL_ROOT, "..", "..", "..");
const DEFAULT_YAML = resolve(REPO_ROOT, ".claude/defaults/model-config.yaml");
const DEFAULT_OUTPUT_DIR = resolve(BB_SKILL_ROOT, "resources");

// ---------------------------------------------------------------------------
// Per-provider defaults: yaml tracks API context_window only; the BB skill's
// truncation engine also needs maxOutput + coefficient (chars-per-token).
// These are codegen-time heuristics matching the existing hand-maintained
// TOKEN_BUDGETS in resources/core/truncation.ts (cycle-098 baseline).
// ---------------------------------------------------------------------------

interface ProviderDefaults {
  maxOutput: number;
  coefficient: number;
}

const PROVIDER_DEFAULTS: Record<string, ProviderDefaults> = {
  anthropic: { maxOutput: 8192, coefficient: 0.25 },
  bedrock: { maxOutput: 8192, coefficient: 0.25 }, // Bedrock hosts Anthropic models
  openai: { maxOutput: 4096, coefficient: 0.23 },
  google: { maxOutput: 8192, coefficient: 0.25 },
};

const FALLBACK_DEFAULT: ProviderDefaults & { maxInput: number } = {
  maxInput: 100000,
  maxOutput: 4096,
  coefficient: 0.25,
};

function providerDefaults(provider: string): ProviderDefaults {
  return PROVIDER_DEFAULTS[provider] ?? { maxOutput: 4096, coefficient: 0.25 };
}

// ---------------------------------------------------------------------------
// Model-config.yaml parsing (via yq subprocess)
// ---------------------------------------------------------------------------

interface YamlPricing {
  input_per_mtok?: number;
  output_per_mtok?: number;
}

interface YamlModelEntry {
  context_window?: number;
  capabilities?: string[];
  endpoint_family?: string;
  pricing?: YamlPricing;
}

interface YamlProvider {
  type?: string;
  models?: Record<string, YamlModelEntry>;
}

interface ProvidersYaml {
  providers?: Record<string, YamlProvider>;
}

function readProviders(yamlPath: string): Record<string, YamlProvider> {
  if (!existsSync(yamlPath)) {
    throw new ConfigError(`source yaml not found: ${yamlPath}`);
  }

  let stdout: string;
  try {
    stdout = execFileSync("yq", ["-o=json", ".", yamlPath], {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new ConfigError(`yq invocation failed (is yq v4+ installed?): ${msg}`);
  }

  let parsed: ProvidersYaml;
  try {
    parsed = JSON.parse(stdout) as ProvidersYaml;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new ConfigError(`yq json output unparseable: ${msg}`);
  }

  if (!parsed.providers || typeof parsed.providers !== "object") {
    throw new ConfigError(`yaml missing .providers map: ${yamlPath}`);
  }
  return parsed.providers;
}

// ---------------------------------------------------------------------------
// Codegen — render TS source strings deterministically
// ---------------------------------------------------------------------------

interface FlatModelEntry {
  modelId: string;
  provider: string;
  contextWindow: number;
  capabilities?: string[];
  endpointFamily?: string;
  pricing?: YamlPricing;
}

/** Flatten yaml providers→models into a sorted list keyed by modelId. */
function flattenModels(providers: Record<string, YamlProvider>): FlatModelEntry[] {
  const entries: FlatModelEntry[] = [];
  // MUST use default code-unit sort (NOT localeCompare) so output is byte-identical
  // across machines with different locales. Verified safe under LC_ALL=tr_TR.UTF-8 +
  // LC_ALL=C — V8's Array.prototype.sort defaults to UTF-16 code-unit comparison.
  const providerNames = Object.keys(providers).sort();
  for (const provider of providerNames) {
    const models = providers[provider]?.models ?? {};
    const modelIds = Object.keys(models).sort();
    for (const modelId of modelIds) {
      const m = models[modelId];
      if (typeof m.context_window !== "number") {
        // Skip models without context_window — they can't drive truncation.
        continue;
      }
      // Validate context_window is a positive integer within JS safe range.
      // Rejects Infinity, NaN, negatives, sub-1 floats, and >MAX_SAFE_INTEGER —
      // any of which would either render an invalid TS literal or silently lose
      // precision through the JSON.parse → toString round-trip.
      if (
        !Number.isInteger(m.context_window) ||
        m.context_window <= 0 ||
        m.context_window > Number.MAX_SAFE_INTEGER
      ) {
        throw new ConfigError(
          `provider ${provider}, model ${modelId}: invalid context_window ${String(
            m.context_window,
          )} (must be positive integer ≤ Number.MAX_SAFE_INTEGER)`,
        );
      }
      entries.push({
        modelId,
        provider,
        contextWindow: m.context_window,
        capabilities: m.capabilities,
        endpointFamily: m.endpoint_family,
        pricing: m.pricing,
      });
    }
  }
  return entries;
}

const HEADER_TRUNCATION = `// AUTO-GENERATED by .claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts
// DO NOT EDIT. Regenerate with \`npm run gen-bb-registry\` (or \`bun run gen-bb-registry\`).
// Source: .claude/defaults/model-config.yaml
//
// Per-provider defaults applied at codegen time (yaml tracks API context_window
// only; maxOutput + coefficient are BB-skill truncation heuristics):
//   anthropic / bedrock / google: maxOutput=8192, coefficient=0.25
//   openai:                       maxOutput=4096, coefficient=0.23
//   default fallback:             maxInput=100000, maxOutput=4096, coefficient=0.25
//
// cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
`;

const HEADER_CONFIG = `// AUTO-GENERATED by .claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts
// DO NOT EDIT. Regenerate with \`npm run gen-bb-registry\` (or \`bun run gen-bb-registry\`).
// Source: .claude/defaults/model-config.yaml
//
// Flattened model registry (provider:model_id → contextWindow + pricing +
// capabilities + endpoint family). Used by future cycle-099 Sprint 2 runtime
// overlay (.run/merged-model-aliases) and by cycle-099 Sprint 1B drift gate
// to keep BB skill model-aware without re-importing yaml at runtime.
//
// cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §3.4 + §5.3.
`;

function renderTruncation(entries: FlatModelEntry[]): string {
  const lines: string[] = [];
  lines.push(HEADER_TRUNCATION);
  lines.push(`import type { TokenBudget } from "./types.js";`);
  lines.push("");
  lines.push(`export const GENERATED_TOKEN_BUDGETS: Record<string, TokenBudget> = {`);
  for (const e of entries) {
    const pd = providerDefaults(e.provider);
    lines.push(
      `  ${jsonKey(e.modelId)}: { maxInput: ${e.contextWindow}, maxOutput: ${pd.maxOutput}, coefficient: ${formatCoefficient(pd.coefficient)} },`,
    );
  }
  // Fallback default entry — preserves the existing TOKEN_BUDGETS["default"] semantic.
  // Quoted for consistency with the always-quote invariant in jsonKey() (HIGH-1).
  lines.push(
    `  "default": { maxInput: ${FALLBACK_DEFAULT.maxInput}, maxOutput: ${FALLBACK_DEFAULT.maxOutput}, coefficient: ${formatCoefficient(FALLBACK_DEFAULT.coefficient)} },`,
  );
  lines.push(`};`);
  lines.push("");
  return lines.join("\n");
}

function renderConfig(entries: FlatModelEntry[]): string {
  const lines: string[] = [];
  lines.push(HEADER_CONFIG);
  lines.push(`export interface GeneratedModelEntry {`);
  lines.push(`  provider: string;`);
  lines.push(`  modelId: string;`);
  lines.push(`  contextWindow: number;`);
  lines.push(`  endpointFamily?: string;`);
  lines.push(`  capabilities?: readonly string[];`);
  lines.push(`  pricing?: { inputPerMtok: number; outputPerMtok: number };`);
  lines.push(`}`);
  lines.push("");
  lines.push(`export const GENERATED_MODEL_REGISTRY: Record<string, GeneratedModelEntry> = {`);
  for (const e of entries) {
    lines.push(`  ${jsonKey(e.modelId)}: {`);
    lines.push(`    provider: ${jsonString(e.provider)},`);
    lines.push(`    modelId: ${jsonString(e.modelId)},`);
    lines.push(`    contextWindow: ${e.contextWindow},`);
    if (e.endpointFamily) {
      lines.push(`    endpointFamily: ${jsonString(e.endpointFamily)},`);
    }
    if (e.capabilities && e.capabilities.length > 0) {
      // Sort capabilities for determinism — yaml insertion order is not guaranteed across editors.
      const sorted = [...e.capabilities].sort();
      lines.push(`    capabilities: [${sorted.map(jsonString).join(", ")}],`);
    }
    if (
      e.pricing &&
      typeof e.pricing.input_per_mtok === "number" &&
      typeof e.pricing.output_per_mtok === "number"
    ) {
      lines.push(
        `    pricing: { inputPerMtok: ${e.pricing.input_per_mtok}, outputPerMtok: ${e.pricing.output_per_mtok} },`,
      );
    }
    lines.push(`  },`);
  }
  lines.push(`};`);
  lines.push("");
  return lines.join("\n");
}

/**
 * TS object key — ALWAYS quote, even for valid identifiers.
 *
 * Rationale: object-literal sugar treats `__proto__: { ... }` as a prototype
 * assignment (NOT an own-property), and `constructor` shadows the inherited
 * Object.prototype.constructor. Both would silently break `Record<string,T>`
 * lookup if a yaml-supplied model_id matched those names. Quoting (`"__proto__":
 * { ... }`) makes them ordinary own-properties.
 *
 * Cosmetic cost: every key is wrapped in `"..."` (e.g., `"default":` vs
 * `default:`) — consumers don't care, and the eliminated bug class is real.
 */
function jsonKey(s: string): string {
  return jsonString(s);
}

/** TS string literal — JSON.stringify guarantees safe escaping. */
function jsonString(s: string): string {
  return JSON.stringify(s);
}

/**
 * Render coefficient as a fixed-decimal string.
 * Avoids platform-dependent float→string variance (e.g., 0.23000000000000001).
 */
function formatCoefficient(n: number): string {
  return n.toFixed(2);
}

// ---------------------------------------------------------------------------
// File I/O — two-phase rename (atomic) + symlink-aware path resolution
// ---------------------------------------------------------------------------

interface OutputPaths {
  truncation: string;
  config: string;
}

function resolveOutputs(outputDir: string): OutputPaths {
  return {
    truncation: resolve(outputDir, "core", "truncation.generated.ts"),
    config: resolve(outputDir, "config.generated.ts"),
  };
}

/**
 * Defense-in-depth: realpath the first existing ancestor of `target` and warn
 * if it differs from the lexically-resolved path. Catches the case where an
 * attacker on a shared CI runner pre-places a symlink at the output path
 * pointing somewhere unexpected. We log to stderr (don't reject) because:
 *   1. Legitimate workflows mount /tmp via symlink in some container runtimes.
 *   2. The codegen output is non-secret framework data.
 *   3. The committed-tree drift gate (sprint-1B) is the load-bearing defense
 *      against silent build-output corruption — this is just transparency.
 */
function warnIfSymlinkRedirect(target: string): void {
  // Walk up to find the first existing ancestor.
  let probe = target;
  while (probe !== dirname(probe)) {
    if (existsSync(probe)) break;
    probe = dirname(probe);
  }
  try {
    const real = realpathSync(probe);
    if (real !== probe) {
      process.stderr.write(
        `[SYMLINK-REDIRECT] ${probe} -> ${real} (output may land outside lexical path)\n`,
      );
    }
  } catch {
    // realpathSync failed (race during ancestor walk); ignore.
  }
}

/**
 * Two-phase write: writeFileSync to <target>.tmp.<pid>, then renameSync to
 * <target>. rename(2) is atomic within the same filesystem, so concurrent
 * codegen invocations cannot leave a half-written .ts file. Tmp file lives
 * in the same dir as the final file (cross-fs rename is non-atomic on
 * Linux — same-dir guarantees same-fs).
 */
function atomicWrite(target: string, content: string): void {
  const tmp = `${target}.tmp.${process.pid}`;
  writeFileSync(tmp, content);
  renameSync(tmp, target);
}

function writeOut(paths: OutputPaths, truncation: string, config: string): void {
  // Ensure parent directories exist (mirroring the BB skill resources layout).
  mkdirSync(dirname(paths.truncation), { recursive: true });
  mkdirSync(dirname(paths.config), { recursive: true });
  warnIfSymlinkRedirect(paths.truncation);
  warnIfSymlinkRedirect(paths.config);
  atomicWrite(paths.truncation, truncation);
  atomicWrite(paths.config, config);
}

interface DriftResult {
  drifted: boolean;
  reasons: string[];
}

function checkDrift(paths: OutputPaths, truncation: string, config: string): DriftResult {
  const reasons: string[] = [];
  if (!existsSync(paths.truncation)) {
    reasons.push(`missing: ${paths.truncation}`);
  } else {
    const onDisk = readFileSync(paths.truncation, "utf-8");
    if (onDisk !== truncation) {
      reasons.push(`content drift: ${paths.truncation}`);
    }
  }
  if (!existsSync(paths.config)) {
    reasons.push(`missing: ${paths.config}`);
  } else {
    const onDisk = readFileSync(paths.config, "utf-8");
    if (onDisk !== config) {
      reasons.push(`content drift: ${paths.config}`);
    }
  }
  return { drifted: reasons.length > 0, reasons };
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

class ConfigError extends Error {}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

interface Args {
  check: boolean;
  outputDir: string;
  sourceYaml: string;
  help: boolean;
}

function parseArgs(argv: string[]): Args {
  const args: Args = {
    check: false,
    outputDir: DEFAULT_OUTPUT_DIR,
    sourceYaml: DEFAULT_YAML,
    help: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--help" || a === "-h") {
      args.help = true;
    } else if (a === "--check") {
      args.check = true;
    } else if (a === "--output-dir") {
      const v = argv[++i];
      if (!v) throw new ConfigError("--output-dir requires a path argument");
      args.outputDir = resolve(v);
    } else if (a === "--source-yaml") {
      const v = argv[++i];
      if (!v) throw new ConfigError("--source-yaml requires a path argument");
      args.sourceYaml = resolve(v);
    } else {
      throw new ConfigError(`unknown argument: ${a}`);
    }
  }
  return args;
}

function printHelp(): void {
  process.stdout.write(
    `gen-bb-registry — cycle-099 sprint-1 codegen for the bridgebuilder-review skill.

Reads .claude/defaults/model-config.yaml and emits:
  resources/core/truncation.generated.ts  (TOKEN_BUDGETS map)
  resources/config.generated.ts           (MODEL_REGISTRY map)

Usage:
  gen-bb-registry [--check] [--output-dir <dir>] [--source-yaml <path>]
  gen-bb-registry --help

Options:
  --check                exit 3 if generated files do not match what
                         would be regenerated (drift detection)
  --output-dir <dir>     emit under <dir>/core/ and <dir>/ (default:
                         .claude/skills/bridgebuilder-review/resources/)
  --source-yaml <path>   override the model-config.yaml source path
                         (testing only — defaults to repo's framework yaml)
  --help, -h             this message

Exit codes:
  0   success
  1   generic error
  3   [DRIFT-DETECTED] (--check mode)
  78  [CONFIG-ERROR] (yaml missing / yq error / unparseable input)
`,
  );
}

function main(argv: string[]): number {
  let args: Args;
  try {
    args = parseArgs(argv);
  } catch (e) {
    process.stderr.write(`[CONFIG-ERROR] ${(e as Error).message}\n`);
    return 78;
  }

  if (args.help) {
    printHelp();
    return 0;
  }

  let truncation: string;
  let config: string;
  try {
    const providers = readProviders(args.sourceYaml);
    const flat = flattenModels(providers);
    if (flat.length === 0) {
      throw new ConfigError(
        `no models with context_window found in ${args.sourceYaml}`,
      );
    }
    truncation = renderTruncation(flat);
    config = renderConfig(flat);
  } catch (e) {
    if (e instanceof ConfigError) {
      process.stderr.write(`[CONFIG-ERROR] ${e.message}\n`);
      return 78;
    }
    throw e;
  }

  const paths = resolveOutputs(args.outputDir);

  if (args.check) {
    const drift = checkDrift(paths, truncation, config);
    if (drift.drifted) {
      process.stderr.write(
        `[DRIFT-DETECTED] regenerate via \`npm run gen-bb-registry\`:\n`,
      );
      for (const r of drift.reasons) {
        process.stderr.write(`  - ${r}\n`);
      }
      return 3;
    }
    return 0;
  }

  try {
    writeOut(paths, truncation, config);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    process.stderr.write(`error writing output: ${msg}\n`);
    return 1;
  }
  process.stderr.write(`generated:\n  ${paths.truncation}\n  ${paths.config}\n`);
  return 0;
}

const exitCode = main(process.argv.slice(2));
process.exit(exitCode);
