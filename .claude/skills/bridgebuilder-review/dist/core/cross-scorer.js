import { levenshteinSimilarity } from "./scoring.js";
/** Maximum output size per comparison (chars, ~4K tokens). */
const MAX_OUTPUT_CHARS = 16_000;
/**
 * Perform pairwise cross-scoring between model results.
 *
 * @param modelResults - Findings from each model
 * @param options - Optional configuration
 * @returns Cross-scoring result with pairwise comparisons
 */
export function crossScore(modelResults, options) {
    if (modelResults.length < 2) {
        return { comparisons: [], agreement_rate: 0, total_pairs: 0 };
    }
    const comparisons = [];
    let totalAgreements = 0;
    let totalFindings = 0;
    // N*(N-1) pairwise fan-out
    for (let i = 0; i < modelResults.length; i++) {
        for (let j = i + 1; j < modelResults.length; j++) {
            const comparison = comparePair(modelResults[i], modelResults[j]);
            comparisons.push(comparison);
            totalAgreements += comparison.agreements.length;
            totalFindings += modelResults[i].findings.length + modelResults[j].findings.length;
        }
    }
    const totalPairs = comparisons.length;
    const agreementRate = totalFindings > 0
        ? (totalAgreements * 2) / totalFindings // multiply by 2 since each agreement covers 2 findings
        : 0;
    return {
        comparisons,
        agreement_rate: Math.round(agreementRate * 100) / 100,
        total_pairs: totalPairs,
    };
}
/**
 * Compare findings between two models.
 */
function comparePair(a, b) {
    const agreements = [];
    const disagreements = [];
    const matchedB = new Set();
    let outputChars = 0;
    for (const fa of a.findings) {
        if (outputChars >= MAX_OUTPUT_CHARS)
            break;
        let bestMatch = null;
        for (let j = 0; j < b.findings.length; j++) {
            if (matchedB.has(j))
                continue;
            const fb = b.findings[j];
            const sim = findingSimilarity(fa, fb);
            if (sim > 0.5 && (!bestMatch || sim > bestMatch.similarity)) {
                bestMatch = { index: j, similarity: sim };
            }
        }
        if (bestMatch) {
            const fb = b.findings[bestMatch.index];
            matchedB.add(bestMatch.index);
            const entry = {
                finding_a_id: fa.id,
                finding_b_id: fb.id,
                similarity: Math.round(bestMatch.similarity * 100) / 100,
                severity_match: fa.severity === fb.severity,
            };
            agreements.push(entry);
            outputChars += JSON.stringify(entry).length;
        }
        else {
            const entry = {
                finding_id: fa.id,
                model: a.model,
                severity: fa.severity,
                reason: "No matching finding in other model",
            };
            disagreements.push(entry);
            outputChars += JSON.stringify(entry).length;
        }
    }
    // Unmatched findings from model B
    for (let j = 0; j < b.findings.length; j++) {
        if (matchedB.has(j) || outputChars >= MAX_OUTPUT_CHARS)
            continue;
        const fb = b.findings[j];
        const entry = {
            finding_id: fb.id,
            model: b.model,
            severity: fb.severity,
            reason: "No matching finding in other model",
        };
        disagreements.push(entry);
        outputChars += JSON.stringify(entry).length;
    }
    return {
        model_a: a.model,
        model_b: b.model,
        agreements,
        disagreements,
    };
}
/**
 * Compute similarity between two findings using multiple signals.
 */
function findingSimilarity(a, b) {
    let score = 0;
    let weight = 0;
    // File match (strong signal)
    if (a.file && b.file) {
        score += a.file === b.file ? 0.4 : 0;
        weight += 0.4;
    }
    // Category match
    if (a.category === b.category) {
        score += 0.2;
    }
    weight += 0.2;
    // Title similarity
    const titleSim = levenshteinSimilarity(a.title, b.title);
    score += titleSim * 0.2;
    weight += 0.2;
    // Description similarity
    const descSim = levenshteinSimilarity(a.description, b.description);
    score += descSim * 0.2;
    weight += 0.2;
    return weight > 0 ? score / weight : 0;
}
//# sourceMappingURL=cross-scorer.js.map