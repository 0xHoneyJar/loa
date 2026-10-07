import { describe, it, mock } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { MultiModelConfigSchema, validateApiKeys, readAgyGate, isAgyRouted, loaConfigPathFor } from "../config.js";
import { GENERATED_MODEL_REGISTRY } from "../config.generated.js";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";

// cycle-127 FR-1: the agy (Antigravity) route — the gemini-headless hop — is opt-in (hounfour.headless.agy_opt_in, default
// false). A google voice whose route is agy (the gemini-headless model id, or any google model under headless mode cli-only)
// is NOT PLANNED with the opt-in off: never registered, never dispatched, and verdict quality counts the planned voices only.

function withConfig(body: string | null, fn: (path: string, root: string) => void | Promise<void>) {
  const root = mkdtempSync(join(tmpdir(), "bb-agy-gate-"));
  const path = join(root, ".loa.config.yaml");
  if (body !== null) writeFileSync(path, body);
  return Promise.resolve(fn(path, root)).finally(() => rmSync(root, { recursive: true, force: true }));
}

describe("readAgyGate", () => {
  for (const [label, body, optIn, mode] of [
    ["no config file", null, false, "prefer-api"],
    ["absent key", "hounfour:\n  headless:\n    mode: cli-only\n", false, "cli-only"],
    ["false", "hounfour:\n  headless:\n    agy_opt_in: false\n", false, "prefer-api"],
    ["a string", "hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", false, "prefer-api"],
    ["true", "hounfour:\n  headless:\n    agy_opt_in: true\n    mode: prefer-cli\n", true, "prefer-cli"],
  ] as const) {
    it(`reads ${label}`, async () => {
      const saved = process.env.LOA_HEADLESS_MODE;
      delete process.env.LOA_HEADLESS_MODE;
      try {
        await withConfig(body, (path) => {
          const g = readAgyGate(path);
          assert.deepEqual({ optIn: g.optIn, mode: g.mode }, { optIn, mode });
          assert.equal(g.readError, undefined, "a readable config (or none) is not a read error");
        });
      } finally {
        if (saved !== undefined) process.env.LOA_HEADLESS_MODE = saved;
      }
    });
  }

  it("LOA_HEADLESS_MODE wins for the mode, as in cheval; nothing in the environment opts in", async () => {
    const saved = process.env.LOA_HEADLESS_MODE;
    process.env.LOA_HEADLESS_MODE = "cli-only";
    process.env.LOA_AGY_OPT_IN = "true";
    try {
      await withConfig("hounfour:\n  headless:\n    mode: prefer-api\n", (path) =>
        assert.deepEqual(readAgyGate(path), { optIn: false, mode: "cli-only" }));
    } finally {
      if (saved === undefined) delete process.env.LOA_HEADLESS_MODE; else process.env.LOA_HEADLESS_MODE = saved;
      delete process.env.LOA_AGY_OPT_IN;
    }
  });
});

describe("isAgyRouted", () => {
  it("the gemini-headless id is agy on any mode; a google model is agy under cli-only only; other providers never", () => {
    assert.equal(isAgyRouted("google", "gemini-headless", "prefer-api"), true);
    assert.equal(isAgyRouted("google", "gemini-3.1-pro-preview", "cli-only"), true);
    assert.equal(isAgyRouted("google", "gemini-3.1-pro-preview", "prefer-api"), false);
    assert.equal(isAgyRouted("google", "gemini-3.1-pro-preview", "prefer-cli"), false);
    assert.equal(isAgyRouted("anthropic", "claude-headless", "cli-only"), false);
    assert.equal(isAgyRouted("openai", "gpt-5.5-pro", "cli-only"), false);
  });
});

