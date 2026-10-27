// cycle-136 Sprint 280 Task 1.2 (sdd.md § 5.2, § 7 C-2, FR-2, bd-9tt4b): the base `.reviewignore` is read through the
// contents API when the base commit is not in the clone (a shallow checkout). Every case drives the REAL two-pass fetch
// and the REAL truncateFiles selection through a provider double; the local read's class is forced through the
// `deps.readBaseReviewignore` seam. The checkout copy lives in a temp directory that is not a git repository, so
// truncateFiles' own fallback read (today's path) answers `base_unavailable` with the checkout patterns.
import { describe, it, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { fetchPRFilesTwoPass } from "../core/paged-fetch.js";
import { REVIEWIGNORE_MAX_BYTES, type BaseRead } from "../core/truncation.js";
import { GitProviderError } from "../ports/git-provider.js";
// cycle-136 C-3 (FR-3 (a)): the port types through the ports barrel, FileContentResult included
import type { FileContentResult, PullRequestFile, PullRequestRef } from "../ports/index.js";

const BASE = "b".repeat(40);
const BASE2 = "d".repeat(40);
const HEAD = "a".repeat(40);
const HEAD2 = "c".repeat(40);
const OWNER = "target-owner";
const REPO = "target-repo";

interface ContentCall { owner: string; repo: string; path: string; ref: string; maxBytes: number }
type Serve = FileContentResult | Error;

interface Fixture {
  files?: PullRequestFile[];
  /** `.reviewignore` at the base (an Error is thrown); default 404. */
  reviewignore?: (maxBytes: number) => Serve;
  /** The probe read of a listed file at the base (an Error is thrown); default text. */
  probe?: Serve;
  /** [base, head] served by the Nth (0-based) read of pulls/N; the last entry repeats. */
  refs?: Array<[string, string]>;
  noMethod?: boolean;
}

/** An error the way the adapter raises it (GhApiError: a GitProviderError carrying the parsed HTTP status). */
function httpError(code: ConstructorParameters<typeof GitProviderError>[0], httpStatus?: number, message = "gh command failed (code=1)") {
  return Object.assign(new GitProviderError(code, message), { httpStatus });
}
const NOT_FOUND = () => httpError("NETWORK", 404);

/** Text the way the adapter returns it: over the bound → too_large. */
function text(content: string) {
  return (maxBytes: number): Serve => {
    const bytes = Buffer.byteLength(content);
    return bytes > maxBytes ? { kind: "too_large" } : { kind: "text", content, bytes };
  };
}

const modified = (filename: string): PullRequestFile =>
  ({ filename, status: "modified", additions: 1, deletions: 0, patch: "@@ -1 +1 @@\n+x" });
const addedWithPatch = (filename: string): PullRequestFile =>
  ({ filename, status: "added", additions: 1, deletions: 0, patch: "@@ -0,0 +1 @@\n+x" });

/** src/a.ts (the probe target), secret/key.ts (the base pattern), vendor/x.ts (the checkout pattern). */
const FILES = [modified("src/a.ts"), modified("secret/key.ts"), modified("vendor/x.ts")];

function provider(fx: Fixture) {
  const contentCalls: ContentCall[] = [];
  let prReads = 0;
  const files = fx.files ?? FILES;
  const refs = fx.refs ?? [[BASE, HEAD]];
  const git = {
    async getPR(): Promise<PullRequestRef> {
      const [base_sha, head_sha] = refs[Math.min(prReads, refs.length - 1)];
      prReads++;
      return { base_sha, head_sha, changed_files: files.length };
    },
    async getPRFilesPage(_o: string, _r: string, _n: number, page: number): Promise<PullRequestFile[]> {
      return files.slice((page - 1) * 100, page * 100).map((f) => ({ ...f }));
    },
    ...(fx.noMethod ? {} : {
      async getFileContent(owner: string, repo: string, path: string, ref: string, maxBytes: number): Promise<FileContentResult> {
        contentCalls.push({ owner, repo, path, ref, maxBytes });
        const out = path === ".reviewignore"
          ? (fx.reviewignore ?? NOT_FOUND)(maxBytes)
          : fx.probe ?? { kind: "text", content: "", bytes: 0 };
        if (out instanceof Error) throw out;
        return out;
      },
    }),
  };
  return { git, contentCalls };
}

const UNKNOWN: BaseRead = { ok: false, why: "unknown_commit", detail: "the base commit is not in the clone" };

let root = "";
before(() => {
  root = mkdtempSync(join(tmpdir(), "loa-c136-ri-"));
  writeFileSync(join(root, ".reviewignore"), "vendor/**\n"); // the checkout (PR-head) copy
});
after(() => rmSync(root, { recursive: true, force: true }));

const sel = () => ({
  excludePatterns: [] as string[], maxDiffBytes: 512_000, maxFilesPerPr: 50, loaAware: true, selfReview: false, repoRoot: root,
});

async function captured<T>(fn: () => Promise<T>): Promise<{ value: T; err: string }> {
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
    return { value: await fn(), err };
  } finally {
    process.stderr.write = original;
  }
}

