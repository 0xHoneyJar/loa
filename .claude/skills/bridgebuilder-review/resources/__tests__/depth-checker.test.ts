import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { checkDepth } from "../core/depth-checker.js";
import type { DepthResult } from "../core/depth-checker.js";

describe("checkDepth", () => {
  it("detects FAANG parallel", () => {
    const review = "This pattern is similar to Netflix's Zuul gateway architecture.";
    const result = checkDepth(review);
    assert.equal(result.elements.faangParallel, true);
  });

  it("detects specific FAANG systems by name", () => {
    const systems = [
      "Kubernetes is the evolution of Google's Borg scheduler",
      "This is similar to how Kafka handles message ordering",
      "Meta's approach to Cassandra sharding applies here",
      "The Spanner consistency model addresses this exact issue",
    ];
    for (const text of systems) {
      const result = checkDepth(text);
      assert.equal(result.elements.faangParallel, true, `Should detect FAANG in: ${text}`);
    }
  });

  it("detects metaphor", () => {
    const review = "Think of this as a traffic cop directing requests to the right lane.";
    const result = checkDepth(review);
    assert.equal(result.elements.metaphor, true);
  });

  it("detects metaphor with 'like' comparison", () => {
    const review = "The circuit breaker pattern works like a physical circuit breaker in your home.";
    const result = checkDepth(review);
    assert.equal(result.elements.metaphor, true);
  });

  it("detects teachable moment", () => {
    const review = "The broader principle here is that you should always validate at system boundaries.";
    const result = checkDepth(review);
    assert.equal(result.elements.teachableMoment, true);
  });

  it("detects teachable moment with 'whenever you' pattern", () => {
    const review = "Whenever you encounter a shared mutable state, consider whether a lock-free structure works.";
    const result = checkDepth(review);
    assert.equal(result.elements.teachableMoment, true);
  });

  it("detects tech history", () => {
    const review = "This pattern historically originated in the Erlang ecosystem and dates back to the 1980s.";
    const result = checkDepth(review);
    assert.equal(result.elements.techHistory, true);
  });

  it("detects business impact", () => {
    const review = "A 100ms increase in latency could impact conversion rates and revenue significantly.";
    const result = checkDepth(review);
    assert.equal(result.elements.businessImpact, true);
  });

  it("detects business impact with dollar amounts", () => {
    const review = "The outage cost Amazon approximately $100M in lost revenue per hour.";
    const result = checkDepth(review);
    assert.equal(result.elements.businessImpact, true);
  });

  it("detects social dynamics", () => {
    const review = "Per Conway's Law, the team structure will mirror this API boundary.";
    const result = checkDepth(review);
    assert.equal(result.elements.socialDynamics, true);
  });

  it("detects social dynamics with DX reference", () => {
    const review = "This increases cognitive load for new developers during onboarding.";
    const result = checkDepth(review);
    assert.equal(result.elements.socialDynamics, true);
  });

  it("detects cross-repo connection", () => {
    const review = "This pattern also appears in the upstream dependency graph.";
    const result = checkDepth(review);
    assert.equal(result.elements.crossRepoConnection, true);
  });

  it("detects frame question", () => {
    const review = "But should we question the premise? Is this the right abstraction?";
    const result = checkDepth(review);
    assert.equal(result.elements.frameQuestion, true);
  });

  it("detects frame question with reframe language", () => {
    const review = "Worth stepping back and asking: what if instead of caching, we optimized the query?";
    const result = checkDepth(review);
    assert.equal(result.elements.frameQuestion, true);
  });

  it("returns correct score for rich review (all 8 elements)", () => {
    const richReview = `
      This is similar to how Netflix's Zuul handles API gateway routing.

      Think of it as a traffic cop directing requests.

      The deeper issue here is that system boundaries need validation.

      This pattern historically dates back to the 1990s.

      A 100ms latency increase impacts revenue and user experience.

      Per Conway's Law, team boundaries affect API design. Developer experience matters.

      This pattern also appears in the upstream repository graph.

      But should we question the premise? Is this the right problem to solve?
    `;
    const result = checkDepth(richReview);
    assert.equal(result.score, 8);
    assert.equal(result.total, 8);
    assert.equal(result.passed, true);
  });

  it("returns correct score for minimal review (0 elements)", () => {
    const minimalReview = "The function returns a value. Consider adding error handling.";
    const result = checkDepth(minimalReview);
    assert.equal(result.score, 0);
    assert.equal(result.passed, false);
  });

  it("uses default min threshold of 5", () => {
    const result = checkDepth("some text");
    assert.equal(result.minThreshold, 5);
  });

  it("respects custom min threshold", () => {
    const review = `
      Similar to Google's Borg scheduler.
      Think of it as a queue.
      The lesson here is important.
    `;
    const result3 = checkDepth(review, { minElements: 3 });
    assert.equal(result3.passed, true);
    assert.equal(result3.minThreshold, 3);

    const result5 = checkDepth(review, { minElements: 5 });
    assert.equal(result5.passed, false);
    assert.equal(result5.minThreshold, 5);
  });

  it("handles empty input", () => {
    const result = checkDepth("");
    assert.equal(result.score, 0);
    assert.equal(result.passed, false);
    assert.equal(result.total, 8);
  });

  it("partial match: 5 of 8 elements passes default threshold", () => {
    const review = `
      Netflix designed Hystrix for this exact failure mode.
      Think of it like a circuit breaker in your house.
      The broader principle: fail fast, recover gracefully.
      This dates back to Erlang's "let it crash" philosophy from the 1980s.
      Downtime SLA violations can cost $50k per incident.
    `;
    const result = checkDepth(review);
    assert.ok(result.score >= 5, `Expected >= 5 elements, got ${result.score}`);
    assert.equal(result.passed, true);
  });

  it("returns all element fields in result", () => {
    const result = checkDepth("some review text");
    const keys = Object.keys(result.elements);
    assert.deepEqual(keys.sort(), [
      "businessImpact",
      "crossRepoConnection",
      "faangParallel",
      "frameQuestion",
      "metaphor",
      "socialDynamics",
      "teachableMoment",
      "techHistory",
    ]);
  });
});
