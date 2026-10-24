# s3-c report — Sprint 3 (global 274) Task 3.3: external seeding, registration v2, guidance

Patch: `~/.cache/loa/cycle-133/patches/s3-c.patch` (20 files, +2723 −542, against `de366cc63`).

## What was built
- **C-4 scanner as one source.** New `.claude/scripts/lib/secret-classes.sh`. It holds the eight credential classes, the placeholder filter and the password-assignment parser, moved verbatim from `record-branch.sh`. It offers `secret_classes_py credscan|parsepw`, `secret_classes_scan`, `secret_classes_names`, and a CLI when executed. `record-branch.sh:80-86` sources it, and the moved Python left `record-branch.sh` (`:441`, `:532-533`).
- **Seeding library.** New `evals/harness/lib/corpus-seed.sh`. It is the record seeder's shared Python held in a shell variable: the labels grammar v1 and v2, build_manifest, sync_labels, the exposure block and MODEL_AVAILABILITY, freeze and check, redaction, and `fail` with `SEED_TAG`. It adds `corpus_set`, `corpus_row`, `write_layout`, `write_tasks` and `no_secrets_scan` (end of file). `seed-corpus-from-record.sh:144-150` sources it, and its main pipes the library and itself into `python3 -I -`. Its output-writing tail now calls those helpers.
- **External seeder.** New `evals/harness/seed-corpus-from-external.sh`; the header documents usage, order, writes, seam and exit codes. Sections: `:239` URL; `:298` gh api and binding; `:335` blobless clone; `:399` tree metadata and limits, before any blob fetch; `:503` batched fetch and archive; `:566` PR.md and leakage; `:594` licence; `:633` C-4 scan; then fix rows, writes, `--dry-run`, `--check`.
- **Registration v2.** `evals/analysis/c132/registration.py:211-327` adds `looks_inventory`, `successors_of` and `looks_seen_errors`. `build --looks-seen JSON [--looks-root DIR]` writes `schema_version: 2` with `looks_root` and `looks_seen`. Without the flag the build is v1, byte for byte. `verify` accepts schema 1 or 2, checks a v2 record against the committed inventory, and flags looks_seen on a v1 record.
- **Guidance.** `evals/harness/README.md` gains § Shipping a measurement cycle. The planning-sprints `REFERENCE.md` gains a pointer as Sequencing principle 5.
- **Candidates.** `evals/fixtures/external-candidates.md` sits outside the `-diff` path.

## Tests
| File | Result | Red evidence |
|---|---|---|
| `tests/unit/secret-classes.bats` (new) | 6/6 | The golden lists came from the pre-extraction helper on planted fixtures. Red before the lib existed. |
| `tests/unit/record-branch.bats` | 14/14 | Unchanged. |
| `evals/tests/corpus-seed-lib.bats` (new) | 4/4 | CSL-1 diffs a full transcript of every mode against `transcript.golden`, made by the original script. The transcript covers stdout, stderr, exit codes and sha256 of every written file, plus a rebuild of every tracked manifest. Red before the extraction. |
| `evals/tests/seed-corpus.bats` | 29/29 | Unchanged. |
| `evals/tests/seed-corpus-from-external.bats` (new) | 20/20 | First run: 12 of 16 red. The causes were archive lazy-fetch, the submodule plant and binding. |
| `evals/analysis/c132/tests/test_registration_v2.py` (new) | 13/13 | First run: 11 red. |
| c132 unittest discover | 228 OK | `COUNT` changed from 215 to 228. |
| manifest-v2, run-ablation, analysis-c132 | 71/71 | — |
| `evals/tests/registration.bats` | 3/4 | REG-4 fails identically on a clean export of `de366cc63`. The cause is the egress refusal, so it is pre-existing and not mine. |

SX-20 was written with its fix, so it never ran red. Local lints pass: raw sha256sum, swallowed jq, knob readers, the eval.yml trust-boundary regex. shellcheck is not installed here.

## Acceptance criteria
- **Lib extracted, byte-identical: Met.** CSL-1 shows it.
- **https-only sanitised URLs: Met.** SX-11 shows the token is never printed.
- **PR base and head verified: Met.** SX-12.
- **base/ = fix^: Met under the reading in Judgment calls.** The fix diff is fix^..fix, and fix^ must descend from the head or the merge commit.
- **Limits from metadata before any fetch: Met.** SX-7.
- **Blobless clone and git archive: Met.**
- **Symlink, submodule and non-regular refusal: Met.** SX-5, SX-6 and the tar member check.
- **Leakage test: Met.** SX-10.
- **C-4 scanner: Met.** SX-13.
- **Licence via the API against the allowlist, LICENSE/NOTICE and attribution: Met.** SX-3, SX-8, SX-9 and SX-19.
- **--dry-run and --check: Met.** SX-1 to SX-4.
- **§5.4 exit codes: Met.** Every refusal exits 2, failures exit 1.
- **Three public dry-runs pass --check, no model call: Met.** The results are below and in the candidates file.
- **looks_seen ordering, integrity and completeness against the inventory, v1 still verifies: Met.** All 18 cycle-132 REGISTRATION*.json verify `ok`, tested.
- **Guidance names four PR kinds and when one PR is acceptable: Met.**
- **bd-y1smc: Not closed by me.** Closing beads is the lead's.

