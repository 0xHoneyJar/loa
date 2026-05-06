export interface StageOutcome {
    stage: number;
    outcome: "hit" | "miss" | "applied" | "skipped" | "error";
    label: string;
    details?: Record<string, unknown>;
}
export interface ResolutionError {
    code: string;
    stage_failed: number;
    detail: string;
}
export interface ResolutionResult {
    skill: string;
    role: string;
    fixture?: string;
    resolved_provider?: string;
    resolved_model_id?: string;
    resolution_path?: StageOutcome[];
    error?: ResolutionError;
}
export interface MergedConfig {
    schema_version?: number;
    framework_defaults?: Record<string, unknown>;
    operator_config?: Record<string, unknown>;
    runtime_state?: Record<string, unknown>;
}
/**
 * Serialize to canonical JSON: sorted keys (recursive), no whitespace,
 * UTF-8 literal (no \uXXXX escapes). Matches Python's
 * `json.dumps(sort_keys=True, ensure_ascii=False, separators=(",",":"))`
 * AND bash `jq -S -c`. Cross-runtime byte-equal emission contract.
 */
export declare function dumpCanonicalJson(obj: unknown): string;
/**
 * Resolve (skill, role) against merged_config per FR-3.9 6 stages.
 *
 * Pure function. No I/O, no env access, no state. Mirrors Python's
 * `model_resolver.resolve` byte-for-byte on canonical-JSON output.
 */
export declare function resolve(mergedConfig: MergedConfig, skill: string, role: string): ResolutionResult;
//# sourceMappingURL=model-resolver.generated.d.ts.map