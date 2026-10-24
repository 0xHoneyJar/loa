import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";
import { z } from "zod/v4";
import {
  CANONICAL_FINDING_SCHEMA_ID,
  CanonicalFindingSchema,
  aliasWarning,
  validateCanonicalFinding,
} from "../core/finding-schema.js";
import { FindingsBlockSchema } from "../core/schemas.js";

// cycle-133 C-11: the zod validator against the shared conformance vectors (the jq, python and markdown validators
// run the same files: tests/unit/finding-conformance.bats)
const SCHEMAS = fileURLToPath(new URL("../../../../schemas/", import.meta.url));
const VECTORS = join(SCHEMAS, "finding.vectors");

interface Vector {
  description: string;
  finding: unknown;
  expect: { errors: string[]; finding: Record<string, unknown> | null; valid: boolean; warnings: string[] };
  markdown: string | null;
}

function vectors(kind: "valid" | "invalid"): Array<[string, Vector]> {
  return readdirSync(join(VECTORS, kind))
    .filter((n) => n.endsWith(".json"))
    .sort()
    .map((n) => [n, JSON.parse(readFileSync(join(VECTORS, kind, n), "utf8")) as Vector]);
}

describe("canonical finding (C-11) — zod validator on the conformance vectors", () => {
  for (const kind of ["valid", "invalid"] as const) {
    const vs = vectors(kind);
    it(`has ${kind} vectors`, () => assert.ok(vs.length >= 15, `${kind}: ${vs.length}`));
    for (const [name, v] of vs) {
      it(`${kind}/${name}: ${v.description}`, () => {
        const got = validateCanonicalFinding(v.finding);
        assert.deepEqual(got, v.expect);
        assert.equal(got.valid, kind === "valid");
        const z1 = CanonicalFindingSchema.safeParse(v.finding);
        assert.equal(z1.success, kind === "valid");
        if (z1.success) assert.deepEqual(z1.data, v.expect.finding);
        else assert.deepEqual(z1.error.issues.map((i) => i.message).sort(), v.expect.errors);
      });
    }
  }

  it("names the alias warning exactly as the SDD states it", () => {
    assert.equal(aliasWarning("failure_mode"), "`failure_mode` is an alias of `failure_scenario`; removed in 2.1.0");
  });

  it("FindingsBlockSchema references the canonical schema", () => {
    const schema = JSON.parse(readFileSync(join(SCHEMAS, "finding.schema.json"), "utf8"));
    assert.equal(schema.$id, CANONICAL_FINDING_SCHEMA_ID);
    const meta = z.globalRegistry.get(FindingsBlockSchema) as Record<string, unknown> | undefined;
    assert.equal(meta?.canonicalFindingSchema, CANONICAL_FINDING_SCHEMA_ID);
    // the extraction stays lenient: a block the canonical contract would reject still parses (no Bridgebuilder regression)
    assert.ok(FindingsBlockSchema.safeParse({ schema_version: 1, findings: [{ id: "F1", severity: "HIGH", category: "x" }] }).success);
  });
});
