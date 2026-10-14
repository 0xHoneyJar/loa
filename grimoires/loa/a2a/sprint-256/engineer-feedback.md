All good

Sprint 256 has been reviewed and approved. All acceptance criteria met, with AC-2.12 Partial as recorded (the full-suite proof is the PR's CI run; vitest is Sprint 3's).

## Round 3 (2026-10-14)

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Implementation reviewed:** `5ecf13f5` (base `b6802e4f`; implementation `40df53ed`, fix rounds `3263bbc4` + `b6030e5b`, `77455afb`, `5ecf13f5`); reports `reviewer.md` with three "Feedback Addressed" sections, `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md`
**Dissent:** `adversarial-review.json` (round 3, on `77455afb`) — two voices (`codex-headless` gpt-5.5-pro primary, `claude-headless` companion), consensus, confidence floor high, chain ok; 3 advisories, 0 blocking, 0 rejected payloads. Rounds 1 and 2 are `adversarial-review.json.prev` lineage and are summarised in `engineer-feedback-r1.md` and `engineer-feedback-r2.md`. This sprint used its three review dissent runs.

Round 1 (`engineer-feedback-r1.md`) asked for one HIGH and seven LOW changes; round 2 (`engineer-feedback-r2.md`) for one HIGH and three LOW. Every item landed and was re-checked against the code and the suites:

- HIGH-1 (backtick substitution inert to the fence): the heredoc-aware normalisation rewrites a backtick pair outside single quotes to the dollar-paren form before any rule runs; unquoted heredoc bodies alternate every backtick, quoted bodies and single quotes stay literal, unbalanced shell quotes fail closed. Corpus D143–D155 block (unquoted-heredoc, `echo`, `printf`, assignment, dollar-paren twin, apostrophe, dash form, mixed quoting, two heredocs, pipeline member, header-line shapes); B79, B81, B84, B86, B90–B94 allow; the knob-off replay differs from the `b6802e4f` hook on exactly the twelve backtick D-rows (DEC-0296, DEC-0298). The first normaliser's miss (an apostrophe in prose) was caught by D144 before commit.
- HIGH-2 (the example pinned eight of nine profile keys): the nine keys appear in the example only as commented, profile-governed lines; PL-4 pins null raw keys, `standard` as the effective value, and `lean`/`full` copies resolving every key with no override; AC-2.4 restated (DEC-0299).
- LOW-1 … LOW-3, LOW-5 (round 1) and LOW-8 … LOW-10 (round 2): CI step for `check-knob-readers.sh`; knob-off self-check; POSIX `touch -t`; `LOA_PROFILE_CONFIG_FILE` documented; negated bats assertions as `run` + status (LI-2/3/5/8, PL-1; DEC-0301); the knob lint escapes every ERE metacharacter, skips binaries, fails on a grep error; `--knob-off` requires the D122 sentinel unless `--no-self-check` (DEC-0300).
- Found on the live tree while re-running the example-reading suites, fixed in r256-2: CMP-188 — the shared includes F rerouted prescribe `profile-lib.sh knob …` in `reviewing-code` and `auditing-security` but no Bash grant admitted it under `deny_raw_shell`; both skills now grant `Bash(.claude/scripts/lib/profile-lib.sh knob *)` in `allowed-tools` and `capabilities` with byte-neutral trims (16,379 and 16,317 B); `karpathy-config-schema.bats` lacked the new `KARPATHY_STATE_DIR` seam and read this session's live accumulator (F's worktree run passed by chance) — seam added, and the 7-keys case expects the two profile-governed keys commented.
- Round 3 advisories, applied in `5ecf13f5` before this approval (LOW-11 … LOW-13): `check-knob-readers.sh` searches only existing directories and quotes grep's stderr; `run-corpus.sh --knob-off` carries a positive control (D01 must still block; DEC-0303); the corpus gains the `miss` class for documented false negatives and B89 became M01 (DEC-0302); the corpus hygiene lint uses `run` + status and admits the class; D107 uses a bare host alias.

What was read for this round, as code: the landed `_bdb_backtick_norm` and its two helpers, the `_bdb_hd_scan_body` strip, the call site; the example's nine commented keys and the `loa:` block; PL-4 and the rewritten LI cases; the two gate skills' frontmatter and capabilities; `check-knob-readers.sh`; `run-corpus.sh` end to end; the corpus rows added in the three rounds. Suites on `5ecf13f5`: fence corpus `benign 93/93 dangerous 155/155 residual 0/5 miss 1/1` (knob on), knob-off with both controls, probe corpora R01–R10 and Q01–Q10 as expected; hook bats 476/0 (r256-1 tree) plus the corpus-gate cases, profile-lib 17/17, profile-floor 7/7, lint-invariants 9/9, karpathy-config-schema 3/3, skill-capabilities, prompt-budget, prompt-audit-keeplist, CMP-188, implement-gate 33/33, the thirteen example-reading suites (424 pass / 0 fail after the fixes); lints green (budget, knob readers, skill capabilities, register drift, validate-constraints, raw sha256, lint self-test).

## Carried (no change required)

- LOW-4: the implementing-skill marker sanctions App-Zone writes for 7,200 s after `mark`; a crashed session leaves the window open (accepted trust class; an `unmark` on SessionEnd is a candidate for Sprint 3's docs pass or a bead).
- LOW-6: `karpathy-surgical-diff-check.sh` costs 43–107 ms per Write/Edit; record the budget in the hooks reference (Sprint 3 Task 3.6).
- LOW-7: AC-2.12 Partial — the full bats sweep and vitest run with the cycle PR's CI; the 14 pre-existing failures F listed on `b6802e4f` are to be triaged with it.
- The `gh api -X DELETE` miss (M01) is a candidate fence rule for a follow-up.

## Rejected dissent payloads

None: the three envelopes report 0 rejected payloads and no `adversarial-rejected-review*.jsonl` sidecar exists.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":3},"excluded":0,"sprint_id":"sprint-256","ts":"2026-10-14T04:58:00Z"} -->
