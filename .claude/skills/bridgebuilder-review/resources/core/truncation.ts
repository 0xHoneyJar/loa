import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import path from "node:path";
import type { PullRequestFile } from "../ports/git-provider.js";
import type {
  BridgebuilderConfig,
  TruncationResult,
  LoaDetectionResult,
  SecurityPatternEntry,
  TokenBudget,
  ProgressiveTruncationResult,
  TokenEstimateBreakdown,
} from "./types.js";

// --- Security Patterns Registry (Task 1.1 — SDD Section 3.6) ---

export const SECURITY_PATTERNS: SecurityPatternEntry[] = [
  // Authentication & Authorization
  { pattern: /(?:^|\/)auth/i, category: "auth", rationale: "Authentication modules" },
  { pattern: /(?:^|\/)login/i, category: "auth", rationale: "Login endpoints" },
  { pattern: /(?:^|\/)oauth/i, category: "auth", rationale: "OAuth flows" },
  { pattern: /(?:^|\/)session/i, category: "auth", rationale: "Session management" },
  { pattern: /(?:^|\/)acl/i, category: "auth", rationale: "Access control lists" },
  { pattern: /(?:^|\/)permissions?[./]/i, category: "auth", rationale: "Permission checks" },
  { pattern: /(?:^|\/)rbac/i, category: "auth", rationale: "Role-based access control" },
  { pattern: /(?:^|\/)middleware\/auth/i, category: "auth", rationale: "Auth middleware" },

  // Cryptography & Secrets
  { pattern: /(?:^|\/)crypto/i, category: "crypto", rationale: "Cryptographic operations" },
  { pattern: /(?:^|\/)secret/i, category: "crypto", rationale: "Secret management" },
  { pattern: /(?:^|\/)password/i, category: "crypto", rationale: "Password handling" },
  { pattern: /(?:^|\/)credential/i, category: "crypto", rationale: "Credential storage" },
  { pattern: /(?:^|\/)security/i, category: "crypto", rationale: "Security configurations" },
  { pattern: /\.pem$/i, category: "crypto", rationale: "PEM certificates" },
  { pattern: /\.key$/i, category: "crypto", rationale: "Private key files" },
  { pattern: /(?:^|\/)\.env/i, category: "crypto", rationale: "Environment secrets" },
  { pattern: /(?:^|\/)vault/i, category: "crypto", rationale: "Secret vault config" },

  // CI/CD & Supply Chain
  { pattern: /(?:^|\/)\.github\/workflows\//i, category: "cicd", rationale: "GitHub Actions workflows" },
  { pattern: /(?:^|\/)\.gitlab-ci/i, category: "cicd", rationale: "GitLab CI config" },
  { pattern: /(?:^|\/)Jenkinsfile/i, category: "cicd", rationale: "Jenkins pipeline" },
  { pattern: /(?:^|\/)Dockerfile/i, category: "cicd", rationale: "Container build definition" },
  { pattern: /(?:^|\/)docker-compose/i, category: "cicd", rationale: "Container orchestration" },
  { pattern: /(?:^|\/)Makefile/i, category: "cicd", rationale: "Build system commands" },

  // Infrastructure as Code
  { pattern: /\.tf$/i, category: "iac", rationale: "Terraform configs" },
  { pattern: /(?:^|\/)helm\//i, category: "iac", rationale: "Helm charts" },
  { pattern: /(?:^|\/)k8s\//i, category: "iac", rationale: "Kubernetes manifests" },
  { pattern: /(?:^|\/)kubernetes\//i, category: "iac", rationale: "Kubernetes manifests" },
  { pattern: /(?:^|\/)pulumi/i, category: "iac", rationale: "Pulumi infrastructure" },

  // Dependency Lockfiles
  { pattern: /(?:^|\/)package-lock\.json$/i, category: "lockfile", rationale: "npm dependency lock" },
  { pattern: /(?:^|\/)yarn\.lock$/i, category: "lockfile", rationale: "Yarn dependency lock" },
  { pattern: /(?:^|\/)pnpm-lock\.yaml$/i, category: "lockfile", rationale: "pnpm dependency lock" },
  { pattern: /(?:^|\/)go\.sum$/i, category: "lockfile", rationale: "Go dependency checksums" },
  { pattern: /(?:^|\/)Cargo\.lock$/i, category: "lockfile", rationale: "Rust dependency lock" },
  { pattern: /(?:^|\/)Gemfile\.lock$/i, category: "lockfile", rationale: "Ruby dependency lock" },
  { pattern: /(?:^|\/)poetry\.lock$/i, category: "lockfile", rationale: "Python dependency lock" },
  { pattern: /(?:^|\/)composer\.lock$/i, category: "lockfile", rationale: "PHP dependency lock" },

  // Security Policy Files
  { pattern: /(?:^|\/)SECURITY\.md$/i, category: "policy", rationale: "Security policy" },
  { pattern: /(?:^|\/)CODEOWNERS$/i, category: "policy", rationale: "Code ownership rules" },
  { pattern: /(?:^|\/)\.github\/CODEOWNERS$/i, category: "policy", rationale: "GitHub CODEOWNERS" },
];

export function isHighRisk(filename: string): boolean {
  return SECURITY_PATTERNS.some((p) => p.pattern.test(filename));
}

export function getSecurityCategory(filename: string): string | undefined {
  const match = SECURITY_PATTERNS.find((p) => p.pattern.test(filename));
  return match?.category;
}

// --- Pattern Matching (SDD Section 3.8) ---

/** Detect if Node 22+ path.matchesGlob is available (BB-F4). */
const hasNativeGlob: boolean =
  typeof (path as Record<string, unknown>).matchesGlob === "function";

/**
 * Simple glob matcher fallback for Node <22.
 * Supports: `*.ext`, `prefix*`, `prefix*suffix`, exact match, substring match,
 * `?` single character wildcards, and `**` recursive directory matching.
 */
function simplifiedGlobMatch(filename: string, pattern: string): boolean {
  // Handle ** recursive patterns: src/**/*.ts
  if (pattern.includes("**")) {
    // Convert glob to regex: ** matches any number of path segments
    const escaped = pattern
      .split("**")
      .map((part) =>
        part
          .split("*")
          .map((seg) => seg.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\?/g, "[^/]"))
          .join("[^/]*"),
      )
      .join(".*");
    return new RegExp(`^${escaped}$`).test(filename);
  }

  // Handle ? single character wildcard (matches any char except /)
  if (pattern.includes("?")) {
    const escaped = pattern
      .split("*")
      .map((part) => part.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\?/g, "[^/]"))
      .join("[^/]*");
    return new RegExp(`^${escaped}$`).test(filename);
  }

  // Original simplified matching for basic patterns
  if (pattern.startsWith("*")) {
    const suffix = pattern.slice(1);
    if (filename.endsWith(suffix)) return true;
  } else if (pattern.endsWith("*")) {
    const prefix = pattern.slice(0, -1);
    if (filename.startsWith(prefix)) return true;
  } else if (pattern.includes("*")) {
    const [before, after] = pattern.split("*", 2);
    if (filename.startsWith(before) && filename.endsWith(after)) return true;
  } else {
    if (filename === pattern || filename.includes(pattern)) return true;
  }
  return false;
}

export function matchesExcludePattern(
  filename: string,
  patterns: string[],
): boolean {
  for (const pattern of patterns) {
    if (hasNativeGlob) {
      // Node 22+: use native path.matchesGlob() for full glob support
      if ((path as unknown as { matchesGlob(p: string, g: string): boolean }).matchesGlob(filename, pattern)) {
        return true;
      }
      // Fallback to simplified match for non-glob patterns (exact/substring)
      if (!pattern.includes("*") && !pattern.includes("?")) {
        if (filename === pattern || filename.includes(pattern)) return true;
      }
    } else {
      if (simplifiedGlobMatch(filename, pattern)) return true;
    }
  }
  return false;
}

// --- Loa Detection (Task 1.2 — SDD Section 3.1) ---

/** Default Loa framework exclude patterns.
 * Use ** for recursive directory matching (BB-F4). */
export const LOA_EXCLUDE_PATTERNS = [
  // Core framework (existing)
  ".claude/**",
  "grimoires/**",
  ".beads/**",
  ".loa-version.json",
  ".loa.config.yaml",
  ".loa.config.yaml.example",
  // State & runtime (Bug 1 — issue #309)
  "evals/**",
  ".run/**",
  ".flatline/**",
  // Docs & config (Bug 1 — issue #309)
  "PROCESS.md",
  "BUTTERFREEZONE.md",
  "INSTALLATION.md",
  "grimoires/**/NOTES.md",
];

/**
 * Load .reviewignore patterns from repo root and merge with LOA_EXCLUDE_PATTERNS.
 * Returns combined patterns array. Graceful when file missing (returns LOA patterns only).
 */
export function loadReviewIgnore(repoRoot?: string): string[] {
  const root = repoRoot ?? process.cwd();
  const reviewignorePath = resolve(root, ".reviewignore");

  const basePatterns = [...LOA_EXCLUDE_PATTERNS];

  try {
    if (!existsSync(reviewignorePath)) {
      return basePatterns;
    }
    const content: string = readFileSync(reviewignorePath, "utf-8");
    for (const rawLine of content.split("\n")) {
      const line = rawLine.trim();
      // Skip blank lines and comments
      if (!line || line.startsWith("#")) continue;
      // Normalize directory patterns: "dir/" → "dir/**"
      const pattern = line.endsWith("/") ? `${line}**` : line;
      // Avoid duplicates
      if (!basePatterns.includes(pattern)) {
        basePatterns.push(pattern);
      }
    }
  } catch {
    // Graceful: return base patterns on any error
  }

  return basePatterns;
}

/**
 * Detect if repo is Loa-mounted by reading .loa-version.json.
 * Resolves paths against repoRoot (git root), NOT cwd (SKP-001, IMP-004).
 *
 * Decision: sync I/O (existsSync/readFileSync) is intentional here.
 * truncateFiles() — the only caller — is synchronous (SDD §3.1), so async
 * would require a cascading refactor for zero runtime benefit.
 */
export function detectLoa(
  config: Pick<BridgebuilderConfig, "loaAware" | "repoRoot">,
): LoaDetectionResult {
  // Config override takes precedence
  if (config.loaAware === true) {
    return { isLoa: true, source: "config_override" };
  }
  if (config.loaAware === false) {
    return { isLoa: false, source: "config_override" };
  }

  // Resolve against repo root (SKP-001)
  const root = config.repoRoot ?? process.cwd();
  if (!config.repoRoot) {
    process.stderr.write(
      "[bridgebuilder] WARN: repoRoot not set, using cwd for Loa detection\n",
    );
  }

  const versionFile = resolve(root, ".loa-version.json");

  if (!existsSync(versionFile)) {
    return { isLoa: false, source: "file" };
  }

  try {
    const content = readFileSync(versionFile, "utf-8");
    const parsed = JSON.parse(content);

    if (
      typeof parsed.framework_version !== "string" ||
      !/^\d+\.\d+\.\d+/.test(parsed.framework_version)
    ) {
      process.stderr.write(
        `[bridgebuilder] WARN: .loa-version.json malformed (missing valid framework_version)\n`,
      );
      return { isLoa: false, source: "file" };
    }

    return {
      isLoa: true,
      version: parsed.framework_version,
      source: "file",
    };
  } catch {
    process.stderr.write(
      `[bridgebuilder] WARN: .loa-version.json could not be parsed\n`,
    );
    return { isLoa: false, source: "file" };
  }
}

// --- Loa System Zone Detection (Bug 2 fix — issue #309) ---

/** Paths that are definitively Loa framework system zones.
 * Security pattern matches in these zones get demoted to tier2 (summary)
 * instead of exception (full diff) to prevent framework file leakage. */
const LOA_SYSTEM_ZONE_PREFIXES = [
  ".claude/",
  "grimoires/",
  ".beads/",
  "evals/",
  ".run/",
  ".flatline/",
];

export function isLoaSystemZone(filename: string): boolean {
  return LOA_SYSTEM_ZONE_PREFIXES.some(prefix => filename.startsWith(prefix));
}

// --- Two-Tier Loa Exclusion (Task 1.3 — SDD Section 3.2) ---

/** Tier 1 extensions: content-excluded (stats only). */
const TIER1_EXTENSIONS = new Set([
  ".md", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico",
  ".lock", ".woff", ".woff2", ".ttf", ".eot", ".bmp", ".webp",
]);

/** Tier 2 extensions: summary-included (first hunk + stats). */
const TIER2_EXTENSIONS = new Set([
  ".sh", ".js", ".ts", ".py", ".yml", ".yaml", ".json", ".toml",
  ".mjs", ".cjs", ".jsx", ".tsx",
]);

/** Paths that should be Tier 2 minimum even if extension says Tier 1 (SKP-002). */
const TIER2_MIN_PATHS = [
  /(?:^|\/)\.github\//i,
  /(?:^|\/)infra\//i,
  /(?:^|\/)deploy\//i,
  /(?:^|\/)k8s\//i,
];

// Note: SECURITY.md and CODEOWNERS match SECURITY_PATTERNS above — no separate
// filename check needed. They are classified as "exception" (full diff always).

export type LoaTier = "tier1" | "tier2" | "exception";

export function classifyLoaFile(filename: string): LoaTier {
  // Security pattern match: full diff for app code, but demoted to tier2
  // for Loa system zone files (Bug 2 fix — issue #309)
  if (isHighRisk(filename)) {
    if (isLoaSystemZone(filename)) {
      return "tier2";
    }
    return "exception";
  }

  const basename = filename.split("/").pop() ?? "";
  const ext = basename.includes(".") ? "." + basename.split(".").pop()!.toLowerCase() : "";

  // SKP-002: path-based heuristics → Tier 2 minimum
  if (TIER2_MIN_PATHS.some((p) => p.test(filename))) {
    return "tier2";
  }

  if (TIER1_EXTENSIONS.has(ext)) {
    return "tier1";
  }

  if (TIER2_EXTENSIONS.has(ext)) {
    return "tier2";
  }

  // Default unknown extensions under Loa paths: Tier 1 (conservative — stats only)
  return "tier1";
}

/** Extract the first hunk from a unified diff patch. */
export function extractFirstHunk(patch: string): string {
  if (!patch) return patch;

  const lines = patch.split("\n");
  const hunkStarts: number[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].startsWith("@@")) {
      hunkStarts.push(i);
    }
  }

  if (hunkStarts.length <= 1) {
    return patch; // Single hunk or no hunks — return as-is
  }

  // Return everything up to the second hunk header
  return lines.slice(0, hunkStarts[1]).join("\n");
}

