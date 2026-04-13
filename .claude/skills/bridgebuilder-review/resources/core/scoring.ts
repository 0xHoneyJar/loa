/**
 * BridgebuilderScorer — dual-track consensus scoring for multi-model reviews.
 *
 * Track 1 (Convergence): Classifies findings as HIGH_CONSENSUS, DISPUTED, LOW_VALUE, or BLOCKER.
 * Track 2 (Diversity): Deduplicates findings across models while preserving unique perspectives.
 */

export type ConsensusClassification =
  | "HIGH_CONSENSUS"
  | "DISPUTED"
  | "LOW_VALUE"
  | "BLOCKER";

export interface ScoringThresholds {
  high_consensus: number;
  disputed_delta: number;
  low_value: number;
  blocker: number;
}

export interface ScoredFinding {
  /** The canonical finding (from the highest-scoring model). */
  finding: ModelFinding;
  /** Consensus classification. */
  classification: ConsensusClassification;
  /** Models that produced a similar finding. */
  agreeing_models: string[];
  /** Average severity score across models. */
  avg_score: number;
  /** Delta between highest and lowest model scores. */
  score_delta: number;
  /** Whether this finding was unique to one model (diversity track). */
  unique: boolean;
}

export interface ModelFinding {
  id: string;
  title: string;
  severity: string;
  category: string;
  file?: string;
  description: string;
  suggestion?: string;
  confidence?: number;
  // Enrichment fields (passthrough)
  faang_parallel?: string;
  metaphor?: string;
  teachable_moment?: string;
  connection?: string;
  [key: string]: unknown;
}

export interface ModelFindings {
  provider: string;
  model: string;
  findings: ModelFinding[];
}

export interface ScoringResult {
  /** Track 1: convergence-classified findings. */
  convergence: ScoredFinding[];
  /** Track 2: unique perspectives preserved from individual models. */
  diversity: ModelFinding[];
  /** Summary statistics. */
  stats: {
    total_findings: number;
    high_consensus: number;
    disputed: number;
    low_value: number;
    blocker: number;
    unique: number;
    models_contributing: number;
  };
}

const DEFAULT_THRESHOLDS: ScoringThresholds = {
  high_consensus: 700,
  disputed_delta: 300,
  low_value: 400,
  blocker: 700,
};

/** Severity to numeric score mapping (0-1000 scale, matching scoring-engine.sh). */
const SEVERITY_SCORES: Record<string, number> = {
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
export function scoreFindings(
  modelResults: ModelFindings[],
  thresholds: Partial<ScoringThresholds> = {},
): ScoringResult {
  const t: ScoringThresholds = { ...DEFAULT_THRESHOLDS, ...thresholds };
  const allFindings: Array<{ provider: string; model: string; finding: ModelFinding }> = [];

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
  const convergence: ScoredFinding[] = [];

  for (const group of groups) {
    const scores = group.map((g) => severityScore(g.finding.severity));
    const avgScore = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);
    const delta = maxScore - minScore;
    const agreeingModels = [...new Set(group.map((g) => g.model))];

    // Pick the finding with the highest severity as canonical
    const canonical = group.reduce((best, curr) =>
      severityScore(curr.finding.severity) > severityScore(best.finding.severity) ? curr : best,
    );

    let classification: ConsensusClassification;

    if (canonical.finding.severity === "CRITICAL" || canonical.finding.severity === "BLOCKER") {
      // Critical/blocker findings from any model are always BLOCKER
      classification = "BLOCKER";
    } else if (agreeingModels.length >= 2 && avgScore >= t.high_consensus) {
      classification = "HIGH_CONSENSUS";
    } else if (delta >= t.disputed_delta) {
      classification = "DISPUTED";
    } else if (avgScore < t.low_value) {
      classification = "LOW_VALUE";
    } else if (agreeingModels.length >= 2) {
      classification = "HIGH_CONSENSUS";
    } else {
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
  const diversity: ModelFinding[] = [];
  const seen = new Set<string>();

  for (const item of allFindings) {
    const key = normalizeForDedup(item.finding);
    if (seen.has(key)) continue;
    seen.add(key);

    // Only include findings with educational depth (enrichment fields)
    if (
      item.finding.faang_parallel ||
      item.finding.metaphor ||
      item.finding.teachable_moment ||
      item.finding.connection
    ) {
      // Check it's not too similar to already-included diversity entries
      const isDuplicate = diversity.some(
        (d) => levenshteinSimilarity(d.description, item.finding.description) > 0.8,
      );
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
function groupSimilarFindings(
  allFindings: Array<{ provider: string; model: string; finding: ModelFinding }>,
): Array<Array<{ provider: string; model: string; finding: ModelFinding }>> {
  const groups: Array<Array<{ provider: string; model: string; finding: ModelFinding }>> = [];
  const assigned = new Set<number>();

  for (let i = 0; i < allFindings.length; i++) {
    if (assigned.has(i)) continue;

    const group = [allFindings[i]];
    assigned.add(i);

    for (let j = i + 1; j < allFindings.length; j++) {
      if (assigned.has(j)) continue;

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
function areSimilarFindings(a: ModelFinding, b: ModelFinding): boolean {
  // Same file and category is a strong signal
  if (a.file && b.file && a.file === b.file && a.category === b.category) {
    return true;
  }

  // Same category + similar description
  if (a.category === b.category) {
    const sim = levenshteinSimilarity(a.description, b.description);
    if (sim > 0.6) return true;
  }

  // Very similar titles
  if (a.title && b.title) {
    const titleSim = levenshteinSimilarity(a.title, b.title);
    if (titleSim > 0.7) return true;
  }

  return false;
}

/** Convert severity string to numeric score. */
function severityScore(severity: string): number {
  return SEVERITY_SCORES[severity.toUpperCase()] ?? 400;
}

/** Normalize a finding for dedup key generation. */
function normalizeForDedup(finding: ModelFinding): string {
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
export function levenshteinSimilarity(a: string, b: string): number {
  if (a === b) return 1.0;
  if (a.length === 0 || b.length === 0) return 0.0;

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

  let prev = new Array<number>(sl + 1);
  let curr = new Array<number>(sl + 1);

  for (let i = 0; i <= sl; i++) prev[i] = i;

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
