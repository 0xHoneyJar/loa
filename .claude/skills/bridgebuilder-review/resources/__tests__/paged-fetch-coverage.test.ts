// cycle-135 Sprint 279 Task 1.4 (sdd.md C-2 consumer side, § 3, § 4; FR-2 rendering, FR-3 marker): the coverage
// record carries the protected-kept files, the excluding pattern, the content-fetch outcome and the `.reviewignore`
// provenance, and the posted summary renders each through the existing `safePath` escaping. The selection producer
// (implementer A's truncateFiles) is replaced by a double where its new fields are needed; A's code is not used here.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { fetchPRFilesTwoPass, formatCoverageSection } from "../core/paged-fetch.js";
import { truncateFiles } from "../core/truncation.js";
import type { CoverageRecord, TruncationResult } from "../core/types.js";
import type { PullRequestFile, PullRequestRef } from "../ports/git-provider.js";

const BASE = "b".repeat(40);
const HEAD = "a".repeat(40);

function provider(files: PullRequestFile[]) {
  return {
    async getPR(): Promise<PullRequestRef> { return { base_sha: BASE, head_sha: HEAD, changed_files: files.length }; },
    async getPRFilesPage(_o: string, _r: string, _n: number, page: number): Promise<PullRequestFile[]> {
      return files.slice((page - 1) * 100, page * 100).map((f) => ({ ...f }));
    },
  };
}

const SEL = { excludePatterns: [] as string[], maxDiffBytes: 512_000, maxFilesPerPr: 50, loaAware: false, selfReview: false };
const patched = (filename: string, patch: string, additions = 1): PullRequestFile =>
  ({ filename, status: "modified", additions, deletions: 0, patch });

type Deps = Record<string, unknown>;
const run = (git: unknown, config: unknown, deps: Deps) =>
  (fetchPRFilesTwoPass as unknown as (...a: unknown[]) => ReturnType<typeof fetchPRFilesTwoPass>)(git, "o", "r", 7, config, deps);

/** A selection double: keeps `keep` (in that order), excludes the rest with the given stats, reports protectedKept. */
function selectionDouble(
  keep: string[], excluded: Record<string, string | { stats: string; pattern?: string }>,
  protectedKept: TruncationResult["protectedKept"], extra: Record<string, unknown> = {},
) {
  const configs: Array<Record<string, unknown>> = [];
  const fn = (files: PullRequestFile[], config: Record<string, unknown>): TruncationResult => {
    configs.push(config);
    const byName = new Map(files.map((f) => [f.filename, f]));
    return {
      included: keep.map((n) => byName.get(n)!).filter(Boolean),
      excluded: Object.entries(excluded).map(([filename, e]) => (typeof e === "string" ? { filename, stats: e } : { filename, ...e })),
      totalBytes: 0, allExcluded: false, selfReviewActive: false, selfReviewState: "inactive", protectedKept, ...extra,
    };
  };
  return { fn, configs };
}

