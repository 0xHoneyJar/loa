import type { ConsensusFindingsBlock } from "./consensus-findings.js";
export type GuardRejection = "tool_grammar" | "multiple_findings_blocks" | "malformed_findings_block" | "own_findings_block" | "duplicate_id" | "altered_field" | "altered_verdict";
export type GuardResult = {
    accepted: true;
    echoed: boolean;
    commentary: string;
} | {
    accepted: false;
    reason: GuardRejection;
    detail: string;
};
/**
 * The first structural tool-call grammar match, described without quoting the text (`line N: xml tag invoke`,
 * `json key tool_calls`), or null.
 */
export declare function findToolGrammar(text: string): string | null;
export declare function guardEnrichment(output: string, consensus: ConsensusFindingsBlock): GuardResult;
//# sourceMappingURL=enrichment-guard.d.ts.map