async function run(fx: Fixture, local: BaseRead | ((repoRoot: string, sha: string) => BaseRead) = UNKNOWN, config = {}) {
  const p = provider(fx);
  const reads: string[] = [];
  const readBaseReviewignore = (r: string, sha: string): BaseRead => {
    reads.push(sha);
    return typeof local === "function" ? local(r, sha) : local;
  };
  const { value: res, err } = await captured(() =>
    fetchPRFilesTwoPass(p.git, OWNER, REPO, 7, { ...sel(), ...config }, { readBaseReviewignore }));
  const infos = err.split("\n").filter((l) => l.startsWith("[bridgebuilder] INFO: .reviewignore at base"));
  const omittedNames = res.coverage.omitted.map((o) => o.file);
  return { res, calls: p.contentCalls, infos, err, reads, omittedNames };
}

function assertBaseUnavailable(r: Awaited<ReturnType<typeof run>>, label: string) {
  assert.equal(r.res.coverage.reviewignore_source, "base_unavailable", label);
  assert.ok(r.omittedNames.includes("vendor/x.ts"), `${label}: the checkout copy governs`);
  assert.ok(!r.omittedNames.includes("secret/key.ts"), label);
  assert.equal(r.res.coverage.degraded, true, label);
  assert.ok(r.res.coverage.degraded_reasons.includes("reviewignore_unavailable"), label);
  assert.equal(r.infos.length, 0, label);
}

