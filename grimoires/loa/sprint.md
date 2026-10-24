# Sprint Plan: The follow-through (cycle-133)

**Version:** 1.1
**Date:** 2026-10-23
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md (cycle-133, 1.1, FR-1 … FR-14; Appendix A D-1 … D-12)
**SDD Reference:** grimoires/loa/sdd.md (1.2; §1.4 components C-1 … C-14, §3.2 schemas, §5.2 interfaces, §8 phases, §11.D D-1.1 … D-4.2)
**Ledger:** cycle `cycle-133-follow-through`, sprints global 272 / 273 / 274 / 275 (local sprint-1 … sprint-4)
**Execution:** `/run sprint-plan`, push AUTO; Opus 5.5 implementers in linked worktrees returning `git diff --cached --binary` patches with a mandatory "Judgment calls" section (each alternative rejected) that the sprint-close task turns into DEC rows; the lead is the integration owner — patches land in the order each sprint names and later implementers rebase on the landed ones; the lead applies, reviews and audits on Fable 5.1; at most three dissent runs per sprint — when they are spent and review or audit is still not APPROVED the lead records a DEC row with the unresolved findings, marks the sprint BLOCKED and HALTS the run for the operator; a draft PR is opened from the cycle branch at the end of Sprint 1 so CI runs for the whole cycle and Sprint 4 marks it ready; sprint dates are targets, not gates — a slip lengthens the cycle and skips nothing
**Task kinds:** every task carries `kind: mechanical | judgment` (DEC-0144); no `operator` task exists — the operator's instruction authorised the cycle end to end (PRD § Authorization basis, D-11); the operator can halt at any time
**Spend:** USD 100 cap excluding subagents, allocated smoke 40 (the ≤ USD 2 scope spike and one reserved verification rerun inside it) / Bridgebuilder 20 (plateau rule: stop after a round adding no new HIGH or MEDIUM, at most three rounds) / dissent 40; the cycle meter is read before every paid step and every sprint report carries a running spend line per share; funds exhausted before a gate → HALT for the operator; no paid measurement; the cycle-132 pin, record and reads untouched (PRD § Constraints, D-S.1 DEC-0859)
**System Zone authorization:** granted for this cycle (PRD § Technical Considerations, D-4): every `.claude/` write under a bounded zone marker, checksums and REPO-MAP regenerated in the same commit

---

## Executive Summary

Four sprints close every cycle-132 follow-up and the three product changes that need no model spend to build. Sprint 1 (global 272) fixes the framework's own tooling: the Bridgebuilder fetch and consensus writer, the release publish path, the record-branch script and four ergonomic defects, CI and the ten failing unit tests. Sprint 2 (273) hardens the harness and the reproduction tooling and pins the next pipeline version. Sprint 3 (274) builds the product: Loa reviewing Loa under a pinned framework (spike first), one finding contract with a judge-able grader hook, and the external corpus seeder. Sprint 4 (275) sweeps the tracker with evidence and ships 2.0.0-rc.8 through the fixed path. Each sprint ends with review and audit; the cycle ends with the Bridgebuilder built on the cycle branch reviewing its own PR.

> Sources: prd.md § Executive Summary, § Timeline & Milestones; sdd.md §8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 272 | The framework's own defects | paged SHA-pinned Bridgebuilder fetch + guarded writer + block verdict (C-1, C-2); publish tags the merge, ledger patch ff (C-3); `record-branch.sh`, notes-guard, hook, dec-write, scope, ledger validator (C-4); CI pytest glob, quarantine, ten tests, gitattributes + tripwire (C-5) | none |
| 2 | 273 | Harness and reproduction hardening | session lib fail-closed + sourced (C-6); reproduction/analysis hardening (C-7); grader 1.4 + refusal policy (C-8); supervisor + egress + image 259 (C-9); pipeline version pinned | Sprint 1 CI |
| 3 | 274 | The product | spike (HALT on failure); HOME-scope mount + clauses (e)–(g) (C-10); finding schema + Failure clause + grader 1.5 + judge read (C-11); shared seeding lib + external seeder + registration v2 + guidance (C-12); the measurement pin and the smoke | Sprint 2 intermediate version; egress suite green |
| 4 | 275 | Hygiene and ship | sweep inventory → manifests → closures + sample (C-13); rc.8 docs, PR, Bridgebuilder, merge, record, publish, archive (C-14) | Sprints 1–3 |

> Sources: prd.md § Timeline & Milestones; sdd.md §8

---

## Sprint 1: The framework's own defects (global 272)

**Duration:** 1 day
**Dates:** 2026-10-24

### Sprint Goal
Make the framework's own tooling trustworthy again: a Bridgebuilder that reads any PR and reports a verdict it can defend, a publish path whose tag `main` can reach, one command for the record branch, four ergonomic defects gone, and green suites in CI.

### Deliverables
- [ ] C-1 paged, SHA-pinned Bridgebuilder fetch with coverage record and `degraded_reason` enum; default excludes; `gh_max_buffer_bytes` → **[G-2]**
- [ ] C-2 enrichment guard (schema + semantic equality + no tool grammar), writer-role allowlist, block-derived verdict with precedence; PR #1289 round replays → **[G-2]**
- [ ] C-3 candidate v2 (target = merge, ledger patch, digests, ref updates), publish with remote-main check, `--force-with-lease` ff, idempotent sequence → **[G-3]**
- [ ] C-4 `record-branch.sh`; `notes-guard.sh rotate` keeps every template section; hook liveness; dec-write length message; `security-audit-scope.sh --help/--files`; `validate_ledger` schema_version → **[G-1]**
- [ ] C-5 CI pytest glob `evals/analysis/*/tests`; `tests/QUARANTINE.tsv` + helper + expiry gate + counts; the ten `tests/unit` failures repaired or quarantined; `.gitattributes` + lint-walk tripwire → **[G-6]**

### Acceptance Criteria
- [ ] PRD FR-1 AC 1–7 (mechanism named; immutable pair; 2,000- and 3,001-file fixtures; coverage record; degraded enum; default excludes; knob documented, dist fresh)
- [ ] PRD FR-2 AC 1–4 (per-adapter no-tools tests; guard rejections; verdict precedence cases; round-1 → COMMENT, round-2 → fallback exit 3)
- [ ] PRD FR-3 AC 1–3 (design-neutral bats incl. moved main, existing tag, crash recovery, mutated candidate; manifest digests)
- [ ] PRD FR-4 AC 1–2 (bats per script incl. the credential-shaped hit that stops the record build; docs; cache scripts retired)
- [ ] PRD FR-5 AC 1–4 (CI runs the analysis pytest; `tests/unit` green; tripwire; expired quarantine fails CI)
- [ ] Review APPROVED, audit APPROVED (`All good`, LOA-VERDICT trailers), ≤ 3 dissent runs

### Technical Tasks

