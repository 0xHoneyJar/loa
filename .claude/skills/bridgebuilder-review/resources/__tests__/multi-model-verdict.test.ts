import { it, mock } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync, existsSync, readdirSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ChevalDelegateAdapter } from "../adapters/cheval-delegate.js";
import { executeMultiModelReview } from "../core/multi-model-pipeline.js";
import type { BridgebuilderConfig, MultiModelConfig, ReviewItem } from "../core/types.js";
import type { PRReviewTemplate } from "../core/template.js";
import { MultiModelConfigSchema } from "../config.js";
import { approvedQuality, approvalBody } from "./helpers/review-quality.js";
import type { ReviewResponse } from "../ports/llm-provider.js";

for (const variant of [
  "healthy", "unparsed", "empty", "comment", "missing-quality", "malformed-quality",
  "degraded", "error", "duplicate-config", "same-resolved-model", "same-voice",
  "example", "split-fence", "missing-provider",
]) {
  it(`each expected multi-model response must qualify independently: ${variant}`, async () => {
    const repoRoot = mkdtempSync(join(tmpdir(), "bb-cohort-"));
    const previousKey = process.env.ANTHROPIC_API_KEY;
    const previousGoogleKey = process.env.GOOGLE_API_KEY;
    process.env.ANTHROPIC_API_KEY = "offline-fixture-unused";
    delete process.env.GOOGLE_API_KEY;
    let calls = 0;
    const comments: string[] = [];
    const stub = mock.method(ChevalDelegateAdapter.prototype, "generateReview", async (): Promise<ReviewResponse> => {
      const index = calls++;
      if (index === 1 && variant === "error") throw new Error("Synthetic voice unavailable");
      const response: ReviewResponse = {
        content: approvalBody, inputTokens: 1, outputTokens: 1,
        provider: "anthropic", model: index === 0 ? "fixture-a" : "fixture-b",
        verdictQuality: approvedQuality(index === 0 ? "fixture-a" : "fixture-b"),
      };
      if (index === 1) {
        if (variant === "unparsed") response.content = "## Summary\nReview could not be completed.\n## Findings\nNo verdict is available for this change.";
        if (variant === "empty") response.content = "";
        if (variant === "comment") response.content = approvalBody.replace("APPROVE", "COMMENT");
        if (variant === "example") response.content = "~~~text\nVerdict: APPROVE\n~~~";
        if (variant === "missing-quality") response.verdictQuality = undefined;
        if (variant === "malformed-quality") response.verdictQuality = { status: "APPROVED" } as ReviewResponse["verdictQuality"];
        if (variant === "degraded") response.verdictQuality!.chain_health = "degraded";
        if (variant === "same-resolved-model") response.model = "fixture-a";
        if (variant === "same-voice") response.verdictQuality!.voices_succeeded_ids = ["fixture-a"];
      }
      if (variant === "split-fence") {
        response.content = index === 0 ? "~~~text\nExample is unfinished." : "~~~\nVerdict: APPROVE\n~~~";
      }
      return response;
    });
    try {
      const multiModel = MultiModelConfigSchema.parse({
        enabled: true, api_key_mode: "graceful",
        models: [
          { provider: "anthropic", model_id: "fixture-a", role: "primary" },
          { provider: variant === "missing-provider" ? "google" : "anthropic",
            model_id: variant === "duplicate-config" ? "fixture-a" : "fixture-b", role: "reviewer" },
        ],
      });
      const config = {
        repos: [], repoRoot, model: "fixture", maxPrs: 1, maxFilesPerPr: 1, maxDiffBytes: 1000,
        maxInputTokens: 1000, maxOutputTokens: 1000, dimensions: [], reviewMarker: "fixture",
        repoOverridePath: "", dryRun: false, excludePatterns: [], sanitizerMode: "default",
        maxRuntimeMinutes: 1, multiModel,
      } as BridgebuilderConfig;
      const result = await executeMultiModelReview(
        { owner: "fixture", repo: "repo", pr: { number: 22, headSha: "fixture" }, files: [], hash: "fixture" } as ReviewItem,
        "fixture", "fixture", config, {
          poster: { hasExistingReview: async () => false,
            postReview: async () => { throw new Error("Unexpected publication"); },
            postComment: async ({ body }) => { comments.push(body); return true; } },
          sanitizer: { sanitize: (content) => ({ safe: true, sanitizedContent: content, redactedPatterns: [] }) },
          logger: { info() {}, warn() {}, error() {}, debug() {} },
        },
      );
      assert.equal(calls, variant === "missing-provider" ? 1 : 2);
      assert.equal(result.reviewVerdict.mergeBlocked, variant !== "healthy");
      if (["unparsed", "empty", "example", "split-fence"].includes(variant)) {
        assert.equal(result.reviewVerdict.verdict, "UNKNOWN");
      }
      if (variant === "healthy") assert.equal(result.reviewVerdict.verdict, "APPROVE");
      // BIR-002: assert the actual posted consensus and emitted trajectory.
      const qualityApproved = variant === "healthy" || variant === "comment";
      if (qualityApproved) {
        assert.match(comments.at(-1)!, /✓ APPROVED — 2\/2 voices, chain ok/);
        if (variant === "comment") assert.match(comments.at(-1)!, /Merge Clearance.*COMMENT — blocked/);
      } else {
        assert.match(comments.at(-1)!, /Verdict Quality.*(?:DEGRADED|FAILED)/);
        assert.doesNotMatch(comments.at(-1)!, /✓ APPROVED|2\/2 voices/);
      }
      const trajectory = join(repoRoot, "grimoires/loa/a2a/trajectory");
      const records = existsSync(trajectory) ? readdirSync(trajectory).flatMap((file) =>
        readFileSync(join(trajectory, file), "utf8").trim().split("\n").map((line) => JSON.parse(line))) : [];
      assert.equal(records.length, qualityApproved ? 0 : 1);
      if (!qualityApproved) {
        assert.match(records[0].verdict_band, /^(DEGRADED|FAILED)$/);
        assert.notEqual(records[0].degradation_reason, "unknown");
      }
    } finally {
      stub.mock.restore();
      if (previousKey === undefined) delete process.env.ANTHROPIC_API_KEY;
      else process.env.ANTHROPIC_API_KEY = previousKey;
      if (previousGoogleKey === undefined) delete process.env.GOOGLE_API_KEY;
      else process.env.GOOGLE_API_KEY = previousGoogleKey;
      rmSync(repoRoot, { recursive: true, force: true });
    }
  });
}

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
