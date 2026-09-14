import { FindingsBlockSchema } from "./schemas.js";
/** Review transport success and GitHub COMMENTED state are not merge clearance. */
export function summarizeReviewVerdict(content, findings = []) {
    const severities = ["CRITICAL", "BLOCKER", "HIGH", "MEDIUM", "LOW"];
    const found = new Set(findings.map((finding) => finding.severity.toUpperCase()));
    let invalidFindings = false;
    const start = "<!-- bridge-findings-start -->";
    const end = "<!-- bridge-findings-end -->";
    if (content.includes(start)) {
        const blocks = content.split(start).slice(1);
        for (const block of blocks) {
            try {
                if (!block.includes(end))
                    throw new Error("Missing findings end");
                const json = block.split(end)[0].trim().replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
                const parsed = FindingsBlockSchema.safeParse(JSON.parse(json));
                if (!parsed.success)
                    invalidFindings = true;
                else
                    for (const finding of parsed.data.findings)
                        found.add(finding.severity.toUpperCase());
            }
            catch {
                invalidFindings = true;
            }
        }
    }
    const prose = content.replace(/```[\s\S]*?```/g, "").replace(/\*\*/g, "");
    // Also recognize prose review severity headings.
    for (const match of prose.matchAll(/^\s*(?:#{1,6}\s*|[-*]\s+)(CRITICAL|BLOCKER|HIGH|MEDIUM|LOW)\b/gm)) {
        found.add(match[1]);
    }
    const knownSeverities = [...severities, "PRAISE", "INFO", "STYLE", "VISION", "SPECULATION"];
    if ([...found].some((severity) => !knownSeverities.includes(severity)))
        invalidFindings = true;
    const highestSeverity = severities.find((severity) => found.has(severity)) ?? null;
    const explicit = new Set();
    for (const line of prose.split("\n")) {
        const match = line.match(/^\s*(?:#{1,6}\s*)?(?:(?:Verdict|Recommendation)\s*:\s*)?(REQUEST_CHANGES|APPROVE|COMMENT)\s*[.!]?\s*$/i);
        if (match)
            explicit.add(match[1].toUpperCase());
    }
    let verdict = "UNKNOWN";
    if (/\bREQUEST_CHANGES\b/.test(content) || ["CRITICAL", "BLOCKER", "HIGH"].includes(highestSeverity ?? "") ||
        /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i.test(content)) {
        verdict = "REQUEST_CHANGES";
    }
    else if (!invalidFindings && explicit.size === 1) {
        verdict = [...explicit][0];
    }
    return { verdict, highestSeverity, mergeBlocked: verdict !== "APPROVE" };
}
//# sourceMappingURL=review-verdict.js.map