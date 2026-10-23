/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2, D-1.2 DEC-0840; KF-055): the posted findings are rendered from the consensus,
 * never produced by the writer.
 *
 * The block is built deterministically from the scored consensus (every canonical field byte for byte, the same
 * multiplicity, ids made unique), its verdict derived by the decision table's rule (1). The writer's output is
 * commentary in a separate section, admitted only from an eligible writer (core/writer-role.ts) and only when the guard
 * (core/enrichment-guard.ts) accepts it; otherwise the un-enriched consensus is posted with the degradation named.
 */
import type { ToolStance } from "../ports/llm-provider.js";
import type { ScoringResult } from "./scoring.js";
import type { CoverageRecord } from "./types.js";
import type { DegradedReason } from "./degraded-reason.js";
import { orderDegradedReasons } from "./degraded-reason.js";
import { summarizeReviewVerdict, type ReviewVerdict } from "./review-verdict.js";
import { guardEnrichment, type GuardResult } from "./enrichment-guard.js";
import { checkWriterEligibility } from "./writer-role.js";
import { formatCoverageSection } from "./paged-fetch.js";

// (the canonical projection lives in finding-canonical.ts so the guard imports it without an import cycle)
export { CANONICAL_FIELDS, canonicalize, FINDINGS_END, FINDINGS_START, type CanonicalFinding } from "./finding-canonical.js";
import { FINDINGS_END, FINDINGS_START } from "./finding-canonical.js";

export interface ConsensusFindingsBlock {
  schema_version: 1;
  verdict: "REQUEST_CHANGES" | "COMMENT";
  findings: Array<Record<string, unknown> & { id: string; severity: string }>;
}

const BLOCKING = new Set(["CRITICAL", "BLOCKER", "HIGH"]);

/** The consensus block: the convergence track's canonical findings (+ consensus metadata), ids unique, verdict derived. */
export function buildConsensusBlock(consensus: ScoringResult): ConsensusFindingsBlock {
  const used = new Set<string>();
  const findings = consensus.convergence.map((scored) => {
    const base = String(scored.finding.id ?? "F");
    let id = base;
    for (let n = 2; used.has(id); n++) id = `${base}~${n}`;
    used.add(id);
    return { ...scored.finding, id, agreeing_models: scored.agreeing_models, consensus_classification: scored.classification };
  });
  const blocking = findings.some((f) => (f as Record<string, unknown>).blocking === true || BLOCKING.has(String(f.severity).toUpperCase()));
  return { schema_version: 1, verdict: blocking ? "REQUEST_CHANGES" : "COMMENT", findings };
}


/**
 * The deterministic block text (2-space JSON inside the markers). `<`, `>` and backticks occur only inside JSON strings
 * and are written as \\u escapes, so voice text can neither open or close a marker nor end the code fence (the
 * parsed values — what the guard and the verdict read — are unchanged).
 */
export function renderFindingsBlock(block: ConsensusFindingsBlock): string {
  const json = JSON.stringify(block, null, 2).replace(/[<>`]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return `${FINDINGS_START}\n\`\`\`json\n${json}\n\`\`\`\n${FINDINGS_END}`;
}

export type ComposeWriter =
  | { output: string; stance: ToolStance | undefined; toolCallsAttempted?: number; allowlist: readonly string[]; label: string }
  | { notEligible: string; label: string };

export interface ComposeInput {
  /** Title, models and statistics (and the verdict-quality header) — rendered above the findings. */
  header: string;
  consensus: ScoringResult;
  writer?: ComposeWriter;
  coverage?: CoverageRecord;
  /** Degradations established before composition (coverage, unparsed voices). */
  degradedReasons?: DegradedReason[];
}

export interface ComposedReview {
  body: string;
  block: ConsensusFindingsBlock;
  guard?: GuardResult;
  degradedReasons: DegradedReason[];
  verdict: ReviewVerdict;
}

/** A third-party string safe for one line of posted markdown. */
function oneLine(text: string, max = 200): string {
  return text.replace(/[\r\n`]+/g, " ").slice(0, max);
}

/** Assemble the consensus review: header, rendered block, admitted commentary or the withheld notice, coverage. */
export function composeConsensusReview(input: ComposeInput): ComposedReview {
  const block = buildConsensusBlock(input.consensus);
  const reasons: DegradedReason[] = [...(input.degradedReasons ?? [])];
  let guard: GuardResult | undefined;
  let commentary: string | undefined;
  let withheld: string | undefined;
  const w = input.writer;
  if (w && "notEligible" in w) {
    reasons.push("writer_not_eligible");
    withheld = `writer_not_eligible — ${oneLine(w.label)}: ${oneLine(w.notEligible)}`;
  } else if (w) {
    const eligibility = checkWriterEligibility(w.stance, w.allowlist, { toolCallsAttempted: w.toolCallsAttempted });
    if (!eligibility.eligible) {
      reasons.push("writer_not_eligible");
      withheld = `writer_not_eligible — ${oneLine(w.label)}: ${oneLine(eligibility.reason)}`;
    } else {
      guard = guardEnrichment(w.output, block);
      if (guard.accepted) commentary = guard.commentary.trim();
      else {
        reasons.push("enrichment_guard_rejected");
        withheld = `enrichment_guard_rejected — ${guard.reason}: ${oneLine(guard.detail)}`;
      }
    }
  }

  const parts: string[] = [input.header.trimEnd(), "", "## Consensus findings", "", renderFindingsBlock(block)];
  if (commentary) {
    parts.push("", "---", "", "## Commentary", "",
      `_Written by ${oneLine(w!.label)} from the consensus findings above; commentary never adds, removes or changes a finding._`,
      "", commentary);
  } else if (withheld) {
    parts.push("", `> **Enrichment withheld** (${withheld}). The consensus findings above are posted un-enriched.`);
  }
  if (input.coverage) parts.push("", formatCoverageSection(input.coverage));
  const body = parts.join("\n");
  const ordered = orderDegradedReasons(reasons);
  return {
    body, block, ...(guard ? { guard } : {}), degradedReasons: ordered,
    verdict: summarizeReviewVerdict(body, [], { degradedReasons: ordered }),
  };
}