export interface LoaTierResult {
  /** Files that passed through (not under Loa paths, or exception). */
  passthrough: PullRequestFile[];
  /** Tier 1 excluded files: name + stats only. */
  tier1Excluded: Array<{ filename: string; stats: string }>;
  /** Tier 2 summary files: first hunk + stats. */
  tier2Summary: Array<{ filename: string; stats: string; summary: string }>;
  /** Total bytes saved by exclusion. */
  bytesSaved: number;
}

/**
 * Apply two-tier Loa exclusion to files under Loa paths.
 * Security check runs BEFORE tier classification (SDD 3.6).
 */
export function applyLoaTierExclusion(
  files: PullRequestFile[],
  loaPatterns: string[],
): LoaTierResult {
  const passthrough: PullRequestFile[] = [];
  const tier1Excluded: Array<{ filename: string; stats: string }> = [];
  const tier2Summary: Array<{ filename: string; stats: string; summary: string }> = [];
  let bytesSaved = 0;

  for (const file of files) {
    // Check if file is under a Loa path
    if (!matchesExcludePattern(file.filename, loaPatterns)) {
      passthrough.push(file);
      continue;
    }

    const tier = classifyLoaFile(file.filename);

    if (tier === "exception") {
      // Security files pass through even under Loa paths
      passthrough.push(file);
      continue;
    }

    const pBytes = file.patch ? new TextEncoder().encode(file.patch).byteLength : 0;
    bytesSaved += pBytes;

    if (tier === "tier1") {
      tier1Excluded.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions} (Loa framework, content excluded)`,
      });
    } else {
      // tier2: include first hunk summary
      const summary = file.patch ? extractFirstHunk(file.patch) : "";
      tier2Summary.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions} (Loa framework, summary only)`,
        summary,
      });
    }
  }

  return { passthrough, tier1Excluded, tier2Summary, bytesSaved };
}

