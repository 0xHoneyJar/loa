// cycle-133 Sprint 1 Task 1.1 (sdd.md C-1, FR-1, KF-054): the Bridgebuilder reads large pull requests.
//
// Every case runs the REAL GitHubCLIAdapter (endpoint allowlist, buffer handling) against a mocked `gh`
// executable and the REAL truncateFiles selection. The mock enforces the per-call `maxBuffer` the way
// Node's execFile does, so an unbounded fetch fails here exactly as it failed on PR #1289.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { GitHubCLIAdapter, type GhExec } from "../adapters/github-cli.js";
import { fetchPRFilesTwoPass, evaluateCoverage, REVIEWABLE_OMISSION_REASONS } from "../core/paged-fetch.js";
import { PRReviewTemplate } from "../core/template.js";
import { ReviewPipeline } from "../core/reviewer.js";
import { BridgebuilderContext } from "../core/context.js";
import { summarizeReviewVerdict } from "../core/review-verdict.js";
import { DEGRADED_REASONS } from "../core/run-outcome.js";
import { DEFAULT_EXCLUDE_PATTERNS } from "../config.js";
import type { BridgebuilderConfig } from "../core/types.js";
import type { PostReviewInput } from "../ports/review-poster.js";

const BASE = "b".repeat(40);
const HEAD = "a".repeat(40);
const HEAD2 = "c".repeat(40);
const MiB = 1024 * 1024;

interface RawFile {
  filename: string;
  status: string;
  additions: number;
  deletions: number;
  patch?: string;
}

/** Deterministic patch of roughly `bytes` bytes with `hunks` hunk headers. */
function makePatch(seed: number, bytes: number, hunks = 1): string {
  const lines: string[] = [];
  let size = 0;
  let h = 0;
  let i = 0;
  while (size < bytes) {
    if (h < hunks && i % Math.max(1, Math.floor(bytes / 60 / hunks)) === 0) {
      const line = `@@ -${i + 1},3 +${i + 1},4 @@ hunk ${h} of file ${seed}`;
      lines.push(line);
      size += line.length + 1;
      h++;
    }
    const line = `+const value_${seed}_${i} = ${(seed * 7919 + i * 104729) % 1000003}; // padding padding`;
    lines.push(line);
    size += line.length + 1;
    i++;
  }
  return lines.join("\n");
}

function codeFiles(n: number, patchBytes: number): RawFile[] {
  return Array.from({ length: n }, (_, i) => ({
    filename: `src/module-${String(i).padStart(4, "0")}.ts`,
    status: "modified",
    additions: 10 + (i % 37),
    deletions: i % 5,
    patch: makePatch(i, patchBytes),
  }));
}

interface GhFixture {
  files: RawFile[];
  changedFiles?: number;
  /** Head sha served by the Nth (0-based) read of pulls/N; the last entry repeats. */
  heads?: string[];
  /** Page number → the error the page request raises. */
  pageErrors?: Map<number, () => Error>;
  /** Page number → serve only this many entries (an incomplete page). */
  shortPages?: Map<number, number>;
}

