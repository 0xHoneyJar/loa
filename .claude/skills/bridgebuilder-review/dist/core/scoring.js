/**
 * BridgebuilderScorer — dual-track consensus scoring for multi-model reviews.
 *
 * Track 1 (Convergence): Classifies findings as HIGH_CONSENSUS, DISPUTED, LOW_VALUE, or BLOCKER.
 * Track 2 (Diversity): Deduplicates findings across models while preserving unique perspectives.
 */
const DEFAULT_THRESHOLDS = {
    high_consensus: 700,
    disputed_delta: 300,
    low_value: 400,
    blocker: 700,
};
/** Severity to numeric score mapping (0-1000 scale, matching scoring-engine.sh). */
const SEVERITY_SCORES = {
    CRITICAL: 1000,
    BLOCKER: 1000,
    HIGH: 800,
    MEDIUM: 500,
    LOW: 200,
    PRAISE: 100,
    SPECULATION: 300,
    REFRAME: 600,
};
/**
 * Score findings from multiple models using dual-track consensus.
 */
export function scoreFindings(modelResults, thresholds = {}) {
    const t = { ...DEFAULT_THRESHOLDS, ...thresholds };
    const allFindings = [];
    for (const mr of modelResults) {
        for (const f of mr.findings) {
            allFindings.push({ provider: mr.provider, model: mr.model, finding: f });
        }
    }
    if (allFindings.length === 0) {
        return {
            convergence: [],
            diversity: [],
            stats: {
                total_findings: 0,
                high_consensus: 0,
                disputed: 0,
                low_value: 0,
                blocker: 0,
                unique: 0,
                models_contributing: modelResults.length,
            },
        };
    }
    // Track 1: Group similar findings and classify by consensus
    const groups = groupSimilarFindings(allFindings);
    const convergence = [];
    for (const group of groups) {
        const scores = group.map((g) => severityScore(g.finding.severity));
        const avgScore = scores.reduce((a, b) => a + b, 0) / scores.length;
        const minScore = Math.min(...scores);
        const maxScore = Math.max(...scores);
        const delta = maxScore - minScore;
        const agreeingModels = [...new Set(group.map((g) => g.model))];
        // Pick the finding with the highest severity as canonical
        const canonical = group.reduce((best, curr) => severityScore(curr.finding.severity) > severityScore(best.finding.severity) ? curr : best);
        let classification;
        if (canonical.finding.severity === "CRITICAL" || canonical.finding.severity === "BLOCKER") {
            // Critical/blocker findings from any model are always BLOCKER
            classification = "BLOCKER";
        }
        else if (agreeingModels.length >= 2 && avgScore >= t.high_consensus) {
            classification = "HIGH_CONSENSUS";
        }
        else if (delta >= t.disputed_delta) {
            classification = "DISPUTED";
        }
        else if (avgScore < t.low_value) {
            classification = "LOW_VALUE";
        }
        else if (agreeingModels.length >= 2) {
            classification = "HIGH_CONSENSUS";
        }
        else {
            // Single-model finding with moderate score
            classification = avgScore >= t.high_consensus ? "HIGH_CONSENSUS" : "DISPUTED";
        }
        convergence.push({
            finding: canonical.finding,
            classification,
            agreeing_models: agreeingModels,
            avg_score: Math.round(avgScore),
            score_delta: delta,
            unique: agreeingModels.length === 1,
        });
    }
    // Track 2: Preserve unique perspectives (diversity dedup)
    const diversity = [];
    const seen = new Set();
    for (const item of allFindings) {
        const key = normalizeForDedup(item.finding);
        if (seen.has(key))
            continue;
        seen.add(key);
        // Only include findings with educational depth (enrichment fields)
        if (item.finding.faang_parallel ||
            item.finding.metaphor ||
            item.finding.teachable_moment ||
            item.finding.connection) {
            // Check it's not too similar to already-included diversity entries
            const isDuplicate = diversity.some((d) => levenshteinSimilarity(d.description, item.finding.description) > 0.8);
            if (!isDuplicate) {
                diversity.push(item.finding);
            }
        }
    }
    // Compute stats
    const stats = {
        total_findings: convergence.length,
        high_consensus: convergence.filter((f) => f.classification === "HIGH_CONSENSUS").length,
        disputed: convergence.filter((f) => f.classification === "DISPUTED").length,
        low_value: convergence.filter((f) => f.classification === "LOW_VALUE").length,
        blocker: convergence.filter((f) => f.classification === "BLOCKER").length,
        unique: convergence.filter((f) => f.unique).length,
        models_contributing: modelResults.length,
    };
    return { convergence, diversity, stats };
}
/**
 * Group findings from different models that refer to the same issue.
 * Similarity is determined by file + category + description overlap.
 */
