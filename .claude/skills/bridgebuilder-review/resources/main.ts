import { readFile, readdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ReviewPipeline,
  PRReviewTemplate,
  BridgebuilderContext,
} from "./core/index.js";
import { createLocalAdapters } from "./adapters/index.js";
import {
  parseCLIArgs,
  resolveConfig,
  resolveRepos,
  formatEffectiveConfig,
  loadMultiModelConfig,
  validateApiKeys,
} from "./config.js";
import type { BridgebuilderConfig, RunSummary } from "./core/types.js";
import { executeMultiModelReview } from "./core/multi-model-pipeline.js";
import { DEFAULT_LORE_PATH, loadLoreEntries } from "./core/lore-loader.js";
import type { LoreEntry } from "./core/template.js";
import { detectRefs, parseManualRefs, fetchCrossRepoContext } from "./core/cross-repo.js";
import { renderCrossRepoSection } from "./core/cross-repo-render.js";
import { ProgressReporter } from "./core/progress.js";
import {
  buildRatingPrompt,
  storeRating,
  createRatingEntry,
  readRatingWithTimeout,
} from "./core/rating.js";
import { truncateFiles, deriveCallConfig } from "./core/truncation.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Persona pack directory relative to this module. */
const PERSONAS_DIR = resolve(__dirname, "personas");

/**
 * Parse optional YAML frontmatter from persona content (V3-2).
 * Returns the model override (if any) and the content without frontmatter.
 */
