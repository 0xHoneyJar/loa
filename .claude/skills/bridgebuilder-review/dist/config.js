import { execFile, execSync } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
import { z } from "zod/v4";
const execFileAsync = promisify(execFile);
/**
 * Zod schema for multi-model configuration (SDD Section 2.7).
 * Validated at startup; all fields have sensible defaults so partial config works.
 */
const ScoringThresholdsSchema = z.object({
    high_consensus: z.number().default(700),
    disputed_delta: z.number().default(300),
    low_value: z.number().default(400),
    blocker: z.number().default(700),
});
export const MultiModelConfigSchema = z.object({
    enabled: z.boolean().default(false),
    models: z.array(z.object({
        provider: z.string(),
        model_id: z.string(),
        role: z.enum(["primary", "reviewer"]).default("reviewer"),
    })).default([]),
    iteration_strategy: z.union([
        z.enum(["every", "final"]),
        z.array(z.number()),
    ]).default("final"),
    api_key_mode: z.enum(["graceful", "strict"]).default("graceful"),
    consensus: z.object({
        enabled: z.boolean().default(true),
        scoring_thresholds: ScoringThresholdsSchema.default(() => ({ high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 })),
    }).default(() => ({ enabled: true, scoring_thresholds: { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 } })),
    token_budget: z.object({
        per_model: z.number().nullable().default(null),
        total: z.number().nullable().default(null),
    }).default(() => ({ per_model: null, total: null })),
    depth: z.object({
        structural_checklist: z.boolean().default(true),
        checklist_min_elements: z.number().default(5),
        permission_to_question: z.boolean().default(true),
        lore_active_weaving: z.boolean().default(true),
    }).default(() => ({ structural_checklist: true, checklist_min_elements: 5, permission_to_question: true, lore_active_weaving: true })),
    cross_repo: z.object({
        auto_detect: z.boolean().default(true),
        manual_refs: z.array(z.string()).default([]),
    }).default(() => ({ auto_detect: true, manual_refs: [] })),
    rating: z.object({
        enabled: z.boolean().default(true),
        timeout_seconds: z.number().default(60),
        retrospective_command: z.boolean().default(true),
    }).default(() => ({ enabled: true, timeout_seconds: 60, retrospective_command: true })),
    progress: z.object({
        verbose: z.boolean().default(true),
    }).default(() => ({ verbose: true })),
    max_concurrency: z.number().optional(),
    cost_rates: z.record(z.string(), z.object({
        input: z.number(),
        output: z.number(),
    })).optional(),
});
/**
 * Load multi-model configuration from .loa.config.yaml using yq CLI (SDD Section 2.7).
 * Falls back to defaults (enabled: false) if yq is missing or config absent.
 */
export function loadMultiModelConfig() {
    try {
        // Check if yq is available
        try {
            execSync("command -v yq", { encoding: "utf8", timeout: 2000, stdio: "pipe" });
        }
        catch {
            // Check if multi_model config exists in the file (simple grep)
            try {
                const content = execSync("grep -c 'multi_model:' .loa.config.yaml 2>/dev/null || echo 0", {
                    encoding: "utf8",
                    timeout: 2000,
                    stdio: "pipe",
                }).trim();
                if (parseInt(content, 10) > 0) {
                    console.error("[bridgebuilder] Multi-model config detected but yq is not installed. " +
                        "Install with: brew install yq (macOS) or snap install yq (Linux). " +
                        "Falling back to single-model mode.");
                }
            }
            catch {
                // Ignore grep errors
            }
            return MultiModelConfigSchema.parse({});
        }
        const result = execSync('yq eval ".run_bridge.bridgebuilder.multi_model" .loa.config.yaml -o json', { encoding: "utf8", timeout: 5000, stdio: "pipe" });
        if (!result || result.trim() === "null" || result.trim() === "") {
            return MultiModelConfigSchema.parse({});
        }
        return MultiModelConfigSchema.parse(JSON.parse(result));
    }
    catch (err) {
        // On any error, return safe defaults (disabled)
        if (err instanceof z.ZodError) {
            console.error(`[bridgebuilder] Invalid multi_model config: ${err.issues.map((i) => i.message).join(", ")}. Using defaults.`);
        }
        return MultiModelConfigSchema.parse({});
    }
}
/** Environment variable to API key mapping for multi-model providers. */
export const PROVIDER_API_KEY_ENV = {
    anthropic: "ANTHROPIC_API_KEY",
    openai: "OPENAI_API_KEY",
    google: "GOOGLE_API_KEY",
};
/**
 * Validate API keys for configured multi-model providers.
 * Returns available and missing provider lists.
 */
