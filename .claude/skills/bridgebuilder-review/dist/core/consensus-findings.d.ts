/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2, D-1.2 DEC-0840; KF-055): the posted findings are rendered from the consensus,
 * never produced by the writer.
 *
 * The block is built deterministically from the scored consensus (every canonical field byte for byte, the same
 * multiplicity, ids made unique), its verdict derived by the decision table's rule (1). The writer's output is
 * commentary in a separate section, admitted only from an eligible writer (core/writer-role.ts) and only when the guard
 * (core/enrichment-guard.ts) accepts it; otherwise the un-enriched consensus is posted with the degradation named.
 */
import type { ToolStance } from "../ports/llm-provider.js";
import type { ScoringResult } from "./scoring.js";
import type { CoverageRecord } from "./types.js";
import type { DegradedReason } from "./degraded-reason.js";
import { type ReviewVerdict } from "./review-verdict.js";
import { type GuardResult } from "./enrichment-guard.js";
export { CANONICAL_FIELDS, canonicalize, FINDINGS_END, FINDINGS_START, type CanonicalFinding } from "./finding-canonical.js";
export interface ConsensusFindingsBlock {
    schema_version: 1;
    verdict: "REQUEST_CHANGES" | "COMMENT";
    findings: Array<Record<string, unknown> & {
        id: string;
        severity: string;
    }>;
}
/** The consensus block: the convergence track's canonical findings (+ consensus metadata), ids unique, verdict derived. */
export declare function buildConsensusBlock(consensus: ScoringResult): ConsensusFindingsBlock;
/**
 * The deterministic block text (2-space JSON inside the markers). `<`, `>` and backticks occur only inside JSON strings
 * and are written as \\u escapes, so voice text can neither open or close a marker nor end the code fence (the
 * parsed values — what the guard and the verdict read — are unchanged).
 */
export declare function renderFindingsBlock(block: ConsensusFindingsBlock): string;
export type ComposeWriter = {
    output: string;
    stance: ToolStance | undefined;
    toolCallsAttempted?: number;
    allowlist: readonly string[];
    label: string;
} | {
    notEligible: string;
    label: string;
};
export interface ComposeInput {
    /** Title, models and statistics (and the verdict-quality header) — rendered above the findings. */
    header: string;
    consensus: ScoringResult;
    writer?: ComposeWriter;
    coverage?: CoverageRecord;
    /** Degradations established before composition (coverage, unparsed voices). */
    degradedReasons?: DegradedReason[];
}
export interface ComposedReview {
    body: string;
    block: ConsensusFindingsBlock;
    guard?: GuardResult;
    degradedReasons: DegradedReason[];
    verdict: ReviewVerdict;
}
/** Assemble the consensus review: header, rendered block, admitted commentary or the withheld notice, coverage. */
export declare function composeConsensusReview(input: ComposeInput): ComposedReview;
//# sourceMappingURL=consensus-findings.d.ts.map