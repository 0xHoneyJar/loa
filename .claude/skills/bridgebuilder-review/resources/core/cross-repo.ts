/**
 * CrossRepoContext — auto-detect and fetch cross-repository context.
 *
 * Detects GitHub refs from PR body/commits, fetches context via gh CLI,
 * and merges with manually configured refs from .loa.config.yaml.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { ILogger } from "../ports/logger.js";

const execFileAsync = promisify(execFile);

/** Timeout per ref fetch (ms). */
const PER_REF_TIMEOUT_MS = 5_000;
/** Total timeout for all ref fetches (ms). */
const TOTAL_TIMEOUT_MS = 30_000;

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
  errors: Array<{ ref: CrossRepoRef; error: string }>;
}

/**
 * GitHub reference patterns for auto-detection.
 * Matches: owner/repo#123, owner/repo@sha, full GitHub URLs.
 */
const GITHUB_REF_PATTERNS = [
  // owner/repo#123 (issue or PR)
  /(?:^|\s)([a-zA-Z0-9_-]+\/[a-zA-Z0-9._-]+)#(\d+)/g,
  // Full GitHub URL: https://github.com/owner/repo/pull/123 or /issues/123
  /https?:\/\/github\.com\/([a-zA-Z0-9_-]+\/[a-zA-Z0-9._-]+)\/(?:pull|issues)\/(\d+)/g,
];

/**
 * Auto-detect GitHub references from PR body and commit messages.
 */
export function detectRefs(text: string, currentRepo?: string): CrossRepoRef[] {
  const refs: CrossRepoRef[] = [];
  const seen = new Set<string>();

  for (const pattern of GITHUB_REF_PATTERNS) {
    // Reset regex lastIndex for each iteration
    const regex = new RegExp(pattern.source, pattern.flags);
    let match: RegExpExecArray | null;

    while ((match = regex.exec(text)) !== null) {
      const repoSlug = match[1];
      const number = parseInt(match[2], 10);

      // Skip self-references (same repo)
      if (currentRepo && repoSlug === currentRepo) continue;

      const key = `${repoSlug}#${number}`;
      if (seen.has(key)) continue;
      seen.add(key);

      const [owner, repo] = repoSlug.split("/");
      refs.push({
        owner,
        repo,
        type: "issue", // Could be issue or PR — resolved on fetch
        number,
        source: "auto",
      });
    }
  }

  return refs;
}

/**
 * Parse manual refs from config (format: "owner/repo#123" or "owner/repo").
 */
export function parseManualRefs(refs: string[]): CrossRepoRef[] {
  const result: CrossRepoRef[] = [];

  for (const ref of refs) {
    const hashMatch = ref.match(/^([a-zA-Z0-9_-]+\/[a-zA-Z0-9._-]+)#(\d+)$/);
    if (hashMatch) {
      const [owner, repo] = hashMatch[1].split("/");
      result.push({
        owner,
        repo,
        type: "issue",
        number: parseInt(hashMatch[2], 10),
        source: "manual",
      });
      continue;
    }

    const repoMatch = ref.match(/^([a-zA-Z0-9_-]+)\/([a-zA-Z0-9._-]+)$/);
    if (repoMatch) {
      result.push({
        owner: repoMatch[1],
        repo: repoMatch[2],
        type: "issue",
        source: "manual",
      });
    }
  }

  return result;
}

/**
 * Fetch context for cross-repo references via gh CLI.
 * Respects per-ref (5s) and total (30s) timeouts.
 */
export async function fetchCrossRepoContext(
  refs: CrossRepoRef[],
  logger?: ILogger,
): Promise<CrossRepoContextResult> {
  const context: CrossRepoContextResult["context"] = [];
  const errors: CrossRepoContextResult["errors"] = [];
  const startMs = Date.now();

  for (const ref of refs) {
    // Check total timeout
    if (Date.now() - startMs > TOTAL_TIMEOUT_MS) {
      logger?.warn("[cross-repo] Total timeout reached, skipping remaining refs");
      break;
    }

    if (!ref.number) continue; // Can't fetch without a number

    try {
      const result = await fetchRef(ref);
      context.push({ ref, ...result });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      logger?.warn(`[cross-repo] Failed to fetch ${ref.owner}/${ref.repo}#${ref.number}`, {
        error: message,
      });
      errors.push({ ref, error: message });
    }
  }

  return { refs, context, errors };
}

/**
 * Fetch a single cross-repo reference via gh CLI.
 */
async function fetchRef(
  ref: CrossRepoRef,
): Promise<{ title?: string; body?: string; labels?: string[] }> {
  // Try as issue first (covers both issues and PRs on GitHub API)
  const { stdout } = await execFileAsync(
    "gh",
    [
      "issue",
      "view",
      String(ref.number),
      "--repo",
      `${ref.owner}/${ref.repo}`,
      "--json",
      "title,body,labels",
    ],
    { timeout: PER_REF_TIMEOUT_MS },
  );

  const data = JSON.parse(stdout) as {
    title?: string;
    body?: string;
    labels?: Array<{ name: string }>;
  };

  return {
    title: data.title,
    // Truncate body to 1000 chars to avoid bloating context
    body: data.body ? data.body.slice(0, 1000) : undefined,
    labels: data.labels?.map((l) => l.name),
  };
}
