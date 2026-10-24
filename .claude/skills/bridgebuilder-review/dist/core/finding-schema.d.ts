import { z } from "zod/v4";
/**
 * cycle-133 C-11 (FR-11; D-3.2 DEC-0849, D-3.5 DEC-0857): the zod validator of the canonical finding,
 * `.claude/schemas/finding.schema.json` v1 — one of the four validators (with lib/finding-validate.sh,
 * lib/finding_validate.py and verdict-derive.sh's bullet grammar) that must agree on every vector under
 * `.claude/schemas/finding.vectors/{valid,invalid}/` (resources/__tests__/finding-schema.test.ts runs them).
 *
 * The result document is the one the other validators print: `{errors, finding, valid, warnings}` — error codes
 * sorted, the normalised finding (named fields only, confidence as the enum, `blocking` defaulted, `id` given or
 * derived `F-<first 6 hex of sha256("<file>:<anchor_line>:<title>")>`) or null.
 */
export declare const CANONICAL_FINDING_SCHEMA_ID = "https://loa.dev/schemas/finding.schema.json";
export declare const CANONICAL_FINDING_SCHEMA_PATH = ".claude/schemas/finding.schema.json";
export declare const SEVERITIES: readonly ["CRITICAL", "HIGH", "MEDIUM", "LOW", "PRAISE", "SPECULATION", "REFRAME", "INFO"];
export declare const DEFECT_SEVERITIES: readonly ["CRITICAL", "HIGH", "MEDIUM", "LOW"];
export declare const SeveritySchema: z.ZodEnum<{
    CRITICAL: "CRITICAL";
    HIGH: "HIGH";
    MEDIUM: "MEDIUM";
    LOW: "LOW";
    PRAISE: "PRAISE";
    SPECULATION: "SPECULATION";
    REFRAME: "REFRAME";
    INFO: "INFO";
}>;
export declare const LineSchema: z.ZodNumber;
export declare const PathSchema: z.ZodString;
export declare const ConfidenceSchema: z.ZodPipe<z.ZodUnion<readonly [z.ZodEnum<{
    low: "low";
    high: "high";
    medium: "medium";
}>, z.ZodNumber]>, z.ZodTransform<"low" | "high" | "medium", number | "low" | "high" | "medium">>;
export declare const IdSchema: z.ZodString;
/** The C-11 content rule for a defect severity's failure_scenario. */
export declare function contentOk(s: string): boolean;
export declare const ScenarioSchema: z.ZodString;
export interface CanonicalFindingResult {
    errors: string[];
    finding: Record<string, unknown> | null;
    valid: boolean;
    warnings: string[];
}
export declare function aliasWarning(key: string): string;
/** Validate and normalise one finding (any JSON value) — the result the other three validators print. */
export declare function validateCanonicalFinding(raw: unknown): CanonicalFindingResult;
/**
 * The canonical finding as a zod schema: parses to the normalised finding, or fails with one issue per error
 * code (the issue message is the code). Unknown properties pass through validation and are dropped from the
 * normalised view.
 */
export declare const CanonicalFindingSchema: z.ZodPipe<z.ZodUnknown, z.ZodTransform<Record<string, unknown>, unknown>>;
//# sourceMappingURL=finding-schema.d.ts.map