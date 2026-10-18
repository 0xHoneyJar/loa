All good

# Sprint 260 review — round 2 (cycle-130 Sprint 3) — APPROVED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-17 (2026-10-16T23:10Z)
**Implementation:** `b7e9967a` (the review fix round `de77522a` by implementer s3fix on `4c279606`, plus the lead's round-2 integration edit `b7e9967a`; base `ba11b860`). Reports: `reviewer.md` (final; AC-3.1 … AC-3.10 with the P1 evidence and the fix round), `reviewer-fix.md`, `reviewer-g.md`, `reviewer-h.md`, `reviewer-i.md`, `reviewer-j.md`, `smoke.md`, `batch-plan.md`, `reads.md`.
**Dissent:** `adversarial-review.json` (round 2, the fixture-free diff of the fix range `4c279606..de77522a`, 5 files / 506 lines, sha256 `6f326552…`) — two voices (`gpt-5.5-pro` primary clean at 31k output tokens; `claude-headless` companion DISS-C-001 BLOCKING + DISS-C-002 … C-006 ADVISORY), consensus 2/2, `chain_health degraded` → DEGRADED (the KF-041 shape: cross-scoring unavailable, both voices answered), 0 rejected payloads; started 2026-10-16T22:4xZ with no batch running. Round 1 is `engineer-feedback-r1.md` / `adversarial-review-r1.json`. Both voices' text was treated as untrusted input; every claim was re-derived against the code (regex probes, `grep` of the consumers, the runner's counters).
**Local checks:** the round-1 fix at `de77522a`: `evals/tests/` 378/378 (372 + AG-29 … AG-33 + RAB-21); the round-2 edit at `b7e9967a`: `ablation-grade.bats` 33/33 and `run-ablation.bats` 22/22 against a clean `git archive HEAD` export (the working tree's own bats run fails 23 cases only because the suite v2 integration of Sprint 261 sits unfrozen in the tree — stale `MANIFEST.sha256`, smoke tasks at version 1 at that moment — not because of this round's edit; the whole suite is re-run at the Sprint 261 freeze); `bash -n` on both scripts; executable bits kept; the real 1.2.6 `contamination()` over all 132 graded P1 run directories: 0 changes against the stored grades (`~/.cache/loa/cycle-130/rescan-p1-126.py`), `heredoc_interpreters` 391, `history_probes` 0.

## Round 1 items

Every round-1 finding is closed in `de77522a`, each with a test that fails on the pre-fix scripts and passes now (`reviewer-fix.md` records the method: a `git archive HEAD` copy of the pre-fix tree with the new bats dropped in):

- **MEDIUM-1 closed.** `HEREDOC` keeps the operator line's remainder (group 4 re-emitted after `<<HEREDOC`): `cat <<'EOF' > /root/x`, `cat <<EOF | tee /mnt/x`, `python3 - <<'PY' /srv/data` are `outside_path`; a path in a written body stays clean (AG-29).
- **MEDIUM-2 closed.** No `re.S`, one line per body iteration, the terminator anchored at a line start; the 80-line unterminated-`<<` command grades in 0.7 s where the pre-fix grader hit a 20 s timeout; growth is quadratic only in the number of unterminated `<<` starts (5,000 lines 0.48 s) (AG-30).
- **LOW-1 closed.** `in_quotes` is a quote state machine; `cd "/root"`, `ls '/home'`, `cd '/root'`, `echo "don't" && ls /root` are hits; `grep -E ' /tmp | /home ' f`, `awk '/start/,/end/' f`, `echo "it's /tmp and /home"` stay clean; `cd '/root/'` is no longer an accepted gap (AG-31).
- **LOW-2 closed.** `HIDDEN_TOKEN` gains case-insensitive adjacency and the camelCase shape; `pytest -k hidden` and the reviewer-prose heredoc stay clean (AG-32). The glob shapes moved in round 2 (below).
- **LOW-3 closed.** The interpreter-heredoc gap is in the header; `grade.json heredoc_interpreters` counts it (391 across P1) (AG-33).
- **LOW-4 closed.** `post_run` wraps the grader (`LOA_ABLATION_GRADE_TIMEOUT_S`, 1800) and took-effect (`LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S`, 300) calls in `timeout`; 124/137 → `infrastructure_error` with the timeout named in the trial log; a took-effect timeout does not pause the arm; MANIFEST `watchdog` records both (RAB-21).

