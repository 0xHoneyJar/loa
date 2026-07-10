# Loa hook-chain performance baseline — pass 1 of 10 (2026-07-05)

> Skill: `extreme-software-optimization` — loop step 1 (BASELINE) + 2 (PROFILE)
> + 3 (PROVE infrastructure). **No production script was modified in this pass.**

## Why this matters

Every tool call in a Loa session spawns fresh hook processes (registered in
`.claude/settings.json`): 2 PreToolUse + 1 PostToolUse per **Bash** call,
4 PreToolUse + 2 PostToolUse per **Write/Edit** call, 2 per Skill call, 2 per
Stop, 1 per user prompt. A working session issues hundreds of Bash calls and
tens-to-hundreds of Write/Edit calls, so per-hook milliseconds multiply into
whole seconds of dead time between every model turn and its tool result.

## Environment

| | |
|---|---|
| Host | Intel Core Ultra 7 268V, 8 CPUs, `powersave` governor (note: adds run-to-run variance; we report min/mean/p95 over 20 runs) |
| OS / kernel | Debian 13, Linux 6.16.12+deb13-amd64 |
| Shell / tools | bash 5.2.37, jq 1.7, yq v4.44.1 (mikefarah), GNU coreutils |
| Repo @ | `4ae8aa5f` (branch `feature/cycle-115-okf-followup-mempalace`) |
| Locale | `LC_ALL=C` pinned by the harness. A UTF-8 comparison row was attempted but the host has no `en_US.UTF-8` locale compiled; the `bash-benign-utf8` row is effectively a C-locale repeat. Grep-heavy hooks may be somewhat slower under UTF-8 locales — re-check if production env differs. |
| hyperfine | not installed → `bench.sh` (bash `$EPOCHREALTIME` loop, 3 warmup + 20 measured runs) |
| strace | **unusable**: `kernel.yama.ptrace_scope=2` denies `PTRACE_TRACEME` to unprivileged processes. Fork/exec census uses a PATH-shim interceptor instead (`exec-census.sh`) — exact for PATH-resolved spawns, blind to same-process builtins and pure subshell forks. |

## Method

- `bench-env.sh` builds a disposable mirror of the repo layout under
  `/tmp/loa-hookbench-$UID` containing **live copies** of every hook (hooks
  derive `PROJECT_ROOT` from `BASH_SOURCE`, so copying them re-roots all side
  effects into the mirror). Re-running it picks up working-tree edits, so
  later passes measure their changes with the same commands.
- `run-matrix.sh` times every hook × payload combo via `bench.sh` (fresh
  stdin payload fd per run) → `results.tsv`.
- `exec-census.sh` counts external-process spawns per invocation → `census.tsv`.
- `golden/capture.sh` captures normalized stdout+stderr+exit per combo;
  `golden/capture.sh --verify` is the mechanical parity gate for every later
  pass (see `golden/README.md`). Verified deterministic across mirror rebuilds.
- Payload field shapes were derived from what the hooks actually parse
  (`tool_input.command`, `tool_input.file_path/new_string/content`,
  `tool_input.skill`, `tool_result.exit_code`, `background_tasks`, …).
- Side effects (audit.jsonl appends, trajectory JSONL, karpathy state,
  marker deletes, context archiving, settings rewrites) all land in the
  mirror; the real repo's `.run/` and `grimoires/` were not touched by the
  harness. (`check-updates.sh` refreshes its normal `~/.loa/cache/` entry;
  `beads-health.sh` was benchmarked read-only `--json`/`--quick`.)

## Process-spawn floors (cost anatomy)

| Primitive | min | mean | p95 (ms) |
|---|---:|---:|---:|
| fork+exec tiny binary (`/usr/bin/true`) | 0.90 | 1.39 | 1.99 |
| `sh -c 'exit 0'` | 1.29 | 1.75 | 2.19 |
| `bash -c 'exit 0'` | 1.06 | 1.62 | 2.05 |
| `jq` startup (1-field parse) | 1.30 | 2.94 | 4.17 |
| `yq` startup (null input) | 2.04 | 3.74 | 6.69 |
| `git rev-parse --show-toplevel` | 0.66 | 0.96 | 1.73 |