describe("coverage record: protected paths, patterns, provenance (C-2 consumer side)", () => {
  it("protected_kept is copied from the selection; a protected file later cut by the budget is also an omission", async () => {
    const a = "@@ -1 +1 @@\n" + "+a".repeat(20);
    const files = [patched("src/a.ts", a, 9), patched(".github/workflows/ci.yml", "@@ -1 +1 @@\n+on: push", 1)];
    const sel = selectionDouble(["src/a.ts", ".github/workflows/ci.yml"], {}, [{ file: ".github/workflows/ci.yml", pattern: "**/*.yml" }]);
    const res = await run(provider(files), { ...SEL, maxDiffBytes: Buffer.byteLength(a) }, { truncate: sel.fn });
    assert.deepEqual(res.coverage.protected_kept, [{ file: ".github/workflows/ci.yml", pattern: "**/*.yml" }]);
    assert.deepEqual(res.coverage.omitted, [{ file: ".github/workflows/ci.yml", reason: "byte_budget", reviewable: true }]);
    assert.deepEqual(res.selection.protectedKept, [{ file: ".github/workflows/ci.yml", pattern: "**/*.yml" }]);
  });

  it("protected_kept is [] when the selection reports none (today's truncateFiles)", async () => {
    const res = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL, {});
    assert.deepEqual(res.coverage.protected_kept, []);
  });

  it("omitted[].pattern: parsed from the Loa-tier ` [pattern: <p>]` suffix and the user-pattern suffix; absent suffix tolerated", async () => {
    const files = [
      patched("src/a.ts", "@@ -1 +1 @@\n+a"), patched(".claude/scripts/x.sh", "@@ -1 +1 @@\n+x"),
      patched("vendor/lib.js", "@@ -1 +1 @@\n+v"), patched(".claude/old.md", "@@ -1 +1 @@\n+o"),
      patched("odd/name.ts", "@@ -1 +1 @@\n+n"),
    ];
    const sel = selectionDouble(["src/a.ts"], {
      ".claude/scripts/x.sh": "+1 -0 (Loa framework, content excluded) [pattern: .claude/scripts/**]",
      "vendor/lib.js": "+1 -0 (.reviewignore user pattern, strict deny) [pattern: vendor/]",
      ".claude/old.md": "+1 -0 (Loa framework, summary only)",
      "odd/name.ts": "+1 -0 (excluded by pattern) [pattern: odd/[ab]] x]",
    }, []);
    const res = await run(provider(files), SEL, { truncate: sel.fn });
    const by = Object.fromEntries(res.coverage.omitted.map((o) => [o.file, o]));
    assert.deepEqual(by[".claude/scripts/x.sh"], { file: ".claude/scripts/x.sh", reason: "excluded_loa", reviewable: false, pattern: ".claude/scripts/**" });
    assert.deepEqual(by["vendor/lib.js"], { file: "vendor/lib.js", reason: "excluded_pattern", reviewable: false, pattern: "vendor/" });
    assert.deepEqual(by[".claude/old.md"], { file: ".claude/old.md", reason: "excluded_loa", reviewable: false });
    assert.equal(by["odd/name.ts"].pattern, "odd/[ab]] x", "the suffix runs to the final ]");
    assert.equal(by["odd/name.ts"].reason, "excluded_pattern");
  });

  it("omitted[].pattern prefers the structured excluded[].pattern over the stats suffix (review round 1, item 7)", async () => {
    const files = [patched("src/a.ts", "@@ -1 +1 @@\n+a"), patched("odd/x.ts", "@@ -1 +1 @@\n+x"), patched(".claude/y.sh", "@@ -1 +1 @@\n+y")];
    const sel = selectionDouble(["src/a.ts"], {
      "odd/x.ts": { stats: "+1 -0 (excluded by pattern) [pattern: odd/]", pattern: "odd/{x,y}.ts]\n" },
      ".claude/y.sh": { stats: "+1 -0 (Loa framework, content excluded)", pattern: ".claude/**" },
    }, []);
    const res = await run(provider(files), SEL, { truncate: sel.fn });
    const by = Object.fromEntries(res.coverage.omitted.map((o) => [o.file, o]));
    assert.equal(by["odd/x.ts"].pattern, "odd/{x,y}.ts]\n");
    assert.equal(by["odd/x.ts"].reason, "excluded_pattern");
    assert.equal(by[".claude/y.sh"].pattern, ".claude/**");
  });

  it("base_unavailable: the record degrades as reviewignore_unavailable and the merge is blocked (review round 1, item 6)", async () => {
    const sel = selectionDouble(["src/a.ts"], {}, [], { reviewignoreSource: "base_unavailable" });
    const res = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL, { truncate: sel.fn });
    assert.equal(res.coverage.reviewignore_source, "base_unavailable");
    assert.equal(res.coverage.degraded, true);
    assert.ok(res.coverage.degraded_reasons.includes("reviewignore_unavailable"), String(res.coverage.degraded_reasons));
    assert.equal(res.coverage.mergeBlockedReason, "incomplete_coverage");
    const clean = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL,
      { truncate: selectionDouble(["src/a.ts"], {}, [], { reviewignoreSource: "base" }).fn });
    assert.equal(clean.coverage.degraded, false);
  });

  it("integration with the real truncateFiles: protected_paths [] lets **/*.yml exclude the workflow; a custom list protects only its entries", async () => {
    const files = [patched("src/a.ts", "@@ -1 +1 @@\n+a"), patched(".github/workflows/ci.yml", "@@ -1 +1 @@\n+on: push"),
      patched(".husky/pre-commit", "@@ -1 +1 @@\n+npm test")];
    const off = await run(provider(files), { ...SEL, excludePatterns: ["**/*.yml"], protectedPaths: [] }, {});
    assert.deepEqual(off.coverage.protected_kept, []);
    assert.equal(off.coverage.omitted.find((o) => o.file === ".github/workflows/ci.yml")?.reason, "excluded_pattern");
    assert.ok(!off.files.some((f) => f.filename === ".github/workflows/ci.yml"));

    const custom = await run(provider(files), { ...SEL, excludePatterns: ["**/*.yml", "**/pre-commit"], protectedPaths: [".husky/**"] }, {});
    assert.deepEqual(custom.coverage.protected_kept, [{ file: ".husky/pre-commit", pattern: "**/pre-commit" }]);
    assert.ok(custom.files.some((f) => f.filename === ".husky/pre-commit"));
    assert.equal(custom.coverage.omitted.find((o) => o.file === ".github/workflows/ci.yml")?.reason, "excluded_pattern");
  });

  it("omitted[].pattern for config exclude_patterns without a suffix: the matching pattern, a non-wildcard one first", async () => {
    const files = [patched("src/a.ts", "@@ -1 +1 @@\n+a"), patched("docs/x.md", "@@ -1 +1 @@\n+x"), patched("docs/y.md", "@@ -1 +1 @@\n+y")];
    const res = await run(provider(files), { ...SEL, excludePatterns: ["docs/**", "docs/x.md"] }, {});
    const by = Object.fromEntries(res.coverage.omitted.map((o) => [o.file, o.pattern]));
    assert.deepEqual(by, { "docs/x.md": "docs/x.md", "docs/y.md": "docs/**" });
  });

  it("the selection receives the PR base sha; reviewignore_source comes from the base-ref read; changed_in_pr from the listing", async () => {
    const reads: Array<[unknown, unknown]> = [];
    const reviewignoreSource = (root: unknown, opts: unknown) => { reads.push([root, opts]); return "base" as const; };
    const sel = selectionDouble(["src/a.ts", ".reviewignore"], {}, []);
    const files = [patched("src/a.ts", "@@ -1 +1 @@\n+a"), patched(".reviewignore", "@@ -1 +1 @@\n+secrets/")];
    const res = await run(provider(files), { ...SEL, repoRoot: "/repo" }, { truncate: sel.fn, reviewignoreSource });
    assert.equal(res.coverage.reviewignore_source, "base");
    assert.equal(res.coverage.reviewignore_changed_in_pr, true);
    assert.deepEqual(reads, [["/repo", { baseSha: BASE }]]);
    assert.ok(sel.configs.length > 0 && sel.configs.every((c) => c.reviewignoreBaseSha === BASE), "truncateFiles is given the base sha");

    const plain = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL, { reviewignoreSource: () => "none" as const });
    assert.equal(plain.coverage.reviewignore_source, "none");
    assert.equal(plain.coverage.reviewignore_changed_in_pr, false);
  });

  it("the default selection is the real truncateFiles (no double): the record still carries the new fields", async () => {
    const res = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL, {});
    assert.equal(res.coverage.reviewignore_changed_in_pr, false);
    assert.ok(Array.isArray(res.coverage.protected_kept));
    assert.deepEqual(res.selection.included.map((f) => f.filename), truncateFiles([patched("src/a.ts", "x")], SEL).included.map((f) => f.filename));
  });

  // Lead wiring (Task 1.7, D-1.2a): with no injected seam, the provenance is what the selection result reports —
  // truncateFiles read `.reviewignore` once (from the base sha when the config carried `reviewignoreBaseSha`).
  it("the .reviewignore provenance comes from the selection result when no seam is injected", async () => {
    const configs: Array<Record<string, unknown>> = [];
    const truncate = (files: PullRequestFile[], config: Record<string, unknown>) => {
      configs.push(config);
      return { ...truncateFiles(files, config as unknown as typeof SEL), reviewignoreSource: "base" as const };
    };
    const res = await run(provider([patched("src/a.ts", "@@ -1 +1 @@\n+a")]), SEL, { truncate });
    assert.equal(res.coverage.reviewignore_source, "base");
    assert.equal(configs[0]?.reviewignoreBaseSha, BASE);
    const text = formatCoverageSection(res.coverage);
    assert.ok(text.includes(".reviewignore: base"), text);
  });
});

