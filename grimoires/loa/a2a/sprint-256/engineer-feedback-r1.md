# Sprint 256 review — round 1 (cycle-129 Sprint 2)

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `40df53ed` (base `b6802e4f`); reports `reviewer.md`, `reviewer-d.md`, `reviewer-e.md`, `reviewer-f.md`
**Dissent:** `adversarial-review.json` — two voices (`codex-headless` gpt-5.5-pro primary, `claude-headless` companion), consensus, confidence floor high, chain ok; 4 findings (1 BLOCKING, 3 advisory), 0 rejected payloads

The code was read, not the reports: `implement-gate.sh` (config loader, sanction order, marker check, decision block), `run-checkpoint.sh` (`resolve` table, `cmd_derive`, `mark`/`unmark`), the full FR-6 classifier hunk and the lead's in-place fix, `profile-lib.sh` (seams, floor filter, `loa_knob`), `validate-skill-capabilities.sh` (the pure-review rule), the corpus rows B79–B89 and D101–D142 with their results under three hooks (`40df53ed`, `b6802e4f`, `864069f2`), the hooks-reference and CHANGELOG hunks, and the 616-case bats run plus the corpus on the integrated tree. Every dissent finding was checked against the tree before it was kept or refuted.

## Findings

### HIGH-1 — backtick command substitution is inert to the fence, and B79/B84 now pin that as the expected result (dissent DISS-C-001, confirmed and widened)

Rows B79 and B84 use an unquoted delimiter and wrap the dangerous command in backticks; bash expands the body of an unquoted heredoc before the consumer sees it, so the row commands would actually merge the spike branch (B79) and force-push (B84). Both carry `expect: allow`, so the corpus — the fence's gate spec — now requires the hook to pass the exact SP-1 and P2 actions it exists to stop. The lead probed the shape outside heredocs with five rows (`~/.cache/loa/cycle-129/fr6-probe2.jsonl`): a force push in backticks inside a double-quoted `echo` argument → allow; a spike merge in backticks inside a double-quoted `printf` argument redirected to a file → allow; the same in a double-quoted assignment → allow; the `$( )` twin of the first → block; the single-quoted twin → allow (correct). The results are identical under the new hook, under `b6802e4f` and under `main` `864069f2`: the hole predates this sprint (the fence treats a backtick span as inert text while it treats `$( )` as a substitution), but this sprint's corpus is the first to document it as expected behaviour, and it contradicts D137/D138 in the same hunk.

Required in the fix round: (a) the fence treats a backtick pair outside single quotes as a command substitution wherever it treats `$( )` — the inert-carrier scrub and the segmenter give the backtick span's inner text its own segment start so P2/SP-1 match, in plain commands and in heredoc bodies under an unquoted delimiter (the classifier's `_hd_synth` path is the natural place for the heredoc case: emit the inner text as a synthetic line before the full scan); (b) B79 and B84 become quoted-delimiter rows (the prose cases keep their coverage) and the unquoted backtick forms become D-rows (spike merge, force push), plus D-rows for the `echo`, `printf` and assignment shapes probed above and a B-row for the single-quoted shape; (c) the hooks-reference SP-1/P2 notes about "another backtick span" gain the quoting qualifier. Expect afterwards: corpus green; `--knob-off` still row-identical to the pre-change hook on the pre-existing rows (the new D-rows differ by design — that is the fix); hook bats green.

### LOW-1 — guardrail readers and `loa_knob` (dissent DISS-C-002; refuted as a defect, kept as a hardening)

Both readers call `loa_knob`: `guardrails-orchestrator.sh` and `danger-level-enforcer.sh` each have three `profile-lib` call sites, and `tools/check-knob-readers.sh` is clean (9 keys). Hardening: add `tools/check-knob-readers.sh` to the Shell Tests workflow so a regression to a bare `yq '.key // true'` read fails CI.

### LOW-2 — knob-off replay reads the right config (dissent DISS-C-003; refuted as a defect, kept as a hardening)