Rule of thumb on this host: **every `echo | grep` costs ~2 ms** (2 forks +
1 exec), **every jq spawn ~3 ms**, **every yq spawn ~4–7 ms**. The hooks below
are almost pure spawn-count multiplied by these constants.

## Results — per hook × payload (ms, 20 runs each)

### PreToolUse:Bash (fires on EVERY Bash tool call)

| Hook / payload | mean | p95 | exit | child spawns |
|---|---:|---:|---|---|
| block-destructive-bash / benign `ls -la` | 39.87 | 49.65 | 0 | 17 (grep×15, jq, cat) |
| block-destructive-bash / mutating `git commit` | 44.38 | 51.87 | 0 | 17 |
| block-destructive-bash / destructive `rm -rf /tmp/x` (allowed) | 47.11 | 60.98 | 0 | 22 (grep×20) |
| block-destructive-bash / blocked `git push --force` | 36.19 | 42.81 | 2 | 12 (sed×4 = redactor) |
| team-role-guard / benign (single-agent: env early-exit) | 1.00 | 1.12 | 0 | 0 |
| team-role-guard / mutating + `LOA_TEAM_MEMBER` | 34.67 | 40.03 | 2 | 13 (grep×11) |

### PostToolUse:Bash

| Hook / payload | mean | p95 | exit | child spawns |
|---|---:|---:|---|---|
| mutation-logger / benign (no append) | 16.35 | 20.51 | 0 | 4 (jq×2, grep, cat) |
| mutation-logger / mutating (append + rotate check) | 29.34 | 33.44 | 0 | 9 (jq×3, stat×2) |

### PreToolUse:Write|Edit (4 hooks fire on EVERY Write/Edit)

| Hook / payload | mean | p95 | exit | child spawns |
|---|---:|---:|---|---|
| team-role-guard-write / grimoires (early-exit) | 1.85 | 2.72 | 0 | 0 |
| team-role-guard-write / grimoires + TEAM | 17.64 | 20.84 | 2 | — |
| spiral-dispatch-guard / grimoires (no sentinel) | 10.10 | 11.68 | 0 | 2 (jq, cat) |
| zone-write-guard / grimoires (ALLOW) | 30.04 | 36.59 | 0 | 7 (yq×2, date×2, realpath, jq, dirname) |
| zone-write-guard / .claude path (BLOCK) | 26.88 | 31.32 | 2 | 7 |
| zone-write-guard / edit-tests (unclassified ALLOW) | 34.77 | 46.34 | 0 | 7 |
| adversarial-review-gate / non-COMPLETED (early-exit) | 8.05 | 12.52 | 0 | 2 (jq, cat) |
| adversarial-review-gate / COMPLETED (full gate) | 36.48 | 45.57 | 2 | 11 (dirname×7, yq×2) |

### PostToolUse:Write|Edit (2 hooks fire on EVERY Write/Edit)

| Hook / payload | mean | p95 | exit | child spawns |
|---|---:|---:|---|---|
| write-mutation-logger / write | 19.38 | 26.84 | 0 | 6 (jq×3) |
| write-mutation-logger / edit | 21.80 | 25.69 | 0 | 6 |
| karpathy-surgical-diff / write, fresh state | 54.56 | 63.30 | 0 | — |
| **karpathy-surgical-diff / write, WARN regime** | **62.46** | **74.93** | 0 | 22 (jq×7, date×3, yq×2, wc×2, tr×2, …) |
| karpathy-surgical-diff / edit, WARN regime | 65.76 | 79.53 | 0 | 22 |

The WARN regime is this repo's **production steady state**: the real
`.run/karpathy-task-state.jsonl` holds 500+ entries, so the running total is
permanently above the default threshold (100) and every Write/Edit takes the
warn path (extra jq×2 + trajectory append).

