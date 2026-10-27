/**
 * cycle-133 C-1 (sdd.md § 1.4, FR-1, D-1.1 DEC-0839; KF-054): the two-pass, SHA-pinned PR file fetch.
 *
 * Pass 1 pages `pulls/N/files?per_page=100&page=K` (never `--paginate`) and keeps filename, status, additions,
 * deletions and the patch's byte length only, deduplicating by filename and re-reading `pulls/N` before every page.
 * `truncateFiles` then runs ONCE over the complete metadata list (Loa tier, exclude_patterns, max_files_per_pr, tier
 * ordering) — the global selection. The byte budget (`max_diff_bytes`) is planned on the recorded sizes in selection
 * order: a file that fits is retained whole, the first that does not is retained cut (`patch_truncated`), the rest are
 * omitted (`byte_budget`). Pass 2 re-pages only the pages holding planned files and keeps their patch text. After pass
 * 2 both SHAs are revalidated; any base/head change discards the attempt, restarts once, then degrades as
 * `pr_head_moved`. GitHub omissions are recorded, never silent (coverage record).
 *
 * cycle-135 C-3 (FR-3, D-1.3, bd-w5pd9): between the selection and the byte planning, an added file GitHub listed
 * without a patch that survived the exclusions is read by content (`getFileContent`, pinned to the listing's head sha,
 * bounded by count, deadline and the aggregate byte budget) and enters planning with a synthesized patch, so it is
 * selected, planned and reviewed like any patched file (`reviewed[].source: "contents"`). Any other outcome leaves it
 * `no_patch` with `omitted[].fetch` naming why.
 */
import { GitProviderError } from "../ports/git-provider.js";
import type { FileContentResult, IGitProvider, PullRequestFile, PullRequestRef } from "../ports/git-provider.js";
import { createHash } from "node:crypto";
import { deriveCallConfig, isWildcardPattern, matchesExcludePattern, truncateFiles } from "./truncation.js";
import { FETCH_DEGRADED_REASONS, orderDegradedReasons, type DegradedReason } from "./degraded-reason.js";
import type { BridgebuilderConfig, CoverageRecord, OmissionReason, ReviewignoreSource, ReviewItem, SelectionConfig, TruncationResult } from "./types.js";

/** GitHub's `pulls/N/files` lists at most this many files (30 pages of 100). */
export const FILES_ENDPOINT_CAP = 3000;
const PAGE_SIZE = 100;

export type PagedGit = Required<Pick<IGitProvider, "getPR" | "getPRFilesPage">>;
/** cycle-135 C-3: the paged contract plus the optional content read (absent → no content fetch). */
export type PagedContentGit = PagedGit & Pick<IGitProvider, "getFileContent">;

export type { SelectionConfig } from "./types.js"; // (cycle-136 Task 1.0: owned by types.ts)

/** cycle-135 C-3: default `max_content_fetches` and the total deadline for the content reads of one attempt. */
export const DEFAULT_MAX_CONTENT_FETCHES = 20;
export const CONTENT_FETCH_DEADLINE_MS = 120_000;


/** Test seams of the two-pass fetch (production passes none). */
export interface TwoPassDeps {
  /** cycle-135 C-3: the clock for the content-fetch deadline (default `Date.now`). */
  now?: () => number;
  /** cycle-135 C-2: the selection (default `truncateFiles`); tests substitute the producer of `protectedKept`. */
  truncate?: (files: PullRequestFile[], config: SelectionConfig) => TruncationResult;
  /** cycle-135 C-2: where `.reviewignore` is read from for this PR (default `defaultReviewignoreSource`). */
  reviewignoreSource?: (repoRoot: string | undefined, opts: { baseSha?: string }) => ReviewignoreSource | undefined;
}

/*
 * cycle-135 C-2 (D-1.2a, bd-i4fyw): the `.reviewignore` provenance for the coverage record comes from the selection
 * result — `truncateFiles` reads `.reviewignore` (from the PR base sha when `reviewignoreBaseSha` is set) and returns
 * `reviewignoreSource` beside `protectedKept` — so the file is read once and the record cannot disagree with the
 * selection. `deps.reviewignoreSource` remains a test seam (lead wiring, Task 1.7).
 */

/** cycle-135 C-2: the ` [pattern: <p>]` suffix A's selection appends to an exclusion's stats (to the final `]`). */
const PATTERN_SUFFIX = / \[pattern: (.+)\]$/;

