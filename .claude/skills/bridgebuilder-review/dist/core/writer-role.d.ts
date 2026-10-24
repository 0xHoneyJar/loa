/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2 AC 1, D-1.7 DEC-0853): who may write the enriched consensus commentary.
 *
 * `bridgebuilder.writer_role_allowlist` (trusted configuration only — config.ts loadTrustedConfig) may NARROW the
 * default set; it can never widen it past the routes whose no-tool stance is proven. An ineligible writer is
 * `degraded_reason: writer_not_eligible`: the un-enriched consensus is posted and the run exits 3.
 */
import type { ToolStance } from "../ports/llm-provider.js";
/** The default `writer_role_allowlist`: claude-headless and the API adapters. */
export declare const DEFAULT_WRITER_ROLE_ALLOWLIST: readonly string[];
/**
 * The proof codex-headless needs to join the allowlist: a test showing its native shell, file and network tools cannot
 * execute under its dispatch. Its argv is a posture (a read-only sandbox and four disabled agent features, no
 * all-tools switch), and proving the rest needs the codex binary under execution capture — not a unit test. Until
 * such a proof exists and is recorded here, codex-headless is refused for the writer role.
 */
export declare const CODEX_WRITER_CAPABILITY_PROOF: null;
/** The configured allowlist intersected with the proven set (config narrows, never widens); default when unset. */
export declare function effectiveWriterAllowlist(configured: readonly string[] | undefined): string[];
export type WriterEligibility = {
    eligible: true;
} | {
    eligible: false;
    reason: string;
};
/**
 * Verify a dispatch's self-reported stance for the writer role: reported, known route at a known stance version,
 * enforced no-tools, on the allowlist, and no tool call in the reply.
 */
export declare function checkWriterEligibility(stance: ToolStance | undefined, allowlist: readonly string[], observed?: {
    toolCallsAttempted?: number;
}): WriterEligibility;
//# sourceMappingURL=writer-role.d.ts.map