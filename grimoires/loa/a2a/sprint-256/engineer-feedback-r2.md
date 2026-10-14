# Sprint 256 review — round 2 (cycle-129 Sprint 2)

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `3263bbc4` + `b6030e5b` (fix round r256-1 on `40df53ed`; base `b6802e4f`); reports `reviewer.md` (with "Feedback Addressed (review round r256-1)"), `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md`
**Dissent:** `adversarial-review.json` (round 2) — two voices (`codex-headless` gpt-5.5-pro primary, `claude-headless` companion), consensus, confidence floor high, chain ok; 4 findings (1 BLOCKING, 3 advisory), 0 rejected payloads. Round 1's envelope is `adversarial-review.json.prev`.

## Round 1 items

HIGH-1 (backtick substitution) is closed: the heredoc-aware normalisation lands the dollar-paren form before any rule runs; D143–D155 block and B79, B81, B84, B86, B90–B94 allow; the knob-off replay differs from the `b6802e4f` hook on exactly the twelve backtick D-rows (DEC-0296); the ten edge-case probes (apostrophes inside double quotes and in unquoted bodies, the dash form, escaped backticks, mixed quoting, two heredocs, a pipeline member, a header-line substitution) all read as expected and are now corpus rows. The first normaliser's miss (an apostrophe opening a phantom single quote across a heredoc body) was found by D144 and fixed before commit; the fail-closed rule for unbalanced shell quotes covers the shape generally. LOW-1, LOW-2, LOW-3 and LOW-5 are closed as reported; LOW-4, LOW-6 and LOW-7 are carried as recorded. KF-043's scope is corrected (DEC-0297).

## Findings

### HIGH-2 — the example pins eight of the nine profile keys, so `loa.profile` governs almost nothing in a copied config (dissent DISS-C-001, confirmed)

`.loa.config.yaml.example` ships explicit values for `known_failures.surface_at_session_start`, `decisions.surface_at_session_start`, `karpathy_principles.surgical_diff_warning`, `karpathy_principles.require_success_criteria`, `guardrails.input.enabled`, `guardrails.danger_level.enforce`, `invisible_retrospective.enabled` and `structured_handoff.enabled`, and in the same file advertises `loa.profile: full` as turning the optional surfaces on. Because an explicit key beats the profile by design (D-9.1), an operator who copies the example — the documented install path — and sets `full` changes only `soul_identity_doc.enabled`; under `full` the guardrails and the danger-level enforcement stay off, silently. F's report named this as a known limitation ("a copied example defeats `lean`") and round 1 let it stand; the dissent is right that it defeats FR-9's purpose ("one knob sets the optional surfaces") and that the guardrails case is security-adjacent. The `/loa` overrides list shows the pins but does not stop them.

Required in the fix round: (a) in the example, every profile-governed key is present as a commented line with its `standard` value and a note that `loa.profile` governs it ("uncomment to pin"), so a copied example follows the profile; the `loa:` block says so; (b) a bats assertion that `yq '.<key>'` on the example is null for every key in `profiles.yaml` (`profile-lib.bats`), and the oracle comparison (PL-3/PL-4) compares the profile's `standard` values with the example's EFFECTIVE values through `loa_knob`, not with raw keys; (c) AC-2.4's "the example reads `false` for both guardrail keys" is restated as the effective value under `standard` with the raw key commented (the sprint-plan AC is amended and the report says why); this repository's `.loa.config.yaml` keeps its explicit `guardrails` block (an intended override). Expect: `profile-lib.bats`, `profile-floor.bats`, `guardrails-orchestrator-file-input.bats`, `karpathy-config-schema.bats` and the example-reading bats green; `/loa` on a copy of the example under `lean` and `full` prints the profile with `explicit overrides: none`.

### LOW-8 — bare `!`-negated assertions mid-test (dissent DISS-C-002)

`tests/unit/lint-invariants.bats` LI-2, LI-3 and LI-8 use `! grep …` / `! echo … | jq -e …` in the middle of a test. Under bats a negated pipeline is exempt from errexit, so these lines cannot fail unless they are the test's last line; LI-8's "no ERROR-level agent_teams result" check is dead today. Replace each with `run` plus a status assertion (the pattern the old IG-11 comment recorded).

### LOW-9 — `tools/check-knob-readers.sh` robustness (dissent DISS-C-003)

Only dots are escaped when the alternation is built, `grep -r` lacks `-I`, stderr is discarded and `|| true` masks a grep exit 2, so a future key with an ERE metacharacter would make the lint print "no direct profile-key reads" and exit 0. Escape every ERE metacharacter, add `-I`, and treat grep exit 2 as a hard error.

### LOW-10 — the `--knob-off` self-check is skipped silently when the corpus has no D122 (dissent DISS-C-004)

`run-corpus.sh` fires the self-check only when D122 was seen; `--knob-off --corpus <other>` exits 0 without proving the knob reached the hook. Under `--knob-off`, an unseen D122 exits 3 unless `--no-self-check` is passed (the probe corpora are the one legitimate case); the header states that the knob reaches the hook through `LOA_REPO_ROOT`.

## Refuted or accepted without action

- None of the round-2 findings is refuted. The backtick fix drew no finding from either voice.

## Acceptance criteria

AC-2.8 is now met (the backtick rows are corpus rows; the knob-off comparison is identical on every row the pre-change hook saw). AC-2.4 needs the restatement under HIGH-2 (c). AC-2.9 is met as built but the example defeats the profile it documents (HIGH-2). AC-2.12 stays Partial as recorded.

## Verdict

CHANGES_REQUIRED — one HIGH. Fix round r256-2: HIGH-2 (a)–(c), LOW-8, LOW-9, LOW-10; rerun the profile suites, the lint-invariants suite, the corpus (knob on and `--knob-off`) and the hook bats; update `reviewer.md` (AC-2.4 and AC-2.9 evidence, a second "Feedback Addressed" section); commit; re-run the review dissent (the sprint's third and last review run) and the review.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-256","ts":"2026-10-14T04:20:00Z"} -->
