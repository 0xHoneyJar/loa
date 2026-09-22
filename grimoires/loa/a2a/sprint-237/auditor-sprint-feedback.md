# Sprint 3 Security Audit — cycle-124 "model-generation floor" (global sprint-237) — round 2

**Auditor:** Paranoid Cypherpunk Auditor (Fable 5.1 lead acting as gate; round-1 record with the full evidence, the three category-auditor reports' dispositions and the four-chunk cross-model dissent: `auditor-sprint-feedback.round-1.md`)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 3)
**Implementation Report:** grimoires/loa/a2a/sprint-237/reviewer.md
**Scope:** `012d0c5e..6920126e` — the round-1 range plus the HIGH-001 follow-through commit `6920126e` (`evals/harness/execute-agent.sh`, `evals/graders/implement-discipline.sh`, the CLI stub and three bats cases, README/SDD argv lines, CHANGELOG, sprint plan, report)
**Review gate:** round 3 APPROVED (`engineer-feedback.md`, 2026-09-22; rounds 1–2 in `engineer-feedback.round-{1,2}.md`)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Round 1 blocked on one HIGH — the FR-9 executor did not confine the agent under test (operator allow rules admitted Bash, file tools unconfined, environment inherited; observed in the surviving A/B transcripts and in 30 of 181 trials writing to `/tmp`). Round 2 verified the fix in `6920126e` at the line, not from the report:

- `evals/harness/execute-agent.sh:161` — `--restricted --tools "Read,Grep,Glob,Write"`. Restricted mode is the CLI's own confinement: code-running tools removed, user/project/local settings ignored, file tools confined to the working directory. The round-1 live probe established the semantics on this CLI (2.1.278): out-of-cwd Write refused (`permission_denials: 1`), in-cwd Write allowed.
- `evals/harness/execute-agent.sh:174-178` — inside the existing run subshell: `unset GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN`; `TMPDIR` set to `<ws>/.eval/tmp`; `HOME`/`PATH` kept for the CLI's own credentials and toolchain. The argv is still an array exec'd through `timeout` — no shell.
- `evals/graders/implement-discipline.sh:44-56` — `env -i` with an explicit allowlist (`PATH`, `HOME`, `TMPDIR`, `LC_ALL`, and `PYTHONPATH`/`VIRTUAL_ENV` only when set) around the agent-authored `test_command`.
- Tests: EA-3 pins the confined argv and refutes `--allowed-tools`; EA-10 asserts the four credentials are empty in the stub's captured environment and `TMPDIR` is under the sandbox; ID-10 runs a `test_command` that fails unless the credentials are absent and `python3` is still reachable. All three were red before the change (recorded in the report) and the three eval suites pass 30/30 on `6920126e` (re-run by the auditor).
- Record: `reviewer.md` §AC-9.2 carries the environment caveat (arms measured unconfined; same-environment comparison; re-measure bd-vq7v); README and SDD state the new argv; the CHANGELOG entry names what leaked and why.

No new trust boundary is opened by the hunk; the six-name credential list is defence in depth behind the tool removal (the review's new LOW). The nine medium and fifteen low findings from round 1 are unchanged, each with a bead or follow-up row, none blocking; the round-1 file keeps their full text and evidence. The cross-model audit dissent (four diff-only chunks, 0 retained, 4 rejected payloads recovered and dispositioned) was not re-run: the follow-through hunk is 60 lines of executor/grader code that the round-1 chunk 1 dissent already covered in shape, and no dissenter finding touched it.

**Security Issues Found (Phase 2.5 tally — open findings at verdict time; HIGH-001 closed):**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 9 |
| Low | 16 |

---

## Previous Audit Feedback Status

| Issue | Status | Notes |
|-------|--------|-------|
| HIGH-001 executor confinement (`execute-agent.sh:161-162`, `:177`; `sanitize_env` never called) | Resolved | `--restricted --tools`; credentials unset + `TMPDIR` in the subshell (`:174-178`); EA-3/EA-10 |
| MED grader runs agent-authored tests with the operator's env (`implement-discipline.sh:47`) | Resolved | `env -i` allowlist (`:44-56`); ID-10 |
| MED compare.sh freshness hashes SHA256SUMS itself | Open (tracked) | bd-sk1t |
| MED check-prompt-budget empty scan passes | Open (tracked) | bd-tc3i |
| MED ×3 verdict-derive consistency gaps (integral floats, lowercase marker strip, title-case scan) | Open (tracked) | bd-zklv — golden path denies in the two reachable cases |
| MED "pinned cheaper model" kernel rule dropped | Open (tracked) | bd-kqz4 |
| MED agent-network read-before-touch dropped | Open (tracked) | bd-1ju5 |
| MED guardrails fail-open (pre-existing; dissent) | Open (tracked) | bd-2a9g |
| LOW ×15 (round 1) | Open (tracked) | bd-tc3i, bd-sk1t, bd-zklv, bd-tjkx, bd-ts9l, bd-tdtr; doc-lock notes recorded |
| LOW (new, review round 3) fixed credential unset list | Open (noted) | extend when a provider is added |

---

## Medium/Low Priority Issues

The nine mediums and fifteen lows are listed with `file:line`, scenario, confidence and bead in `auditor-sprint-feedback.round-1.md` §Medium/Low; they are unchanged by `6920126e` and are counted above. One low is added this round:

- **LOW** (confidence: high) `evals/harness/execute-agent.sh:174-178` — the credential unset list is six fixed names; a future provider variable (`GOOGLE_API_KEY`, `AZURE_*`, …) is not covered. Behind `--restricted` the agent has no code-running tool through which to read the environment, so this is defence in depth, not the boundary. Extend with the provider catalog when one is added.

---

## Cross-Model Security Observations (Phase 1C)

Round-1 record stands (`adversarial-audit.json` merged from `adversarial-audit.{1-evals,1-evals.rerun,2-tools-tests,3-review-prompts,4-exec-prompts}.json`; rejected payloads in `adversarial-rejected-audit.4-exec-prompts.jsonl`; KF-004 recurrence 31 with the evidence row). The two recovered dissenter items are tallied above as MEDIUM (guardrails fail-open, bd-2a9g) and LOW (Phase 0 cleanup continue-on-error, bd-ts9l).

---

## Verified negatives (delta for `6920126e`; the round-1 list stands)

- `execute-agent.sh`: `bash -n` clean; argv array unchanged in shape (`:157-166`); `--permission-mode acceptEdits` retained (in-cwd writes are the point of the harness); `--max-turns` and `timeout --kill-after` still bound the run; the `tool_writes` extractor still records `Edit`/`MultiEdit` defensively although `--tools` makes them unavailable (header `:28-30` says so); `mkdir -p "$eval_dir/tmp"` sits inside the sandbox path the caller created.
- `implement-discipline.sh`: `bash -n` clean; `env -i` receives an array, no string splitting; `PATH` passes through unchanged (toolchain), `HOME` unchanged (user-site packages — the first cut proved it matters), no credential names in the allowlist.
- Stub: `claude-stub.sh:19` only widens the captured key list; no behaviour change for other tests (suite 30/30).
- Docs: README/SDD lines are the only prose changes; CHANGELOG entry contains no secrets or internal URLs; `git diff 012d0c5e..6920126e -- .claude/hooks .claude/scripts/{implement-gate,zone-write-guard,block-destructive-bash,audit-envelope}.sh .claude/settings.json` still empty.
- Secrets: key-shape scan over `d562d510..6920126e`: 0 hits.

---

## Rubric scores (1–5)

| Dimension | Score | Basis |
|-----------|-------|-------|
| Security | 4 | executor confined and probe-verified; env hygiene; remaining mediums are consistency gaps the golden path already denies, plus two prompt-rule restorations |
| Architecture | 4 | unchanged from round 1 |
| Code quality | 4 | tests first, red→green recorded, honest note on the HOME misstep |
| DevOps | 4 | unchanged from round 1 (empty-scan pass and `permissions:` block tracked) |

---

## Documentation audit

CHANGELOG entry per task including the audit follow-through; security-relevant code commented (`execute-agent.sh:20-32`, `:174-176`; `implement-discipline.sh:43-46`); README/SDD argv corrected; no secrets or internal URLs in docs; no API change. Manually verified — no `documentation-coherence-*` reports exist for this sprint.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Agent under test confined to its sandbox (`--restricted --tools`; probe-verified)
- [x] Operator credentials stripped from the agent's and the grader's environment
- [x] Input validation on the new entry points (effort, trailer ints in golden-path, fixture ids, `--metric`, `--root`)
- [x] Fences and hooks unchanged
- [x] Error handling doesn't leak info
- [x] Tests cover the gate paths (PB/PR/NH/VO/ED/EA/BF/ID suites; tracked gaps named in round 1)

---

## Next Steps

1. Sprint is cleared: write the COMPLETED marker, close the sprint in the ledger and beads, move to Sprint 4 (FR-10).
2. Improvements to carry (beads): confined A/B re-measure (bd-vq7v); corpus freshness verification, ledger isolation and regex bound (bd-sk1t); empty-scan guard, warn surfacing and workflow permissions (bd-tc3i); verdict-derive integer/case tightening (bd-zklv); the two kernel-rule restorations (bd-kqz4, bd-1ju5); the six low prompt drops (bd-tjkx); guardrails fail-open policy (bd-2a9g); dissent sidecar per-run naming (bd-tdtr).

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":9,"low":16},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-3","ts":"2026-09-22T07:50:00Z"} -->