// --- Token Budget Constants (IMP-001) ---
// Coefficients are chars-per-token ratios: 0.25 ≈ 4 chars/token (cl100k_base
// average for English prose + code). GPT-5.2 uses 0.23 per OpenAI's tokenizer
// calibration. These are intentionally conservative (over-estimate) to leave
// headroom and avoid context-window overflows at runtime.

export const TOKEN_BUDGETS: Record<string, TokenBudget> = {
  "claude-sonnet-4-6": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
  "claude-sonnet-4-5-20250929": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
  "claude-opus-4-6": { maxInput: 200_000, maxOutput: 8_192, coefficient: 0.25 },
  "gpt-5.2": { maxInput: 128_000, maxOutput: 4_096, coefficient: 0.23 },
  default: { maxInput: 100_000, maxOutput: 4_096, coefficient: 0.25 },
};

export function getTokenBudget(model: string): TokenBudget {
  return TOKEN_BUDGETS[model] ?? TOKEN_BUDGETS["default"];
}

/** Estimate tokens from string using model-specific coefficient. */
export function estimateTokens(text: string, model: string): number {
  const { coefficient } = getTokenBudget(model);
  return Math.ceil(text.length * coefficient);
}

// --- Progressive Truncation Helpers (Task 1.7) ---

/** Size threshold for security files to get hunk summary instead of full diff (SKP-005). */
const SECURITY_FILE_SIZE_CAP = 50_000; // 50KB
const SECURITY_MAX_HUNKS = 10;