/**
 * The pattern that excluded a file: the stats suffix when the selection wrote one; else, for a config
 * `exclude_patterns` exclusion, the matching pattern with a non-wildcard one first (sdd.md § 5.2's precedence).
 */
function exclusionPattern(stats: string, filename: string, excludePatterns: readonly string[] | undefined): string | undefined {
  const m = PATTERN_SUFFIX.exec(stats);
  if (m) return m[1];
  if (!/\(excluded by pattern\)/.test(stats)) return undefined;
  const matching = (excludePatterns ?? []).filter((p) => matchesExcludePattern(filename, [p]));
  return matching.find((p) => !isWildcardPattern(p)) ?? matching[0];
}

type FetchOutcome = NonNullable<CoverageRecord["omitted"][number]["fetch"]>;

export interface TwoPassResult {
  /** Selected files with their retained (possibly cut) patch text, in selection order. */
  files: PullRequestFile[];
  /** The global selection, `included` === `files`. */
  selection: TruncationResult;
  coverage: CoverageRecord;
}

/** Omission reasons that count against coverage when the file is a reviewable code file. */
export const REVIEWABLE_OMISSION_REASONS: ReadonlySet<OmissionReason> = new Set<OmissionReason>([
  "file_cap", "byte_budget", "no_patch", "patch_truncated", "page_incomplete", "excluded_fail_closed",
]);

/** The review set: code, scripts, config and docs (sdd.md C-1 "reviewable code file"). */
const REVIEWABLE_EXTENSIONS = new Set([
  // code
  "ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs", "py", "pyi", "rb", "go", "rs", "java", "kt", "kts", "scala",
  "c", "h", "cc", "cpp", "cxx", "hpp", "hh", "cs", "fs", "swift", "m", "mm", "php", "pl", "pm", "lua", "ex", "exs",
  "erl", "hs", "clj", "dart", "r", "jl", "sol", "vy", "zig", "nim", "sql", "graphql", "gql", "proto", "vue", "svelte",
  "astro", "html", "htm", "css", "scss", "sass", "less", "wasm.wat", "wat",
  // scripts
  "sh", "bash", "zsh", "fish", "ps1", "psm1", "bat", "cmd", "bats", "awk", "sed", "jq",
  // config
  "json", "jsonc", "json5", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "xml", "tf", "tfvars", "hcl", "nix",
  "gradle", "properties", "plist", "service", "rules", "tpl", "j2", "mk", "cmake", "lock.json",
  // docs
  "md", "mdx", "markdown", "rst", "txt", "adoc", "org", "tex",
]);

/** Extensionless names in the review set (build files, CI and ownership config). */
const REVIEWABLE_BASENAMES = new Set([
  "Dockerfile", "Containerfile", "Makefile", "GNUmakefile", "Justfile", "justfile", "Rakefile", "Gemfile", "Procfile",
  "Vagrantfile", "Jenkinsfile", "CODEOWNERS", "LICENSE", "NOTICE", "README", "BUILD", "WORKSPACE",
]);

/** A file in the review set by name (dotfiles such as `.gitattributes` are config). */
export function isReviewableCodeFile(filename: string): boolean {
  const base = filename.split("/").pop() ?? filename;
  if (REVIEWABLE_BASENAMES.has(base)) return true;
  if (base.startsWith(".") && !base.slice(1).includes(".")) return true;
  const dot = base.lastIndexOf(".");
  if (dot <= 0) return false;
  return REVIEWABLE_EXTENSIONS.has(base.slice(dot + 1).toLowerCase());
}

/** A base or head change between the pin and a later read. */
export class PrHeadMoved extends Error {
  constructor(readonly latest: PullRequestRef) {
    super("PR base or head moved during the fetch");
    this.name = "PrHeadMoved";
  }
}

function utf8Bytes(text: string): number {
  return Buffer.byteLength(text, "utf8");
}

/** Cut a patch to at most `maxBytes` UTF-8 bytes, at the last line boundary when one exists (always a prefix). */
export function cutPatch(patch: string, maxBytes: number): string {
  if (utf8Bytes(patch) <= maxBytes) return patch;
  let bytes = 0;
  let lastNl = -1;
  let i = 0;
  while (i < patch.length) {
    const cp = patch.codePointAt(i)!;
    const len = cp < 0x80 ? 1 : cp < 0x800 ? 2 : cp < 0x10000 ? 3 : 4;
    if (bytes + len > maxBytes) break;
    bytes += len;
    if (patch[i] === "\n") lastNl = i;
    i += cp > 0xffff ? 2 : 1;
  }
  return lastNl > 0 ? patch.slice(0, lastNl) : patch.slice(0, i);
}

