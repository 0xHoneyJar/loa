// cycle-135 Sprint 279 Task 1.3 (sdd.md C-3, FR-3, D-1.3, D-1.3a, D-1.3b, bd-w5pd9): an added file GitHub listed
// without a patch is fetched by content in pass 1 and reviewed like any patched file. Every case drives the REAL
// two-pass fetch and the REAL truncateFiles selection through a provider double (listing → content → selection →
// pass 2 → coverage); one case runs the REAL GitHubCLIAdapter behind a stub `gh`.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { fetchPRFilesTwoPass } from "../core/paged-fetch.js";
import { GitHubCLIAdapter, type GhExec } from "../adapters/github-cli.js";
import { GitProviderError, type PullRequestFile, type PullRequestRef } from "../ports/git-provider.js";

const BASE = "b".repeat(40);
const HEAD = "a".repeat(40);
const HEAD2 = "c".repeat(40);

type Content = { kind: "text"; content: string; bytes: number } | { kind: "binary" } | { kind: "too_large" };
interface ContentCall { owner: string; repo: string; path: string; ref: string; maxBytes: number }

interface Fixture {
  files: PullRequestFile[];
  /** path → what the content read returns for a ref (an Error is thrown); default: not found. */
  serve?: (path: string, ref: string, maxBytes: number) => Content | Error;
  /** Head sha served by the Nth (0-based) read of pulls/N; the last entry repeats. */
  heads?: string[];
  /** The provider has no getFileContent (an older provider or test double). */
  noMethod?: boolean;
}

/** Text the way a provider returns it: over the bound → too_large (the adapter's size check). */
function text(content: string) {
  return (maxBytes: number): Content => {
    const bytes = Buffer.byteLength(content);
    return bytes > maxBytes ? { kind: "too_large" } : { kind: "text", content, bytes };
  };
}

function provider(fx: Fixture) {
  const contentCalls: ContentCall[] = [];
  let prReads = 0;
  const heads = fx.heads ?? [HEAD];
  const git = {
    async getPR(): Promise<PullRequestRef> {
      const head = heads[Math.min(prReads, heads.length - 1)];
      prReads++;
      return { base_sha: BASE, head_sha: head, changed_files: fx.files.length };
    },
    async getPRFilesPage(_o: string, _r: string, _n: number, page: number): Promise<PullRequestFile[]> {
      return fx.files.slice((page - 1) * 100, page * 100).map((f) => ({ ...f }));
    },
    ...(fx.noMethod ? {} : {
      async getFileContent(owner: string, repo: string, path: string, ref: string, maxBytes: number): Promise<Content> {
        contentCalls.push({ owner, repo, path, ref, maxBytes });
        const out = fx.serve ? fx.serve(path, ref, maxBytes) : new GitProviderError("NOT_FOUND", "no fixture");
        if (out instanceof Error) throw out;
        return out;
      },
    }),
  };
  return { git, contentCalls };
}

const SEL = { excludePatterns: [] as string[], maxDiffBytes: 512_000, maxFilesPerPr: 50, loaAware: false, selfReview: false };

const added = (filename: string, additions = 3): PullRequestFile => ({ filename, status: "added", additions, deletions: 0 });
const patched = (filename: string, patch: string, additions = 1): PullRequestFile =>
  ({ filename, status: "modified", additions, deletions: 0, patch });