describe("validateApiKeys with the agy gate", () => {
  const models = MultiModelConfigSchema.parse({
    enabled: true,
    models: [
      { provider: "anthropic", model_id: "claude-headless" },
      { provider: "google", model_id: "gemini-3.1-pro-preview" },
    ],
  });

  it("off + cli-only: the google voice is not planned (not missing, not valid) even with a key", () => {
    const saved = process.env.GOOGLE_API_KEY;
    process.env.GOOGLE_API_KEY = "fixture-not-a-key";
    try {
      const r = validateApiKeys(models, { optIn: false, mode: "cli-only" });
      assert.deepEqual(r.valid.map((v) => v.provider), ["anthropic"]);
      assert.deepEqual(r.missing, []);
      assert.deepEqual(r.notPlanned, [{ provider: "google", modelId: "gemini-3.1-pro-preview", reason: "opt_in_required" }]);
    } finally {
      if (saved === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = saved;
    }
  });

  it("on + cli-only: registered as before", () => {
    const saved = process.env.GOOGLE_API_KEY;
    process.env.GOOGLE_API_KEY = "fixture-not-a-key";
    try {
      const r = validateApiKeys(models, { optIn: true, mode: "cli-only" });
      assert.deepEqual(r.valid.map((v) => v.provider), ["anthropic", "google"]);
      assert.deepEqual(r.notPlanned, []);
    } finally {
      if (saved === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = saved;
    }
  });

  it("off + prefer-api: an HTTP google route is not gated (a missing key stays missing)", () => {
    const saved = process.env.GOOGLE_API_KEY;
    delete process.env.GOOGLE_API_KEY;
    try {
      const r = validateApiKeys(models, { optIn: false, mode: "prefer-api" });
      assert.deepEqual(r.missing.map((m) => m.provider), ["google"]);
      assert.deepEqual(r.notPlanned, []);
    } finally {
      if (saved !== undefined) process.env.GOOGLE_API_KEY = saved;
    }
  });
});

describe("executeMultiModelReview with the agy opt-in off", () => {
  it("does not register the google voice, logs the reason once, and counts the two planned voices as a full APPROVED cohort", async () => {
    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_path, repoRoot) => {
      const savedKey = process.env.GOOGLE_API_KEY;
      const savedMode = process.env.LOA_HEADLESS_MODE;
      process.env.GOOGLE_API_KEY = "fixture-not-a-key";
      delete process.env.LOA_HEADLESS_MODE;
      const seen: string[] = [];
      const infos: string[] = [];
      const bodies: string[] = [];
      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async function (this: unknown) {
        seen.push(String((this as { opts?: { model?: string } }).opts?.model ?? ""));
        return {
          content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
          inputTokens: 1, outputTokens: 1, model: "fixture",
          verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
        };
      });
      try {
        const multiModel = {
          enabled: true,
          models: [
            { provider: "anthropic", model_id: "claude-headless", role: "primary" },
            { provider: "openai", model_id: "codex-headless", role: "reviewer" },
            { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
          ],
          api_key_mode: "graceful", consensus: { enabled: true, scoring_thresholds: {} },
        } as MultiModelConfig;
        const config = {
          repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
          maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
          repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
          maxRuntimeMinutes: 1, multiModel,
        } as BridgebuilderConfig;
        const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
        const result = await executeMultiModelReview(item, "fixture", "fixture", config, {
          poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async (c: { body: string }) => { bodies.push(c.body); return true; } },
          sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
          logger: { info(m: string) { infos.push(m); }, warn() {}, error() {}, debug() {} },
        }, { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" });
        assert.ok(!seen.includes("gemini-3.1-pro-preview"), `dispatched ${JSON.stringify(seen)}`);
        assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic", "openai"]);
        assert.deepEqual(result.notPlanned, [{ provider: "google", modelId: "gemini-3.1-pro-preview", reason: "opt_in_required" }]);
        assert.equal(infos.filter((m) => m === "google voice not planned: agy opt-in off (hounfour.headless.agy_opt_in)").length, 1);
        const summary = bodies.find((b) => b.includes("**Verdict Quality**"));
        assert.ok(summary && summary.includes("✓ APPROVED — 2/2 voices"), `summary: ${summary}`);
        assert.ok(!result.reviewVerdict.mergeBlocked, "a not-planned voice never blocks the merge as a missing one would");
      } finally {
        stub.mock.restore();
        if (savedKey === undefined) delete process.env.GOOGLE_API_KEY; else process.env.GOOGLE_API_KEY = savedKey;
        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
      }
    });
  });
});

// --- review r251-1 G3 (findings 20, 21) ------------------------------------------------------------------------------

function pipelineFixture(models: MultiModelConfig["models"], mode: "graceful" | "strict", repoRoot: string) {
  const multiModel = { enabled: true, models, api_key_mode: mode, consensus: { enabled: true, scoring_thresholds: {} } } as MultiModelConfig;
  const config = {
    repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
    maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
    repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
    maxRuntimeMinutes: 1, multiModel,
  } as BridgebuilderConfig;
  const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
  const infos: string[] = [];
  const warns: string[] = [];
  const adapters = {
    poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async () => true },
    sanitizer: { sanitize: (content: string) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
    logger: { info(m: string) { infos.push(m); }, warn(m: string) { warns.push(m); }, error() {}, debug() {} },
  };
  const enrichment = { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" };
  return { config, item, adapters, enrichment, infos, warns };
}

describe("executeMultiModelReview edge cases (r251-1 G3)", () => {
  it("every configured voice gated off: refuses with the opt-in named, never 'all API keys missing' and never a clear", async () => {
    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_p, repoRoot) => {
      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => { throw new Error("dispatched"); });
      try {
        const f = pipelineFixture([{ provider: "google", model_id: "gemini-3.1-pro-preview", role: "primary" }] as MultiModelConfig["models"], "graceful", repoRoot);
        await assert.rejects(
          executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment),
          (err: Error) => /not planned/.test(err.message) && /hounfour\.headless\.agy_opt_in/.test(err.message) && !/all API keys missing/.test(err.message),
        );
        assert.equal(stub.mock.callCount(), 0);
      } finally {
        stub.mock.restore();
        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
      }
    });
  });

  it("strict mode: a configured voice removed by the gate WARNs (it will not run) and does not throw", async () => {
    await withConfig("hounfour:\n  headless:\n    mode: cli-only\n", async (_p, repoRoot) => {
      const savedMode = process.env.LOA_HEADLESS_MODE; delete process.env.LOA_HEADLESS_MODE;
      const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => ({
        content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
        inputTokens: 1, outputTokens: 1, model: "fixture",
        verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
      }));
      try {
        const f = pipelineFixture([
          { provider: "anthropic", model_id: "claude-headless", role: "primary" },
          { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
        ] as MultiModelConfig["models"], "strict", repoRoot);
        const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
        const w = f.warns.filter((m) => m.includes("gemini-3.1-pro-preview") && m.includes("strict") && m.includes("hounfour.headless.agy_opt_in"));
        assert.equal(w.length, 1, JSON.stringify(f.warns));
        assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic"]);
      } finally {
        stub.mock.restore();
        if (savedMode !== undefined) process.env.LOA_HEADLESS_MODE = savedMode;
      }
    });
  });
});

