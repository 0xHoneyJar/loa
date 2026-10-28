# Extreme-software-optimization loop, 22 passes (2026-10-27/28)

Branch `perf/eso-skill-loop-2026-10-27`, base main 9e23cbf84. Source of the per-pass facts: `.skill-loop-progress.md`, section "LOOP 2 (2026-10-27)". Source of the before/after table: the orchestrator's final re-baseline (`~/.cache/loa/eso-loop/final-table.tsv`), run with the same hyperfine commands as the loop's start.

## Method

- **Profile first.** Every pass starts from a hyperfine baseline and a `bash -x` timestamp trace (or cProfile for Python) and names the hotspot and its share of wall time before editing.
- **One lever per commit.** One technique per pass; a behaviour change counts as a failure even if it is an improvement. A pass is implemented only when impact x confidence / effort >= 2.0.
- **Old-versus-new parity.** Golden outputs (stdout, stderr, exit code, every written file) are captured before the edit and compared after. Mirrors of the old and new script run side by side over payload and fixture matrices that include control bytes, `|`, `<`, newlines, tabs, empty and malformed input, and missing tools.
- **Roles.** A Sonnet 5.5 implementer proposes the patch, the Fable 5.1 orchestrator verifies parity and applies or commits, and a fresh-context Opus 5.5 reviewer with a time budget gives APPROVE or CHANGES_REQUIRED before each commit.
- **Trust boundaries stay put.** Hooks keep their documented fail-open and fail-closed behaviour, untrusted bodies stay sanitised at surfacing, and security-sensitive levers scoring below 2.0 were not taken.

## Before and after

Mean wall time in ms, hyperfine, this host.

| Command | Baseline | Final | Touched by pass |
|---|---:|---:|---|
| repo-map-gen | 4658.4 | 1218.5 | 1, 2, 3, 20 |
| grimoire-index | 1818.9 | 826.2 | 4, 5, 8 |
| loa-status | 899.0 | 817.5 | 13, 14 |
| beads-health | 207.6 | 225.9 | not touched, host noise |
| upgrade-health (Setup) | 214.8 | 211.3 | 16 |
| cheval --help | 128.6 | 122.1 | 17 |
| SessionStart kf-surface | 487.6 | 15.4 | 6, 8 |
| SessionStart run-state | 29.7 | 17.6 | 11 |
| SessionStart context-class | 24.2 | 24.7 | not touched, host noise |
| SessionStart decisions | 17.1 | 17.0 | not touched, host noise |
| PreToolUse implement-gate | 35.4 | 23.1 | 8, 9 |
| PreToolUse notes-size-guard | 21.5 | 20.1 | 10 |
| PreToolUse zone-write-guard | 12.3 | 13.9 | not touched, host noise |
| PreToolUse block-destructive-bash | 15.5 | 18.5 | not touched, host noise |
| PostToolUse karpathy | 96.0 | 80.5 | 7, 19 |
| Stop run-mode-stop-guard | 23.6 | 13.6 | 18 |

## Per-pass results

| Pass | Target | Lever | Measured | Commit | Review |
|---:|---|---|---|---|---|
| 1 | repo-map-gen.sh, repo_map.py | one engine run emits md and json | 4.64 s to 2.30 s | 395795939 | APPROVE |
| 2 | repo_map.py PageRank | hoist loop-invariant sorted() (213,996 to 4,962 calls) | 2318 to 1695 ms | 1dcdf8a50 | APPROVE |
| 3 | repo_map.py build_map | file-to-names inverse index | 1748 to 1547 ms | 87a1c3c71 | APPROVE |
| 4 | grimoire-index.sh | one awk per family, no per-field san() spawns | 1459 to 522 ms; trace 7,402 to 1,793 lines | 08fa29222 | CHANGES_REQUIRED, fixed, accepted |
| 5 | grimoire-index.sh render_md | one jq program instead of up to 13 | 833 to 647 ms | d8ff5578f | APPROVE |
| 6 | loa-kf-surface.sh | single awk pass sanitises and formats | 478 to 16 ms | 5cfefb38c | APPROVE |
| 7 | run-checkpoint.sh cmd_read | one-jq fast path with verbatim fallback | 54.3 to 39.9 ms | 8da33669d | CHANGES_REQUIRED, fixed, accepted |
| 8 | compat-lib.sh | lazy capability probes | source 10.2 to 2.3 ms; implement-gate 31.8 to 22.3 ms | 5656dc402 | CHANGES_REQUIRED, fixed, accepted |
| 9 | implement-gate.sh | parse the payload once | 21.7 to 15.3 ms | 5f6ea7c17 | APPROVE |
| 10 | notes-size-guard.sh | fuse the parse gate and path read | 18.8 to 16.1 ms | 854ecfa9d | APPROVE |
| 11 | loa-run-state-surface.sh | one jq per state file | 22.8 to 16.5 ms | aa8c51b30 | APPROVE |
| 12 | audit-envelope verify-chain | no change, below the 2.0 bar | n/a | none | n/a |
| 13 | cache-manager.sh get_config | one yq read instead of probe plus read | get 66.0 to 56.7 ms; workflow-state 118.5 to 109.8 ms | 81b4a5c19 | APPROVE |
| 14 | loa-status.sh | memoise the agy opt-in read | 670.8 to 637.0 ms | d4ed6df63 | APPROVE |
| 15 | beads-health.sh --json | no change, `br doctor` floor | n/a | none | n/a |
| 16 | upgrade-health-check.sh | one yq probe instead of five | 223.0 to 208.4 ms | adf42ecec | APPROVE |
| 17 | cheval providers | lazy adapter imports | --help 122.5 to 114.7 ms | 6a534a7bb | APPROVE |
| 18 | push-notify-lib.sh | one yq instead of three | 23.0 to 15.3 ms | 726bd4f46 | APPROVE |
| 19 | karpathy hook | skip jq round-trips for charset-safe session ids | 79.2 to 75.8 ms | 8c782b0b3 | APPROVE |
| 20 | repo_map.py PageRank | list-indexed instead of dict-keyed | 1.564 to 1.141 s | c69cbcac3 | APPROVE |
| 21 | tests/unit symlink-farm helpers | one `ln` per PATH directory | helper call 2.0 to 0.09 s | 4072f194c | APPROVE |
| 22 | tests/unit/perf-spawn-budget.bats | spawn-count regression guard | 6 targets, 1.6 s | uncommitted | n/a |

