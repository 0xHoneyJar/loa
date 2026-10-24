import { FindingsBlockSchema } from "./schemas.js";
import { FETCH_DEGRADED_REASONS, orderDegradedReasons, primaryDegradedReason } from "./degraded-reason.js";
const START = "<!-- bridge-findings-start -->";
const END = "<!-- bridge-findings-end -->";
const SEVERITIES = ["CRITICAL", "BLOCKER", "HIGH", "MEDIUM", "LOW"];
const BLOCKING_SEVERITIES = ["CRITICAL", "BLOCKER", "HIGH"];
/** INFO, PRAISE, SPECULATION and REFRAME never block (sdd.md C-2); STYLE and VISION are accepted legacy labels. */
const KNOWN_SEVERITIES = [...SEVERITIES, "PRAISE", "INFO", "STYLE", "VISION", "SPECULATION", "REFRAME"];
const BLOCK_VERDICTS = ["REQUEST_CHANGES", "APPROVE", "COMMENT"];
function parseBlocks(content) {
    if (!content.includes(START))
        return [];
    const blocks = [];
    for (const block of content.split(START).slice(1)) {
        try {
            if (!block.includes(END))
                throw new Error("Missing findings end");
            const json = block.split(END)[0].trim().replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
            const raw = JSON.parse(json);
            const parsed = FindingsBlockSchema.safeParse(raw);
            if (!parsed.success) {
                blocks.push({ valid: false, findings: [] });
                continue;
            }
            const verdict = raw.verdict;
            if (verdict !== undefined && !(typeof verdict === "string" && BLOCK_VERDICTS.includes(verdict))) {
                blocks.push({ valid: false, findings: [] });
                continue;
            }
            blocks.push({
                valid: true,
                ...(typeof verdict === "string" ? { verdict } : {}),
                findings: parsed.data.findings,
            });
        }
        catch {
            blocks.push({ valid: false, findings: [] });
        }
    }
    return blocks;
}
/**
 * Review transport success and GitHub COMMENTED state are not merge clearance.
 *
 * cycle-133 C-2 decision table (sdd.md § 1.4, FR-2, D-1.2 DEC-0840), applied in order:
 *  (1) any finding with `blocking: true` or severity CRITICAL/BLOCKER/HIGH → REQUEST_CHANGES;
 *  (2) a guard rejection, incomplete coverage or a fetch-side degradation → UNKNOWN, degraded, merge blocked with the
 *      reason (`incomplete_coverage` for every fetch-side reason);
 *  (5) two blocks, a malformed block or a block verdict contradicting (1) → `verdict_conflict`, UNKNOWN, merge blocked
 *      (under (1) the verdict stays REQUEST_CHANGES and the conflict is still recorded as a degradation);
 *  (3) exactly one valid consensus block carrying a `verdict` → that verdict (COMMENT and APPROVE clear the merge);
 *  (4) otherwise the prose rule (an explicit single verdict line; APPROVE alone clears the merge).
 * `writer_not_eligible` is a degradation that does not change the verdict: the un-enriched consensus is authoritative.
 */
export function summarizeReviewVerdict(content, findings = [], options = {}) {
    const blocks = parseBlocks(content);
    const all = [...findings, ...blocks.flatMap((b) => b.findings)];
    const found = new Set(all.map((finding) => String(finding.severity).toUpperCase()));
    const unknownSeverity = [...found].some((severity) => !KNOWN_SEVERITIES.includes(severity));
    const single = blocks.length === 1 && blocks[0].valid ? blocks[0] : undefined;
    const blockVerdict = single?.verdict;
    const prose = content.replace(/```[\s\S]*?```/g, "").replace(/\*\*/g, "");
    // (4) the prose rule reads severity headings only when no consensus block carries the verdict
    if (blockVerdict === undefined) {
        for (const match of prose.matchAll(/^\s*(?:#{1,6}\s*|[-*]\s+)(CRITICAL|BLOCKER|HIGH|MEDIUM|LOW)\b/gm)) {
            found.add(match[1]);
        }
    }
    const highestSeverity = SEVERITIES.find((severity) => found.has(severity)) ?? null;
    const structuredBlocking = all.some((f) => f.blocking === true || BLOCKING_SEVERITIES.includes(String(f.severity).toUpperCase()));
    const blocking = structuredBlocking || (blockVerdict === undefined && BLOCKING_SEVERITIES.includes(highestSeverity ?? ""));
    const reasons = [...(options.degradedReasons ?? [])];
    const conflict = blocks.length > 1 || blocks.some((b) => !b.valid) || unknownSeverity ||
        (blockVerdict !== undefined && blockVerdict !== "REQUEST_CHANGES" && blocking);
    if (conflict && !reasons.includes("verdict_conflict"))
        reasons.push("verdict_conflict");
    const result = (verdict, mergeBlocked, mergeBlockedReason) => {
        const out = { verdict, highestSeverity, mergeBlocked };
        if (mergeBlockedReason !== undefined)
            out.mergeBlockedReason = mergeBlockedReason;
        const primary = primaryDegradedReason(reasons);
        if (primary !== undefined) {
            out.degraded = true;
            out.degradedReason = primary;
            out.degradedReasons = orderDegradedReasons(reasons);
        }
        return out;
    };
    // (1)
    if (blocking)
        return result("REQUEST_CHANGES", true);
    // (2) and (5): every degradation except writer_not_eligible leaves the verdict unknown
    const blockingReason = primaryDegradedReason(reasons.filter((r) => r !== "writer_not_eligible"));
    if (blockingReason !== undefined) {
        return result("UNKNOWN", true, FETCH_DEGRADED_REASONS.has(blockingReason) ? "incomplete_coverage" : blockingReason);
    }
    // (3)
    if (blockVerdict !== undefined) {
        const verdict = blockVerdict;
        return result(verdict, verdict === "REQUEST_CHANGES");
    }
    // (4) the prose rule
    const explicit = new Set();
    for (const line of prose.split("\n")) {
        const match = line.match(/^\s*(?:#{1,6}\s*)?(?:(?:Verdict|Recommendation)\s*:\s*)?(REQUEST_CHANGES|APPROVE|COMMENT)\s*[.!]?\s*$/i);
        if (match)
            explicit.add(match[1].toUpperCase());
    }
    let verdict = "UNKNOWN";
    if (/\bREQUEST_CHANGES\b/.test(content) ||
        /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i.test(content)) {
        verdict = "REQUEST_CHANGES";
    }
    else if (explicit.size === 1) {
        verdict = [...explicit][0];
    }
    return result(verdict, verdict !== "APPROVE");
}
//# sourceMappingURL=review-verdict.js.map