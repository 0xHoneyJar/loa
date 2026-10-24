import { z } from "zod/v4";
import { CANONICAL_FINDING_SCHEMA_ID, CANONICAL_FINDING_SCHEMA_PATH } from "./finding-schema.js";
/**
 * Confidence field: accepts any value but only preserves valid numbers in [0, 1].
 * Invalid values (wrong type, out of bounds) are silently stripped to undefined,
 * matching the existing lenient behavior from the inline type guard.
 */
const ConfidenceField = z
    .unknown()
    .transform((val) => {
    if (typeof val === "number" && val >= 0 && val <= 1) {
        return val;
    }
    return undefined;
})
    .optional();
/**
 * Zod schema for an individual bridge finding.
 *
 * Required fields: id, severity, category (all strings).
 * Optional: confidence (number 0.0-1.0), stripped if outside bounds or wrong type.
 * Passthrough: enrichment fields (faang_parallel, metaphor, teachable_moment, connection)
 * are preserved without validation via .passthrough().
 */
export const FindingSchema = z
    .object({
    id: z.string(),
    severity: z.string(),
    category: z.string(),
    confidence: ConfidenceField,
})
    .passthrough();
/**
 * Zod schema for the findings block extracted from bridge-findings markers.
 *
 * Validates the top-level structure: schema_version (number) and findings (array).
 * Individual findings are validated per FindingSchema (the lenient extraction shape). The finding contract is the
 * canonical `.claude/schemas/finding.schema.json` v1 (cycle-133 C-11): its zod validator is
 * `CanonicalFindingSchema` / `validateCanonicalFinding` in ./finding-schema.ts, named in this schema's metadata.
 */
export const FindingsBlockSchema = z
    .object({
    schema_version: z.number(),
    findings: z.array(FindingSchema),
})
    .meta({ canonicalFindingSchema: CANONICAL_FINDING_SCHEMA_ID, canonicalFindingSchemaPath: CANONICAL_FINDING_SCHEMA_PATH });
//# sourceMappingURL=schemas.js.map