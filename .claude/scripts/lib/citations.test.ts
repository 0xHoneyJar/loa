import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { extractCitations, parseCitationKey } from "./citations";

const SAMPLE = `
# Title

Some text with [claim one](~/hivemind/wiki/concepts/foo.md:42).
Another [claim two](~/hivemind/wiki/concepts/bar.md:7).
And [claim three](~/bonfire/.claude/constructs/packs/observer/identity/KEEPER.md:100).
Non-citation [link](https://example.com).
No-tilde [link](./local/file.md:5).
`;

describe("extractCitations", () => {
  it("returns 3 citations from sample markdown", () => {
    const result = extractCitations(SAMPLE);
    assert.equal(result.size, 3);
  });

  it("deduplicates exact duplicate tokens", () => {
    const dup = "[a](~/foo.md:1) [b](~/foo.md:1)";
    const result = extractCitations(dup);
    assert.equal(result.size, 1);
  });

  it("returns empty Set when no citations present", () => {
    const result = extractCitations("# No citations here\n\nJust text.");
    assert.equal(result.size, 0);
  });

  it("correctly parses citation with line number 1", () => {
    const result = extractCitations("[x](~/path/file.md:1)");
    assert.ok(result.has("~/path/file.md:1"));
  });

  it("correctly parses citation with line number 999", () => {
    const result = extractCitations("[x](~/path/file.md:999)");
    assert.ok(result.has("~/path/file.md:999"));
  });

  it("ignores non-tilde links", () => {
    const result = extractCitations("[link](https://example.com) [local](./file.md:5)");
    assert.equal(result.size, 0);
  });
});

describe("parseCitationKey", () => {
  it("parses file path and line number", () => {
    const pair = parseCitationKey("~/hivemind/wiki/concepts/foo.md:42");
    assert.equal(pair.filePath, "~/hivemind/wiki/concepts/foo.md");
    assert.equal(pair.lineNumber, 42);
  });

  it("handles deep path with colons in directory names", () => {
    const pair = parseCitationKey("~/hivemind/wiki/concepts/memory-architecture-synthesis.md:127");
    assert.equal(pair.lineNumber, 127);
  });

  it("returns lineNumber as integer, not string", () => {
    const pair = parseCitationKey("~/foo.md:5");
    assert.strictEqual(typeof pair.lineNumber, "number");
  });
});
