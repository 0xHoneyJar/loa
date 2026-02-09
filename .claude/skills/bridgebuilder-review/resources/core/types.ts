import type { PullRequest, PullRequestFile } from "../ports/git-provider.js";

export interface BridgebuilderConfig {
  repos: Array<{ owner: string; repo: string }>;
  model: string;
  maxPrs: number;
  maxFilesPerPr: number;
  maxDiffBytes: number;
  maxInputTokens: number;
  maxOutputTokens: number;
  dimensions: string[];
  reviewMarker: string;
  repoOverridePath: string;
  dryRun: boolean;
  excludePatterns: string[];
  sanitizerMode: "default" | "strict";
  maxRuntimeMinutes: number;
  /** When set (via --pr flag), filters fetchPRItems() to this single PR number. */
  targetPr?: number;
  /** Explicit Loa-aware mode override. true=force on, false=force off, undefined=auto-detect. */
  loaAware?: boolean;
  /** Git repo root for path resolution (defaults to cwd). */
  repoRoot?: string;
  /** Persona pack name (e.g. "security", "dx"). */
  persona?: string;
  /** Custom persona file path. */
  personaFilePath?: string;
  /** Force full review even when incremental context is available (V3-1). */
  forceFullReview?: boolean;
}

export interface ReviewItem {
  owner: string;
  repo: string;
  pr: PullRequest;
  files: PullRequestFile[];
  hash: string;
}

export type ErrorCategory = "transient" | "permanent" | "unknown";

export interface ReviewError {
  code: string;
  message: string;
  category: ErrorCategory;
  retryable: boolean;
  source: "github" | "llm" | "sanitizer" | "pipeline";
}

export interface ReviewResult {
  item: ReviewItem;
  posted: boolean;
  skipped: boolean;
  skipReason?: string;
  inputTokens?: number;
  outputTokens?: number;
  error?: ReviewError;
}

export interface RunSummary {
  reviewed: number;
  skipped: number;
  errors: number;
  startTime: string;
  endTime: string;
  runId: string;
  results: ReviewResult[];
}

export interface TruncationResult {
  included: PullRequestFile[];
  excluded: Array<{ filename: string; stats: string }>;
  totalBytes: number;
  /** True when all files were excluded by Loa filtering (no app files remain). */
  allExcluded?: boolean;
  /** Banner string when Loa files were excluded. */
  loaBanner?: string;
  /** Loa exclusion statistics. */
  loaStats?: { filesExcluded: number; bytesSaved: number };
  /** Truncation level applied (undefined = no progressive truncation). */
  truncationLevel?: 1 | 2 | 3;
  /** Disclaimer text for the current truncation level. */
  truncationDisclaimer?: string;
}

export interface LoaDetectionResult {
  isLoa: boolean;
  version?: string;
  source: "file" | "config_override";
}

/** Security pattern entry with category and rationale for auditability. */
export interface SecurityPatternEntry {
  pattern: RegExp;
  category: string;
  rationale: string;
}

/** Per-model token budget constants. */
export interface TokenBudget {
  maxInput: number;
  maxOutput: number;
  coefficient: number;
}

/** Progressive truncation result from the retry loop. */
export interface ProgressiveTruncationResult {
  success: boolean;
  level?: 1 | 2 | 3;
  files: PullRequestFile[];
  excluded: Array<{ filename: string; stats: string }>;
  totalBytes: number;
  disclaimer?: string;
  tokenEstimate?: TokenEstimateBreakdown;
}

/** Token estimate broken down by component for calibration logging. */
export interface TokenEstimateBreakdown {
  persona: number;
  template: number;
  metadata: number;
  diffs: number;
  total: number;
}
