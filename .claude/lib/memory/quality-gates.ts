/**
 * Memory Quality Gates — 6 pure filter functions for memory entry evaluation.
 * All functions are pure (no I/O, no side effects). Per SDD Section 4.2.1.
 */

// ── Types ────────────────────────────────────────────

export interface MemoryEntry {
  content: string;
  timestamp: number;
  source: string;
  confidence?: number;
  metadata?: Record<string, unknown>;
}

export type GateResult = { pass: boolean; reason?: string };

// ── Speculation Language ─────────────────────────────

const SPECULATION_WORDS = [
  "might",
  "maybe",
  "perhaps",
  "probably",
  "possibly",
  "could be",
  "likely",
  "unlikely",
  "it seems",
  "i think",
  "i believe",
  "not sure",
  "uncertain",
  "guess",
  "assume",
];

const INSTRUCTION_PREFIXES = [
  "please ",
  "you should ",
  "make sure ",
  "don't forget ",
  "remember to ",
  "try to ",
  "always ",
  "never ",
  "do not ",
];

// ── Gate Functions ───────────────────────────────────

export function temporalGate(
  entry: MemoryEntry,
  maxAgeMs: number,
  clock?: { now(): number },
): GateResult {
  const now = clock?.now() ?? Date.now();
  const age = now - entry.timestamp;
  if (age > maxAgeMs) {
    return { pass: false, reason: `Entry too old: ${Math.round(age / 1000)}s > ${Math.round(maxAgeMs / 1000)}s` };
  }
  return { pass: true };
}

export function speculationGate(entry: MemoryEntry): GateResult {
  const lower = entry.content.toLowerCase();
  for (const word of SPECULATION_WORDS) {
    if (lower.includes(word)) {
      return { pass: false, reason: `Speculation detected: "${word}"` };
    }
  }
  return { pass: true };
}

export function instructionGate(entry: MemoryEntry): GateResult {
  const lower = entry.content.toLowerCase();
  for (const prefix of INSTRUCTION_PREFIXES) {
    if (lower.startsWith(prefix)) {
      return { pass: false, reason: `Instruction content: starts with "${prefix.trim()}"` };
    }
  }
  return { pass: true };
}

export function confidenceGate(
  entry: MemoryEntry,
  threshold: number = 0.5,
): GateResult {
  if (entry.confidence !== undefined && entry.confidence < threshold) {
    return {
      pass: false,
      reason: `Low confidence: ${entry.confidence} < ${threshold}`,
    };
  }
  return { pass: true };
}

export function qualityGate(entry: MemoryEntry): GateResult {
  // Composite quality: content length and substance
  if (entry.content.trim().length < 10) {
    return { pass: false, reason: "Content too short (< 10 chars)" };
  }
  // Check for pure whitespace or repetitive content
  const unique = new Set(entry.content.toLowerCase().split(/\s+/)).size;
  if (unique < 3) {
    return { pass: false, reason: "Content lacks substance (< 3 unique words)" };
  }
  return { pass: true };
}

export function technicalGate(entry: MemoryEntry): GateResult {
  // Must contain at least one technical indicator
  const technicalPatterns = [
    /\b(?:function|class|interface|type|const|let|var|import|export)\b/,
    /\b(?:error|bug|fix|test|api|http|sql|json|xml|html|css)\b/i,
    /\b(?:file|directory|path|module|package|library|framework)\b/i,
    /\b(?:config|setting|option|parameter|argument|flag)\b/i,
    /[./:_\-]{2,}/, // Paths, URLs, identifiers
    /\b\d+\.\d+/, // Version numbers
  ];

  for (const pattern of technicalPatterns) {
    if (pattern.test(entry.content)) {
      return { pass: true };
    }
  }
  return { pass: false, reason: "No technical content detected" };
}

// ── Composite ────────────────────────────────────────

export function evaluateAllGates(
  entry: MemoryEntry,
  config?: {
    maxAgeMs?: number;
    confidenceThreshold?: number;
    clock?: { now(): number };
  },
): GateResult {
  const gates: GateResult[] = [
    config?.maxAgeMs
      ? temporalGate(entry, config.maxAgeMs, config.clock)
      : { pass: true },
    speculationGate(entry),
    instructionGate(entry),
    confidenceGate(entry, config?.confidenceThreshold),
    qualityGate(entry),
    technicalGate(entry),
  ];

  for (const result of gates) {
    if (!result.pass) return result;
  }
  return { pass: true };
}
