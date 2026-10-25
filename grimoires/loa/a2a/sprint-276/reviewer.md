# Sprint 276 (cycle-134 sprint-1) — Implementation Report

**Branch:** `feature/cycle-134-post-ship-fixes` (sprint base `f17bfe0e4`; landing commit **`5fc05dc9`**, 67 files, +4399/−169; KF-034 follow-up `a601702d`; review-round fix `c87cc20c`; portability fix `dad9136f` — the PR head)
**Implementers:** four Opus 5.5 subagents in linked worktrees (A validator, B mount rules, C publish path, D harness libraries), patches under `~/.cache/loa/cycle-134/patches/`, reports under `~/.cache/loa/cycle-134/reports/`; the lead landed C, D, then A (plus A's home-scope fixture companion), then B; `run-ablation.sh`'s two record writers (D's outside-allowlist hunk) landed by the lead.
**Decisions:** planning DEC-0961 … DEC-0986; implementation (the implementers' judgment calls) DEC-0987 … DEC-0997 (sdd.md § 11.I).
**Regression:** `a2a/sprint-276/regression.md` — D-4.3 met (both retained smoke runs keep their verdicts; the one pre-registered `(g) transcript REVIEW: no result event` addition).

## Tasks

| Task | Owner | Status | Evidence |
|---|---|---|---|
| 1.1 Validator hook rule (bd-bex39) | A | done | `evals/harness/took-effect.sh`; `evals/tests/took-effect-hooks.bats` TEH-0 … TEH-13 (14; 13 red before) |
| 1.2 Validator transcript completeness (bd-k3dia) | A | done | `took-effect-transcripts.bats` TET-1 … TET-15 (15 red before) |
| 1.3 Validator integrity cross-check (bd-htzy2) | A | done (binding amended, DEC-0990) | `took-effect-integrity.bats` TEI-1 … TEI-8 (8 red before) |
| 1.4 Q-1 grammar + baseline (lead) | lead | done | `a2a/sprint-276/regression.md`; `~/.cache/loa/cycle-134/q1/` |
| 1.5 Mount rules corpus table, narrowing, hook-group emitter (bd-kgfh5) | B | done | `evals/harness/lib/sandbox-mount.sh`; `sandbox-mount-rules.bats` MR-01 … MR-24, HK-1 … HK-4 (28; 11 red before); sdd.md § 11.F; `r3r5-corpus.tsv` |
| 1.6 Classify guard (bd-hyx0n, KF-063) | C | done (merge-commit form added, DEC-0993) | `classify-merge-pr.sh`, `post-merge.yml`; `classify-merge-pr.bats` KF063-T1 … T13; `post-merge-workflow-guards.bats` PMWG-T1 … T4 (12 red before) |
| 1.7 Publish contract (bd-4pv1j) | C | done | `post-merge-orchestrator.sh`; `post-merge-publication.bats` c134 C-9 ×16 (13 red before); the rc.8 candidate fixture |
| 1.8 Proxy pid limit (bd-1br0v) | D | done (allowance placeholder: see Open items) | `egress-proxy.sh:206`, `Dockerfile.proxy:45`; `egress-proxy.bats` EP-10 (red before) |
| 1.9 Supervisor job identity (bd-ruo5b) | D | done | `batch-supervisor.sh` record-job/reclaim; `batch-supervisor.bats` BSV-14 … BSV-19 (+ BSV-8/13 asserts fixed); `run-ablation.sh:1670, 1763` |
| 1.10 Seeder fix-diff blobs (bd-kdk3l) | D | done | `seed-corpus-from-external.sh`; `seed-corpus-from-external.bats` SX-21 … SX-24 (3 red before) |
| 1.11 Sprint close | lead | done (this report; suites below; review and audit next) | `landing.md`, CHANGELOG `[Unreleased]`, DEC-0987 … DEC-0997, commit `5fc05dc9` |
| 1.12 Ship | lead | pending | — |

## Fails-before verification (lead, scratch worktree at f17bfe0e4, tests + fixtures only)

| Patch | new cases red before | after landing |
|---|---|---|
| C | 25 of 98 | 98/98 |
| D | 11 of 66 | 66/66 (egress 23/23 incl. containers) |
| A | 36 of 37 | 37/37; home-scope + took-effect existing 53/53 with the companion |
| B | 11 of 28 | 28/28 |

Combined after C+D: unit + harness 141/141. After A+B (+ companion): took-effect/mount suites 134/134. Full CI mirror: see "Suites" below.

## What was built (from the implementer reports)

### A — validator
- **1.1 hook rule (C-1)**:
  - The parse loop records `hook_started` as (transcript, event, query) from `hook_name` = `<event>[:<query>]` (`took-effect.sh:807`). A mismatched `hook_event` or an empty name fails.
  - Per-transcript trigger counters (`:778`): init, prompt turns, result, tool_use names.
  - The rule itself is at `:1378-1460`, with `triggers()` at `:1387`. It decodes `home_hook_groups`, merges same keys and checks malformed entries. When both lines are present, their per-event sums must agree.
  - Without `home_hook_groups`, `home_hook_counts` serves as the event-level aggregate. When both are absent, the cycle-133 message is kept.
  - The equation per transcript and name is c = k·n, with k ≤ triggers.
  - The evidence now ends `hooks: … c= n= k= triggers=; cc=…` (`:1462`). The header is at `:133-148`.
- **1.2 transcript completeness (C-2)**:
  - The suite's expected labels are passed into the clause (f)/(g) helper (`:663`, `:677`).
  - The phase-record check is at `:1064`.
  - `transcript_check()` (`:1079`) applies the JSONL policy.
  - The evidence carries `transcripts: …; unlabelled=…`. The header is at `:114-125`.
  - The parse loop skips non-regular or unreadable transcripts instead of crashing.
- **1.3 integrity cross-check (C-3)**:
  - The home-scope branch is at `:424-446`, with `operator_pin()` at `:475` and `_te_home_bind_py()` at `:493`, covering the pin manifest and the retained-HOME walk.
  - The header is at `:41-57`, and the "Tested by" list is updated.
- **Fixtures**: the corrected `home_hook_groups.sample`; `fixtures/took-effect/te-lib.bash`, which builds a real home-scope run through the mount library; the 8 real Q-1 events verbatim; the synthetic shapes; and a README as their comment.

### B — mount rules and the hook-group emitter
**Part 1 — the verify claim (correction, no code change).** `cmd_verify` (pin :1707-1731, now :1763-1785) compares `reverse(copied bytes)` with the pinned bytes for every file. `reverse()` (pin :1609-1626, now :1665) applies `R5_REV` to Python files (pin :1613, now :1669). So verify already round-trips R5. MR-23 proves it: it passes on the unpatched script.

**Part 1 — corpus and narrowing.**
- `evals/harness/lib/sandbox-mount.sh:1501-1550` holds `R3_TOK`, `R3_DATA`, `R3_FENCE`, `r3_pinned`, `r3_decide` and `r3_sub`. The regex R3 itself is unchanged; a context guard decides each hit.
- `:1617` makes `transform(text, k, home, rel, tree)` take the pinned tree (required, single caller `:1729`). `:1630-1632` routes the markdown branch through `r3_sub`.
- R5 is unchanged: all four R5 hits are run-time path operands.
- `reverse()` is unchanged and still an exact inverse. A source file already holding `<home>/.claude/` is refused before transform, as before.
- Header docs: `:153-157` (mount_home_scope entry), `:1471-1475` (R3 rule comment).
- Corpus: `evals/tests/fixtures/sandbox-mount/r3r5-corpus.tsv` has one line per hit, 1216 hits at f17bfe0e4 (1212 R3, 4 R5): row, rule, path, line, col, context, decision, token.
- `grimoires/loa/sdd.md` § 11.F: the placeholder row replaced by 21 rows. Nothing else in the file changed.

**Rule applied.** An R3 hit is rewritten when its token names an entry of the pinned tree: the literal path exists, a `*` glob matches, or a `{…}`/`<…>` placeholder sits under an existing directory below `.claude/`. The zone `.claude/` itself counts as pinned. Not rewritten: a path the pinned tree does not hold (`drop:absent`, 40 hits) and any hit in a file under `__tests__/` or `fixtures/` (`drop:data`, 3 hits). Exception: on a fenced command line that also names a pinned path, an absent path is rewritten too (`rewrite:line`, 3 hits). Example: `mv .claude/x.tmp.$$ .claude/x`.

**Before/after diff over the pinned tree** (scratch, `mount_home_scope` with the old and the new script):
```
home_transform R3:1212 -> R3:1169 (other rules identical)   home_transformed_files 394 -> 388
files differing 17, lines differing 43, unexplained 0; dropped hits per TSV row {11:16, 12:13, 13:9, 14:2, 17:3} = 43
home_verify=ok 1778 files, 388 redirected, reverse == pinned
```
Every difference is one dropped row: the after-line equals the before-line with `<home>/` removed exactly at that row's hits.

**Part 2 — `home_hook_groups`.**
- `cmd_hooks` (`:1787-1806`) prints line 1 unchanged (`home_hook_counts`). Line 2 is `<event>:<hex12>:<n>;…`, merged by (event, SHA-256(matcher)[:12]) and sorted by event, then hex.
- The writer is `mount_home_scope` in this file (`:1863-1865`). It writes both lines into `ARM_EVIDENCE_FILE`, so `meta/arm-evidence.txt` gets both and `pipeline-run.sh` needs no change. `_sm_evidence` flattens newlines, so the two lines are split before writing.
- Real pinned settings emit 14 groups across 8 events. Per event the group sums equal `home_hook_counts`.
- `evals/tests/fixtures/home_hook_groups.sample`: the brief's hash was wrong. `printf %s Bash | sha256sum` gives `d1e9567da9a8…`, not `a5e744f0d4f6`. The shipped sample uses `d1e9567da9a8`, and c134-impl-a and the lead were told mid-task. `e3b0c44298fc` (empty string) is correct. `Write|Edit:x` gives `2b07a9f0e8be`.

### C — classify guard and publish contract
**Task 1.6 (bd-hyx0n, KF-063)**
- `classify-merge-pr.sh:21-30` header; `:97-107` the number is the trailing `\(#([0-9]+)\)[[:space:]]*$`, else the prefix `^Merge pull request #([0-9]+)([[:space:]:]|$)`, kept only if `^[1-9][0-9]*$`; `:151-156` an empty number gives `pr_type=other` and the stderr line `[classify-merge-pr] no associated PR: a push, not a merge`. `--pr-number` and the `gh` failure path are unchanged.
- `post-merge.yml:182-187`: `full-pipeline` has `if: needs.classify.outputs.pr_type == 'cycle' && needs.classify.outputs.pr_number != ''`, under a comment naming KF-063 and run 40112013975. `simple-release` (:110) is unchanged.
- KF-063: Status "Fixed in cycle-134 Sprint 276 (classify-merge-pr.sh trailing (#NNN) + full-pipeline guard; live confirmation at the next rc publish)"; attempt row via `kf-write-lib.sh attempt` with the brief's text.

**Task 1.7 (bd-4pv1j)**, `post-merge-orchestrator.sh`:
- `:45-71` header: a "Publish contract" block, then the exit table:
  ```
  #   1 - Invalid arguments, generation failure, or a publication step failed
  #       after a write (e.g. a tag appearing between validation and the push)
  #   2 - Refusal before any write (digest, schema, v1, ancestry, ledger patch;
  #       local or remote tag identity mismatch, lightweight tag, unreachable
  #       remote; a non-integer number at generate or publish), fatal setup
  #       error
  ```
- `:1105-1127` `phase_tag`: a local or remote mismatch at the re-check now fails the phase with "… of another identity appeared between validation and the push" and returns 1, not 2. An identical remote tag still skips the push.
- `:1665-1675` `remote_tag_lookup`: `ls-remote` under `timeout 60` when available.
- `:1677-1700` `validate_tag_identity`: the local tag must pass `tag_identity_matches`, so a lightweight tag is refused. A failed lookup or fetch is "remote unreachable, identity unverified". A remote tag is fetched to `refs/loa/post-merge/observed-tag` and must match. Each refusal is one line, exit 2.
- `:1701-1769` `number_domain_check FILE PREFIX` (Python `-I`): raw tokens from the `json` parse hooks are checked against the brief's regex. It refuses a fraction, an exponent, `-0`, |n| > 2^53−1 and NaN/Infinity, and names the token and path. Duplicate keys are visited.
- `:2027-2028` `validate_candidate_v2` scans first; `:2070-2072` it checks the tag identity before the ledger checks, all before `PUBLISHING` (:2322). `:2105-2106` `prepare_candidate` scans `$STATE_FILE` as `.prepared_state` before any candidate artefact. `:2249-2250` the `--allow-v1` path checks the tag identity too. `jcs_stdlib_file` is unchanged.

### D — harness libraries
- **1.8 (C-5).** `egress-proxy.sh:206` raises the sidecar's `--pids-limit` from 128 to 256, with a one-line reason at :203. `Dockerfile.proxy:45`, the documented run line, follows. The guard (`--pids-limit 16`) and the probe (256) are unchanged.
- **1.9 (C-6), `lib/batch-supervisor.sh`:**
  - `record-job <jobs-dir> <name> <pgid> [fields…]` (:639, dispatched before `paths`) writes `<name>.ident` and then `<name>.pgid`, each through a temporary file and a rename.
  - New helpers: `leader_live` (:120), `job_ident` (:127), `job_ident_settled` (:139) and `group_members` (:160, `pgrep -g`, else a `/proc` scan).
  - `kill_group` (:306) takes an optional identity. It re-reads it before TERM and again before KILL.
  - `reclaim` (:326) checks identity, handles legacy and leaderless records, and gives one warning line for the legacy ones.
  - The header documents the `record-job` usage (:36) and the "Job records" section (:75): the format, the legacy and leaderless handling, and the residual window.
- **1.10 (C-7), `seed-corpus-from-external.sh`:**
  - `fix_want` takes every blob entry of both sides of `changed(FIX_PARENT, FIX_LAST)` (:487), now symlinks too.
  - The fix's blobs not already in the PR's set are counted separately (:513). They are charged once against the same bounds. When they do not fit, the run refuses with `fix diff needs N blob(s) outside the fetch bounds: <paths>` (:524).
  - A failed batch fetch now exits 1 naming its paths (:540).
  - The fix diff runs with `check=False`. A non-zero exit refuses (exit 2), so no partial diff is written (:599).
  - The header gains the five phases (:43-53).
- **Outside the allowlist, `run-ablation.sh:1670, 1763`.** The two `.pgid` printf writers call `lib/batch-supervisor.sh record-job`. If that call fails, the old printf runs as a fallback.

## Tests (implementer-reported; the lead's fails-before table above is the independent check)

### A
| File | Cases | Red on pristine `HEAD` | Green |
|---|---|---|---|
| `evals/tests/took-effect-hooks.bats` | TEH-0 … TEH-13 (14) | 13 of 14 (TEH-0 is the sample self-check) | 14 |
| `evals/tests/took-effect-transcripts.bats` | TET-1 … TET-15 (15) | 15 | 15 |
| `evals/tests/took-effect-integrity.bats` | TEI-1 … TEI-8 (8) | 8 | 8 |

The red run used the final files against `HEAD`'s `took-effect.sh` (`scratch-a/red-final.txt`). Key reproductions:
- **TEH-1 before (F-001):** `FAIL (g) -: 2 PreToolUse hook(s) ran in events-REVIEW.jsonl; the pinned user settings declare 1 (home_hook_counts)`. After: `REVIEW PreToolUse:Bash c=2 n=1 k=2 triggers=2`.
- **TET-2 and TET-5 before (F-002):** `oracle_closed OK` with the AUDIT transcript missing, or with no result event. After: `transcript AUDIT: missing (transcripts/events-AUDIT.jsonl)`, and `transcript REVIEW: no result event (last line 4)`.
- **TEI-4, TEI-5 and TEI-6 before:** `integrity_clean OK home-scope: 1 HOME framework entries verified at finish`, the record trusted. After: the count, pin and tamper failures, each by name.

With the companion applied, the 11 bats files that reach `took-effect.sh` ran 418 tests. 417 passed. `ablation-row.bats` test 273 failed on a shared-`/tmp` race with other implementers, and it passes alone.

Without the companion, the main patch fails seven home-scope cases: HS-5, HS-5b, HS-6, HS-7, HS-8, HS-12 and HS-13. Their fixtures write no result event. HS-8's record lacks AUDIT. HS-12's suite pins the placeholder `<sprint-258-commit>`, and its framework has no `checksums.json`. The companion fixes all seven: one final result per transcript, HS-8's REVIEW-only phase set, and a manifest and pin for HS-12. Evidence is in `scratch-a/hs-main-only.txt`.

### B
`evals/tests/sandbox-mount-rules.bats` (new, 28 cases) uses the fixtures under `evals/tests/fixtures/sandbox-mount/pinned/.claude/`. Each row file holds one verbatim line of the pinned framework. Row 17 is shortened from `pr1289-r2-comments.md:95`.
- MR-01…MR-21: one per § 11.F row. Kept rows must equal the expected rewrite, differ from pinned and pass verify. Dropped rows must be byte-identical.
- MR-22: a planted prose mention of absent paths is not rewritten; the zone and the pinned script on the same lines are.
- MR-23: verify FAILs on a planted `.claude/` literal and on an edited literal inside an R5 wrapper.
- MR-24: the real corpus from `git archive f17bfe0e4 .claude`. The TSV equals the set of R3/R5 hits, and the transform output (R1/R2 undone) equals the pinned text with `<home>/` inserted at exactly the kept rows. It reports `ok 1216 rows, 1173 kept, 43 dropped` and skips if the commit is absent from the clone.
- HK-1…HK-4: the sample, the colon/pipe matcher round-trip via a `hook_name` parse, the merge (including empty and missing matcher), and both evidence lines from `mount_home_scope`.

Red, with the original script swapped in: 17 ok, 11 not ok. The failing cases are MR-11, 12, 13, 14, 17, 22, 24 and HK-1, 2, 3, 4. MR-24 failed with `rewrite differs from the TSV in 17 file(s)`; its completeness half passed. HK-1 printed only `PreToolUse:3,SessionStart:8,UserPromptSubmit:2`. The kept rows and MR-23 pass before and after: behaviour preserved, and verify already covered R5.

Green, patched (bats 1.13 via npx):
| file | ok | not ok |
|---|---|---|
| sandbox-mount-rules.bats | 28 | 0 |
| sandbox-mount-home-scope.bats (incl. HS-8 negative control, HS-10, HS-11) | 15 | 0 |
| sandbox-mount.bats | 16 | 0 |
| arm-toggles.bats | 26 | 0 |
| took-effect.bats | 38 | 0 |
| pipeline-run.bats | 99 | 0 |
| execute-agent.bats | 14 | 0 |
| ablation-grade.bats | 88 | 0 |

egress-proxy.bats was not run: it starts containers, and the file is untouched.

### C
| File | Cases | Result |
|---|---|---|
| tests/unit/classify-merge-pr.bats | 30 (17 existing + KF063-T1…T13) | 30/30 |
| tests/unit/post-merge-workflow-guards.bats (new) | PMWG-T1…T4 | 4/4 |
| tests/unit/post-merge-publication.bats | 64 (48 existing + 16 "c134 C-9") | 64/64 |
| other post-merge suites (11 files: integration 697, archive-gate, changelog-routing, classifier, gt-regen, lore-promote, orchestrator, preflight-guard, version-bump, bug-986, mount-workflow-scaffold) | 126 | 126/126 |

The baseline before any change was 65/65 on classifier plus publication.

**Red → green**
- Classifier. KF063-T1–T7, T12 and T13 were red: the ledger subject gave `pr_type=cycle` and T3 gave `pr_number=12`. T8–T11 were already green and stay as guards.
- Guards. PMWG-T2, T3 and T4 were red ("job full-pipeline needs classify without a pr_number guard"). T1 was already green.
- Publication. The four tag-identity cases were red on the message: the old code exited 2 from `phase_tag` after PUBLISHING was written. The unreachable case exited 2 through the ancestry preflight, not "identity unverified". The race gave 2 where 1 is required.
- With rfc8785, `--generate` accepted `1.0`, `1e3` and `-0` with **status 0**, which is the defect. ±2^53 exited 2 only through rfc8785's own error. The `--publish` scan case was refused by the canonical-form check without a path. The rc.8 scan failed because the function did not exist.
- Already green and kept as guards: the identical-identity re-run, the 2^53−1 accept case, and stdlib/rfc8785 agreement on rc.8. All 16 are green after the patch.
- The race is injected by a `reference-transaction` hook: when the preflight first writes `refs/loa/post-merge/observed-main`, it creates an annotated tag of another identity in the bare remote. "Without rfc8785" is a `PYTHONPATH` stub that raises ImportError.
- "Pre-write" is `prewrite_fingerprint`: the state, progress and ledger-patch hashes, local `refs/heads` and `refs/tags`, every remote ref, the state still PREPARED, and no GitHub POST.

### D
| File | New or changed cases | Red before the fix | After |
|---|---|---|---|
| egress-proxy.bats | EP-10 (:278; `BASE_ALLOWANCE=16` with the placeholder comment at :264-265) | `[ "$lim" -ge $((maxc + BASE_ALLOWANCE)) ]' failed`, printing `launcher=128 dockerfile_run_line=128 MaxClients=200` | 23/23, with `LOA_EGRESS_GATE=1` on Docker 26.1.5: every EGR container case ran the proxy at 256 |
| batch-supervisor.bats | BSV-14 … BSV-19 (:280-380); BSV-8 (:209, :218-219); BSV-13 (:469) | BSV-14 to 19 failed: `record-job` exit 2, legacy and leaderless groups signalled. BSV-8 failed once its `!` assertion was made effective: the pipeline survived. BSV-13 with the allowlisted patch alone: `groups_terminated | length' -ge 1 failed` and `WARN reclaim: 1 .jobs record(s) carry no identity` | 19/19, run three times, with both patches |
| seed-corpus-from-external.bats | SX-21 … SX-24 (:391-462) | SX-22: generic `exceed --max-files` message. SX-23: `git diff --no-color failed: … could not fetch 32d46ee8… from promisor remote`, the defect reproduced with a symlink in the fix. SX-24: no path named. SX-21 was already green and stays as a guard | 24/24 |
| run-ablation.bats | none | — | 59/59 with both patches |
| quarantine-expiry, secret-classes, corpus-seed-lib | none | — | 37/37 |

## Acceptance criteria (implementer-reported, lead-checked against prd.md)

### A (FR-1, FR-2, FR-4)
- **FR-1:** AC1, AC3, AC4 and AC5 are met (TEH-1, TEH-3 to TEH-5, TEH-12, the regression, the header). AC2 is partly met. The parser takes both forms, but the real-event grammar is confirmed only for `SessionStart:startup` (Q-1), so tool hooks stay open on bd-bex39.
- **FR-2:** all three ACs are met (TET-1 to TET-15, the regression, the header).
- **FR-4:** both ACs are met (TEI-1 to TEI-4, TEI-6, the regression) under the binding in judgment call 14, because literal digest equality is infeasible.

### B (FR-5; FR-1 evidence part)
- FR-5 AC1 (table per rule, each row a case, corpus diffed, every difference explained): **met**. § 11.F has 21 rows, each an MR case. The TSV holds every hit. The diff shows 43 differences, all dropped rows.
- FR-5 AC2 (verify re-checks R5 and fails on a planted literal): **met** (MR-23). Verify already did this; the correction is recorded.
- FR-5 AC3 (home-scope bats and negative control green): **met**, 15/15.
- § 3.2 / D-1.1a evidence (`home_hook_groups`): **met** (HK-1…4). The sample is shared with A.

### C (FR-3, FR-9)
- **FR-3 AC1, met.** The ledger subject and an empty number give `other` (KF063-T1, T2, T13). `closes #12 (#345)` gives 345 (T3). Values without a valid trailer give no number (T4–T7).
- **FR-3 AC2, met.** PMWG-T2 and T3 check the workflow text with yq.
- **FR-3 AC3, met.** A `gh` failure with a trailer keeps the subject classification and the number (KF063-T10).
- **FR-3 AC4, met.** The change is confined to `post-merge.yml` and the classifier. The 31 other workflows that run on a push to `main` are unchanged: activation-regression, aleph-bundle-integrity, audit-secret-redaction, bash-runner, bats-tests, beads-health-gate, bridgebuilder-dist-smoke, bun-runner, check-bb-dist-fresh, check-glossary-terms, check-no-raw-sha256sum, check-no-swallowed-jq, check-prompt-budget, ci, cycle099-sprint-{1e,1e-b,1e-c-ts,1e-c2-dns,2d,2d-c-ts,2d-d-property,2e}-tests, cycle-108-schema-guard, jcs-conformance, lib-tests, model-health-probe-concurrency, no-direct-llm-fetch, python-runner, readme-version-sync, security-audit, workload-tier-map-drift.
- **FR-3 AC5, KF part met.** The lead writes the CHANGELOG entry. The live confirmation is pending until the next publish.
- **FR-9 AC1, met.** A local tag of another identity, a remote tag of another identity, a lightweight tag (local and remote) and an unreachable remote all exit 2 with nothing written. The race exits 1 with the state FAILED. The identical-identity re-run skips the push.
- **FR-9 AC2, met.** `1.0`, `1e3`, `-0` and ±2^53 exit 2 with the nested path, with and without rfc8785. At `--publish`, `1.0`, `-0`, 2^53 and `1E+3` exit 2 with the path. 2^53−1 passes and is byte-identical on both canonicalisers. The rc.8 fixture has 10 integers, passes, and canonicalises identically.
- **FR-9 AC3, met.** The header table is shown above.

### D (FR-6, FR-7, FR-8)
- **FR-6.**
  - The pid limit is at least MaxClients + 16, both read from the files: met (EP-10).
  - The allowance constant carries the placeholder comment as briefed. The lead's observation is still to do. One data point for it: `docker stats` showed **1 PID** at idle in `loa-proxy-egt16906` (PidsLimit=256) on 2026-10-25. `/sys/fs/cgroup/pids.current` is not visible inside the container. The host path under `/sys/fs/cgroup/…/docker-<id>.scope/pids.current` is the way to read it.
  - Every launch path uses the same limit: met. EP-10 asserts that exactly one `--name "$PROXY"` run exists.
  - The Dockerfile run line matches the launcher: met.
- **FR-7.**
  - A stale identity is not signalled: met (BSV-15). A matching identity is terminated: met (BSV-16, BSV-8).
  - A record with no `.ident` is stale and never signalled: met (BSV-17).
  - Leaderless groups are handled: met (BSV-18).
  - The identity is re-read before KILL: met (BSV-19). The re-read before TERM uses the same code, but no test reaches it deterministically.
  - The residual window is documented in the header: met.
  - Existing tests stay green: met, **only with the run-ablation hunk**. Without it, BSV-13 fails.
- **FR-8.**
  - A `file://` fixture exercises the real fetch: met.
  - A fix outside the PR's files is fetched within the bounds and its diff is complete: met. SX-21 and SX-23 compare the fix-diff byte count against git's.
  - Out of bounds, the run refuses naming the paths and writes nothing: met (SX-22, for files and bytes, dry-run and `--commit-trees`).
  - A corrupted object gives no partial output: met (SX-24).
  - Existing SX-1 to SX-20 stay green: met.

## Judgment calls → decisions

Every implementer judgment call is recorded in `grimoires/loa/decisions.yaml` as DEC-0987 … DEC-0997 (sdd.md § 11.I lists the design amendments: integrity binding by coverage not digest equality — DEC-0990; the merge-commit PR-number form — DEC-0993; the hook_name suffix as the trigger query with regex-only groups failing closed — DEC-0987; tool triggers compared as text — DEC-0988; the supervisor record-job and settle rule — DEC-0995). Brief errata: the sample fixture's `sha256("Bash")[:12]` was given as `a5e744f0d4f6`; the correct value `d1e9567da9a8` was computed independently by A and B.

## Open items (implementer-reported, with the lead's disposition)

### A
- Tool-hook `hook_name` grammar is unconfirmed (Q-1), and the regex-only groups of judgment call 3 depend on it.
- The c133-smoke suite's `source_commit: "ba11b860"` is stale for these batches. The C-3 pin relies on the batch MANIFEST.
- The C-3 spec (PRD FR-4, SDD D-1.3, Task 1.3) says digest equality, so judgment call 14 needs a DEC row.
- `ablation-row.bats` test 273 is flaky under concurrent `/tmp` use, independent of this patch.

### B
- **bd-kgfh5 comment** for the lead to post: "verify already round-trips R5 via R5_REV (sandbox-mount.sh:1613, 1707-1731); the breadth concern stands and is narrowed per the § 11.F table". After this patch those lines sit at :1669 and :1763-1785.
- **sdd.md § 11.F intro.** It still says "sandbox-mount.sh:1496, 1503" and "lists every hit". After the patch R3 is at :1501 and R5 at :1557. I could not edit the intro (table only).
- **Optional `pipeline-run.sh:836-840`** (not mine): record the groups in `meta/mount.json` by adding the two lines below. The validator does not need this.
  ```
  --arg groups "$(sed -n 's/^home_hook_groups=//p' "$ARM_EVIDENCE_FILE" | sed -n '$p')" \
  home_hook_groups: $groups,
  ```
- **MR-24 is pinned to f17bfe0e4.** A shallow CI clone skips it. A future `.claude/` change does not break it.
- **No unrelated defects were found.**

### C
- **KF-063 index row (for the lead).** The KF-063 row in the file's index table, at `known-failures.md:113`, still says "Open (bead bd-hyx0n …)". It is outside my allowlist, so the lead should update it or regenerate it.
- **Live confirmation.** KF-063 is confirmed live only after the next publish's ledger push. The attempt row should be updated then.
- **Stdlib bound, not changed.** `jcs_stdlib_file` refuses only `abs(n) > 2**53`, so it accepts 2^53, while rfc8785 refuses it. The new scan closes the gap upstream. The canonicaliser was left as is, per the brief.
- **shellcheck not run.** It is not installed on this host.

### D
1. **The outside-allowlist hunk must land with s1-d.** Without it, every real `.jobs` record lacks `.ident`. Reclaim then removes it unsignalled, so a supervised resume leaves orphaned pipelines spending. BSV-13 fails in that state.
2. The new `record-job` call can delay the `.pgid` write by up to 5 s, typically about 50-100 ms, before `wait`. In that window a driver SIGTERM's cleanup does not see the job.
3. The seeder's "reads an object outside the fetched set" refusal is defensive. Once every changed blob is in the want set, no fixture reaches it.
4. Shellcheck is not installed on this host, so it was not run. `bash -n` passes on all three scripts.
5. Landing precondition from Task 1.11: no live `.jobs` records on the host. Legacy records become stale and unsignalled.

Lead dispositions: the pid-limit `BASE_ALLOWANCE` placeholder is replaced with the observed `pids.current` before the review (Task 1.8 AC); the tool-hook grammar and regex-only groups stay open on bd-bex39 (DEC-0987); the stale `source_commit` in the c133-smoke suite is recorded evidence and not edited (DEC-0990); `pipeline-run.sh`'s optional `mount.json` groups line is not taken (the validator reads the evidence file); the KF-063 index row is updated by the lead; a stray untracked `grimoires/loa/evals/judge-v2/PREREGISTRATION.md` appeared in the lead's checkout during the sprint (a grader-validation preregistration unrelated to Sprint 276) and is left untouched and unstaged.

## Suites (lead, local CI mirror `~/.cache/loa/cycle-134/scripts/s-tests.sh all`, logs `~/.cache/loa/cycle-134/tests/20261025T050511Z-*.log`)

| Suite | Result | Notes |
|---|---|---|
| unit (`tests/unit/`) | 7162 ok, 4 not ok | 3 × `semver-evidence.bats` "fatal: no tag message?" = **KF-034** (host `tag.gpgSign`/`forceSignAnnotated`; red on `origin/main` too in a scratch worktree; CI hermetic) → KF-034 recurrence 5 + attempt row; 1 × `template-safety.bats` ISO-8601 on a **gitignored local** vision entry (`visions/entries/vision-021.md`; CI skips the dir) → the local file's Date line split, now green |
| evals (`evals/tests/`) | 918 ok, 0 not ok | includes the container egress bats (23) and the new took-effect/mount/supervisor/seeder cases |
| scripts (`.claude/scripts/tests/`) | 399 ok | |
| vitest (Bridgebuilder) | 159 ok | |
| pytest (adapters + unit py) | 3493 passed, 2 failed, 6 skipped | both `test_claude_headless_adapter` command tests assert `cmd[0] == "claude"`; the host exports `CLAUDE_HEADLESS_BIN` (the operator's claude-fallback wrapper); pass with the variable unset — host-local, not a sprint change |
| analysis (`evals/analysis/c132/tests`) | 250 passed | |
| gates (guard-yield, knob-readers, manifest-paths, checksums --check, swallowed-jq) | PASS | checksums/REPO-MAP regenerated under the marker in the landing commit |

CI on the PR is the gate of record; the four host-local reds are explained above and reproduce on `main`.
