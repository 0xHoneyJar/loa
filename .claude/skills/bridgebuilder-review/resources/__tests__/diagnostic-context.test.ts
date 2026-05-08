import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { formatDiagnosticDetail } from "../adapters/diagnostic-context.js";

/**
 * Issue #789 — TS adapter diagnostic-context preservation.
 * Mirrors the upstream PR #781 cheval ConnectionLostError pattern.
 */
describe("formatDiagnosticDetail", () => {
  describe("error name + message preservation", () => {
    it("includes error name", () => {
      const err = new TypeError("network-level failure");
      const detail = formatDiagnosticDetail(err, 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /TypeError:/);
    });

    it("includes error message", () => {
      const err = new TypeError("Premature stream close before final chunk");
      const detail = formatDiagnosticDetail(err, 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /Premature stream close before final chunk/);
    });

    it("preserves cause chain when present (Node.js fetch UND_ERR_*)", () => {
      const cause = new Error("UND_ERR_SOCKET");
      cause.name = "UND_ERR_SOCKET";
      const err = new TypeError("fetch failed");
      // @ts-expect-error — Node.js fetch wraps low-level errors in cause
      err.cause = cause;
      const detail = formatDiagnosticDetail(err, 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /TypeError: fetch failed/);
      assert.match(detail, /cause=UND_ERR_SOCKET: UND_ERR_SOCKET/);
    });

    it("handles error without cause", () => {
      const err = new TypeError("simple failure");
      const detail = formatDiagnosticDetail(err, 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /TypeError: simple failure/);
      assert.doesNotMatch(detail, /cause=/);
    });

    it("handles non-Error thrown values gracefully", () => {
      const detail = formatDiagnosticDetail("plain string", 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /string: plain string/);
    });

    it("handles undefined", () => {
      const detail = formatDiagnosticDetail(undefined, 1024, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /undefined: undefined/);
    });
  });

  describe("diagnostic context fields", () => {
    it("includes request_size_bytes", () => {
      const err = new Error("foo");
      const detail = formatDiagnosticDetail(err, 27531, 0, 3, "gemini-2.5-pro");
      assert.match(detail, /request_size=27531B/);
    });

    it("includes attempt count as 1-indexed humanized form", () => {
      const err = new Error("foo");
      const detail = formatDiagnosticDetail(err, 0, 1, 3, "gemini-2.5-pro");
      assert.match(detail, /attempt=2\/3/);
    });

    it("includes model identifier", () => {
      const err = new Error("foo");
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "claude-opus-4-7");
      assert.match(detail, /model=claude-opus-4-7/);
    });

    it("formats all three context fields together", () => {
      const err = new Error("foo");
      const detail = formatDiagnosticDetail(err, 100, 2, 3, "gpt-5.3-codex");
      assert.match(detail, /\(request_size=100B, attempt=3\/3, model=gpt-5.3-codex\)/);
    });
  });

  describe("sanitization (auth tokens / API keys MUST NOT leak)", () => {
    it("redacts ?key= URL query parameter (Google API auth pattern)", () => {
      const err = new Error("fetch to https://example.com/v1/models?key=AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx failed");
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "gemini-2.5-pro");
      assert.doesNotMatch(detail, /AIzaSy/);
      assert.match(detail, /\?key=<redacted>/);
    });

    it("redacts Bearer token", () => {
      const err = new Error("Authorization header rejected: Bearer sk-ant-api03-EXAMPLE-TOKEN");
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "claude-opus-4-7");
      assert.doesNotMatch(detail, /sk-ant-api03/);
      assert.match(detail, /Bearer <redacted>/);
    });

    it("redacts api-key= patterns", () => {
      const err = new Error("Request failed: api-key=secret-token-here");
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "claude-opus-4-7");
      assert.doesNotMatch(detail, /secret-token-here/);
      assert.match(detail, /api-key=<redacted>/);
    });

    it("redacts in cause chain too", () => {
      const cause = new Error("?key=AIzaSy_LEAKED_KEY_IN_CAUSE");
      const err = new Error("outer failure");
      // @ts-expect-error — Node.js fetch wraps low-level errors in cause
      err.cause = cause;
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "gemini-2.5-pro");
      assert.doesNotMatch(detail, /AIzaSy_LEAKED/);
      assert.match(detail, /\?key=<redacted>/);
    });

    it("caps message length at 1024 chars to prevent log explosion", () => {
      const huge = "a".repeat(50_000);
      const err = new Error(huge);
      const detail = formatDiagnosticDetail(err, 0, 0, 3, "gemini-2.5-pro");
      // Detail wraps the message; the message portion should be capped at 1024.
      // Total detail length is bounded.
      assert.ok(detail.length < 2_000, `detail too long: ${detail.length}`);
    });
  });

  describe("integration with LLMProviderError surfacing", () => {
    it("produces a string suitable for inclusion after a provider prefix", () => {
      const err = new TypeError("fetch failed");
      const detail = formatDiagnosticDetail(err, 27531, 0, 3, "gemini-2.5-pro");
      const errorMessage = `Google API network error — ${detail}`;
      // The full error message should be useful to operators.
      assert.match(errorMessage, /Google API network error/);
      assert.match(errorMessage, /TypeError: fetch failed/);
      assert.match(errorMessage, /request_size=27531B/);
      assert.match(errorMessage, /attempt=1\/3/);
      assert.match(errorMessage, /model=gemini-2.5-pro/);
    });
  });
});
