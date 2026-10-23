# Security analysis working file — sprint-1 audit (PR: sprint-252 decision surfaces, part 1)

Phase 1A recon (sources / sinks in `pr/head.diff`), Phase 1B status after tracing. Lines are `head/<path>:<line>`.

## Untrusted sources

| # | Source | Trust | Status | Trace |
|---|--------|-------|--------|-------|
| S1 | CLI flags to `dec-write-lib.sh` (`--recorded-by`, `--file`, `--rewrite`, `--from`, `--answer-ref`, `--summary`…) `:92-109` | agent-controlled | CONFIRMED | `--recorded-by decisions-command` is the sole authz check `:359` (HIGH-002); `--file` skips `ci_blocked` `:250-253` (MED-001); `--rewrite`/`--from` uncontained `:649-655` (MED-002); text fields pass `san1` `:73` then `jq --arg` (SAFE) |
| S2 | Ledger rows (`grimoires/loa/decisions.yaml`) | agent-authored, UNTRUSTED | PARTIAL | hook `loa-decisions-surface.sh:68-75` strips/escapes/fences (SAFE); `grimoire-index.sh:189` and `dec-write-lib.sh:677-678` pass `<`/`>`/backtick/C1 (MED-003) |
| S3 | Pending file rows (`a2a/sprint-N/decisions-pending.yaml`) | worktree-agent-owned | CONFIRMED | `op_import :642-647` copies status/decided_by/transitions verbatim (HIGH-003) |
| S4 | `.run/unattended.json`, `.run/*state.json`, `LOA_UNATTENDED`, `LOA_FLATLINE_MODE`, `CLAUDE_SESSION_ID` | caller-controlled | CONFIRMED | signal set `:164-182` decides the confirm gate; `grep -q` under pipefail fails open `:184` (HIGH-001); env override flips marker `:157-158` (HIGH-002 support, MED-007) |
| S5 | PRD `**Status**` line `:177-180` | agent-authored | CONFIRMED | folded into `is_unattended` `:183` → operator attribution dropped (HIGH-004) |
| S6 | `.loa.config.yaml` (`decisions.*`) | operator | SAFE | numeric TTL validated `:142`; boolean compared literally (hook `:48`) |
| S7 | Interview transcript to `check-round-independence.sh` | agent/operator | SAFE | `jq --argjson` parse of untrusted JSON only; greedy regex is a correctness bug (LOW-004) |
| S8 | Flatline/dissent artifact path (`--as`, `--answer-ref flatline:|dissent:`) `:289-305` | agent | PARTIAL | `..`, prefix and shape checked; final symlink component unresolved (LOW-007) |

## Dangerous sinks

| # | Sink | Status | Notes |
|---|------|--------|-------|
| K1 | `yq -i` with `env(ROW)` / `strenv(ROWID)` `:386,:390` | SAFE | expression static; values via env |
| K2 | `jq` with `--arg`/`--argjson`/`--slurpfile` throughout | SAFE | no string interpolation into filters; `gsub($e.key…)` keys are `PEND-[0-9a-f]{8}` |
| K3 | `mv -f "$TMPF" "$TARGET"` `:419` | SAFE for default targets | target chosen by `--file` → see S1 |
| K4 | `awk gsub … > tmp; mv -f tmp "$p"` `:652-653` | CONFIRMED | any path, follows/replaces symlinks (MED-002) |
| K5 | `rm -f -- "$from"` `:655` | CONFIRMED | any path that validates (MED-002); race with pending writer (HIGH-007) |
| K6 | `cat > "$TARGET"` pending bootstrap `:264` | PARTIAL | before lock; speculative race (Observations, excluded_confirmed) |
| K7 | SessionStart stdout (hook) | SAFE | L6 fence required or nothing printed `:118-124` |
| K8 | INDEX.md / `.run/grimoire-index.json` / PR body / SDD-PRD appendices | CONFIRMED | unfenced untrusted text (MED-003) |
| K9 | `flock`/mkdir lock under `${PROJECT_ROOT}/.run` `:203-230` | PARTIAL | keyed by invoking checkout, so a worktree writer and the main import never contend (HIGH-007) |
| K10 | `exec 9>"$lp"` `:213` | SAFE | path under `.run`, hash-named |

## Second-order flows

- Stored rows → `list --format md` → operator's confirming session (decisions.md:52) → `confirm` write: unfenced text precedes the authz-relevant action (MED-003 + HIGH-002).
- Stored `supersede_proposed_by` pointer → later `supersede` refusal `:601`; validator `:656-657` never invalidates it (HIGH-006, MED-004).
- Pending rows → `import` → live ledger: imported ids are all `touched`, so `verify_and_swap` compares their content to nothing (HIGH-003).

## Deferred / out of scope

- Repo-wide `security-audit-scope.sh` catalog (193 exec sinks, 153 file sinks) — pre-existing code, not in the diff.
- Documentation-coherence subagent reports — none exist in this evaluation workspace (LOW-008).
- `br`, `shellcheck` not installed: no beads comment, no shellcheck pass.
