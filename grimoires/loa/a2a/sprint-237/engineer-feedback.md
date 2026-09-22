All good

Observations documented and non-blocking. See Observations below.

# Sprint 3 Review Feedback — round 3 (post-audit fix)

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; earlier rounds: `engineer-feedback.round-1.md` CHANGES_REQUIRED 0/2/4/3, `engineer-feedback.round-2.md` APPROVED 0/0/4/3; cross-model dissent gpt-5.5-pro over four chunks in round 1)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 3, global sprint-237)
**Implementation Report:** grimoires/loa/a2a/sprint-237/reviewer.md
**Range under review this round:** `d562d510..6920126e` (the audit HIGH-001 follow-through)

---

## Overall Assessment

Round 3 exists because the security audit (round 1, `auditor-sprint-feedback.round-1.md`) returned CHANGES_REQUIRED on one HIGH: the FR-9 executor ran the agent under test with `--allowed-tools`, which adds allow rules on top of the operator's own `~/.claude` settings instead of fixing the tool set, and the surviving A/B transcripts showed Bash calls the executor never granted. The fix in `6920126e` is the smallest one that closes it, verified in the code rather than the report:

- `evals/harness/execute-agent.sh:161` — `--restricted --tools "Read,Grep,Glob,Write"` replaces `--allowed-tools`; the CLI's restricted mode removes the code-running tools, ignores user/project/local settings and confines the file tools to the working directory (the audit's live probe: out-of-cwd Write refused with `permission_denials: 1`, in-cwd Write allowed). `:174-178` unset `GH_TOKEN GITHUB_TOKEN OPENAI_API_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN` and set `TMPDIR` to `<ws>/.eval/tmp` inside the existing run subshell; `HOME` and `PATH` stay so the CLI finds its own credentials and toolchain — the right call, and the header comment (`:20-32`) says why. The argv is still an array exec'd through `timeout`; no shell anywhere.
- `evals/graders/implement-discipline.sh:44-56` — `test_command` runs under `env -i` with an explicit allowlist (`PATH`, `HOME`, `TMPDIR`, `LC_ALL`, plus `PYTHONPATH`/`VIRTUAL_ENV` only when set). The first cut moved `HOME` into the workspace and broke user-site `pytest`; ID-1/ID-9 caught it and the report says so — the kind of honesty the round-1 feedback asked for.
- Tests were written first and were red before the change: EA-3 now pins `--restricted`, `--tools`, `Read,Grep,Glob,Write` and refutes `--allowed-tools` (`evals/tests/execute-agent.bats:94-116`); EA-10 checks the four credentials are empty in the stub's captured environment and `TMPDIR` sits under the sandbox while `HOME` is unchanged (`:118-129`); ID-10 runs a `test_command` that fails unless the credentials are absent and `python3` is still reachable (`evals/tests/implement-discipline-grader.bats:80-92`). The stub gained the extra env keys (`evals/tests/fixtures/claude-stub.sh:19`). Re-run here: `execute-agent.bats` + `implement-discipline-grader.bats` + `eval-recall-grader.bats` 30/30.
- Documentation: `CHANGELOG.md` Unreleased carries the entry; `evals/README.md:474` and `grimoires/loa/sdd.md:320` state the new argv; `reviewer.md` §AC-9.2 carries the environment caveat and a "Audit round 1 response" section; the sprint plan's Sprint 3 follow-ups table gained the nine audit beads.

The A/B record is not re-measured under the confined executor (hours of wall-clock; bead bd-vq7v). That is the right scope call for this sprint: both arms shared the unconfined environment, so the comparison the report draws is internally valid, and the report now says exactly what it measured.

Zero critical/high findings remain in the sprint range. The observations below are unchanged from round 2 (all tracked) plus one new low on the fix itself. Approval rationale: the audit's blocking item is fixed with tests that failed first, nothing in the new hunk widens a trust boundary, and every residual has a bead.

**Verdict:** APPROVED

---

## Observations

### 1. On the audit follow-through (new this round)

- **LOW** (confidence: high) `evals/harness/execute-agent.sh:174-178` — the credential unset list is a fixed six names; a future provider key (e.g. `GOOGLE_API_KEY`, `AZURE_*`) is not covered. With `--restricted` the agent has no code-running tool through which to read the environment, so the list is defence in depth, not the boundary. Extend when a provider is added; no bead needed beyond bd-vq7v's re-measure note.

