import { z } from "zod/v4";
/**
 * Zod schema for an individual bridge finding.
 *
 * Required fields: id, severity, category (all strings).
 * Optional: confidence (number 0.0-1.0), stripped if outside bounds or wrong type.
 * Passthrough: enrichment fields (faang_parallel, metaphor, teachable_moment, connection)
 * are preserved without validation via .passthrough().
 */
export declare const FindingSchema: z.ZodObject<{
    id: z.ZodString;
    severity: z.ZodString;
    category: z.ZodString;
    confidence: z.ZodOptional<z.ZodPipe<z.ZodUnknown, z.ZodTransform<number | undefined, unknown>>>;
}, z.core.$loose>;
/**
 * Zod schema for the findings block extracted from bridge-findings markers.
 *
 * Validates the top-level structure: schema_version (number) and findings (array).
 * Individual findings are validated per FindingSchema (the lenient extraction shape). The finding contract is the
 * canonical `.claude/schemas/finding.schema.json` v1 (cycle-133 C-11): its zod validator is
 * `CanonicalFindingSchema` / `validateCanonicalFinding` in ./finding-schema.ts, named in this schema's metadata.
 */
export declare const FindingsBlockSchema: z.ZodObject<{
    schema_version: z.ZodNumber;
    findings: z.ZodArray<z.ZodObject<{
        id: z.ZodString;
        severity: z.ZodString;
        category: z.ZodString;
        confidence: z.ZodOptional<z.ZodPipe<z.ZodUnknown, z.ZodTransform<number | undefined, unknown>>>;
    }, z.core.$loose>>;
}, z.core.$strip>;
/** Inferred TypeScript type for a validated finding. */
export type ValidatedFinding = z.infer<typeof FindingSchema>;
/** Inferred TypeScript type for a validated findings block. */
export type ValidatedFindingsBlock = z.infer<typeof FindingsBlockSchema>;
//# sourceMappingURL=schemas.d.ts.map