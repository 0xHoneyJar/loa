/**
 * PII Redactor — detection and redaction of personally identifiable information.
 *
 * 15+ built-in regex patterns + Shannon entropy detector.
 * Constructor-injectable custom patterns. Per SDD Section 4.1.1.
 *
 * All built-in patterns avoid nested quantifiers to prevent catastrophic
 * backtracking (Flatline IMP-003).
 */
import { LoaLibError } from "../errors.js";

// ── Types ────────────────────────────────────────────

export interface PIIPattern {
  name: string;
  regex: RegExp;
  replacement: string;
}

export interface PIIRedactorConfig {
  patterns?: PIIPattern[];
  disabledBuiltins?: string[];
  entropyThreshold?: number; // Default: 4.5 bits/char
  minEntropyLength?: number; // Default: 20 chars
}

export interface RedactionMatch {
  pattern: string;
  position: number;
  length: number;
}

// ── Built-in Patterns ────────────────────────────────

const BUILTIN_PATTERNS: PIIPattern[] = [
  {
    name: "email",
    regex: /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g,
    replacement: "[REDACTED_EMAIL]",
  },
  {
    name: "ssn",
    regex: /\b\d{3}-\d{2}-\d{4}\b/g,
    replacement: "[REDACTED_SSN]",
  },
  {
    name: "phone_us",
    regex: /\b(?:\+1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/g,
    replacement: "[REDACTED_PHONE]",
  },
  {
    name: "phone_intl",
    regex: /\b\+\d{1,3}[\s.-]?\d{4,14}\b/g,
    replacement: "[REDACTED_PHONE]",
  },
  {
    name: "credit_card",
    regex: /\b\d{4}[\s.-]?\d{4}[\s.-]?\d{4}[\s.-]?\d{4}\b/g,
    replacement: "[REDACTED_CC]",
  },
  {
    name: "aws_key_id",
    regex: /\bAKIA[0-9A-Z]{16}\b/g,
    replacement: "[REDACTED_AWS_KEY]",
  },
  {
    name: "aws_secret",
    // Exclude hex-only 40-char strings (SHA-1 hashes, git commits) — cycle-028 FR-7
    regex: /\b(?![0-9a-fA-F]{40}\b)[A-Za-z0-9/+=]{40}\b/g,
    replacement: "[REDACTED_AWS_SECRET]",
  },
  {
    name: "github_token",
    regex: /\bg(?:hp|ho|hu|hs|hr)_[A-Za-z0-9_]{36,255}\b/g,
    replacement: "[REDACTED_GITHUB_TOKEN]",
  },
  {
    name: "generic_api_key",
    regex: /\b(?:api[_-]?key|apikey|token|secret|password)[\s]*[=:]\s*["']?[A-Za-z0-9_\-./+=]{16,}["']?/gi,
    replacement: "[REDACTED_API_KEY]",
  },
  {
    name: "ipv4",
    regex: /\b(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b/g,
    replacement: "[REDACTED_IP]",
  },
  {
    name: "ipv6",
    regex: /\b(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}\b/g,
    replacement: "[REDACTED_IPV6]",
  },
  {
    name: "jwt",
    regex: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/g,
    replacement: "[REDACTED_JWT]",
  },
  {
    name: "uuid",
    regex: /\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b/g,
    replacement: "[REDACTED_UUID]",
  },
  {
    name: "date_of_birth",
    regex: /\b(?:19|20)\d{2}[-/](?:0[1-9]|1[0-2])[-/](?:0[1-9]|[12]\d|3[01])\b/g,
    replacement: "[REDACTED_DOB]",
  },
  {
    name: "passport",
    regex: /\b[A-Z]{1,2}\d{6,9}\b/g,
    replacement: "[REDACTED_PASSPORT]",
  },
  {
    name: "private_key_header",
    regex: /-----BEGIN (?:RSA |EC |DSA )?PRIVATE KEY-----/g,
    replacement: "[REDACTED_PRIVATE_KEY]",
  },
];

// ── Shannon Entropy ──────────────────────────────────

function shannonEntropy(str: string): number {
  const freq = new Map<string, number>();
  for (const ch of str) {
    freq.set(ch, (freq.get(ch) ?? 0) + 1);
  }
  let entropy = 0;
  const len = str.length;
  for (const count of freq.values()) {
    const p = count / len;
    entropy -= p * Math.log2(p);
  }
  return entropy;
}

function findHighEntropySubstrings(
  input: string,
  threshold: number,
  minLength: number,
): RedactionMatch[] {
  const matches: RedactionMatch[] = [];
  // Split on whitespace and common delimiters to find token boundaries
  const tokenRegex = /[^\s,;:'"(){}\[\]<>]+/g;
  let match: RegExpExecArray | null;

  while ((match = tokenRegex.exec(input)) !== null) {
    const token = match[0];
    if (token.length >= minLength && shannonEntropy(token) >= threshold) {
      matches.push({
        pattern: "high_entropy",
        position: match.index,
        length: token.length,
      });
    }
  }
  return matches;
}

// ── PIIRedactor Class ────────────────────────────────

export class PIIRedactor {
  private readonly patterns: PIIPattern[];
  private readonly entropyThreshold: number;
  private readonly minEntropyLength: number;

  constructor(config?: PIIRedactorConfig) {
    const disabled = new Set(config?.disabledBuiltins ?? []);
    const builtins = BUILTIN_PATTERNS.filter((p) => !disabled.has(p.name));
    this.patterns = [...builtins, ...(config?.patterns ?? [])];
    this.entropyThreshold = config?.entropyThreshold ?? 4.5;
    this.minEntropyLength = config?.minEntropyLength ?? 20;
  }

  redact(input: string): { output: string; matches: RedactionMatch[] } {
    if (!input) return { output: input, matches: [] };

    const allMatches: RedactionMatch[] = [];

    // Collect all pattern matches with positions
    type RawMatch = { pattern: string; start: number; end: number; replacement: string };
    const rawMatches: RawMatch[] = [];

    for (const pat of this.patterns) {
      // Ensure global flag to safely iterate all matches
      const flags = pat.regex.flags.includes("g") ? pat.regex.flags : pat.regex.flags + "g";
      const regex = new RegExp(pat.regex.source, flags);
      let m: RegExpExecArray | null;
      while ((m = regex.exec(input)) !== null) {
        // Guard against zero-length matches to prevent infinite loops
        if (m[0].length === 0) {
          regex.lastIndex++;
          continue;
        }
        rawMatches.push({
          pattern: pat.name,
          start: m.index,
          end: m.index + m[0].length,
          replacement: pat.replacement,
        });
      }
    }

    // Add entropy matches
    const entropyMatches = findHighEntropySubstrings(
      input,
      this.entropyThreshold,
      this.minEntropyLength,
    );
    for (const em of entropyMatches) {
      rawMatches.push({
        pattern: em.pattern,
        start: em.position,
        end: em.position + em.length,
        replacement: "[REDACTED_HIGH_ENTROPY]",
      });
    }

    // Sort by position, prefer longer when same start
    rawMatches.sort((a, b) => a.start - b.start || (b.end - b.start) - (a.end - a.start));

    // Select non-overlapping matches where the longest wins within any overlap group
    const selected: RawMatch[] = [];
    let current: RawMatch | undefined;
    for (const rm of rawMatches) {
      if (!current) {
        current = rm;
        continue;
      }
      if (rm.start >= current.end) {
        selected.push(current);
        current = rm;
      } else {
        // Overlap: keep the longest match
        const currLen = current.end - current.start;
        const rmLen = rm.end - rm.start;
        if (rmLen > currLen) {
          current = rm;
        }
      }
    }
    if (current) selected.push(current);

    // Process left-to-right, no re-scanning of redacted regions
    let output = "";
    let cursor = 0;

    for (const rm of selected) {
      output += input.slice(cursor, rm.start) + rm.replacement;
      allMatches.push({
        pattern: rm.pattern,
        position: rm.start,
        length: rm.end - rm.start,
      });
      cursor = rm.end;
    }
    output += input.slice(cursor);

    return { output, matches: allMatches };
  }

  addPattern(pattern: PIIPattern): void {
    this.patterns.push(pattern);
  }

  getPatterns(): readonly PIIPattern[] {
    return this.patterns;
  }
}

export function createPIIRedactor(config?: PIIRedactorConfig): PIIRedactor {
  return new PIIRedactor(config);
}
