# ESO skill-loop — implementer contract (read fully before touching code)

Repo: /home/merlin/Documents/thj/code/loa (branch perf/eso-skill-loop-2026-10-27). You are ONE pass of a 22-pass
extreme-software-optimization loop. The orchestrator commits; you do NOT run `git commit`, `git stash`, `git checkout`, or
`git add`. Scratch for this pass: ~/.cache/loa/eso-loop/pass-<K>/ (create it). Never write scratch files inside the repo.

## The One Rule
Profile first. Prove behavior unchanged. ONE lever (one optimization technique) per pass. Behavior change = failure, even if
"better". Only implement if Impact×Confidence/Effort ≥ 2.0.

## Mandatory loop (do every step, keep the evidence)
1. BASELINE  `hyperfine -N --warmup 3 --runs 10 [-i if the command exits nonzero by design] [--input payload.json for stdin hooks]
             --export-json ~/.cache/loa/eso-loop/pass-<K>/before.json '<command>'`. hyperfine 2.0 schema: times are in
             .results[0].measurements[].time_wall_clock.value (seconds).
2. PROFILE   bash: `PS4='+${EPOCHREALTIME} ${BASH_SOURCE##*/}:${LINENO} ' bash -x <script> 2>trace.txt` then rank gaps between
             consecutive timestamps (a trace-line count is also a proxy for process spawns). python: `python3 -m cProfile -o
             prof.out` + pstats sort tottime. Name the hotspot and its % of wall time BEFORE editing.
3. GOLDEN    Capture every observable output of the target BEFORE editing into ~/.cache/loa/eso-loop/pass-<K>/golden/:
             stdout, stderr, exit code, and every file the command writes — for EVERY mode/flag and a payload matrix for hooks
             (normal, empty stdin, malformed JSON, non-matching tool, oversized/adversarial field with control bytes, `|`, `<`,
             newline, tab). Reuse fixtures from the bats tests that cover the target. `sha256sum golden/* > golden_checksums.txt`
             (raw sha256sum is fine in scratch; NOT in repo scripts — see lint rules).
             If the output legitimately embeds a timestamp/pid, pin it (env override / fixed clock) or normalise with a
             documented sed and say so in the proof.
4. IMPLEMENT one lever. Surgical diff. Keep every comment block that documents contracts; update comments that describe
             the old implementation. Do not "fix" unrelated things, do not reformat, do not rename.
5. VERIFY    re-run the SAME capture → `sha256sum -c golden_checksums.txt` must pass 100%. Run the bats files that cover the
             target: `npx --no-install bats <files>` (bats 1.13 via npx; `bats` is NOT on PATH). Run pytest for python changes
             (`.claude/adapters/tests` for cheval; `tests/python` as relevant). Then hyperfine again → after.json.
6. REPORT    Write ~/.cache/loa/eso-loop/pass-<K>/REPORT.md with: opportunity-matrix row (Impact, Confidence, Effort, Score),
             hotspot evidence (% of wall time), before/after mean±σ (ms), the isomorphism proof (template below), golden result,
             tests run with pass counts, files changed and why, what you checked and found already optimal (≥3 items).

## Isomorphism proof template (fill every line)
- Ordering preserved: yes/no + why    - Tie-breaking unchanged: yes/no + why
- Floating-point: identical / N/A     - RNG / hash seeds: unchanged / N/A (PYTHONHASHSEED=0 is set by callers)
- Trust-boundary sanitisation (control bytes, length caps, `|`/`<`/`>` escaping) unchanged: yes + where
- Error/degraded paths (missing file, no jq/yq, bad input) exit codes + messages unchanged: yes + how verified
- Golden outputs: sha256sum -c golden_checksums.txt → N/N OK

## Repo rules that CI enforces (violations = failed pass)
- No raw `sha256sum`/`shasum` in repo scripts: use `sha256_portable` from .claude/scripts/compat-lib.sh.
- No output-swallowing jq shape (`jq … 2>/dev/null || true` / `|| echo`): use `jq_strict` from compat-lib.sh or keep the
  existing shape exactly. tools/check-no-swallowed-jq.sh --help explains.
- Portability: no bare `sed -i`, no `readlink -f` (use compat-lib helpers); scripts must stay bash-3.2/BSD-friendly where the
  surrounding file already is (no new `mapfile`, `${var,,}`, `declare -A` unless the file already uses them).
- Hooks are SAFETY/TRUST boundaries: they must still fail OPEN/CLOSED exactly as documented; untrusted bodies (known-failures,
  decisions, handoffs, notes) must remain sanitised at surfacing; never interpret their text.
- Determinism: keep `export LC_ALL=C`, `TZ=UTC`, `PYTHONHASHSEED=0` where present; generated files must be byte-identical.
- Zone model: you may edit .claude/ in THIS repo (it is the framework source). Do not touch grimoires/, .run/, .beads/ except
  through the target command's own regeneration. `git status` at the end must list only the intended source files.
- No new dependencies. Do not add timing-based tests (flaky in CI); a deterministic guard (e.g. trace-line/spawn budget) is OK
  only if the mission asks for it.

ALSO write the identical report to ~/.cache/loa/eso-loop/pass-<K>/REPORT.md (the orchestrator reads the FILE; chat messages may not arrive).
## Report back (final message) — the orchestrator and an independent reviewer read this
1. Files changed and why (file:line ranges)   2. Hotspot found + % of wall time   3. Before/after numbers
4. Golden result + tests run   5. Issues found in scope that you did NOT fix (and why)   6. ≥3 things checked and found correct
