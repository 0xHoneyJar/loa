import type { BridgebuilderConfig } from "./core/types.js";
export interface CLIArgs {
    dryRun?: boolean;
    repos?: string[];
    pr?: number;
    noAutoDetect?: boolean;
    maxInputTokens?: number;
    maxOutputTokens?: number;
    maxDiffBytes?: number;
    model?: string;
    persona?: string;
    exclude?: string[];
    forceFullReview?: boolean;
    repoRoot?: string;
    reviewMode?: "two-pass" | "single-pass";
}
export interface YamlConfig {
    enabled?: boolean;
    repos?: string[];
    model?: string;
    max_prs?: number;
    max_files_per_pr?: number;
    max_diff_bytes?: number;
    max_input_tokens?: number;
    max_output_tokens?: number;
    dimensions?: string[];
    review_marker?: string;
    persona_path?: string;
    exclude_patterns?: string[];
    sanitizer_mode?: "default" | "strict";
    max_runtime_minutes?: number;
    loa_aware?: boolean;
    persona?: string;
    review_mode?: "two-pass" | "single-pass";
}
export interface EnvVars {
    BRIDGEBUILDER_REPOS?: string;
    BRIDGEBUILDER_MODEL?: string;
    BRIDGEBUILDER_DRY_RUN?: string;
    BRIDGEBUILDER_REPO_ROOT?: string;
    LOA_BRIDGE_REVIEW_MODE?: string;
}
/**
 * Parse CLI arguments from process.argv.
 */
export declare function parseCLIArgs(argv: string[]): CLIArgs;
/**
 * Resolve repoRoot: CLI > env > git auto-detect > undefined.
 * Called once per resolveConfig() invocation (Bug 3 fix — issue #309).
 *
 * Note: uses execSync intentionally (not execFile/await) because this is called
 * once at startup and the calling chain (resolveConfig → truncateFiles) is the
 * only consumer. Matches the sync I/O precedent in truncation.ts:215.
 */
export declare function resolveRepoRoot(cli: CLIArgs, env: EnvVars): string | undefined;
/**
 * Resolve config using 5-level precedence: CLI > env > yaml > auto-detect > defaults.
 * Returns config and provenance (where each key value came from).
 */
export declare function resolveConfig(cliArgs: CLIArgs, env: EnvVars, yamlConfig?: YamlConfig): Promise<{
    config: BridgebuilderConfig;
    provenance: ConfigProvenance;
}>;
/**
 * Validate --pr flag: requires exactly one repo (IMP-008).
 */
export declare function resolveRepos(config: BridgebuilderConfig, prNumber?: number): Array<{
    owner: string;
    repo: string;
}>;
export type ConfigSource = "cli" | "env" | "yaml" | "auto-detect" | "default";
export interface ConfigProvenance {
    repos: ConfigSource;
    model: ConfigSource;
    dryRun: ConfigSource;
    maxInputTokens: ConfigSource;
    maxOutputTokens: ConfigSource;
    maxDiffBytes: ConfigSource;
    reviewMode: ConfigSource;
}
/**
 * Format effective config for logging (secrets redacted).
 * Includes provenance annotations showing where each value originated.
 */
export declare function formatEffectiveConfig(config: BridgebuilderConfig, provenance?: ConfigProvenance): string;
//# sourceMappingURL=config.d.ts.map