describe("content fetch for patch-less added files (C-3)", () => {
  it("end to end: the added file is reviewed with the synthesized patch, source contents, and the coverage is not degraded", async () => {
    const p = provider({
      files: [patched("src/a.ts", "@@ -1 +1 @@\n+a"), added("src/new.ts")],
      serve: (path, _ref, max) => (path === "src/new.ts" ? text("one\ntwo\nthree\n")(max) : new Error("unexpected")),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
    const synth = "@@ -0,0 +1,3 @@\n+one\n+two\n+three";
    assert.deepEqual(res.files.find((f) => f.filename === "src/new.ts")?.patch, synth);
    assert.deepEqual(res.coverage.reviewed.find((r) => r.file === "src/new.ts"),
      { file: "src/new.ts", bytes: Buffer.byteLength(synth), hunks: 1, source: "contents" });
    assert.equal(res.coverage.reviewed.find((r) => r.file === "src/a.ts")?.source, undefined, "a GitHub patch carries no source");
    assert.deepEqual(res.coverage.omitted, []);
    assert.equal(res.coverage.degraded, false);
    assert.deepEqual(p.contentCalls, [{ owner: "o", repo: "r", path: "src/new.ts", ref: HEAD, maxBytes: 512_000 }],
      "the ref is the listing's head sha; the bound is the remaining aggregate budget");
    assert.ok(res.selection.included.some((f) => f.filename === "src/new.ts"));
  });

  it("binary, too_large and a provider error leave the file no_patch (reviewable) with the fetch outcome", async () => {
    const outcomes: Array<[string, Content | Error, string]> = [
      ["binary", { kind: "binary" }, "binary"],
      ["too_large", { kind: "too_large" }, "too_large"],
      ["provider error", new GitProviderError("NETWORK", "gh command failed"), "error"],
      ["malformed envelope (adapter throws)", new GitProviderError("NETWORK", "malformed contents envelope"), "error"],
      ["any thrown error", new Error("allowlist refusal"), "error"],
    ];
    for (const [label, out, fetch] of outcomes) {
      const p = provider({ files: [added("src/new.ts")], serve: () => out });
      const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
      assert.deepEqual(res.coverage.omitted, [{ file: "src/new.ts", reason: "no_patch", reviewable: true, fetch }], label);
      assert.deepEqual(res.files, [], label);
      assert.equal(res.coverage.degraded, true, `${label}: a reviewable no_patch still degrades, exactly as today`);
      assert.equal(p.contentCalls.length, 1, label);
    }
  });

  it("an excluded patch-less file is never fetched (counting double)", async () => {
    const p = provider({
      files: [added("generated/big.ts"), added("src/keep.ts")],
      serve: (_p, _r, max) => text("x\n")(max),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, excludePatterns: ["generated/**"] });
    assert.deepEqual(p.contentCalls.map((c) => c.path), ["src/keep.ts"]);
    const ex = res.coverage.omitted.find((o) => o.file === "generated/big.ts");
    assert.equal(ex?.reason, "excluded_pattern");
    assert.equal(ex?.fetch, undefined);
  });

  it("a file beyond max_files_per_pr is not fetched (it is a file_cap omission either way)", async () => {
    const p = provider({ files: [added("src/big.ts", 50), added("src/small.ts", 2)], serve: (_p, _r, max) => text("x\n")(max) });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxFilesPerPr: 1 });
    assert.deepEqual(p.contentCalls.map((c) => c.path), ["src/big.ts"]);
    assert.equal(res.coverage.omitted.find((o) => o.file === "src/small.ts")?.reason, "file_cap");
  });

  it("max_content_fetches: the files beyond the cap are skipped_cap, in listing order", async () => {
    const files = [added("src/a.ts"), added("src/b.ts"), added("src/c.ts")];
    const p = provider({ files, serve: (_p, _r, max) => text("x\n")(max) });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxContentFetches: 2 } as typeof SEL);
    assert.deepEqual(p.contentCalls.map((c) => c.path), ["src/a.ts", "src/b.ts"]);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/c.ts", reason: "no_patch", reviewable: true, fetch: "skipped_cap" }]);
    assert.deepEqual(res.coverage.reviewed.map((r) => [r.file, r.source]), [["src/a.ts", "contents"], ["src/b.ts", "contents"]]);

    const zero = provider({ files, serve: (_p, _r, max) => text("x\n")(max) });
    const none = await fetchPRFilesTwoPass(zero.git, "o", "r", 7, { ...SEL, maxContentFetches: 0 } as typeof SEL);
    assert.equal(zero.contentCalls.length, 0);
    assert.deepEqual(none.coverage.omitted.map((o) => o.fetch), ["skipped_cap", "skipped_cap", "skipped_cap"]);
  });

  it("the 120 s deadline (injected clock) stops further fetches: the rest are deadline", async () => {
    const files = [added("src/a.ts"), added("src/b.ts"), added("src/c.ts")];
    const p = provider({ files, serve: (_p, _r, max) => text("x\n")(max) });
    const times = [1_000, 60_000, 121_000];
    let i = 0;
    const now = () => times[Math.min(i++, times.length - 1)];
    const res = await (fetchPRFilesTwoPass as (...a: unknown[]) => ReturnType<typeof fetchPRFilesTwoPass>)(
      p.git, "o", "r", 7, SEL, { now });
    assert.deepEqual(p.contentCalls.map((c) => c.path), ["src/a.ts", "src/b.ts"]);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/c.ts", reason: "no_patch", reviewable: true, fetch: "deadline" }]);
  });

  it("several patch-less files compete for the aggregate max_diff_bytes budget, header and `+` prefixes counted", async () => {
    // "aaaaaaaaa\n" × 3 = 30 content bytes → "@@ -0,0 +1,3 @@\n" (16) + "+aaaaaaaaa" × 3 joined (32) = 48 patch bytes
    const content = "aaaaaaaaa\n".repeat(3);
    const synthBytes = 16 + 32;
    const files = [added("src/a.ts"), added("src/b.ts"), added("src/c.ts")];
    const p = provider({ files, serve: (_p, _r, max) => text(content)(max) });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxDiffBytes: 100 });
    // review round 1: the third has 4 bytes left, below the smallest patch its 3 additions can make → budget, no read
    assert.deepEqual(p.contentCalls.map((c) => c.maxBytes), [100, 100 - synthBytes]);
    assert.deepEqual(res.coverage.reviewed.map((r) => [r.file, r.bytes]), [["src/a.ts", synthBytes], ["src/b.ts", synthBytes]]);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/c.ts", reason: "no_patch", reviewable: true, fetch: "budget" }]);
    assert.ok(res.coverage.reviewed.reduce((n, r) => n + r.bytes, 0) <= 100);
  });

  it("content that fits the bound but whose synthesized patch does not is budget, never truncated", async () => {
    // 40 content bytes in 4 lines → 16 + 4 + 39 = 59 patch bytes > 50
    const p = provider({ files: [added("src/a.ts")], serve: (_p, _r, max) => text("aaaaaaaaa\n".repeat(4))(max) });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxDiffBytes: 50 });
    assert.deepEqual(res.coverage.omitted, [{ file: "src/a.ts", reason: "no_patch", reviewable: true, fetch: "budget" }]);
    assert.equal(p.contentCalls.length, 1, "the read succeeded; its patch did not fit what was left");
    assert.deepEqual(res.files, []);
  });

  it("GitHub patches selected ahead consume the budget first: no read is issued and the outcome is budget", async () => {
    // the ordinary patch (larger change, selected first) leaves 10 bytes; the 48-byte synthesized patch is not cut
    const big = "@@ -1 +1 @@\n" + "+x".repeat(44);
    const p = provider({
      files: [patched("src/big.ts", big, 90), added("src/new.ts")],
      serve: (_p, _r, max) => text("aaaaaaaaa\n".repeat(3))(max),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxDiffBytes: Buffer.byteLength(big) + 10 });
    assert.deepEqual(res.files.map((f) => f.filename), ["src/big.ts"]);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/new.ts", reason: "no_patch", reviewable: true, fetch: "budget" }]);
    assert.equal(p.contentCalls.length, 0, "no wasted read for a patch that could never be kept");
  });

  it("only GitHub patches AHEAD in selection order are charged: a larger added file ahead of a patch is read in full", async () => {
    const big = "@@ -1 +1 @@\n" + "+x".repeat(44); // 100 bytes, the smaller change → selected after the added file
    const p = provider({
      files: [patched("src/big.ts", big, 1), added("src/new.ts", 3)],
      serve: (_p, _r, max) => text("aaaaaaaaa\n".repeat(3))(max),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxDiffBytes: 110 });
    assert.deepEqual(p.contentCalls.map((c) => c.maxBytes), [110]);
    assert.deepEqual(res.coverage.reviewed.map((r) => [r.file, r.source]), [["src/new.ts", "contents"], ["src/big.ts", undefined]]);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/big.ts", reason: "patch_truncated", reviewable: true }]);
  });

  it("RATE_LIMITED / FORBIDDEN / HTTP 401·403 stop the loop: error for the file, aborted for the rest, one call", async () => {
    const stoppers: Array<[string, Error]> = [
      ["RATE_LIMITED", new GitProviderError("RATE_LIMITED", "rate limit")],
      ["FORBIDDEN", new GitProviderError("FORBIDDEN", "gh exit 4")],
      ["HTTP 403", Object.assign(new GitProviderError("NETWORK", "gh command failed (code=1)"), { httpStatus: 403 })],
      ["HTTP 401", Object.assign(new GitProviderError("NETWORK", "gh command failed (code=1)"), { httpStatus: 401 })],
    ];
    for (const [label, err] of stoppers) {
      const p = provider({ files: [added("src/a.ts"), added("src/b.ts"), added("src/c.ts")], serve: () => err });
      const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
      assert.equal(p.contentCalls.length, 1, label);
      assert.deepEqual(res.coverage.omitted.map((o) => [o.file, o.fetch]),
        [["src/a.ts", "error"], ["src/b.ts", "aborted"], ["src/c.ts", "aborted"]], label);
    }
    // a per-file failure (a path that moved: 404; a malformed envelope) does not stop the loop
    for (const err of [Object.assign(new GitProviderError("NETWORK", "x"), { httpStatus: 404 }), new GitProviderError("NETWORK", "malformed")]) {
      const p = provider({ files: [added("src/a.ts"), added("src/b.ts")], serve: () => err });
      const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
      assert.equal(p.contentCalls.length, 2);
      assert.deepEqual(res.coverage.omitted.map((o) => o.fetch), ["error", "error"]);
    }
  });

  it("the restart path (head moved at the post-pass-1 re-check) discards the synthesized patches and refetches at the new head", async () => {
    // reads: pin, before page 1, pass-2 re-check (moved) → restart at HEAD2
    const p = provider({
      files: [patched("src/a.ts", "@@ -1 +1 @@\n+a"), added("src/new.ts")],
      heads: [HEAD, HEAD, HEAD2],
      serve: (_p, ref, max) => text(ref === HEAD ? "old\n" : "new\n")(max),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
    assert.equal(res.coverage.restarts, 1);
    assert.equal(res.coverage.head_sha, HEAD2);
    assert.deepEqual(p.contentCalls.map((c) => c.ref), [HEAD, HEAD2], "each attempt asks for its own pinned head");
    assert.equal(res.files.find((f) => f.filename === "src/new.ts")?.patch, "@@ -0,0 +1,1 @@\n+new");
  });

  it("fetch_missing_patches: false → no provider call, no_patch as today (no fetch outcome)", async () => {
    const p = provider({ files: [added("src/new.ts")], serve: (_p, _r, max) => text("x\n")(max) });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, fetchMissingPatches: false } as typeof SEL);
    assert.equal(p.contentCalls.length, 0);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/new.ts", reason: "no_patch", reviewable: true }]);
  });

  it("a provider without getFileContent → no fetch, today's behaviour", async () => {
    const p = provider({ files: [added("src/new.ts")], noMethod: true });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
    assert.deepEqual(res.coverage.omitted, [{ file: "src/new.ts", reason: "no_patch", reviewable: true }]);
  });

  it("modified, renamed and zero-addition added files without a patch are never fetched (no_patch / renamed pinned)", async () => {
    const p = provider({
      files: [
        { filename: "src/mod.ts", status: "modified", additions: 9000, deletions: 0 },
        { filename: "src/moved.ts", status: "renamed", additions: 4, deletions: 1 },
        { filename: "assets/logo.png", status: "added", additions: 0, deletions: 0 },
      ],
      serve: (_p, _r, max) => text("x\n")(max),
    });
    const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
    assert.equal(p.contentCalls.length, 0);
    assert.deepEqual(res.coverage.omitted, [
      { file: "assets/logo.png", reason: "no_patch", reviewable: false },
      { file: "src/mod.ts", reason: "no_patch", reviewable: true },
      { file: "src/moved.ts", reason: "no_patch", reviewable: true },
    ]);
  });

  it("synthesized-patch matrix: final newline, CRLF, multibyte UTF-8, diff-marker content", async () => {
    const cases: Array<[string, string, number]> = [
      ["a\nb", "@@ -0,0 +1,2 @@\n+a\n+b\n\\ No newline at end of file", 1],
      ["a\r\nb\r\n", "@@ -0,0 +1,2 @@\n+a\r\n+b\r", 1],
      ["only\r\n", "@@ -0,0 +1,1 @@\n+only\r", 1],
      ["héllo ✓ 𝄞\nñ\n", "@@ -0,0 +1,2 @@\n+héllo ✓ 𝄞\n+ñ", 1],
      ["+++ b/x\n--- a/x\n@@ -1 +1 @@\n-old\n", "@@ -0,0 +1,4 @@\n++++ b/x\n+--- a/x\n+@@ -1 +1 @@\n+-old", 1],
      ["\n\n", "@@ -0,0 +1,2 @@\n+\n+", 1],
    ];
    for (const [content, patch, hunks] of cases) {
      const p = provider({ files: [added("src/f.ts")], serve: (_p, _r, max) => text(content)(max) });
      const res = await fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL);
      assert.equal(res.files[0]?.patch, patch, JSON.stringify(content));
      assert.deepEqual(res.coverage.reviewed, [{ file: "src/f.ts", bytes: Buffer.byteLength(patch), hunks, source: "contents" }],
        JSON.stringify(content));
    }
  });

  it("through the real adapter: the base64 envelope (60-char lines) becomes a reviewed file; an envelope-shaped text file is text", async () => {
    const raw = JSON.stringify({ type: "file", encoding: "base64", size: 2, content: "aGk=" }) + "\n";
    const b64 = Buffer.from(raw).toString("base64").replace(/.{60}/g, "$&\n") + "\n";
    const calls: string[][] = [];
    const exec: GhExec = async (_f, args) => {
      calls.push(args);
      const ep = args[1];
      if (ep === "/repos/o/r/pulls/7") return { stdout: JSON.stringify({ base: { sha: BASE }, head: { sha: HEAD }, changed_files: 1 }) };
      if (ep === "/repos/o/r/pulls/7/files?per_page=100&page=1") {
        return { stdout: JSON.stringify([{ filename: "fixtures/env.json", status: "added", additions: 1, deletions: 0 }]) };
      }
      if (ep === `/repos/o/r/contents/fixtures/env.json?ref=${HEAD}`) {
        return { stdout: JSON.stringify({ type: "file", encoding: "base64", size: Buffer.byteLength(raw), content: b64 }) };
      }
      throw new Error(`unexpected gh call: ${args.join(" ")}`);
    };
    const git = new GitHubCLIAdapter({ reviewMarker: "bridgebuilder-review", exec });
    const res = await fetchPRFilesTwoPass(git, "o", "r", 7, SEL);
    assert.equal(res.files[0]?.patch, "@@ -0,0 +1,1 @@\n+" + raw.slice(0, -1));
    assert.equal(res.coverage.reviewed[0]?.source, "contents");
    assert.equal(res.coverage.degraded, false);
    assert.ok(calls.some((a) => a.length === 2 && a[1].startsWith("/repos/o/r/contents/")), "the contents call carries no flags");
  });
});