// --- review r251-1 G12/G14/G15/G16 ------------------------------------------------------------------------------------

describe("readAgyGate states (r251-1 G12, G14)", () => {
  it("a present non-boolean agy_opt_in (the string \"true\") reads off and is flagged for one WARN naming the key", async () => {
    await withConfig("hounfour:\n  headless:\n    agy_opt_in: \"true\"\n", (path) => {
      const g = readAgyGate(path);
      assert.equal(g.optIn, false);
      assert.match(String(g.typeWarning), /hounfour\.headless\.agy_opt_in/);
      assert.match(String(g.typeWarning), /boolean/);
    });
    await withConfig("hounfour:\n  headless:\n    agy_opt_in: true\n", (path) => assert.equal(readAgyGate(path).typeWarning, undefined));
    await withConfig("hounfour: {}\n", (path) => assert.equal(readAgyGate(path).typeWarning, undefined));
  });

  it("an unreadable config fails closed but says why: readError carries the underlying error", async () => {
    await withConfig("hounfour: [unclosed\n", (path) => {
      const g = readAgyGate(path);
      assert.equal(g.optIn, false);
      assert.ok(g.readError && g.readError.length > 0, JSON.stringify(g));
    });
  });

  it("a missing config file is no error (no Loa config: the opt-in is simply off)", async () => {
    await withConfig(null, (path) => assert.equal(readAgyGate(path).readError, undefined));
  });
});

