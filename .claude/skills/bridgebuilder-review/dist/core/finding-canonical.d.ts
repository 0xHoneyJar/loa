/**
 * cycle-133 C-2: the canonical finding projection shared by the consensus renderer and the enrichment guard
 * (sdd.md C-2 canonical fields; the failure_scenario alias precedence of C-11).
 */
export declare const FINDINGS_START = "<!-- bridge-findings-start -->";
export declare const FINDINGS_END = "<!-- bridge-findings-end -->";
/** The canonical finding fields the posted block carries byte for byte and the guard compares. */
export declare const CANONICAL_FIELDS: readonly ["id", "file", "anchor_line", "anchor_line_end", "severity", "confidence", "failure_scenario", "suggestion", "blocking"];
export interface CanonicalFinding {
    id: string;
    file: string | null;
    anchor_line: number | null;
    anchor_line_end: number | null;
    severity: string;
    confidence: unknown;
    failure_scenario: unknown;
    suggestion: unknown;
    blocking: boolean;
}
/**
 * The canonical projection of a finding: `file:line[-end]` references split into file and anchors (explicit
 * `anchor_line`/`anchor_line_end`/`line` win), `failure_scenario` by alias precedence (failure_scenario > failure_mode >
 * description, C-11), absent fields as null, `blocking` true only when the voice marked it so.
 */
export declare function canonicalize(f: Record<string, unknown>): CanonicalFinding;
//# sourceMappingURL=finding-canonical.d.ts.map