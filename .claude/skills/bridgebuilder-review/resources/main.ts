import { readFile } from "node:fs/promises";
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
} from "./config.js";
import type { RunSummary } from "./core/types.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Load persona from precedence chain:
 * 1. grimoires/bridgebuilder/BEAUVOIR.md (project override)
 * 2. resources/BEAUVOIR.md (default shipped with skill)
 */
async function loadPersona(configPath: string): Promise<string> {
  // Try project override first
  try {
    return await readFile(configPath, "utf-8");
  } catch {
    // Fall through to default
  }

  // Try default persona next to main.ts (or in resources/ at build time)
  const defaultPath = resolve(__dirname, "BEAUVOIR.md");
  try {
    return await readFile(defaultPath, "utf-8");
  } catch {
    throw new Error(
      `No persona found. Expected at "${configPath}" or "${defaultPath}".`,
    );
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
      "Usage: bridgebuilder [--dry-run] [--repo owner/repo] [--pr N] [--no-auto-detect]",
    );
    console.log("");
    console.log("Options:");
    console.log("  --dry-run          Run without posting reviews");
    console.log("  --repo owner/repo  Target repository (can be repeated)");
    console.log("  --pr N             Target specific PR number");
    console.log("  --no-auto-detect   Skip auto-detection of current repo");
    console.log("  --help, -h         Show this help");
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

  // Log effective config with provenance annotations
  console.error(formatEffectiveConfig(config, provenance));

  // Load persona
  const persona = await loadPersona(config.personaPath);

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
  const summary = await pipeline.run(runId);

  // Output
  printSummary(summary);

  // Exit code: 1 if any errors occurred
  if (summary.errors > 0) {
    process.exit(1);
  }
}

main().catch((err: unknown) => {
  console.error(
    `[bridgebuilder] Fatal: ${err instanceof Error ? err.message : String(err)}`,
  );
  process.exit(1);
});