/**
 * cycle-135 C-3: the patch for a whole added file — `@@ -0,0 +1,N @@` then every line with a `+` prefix (bytes
 * verbatim, so CRLF keeps its `\r`), and git's `\ No newline at end of file` marker when the content lacks one.
 */
export function synthesizeAddedPatch(content: string): string {
  const finalNewline = content.endsWith("\n");
  const lines = (finalNewline ? content.slice(0, -1) : content).split("\n");
  return `@@ -0,0 +1,${lines.length} @@\n` + lines.map((l) => "+" + l).join("\n") +
    (finalNewline ? "" : "\n\\ No newline at end of file");
}

function countHunks(patch: string): number {
  let n = 0;
  for (const line of patch.split("\n")) if (line.startsWith("@@")) n++;
  return n;
}

/** The degraded reason a failed page request maps to, or undefined (rethrow: auth, not found). */
function pageFailureReason(err: unknown): DegradedReason | undefined {
  if (!(err instanceof GitProviderError)) return undefined;
  if (err.code === "PAYLOAD_OVERSIZE") return "files_payload_oversize";
  if (err.code === "RATE_LIMITED") return "patch_fetch_rate_limited";
  if (err.code === "NETWORK") return "page_incomplete";
  return undefined;
}

/** Map one `truncateFiles` exclusion (its stats suffix) to the coverage reason. */
function exclusionReason(stats: string, file: PullRequestFile | undefined): OmissionReason {
  if (/fail-closed/.test(stats)) return "excluded_fail_closed";
  if (/\(Loa framework/.test(stats)) return "excluded_loa";
  if (/\.reviewignore user pattern|\(excluded by pattern\)/.test(stats)) return "excluded_pattern";
  if (/\(diff unavailable\)/.test(stats)) {
    return file && file.status === "renamed" && file.additions === 0 && file.deletions === 0 ? "renamed" : "no_patch";
  }
  return "file_cap";
}

/**
 * Degradation from the coverage: a fetch-side reason is reported as itself; otherwise any omitted reviewable file or
 * any unknown (unlisted) file is `incomplete_coverage`. Either way the merge is blocked as incomplete_coverage.
 */
export function evaluateCoverage(input: {
  omitted: CoverageRecord["omitted"];
  unknown_omitted: number;
  fetchReasons: DegradedReason[];
}): Pick<CoverageRecord, "degraded" | "degraded_reasons" | "mergeBlockedReason"> {
  const fetch = input.fetchReasons.filter((r) => FETCH_DEGRADED_REASONS.has(r));
  const incomplete = input.unknown_omitted > 0 || input.omitted.some((o) => o.reviewable);
  const reasons: DegradedReason[] = fetch.length > 0 ? orderDegradedReasons(fetch) : incomplete ? ["incomplete_coverage"] : [];
  if (reasons.length === 0) return { degraded: false, degraded_reasons: [] };
  return { degraded: true, degraded_reasons: reasons, mergeBlockedReason: "incomplete_coverage" };
}

function omission(
  file: string, reason: OmissionReason, fetch?: FetchOutcome, pattern?: string,
): CoverageRecord["omitted"][number] {
  return {
    file, reason, reviewable: REVIEWABLE_OMISSION_REASONS.has(reason) && isReviewableCodeFile(file),
    ...(pattern !== undefined ? { pattern } : {}),
    ...(fetch ? { fetch } : {}),
  };
}

async function recheck(git: PagedGit, owner: string, repo: string, prNumber: number, pin: PullRequestRef): Promise<void> {
  const now = await git.getPR(owner, repo, prNumber);
  if (now.base_sha !== pin.base_sha || now.head_sha !== pin.head_sha) throw new PrHeadMoved(now);
}

interface Meta {
  file: PullRequestFile;
  page: number;
}

/** cycle-135 C-3: an added file GitHub listed without a patch, with content to read (additions > 0). */
function isContentCandidate(f: PullRequestFile): boolean {
  return f.status === "added" && f.patch == null && f.patchBytes == null && f.additions > 0;
}

/**
 * cycle-135 C-3 (review round 1): the smallest patch `additions` lines can synthesize — the shortest header
 * `@@ -0,0 +1,N @@\n` (16 bytes) plus one `+` per line and the newlines between them. Below it no read can fit.
 */
function minSynthesizedBytes(additions: number): number {
  return 16 + 2 * additions - 1;
}

/**
 * cycle-135 C-3 (review round 1, bd-w5pd9): a provider refusal that will repeat for every file (rate limit, auth) stops
 * the loop. `FORBIDDEN` is gh's exit 4 (auth); an HTTP 401/403 arrives as `NETWORK` with the parsed status on the
 * adapter's error. A 404 or a malformed envelope is per-file and does not stop it.
 */
function stopsContentFetches(err: unknown): boolean {
  if (!(err instanceof GitProviderError)) return false;
  if (err.code === "RATE_LIMITED" || err.code === "FORBIDDEN") return true;
  const status = (err as { httpStatus?: unknown }).httpStatus;
  return status === 401 || status === 403;
}

/**
 * cycle-135 C-3 (sdd.md C-3, D-1.3a/b; review round 1): read the content of every eligible file — a candidate the
 * placement selection kept (it survived the Loa-tier and user exclusions and the file cap) — in selection order,
 * sequentially, at most `maxContentFetches`, within the deadline from the first read. Each read is bounded by what the
 * planner will have left at the file's position: `maxDiffBytes` minus the GitHub patch bytes selected ahead of it
 * minus the patches synthesized ahead of it (a prefix sum over `placement.included`, the order the planner charges
 * in). A file that cannot fit is `budget` without a call; a read whose patch does not fit is `budget`. A synthesized
 * patch sets the entry's `patchBytes` and is returned for pass 2, pinned to `pin.head_sha` by construction (an
 * attempt that restarts discards it with the rest of its state). A rate-limit or auth refusal stops the loop.
 */
async function fetchMissingPatches(
  git: PagedContentGit, owner: string, repo: string, pin: PullRequestRef, placement: TruncationResult,
  candidates: ReadonlySet<PullRequestFile>, config: SelectionConfig, now: () => number,
): Promise<{ synthesized: Map<string, string>; outcomes: Map<string, FetchOutcome> }> {
  const synthesized = new Map<string, string>();
  const outcomes = new Map<string, FetchOutcome>();
  const cap = config.maxContentFetches ?? DEFAULT_MAX_CONTENT_FETCHES;
  let fetches = 0;
  let charged = 0; // bytes the planner will have charged ahead of the current file
  let start: number | undefined;
  let pastDeadline = false;
  let aborted = false;
  for (const f of placement.included) {
    if (!candidates.has(f)) { charged += f.patchBytes ?? 0; continue; }
    if (aborted) { outcomes.set(f.filename, "aborted"); continue; }
    if (pastDeadline) { outcomes.set(f.filename, "deadline"); continue; }
    if (fetches >= cap) { outcomes.set(f.filename, "skipped_cap"); continue; }
    const remaining = config.maxDiffBytes - charged;
    if (remaining < minSynthesizedBytes(f.additions)) { outcomes.set(f.filename, "budget"); continue; } // no wasted read
    const t = now();
    if (start === undefined) start = t;
    else if (t - start >= CONTENT_FETCH_DEADLINE_MS) { pastDeadline = true; outcomes.set(f.filename, "deadline"); continue; }
    fetches++;
    let res: FileContentResult;
    try {
      res = await git.getFileContent!(owner, repo, f.filename, pin.head_sha, remaining);
    } catch (err) {
      // (network, a path that moved, a malformed envelope, an allowlist refusal: today's no_patch, named)
      outcomes.set(f.filename, "error");
      if (stopsContentFetches(err)) aborted = true;
      continue;
    }
    if (res.kind !== "text") { outcomes.set(f.filename, res.kind); continue; }
    if (res.content.length === 0) { outcomes.set(f.filename, "error"); continue; } // (additions > 0 says it is not empty)
    const patch = synthesizeAddedPatch(res.content);
    const bytes = utf8Bytes(patch);
    if (bytes > remaining) { outcomes.set(f.filename, "budget"); continue; } // never truncated
    charged += bytes;
    synthesized.set(f.filename, patch);
  }
  return { synthesized, outcomes };
}

async function attempt(
  git: PagedContentGit, owner: string, repo: string, prNumber: number, config: SelectionConfig, restarts: number,
  deps: TwoPassDeps,
): Promise<TwoPassResult> {
  const pin = await git.getPR(owner, repo, prNumber);
  const listedTotal = Math.min(pin.changed_files, FILES_ENDPOINT_CAP);
  const pages = Math.ceil(listedTotal / PAGE_SIZE);
  const fetchReasons: DegradedReason[] = [];
  if (pin.changed_files > FILES_ENDPOINT_CAP) fetchReasons.push("files_list_truncated");

  // ── Pass 1: metadata pages ───────────────────────────────────────────────
  const meta = new Map<string, Meta>();
  for (let k = 1; k <= pages; k++) {
    await recheck(git, owner, repo, prNumber, pin);
    const expected = Math.min(PAGE_SIZE, listedTotal - (k - 1) * PAGE_SIZE);
    let entries: PullRequestFile[];
    try {
      entries = await git.getPRFilesPage(owner, repo, prNumber, k);
    } catch (err) {
      const reason = pageFailureReason(err);
      if (reason === undefined) throw err;
      fetchReasons.push(reason);
      continue;
    }
    if (entries.length < expected) fetchReasons.push("page_incomplete");
    for (const e of entries.slice(0, PAGE_SIZE)) {
      if (typeof e.filename !== "string" || meta.has(e.filename)) continue;
      meta.set(e.filename, {
        page: k,
        file: {
          filename: e.filename,
          status: e.status,
          additions: e.additions,
          deletions: e.deletions,
          ...(e.patch != null ? { patchBytes: utf8Bytes(e.patch) } : {}),
        },
      });
    }
  }
  const listed = [...meta.values()].map((m) => m.file);

  // ── Global selection over the complete metadata list ─────────────────────
  // (the byte budget is applied below with cut semantics, so truncateFiles selects on filters, tiers and the file cap)
  // (cycle-135 C-2: the selection is given the PR base sha, so `.reviewignore` is the base ref's copy — D-1.2a)
  const selConfig = { ...config, maxDiffBytes: Number.MAX_SAFE_INTEGER, reviewignoreBaseSha: pin.base_sha };
  const select = deps.truncate ?? truncateFiles;
  // ── cycle-135 C-3: content for added files listed without a patch ────────
  // (review round 1) A candidate is given a placeholder size of 0 for a placement selection: the selection's filters
  // and order never depend on the patch, so the file sits exactly where the planner will charge it, and the GitHub
  // patch bytes ahead of it are known before any read. After the reads the selection is re-run on the real sizes (a
  // synthesized patchBytes, or none again) — so with a candidate present the selection runs twice.
  const fetchOn = config.fetchMissingPatches !== false && typeof git.getFileContent === "function";
  const candidates = new Set(fetchOn ? listed.filter(isContentCandidate) : []);
  for (const f of candidates) f.patchBytes = 0;
  let sel = select(listed, selConfig);
  let synthesized = new Map<string, string>();
  let outcomes = new Map<string, FetchOutcome>();
  if (candidates.size > 0) {
    ({ synthesized, outcomes } = await fetchMissingPatches(git, owner, repo, pin, sel, candidates, config, deps.now ?? Date.now));
    for (const f of candidates) {
      const patch = synthesized.get(f.filename);
      if (patch !== undefined) f.patchBytes = utf8Bytes(patch);
      else delete f.patchBytes;
    }
    sel = select(listed, selConfig);
  }

  const byName = new Map(listed.map((f) => [f.filename, f]));
  const omitted: CoverageRecord["omitted"] = [];
  for (const ex of sel.excluded) {
    const reason = exclusionReason(ex.stats.replace(PATTERN_SUFFIX, ""), byName.get(ex.filename));
    // (review round 1: the structured field first; the stats suffix and the config fallback until A drops the suffix)
    const pattern = reason === "excluded_loa" || reason === "excluded_pattern"
      ? ex.pattern ?? exclusionPattern(ex.stats, ex.filename, config.excludePatterns) : undefined;
    omitted.push(omission(ex.filename, reason, reason === "no_patch" ? outcomes.get(ex.filename) : undefined, pattern));
  }

  // Byte budget planned on the recorded sizes, in selection order.
  const plan: Array<{ file: PullRequestFile; bytes: number; cut: boolean }> = [];
  const budgetExcluded: Array<{ filename: string; stats: string }> = [];
  let remaining = config.maxDiffBytes;
  for (const f of sel.included) {
    const size = f.patchBytes ?? 0;
    if (synthesized.has(f.filename) && size > remaining) {
      // cycle-135 C-3: a synthesized patch is never cut — it stays today's no_patch, named budget (the fetch already
      // charged the bytes ahead of it, so this is defensive)
      omitted.push(omission(f.filename, "no_patch", "budget"));
      budgetExcluded.push({ filename: f.filename, stats: `+${f.additions} -${f.deletions} (diff unavailable)` });
      continue;
    }
    if (size <= remaining) {
      plan.push({ file: f, bytes: size, cut: false });
      remaining -= size;
    } else if (remaining > 0) {
      plan.push({ file: f, bytes: remaining, cut: true });
      remaining = 0;
    } else {
      omitted.push(omission(f.filename, "byte_budget"));
      budgetExcluded.push({ filename: f.filename, stats: `+${f.additions} -${f.deletions} (over max_diff_bytes)` });
    }
  }

  // ── Pass 2: patches for planned files only ───────────────────────────────
  const planned = new Map(plan.map((p) => [p.file.filename, p]));
  // (a synthesized patch is pre-retained: its page holds no patch text for it)
  const neededPages = [...new Set(plan.filter((p) => !synthesized.has(p.file.filename))
    .map((p) => meta.get(p.file.filename)!.page))].sort((a, b) => a - b);
  const retained = new Map<string, PullRequestFile>();
  for (const p of plan) {
    const patch = synthesized.get(p.file.filename);
    if (patch !== undefined) retained.set(p.file.filename, { ...p.file, patch });
  }
  const failedPages = new Set<number>();
  for (const k of neededPages) {
    await recheck(git, owner, repo, prNumber, pin);
    let entries: PullRequestFile[] = [];
    try {
      entries = await git.getPRFilesPage(owner, repo, prNumber, k);
    } catch (err) {
      const reason = pageFailureReason(err);
      if (reason === undefined) throw err;
      fetchReasons.push(reason);
      failedPages.add(k);
    }
    for (const e of entries) {
      const p = planned.get(e.filename);
      if (!p || retained.has(e.filename) || e.patch == null) continue;
      // (cutting a whole-file plan to its recorded size is a no-op under the pin; it keeps max_diff_bytes binding)
      retained.set(e.filename, { ...p.file, patch: cutPatch(e.patch, p.bytes) });
    }
  }
  await recheck(git, owner, repo, prNumber, pin);

  const files: PullRequestFile[] = [];
  const reviewed: CoverageRecord["reviewed"] = [];
  const pageExcluded: Array<{ filename: string; stats: string }> = [];
  for (const p of plan) {
    const f = retained.get(p.file.filename);
    if (!f) {
      // (a failed page already named its reason; a page that arrived without the file is page_incomplete)
      if (!failedPages.has(meta.get(p.file.filename)!.page)) fetchReasons.push("page_incomplete");
      omitted.push(omission(p.file.filename, "page_incomplete"));
      pageExcluded.push({ filename: p.file.filename, stats: `+${p.file.additions} -${p.file.deletions} (patch not received)` });
      continue;
    }
    const bytes = utf8Bytes(f.patch!);
    const truncated = p.cut || bytes < (p.file.patchBytes ?? 0);
    if (truncated) omitted.push(omission(f.filename, "patch_truncated"));
    files.push(f);
    reviewed.push({
      file: f.filename, bytes, hunks: countHunks(f.patch!),
      ...(synthesized.has(f.filename) ? { source: "contents" as const } : {}),
    });
  }

  omitted.sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : a.reason < b.reason ? -1 : a.reason > b.reason ? 1 : 0));
  const unknown = Math.max(0, pin.changed_files - meta.size);
  // cycle-135 C-2 (D-1.2a; lead wiring, Task 1.7): `truncateFiles` read `.reviewignore` once — from the PR base sha when the
  // selection config carried `reviewignoreBaseSha` — and reports where it came from on its result; the record takes that
  // (one read, no second `parseReviewignoreFile`). Tests may inject `deps.reviewignoreSource` instead.
  const reviewignoreSource = deps.reviewignoreSource
    ? deps.reviewignoreSource(config.repoRoot, { baseSha: pin.base_sha })
    : sel.reviewignoreSource;
  // (review round 1) the base copy could not be read, so the checkout's — PR-head-controlled — copy governed the
  // exclusions: a fetch-side reason, so the merge is blocked as incomplete_coverage
  if (reviewignoreSource === "base_unavailable") fetchReasons.push("reviewignore_unavailable");
  const verdict = evaluateCoverage({ omitted, unknown_omitted: unknown, fetchReasons });
  const totalBytes = reviewed.reduce((n, r) => n + r.bytes, 0);
  return {
    files,
    selection: { ...sel, included: files, excluded: [...sel.excluded, ...budgetExcluded, ...pageExcluded], totalBytes },
    coverage: {
      base_sha: pin.base_sha,
      head_sha: pin.head_sha,
      changed_files: pin.changed_files,
      listed: meta.size,
      reviewed,
      omitted,
      unknown_omitted: unknown,
      ...verdict,
      restarts,
      // cycle-135 C-2 (consumer side): what protection kept, and where `.reviewignore` came from
      protected_kept: sel.protectedKept ?? [],
      ...(reviewignoreSource !== undefined ? { reviewignore_source: reviewignoreSource } : {}),
      reviewignore_changed_in_pr: meta.has(".reviewignore"),
    },
  };
}