function groupSimilarFindings(allFindings) {
    const groups = [];
    const assigned = new Set();
    for (let i = 0; i < allFindings.length; i++) {
        if (assigned.has(i))
            continue;
        const group = [allFindings[i]];
        assigned.add(i);
        for (let j = i + 1; j < allFindings.length; j++) {
            if (assigned.has(j))
                continue;
            if (areSimilarFindings(allFindings[i].finding, allFindings[j].finding)) {
                group.push(allFindings[j]);
                assigned.add(j);
            }
        }
        groups.push(group);
    }
    return groups;
}
/**
 * Determine if two findings refer to the same issue.
 * Uses file + category match as a strong signal, then description similarity.
 */
function areSimilarFindings(a, b) {
    // Same file and category is a strong signal
    if (a.file && b.file && a.file === b.file && a.category === b.category) {
        return true;
    }
    // Same category + similar description
    if (a.category === b.category) {
        const sim = levenshteinSimilarity(a.description, b.description);
        if (sim > 0.6)
            return true;
    }
    // Very similar titles
    if (a.title && b.title) {
        const titleSim = levenshteinSimilarity(a.title, b.title);
        if (titleSim > 0.7)
            return true;
    }
    return false;
}
/** Convert severity string to numeric score. */
function severityScore(severity) {
    return SEVERITY_SCORES[severity.toUpperCase()] ?? 400;
}
/** Normalize a finding for dedup key generation. */
function normalizeForDedup(finding) {
    const parts = [
        finding.file ?? "",
        finding.category ?? "",
        finding.severity ?? "",
        (finding.description ?? "").slice(0, 100).toLowerCase(),
    ];
    return parts.join("|");
}
/**
 * Levenshtein similarity (0.0 = completely different, 1.0 = identical).
 * Optimized for short-to-medium strings (< 500 chars).
 */
export function levenshteinSimilarity(a, b) {
    if (a === b)
        return 1.0;
    if (a.length === 0 || b.length === 0)
        return 0.0;
    // Truncate for performance on long strings
    const maxLen = 500;
    const sa = a.length > maxLen ? a.slice(0, maxLen) : a;
    const sb = b.length > maxLen ? b.slice(0, maxLen) : b;
    const la = sa.length;
    const lb = sb.length;
    // Single-row DP (O(min(m,n)) space)
    const shorter = la < lb ? sa : sb;
    const longer = la < lb ? sb : sa;
    const sl = shorter.length;
    const ll = longer.length;
    let prev = new Array(sl + 1);
    let curr = new Array(sl + 1);
    for (let i = 0; i <= sl; i++)
        prev[i] = i;
    for (let j = 1; j <= ll; j++) {
        curr[0] = j;
        for (let i = 1; i <= sl; i++) {
            const cost = shorter[i - 1] === longer[j - 1] ? 0 : 1;
            curr[i] = Math.min(prev[i] + 1, curr[i - 1] + 1, prev[i - 1] + cost);
        }
        [prev, curr] = [curr, prev];
    }
    const distance = prev[sl];
    return 1.0 - distance / Math.max(la, lb);
}
//# sourceMappingURL=scoring.js.map