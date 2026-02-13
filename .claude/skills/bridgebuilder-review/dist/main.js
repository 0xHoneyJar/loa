import { readFile, readdir } from "node:fs/promises";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ReviewPipeline, PRReviewTemplate, BridgebuilderContext, } from "./core/index.js";
import { createLocalAdapters } from "./adapters/index.js";
import { parseCLIArgs, resolveConfig, resolveRepos, formatEffectiveConfig, } from "./config.js";
const __dirname = dirname(fileURLToPath(import.meta.url));
/** Persona pack directory relative to this module. */
const PERSONAS_DIR = resolve(__dirname, "personas");
/**
 * Parse optional YAML frontmatter from persona content (V3-2).
 * Returns the model override (if any) and the content without frontmatter.
 */
export function parsePersonaFrontmatter(raw) {
    const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
    if (!match)
        return { content: raw };
    const frontmatter = match[1];
    const content = match[2];
    // Extract model field from frontmatter (simple key: value parsing)
    const modelMatch = frontmatter.match(/^\s*model:\s*(.+?)\s*$/m);
    const model = modelMatch?.[1]?.replace(/^["']|["']$/g, "");
    // Ignore commented-out model lines (# model: ...)
    if (model && model.startsWith("#"))
        return { content };
    return { content, model: model || undefined };
}
/**
 * Discover available persona packs from the personas/ directory.
 * Returns pack names (e.g., ["default", "security", "dx", "architecture", "quick"]).
 */
export async function discoverPersonas() {
    try {
        const files = await readdir(PERSONAS_DIR);
        return files
            .filter((f) => f.endsWith(".md"))
            .map((f) => f.replace(/\.md$/, ""))
            .sort();
    }
    catch {
        return [];
    }
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
export async function loadPersona(config, logger) {
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
                    logger?.warn(`Using --persona ${packName} (repo override at ${repoOverridePath} ignored)`);
                }
                catch {
                    // Repo override doesn't exist — no warning needed
                }
            }
            return { content, source: `pack:${packName}`, model };
        }
        catch {
            // Unknown persona — list available packs
            const available = await discoverPersonas();
            throw new Error(`Unknown persona "${packName}". Available: ${available.join(", ")}`);
        }
    }
    // Level 3: persona_path: YAML config → load custom file path
    if (customPath) {
        try {
            const raw = await readFile(customPath, "utf-8");
            const { content, model } = parsePersonaFrontmatter(raw);
            return { content, source: `custom:${customPath}`, model };
        }
        catch {
            throw new Error(`Persona file not found at custom path: "${customPath}".`);
        }
    }
    // Level 4: Repo-level override (grimoires/bridgebuilder/BEAUVOIR.md)
    if (repoOverridePath) {
        try {
            const raw = await readFile(repoOverridePath, "utf-8");
            const { content, model } = parsePersonaFrontmatter(raw);
            return { content, source: `repo:${repoOverridePath}`, model };
        }
        catch {
            // Fall through to default
        }
    }
    // Level 5: Built-in default persona
    const defaultPath = resolve(PERSONAS_DIR, "default.md");
    try {
        const raw = await readFile(defaultPath, "utf-8");
        const { content, model } = parsePersonaFrontmatter(raw);
        return { content, source: "pack:default", model };
    }
    catch {
        // Fallback to legacy BEAUVOIR.md next to main.ts
        const legacyPath = resolve(__dirname, "BEAUVOIR.md");
        try {
            const raw = await readFile(legacyPath, "utf-8");
            const { content, model } = parsePersonaFrontmatter(raw);
            return { content, source: `legacy:${legacyPath}`, model };
        }
        catch {
            throw new Error(`No persona found. Expected at "${defaultPath}" or "${legacyPath}".`);
        }
    }
}
function printSummary(summary) {
    // Build skip reason distribution
    const skipReasons = {};
    for (const r of summary.results) {
        if (r.skipReason) {
            skipReasons[r.skipReason] = (skipReasons[r.skipReason] ?? 0) + 1;
        }
    }
    // Build error code distribution
    const errorCodes = {};
    for (const r of summary.results) {
        if (r.error) {
            errorCodes[r.error.code] = (errorCodes[r.error.code] ?? 0) + 1;
        }
    }
    console.log(JSON.stringify({
        runId: summary.runId,
        reviewed: summary.reviewed,
        skipped: summary.skipped,
        errors: summary.errors,
        startTime: summary.startTime,
        endTime: summary.endTime,
        ...(Object.keys(skipReasons).length > 0 ? { skipReasons } : {}),
        ...(Object.keys(errorCodes).length > 0 ? { errorCodes } : {}),
    }, null, 2));
}
async function main() {
    const argv = process.argv.slice(2);
    // --help flag
    if (argv.includes("--help") || argv.includes("-h")) {
        console.log("Usage: bridgebuilder [--dry-run] [--repo owner/repo] [--pr N] [--persona NAME] [--exclude PATTERN]");
        console.log("");
        console.log("Options:");
        console.log("  --dry-run            Run without posting reviews");
        console.log("  --repo owner/repo    Target repository (can be repeated)");
        console.log("  --pr N               Target specific PR number");
        console.log("  --persona NAME       Use persona pack (default, security, dx, architecture, quick)");
        console.log("  --exclude PATTERN    Exclude file pattern (can be repeated, additive)");
        console.log("  --no-auto-detect     Skip auto-detection of current repo");
        console.log("  --force-full-review  Skip incremental review, review all files");
        console.log("  --help, -h           Show this help");
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
    // Load persona via 5-level precedence chain
    const personaResult = await loadPersona(config, {
        warn: (msg) => console.error(`[bridgebuilder] WARN: ${msg}`),
    });
    const persona = personaResult.content;
    console.error(`[bridgebuilder] Persona: ${personaResult.source}`);
    // Apply persona model override (V3-2): persona model wins unless CLI --model was explicit
    if (personaResult.model && provenance.model !== "cli") {
        config.model = personaResult.model;
        console.error(`[bridgebuilder] Model override: ${personaResult.model} (from persona:${personaResult.source})`);
    }
    // Create adapters
    const apiKey = process.env.ANTHROPIC_API_KEY ?? "";
    const adapters = createLocalAdapters(config, apiKey);
    // Wire pipeline
    const template = new PRReviewTemplate(adapters.git, adapters.hasher, config);
    const context = new BridgebuilderContext(adapters.contextStore);
    const pipeline = new ReviewPipeline(template, context, adapters.git, adapters.poster, adapters.llm, adapters.sanitizer, adapters.logger, persona, config);
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
main().catch((err) => {
    console.error(`[bridgebuilder] Fatal: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
});
//# sourceMappingURL=main.js.map