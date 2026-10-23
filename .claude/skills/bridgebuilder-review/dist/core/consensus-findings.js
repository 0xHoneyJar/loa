import { orderDegradedReasons } from "./degraded-reason.js";
import { summarizeReviewVerdict } from "./review-verdict.js";
import { guardEnrichment } from "./enrichment-guard.js";
import { checkWriterEligibility } from "./writer-role.js";
import { formatCoverageSection } from "./paged-fetch.js";
// (the canonical projection lives in finding-canonical.ts so the guard imports it without an import cycle)
export { CANONICAL_FIELDS, canonicalize, FINDINGS_END, FINDINGS_START } from "./finding-canonical.js";
import { FINDINGS_END, FINDINGS_START } from "./finding-canonical.js";
const BLOCKING = new Set(["CRITICAL", "BLOCKER", "HIGH"]);
/** The consensus block: the convergence track's canonical findings (+ consensus metadata), ids unique, verdict derived. */
export function buildConsensusBlock(consensus) {
    const used = new Set();
    const findings = consensus.convergence.map((scored) => {
        const base = String(scored.finding.id ?? "F");
        let id = base;
        for (let n = 2; used.has(id); n++)
            id = `${base}~${n}`;
        used.add(id);
        return { ...scored.finding, id, agreeing_models: scored.agreeing_models, consensus_classification: scored.classification };
    });
    const blocking = findings.some((f) => f.blocking === true || BLOCKING.has(String(f.severity).toUpperCase()));
    return { schema_version: 1, verdict: blocking ? "REQUEST_CHANGES" : "COMMENT", findings };
}
/**
 * The deterministic block text (2-space JSON inside the markers). `<`, `>` and backticks occur only inside JSON strings
 * and are written as \\u escapes, so voice text can neither open or close a marker nor end the code fence (the
 * parsed values — what the guard and the verdict read — are unchanged).
 */
export function renderFindingsBlock(block) {
    const json = JSON.stringify(block, null, 2).replace(/[<>`]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
    return `${FINDINGS_START}\n\`\`\`json\n${json}\n\`\`\`\n${FINDINGS_END}`;
}
/** A third-party string safe for one line of posted markdown. */
function oneLine(text, max = 200) {
    return text.replace(/[\r\n`]+/g, " ").slice(0, max);
}
/** Assemble the consensus review: header, rendered block, admitted commentary or the withheld notice, coverage. */
export function composeConsensusReview(input) {
    const block = buildConsensusBlock(input.consensus);
    const reasons = [...(input.degradedReasons ?? [])];
    let guard;
    let commentary;
    let withheld;
    const w = input.writer;
    if (w && "notEligible" in w) {
        reasons.push("writer_not_eligible");
        withheld = `writer_not_eligible — ${oneLine(w.label)}: ${oneLine(w.notEligible)}`;
    }
    else if (w) {
        const eligibility = checkWriterEligibility(w.stance, w.allowlist, { toolCallsAttempted: w.toolCallsAttempted });
        if (!eligibility.eligible) {
            reasons.push("writer_not_eligible");
            withheld = `writer_not_eligible — ${oneLine(w.label)}: ${oneLine(eligibility.reason)}`;
        }
        else {
            guard = guardEnrichment(w.output, block);
            if (guard.accepted)
                commentary = guard.commentary.trim();
            else {
                reasons.push("enrichment_guard_rejected");
                withheld = `enrichment_guard_rejected — ${guard.reason}: ${oneLine(guard.detail)}`;
            }
        }
    }
    const parts = [input.header.trimEnd(), "", "## Consensus findings", "", renderFindingsBlock(block)];
    if (commentary) {
        parts.push("", "---", "", "## Commentary", "", `_Written by ${oneLine(w.label)} from the consensus findings above; commentary never adds, removes or changes a finding._`, "", commentary);
    }
    else if (withheld) {
        parts.push("", `> **Enrichment withheld** (${withheld}). The consensus findings above are posted un-enriched.`);
    }
    if (input.coverage)
        parts.push("", formatCoverageSection(input.coverage));
    const body = parts.join("\n");
    const ordered = orderDegradedReasons(reasons);
    return {
        body, block, ...(guard ? { guard } : {}), degradedReasons: ordered,
        verdict: summarizeReviewVerdict(body, [], { degradedReasons: ordered }),
    };
}
//# sourceMappingURL=consensus-findings.js.map