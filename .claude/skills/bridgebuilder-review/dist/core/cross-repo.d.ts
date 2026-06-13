import type { ILogger } from "../ports/logger.js";
/**
 * Injectable exec seam (#1014). Defaults to the real promisified execFile;
 * tests inject a fake to prove the allowlist blocks fetches without shelling
 * out to a real gh.
 */
export type CrossRepoExec = (file: string, args: readonly string[], options: {
    timeout: number;
}) => Promise<{
    stdout: string;
}>;
export declare function sanitizeUntrusted(text: string): string;
export interface CrossRepoRef {
    owner: string;
    repo: string;
    type: "issue" | "pr" | "commit";
    number?: number;
    sha?: string;
    source: "auto" | "manual";
}
export interface CrossRepoContextResult {
    refs: CrossRepoRef[];
    context: Array<{
        ref: CrossRepoRef;
        title?: string;
        body?: string;
        labels?: string[];
    }>;
    errors: Array<{
        ref: CrossRepoRef;
        error: string;
    }>;
}
/**
 * Auto-detect GitHub references from PR body and commit messages.
 */
export declare function detectRefs(text: string, currentRepo?: string): CrossRepoRef[];
/**
 * Parse manual refs from config (format: "owner/repo#123" or "owner/repo").
 */
export declare function parseManualRefs(refs: string[]): CrossRepoRef[];
/**
 * Fetch context for cross-repo references via gh CLI.
 * Respects per-ref (5s) and total (30s) timeouts.
 */
export declare function fetchCrossRepoContext(refs: CrossRepoRef[], logger?: ILogger, allowedOwners?: ReadonlySet<string>, exec?: CrossRepoExec): Promise<CrossRepoContextResult>;
//# sourceMappingURL=cross-repo.d.ts.map