// (review round 1: { concurrency: 1 } — the cases swap process.stderr.write, so they must never interleave)
describe("base .reviewignore through the contents API (cycle-136 C-2, bd-9tt4b)", { concurrency: 1 }, () => {
  it("unknown_commit + the API serves the file → base, the base patterns apply, not degraded, one call, one INFO line", async () => {
    const r = await run({ reviewignore: text("secret/**\n") });
    assert.equal(r.res.coverage.reviewignore_source, "base");
    assert.deepEqual(r.res.coverage.omitted.map((o) => [o.file, o.reason]), [["secret/key.ts", "excluded_pattern"]]);
    assert.ok(r.res.files.some((f) => f.filename === "vendor/x.ts"), "the checkout's (PR head's) copy is not applied");
    assert.equal(r.res.coverage.degraded, false);
    assert.deepEqual(r.calls, [{ owner: OWNER, repo: REPO, path: ".reviewignore", ref: BASE, maxBytes: REVIEWIGNORE_MAX_BYTES }],
      "exactly one call, for .reviewignore, at pin.base_sha, against the target owner/repo, bounded at 1 MiB");
    assert.equal(r.infos.length, 1, r.err);
    assert.ok(r.infos[0].includes(BASE) && r.infos[0].includes("contents API"), r.infos[0]);
  });

  for (const [label, probe] of [
    ["text", { kind: "text", content: "x", bytes: 1 }],
    ["too_large", { kind: "too_large" }],
    ["binary", { kind: "binary" }],
  ] as Array<[string, FileContentResult]>) {
    it(`404 + the access probe readable (${label}) → none, no patterns, not degraded, exactly two calls`, async () => {
      const r = await run({ probe });
      assert.equal(r.res.coverage.reviewignore_source, "none");
      assert.deepEqual(r.res.coverage.omitted, []);
      assert.equal(r.res.coverage.degraded, false);
      assert.deepEqual(r.calls.map((c) => [c.path, c.ref, c.maxBytes]), [[".reviewignore", BASE, REVIEWIGNORE_MAX_BYTES], ["src/a.ts", BASE, 1]],
        "the probe is the first modified/removed listed file, at the base sha, maxBytes 1");
      assert.ok(r.calls.every((c) => c.owner === OWNER && c.repo === REPO));
      assert.equal(r.infos.length, 0);
    });
  }

  it("404 + the probe answers 404 → base_unavailable (an authorization gap is not an absence)", async () => {
    const r = await run({ probe: NOT_FOUND() });
    assertBaseUnavailable(r, "probe 404");
    assert.equal(r.calls.length, 2);
  });

  it("404 + the probe throws any other error → base_unavailable", async () => {
    const r = await run({ probe: new TypeError("boom") });
    assertBaseUnavailable(r, "probe error");
    assert.equal(r.calls.length, 2);
  });

  it("404 + a listing with only added files (no base-existing probe target) → base_unavailable, one call", async () => {
    const r = await run({ files: [addedWithPatch("src/a.ts"), addedWithPatch("vendor/x.ts")] });
    assert.equal(r.res.coverage.reviewignore_source, "base_unavailable");
    assert.ok(r.omittedNames.includes("vendor/x.ts"));
    assert.ok(r.res.coverage.degraded_reasons.includes("reviewignore_unavailable"));
    assert.deepEqual(r.calls.map((c) => c.path), [".reviewignore"]);
  });

  it("404 + a removed file is a probe target", async () => {
    const removed: PullRequestFile = { filename: "old/gone.ts", status: "removed", additions: 0, deletions: 1, patch: "@@ -1 +0,0 @@\n-x" };
    const r = await run({ files: [addedWithPatch("src/a.ts"), removed] });
    assert.equal(r.res.coverage.reviewignore_source, "none");
    assert.deepEqual(r.calls.map((c) => c.path), [".reviewignore", "old/gone.ts"]);
  });

  for (const [label, serve] of [
    ["RATE_LIMITED", () => httpError("RATE_LIMITED", 429)],
    ["FORBIDDEN", () => httpError("FORBIDDEN", 403)],
    ["401", () => httpError("NETWORK", 401)],
    ["malformed envelope", () => httpError("NETWORK", undefined, "getFileContent: the contents response is not a file envelope")],
    ["too_large", () => ({ kind: "too_large" })],
    ["binary", () => ({ kind: "binary" })],
    ["size mismatch", () => httpError("NETWORK", undefined, "getFileContent: contents size disagrees with the decoded bytes")],
    ["a plain TypeError", () => new TypeError("cannot read properties of undefined")],
    ["timeout-shaped", () => httpError("NETWORK", undefined, "gh command failed (code=ETIMEDOUT)")],
  ] as Array<[string, (maxBytes: number) => Serve]>) {
    it(`${label} on the .reviewignore read → base_unavailable, checkout patterns, reviewignore_unavailable, one call`, async () => {
      const r = await run({ reviewignore: serve });
      assertBaseUnavailable(r, label);
      assert.deepEqual(r.calls.map((c) => c.path), [".reviewignore"], label);
    });
  }

  it("ok locally → the local patterns, zero API calls", async () => {
    const r = await run({ reviewignore: text("vendor/**\n") }, { ok: true, patterns: ["secret/**"] });
    assert.equal(r.res.coverage.reviewignore_source, "base");
    assert.deepEqual(r.omittedNames, ["secret/key.ts"]);
    assert.equal(r.res.coverage.degraded, false);
    assert.equal(r.calls.length, 0);
    assert.equal(r.infos.length, 0);
  });

  it("absent locally → none, zero API calls", async () => {
    const r = await run({}, { ok: false, why: "absent", detail: "absent at the base" });
    assert.equal(r.res.coverage.reviewignore_source, "none");
    assert.deepEqual(r.res.coverage.omitted, []);
    assert.equal(r.res.coverage.degraded, false);
    assert.equal(r.calls.length, 0);
  });

  it("other locally (symlink, oversize, git error) → base_unavailable, zero API calls", async () => {
    const r = await run({ reviewignore: text("secret/**\n") }, { ok: false, why: "other", detail: "not a regular file at the base (mode 120000)" });
    assertBaseUnavailable(r, "other");
    assert.equal(r.calls.length, 0);
  });

  it("a provider without getFileContent → today's behaviour (base_unavailable)", async () => {
    const r = await run({ noMethod: true });
    assertBaseUnavailable(r, "no getFileContent");
  });

  it("local mode (no 40-hex base sha) → no API call", async () => {
    const r = await run({ refs: [["", HEAD]], reviewignore: text("secret/**\n") });
    assert.equal(r.calls.length, 0);
    assert.equal(r.infos.length, 0);
  });

  it("a restarted attempt with the same base sha makes no second call and no second INFO line", async () => {
    // pulls/N reads of attempt 1: pin, page-1 recheck, pass-2 recheck, final recheck (the head moves there)
    const r = await run({ reviewignore: text("secret/**\n"), refs: [[BASE, HEAD], [BASE, HEAD], [BASE, HEAD], [BASE, HEAD2]] });
    assert.equal(r.res.coverage.restarts, 1);
    assert.equal(r.res.coverage.head_sha, HEAD2);
    assert.equal(r.res.coverage.reviewignore_source, "base");
    assert.equal(r.calls.length, 1);
    assert.equal(r.infos.length, 1);
    assert.deepEqual(r.reads, [BASE], "the local read is cached too");
  });

  it("a restarted attempt after a FAILED resolution makes no second call (the failure is cached)", async () => {
    const r = await run({ reviewignore: () => httpError("RATE_LIMITED", 429), refs: [[BASE, HEAD], [BASE, HEAD], [BASE, HEAD], [BASE, HEAD2]] });
    assert.equal(r.res.coverage.restarts, 1);
    assertBaseUnavailable(r, "cached failure");
    assert.equal(r.calls.length, 1);
  });

  it("a base move re-resolves: one new call at the new base", async () => {
    const r = await run({ reviewignore: text("secret/**\n"), refs: [[BASE, HEAD], [BASE, HEAD], [BASE, HEAD], [BASE2, HEAD2]] });
    assert.equal(r.res.coverage.restarts, 1);
    assert.equal(r.res.coverage.base_sha, BASE2);
    assert.deepEqual(r.calls.map((c) => c.ref), [BASE, BASE2]);
    assert.equal(r.infos.length, 2, "one INFO line per base-sha resolution");
  });

  it("content exactly at REVIEWIGNORE_MAX_BYTES is read; one byte over is too_large → base_unavailable", async () => {
    const head = "secret/**\n";
    const at = head + "#".repeat(REVIEWIGNORE_MAX_BYTES - head.length - 1) + "\n";
    assert.equal(Buffer.byteLength(at), REVIEWIGNORE_MAX_BYTES);
    const ok = await run({ reviewignore: text(at) });
    assert.equal(ok.res.coverage.reviewignore_source, "base");
    assert.deepEqual(ok.omittedNames, ["secret/key.ts"]);
    const over = await run({ reviewignore: text(at + "#") });
    assertBaseUnavailable(over, "one byte over");
  });

  it("an empty file at the base → base with zero patterns", async () => {
    const r = await run({ reviewignore: text("") });
    assert.equal(r.res.coverage.reviewignore_source, "base");
    assert.deepEqual(r.res.coverage.omitted, []);
    assert.equal(r.res.coverage.degraded, false);
  });

  it("max_content_fetches: 0 and fetch_missing_patches: false do not affect it", async () => {
    for (const config of [{ maxContentFetches: 0 }, { fetchMissingPatches: false }]) {
      const r = await run({ reviewignore: text("secret/**\n") }, UNKNOWN, config);
      assert.equal(r.res.coverage.reviewignore_source, "base", JSON.stringify(config));
      assert.equal(r.calls.length, 1, JSON.stringify(config));
    }
  });
});