/** Check if a test file is adjacent to a changed non-test file (IMP-002). */
export function isAdjacentTest(
  filename: string,
  allFiles: PullRequestFile[],
): boolean {
  if (!isTestFile(filename)) return false;
  const dir = filename.substring(0, filename.lastIndexOf("/") + 1);
  return allFiles.some(
    (f) =>
      f.filename !== filename &&
      !isTestFile(f.filename) &&
      f.filename.startsWith(dir),
  );
}

function isTestFile(filename: string): boolean {
  return /\.(test|spec)\.[^.]+$/.test(filename);
}

function isEntryOrConfig(filename: string): boolean {
  const basename = filename.split("/").pop() ?? "";
  return (
    /^(index|main|app)\.[^.]+$/.test(basename) ||
    /\.config\.[^.]+$/.test(basename) ||
    /\.(json|yaml|yml)$/.test(basename)
  );
}

/** Parse unified diff into hunks. Returns null on parse failure (SKP-003 fallback). */
export function parseHunks(
  patch: string,
): Array<{ header: string; lines: string[] }> | null {
  if (!patch) return [];

  try {
    const lines = patch.split("\n");
    const hunks: Array<{ header: string; lines: string[] }> = [];
    let current: { header: string; lines: string[] } | null = null;

    for (const line of lines) {
      if (line.startsWith("@@")) {
        if (current) hunks.push(current);
        current = { header: line, lines: [] };
      } else if (current) {
        current.lines.push(line);
      }
      // Lines before first @@ (diff header) are ignored in hunk parsing
    }

    if (current) hunks.push(current);
    return hunks;
  } catch {
    return null; // SKP-003: fallback to full patch
  }
}

