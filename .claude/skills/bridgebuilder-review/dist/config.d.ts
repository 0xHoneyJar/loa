import { z } from "zod/v4";
import type { BridgebuilderConfig, MultiModelConfig } from "./core/types.js";
export declare const MultiModelConfigSchema: z.ZodObject<{
    enabled: z.ZodDefault<z.ZodBoolean>;
    models: z.ZodDefault<z.ZodArray<z.ZodObject<{
        provider: z.ZodString;
        model_id: z.ZodString;
        role: z.ZodDefault<z.ZodEnum<{
            primary: "primary";
            reviewer: "reviewer";
        }>>;
    }, z.core.$strip>>>;
    iteration_strategy: z.ZodDefault<z.ZodUnion<readonly [z.ZodEnum<{
        every: "every";
        final: "final";
    }>, z.ZodArray<z.ZodNumber>]>>;
    api_key_mode: z.ZodDefault<z.ZodEnum<{
        strict: "strict";
        graceful: "graceful";
    }>>;
    consensus: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        scoring_thresholds: z.ZodDefault<z.ZodObject<{
            high_consensus: z.ZodDefault<z.ZodNumber>;
            disputed_delta: z.ZodDefault<z.ZodNumber>;
            low_value: z.ZodDefault<z.ZodNumber>;
            blocker: z.ZodDefault<z.ZodNumber>;
        }, z.core.$strip>>;
    }, z.core.$strip>>;
    token_budget: z.ZodDefault<z.ZodObject<{
        per_model: z.ZodDefault<z.ZodNullable<z.ZodNumber>>;
        total: z.ZodDefault<z.ZodNullable<z.ZodNumber>>;
    }, z.core.$strip>>;
    depth: z.ZodDefault<z.ZodObject<{
        structural_checklist: z.ZodDefault<z.ZodBoolean>;
        checklist_min_elements: z.ZodDefault<z.ZodNumber>;
        permission_to_question: z.ZodDefault<z.ZodBoolean>;
        lore_active_weaving: z.ZodDefault<z.ZodBoolean>;
    }, z.core.$strip>>;
    cross_repo: z.ZodDefault<z.ZodObject<{
        auto_detect: z.ZodDefault<z.ZodBoolean>;
        manual_refs: z.ZodDefault<z.ZodArray<z.ZodString>>;
    }, z.core.$strip>>;
    rating: z.ZodDefault<z.ZodObject<{
        enabled: z.ZodDefault<z.ZodBoolean>;
        timeout_seconds: z.ZodDefault<z.ZodNumber>;
        retrospective_command: z.ZodDefault<z.ZodBoolean>;
    }, z.core.$strip>>;
    progress: z.ZodDefault<z.ZodObject<{
        verbose: z.ZodDefault<z.ZodBoolean>;
    }, z.core.$strip>>;
    max_concurrency: z.ZodOptional<z.ZodNumber>;
    cost_rates: z.ZodOptional<z.ZodRecord<z.ZodString, z.ZodObject<{
        input: z.ZodNumber;
        output: z.ZodNumber;
    }, z.core.$strip>>>;
}, z.core.$strip>;
/**
 * Load multi-model configuration from .loa.config.yaml using yq CLI (SDD Section 2.7).
 * Falls back to defaults (enabled: false) if yq is missing or config absent.
 */
export declare function loadMultiModelConfig(): MultiModelConfig;
/** Environment variable to API key mapping for multi-model providers. */
export declare const PROVIDER_API_KEY_ENV: Record<string, string>;
/**
 * Validate API keys for configured multi-model providers.
 * Returns available and missing provider lists.
 */
export declare function validateApiKeys(config: MultiModelConfig): {
    valid: Array<{
        provider: string;
        modelId: string;
    }>;
    missing: Array<{
        provider: string;
        envVar: string;
    }>;
};
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
    ecosystem_context_path?: string;
    pass1_cache_enabled?: boolean;
}
export interface EnvVars {
    BRIDGEBUILDER_REPOS?: string;
    BRIDGEBUILDER_MODEL?: string;
    BRIDGEBUILDER_DRY_RUN?: string;
    BRIDGEBUILDER_REPO_ROOT?: string;
    LOA_BRIDGE_REVIEW_MODE?: string;
    BRIDGEBUILDER_PASS1_CACHE?: string;
}
/**
 * Parse CLI arguments from process.argv.
 */
export declare function parseCLIArgs(argv: string[]): CLIArgs;
/**
 * Load YAML config from .loa.config.yaml if it exists.
 * Uses a simple key:value parser — no YAML library dependency.
 * Supports scalar values and YAML list syntax (- item).
 */
export declare function loadYamlConfig(): Promise<YamlConfig>;
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