import { it, mock } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";

// cycle-126 thirty-seventh run, e2b DISS-C-003: the multi-model `anthropic` entry is `claude-headless` on a host with no
// ANTHROPIC_API_KEY; the pipeline dropped it at the key gate (graceful) and, with no other voice, threw "all API keys missing".
// Every voice dispatches through cheval, whose CLI hop authenticates itself, so a headless entry is dispatched without a key.
// (thirty-eighth run, e4 DISS-C-004: the openai route — codex-headless with no OPENAI_API_KEY — as well as the anthropic one)
const ROUTES = [
  { provider: "anthropic", modelId: "claude-headless", envVar: "ANTHROPIC_API_KEY" },
  { provider: "openai", modelId: "codex-headless", envVar: "OPENAI_API_KEY" },
] as const;
for (const route of ROUTES) for (const mode of ["graceful", "strict"] as const) {
  it(`a ${route.modelId} multi-model voice is dispatched with no ${route.envVar} (${mode})`, async () => {
    const repoRoot = mkdtempSync(join(tmpdir(), "bb-headless-key-"));
    const previousKey = process.env[route.envVar];
    delete process.env[route.envVar];
    const seen: string[] = [];
    const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async function (this: unknown) {
      seen.push(String((this as { opts?: { model?: string } }).opts?.model ?? ""));
      return {
        content: "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [] }) + "\n```\n<!-- bridge-findings-end -->",
        inputTokens: 1, outputTokens: 1, model: "fixture",
      };
    });
    try {
      const multiModel = {
        enabled: true,
        models: [{ provider: route.provider, model_id: route.modelId, role: "primary" }],
        api_key_mode: mode, consensus: { enabled: true, scoring_thresholds: {} },
      } as MultiModelConfig;
      const config = {
        repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
        maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
        repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
        maxRuntimeMinutes: 1, multiModel,
      } as BridgebuilderConfig;
      const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
      await executeMultiModelReview(item, "fixture", "fixture", config, {
        poster: { postReview: async () => true, hasExistingReview: async () => false, postComment: async () => true },
        sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
        logger: { info() {}, warn() {}, error() {}, debug() {} },
      }, { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" });
      assert.ok(stub.mock.callCount() >= 1, "the headless voice was dispatched");
      assert.ok(seen.length > 0 && seen.every((m) => m === route.modelId), `dispatched as ${JSON.stringify(seen)}`);
    } finally {
      stub.mock.restore();
      if (previousKey === undefined) delete process.env[route.envVar];
      else process.env[route.envVar] = previousKey;
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });
}
