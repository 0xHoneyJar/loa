All good

Sprint 4 (global sprint 250) has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 4 Review Feedback (cycle-126, global sprint 250) — round 2, approval

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, unattended `/run sprint-plan`, review round 2). No new dissent run this round: the per-sprint cap of three review runs was spent in round 1, so the dissent record for this gate is the standing envelope `adversarial-review.json` (the run-3 merge, `metadata.head 64c2eb09`, `voices_planned 2 / voices_succeeded 2` on both chunks, `rejected_summary []`, `rejected_count 0`), triaged in `review-dissent-triage-run-{1,2,3}.md` and verified in the code in round 1. An audit dissent was running in this directory during this pass, so no ledger-hash comparison was used as evidence.
**Date:** 2026-10-07
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 4 (Final), global 250 via `ledger.json`
**Implementation Report:** grimoires/loa/a2a/sprint-250/reviewer.md
**Previous feedback:** round 1 at `27ff5a4b` (CHANGES_REQUIRED, 0 critical / 2 high / 3 medium / 7 low)
**Tree reviewed:** `feature/cycle-126-full-size` at `db49cd32` (round-1 fix delta `27ff5a4b..db49cd32`: two commits, 8 files, +33 / −12 — CHANGELOG, migration guide, headless adapter docstring, SDD amendment, sprint.md Task 4.9, checksums.json, REPO-MAP + sidecar; working tree clean)

---

## Overall Assessment

Both round-1 HIGH findings are resolved in the files, not just the report, and no new critical or high issue exists in the tree. The fix delta is documentation plus one docstring; nothing executable changed since round 1, so the round-1 code verification stands and was re-confirmed by re-running the suites each acceptance criterion names.

- **Round-1 HIGH 1 (no `## AC Verification`) — resolved.** `reviewer.md` now carries `## AC Verification (sprint.md)` quoting all five `sprint.md:189-193` criteria verbatim with a status, `file:line` evidence and the test ids. `validate-ac-verification.sh --report … --sprint … --sprint-id sprint-4` exits 0 here. Every cited line was opened: `check-permissions.sh:167` is `rule_key()` and `:242-262` the deny-first loop; `implement-gate.sh:39-50` the lead-only, once, atomic recorder, `:113-117` the config-only mode read, `:122-157` the authoritative branch with its heuristic fallback; `test_trust_scopes.py:360` and `:368` are the two named tests over `_served_anthropic_keys()`; `model-residue.bats:27-89` RES-1–7, `check-permissions.bats:151/163/187/229` CP-11–14, `implement-gate.bats:39-151` IG-1–11, `compliance-hook.bats:151-178` CH-T8–10 and `model-adapter.bats:28-156` MA-1–10 exist at the cited lines with the cited names. AC 1's status says in words that the literal grep is non-empty (152 lines) and why each class is an exception the AC's parenthesis anticipates — the reading round 1 asked for.
- **Round-1 HIGH 2 (CHANGELOG) — resolved.** `CHANGELOG.md:20` (Bridgebuilder alias budget clamp, `GENERATED_MODEL_ALIASES` / `effectiveInputBudget`, tests named), `:21` (universal Bash rules including `Bash(:*)`, CP-14), `:22-31` (recall grader 1.1.2, RG-11–26, the 16-run re-score and the revert outcome) and `:41` under Fixed (east-of-UTC license fixtures, LFF-1–5, the three suites). `docs/migration/v2.0-model-generation-floor.md:265` now names `Bash(:*)`.
- **AC re-verification at `db49cd32`.** Serial, `env -u CLAUDE_HEADLESS_BIN -u AWS_BEARER_TOKEN_BEDROCK`: implement-gate 11/11, check-permissions 14/14, model-residue 7/7, model-adapter 10/10, license-fixture-freshness 5/5, compliance-hook 14/14 — 61 ok, 0 not ok, 0 skip. AC 2 re-derived with `yq`: 16 served Anthropic/Bedrock catalog keys, every one has a `model_permissions` row (`comm -23` empty), and all 16 rows equal the `anthropic:claude-opus-4-7` row on `trust_scopes`, `trust_level`, `capabilities` and `execution_mode` (re-derived with `yq`/`jq`; `test_trust_scopes.py:368` asserts the same). AC 1: the residue grep over `.claude/scripts`, `.claude/skills`, `.claude/data`, `.claude/defaults` (sh/yaml/md/ts/json; dist, tests and `.run` excluded) reproduces the recorded 152 lines once the catalog file itself (43 lines, the fallback chains the AC excepts) and one schema example are set aside — the file set is otherwise identical to `e2e/g4-residue-grep.txt`; the `.py` lines the record's scope leaves out are Observation 3. AC 5: `tools/check-prompt-budget.sh` exit 0 (`CLAUDE.loa.md 10225 B (limit 10240)`, protocols 131,189 B, every SKILL.md ≤ 16,384); `repo-map-gen.sh --validate` "consistent"; `REPO-MAP.md.checksum` equals `sha256(REPO-MAP.md)` (`84e7c925…`); `generate-skill-includes.sh --check` current; `marker-utils.sh verify-hash` exit 0; the one `.claude/` file changed since round 1 (`claude_headless_adapter.py`) hashes to its `checksums.json` entry (`cad0a0b1…`) and compiles (`python3 -I -m py_compile`). `README.md:24` names the cycle.
- **Full unit run at `db49cd32` (round-1 Observation 8) — verified from the tap, not the report.** `~/.cache/loa/cycle-126-dissent/fullrun-r6/`: `meta.txt` head `db49cd32`, 2026-10-07T00:11:00Z–00:59:01Z; `unit.tap` plan `1..6229`, 6,203 `ok`, 26 `not ok`, 130 `# skip`. The 26 by suite: `publication` 22 (tests 3982–4003), `semver evidence` 3 (4710, 4711, 4713), `template-safety` 1 (5451, the operator-local `vision-021.md`) — exactly the recorded residual classes (KF-034 plus local state), a strict subset of Task 4.7's 42, nothing new red. LSP-1 passed (`ok 3158`). `unit.err`'s two "Killed … sleep" lines are CMP-30 (`ok 111`) reaping its deliberately TERM-ignoring stub. The sha pairs in `sha-before.txt` / `sha-after.txt` are identical as recorded by the lead; they were not re-derived here because the audit dissent is appending the ledgers during this pass.
- **Documentation verification (no subagent reports present; checked by hand).** A CHANGELOG entry per task (the sprint-250 bullet at `:18` plus the four round-1 lines); no new command or skill this sprint, so no CLAUDE.md entry is due (`agent-types.yaml` is data); the security-relevant recorder is commented in place (`implement-gate.sh:39`); the architecture change is in the SDD (`sdd.md:88`, round-1 Observation 2) and the plan (`sprint.md:204`, Task 4.9).
- **Dissent coverage.** The standing envelope's head is `64c2eb09`; round r250-4 (`27ff5a4b`), `39bfff76` and `db49cd32` are not covered by a review dissent run because the cap is spent. Those three commits are a grader parser fix with RG-25/26, MA-10, a header line, and documentation; they were read line by line in round 1 and here, and the audit dissent now running covers the full sprint diff `2fcd4af8..db49cd32`.
- **Complexity and Karpathy.** No executable code changed since round 1 ("Lean already. Ship." stands). The fix commits are surgical: the amendment is one dated bullet after the decision it supersedes rather than a rewrite of D-4.1, the migration caveat is one bullet, the CHANGELOG lines name their tests.