### PreToolUse:Skill / Stop / UserPromptSubmit

| Hook / payload | mean | p95 | exit | child spawns |
|---|---:|---:|---|---|
| team-skill-guard / implement (early-exit) | 2.12 | 3.09 | 0 | 0 |
| team-skill-guard / implement + TEAM | 7.89 | 11.86 | 0 | — |
| spiral-skill-sentinel / implement | 10.28 | 11.59 | 0 | 2 (jq, cat) |
| run-mode-stop-guard / idle states | 33.73 | 42.68 | 0 | 8 (jq×7) |
| settings-cleanup / 2KB settings (early-exit) | 5.38 | 6.82 | 0 | 1 (stat) |
| settings-cleanup / >64KB settings (full path) | 89.81 | 102.09 | 0 | 35 (grep×24, jq×6) |
| post-compact-reminder / no marker (normal) | 3.39 | 4.09 | 0 | 0 |
| post-compact-reminder / marker present (one-shot) | 45.74 | 52.30 | 0 | 17 |
| cleanup-context / no context dir | 2.15 | 3.39 | 0 | — |
| cleanup-context / full archive (7 files) | 40.97 | 55.60 | 0 | — |

Note: this repo's real `settings.local.json` is 55 KB — 86% of the 64 KB
early-exit threshold. When it crosses, every Stop event pays ~90 ms.

### Workflow-boundary scripts (real repo, read-only)

| Script | mean | p95 | exit | notes |
|---|---:|---:|---|---|
| beads-health.sh --json | 107.52 | 117.12 | 4 (DEGRADED) | spawns `br --version` + `br doctor` |
| beads-health.sh --quick --json | 50.08 | 66.30 | 4 | |
| check-updates.sh --notify | 79.64 | 94.57 | 1 | cached path; on cache miss (24 h TTL) it performs a GitHub API call — timed with `--timeout 30`, network-dependent |
| `source golden-path.sh` | 85.63 | 102.19 | 0 | sources bootstrap + compat-lib + path-lib (~1,300 lines) |

## Headline: per-tool-call hook overhead (sum of registered chain)

| Tool call | hooks | mean | p95(sum) |
|---|---|---:|---:|
| **Bash** | block-destructive + team-role-guard + mutation-logger | **57.2 ms** | 71.3 ms |
| **Write** | trg-write + spiral-guard + zone-guard + adv-gate + write-mutation-logger + karpathy(warn) | **131.9 ms** | 165.3 ms |
| **Edit** | same chain, edit payloads | **142.3 ms** | 178.5 ms |
| Skill | team-skill-guard + spiral-skill-sentinel | 12.4 ms | 14.7 ms |
| Stop | run-mode-stop-guard + settings-cleanup(small) | 39.1 ms | 49.5 ms |
| UserPromptSubmit | post-compact-reminder | 3.4 ms | 4.1 ms |

These sums exclude Claude Code's own per-hook `sh -c` wrapper (~1.7 ms × N
hooks) — add ~5 ms/Bash call and ~10 ms/Write call for the true end-to-end
figure. **A representative 100-Bash + 40-Write session turn burns ≈ 11 s of
pure hook overhead.**

## Opportunity Matrix (Impact × Confidence ÷ Effort; implement only ≥ 2.0)

Ranked by expected absolute saving per session. "Impact" folds in call
frequency (per-call ms × calls/session). Line refs are to current `HEAD`.