**Dry-runs.** All ran on 2026-10-24 between 08:33:34Z and 08:34:53Z:
- `keras-team/keras#23938` with fix `d7b8ca0c`: Python, Apache-2.0, 2 fix rows.
- `transitmatters/t-performance-dash#1180` with fix `5a298926`: TypeScript, MIT, 3 fix rows.
- `ionic-bond/twitter-monitor#22` with fix `dbc86a89`: Python, MIT, 3 fix rows.

Each `--check`, and the record seeder's, passed. With `claude`, `codex` and `cheval` shimmed on PATH to log and fail, the log shows 21 `gh api` reads and 0 model calls. The cost ledger stayed at 1652 rows, and `spend.sh` reported USD 0.00 for the window. `Meliox/PVE-mods#357` was refused with exit 2, correctly: its fix edits a file the PR never changed.

## Judgment calls
- **base/ and fix^.** base/ is the PR's merge base, head/ is the PR head, and the fix diff is fix^..fix; for a range, `<first>^..<last>` with the range inclusive. I rejected base/ = fix^ literally, because head.diff would then not be the PR, which contradicts PRD FR-12. The relation checked is that the head, or the merge commit for squash merges, is an ancestor of fix^ or equal to it. I sent this reading to the lead by message.
- **One exit code for all refusals.** Every refusal exits 2 with a distinct named reason, per §5.4. I rejected distinct exit codes, which §5.4 forbids, and the §5.2 row "1 refused", which §5.4 overrides.
- **Shared scanner home.** The scanner lives in `.claude/scripts/lib/secret-classes.sh`, because a mounted install has no evals/. Python callers use its CLI mode. This edits `record-branch.sh`, which my list did not name, but the lead's note asked for it.
- **Library shape.** Python source in a shell variable, fed with each main to `python3 -I -`; not a `.py` module, since the SDD names `lib/corpus-seed.sh` and `-I` blocks imports.
- **Sizes from the GitHub trees API.** `GIT_NO_LAZY_FETCH=1 git ls-tree -l` prints `BAD` for missing blobs, so sizes come from the git/trees API. Every entry must match the clone's oid and mode, and a truncated listing refuses.
- **Archive a synthesized tree.** `git archive` reads blobs outside its pathspec, so I archive a tree built in a temporary index from exactly the checked entries. A non-commit tree-ish also gets no export-subst. Every member is verified by blob id.
- **Batch fetch.** One batch with `fetch.negotiationAlgorithm=noop`, git's promisor recipe; default negotiation fails GitHub's connectivity check.
- **Limits scope.** Limits apply to the blobs actually fetched: PR files at base and head, fix files at fix^ and fix, and root licence and manifest files. I rejected applying them to the whole repository tree, which would refuse every large repository with a small PR.
- **Fix must touch the PR.** A fix that touches no PR file refuses. Fix hunks are carried to head/ lines through the head-to-fix^ diff, and hunks with no head place are listed as dropped.
- **Licence policy.**
  - A licence outside the allowlist always refuses. I took the PRD's "refused" option, not the alternative of keeping a fetch-only fixture.
  - Without `--commit-trees`, an allowlisted licence yields a fetch manifest with hashes and no third-party bytes.
  - A conflict is judged by licence family, because keras' pyproject "Apache License 2.0" would falsely conflict under exact SPDX matching.
- **What the scan does.** Any scanner hit, password class included, refuses. The record seeder redacts instead; I did not redact here, because external code is not ours to rewrite.
- **Generated outputs.** Labels hold only fix rows with `approved-by: pending`, because the defects come from blind annotation. The corpus.tsv kind is `external`, or `external-fetch` without trees. Provenance goes to `external/pr-NN.json` and attribution to `THIRD-PARTY.tsv`.
- **What `look` is.** `look` is the inventory id `c<N>-looks/<dir>`, because look-1 and look-1-amended share index 1. Order is strictly increasing by (N, i, suffix-last).
- **Completeness rule.** An unlisted committed look is allowed only if it was read under this registration or a successor; at build time every committed look must be listed. A look counts as committed when `git ls-files` tracks it, and its `<dir>.json` inputs.rows_sha256 must equal the file's hash.
- **Schema bump.** Only `--looks-seen` makes a record v2, which adds `looks_root` so verification is self-contained.
- **Self-reference.** A self or successor reference is refused. A real cycle is impossible by hash construction, so the helper carries the test.

## What the lead must do
- Regenerate checksums and REPO-MAP for the new and changed `.claude/` files: `lib/secret-classes.sh`, `record-branch.sh` and the planning-sprints `REFERENCE.md`.
- `evals/analysis/c132/tests/COUNT` is now 228, my 13 new cases. Re-add B's cases at landing.
- REG-4 in `evals/tests/registration.bats` was already red at `de366cc63`. run-ablation refuses the blocked egress arm, so the test probably needs `LOA_EGRESS_TEST_MODE=1`. The file is outside my ownership.
- D's README rewrite keeps § Shipping a measurement cycle.
- Close bd-y1smc and add DEC rows from the judgment calls.
- The a2a report copy is gitignored.
