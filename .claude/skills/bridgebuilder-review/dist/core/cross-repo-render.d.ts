/**
 * cross-repo-render.ts — formats a CrossRepoContextResult into the
 * markdown section that gets injected into the multi-model review user
 * prompt by `buildConvergenceUserPrompt`.
 *
 * Closes #464 A4: previously the cross-repo fetch result existed but had
 * no rendering or injection path. The render happens in main.ts so the
 * template stays a pure formatter.
 *
 * Truncation strategy: hard cap on total bytes (default 20KB) protects
 * the input token budget. When over budget, later refs are dropped with
 * a `[truncated: N more refs]` note rather than mid-content cuts.
 */
import type { CrossRepoContextResult } from "./cross-repo.js";
export declare const DEFAULT_CROSS_REPO_MAX_BYTES = 20000;
/**
 * Render a CrossRepoContextResult as a markdown section.
 * Returns "" when there is nothing to show (no successes, no errors).
 */
export declare function renderCrossRepoSection(result: CrossRepoContextResult, maxBytes?: number): string;
//# sourceMappingURL=cross-repo-render.d.ts.map