- [ ] Task 1.1: Bridgebuilder paged fetch (A) — `adapters/github-cli.ts`: `getPR` (base/head sha, changed_files), the two-pass fetch of sdd.md C-1 (pass 1 metadata pages with per-page SHA re-check and dedup, global `truncateFiles` selection, pass 2 patches for selected files only, final base+head revalidation), `gh_max_buffer_bytes`; the two default excludes; callers `core/reviewer.ts:820`, `main.ts:614`; coverage record (`reviewed`, `omitted` with reasons incl. `no_patch`, `patch_truncated`, `files_list_truncated`, `page_incomplete`, `unknown_omitted`) in the marker and summary JSON, counts plus first 20 paths in the comment; verdict eligibility per `degraded_reason` (an omitted reviewable code file → `mergeBlocked: true`, `incomplete_coverage`); `degraded_reason` enum in `core/run-outcome.ts`; vitest: 2,000-file fixture with mocked `gh`, 3,001-file cap, oversize single patch, head moved → restart once then degrade, patch fetch count equals selected count, excluded security-relevant file never degrades, each degraded reason's verdict; `npm run build`, `dist/` committed, `check-bb-dist-fresh`; SKILL.md knobs; bead bd-ra4im → **[G-2]** · kind: mechanical
- [ ] Task 1.2: Bridgebuilder consensus integrity (A, after 1.1 on the same files) — findings rendered deterministically from the consensus with every canonical field (id, file, anchor_line, anchor_line_end, severity, confidence, failure_scenario, suggestion, blocking), writer output as separate commentary; `core/enrichment-guard.ts` (own findings block, altered or omitted canonical field, duplicate ids, structural tool-grammar match outside fenced spans and string values → `enrichment_guard_rejected`, exit 3); `writer_role_allowlist` default claude-headless + API adapters (codex-headless only after a vitest proves its native tools cannot execute; adapters self-report the enforced no-tool stance in the dispatch result and the role check verifies it; unknown adapter versions refused; `writer_not_eligible`); `core/review-verdict.ts` decision table of sdd.md C-2 incl. `blocking`, `verdict_conflict`, `mergeBlockedReason`; fixtures: the PR #1289 round-1 and round-2 bodies (from `record/cycle-132-conclusive-review-catch:grimoires/loa/a2a/sprint-271/bridgebuilder/`) replay as COMMENT and as guard-rejected fallback; attempted-tool-call tests per eligible adapter; bead bd-cpvc6 → **[G-2]** · kind: mechanical
- [ ] Task 1.3: Release publish (B) — `post-merge-orchestrator.sh --generate`: candidate schema_version 2 per sdd.md C-3 (sealed object canonicalised with `lib/jcs.sh`: `target_commit = merge_sha`, `post-merge-ledger.patch` + `ledger_patch_sha256`, deterministic `ledger_commit` identity and dates so `ref_updates[].new` is computable, `release_notes_sha256`, `target_on_main`; mutable `progress` file beside it); `--publish`: v1 candidates refused with a regeneration instruction (`--allow-v1` with a logged reason only), digest check, `merge_sha` ancestor of the freshly fetched remote `main`, ancestry re-verified before each externally visible step, tag the merge (existing tag accepted only on identical target and release identity), release, ledger patch validated (only `grimoires/loa/ledger.json`, active → archived) and pushed `--force-with-lease=refs/heads/main:<observed sha>` (lease failure → `ledger_commit: deferred` + `.run/post-merge-ledger-deferred.json`; `--publish --ledger-only` completes it), recovery state machine; branch protection read (`branches/main/protection`) recorded in the sprint report; `tests/unit/post-merge-publication.bats`: ancestor success, main advanced between check and tag, moved main at the ledger step → deferral, existing-tag identity match vs conflict, crash after tag / after release / after ledger push → idempotent re-run, mutated candidate or digest refusal, v1 refusal, tag reachable from main (KF-034 setup kept); bead bd-kwloh → **[G-3]** · kind: mechanical
- [ ] Task 1.4: `record-branch.sh` (C) — `.claude/scripts/record-branch.sh` per sdd.md C-4 (manifest from the ledger cycle or `--manifest`, symlink and escape refusal over the complete final tree, temp index, scan of the paths that differ from `<head>` exported to a bounded temp dir for `audit-secret-redaction-scan.sh` — the parents `prev` and `head` are already public refs, which the script asserts before committing — credential-shaped classes non-bypassable (exit 2), `--accept-scan TREE` for other classes recorded in the commit message and manifest (`scan_tree`, `accepted_scan`), `commit-tree -p prev -p head`, `update-ref` compare-and-swap, `--dry-run` size table); bats on a fixture repo (paths present, sandbox absent, refusals, planted credential hit stops even with accept, CAS refusal on a moved record ref, dry-run no ref); the archive-cycle and ship skill text names it; NOTES records the retirement of the cycle-125 … 132 cache scripts; bead bd-mgun5 → **[G-1]** · kind: mechanical
- [ ] Task 1.5: Framework ergonomics (C) — `notes-guard.sh cmd_rotate` section-by-section retention (Blockers and Active Sub-Goals whole, newest Session Continuity, three Decision Logs, capped Session Log) with a bats case that two open blockers and two sub-goals survive and `check-loa.sh` passes; `pre-compact-marker.sh` liveness by state allowlist + `LOA_HOOK_LIVE_WINDOW_DAYS` (COMPLETED file → silent; RUNNING → active; HALTED → awaiting resume); `dec-write-lib.sh:471` message with measured and maximum length; `security-audit-scope.sh --help`, `--files`, `--paths` + the auditing-security SKILL.md Phase -1 text; `ledger-lib.sh validate_ledger` schema_version (alias `version`) with a bats case on the live shape; beads bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5, bd-4pjqm → **[G-1]** · kind: mechanical
- [ ] Task 1.6: CI and test health (D) — `bats-tests.yml` pytest step globs `evals/analysis/*/tests`; `tests/QUARANTINE.tsv` (expiry = quarantine commit date + 30 days, ISO), `tests/unit/helpers/quarantine.bash`, `tools/check-quarantine-expiry.sh` (row validation per sdd.md C-5; fails on expiry; prints full-suite executed / skipped / quarantined totals) wired into CI; the ten `tests/unit` failures (cheval-alias-regression A1–A6, cost-report CR-7 `--reprice`, c114-FR1-2/-3, c124-1.3-5): a fix counts as local only when it touches test files or the function under test and changes no shipped behaviour — the implementer lists each decision for the lead's judgment in Task 1.7; at most four quarantined, each with owner, expiry, bead and reason; `.gitattributes` `linguist-generated -diff` for `evals/fixtures/review-prs/pr-*/**` and `grimoires/loa/reports/ablation-2.0/*-grades/**` (markdown at the fixture root stays reviewable; workflows rule untouched; `gitattributes-workflow-protection` green); `tools/check-no-swallowed-jq.sh` prunes the fixture trees; `tests/unit/lint-walk-excludes-fixtures.bats` plants a known violation under a temp copy of `pr-99/` and asserts every lint walk reports zero; beads bd-yroj0, bd-tgn04, bd-dt5r8 → **[G-6]** · kind: mechanical
- [ ] Task 1.7: Sprint close (lead) — apply the four patches in the order A (1.1 then 1.2), B, C, D; checksums and REPO-MAP regenerated under the zone marker; CHANGELOG `[Unreleased]` entries per fix with the revert path; DEC rows from every implementer's "Judgment calls" section (incl. the ten repair-vs-quarantine decisions); beads closed with the commit and test named; `tests/unit`, bats, vitest green; the draft PR opened from the cycle branch (ICE) so CI runs; the running spend line; `/review-sprint`, `/audit-sprint` → **[G-1]** · kind: judgment
- [ ] Task 1.E2E: End-to-End Goal Validation — G-2 (the 2,000-file fixture review and the verdict equality in vitest), G-3 (the reachable-tag bats case), G-6 (the draft PR's check-runs show the analysis pytest green and `tests/unit` green); evidence paths named in the sprint report · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| The 2,000-file fixture through the real `truncateFiles` with a mocked `gh` | an unbounded fetch; a patch retained for an excluded file | GitHub-side truncation shapes the mock does not model | KF-054 |
| PR #1289 round bodies replayed | a verdict parser that reads UNKNOWN on a valid block; a guard that accepts tool markup | writer outputs of a shape not yet seen | KF-055 |
| A bare remote with `main` moved between generate and publish | a tag on an unreachable commit; a push over a moved `main` | GitHub branch-protection semantics (checked at the real rc.8 publish) | rc.6, rc.7 |
| A fixture repo with a planted credential-shaped string in a record path | a record build that commits a secret | a secret in a shape the scanner does not know | record stages 1–2 |

### Dependencies
- None external; the Bridgebuilder `node_modules` installed (`npm ci`); `npx --no-install bats`

### Security Considerations
- The writer role runs with tools disabled and its output is validated before posting; the record build's credential-shaped hits cannot be bypassed; every System Zone write carries the zone marker

### Risks & Mitigation
- Risk: `dist/` drift between source and the committed build → rebuild in the same commit; `check-bb-dist-fresh` is a gate
- Risk: a `tests/unit` repair changes shipped behaviour → quarantine with expiry instead (D-9), bead filed
- Risk: dissent voices time out on the Bridgebuilder diff → code-only diff per implementer; ≤ 3 runs

### Success Metrics
- The four patches land; vitest, bats, `tests/unit` and the analysis pytest green locally and in CI; review and audit APPROVED; 12 beads closed with evidence (Appendix E)

---

## Sprint 2: Harness and reproduction hardening (global 273)

**Duration:** 1.5 days
**Dates:** 2026-10-25 – 2026-10-26

### Sprint Goal
A harness whose cap cannot read zero, whose batches survive a reboot, whose sandboxes cannot reach the upstream repository, whose grader knows two more benign shapes, and reproduction tooling that attests the tree it runs; pinned as the next pipeline version.

### Deliverables
- [ ] C-6 `lib/session-exec.sh` fail-closed (`ERR` sentinel, metering completeness, `/proc/self/fd` closing, secrecy assertion), sourced by `pipeline-run.sh`, bats harness stages the lib → **[G-8]**
- [ ] C-7 `reproduce.sh` worktree attestation + exit table + live gating; `record_lite.py`, `judge_defects.py`, drivers, synth fixtures, `spend.sh` → **[G-1]**
- [ ] C-8 grader 1.4 shapes; `refusal_policy` suite key and row fields → **[G-8]**
- [ ] C-9 `run-ablation.sh --supervised`, `lib/batch-supervisor.sh`, `lib/egress-proxy.sh`, proxy sidecar image, `egress` suite key, `loa-ablation:259` → **[G-8]**
- [ ] The pipeline version pinned: the Sprint 2 head recorded in `evals/harness/README.md` with the image digest and the self-check log → **[G-8]**

### Acceptance Criteria
- [ ] PRD FR-6 AC 1–3 (sentinel on every listed condition; descriptors above 65535 and above a lowered soft limit closed; secrecy assertion; one copy of the mechanics; swallowed-jq scan covers the lib)
- [ ] PRD FR-7 AC 1–2 (pytest/bats per item; the cycle-132 record untouched; version note)
- [ ] PRD FR-8 AC 1–2 (shapes re-graded benign, every other fixture identical; policy recorded before execution with the row fields)
- [ ] PRD FR-9 AC 1–2 (supervisor bats incl. lock, orphan reconciliation, atomic rows; container bats or dated quarantine; denied connects logged; image 259 pinned)
- [ ] Review APPROVED, audit APPROVED, ≤ 3 dissent runs

### Technical Tasks

- [ ] Task 2.1: Session library (A, lands first; C and D rebase on it) — `lib/session-exec.sh` per sdd.md C-6: `price_for`/`price_events` print `ERR` and return non-zero on parse failure, unknown model, null/negative/non-finite price, invalid token count, usage-less completed turn; zero prices pass; metering rules (streaming, cached, interrupted, retries; `unmetered_attempt` rows); `assert_secret_keys` with the documented `SECRET_KEY_PATTERN` and `NON_SECRET_ALLOWLIST`; `ENV_SHIM` enumerates `/proc/self/fd` with `LOA_KEEP_FDS`, fallbacks for `/proc` absent and an infinite hard limit; `blind-session.sh` refuses to launch on `ERR`; `pipeline-run.sh` sources the lib by literal relative path and stops a phase as `infrastructure_error metering_incomplete`; its bats harness stages `lib/`; the drift test stays until Task 3.6; `check-no-swallowed-jq.sh` covers `evals/harness/lib/`; bats for each sentinel condition, the fd cases (a descriptor above 65535 inherited by a subprocess) and the assertion; beads bd-wqaj4, bd-g2c5i → **[G-8]** · kind: mechanical
- [ ] Task 2.2: Reproduction and analysis hardening (B) — `reproduce.sh` (`pinned_trees_identical_to_worktree` over harness, suites, fixtures, tasks, analysis; porcelain clean; `git describe --dirty`; exit table 0/1/2/3; `--live-sample` requires rc 0 and a match, `$REG` hash, valid-row range, environment verdicts in the live table; `--no-env-check` never asserts a match); `record_lite.py` (`sha256_file(verify=True)` bypasses the cache on verification paths; `safe_rel` on symlink targets; REPRODUCE.md names `INDEX.json`/`INDEX-only.json`); `judge_defects.py` (`sample_id` in packets and labels, `--force` for an existing key, `aggregate` rejects mismatch and loads grades; `run-judge-defects.sh` chunk dir by key sha); `final.sh`/`run-judge-defects.sh` whitelist parse of `registration.txt`, root from `BASH_SOURCE`; power-mini fixtures from `synth.py --seed 20261023` in a pytest fixture after a test asserts the generator reproduces the committed 4.5 K lines byte-identically in the CI Python, then the committed lines removed (the assertion stays); `spend.sh` anonymous-row dedup by `(run_id, batch)`; the new `REPRODUCE.md` states that cycle-132 reproduction runs from a worktree at `fbd36a0c`; pytest per item; the cycle-132 record untouched; beads bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm, bd-um8ol → **[G-1]** · kind: mechanical
- [ ] Task 2.3: Grader 1.4 and refusal policy (C, lands after 2.1; D rebases its `run-ablation.sh` changes on this) — `ablation-grade.sh` 1.4: class-7 exemption for a heredoc-written report whose quoted token is PR-native; `outside_path` exemption for the container-mode bare `/home` probe; per-class fixtures; every other 1.3.8 fixture grades identically (regression run over the fixture set); suite key `refusal_policy: exclude | keep | rerun-once` (default `exclude`), `run-ablation.sh` writes `refusal_policy_applied` and `attempt`, implements `rerun-once` with immutable attempt records under the same cap and the final-row selection rule of sdd.md C-8, per-arm `refusal_rate`; tests: second refusal, infrastructure failure on retry, resume after the first attempt; `ablation-row.sh` denominator rule; `evals/harness/README.md` § Refusal policy; beads bd-kddde, bd-r9abp → **[G-8]** · kind: mechanical
- [ ] Task 2.4: Supervisor and egress (D, lands last in Sprint 2, rebased on 2.1 and 2.3) — `run-ablation.sh --supervised [--max-retries N]` per sdd.md C-9 (linger precondition; systemd-run --user unit when available, else `lib/batch-supervisor.sh` setsid loop; `flock supervisor.lock` held across daemonisation; durable identity — boot id, start time, attempt id, provider request ids; hang detection at 30 min without a STATUS update; retryable vs non-retryable classes; owned process group terminated and `loa-abl-<run_id>-*` containers stopped before resume; run arguments persisted for reboot restoration; STATUS.json `supervisor` entries); `lib/egress-proxy.sh up|down|self-check` (internal network `loa-egress-<batch>`, `Dockerfile.proxy` tinyproxy 1.11 on the internal and an external network, allowlist generated from a new `egress_hosts[]` per provider in `model-config.yaml`, resolved-address validation denying private/loopback/link-local/metadata ranges and the host gateway, CONNECT restricted to 443, redirect re-validation, denial attribution by source address into `<run>/meta/egress-denied.jsonl`; `self-check` = a connectivity or auth-only probe per planned model without completion tokens plus the denial cases); `pipeline-run.sh`/`blind-session.sh` join a per-container guard namespace on the network (`egress-proxy.sh guard`; the guard, not the sandbox, carries `--dns 0.0.0.1` and the netfilter — amended by the s3-e KF-058 fix in Sprint 274) and export `HTTPS_PROXY/HTTP_PROXY`, `NO_PROXY=`, recording the container address in meta; suite key `egress: blocked | bridge` per arm (default blocked) in MANIFEST and meta; `Dockerfile.ablation` → `loa-ablation:259` with the Claude Code version pinned and recorded; bats: supervisor cases (resume once with retry id, second owner refused, orphan reconciled, crash during result write leaves no duplicate row, reboot with PID reuse, cancellation mid-request, retry cap); container egress bats (allowlisted endpoint succeeds; github.com, raw.githubusercontent.com, gitlab.com, a direct IP, IPv6, a redirect to a non-allowlisted host, CONNECT to a non-allowlisted host or port, external DNS, host-gateway access, DNS rebinding, a misconfigured proxy all fail) — a release gate: run in the Docker-enabled CI job, else by the lead on this host with the bats output and the denial log attached as Sprint 2 E2E evidence; never a quarantine row; beads bd-yvjew, bd-ijxuk → **[G-8]** · kind: mechanical
- [ ] Task 2.5: Intermediate pipeline version (lead) — after 2.1–2.4 land: build `loa-ablation:259`, run the egress suite and the image self-check (tools and connectivity probes only, no completion tokens) to `grimoires/loa/reports/ablation-2.0/self-check-c133.txt`, record the commit after this task (its tree hash; later docs-only commits do not invalidate it), the image digest and the Claude Code version in `evals/harness/README.md` § Pipeline versions as the intermediate version; DEC row → **[G-8]** · kind: judgment
- [ ] Task 2.6: Sprint close (lead) — patches applied; CHANGELOG entries with revert paths; DEC rows; beads closed with evidence; bats/pytest green; `/review-sprint`, `/audit-sprint` · kind: judgment
- [ ] Task 2.E2E: End-to-End Goal Validation — G-8 parts (pricing sentinel bats, descriptor bats, egress denial bats or quarantine row, supervisor bats, grader 1.4 fixtures, policy row fields) and G-1 (bead closures) with evidence paths · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| A prices JSON lacking the session's model id | a free-reading cap | a provider that bills a unit the table does not know | DISS F-001 (PR #1289) |
| A killed driver under the supervisor | a batch that stays dead; a duplicate row | a kernel crash mid-write on the host filesystem | KF-052 |
| `git ls-remote github.com` from inside the sandbox | repository egress | a covert channel through the allowlisted endpoints | bd-ijxuk (nine bare sessions) |
| `reproduce.sh` in a dirty worktree | a false "identical to the pin" | a dirty path outside the compared set | cycle-132 audit DO-001 |

### Dependencies
- Sprint 1 landed on the cycle branch (CI gates and the quarantine mechanism run on the draft PR); Docker 26.1.5 on the host; `systemd-run --user` with linger available (fallback otherwise); landing order 2.1 → 2.2 → 2.3 → 2.4 (2.3 and 2.4 both touch `run-ablation.sh`; 2.1 and 2.4 both touch `pipeline-run.sh` and `blind-session.sh`)

### Security Considerations
- Egress default-deny with logged denials; metering fails closed; the secrecy assertion refuses a new key-shaped pass-through; no change to the cycle-132 record

### Risks & Mitigation
- Risk: the proxy allowlist misses a fallback endpoint → generated from the registry; `self-check` requests each planned model before a batch
- Risk: `systemd-run --user` unavailable on CI runners → the watchdog fallback is the tested path there
- Risk: grader 1.4 changes a cycle-132 grade → the regression run over every 1.3.8 fixture must be identical except the two named shapes

### Success Metrics
- bats and pytest green; the intermediate pipeline version recorded; 13 beads closed with evidence (Appendix E); review and audit APPROVED

---

## Sprint 3: The product (global 274)

**Duration:** 1.5 days
**Dates:** 2026-10-27 – 2026-10-28

### Sprint Goal
Loa reviews Loa without reading its own installed files; every gate's findings carry a failure scenario a judge can grade; a corpus can be seeded from outside Loa's history.

### Deliverables
- [ ] Task 3.0 spike record: the Claude Code scope facts in the image with a canary per surface item; the design confirmed, or the run HALTED for the operator's decision on fallback (c) → **[G-4]**
- [ ] C-10 mount mode `home-scope`, `check_mount_closed` clause (e), `took-effect.sh` clauses (f) `pr_bytes_read` and (g) no project execution, grader negative control, the measurement pin recorded, the smoke grade → **[G-4]**
- [ ] C-11 `finding.schema.json` v1, the `Failure:` clause grammar in the review/audit templates and `verdict-derive.sh`, Bridgebuilder and dissent schema references with aliases, grader 1.5 `--judge-verdicts`, `reads-c132.py --judge-defects` under registration v2 → **[G-5]**
- [ ] C-12 `lib/corpus-seed.sh`, `seed-corpus-from-external.sh` with three dry-runs, registration v2 `looks_seen`, measurement-cycle guidance → **[G-8]**
- [ ] Harness README and evals index complete (not gated on the smoke); the session-library drift test removed only after a green smoke (else it stays and a bead is filed)

### Acceptance Criteria
- [ ] PRD FR-10 AC 1–4 (positive-evidence clause (f) and negative control with distinct PR and pinned bytes; the smoke at the measurement pin within the USD 40 share with the launch rule; design-neutral bats incl. executing SKILL.md, hook, script, deletion, rename, symlink, `.mcp.json`, root `CLAUDE.md`, rules, output styles, plugins, and clause (g) proving no planted item loaded or executed; docs). A failed smoke leaves G-4 incomplete and defers FR-10 with a DEC row.
- [ ] PRD FR-11 AC 1–4 (four validators refuse missing/boilerplate/conflicting/outside-repo findings and normalise aliases with the warning; judged recall and unjudged count; stale verdicts rejected; grader 1.5; cycle-132 chain still verifies; templates and persona carry the field)
- [ ] PRD FR-12 AC 1–2 (three dry-runs pass `--check`, no model call; refusals for symlink, submodule, oversize, licence, leakage; `looks_seen` verifier cases; v1 chain verifies)
- [ ] Review APPROVED, audit APPROVED, ≤ 3 dissent runs

### Technical Tasks

- [ ] Task 3.0: Spike — Claude Code scope facts (lead, first) — in `loa-ablation:259` inside the egress block with `--max-usd 2`: a `claude -p` run with the HOME-scope layout (`$HOME/.claude/{CLAUDE.md,settings.json,skills/,hooks/,rules/}`, settings restricted to the user scope by the flag the docs name) and a planted canary for every surface item (hook, skill, command, agent, settings, `.mcp.json`, root `CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, a `.claude/rules/` file, an `@` import, an output style, a plugin, a `.claude/scripts/` file at the root), each with a deterministic filesystem effect, under process-execution capture (hook log, one-second `ps` sampler); the record names the image digest, Claude Code version, scope flags, effective settings and framework content hashes, and every denied connect (the allowlist gaps for Claude Code's non-model endpoints surface here); evidence: the pinned skill loaded, no canary loaded or executed; outcome → confirm D-3.1 with a DEC row, or **HALT the run with the spike record for the operator's decision on fallback (c)** (D-3.6); the assertions are repeated if any recorded input changes before the smoke; record in `grimoires/loa/a2a/sprint-274/spike-scope.md` → **[G-4]** · kind: judgment
- [ ] Task 3.1: Loa reviews Loa (A; the spike-invariant parts — clause (e), clause (f) parser and `pr_bytes_read`, clause (g), the negative-control fixture with distinct PR and pinned bytes, bats scaffolding — start while the spike runs; the mount mode lands after the spike confirms) — `lib/sandbox-mount.sh` mount mode `home-scope` per sdd.md C-10 (pinned framework materialised under the sandbox HOME with absolute-path imports, hook commands and framework `.claude/` references resolved through one root variable; the workspace root overlaid with the PR's changed paths except the executable and prompt surface derived from the pinned Claude Code version — skills, commands, agents, hooks, settings, `*.local.*`, rules, `.claude/CLAUDE.md`, root `CLAUDE.md`/`CLAUDE.local.md`, `.mcp.json`, output-styles, plugins, `@` imports — removed from the root and kept under `pr/head/`), `pipeline-run.sh` launch flags for the user scope, `check_mount_closed` clause (e), `took-effect.sh` clauses (f) (versioned transcript parser, gutter stripped, ≥ 60 % line coverage, Grep never counts, every cited changed `.claude/` file read) and (g); grader negative control (the cycle-132 mount still fires); design-neutral bats per PRD FR-10 AC 3; harness README § Mount modes → **[G-4]** · kind: mechanical
- [ ] Task 3.2: One finding contract and grader 1.5 (B; depends on Task 3.3's `registration.py` v2 for the chain version) — `.claude/schemas/finding.schema.json` v1 per sdd.md C-11 (fields, `blocking`, confidence normalisation, id derivation, path and anchor rules, content rule and denylist, exemptions for PRAISE/INFO/REFRAME/SPECULATION) with conformance vectors under `.claude/schemas/finding.vectors/{valid,invalid}/` run by the zod, jq and python validators; `verdict-derive.sh`: the `Failure:` clause grammar (dash variants, last-token disambiguation), a defect bullet without a valid clause is a violation, **a CRITICAL/HIGH/blocking bullet without a valid clause still counts as blocking and the gate reports a non-approving outcome with a non-zero exit** (red tests: only invalid blockers; valid lows mixed with an invalid blocker; one malformed CRITICAL never yields APPROVE); `reviewing-code` and `auditing-security` templates emit the clause; Bridgebuilder persona asks for it, `FindingsBlockSchema` references the canonical schema, `npm run build`, `dist/` committed, `check-bb-dist-fresh`; `adversarial-finding.schema.json` + `adversarial-review.sh` normalise aliases with the named warning (removal 2.1.0), reject both-present-and-different; `ablation-grade.sh` 1.5 `--judge-verdicts` (JSONL schema with `judge_prompt_sha256` and `supersedes`, one-to-one binding by `(run_id, finding_id, defect_key)`, duplicate refused without `supersedes`, `blind: false` in a separate column, stale hash/version rejection, `recall_judged`, `judged_pairs`, `unjudged_pairs`, provenance in grade.json) with a regression run asserting every 1.4 fixture grades identically except the judge cases; `reads-c132.py --judge-defects` as a registered read under the v2 chain; tests: the cycle-132 chain and reads verify unchanged; bats + vitest + pytest → **[G-5]** · kind: mechanical
- [ ] Task 3.3: External corpus seeding, registration v2 and guidance (C; lands before 3.2 consumes registration v2) — extract `lib/corpus-seed.sh` from `seed-corpus-from-record.sh` (byte-identical outputs on the existing fixtures, asserted); `seed-corpus-from-external.sh` per sdd.md C-12 (https-only sanitised URLs, PR base/head verified against the clone, `base/` = `fix^`, limits checked from tree metadata before any blob fetch, blobless clone, `git archive` materialisation, symlink/submodule/non-regular refusal, PR.md from title and body with the substantive-overlap leakage test, the C-4 secret scanner over the materialised trees, licence via the GitHub license API against the SPDX allowlist with LICENSE/NOTICE and an attribution row on `--commit-trees`, `--dry-run`, `--check`; exit codes per sdd.md §5.4); three public candidates dry-run (criteria: post-cutoff fix, documented defect, size bounds, harness language) with the results in `evals/fixtures/external-candidates.md` (outside the `-diff` path) and the cost ledger showing no model call; `registration.py` v2 optional `looks_seen` (ordering and integrity rules) validated against the committed looks inventory, v1 verifies; `evals/harness/README.md` § Shipping a measurement cycle and the planning-sprints reference pointer; bead bd-y1smc → **[G-8]** · kind: mechanical
- [ ] Task 3.4: Harness documentation (D, not gated on the smoke) — `evals/harness/README.md` complete (mount modes, egress threat model and supervisor, refusal policy and denominators, pipeline version table, exit codes per sdd.md §5.4); `evals/README.md` index; CHANGELOG entries → **[G-8]** · kind: mechanical
- [ ] Task 3.5: Measurement pin and the smoke (lead with A) — after 3.1–3.3 land: the integrated self-check (grader 1.5, registration v2, the four validators, the mount mode, the seeding lib) passes on the image; the egress suite passes on the actual image and network (the hard precondition); the commit after this step is recorded as the measurement pin (tree hash, image digest, Claude Code version) in the README and in a DEC row; then the smoke: one `a1_full` trial on pr-20 (pr-16 if pr-20's changed files exceed the overlay's tested range) at that pin, `--max-usd` within the USD 40 share, meta recording framework commit, harness tree, fixture SHA256SUMS, image digest, Claude Code version, scope flags and effective settings; pass criteria per sdd.md §7.3; a launch is a session that reached the model (spend > USD 0.50); a failed smoke leaves G-4 incomplete — one verification rerun after a fix within the share, else FR-10 is deferred with a DEC row → **[G-4]** · kind: judgment
- [ ] Task 3.6: Drift-test removal (D, only after a green smoke) — delete the session-library drift test and its fixture in a versioned commit; if the smoke did not pass, the test stays and a bead is filed → **[G-8]** · kind: mechanical
- [ ] Task 3.7: Sprint close (lead) — patches applied in the order C (3.3) → B (3.2) → A (3.1) → D (3.4, 3.6); the spend recorded against the USD 40 share with the running line; DEC rows (incl. the Task 3.0 outcome and the pin); beads closed; `/review-sprint`, `/audit-sprint` · kind: judgment
- [ ] Task 3.E2E: End-to-End Goal Validation — G-4 (the smoke's `grade.json` and the negative control), G-5 (the four validators' refusal fixtures), G-8 parts (three dry-runs, `looks_seen` cases) with evidence paths · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| A planted project-scope hook under the HOME-scope mount | PR code executing in the reviewing session | a Claude Code version that changes scope rules after the pin | PREREGISTRATION addendum 9 |
| The negative-control fixture (cycle-132 mount) through clause (f) and the grader | a detector that went silent for the wrong reason | — | cycle-132 oracle exposures |
| A finding with a one-word `Failure:` clause through all four validators | a gate that tallies a scenario-less finding | a plausible but wrong scenario (the judge's job) | cycle-132 judge read |
| An external repository with a symlink and a submodule | code execution or escape during seeding | a licence misdeclared upstream | seed-corpus-from-record.sh |

### Dependencies
- Sprint 2 intermediate version recorded; Docker image 259; the egress suite green on it; model credentials for the spike and the smoke (operator environment); landing order 3.3 → 3.2 → 3.1 → 3.4/3.6 (3.2 and 3.3 both touch `registration.py`: v2 lives in 3.3); the measurement pin is the commit recorded by Task 3.5

### Security Considerations
- PR-supplied `.claude/` content is data only (the spike proves it before the mount lands); the smoke runs under the egress block; no change to the cycle-132 record

### Risks & Mitigation
- Risk: the spike shows project-scope items still load → the run HALTS with the spike record; fallback (c) is the operator's decision (D-3.6); nothing else in Sprint 3 depends on the mount mode and continues
- Risk: the smoke exposes the oracle for a path class the overlay missed → the detector names the path; fix the overlay; one verification rerun within the USD 40 share; if that fails too, G-4 stays incomplete and FR-10 is deferred with a DEC row — never claimed
- Risk: alias normalisation breaks an existing dissent envelope → aliases accepted with a warning for one release; replay of cycle-132 envelopes in tests

### Success Metrics
- The smoke grade at the recorded measurement pin: `oracle_exposed_defects` 0, `pr_bytes_read` covering every cited changed file, clause (g) clean; four validators agree on the vectors; three dry-runs pass; 1 bead closed (Appendix E); review and audit APPROVED

---

## Sprint 4 (Final): Hygiene and ship (global 275)

**Duration:** 1 day
**Dates:** 2026-10-29

### Sprint Goal
A tracker that tells the truth and a release candidate on a commit `main` can reach, shipped through the gates this cycle fixed.

### Deliverables
- [ ] C-13 the frozen inventory, seven Explore batch manifests, applied closures and labels, the 10 % re-verification, the five-category table → **[G-7]**
- [ ] C-14 CHANGELOG `## [2.0.0-rc.8]`, release notes, version stamps, README pin; PR; Bridgebuilder (cycle-branch build) round(s) triaged; CI green; admin merge; `record-branch.sh` stage; rc.8 published through the fixed path; archive → **[G-3]**

### Acceptance Criteria
- [ ] PRD FR-13 AC 1–2 (the manifests form a complete partition of the frozen inventory; categories sum; opened-during-cycle listed; the sample is verified before any closure applies and a disagreement re-sweeps the batch)
- [ ] PRD FR-14 AC 1–2 (rc.8 pre-release with notes and `main` contains the tag; record branch by `record-branch.sh`; archive directory with the merged CHANGELOG section and README)
- [ ] PRD G-2 (the cycle's own PR reviewed by the Bridgebuilder built on the cycle branch with no `degraded_reason`, summary verdict equal to the consensus block's; if the PR's shape degrades the review, the PR is split per the FR-12 guidance before G-2 is read)
- [ ] Review APPROVED, audit APPROVED before the admin merge (Task 4.4; the sweep report, the release metadata and any Bridgebuilder-triggered fix are the sprint's code), ≤ 3 dissent runs

### Technical Tasks

- [ ] Task 4.1: Sweep inventory and batches (lead + Explore) — the lead decides the batch boundaries and judges each returned row's evidence before it counts; `sweep-inventory.sh` freezes the open beads (minus Tier 1) to `a2a/sprint-275/sweep/inventory.jsonl` with its sha256; Explore subagents (read-only, ≤ 40 beads each; as many batches as the inventory needs) verify each bead against the code and return `manifest-<k>.jsonl` rows `{id, category ∈ {closed-implemented, closed-obsolete, kept, pulled-in}, evidence, confidence}`; `sweep-apply.sh --validate` checks the manifests form a complete partition (duplicate, missing, unknown or conflicting ids rejected) and that every closure's evidence resolves (commit sha, PR number, or a path at head) → **[G-7]** · kind: judgment
- [ ] Task 4.2: Sample, apply, report (lead) — `sweep-sample.sh` (seed 20261023, `ceil(10 %)` of the proposed closures) re-verified by a second Explore BEFORE anything is applied; a disagreement sends that batch back for a re-sweep; then the lead triages every closure row (accept, demote to kept, or send back) and `sweep-apply.sh` closes with `--reason` naming the evidence, labels `backlog-2026-10` with the status line and review-by date, pulls in by the rule, writing the append-only `applied.jsonl` (every mutation reversible with `br reopen`); the five-category table (incl. opened-during-cycle) and the sample result in the sprint report → **[G-7]** · kind: judgment
- [ ] Task 4.3: Release metadata (lead) — CHANGELOG `[Unreleased]` → `## [2.0.0-rc.8] — <date> — The follow-through (release candidate)` with a fresh `[Unreleased]`; `grimoires/loa/reports/release-notes-2.0.0-rc.8.md` (what shipped, the revert paths, the deferred Should Haves and any deferred FR-10); `update-loa-bump-version.sh --target 2.0.0-rc.8` under the zone marker; checksums; README version, badge and install pin; any fix landed afterwards is appended to the rc.8 section and the notes and the stamps and checksums re-verified → **[G-3]** · kind: mechanical
- [ ] Task 4.4: Sprint close (lead) — the sweep report, the release metadata and any pending fix are the sprint's code: `/review-sprint`, `/audit-sprint` (≤ 3 dissent runs); DEC rows; beads closed; the running spend line per share; nothing merges before both are APPROVED · kind: judgment
- [ ] Task 4.5: Ship (lead) — the lead triages the Bridgebuilder findings, decides the merge and judges the publish preconditions; the draft PR from Sprint 1 marked ready (body from the sprint reports); Bridgebuilder round(s) with the skill built on the cycle branch, triaged (a fix touching the harness re-runs the relevant bats; plateau rule: stop after a round adding no new HIGH or MEDIUM, at most three rounds within USD 20; a HIGH → fix, re-review, re-audit before the merge); required checks enumerated and every result bound to the final head sha — any later patch invalidates the evidence and the checks re-run; admin merge (merge commit); `record-branch.sh --cycle 133 --head <merge> --prev <cycle-132 record> --stage "stage 1"` + ICE push; branch-protection preflight recorded; post-merge candidate v2 → publish through C-3 (ancestry re-verified against freshly fetched remote `main`; remote tag target and pre-release metadata verified after) → `git branch --contains v2.0.0-rc.8` lists `main`; a deferred ledger commit has an owner (the lead) and a bead; if the v2 publish path fails irrecoverably, `--allow-v1` with a logged reason, a bead and a DEC row (the tag-on-merge requirement still holds); `archive-cycle.sh --cycle 133 --retention 50` (archive README by hand as cycles 131/132); beads closed; run state JACKED_OUT; NOTES and memory → **[G-3]** · kind: judgment
- [ ] Task 4.E2E: End-to-End Goal Validation — G-1 (every Tier 1 bead closed with commit and test), G-7 (the table and the sample), G-3 (the tag reachable from freshly fetched `main`; remote tag and pre-release verified), G-2 (the PR's non-degraded Bridgebuilder verdict); evidence paths named · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| The 10 % re-verification sample | a batch of false closures | a false closure outside the sample | beads-compliance lesson |
| The cycle PR through the cycle-branch Bridgebuilder | a regression in C-1/C-2 on a real PR | — | KF-054, KF-055 |
| `git branch --contains v2.0.0-rc.8` | an unreachable tag | — | rc.6, rc.7 |

### Dependencies
- Sprints 1–3 landed on the cycle branch; Task 4.4 (review and audit) before Task 4.5; the operator token for the admin merge and the publish; `gh` authenticated

### Security Considerations
- The refusal list (PRD § Authorization basis) binds every git and GitHub action; the record build's secret scan; no publish of a non-rc

### Risks & Mitigation
- Risk: the Bridgebuilder round finds a HIGH in the cycle's own changes → fix cycle on the cycle branch, re-review, re-audit; the PR waits
- Risk: `--force-with-lease` push refused by branch protection → the preflight predicts it; the deferral path leaves the tag valid, the lead owns the deferred ledger commit with a bead
- Risk: the v2 publish path fails on its first real exercise → `--allow-v1` with a logged reason, a bead and a DEC row; the tag still lands on the merge
- Risk: Sprint 4's day ends before publish → dates are targets; the gates are not; the cycle runs longer
- Risk: the sweep sample disagrees → re-sweep the batch before applying

### Success Metrics
- rc.8 published and reachable from freshly fetched `main`; the sweep table published with the sample verified first; every Tier 1 bead closed (Appendix E: 26); review and audit APPROVED before the merge

---

## Risk Register

| Risk | Sprint | Likelihood | Impact | Mitigation |
|------|--------|-----------|--------|------------|
| Scope facts do not support design (a′) | 3 | Medium | High | spike first; fallback (c); DEC amended |
| Branch protection refuses the ledger fast-forward | 4 | Low | Medium | deferral path; tag on the merge is always valid |
| Proxy allowlist incomplete | 2 | Medium | High | registry-generated; self-check per model before a batch |
| `dist/` drift | 1 | Medium | Medium | rebuild in the same commit; CI gate |
| Unit-test repairs change shipped behaviour | 1 | Medium | Medium | quarantine with expiry (D-9) |
| Sweep false closures | 4 | Medium | Medium | evidence rule; manifest review; 10 % sample |
| Dissent voice budget (KF-004) | all | High | Low | code-only diffs; ≤ 3 runs |
| Smoke spend over its share | 3 | Low | Low | one launch; `--max-usd 30` |

> Sources: prd.md § Risks & Mitigation; sdd.md §9

---

## Success Metrics Summary

| Goal | Sprint | Evidence |
|------|--------|----------|
| G-1 every Tier 1 bead closed with evidence | 1–4 | `br show` per bead; sprint reports |
| G-2 Bridgebuilder reviews a large PR; verdict trustworthy | 1, 4 | vitest fixtures; the cycle PR's round |
| G-3 tag reachable from `main` | 1, 4 | bats; `git branch --contains v2.0.0-rc.8` |
| G-4 Loa reviews Loa | 3 | the smoke's grade; clause (f); negative control |
| G-5 one finding contract at four gates | 3 | validator fixtures |
| G-6 green suites in CI | 1 | check-runs on the cycle PR |
| G-7 truthful tracker | 4 | the five-category table |
| G-8 shippable harness | 2, 3 | bats; dry-runs; pipeline version table |

> Sources: prd.md § Goals & Success Metrics

---

## Dependencies Map

Sprint 1 (land A 1.1 → 1.2, B, C, D; draft PR opened) → Sprint 2 (2.1 → 2.2 → 2.3 → 2.4 → 2.5 intermediate version; egress suite green) → Sprint 3 (3.0 spike first with 3.1's invariant parts in parallel; 3.3 → 3.2 → 3.1 mount mode → 3.4; 3.5 pin + smoke; 3.6 after a green smoke) → Sprint 4 (4.1 → 4.2 → 4.3 → 4.4 review and audit → 4.5 ship).

> Sources: sdd.md §8

---

## Appendix

### A. PRD Feature Mapping
| PRD Feature (FR-X) | Sprint (Tasks) | Status |
|--------------------|----------------|--------|
| FR-1 Bridgebuilder large PRs | 1 (1.1) | Planned |
| FR-2 consensus integrity | 1 (1.2) | Planned |
| FR-3 release tag reaches main | 1 (1.3); 4 (4.4) | Planned |
| FR-4 framework ergonomics | 1 (1.4, 1.5) | Planned |
| FR-5 CI and test health | 1 (1.6) | Planned |
| FR-6 session library | 2 (2.1); 3 (3.6) | Planned |
| FR-7 reproduction and analysis | 2 (2.2) | Planned |
| FR-8 grader 1.4 and refusal policy | 2 (2.3) | Planned |
| FR-9 batch operations | 2 (2.4, 2.5) | Planned |
| FR-10 Loa reviews Loa | 3 (3.0, 3.1, 3.5) | Planned |
| FR-11 finding contract and judge hook | 3 (3.2) | Planned |
| FR-12 external seeding and guidance | 3 (3.3) | Planned |
| FR-13 beads hygiene | 4 (4.1, 4.2) | Planned |
| FR-14 release and ship | 4 (4.3, 4.4, 4.5) | Planned |

### B. SDD Component Mapping
| Component | Sprint (Tasks) |
|-----------|----------------|
| C-1, C-2 Bridgebuilder | 1 (1.1, 1.2) |
| C-3 release publish | 1 (1.3) |
| C-4 framework ergonomics | 1 (1.4, 1.5) |
| C-5 CI and quarantine | 1 (1.6) |
| C-6 session library | 2 (2.1) |
| C-7 reproduction and analysis | 2 (2.2) |
| C-8 grader 1.4, refusal policy | 2 (2.3) |
| C-9 supervisor, egress, image | 2 (2.4, 2.5) |
| C-10 Loa reviews Loa | 3 (3.0, 3.1, 3.5) |
| C-11 finding contract, grader 1.5 | 3 (3.2) |
| C-12 seeder, registration v2, guidance | 3 (3.3) |
| C-13 sweep | 4 (4.1, 4.2) |
| C-14 release | 4 (4.3, 4.4, 4.5) |

### C. PRD Goal Mapping
| Goal | Evidence path |
|------|---------------|
| G-1 | `br show <bead>` close reasons naming commit and test |
| G-2 | `resources/__tests__/paged-fetch.test.ts`, `enrichment-guard.test.ts`; the cycle PR's Bridgebuilder summary JSON |
| G-3 | `tests/unit/post-merge-publication.bats`; `git branch --contains v2.0.0-rc.8` |
| G-4 | the smoke's `grade.json` (`oracle_exposed_defects`, `pr_bytes_read`); `evals/tests/sandbox-mount-home-scope.bats` |
| G-5 | `tests/unit/verdict-derive-failure-clause.bats`; `adversarial-finding` schema tests; BB `schemas.test.ts`; `test_grader_judge_verdicts.py` |
| G-6 | the cycle PR's check-runs |
| G-7 | `a2a/sprint-275/sweep/report.md` |
| G-8 | `evals/tests/session-exec.bats`, `egress-proxy.bats`, `batch-supervisor.bats`, grader 1.4 fixtures, `external-candidates.md` |

### D. Flatline integration (sprint review, `a2a/flatline/cycle-133-sprint-review.json`; D-S.1 DEC-0859)

Run: claude-headless + gpt-5.5, cross-scoring degraded (KF-041, recurrence 11), 18 skeptic blockers, 21 + 28 reviewer items; every one folded.

| Concern | Where it landed |
|---|---|
| SKP-001 (pin contradiction), gpt 01, 13–14, opus 01, 10 | Task 2.5 intermediate version; Task 3.5 measurement pin + integrated self-check; smoke metadata |
| SKP-002 (smoke fix without rerun), gpt 02, opus 04 | Task 3.5 launch rule, one reserved rerun, G-4 incomplete → FR-10 deferred; Spend header |
| SKP-006, gpt 03–04, opus 06 | Spend header: shares 40/20/40, spike inside the smoke share, running line, HALT when exhausted |
| SKP-022, gpt 21 | Task 4.5: required checks bound to the final head sha; ancestry and remote tag verified |
| SKP-008, SKP-009, SKP-010, gpt 05–08, opus 15, 18 | Task 1.3: ancestry re-verified per step, identity-matched existing tag, ledger patch restriction, state-aware rerun, v1 refusal; Task 4.5 fallback and preflight |
| SKP-004, SKP-002b, gpt 09, opus 12–13 | Tasks 2.4, 2.5, 3.0, 3.5: egress suite a hard gate, run locally when CI cannot, spike inside the block |
| SKP-014, SKP-016, gpt 15–16 | Tasks 1.1, 3.2: verdict eligibility per degraded reason; invalid blockers still block; vectors across four validators |
| SKP-017, gpt 10 | Task 2.4: durable identity, reboot lifecycle, retry classes |
| SKP-012, SKP-013 | Task 1.2: every canonical field preserved; adapters prove the stance at invocation |
| SKP-001b (surface), SKP-003, gpt 12–13 | Tasks 3.0, 3.1: surface derived from the pinned version incl. output-styles and plugins; canaries with filesystem effects under process capture; spike inputs recorded |
| SKP-005 | Task 2.4: ports, resolved addresses, DNS, host gateway, rebinding, misconfiguration |
| SKP-011 | Task 1.4: parents asserted public; scan of the differing paths |
| gpt 11, opus 26 | Task 2.3: immutable attempts, final-row rule |
| gpt 17–18, opus 28, 30 | Tasks 4.1, 4.2: complete partition, sample before apply, overflow batches |
| gpt 19, opus 09 | Task 1.6: ISO expiry (commit date + 30 days), full-suite totals |
| gpt 20, opus 05 | Execution header and Dependencies: landing order, one integration owner, same-file tasks sequenced |
| opus 02, 03, 27 | Task 4.4 close before the merge; dissent-exhaustion HALT; plateau rule |
| opus 07 | Appendix E bead map; counts corrected (12 / 13 / 1) |
| opus 08 | Task 1.7: draft PR at Sprint 1 close carries CI |
| opus 11 | Task 3.2: build, dist, grader 1.5 regression |
| opus 14 | Sprint 4 AC G-2: non-degraded review or split the PR |
| opus 16 | Task 3.0: fallback is a HALT, never built autonomously |
| opus 17, 20 | Tasks 3.4/3.6 split; 3.1 invariant parts start during the spike |
| opus 19 | Execution header: dates are targets |
| opus 21–23 | Task 1.6 repair rule; "Judgment calls" section; CHANGELOG after stamping |
| opus 24–25 | Tasks 2.5, 2.2: probe shape; synth reproduction assertion |
| opus 26 | Task 3.3: candidates file outside the `-diff` path |

### E. Tier 1 bead map (26 beads)

| Sprint | Task | Beads |
|---|---|---|
| 1 | 1.1 | bd-ra4im |
| 1 | 1.2 | bd-cpvc6 |
| 1 | 1.3 | bd-kwloh |
| 1 | 1.4 | bd-mgun5 |
| 1 | 1.5 | bd-rz5ks, bd-nbs7w, bd-d7dwt, bd-crzm5, bd-4pjqm |
| 1 | 1.6 | bd-yroj0, bd-tgn04, bd-dt5r8 |
| 2 | 2.1 | bd-wqaj4, bd-g2c5i |
| 2 | 2.2 | bd-jat0z, bd-161zz, bd-ombvn, bd-xr3uq, bd-o3a5h, bd-qxwrm, bd-um8ol |
| 2 | 2.3 | bd-kddde, bd-r9abp |
| 2 | 2.4 | bd-yvjew, bd-ijxuk |
| 3 | 3.3 | bd-y1smc |
| 4 | 4.1, 4.2 | the other open beads (FR-13) |
