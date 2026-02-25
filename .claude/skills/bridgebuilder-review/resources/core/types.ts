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
  /** Review mode: two-pass (convergence + enrichment) or single-pass (legacy). */
  reviewMode: "two-pass" | "single-pass";
  /** Path to ecosystem context JSON file for cross-repo pattern hints (Pass 0 prototype). */
  ecosystemContextPath?: string;
  /** Pass 1 convergence cache configuration (Sprint 70). */
  pass1Cache?: { enabled: boolean };
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

/** Token metrics for a single LLM pass. */
export interface PassTokenMetrics {
  input: number;
  output: number;
  duration: number;
}

export interface ReviewResult {
  item: ReviewItem;
  posted: boolean;
  skipped: boolean;
  skipReason?: string;
  inputTokens?: number;
  outputTokens?: number;
  error?: ReviewError;
  /** Raw Pass 1 response content (for observability — FR-5.2). */
  pass1Output?: string;
  /** Token metrics for convergence pass (two-pass mode only). */
  pass1Tokens?: PassTokenMetrics;
  /** Token metrics for enrichment pass (two-pass mode only). */
  pass2Tokens?: PassTokenMetrics;
  /** Confidence statistics from Pass 1 findings (two-pass mode only). */
  pass1ConfidenceStats?: { min: number; max: number; mean: number; count: number };
  /** Persona identity for provenance tracking (two-pass mode only). */
  personaId?: string;
  /** SHA-256 hash of persona content for integrity verification. */
  personaHash?: string;
  /** Whether Pass 1 findings were served from cache (Sprint 70). */
  pass1CacheHit?: boolean;
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

/** Persona identity and version for provenance tracking. */
export interface PersonaMetadata {
  id: string;
  version: string;
  hash: string;
}

/** Cross-repository pattern hints for enrichment context (Pass 0 prototype). */
export interface EcosystemContext {
  patterns: Array<{ repo: string; pr?: number; pattern: string; connection: string }>;
  lastUpdated: string;
}

/** Truncation context passed from Pass 1 to Pass 2 for enrichment awareness. */
export interface TruncationContext {
  filesExcluded: number;
  totalFiles: number;
}

/** Consolidated options for the enrichment prompt builder (Sprint 69 — params object pattern). */
export interface EnrichmentOptions {
  findingsJSON: string;
  item: ReviewItem;
  persona: string;
  truncationContext?: TruncationContext;
  personaMetadata?: PersonaMetadata;
  ecosystemContext?: EcosystemContext;
}

/** Token estimate broken down by component for calibration logging. */
export interface TokenEstimateBreakdown {
  persona: number;
  template: number;
  metadata: number;
  diffs: number;
  total: number;
}

/**
 * Ecosystem pattern extracted from bridge findings (Sprint 71 — dynamic ecosystem context).
 * Extends the static pattern shape with provenance fields for traceability.
 */
export interface EcosystemPattern {
  repo: string;
  pr: number;
  pattern: string;
  connection: string;
  extractedFrom: string;
  confidence: number | undefined;
}

/**
 * Persona registry entry for the persona marketplace (Sprint 71 — schema primitives).
 * Defines the identity and metadata for a review persona.
 * The full persona marketplace is future work; these types formalize the slot architecture.
 */
export interface PersonaRegistryEntry {
  name: string;
  version: string;
  hash: string;
  description: string;
  dimensions: string[];
  voiceSamples?: string[];
}
