import { qualifyReviewCohort } from "../../core/multi-model-pipeline.js";
import type { ReviewResponse } from "../../ports/llm-provider.js";
import { approvalBody } from "./review-quality.js";

/** Complete offline responses for the banner/trajectory unit fixtures. */
export function qualityCohort(voices: Array<{
  provider?: string; modelId?: string; verdictQuality?: unknown;
}>) {
  const expected = voices.map((voice, i) => ({
    provider: voice.provider ?? "fixture", model_id: voice.modelId ?? `fixture-${i}`,
  }));
  return qualifyReviewCohort(expected, voices.map((voice, i) => ({
    provider: expected[i].provider, model: expected[i].model_id, posted: false,
    response: {
      provider: expected[i].provider, model: expected[i].model_id,
      content: approvalBody, inputTokens: 1, outputTokens: 1,
      verdictQuality: voice.verdictQuality as ReviewResponse["verdictQuality"],
    },
  })));
}
