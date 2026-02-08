import type { PullRequest, PullRequestFile } from "../ports/git-provider.js";
export interface BridgebuilderConfig {
    repos: Array<{
        owner: string;
        repo: string;
    }>;
    model: string;
    maxPrs: number;
    maxFilesPerPr: number;
    maxDiffBytes: number;
    maxInputTokens: number;
    maxOutputTokens: number;
    dimensions: string[];
    reviewMarker: string;
    personaPath: string;
    dryRun: boolean;
    excludePatterns: string[];
    sanitizerMode: "default" | "strict";
    maxRuntimeMinutes: number;
    targetPr?: number;
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
    excluded: Array<{
        filename: string;
        stats: string;
    }>;
    totalBytes: number;
}
//# sourceMappingURL=types.d.ts.map