| # | Hotspot | file:line | Lever (Tier 1 catalog) | I | C | E | Score | Est. saving |
|---|---------|-----------|------------------------|---|---|---|-------|-------------|
| 1 | 15–20 sequential `echo\|grep -qE` pattern dispatches on every Bash call | `.claude/hooks/safety/block-destructive-bash.sh:154-462` | fork-elimination: bash `[[ =~ ]]` (0 spawns) and/or one combined pre-filter grep that fast-paths the ~95% benign case | 5 | 4 | 2 | **10.0** | ~40 → ~8 ms per Bash call |
| 2 | 7 jq + 2 yq + wc/tr/dirname per Write/Edit (WARN steady state) | `.claude/hooks/quality/karpathy-surgical-diff-check.sh:39-129` (yq×2 @39/46; jq @54,56,65/68,79,97,118,121) | N+1→batch: single jq pass extracting tool_name+file+lines; single yq call for both config keys; fold FILES_MOD/TOOL_CALLS aggregation into the existing awk pass @87 | 5 | 5 | 2 | **12.5** | ~62 → ~12 ms per Write/Edit |
| 3 | 2 yq spawns + bash glob loop over ~30 zone patterns per Write/Edit | `.claude/hooks/safety/zone-write-guard.sh:121-149` (+date×2 @158/161) | batch: one yq emitting `zone TAB pattern` pairs (or a precompiled zones cache); one `date` reused | 4 | 4 | 2 | **8.0** | ~30 → ~10 ms per Write/Edit |
| 4 | stdin read + jq parse happens BEFORE the sentinel-file existence check that no-ops the hook 99.9% of the time | `.claude/hooks/safety/spiral-dispatch-guard.sh:23-41` | lazy eval: test `.run/spiral-dispatch-active` first (builtin, 0 spawns), parse stdin only if present | 3 | 5 | 1 | **15.0** | ~10 → ~1.5 ms per Write/Edit |
| 5 | 2 jq spawns to read 2 fields; `stat -f%z` (BSD form) always fails first on Linux → 2 stat spawns | `.claude/hooks/audit/mutation-logger.sh:35-36,72` | batch: one jq `@tsv` for command+exit_code; reorder stat fallback GNU-first | 3 | 5 | 1 | **15.0** | ~16 → ~8 ms per Bash call |
| 6 | 3 jq spawns (file_path, tool_name, emit) | `.claude/hooks/audit/write-mutation-logger.sh:29,37,48` | batch: single jq that parses AND emits the JSONL row | 3 | 5 | 1 | **15.0** | ~19 → ~8 ms per Write/Edit |
| 7 | 7 jq spawns: 1 bg-parse + 2 per state file × 3 files | `.claude/hooks/safety/run-mode-stop-guard.sh:47-101` | batch: one jq over stdin + all existing state files (`jq -n 'inputs'` or per-file single `@tsv`) | 3 | 5 | 1 | **15.0** | ~34 → ~8 ms per Stop |
| 8 | `cat` + jq spawn per Write/Edit just to discover "not a COMPLETED write" | `.claude/hooks/safety/adversarial-review-gate.sh:55-71` | lazy: cheap bash substring probe of raw payload for `/COMPLETED` before the jq parse (keep jq for the positive case) | 2 | 4 | 1 | **8.0** | ~8 → ~2 ms per Write/Edit |
| 9 | 4 Pre + 2 Post separate processes per Write/Edit; 6× stdin re-parse of the same payload | `.claude/settings.json` hooks registration + the 6 scripts | hook consolidation: one dispatcher per event parses stdin once and calls guard functions in-process. **System-Zone + settings change — needs cycle-level authorization; keep for a late pass** | 4 | 4 | 3 | **5.3** | ~15–25 ms per Write/Edit on top of #2–#6 |
| 10 | 24 grep spawns in post-cleanup secret scan (2 per pattern × 12) | `.claude/hooks/hygiene/settings-cleanup.sh:100-107` | batch: single `grep -E` with alternation (or drop the redundant `-qP`/`-qE` double-probe) | 2 | 5 | 2 | **5.0** | ~90 → ~40 ms per Stop (only when settings >64 KB; repo is at 55 KB and rising) |
| 11 | jq spawn per Skill call to read one field | `.claude/hooks/safety/spiral-skill-sentinel.sh:18-19` | bash substring check for `"spiraling"` before jq (skill payloads are small/trusted-shape) | 2 | 4 | 1 | **8.0** | ~10 → ~2 ms per Skill call |
| 12 | workflow-boundary scripts: beads-health 108 ms (br doctor), golden-path source 86 ms (1,300-line lib chain + yq), check-updates 80 ms | `.claude/scripts/beads/beads-health.sh`, `.claude/scripts/golden-path.sh:26-28`, `.claude/scripts/check-updates.sh` | needs its own profile pass (memoize path-lib resolution; cache br doctor within a session) | 3 | 3 | 3 | **3.0** | boundary events only |

