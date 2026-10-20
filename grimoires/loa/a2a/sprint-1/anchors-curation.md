# Sprint 263 Task 1.5: multi-site anchor curation (implementer D)

Date: 2026-10-19. Curated by implementer D (Claude Opus 5.5) for the lead's re-approval.

## Blinding statement

The added lines were derived only from each defect's `source` record-review line (`git show record/cycle-12N-a2a:<path>`), the review's own citations and the sentences around them, and the fixture `head/` files. To map review line numbers that were written against a later commit than the fixture head, the curator read the source file at the commit the review names (`git show <sha>:<path>`, e.g. 4992b5a6, db49cd32, 005b9105, cbfccab2) and matched by content. The curator did NOT read anything under `grimoires/loa/reports/ablation-2.0/batches/`, `evals/results/`, `grimoires/loa/a2a/analysis-2026-10/`, the branch `record/cycle-130-analysis`, or the main checkout; no arm output, grade, or envelope was opened.

## Rules applied

- A line is added when the human finding names it for that defect in the defect's own file: an explicit `path:line`, a range's endpoints and the distinct statements inside it the finding names, or a code statement the finding names by identifier or quote (resolved in `head/`). At most 6 added lines per defect; blank endpoints are skipped.
- Review line numbers are mapped to `head/` by content when the review commit differs from the fixture head; a citation whose code does not exist in `head/` is not added (marked HEAD-ABSENT).
- Nothing removed; `anchor_line`, `id`, `file`, `severity`, `category`, `must_match` unchanged; `anchors` created from `anchor_line` when absent, deduped and sorted.

## Synthetic fixtures pr-01 … pr-10

pr-01 … pr-08 have no `label_source`/`source` field and no record review; pr-09 and pr-10 have no defects. Their defects are planted from historical commits with one key line each and no planting description naming a second line, so nothing was added and their manifests (including `approved_by`, which they do not carry) are unchanged.

## pr-11

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-the-unverified-zone-flag-is-computed-onc (review) | 1992, 2304 | 1843, 2256, 2297 | `_ceiling_unverified` is set from the head's pre-flight outcome; read in the RateLimitError and ProviderContextLimitError arms | cycle-126-a2a:sprint-247/engineer-feedback-round-1.md#L22 |
| L02-the-read-append-cycle-takes-no-interproc (review) | 264, 277, 292 | 279, 290, 299 | the read → append → `os.replace` cycle takes no interprocess lock | cycle-126-a2a:sprint-247/engineer-feedback-round-1.md#L30 |
| L03-the-premium-multiplies-already-floored-p (review) | 165, 171 | 172, 173, 174, 175 | the premium multiplies already-floored per-category micro-USD costs | cycle-126-a2a:sprint-247/engineer-feedback-round-1.md#L38 |
| L04-store-and-catalog-paths-are-read-through (audit) | 225 | 231 | the read side opens the path normally, so a symlink … is read through | cycle-126-a2a:sprint-247/auditor-sprint-feedback.md#L59 |
| L05-local-filesystem-path-in-the-envelope (audit) | 2004, 2022 | 2016 | `_calibration_needed_exit` (`calibration_needed.store`): the envelope … carry the absolute store path | cycle-126-a2a:sprint-247/auditor-sprint-feedback.md#L65 |

## pr-12

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-the-check-only-proves-the-heading-exists (review) | 131 | 137 | the check only proves the `## Rejected dissent payloads` heading exists | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L22 |
| L02-is-unguarded (review) | 2183 | none | names only `result=$(_fold_companion …)` in `main`, already the anchor (2183) | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L30 |
| L03-when-the-primary-ends-and-the-companion (review) | 1898, 1906 | 1907, 1914 | when the primary ends `api_failure` … and the companion completes, its findings are appended | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L38 |
| L04-the-companion-is-forked-before-the-prima (review) | 2140 | 2182 | the companion is forked before the primary walk and only reaped by an unbounded `wait` | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L46 |
| L05-the-cli-hop-is-always-planned-so-a-singl (review) | 1835, 1851 | 1837, 1838 | `_companion_chain` — the CLI hop is always planned | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L52 |
| L06-the-companion-runs (review) | 1868, 2140 | 1918 | `failure_class` is reconstructed from the exit code alone | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L54 |
| L07-the-pipeline-materialises-the-secret-in (review) | 487 | 502, 503 | the `grep \| tail \| sed` pipeline materialises the secret in `val` before testing `-n` | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L63 |
| L08-the-stub-spoke-the-review-vocabulary-to (review) | 26, 63 | 72, 79, 85 | `setup` — the stub spoke the review vocabulary to the audit gate | cycle-126-a2a:sprint-248/engineer-feedback-round-1.md#L67 |

