## Bridgebuilder triage (run bridgebuilder-20261013T080206-68fe, head a63d28a4; two voices, 23 unique findings, 2 consensus, 5 disputed, 0 blocker)

Every finding was verified against the code before it was fixed or refuted. Fixes landed in 3758ddd0 (after the CI gate fix 79224a9e); each has a test. The consensus comment's enrichment body is a degraded writer output (tool-call markup instead of prose) and carries no findings; the two voice comments are the record.

### Fixed

| Finding | Severity (voice) | What changed |
|---|---|---|
| OpenAI RTC-001 | HIGH | `red-test-check.sh`: a configured `red_test.command` / `red_test.setup` no longer bypasses the hard denials (shells, `env`, `eval`, `exec`, inline-code interpreters and runner inline-code flags are refused first; config only widens the runner list); when `.loa.config.yaml` differs from the base branch and the argv is accepted only through config, the check refuses unless `--trust-config` is given. |
| Anthropic F-003 | MEDIUM | `dec-write-lib.sh`: the PRD Status line is a planning-time default only (`new`/`decide` still land `proposed` under it); the `context` verdict, attribution and the operator-only operations follow live signals (fresh marker, RUNNING run state, `LOA_UNATTENDED=1`, autonomous Flatline mode). Under this repository's autonomous PRD, `/decisions confirm` now records `decided_by: operator` and `/chart` is not refused. Recorded as DEC-0124. |
| Anthropic F-002 | MEDIUM | `validate-artifact.sh --type decisions`: merge-base mode applies history rules (an unchanged base prefix, any number of legal appended transitions, a content field set when any appended transition legitimises it); the strict single-write rules stay on the `--base-file` path the writer uses. |
| Anthropic F-004 | MEDIUM | The validator's usage header and the CHANGELOG Migration note now state the live-plan Date rule as implemented (undated archived and fixture plans WARN; an undated live plan under `grimoires/loa/` fails). |
| OpenAI CHART-001 / Anthropic F-005 | MEDIUM / LOW | `chart-ticket.sh epic` reuses an existing map epic for the slug when the doc is missing (refuses when several exist) instead of creating a second one. |
| OpenAI CHART-002 | LOW | `research-begin` waits one second after its marker so `research-end`'s mtime check holds on one-second filesystems; the boundary is stated. |
| Anthropic F-007 | LOW | The SDD Open Questions check no longer counts `Unresolved` as `Resolved`. |
| Anthropic F-008 | LOW | GNU-only `sed` forms in the new tests replaced with portable ones. |
| Anthropic F-009 | LOW | `sprint.md`: the ledger seed is `proposed`, the Appendix D free-form sentence records its supersession by the r254-2 runner allowlist, Appendix A statuses read Complete. |
| Anthropic F-010 | LOW | The PRD's 21 operator-behalf decisions carry `[ASSUMPTION decision]` tags citing their ledger rows (D21 seeded as DEC-0123); the PRD gate now exercises itself (21 decision tags, 0 misses). |
| Anthropic F-012 | LOW | `validate_decisions` uses no jq 1.6-only builtin. |
| Anthropic F-013 | LOW | `close --consumed-by` on an already closed or abandoned map is a no-op (exit 0). |
| Anthropic F-014 | LOW | The SessionStart decisions surface prints one WARNING when enabled without yq v4 or jq (the config is read by a plain-text fallback). |
| Anthropic F-015 | LOW | SP-1 also blocks `git checkout -p|--patch <spike>` and `HEAD~N`/`HEAD^` push refspecs from a spike checkout; `format-patch`/`am` and `archive` join the documented misses. |
| Anthropic F-016 | LOW | `demote_headings` tracks fences with the shared `lib/md-fence.awk`. |
| Anthropic F-017 | LOW | `dec-write-lib.sh` honours `LOA_PROJECT_ROOT`; the validator passes its own `PROJECT_ROOT` to the context probe. |
| Anthropic F-001 | HIGH (claimed) | Refuted (below), regression test added: a proposed row's uppercase summary appears verbatim in the surface output. |

### Refuted, with evidence

| Finding | Claim | Evidence |
|---|---|---|
| Anthropic F-001 | The surface's jq `clean` uses `\^` (invalid escape) and a range covering A-Z | The source (`loa-decisions-surface.sh:69`) reads `gsub("[[:cntrl:]\u0080-\u009f  ]"; " ")` with `\u` escapes and the two literal separator characters; `jq -n -f` on that definition compiles and `"A-Z Beads ^@ <b> \x01 x" \| clean` yields `"A-Z Beads ^@ ‹b› x"`. The voice read a rendering of the diff, not the file. |
| Anthropic F-011 | `sanitize_for_session_start` is called with text in one place and a path in two others | `context-isolation-lib.sh:97-98` takes `content_or_path`; both forms are the documented contract. |
| OpenAI SPK-001, Anthropic F-006 | SP-1 leaves documented copy routes open; dependency symlinks let tests write the live tree | Both are stated acceptances: the fence header's "Misses (fence, not boundary)" list and the hooks-reference "Decision surfaces" table name them, and `red-test-check.sh`'s header states the symlink behaviour with `--no-link-deps` as the opt-out. A text fence is not the boundary; ICE refuses the same merges and PRs inside run mode. |
| Anthropic F-009 (part) | Appendix D says the test command "stays free-form" | True at planning time; the sentence now records its supersession rather than being deleted, so the planning record stays honest. |

### Praise acknowledged

OpenAI DEC-001, Anthropic F-018 (the ledger writer's verification boundary), F-019 (`red-test-check.sh`'s gaming defences), F-020 (the glossary CI controls), F-021 (the probe's leakage tests).

Verification after the fixes: 25 bats suites on the final tree (every cycle-128 suite plus validate-artifact, validate-ac-verification, prompt-budget, skill-capabilities, agents-md-gen, repo-map-gen, user-invoked-commands, run-mode-ice, grimoire-index, check-round-independence and the adversarial-review companion suite): 1,022+ ok, 1 failure that was the new F-007 test's own line-number assertion, fixed and re-run green before the commit; `check-prompt-budget` exit 0; `validate-skill-capabilities` 37/37; `agents-md-gen --check` 51 commands; `repo-map-gen --validate` exit 0; swallowed-jq and raw-sha256sum lints clean; `sync-fixtures --check` current; `bash -n` on every changed script; shell-compat greps clean; `check-glossary-terms.sh` PASS; PRD (21 decision tags, 0 misses), SDD, sprint plan and the 124-row ledger validate; CI on 3758ddd0: 50 checks green, Shell Tests running.