export function parsePersonaFrontmatter(raw: string): { content: string; model?: string } {
  const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return { content: raw };

  const frontmatter = match[1];
  const content = match[2];

  // Extract model field from frontmatter (simple key: value parsing)
  const modelMatch = frontmatter.match(/^\s*model:\s*(.+?)\s*$/m);
  const model = modelMatch?.[1]?.replace(/^["']|["']$/g, "");

  // Ignore commented-out model lines (# model: ...)
  if (model && model.startsWith("#")) return { content };

  return { content, model: model || undefined };
}

/**
 * Discover available persona packs from the personas/ directory.
 * Returns pack names (e.g., ["default", "security", "dx", "architecture", "quick"]).
 */
export async function discoverPersonas(): Promise<string[]> {
  try {
    const files = await readdir(PERSONAS_DIR);
    return files
      .filter((f) => f.endsWith(".md"))
      .map((f) => f.replace(/\.md$/, ""))
      .sort();
  } catch {
    return [];
  }
}

/**
 * Read the H1 title from a persona file (after YAML frontmatter).
 * Returns the title text without the leading "# " marker, or the pack name
 * fallback if no H1 is found. Used by --list-personas to give users a
 * one-line description of each pack.
 */
export async function readPersonaTitle(packName: string): Promise<string> {
  const packPath = resolve(PERSONAS_DIR, `${packName}.md`);
  try {
    const raw = await readFile(packPath, "utf-8");
    const { content } = parsePersonaFrontmatter(raw);
    const firstLine = content.split("\n").find((l) => l.trim().length > 0) ?? "";
    const titleMatch = firstLine.match(/^#\s+(.+?)\s*$/);
    return titleMatch ? titleMatch[1] : packName;
  } catch {
    return packName;
  }
}

/**
 * Summarize the persona resolution cascade for `--show-persona-resolution`.
 * Returns an ordered list of cascade levels with whether each is active,
 * skipped (input not provided), or shadowed (input provided but a higher
 * level won). The active level is the one `loadPersona()` will return.
 */
export interface PersonaResolutionStep {
  level: number;
  name: string;
  state: "active" | "skip" | "shadow" | "missing";
  value?: string;
  reason?: string;
}

export async function traceResolution(
  config: BridgebuilderConfig,
): Promise<PersonaResolutionStep[]> {
  const packName = config.persona;
  const customPath = config.personaFilePath;
  const repoOverridePath = config.repoOverridePath;

  const steps: PersonaResolutionStep[] = [];
  let activeFound = false;

  // Level 1: --persona CLI flag / Level 2: persona: YAML (both resolve to pack name)
  if (packName) {
    const packPath = resolve(PERSONAS_DIR, `${packName}.md`);
    let packExists = false;
    try {
      await readFile(packPath, "utf-8");
      packExists = true;
    } catch {
      packExists = false;
    }
    steps.push({
      level: 1,
      name: "--persona flag / persona: YAML",
      state: packExists ? "active" : "missing",
      value: packName,
      reason: packExists
        ? `pack file: ${packPath}`
        : `pack file not found: ${packPath}`,
    });
    if (packExists) activeFound = true;
  } else {
    steps.push({
      level: 1,
      name: "--persona flag / persona: YAML",
      state: "skip",
      reason: "not provided",
    });
  }

  // Level 3: persona_path → custom file
  if (customPath) {
    let customExists = false;
    try {
      await readFile(customPath, "utf-8");
      customExists = true;
    } catch {
      customExists = false;
    }
    const state = activeFound
      ? "shadow"
      : customExists
      ? "active"
      : "missing";
    steps.push({
      level: 3,
      name: "persona_path: YAML",
      state,
      value: customPath,
      reason: customExists
        ? undefined
        : state === "missing"
        ? `file not found: ${customPath}`
        : undefined,
    });
    if (state === "active") activeFound = true;
  } else {
    steps.push({
      level: 3,
      name: "persona_path: YAML",
      state: "skip",
      reason: "not provided",
    });
  }

  // Level 4: repo override (grimoires/bridgebuilder/BEAUVOIR.md)
  if (repoOverridePath) {
    let repoExists = false;
    try {
      await readFile(repoOverridePath, "utf-8");
      repoExists = true;
    } catch {
      repoExists = false;
    }
    const state = activeFound
      ? "shadow"
      : repoExists
      ? "active"
      : "missing";
    steps.push({
      level: 4,
      name: "repo override (BEAUVOIR.md)",
      state,
      value: repoOverridePath,
      reason: repoExists
        ? undefined
        : state === "missing"
        ? `file not found: ${repoOverridePath}`
        : undefined,
    });
    if (state === "active") activeFound = true;
  } else {
    steps.push({
      level: 4,
      name: "repo override (BEAUVOIR.md)",
      state: "skip",
      reason: "not provided",
    });
  }

  // Level 5: built-in default
  const defaultPath = resolve(PERSONAS_DIR, "default.md");
  steps.push({
    level: 5,
    name: "built-in default",
    state: activeFound ? "shadow" : "active",
    value: defaultPath,
  });

  return steps;
}

/**
 * Format persona resolution steps for terminal display.
 */
export function formatResolutionTrace(steps: PersonaResolutionStep[]): string {
  const lines: string[] = ["persona resolution:"];
  for (const step of steps) {
    const marker =
      step.state === "active"
        ? "[active]"
        : step.state === "shadow"
        ? "[shadow]"
        : step.state === "missing"
        ? "[missing]"
        : "[skip]  ";
    const head = `  ${marker} L${step.level} ${step.name}`;
    const tail = step.value ? `: ${step.value}` : "";
    const note = step.reason ? `  (${step.reason})` : "";
    lines.push(`${head}${tail}${note}`);
  }
  return lines.join("\n");
}

/**
 * Load persona using 5-level CLI-wins precedence chain:
 * 1. --persona <name> CLI flag → resources/personas/<name>.md
 * 2. persona: <name> YAML config → resources/personas/<name>.md
 * 3. persona_path: <path> YAML config → load custom file path
 * 4. grimoires/bridgebuilder/BEAUVOIR.md (repo-level override)
 * 5. resources/personas/default.md (built-in default)
 *
 * Returns { content, source } for logging.
 */
export async function loadPersona(
  config: BridgebuilderConfig,
  logger?: { warn: (msg: string) => void },
): Promise<{ content: string; source: string; model?: string }> {
  const repoOverridePath = config.repoOverridePath;
  const packName = config.persona;
  const customPath = config.personaFilePath;

  // Level 1 & 2: --persona CLI or persona: YAML (both resolve to pack name)
  if (packName) {
    const packPath = resolve(PERSONAS_DIR, `${packName}.md`);
    try {
      const raw = await readFile(packPath, "utf-8");
      const { content, model } = parsePersonaFrontmatter(raw);

      // Warn if repo override exists but is being ignored
      if (repoOverridePath) {
        try {
          await readFile(repoOverridePath, "utf-8");
          logger?.warn(
            `Using --persona ${packName} (repo override at ${repoOverridePath} ignored)`,
          );
        } catch {
          // Repo override doesn't exist — no warning needed
        }
      }

      return { content, source: `pack:${packName}`, model };
    } catch {
      // Unknown persona — list available packs
      const available = await discoverPersonas();
      throw new Error(
        `Unknown persona "${packName}". Available: ${available.join(", ")}`,
      );
    }
  }

  // Level 3: persona_path: YAML config → load custom file path
  if (customPath) {
    try {
      const raw = await readFile(customPath, "utf-8");
      const { content, model } = parsePersonaFrontmatter(raw);
      return { content, source: `custom:${customPath}`, model };
    } catch {
      throw new Error(`Persona file not found at custom path: "${customPath}".`);
    }
  }

  // Level 4: Repo-level override (grimoires/bridgebuilder/BEAUVOIR.md)
  if (repoOverridePath) {
    try {
      const raw = await readFile(repoOverridePath, "utf-8");
      const { content, model } = parsePersonaFrontmatter(raw);
      return { content, source: `repo:${repoOverridePath}`, model };
    } catch {
      // Fall through to default
    }
  }

  // Level 5: Built-in default persona
  const defaultPath = resolve(PERSONAS_DIR, "default.md");
  try {
    const raw = await readFile(defaultPath, "utf-8");
    const { content, model } = parsePersonaFrontmatter(raw);
    return { content, source: "pack:default", model };
  } catch {
    // Fallback to legacy BEAUVOIR.md next to main.ts
    const legacyPath = resolve(__dirname, "BEAUVOIR.md");
    try {
      const raw = await readFile(legacyPath, "utf-8");
      const { content, model } = parsePersonaFrontmatter(raw);
      return { content, source: `legacy:${legacyPath}`, model };
    } catch {
      throw new Error(
        `No persona found. Expected at "${defaultPath}" or "${legacyPath}".`,
      );
    }
  }
}

function printSummary(summary: RunSummary): void {
  // Build skip reason distribution
  const skipReasons: Record<string, number> = {};
  for (const r of summary.results) {
    if (r.skipReason) {
      skipReasons[r.skipReason] = (skipReasons[r.skipReason] ?? 0) + 1;
    }
  }

  // Build error code distribution
  const errorCodes: Record<string, number> = {};
  for (const r of summary.results) {
    if (r.error) {
      errorCodes[r.error.code] = (errorCodes[r.error.code] ?? 0) + 1;
    }
  }

  console.log(
    JSON.stringify(
      {
        runId: summary.runId,
        reviewed: summary.reviewed,
        skipped: summary.skipped,
        errors: summary.errors,
        startTime: summary.startTime,
        endTime: summary.endTime,
        ...(Object.keys(skipReasons).length > 0 ? { skipReasons } : {}),
        ...(Object.keys(errorCodes).length > 0 ? { errorCodes } : {}),
      },
      null,
      2,
    ),
  );
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);

  // --help flag
  if (argv.includes("--help") || argv.includes("-h")) {
    console.log(
      "Usage: bridgebuilder [--dry-run] [--repo owner/repo] [--pr N] [--persona NAME] [--exclude PATTERN]",
    );
    console.log("");
    console.log("Options:");
    console.log("  --dry-run                   Run without posting reviews");
    console.log("  --repo owner/repo           Target repository (can be repeated)");
    console.log("  --pr N                      Target specific PR number");
    console.log("  --persona NAME              Use persona pack (see --list-personas)");
    console.log("  --list-personas             List built-in persona packs with titles, then exit");
    console.log("  --show-persona-resolution   Show the 5-level persona cascade (active/shadow/skip), then exit");
    console.log("  --exclude PATTERN           Exclude file pattern (can be repeated, additive)");
    console.log("  --no-auto-detect            Skip auto-detection of current repo");
    console.log("  --force-full-review         Skip incremental review, review all files");
    console.log("  --help, -h                  Show this help");
    process.exit(0);
  }

  // --list-personas: print built-in packs with one-line titles, exit (#396).
  // Runs before config resolution so users don't need valid config to discover.
  if (argv.includes("--list-personas")) {
    const packs = await discoverPersonas();
    if (packs.length === 0) {
      console.error("No persona packs found.");
      process.exit(1);
    }
    console.log("Available persona packs:");
    for (const p of packs) {
      const title = await readPersonaTitle(p);
      console.log(`  ${p.padEnd(14)} ${title}`);
    }
    console.log("");
    console.log("Select one via --persona NAME or config: bridgebuilder.persona: NAME");
    process.exit(0);
  }

  const cliArgs = parseCLIArgs(argv);

  const { config, provenance } = await resolveConfig(cliArgs, {
    BRIDGEBUILDER_REPOS: process.env.BRIDGEBUILDER_REPOS,
    BRIDGEBUILDER_MODEL: process.env.BRIDGEBUILDER_MODEL,
    BRIDGEBUILDER_DRY_RUN: process.env.BRIDGEBUILDER_DRY_RUN,
  });

  // Validate --pr + repos combination
  resolveRepos(config, cliArgs.pr);

  // --show-persona-resolution: trace the 5-level cascade against resolved
  // config and exit without performing a review (#396). Reads config but
  // doesn't invoke APIs or post anywhere — safe diagnostic.
  if (argv.includes("--show-persona-resolution")) {
    const steps = await traceResolution(config);
    console.log(formatResolutionTrace(steps));
    process.exit(0);
  }

  // Log effective config with provenance annotations
  console.error(formatEffectiveConfig(config, provenance));

  // Load persona via 5-level precedence chain
  const personaResult = await loadPersona(config, {
    warn: (msg: string) => console.error(`[bridgebuilder] WARN: ${msg}`),
  });
  const persona = personaResult.content;
  console.error(`[bridgebuilder] Persona: ${personaResult.source}`);

  // Apply persona model override (V3-2): persona model wins unless CLI --model was explicit
  if (personaResult.model && provenance.model !== "cli") {
    config.model = personaResult.model;
    console.error(`[bridgebuilder] Model override: ${personaResult.model} (from persona:${personaResult.source})`);
  }

  // Load multi-model config (Sprint 1: T1.4)
  const multiModelConfig = loadMultiModelConfig();
  if (multiModelConfig.enabled) {
    config.multiModel = multiModelConfig;
    const keyStatus = validateApiKeys(multiModelConfig);
    console.error(
      `[bridgebuilder] Multi-model: ${keyStatus.valid.length} provider(s) available, ` +
      `${keyStatus.missing.length} missing (mode: ${multiModelConfig.api_key_mode})`,
    );
    if (keyStatus.missing.length > 0) {
      console.error(
        `[bridgebuilder] Missing API keys: ${keyStatus.missing.map((m) => `${m.provider} (${m.envVar})`).join(", ")}`,
      );
    }
  }

  // Create adapters
  const apiKey = process.env.ANTHROPIC_API_KEY ?? "";
  const adapters = createLocalAdapters(config, apiKey);

  // Wire pipeline
  const template = new PRReviewTemplate(
    adapters.git,
    adapters.hasher,
    config,
  );
  const context = new BridgebuilderContext(adapters.contextStore);
  const pipeline = new ReviewPipeline(
    template,
    context,
    adapters.git,
    adapters.poster,
    adapters.llm,
    adapters.sanitizer,
    adapters.logger,
    persona,
    config,
  );

  // Run — structured ID: bridgebuilder-YYYYMMDDTHHMMSS-hex4 (sortable + unique)
  const now = new Date();
  const ts = now.toISOString().replace(/[-:]/g, "").replace(/\.\d+Z$/, "");
  const hex = Math.random().toString(16).slice(2, 6);
  const runId = `bridgebuilder-${ts}-${hex}`;

  // Multi-model routing: dispatch to multi-model pipeline when enabled (Fix #1)
  if (config.multiModel?.enabled) {
    // Progress reporter (Fix #3)
    const progress = new ProgressReporter({
      verbose: config.multiModel.progress.verbose,
    });
    progress.start();

    for (const entry of config.multiModel.models) {
      progress.registerModel(entry.provider, entry.model_id);
    }

    progress.setPhase("review");

    // A5 (#464): load lore entries once per run when active weaving is enabled.
    // Loader degrades gracefully — missing file → [] + warning log, never throws
    // on an absent or empty patterns.yaml.
    let loreEntries: LoreEntry[] = [];
    const loreActiveWeaving = config.multiModel.depth?.lore_active_weaving === true;
    if (loreActiveWeaving) {
      const lorePath = config.multiModel.depth?.lore_path ?? DEFAULT_LORE_PATH;
      try {
        loreEntries = await loadLoreEntries(lorePath, adapters.logger);
        adapters.logger.info(
          `[bridgebuilder] Loaded ${loreEntries.length} lore entries from ${lorePath}`,
        );
      } catch (err) {
        // Throwing only happens on truly unexpected conditions (yq fail with
        // a non-empty file). Log and continue with no lore — review proceeds.
        adapters.logger.warn(
          `[bridgebuilder] Lore loading failed: ${err instanceof Error ? err.message : String(err)} — continuing without lore`,
        );
      }
    }

    // Resolve review items then execute multi-model review for each
    const items = await template.resolveItems();

    // A4 (#464): pre-resolve manual cross-repo refs once per run.
    // Bridgebuilder pass-1 FIND-002: also pre-FETCH manual refs once per run
    // since they're loop-invariant. Previously a run with N PRs and M manual
    // refs made N×M redundant network calls. Auto-detected refs still vary
    // per-item and are fetched inside the loop.
    const manualRefsRaw = config.multiModel.cross_repo?.manual_refs ?? [];
    const manualRefs = manualRefsRaw.length > 0 ? parseManualRefs(manualRefsRaw) : [];
    const autoDetectEnabled = config.multiModel.cross_repo?.auto_detect === true;

    let manualRefContext: Awaited<ReturnType<typeof fetchCrossRepoContext>> | null = null;
    if (manualRefs.length > 0) {
      const manualFetchStart = Date.now();
      manualRefContext = await fetchCrossRepoContext(manualRefs, adapters.logger);
      adapters.logger.info(
        `[bridgebuilder] cross-repo (manual, hoisted): fetched ${manualRefContext.context.length}/${manualRefs.length} refs ` +
        `(${manualRefContext.errors.length} errors) in ${Date.now() - manualFetchStart}ms`,
      );
    }

    for (const item of items) {
      // Use convergence prompt so models return findings JSON parseable by
      // extractFindingsFromContent() (bug-20260413-9f9b39).
      // #796 / vision-013 + BB-004: deriveCallConfig is the single chokepoint.
      // BB iter-1 on PR #797 caught a missing call site here; iter-2 caught
      // duplicate spread shape. Centralizing prevents both classes of regression.
      const truncated = truncateFiles(item.files, deriveCallConfig(config, item.pr));
      const systemPrompt = template.buildConvergenceSystemPrompt();

      // A4 (#464): per-item cross-repo wiring. Manual refs were fetched once
      // before the loop (FIND-002 fix); here we only fetch the auto-detected
      // refs (which vary per PR) and merge with the cached manual context.
      let crossRepoSection = "";
      if (autoDetectEnabled || manualRefContext) {
        const currentRepo = `${item.owner}/${item.repo}`;
        // PullRequest carries title but not body in this skill's port type.
        // Auto-detection scans the title (PR titles commonly include refs
        // like "fix(auth): close #123" or "ports forge/x#456 fix").
        const detected = autoDetectEnabled
          ? detectRefs(item.pr.title, currentRepo)
          : [];
        // Dedupe detected against manual to avoid double-fetching the same ref.
        const manualKeys = new Set(
          manualRefs.map((r) => `${r.owner}/${r.repo}#${r.number ?? ""}`),
        );
        const detectedNew = detected.filter(
          (r) => !manualKeys.has(`${r.owner}/${r.repo}#${r.number ?? ""}`),
        );

        let detectedContext: Awaited<ReturnType<typeof fetchCrossRepoContext>> | null = null;
        if (detectedNew.length > 0) {
          const fetchStart = Date.now();
          detectedContext = await fetchCrossRepoContext(detectedNew, adapters.logger);
          adapters.logger.info(
            `[bridgebuilder] cross-repo (auto, per-item): fetched ${detectedContext.context.length}/${detectedNew.length} refs ` +
            `(${detectedContext.errors.length} errors) in ${Date.now() - fetchStart}ms`,
          );
        }

        // Merge cached manual + per-item detected into a single result.
        const merged = {
          refs: [
            ...(manualRefContext?.refs ?? []),
            ...(detectedContext?.refs ?? []),
          ],
          context: [
            ...(manualRefContext?.context ?? []),
            ...(detectedContext?.context ?? []),
          ],
          errors: [
            ...(manualRefContext?.errors ?? []),
            ...(detectedContext?.errors ?? []),
          ],
        };
        if (merged.refs.length > 0) {
          crossRepoSection = renderCrossRepoSection(merged);
        }
      }

      const userPrompt = template.buildConvergenceUserPrompt(item, truncated, crossRepoSection);

      const mmResult = await executeMultiModelReview(
        item,
        systemPrompt,
        userPrompt,
        config,
        { poster: adapters.poster, sanitizer: adapters.sanitizer, logger: adapters.logger },
        // A5 (#464): pass loreEntries through enrichment context. Empty array
        // when active weaving is disabled — template inclusion is gated by
        // depth_5.lore_active_weaving, so passing [] is a safe no-op.
        { template, persona, loreEntries },
      );

      for (const mr of mmResult.modelResults) {
        progress.updateModel(mr.provider, mr.model, {
          phase: mr.error ? "error" : "complete",
          latencyMs: mr.response?.latencyMs,
          inputTokens: mr.response?.inputTokens,
          outputTokens: mr.response?.outputTokens,
        });
      }

      progress.reportScoring({
        total: mmResult.consensus.stats.total_findings,
        highConsensus: mmResult.consensus.stats.high_consensus,
        disputed: mmResult.consensus.stats.disputed,
        blocker: mmResult.consensus.stats.blocker,
      });
    }

    progress.reportComplete(Date.now() - now.getTime(), config.multiModel.models.length);
    progress.stop();

    // Rating prompt — non-blocking, respects timeout (Issue #464 A1)
    if (config.multiModel.rating.enabled) {
      const modelsLabel = config.multiModel.models.map((m) => m.model_id).join(", ");
      const ratingPrompt = buildRatingPrompt(runId, modelsLabel, 1);
      console.error(ratingPrompt);

      try {
        const { score, timedOut } = await readRatingWithTimeout({
          timeoutMs: config.multiModel.rating.timeout_seconds * 1000,
        });
        if (score !== null) {
          const entry = createRatingEntry(runId, 1, modelsLabel, score);
          await storeRating(entry);
          console.error(`[bridgebuilder] Rating stored: ${score}/5`);
        } else if (timedOut) {
          console.error(`[bridgebuilder] Rating prompt timed out after ${config.multiModel.rating.timeout_seconds}s`);
        } else {
          console.error("[bridgebuilder] Rating skipped");
        }
      } catch (err) {
        // Rating must never crash the pipeline — log and continue
        console.error(`[bridgebuilder] Rating capture failed: ${err instanceof Error ? err.message : String(err)}`);
      }
    }

    console.log(JSON.stringify({ runId, mode: "multi-model", items: items.length }, null, 2));
  } else {
    // Single-model path — existing behavior, unchanged
    const summary = await pipeline.run(runId);
    printSummary(summary);

    if (summary.errors > 0) {
      process.exit(1);
    }
  }
}

main().catch((err: unknown) => {
  console.error(
    `[bridgebuilder] Fatal: ${err instanceof Error ? err.message : String(err)}`,
  );
  process.exit(1);
});
