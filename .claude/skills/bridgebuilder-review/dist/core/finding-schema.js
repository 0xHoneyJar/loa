import { createHash } from "node:crypto";
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
export const CANONICAL_FINDING_SCHEMA_ID = "https://loa.dev/schemas/finding.schema.json";
export const CANONICAL_FINDING_SCHEMA_PATH = ".claude/schemas/finding.schema.json";
export const SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "PRAISE", "SPECULATION", "REFRAME", "INFO"];
export const DEFECT_SEVERITIES = ["CRITICAL", "HIGH", "MEDIUM", "LOW"];
const WS = /[ \t\n\r\f\v]+/;
const WS_SRC = "[ \\t\\n\\r\\f\\v]+";
const DENY = ["todo", "n/a", "see above", "as described", "placeholder"].map((p) => new RegExp("(?<![A-Za-z0-9])" + p.split(" ").map((w) => w.replace(/[/]/g, "\\/")).join(WS_SRC) + "(?![A-Za-z0-9])"));
const LINE_MAX = 10_000_000;
const asciiLower = (s) => s.replace(/[A-Z]/g, (c) => c.toLowerCase());
const present = (v) => v !== undefined && v !== null;
export const SeveritySchema = z.enum(SEVERITIES);
export const LineSchema = z.number().refine((n) => Number.isInteger(n) && n >= 1 && n <= LINE_MAX);
export const PathSchema = z.string().refine((p) => {
    if (p === "" || p.startsWith("/") || p.includes("\\"))
        return false;
    for (const ch of p) {
        const c = ch.codePointAt(0) ?? 0;
        if (c < 0x20 || c === 0x7f)
            return false;
    }
    return p.split("/").every((seg) => seg !== "" && seg !== "." && seg !== "..");
});
export const ConfidenceSchema = z
    .union([z.enum(["high", "medium", "low"]), z.number().min(0).max(1)])
    .transform((v) => (typeof v === "string" ? v : v >= 0.75 ? "high" : v >= 0.45 ? "medium" : "low"));
export const IdSchema = z.string().refine((s) => s.replace(/[ \t\n\r\f\v]/g, "") !== "");
function tokens(s) {
    return s.split(WS).filter((t) => t.length > 0);
}
function whenThen(toks) {
    const st = toks.map((t) => asciiLower(t.replace(/^[^A-Za-z0-9]+/, "").replace(/[^A-Za-z0-9]+$/, "")));
    for (let i = 0; i < st.length; i++) {
        if (st[i] !== "when")
            continue;
        for (let j = i + 2; j < st.length - 1; j++)
            if (st[j] === "then")
                return true;
    }
    return false;
}
/** The C-11 content rule for a defect severity's failure_scenario. */
export function contentOk(s) {
    const low = asciiLower(s);
    if (DENY.some((r) => r.test(low)))
        return false;
    const t = tokens(s);
    return t.length >= 12 || whenThen(t);
}
export const ScenarioSchema = z.string().refine(contentOk);
export function aliasWarning(key) {
    return "`" + key + "` is an alias of `failure_scenario`; removed in 2.1.0";
}
function deriveId(file, line, title) {
    const text = `${present(file) ? String(file) : ""}:${present(line) ? String(line) : ""}:${present(title) ? String(title) : ""}`;
    return "F-" + createHash("sha256").update(text, "utf8").digest("hex").slice(0, 6);
}
/** Validate and normalise one finding (any JSON value) — the result the other three validators print. */
export function validateCanonicalFinding(raw) {
    if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
        return { errors: ["not_object"], finding: null, valid: false, warnings: [] };
    }
    const f = raw;
    const errs = new Set();
    const warns = [];
    const out = {};
    const sev = SeveritySchema.safeParse(f.severity);
    const defect = sev.success ? DEFECT_SEVERITIES.includes(sev.data) : null;
    if (!sev.success)
        errs.add("severity");
    if (present(f.id)) {
        if (IdSchema.safeParse(f.id).success)
            out.id = f.id;
        else
            errs.add("id");
    }
    if (present(f.file)) {
        if (PathSchema.safeParse(f.file).success)
            out.file = f.file;
        else
            errs.add("file");
    }
    else if (defect)
        errs.add("file");
    let line = null;
    if (present(f.anchor_line)) {
        const r = LineSchema.safeParse(f.anchor_line);
        if (r.success)
            line = out.anchor_line = r.data;
        else
            errs.add("anchor_line");
    }
    else if (defect)
        errs.add("anchor_line");
    if (present(f.anchor_line_end)) {
        const r = LineSchema.safeParse(f.anchor_line_end);
        if (!r.success || line === null || r.data < line)
            errs.add("anchor_line_end");
        else
            out.anchor_line_end = r.data;
    }
    if (present(f.blocking) && typeof f.blocking !== "boolean")
        errs.add("blocking");
    if (present(f.confidence)) {
        const r = ConfidenceSchema.safeParse(f.confidence);
        if (r.success)
            out.confidence = r.data;
        else
            errs.add("confidence");
    }
    for (const k of ["title", "suggestion"]) {
        if (present(f[k])) {
            if (typeof f[k] === "string")
                out[k] = f[k];
            else
                errs.add(k);
        }
    }
    const fs = f.failure_scenario;
    const fm = f.failure_mode;
    if (present(fs) && present(fm) && !(typeof fs === "string" && typeof fm === "string" && fs === fm))
        errs.add("alias_conflict");
    let picked = null;
    for (const key of ["failure_scenario", "failure_mode", "description"]) {
        if (present(f[key])) {
            picked = f[key];
            if (key !== "failure_scenario")
                warns.push(aliasWarning(key));
            break;
        }
    }
    if (picked === null) {
        if (defect)
            errs.add("failure_scenario");
    }
    else if (typeof picked !== "string")
        errs.add("failure_scenario");
    else if (defect && !ScenarioSchema.safeParse(picked).success)
        errs.add("failure_scenario");
    else
        out.failure_scenario = picked;
    if (errs.size > 0)
        return { errors: [...errs].sort(), finding: null, valid: false, warnings: warns };
    out.severity = sev.data;
    out.blocking = f.blocking === true;
    if (!("id" in out))
        out.id = deriveId(out.file, out.anchor_line, out.title);
    return { errors: [], finding: out, valid: true, warnings: warns };
}
/**
 * The canonical finding as a zod schema: parses to the normalised finding, or fails with one issue per error
 * code (the issue message is the code). Unknown properties pass through validation and are dropped from the
 * normalised view.
 */
export const CanonicalFindingSchema = z.unknown().transform((v, ctx) => {
    const r = validateCanonicalFinding(v);
    if (!r.valid) {
        for (const e of r.errors)
            ctx.addIssue({ code: "custom", message: e });
        return z.NEVER;
    }
    return r.finding;
});
//# sourceMappingURL=finding-schema.js.map