export function validateApiKeys(config) {
    const valid = [];
    const missing = [];
    for (const model of config.models) {
        const envVar = PROVIDER_API_KEY_ENV[model.provider];
        if (!envVar) {
            missing.push({ provider: model.provider, envVar: `Unknown provider: ${model.provider}` });
            continue;
        }
        if (process.env[envVar]) {
            valid.push({ provider: model.provider, modelId: model.model_id });
        }
        else {
            missing.push({ provider: model.provider, envVar });
        }
    }
    return { valid, missing };
}
/** Built-in defaults per PRD FR-4 (lowest priority). */
const DEFAULTS = {
    repos: [],
    model: "claude-opus-4-7",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 512_000,
    maxInputTokens: 128_000,
    maxOutputTokens: 16_000,
    dimensions: ["security", "quality", "test-coverage"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "grimoires/bridgebuilder/BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default",
    maxRuntimeMinutes: 30,
    reviewMode: "two-pass",
};
/**
 * Parse CLI arguments from process.argv.
 */
export function parseCLIArgs(argv) {
    const args = {};
    for (let i = 0; i < argv.length; i++) {
        const arg = argv[i];
        if (arg === "--dry-run") {
            args.dryRun = true;
        }
        else if (arg === "--no-auto-detect") {
            args.noAutoDetect = true;
        }
        else if (arg === "--repo" && i + 1 < argv.length) {
            args.repos = args.repos ?? [];
            args.repos.push(argv[++i]);
        }
        else if (arg === "--pr" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --pr value: ${argv[i]}. Must be a positive integer.`);
            }
            args.pr = n;
        }
        else if (arg === "--max-input-tokens" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-input-tokens value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxInputTokens = n;
        }
        else if (arg === "--max-output-tokens" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-output-tokens value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxOutputTokens = n;
        }
        else if (arg === "--max-diff-bytes" && i + 1 < argv.length) {
            const n = Number(argv[++i]);
            if (isNaN(n) || n <= 0) {
                throw new Error(`Invalid --max-diff-bytes value: ${argv[i]}. Must be a positive integer.`);
            }
            args.maxDiffBytes = n;
        }
        else if (arg === "--model" && i + 1 < argv.length) {
            args.model = argv[++i];
        }
        else if (arg === "--persona" && i + 1 < argv.length) {
            args.persona = argv[++i];
        }
        else if (arg === "--exclude" && i + 1 < argv.length) {
            args.exclude = args.exclude ?? [];
            args.exclude.push(argv[++i]);
        }
        else if (arg === "--force-full-review") {
            args.forceFullReview = true;
        }
        else if (arg === "--repo-root" && i + 1 < argv.length) {
            args.repoRoot = argv[++i];
        }
        else if (arg === "--review-mode" && i + 1 < argv.length) {
            const mode = argv[++i];
            if (mode !== "two-pass" && mode !== "single-pass") {
                throw new Error(`Invalid --review-mode value: ${mode}. Must be "two-pass" or "single-pass".`);
            }
            args.reviewMode = mode;
        }
    }
    return args;
}
/**
 * Auto-detect owner/repo from git remote -v.
 */
async function autoDetectRepo() {
    try {
        const { stdout } = await execFileAsync("git", ["remote", "-v"], {
            timeout: 5_000,
        });
        const lines = stdout.split("\n");
        const ghPattern = /(?:github\.com)[:/]([^/\s]+)\/([^/\s.]+?)(?:\.git)?\s/;
        // Prefer "origin" remote — avoids picking framework remote alphabetically (#395)
        const originLine = lines.find((l) => l.startsWith("origin\t") && l.includes("(fetch)"));
        const targetLine = originLine ?? lines.find((l) => l.includes("(fetch)"));
        const match = targetLine?.match(ghPattern);
        if (match) {
            return { owner: match[1], repo: match[2] };
        }
        return null;
    }
    catch {
        return null;
    }
}
/**
 * Parse "owner/repo" string into components.
 */
function parseRepoString(s) {
    const parts = s.split("/");
    if (parts.length !== 2 || !parts[0] || !parts[1]) {
        throw new Error(`Invalid repo format: "${s}". Expected "owner/repo".`);
    }
    return { owner: parts[0], repo: parts[1] };
}
// Decision: Pure regex YAML parser over yaml/js-yaml library.
// Zero runtime dependencies is a hard constraint for this skill (PRD NFR-1).
// The config surface is flat key:value pairs + simple lists — no anchors, aliases,
// multi-line strings, or nested objects needed. A full YAML parser (~50KB min)
// would add attack surface and supply chain risk for features we don't use.
// If nested config objects are ever needed, swap to js-yaml behind this function.
/**
 * Load YAML config from .loa.config.yaml if it exists.
 * Uses a simple key:value parser — no YAML library dependency.
 * Supports scalar values and YAML list syntax (- item).
 */
export async function loadYamlConfig() {
    try {
        const content = await readFile(".loa.config.yaml", "utf-8");
        // Find bridgebuilder section
        const match = content.match(/^bridgebuilder:\s*\n((?:[ \t]+.+\n?)*)/m);
        if (!match)
            return {};
        const section = match[1];
        const config = {};
        const lines = section.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const kv = lines[i].match(/^\s+([\w_]+):\s*(.*)/);
            if (!kv)
                continue;
            const [, key, rawValue] = kv;
            const value = rawValue.replace(/#.*$/, "").trim().replace(/^["']|["']$/g, "");
            // Check if next lines are YAML list items (- value)
            if (value === "" || value === undefined) {
                const items = [];
                while (i + 1 < lines.length) {
                    const listItem = lines[i + 1].match(/^\s+-\s+(.+)/);
                    if (!listItem)
                        break;
                    items.push(listItem[1].replace(/#.*$/, "").trim().replace(/^["']|["']$/g, ""));
                    i++;
                }
                if (items.length > 0) {
                    switch (key) {
                        case "repos":
                            config.repos = items;
                            break;
                        case "dimensions":
                            config.dimensions = items;
                            break;
                        case "exclude_patterns":
                            config.exclude_patterns = items;
                            break;
                    }
                    continue;
                }
            }
            switch (key) {
                case "enabled":
                    config.enabled = value === "true";
                    break;
                case "model":
                    config.model = value;
                    break;
                case "max_prs":
                    config.max_prs = Number(value);
                    break;
                case "max_files_per_pr":
                    config.max_files_per_pr = Number(value);
                    break;
                case "max_diff_bytes":
                    config.max_diff_bytes = Number(value);
                    break;
                case "max_input_tokens":
                    config.max_input_tokens = Number(value);
                    break;
                case "max_output_tokens":
                    config.max_output_tokens = Number(value);
                    break;
                case "review_marker":
                    config.review_marker = value;
                    break;
                case "persona_path":
                    config.persona_path = value;
                    break;
                case "sanitizer_mode":
                    if (value === "default" || value === "strict") {
                        config.sanitizer_mode = value;
                    }
                    break;
                case "max_runtime_minutes":
                    config.max_runtime_minutes = Number(value);
                    break;
                case "loa_aware":
                    config.loa_aware = value === "true";
                    break;
                case "persona":
                    config.persona = value;
                    break;
                case "review_mode":
                    if (value === "two-pass" || value === "single-pass") {
                        config.review_mode = value;
                    }
                    break;
                case "ecosystem_context_path":
                    config.ecosystem_context_path = value;
                    break;
                case "pass1_cache_enabled":
                    config.pass1_cache_enabled = value === "true";
                    break;
            }
        }
        return config;
    }
    catch {
        return {};
    }
}
/**
 * Resolve repoRoot: CLI > env > git auto-detect > undefined.
 * Called once per resolveConfig() invocation (Bug 3 fix — issue #309).
 *
 * Note: uses execSync intentionally (not execFile/await) because this is called
 * once at startup and the calling chain (resolveConfig → truncateFiles) is the
 * only consumer. Matches the sync I/O precedent in truncation.ts:215.
 */
export function resolveRepoRoot(cli, env) {
    if (cli.repoRoot)
        return cli.repoRoot;
    if (env.BRIDGEBUILDER_REPO_ROOT)
        return env.BRIDGEBUILDER_REPO_ROOT;
    try {
        return execSync("git rev-parse --show-toplevel", {
            encoding: "utf-8",
            timeout: 5_000,
            stdio: ["pipe", "pipe", "pipe"],
        }).trim();
    }
    catch {
        return undefined;
    }
}
/**
 * Resolve pass1Cache.enabled: env > yaml > default (false).
 * Returns boolean or null if no explicit config.
 */
function resolvePass1Cache(_cliArgs, env, yaml) {
    if (env.BRIDGEBUILDER_PASS1_CACHE === "true")
        return true;
    if (env.BRIDGEBUILDER_PASS1_CACHE === "false")
        return false;
    if (yaml.pass1_cache_enabled != null)
        return yaml.pass1_cache_enabled;
    return null;
}
/**
 * Resolve config using 5-level precedence: CLI > env > yaml > auto-detect > defaults.
 * Returns config and provenance (where each key value came from).
 */
export async function resolveConfig(cliArgs, env, yamlConfig) {
    const yaml = yamlConfig ?? (await loadYamlConfig());
    // Check enabled flag from YAML
    if (yaml.enabled === false) {
        throw new Error("Bridgebuilder is disabled in .loa.config.yaml. Set bridgebuilder.enabled: true to enable.");
    }
    // Build repos list: first-non-empty-wins (CLI > env > yaml > auto-detect)
    let repos = [];
    let reposSource = "default";
    // CLI --repo flags (highest priority)
    if (cliArgs.repos?.length) {
        for (const r of cliArgs.repos) {
            repos.push(parseRepoString(r));
        }
        reposSource = "cli";
    }
    // Env BRIDGEBUILDER_REPOS (comma-separated) — only if CLI didn't set repos
    if (repos.length === 0 && env.BRIDGEBUILDER_REPOS) {
        for (const r of env.BRIDGEBUILDER_REPOS.split(",")) {
            const trimmed = r.trim();
            if (trimmed)
                repos.push(parseRepoString(trimmed));
        }
        if (repos.length > 0)
            reposSource = "env";
    }
    // YAML repos — only if no higher-priority source set repos
    if (repos.length === 0 && yaml.repos?.length) {
        for (const r of yaml.repos) {
            repos.push(parseRepoString(r));
        }
        reposSource = "yaml";
    }
    // Auto-detect (unless --no-auto-detect) — only if no explicit repos configured
    if (repos.length === 0 && !cliArgs.noAutoDetect) {
        const detected = await autoDetectRepo();
        if (detected) {
            repos.push(detected);
            reposSource = "auto-detect";
        }
    }
    if (repos.length === 0) {
        throw new Error("No repos configured. Use --repo owner/repo, set BRIDGEBUILDER_REPOS, or run from a git repo.");
    }
    // Track model provenance (CLI > env > yaml > default)
    const modelSource = cliArgs.model
        ? "cli"
        : env.BRIDGEBUILDER_MODEL
            ? "env"
            : yaml.model
                ? "yaml"
                : "default";
    // Track dryRun provenance
    const dryRunSource = cliArgs.dryRun != null
        ? "cli"
        : env.BRIDGEBUILDER_DRY_RUN === "true"
            ? "env"
            : "default";
    // Track token/size provenance
    const maxInputTokensSource = cliArgs.maxInputTokens != null
        ? "cli"
        : yaml.max_input_tokens != null
            ? "yaml"
            : "default";
    const maxOutputTokensSource = cliArgs.maxOutputTokens != null
        ? "cli"
        : yaml.max_output_tokens != null
            ? "yaml"
            : "default";
    const maxDiffBytesSource = cliArgs.maxDiffBytes != null
        ? "cli"
        : yaml.max_diff_bytes != null
            ? "yaml"
            : "default";
    // Resolve repoRoot: CLI > env > git auto-detect (Bug 3 fix — issue #309)
    const repoRoot = resolveRepoRoot(cliArgs, env);
    // Resolve remaining fields: CLI > env > yaml > defaults
    const config = {
        repos,
        repoRoot,
        model: cliArgs.model ?? env.BRIDGEBUILDER_MODEL ?? yaml.model ?? DEFAULTS.model,
        maxPrs: yaml.max_prs ?? DEFAULTS.maxPrs,
        maxFilesPerPr: yaml.max_files_per_pr ?? DEFAULTS.maxFilesPerPr,
        maxDiffBytes: cliArgs.maxDiffBytes ?? yaml.max_diff_bytes ?? DEFAULTS.maxDiffBytes,
        maxInputTokens: cliArgs.maxInputTokens ?? yaml.max_input_tokens ?? DEFAULTS.maxInputTokens,
        maxOutputTokens: cliArgs.maxOutputTokens ?? yaml.max_output_tokens ?? DEFAULTS.maxOutputTokens,
        dimensions: yaml.dimensions ?? DEFAULTS.dimensions,
        reviewMarker: yaml.review_marker ?? DEFAULTS.reviewMarker,
        repoOverridePath: yaml.persona_path ?? DEFAULTS.repoOverridePath,
        dryRun: cliArgs.dryRun ??
            (env.BRIDGEBUILDER_DRY_RUN === "true" ? true : undefined) ??
            DEFAULTS.dryRun,
        excludePatterns: [
            ...(yaml.exclude_patterns ?? []),
            ...(cliArgs.exclude ?? []),
        ],
        sanitizerMode: yaml.sanitizer_mode ?? DEFAULTS.sanitizerMode,
        maxRuntimeMinutes: yaml.max_runtime_minutes ?? DEFAULTS.maxRuntimeMinutes,
        ...(cliArgs.pr != null ? { targetPr: cliArgs.pr } : {}),
        ...(yaml.loa_aware != null ? { loaAware: yaml.loa_aware } : {}),
        ...(cliArgs.persona != null || yaml.persona != null
            ? { persona: cliArgs.persona ?? yaml.persona }
            : {}),
        ...(yaml.persona_path != null
            ? { personaFilePath: yaml.persona_path }
            : {}),
        ...(cliArgs.forceFullReview ? { forceFullReview: true } : {}),
        ...(yaml.ecosystem_context_path != null
            ? { ecosystemContextPath: yaml.ecosystem_context_path }
            : {}),
        ...(resolvePass1Cache(cliArgs, env, yaml) != null
            ? { pass1Cache: { enabled: resolvePass1Cache(cliArgs, env, yaml) } }
            : {}),
        reviewMode: cliArgs.reviewMode ??
            (env.LOA_BRIDGE_REVIEW_MODE === "two-pass" || env.LOA_BRIDGE_REVIEW_MODE === "single-pass"
                ? env.LOA_BRIDGE_REVIEW_MODE
                : undefined) ??
            yaml.review_mode ??
            DEFAULTS.reviewMode,
    };
    // Track reviewMode provenance
    const reviewModeSource = cliArgs.reviewMode
        ? "cli"
        : env.LOA_BRIDGE_REVIEW_MODE === "two-pass" || env.LOA_BRIDGE_REVIEW_MODE === "single-pass"
            ? "env"
            : yaml.review_mode
                ? "yaml"
                : "default";
    const provenance = {
        repos: reposSource,
        model: modelSource,
        dryRun: dryRunSource,
        maxInputTokens: maxInputTokensSource,
        maxOutputTokens: maxOutputTokensSource,
        maxDiffBytes: maxDiffBytesSource,
        reviewMode: reviewModeSource,
    };
    return { config, provenance };
}
/**
 * Validate --pr flag: requires exactly one repo (IMP-008).
 */
export function resolveRepos(config, prNumber) {
    if (prNumber != null && config.repos.length > 1) {
        throw new Error(`--pr ${prNumber} specified but ${config.repos.length} repos configured. ` +
            "Use --repo owner/repo to target a single repo when using --pr.");
    }
    return config.repos;
}
/**
 * Format effective config for logging (secrets redacted).
 * Includes provenance annotations showing where each value originated.
 */
export function formatEffectiveConfig(config, provenance) {
    const repoNames = config.repos
        .map((r) => `${r.owner}/${r.repo}`)
        .join(", ");
    const p = provenance;
    const repoSrc = p ? ` (${p.repos})` : "";
    const modelSrc = p ? ` (${p.model})` : "";
    const drySrc = p ? ` (${p.dryRun})` : "";
    const prFilter = config.targetPr != null ? `, target_pr=#${config.targetPr}` : "";
    const inputSrc = p ? ` (${p.maxInputTokens})` : "";
    const outputSrc = p ? ` (${p.maxOutputTokens})` : "";
    const diffSrc = p ? ` (${p.maxDiffBytes})` : "";
    const personaInfo = config.persona ? `, persona=${config.persona}` : "";
    const excludeInfo = config.excludePatterns.length > 0
        ? `, exclude_patterns=[${config.excludePatterns.join(", ")}]`
        : "";
    return (`[bridgebuilder] Config: repos=[${repoNames}]${repoSrc}, ` +
        `model=${config.model}${modelSrc}, max_prs=${config.maxPrs}, ` +
        `max_input_tokens=${config.maxInputTokens}${inputSrc}, ` +
        `max_output_tokens=${config.maxOutputTokens}${outputSrc}, ` +
        `max_diff_bytes=${config.maxDiffBytes}${diffSrc}, ` +
        `dry_run=${config.dryRun}${drySrc}, sanitizer_mode=${config.sanitizerMode}${prFilter}` +
        `${personaInfo}${excludeInfo}` +
        `, review_mode=${config.reviewMode}${p ? ` (${p.reviewMode})` : ""}`);
}
//# sourceMappingURL=config.js.map