/** Reduce context lines around changed hunks (3→1→0). */
export function reduceHunkContext(
  hunks: Array<{ header: string; lines: string[] }>,
  contextLines: number,
): Array<{ header: string; lines: string[] }> {
  return hunks.map((hunk) => {
    const kept: string[] = [];
    const lines = hunk.lines;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // Always keep changed lines
      if (line.startsWith("+") || line.startsWith("-")) {
        kept.push(line);
        continue;
      }
      // Keep context lines within range of a changed line
      if (line.startsWith(" ") || line === "") {
        let nearChange = false;
        for (
          let j = Math.max(0, i - contextLines);
          j <= Math.min(lines.length - 1, i + contextLines);
          j++
        ) {
          if (
            lines[j] &&
            (lines[j].startsWith("+") || lines[j].startsWith("-"))
          ) {
            nearChange = true;
            break;
          }
        }
        if (nearChange) {
          kept.push(line);
        }
      } else {
        // Non-standard line (e.g., "\ No newline at end of file") — keep
        kept.push(line);
      }
    }

    return { header: hunk.header, lines: kept };
  });
}

/** Rebuild a patch string from hunks. */
function rebuildPatch(
  hunks: Array<{ header: string; lines: string[] }>,
): string {
  return hunks.map((h) => h.header + "\n" + h.lines.join("\n")).join("\n");
}

/**
 * Apply size-aware handling for large security files (SKP-005).
 * Files >50KB get hunk summary instead of full diff.
 */
