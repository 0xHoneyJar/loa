// cycle-109 Sprint 4 T4.8 — BB PR-comment chunked-review annotation.
//
// formatChunkedReviewAnnotation renders an operator-facing block when
// per-model results carry chunked_review envelopes. Pinned by:
//   - chunked=true on at least one result → annotation rendered
//   - chunks_reviewed / chunks_dropped / chunks_with_findings aggregated
//   - cross_chunk_pass=true → extra annotation line
//   - empty / no-chunked-review results → empty string (no annotation)

import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { formatChunkedReviewAnnotation } from "../core/multi-model-pipeline.js";

describe("formatChunkedReviewAnnotation — chunked-review surface", () => {
  it("returns empty string when no chunked review occurred", () => {
    const out = formatChunkedReviewAnnotation([
      { provider: "anthropic", modelId: "claude-opus-4-7" },
      { provider: "openai", modelId: "gpt-5.5-pro" },
    ]);
    assert.equal(out, "");
  });

  it("returns empty string when chunkedReview.chunked is false", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: { chunked: false, chunks_reviewed: 0 },
      },
    ]);
    assert.equal(out, "");
  });

  it("renders annotation when chunkedReview.chunked is true", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 5,
          chunks_dropped: 0,
          chunks_with_findings: 3,
        },
      },
    ]);
    assert.ok(out.length > 0);
    assert.match(out, /Chunked review/);
    assert.match(out, /5/);  // total chunks
    assert.match(out, /3/);  // chunks with findings
  });

  it("aggregates across multiple chunked models", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 3,
          chunks_with_findings: 2,
        },
      },
      {
        provider: "openai", modelId: "gpt-5.5-pro",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 4,
          chunks_with_findings: 1,
        },
      },
    ]);
    assert.match(out, /7/);  // total chunks across both = 7
    assert.match(out, /3/);  // total with findings = 3
    assert.match(out, /2 models/);  // plural model count
  });

  it("flags dropped chunks with a warning", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 5,
          chunks_dropped: 2,
          chunks_with_findings: 1,
        },
      },
    ]);
    assert.match(out, /2 dropped/);
    assert.match(out, /⚠/);
  });

  it("flags cross-chunk pass when invoked", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 4,
          chunks_with_findings: 2,
          cross_chunk_pass: true,
        },
      },
    ]);
    assert.match(out, /Cross-chunk pass invoked/);
  });

  it("omits cross-chunk-pass line when not invoked", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 3,
          chunks_with_findings: 1,
          cross_chunk_pass: false,
        },
      },
    ]);
    assert.doesNotMatch(out, /Cross-chunk pass invoked/);
  });

  it("references KF-002 layer-1 closure in the annotation", () => {
    const out = formatChunkedReviewAnnotation([
      {
        provider: "anthropic", modelId: "claude-opus-4-7",
        chunkedReview: {
          chunked: true,
          chunks_reviewed: 2,
        },
      },
    ]);
    assert.match(out, /KF-002/);
  });
});
