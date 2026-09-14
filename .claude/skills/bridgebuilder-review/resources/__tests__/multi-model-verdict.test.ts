import { it, mock } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";

for (const structured of [true, false]) {
  it(`multi-model handoff ${structured ? "retains HIGH findings and DEGRADED health" : "blocks unparsed reviews despite enrichment approval"} (#1171)`, async () => {
    const repoRoot = mkdtempSync(join(tmpdir(), "bb-verdict-"));
    const previousKey = process.env.ANTHROPIC_API_KEY;
    process.env.ANTHROPIC_API_KEY = "offline-fixture-unused";
    let calls = 0;
    const comments: string[] = [];
    const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async () => {
      calls++;
      return {
        content: calls <= 2 ? (structured ? "<!-- bridge-findings-start -->\n```json\n" + JSON.stringify({ schema_version: 1, findings: [
          { id: "INV2-001", title: "Fixture ownership", severity: "HIGH", category: "correctness", description: "Synthetic ownership is served" },
        ] }) + "\n```\n<!-- bridge-findings-end -->" : "Unparseable reviewer response") : "## Summary\nVerdict: APPROVE\n## Findings\nEnriched prose.",
        inputTokens: 1, outputTokens: 1, model: "fixture",
        verdictQuality: {
          status: structured ? "DEGRADED" : "APPROVED", consensus_outcome: "consensus", truncation_waiver_applied: false,
          voices_planned: 1, voices_succeeded: 1, voices_succeeded_ids: ["fixture"], voices_dropped: [],
          chain_health: structured ? "degraded" : "ok", confidence_floor: "med", rationale: "fixture", single_voice_call: true,
        },
      };
    });
    try {
      const multiModel = {
        enabled: true,
        models: [
          { provider: "anthropic", model_id: "claude-opus-4-7", role: "primary" },
          { provider: "anthropic", model_id: "claude-sonnet-4-6", role: "secondary" },
        ],
        api_key_mode: "strict", consensus: { enabled: true, scoring_thresholds: {} },
      } as MultiModelConfig;
      const config = {
        repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
        maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
        repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
        maxRuntimeMinutes: 1, multiModel,
      } as BridgebuilderConfig;
      const item = { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem;
      const result = await executeMultiModelReview(item, "fixture", "fixture", config, {
        poster: { postReview: async () => true, hasExistingReview: async () => false,
          postComment: async ({ body }) => { comments.push(body); return true; } },
        sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
        logger: { info() {}, warn() {}, error() {}, debug() {} },
      }, { template: { buildEnrichmentPrompt: () => ({ systemPrompt: "fixture", userPrompt: "fixture" }) } as unknown as PRReviewTemplate, persona: "fixture" });
      assert.equal(calls, 3, "two mocked voices and one mocked enrichment");
      assert.equal(result.reviewVerdict.verdict, structured ? "REQUEST_CHANGES" : "UNKNOWN");
      assert.equal(result.reviewVerdict.highestSeverity, structured ? "HIGH" : null);
      assert.equal(result.reviewVerdict.mergeBlocked, true);
      if (structured) assert.match(comments.at(-1)!, /DEGRADED/);
    } finally {
      stub.mock.restore();
      if (previousKey === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = previousKey;
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });
}