Suggested pass order for passes 2–10: #2 (karpathy), #1 (block-destructive),
#3 (zone-guard), #4+#5+#6 (one lever each, trivial), #7+#8+#11, #10, #12,
then #9 (consolidation) last — it subsumes per-script wins and carries the
System-Zone governance cost. One lever per commit;
`golden/capture.sh --verify` + `run-matrix.sh` after each.

Projected steady state after #1–#8: **Bash call ≈ 18 ms (from 57), Write/Edit
≈ 42 ms (from 132–142)** — a ~68% cut without touching hook registration.

## Already fast — later passes should SKIP these paths

| Path | mean | why it's fine |
|---|---:|---|
| team-role-guard.sh single-agent early-exit | 1.0 ms | env-var test before stdin read; ~bash-startup floor |
| team-role-guard-write.sh single-agent early-exit | 1.8 ms | same pattern |
| team-skill-guard.sh single-agent early-exit | 2.1 ms | same pattern |
| post-compact-reminder.sh no-marker (the every-prompt path) | 3.4 ms | marker existence test only, 0 spawns |
| settings-cleanup.sh with <64 KB settings (today's path) | 5.4 ms | single stat + size branch |
| cleanup-context.sh missing-context early exit | 2.2 ms | dir test |
| adversarial-review-gate COMPLETED full path | 36 ms | fires once per sprint, not per call — leave it |
| post-compact-reminder marker path | 46 ms | one-shot after compaction |
| team-guard TEAM-mode paths | 8–35 ms | Agent-Teams mode only; not the default profile |

## Caveats / honesty notes

1. `powersave` governor → high run-to-run variance (some mins are ~2× below
   means). Rankings are stable; absolute numbers are conservative (agents in
   flight keep the CPU un-idle, closer to the mean than the min).
2. Census counts PATH-resolved child execs only (ptrace unavailable —
   yama ptrace_scope=2). Pure subshell forks (≈1 per `echo|grep`, ≈1 per
   `$(...)`) add ~0.4–0.8 ms each on top; directionally the spawn counts
   understate true fork totals by ~2×, uniformly.
3. The Write/Edit chain total uses the karpathy WARN regime (production
   steady state on this repo) and the zone-guard trajectory-append path
   (trajectory dir exists) — deliberate worst-typical, not best case.
4. `block-destructive/bash-benign-utf8` could not actually test a UTF-8
   locale (not compiled on host); treat locale sensitivity as unmeasured.
5. `post-compact-reminder` marker-path excludes the production
   `trajectory-gen.sh --condensed` sub-spawn (script not mirrored); the
   production marker path is slower than the 46 ms shown. One-shot, so low
   priority regardless.
6. beads-health exits 4 (DEGRADED) on this repo — that's today's real
   state; timings reflect the DEGRADED code path.
7. During this pass my own session tool calls appended (as designed) to the
   real repo's `.run/audit.jsonl` / karpathy state / trajectory logs — this
   is normal hook operation, not harness leakage; the harness itself writes
   only inside `/tmp/loa-hookbench-$UID` and this perf directory.

## Reproduction

```bash
grimoires/loa/perf/skill-loop-2026-07-05/run-matrix.sh          # timings → results.tsv
grimoires/loa/perf/skill-loop-2026-07-05/exec-census.sh         # spawn census → census.tsv
grimoires/loa/perf/skill-loop-2026-07-05/golden/capture.sh --verify   # behavior parity gate
```
