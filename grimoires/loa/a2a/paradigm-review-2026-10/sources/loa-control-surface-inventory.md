# Loa control-surface inventory: scaffolding vs guardrail

Verified against `main` @ 864069f2 (v2.0.0-rc.4, cycle-128 shipped), read 2026-10-14. Read-only sweep. The only command executed beyond reads was `tools/check-prompt-budget.sh --json` (local, read-only). Local untracked state (`.run/`, `grimoires/loa/a2a/`) is cited where it is the only evidence; those files are gitignored and exist on this host only.

Prior file `grimoires/loa/a2a/skills-review-2026-10/sources/loa-gate-evidence.md` (rc.3, 76e7650b) was re-checked. Its implement-gate cites still hold (`.claude/hooks/compliance/implement-gate.sh:162,170,246,272,293,390,442,449`). Shifted cites: adversarial-review-gate block is now `:202-236` (was 202-214); Karpathy "refactor the unbroken" is `karpathy-principles.md:79` (was 76) and "failing repro test first" is `:89` (was 86), runnable check `:92`. Superseded finding: prior G1 said nothing checks that a bug test failed before the fix. Cycle-128 added `red-test-check.sh` and a two-commit micro-sprint rule (`.claude/scripts/red-test-check.sh:3-20`, `.claude/skills/bug-triaging/resources/templates/micro-sprint.md:32,43`, `.claude/skills/reviewing-code/SKILL.md:218`). Still true: `implementing-tasks/SKILL.md:28` says app `permission: read` while `:76` says app zone is Read/Write.

Legend. **HARNESS**: a hook, permission rule, `disallowed-tools` or `disable-model-invocation`; the model cannot override it. **SCRIPT**: a script verifies an artifact or state; note whether its invocation is itself prose. **PROSE**: the model is asked to comply. Verdict: **EARNS** (guards a recently observed failure), **SCAFFOLD** (compensates for a weakness with no recent evidence, or does not function), **AMBIGUOUS**.

## Cross-cutting evidence used below

- **E1, review and audit catch real defects on 2026 models.** Every cycle-128 sprint failed round 1 of review or audit. Opus 5.5 implementers, Fable 5.1 reviewers. Sprint 252 review r1 CHANGES_REQUIRED 0/0/4/1 (`grimoires/loa/a2a/sprint-252/engineer-feedback-r1.md:21-39`, trailer last line). Sprint 253 review r1 HIGH "research subagent writes while it reads untrusted web content" (`sprint-253/engineer-feedback-r1.md:24-31`); audit r1 HIGH-001 arbitrary execution in `chart-unblock-probe.sh`, "dissent DISS-002 and DISS-C-007, confirmed" (`sprint-253/auditor-sprint-feedback-r1.md:37-39`). Sprint 254 review r2 APPROVED, then audit r1 HIGH-001 "`red-test-check.sh` is an unbounded, credentialed execution path", "Dissent DISS-001, DISS-C-001 and DISS-C-002, confirmed" (`sprint-254/auditor-sprint-feedback-r1.md:33-35`). Bridgebuilder on PR #1279: 17 findings fixed, 4 refuted (commit 3758ddd0 message).
- **E2, the new HIGHs were all in guard code.** All three cycle-128 HIGHs are trust-boundary defects in newly written control surfaces (researcher agent, unblock probe, red-test check). Building guards generates review load.
- **E3, prose run-state is not maintained.** `.run/circuit-breaker.json:1-23` was written once (mtime 2026-10-13 11:58 +1100) and never updated: `cycle_count.current: 0`, `history: []`, `timeout.limit_hours: 48`, despite five CHANGES_REQUIRED rounds across 252-254. `.run/sprint-plan-state.json` reads `state: RUNNING` with a `jacked_out` timestamp, `sprints.completed: 1` while all three list entries are `completed`, and sprint-2 `cycles: 0`.
- **E4, fence friction.** `.run/audit.jsonl` holds 500 `block` rows from 2026-09-17 to 2026-10-14. 395 are bats fixture replays (identical commands in multiples of 11, written to the live log, the KF-033 class). Of the 105 real-session blocks, 96 involve a heredoc body or a scratch or worktree path. The other 9 are text mentions (FR-MERGE-2 on a `br`/KF note, FR-2 on a `grep` of test text), framework self-dev edits, two FR-NOTES and one `git branch -D` of a stale local main. No real-session block in the window stopped an unintended destructive action. This sweep was itself blocked once (P2) for quoting a force-push string inside a Python heredoc. Recorded gotchas: `grimoires/loa/NOTES.md:130,166,182`; documented FP `hooks-reference.md:199` ("Prose that names a spike merge inside a heredoc body is a known false positive"). Pre-relaxation baseline passed 14 of 46 benign commands (`tests/fixtures/fence-corpus/baseline.json:4-5`).
- **E5, harness classifier friction.** KF-042 (recurrence 1, 2026-10-13): auto mode denied four Loa cycle operations as Self-Modification and stopped the cycle at kickoff (`grimoires/loa/known-failures.md:1675-1694`; `NOTES.md:24,32`).
- **E6, KF ledger is infrastructure-heavy.** Of 42 KF entries, only KF-019 (recurrence 1, attested downstream) is an agent-reasoning failure (`known-failures.md:1130-1157`). High recurrences are multi-model plumbing: KF-004 (31), KF-037 (9), KF-002 (5), KF-022 (4), KF-041 (3), KF-036 (3) (`grimoires/loa/INDEX.md:147-187`).

