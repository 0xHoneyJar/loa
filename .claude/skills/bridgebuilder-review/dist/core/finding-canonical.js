/**
 * cycle-133 C-2: the canonical finding projection shared by the consensus renderer and the enrichment guard
 * (sdd.md C-2 canonical fields; the failure_scenario alias precedence of C-11).
 */
export const FINDINGS_START = "<!-- bridge-findings-start -->";
export const FINDINGS_END = "<!-- bridge-findings-end -->";
/** The canonical finding fields the posted block carries byte for byte and the guard compares. */
export const CANONICAL_FIELDS = [
    "id", "file", "anchor_line", "anchor_line_end", "severity", "confidence", "failure_scenario", "suggestion", "blocking",
];
function positiveInt(v) {
    return typeof v === "number" && Number.isInteger(v) && v > 0 ? v : null;
}
/**
 * The canonical projection of a finding: `file:line[-end]` references split into file and anchors (explicit
 * `anchor_line`/`anchor_line_end`/`line` win), `failure_scenario` by alias precedence (failure_scenario > failure_mode >
 * description, C-11), absent fields as null, `blocking` true only when the voice marked it so.
 */
export function canonicalize(f) {
    let file = typeof f.file === "string" ? f.file : null;
    let line = null;
    let end = null;
    if (file !== null) {
        const m = /^(.*?):(\d+)(?:-(\d+))?$/.exec(file);
        if (m) {
            file = m[1];
            line = Number(m[2]) > 0 ? Number(m[2]) : null;
            end = m[3] !== undefined && Number(m[3]) > 0 ? Number(m[3]) : null;
        }
    }
    const pick = (...keys) => {
        for (const k of keys)
            if (f[k] !== undefined && f[k] !== null)
                return f[k];
        return null;
    };
    return {
        id: String(f.id),
        file,
        anchor_line: positiveInt(f.anchor_line) ?? positiveInt(f.line) ?? line,
        anchor_line_end: positiveInt(f.anchor_line_end) ?? end,
        severity: String(f.severity ?? "").toUpperCase(),
        confidence: pick("confidence"),
        failure_scenario: pick("failure_scenario", "failure_mode", "description"),
        suggestion: pick("suggestion"),
        blocking: f.blocking === true,
    };
}
//# sourceMappingURL=finding-canonical.js.map