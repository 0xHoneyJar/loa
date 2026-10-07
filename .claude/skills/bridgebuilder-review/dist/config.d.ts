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
        allowed_owners: z.ZodDefault<z.ZodArray<z.ZodString>>;
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
/** A `*-headless` model id: a kind:cli alias, whose CLI hop needs no API key in BB's environment. */
export declare function isHeadlessModelId(modelId: string, provider?: string): boolean;
/** cycle-127 FR-1: the agy (Antigravity) route's opt-in and the headless mode that decides whether a google voice routes to it. */
export interface AgyGate {
    optIn: boolean;
    mode: string;
    /** The config could not be read (yq missing, unparsable YAML): the gate failed closed for this reason (r251-1 G14). */
    readError?: string;
    /** `agy_opt_in` is present but not written exactly `true` / `false` (the string "true", `True`, `yes` …): it reads off,
     * said once (r251-1 G12, r251-2 K1 — the bash and Python readers apply the same strict rule). */
    typeWarning?: string;
}
/** The Loa config the agy gate reads: the repo root's when one is known, else the cwd's (r251-1 G15 — one path for all callers). */
export declare function loaConfigPathFor(repoRoot?: string): string;
/** The go-yq "is the key present" program — the same text as the bash lib's `_AGY_YQ_HAS` and the Python loader's
 * `_YQ_HAS` (r251-4 S3): every level a real mapping (`kind` is "alias" for an alias node) and the explicit key only (`has`
 * never sees a merge key's). */
export declare const AGY_YQ_HAS = ".hounfour | (kind == \"map\" and (.headless | (kind == \"map\" and has(\"agy_opt_in\"))))";
/**
 * Why the file's group is not its owner's USER-PRIVATE group, or undefined when it is (review r251-6 V1, BB #1). ONE rule with
 * cheval's `loader._not_private_group` and the bash lib's `_agy_group_not_private`: the file's gid is the owner's primary gid,
 * the group is NAMED for the owner (a shared `users` / macOS `staff` fails — their member lists are empty for primary members,
 * so emptiness alone never proved privacy: audit LOW-001), no account but the owner is a listed member, no other account has
 * it as its primary group (enumerated last), and no ACL makes the group bits a mask over named grants (`ls -ldL`'s `+`, on
 * the read's own descriptor when one is given). Accounts come from `getent`; a host without it, or one that cannot answer,
 * is no proof: not private.
 */
export declare function agyGroupNotPrivate(uid: number, gid: number, fd?: number, configPath?: string): string | undefined;
/**
 * Why the opt-in config is not the current user's alone to write, or undefined when it is (review r251-5 U1/U2, r251-6 V1):
 * ONE permission rule with cheval's `loader._config_untrusted_reason` and the bash lib's `_agy_config_untrusted` — owned by
 * the current user, never world-writable, and group-writable only for the owner's user-private group (`agyGroupNotPrivate`;
 * Ubuntu's umask 002 makes every checkout 0664). `st` / `fd` are the read's own open file (r251-6 V3, BB #2: the bytes read
 * and the inode judged are one); without them `statSync` follows a symlink: the target decides, as in the other readers. A
 * config that cannot be stat'ed is untrusted (fail closed). Where the platform has no uid (`process.getuid` absent), the
 * owner half is skipped.
 */
export declare function agyConfigUntrustedReason(configPath: string, st?: {
    uid: number;
    gid: number;
    mode: number;
}, fd?: number): string | undefined;
/**
 * Read `hounfour.headless.agy_opt_in` (true only for a YAML boolean true) and `hounfour.headless.mode` from the Loa config
 * with one yq call. LOA_HEADLESS_MODE wins for the mode, as it does in cheval; nothing in the environment opts in. A missing
 * file reads as off; a missing yq or an unreadable config reads as off too (the gate fails closed) and carries `readError`.
 */
export declare function readAgyGate(configPath: string): AgyGate;
/** The ancestors' kind and tag (r251-6 V5): `hounfour`, and `hounfour.headless` only below a real mapping. */
export declare const AGY_YQ_ANCESTORS = "\"k1\": (.hounfour | kind), \"t1\": (.hounfour | tag), \"k2\": ((.hounfour | select(kind == \"map\") | .headless | kind) // \"\"), \"t2\": ((.hounfour | select(kind == \"map\") | .headless | tag) // \"\")";
/**
 * A voice cheval would dispatch through agy: a google headless id of the generated registry (today `gemini-headless`), or
 * any google model when the effective headless mode is cli-only (the bash/Python predicate's shape — lib/agy-gate-lib.sh).
 */
export declare function isAgyRouted(provider: string, modelId: string, mode: string): boolean;
/**
 * Validate API keys for configured multi-model providers.
 * Returns available and missing provider lists, and the voices not planned because their agy route's opt-in is off
 * (cycle-127 FR-1: neither valid nor missing — a voice that cannot exist on this host is never counted as a failed one).
 */
export declare function validateApiKeys(config: MultiModelConfig, gate: AgyGate): {
    valid: Array<{
        provider: string;
        modelId: string;
    }>;
    missing: Array<{
        provider: string;
        envVar: string;
    }>;
    notPlanned: Array<{
        provider: string;
        modelId: string;
        reason: "opt_in_required";
    }>;
};
/**
 * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
 * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
 * per review.
 */
export declare function agyGateStartupLines(gate: AgyGate, keyStatus: ReturnType<typeof validateApiKeys>): string[];
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