// cycle-135 Sprint 279 Task 1.3 (sdd.md C-3, § 5.3, FR-3, bd-w5pd9): the contents read for an added file GitHub
// returned without a patch. The REAL GitHubCLIAdapter runs against a stub `gh` executor; the allowlist is exercised
// directly. Q-1 (a2a/sprint-279/contract.md): the envelope is JSON, `encoding: "base64"`, `size` = decoded bytes, and
// `content` carries a newline every 60 characters; above 1 MiB GitHub answers `encoding: "none"` with empty content.
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import * as ghcli from "../adapters/github-cli.js";
import type { GhExec } from "../adapters/github-cli.js";
import { GitProviderError } from "../ports/git-provider.js";

const { GitHubCLIAdapter } = ghcli;
const HEAD = "a".repeat(40);

/** The contents envelope as GitHub sends it (base64 wrapped at 60 characters, trailing newline). */
function envelope(bytes: Buffer, overrides: Record<string, unknown> = {}): string {
  const b64 = bytes.toString("base64").replace(/.{60}/g, "$&\n") + "\n";
  return JSON.stringify({
    name: "x", path: "x", sha: "f".repeat(40), size: bytes.length, url: "u", html_url: "h", git_url: "g",
    download_url: "d", type: "file", content: b64, encoding: "base64", _links: {}, ...overrides,
  });
}