Pass 22 adds no optimisation. It adds the guard, this report and the changelog entry.

## Per-event hook chains

| Event | Start | End | Floor or note |
|---|---:|---:|---|
| PreToolUse Write/Edit chain | about 78 ms | about 62 ms | implement-gate, notes-size-guard and zone-write-guard dominate |
| PostToolUse karpathy | 96 ms | about 80 ms | `br show` trust check is the floor |
| SessionStart chain | about 600 ms | about 112 ms | kf-surface was the bulk |
| Stop | about 26 ms | about 16 ms | |
| Setup (upgrade-health) | 214 ms | about 208 ms | `br doctor` is the floor |

## Documented no-change passes

- **Pass 12, audit-envelope verify-chain.** The cost is python startup, the `loa_cheval.audit_envelope` import and the trust-store check, which spawns a second python process for about 70 ms. The levers scored 1.0, 1.5 and 1.0, all below 2.0. Two of them touch a deliberate fail-closed boundary, so they were not taken.
- **Pass 15, beads-health --json.** `br doctor` is 76% of the time and is the `br` contract. The remaining 15 spawns are each 4 ms or less, and merging them scored 0.7 and 1.5 and would change the per-file BSD fallback chain.

## Accepted divergences (all documented in the pass entries)

- **grimoire-index, handoff row with a NUL byte.** The old `grep` treated the file as binary and emitted no rows. The new awk emits the sanitised row.
- **kf-surface, NUL in a symptom.** Stdout is identical, but bash's "ignored null byte" stderr warning no longer appears.
- **compat-lib `$(...)` re-probe.** A lazy probe inside a command substitution cannot reach the parent's cache, so each such call re-probes (+1.6 ms). Two looping scripts pre-warm; the trade-off is in the lib header.
- **Lazy provider adapters.** Submodule attributes such as `loa_cheval.providers.openai_adapter` are no longer bound as import side effects before first use. No in-tree reader relies on it, and an adapter import error now surfaces at first use of that type.

## Follow-ups found, out of scope

- The KF `**Symptom (short)**:` field variant is not parsed by loa-kf-surface.sh or grimoire-index.sh. A `## KF-abc:` heading does not reset `cur`, so its Symptom lands on the previous entry.
- loa-status makes six per-model yq ceiling reads (about 40 ms), and `agy_gate_warn_once` reads its node twice (about 25 ms).
- The grimoire-index decisions yq parse is the parser floor (about 175 ms).
- audit-envelope verify-chain runs once per chain file; batching the five calls into one python process is an interface change.
- profile-lib misses its cache for karpathy's `diff_lines_per_task` knob, so each call runs yq (about 7 ms each).
- `adversarial-review-companion.bats` exceeds 900 s, and `block-destructive-bash.bats` runs its corpus three times.
- cheval config parsing could use `yaml.CSafeLoader`; this risks changing error text.
- A `grep -q push_command` pre-check could skip yq in the Stop hook when the section is absent, pending an anchor and merge-key fixture.

## Regression guard

`tests/unit/perf-spawn-budget.bats` counts `PS4='+' bash -x` trace lines for six targets against fixed fixtures built under the test temp dir. Counts were identical over three consecutive runs per target.

| Target | Trace lines | External-tool lines | Set by pass |
|---|---:|---:|---|
| loa-kf-surface.sh, 5 entries | 34 | 2 | 6, 8 |
| grimoire-index.sh --tsv | 96 | 11 | 4, 5, 8 |
| implement-gate.sh, Write payload | 113 | 5 | 8, 9 |
| notes-size-guard.sh, non-NOTES payload | 26 | 3 | 10 |
| compat-lib.sh source | 15 | 0 | 8 |
| run-mode-stop-guard.sh, HALTED, push off | 78 | 2 | 18 |

The budget is measured plus 10% for trace lines and measured plus 2 for external-tool lines. The compat-lib test also asserts that no `uname`, `sed --version`, `sort -V`, `readlink -f`, `find -printf` or `stat -c` line appears. Tests skip when jq, yq or awk is missing, and the grimoire-index test also needs Mike Farah yq v4. A failure prints both counts and says to update the budget in the same commit with a reason.

## Gotchas

- zsh does not word-split unquoted variables; use arrays or `bash -c`.
- hyperfine 2.0 JSON keeps times in `.results[0].measurements[].time_wall_clock.value`, in seconds.
- A mirror directory built from symlinks lets `..` escape to the live tree. Mirror with real directories, or an A/B compares new against new.
- `.claude/checksums.json` must be refreshed per commit; passes 1 to 17 had left it stale until pass 18.
- Subagent final messages may not reach the orchestrator. Read the report files instead.
- With `PS4='+'` trace lines have no space after the plus, so match `^\++ ?tool`.
