**[1/3] Review by anthropic (claude-headless)**

<!-- bridge-findings-start -->
```json
{
  "schema_version": 1,
  "findings": [
    {
      "id": "F-001",
      "title": "Surface hook's jq `clean` regex is malformed: `\\^` is not a jq string escape (compile error) and `@-\\^` is a range covering A-Z",
      "severity": "HIGH",
      "category": "correctness",
      "file": ".claude/hooks/session-start/loa-decisions-surface.sh",
      "description": "The row-rendering jq program defines `clean` with `gsub(\"[[:cntrl:]\\^@-\\^_  ]\"; \" \")`. jq string literals accept only the JSON escapes, so `\\^` is rejected at compile time with 'Invalid escape'; the whole program fails under `2>/dev/null || true`, `rows` is empty, `n_prop`/`n_open` stay 0 and the hook exits silently even when enabled with proposed rows. If a jq build did accept the literal, the bracket would parse as `^`, the range `@`..`^` (which includes `A`-`Z`, `[`, `\\`, `]`) and `_`, so every uppercase letter in a summary would be replaced by a space. Either way the caret-notation control range (`^@`..`^_`) is redundant with `[[:cntrl:]]` and does not do what the comment describes.",
      "suggestion": "Replace the bracket with `[[:cntrl:]\\u2028\\u2029]` (jq `\\u` escapes are valid) or write the two separator characters as literal UTF-8 and drop the caret range. Add a bats case that enables the surface with one proposed row whose summary contains uppercase letters and asserts the summary text appears in stdout verbatim.",
      "confidence": 0.6
    },
    {
      "id": "F-002",
      "title": "Append-only check against the merge-base copy rejects legitimate multi-write lifecycles on one branch",
      "severity": "MEDIUM",
      "category": "correctness",
      "file": ".claude/scripts/validate-artifact.sh",
      "description": "Without `--base-file`, `validate_decisions` compares against the ledger at `git merge-base origin/main HEAD` and applies the same per-write invariants the writer uses: `more than one transition appended in one write` fires when `$rl - $bl > 1`, and every content-edit allowance is keyed on the last transition only (`$t = $r.transitions[-1]`). A row that was `open` on main and went open -> proposed -> decided on the branch accumulates two transitions and a `decision` set while `$t.to == \"decided\"`, so a PR-time run fails with 'more than one transition appended' and 'content edit to decision' although each individual write passed the writer's gate. This PR is unaffected only because the ledger does not yet exist on main.",
      "suggestion": "In merge-base mode, relax the per-write checks to history checks: allow any number of appended transitions as long as the base prefix is unchanged and each appended step is a legal transition, and permit a content field to be set if any appended transition (not only the last) legitimises it. Keep the strict single-write rules for the `--base-file` path the writer uses, and add a bats case that validates a branch ledger holding an open->proposed->decided row against its base.",
      "confidence": 0.75
    },
    {
      "id": "F-003",
      "title": "PRD Status line as an unattended signal makes operator attribution unreachable while the PRD says 'autonomous run'",
      "severity": "MEDIUM",
      "category": "design",
      "file": ".claude/scripts/lib/dec-write-lib.sh",
      "description": "`ctx_signals` reports `prd prd-status:` whenever `grimoires/loa/prd.md` has a Status line matching `autonomous|unattended`, and `is_unattended` is true on any signal. In `op_confirm`, `derive_attribution 0` then discards `--answer-ref` with a WARN, so `decided_by` becomes the proposing voice (`agent`) rather than `operator` even though the operator is running `/decisions confirm` interactively and the transition records `by: operator:decisions-command`. `op_reject` of a decided row dies under the same signal, `op_supersede` by the operator is downgraded to an agent proposal, and `chart-ticket.sh need_interactive` refuses every `/chart` write. In this repository the live prd.md carries 'Draft — autonomous run', so confirming the seeded rows would attribute all of them to `agent`, which defeats G-1 ('who decided it'). The dec-write-lib tests confirm without `--answer-ref` under this signal and therefore do not catch the dropped ref.",
      "suggestion": "Treat the PRD Status line as a signal for PRD validation and for `new`/`decide` defaults only, not for the operator-only operations: in `op_confirm`, `op_reject` (decided) and `op_supersede` gate on `live_run_signal` alone, or let an explicit operator-grammar `--answer-ref` win over the PRD-status signal with a WARN. Add a test: PRD Status autonomous, no live signal, `confirm --answer-ref cli:...` yields `decided_by: operator`.",
      "confidence": 0.6
    },
    {
      "id": "F-004",
      "title": "Undated live sprint plan now FAILS the Seams gate, contradicting the PRD's 'undated plans WARN only' and the script's own usage header",
      "severity": "MEDIUM",
      "category": "spec-drift",
      "file": ".claude/scripts/validate-artifact.sh",
      "description": "`validate_sprint_seams` adds a violation for any plan under `grimoires/loa/` (outside `archive/`) whose header has no parseable `**Date:**`. PRD FR-7 and the usage comment at the top of the script both state that older and undated plans WARN only; the function comment states the opposite. A consumer project with an existing `grimoires/loa/sprint.md` lacking a bold Date header moves from pass to exit 1 on upgrade, in a code path that run mode and `/sprint-plan` validation exercise.",
      "suggestion": "Either downgrade the undated-live-plan case to a WARN as the PRD specifies, or update PRD FR-7, the usage header and CHANGELOG to state the fail-closed rule and add a migration note telling operators to add `**Date:**` to live plans.",
      "confidence": 0.55
    },
    {
      "id": "F-005",
      "title": "`chart-ticket.sh epic` creates the epic bead before the map doc without a slug lookup, so a doc-write failure duplicates epics",
      "severity": "LOW",
      "category": "robustness",
      "file": ".claude/scripts/chart-ticket.sh",
      "description": "`op_epic` returns early only when the map doc exists. It then runs `br create ... --slug map-${SLUG}` and writes the doc afterwards. If `mkdir`/`mktemp`/`mv` fails, or the doc is deleted, the next run creates a second `map` epic with the same slug. Tickets are made idempotent by `source`/`external_ref`, but the epic step has no equivalent key even though `--slug map-<slug>` is available.",
      "suggestion": "Before `br create`, look up an existing epic with label `map` and slug `map-${SLUG}` (or title `Map: <title>`) in `beads_all` and reuse its id; write the doc through the same temp-and-rename path and report the reuse on stderr.",
      "confidence": 0.6
    },
    {
      "id": "F-006",
      "title": "Dependency symlinks into worktrees let `--setup` and tests mutate the live tree's node_modules/.venv/vendor",
      "severity": "LOW",
      "category": "safety",
      "file": ".claude/scripts/red-test-check.sh",
      "description": "`link_deps` symlinks `node_modules .venv vendor target .tox` from the live checkout into each worktree, then `--setup` and the test argv run with cwd in the worktree. A project `npm run <script>` or `make` target that rebuilds or cleans those directories writes through the symlink into the live tree. The header documents this, and `--no-link-deps` exists, but linking stays on by default even when `--setup` is given, which is the case most likely to rewrite dependencies.",
      "suggestion": "Disable dependency linking by default when `--setup` is present (setup is expected to provision the worktree), or require an explicit `--link-deps` with `--setup`. Print the linked directories before the first run so the reviewer sees the exposure.",
      "confidence": 0.5
    },
    {
      "id": "F-007",
      "title": "SDD Open Questions check matches 'Unresolved' as Resolved",
      "severity": "LOW",
      "category": "correctness",
      "file": ".claude/scripts/validate-artifact.sh",
      "description": "`validate_sdd_open_questions` uses `tolower(c[st]) ~ /resolved/`, which also matches a Status cell of `Unresolved`, producing a false WARN for rows that are still open.",
      "suggestion": "Anchor the match on the trimmed cell, for example `trim(tolower(c[st])) ~ /^resolved/` or an exact comparison against `resolved`.",
      "confidence": 0.8
    },
    {
      "id": "F-008",
      "title": "New tests use GNU-only sed syntax (`0,/re/` address, `1i text`) that fails on macOS/BSD sed",
      "severity": "LOW",
      "category": "portability",
      "file": "tests/unit/validate-artifact.bats",
      "description": "The map ordering test uses `sed 's/...; 0,/^## Decisions so far$/!{...}'`, and `tests/unit/red-test-check.bats` RTC-21 uses `sed -i.bak '1i #!/bin/sh'`. Both forms are GNU extensions; BSD sed rejects the `0,` address and requires `1i\\` followed by a newline. The sprint plan claims a BSD/macOS matrix for the new scripts.",
      "suggestion": "Replace the `0,/re/` edit with an awk rewrite of the two headings, and build the shebang-prefixed fixture with `{ printf '#!/bin/sh\\n'; cat file; } > tmp && mv tmp file`.",
      "confidence": 0.75
    },
    {
      "id": "F-009",
      "title": "sprint.md contradicts the implemented and decided behaviour in three places",
      "severity": "LOW",
      "category": "documentation",
      "file": "grimoires/loa/sprint.md",
      "description": "Sprint 1 Deliverables say the ledger is 'seeded with cycle-127 D1–D3 as `decided`', while Task 1.6, PRD D16 and the writer's rules make every seed row `proposed`. Appendix D says the red-test command 'stays free-form ... rather than an allowlisted runner', while `red-test-check.sh` ships a strict runner allowlist (r254-2) and refuses shells. Appendix A still lists every FR as 'Planned' although all tasks are checked.",
      "suggestion": "Update the Deliverables bullet to `proposed`, replace the Appendix D sentence with the allowlist decision and its config keys, and set Appendix A statuses to Complete.",
      "confidence": 0.8
    },
    {
      "id": "F-010",
      "title": "The PRD mandates `[ASSUMPTION decision]` tags with DEC rows but its own 21 decisions carry no tags, so the new gate is vacuous on the document that introduces it",
      "severity": "LOW",
      "category": "process",
      "file": "grimoires/loa/prd.md",
      "description": "FR-2 and the validator's tag-to-row rule fire only on `[ASSUMPTION decision]` lines. Appendix E lists D1–D21 taken unattended as a table with no tags, and the Assumptions section carries only `[ASSUMPTION fact]`. The PRD's Status line marks it unattended, so a tagged version would exercise the FAIL path against the seeded rows; the untagged version passes without checking anything. The KPI '100 % of [ASSUMPTION] decisions in this cycle's own PRD' therefore has no mechanical measurement.",
      "suggestion": "Tag each Appendix E row (or its first sentence in the body) with `[ASSUMPTION decision] (DEC-NNNN)` citing the seeded row whose `source` names prd.md, so `validate-artifact --type prd` verifies the mapping the PRD promises.",
      "confidence": 0.7
    },
    {
      "id": "F-011",
      "title": "`sanitize_for_session_start` is called with inline content in one caller and with a file path in two others",
      "severity": "SPECULATION",
      "category": "consistency",
      "file": ".claude/scripts/chart-ticket.sh",
      "description": "`loa-decisions-surface.sh` passes `\"$block\"` (text) as the second argument; `chart-ticket.sh fence_append` and `red-test-check.sh fence_tail` pass `\"$n\"` (a temp file path). `context-isolation-lib.sh` is not in the diff, so it is not visible whether the function accepts both. If it accepts only one form, one caller takes the `sanitizer unavailable` fallback on every invocation (the surface prints its WARNING line, or the snapshot fences the literal path string).",
      "suggestion": "Confirm the function's contract and use one form in all three callers; add a bats assertion in each suite that the fenced block contains the expected content, not a path.",
      "confidence": 0.3
    },
    {
      "id": "F-012",
      "title": "`--type decisions` depends on jq 1.6 builtins (`IN`) with no dependency check, while the glossary checker is kept jq 1.5-compatible",
      "severity": "LOW",
      "category": "portability",
      "file": ".claude/scripts/validate-artifact.sh",
      "description": "`validate_decisions` uses `IN(...)` throughout, and `dec-write-lib.sh import` uses `walk`, both absent from jq 1.5. The validator preflights yq v4 (`_dec_have_yq4`) but not jq, so on a jq 1.5 host the result is 'decisions validator failed to evaluate' with a cryptic first error line. `tests/unit/glossary-terms.bats` GT-26 explicitly guards jq 1.5 portability for `check-glossary-terms.sh`, so the repo's floor is inconsistent.",
      "suggestion": "Either state jq 1.6 as the floor repo-wide (and drop GT-26), or add a jq version preflight to `validate_decisions` that emits one clear violation naming the requirement.",
      "confidence": 0.5
    },
    {
      "id": "F-013",
      "title": "`close --consumed-by` is not idempotent: a second consume of an already `closed` map dies with 'was not handed off'",
      "severity": "LOW",
      "category": "robustness",
      "file": ".claude/scripts/chart-ticket.sh",
      "description": "`op_close` with `--consumed-by` requires `Status: handed-off` and zero open rows. After a successful consume the Status is `closed`, so a re-run (for example `/plan-and-analyze` retried after a later failure) exits 1 with a message that misdescribes the state. `close --reason` is idempotent by contrast.",
      "suggestion": "Treat `Status: closed` with a matching 'consumed by <cycle>' line as success (exit 0, message 'already consumed'), and reserve the refusal for `charting`/`abandoned`.",
      "confidence": 0.6
    },
    {
      "id": "F-014",
      "title": "Surface hook is silent when enabled but yq v4 or jq is missing, contrary to its degraded-mode WARNING contract",
      "severity": "LOW",
      "category": "observability",
      "file": ".claude/hooks/session-start/loa-decisions-surface.sh",
      "description": "The tool checks (`command -v yq`, version test, `command -v jq`) exit 0 before the config is read, so an operator who enabled `decisions.surface_at_session_start` on a host without yq v4 sees nothing and cannot tell the surface from a disabled one. The header promises a `[DECISIONS] WARNING` line for an enabled-but-degraded surface.",
      "suggestion": "Read the config first with a plain `grep` fallback; if enabled and yq v4 or jq is absent, print the one-line WARNING naming the missing tool and exit 0.",
      "confidence": 0.6
    },
    {
      "id": "F-015",
      "title": "SP-1 fence misses `git checkout -p/--patch <spike>`, `git format-patch`/`git am`, `git archive`, and `HEAD~0:<dst>` pushes from a spike checkout",
      "severity": "LOW",
      "category": "security",
      "file": ".claude/hooks/safety/block-destructive-bash.sh",
      "description": "`_sp1_checkout_copies` counts operands, so `git checkout -p spike/x` (one operand, patch mode copies hunks into the working tree) passes. `_sp1_push_refspec` recognises only `HEAD`, `@` and empty sources for the on-spike-branch rule, so `git push origin HEAD~0:main` or `HEAD@{0}:main` from a spike checkout is allowed. `git format-patch main..spike/x` followed by `git am`, and `git archive spike/x | tar x`, are undocumented misses alongside the documented `git show`/`git diff` ones. These are fence gaps, not boundary failures, and ICE covers run mode, but the header's miss list should be complete.",
      "suggestion": "Add `-p|--patch` to the checkout rule, treat any source that starts with `HEAD`/`@` (including `~`/`^`/`@{`) as the current checkout in the push rule, and list `format-patch`/`am` and `archive` under Misses or add them to the verb pattern.",
      "confidence": 0.6
    },
    {
      "id": "F-016",
      "title": "`demote_headings` uses a naive fence toggle while the repo ships `lib/md-fence.awk` for CommonMark fences",
      "severity": "LOW",
      "category": "consistency",
      "file": ".claude/scripts/chart-ticket.sh",
      "description": "The hand-off snapshot demotes headings with `/^(```|~~~)/ { infence = !infence }`, so a `~~~` line inside a backtick block, or a longer fence closing a shorter one, toggles incorrectly and a `#` line inside code may be demoted or a heading left undemoted. `validate-artifact.sh` and `check-glossary-terms.sh` use `md-fence.awk` for the same decision, so the snapshot and the validator can disagree about the same document.",
      "suggestion": "Source `md-fence.awk` in `demote_headings` (as `validate_glossary` does) so fence tracking is shared.",
      "confidence": 0.6
    },
    {
      "id": "F-017",
      "title": "Validator honours a `PROJECT_ROOT` override but the context probe it spawns derives its root from the script location",
      "severity": "LOW",
      "category": "consistency",
      "file": ".claude/scripts/validate-artifact.sh",
      "description": "`_dec_context_why` runs `lib/dec-write-lib.sh context --why`, whose `PROJECT_ROOT` is `SCRIPT_DIR/../../..`, while `validate-artifact.sh` reads `$PROJECT_ROOT` from the environment (the charting-lint and validate-artifact suites set it to a fixture tree). When they differ, the PRD gate's unattended verdict and the decisions check's `live` signal come from a different project's `.run` and `prd.md` than the artifact being validated. The validate-artifact suite works around this by copying the scripts into a hermetic tree.",
      "suggestion": "Let `dec-write-lib.sh` accept `LOA_PROJECT_ROOT`/`PROJECT_ROOT` from the environment when set (validated as an existing directory), and pass it from `_dec_context_why`.",
      "confidence": 0.5
    },
    {
      "id": "F-018",
      "title": "Writer verifies every candidate with a structural jq check plus the validator before the atomic rename, and a hostile-string corpus proves the round-trip",
      "severity": "PRAISE",
      "category": "robustness",
      "file": ".claude/scripts/lib/dec-write-lib.sh",
      "description": "`verify_and_swap` checks schema, dropped ids, duplicates, exact row-count delta and JSON equality of untouched rows, then runs `validate-artifact.sh --type decisions --base-file <current>` and only then renames. Values reach yq exclusively through `env()` and rows are built by `jq --arg`, with `STYLE_ROW` forcing double-quoted scalars. `dec-write-lib.bats` exercises YAML-looking values, control bytes, C1 and U+2028/9, verifies byte-equal round-trips, and asserts a failed write leaves the file byte-identical.",
      "suggestion": "Keep this pattern as the template for other State Zone writers.",
      "confidence": 0.9
    },
    {
      "id": "F-019",
      "title": "red-test-check closes the obvious gaming routes: second red run, runner allowlist, scrubbed env, and a shared-.git snapshot",
      "severity": "PRAISE",
      "category": "security",
      "file": ".claude/scripts/red-test-check.sh",
      "description": "The second red run after green catches stateful decoys; the argv allowlist refuses shells, inline-code interpreters and the inline-code flags of listed runners while naming the config key for the operator; runs start from `env -i` with per-run HOME/TMPDIR and credential-shaped `--env-pass` names refused; refs, HEAD, config hashes and hooks are snapshotted and any change exits 2. Test output is control-stripped, line-capped and fenced, with the authoritative verdict line printed last and asserted by RTC-25 against forged markers.",
      "suggestion": "None.",
      "confidence": 0.9
    },
    {
      "id": "F-020",
      "title": "Glossary CI workflow includes positive and negative controls that prove the gate itself still bites",
      "severity": "PRAISE",
      "category": "testing",
      "file": ".github/workflows/check-glossary-terms.yml",
      "description": "After the real check, the workflow runs the checker on a `miss` fixture and asserts exit 1, then on an `ok` fixture and asserts exit 0, each gated with `if: success()` so a real failure stays the visible one. The checkout action is pinned by SHA.",
      "suggestion": "None.",
      "confidence": 0.9
    },
    {
      "id": "F-021",
      "title": "Unblock-probe tests assert leakage through tags, hooks, config, refs, remotes and the environment",
      "severity": "PRAISE",
      "category": "testing",
      "file": "tests/unit/charting-decisions.bats",
      "description": "CD-27 through CD-27f verify that a probe cannot write to the main tree, ignored `.run`/`.beads` files, tags, hooks, git config, `update-ref`, or a local bare remote, and that it runs with a scratch HOME and without session secrets, while a clean read-only probe still passes. This is the right shape of evidence for a 'throwaway worktree' claim.",
      "suggestion": "None.",
      "confidence": 0.85
    }
  ]
}
```
<!-- bridge-findings-end -->