## pr-13

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-is-discarded-silently (review) | 90, 92 | 93 | `loa-context-class.sh:98-101` (head 90-93 by content) — `Standard` / `STANDARD` is discarded silently | cycle-126-a2a:sprint-249/engineer-feedback.md#L74 |
| L02-the-model-id-shape-this-host-s-harness-e (audit) | 78, 81, 89 | 47, 48, 49, 82, 85 | `:90-93` (alias then exact-key lookup) [head 82-85]; `:48-50` (`_print_line` for `long` prints no model) [head 47-49] | cycle-126-a2a:sprint-249/auditor-sprint-feedback.md#L50 |
| L03-the-alias-target-is-interpolated-into-th (audit) | 78, 82, 83, 89 | 75, 85 | `MODEL` is whitelisted … at `:83` [head 75]; then `yq eval "[.providers[].models.\"$m\"…` [head 85] | cycle-126-a2a:sprint-249/auditor-sprint-feedback.md#L64 |
| L04-the-protocol-s-never-load-a-1-000-line-f (audit) | 39 | 17 | the same file's table now permits a full-file load up to 30,000 tokens (`:17`) | cycle-126-a2a:sprint-249/auditor-sprint-feedback.md#L71 |
| L05-the-parallelism-sentence-cites-a-number (audit) | 42, 71, 136 | 162 | `.claude/skills/auditing-security/SKILL.md:162` / `:42` (`parallel_threshold: 2000`) | cycle-126-a2a:sprint-249/auditor-sprint-feedback.md#L85 |

## pr-14

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-with-set-a-write-to-whose-reads-exits-0 (review) | 111, 123, 133 | 122, 128, 129, 137 | `implement-gate.sh:122-137` — a Write … whose `tool_input.active_skill` reads `implement` exits 0 silently | cycle-126-a2a:sprint-250/engineer-feedback.md#L55 |
| L02-the-gate-roots-its-zone-test-on-the-hook (audit) | 35, 123, 133 | 76, 77, 89, 107, 108 | root consumed at the root-relative forms (`:244-245`) [head 76-77] and the App-Zone case (`:277-288`) [head 89-108] | cycle-126-a2a:sprint-250/auditor-sprint-feedback.md#L50 |

## pr-15

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-adds-and-to-the-words-that-used-to-trigg (review) | 578 | none | HEAD-ABSENT: cites `:577` `is_throttle_message` at 58f87195; the fixture head 8ad37c55 has no such function or words | cycle-127-a2a:sprint-251/engineer-feedback.md#L41 |
| L02-the-owner-mode-refusal-of-the-opt-in-con (audit) | 113 | none | HEAD-ABSENT: cites `loader.py:167-176,:216,:281-285` (`_config_untrusted_reason`, `_UntrustedConfig`) at cbfccab2; none exist in the fixture head 8ad37c55 | cycle-127-a2a:sprint-251/auditor-sprint-feedback.md#L48 |
| L03-a-throttle-marker-still-precedes-the-sta (audit) | 543, 578 | 547, 551, 553, 583 | a login message containing `please wait`, `quota` or a bare `429` would … walk (`_throttle` wins) [head by content] | cycle-127-a2a:sprint-251/auditor-sprint-feedback.md#L82 |

## pr-16

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-treats-any-as-a-fixture-so-reaches-the-w (review) | 249 | 250, 251, 261 | `dec-write-lib.sh:250-261` — `resolve_target` treats any `--file` as a fixture, so `CI=1 …` reaches the write path | cycle-128-a2a:sprint-252/engineer-feedback-r1.md#L33 |
| L02-discards-any-line-containing-user-operat (review) | 61, 74 | 65 | `user-invoked-commands.bats:65-74` — `grep -viE "$exempt"` discards any line containing user/operator/… | cycle-128-a2a:sprint-252/engineer-feedback-r1.md#L41 |
| L03-the-shape-check-runs-over-a-json-stream (review) | 65, 71 | 72 | `check-round-independence.sh:63-72` — the shape check runs `jq -e` over a JSON stream | cycle-128-a2a:sprint-252/engineer-feedback-r1.md#L60 |
| L04-index-decisions-family-emitted-ledger-te (audit) | 177, 186 | 189, 191, 192 | `emit_decisions()`: summaries and sources … reached INDEX.md, TSV and JSON unsanitised | cycle-128-a2a:sprint-252/auditor-sprint-feedback.md#L76 |

