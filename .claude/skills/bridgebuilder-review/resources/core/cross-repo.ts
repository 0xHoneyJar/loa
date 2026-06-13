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

/**
 * Injectable exec seam (#1014). Defaults to the real promisified execFile;
 * tests inject a fake to prove the allowlist blocks fetches without shelling
 * out to a real gh.
 */
export type CrossRepoExec = (
  file: string,
  args: readonly string[],
  options: { timeout: number },
) => Promise<{ stdout: string }>;

const defaultExec: CrossRepoExec = (file, args, options) =>
  execFileAsync(file, args as string[], options);

/**
 * Strip control + zero-width / bidi characters from untrusted fetched content
 * before it can enter the review prompt (#1014 sanitize-at-ingest). Tab,
 * newline, and carriage return are preserved.
 */
const _UNTRUSTED_STRIP_RE = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u200b-\u200f\u2028\u2029\u202a-\u202e\u2060\ufeff]/g;

export function sanitizeUntrusted(text: string): string {
  return text.replace(_UNTRUSTED_STRIP_RE, "");
}

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
  allowedOwners?: ReadonlySet<string>,
  exec: CrossRepoExec = defaultExec,
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

    // #1014: auto-detected refs come from UNTRUSTED PR text and would otherwise
    // drive a gh issue view against an attacker-chosen repo with the bot
    // credential. Only fetch auto refs whose owner is allowlisted (org-only by
    // default). Fail closed: with no allowlist, NO auto ref is fetched. Manual
    // refs are operator-configured (explicit opt-in) and remain trusted.
    if (ref.source === "auto") {
      const ownerAllowed = allowedOwners?.has(ref.owner.toLowerCase()) ?? false;
      if (!ownerAllowed) {
        const reason =
          `blocked: auto-detected owner '${ref.owner}' is not on the cross-repo allowlist`;
        logger?.warn(
          `[cross-repo] ${reason} - not fetching ${ref.owner}/${ref.repo}#${ref.number}`,
        );
        errors.push({ ref, error: reason });
        continue;
      }
      // #1014 audit SEC-001: an allowlisted OWNER is not authorization to read
      // that owner's PRIVATE repos with the bot credential. Auto refs are
      // fetched only when the repo is PUBLIC; fail closed on any uncertainty.
      let isPublic = false;
      try {
        isPublic = (await fetchRepoVisibility(ref.owner, ref.repo, exec)) === "public";
      } catch {
        isPublic = false; // fail closed
      }
      if (!isPublic) {
        // #1014 audit #1: collapse private / internal / not-found / error into
        // ONE generic outcome so the logged/rendered result is not a
        // private-repo existence oracle.
        const reason = "blocked: auto-detected ref is not an accessible public repository";
        logger?.warn(`[cross-repo] ${reason} (${ref.owner}/${ref.repo}#${ref.number})`);
        errors.push({ ref, error: reason });
        continue;
      }
    }

    try {
      // #1014 audit SEC-002: auto-detected refs come from untrusted PR text, so
      // fetch METADATA ONLY (no body) - an untrusted issue body must not be
      // injected into the review prompt. Manual refs (operator opt-in) get the
      // full body.
      const includeBody = ref.source !== "auto";
      const result = await fetchRef(ref, exec, includeBody);
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
 * Fetch a repo's visibility ("public" / "private" / "internal") via gh CLI.
 * Gates auto-detected refs to PUBLIC repos only (#1014 audit SEC-001).
 */
async function fetchRepoVisibility(
  owner: string,
  repo: string,
  exec: CrossRepoExec = defaultExec,
): Promise<string> {
  const { stdout } = await exec(
    "gh",
    ["repo", "view", `${owner}/${repo}`, "--json", "visibility"],
    { timeout: PER_REF_TIMEOUT_MS },
  );
  const data = JSON.parse(stdout) as { visibility?: string };
  return (data.visibility ?? "").toLowerCase();
}

/**
 * Fetch a single cross-repo reference via gh CLI.
 */
async function fetchRef(
  ref: CrossRepoRef,
  exec: CrossRepoExec = defaultExec,
  includeBody = true,
): Promise<{ title?: string; body?: string; labels?: string[] }> {
  // Try as issue first (covers both issues and PRs on GitHub API). For auto
  // refs (includeBody=false) the body is neither requested nor returned.
  const { stdout } = await exec(
    "gh",
    [
      "issue",
      "view",
      String(ref.number),
      "--repo",
      `${ref.owner}/${ref.repo}`,
      "--json",
      includeBody ? "title,body,labels" : "title,labels",
    ],
    { timeout: PER_REF_TIMEOUT_MS },
  );

  const data = JSON.parse(stdout) as {
    title?: string;
    body?: string;
    labels?: Array<{ name: string }>;
  };

  // #1014: the fetched issue/PR is untrusted external content. Strip control /
  // zero-width characters at ingest before it can reach the review prompt.
  return {
    title: data.title ? sanitizeUntrusted(data.title) : undefined,
    // Truncate body to 1000 chars to avoid bloating context
    body: includeBody && data.body ? sanitizeUntrusted(data.body.slice(0, 1000)) : undefined,
    labels: data.labels?.map((l) => sanitizeUntrusted(l.name)),
  };
}