/** The two-pass fetch with one restart on a base/head move (sdd.md C-1). */
export async function fetchPRFilesTwoPass(
  git: PagedContentGit, owner: string, repo: string, prNumber: number, config: SelectionConfig, deps: TwoPassDeps = {},
): Promise<TwoPassResult> {
  let restarts = 0;
  for (;;) {
    try {
      return await attempt(git, owner, repo, prNumber, config, restarts, deps);
    } catch (err) {
      if (!(err instanceof PrHeadMoved)) throw err;
      if (restarts === 0) {
        restarts = 1;
        continue;
      }
      return {
        files: [],
        selection: { included: [], excluded: [], totalBytes: 0, allExcluded: false, selfReviewActive: false, selfReviewState: "inactive" },
        coverage: {
          base_sha: err.latest.base_sha,
          head_sha: err.latest.head_sha,
          changed_files: err.latest.changed_files,
          listed: 0,
          reviewed: [],
          omitted: [],
          unknown_omitted: err.latest.changed_files,
          degraded: true,
          degraded_reasons: ["pr_head_moved"],
          mergeBlockedReason: "incomplete_coverage",
          restarts,
        },
      };
    }
  }
}

/** Whether a provider implements the paged contract. */
export function hasPagedContract(git: IGitProvider): git is IGitProvider & PagedGit {
  return typeof git.getPR === "function" && typeof git.getPRFilesPage === "function";
}

