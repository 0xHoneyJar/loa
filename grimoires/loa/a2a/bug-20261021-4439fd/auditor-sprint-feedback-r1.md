# sprint-bug-267 Security Audit (round 1)

**Auditor:** Fable 5.1 lead (auditing-security contract; dissent via adversarial-review.sh --type audit)
**Date:** 2026-10-21T02:20:00Z
**Sprint Reference:** grimoires/loa/a2a/bug-20261021-4439fd/sprint.md (sprint-bug-267)
**Review:** grimoires/loa/a2a/bug-20261021-4439fd/engineer-feedback.md (All good, after round 1)
**Commits audited:** `06bc53ce` → `3ec4e927` → `2302aeba` on `fix/cycle-132-bugs` (diff vs `70330e48`: `.claude/scripts/post-pr-orchestrator.sh`, `tests/unit/post-pr-flatline-degraded.bats`)
**Dissent:** adversarial-audit.json (gpt-5.5-pro; status clean; 6 findings, 0 schema-rejected; 2 of ≤ 3 dissent runs used for this sprint)

---

## Scope

A state machine that decides whether a PR reads "validated". The audit read the diff for fail-closed behaviour on every input shape, temp-file handling, and cross-run state leakage.

## Findings

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 1 |
| LOW | 5 |

### MEDIUM-1 — The verdict read accepts any stdout shape that happens to reduce to one string (dissent DISS-C-001)
`.claude/scripts/post-pr-orchestrator.sh:500-506` — `jq -er '.verdict_quality.status | strings'` over the captured file evaluates every top-level document; `-e` reports the last output and `$(...)` joins outputs. Today every multi-document case fails closed (the joined string never equals `APPROVED`), which is why the review accepted DISS-C-001, but the behaviour is accidental, not stated. **Required:** read the envelope as exactly one JSON document (`jq -es 'length == 1 and (.[0] | type == "object")'` first, then the status from `.[0]`); more than one document or a non-object is `no_verdict_quality`. Test: two concatenated documents, the first APPROVED → `failed`.

### LOW-1 — Green ignores the envelope's other signals (dissent DISS-C-002)
`:508-512` — green needs only `status == APPROVED`; `degraded == true`, a non-empty `degraded_models` or a non-empty `blockers` alongside an exit 0 would still read green. **Required:** green requires `status == APPROVED` and `degraded != true` and `(blockers // []) | length == 0`; otherwise `verdict_quality_degraded` (or `blockers_present`). Test each.

### LOW-2 — Unchecked `mktemp` for the captured output (dissent DISS-C-003)
`:478` — a `mktemp` failure leaves an empty variable, an ambiguous redirect, and the run falls into `*)` as `exit_1`. **Required:** `|| { log_error …; _flatline_pr_not_green "tmp_failed" …; return 0; }` as the other `mktemp`s in the file do.

### LOW-3 — Unguarded `jq` reads in the summary writer (dissent DISS-C-004)
`:388-390` — `vq=$(jq -c …)` and `degraded_models=$(jq -c …)` can fail (non-iterable `voices_dropped`) or emit several lines on multi-document input, then reach `--argjson`. **Required:** guard both (`|| vq='{}'`, `|| degraded_models='[]'`) and validate with `jq -e type` before `--argjson`.

### LOW-4 — An empty `previous_summary` breaks the Bridgebuilder summary write (dissent DISS-C-005)
`:714-724` — `jq -n … --argjson previous "$previous_summary" > tmp; mv -f` moves an empty file over the summary when `jq -n` fails. **Required:** `if jq … > "$tmp"; then mv; else rm -f "$tmp"; log_error; fi`, and `previous` only when it parses.

### LOW-5 — A Flatline summary from another run or PR survives `--resume` (dissent DISS-C-006)
`:584-590` — the Bridgebuilder phase preserves any summary whose `.phase`/`.previous.phase` is `flatline_pr` without checking it belongs to this PR; a leftover from a previous PR's run is carried into this hand-off. **Required:** preserve only when the summary's `pr_number` equals this run's; clear it at `init`/PR_CREATED; test with a stale summary for PR 41 before a run for PR 42.

## Secrets, zones, dependencies
- No credential handling; files written under `.run/` by temp-and-move; no new dependency; System Zone edit under `/bug` with the triage's authorization. Tests are hermetic (scratch project, stub orchestrator).

## Verdict

CHANGES REQUIRED — one MEDIUM (an accidental rather than stated fail-closed parse) and five LOW hardening items on a script that decides a PR's green state. The review's approval stands; this round is the audit's.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":1,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-bug-267","ts":"2026-10-21T02:20:00Z"} -->