### 2. Carried from round 2 (tracked, unchanged)

- **MEDIUM** (confidence: high) `.claude/skills/implementing-tasks/SKILL.md:26-28` — frontmatter `zones.app.permission: read` while the body says Read/Write; identical at `80be4b0f`. Bead bd-hf7g.
- **MEDIUM** (confidence: high) `.claude/skills/autonomous-agent/SKILL.md:48` — registry-rendered phase sequence names phases the skill never defines; byte-identical at the base. Bead bd-ts9l.
- **MEDIUM** (confidence: high) `evals/harness/compare-ab.py:51-108` and `:111-176` — `summarize()` / `main()` over 50 lines with `loa:shortcut:` justifications; accepted.
- **MEDIUM** (confidence: high) `evals/fixtures/implement-tasks/expectations/01.json` … `05.json` — implement-discipline composite 0/15 in both arms, gate vacuous. Beads bd-fwt0, bd-azrr.
- **LOW** (confidence: medium) `grimoires/loa/a2a/sprint-237/ab/compare/review-recall.b2.json` — one high-severity finding on a clean PR in one of six clean trials. Follow-ups block.
- **LOW** (confidence: high) `.claude/skills/simstim-workflow/SKILL.md` — dangling "Phase 6.5" reference; bd-ts9l.

---

## Previous Feedback Status

| Issue | Status | Notes |
|-------|--------|-------|
| Audit round 1 HIGH-001 — executor confinement | Resolved | `execute-agent.sh:161,174-178`; EA-3/EA-10 red→green |
| Audit round 1 MED — grader runs agent tests with the operator's env | Resolved | `implement-discipline.sh:44-56` `env -i` allowlist; ID-10 |
| Audit round 1 — A/B record measured unconfined | Resolved (documented) | `reviewer.md` §AC-9.2 caveat; re-measure is bd-vq7v |
| Review round 1 #1 — CHANGELOG entries | Resolved | round 2 |
| Review round 1 #2 — AC-9.2 scope-split | Resolved | round 2; table extended with the audit rows |
| Review round 2 observations | Tracked | bd-hf7g, bd-ts9l, bd-fwt0, bd-azrr |

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| AC-8.1 budget tool + CI gate | Pass | live gate `ok: true`; PB-1..PB-9; sentinel controls (empty-scan gap tracked as bd-tc3i) |
| AC-8.2 no history in rule text; mechanisms named | Pass | NH-1..NH-3 green |
| AC-8.3 keep list, reports, generated sections, refs, validators, goldens, reminder fence | Pass | 49 reports; dry-runs clean; PR-1..PR-3; 36/36; 32/32; hooks untouched |
| AC-9.1 coverage-first + `excluded` + effort | Pass | four `### Coverage` blocks; VO-1..VO-11; ED-1..ED-10 |
| AC-9.2 A/B | Partial, scope-split recorded, environment caveat stated | review recall ✓ (B2), review FP ✗ 0.167, audit recall/FP ✓, audit tokens ✗ 0.758, discipline vacuous; measured unconfined (bd-vq7v) |
| AC-9.3 suites green after the diff | Pass | evals suites 30/30 after the fix; 38 unit red = 30 pre-existing + 8 time-dependent licence fixtures; pytest 2276/0; integration 101/101 |
| Sprint-level rows | Pass (AC row intentionally unticked) | see report §Sprint-level ACs |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (range scanned)
- [x] Fence patterns unchanged; hooks untouched
- [x] Agent under test confined to its sandbox (`--restricted --tools`; probe-verified)
- [x] Operator credentials stripped from the agent's and the grader's environment
- [x] No new dependencies; argv arrays, no shell interpolation
- [x] Error output carries no credentials

---

## Next Steps

1. `/audit-sprint sprint-3` round 2 — confirms HIGH-001 closed and `excluded_confirmed: 0`; writes the COMPLETED marker.
2. Sprint 4 (FR-10) on `6920126e`+.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":4,"low":3},"excluded":0,"sprint_id":"sprint-3","ts":"2026-09-22T07:40:00Z"} -->
