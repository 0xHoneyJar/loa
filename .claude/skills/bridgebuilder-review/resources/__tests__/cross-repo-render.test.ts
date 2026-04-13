/**
 * cross-repo-render.test.ts — coverage for #464 A4 (cross-repo wiring).
 *
 * Tests the rendering layer (cross-repo-render.ts) and verifies the
 * template injection point (buildConvergenceUserPrompt now accepts an
 * optional crossRepoSection arg). Network fetches (fetchCrossRepoContext)
 * are tested separately in cross-repo.test.ts; this suite covers the
 * pieces that PR #464 A4 added.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import {
  renderCrossRepoSection,
  DEFAULT_CROSS_REPO_MAX_BYTES,
} from "../core/cross-repo-render.js";
import type { CrossRepoContextResult, CrossRepoRef } from "../core/cross-repo.js";
import { PRReviewTemplate } from "../core/template.js";
import type { ReviewItem } from "../core/types.js";

function makeRef(owner: string, repo: string, num: number): CrossRepoRef {
  return { owner, repo, type: "issue", number: num, source: "auto" };
}

function makeItem(): ReviewItem {
  return {
    owner: "myorg",
    repo: "myrepo",
    pr: {
      number: 100,
      title: "Test PR",
      author: "alice",
      baseBranch: "main",
      headSha: "abc123",
      labels: [],
    },
    files: [],
  };
}

describe("renderCrossRepoSection (A4 wiring)", () => {
  it("returns empty string for no context and no errors", () => {
    const result: CrossRepoContextResult = { refs: [], context: [], errors: [] };
    assert.equal(renderCrossRepoSection(result), "");
  });

  it("renders a single successful ref with title, labels, and body", () => {
    const ref = makeRef("upstream", "loa", 467);
    const result: CrossRepoContextResult = {
      refs: [ref],
      context: [{
        ref,
        title: "Multi-model Bridgebuilder roadmap",
        body: "Persistent context anchor for the multi-model Bridgebuilder.",
        labels: ["RFC", "Feature"],
      }],
      errors: [],
    };
    const rendered = renderCrossRepoSection(result);
    assert.match(rendered, /^## Cross-Repository Context/);
    assert.match(rendered, /upstream\/loa#467/);
    assert.match(rendered, /Multi-model Bridgebuilder roadmap/);
    assert.match(rendered, /RFC, Feature/);
    assert.match(rendered, /Persistent context anchor/);
    // Marker for untrusted treatment must always appear
    assert.match(rendered, /untrusted data/);
  });

  it("includes an error section when any ref failed to fetch", () => {
    const okRef = makeRef("o", "r", 1);
    const failRef = makeRef("o", "r", 2);
    const result: CrossRepoContextResult = {
      refs: [okRef, failRef],
      context: [{ ref: okRef, title: "OK ref" }],
      errors: [{ ref: failRef, error: "timeout" }],
    };
    const rendered = renderCrossRepoSection(result);
    assert.match(rendered, /OK ref/);
    assert.match(rendered, /Cross-Repo Fetch Failures/);
    assert.match(rendered, /o\/r#2: timeout/);
  });

  it("respects the byte budget, drops later refs with a truncation note", () => {
    // Each ref renders to ~80 bytes header + ~1000 byte body
    const refs: CrossRepoRef[] = [];
    const context: CrossRepoContextResult["context"] = [];
    const bigBody = "x".repeat(950);
    for (let i = 1; i <= 10; i++) {
      const ref = makeRef("o", "r", i);
      refs.push(ref);
      context.push({ ref, title: `Ref ${i}`, body: bigBody });
    }
    const result: CrossRepoContextResult = { refs, context, errors: [] };
    // Use a 3KB budget so only ~2 refs fit
    const rendered = renderCrossRepoSection(result, 3000);
    assert.ok(rendered.length <= 3500, `rendered size ${rendered.length} > 3500 (some slack)`);
    assert.match(rendered, /truncated:.*more reference\(s\) omitted/);
  });

  it("DEFAULT_CROSS_REPO_MAX_BYTES is 20KB", () => {
    assert.equal(DEFAULT_CROSS_REPO_MAX_BYTES, 20_000);
  });
});

describe("buildConvergenceUserPrompt cross-repo injection (A4 wiring)", () => {
  const baseConfig = {
    repos: [],
    model: "claude-opus-4-6",
    maxPrs: 10,
    maxFilesPerPr: 50,
    maxDiffBytes: 100_000,
    maxInputTokens: 8000,
    maxOutputTokens: 4000,
    dimensions: ["security"],
    reviewMarker: "<!-- review -->",
    repoOverridePath: "",
    dryRun: false,
    excludePatterns: [],
    redactionEnabled: false,
    autoDetectEnabled: false,
    sanitizerMode: "default" as const,
    reviewMode: "two-pass" as const,
  };

  function emptyTruncation() {
    return {
      included: [],
      excluded: [],
      loaBanner: undefined,
      truncationDisclaimer: undefined,
    };
  }

  it("does not modify prompt when crossRepoSection is undefined", () => {
    const tmpl = new PRReviewTemplate(
      { items: [] },
      "test-persona",
      baseConfig,
    );
    const item = makeItem();
    const prompt = tmpl.buildConvergenceUserPrompt(item, emptyTruncation());
    assert.equal(prompt.includes("## Cross-Repository Context"), false);
  });

  it("does not modify prompt when crossRepoSection is empty string", () => {
    const tmpl = new PRReviewTemplate(
      { items: [] },
      "test-persona",
      baseConfig,
    );
    const item = makeItem();
    const prompt = tmpl.buildConvergenceUserPrompt(item, emptyTruncation(), "");
    assert.equal(prompt.includes("## Cross-Repository Context"), false);
  });

  it("injects crossRepoSection between PR metadata and Files Changed", () => {
    const tmpl = new PRReviewTemplate(
      { items: [] },
      "test-persona",
      baseConfig,
    );
    const item = makeItem();
    const section = "## Cross-Repository Context\n\nupstream/loa#467 — relevant context";
    const prompt = tmpl.buildConvergenceUserPrompt(item, emptyTruncation(), section);
    assert.match(prompt, /## Cross-Repository Context/);
    assert.match(prompt, /upstream\/loa#467/);
    // Section must appear before the Files Changed header
    const xrIdx = prompt.indexOf("## Cross-Repository Context");
    const filesIdx = prompt.indexOf("## Files Changed");
    assert.ok(xrIdx > 0 && filesIdx > xrIdx, `cross-repo (${xrIdx}) should precede files (${filesIdx})`);
  });
});