## pr-17

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-finding (review) | 3, 5, 11, 38 | none | names `chart-researcher.md:5`, already an anchor; its other citations are in other files | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L26 |
| L02-with-skips-the-context-check-by-design-t (review) | 369, 373, 414 | 398, 402, 408, 435 | `chart-ticket.sh:398-435` — `op_close` with `--consumed-by` skips the context check … but verifies nothing else | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L34 |
| L03-simulates-no-br-and-also-drops-jq-and-yq (review) | 399, 403 | none | names `charting-lint.bats:403`, already the anchor | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L42 |
| L04-as-failure-injection-is-a-no-op-under-ui (review) | 222, 224 | 226 | `charting-decisions.bats:224-226` (CD-14) — `chmod a-w` as failure injection is a no-op under uid 0 | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L43 |
| L05-the-create-parser-s-swallows-unknown-fla (review) | 13, 28 | none | names `-*) shift 2` (28) and `save()` (13), both already anchors | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L44 |
| L06-unlocks-from-a-row-in-the-tracked-ledger (review) | 637 | 642, 651, 653, 655, 657, 691 | `block-destructive-bash.sh:642-657,691` — `_fr11_spike_decided` unlocks … from a row in the tracked ledger | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L48 |
| L07-the-new-path-runs-a-real-on-a-spike-head (review) | 257, 274 | none | names `safe_merge` / `git merge --no-edit` (257, 274), both already anchors | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L52 |
| L08-the-verdict-is-a-porcelain-diff-of-the-m (review) | 42, 57, 62 | 71, 72, 76 | `chart-unblock-probe.sh:57-76` — the verdict is a porcelain diff of the main tree | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L56 |
| L09-the-merge-rebase-pull-cherry-pick-rule-r (review) | 821, 841, 846 | 839, 869, 870, 871 | `block-destructive-bash.sh:839-871` — the merge/rebase/pull/cherry-pick rule reaches the spike ref through `[^;&\|]*` | cycle-128-a2a:sprint-253/engineer-feedback-r1.md#L64 |
| L10-is-an-arbitrary-execution-path-with-a-bo (audit) | 66 | 57, 71, 72 | (`(cd "$WT" && run_with_timeout …)`, the `before`/`after` porcelain comparison …) | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L37 |
| L11-the-hand-off-snapshot-inlines-the-map-do (audit) | 360, 369, 387 | 373, 377 | `op_handoff` (the `sed` heading demotion, `dw list --source-epic … --format md`, the L6 subshell) | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L44 |
| L12-the-d-5-9-unlock-never-checks-that-the-s (audit) | 642 | 651, 691 | `_fr11_spike_decided` and its call site … the code checks only the ledger row | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L65 |
| L13-interprets-backslash-escapes-in-the-line (audit) | 125, 127, 137 | 325, 347 | `section_append` (`awk -v sec=… -v line="$2"`), called from `op_resolve` and `op_rule_out` | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L72 |
| L14-the-write-subcommands-never-consult-the (audit) | 398, 408, 414, 437 | 407, 474, 476, 478, 480, 482 | dispatcher: `epic`, `ticket`, `edge`, `claim`, `resolve`, `rule-out`, `handoff`, `research-begin`; only `close --reason` checks context | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L79 |
| L15-filters-on-only-fail-open (audit) | 72 | none | names the one `map(select(.issue_type …))` line (72), already the anchor | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L86 |
| L16-fails-open (audit) | 88 | 91, 93, 94 | Any first line other than `unattended` … reads as interactive, `--prd` is not passed | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L90 |
| L17-in-strips-c0-and-del-only (audit) | 51 | none | names `san1` (51), already the anchor | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L94 |
| L18-map-epic-check-misses-the-reply-shape (audit) | 117 | 118 | `create-sprint-task.sh` (`EPIC_IS_MAP` jq) | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L102 |
| L19-declarative-globs-load-every-snapshot-an (audit) | 21, 44 | none | names the `chart-*.md` glob (44), already an anchor; `chart.md` is another file | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L106 |
| L20-dispatch-markers-the-pending-file-glob-a (audit) | 144, 438 | 451, 458 | `op_research_begin`, `op_research_end`, `map_rows` … the scope check exempts the whole `grimoires/loa/research/` directory | cycle-128-a2a:sprint-253/auditor-sprint-feedback-r1.md#L110 |

## pr-18

