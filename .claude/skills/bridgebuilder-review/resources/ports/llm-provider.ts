export interface ReviewRequest {
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
}

export interface ReviewResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
  model: string;
  /** Provider identifier (e.g., "anthropic", "openai", "google"). Multi-model extension. */
  provider?: string;
  /** Wall-clock time for the API call in milliseconds. Multi-model extension. */
  latencyMs?: number;
  /** Estimated cost in USD for this call. Multi-model extension. */
  estimatedCostUsd?: number;
  /** Error state if the call failed but returned partial content. Multi-model extension. */
  errorState?: LLMProviderErrorCode | null;
  /**
   * cycle-109 Sprint 2 T2.6 — verdict_quality envelope read from cheval's
   * LOA_VERDICT_QUALITY_SIDECAR file. Shape matches
   * `.claude/data/schemas/verdict-quality.schema.json`. Optional / additive:
   * pre-T2.3 cheval emits omit it, and adapters that don't (yet) wire the
   * sidecar leave the field undefined. Downstream consumers (multi-model
   * pipeline, PR-comment formatter) MUST handle absence gracefully.
   */
  verdictQuality?: VerdictQualityEnvelope;
}

/** cycle-109 Sprint 2 — verdict_quality envelope structural type. The
 * canonical schema lives at `.claude/data/schemas/verdict-quality.schema.json`;
 * this interface is a TypeScript mirror for type-checking. Extra fields
 * are tolerated (TS object types are open) — only the fields BB renders are
 * declared. */
export interface VerdictQualityEnvelope {
  status: "APPROVED" | "DEGRADED" | "FAILED";
  consensus_outcome: "consensus" | "impossible";
  truncation_waiver_applied: boolean;
  voices_planned: number;
  voices_succeeded: number;
  voices_succeeded_ids: string[];
  voices_dropped: Array<{
    voice: string;
    reason: string;
    exit_code: number;
    blocker_risk: "unknown" | "low" | "med" | "high";
    chain_walk?: string[];
  }>;
  chain_health: "ok" | "degraded" | "exhausted";
  confidence_floor: "high" | "med" | "low";
  rationale: string;
  single_voice_call?: boolean;
}

/** Typed error codes for LLM provider operations. */
export type LLMProviderErrorCode =
  | "TOKEN_LIMIT"
  | "RATE_LIMITED"
  | "INVALID_REQUEST"
  | "NETWORK"
  | "TIMEOUT"
  | "AUTH_ERROR"
  | "PROVIDER_ERROR";

/** Typed error thrown by LLM provider adapters for structured classification. */
export class LLMProviderError extends Error {
  readonly code: LLMProviderErrorCode;

  constructor(code: LLMProviderErrorCode, message: string) {
    super(message);
    this.name = "LLMProviderError";
    this.code = code;
  }
}

export interface ILLMProvider {
  generateReview(request: ReviewRequest): Promise<ReviewResponse>;
}