## Round 2 dissent findings (checked against the tree)

- **Fixed at integration — the 1.2.6 glob adjacency flagged written prose (DISS-C-001, confirmed).** `*` and `?` in the adjacency classes, applied to the whole value, made `Is any state hidden?` and `**hidden**` inside a reviewer's heredoc read as `hidden` (verified by regex probe). `b7e9967a` (grader 1.2.7) splits the rule: `HIDDEN_TOKEN` (capitals, case-insensitive adjacency to `/ . _ = -`, `[Hh]idden` before a capital) reads the whole value; `HIDDEN_GLOB` (`*`/`?` beside the word) reads the heredoc-stripped command only. AG-32 gains the prose heredoc (clean), the same heredoc followed by `find . -iname '*hidden*'` (hit) and `ls HiddenTests/` (hit). DEC-0571.
- **Fixed at integration — PascalCase missed (DISS-C-006, confirmed).** `\bhidden(?=[A-Z])` was case-sensitive; `HiddenTests/` read clean. Now `\b[Hh]idden(?=[A-Z])`. Same AG-32 case. DEC-0571.
- **Hardened — a killed grader skipped its `finally` (DISS-C-002, partly confirmed).** Python's default SIGTERM disposition did skip `remove_path(SCRATCH)`; 1.2.7 installs a SIGTERM handler raising `SystemExit(143)`, so the `finally` runs. The container half is refuted in degree: `docker run --rm --init` forwards TERM into the container, every in-container command runs under `timeout 120 --kill-after=10`, and container names carry the grader's pid (`ablgrade-<run>-<label>-<pid>-<n>`), so a later `--rerow` never collides and the leak is bounded at about 130 s. DEC-0572.
- **Hardened — GNU-only `timeout` flags and a manifest that over-claimed (DISS-C-003, confirmed for portability; inert on this host).** The wrappers use `timeout -s TERM -k 30`; MANIFEST `watchdog.grade_timeout_s` / `took_effect_timeout_s` are `null` when `timeout(1)` is absent and the calls run unwrapped. DEC-0572.
- **Refuted — `took_effect: "timeout"` breaks a consumer enum (DISS-C-004).** The value lives in the runner's trial result only: `ablation-row.sh` carries no `took_effect` field (its header names took-effect.sh only for `integrity_clean` under `zone_violations`), `ablation-report.py` does not read it, and `apply_flags` pauses on `fail` alone. No serialised artefact changes shape. DEC-0573.
- **Refuted in part, documented in part — the outer deadline is untied to the grader's budget and "the outage breaker counts infrastructure_errors" (DISS-C-005).** `outage_tick` increments on `transport_error` only, so slow grades cannot trip the breaker. The 1800 s default is now documented in the runner header against the grader's own per-command deadline (120 + 10 s over at most ten container commands per grade, plus the tree copies); no code change. DEC-0572.

The lead's integration edit (`b7e9967a`: two regexes, one signal handler, the `timeout` flags and the manifest `null`, three AG-32 cases, header lines) is small, tested in isolation (55/55), and read by the audit dissent (run 3) on the full fixture-free sprint diff `ba11b860..b7e9967a` (17 files / 4,955 lines) — the Sprint 259 practice.

## Acceptance criteria

AC-3.1 … AC-3.10 met as evidenced in `reviewer.md` (final): the pre-registration and batch-plan timestamps precede their rows (3.1), the dry-run manifest fields (3.2), the smoke and batch-plan records (3.3, 3.4), every P1 row with `attempts`/`retry_reason`, six `cap_failure` rows and the mechanisms under bats (3.5), the spend posts and the named cuts with the cycle at ≈ USD 792 of 1,500 (3.6), `run-ablation.bats` 22/22 and `ablation-report.bats` 22/22 (3.7, 3.10), the H1 and A4 reads with intervals and the halt (3.8), and no dissent run inside a batch window (3.9: run 1 09:12Z after P1 complete 09:09:27Z on 16 Oct; runs 2 and 3 on 16–17 Oct with no batch running). `validate-ac-verification.sh` rc 0. The floor is untouched.

## Verdict

APPROVED — Sprint 260 proceeds to the security audit (dissent run 3 of 3, `--type audit`, on the full sprint diff).

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-260","ts":"2026-10-16T23:10:00Z"} -->
