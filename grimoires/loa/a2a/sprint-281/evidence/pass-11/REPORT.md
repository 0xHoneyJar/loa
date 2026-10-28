# ESO pass 11 - SessionStart hooks: loa-run-state-surface.sh

Re-baseline (hook-guard wrapped, hyperfine -N, 20 runs, ms): check-updates 16.3, l6 11.0, l7 10.1, session-title 9.1, kf 14.6, decisions 16.4, run-state 26.6, context-class 24.8. Chain total ~129 ms.
Hotspot: loa-run-state-surface.sh (largest). Trace: 6 jq spawns (3 per existing state file: `jq -e .`, state, timestamp), ~2.3 ms each = ~14 of ~26 ms (~50%+).
Matrix: Impact 4 (-9 ms on the largest hook), Confidence 5, Effort 2 -> 10.
Lever: one `jq -rs` per file validates and extracts state+timestamp (fast path); falls back to the original 3-jq sequence for ANY anomaly (unparsable, empty, multi-doc, non-object, non-string value, control bytes in value, jq error). File: .claude/hooks/session-start/loa-run-state-surface.sh surface() ~L46-66.
Result (mirror, 30 runs): old 25.8+-3.7 ms -> new 16.7+-0.8 ms (-9.1 ms). Chain ~129 -> ~120 ms. Live jq spawns 6 -> 2.
Golden: 36 fixtures (halted/interrupted/stale/fresh running, simstim, null/missing/bad ts, unparsable, empty, null/false/array/string docs, multi-doc, num/obj/false state, control bytes, DEL, newline, long, unicode, pipe/<>, empty-string, all-files, session-limit, PATH without jq) stdout+stderr+rc cmp old vs new: 36/36 identical; live state via hook-guard identical. Script: pass-11/parity.sh.
Tests: bats run-state-surface.bats + run-checkpoint-derive.bats: all ok, 0 not ok. check-no-swallowed-jq: OK.
Isomorphism: ordering/tie-breaking unchanged; FP N/A; RNG N/A; sanitisation (_san: tr control bytes, cut 80) unchanged and still applied; fast path refuses values with control bytes (falls back); degraded paths identical (verified by fixtures); no jq -> exit 0 silent before surface runs; exit 0 always.
Not fixed: session-limit block still does up to 3 jq when that file exists (absent live; could use same trick); _san/_age fork tr/cut/date; loa-context-class.sh (24.8 ms, 55 trace lines) untouched; one lever only.
Checked and fine: check-updates/l6/l7/title are 9-16 ms, near process-start floor; kf-surface done in pass 6; hook-guard wrapper overhead small.