function stub(respond: (args: string[]) => string | Error) {
  const calls: Array<{ args: string[]; options: { timeout: number; maxBuffer: number } }> = [];
  const exec: GhExec = async (_file, args, options) => {
    calls.push({ args, options });
    const out = respond(args);
    if (out instanceof Error) throw out;
    if (Buffer.byteLength(out) > options.maxBuffer) {
      throw Object.assign(new RangeError("stdout maxBuffer length exceeded"), { code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER" });
    }
    return { stdout: out };
  };
  return { exec, calls, adapter: new GitHubCLIAdapter({ reviewMarker: "bridgebuilder-review", exec }) };
}

/** The adapter's optional method, called through an untyped view so the red phase fails per test, not at load. */
function getFileContent(a: unknown, ...args: [string, string, string, string, number]): Promise<unknown> {
  const fn = (a as { getFileContent?: (...x: unknown[]) => Promise<unknown> }).getFileContent;
  assert.equal(typeof fn, "function", "GitHubCLIAdapter.getFileContent is implemented");
  return fn!.apply(a, args);
}

/** The allowlist validator; its absence fails the test before any `assert.throws` (no vacuous red-phase pass). */
function validator(): (args: string[]) => void {
  const fn = (ghcli as unknown as { assertAllowedArgs?: (a: string[]) => void }).assertAllowedArgs;
  assert.equal(typeof fn, "function", "assertAllowedArgs is exported for the allowlist tests");
  return fn!;
}

describe("GitHubCLIAdapter.getFileContent (C-3, § 5.3)", () => {
  it("issues exactly `api /repos/<o>/<r>/contents/<encoded path>?ref=<sha>` with no header and the sized buffer", async () => {
    const text = Buffer.from("export const x = 1;\n");
    const s = stub(() => envelope(text));
    const res = await getFileContent(s.adapter, "o", "r", "src/a b/é.ts", HEAD, 1000);
    assert.deepEqual(res, { kind: "text", content: "export const x = 1;\n", bytes: text.length });
    assert.equal(s.calls.length, 1);
    assert.deepEqual(s.calls[0].args, ["api", `/repos/o/r/contents/src/a%20b/%C3%A9.ts?ref=${HEAD}`]);
    assert.equal(s.calls[0].options.maxBuffer, Math.ceil((1000 * 4) / 3) + 4096);
  });

  it("decodes base64 with the 60-character line breaks GitHub embeds (Q-1) and checks size against the bytes", async () => {
    const text = Buffer.from("line ".repeat(500));
    const res = await getFileContent(stub(() => envelope(text)).adapter, "o", "r", "a.txt", HEAD, 10_000);
    assert.deepEqual(res, { kind: "text", content: text.toString("utf8"), bytes: text.length });
  });

  it("a raw text file whose content looks like a contents envelope is returned as that text (decoded once)", async () => {
    const raw = JSON.stringify({ type: "file", encoding: "base64", size: 2, content: "aGk=" }) + "\n";
    const res = await getFileContent(stub(() => envelope(Buffer.from(raw))).adapter, "o", "r", "fixture.json", HEAD, 10_000);
    assert.deepEqual(res, { kind: "text", content: raw, bytes: Buffer.byteLength(raw) });
  });

  it("binary: a NUL byte in the first 8 KiB, or bytes that are not UTF-8", async () => {
    const nul = Buffer.concat([Buffer.from("PK"), Buffer.from([0]), Buffer.from("rest")]);
    assert.deepEqual(await getFileContent(stub(() => envelope(nul)).adapter, "o", "r", "a.bin", HEAD, 1000), { kind: "binary" });
    const latin1 = Buffer.from([0x63, 0x61, 0x66, 0xe9, 0x0a]);
    assert.deepEqual(await getFileContent(stub(() => envelope(latin1)).adapter, "o", "r", "a.txt", HEAD, 1000), { kind: "binary" });
  });

  it("too_large: `size` over the bound, `encoding: none` (GitHub's > 1 MiB answer), or a maxBuffer overflow", async () => {
    const text = Buffer.from("x".repeat(2000));
    assert.deepEqual(await getFileContent(stub(() => envelope(text)).adapter, "o", "r", "a.txt", HEAD, 1999), { kind: "too_large" });
    const none = JSON.stringify({ type: "file", encoding: "none", size: 2 * 1024 * 1024, content: "" });
    assert.deepEqual(await getFileContent(stub(() => none).adapter, "o", "r", "a.txt", HEAD, 1000), { kind: "too_large" });
    const overflow = Object.assign(new RangeError("stdout maxBuffer length exceeded"), { code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER" });
    assert.deepEqual(await getFileContent(stub(() => overflow).adapter, "o", "r", "a.txt", HEAD, 1000), { kind: "too_large" });
  });

  it("errors: a timeout, malformed base64, a size that disagrees with the bytes, and every malformed envelope", async () => {
    const bad: Array<[string, string | Error]> = [
      ["timeout", Object.assign(new Error("killed"), { killed: true, signal: "SIGTERM", code: null })],
      ["malformed base64", JSON.stringify({ type: "file", encoding: "base64", size: 3, content: "@@@@" })],
      ["size mismatch", envelope(Buffer.from("abc"), { size: 4 })],
      ["not JSON", "<html>"],
      ["an array (a directory)", JSON.stringify([{ type: "file" }])],
      ["type symlink", envelope(Buffer.from("abc"), { type: "symlink" })],
      ["encoding utf-8", envelope(Buffer.from("abc"), { encoding: "utf-8" })],
      ["size not an integer", envelope(Buffer.from("abc"), { size: 2.5 })],
      ["size negative", envelope(Buffer.from("abc"), { size: -1 })],
      ["content missing", JSON.stringify({ type: "file", encoding: "base64", size: 3 })],
    ];
    for (const [label, out] of bad) {
      await assert.rejects(getFileContent(stub(() => out).adapter, "o", "r", "a.txt", HEAD, 1000),
        (err: unknown) => err instanceof GitProviderError, label);
    }
  });

  it("refuses an invalid path, owner, repo or ref before any gh call", async () => {
    const paths = ["", "../x", "a/../b", "a/..", "a//b", "./a", "a/./b", "/a", "a/", "a?b", "a#b", "a\nb", "a\u0001b", "a\u007fb"];
    for (const p of paths) {
      const s = stub(() => envelope(Buffer.from("x")));
      await assert.rejects(getFileContent(s.adapter, "o", "r", p, HEAD, 1000), undefined, JSON.stringify(p));
      assert.equal(s.calls.length, 0, `no gh call for path ${JSON.stringify(p)}`);
    }
    const others: Array<[string, string, string]> = [
      ["-x", "r", HEAD], ["..", "r", HEAD], ["o", "a/b", HEAD], ["o w", "r", HEAD],
      ["o", "r", "abc123"], ["o", "r", "A".repeat(40)], ["o", "r", "g".repeat(40)], ["o", "r", HEAD + "0"],
    ];
    for (const [owner, repo, ref] of others) {
      const s = stub(() => envelope(Buffer.from("x")));
      await assert.rejects(getFileContent(s.adapter, owner, repo, "a.ts", ref, 1000), undefined, `${owner}/${repo}@${ref}`);
      assert.equal(s.calls.length, 0, `no gh call for ${owner}/${repo}@${ref}`);
    }
  });
});

describe("assertAllowedArgs: the contents shape (C-3, § 5.3)", () => {
  const ok = (path: string, tail = `?ref=${HEAD}`) => ["api", `/repos/o/r/contents/${path}${tail}`];

  it("accepts the exact shape, including per-segment percent-encoding of Unicode and spaces", () => {
    const allowed = validator();
    for (const p of ["README.md", "src/a.ts", "src/a%20b/%C3%A9.ts", ".github/workflows/ci.yml", "a-b_c.d/e~f"]) {
      assert.doesNotThrow(() => allowed(ok(p)), p);
    }
    assert.doesNotThrow(() => allowed(["api", `/repos/my-org.x/re_po.y/contents/a.ts?ref=${HEAD}`]));
  });

  it("rejects traversal, empty and dot segments, a leading slash, and encoded separators", () => {
    const allowed = validator();
    for (const p of ["..", "a/../b", "%2e%2e/x", "%2E%2E/x", "a/%2e%2e", ".", "a/./b", "%2e/x", "a//b", "/a", "a/",
      "a%2Fb", "a%2fb", ""]) {
      assert.throws(() => allowed(ok(p)), undefined, p);
    }
  });

  it("rejects `?`, `#` and control characters in the path (raw or encoded) and non-canonical encodings", () => {
    const allowed = validator();
    for (const p of ["a?b", "a#b", "a%3Fb", "a%23b", "a%0Ab", "a%00b", "a%7Fb", "a\nb", "a b", "%c3%a9.ts", "%41.ts", "a%zz"]) {
      assert.throws(() => allowed(ok(p)), undefined, p);
    }
  });

  it("rejects a foreign or extra query, a short, upper-case or non-hex ref", () => {
    const allowed = validator();
    for (const tail of ["", "?ref=", `?ref=${HEAD}&per_page=1`, `?foo=1`, `?ref=${HEAD}#x`, "?ref=abc1234",
      `?ref=${"A".repeat(40)}`, `?ref=${"g".repeat(40)}`, `?ref=${HEAD}0`, `?ref=main`]) {
      assert.throws(() => allowed(ok("a.ts", tail)), undefined, tail);
    }
  });

  it("rejects invalid owner/repo segments and option-like inputs", () => {
    const allowed = validator();
    for (const ep of [`/repos/../r/contents/a.ts?ref=${HEAD}`, `/repos/o/../contents/a.ts?ref=${HEAD}`,
      `/repos/-x/r/contents/a.ts?ref=${HEAD}`, `/repos/o/-x/contents/a.ts?ref=${HEAD}`, `/repos/o%20w/r/contents/a.ts?ref=${HEAD}`]) {
      assert.throws(() => allowed(["api", ep]), undefined, ep);
    }
    assert.throws(() => allowed(["api", `-x`]));
  });

  it("rejects any header or extra flag on the contents call", () => {
    const allowed = validator();
    for (const extra of [["-H", "Accept: application/vnd.github.raw"], ["--header", "Accept: x"], ["-H"], ["--paginate"],
      ["-X", "POST"], ["-f", "a=b"], ["-x"], ["--method=GET"], ["extra"]]) {
      assert.throws(() => allowed([...ok("a.ts"), ...extra]), undefined, extra.join(" "));
    }
  });

  it("leaves the existing shapes unchanged", () => {
    const allowed = validator();
    assert.doesNotThrow(() => allowed(["api", "/repos/o/r/pulls/7/files?per_page=100&page=2"]));
    assert.doesNotThrow(() => allowed(["api", "/repos/o/r/pulls?state=open&per_page=100", "--paginate"]));
    assert.throws(() => allowed(["api", "/repos/o/r/contents"]));
  });
});
