/**
 * Quality Gates — 4-gate quality filter for compound learnings.
 *
 * Extracted from deploy/loa-identity/quality-gates.ts.
 * Portable: no container dependencies.
 *
 * Gates:
 *   G1: Discovery Depth — Is the solution non-trivial?
 *   G2: Reusability      — Is the pattern generalizable?
 *   G3: Trigger Clarity   — Can we identify when this applies?
 *   G4: Verification      — Was the solution verified to work?
 *
 * @module .claude/lib/persistence/learning/quality-gates
 */

import type { Learning, QualityGates, IQualityGateScorer } from "./learning-store.js";

// ── Thresholds ─────────────────────────────────────────────

export const GATE_THRESHOLDS = {
  discovery_depth: 5,
  reusability: 5,
  trigger_clarity: 5,
  verification: 3,
} as const;

export const MINIMUM_TOTAL_SCORE = 18;

// ── Gate Scorers ───────────────────────────────────────────

export function scoreDiscoveryDepth(learning: Partial<Learning>): number {
  let score = 0;
  const patternLength = (learning.pattern || "").length;
  if (patternLength > 500) score += 3;
  else if (patternLength > 200) score += 2;
  else if (patternLength > 50) score += 1;

  const solutionLength = (learning.solution || "").length;
  if (solutionLength > 500) score += 3;
  else if (solutionLength > 200) score += 2;
  else if (solutionLength > 50) score += 1;

  if (/```[\s\S]*```|`[^`]+`/.test(learning.solution || "")) score += 2;
  if (/when|if|after|before|during/i.test(learning.trigger || "")) score += 2;

  return Math.min(10, score);
}

export function scoreReusability(learning: Partial<Learning>): number {
  let score = 0;
  const text = `${learning.trigger || ""} ${learning.pattern || ""}`.toLowerCase();

  const genericTerms = [
    "similar",
    "pattern",
    "approach",
    "strategy",
    "general",
    "common",
    "typical",
    "often",
    "usually",
    "any",
    "all",
  ];
  score += Math.min(3, genericTerms.filter((t) => text.includes(t)).length);

  const specificIndicators = [
    "only this file",
    "just for",
    "exactly this",
    "specific to",
    "unique case",
    "one-time",
    "temporary fix",
  ];
  score -= Math.min(3, specificIndicators.filter((t) => text.includes(t)).length * 2);

  if (/or|and|also|as well|multiple/i.test(learning.trigger || "")) score += 2;

  if (learning.target === "loa" || learning.target === "devcontainer") score += 2;
  else score += 1;

  if (learning.pattern && learning.pattern.length > 0) score += 2;

  return Math.max(0, Math.min(10, score));
}

export function scoreTriggerClarity(learning: Partial<Learning>): number {
  let score = 0;
  const trigger = learning.trigger || "";
  if (trigger.length === 0) return 0;

  const conditionalPatterns = [
    /when\s+\w+/i,
    /if\s+\w+/i,
    /after\s+\w+/i,
    /before\s+\w+/i,
    /during\s+\w+/i,
    /whenever\s+\w+/i,
  ];
  score += Math.min(4, conditionalPatterns.filter((p) => p.test(trigger)).length * 2);

  const actionPatterns = [
    /error|fail|crash|exception/i,
    /deploy|build|test|install/i,
    /create|update|delete|modify/i,
    /start|stop|restart|initialize/i,
    /request|response|api|endpoint/i,
  ];
  score += Math.min(3, actionPatterns.filter((p) => p.test(trigger)).length);

  if (trigger.length >= 20 && trigger.length <= 200) score += 2;
  else if (trigger.length >= 10) score += 1;

  if (/in\s+\w+|with\s+\w+|using\s+\w+|for\s+\w+/i.test(trigger)) score += 1;

  return Math.min(10, score);
}

export function scoreVerification(learning: Partial<Learning>): number {
  let score = 0;

  if (learning.source === "sprint") score += 3;
  else if (learning.source === "error-cycle") score += 2;
  else if (learning.source === "retrospective") score += 1;

  const solution = learning.solution || "";
  const terms = [
    "tested",
    "verified",
    "confirmed",
    "works",
    "successful",
    "passed",
    "validated",
    "checked",
  ];
  score += Math.min(3, terms.filter((t) => solution.toLowerCase().includes(t)).length);

  if (learning.effectiveness) {
    const { successes, applications } = learning.effectiveness;
    if (applications > 0) {
      const rate = successes / applications;
      if (rate >= 0.8) score += 3;
      else if (rate >= 0.6) score += 2;
      else if (rate >= 0.4) score += 1;
    }
  }

  if (solution.length > 0) score += 1;

  return Math.min(10, score);
}

// ── Combined Scoring ───────────────────────────────────────

export function scoreAllGates(learning: Partial<Learning>): QualityGates {
  return {
    discovery_depth: scoreDiscoveryDepth(learning),
    reusability: scoreReusability(learning),
    trigger_clarity: scoreTriggerClarity(learning),
    verification: scoreVerification(learning),
  };
}

export function passesQualityGates(learning: Partial<Learning>): boolean {
  const gates = learning.gates || scoreAllGates(learning);

  if (gates.discovery_depth < GATE_THRESHOLDS.discovery_depth) return false;
  if (gates.reusability < GATE_THRESHOLDS.reusability) return false;
  if (gates.trigger_clarity < GATE_THRESHOLDS.trigger_clarity) return false;
  if (gates.verification < GATE_THRESHOLDS.verification) return false;

  const total =
    gates.discovery_depth + gates.reusability + gates.trigger_clarity + gates.verification;

  return total >= MINIMUM_TOTAL_SCORE;
}

// ── Scorer Implementation ──────────────────────────────────

/** Default quality gate scorer implementing IQualityGateScorer. */
export class DefaultQualityGateScorer implements IQualityGateScorer {
  scoreAll(learning: Partial<Learning>): QualityGates {
    return scoreAllGates(learning);
  }

  passes(learning: Partial<Learning>): boolean {
    return passesQualityGates(learning);
  }
}
