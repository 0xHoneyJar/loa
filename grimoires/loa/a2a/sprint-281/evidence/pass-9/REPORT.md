# ESO pass 9 - implement-gate.sh: parse the PreToolUse payload once

Opportunity matrix: Impact 4 (hot path, every Write/Edit), Confidence 4 (jq program is the same expressions; any odd shape falls back to the old code), Effort 2 -> score 8.0.

## Hotspot (bash -x trace, write.json, old hook)
Four jq spawns over the same stdin, ~2.4-2.8 ms each = ~10 ms of ~20.7 ms wall (~48%):
recorder `jq -e` (line 218) 2.35 ms, `jq -e .` (230) 2.55 ms, `jq -j` path (238) 2.76 ms, `jq -r` cwd (297) 2.62 ms.
Other costs: realpath x2 ~2.8 ms, compat-lib source ~1 ms, cat 1 ms, dirname ~1 ms each (not in scope).

## Lever
One `jq -nj '[inputs] ...'` before the recorder emits NUL-terminated fields: mode, lead-session test, file_path/notebook_path, cwd (read via `IFS= read -r -d ''` from process substitution, so newlines survive).
Mode F = exactly one parsed value, string-or-absent path, no NUL in path/cwd: use the fields. Mode U = single null/false (what `jq -e .` rejects): ask as before.
Anything else (no jq, parse error, empty stdin, several values, non-string path, NUL in path or cwd) = mode L/empty: the original separate jq calls run unchanged, so their exact bytes, bash NUL warnings and messages are kept.
cwd trailing newlines are stripped in bash (as `$(...)` did). Decision logic, messages, markers, audit rows untouched.

## Numbers (hyperfine -N, warmup 3, 20 runs, --input write.json)
| | mean +- sigma |
|---|---|
| before (old hook, mirror) | 20.7 +- 0.9 ms (22.1 +- 1.2 in the paired run) |
| after (new hook, mirror) | 14.9 +- 1.0 ms (paired run vs old: 1.48x faster) |
jq spawns 4 -> 1. bash -x trace lines 81 -> 113 (more shell lines, far fewer processes; trace-line count is NOT a spawn proxy here).

## Isomorphism proof
- Ordering preserved: yes. Recorder, parse verdict, path, empty-path allow, canonicalisation order are unchanged; only where the values come from changed.
- Tie-breaking unchanged: yes (file_path wins over notebook_path via the same `//` expression; false/null/absent falls through identically).
- Floating-point: N/A. RNG/hash seeds: N/A.
- Trust-boundary sanitisation unchanged: yes. strip_controls, cut_utf8_256, zone matching untouched; raw path bytes identical.
- Error/degraded paths unchanged: yes. Unparsable, empty, malformed, array, null/false, non-string path (incl. pretty-printed objects), NUL paths fall back to the old code or the same ask.
- Golden: 12 scenarios (plain, no .run, fresh marker, stale marker, claims authoritative, authoritative+marker, mode deny, telemetry, LOA_TEAM_MEMBER, override, features already seen, features base) x 101 payloads = 1212 runs per hook. stdout+stderr+rc+.run contents compared, timestamps normalised with a documented sed, mirror root replaced by @ROOT@, and bash "line N:" numbers normalised (the only raw difference: shifted line numbers inside bash NUL/redirect warnings). Result: IDENTICAL, 1212/1212. Checksums: golden/matrix.old + matrix.new in golden_checksums.txt.
  Payloads: all 6 files in payloads/, Edit, NotebookEdit-only, both fields, empty-string/null/false file_path with notebook_path, newline mid/end/double-end, tab, quote, backslash, NUL escape (src and docs), number/float/object/array/true/empty path, unicode/ZWSP, lone surrogate, invalid UTF-8, BOM, 600-byte path, ../ and uppercase paths, trust inputs, grimoires/.claude/src/lib/app/nested, abs paths, cwd missing/number/object/array/null/false/true/empty/relative/trailing-newlines/mid-newline/only-newline/NUL, active_skill with/without agent_id (string, empty, number, false), non-string skills, empty/ws/malformed/array/null/false/true/number/string/{} stdin, tool_input of every type, multi-value streams (incl. null last/first, bad tail), duplicate keys, bigint, 1 MB content (both zones).
- Tests: `npx --no-install bats` on implement-gate, compliance-hook, guard-origins, hook-wiring, run-checkpoint-derive, glossary-validator, guard-yield = 132/132 ok.

## Files changed
.claude/hooks/compliance/implement-gate.sh: new single-pass block + `_ig_lead_claim` before the recorder; parse check, file_path and payload_cwd extraction use the fields in mode F (the old calls remain as the fallback).

## Checked, found already optimal / out of scope
- The `jq -e '.active_skill_seen_at' FEATURES_FILE` runs only when the lead-claim test passes: not on the hot path.
- strip_controls/_ig_strip_seqs_init are lazy (built only for ask/log paths).
- Non-App-Zone allow exits before load_gate_config/yq; claims branch `jq -j active_skill` runs only in authoritative mode: left alone (not a payload spawn on the hot path).
- Remaining cost: two realpath spawns, dirname subshells, cat, compat-lib source (not touched).
## Not fixed
Authoritative-mode active_skill jq stays a separate spawn (only under claims: authoritative, and needs the exact -j/sentinel semantics); two `realpath` spawns could be one but that is outside this mission.
