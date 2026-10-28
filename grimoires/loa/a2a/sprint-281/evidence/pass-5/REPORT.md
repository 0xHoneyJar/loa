# ESO pass 5 - grimoire-index.sh render_md: one jq program instead of up to 13

## Opportunity matrix
| Lever | Impact | Confidence | Effort | Score |
|---|---|---|---|---|
| (1) render_md as ONE jq over the index JSON | 4 (~175 ms of ~820) | 5 | 1 | 20 |
| (2) emit_decisions yq|jq collapse | 2 (~35-60 ms) | 4 | 2 | 4 |
Chosen: (1). (2) is the next lever.

## Hotspot evidence
- The bash -x profile is misleading for the 1.3 MB string: the 0.24 s printf and 0.17 s yq gaps include xtrace echoing the whole JSON. Un-traced segment timing (bash EPOCHREALTIME): yq 170-180 ms, jq validate 33 ms, jq render 32 ms (incl. printf round trip), 13 x `echo "$json" | jq` on the 620 KB index = 175-183 ms (~21% of 822 ms wall).
- Trace lines before 298,961 / after 110,536 (jq spawn lines 116 -> 44, includes xtrace echoes of the JSON).
- Note: yq with stdout=/dev/null takes ~30 s (yq colorizes when stdout is a char device); irrelevant to the script (stdout is a $() pipe) but do not benchmark yq with >/dev/null.

## Numbers (hyperfine -N, warmup 3, 10 runs, write mode)
| | mean +- sigma |
|---|---|
| before (HEAD 08fa29222) | 822.3 +- 19.1 ms |
| after | 646.8 +- 21.2 ms (-21.3%) |
(machine load avg ~11 from sibling passes; both measured in the same hyperfine invocation)

## Change
.claude/scripts/grimoire-index.sh render_md (~lines 252-290): the 5 static header lines stay as before (4 echos); the "Total entries" sentence and every family section (heading, blank, column header, separator, rows, trailing blank) come from one `jq -r` fed `$json` once. Same family order, `// 0` count with `select($count != 0)`, same three row layouts and `esc`. Comments kept.

## Isomorphism proof
- Ordering preserved: yes - family order is the literal generator `"decisions","handoff","kf","lore","notes","vision"`; row order is the unchanged `.families[$f][]` order.
- Tie-breaking unchanged: yes - no sorting touched (collect's sort untouched).
- Floating-point: N/A (counts/total are integers interpolated as before).
- RNG / hash seeds: N/A.
- Trust-boundary sanitisation unchanged: yes - rows are sanitised at emit time (pass 4 awk / decisions jq, untouched); render keeps `esc` pipe-escaping on every cell, same expressions.
- Error/degraded paths unchanged: yes - no yq / unparsable decisions.yaml / absent decisions.yaml / empty corpus (zero families) fixtures give byte-identical stdout, stderr and rc.
- Golden outputs: 168/168 files identical (6 fixtures x {yq present, yq absent via PATH without yq} x {--tsv, --json, --validate, write(stdout,stderr,rc,INDEX.md,.run json)}) old HEAD vs new, plus live repo write mode (stdout, stderr, INDEX.md, grimoire-index.json) identical. Checksums: pass-5/golden_checksums.txt (matrix in golden/matrix). Fixtures: live corpus copy; adv (decisions with `|`, `<`, `>`, control bytes, tab/newline/CR/DEL, C1, 300-char summaries, missing decided_by/proposed_by, non-object entries, numeric/bool/object ids, empty id; KF/vision/notes titles with `|`); bad (unparsable decisions.yaml); absent; empty (no families, "Total entries: 0."); onlydec.

## Tests
- `npx --no-install bats tests/unit/grimoire-index.bats tests/unit/kf-surface.bats`: 21/21 ok, 0 not ok.
- tools/check-no-swallowed-jq.sh: OK.

## Files changed
- .claude/scripts/grimoire-index.sh (render_md only).

## Checked and found already optimal / left alone
- to_json is a single `jq -R -s` over the TSV - one pass, fine.
- Un-traced, the decisions validate + render jq calls are 33 + 32 ms and the bash variable round trip is cheap; the 0.24 s printf in the trace is xtrace overhead, so lever (2) is worth only ~35-60 ms.
- yq itself (~175 ms parsing a 2 MB / 39k-line YAML) dominates what remains and cannot be reduced without changing the parser.
- write mode still does `echo "$JSON" | jq` for the `bad` check and the final total (2 more parses of 620 KB, ~25 ms); not touched (outside mission, tied to validate/lock logic).

## Next levers
1. emit_decisions: `yq ... | jq` with one validation+render jq (drops var round trip + one jq parse of 1.9 MB, ~35-60 ms), keeping both NOTE messages.
2. Fold the write-mode `bad` check and final `.total` into to_json's output / one jq (~25 ms).
