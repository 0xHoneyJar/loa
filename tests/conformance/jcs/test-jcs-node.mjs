// =============================================================================
// tests/conformance/jcs/test-jcs-node.mjs
//
// cycle-098 Sprint 1A — IMP-001 (HIGH_CONSENSUS 736). Native node:test harness
// exercising the Node JCS adapter (.claude/scripts/lib/jcs.mjs) against the
// conformance corpus.
//
// Run:
//   cd tests/conformance/jcs && npm install
//   node --test test-jcs-node.mjs
// =============================================================================

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(SCRIPT_DIR, "..", "..", "..");
const VECTORS_PATH = resolve(SCRIPT_DIR, "test-vectors.json");
const NODE_LIB = resolve(REPO_ROOT, ".claude", "scripts", "lib", "jcs.mjs");

const adapter = await import(`file://${NODE_LIB}`);

// Load corpus once, share across tests.
const corpus = JSON.parse(await readFile(VECTORS_PATH, "utf8"));
const vectors = corpus.vectors;

test("adapter is available", async () => {
  assert.equal(await adapter.available(), true, "canonicalize npm package not installed");
});

test("corpus size meets Sprint 1 AC (>= 20 vectors)", () => {
  assert.ok(vectors.length >= 20, `corpus has ${vectors.length} vectors; AC requires >= 20`);
});

test("canonicalize() returns Buffer", async () => {
  const out = await adapter.canonicalize({ a: 1 });
  assert.ok(Buffer.isBuffer(out), `expected Buffer, got ${typeof out}`);
});

for (const vector of vectors) {
  test(`vector ${vector.id}`, async () => {
    const actual = await adapter.canonicalize(vector.input);
    const expected = Buffer.from(vector.expected, "utf8");
    assert.deepEqual(
      actual,
      expected,
      `divergence on ${vector.id}: got ${JSON.stringify(actual.toString("utf8"))}, ` +
        `expected ${JSON.stringify(vector.expected)}`
    );
  });
}

test("determinism — different input order, identical bytes", async () => {
  const a = await adapter.canonicalize({ x: 1.5, y: [1, 2, 3] });
  const b = await adapter.canonicalize({ y: [1, 2, 3], x: 1.5 });
  assert.deepEqual(a, b);
});
