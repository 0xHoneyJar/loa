APPROVED - LET'S FUCKING GO

# Sprint 261 security audit — round 1 (cycle-130 Sprint 4) — APPROVED

**Auditor:** Paranoid Security Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T10:35:16Z)
**Scope:** the full Sprint 261 harness diff `4434d450..631d628f` (22 files / 4,598 lines, fixtures and the fairness-reviewed task directories excluded) plus the audit fix `e95139fe`; the review verdict `engineer-feedback.md` (round 3 APPROVED; rounds 1–2 archived).
**Dissent:** `adversarial-audit.json` (run 3 of 3, `--type audit`): two voices (`codex-headless`, `claude-headless`; 2 of 2 planned), status `clean`, three findings (2 MEDIUM, 1 LOW) — one accepted and fixed, one accepted with a documented residual and a bead, one refuted with evidence (below).
**Local checks:** `evals/tests/` 430/430 on `631d628f` and `pipeline-run.bats` 64/64 on `e95139fe` (the full suite on `e95139fe` runs at the close); the official image self-check 36/36 under grader 1.2.13; the blind re-grade of 165 run directories identical to the inline grades.

## Findings

### MEDIUM-1 (DISS-C-001, secrets) — the codex credential copy is readable by the agent under evaluation: ACCEPTED, mitigated, residual documented
`pipeline-run.sh make_home()` writes a copy of `~/.codex/auth.json` into `<run>/meta/home/.codex`, bind-mounted read-write at `/home/evaluser` where the agent runs with Bash and network. The refresh token is a placeholder (KF-048) and the access token's lifetime is bounded by the pre-flight horizon, but `tokens.access_token`, `id_token` and `account_id` are copied — and the codex CLI needs all three (the auditor verified on the host that a copy without `id_token` gets `401 Missing bearer`). Pre-existing in part (the Sprint 258 code copied the whole file, refresh token included); the Sprint 261 diff is an improvement. **Fix `e95139fe`:** a long-lived `OPENAI_API_KEY` never reaches the copy — dropped in ChatGPT mode (unused by codex) and, in API-key mode, copied only under `LOA_EVAL_CODEX_APIKEY_COPY=1` with one WARN line otherwise (the run then has no codex credential and the row flags the degradation); the header states the residual exposure (the bearer readable by the agent for the token's lifetime); `run-ablation.sh`'s header no longer says the file is copied unchanged; pipeline-run.bats +1 (the key never reaches the copy or the docker argv without the knob). **Residual, accepted for this cycle:** the ChatGPT access token stays readable by an Opus agent running the harness's own prompts inside a network-enabled container; the host-side credential holder (proxy or sidecar, or a per-run scoped token) is bead **bd-lfrkn** for the next cycle.

### LOW-1 (DISS-C-003, config) — `collision_rule` reads the fixture's pytest config while pytest reads the tree's: ACCEPTED as a documented gap, bead bd-w0ofw
`remove_harness` (HIGH-A1, Sprint 259/260) removes every agent-added or agent-edited `conftest.py`, `pytest.ini`, `.pytest.ini`, `pyproject.toml`, `setup.cfg` and `tox.ini` that is not byte-identical to the fixture's copy before any command runs (`HARNESS_NAMES`), so an agent cannot inject a config pytest would read; the residual is an agent-edited *fixture* config, which is removed rather than restored (only `grader_protected` paths are restored), so pytest would fall back to defaults while `collision_rule` modelled the fixture's `python_files`. No frozen fixture sets `python_files`, so no row is affected; the restore-or-pass-explicitly fix is **bd-w0ofw**.

## Refuted dissent findings (the envelope itself rejected no payload)

- **DISS-C-002 (MEDIUM, `remove_colliding`): an agent-added `conftest.py` as a `sys.path`/`sys.modules` vector for shadowing a protected sibling import.** REFUTED with evidence: `conftest.py` is in `HARNESS_NAMES` (`ablation-grade.sh` line 339) and `remove_harness()` runs before `remove_colliding()` in `prepare()`, unlinking every `conftest.py` in the grading tree that is not a hidden-overlay dest and not byte-identical to the fixture's copy at the same path — an agent-added `conftest.py` at the tree root or in any ancestor of the hidden tests never survives to the test command (the HIGH-A1 rule of Sprint 259, `grading/<label>.harness-removed.txt` records it); the fixture's own `tests/conftest.py` is `grader_protected` and restored from the frozen fixture. The helper-shadow rule's `conftest.py` exemption therefore concerns only the fixture's conftest, which pytest loads from a directory the agent cannot alter. The dissent voice said it "could not see the call sites"; the lead did.

## Security posture of the sprint diff (verified)
No `eval` with `$`; no `.claude/` sourcing in the harness; no secret value in argv, logs, rows, reports or test names (the KF-048 and API-key cases assert it); the host credential file is never written; the per-run copy is 0600 under a 0700 HOME; the pre-flight prints only the auth file path and ISO instants; the grader's removals are confined to agent-added files that would abort collection or shadow a protected import, each recorded in a sidecar and a counter; the frozen suite and its manifest are untouched by the sprint's code; the fixture PRs are untrusted data throughout.

## Verdict

APPROVED — Sprint 261 is complete. Residuals carried as beads bd-lfrkn (credential holder), bd-w0ofw (fixture pytest config restore), bd-ocovl (no-envelope gates), bd-85o9e (empty-row guard).

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":1},"excluded":0,"sprint_id":"sprint-261","ts":"2026-10-18T10:35:16Z"} -->
