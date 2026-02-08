import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { readFile } from "node:fs/promises";
const execFileAsync = promisify(execFile);
/** Built-in defaults per PRD FR-4 (lowest priority). */
const DEFAULTS = {
    repos: [],
    model: "claude-sonnet-4-5-20250929",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 8_000,
    maxOutputTokens: 4_000,
    dimensions: ["security", "quality", "test-coverage"],
    reviewMarker: "bridgebuilder-review",
    personaPath: "grimoires/bridgebuilder/BEAUVOIR.md",
    dryRun: false,
    excludePatterns: [],
    sanitizerMode: "default",
    maxRuntimeMinutes: 30,
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
        // Match first line: origin	git@github.com:owner/repo.git (fetch)
        // or:               origin	https://github.com/owner/repo.git (fetch)
        const match = stdout.match(/(?:github\.com)[:/]([^/\s]+)\/([^/\s.]+?)(?:\.git)?\s/);
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
/**
 * Load YAML config from .loa.config.yaml if it exists.
 * Uses a simple key:value parser — no YAML library dependency.
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
        // Parse simple key: value pairs
        for (const line of section.split("\n")) {
            const kv = line.match(/^\s+([\w_]+):\s*(.+)/);
            if (!kv)
                continue;
            const [, key, rawValue] = kv;
            const value = rawValue.replace(/#.*$/, "").trim().replace(/^["']|["']$/g, "");
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
            }
        }
        return config;
    }
    catch {
        return {};
    }
}
/**
 * Resolve config using 5-level precedence: CLI > env > yaml > auto-detect > defaults.
 */
export async function resolveConfig(cliArgs, env, yamlConfig) {
    const yaml = yamlConfig ?? (await loadYamlConfig());
    // Check enabled flag from YAML
    if (yaml.enabled === false) {
        throw new Error("Bridgebuilder is disabled in .loa.config.yaml. Set bridgebuilder.enabled: true to enable.");
    }
    // Build repos list: CLI > env > yaml > auto-detect
    const repos = [];
    // CLI --repo flags
    if (cliArgs.repos?.length) {
        for (const r of cliArgs.repos) {
            repos.push(parseRepoString(r));
        }
    }
    // Env BRIDGEBUILDER_REPOS (comma-separated)
    if (env.BRIDGEBUILDER_REPOS) {
        for (const r of env.BRIDGEBUILDER_REPOS.split(",")) {
            const trimmed = r.trim();
            if (trimmed)
                repos.push(parseRepoString(trimmed));
        }
    }
    // YAML repos
    if (yaml.repos?.length) {
        for (const r of yaml.repos) {
            repos.push(parseRepoString(r));
        }
    }
    // Auto-detect (unless --no-auto-detect)
    if (!cliArgs.noAutoDetect) {
        const detected = await autoDetectRepo();
        if (detected) {
            // Only add if not already in list
            const exists = repos.some((r) => r.owner === detected.owner && r.repo === detected.repo);
            if (!exists)
                repos.push(detected);
        }
    }
    if (repos.length === 0) {
        throw new Error("No repos configured. Use --repo owner/repo, set BRIDGEBUILDER_REPOS, or run from a git repo.");
    }
    // Resolve remaining fields: CLI > env > yaml > defaults
    const config = {
        repos,
        model: env.BRIDGEBUILDER_MODEL ?? yaml.model ?? DEFAULTS.model,
        maxPrs: yaml.max_prs ?? DEFAULTS.maxPrs,
        maxFilesPerPr: yaml.max_files_per_pr ?? DEFAULTS.maxFilesPerPr,
        maxDiffBytes: yaml.max_diff_bytes ?? DEFAULTS.maxDiffBytes,
        maxInputTokens: yaml.max_input_tokens ?? DEFAULTS.maxInputTokens,
        maxOutputTokens: yaml.max_output_tokens ?? DEFAULTS.maxOutputTokens,
        dimensions: yaml.dimensions ?? DEFAULTS.dimensions,
        reviewMarker: yaml.review_marker ?? DEFAULTS.reviewMarker,
        personaPath: yaml.persona_path ?? DEFAULTS.personaPath,
        dryRun: cliArgs.dryRun ??
            (env.BRIDGEBUILDER_DRY_RUN === "true" ? true : undefined) ??
            DEFAULTS.dryRun,
        excludePatterns: yaml.exclude_patterns ?? DEFAULTS.excludePatterns,
        sanitizerMode: yaml.sanitizer_mode ?? DEFAULTS.sanitizerMode,
        maxRuntimeMinutes: yaml.max_runtime_minutes ?? DEFAULTS.maxRuntimeMinutes,
    };
    return config;
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
 */
export function formatEffectiveConfig(config) {
    const repoNames = config.repos
        .map((r) => `${r.owner}/${r.repo}`)
        .join(", ");
    return (`[bridgebuilder] Config: repos=[${repoNames}], ` +
        `model=${config.model}, max_prs=${config.maxPrs}, ` +
        `dry_run=${config.dryRun}, sanitizer_mode=${config.sanitizerMode}`);
}
//# sourceMappingURL=config.js.map