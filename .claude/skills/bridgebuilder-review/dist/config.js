import { execFile, execSync } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
const execFileAsync = promisify(execFile);
/** Built-in defaults per PRD FR-4 (lowest priority). */
const DEFAULTS = {
    repos: [],
    model: "claude-opus-4-6",
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
async function loadYamlConfig() {
    try {
        const content = await readFile(".loa.config.yaml", "utf-8");
        // Find bridgebuilder section
        const match = content.match(/^bridgebuilder:\s*\n((?:\s+.+\n?)*)/m);
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