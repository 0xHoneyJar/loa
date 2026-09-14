import { FindingsBlockSchema } from "./schemas.js";
import { z } from "zod/v4";
import { Parser } from "commonmark";
import type { ReviewResponse } from "../ports/llm-provider.js";

export interface ReviewVerdict {
  verdict: "REQUEST_CHANGES" | "APPROVE" | "COMMENT" | "UNKNOWN";
  highestSeverity: string | null;
  mergeBlocked: boolean;
}

// Clearance accepts only complete, internally consistent APPROVED evidence.
// Delivery may still succeed for legacy responses without this envelope.
const ApprovedQualitySchema = z.object({
  status: z.literal("APPROVED"),
  consensus_outcome: z.literal("consensus"),
  truncation_waiver_applied: z.literal(false),
  voices_planned: z.number().int().min(1),
  voices_succeeded: z.number().int().min(1),
  voices_succeeded_ids: z.array(z.string().regex(/^[A-Za-z0-9._-]+$/)),
  voices_dropped: z.array(z.never()).length(0),
  chain_health: z.literal("ok"),
  confidence_floor: z.enum(["high", "med", "low"]),
  rationale: z.string().min(1).max(1024),
  single_voice_call: z.boolean().optional(),
  scoring_degraded: z.literal(false).optional(),
  chunked: z.boolean().optional(),
  chunks_reviewed: z.number().int().min(0).optional(),
  chunks_dropped: z.literal(0).optional(),
  chunks_aggregated_findings: z.number().int().min(0).optional(),
}).strict();

export function hasApprovedReviewQuality(response: ReviewResponse | undefined): boolean {
  if (!response || response.errorState != null) return false;
  const result = ApprovedQualitySchema.safeParse(response.verdictQuality);
  if (!result.success) return false;
  const quality = result.data;
  return quality.voices_planned === quality.voices_succeeded &&
    quality.voices_succeeded_ids.length === quality.voices_succeeded &&
    new Set(quality.voices_succeeded_ids).size === quality.voices_succeeded &&
    (!quality.single_voice_call || quality.voices_planned === 1);
}

/** Read operative prose from CommonMark blocks, never code or quoted examples. */
function reviewProse(content: string): string {
  const lines: string[] = [];
  const walker = new Parser().parse(content).walker();
  let block: string | undefined;
  let containsHTML = false;
  let event;
  while ((event = walker.next())) {
    const { node, entering } = event;
    if (entering && node.type === "block_quote") {
      walker.resumeAt(node, false);
      continue;
    }
    if (entering && node.type === "image") {
      if (block !== undefined) block += "\uFFFC";
      walker.resumeAt(node, false);
      continue;
    }
    if (node.type === "paragraph" || node.type === "heading") {
      if (entering) {
        block = node.type === "heading" ? "# " : node.parent?.type === "item" ? "- " : "";
        containsHTML = false;
      } else {
        // Inline HTML may wrap an example across several lines. The operative
        // contract is Markdown prose; raw HTML paragraphs grant no verdict.
        if (!containsHTML && block !== undefined) lines.push(block);
        block = undefined;
      }
    } else if (entering && block !== undefined) {
      if (node.type === "text") block += node.literal;
      if (node.type === "softbreak" || node.type === "linebreak") block += "\n";
      // Keep an opaque boundary instead of joining text around a removed span
      // into a new verdict. CommonMark resolves multiline/multi-backtick spans.
      if (node.type === "code") block += "\uFFFC";
      if (node.type === "html_inline") containsHTML = true;
    }
  }
  return lines.join("\n");
}

export function combineReviewVerdicts(decisions: ReadonlyArray<ReviewVerdict>): ReviewVerdict {
  const highestSeverity = ["CRITICAL", "BLOCKER", "HIGH", "MEDIUM", "LOW"]
    .find((severity) => decisions.some((decision) => decision.highestSeverity === severity)) ?? null;
  const verdict = decisions.some((decision) => decision.verdict === "REQUEST_CHANGES") ? "REQUEST_CHANGES"
    : decisions.length === 0 || decisions.some((decision) => decision.verdict === "UNKNOWN") ? "UNKNOWN"
    : decisions.some((decision) => decision.verdict === "COMMENT") ? "COMMENT" : "APPROVE";
  return { verdict, highestSeverity, mergeBlocked: verdict !== "APPROVE" || decisions.some((decision) => decision.mergeBlocked) };
}

/** Review transport success and GitHub COMMENTED state are not merge clearance. */
export function summarizeReviewVerdict(
  content: string,
  findings: ReadonlyArray<{ severity: string }> = [],
): ReviewVerdict {
  const severities = ["CRITICAL", "BLOCKER", "HIGH", "MEDIUM", "LOW"];
  const found = new Set(findings.map((finding) => finding.severity.toUpperCase()));
  let invalidFindings = false;
  const start = "<!-- bridge-findings-start -->";
  const end = "<!-- bridge-findings-end -->";
  if (content.includes(start)) {
    const blocks = content.split(start).slice(1);
    for (const block of blocks) {
      try {
        if (!block.includes(end)) throw new Error("Missing findings end");
        const json = block.split(end)[0].trim().replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
        const parsed = FindingsBlockSchema.safeParse(JSON.parse(json));
        if (!parsed.success) invalidFindings = true;
        else for (const finding of parsed.data.findings) found.add(finding.severity.toUpperCase());
      } catch {
        invalidFindings = true;
      }
    }
  }
  const prose = reviewProse(content);
  // Also recognize prose review severity headings.
  for (const match of prose.matchAll(/^\s*(?:#{1,6}\s*|[-*]\s+)(CRITICAL|BLOCKER|HIGH|MEDIUM|LOW)\b/gm)) {
    found.add(match[1]);
  }
  const knownSeverities = [...severities, "PRAISE", "INFO", "STYLE", "VISION", "SPECULATION"];
  if ([...found].some((severity) => !knownSeverities.includes(severity))) invalidFindings = true;
  const highestSeverity = severities.find((severity) => found.has(severity)) ?? null;
  const explicit = new Set<string>();
  for (const line of prose.split("\n")) {
    const match = line.match(/^\s*(?:#{1,6}\s*)?(?:(?:Verdict|Recommendation)\s*:\s*)?(REQUEST_CHANGES|APPROVE|COMMENT)\s*[.!]?\s*$/i);
    if (match) explicit.add(match[1].toUpperCase());
  }
  let verdict: ReviewVerdict["verdict"] = "UNKNOWN";
  if (/\bREQUEST_CHANGES\b/.test(prose) || ["CRITICAL", "BLOCKER", "HIGH"].includes(highestSeverity ?? "") ||
      /\b(critical|security vulnerability|sql injection|xss|secret leak|must fix)\b/i.test(prose)) {
    verdict = "REQUEST_CHANGES";
  } else if (!invalidFindings && explicit.size === 1) {
    verdict = [...explicit][0] as ReviewVerdict["verdict"];
  }
  return { verdict, highestSeverity, mergeBlocked: verdict !== "APPROVE" };
}
