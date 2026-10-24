# s3-b — Sprint 274 Task 3.2: one finding contract and grader 1.5 (sdd.md C-11; D-3.2 DEC-0849, D-3.5 DEC-0857)

Worktree `loa-wt-s3b` at `de366cc63`; patch `~/.cache/loa/cycle-133/patches/s3-b.patch` (+ `.stat`). No model calls. `registration.py` not edited.

## What was built
- `.claude/schemas/finding.schema.json` v1 implements every C-11 rule; rules JSON Schema cannot state sit in `x-loa-rules` with the error codes. 47 vectors live in `finding.vectors/{valid 18, invalid 29}/` as {finding, expect, markdown?}.
- Four validators agree on all of them:
  - `lib/finding_validate.py` (stdlib)
  - `lib/finding-validate.sh` (jq, sourceable)
  - `bridgebuilder-review/resources/core/finding-schema.ts` (zod; `validateCanonicalFinding`, `CanonicalFindingSchema`)
  - `verdict-derive.sh` `finding_bullets_check`, which uses the jq filter
- `verdict-derive.sh`: a fence- and section-aware bullet scan; a defect bullet without a valid clause is a violation on every path; a CRITICAL, HIGH or blocking bullet joins `blocking_tally`; tally > 0 with APPROVED is a violation. The header and `--help` document it.
- Templates: `review-feedback.md` and `sprint-audit-feedback.md` carry the clause. Both SKILL.md files stay within budget (16,383 B and 16,381 B). `BEAUVOIR.md` and the `template.ts` prompt ask for `failure_scenario`. `FindingsBlockSchema.meta()` names the canonical schema. `dist/` is rebuilt and fresh.
- `adversarial-review.sh`: rejects a differing failure_scenario/failure_mode pair (`alias-conflict-failure_scenario-failure_mode`); fills failure_mode from a lone failure_scenario; gives every accepted finding `failure_scenario`; warns once per alias per run. `adversarial-finding.schema.json` adds the field with a `$comment` reference.
- `ablation-grade.sh` 1.5.0: `--judge-verdicts FILE [--run-id ID]` on run and union grades. Details are in the header block and the Judgment calls. Without the flag the grade equals 1.4.0's.
- `reads.py --judge-defects`: needs a schema_version 2 registration. It reads judged recall on fully judged pairs and lists the rest.

## Tests (red → green)
- `tests/unit/verdict-derive-failure-clause.bats`: 12 tests. Nine were red first (VFC-1 only invalid blockers, VFC-2 valid lows plus an invalid blocker, VFC-3 a malformed CRITICAL never approves) and three were green controls. Now 12/12.
- `tests/unit/finding-conformance.bats`: 7/7 (python, jq, zod, markdown, the seam, code coverage, jq = python).
- `evals/tests/ablation-grade.bats` AG-c133-J1…J8: 8/8 were red first. The full file passes 88/88; seven version pins moved to 1.5.0.
- `evals/tests/fixtures/grader-1.5/regress.sh` (1.4.0 at `de366cc63` against 1.5.0): 417 pairs over 85 tests, 389 identical, 17 refused by both, 11 exit_differs (all AG-c133-J), 0 unexpected. AG-24 fails under the wrapper by construction, as in 1.4.
- Bridgebuilder `finding-schema.test.ts`: 51/51. `npm test`: 1068/1068.
- `adversarial-review-normalise.bats` NRM-C133-1…5: 5/5. These include a replay of the 4 non-empty cycle-132 envelopes (22 findings): all accepted, alias fields byte-identical. Severity is excluded from that comparison because validate_anchor demotes without a diff, which predates this change.
- `evals/analysis/c132/tests/test_judge_read.py`: 5 tests. `unittest discover` runs 220 OK, and `tests/COUNT` is set to 220.
- `registration.py verify`: ok on all 18 cycle-132 REGISTRATION*.json.
- CI lints clean: raw sha256sum, swallowed jq, knob readers, direct fetch, raw curl, manifest paths, prompt budget, eval trust boundary.
- Fixtures moved to the grammar: verdict-observations-section (15 bullets), profile-floor (2), golden-path-c8 (5, plus copying the lib into its temp tree), verdict-derive (1).
- Consumer suites: 890/890 across 31 bats files (every adversarial-review*, wire-schemas, ablation-row, analysis-c132, run-checkpoint, guard-origins, spiral-evidence, mount-clean and the verdict suites). The verdict-derive suites were rerun after the final edit: 145/145.

## Acceptance criteria (sprint.md Task 3.2)
- Schema v1 per C-11 with all listed rules: **Met** (the schema file and 47 vectors).
- Vectors run by zod, jq and python: **Met** (the markdown grammar is a fourth validator): FC-1…FC-4.
- `Failure:` grammar with dash variants and last-token disambiguation: **Met**: VFC-8, VFC-9.
- A defect bullet without a clause is a violation, and an invalid CRITICAL/HIGH/blocking bullet still blocks with a non-zero exit: **Met**: VFC-1…6, VFC-11, VFC-12.
- Review and audit templates emit the clause: **Met**.
- The persona asks for the field; `FindingsBlockSchema` references the canonical schema; build, dist and freshness check: **Met** (dist staged; `check-bb-dist-fresh --check` OK).
- Dissent schema plus script normalise aliases with the named warning and reject a differing pair: **Met**: NRM-C133-1…4.
- Grader 1.5 `--judge-verdicts` with every listed property, plus the regression: **Met**: AG-c133-J1…J8 and regress.sh.
- `--judge-defects` as a registered read under v2: **Met** (it requires schema_version 2; C lands the v2 builder).
- The cycle-132 chain and reads verify unchanged; bats, node tests and unittest pass: **Met**.