/**
 * The truncation for a (possibly incremental) item: the fetch's global selection when the item still carries the
 * fetched file list, else `truncateFiles` over the given files (deriveCallConfig stays the single chokepoint).
 */
export function truncationFor(
  item: ReviewItem,
  config: Parameters<typeof truncateFiles>[1] & Pick<BridgebuilderConfig, "selfReview">,
): TruncationResult {
  if (item.selection && item.files === item.selection.included) return item.selection;
  return truncateFiles(item.files, deriveCallConfig(config, item.pr));
}

const MARKER_FULL_LIMIT = 20_000;

/**
 * A PR-supplied path made safe for one line of the posted markdown: no backtick or newline (code-span breakout) and
 * no `<`/`>` (a path can never spell an HTML comment such as a review marker). The summary JSON keeps the real name.
 */
function safePath(p: string): string {
  return p.replace(/[`\r\n]/g, "'").replace(/</g, "%3C").replace(/>/g, "%3E");
}

/**
 * The coverage marker: the full record when it fits the comment budget, else a compact form carrying both SHAs,
 * the counts and the sha256 of the full record (which is in the summary JSON in full).
 */
export function coverageMarker(coverage: CoverageRecord): string {
  const full = JSON.stringify(coverage);
  let payload = full;
  if (full.length > MARKER_FULL_LIMIT) {
    payload = JSON.stringify({
      base_sha: coverage.base_sha,
      head_sha: coverage.head_sha,
      changed_files: coverage.changed_files,
      listed: coverage.listed,
      reviewed_count: coverage.reviewed.length,
      omitted_counts: omissionCounts(coverage),
      unknown_omitted: coverage.unknown_omitted,
      degraded: coverage.degraded,
      degraded_reasons: coverage.degraded_reasons,
      ...(coverage.mergeBlockedReason ? { mergeBlockedReason: coverage.mergeBlockedReason } : {}),
      restarts: coverage.restarts,
      record_sha256: createHash("sha256").update(full).digest("hex"),
      record: "summary-json",
    });
  }
  // "--" never occurs outside JSON strings; escaping it inside strings keeps "-->" from closing the comment
  return `<!-- bridgebuilder-coverage: ${payload.replace(/--/g, "-\\u002d")} -->`;
}

function omissionCounts(coverage: CoverageRecord): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const o of coverage.omitted) counts[o.reason] = (counts[o.reason] ?? 0) + 1;
  return Object.fromEntries(Object.entries(counts).sort(([a], [b]) => (a < b ? -1 : 1)));
}

/** The posted coverage section: pinned pair, counts per reason, the first 20 omitted paths, and the marker. */
export function formatCoverageSection(coverage: CoverageRecord): string {
  const lines: string[] = [];
  lines.push("### Review coverage");
  lines.push("");
  lines.push(`Pinned: base ${coverage.base_sha.slice(0, 12)} · head ${coverage.head_sha.slice(0, 12)}` +
    (coverage.restarts > 0 ? ` (fetch restarted ${coverage.restarts}× after a head move)` : ""));
  const bytes = coverage.reviewed.reduce((n, r) => n + r.bytes, 0);
  lines.push(`Reviewed ${coverage.reviewed.length} of ${coverage.changed_files} changed files (${bytes} patch bytes); ` +
    `${coverage.omitted.length} omitted by name; ${coverage.unknown_omitted} not listed by GitHub.`);
  const counts = omissionCounts(coverage);
  if (Object.keys(counts).length > 0) {
    lines.push("");
    for (const [reason, n] of Object.entries(counts)) lines.push(`- ${reason}: ${n}`);
  }
  if (coverage.omitted.length > 0) {
    const ordered = [...coverage.omitted].sort((a, b) => Number(b.reviewable) - Number(a.reviewable));
    lines.push("");
    lines.push(`First ${Math.min(20, ordered.length)} omitted paths:`);
    for (const o of ordered.slice(0, 20)) {
      // cycle-135 C-2/C-3: the excluding pattern and the content-fetch outcome, when recorded
      lines.push(`- \`${safePath(o.file)}\` — ${o.reason}${o.reviewable ? " (reviewable)" : ""}` +
        (o.pattern !== undefined ? ` · pattern \`${safePath(o.pattern)}\`` : "") +
        (o.fetch ? ` · fetch: ${o.fetch}` : ""));
    }
  }
  const fromContents = coverage.reviewed.filter((r) => r.source === "contents");
  if (fromContents.length > 0) {
    // cycle-135 C-3: patches synthesized from the file's content (an added file GitHub listed without one)
    lines.push("");
    lines.push(`Reviewed from file contents (${fromContents.length}):`);
    for (const r of fromContents) lines.push(`- \`${safePath(r.file)}\` (source: contents)`);
  }
  const kept = coverage.protected_kept ?? [];
  if (kept.length > 0) {
    // cycle-135 C-2: protected files a wildcard user exclusion would have removed, with their final status
    lines.push("");
    lines.push(`Protected paths kept (${kept.length}):`);
    for (const k of kept) {
      const cut = coverage.omitted.filter((o) => o.file === k.file).map((o) => o.reason);
      lines.push(`- \`${safePath(k.file)}\` — kept despite \`${safePath(k.pattern)}\`` +
        (cut.length > 0 ? ` then omitted (${cut.join(", ")})` : ""));
    }
  }
  if (coverage.reviewignore_source !== undefined || coverage.reviewignore_changed_in_pr) {
    lines.push("");
    const source = coverage.reviewignore_source === "base_unavailable"
      ? "base_unavailable (checkout copy applied; review degraded)" : coverage.reviewignore_source ?? "not recorded";
    lines.push(`.reviewignore: ${source}` +
      (coverage.reviewignore_changed_in_pr ? " (changed in this PR)" : ""));
  }
  if (coverage.degraded) {
    lines.push("");
    lines.push(`**Degraded**: ${coverage.degraded_reasons.join(", ")} — merge blocked: ${coverage.mergeBlockedReason ?? "incomplete_coverage"}.`);
  }
  lines.push("");
  lines.push(coverageMarker(coverage));
  return lines.join("\n");
}