**Verdict:** APPROVED

---

## Previous Feedback Status

| Round-1 item | Status | Verified how |
|---|---|---|
| HIGH 1 — `reviewer.md` lacked `## AC Verification` | Resolved | Section present, five ACs verbatim; validator exit 0; every `file:line` and test id opened (above) |
| HIGH 2 — CHANGELOG missing (a) BB alias budget clamp, (b) universal Bash rules, (c) east-of-UTC license fix, (d) grader 1.1.2; migration guide omitted `Bash(:*)` | Resolved | `CHANGELOG.md:20`, `:21`, `:41`, `:22-31`; `v2.0-model-generation-floor.md:265` |
| MED 1 — authoritative mode trusts a model-authored field | Carried (by design, non-blocking) | Unchanged in `implement-gate.sh:122-137`, as the plan accepted; follow-up bead filed by the lead; recorded again as Observation 1 |
| MED 2 — `opus → claude-opus-5-5` retarget in no plan document | Resolved | `sdd.md:88` dated amendment after D-4.3 (bd-2fti, vendor-sourced entry, 180K ceiling, fallback chain); `sprint.md:204` Task 4.9 |
| MED 3 — effort default lowered for `opus` callers that pass none | Resolved (documented) | `v2.0-model-generation-floor.md:268-273` caveat ("pass `--effort high`"); follow-up bead bd-9qe2 filed by the lead |
| LOW 4 — headless adapter docstring bound `opus`/`cheap` to 4.x ids | Resolved | `claude_headless_adapter.py:138-148` now `claude-opus-5-5` / `claude-sonnet-5`; no `claude-opus-4-7` or `claude-sonnet-4-6` left in the file; `py_compile` OK |
| LOW 5 — Aleph example departs from D-4.3 without saying so | Resolved | The `sdd.md:88` amendment records the `loa-aleph` deviation under the standing Aleph policy |
| LOW 6 — no NOTES Decision Log entry for Sprint 4's rulings | Resolved | `NOTES.md:61` (round-1 verdict and the two HIGHs) and `:72` (follow-up, full run, audit dissent launch) |
| LOW 7 — pre-registration ordering unverifiable until the a2a record branch exists | Carried | Cycle-end action (record branch push); Observation 4 |
| LOW 8 — full unit run was six commits behind | Resolved | `fullrun-r6` at `db49cd32`, classification verified from the tap (above) |
| LOW 9 — sibling 5-family entries carry an unverified long-context tier | Carried | Pre-existing (cycle-124); follow-up bead filed by the lead; Observation 5 |
| LOW 10 — LSP-1 load-sensitive | Closed for this round | `ok 3158` in the full run; the Known-flakes entry stands |

