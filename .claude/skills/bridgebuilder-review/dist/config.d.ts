import { z } from "zod/v4";
import type { BridgebuilderConfig, MultiModelConfig, MultiModelProviderEntry, ProviderDecl, TrustedConfig } from "./core/types.js";
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
export declare function validateApiKeys(config: MultiModelConfig, gate: AgyGate, trusted?: TrustedConfig): {
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
/** The refusal text for a keyless or insecure provider only the PR head declares (D-7.5; tests pin it). */
export declare function headOnlyRefusal(provider: string): string;
/** The locality refusal text — one sentence with the dissent script and Flatline (SDD §4.3, D-8.1). */
export declare function localityRefusal(modelId: string, provider: string): string;
/**
 * The env var holding a provider's credential: the built-in map first, then an `auth: "{env:VAR}"` template from the
 * TRUSTED config (never the head's, so a head cannot point a credential at a provider of its choosing). Undefined when
 * neither names one.
 */
export declare function providerKeyEnv(provider: string, trusted?: TrustedConfig): string | undefined;
/** Default `bridgebuilder.exit_on_degraded` (DEC-0150): exit 3 when the consensus verdict is DEGRADED. */
export declare const DEFAULT_EXIT_ON_DEGRADED = 3;
/**
 * Normalise `hounfour.providers` (any JSON) into declarations. A non-mapping value or an entry that is not a mapping is
 * dropped with a warning — never admitted. D-8.0: `keyless: true` or a literal `auth` (one without `{env:`) is keyless.
 */
export declare function parseProviderDecls(raw: unknown, label: string, warnings: string[]): Record<string, ProviderDecl>;
export interface TrustedView {
    providers: unknown;
    locality: unknown;
    exit: unknown;
    /** cycle-133 C-2: `bridgebuilder.writer_role_allowlist`. */
    writer?: unknown;
    /** `hounfour.aliases` (audit a257-1: resolves fallback aliases; compared for head drift). */
    aliases?: unknown;
    /** `hounfour.secret_env_allowlist` — the list cheval's loader reads (compared for head drift). */
    allowlist?: unknown;
    /** A root-level `secret_env_allowlist` (compared for head drift too: it is the shape the docs once showed). */
    rootAllowlist?: unknown;
    /** sprint-279 review round 1 (HIGH 3): the review-scope keys as the trusted source states them (null = absent). */
    scope?: TrustedReviewScope;
}
/** The four keys that narrow or widen what is reviewed; on a pull request they come from the trusted source. */
export interface TrustedReviewScope {
    protected_paths: unknown;
    exclude_patterns: unknown;
    fetch_missing_patches: unknown;
    max_content_fetches: unknown;
}
/** Parse Loa config text (YAML or JSON) into the trusted view with yq; throws with yq's first stderr line on failure. */
export declare function yqTrustedView(text: string): TrustedView;
/** A branch name safe to place in `refs/remotes/origin/<name>` for `git show` (no option, no `..`, no control chars). */
export declare function isSafeRefName(name: string): boolean;
/** I/O seams for loadTrustedConfig (tests replace them; the defaults touch git, gh, the filesystem and yq). */
export interface TrustedConfigDeps {
    env: Record<string, string | undefined>;
    /** The working tree's `.loa.config.yaml` text, or undefined when the file is absent. */
    readWorkingTree: (path: string) => string | undefined;
    /** True when `ref` names a commit in the repository. */
    refExists: (repoRoot: string | undefined, ref: string) => boolean;
    /** `.loa.config.yaml` at `ref`, or undefined when the ref has no such file. Throws when git cannot answer. */
    gitShow: (repoRoot: string | undefined, ref: string) => string | undefined;
    /** The PR's base branch name from its metadata, or undefined when it cannot be read. */
    prBaseRef: (pr: number, repo: string | undefined) => string | undefined;
    parse: (text: string) => TrustedView;
}
export declare const defaultTrustedConfigDeps: TrustedConfigDeps;
/** True when Bridgebuilder runs on a pull request (D-7.5): `--pr`, a PR event, or a base ref in the environment. */
export declare function isPullRequestContext(pr: number | undefined, env: Record<string, string | undefined>): boolean;
/** The env var a workflow sets from a repository variable to supply trusted config text (YAML or JSON). */
export declare const TRUSTED_CONFIG_ENV = "BRIDGEBUILDER_TRUSTED_CONFIG";
/**
 * Load the trusted configuration (D-7.5, DEC-0170). Precedence:
 *   local (no PR context):  the working tree's `.loa.config.yaml`.
 *   pull request:           `BRIDGEBUILDER_TRUSTED_CONFIG` (repository settings) when set, else `.loa.config.yaml` at
 *                           `refs/remotes/origin/<base>` (base from `GITHUB_BASE_REF`, else the PR metadata), else at
 *                           `refs/remotes/origin/main`; when none can be read, no provider declaration is trusted.
 * The head checkout is read on a pull request to find keyless / insecure declarations the trusted source lacks, which
 * are refused by name, and (audit a257-1 MEDIUM-A2) to compute `headDrift` — the keys cheval would read differently from
 * the checkout than the trusted source says; main.ts refuses the run on any. Throws on an invalid `hounfour.locality` (a posture typo never runs hosted silently).
 */
export declare function loadTrustedConfig(opts: {
    pr?: number;
    repoRoot?: string;
    repo?: string;
}, deps?: TrustedConfigDeps): TrustedConfig & {
    reviewScope?: TrustedReviewScope;
};
/**
 * sprint-279 review round 1 (HIGH 3, bd-i4fyw): on a pull request with a trusted source, `protected_paths`,
 * `exclude_patterns`, `fetch_missing_patches` and `max_content_fetches` come from that source, so a PR cannot widen
 * or narrow its own review (e.g. `protected_paths: []`). A head value whose effect differs is replaced with one WARN
 * naming the key. These keys change review scope, not provider identity, so drift is warned, not refused (no exit
 * 5). `--exclude` stays additive (the operator's argv). Local mode: unchanged. No readable trusted source on a pull
 * request (Bridgebuilder round 1, PR #1302, bd-ous65): the four keys fall to their defaults with one WARN — fail closed,
 * so a shallow checkout cannot be used to widen the PR's own review. main.ts calls this right after `loadTrustedConfig`.
 */
export declare function applyTrustedReviewScope(config: BridgebuilderConfig, trusted: TrustedConfig & {
    reviewScope?: TrustedReviewScope;
}, cli: Pick<CLIArgs, "exclude">, provenance?: Pick<ConfigProvenance, "deferredScopeKeys">): void;
/**
 * cycle-136 FR-5 (sdd.md § 5.6, DEC-1084): the review must not run on a configuration whose head-side scope keys were
 * deferred by `resolveConfig` and never replaced by `applyTrustedReviewScope` — a config error naming the keys.
 */
export declare function assertNoDeferredScopeKeys(provenance: Pick<ConfigProvenance, "deferredScopeKeys">): void;
/** Key-order-independent structural equality over JSON values (the yq view is JSON). */
export declare function jsonDeepEqual(a: unknown, b: unknown): boolean;
/**
 * audit a257-1 MEDIUM-A2 (pure): the dotted keys that differ between the PR head's view and the trusted view —
 * `hounfour.providers.<name>` (every field: endpoint, auth template, models, opt-ins), `hounfour.aliases.<alias>`,
 * `hounfour.locality` (absent ⇒ `hosted`), `hounfour.secret_env_allowlist` and a root `secret_env_allowlist` (absent ⇒
 * `[]`). An absent head file reads as all defaults; an unparsable head is drift on `.loa.config.yaml` itself (fail
 * closed: cheval's YAML reader might accept what yq refused).
 */
export declare function computeHeadDrift(head: TrustedView | undefined, trusted: TrustedView, headUnreadable?: boolean): string[];
/** Where the trusted config came from, in words, for the drift refusal. */
export declare function trustedSourceDescription(t: TrustedConfig): string;
/** Exit code for a multi-model run refused by trusted-config drift (distinct from 0, 3 DEGRADED and 4 FAILED). */
export declare const EXIT_TRUSTED_CONFIG_DRIFT = 5;
/**
 * The refusal decision for the multi-model run (pure; main.ts prints and exits): the stderr line, or undefined when the
 * run may proceed (local mode, or no drift).
 */
export declare function headDriftRefusal(t: TrustedConfig): string | undefined;
/** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
export declare function trustedConfigStartupLine(t: TrustedConfig): string;
/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
export declare const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
/**
 * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
 * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
 * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
 * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
 * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
 * `host` is the canonical host for a refusal message ("" when there is no endpoint).
 */
export declare function localEndpointHost(endpoint: unknown): {
    ok: boolean;
    host: string;
};
/**
 * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
 * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
 * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
 * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
 */
export declare function localVoiceDecision(provider: string, modelId: string, trusted: TrustedConfig): {
    local: boolean;
    declared: boolean;
    reason?: string;
};
/** The fallback walk's depth bound (audit a257-1 MEDIUM-A1 (c); endpoint_policy.LOCAL_FALLBACK_MAX_DEPTH). */
export declare const LOCAL_FALLBACK_MAX_DEPTH = 8;
/**
 * A `fallback_chain` entry as `[provider, model]`: a `provider:model` pin, or an alias followed through the TRUSTED
 * `hounfour.aliases` (depth-limited, cycle-safe). Undefined when it does not resolve — the caller treats that as hosted.
 */
export declare function resolveFallbackSpec(spec: string, aliases: Record<string, string> | undefined): [string, string] | undefined;
/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
export declare function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean;
/**
 * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
 * reason; never reroute. `hosted` (the default) returns the list unchanged.
 */
export declare function applyLocality(models: MultiModelProviderEntry[], trusted: TrustedConfig): {
    kept: MultiModelProviderEntry[];
    refused: Array<{
        provider: string;
        modelId: string;
        reason: string;
    }>;
};
/**
 * The provider of a single-model `model` value for the locality check: `provider:model`, a generated-registry id, or a
 * model the trusted config declares; undefined when none says.
 */
export declare function resolveModelProvider(model: string, trusted: TrustedConfig): string | undefined;
/**
 * Under `local_voices`, the single-model path's voice must be local too: returns the refusal text, or undefined when the
 * voice may run (or the posture is hosted).
 */
export declare function singleModelLocalityRefusal(model: string, trusted: TrustedConfig): string | undefined;
/**
 * The startup lines for the agy gate (r251-2 K7f): the read error and the type warning each said once, unconditionally —
 * not only when a voice is not planned — and the not-planned voices. main.ts prints them; the pipeline says its own once
 * per review.
 */
export declare function agyGateStartupLines(gate: AgyGate, keyStatus: ReturnType<typeof validateApiKeys>): string[];
/**
 * cycle-133 C-1 (FR-1): exclude patterns every review applies before any patch is retained (prepended to
 * `bridgebuilder.exclude_patterns` and `--exclude`). Frozen review-PR fixtures and ablation grade trees are data, not
 * code under review; they made PR #1289's payload unreadable (KF-054). They apply under self-review too.
 */
export declare const DEFAULT_EXCLUDE_PATTERNS: readonly string[];
/** cycle-133 C-1: bounds for `bridgebuilder.gh_max_buffer_bytes` (default 64 MiB; 1 MiB … 512 MiB). */
export declare const GH_MAX_BUFFER_BYTES_DEFAULT: number;
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
    /** cycle-133 C-1: per-call `gh` stdout buffer in bytes. */
    gh_max_buffer_bytes?: number;
    /** cycle-135 C-2: replaces DEFAULT_PROTECTED_PATHS; `[]` disables. Validated in resolveConfig (validateProtectedPaths). */
    protected_paths?: unknown;
    /** cycle-135 C-3: fetch the content of added files GitHub returned without a patch (default true). */
    fetch_missing_patches?: boolean;
    /** cycle-135 C-3: at most this many content fetches per review (integer ≥ 0, default 20). */
    max_content_fetches?: number;
}
export interface EnvVars {
    BRIDGEBUILDER_REPOS?: string;
    BRIDGEBUILDER_MODEL?: string;
    BRIDGEBUILDER_DRY_RUN?: string;
    BRIDGEBUILDER_REPO_ROOT?: string;
    LOA_BRIDGE_REVIEW_MODE?: string;
    BRIDGEBUILDER_PASS1_CACHE?: string;
    /** cycle-136 FR-5: the pull-request signals `isPullRequestContext` reads (as `loadTrustedConfig` does). */
    GITHUB_EVENT_NAME?: string;
    GITHUB_BASE_REF?: string;
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
 * cycle-135 C-2 (bd-i4fyw): `bridgebuilder.protected_paths` — a list of non-empty, repository-relative patterns in
 * the exclusion grammar. A leading `/` or `./` is stripped (through the one loader, normalizeExcludePatterns); a
 * non-string, an empty entry, a `..` segment or a construct outside the grammar is a config error naming the entry.
 */
export declare function validateProtectedPaths(raw: unknown): string[];
/** cycle-135 C-3: `bridgebuilder.max_content_fetches` — an integer ≥ 0, else a config error. */
export declare function validateMaxContentFetches(raw: number): number;
/**
 * cycle-133 C-1: `bridgebuilder.gh_max_buffer_bytes` — an integer in 1 MiB … 512 MiB, else the default with a warning
 * (a configured buffer bounds memory per call; it is never unbounded).
 */
export declare function resolveGhMaxBufferBytes(raw: number | undefined): number;
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
    /**
     * cycle-136 FR-5 (DEC-1084): review-scope keys whose PR-head value was invalid on a pull request — left unset by
     * resolveConfig until applyTrustedReviewScope installs the trusted value or the default (and deletes this list).
     */
    deferredScopeKeys?: string[];
}
/**
 * Format effective config for logging (secrets redacted).
 * Includes provenance annotations showing where each value originated.
 */
export declare function formatEffectiveConfig(config: BridgebuilderConfig, provenance?: ConfigProvenance): string;
//# sourceMappingURL=config.d.ts.map