function record(over: Partial<CoverageRecord> = {}): CoverageRecord {
  return {
    base_sha: BASE, head_sha: HEAD, changed_files: 6, listed: 6,
    reviewed: [{ file: "src/a.ts", bytes: 10, hunks: 1 }, { file: "src/new.ts", bytes: 20, hunks: 1, source: "contents" }],
    omitted: [
      { file: ".claude/scripts/x.sh", reason: "excluded_loa", reviewable: false, pattern: ".claude/scripts/**" },
      { file: "vendor/lib.js", reason: "excluded_pattern", reviewable: false, pattern: "vendor/" },
      { file: "src/blob.ts", reason: "no_patch", reviewable: true, fetch: "too_large" },
      { file: ".github/workflows/ci.yml", reason: "byte_budget", reviewable: true },
    ],
    unknown_omitted: 0, degraded: true, degraded_reasons: ["incomplete_coverage"], mergeBlockedReason: "incomplete_coverage",
    restarts: 0,
    protected_kept: [{ file: ".github/workflows/ci.yml", pattern: "**/*.yml" }, { file: ".husky/pre-commit", pattern: ".husky/*" }],
    reviewignore_source: "base", reviewignore_changed_in_pr: true,
    ...over,
  };
}

describe("rendered coverage summary (§ 4)", () => {
  it("renders protected-kept files with their final status, the synthesized marker, patterns, fetch outcomes and provenance", () => {
    const text = formatCoverageSection(record());
    const lines = text.split("\n");
    assert.ok(lines.includes("Protected paths kept (2):"), text);
    assert.ok(lines.includes("- `.github/workflows/ci.yml` — kept despite `**/*.yml` then omitted (byte_budget)"), text);
    assert.ok(lines.includes("- `.husky/pre-commit` — kept despite `.husky/*`"), text);
    assert.ok(lines.includes("- `src/new.ts` (source: contents)"), text);
    assert.ok(!lines.some((l) => l.startsWith("- `src/a.ts`")), "a GitHub-patched reviewed file is not listed");
    assert.ok(lines.includes("- `.claude/scripts/x.sh` — excluded_loa · pattern `.claude/scripts/**`"), text);
    assert.ok(lines.includes("- `vendor/lib.js` — excluded_pattern · pattern `vendor/`"), text);
    assert.ok(lines.includes("- `src/blob.ts` — no_patch (reviewable) · fetch: too_large"), text);
    assert.ok(lines.includes(".reviewignore: base (changed in this PR)"), text);
  });

  it("renders base_unavailable as the checkout copy applied and the review degraded; budget and aborted outcomes", () => {
    const text = formatCoverageSection(record({
      reviewignore_source: "base_unavailable", reviewignore_changed_in_pr: false,
      omitted: [
        { file: "src/late.ts", reason: "no_patch", reviewable: true, fetch: "budget" },
        { file: "src/rest.ts", reason: "no_patch", reviewable: true, fetch: "aborted" },
      ],
    }));
    const lines = text.split("\n");
    assert.ok(lines.includes(".reviewignore: base_unavailable (checkout copy applied; review degraded)"), text);
    assert.ok(lines.includes("- `src/late.ts` — no_patch (reviewable) · fetch: budget"), text);
    assert.ok(lines.includes("- `src/rest.ts` — no_patch (reviewable) · fetch: aborted"), text);
  });

  it("omits the new sections when the record has nothing for them (older records stay renderable)", () => {
    const text = formatCoverageSection(record({ protected_kept: undefined, reviewignore_source: undefined, reviewignore_changed_in_pr: undefined,
      reviewed: [{ file: "src/a.ts", bytes: 10, hunks: 1 }] }));
    assert.ok(!/Protected paths kept/.test(text));
    assert.ok(!/source: contents/.test(text));
    assert.ok(!/^\.reviewignore:/m.test(text));
    const checkout = formatCoverageSection(record({ reviewignore_source: "checkout", reviewignore_changed_in_pr: false }));
    assert.ok(checkout.split("\n").includes(".reviewignore: checkout"), checkout);
  });

  it("every name and pattern goes through safePath: Markdown delimiters, HTML tags and newlines cannot break out", () => {
    const evil = "a`b\n- [x](javascript:alert(1)) <img src=x onerror=alert(1)> **bold** _i_\r.yml";
    const evilPattern = "**/*`<script>alert(1)</script>`\n- injected.yml";
    const text = formatCoverageSection(record({
      reviewed: [{ file: evil, bytes: 1, hunks: 1, source: "contents" }],
      omitted: [
        { file: evil, reason: "excluded_pattern", reviewable: false, pattern: evilPattern },
        { file: evil, reason: "no_patch", reviewable: true, fetch: "error" },
      ],
      protected_kept: [{ file: evil, pattern: evilPattern }],
    }));
    const body = text.slice(0, text.lastIndexOf("<!-- bridgebuilder-coverage:"));
    assert.ok(!/<img|<script|<\/script>/i.test(body), body);
    assert.ok(!/^- \[x\]/m.test(body), "a newline in a name cannot start a list item");
    assert.ok(!/^- injected/m.test(body), "a newline in a pattern cannot start a list item");
    for (const line of body.split("\n").filter((l) => l.startsWith("- "))) {
      assert.equal((line.match(/`/g) ?? []).length % 2, 0, `balanced code spans: ${line}`);
    }
    assert.equal((text.match(/<!--/g) ?? []).length, 1, "only the coverage marker opens a comment");
  });
});