export function capSecurityFile(file: PullRequestFile): PullRequestFile {
  if (!file.patch) return file;

  const bytes = new TextEncoder().encode(file.patch).byteLength;
  if (bytes <= SECURITY_FILE_SIZE_CAP) return file;

  const hunks = parseHunks(file.patch);
  if (!hunks || hunks.length === 0) return file;

  const capped = hunks.slice(0, SECURITY_MAX_HUNKS);
  const rebuilt = rebuildPatch(capped);

  // Validation: if rebuilt is empty or larger than original, use original (SKP-003)
  if (!rebuilt || rebuilt.length >= file.patch.length) return file;

  return {
    ...file,
    patch:
      rebuilt +
      `\n\n[${capped.length} of ${hunks.length} hunks included — file truncated due to size]`,
  };
}

/**
 * Deterministic file priority for Level 1 truncation (IMP-002).
 * Returns files sorted by retention priority (highest first).
 */
export function prioritizeFiles(
  files: PullRequestFile[],
): PullRequestFile[] {
  const scored = files.map((f) => ({
    file: f,
    priority: getFilePriority(f, files),
    changeSize: f.additions + f.deletions,
  }));

  scored.sort((a, b) => {
    // Higher priority first
    if (a.priority !== b.priority) return b.priority - a.priority;
    // Within same priority: larger change size first
    if (a.changeSize !== b.changeSize) return b.changeSize - a.changeSize;
    // Tie-breaker: alphabetical for determinism
    return a.file.filename.localeCompare(b.file.filename);
  });

  return scored.map((s) => s.file);
}

function getFilePriority(
  file: PullRequestFile,
  allFiles: PullRequestFile[],
): number {
  if (isHighRisk(file.filename)) return 4; // Priority 1 (highest)
  if (isAdjacentTest(file.filename, allFiles)) return 3; // Priority 2
  if (isEntryOrConfig(file.filename)) return 2; // Priority 3
  return 1; // Priority 4 (lowest)
}

// --- Truncation Level Disclaimers ---
// Context reduction spans Level 1 → Level 2:
//   Level 1 uses full patches which include default git context (3 lines around changes).
//   Level 2 reduces context: first to 1 line, then to 0 lines.
//   The "3→1→0" reduction in the PR description spans Level 1 → Level 2 sub-steps.
//   Level 3 drops diff content entirely, showing stats-only.

const LEVEL_DISCLAIMERS: Record<1 | 2 | 3, string> = {
  1: "[Partial Review: {n} low-priority files excluded]",
  2: "[Partial Review: patches truncated to changed hunks]",
  3: "[Summary Review: diff content unavailable, reviewing file structure only]",
};

/**
 * Progressive truncation engine (Task 1.7 — SDD Section 3.3).
 * Attempts 3 levels of truncation to fit within token budget.
 * Budget target: 90% of maxInputTokens (SKP-004).
 */