describe("validateApiKeys takes the gate explicitly (r251-1 G15)", () => {
  it("the gate parameter is required: the function arity is 2 and no default reads the process cwd", () => {
    assert.equal(validateApiKeys.length, 2);
  });
  it("loaConfigPathFor resolves the repo root's .loa.config.yaml, and the cwd file only without a root", () => {
    assert.equal(loaConfigPathFor("/x/repo"), join("/x/repo", ".loa.config.yaml"));
    assert.equal(loaConfigPathFor(undefined), ".loa.config.yaml");
  });
});

describe("isAgyRouted reads the generated registry (r251-1 G16)", () => {
  it("every google headless id in the registry is agy-routed on any mode; other providers' headless ids never are", () => {
    const ids = Object.entries(GENERATED_MODEL_REGISTRY).filter(([id, e]) => /-headless$/.test(id) && e.provider === "google").map(([id]) => id);
    assert.ok(ids.length > 0);
    for (const id of ids) assert.equal(isAgyRouted("google", id, "prefer-api"), true, id);
    for (const [id, e] of Object.entries(GENERATED_MODEL_REGISTRY)) {
      if (/-headless$/.test(id) && e.provider !== "google") assert.equal(isAgyRouted(e.provider, id, "cli-only"), false, id);
    }
    assert.equal(isAgyRouted("google", "not-a-registry-headless", "prefer-api"), false);
  });
});

describe("executeMultiModelReview gate diagnostics (r251-1 G12, G14)", () => {
  for (const [label, body, want] of [
    ["unreadable config", "hounfour: [unclosed\n", /agy gate unreadable/],
    ["string opt-in", "hounfour:\n  headless:\n    mode: cli-only\n    agy_opt_in: \"true\"\n", /hounfour\.headless\.agy_opt_in.*boolean/],
  ] as const) {
    it(`${label}: one warn with the reason, the google voice not planned`, async () => {
      await withConfig(body, async (_p, repoRoot) => {
        const savedMode = process.env.LOA_HEADLESS_MODE; process.env.LOA_HEADLESS_MODE = "cli-only";
        const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => ({
          content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->\n\nVerdict: APPROVE",
          inputTokens: 1, outputTokens: 1, model: "fixture",
          verdictQuality: { status: "APPROVED", voices_planned: 1, voices_succeeded: 1, chain_health: "ok" },
        }));
        try {
          const f = pipelineFixture([
            { provider: "anthropic", model_id: "claude-headless", role: "primary" },
            { provider: "google", model_id: "gemini-3.1-pro-preview", role: "reviewer" },
          ] as MultiModelConfig["models"], "graceful", repoRoot);
          const result = await executeMultiModelReview(f.item, "fixture", "fixture", f.config, f.adapters as never, f.enrichment);
          assert.equal(f.warns.filter((m) => want.test(m)).length, 1, JSON.stringify(f.warns));
          assert.deepEqual(result.modelResults.map((r) => r.provider), ["anthropic"]);
        } finally {
          stub.mock.restore();
          if (savedMode === undefined) delete process.env.LOA_HEADLESS_MODE; else process.env.LOA_HEADLESS_MODE = savedMode;
        }
      });
    });
  }
});
