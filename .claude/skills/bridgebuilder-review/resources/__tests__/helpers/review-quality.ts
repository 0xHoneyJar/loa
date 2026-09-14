import type { VerdictQualityEnvelope } from "../../ports/llm-provider.js";

export function approvedQuality(voice = "fixture"): VerdictQualityEnvelope {
  return {
    status: "APPROVED",
    consensus_outcome: "consensus",
    truncation_waiver_applied: false,
    voices_planned: 1,
    voices_succeeded: 1,
    voices_succeeded_ids: [voice],
    voices_dropped: [],
    chain_health: "ok",
    confidence_floor: "high",
    rationale: "Local synthetic review completed.",
    single_voice_call: true,
  };
}

export const approvalBody = "## Summary\nReview completed for the changed source.\nVerdict: APPROVE\n\n## Findings\nNo issues found.";
export const advisoryFindingsJSON = '{"schema_version":1,"findings":[{"id":"F1","severity":"LOW","category":"style"}]}';
export const advisoryFindings = '<!-- bridge-findings-start -->\n```json\n' + advisoryFindingsJSON + '\n```\n<!-- bridge-findings-end -->';