| Defect | Original anchors | Added lines | Review text (≤ 20 words) | label_source |
|---|---|---|---|---|
| L01-validate-artifact-shvalidate-glossary-al (review) | 131, 148 | 100, 105, 130, 136, 164 | (the glossary pass and `lookup()`) — any token on an `_Aliases_:` line resolves, with no cap | cycle-128-a2a:sprint-254/engineer-feedback-r1.md#L26 |
| L02-glossary-pass-an-line-before-any-is-stor (review) | 131, 148, 183 | 100, 105, 124 | an `_Aliases_:` line before any `**Term**:` is stored with an empty entry; `put()` is first-wins | cycle-128-a2a:sprint-254/engineer-feedback-r1.md#L46 |
| L03-rtc-9-the-no-shim-symlinks-and (review) | 143 | 146 | RTC-9 — the no-`timeout` shim symlinks `/usr/local/bin`, `/usr/bin` and `/bin` | cycle-128-a2a:sprint-254/engineer-feedback-r1.md#L50 |
| L05-a-red-run-with-no-output-prints-an-empty (review) | 133, 160 | 149, 152 | `finish()` — a red run with no output prints an empty block between the markers; same for the green block | cycle-128-a2a:sprint-254/engineer-feedback-r1.md#L58 |
| L06-is-an-unbounded-credentialed-execution-p (audit) | 237, 248, 250 | 113, 292 | `run_bounded` (`exec "$@"`, `--setup` argv; only `GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX` unset) | cycle-128-a2a:sprint-254/auditor-sprint-feedback-r1.md#L33 |
| L07-the-temporary-worktrees-share-with-the-l (audit) | 214, 216 | 34 | `add_wt` (`-c core.hooksPath=/dev/null` on the add only) and the header's cleanup claim | cycle-128-a2a:sprint-254/auditor-sprint-feedback-r1.md#L54 |
| L08-the-seams-rule-s-fence-tracking-and-date (audit) | 869 | 871, 875, 890, 897 | `validate_sprint_seams` (its own `fence = !fence` toggle …; a missing … `**Date:**` turns the violation into a WARN) | cycle-128-a2a:sprint-254/auditor-sprint-feedback-r1.md#L61 |
| L09-manifest-coverage-of-the-new-framework-f (audit) | 79 | none | names the GLOSSARY.md manifest entry (79), already the anchor; the rest are other files | cycle-128-a2a:sprint-254/auditor-sprint-feedback-r1.md#L71 |

## Count

44 defects changed across 8 manifests (pr-11 … pr-18); 112 lines added in total; 0 anchors removed. pr-01 … pr-10 unchanged.

## Citations in other files (not added)

- pr-11 L04: `tools/ceiling-probe-live.py:_write_catalog_file`.
- pr-12 L01: `resources/ADVERSARIAL-REVIEW.md` (the contract text).
- pr-13 L02: `.claude/defaults/model-config.yaml`. L04: `grimoires/loa/prd.md:143`. L05: `implementing-tasks/SKILL.md:223,:17`, `reviewing-code/SKILL.md:202,:43`, `.claude/scripts/skills-adapter.sh:173`, `auditing-security/resources/REFERENCE.md:298-300`.
- pr-14 L02: `.claude/settings.json:586`.
- pr-15 L02: `.claude/scripts/lib/agy-gate-lib.sh:61,:106-110`, `bridgebuilder-review/resources/config.ts:176-195`, `adversarial-review.sh:2367`, `flatline-orchestrator.sh:524`, `run-preflight.sh` P3, `loa-status.sh:792`, `core/multi-model-pipeline.ts:172-173`. L03: `.claude/adapters/loa_cheval/routing/ceiling.py:273-283`.
- pr-17 L01: `chart-ticket.sh:451-470`, `charting-decisions/SKILL.md:141-149`, `.claude/data/agent-types.yaml`. L02: `charting-decisions.bats` CD-22. L10: `charting-decisions/SKILL.md` allowed-tools. L11: `dec-write-lib.sh:335,366-373,459,466,515-519`, `validate-artifact.sh:676`. L15: `chart-frontier.sh`, `chart-ticket.sh`. L17: `dec-write-lib.sh` `san1`. L19: `.claude/commands/chart.md`.
- pr-18 L01: `validate-artifact.sh` `validate_glossary`. L06: `reviewing-code/SKILL.md`. L09: `mount-loa.sh`, `mount-submodule.sh`, `.claude/checksums.json`.

## Citations whose code is absent from the fixture head (not added)

- pr-14 L02: `implement-gate.sh:216-217` (`canonical_root`/`logical_root`) and `:256-269` (the trust-input case) exist at 005b9105 only; the head d785fc9a has neither. `:133`, `:244-245` and `:277-288` were mapped by content to head 35, 76-77 and 89-108.
- pr-15 L01 and L02: see the pr-15 table. pr-15 L03 was mapped by content: the head's rate-limit branch (`429`, `quota`, `raise RateLimitError`) precedes the static-auth arm (`raise ConfigError`).
- pr-17 L10: the `.run`/`.beads` newer-than check exists only after r253-1, not in the head cea919ca.
- pr-13: every review line number was mapped from 4992b5a6 to the head 41b783a1 by content (offset 8 in the resolver, 1 in `_print_line`).
