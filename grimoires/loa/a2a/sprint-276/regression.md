# Sprint 276 — took-effect regression (D-4.2 / D-4.3) and the Q-1 hook-name probe (Task 1.4, lead)

## Baseline (before C-1/C-2/C-3), 2026-10-25 — identical to the recorded `meta/took-effect.json`

Command: `bash evals/harness/took-effect.sh --run-dir <run> --suite-file grimoires/loa/reports/ablation-2.0/c133-smoke/suite.yaml --json`

| Run dir | rc | failing rules | oracle_closed evidence (first) | integrity_clean |
|---|---|---|---|---|
| `evals/results/ablation-2.0/smoke-c133-s274/a1_full/smoke-review-c133-t1` | 1 | `oracle_closed`, `dissent_present` | `FAIL (f) .claude/skills/reviewing-code/SKILL.md: pinned_bytes_read: a later-only line of the pinned version in Bash (events-REVIEW.jsonl) (+34 more)` | pass — `home-scope: 2073 HOME framework entries verified at finish; manifest_sha256 a907ed444e10` |
| `evals/results/ablation-2.0/smoke-c133-s274-r2/a1_full/smoke-review-c133b-t1` | 1 | `oracle_closed` | `FAIL (f) .claude/scripts/classify-pr-type.sh: pinned_bytes_read: a later-only line of the pinned version in Bash (events-AUDIT.jsonl) (+11 more)` | pass — `home-scope: 2073 HOME framework entries verified at finish; manifest_sha256 2e9e37de1007` |

Transcript inventory: run 1 `events-REVIEW.jsonl` 845 lines, init 1, result **0** (the capture has no result event); run 2 `events-REVIEW.jsonl` 386 lines (init 1, result 1), `events-AUDIT.jsonl` 273 lines (init 1, result 1). `hook_started` events: `SessionStart | SessionStart:startup` ×8 per transcript (8 configured SessionStart commands, 1 init) and nothing else, beside 66 / 31 / 34 Bash tool uses. `home_hook_counts=PermissionRequest:1,PostToolUse:4,PreCompact:1,PreToolUse:11,SessionStart:8,Setup:1,Stop:2,UserPromptSubmit:2` in both runs.

## Expected after C-1/C-2/C-3 (pre-registered, D-4.3 = DEC-0986)

Same `rc`, same failing sets, `integrity_clean` passes as `record cross-checked against the pin (HOME deleted at exit)`; run 1 additionally reports `(g) transcript REVIEW: no result event` inside the `+N more` list (the one explained change); hook groups pass with k = 1 for `SessionStart:startup` and k = 0 for every other group. Any other difference is a shipping gate (DEC row with the explanation and the table amended, or the change fixed) before merge.

## After (Task 1.11, lead re-run 2026-10-25 after landing A, B, C, D and A's home-scope fixture companion)

| Run dir | rc | failing rules | oracle_closed evidence (first) | integrity_clean |
|---|---|---|---|---|
| `smoke-c133-s274/a1_full/smoke-review-c133-t1` | 1 | `oracle_closed`, `dissent_present` (unchanged) | `FAIL (f) .claude/skills/reviewing-code/SKILL.md: pinned_bytes_read: … (events-REVIEW.jsonl) (+35 more)` — **+1** against the baseline's +34: implementer A's debug listing shows the addition is exactly `(g) -: transcript REVIEW: no result event (last line 845)`, the pre-registered change | pass — `… manifest_sha256 a907ed444e10; pin 32a8d79cf091 (batch MANIFEST.json) = source_commit; the pin's manifest 4b2a465e4088 (2072 entries) covered; record cross-checked against the pin (HOME deleted at exit)` |
| `smoke-c133-s274-r2/a1_full/smoke-review-c133b-t1` | 1 | `oracle_closed` (unchanged) | `FAIL (f) .claude/scripts/classify-pr-type.sh: pinned_bytes_read: … (events-AUDIT.jsonl) (+11 more)` — unchanged | pass — `… manifest_sha256 2e9e37de1007; pin 7d211947791e (batch MANIFEST.json) = source_commit; the pin's manifest 6adf1c49be20 (2072 entries) covered; record cross-checked against the pin (HOME deleted at exit)` |

Verdict against D-4.3 (DEC-0986): **met** — identical `rc` and failing sets; the one explained addition; `integrity_clean` passes as "record cross-checked against the pin". Hook groups: `SessionStart c=8 n=8 k=1 triggers=1` per transcript, k = 0 elsewhere (A's report). One design deviation surfaced and is recorded as DEC-0990 (I-1.3a): the HOME manifest is regenerated over the transformed copy with a `generated` timestamp, so literal digest equality with the pin's `checksums.json` blob is infeasible; the binding is instead "the pin's manifest entries are covered by the record's count (2073 ≥ 2072), the record equals arm_evidence, and the pin named by the suite/batch equals pipeline.json's source_commit" (A, judgment call 14). The suite file `grimoires/loa/reports/ablation-2.0/c133-smoke/suite.yaml` carries a stale `source_commit: ba11b860` for these batches; the pin was taken from the batch `MANIFEST.json` (A, judgment call 13; DEC-0990) — recorded evidence, not edited.

## Q-1 — the `hook_started` grammar on a real session (2026-10-25, lead host)

- Zero-cost source first: the retained smoke transcripts hold only `SessionStart:startup` events (above).
- One-turn probe: `claude -p 'Run exactly one shell command: echo q1-hook-probe …' --output-format stream-json --verbose --setting-sources project --tools Bash --max-turns 3` in the repository root (its project hooks declare PreToolUse groups with matchers `Bash`, `Write|Edit|MultiEdit|NotebookEdit`, `Skill`, `Skill(plan-and-analyze.*)`, plus UserPromptSubmit ×2 and Stop ×2 without matchers). Claude Code **2.1.310**, model `global.anthropic.claude-sonnet-5-5`, cost USD 0.053, one Bash `tool_use`. Result: **8 `hook_started` events, all `SessionStart | SessionStart:startup`; no PreToolUse, UserPromptSubmit or Stop hook event was emitted** although the prompt was submitted and Bash ran. Capture: `~/.cache/loa/cycle-134/q1/events.jsonl`.
- Reading: in `-p` stream-json mode the tool- and prompt-event hooks emit no `hook_started` events (whether they ran is not observable in the stream), so the `hook_name` grammar for those groups is **unconfirmed on a real event**. Shipping decision (DEC row at the sprint close): A ships the two-form parser (`<event>` and `<event>:<matcher>`) with k = 0 legal; fixtures for tool-hook groups are synthesised from the SDK message types and marked `synthetic` in the fixture files; the first live home-scope run that emits such an event re-checks the grammar (noted on bd-bex39).

> Written by the lead (Task 1.4). Sources: the commands above; `~/.cache/loa/cycle-134/q1/`; sdd.md D-1.1a, D-4.3.
