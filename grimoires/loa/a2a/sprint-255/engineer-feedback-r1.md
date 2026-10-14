# Sprint 255 review — round 1 (cycle-129 Sprint 1)

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-14
**Implementation:** `ee1625a0` (plan `ffd25258`); reports `reviewer.md`, `reviewer-a.md`, `reviewer-b.md`, `reviewer-c.md`
**Dissent:** `adversarial-review.json` — two voices (`gpt-5.5-pro` primary, `claude-headless` companion), status clean, verdict quality APPROVED (2/2), 7 advisory findings, 0 rejected payloads

The code was read, not the reports: `guard-yield.sh` in full, the fence hunk (`git show ee1625a0`), `validate_sprint_kinds`, `run-arms.sh`, the `execute-agent.sh` toggles, the seeding script's path and redaction logic, `cycle-ratio.sh`, the `loa-status.sh` Guards block, the workflow step, the rule-file frontmatter, `arms-report.py`'s verdict logic and the `compare-ab.py` change. Every AC is walked in `reviewer.md` and `validate-ac-verification.sh` exits 0. The work is close to approval; three MEDIUM items must land first.

## Changes Required

### MEDIUM-001 — `run-arms.sh` default executor and header contradict DEC-0172
`evals/harness/run-arms.sh:45-46,56` set `DEFAULT_MODEL="claude-fable-5-1"` and cite D33, while DEC-0172 (recorded in this sprint from B's own finding) pins the executor to Opus 5.5 because Fable's safeguard fallback breaks homogeneity. A lead who runs the script without `--model` would start a Fable batch. Fix: default `global.anthropic.claude-opus-5-5`, header states DEC-0172 and the model-transfer assumption; `evals/tests/run-arms.bats` RA-1 expectation updated.

### MEDIUM-002 — the floor snapshot never runs in CI
`tests/unit/floor-snapshot.bats:17-18` skips when `origin/main` is unreachable; `.github/workflows/bats-tests.yml` checks out at the default depth 1 with no `origin/main`, so FS-1 … FS-4 (the "floor unchanged" and "register disables nothing" proofs) skip on every CI run and hold only on a developer's machine. Fix: one workflow step after checkout fetching `+refs/heads/main:refs/remotes/origin/main` (no tags, depth 1).

### MEDIUM-003 — a floor gate can be unregistered without tripping the register (dissent DISS-C-003)
`floor.yaml` pins the bytes of `adversarial-review-gate.sh` and the deny template, but neither `guard-yield.sh --check` nor the snapshot requires that a floor gate implemented as a hook is still registered in `.claude/settings.json`, and the live `permissions.deny` list is not pinned. A task could delete the `safety/adversarial-review-gate.sh` registration and its hook row, regenerate, and pass every gate while the COMPLETED-marker check never runs again. Fix: `guard-yield.sh` fails (exit 5) when a `floor: true` gate whose script lives under `.claude/hooks/` has no registered command; `floor-snapshot.bats` FS-5 pins `.permissions.deny` to `origin/main` and FS-6 asserts every floor gate hook is registered.

### LOW-001 — intermediate symlink escapes the hook containment check (dissent DISS-C-002)
`guard-yield.sh:219-229` resolves only the leaf: a symlinked directory under `.claude/` (`hooks/ext -> /opt/x`) passes the schema and `-f`, and the row id points outside `.claude/`. Fix: canonicalise the parent with `pwd -P` and the leaf with `readlink`, then require the physical path to lie under `$ROOT/.claude/`.

### LOW-002 — marker order unchecked in `render_hooks_ref` (dissent DISS-C-006)
A hooks reference with the end marker before the begin marker passes the count check and the awk pass discards every line after the begin marker. Fix: require the begin line number to precede the end line number (exit 3 with the two line numbers).

## Observations

- (observation, speculative, not a finding) DISS-C-005: the burst-replay rule (≥ 10 block rows in one UTC minute) could misclassify a genuine burst of blocks. The yield labels itself a heuristic and reports `replay_rows_by_rule.burst` separately; the register disables nothing. No change this sprint; the Sprint 2 report revisits it with the FR-6 classifier available.
- (observation, by design) DISS-C-004: path-scoped `stash-safety.md` no longer loads on a Bash-only turn. This is DEC-0129; the crosswalk in `reviewer.md` names the two unmechanised judgment rules and the `no_rule_files` arm measures the effect.
- (observation, process) DISS-C-001 and DISS-C-007: the diff handed to the dissent began with an unmerged-index line for the fence and the companion saw a truncated `guard-yield.sh` hunk. The diff was generated from the index while the fence entry was in a 3-way state; the lead reviewed both files in full from the commit, and the audit dissent will run on a diff generated from the committed range (`ffd25258..ee1625a0`, standard prefixes). Recorded as a gotcha in NOTES.
- (observation, note) `guard-yield.sh` uses jq's `IN` builtin (jq 1.6); five other scripts in `.claude/scripts/` already do, and the CI runner's jq is 1.6 or newer. The cycle-128 decisions validator avoided it for a consumer with jq 1.5; if that floor is ever stated for the whole repository, this script follows.

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar exists.

## Verdict

Changes required: three MEDIUM, two LOW. All five are small and the lead lands them in round r255-1; round 2 re-checks them against the suites and `guard-yield.sh --check`.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":2},"excluded":0,"sprint_id":"sprint-255","ts":"2026-10-14T01:05:00Z"} -->