export function progressiveTruncate(
  files: PullRequestFile[],
  budgetTokens: number,
  model: string,
  systemPromptLen: number,
  metadataLen: number,
): ProgressiveTruncationResult {
  const targetBudget = Math.floor(budgetTokens * 0.9);
  const { coefficient } = getTokenBudget(model);
  const fixedTokens = Math.ceil((systemPromptLen + metadataLen) * coefficient);

  // Apply size-aware security handling first (SKP-005)
  const capped = files.map((f) =>
    isHighRisk(f.filename) ? capSecurityFile(f) : f,
  );

  // Prioritize files (IMP-002)
  const prioritized = prioritizeFiles(capped);

  // --- Level 1: Drop low-priority files ---
  {
    const included: PullRequestFile[] = [];
    const excluded: Array<{ filename: string; stats: string }> = [];
    let diffTokens = 0;

    for (const file of prioritized) {
      const patchLen = file.patch?.length ?? 0;
      const fileTokens = Math.ceil(patchLen * coefficient);

      if (fixedTokens + diffTokens + fileTokens <= targetBudget) {
        included.push(file);
        diffTokens += fileTokens;
      } else {
        excluded.push({
          filename: file.filename,
          stats: `+${file.additions} -${file.deletions}`,
        });
      }
    }

    if (included.length > 0) {
      const totalBytes = included.reduce(
        (sum, f) =>
          sum +
          (f.patch ? new TextEncoder().encode(f.patch).byteLength : 0),
        0,
      );
      return {
        success: true,
        level: 1,
        files: included,
        excluded,
        totalBytes,
        disclaimer: LEVEL_DISCLAIMERS[1].replace(
          "{n}",
          String(excluded.length),
        ),
        tokenEstimate: {
          persona: Math.ceil(systemPromptLen * coefficient),
          template: 0,
          metadata: Math.ceil(metadataLen * coefficient),
          diffs: diffTokens,
          total: fixedTokens + diffTokens,
        },
      };
    }
  }

  // --- Level 2: Hunk-based truncation with context reduction ---
  // Level 1 uses full patches which include default git context (3 lines).
  // Level 2 reduces: context=1, then context=0. The "3→1→0" reduction
  // spans Level 1 → Level 2.
  for (const contextLines of [1, 0]) {
    const included: PullRequestFile[] = [];
    const excluded: Array<{ filename: string; stats: string }> = [];
    let diffTokens = 0;

    for (const file of prioritized) {
      if (!file.patch) {
        excluded.push({
          filename: file.filename,
          stats: `+${file.additions} -${file.deletions} (diff unavailable)`,
        });
        continue;
      }

      const hunks = parseHunks(file.patch);
      if (!hunks) {
        // SKP-003: parse failure → use full patch
        const patchTokens = Math.ceil(file.patch.length * coefficient);
        if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
          included.push(file);
          diffTokens += patchTokens;
        } else {
          excluded.push({
            filename: file.filename,
            stats: `+${file.additions} -${file.deletions}`,
          });
        }
        continue;
      }

      const reduced = reduceHunkContext(hunks, contextLines);
      const rebuilt = rebuildPatch(reduced);

      // SKP-003: validate rebuilt patch
      if (!rebuilt || rebuilt.length >= (file.patch?.length ?? 0)) {
        // Fallback: use original patch
        const patchTokens = Math.ceil(file.patch.length * coefficient);
        if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
          included.push(file);
          diffTokens += patchTokens;
        } else {
          excluded.push({
            filename: file.filename,
            stats: `+${file.additions} -${file.deletions}`,
          });
        }
        continue;
      }

      const patchTokens = Math.ceil(rebuilt.length * coefficient);
      if (fixedTokens + diffTokens + patchTokens <= targetBudget) {
        const annotation = `[${reduced.length} of ${hunks.length} hunks included]`;
        included.push({
          ...file,
          patch: rebuilt + "\n" + annotation,
        });
        diffTokens += patchTokens;
      } else {
        excluded.push({
          filename: file.filename,
          stats: `+${file.additions} -${file.deletions}`,
        });
      }
    }

    if (included.length > 0) {
      const totalBytes = included.reduce(
        (sum, f) =>
          sum +
          (f.patch ? new TextEncoder().encode(f.patch).byteLength : 0),
        0,
      );
      return {
        success: true,
        level: 2,
        files: included,
        excluded,
        totalBytes,
        disclaimer: LEVEL_DISCLAIMERS[2],
        tokenEstimate: {
          persona: Math.ceil(systemPromptLen * coefficient),
          template: 0,
          metadata: Math.ceil(metadataLen * coefficient),
          diffs: diffTokens,
          total: fixedTokens + diffTokens,
        },
      };
    }
  }

  // --- Level 3: Stats only (no diff content) ---
  {
    const excluded = prioritized.map((f) => ({
      filename: f.filename,
      stats: `+${f.additions} -${f.deletions} (stats only)`,
    }));

    const statsText = excluded.map((e) => `${e.filename}: ${e.stats}`).join("\n");
    const statsTokens = Math.ceil(statsText.length * coefficient);

    if (fixedTokens + statsTokens <= targetBudget) {
      return {
        success: true,
        level: 3,
        files: [],
        excluded,
        totalBytes: 0,
        disclaimer: LEVEL_DISCLAIMERS[3],
        tokenEstimate: {
          persona: Math.ceil(systemPromptLen * coefficient),
          template: 0,
          metadata: Math.ceil(metadataLen * coefficient),
          diffs: statsTokens,
          total: fixedTokens + statsTokens,
        },
      };
    }
  }

  // All levels failed
  return {
    success: false,
    files: [],
    excluded: [],
    totalBytes: 0,
  };
}

// --- Main Truncation Pipeline ---

function changeSize(file: PullRequestFile): number {
  return file.additions + file.deletions;
}

function patchBytes(file: PullRequestFile): number {
  return file.patch ? new TextEncoder().encode(file.patch).byteLength : 0;
}