---

## Observations

### 1. In authoritative mode the trust boundary is a model-authored field (carried from round 1)

- **MEDIUM** (confidence: high) `.claude/hooks/compliance/implement-gate.sh:122-137` — with `implement_gate.mode: authoritative` set, a Write to `src/` whose `tool_input.active_skill` reads `implement` exits 0 silently (IG-7 pins this), while the heuristic branch would `ask`; the field is model-authored (the Task 4.4 research outcome), so the opt-in is weaker than the default. Accepted by the plan (key undocumented, IG-11; `/loa` evidence line, IG-10) and now tracked in the lead's follow-up beads; recorded so the audit sees it. Suggested shape unchanged: write one `compliance.mode.model_signal` audit row when the branch is taken, or treat the opt-in as heuristic plus WARN until a harness signal exists. CWE-807, bounded by the opt-in and the hook's `ask` semantics.

### 2. Two derived SDD lines still describe the Bridgebuilder default as Opus 5

- **LOW** (confidence: high) `grimoires/loa/sdd.md:57` and `:149` — the cost table row reads "Bridgebuilder pass | … | Opus 5, ≤ 200K in / ≤ 32K out ≈ $1.8", and the ceiling worked example lists "Fable 5.1 / Opus 5 / Sonnet 5" only. After the retarget the BB default `opus` resolves to `claude-opus-5-5` ($4 / $20 per MTok, BB `maxInput 160000`), so the row's model name and estimate are stale and the example omits the entry the default now hits. The `:88` amendment records the decision, not these two derived lines. Scenario: a reader budgets a BB pass from the table. Fix: one-line edits (model name; ≈ $1.3 at 160K in / 32K out) or a pointer to the amendment.

### 3. Previous-generation ids in `.py` files sit outside the recorded residue grep's scope

- **LOW** (confidence: high) `.claude/scripts/lib/model-overlay-hook.py:407,410`, `.claude/scripts/lib/model-config-migrate.py:259`, `.claude/scripts/loa-migrate-model-config.py:326`, `.claude/scripts/lib/model-resolver.py:370`, `.claude/data/trajectory-schemas/model-error.schema.json:53` — a grep over the AC's three directories that admits `*.py` finds five more lines than `e2e/g4-residue-grep.txt`: a design-note docstring showing the emitted bash form, the migrator's reasoning-class prefix matcher (`"claude-opus-4-"`, a compat matcher for entries the catalog still serves), a migration help string, a docstring example of the `aliases:` block, and a schema `description` example. None is a default and none describes an old id as current, so AC 1 holds; but the classification table (reviewer.md § Residue grep) cannot say so because the recorded grep's file-type set (sh/yaml/md/ts/json) never saw them. Fix next cycle: add `--include='*.py'` to the recorded grep and a row for examples and migration matchers.

### 4. The A/B pre-registration ordering is still unprovable from version control (carried)

- **LOW** (confidence: high) `grimoires/loa/a2a/sprint-250/replay-ab-rerun.md:55-57,69` — `a2a/` is untracked until the record branch is pushed at cycle end, so the 23:25Z pre-registration and the 23:26Z launch have no commits behind them. Unchanged; the lead's cycle-end push closes it. The suggestion stands: commit pre-registrations to the record branch at the moment they are fixed.

### 5. Sibling 5-family entries keep an unverified long-context tier (carried)

- **LOW** (confidence: medium) `.claude/defaults/model-config.yaml:476-482` — `claude-opus-5-5` omits `long_context` per the vendor statement while `claude-opus-5`, `claude-sonnet-5`, `claude-fable-5-1` keep an `unverified` tier above 200K; cost estimates above 200K on those three ids are over-stated until an invoice settles it. Pre-existing (cycle-124), disclosed in the migration addendum, bead filed by the lead.

---

## Rejected dissent payloads
None — the standing envelope `adversarial-review.json` (the run-3 merge) reads `rejected_summary []`, `rejected_sidecars []`, `rejected_count 0`, `voices_planned 2 / voices_succeeded 2` on both chunks (`s3-shell`, `e3-eval`); the five review sidecars beside this file — `adversarial-rejected-review-{g-gate,k1-kernel,k2-kernel,m1-pins,v-eval}.jsonl` — are each 0 bytes, no row. No review dissent run was made this round (cap of three spent); the audit-gate files appearing in this directory belong to the audit dissent now running and were not read.

---

## Scope of this pass
- No `br` operations, no `.run/` reads or writes, no model calls, no edits to code, `.claude/`, CHANGELOG, docs or the SDD (the lead's round-2 constraints). Trajectory logging to `a2a/trajectory/` was skipped under the same write restriction. `pytest -k headless` (486 passed per the lead) was not re-run here: the docstring change is comment-only and the file compiles.
- Writes made: this file; `sprint.md:189-193` ticked; the sprint-250 row of `a2a/index.md`.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"sprint_id":"sprint-250","ts":"2026-10-07T01:15:00Z"} -->
