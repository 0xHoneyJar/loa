VERDICT: APPROVE

Findings:
- LOW (informational, unreachable), .claude/scripts/grimoire-index.sh:262 — on malformed JSON fed to render_md, old printed TWO "jq: parse error" lines (the .total substitution inside echo does not trip set -e; the first count= assignment does), new prints ONE. rc (5) and INDEX.md (untouched, mv never reached) identical. Unreachable in practice: $JSON is always to_json's jq output. Verified with scratch copies of both render_md bodies under set -euo pipefail, feeding "{bad json" (/tmp/eso-r5/err-{old,new}.sh). No action needed.
- Diff read line by line: all three row templates textually identical (column order, esc per cell, join(",") decisions vs join(", ") default, .voice//"", .recurrence//"", .symptom//"", .refs//[]). Header/separator lines identical. "Total entries: N." sentence identical incl. "·" chars and trailing period. Moved comments are jq "#" comments inside the single-quoted program, contain no apostrophe, do not alter output. Trailing "" per family = old trailing echo.
- Skip semantics: counts come from `length` in to_json (always a number); absent family -> `// 0` -> 0 -> skipped; empty corpus -> counts {} -> all skipped. Old string "0" compare and new numeric != 0 are equivalent on every reachable input.
- Error path: require_jq (line 290) runs before any render; jq-absent render path unreachable. Write mode renders to mktemp then mv under set -e in both versions; render failure leaves INDEX.md untouched in both (stray tmp file in both, pre-existing).

Parity: old (HEAD mirror, confirmed == git show HEAD) vs new, write mode stdout/stderr(path-normalized)/rc/INDEX.md/.run/grimoire-index.json byte-identical on 3 fixtures: empty corpus (0 entries, counts {}), weird (live kf + decisions + handoffs, no visions/lore/NOTES, extra KF-999 with | \ " in title/status/symptom), onlynotes (single NOTES heading with | " \). 15/15 SAME. Fixtures under /tmp/eso-r5/.
Bats: tests/unit/grimoire-index.bats + kf-surface.bats 21/21 ok.
Hyperfine (write mode, -N warmup 2 runs 5): old 818.3±21.7 ms, new 631.1±15.7 ms (-22.9%, ~9σ). Live INDEX.md unchanged after runs.
Lint/scope: tools/check-no-swallowed-jq.sh --quiet rc=0; repo diff only grimoire-index.sh (render_md + header comment) and orchestrator's .skill-loop-progress.md (commit-SHA line for pass 4, not implementer debris). One lever.
UNVERIFIED: implementer's 168/168 golden checksums not re-run (time budget); yq-absent fixture not re-run (render_md does not touch yq; to_json unchanged).