## A. Always-on prompt surface

| Surface: what it does | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| `CLAUDE.loa.md` NEVER/ALWAYS/Teams/Merge tables (`.claude/loa/CLAUDE.loa.md:66-131`): process rules generated from `constraints.json` | PROSE | Code outside the cycle, skipped gates, TaskCreate misuse | E1 shows gates matter, but these rows describe gates, they do not run them | 10,225 B every turn, 15 B under the 10,240 cap (check-prompt-budget JSON) | none | AMBIGUOUS: the rows that point at a mechanism earn; the prose-only rows (section F) have no observed failure |
| Karpathy principles (`CLAUDE.loa.md:58-64`; `.claude/protocols/karpathy-principles.md`, 6,502 B) | PROSE | Over-building, drive-by refactors, untested logic | Review flags exist (`reviewing-code/SKILL.md:220`); no cycle-128 finding is tagged SIMPLICITY/SURGICAL | ~1 KB per turn in CLAUDE.loa.md | `karpathy_principles.simplicity_intensity` (`.loa.config.yaml.example:2852`) | AMBIGUOUS: frontier models over-build less, and no recent tagged finding |
| Always-loaded rule files `stash-safety.md`, `skill-invariants.md` (no `paths:` frontmatter) | PROSE | Stash data loss (#555), agent-type write refusal (#553) | Both mechanized: FR-1.2b in the fence, `validate-skill-capabilities.sh` in CI (`skill-invariants.md:27-31`) | 7,301 B every turn (2,180 + 5,121) | none | SCAFFOLD: the text restates checks that already run mechanically |
| KF SessionStart table (`.claude/hooks/loa-kf-surface.sh:7,61`) | SCRIPT (injects prose) | Re-trying documented dead ends | E6: entries are plumbing, mostly RESOLVED | 5,168 B per session start (measured) | `known_failures.surface_at_session_start` default false (`.loa.config.yaml.example:289`); true in this repo | AMBIGUOUS: useful for framework devs, low value for agent behavior |
| Other SessionStart surfaces: decisions (default off), run-state, context-class, L6 handoffs, L7 soul, session title, update check (`.claude/settings.json:474-524`) | SCRIPT | Lost run context, stale framework | Run-state stays silent unless HALTED or idle 12h (`hooks-reference.md:175`) | 8 hooks per start; silent when off | `decisions.surface_at_session_start` (`:302`), `structured_handoff.enabled: false` (`:2887`) | AMBIGUOUS: cheap when silent |
| Post-compact and session-limit reminders (`.claude/settings.json:536-549`; `hooks-reference.md:11-62`) | SCRIPT (injects prose) | Losing run state after compaction or a usage cap | KF-038 (recurrence 2) usage-window hits mid-run | Silent unless marker present | none | EARNS: usage caps still occur |

## B. Harness hooks and permissions

| Surface: what it does | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| `block-destructive-bash.sh` fence (1,992 lines): 32 pattern IDs over 41 block sites (`.claude/hooks/safety/block-destructive-bash.sh:576-1986`) | HARNESS (exit 2) | Destructive git/rm/SQL/kubectl; System-Zone Bash writes | E4: zero real catches in 4 weeks; #555 stash loss was real and recurred in cycle-122 (`.claude/rules/stash-safety.md`, Origin section) | 105 real blocks in 4 weeks, 96 likely FP; p95 latency budget 80 ms (`hooks-reference.md:260`); accepted bypasses listed `:260` | per-rule env only: `LOA_ALLOW_GIT_TAG=1`, `LOA_ALLOW_STATE_ZONE_EXEC_WRITE=1` (`:254`); no config key | AMBIGUOUS: insurance for rare catastrophes, high observed FP rate |
| Fence SP-1 and FR-1.1 spike unlock (cycle-128; `hooks-reference.md:199-200`) | HARNESS | Spike code entering another branch | No spike merge attempt recorded; 5 real SP-1 blocks, all heredoc bodies (E4) | Review and audit time: sprint-253 audit MEDIUM-002/003 and review item 8 were SP-1 gaps (`sprint-253/auditor-sprint-feedback-r1.md:51-64`) | none | SCAFFOLD: guards a hypothetical, has only produced FPs and review work |
| Permission deny list, 62 entries (`.claude/settings.json:397-460`) plus credential template (`.claude/hooks/settings.deny.json`) | HARNESS | sudo, disk wipes, curl-pipe-shell, cron/skill tamper | no recent evidence found | Zero runtime cost | install via `install-deny-rules.sh` (`hooks-reference.md:131-132`) | EARNS as cheap insurance, not on evidence |
| `zone-write-guard.sh` (`.claude/hooks/safety/zone-write-guard.sh:10-44`) | HARNESS (exit 2) | Writes into framework zone from project work | Lifetime 586 BLOCK, 2,622 ALLOW, 370 marker, 43 bypass (`grimoires/loa/a2a/trajectory/zone-guard-*.jsonl`); BLOCKs cluster on framework self-dev days (251 on 2026-07-05); none after 2026-10-05 | Self-dev needs a dated marker file each cycle (`NOTES.md:22`); creating it was a KF-042 denial | `LOA_ZONE_GUARD_BYPASS=1`, `LOA_ZONE_GUARD_DISABLE=1`, marker (`zone-write-guard.sh:26-33`) | AMBIGUOUS: protects downstream vendored copies, pure friction in this repo |
| `implement-gate.sh` (`.claude/hooks/compliance/implement-gate.sh:5-12,442-449`) | HARNESS (ask only) | App-Zone writes outside a run | Ask was dead from cycle-050 to rc.3 (`CHANGELOG.md:118`); `.run/audit.jsonl` has 1 `compliance.state_write` row; asks are not logged | Bash writes unseen; trusts Bash-writable `.run/` (`hooks-reference.md:246`); E3 shows `sprint-plan-state.json` left RUNNING after ship, so the gate would allow | `implement_gate.mode` exists but is absent from the example (`hooks-reference.md:223`) | SCAFFOLD: never blocks, trusts state the model writes, was inert for years unnoticed |
| `adversarial-review-gate.sh` (`.claude/hooks/safety/adversarial-review-gate.sh:5-24,202-236`) | HARNESS (exit 2) | COMPLETED written without cross-model dissent | Header cites the real class "skills execute inline and silently skip Phase 2.5" (`:10-11`); cycle-128 dissent produced two confirmed audit HIGHs (E1) | Bug-dir path friction (`NOTES.md:130`) | `flatline_protocol.code_review.enabled: false` and `security_audit.enabled: false` in the example (`.loa.config.yaml.example:1453,1508`); env `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` (`:24`) | EARNS here, but OFF by default for downstream installs |
| `spiral-dispatch-guard.sh` (`.claude/hooks/safety/spiral-dispatch-guard.sh:5-13,105`) | HARNESS (exit 2) | Inline implementation under `/spiraling` | Memory and the rule text record the fox-guarding-henhouse class (`CLAUDE.loa.md:78`); no 2026-10 instance | No jq spawn when sentinel absent (`:21-25`) | none | AMBIGUOUS: cheap, rarely armed |
| `notes-size-guard.sh` and FR-NOTES (`.claude/hooks/safety/notes-size-guard.sh:3-14`) | HARNESS | NOTES.md growth past 200 KiB | NOTES.md is 170,429 B now; 2 real FR-NOTES blocks (E4) | low | none | EARNS: the file approaches the cap each cycle |
| Team guards: `team-role-guard.sh`, `-write.sh`, `team-skill-guard.sh` (`.claude/settings.json:569-614`) | HARNESS when armed | Teammates running beads, git, `.run/` writes, planning skills | In this live teammate session `LOA_TEAM_MEMBER` is unset, so all three are no-ops (`team-role-guard.sh:12,41`); the lead must export it (`agent-teams-reference.md:329`) | 3 hooks per tool call | env only | SCAFFOLD: inert under Claude Code native teams, so the C-TEAM rows are prose in practice |
| FR-8 `disable-model-invocation` on 8 commands (`.claude/data/user-invoked-commands.txt:6-13`) | HARNESS (Skill tool refuses) | Model running `/decisions`, `/contribute`, `/run-halt`, `/loa-eject` | Task 1.0 harness check verified live (`NOTES.md:19`) | none | `LOA_HARNESS_CHECK=0` skips the live test (`hooks-reference.md:202`) | EARNS: zero-cost, harness-enforced operator boundary |
| `disallowed-tools` (`reviewing-code/SKILL.md:8-9`, `auditing-security`, `red-teaming`, `bridgebuilder-review`) | HARNESS | Review skills editing code | Only NotebookEdit and git add/commit/push are removed; no skill strips Write or Edit | none | none | SCAFFOLD: the barrier it names does not exist for Write/Edit |
| Review-skill Bash allowlist (`reviewing-code/SKILL.md:6`) | HARNESS [ASSUMPTION: whether `allowed-tools` restricts or only pre-approves is a harness question] | Review running arbitrary shell | E1/E2: granting `red-test-check.sh` to review was the sprint-254 audit HIGH | none | none | EARNS if it restricts |
| `hook-guard.sh` wrapper (`.claude/hooks/hook-guard.sh:3-12`) | HARNESS meta | A syntax-broken hook bricking Bash (#1180) | #1180 was real (2026-07-06, memory index) | one `bash -n` per call | none | EARNS: protects the other hooks' availability |
| Stop guard (`.claude/hooks/safety/run-mode-stop-guard.sh:6-8,72-76`) | HARNESS (soft block) | Stopping mid-run, orphaned background tasks | Operator gotcha: counts idle teammates (operator memory, cycle-128) | Soft block each Stop while a run is active | `notifications.push_command` (`hooks-reference.md:109`) | AMBIGUOUS |

## C. PostToolUse and logging

| Surface | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| `karpathy-surgical-diff-check.sh`, 848 lines (`.claude/hooks/quality/karpathy-surgical-diff-check.sh:5-12`) | HARNESS hook, warn-only | Oversized diffs | `.run/karpathy-task-state.jsonl` running total 143,324 lines against a 100-line threshold (last row 2026-10-13T14:11Z), so it warns on every write; it writes stderr with exit 0, which Loa documents as transcript-only (`loa-kf-surface.sh:11`) | 603 KB state file, 3,010 rows, a hook spawn per write | `karpathy_principles.surgical_diff_warning` (`.loa.config.yaml.example:2857`), `diff_lines_per_task` (`:2864`) | SCAFFOLD: the model never sees it and the signal saturated |
| `mutation-logger.sh`, `write-mutation-logger.sh` (`.claude/settings.json:622-649`) | SCRIPT (audit log) | Untraceable mutations | Log is polluted by bats replays (E4; KF-033 recurrence 1) | 3 hooks per call | none | AMBIGUOUS: forensic value reduced by test pollution |
| `permission-audit.sh log` (`.claude/settings.json:675-684`) | SCRIPT | HITL prompt analysis | no recent evidence found | async | none | AMBIGUOUS |

## D. Plan phase

| Surface | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| Flatline on PRD/SDD/sprint (`.loa.config.yaml.example:1401-1412`) | SCRIPT, invocation prose | Planning defects before build | cycle-128: PRD 3 blockers, SDD 7 (forgeable attribution, agent-clearable marker), sprint 4 (`NOTES.md:21`); every run in KF-041 degraded shape (recurrence 3) | Provider plumbing: KF-037 (9), KF-038 (2), KF-041 (3) | `flatline_protocol.enabled`, `phases.prd/sdd/sprint` (`:1403-1412`) | EARNS: blockers became shipped design decisions |
| `validate-artifact.sh` prd/sdd/sprint/decisions/map/glossary (1,451 lines) | SCRIPT, invocation prose (`planning-sprints/SKILL.md:340`, `discovering-requirements/SKILL.md:331`, `designing-architecture/SKILL.md:343`) | Malformed artifacts, untagged assumptions | CI gate false positive on `role: planning` (`NOTES.md:8`) | Each new rule is a dated migration (`CHANGELOG.md:71-74`) | none | AMBIGUOUS |
| Decision ledger: `dec-write-lib.sh` (792 lines), `/decisions`, `[ASSUMPTION decision]` tags (`.claude/scripts/lib/dec-write-lib.sh:3-20`) | SCRIPT plus HARNESS (FR-8) | Agent decisions passing as operator decisions | Born from Flatline SDD blockers (`NOTES.md:21`) | `grimoires/loa/decisions.yaml` is 173,930 B; all 124 rows are `proposed`, none operator-confirmed; yq v4 hard dependency (`CHANGELOG.md:73`) | `decisions.*` (`.loa.config.yaml.example:297-303`) | AMBIGUOUS: the attribution need is real; the operator backlog shows the review half is not happening |
| `/chart`, `chart-guard.sh`, `chart-ticket.sh` (653 lines) (`hooks-reference.md:201`) | SCRIPT | Multi-cycle efforts started unattended | Two of three cycle-128 HIGHs were in this surface (E1) | 4 new scripts plus an agent | none | AMBIGUOUS: new, no usage yet |
| Interview rounds and fact/decision split (`CHANGELOG.md:20-22`) | PROSE plus `check-round-independence.sh` | Over-asking the operator | no recent evidence found | prose in discovery skill | `interview.pacing` (`.loa.config.yaml.example:104`) | AMBIGUOUS |
| Glossary plus `check-glossary-terms.sh` CI (`.claude/loa/GLOSSARY.md`, 81 lines; `CHANGELOG.md:37-39`) | SCRIPT (CI) | Undefined jargon in CLAUDE.loa.md | no recent evidence found | mounted into every project; allowlist up to 30 | none | SCAFFOLD: vocabulary hygiene, not a model failure |
| Seams Under Test table (`CHANGELOG.md:40,72`) | SCRIPT (validator) | Untested seams | no recent evidence found | Required in every sprint block from 2026-10-13 | none | AMBIGUOUS |

## E. Implement phase

| Surface | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| `implementing-tasks` prose: tests, report format (`implementing-tasks/SKILL.md:151,162,164`) | PROSE | Untested code, missing reports | E1 findings were mostly test gaps and boundaries, which suggests tests alone do not catch them | 16,274 B per invocation | none | EARNS as the work spec |
| AC Verification gate plus `validate-ac-verification.sh` (`implementing-tasks/SKILL.md:166-171`; script `:3-14`) | SCRIPT, invocation prose | Silently skipped acceptance criteria | Script rejects `--sprint-id sprint-bug-N` (`NOTES.md:130`); header admits it cannot catch fabricated evidence (`:10-14`) | Reviewers read the walkthrough anyway (`reviewing-code/SKILL.md:238-241`) | none | AMBIGUOUS: duplicates reviewer reading |
| Goal-driven gate (`implementing-tasks/SKILL.md:190-192`) | PROSE | Building without success criteria | no recent evidence found | small | `karpathy_principles.require_success_criteria` (`.loa.config.yaml.example:2875`) | SCAFFOLD |
| Input guardrails and danger level, `@skill-include input_guardrails` (`.claude/data/skill-includes/input_guardrails.md`) | SCRIPT invoked by prose | PII, prompt injection, high-risk autonomous skills | 82 events: PII and injection checks PASS on all 74; all 7 BLOCKs were `danger_level` on run-mode, reviewing-code and auditing-security themselves (`grimoires/loa/a2a/trajectory/guardrails-*.jsonl`) | Write a temp file plus a script call per skill run | `guardrails.input.enabled` (`.loa.config.yaml.example:1280-1283`), `guardrails.danger_level.enforce` (`:1328-1329`) | SCAFFOLD: zero catches, blocks only the sanctioned path |
| Invisible retrospective postlude (`@skill-include retrospective_postlude`) | PROSE | Lost learnings | no recent evidence found | ~420 B in 3 golden skills | `invisible_retrospective.enabled` (`:1355-1357`) | SCAFFOLD |
| `red-test-check.sh` (616 lines) and two-commit rule (`red-test-check.sh:3-20`) | SCRIPT, invocation prose (`reviewing-code/SKILL.md:218`) | Bug test that never failed before the fix | New. Its first review produced a HIGH against itself (E1) | runner allowlist, `env -i`, worktrees | `red_test.*` commented (`.loa.config.yaml.example:2896-2909`) | AMBIGUOUS: plausible target, no run history yet |

## F. Review, audit, post-PR

| Surface | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| `/review-sprint` and `/audit-sprint` as separate passes (`reviewing-code`, `auditing-security` SKILL.md) | PROSE driving a model | Shipping defects | E1: 3 HIGHs and many MEDIUMs across 252-254; audit found a HIGH after review approved sprint 254 | 16,306 B and 16,268 B per run; two rounds each per sprint | none | EARNS: the strongest recent evidence in the repo |
| `LOA-VERDICT` trailer plus `verdict-derive.sh` (`.claude/scripts/verdict-derive.sh:7-28`) | SCRIPT, invocation prose (`reviewing-code/SKILL.md:257-259`), consumed by `golden-path.sh` | Prose and verdict disagreeing; approval with highs | Gotcha: approved review must start with `All good` (operator memory, cycle-128) | small | none | EARNS: cheap, machine-readable |
| Two-voice dissent `adversarial-review.sh` (4,510 lines) | SCRIPT | Single-model blind spots | Two cycle-128 audit HIGHs confirmed from dissent (E1); sprint-252 DISS-001 BLOCKING refuted (`NOTES.md:18`) | Highest-recurrence KFs are this plumbing: KF-004 (31), KF-037 (9), KF-002 (5); dissent capped at 3 runs per sprint | `companion_voice` (`.loa.config.yaml.example:1477,1516`), `budget_cents` (`:1456`) | EARNS on findings, costly to operate |
| Bridgebuilder post-PR (`post_pr_validation`, `run_bridge`, `.loa.config.yaml.example:1745,2017`) | SCRIPT, optional | Defects surviving sprint review | PR #1279: 17 fixed, 4 refuted (3758ddd0) | One pass per PR | config-gated | EARNS |
| CI gates: prompt budget, skill capabilities, FR-8 lint, bats (`.github/workflows/check-prompt-budget.yml`; `tests/unit/user-invoked-commands.bats`) | SCRIPT (CI) | Prompt bloat, invariant drift | All six golden skills within 1% of the 16,384 B cap (section G) | Doc drift: workflow comment says protocols cap 200,000 B (`.github/workflows/check-prompt-budget.yml:5`), script enforces 160,000 B (`tools/check-prompt-budget.sh:11,53`) | none | EARNS: the budget is what holds prompt size down |

## G. Run mode

| Surface | Class | Prevents | 2026 evidence | Cost | Knob | Verdict |
|---|---|---|---|---|---|---|
| Run loop and circuit breaker (`run-mode/SKILL.md:103-122,131-160`) | PROSE (the model runs jq and writes state) | Infinite fix loops, runaway time | E3: breaker never counted a cycle in cycle-128; state inconsistent after ship | 15,372 B skill | `run_mode.defaults.max_cycles: 20`, `timeout_hours: 8` (`.loa.config.yaml.example:549-553`) | SCAFFOLD as written: it does not execute; the loop itself was run by the lead |
| `run-preflight.sh` P1-P8 (`.claude/scripts/run-preflight.sh:9-33`) | SCRIPT, invocation prose (`run-mode/SKILL.md:73`) | Unattended run in a mode that will stall | KF-042: permission mode stalls are real; P1 is the check named in the reading guide | 339 lines | `--unattended` flag | EARNS |
| `run-mode-ice.sh` git wrapper (559 lines; `run-mode/SKILL.md:238`) | SCRIPT, use is prose ("MUST go through") | Pushing to protected branches, merging | no recent evidence found; a raw push to main is not fenced (prior file G3) | wrapper per git op | `run_mode.git` section (`:560+`) | AMBIGUOUS |
| `run-checkpoint.sh` (102 lines; `run-mode/SKILL.md:125`) | SCRIPT | Lost phase on resume | E3 shows the checkpointed state disagreeing with reality | small | none | AMBIGUOUS |
| `danger-level-enforcer.sh` (`run-mode/SKILL.md:40-43`) | SCRIPT, invocation prose | High-risk skills unattended | 4 BLOCKs on run-mode itself (section E) | per call | `guardrails.danger_level.*` | SCAFFOLD |

## Quantitative totals

| Measure | Value | Cite |
|---|---|---|
| Hooks registered in settings.json | 30 commands: Setup 1, SessionStart 8, PreCompact 1, UserPromptSubmit 2, PreToolUse 11 (Bash 2, Write/Edit 6, Skill 3), PostToolUse 4, Stop 2, PermissionRequest 1 | `.claude/settings.json:462-687` |
| Hooks on every Write/Edit | 6 PreToolUse plus 2 PostToolUse | `.claude/settings.json:574-658` |
| Hook scripts on disk | 29 `.sh` (incl. unregistered `stop-input-probe.sh`) | `.claude/hooks/` |
| hooks-reference registration table | 18 rows, omits zone-write-guard, spiral guards, adversarial gate, Karpathy check, Setup, PermissionRequest | `hooks-reference.md:170-189` |
| Permission rules | 381 allow, 62 deny | `.claude/settings.json:14-460` |
| Fence pattern IDs | 32 distinct (P2, P2b, P3, P4; FR-1.1 to 1.8 incl. 1.2b; FR-MERGE-2; SP-1; FR-SZ-* 8; FR-SZ2-* 5; FR-2-BLOCK, FR-2-AMBIGUOUS; FR-NOTES; LEGACY) over 41 block sites | `block-destructive-bash.sh:544-1986` |
| Fence corpus | 183 rows: 100 block, 78 allow, 5 residual | `tests/fixtures/fence-corpus/corpus.jsonl` |
| CLAUDE.loa.md | 138 lines, 10,225 B (cap 10,240) | `tools/check-prompt-budget.sh:53` |
| Always-loaded prose per turn | about 20.0 KB: CLAUDE.loa.md 10,225 + project CLAUDE.md 2,460 + 2 unscoped rules 7,301; plus 5,168 B KF table at session start | measured |
| Protocols | 27 files, 131,444 B (warn 114,688, fail 160,000) | check-prompt-budget JSON |
| Scripts | `.claude/scripts`: 380 `.sh`, 29 `.py`; `.claude/adapters`: 0 `.sh`, 75 `.py` plus 144 Python test files | find |
| Bats | 583 files, 9,032 `@test` | `tests/**/*.bats` |
| Config example | 2,916 lines, 134,175 B, 55 top-level keys | `.loa.config.yaml.example` |

Golden-path SKILL.md bytes, model-executed on every invocation (no resource is charged as unconditionally read):

| Skill | Bytes | Frontmatter | `@skill-include` blocks | `@constraint-generated` | Includes |
|---|---|---|---|---|---|
| discovering-requirements | 15,887 | 803 | 2,855 (18%) | 603 | prompt_enhancement, integrity, grounding, context, trajectory |
| designing-architecture | 15,568 | 667 | 2,229 (14%) | 0 | integrity, grounding, context, trajectory |
| planning-sprints | 16,124 | 581 | 2,229 (14%) | 0 | same four |
| implementing-tasks | 16,274 | 845 | 4,415 (27%) | 1,295 | adds input_guardrails, prompt_enhancement, retrospective |
| reviewing-code | 16,306 | 2,144 | 3,785 (23%) | 531 | adds input_guardrails, retrospective |
| auditing-security | 16,268 | 2,049 | 3,788 (23%) | 0 | adds input_guardrails, retrospective |
| Total | 96,427 | 7,089 | 19,301 (20%) | 2,429 | 7 include sources, 212 to 729 B each (`.claude/data/skill-includes/`) |

All six sit within 1% of the 16,384 B cap, so the cap, not need, sets their size.

## Optional today vs always-on

**Config knob exists:** KF surface, decisions surface, L6 handoffs, L7 soul (`soul_identity_doc.enabled`), Flatline planning and code/audit dissent (and so the COMPLETED gate), companion voice, Karpathy diff warning, success-criteria gate, input guardrails, danger level, invisible retrospective, run mode itself, interview pacing, red_test inputs, `implement_gate.mode` (undocumented).

**Env-only overrides:** fence tag and System-Zone rules, zone guard bypass/disable, adversarial gate, harness live check, team guards (armed only by env).

**Always-on, no knob:** fence core rules and SP-1, deny list, implement-gate, spiral guards, notes-size guard, hook-guard, Stop guard, mutation loggers, post-compact reminders, FR-8 flags, verdict-derive, CI gates, CLAUDE.loa.md and unscoped rule text.

## Prose-only NEVER/ALWAYS rules with no mechanical check

| Rule | Status at 864069f2 |
|---|---|
| NEVER TaskCreate for sprint tracking (`CLAUDE.loa.md:75`) | No hook references TaskCreate. Prose only |
| NEVER `/bug` for feature work; ALWAYS validate bug eligibility (`:77,89`) | Eligibility scoring is model-executed. Prose only |
| ALWAYS create beads from the sprint plan (`:87`) | Preflight P7 checks beads health, not task creation (`run-preflight.sh:30`). Prose only |
| NEVER skip review/audit; ALWAYS full cycle (`:76,88`) | Partial: adversarial gate checks dissent artifacts only, off by default downstream |
| NEVER code outside /implement; ALWAYS route via /run or /bug (`:74,86`) | Partial: implement-gate asks, never blocks, Bash unseen |
| Agent Teams rows (`:126-130`) | Hooks exist but are inert without `LOA_TEAM_MEMBER`, which is unset in this live team session. Effectively prose |
| Run-mode circuit breaker and state transitions (`run-mode/SKILL.md:131-160`) | Prose arithmetic; E3 shows it was not executed |
| ICE "all git operations MUST go through" (`run-mode/SKILL.md:238`) | Wrapper is mechanical, its use is prose |
| ALWAYS post-merge-orchestrator (`CLAUDE.loa.md:116`) | Mechanical in CI on merge only |
| Karpathy principles 1-4 (`CLAUDE.loa.md:61-64`) | Review tags plus a warn-only hook the model never sees |
