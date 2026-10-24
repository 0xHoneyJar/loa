/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2 AC 1, D-1.7 DEC-0853): who may write the enriched consensus commentary.
 *
 * `bridgebuilder.writer_role_allowlist` (trusted configuration only — config.ts loadTrustedConfig) may NARROW the
 * default set; it can never widen it past the routes whose no-tool stance is proven. An ineligible writer is
 * `degraded_reason: writer_not_eligible`: the un-enriched consensus is posted and the run exits 3.
 */
import type { ToolStance } from "../ports/llm-provider.js";
import { TOOL_STANCE_VERSION } from "../adapters/tool-stance.js";

/**
 * Routes whose no-tool stance a test proves at dispatch (writer-role.test.ts), with the stance versions proven.
 * codex-headless is absent: see CODEX_WRITER_CAPABILITY_PROOF.
 */
const PROVEN_WRITER_STANCES: Readonly<Record<string, readonly string[]>> = Object.freeze({
  "claude-headless": [TOOL_STANCE_VERSION],
  "anthropic-api": [TOOL_STANCE_VERSION],
  "openai-api": [TOOL_STANCE_VERSION],
  "google-api": [TOOL_STANCE_VERSION],
  "bedrock-api": [TOOL_STANCE_VERSION],
});

/** The default `writer_role_allowlist`: claude-headless and the API adapters. */
export const DEFAULT_WRITER_ROLE_ALLOWLIST: readonly string[] = Object.freeze(Object.keys(PROVEN_WRITER_STANCES));

/**
 * The proof codex-headless needs to join the allowlist: a test showing its native shell, file and network tools cannot
 * execute under its dispatch. Its argv is a posture (a read-only sandbox and four disabled agent features, no
 * all-tools switch), and proving the rest needs the codex binary under execution capture — not a unit test. Until
 * such a proof exists and is recorded here, codex-headless is refused for the writer role.
 */
export const CODEX_WRITER_CAPABILITY_PROOF: null = null;

/** The configured allowlist intersected with the proven set (config narrows, never widens); default when unset. */
export function effectiveWriterAllowlist(configured: readonly string[] | undefined): string[] {
  if (configured === undefined) return [...DEFAULT_WRITER_ROLE_ALLOWLIST];
  return configured.filter((a, i) => Object.hasOwn(PROVEN_WRITER_STANCES, a) && configured.indexOf(a) === i);
}

export type WriterEligibility = { eligible: true } | { eligible: false; reason: string };

/**
 * Verify a dispatch's self-reported stance for the writer role: reported, known route at a known stance version,
 * enforced no-tools, on the allowlist, and no tool call in the reply.
 */
export function checkWriterEligibility(
  stance: ToolStance | undefined,
  allowlist: readonly string[],
  observed: { toolCallsAttempted?: number } = {},
): WriterEligibility {
  if (stance === undefined) return { eligible: false, reason: "the dispatch reported no tool stance" };
  const versions = PROVEN_WRITER_STANCES[stance.adapter];
  if (!Object.hasOwn(PROVEN_WRITER_STANCES, stance.adapter) || versions === undefined) {
    return { eligible: false, reason: `${stance.adapter}: no proven no-tool stance (${stance.mechanism})` };
  }
  if (!versions.includes(stance.adapter_version)) {
    return { eligible: false, reason: `${stance.adapter}: unknown adapter stance version ${stance.adapter_version} (known: ${versions.join(", ")})` };
  }
  if (stance.tools !== "none" || !stance.enforced) {
    return { eligible: false, reason: `${stance.adapter}: the stance is not an enforced no-tool dispatch` };
  }
  if (!allowlist.includes(stance.adapter)) {
    return { eligible: false, reason: `${stance.adapter} is not on bridgebuilder.writer_role_allowlist (${allowlist.join(", ") || "empty"})` };
  }
  if ((observed.toolCallsAttempted ?? 0) > 0) {
    return { eligible: false, reason: `${stance.adapter}: the reply carried ${observed.toolCallsAttempted} tool call(s)` };
  }
  return { eligible: true };
}