`run-corpus.sh:43` exports `LOA_REPO_ROOT="$work"` and the hook's `_bdb_heredoc_knob_on` reads `${LOA_REPO_ROOT:-${CLAUDE_PROJECT_DIR:-.}}/.loa.config.yaml`, and the knob-off run demonstrably diverges from the knob-on run (the prose probe rows block only with the knob off). Hardening: at the top of a `--knob-off` run assert one known-divergent row flips (D122 or D123 exit 2 only with the classifier on), so a future config-resolution change cannot make the comparison compare the hook with itself.

### LOW-3 — GNU-only `touch -d` in KS-5 (dissent DISS-C-004)

`tests/unit/karpathy-surgical-diff.bats:112` backdates fixtures with `touch -d "2026-01-01 00:00:$i"`; BSD/macOS `touch -d` rejects the space-separated form. Use `touch -t "202601010000.$i"` (two-digit seconds already come from `seq -w`).

### LOW-4 — the implementing-skill marker's window

`check_implement_marker` accepts a marker up to 7,200 s old. A session that crashes between `mark` and `unmark` leaves App-Zone writes sanctioned for two hours under every mode. Same trust class as the `.run` state files (documented in Accepted gaps); consider an `unmark` on SessionEnd or a shorter window. No change required this round.

### LOW-5 — `LOA_PROFILE_CONFIG_FILE` is an ungated seam

`profile-lib.sh:61` honours `LOA_PROFILE_CONFIG_FILE` outside bats (F-7, DEC-0271: hooks pass their own seam through it), so an environment variable can point every optional-knob reader at another file. Floor keys are excluded by design, so the blast radius is the optional surfaces. Document the seam in the example's `loa:` block or gate it like `LOA_STATUS_CONFIG_FILE`.

### LOW-6 — surgical-diff hook cost per write

The hook now runs `run-checkpoint.sh read --json` (and `br show` when a checkpoint names a bead) on every Write/Edit: 43 ms without run state, about 107 ms with (F's measurements). Acceptable; record the budget next to the fence's in the hooks reference.

### LOW-7 — AC-2.12 is Partial

The full bats sweep (≈13 h locally) and vitest (`bridgebuilder-review` has no `node_modules`) were not run on the final tree; the PR's CI run and Sprint 3 Task 3.4's `npm ci` close it. The 14 pre-existing failures F found on pristine `b6802e4f` (five files, listed in `reviewer.md`) must be triaged or filed as beads before the cycle PR.

## Refuted or accepted without action

- DISS-C-002 and DISS-C-003 as defects: refuted with the call sites and the divergence evidence above (kept as LOW hardenings).
- D's SDD-over-PRD reading for the drift fixture (DEC-0258), F's `rtfm-testing` reclassification (DEC-0266) and E's quoted-delimiter reading (DEC-0259): accepted; the single-quoted probe row confirms quoted contexts are literal.
- `gh api -X DELETE` has no fence rule (B89): a documented miss, candidate for a follow-up row; not this sprint's regression.
- The checksums manifest's 7-entry gap predates the sprint (recorded in the report).
- The main-session harness probe cost this session its Write/Edit tools (KF-043): a process finding, recorded; the fix round therefore runs in a fresh session.

## Acceptance criteria

AC-2.1 … AC-2.7, AC-2.9 … AC-2.11 as reported (met). AC-2.8 is Partial until HIGH-1 lands (two allow rows pin executing commands). AC-2.12 Partial as reported.

## Verdict

CHANGES_REQUIRED — one HIGH. Fix round: HIGH-1 (a)–(c), LOW-1 … LOW-3 (cheap, same files), then rerun the corpus (knob on; `--knob-off --rows` diff against `b6802e4f`), the hook bats and the skill-capabilities validator, update `reviewer.md` (AC-2.8 evidence, the probe rows as corpus ids), commit, and re-run the review dissent on the committed range.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":7},"excluded":0,"sprint_id":"sprint-256","ts":"2026-10-14T03:40:00Z"} -->