// cycle-136 C-3 (FR-3 (c), sdd.md § 4, bd-gyrgq): a failed content read is no longer silent — one bounded WARN per file
// per attempt for the outcomes error / too_large / binary (budget, skipped_cap, deadline and aborted are not failed reads).
// (review round 1: { concurrency: 1 } — the cases swap process.stderr.write, so they must never interleave)
describe("failed content read WARN (cycle-136 C-3, bd-gyrgq)", { concurrency: 1 }, () => {
  async function captured<T>(fn: () => Promise<T>): Promise<{ value: T; warns: string[]; err: string }> {
    const original = process.stderr.write;
    let err = "";
    // (review round 1: the stand-in keeps write()'s contract — an `encoding` or callback argument is honoured)
    (process.stderr as unknown as { write: (c: unknown, e?: unknown, cb?: unknown) => boolean }).write = (c, e, cb) => {
      err += String(c);
      const done = typeof e === "function" ? e : cb;
      if (typeof done === "function") process.nextTick(done as () => void);
      return true;
    };
    try {
      const value = await fn();
      return { value, err, warns: err.split("\n").filter((l) => l.startsWith("[bridgebuilder] WARN: content read of ")) };
    } finally {
      process.stderr.write = original;
    }
  }

  for (const [label, out, outcome] of [
    ["binary", { kind: "binary" }, "binary"],
    ["too_large", { kind: "too_large" }, "too_large"],
    ["provider error", new GitProviderError("NETWORK", "gh command failed"), "error"],
    ["any thrown error", new Error("allowlist refusal {\"message\":\"raw body\"}"), "error"],
  ] as Array<[string, Content | Error, string]>) {
    it(`${label}: exactly one WARN naming the file and the outcome, never the error text`, async () => {
      const p = provider({ files: [added("src/new.ts"), patched("src/a.ts", "@@ -1 +1 @@\n+a")], serve: () => out });
      const { warns, err } = await captured(() => fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL));
      assert.deepEqual(warns, [`[bridgebuilder] WARN: content read of "src/new.ts" failed: ${outcome} (no_patch)`], err);
      assert.ok(!err.includes("raw body") && !err.includes("gh command failed"), err);
    });
  }

  it("a filename with a newline is escaped (one line); a long one is bounded to 200 characters", async () => {
    const long = "src/" + "x".repeat(400) + ".ts";
    const p = provider({ files: [added("src/a\nb.ts"), added(long)], serve: () => ({ kind: "binary" }) });
    const { warns, err } = await captured(() => fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL));
    assert.equal(warns.length, 2, err);
    assert.equal(warns[0], `[bridgebuilder] WARN: content read of "src/a\\nb.ts" failed: binary (no_patch)`);
    const shown = warns[1].slice("[bridgebuilder] WARN: content read of ".length, warns[1].indexOf(" failed: "));
    assert.ok(shown.length <= 200 && shown.startsWith("\"src/xxx"), shown);
    assert.equal(err.split("\n").filter((l) => l.includes("WARN: content read")).length, 2, "nothing spills onto a second line");
  });

  it("budget, skipped_cap and aborted outcomes write no WARN", async () => {
    const p = provider({ files: [added("src/one.ts"), added("src/two.ts")], serve: (_p, _r, max) => text("x\n")(max) });
    const capped = await captured(() => fetchPRFilesTwoPass(p.git, "o", "r", 7, { ...SEL, maxContentFetches: 0 }));
    assert.deepEqual(capped.warns, []);
    const tight = await captured(() => fetchPRFilesTwoPass(provider({ files: [added("src/big.ts", 500)] }).git, "o", "r", 7, { ...SEL, maxDiffBytes: 10 }));
    assert.deepEqual(tight.warns, []);
    const stop = provider({ files: [added("src/one.ts"), added("src/two.ts")], serve: () => new GitProviderError("RATE_LIMITED", "rate limited") });
    const aborted = await captured(() => fetchPRFilesTwoPass(stop.git, "o", "r", 7, SEL));
    assert.deepEqual(aborted.warns, [`[bridgebuilder] WARN: content read of "src/one.ts" failed: error (no_patch)`], "the aborted rest stay silent");
  });

  // review round 1 (MEDIUM): `deadline` is not a failed read either (the injected-clock harness of the deadline case above)
  it("deadline outcomes write no WARN", async () => {
    const files = [added("src/a.ts"), added("src/b.ts"), added("src/c.ts")];
    const p = provider({ files, serve: (_p, _r, max) => text("x\n")(max) });
    const times = [1_000, 60_000, 121_000];
    let i = 0;
    const now = () => times[Math.min(i++, times.length - 1)];
    const { value: res, warns } = await captured(() =>
      (fetchPRFilesTwoPass as (...a: unknown[]) => ReturnType<typeof fetchPRFilesTwoPass>)(p.git, "o", "r", 7, SEL, { now }));
    assert.deepEqual(res.coverage.omitted, [{ file: "src/c.ts", reason: "no_patch", reviewable: true, fetch: "deadline" }]);
    assert.deepEqual(warns, []);
  });

  // review round 1 (MEDIUM; B's judgment call 9): an empty `text` answer for a file listed with additions > 0 is the
  // outcome `error` — a failed read, so it WARNs like any other
  it("an empty text answer with additions > 0 is error and writes one WARN", async () => {
    const p = provider({ files: [added("src/empty.ts", 3)], serve: () => ({ kind: "text", content: "", bytes: 0 }) });
    const { value: res, warns } = await captured(() => fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL));
    assert.deepEqual(res.coverage.omitted, [{ file: "src/empty.ts", reason: "no_patch", reviewable: true, fetch: "error" }]);
    assert.deepEqual(warns, [`[bridgebuilder] WARN: content read of "src/empty.ts" failed: error (no_patch)`]);
    assert.equal(p.contentCalls.length, 1);
  });

  it("a restarted attempt writes the WARN again (once per file per attempt)", async () => {
    const p = provider({ files: [added("src/new.ts")], serve: () => ({ kind: "binary" }), heads: [HEAD, HEAD, HEAD2] });
    // (pulls/N reads: pin, page-1 recheck, final recheck — no pass-2 page, the file has no patch — then the restart)
    const { value, warns } = await captured(() => fetchPRFilesTwoPass(p.git, "o", "r", 7, SEL));
    assert.equal(value.coverage.restarts, 1);
    assert.equal(warns.length, 2);
  });
});