## Judgment calls
- Four validators: zod, jq, python and verdict-derive's markdown grammar. The dissent validator handles aliases and conflicts but not the canonical vectors, because its BLOCKING/ADVISORY vocabulary is not canonical (mapping rejected).
- `alias_conflict` applies only to failure_scenario versus failure_mode. `description` is the lowest-precedence fallback and never conflicts, because dissent and Bridgebuilder findings carry it beside the scenario. "Any two differ" was rejected: it would refuse every dissent finding.
- Unknown properties pass through and the normalised view keeps only named fields. Strict mode was rejected: it would refuse every dissent and Bridgebuilder finding.
- file and anchor_line are required only for defect severities. Severity must be exact upper case. confidence is optional in JSON but required by the markdown grammar.
- For cross-language identity: anchors are integral numbers (12.0 accepted) up to 10^7; whitespace is the ASCII set; the denylist matches whole words, ASCII case-insensitive; when…then is a token rule.
- A bullet counts as a finding when written `**SEV**`, `**[SEV]**`, `[SEV]` (any case) or bare upper case, followed by a blank, `(` or end of line. So `- **Critical**: 0` and `HIGH-1` are not findings.
- Bullets are judged everywhere except code fences and `## Rejected dissent payloads`, with or without a trailer.
- Paren items are comma-separated in any order: exactly one confidence, plus optional speculative and blocking. Any other item is a grammar violation.
- The blocking tally excepts FR-9's speculative low-confidence HIGH under Observations. It forbids APPROVED. There is no undercount check against the trailer counts, which keeps the one-way rule.
- lib/finding-validate.sh is sourced only when the file has list items, so a verdict-derive copied alone still works on bullet-free files. A missing lib with bullets is a named violation.
- The `--json` key set is unchanged; error codes ride in the violation text.
- FindingsBlockSchema references the canonical schema via `.meta()`, and Bridgebuilder extraction stays lenient (no regression).
- Envelopes keep failure_mode and add failure_scenario, with one WARN per alias per run (description-derived included). The wire schema and prompt still ask for failure_mode, so every dissent run warns until the wire moves. Suggest a bead before 2.1.0.
- Grader credited pairs use pm3, the decision rule (DEC-0638), not the same-function rule.
- A pair's finding is the citation reference {id, file, anchor_line[, end]}: a citation has no severity or title, so the id is derived with an empty title. The same file and line are one finding.
- Judge fields appear only with `--judge-verdicts`, so a grade without it equals 1.4.0. An empty verdicts file lists the pairs.
- Every row carries run_id: the SDD's field list omits it but the sprint's pair key needs it. It defaults to the directory name, and `--run-id` overrides it.
- `supersedes` is the sha256 of the superseded row's RFC 8785 text. That row must be an earlier one of the same pair, and a row is superseded at most once. Unknown keys are refused.
- A stale row of this run refuses the whole grade (exit 2), even when that row is superseded.
- The grader has its own RFC 8785 serialiser: it may not source .claude/ code, and under `python -I` the rfc8785 package may be absent.
- recall_judged = defects with a blind describes / defects_seeded. Unblind verdicts are counted in judged_pairs_unblind, never in unjudged_pairs.
- `--judge-defects` is "registered" as requiring a schema_version 2 registration (v2 has no reads list), with exit 1 on v1. A pair enters only when both cells are fully judged 1.5.0 grades.
- Bridgebuilder tests use the package's node:test runner, not vitest.
- Fixtures in four suites outside my named ownership were moved to the grammar; listed under "What the lead must do".

## What the lead must do
- `tests/COUNT`: I set 220 (215 + 5). Implementer C's registration-v2 tests add more; at landing set COUNT to the unittest-collected total.
- Regenerate `.claude/checksums.json` and REPO-MAP for the new `.claude/` files (schema, vectors, two libs, the zod module and dist).
- `grimoires/loa/a2a/sprint-274/reviewer-b.md` is git-ignored on this branch; it is in the worktree only.
- Tests outside my named ownership were edited only to move fixtures to the new grammar: `verdict-observations-section.bats`, `profile-floor.bats`, `golden-path-c8-verdict-trailer.bats` and the NRM-C133 block appended to `adversarial-review-normalise.bats`.
- CHANGELOG and DEC rows for: grader 1.5.0, the canonical finding contract, the verdict-derive blocking rule and the alias deprecation (removal in 2.1.0).
- No `registration.py` edit was needed. `--judge-defects` only reads `schema_version` and the existing `supersedes` chain.
