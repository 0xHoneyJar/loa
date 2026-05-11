// cycle-103 Sprint 1 T1.5 — end-to-end test that proves the TS delegate
// (T1.2) and the cheval --mock-fixture-dir flag (T1.5) work together as one
// pipeline. Spawns a real `python3 cheval.py` subprocess.
//
// Skipped when python3 is unavailable on PATH. CI runners (which have
// python3) get the full integration coverage; constrained dev environments
// fall through gracefully.

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { execSync, spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";

function pythonAvailable(): boolean {
  try {
    const out = spawnSync("python3", ["--version"], { stdio: "pipe" });
    return out.status === 0;
  } catch {
    return false;
  }
}

function repoRoot(): string {
  const out = execSync("git rev-parse --show-toplevel", { encoding: "utf8" });
  return out.trim();
}

describe("ChevalDelegateAdapter end-to-end with real cheval.py + --mock-fixture-dir", () => {
  if (!pythonAvailable()) {
    it("skipped — python3 not on PATH", () => {
      // No-op skip: keeps the suite green on environments without python3.
    });
    return;
  }

  const root = repoRoot();
  const chevalScript = resolve(root, ".claude/adapters/cheval.py");

  it("delegate → cheval --mock-fixture-dir → ReviewResponse round-trip", async () => {
    const fixtureDir = mkdtempSync(join(tmpdir(), "cheval-e2e-fixture-"));
    try {
      writeFileSync(
        join(fixtureDir, "response.json"),
        JSON.stringify({
          content: "## Summary\nE2E fixture content surfaced via the delegate.",
          usage: { input_tokens: 42, output_tokens: 13 },
        }),
        { encoding: "utf8" },
      );

      const adapter = new ChevalDelegateAdapter({
        model: "reviewer",
        agent: "flatline-reviewer",
        mockFixtureDir: fixtureDir,
        timeoutMs: 30_000,
        chevalScript,
      });

      const result = await adapter.generateReview({
        systemPrompt: "You are a code reviewer.",
        userPrompt: "Review this PR diff.",
        maxOutputTokens: 4_000,
      });

      assert.equal(result.content, "## Summary\nE2E fixture content surfaced via the delegate.");
      assert.equal(result.inputTokens, 42);
      assert.equal(result.outputTokens, 13);
      // Provider/model resolved from cheval's binding lookup; fixture didn't pin them.
      assert.ok(typeof result.provider === "string" && result.provider.length > 0);
      assert.ok(typeof result.model === "string" && result.model.length > 0);
    } finally {
      rmSync(fixtureDir, { recursive: true, force: true });
    }
  });

  it("missing fixture → typed INVALID_REQUEST error (exit 2)", async () => {
    const fixtureDir = mkdtempSync(join(tmpdir(), "cheval-e2e-empty-"));
    try {
      const adapter = new ChevalDelegateAdapter({
        model: "reviewer",
        agent: "flatline-reviewer",
        mockFixtureDir: fixtureDir,
        timeoutMs: 30_000,
        chevalScript,
      });

      await assert.rejects(
        adapter.generateReview({
          systemPrompt: "You are a code reviewer.",
          userPrompt: "x",
          maxOutputTokens: 1_000,
        }),
        (err: unknown) => {
          // LLMProviderError with INVALID_REQUEST per SDD §5.3 row for exit 2.
          const e = err as { name?: string; code?: string; message?: string };
          if (e.name !== "LLMProviderError") return false;
          if (e.code !== "INVALID_REQUEST") return false;
          if (!/no fixture found/i.test(e.message ?? "")) return false;
          return true;
        },
      );
    } finally {
      rmSync(fixtureDir, { recursive: true, force: true });
    }
  });
});