export function truncateFiles(
  files: PullRequestFile[],
  config: Pick<
    BridgebuilderConfig,
    "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr" | "loaAware" | "repoRoot"
  >,
): TruncationResult {
  const patterns = config.excludePatterns ?? [];

  // Step 0: Loa-aware filtering (prepended, not replacing user patterns)
  // Load .reviewignore and merge with LOA_EXCLUDE_PATTERNS (#303)
  const loaDetection = detectLoa(config);
  let loaBanner: string | undefined;
  let loaStats: { filesExcluded: number; bytesSaved: number } | undefined;
  let allExcluded = false;
  const loaExcludedEntries: Array<{ filename: string; stats: string }> = [];

  let afterLoa = files;
  if (loaDetection.isLoa) {
    const effectivePatterns = loadReviewIgnore(config.repoRoot);
    const tierResult = applyLoaTierExclusion(files, effectivePatterns);
    afterLoa = tierResult.passthrough;

    // Collect Loa excluded entries
    for (const entry of tierResult.tier1Excluded) {
      loaExcludedEntries.push(entry);
    }
    for (const entry of tierResult.tier2Summary) {
      loaExcludedEntries.push({
        filename: entry.filename,
        stats: entry.stats,
      });
    }

    const totalLoaExcluded =
      tierResult.tier1Excluded.length + tierResult.tier2Summary.length;
    const kbSaved = Math.round(tierResult.bytesSaved / 1024);

    if (totalLoaExcluded > 0) {
      loaBanner = `[Loa-aware: ${totalLoaExcluded} framework files excluded (${kbSaved} KB saved)]`;
      loaStats = {
        filesExcluded: totalLoaExcluded,
        bytesSaved: tierResult.bytesSaved,
      };
    }

    // IMP-004: all files excluded by Loa filtering
    if (afterLoa.length === 0) {
      allExcluded = true;
      return {
        included: [],
        excluded: loaExcludedEntries,
        totalBytes: 0,
        allExcluded: true,
        loaBanner,
        loaStats,
      };
    }
  }

  // Step 1: Separate files matching excludePatterns (sole enforcement point — IMP-005)
  const afterExclude: PullRequestFile[] = [];
  const excludedByPattern: Array<{ filename: string; stats: string }> = [];
  for (const f of afterLoa) {
    if (matchesExcludePattern(f.filename, patterns)) {
      excludedByPattern.push({
        filename: f.filename,
        stats: `+${f.additions} -${f.deletions} (excluded by pattern)`,
      });
    } else {
      afterExclude.push(f);
    }
  }

  // Step 2: Classify into high-risk and normal
  const highRisk: PullRequestFile[] = [];
  const normal: PullRequestFile[] = [];
  for (const file of afterExclude) {
    if (isHighRisk(file.filename)) {
      highRisk.push(file);
    } else {
      normal.push(file);
    }
  }

  // Step 3: Sort each tier by change size (descending)
  highRisk.sort((a, b) => changeSize(b) - changeSize(a));
  normal.sort((a, b) => changeSize(b) - changeSize(a));

  // Interleave: high-risk first, then normal
  const sorted = [...highRisk, ...normal];

  // Apply maxFilesPerPr cap
  const capped = sorted.slice(0, config.maxFilesPerPr);

  // Step 4: Include full diff content until byte budget exhausted
  const included: PullRequestFile[] = [];
  const excluded: Array<{ filename: string; stats: string }> = [];
  let totalBytes = 0;

  for (const file of capped) {
    const bytes = patchBytes(file);

    // Step 6: Handle patch-optional files (binary/large — GitHub omits patch)
    if (file.patch == null) {
      excluded.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions} (diff unavailable)`,
      });
      continue;
    }

    if (totalBytes + bytes <= config.maxDiffBytes) {
      included.push(file);
      totalBytes += bytes;
    } else {
      // Step 5: Remaining files get name + stats only
      excluded.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions}`,
      });
    }
  }

  // Files beyond maxFilesPerPr cap also go to excluded
  for (const file of sorted.slice(config.maxFilesPerPr)) {
    excluded.push({
      filename: file.filename,
      stats: `+${file.additions} -${file.deletions}`,
    });
  }

  return {
    included,
    excluded: [...loaExcludedEntries, ...excludedByPattern, ...excluded],
    totalBytes,
    allExcluded,
    loaBanner,
    loaStats,
  };
}