function maxBufferError(): Error {
  return Object.assign(new RangeError("stdout maxBuffer length exceeded"), { code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER" });
}

function ghFixture(fx: GhFixture) {
  const calls: string[][] = [];
  let prReads = 0;
  const heads = fx.heads ?? [HEAD];
  const exec: GhExec = async (_file, args, options) => {
    calls.push(args);
    if (args[0] === "auth") return { stdout: "Token scopes: repo" };
    const endpoint = args[1];
    let body: string;
    const pr = endpoint.match(/^\/repos\/o\/r\/pulls\/7$/);
    const page = endpoint.match(/^\/repos\/o\/r\/pulls\/7\/files\?per_page=100&page=(\d+)$/);
    const legacy = endpoint === "/repos/o/r/pulls/7/files?per_page=100";
    if (endpoint === "/rate_limit") {
      body = JSON.stringify({ resources: { core: { remaining: 5000 } } });
    } else if (endpoint === "/repos/o/r") {
      body = JSON.stringify({ full_name: "o/r" });
    } else if (pr) {
      const head = heads[Math.min(prReads, heads.length - 1)];
      prReads++;
      body = JSON.stringify({
        number: 7, base: { sha: BASE, ref: "main" }, head: { sha: head }, changed_files: fx.changedFiles ?? fx.files.length,
      });
    } else if (page) {
      const k = Number(page[1]);
      const err = fx.pageErrors?.get(k);
      if (err) throw err();
      const listed = fx.files.slice(0, 3000);
      let slice = listed.slice((k - 1) * 100, k * 100);
      const short = fx.shortPages?.get(k);
      if (short !== undefined) slice = slice.slice(0, short);
      body = JSON.stringify(slice);
    } else if (legacy) {
      body = JSON.stringify(fx.files.slice(0, 3000));
    } else {
      throw new Error(`unexpected gh call: ${args.join(" ")}`);
    }
    if (Buffer.byteLength(body) > options.maxBuffer) throw maxBufferError();
    return { stdout: body };
  };
  return { exec, calls, pageCalls: () => calls.filter((a) => a[1].includes("&page=")), prReads: () => prReads };
}

function adapter(exec: GhExec, ghMaxBufferBytes = 64 * MiB): GitHubCLIAdapter {
  return new GitHubCLIAdapter({ reviewMarker: "bridgebuilder-review", exec, ghMaxBufferBytes });
}

const SEL = {
  excludePatterns: [...DEFAULT_EXCLUDE_PATTERNS],
  maxDiffBytes: 512_000,
  maxFilesPerPr: 50,
  loaAware: false,
  selfReview: false,
};

function makeConfig(overrides: Partial<BridgebuilderConfig> = {}): BridgebuilderConfig {
  return {
    repos: [{ owner: "o", repo: "r" }],
    model: "fixture",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 512_000,
    maxInputTokens: 2_000_000,
    maxOutputTokens: 4000,
    dimensions: ["security"],
    reviewMarker: "bridgebuilder-review",
    repoOverridePath: "",
    dryRun: false,
    excludePatterns: [...DEFAULT_EXCLUDE_PATTERNS],
    sanitizerMode: "default",
    maxRuntimeMinutes: 30,
    reviewMode: "single-pass",
    loaAware: false,
    targetPr: 7,
    ...overrides,
  };
}

describe("two-pass paged fetch (C-1)", () => {
  it("KF-054: one 2,000-file payload overflows a 10 MiB per-call buffer; the paged fetch reads it under the same buffer", async () => {
    const files = codeFiles(2000, 5600);
    const total = Buffer.byteLength(JSON.stringify(files));
    assert.ok(total > 10 * MiB, `fixture patch payload must exceed 10 MiB (got ${total})`);
    const gh = ghFixture({ files });
    // the pre-cycle-133 shape: every file and every patch in one call
    await assert.rejects(adapter(gh.exec, 10 * MiB).getPRFiles("o", "r", 7), (err: Error & { code?: string }) => err.code === "PAYLOAD_OVERSIZE");
    const res = await fetchPRFilesTwoPass(adapter(gh.exec, 10 * MiB), "o", "r", 7, SEL);
    assert.equal(res.coverage.listed, 2000);
    assert.equal(res.coverage.unknown_omitted, 0);
    assert.equal(res.files.length, 50, "max_files_per_pr bounds the selection");
    const retained = res.files.reduce((n, f) => n + Buffer.byteLength(f.patch ?? ""), 0);
    assert.ok(retained <= SEL.maxDiffBytes, `retained ${retained} bytes must not exceed max_diff_bytes`);
    // every listed file is accounted for exactly once as reviewed or omitted (patch_truncated may be both)
    const accounted = new Set([...res.coverage.reviewed.map((r) => r.file), ...res.coverage.omitted.map((o) => o.file)]);
    assert.equal(accounted.size, 2000);
    assert.equal(res.coverage.base_sha, BASE);
    assert.equal(res.coverage.head_sha, HEAD);
  });

  it("pass 2 fetches only the pages that hold selected files; the patch count equals the selected count", async () => {
    const files = codeFiles(250, 300);
    // the three largest changes sit on pages 1 and 3 — the selection (max_files_per_pr: 3) is those three
    files[5].additions = 900;
    files[230].additions = 800;
    files[240].additions = 700;
    const gh = ghFixture({ files });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, { ...SEL, maxFilesPerPr: 3 });
    assert.deepEqual(res.files.map((f) => f.filename).sort(), [files[5], files[230], files[240]].map((f) => f.filename).sort());
    assert.equal(res.files.filter((f) => typeof f.patch === "string").length, 3, "patches retained == selected");
    assert.equal(res.coverage.reviewed.length, 3);
    const pageRequests = gh.pageCalls().map((a) => Number(/&page=(\d+)$/.exec(a[1])![1]));
    // pass 1 reads pages 1..3 once each; pass 2 re-reads exactly pages 1 and 3
    assert.deepEqual(pageRequests, [1, 2, 3, 1, 3]);
    for (const f of res.selection.included) assert.ok(res.files.includes(f));
  });

  it("3,001 files: the endpoint's 3,000-file cap is recorded as files_list_truncated with the unknown count kept apart", async () => {
    const files = codeFiles(3001, 40);
    const gh = ghFixture({ files, changedFiles: 3001 });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    assert.equal(res.coverage.changed_files, 3001);
    assert.equal(res.coverage.listed, 3000);
    assert.equal(res.coverage.unknown_omitted, 1);
    assert.ok(!res.coverage.omitted.some((o) => o.file === files[3000].filename), "an unlisted file is never named");
    assert.ok(res.coverage.degraded_reasons.includes("files_list_truncated"));
    assert.equal(res.coverage.degraded, true);
    assert.equal(res.coverage.mergeBlockedReason, "incomplete_coverage");
    assert.ok(!gh.pageCalls().some((a) => a[1].endsWith("page=31")), "no page beyond the cap is requested");
  });

  it("one selected file whose patch alone exceeds max_diff_bytes is retained cut and recorded patch_truncated", async () => {
    const big = makePatch(1, 4000, 4);
    const gh = ghFixture({ files: [{ filename: "src/big.ts", status: "modified", additions: 80, deletions: 2, patch: big }] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, { ...SEL, maxDiffBytes: 1000 });
    assert.equal(res.files.length, 1);
    const kept = res.files[0].patch!;
    assert.ok(Buffer.byteLength(kept) <= 1000 && kept.length > 0);
    assert.ok(big.startsWith(kept), "the retained text is a prefix of the GitHub patch");
    assert.deepEqual(res.coverage.omitted, [{ file: "src/big.ts", reason: "patch_truncated", reviewable: true }]);
    assert.equal(res.coverage.reviewed[0].bytes, Buffer.byteLength(kept));
    assert.ok(res.coverage.reviewed[0].hunks >= 1);
    assert.equal(res.selection.totalBytes, Buffer.byteLength(kept));
    assert.equal(res.coverage.mergeBlockedReason, "incomplete_coverage");
  });

  it("head moved mid-fetch restarts once and pins the new pair", async () => {
    const files = codeFiles(150, 200);
    // reads: initial, before page 1, before page 2 (moved) → restart: initial…
    const gh = ghFixture({ files, heads: [HEAD, HEAD, HEAD2] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    assert.equal(res.coverage.head_sha, HEAD2);
    assert.equal(res.coverage.restarts, 1);
    assert.ok(!res.coverage.degraded_reasons.includes("pr_head_moved"));
    assert.equal(res.files.length, 50);
  });

  it("head moved again after the restart degrades as pr_head_moved and keeps no files", async () => {
    const files = codeFiles(150, 200);
    const gh = ghFixture({ files, heads: [HEAD, HEAD, HEAD2, HEAD2, "d".repeat(40)] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    assert.deepEqual(res.files, []);
    assert.equal(res.coverage.degraded, true);
    assert.deepEqual(res.coverage.degraded_reasons, ["pr_head_moved"]);
    assert.equal(res.coverage.mergeBlockedReason, "incomplete_coverage");
  });

  it("a head change detected by the final revalidation (after pass 2) also restarts", async () => {
    const files = codeFiles(20, 100);
    // reads for one attempt with 1 page: initial, before p1 (pass 1), before p1 (pass 2), final → the final read moves
    const gh = ghFixture({ files, heads: [HEAD, HEAD, HEAD, HEAD2] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    assert.equal(res.coverage.restarts, 1);
    assert.equal(res.coverage.head_sha, HEAD2);
  });

  it("an excluded security-relevant file never degrades and its patch is never retained (both default excludes)", async () => {
    const gh = ghFixture({ files: [
      { filename: "src/app.ts", status: "modified", additions: 3, deletions: 1, patch: "@@ -1 +1 @@\n+ok" },
      { filename: "evals/fixtures/review-prs/pr-9/head/src/auth/session.ts", status: "added", additions: 400, deletions: 0, patch: makePatch(2, 900) },
      { filename: "grimoires/loa/reports/ablation-2.0/c132-grades/run-1/grade.json", status: "added", additions: 50, deletions: 0, patch: makePatch(3, 300) },
    ] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, { ...SEL, selfReview: true, loaAware: true });
    assert.deepEqual(res.files.map((f) => f.filename), ["src/app.ts"]);
    const reasons = Object.fromEntries(res.coverage.omitted.map((o) => [o.file, o]));
    assert.deepEqual(reasons["evals/fixtures/review-prs/pr-9/head/src/auth/session.ts"], { file: "evals/fixtures/review-prs/pr-9/head/src/auth/session.ts", reason: "excluded_pattern", reviewable: false, pattern: "evals/fixtures/review-prs/**" });
    assert.equal(reasons["grimoires/loa/reports/ablation-2.0/c132-grades/run-1/grade.json"].reason, "excluded_pattern");
    // cycle-135 C-2 (consumer side): the omission names the default pattern that excluded it
    assert.equal(reasons["grimoires/loa/reports/ablation-2.0/c132-grades/run-1/grade.json"].pattern, "grimoires/loa/reports/ablation-2.0/*-grades/**");
    assert.equal(res.coverage.degraded, false);
    assert.equal(res.coverage.mergeBlockedReason, undefined);
  });

  it("GitHub omissions are recorded, never silent: a code file without a patch degrades, a binary does not", async () => {
    const gh = ghFixture({ files: [
      { filename: "src/a.ts", status: "modified", additions: 1, deletions: 0, patch: "@@ -1 +1 @@\n+a" },
      { filename: "assets/logo.png", status: "added", additions: 0, deletions: 0 },
      { filename: "docs/old-name.md", status: "renamed", additions: 0, deletions: 0 },
    ] });
    const ok = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    assert.deepEqual(ok.coverage.omitted, [
      { file: "assets/logo.png", reason: "no_patch", reviewable: false },
      { file: "docs/old-name.md", reason: "renamed", reviewable: false },
    ]);
    assert.equal(ok.coverage.degraded, false);
    const gh2 = ghFixture({ files: [{ filename: "src/huge.ts", status: "modified", additions: 9000, deletions: 0 }] });
    const bad = await fetchPRFilesTwoPass(adapter(gh2.exec), "o", "r", 7, SEL);
    assert.deepEqual(bad.coverage.omitted, [{ file: "src/huge.ts", reason: "no_patch", reviewable: true }]);
    assert.equal(bad.coverage.degraded, true);
    assert.deepEqual(bad.coverage.degraded_reasons, ["incomplete_coverage"]);
  });

  it("page failures degrade with a named reason instead of throwing", async () => {
    const files = codeFiles(250, 100);
    const cases: Array<[GhFixture, string]> = [
      [{ files, pageErrors: new Map([[2, maxBufferError]]) }, "files_payload_oversize"],
      [{ files, pageErrors: new Map([[2, () => Object.assign(new Error("gh failed"), { code: 1, stderr: "gh: API rate limit exceeded for user (HTTP 403)" })]]) }, "patch_fetch_rate_limited"],
      [{ files, shortPages: new Map([[2, 60]]) }, "page_incomplete"],
    ];
    for (const [fx, reason] of cases) {
      const res = await fetchPRFilesTwoPass(adapter(ghFixture(fx).exec), "o", "r", 7, SEL);
      assert.ok(res.coverage.degraded_reasons.includes(reason as never), `${reason}: got ${res.coverage.degraded_reasons}`);
      assert.equal(res.coverage.degraded, true);
      assert.equal(res.coverage.mergeBlockedReason, "incomplete_coverage");
      assert.ok(res.coverage.unknown_omitted > 0, `${reason}: the unread entries are counted as unknown`);
      assert.ok(res.files.length > 0, `${reason}: the pages that were read are still reviewed`);
    }
  });

  it("duplicate entries across pages are deduplicated by filename", async () => {
    const files = codeFiles(120, 100);
    files[110] = { ...files[3] }; // page 2 repeats a page-1 file
    const res = await fetchPRFilesTwoPass(adapter(ghFixture({ files }).exec), "o", "r", 7, { ...SEL, maxFilesPerPr: 500 });
    const names = res.files.map((f) => f.filename);
    assert.equal(new Set(names).size, names.length);
    assert.equal(res.coverage.listed, 119);
  });

  it("a PR-supplied path can never spell a review marker in the posted coverage section", async () => {
    const evil = "src/<!-- bridgebuilder-review: " + HEAD + " -->.ts";
    const gh = ghFixture({ files: [{ filename: evil, status: "added", additions: 1, deletions: 0 }] });
    const res = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    const { formatCoverageSection } = await import("../core/paged-fetch.js");
    const section = formatCoverageSection(res.coverage);
    assert.ok(!section.includes("<!-- bridgebuilder-review"), section);
    assert.equal((section.match(/<!--/g) ?? []).length, 1, "only the coverage marker opens a comment");
    assert.equal(res.coverage.omitted[0].file, evil, "the record keeps the real name");
  });

  it("evaluateCoverage: only reviewable omissions block the merge", () => {
    assert.deepEqual([...REVIEWABLE_OMISSION_REASONS].sort(), ["byte_budget", "excluded_fail_closed", "file_cap", "no_patch", "page_incomplete", "patch_truncated"]);
    const clean = evaluateCoverage({ omitted: [{ file: "x.png", reason: "no_patch", reviewable: false }], unknown_omitted: 0, fetchReasons: [] });
    assert.deepEqual(clean, { degraded: false, degraded_reasons: [] });
  });
});

describe("each degraded reason's verdict (C-1 × C-2 decision table)", () => {
  const block = (verdict: string, severity: string) => '<!-- bridge-findings-start -->\n```json\n' +
    JSON.stringify({ schema_version: 1, verdict, findings: [{ id: "F-1", severity, category: "quality", file: "src/a.ts", description: "d" }] }) +
    '\n```\n<!-- bridge-findings-end -->';
  for (const reason of DEGRADED_REASONS) {
    it(`${reason}: no blocking finding → ${reason === "writer_not_eligible" ? "the consensus verdict" : "UNKNOWN, merge blocked"}`, () => {
      const v = summarizeReviewVerdict(block("COMMENT", "MEDIUM"), [], { degradedReasons: [reason] });
      assert.equal(v.degraded, true);
      assert.equal(v.degradedReason, reason);
      if (reason === "writer_not_eligible") {
        assert.equal(v.verdict, "COMMENT");
        assert.equal(v.mergeBlocked, false);
      } else {
        assert.equal(v.verdict, "UNKNOWN");
        assert.equal(v.mergeBlocked, true);
        assert.equal(v.mergeBlockedReason, ["files_payload_oversize", "files_list_truncated", "page_incomplete", "patch_fetch_rate_limited", "pr_head_moved"].includes(reason) ? "incomplete_coverage" : reason);
      }
    });
    it(`${reason}: a HIGH finding still yields REQUEST_CHANGES (rule 1 first)`, () => {
      const v = summarizeReviewVerdict(block("REQUEST_CHANGES", "HIGH"), [], { degradedReasons: [reason] });
      assert.equal(v.verdict, "REQUEST_CHANGES");
      assert.equal(v.mergeBlocked, true);
      assert.equal(v.degraded, true);
    });
  }
});

describe("2,000-file PR end to end (mocked gh, mocked model)", () => {
  it("resolves, reviews and posts with the coverage record; the verdict names incomplete_coverage", async () => {
    const files = codeFiles(2000, 5600);
    const gh = ghFixture({ files });
    const git = adapter(gh.exec, 10 * MiB);
    // listOpenPRs is not part of the paged contract; serve it from the fixture PR
    (git as unknown as { listOpenPRs: () => Promise<unknown[]> }).listOpenPRs = async () => [
      { number: 7, title: "big", headSha: HEAD, baseBranch: "main", labels: [], author: "dev" },
    ];
    (git as unknown as { getPRReviews: () => Promise<unknown[]> }).getPRReviews = async () => [];
    const config = makeConfig();
    const hasher = { sha256: async (s: string) => (await import("node:crypto")).createHash("sha256").update(s).digest("hex") };
    const template = new PRReviewTemplate(git, hasher, config);
    const posted: PostReviewInput[] = [];
    const poster = {
      postReview: async (input: PostReviewInput) => { posted.push(input); return true; },
      hasExistingReview: async () => false,
    };
    const store = {
      load: async () => {}, getLastHash: async () => null, setLastHash: async () => {}, claimReview: async () => true,
      finalizeReview: async () => {}, getLastReviewedSha: async () => null, setLastReviewedSha: async () => {},
    };
    const llm = { generateReview: async () => ({
      content: "## Summary\nReviewed.\n\n## Findings\n- **MEDIUM** `src/module-0001.ts:1` — padding.\n\n## Callouts\n- none\n\nVerdict: COMMENT",
      inputTokens: 1, outputTokens: 1, model: "fixture",
    }) };
    const pipeline = new ReviewPipeline(
      template, new BridgebuilderContext(store as never), git, poster, llm,
      { sanitize: (c: string) => ({ safe: true, sanitizedContent: c, redactedPatterns: [] }) },
      { info() {}, warn() {}, error() {}, debug() {} }, "persona", config,
    );
    const summary = await pipeline.run("run-fixture");
    assert.equal(summary.errors, 0, JSON.stringify(summary.results.map((r) => r.error)));
    assert.equal(summary.reviewed, 1);
    const r = summary.results[0];
    assert.equal(r.item.files.length, 50);
    assert.equal(r.item.coverage?.listed, 2000);
    assert.equal(r.verdict, "UNKNOWN");
    assert.equal(r.mergeBlocked, true);
    assert.equal(r.mergeBlockedReason, "incomplete_coverage");
    assert.equal(r.degradedReason, "incomplete_coverage");
    assert.equal(posted.length, 1);
    const body = posted[0].body;
    assert.match(body, /Review coverage/);
    assert.match(body, /file_cap: 1950/);
    assert.match(body, new RegExp(`base ${BASE.slice(0, 12)}`));
    const marker = body.match(/<!-- bridgebuilder-coverage: (\{.*\}) -->/);
    assert.ok(marker, "the coverage marker is posted");
    const parsed = JSON.parse(marker![1]);
    assert.equal(parsed.base_sha, BASE);
    assert.equal(parsed.head_sha, HEAD);
    assert.equal(parsed.unknown_omitted, 0);
    // the comment lists at most 20 omitted paths
    const listed = body.split("\n").filter((l) => /^- `src\/module-\d{4}\.ts` — /.test(l));
    assert.ok(listed.length > 0 && listed.length <= 20, `listed ${listed.length}`);
  });
});

describe("multi-model consensus carries the coverage record (C-1)", () => {
  it("an incomplete coverage blocks the consensus verdict and the coverage section is posted with the marker", async () => {
    const { composeConsensusReview } = await import("../core/consensus-findings.js");
    const { scoreFindings } = await import("../core/scoring.js");
    const gh = ghFixture({ files: [{ filename: "src/huge.ts", status: "modified", additions: 9000, deletions: 0 },
      { filename: "src/a.ts", status: "modified", additions: 1, deletions: 0, patch: "@@ -1 +1 @@\n+a" }] });
    const fetched = await fetchPRFilesTwoPass(adapter(gh.exec), "o", "r", 7, SEL);
    const consensus = scoreFindings([
      { provider: "anthropic", model: "claude-headless", findings: [{ id: "F-1", title: "t", severity: "LOW", category: "c", file: "src/a.ts:1", description: "d" }] },
      { provider: "openai", model: "gpt-5.5-pro", findings: [] },
    ], { high_consensus: 700, disputed_delta: 300, low_value: 400, blocker: 700 });
    const out = composeConsensusReview({ header: "h", consensus, coverage: fetched.coverage, degradedReasons: fetched.coverage.degraded_reasons });
    assert.deepEqual([out.verdict.verdict, out.verdict.mergeBlocked, out.verdict.mergeBlockedReason], ["UNKNOWN", true, "incomplete_coverage"]);
    assert.match(out.body, /<!-- bridgebuilder-coverage: \{.*"head_sha":"a{40}".*\} -->/);
    assert.match(out.body, /`src\/huge\.ts` — no_patch \(reviewable\)/);
  });
});
