import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { computeScore } from "./score";

const ORACLE_5 = `
[claim a](~/src/a.md:1)
[claim b](~/src/b.md:2)
[claim c](~/src/c.md:3)
[claim d](~/src/d.md:4)
[claim e](~/src/e.md:5)
`;

const CANDIDATE_4_OF_5 = `
[claim a](~/src/a.md:1)
[claim b](~/src/b.md:2)
[claim c](~/src/c.md:3)
[claim d](~/src/d.md:4)
`;

const CANDIDATE_3_OF_5 = `
[claim a](~/src/a.md:1)
[claim b](~/src/b.md:2)
[claim c](~/src/c.md:3)
`;

describe("computeScore", () => {
  it("4/5 oracle citations matched → fidelity 0.800, pass true", () => {
    const result = computeScore(ORACLE_5, CANDIDATE_4_OF_5, "sha-x", "sha-x");
    assert.equal(result.fidelity, 0.8);
    assert.equal(result.pass, true);
    assert.equal(result.oracle_citations, 5);
    assert.equal(result.intersection, 4);
  });

  it("3/5 matched → fidelity 0.600, pass false", () => {
    const result = computeScore(ORACLE_5, CANDIDATE_3_OF_5, "sha-x", "sha-x");
    assert.equal(result.fidelity, 0.6);
    assert.equal(result.pass, false);
  });

  it("empty oracle set → fidelity 0, pass false", () => {
    const result = computeScore("# no citations", CANDIDATE_4_OF_5, "sha-x", "sha-x");
    assert.equal(result.fidelity, 0);
    assert.equal(result.pass, false);
    assert.equal(result.oracle_citations, 0);
  });

  it("sha256 mismatch → oracle_integrity false", () => {
    const result = computeScore(ORACLE_5, CANDIDATE_4_OF_5, "sha-before", "sha-after");
    assert.equal(result.oracle_integrity, false);
  });

  it("sha256 match → oracle_integrity true", () => {
    const result = computeScore(ORACLE_5, CANDIDATE_4_OF_5, "same-hash", "same-hash");
    assert.equal(result.oracle_integrity, true);
  });

  it("fidelity is rounded to exactly 3 decimal places", () => {
    const oracle = "[a](~/a.md:1) [b](~/b.md:2) [c](~/c.md:3)";
    const candidate = "[a](~/a.md:1)";
    const result = computeScore(oracle, candidate, "x", "x");
    assert.ok(Number.isFinite(result.fidelity));
    const asStr = result.fidelity.toFixed(3);
    assert.ok(asStr.split(".")[1].length === 3);
  });
});
