# Security analysis working file — sprint-1 audit, 2026-10-22

Scope: `pr/head.diff` (sprint-252 decision surfaces, part 1). `security-audit-scope.sh --json` found 0 sources / 0 sinks (app-tuned); entries below are hand-catalogued. Status: PENDING → CONFIRMED / SAFE / PARTIAL / N/A.

## Sources (untrusted entry points)

| # | file:line | Source | Trust | Status | Note |
|---|-----------|--------|-------|--------|------|
| S1 | `head/.claude/scripts/lib/dec-write-lib.sh:92-109` | CLI flags from any Bash caller (`--recorded-by`, `--answer-ref`, `--as`, `--file`, `--from`, `--rewrite`, free text) | untrusted (agent) | CONFIRMED | `--recorded-by decisions-command` is the operator gate → HIGH-001 |
| S2 | `head/.claude/scripts/lib/dec-write-lib.sh:629` | pending file rows (`import --from`) | untrusted (worktree agent) | CONFIRMED | state not re-derived → MED-001; unlocked during snapshot → MED-002 |
| S3 | `head/.claude/scripts/lib/dec-write-lib.sh:177-180` | `grimoires/loa/prd.md` `**Status:**` line | agent-written state | CONFIRMED | non-live signal misattributes operator confirm → HIGH-002 |
| S4 | `head/.claude/scripts/lib/dec-write-lib.sh:166-176` | `.run/unattended.json`, `sprint-plan-state.json`, env `LOA_UNATTENDED`, `LOA_FLATLINE_MODE` | agent-writable | SAFE (fail-closed: more signals ⇒ more restrictive); `--clear` only partial → MED-003 |
| S5 | `head/.claude/hooks/session-start/loa-decisions-surface.sh:61-76` | ledger rows surfaced into session context | untrusted (agent-authored) | SAFE | id reduced to `[A-Za-z0-9-]{0,16}`, summary control-stripped, `<>` and backtick replaced, 100-char cap, L6 fence, 2000-char cap; no output without the sanitizer |
| S6 | `head/.claude/scripts/lib/dec-write-lib.sh:674-699` | ledger rows in `list --format md/tsv` | untrusted | PARTIAL | control chars stripped, pipes escaped, no fence → LOW-001 |
| S7 | `head/.claude/scripts/grimoire-index.sh:177-193` | ledger rows into INDEX.md | untrusted | PARTIAL | control chars stripped, 160 cap, no fence → LOW-001 |
| S8 | `head/tools/check-round-independence.sh:59-80` | interview transcript blocks | untrusted text | SAFE | regex-bounded, round number digits only, array only via `--argjson` after jq shape check; greedy regex → LOW-006 |
| S9 | `head/.claude/scripts/lib/dec-write-lib.sh:289-305` | `flatline:`/`dissent:` artifact paths | untrusted | PARTIAL | `..` rejected, prefix check on canonical dir, but final component may be a symlink → LOW-002 |
| S10 | `head/.claude/scripts/validate-artifact.sh:160-196` | candidate ledger + `--base-file` | writer-supplied | SAFE | parsed by yq, compared in jq via `--slurpfile`; PII filter |

## Sinks (dangerous operations)

| # | file:line | Sink | Status | Note |
|---|-----------|------|--------|------|
| K1 | `dec-write-lib.sh:386,390` | `yq -i` with `env(ROW)`/`strenv(ROWID)` | SAFE | no interpolation; ROW is jq-built JSON |
| K2 | `dec-write-lib.sh:419` | `mv -f "$TMPF" "$TARGET"` | SAFE | after verify + validator; `--file` lets a caller target any YAML, by design (test seam, CI-exempt) |
| K3 | `dec-write-lib.sh:652-653` | awk `gsub(k, m[k])` + `mv -f` over `--rewrite` paths | SAFE | keys are `PEND-[0-9a-f]{8}` only; paths unconstrained but lead-supplied |
| K4 | `dec-write-lib.sh:655` | `rm -f -- "$from"` | CONFIRMED | race → MED-002; retry duplication → LOW-003 |
| K5 | `dec-write-lib.sh:718` | `rm -f -- .run/unattended.json` | CONFIRMED | gate is the spoofable flag → HIGH-001; partial clear → MED-003 |
| K6 | `dec-write-lib.sh:536-540` | write `decided_by`/`status: decided` | CONFIRMED | HIGH-001 (forgeable), HIGH-002 (misattributed) |
| K7 | `dec-write-lib.sh:580-585` | write `status: rejected` | CONFIRMED | dangling pointer → HIGH-003 |
| K8 | `dec-write-lib.sh:213-214,218-229` | flock / mkdir lock under `.run` | SAFE | bounded wait, stale check on pid + age |
| K9 | `loa-decisions-surface.sh:118-124` | stdout → SessionStart context | SAFE | L6 fence or nothing |
| K10 | `user-invoked-harness.bats:148-150` | `claude -p … --tools Skill` from unit tests | CONFIRMED | live agent run in the unit suite → MED-004 |
| K11 | `.claude/hooks/safety/block-destructive-bash.sh:1464-1475` (base) | spike-branch force-delete unlocked by a `decided` ledger row | CONFIRMED (impact of HIGH-001) | consumer of forged rows |

## Auth surfaces

| # | file:line | Check | Status |
|---|-----------|-------|--------|
| A1 | `dec-write-lib.sh:359` `is_operator_call` | string equality on a flag | CONFIRMED weak → HIGH-001 |
| A2 | `dec-write-lib.sh:509` `live_run_signal` | refuses confirm under live signals | PARTIAL (cleared by A1's flag) |
| A3 | `validate-artifact.sh:683,686` | refuses `decided_by operator` written under a live signal | SAFE (narrow) |
| A4 | `decisions.md:4` `disable-model-invocation` | Skill-tool only | PARTIAL (Bash tool unaffected) |
| A5 | `tests/unit/dec-write-lib.bats:547-562` | prose scan for the flag string | N/A as a control |

## Deferred

- Concurrent-writer reproduction of K4 (MED-002): not run; confirmed from code.
- `shellcheck`: not installed in this workspace.
