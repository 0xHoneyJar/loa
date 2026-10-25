# Software Design Document: Post-ship fixes (cycle-134)

**Version:** 1.2
**Date:** 2026-10-25
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-134, 1.0, FR-1 … FR-10, Appendix A D-1 … D-5 = DEC-0966 … DEC-0970)
**Status:** Draft 1.2 — autonomous run; design-level decisions taken on the operator's behalf are § 11 D-1.1 … D-4.2 (DEC-0971 … DEC-0980), D-3.2a from the Flatline PRD review (DEC-0981) and D-1.1a, D-1.2a, D-2.1a, D-3.2b, D-4.3 from the Flatline SDD review (DEC-0982 … DEC-0986; every blocker and medium item dispositioned in § 11.G).
**Branch:** `feature/cycle-134-post-ship-fixes` from `chore/cycle-133-post-ship c533d760`
**Pins:** the cycle-132 pipeline pin `fbd36a0c` and the cycle-133 pin `7d2119477`, their record branches and recorded evidence are untouched; the harness changes here land as the next pipeline version with tests, not as a re-run.

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 System Overview

Nine local repairs in five areas of an existing system; no new component, no new interface. The areas: the home-scope validator (`evals/harness/took-effect.sh`), the mount transform (`evals/harness/lib/sandbox-mount.sh`), three harness libraries (`evals/harness/lib/egress-proxy.sh` with `Dockerfile.proxy`, `evals/harness/lib/batch-supervisor.sh`, `evals/harness/seed-corpus-from-external.sh`), and the publish path (`.github/workflows/post-merge.yml`, `.claude/scripts/classify-merge-pr.sh`, `.claude/scripts/post-merge-orchestrator.sh`). Each repair keeps the file's existing contract (exit codes § 5.4, evidence-line format, record formats) and adds the missing check or narrows the over-broad one.

> Sources: prd.md § Technical Considerations / Architecture; § 1.4 below

### 1.2 Architectural Pattern

Validators read captures and recompute; drivers write records; a validator never trusts a driver-written record for a fact it can recompute (D-1.3). Guards fail closed with a named reason (D-1.1, D-1.2, D-2.4). Workflow safety has two independent layers (classifier and job guard, D-3.1). Exit codes keep the four-value contract of cycle-133 (§ 5.4).

> Sources: prd.md § Non-Functional Requirements / Security, Reliability; cycle-133 sdd.md § 5.4 (archived)

### 1.3 Component Diagram

```
 pinned framework commit ──git show──► took-effect.sh ◄── transcripts/events-<label>.jsonl (hook_started, init, result, tool_use)
        │                                   ▲  ▲                 meta/ps-<label>.txt, meta/home-integrity.json, meta/arm-evidence.txt
        │                                   │  └── sandbox-mount.sh cmd_hooks → home_hook_counts=<event>[:<matcher>]:<n>
        └── sandbox-mount.sh transform/verify (R1–R8; verify = reverse(copy) == pinned bytes)

 egress-proxy.sh up ──docker run --pids-limit 256──► loa-egress-proxy (Docker 26.1; tinyproxy 1.11 MaxClients 200)
 batch-supervisor.sh ── .jobs/<name>.pgid + <name>.ident ──► reclaim (identity-checked kill_group)
 seed-corpus-from-external.sh ── trees → want (PR files ∪ fix-diff files) → one bounded fetch → head.diff, fix diff

 post-merge.yml: classify (classify-merge-pr.sh: pr_type, pr_number) ──► simple-release [pr_type != cycle && pr_number != '']
                                                                     └─► full-pipeline  [pr_type == cycle && pr_number != '']
 post-merge-orchestrator.sh --publish: validate_candidate_v2 (+ local and remote tag identity → exit 2) → PUBLISHING → phase_tag (re-check; race → 1) → …
```

> Sources: the file:line reads in § 1.4

### 1.4 System Components

| Id | Component | File(s) | Change | PRD |
|---|---|---|---|---|
| C-1 | Hook identity rule | `evals/harness/took-effect.sh:600-640, 1102-1113` | parse `hook_name` as `<event>[:<matcher>]` (the matcher is everything after the first colon); the (event, matcher) group must exist in the pinned user settings read from the HOME copy (groups with the same key merge, counts summed); per group the observed count c = k·n with an integer k ≥ 0 and k ≤ triggers where the trigger count is derivable (§ 11.H); k = 0 passes (D-1.1, D-1.1a); the group evidence is read from `home_hook_groups` (hex ids, § 3.2) with the old `home_hook_counts` grammar accepted as event-level aggregates; confirming the `hook_name` grammar for a matcher-less and a regex group on a real one-turn session is a pre-merge gate (Q-1) | FR-1 |
| C-2 | Transcript completeness rule | `evals/harness/took-effect.sh:590-601, 865-871` | `labels_run` = the non-skipped phases of `meta/pipeline.json`; per label a regular non-symlink non-empty transcript in which every non-empty line parses as a JSON object, exactly one `result` event is the final non-empty line, at least one `system`/`init` precedes it and every event carrying `session_id` shares the init's; any violation fails (g) as `transcript <label>: <reason> (line N)` (D-1.2, D-1.2a) | FR-2 |
| C-3 | Independent integrity cross-check | `evals/harness/took-effect.sh:363-400`; `evals/harness/pipeline-run.sh:552-576` | recompute the pin's manifest digest; bind record and arm_evidence to it and to the entry count; walk a retained HOME when present; evidence names the mode (D-1.3) | FR-4 |
| C-4 | R3/R5 corpus table and narrowing; hook-group evidence emitter | `evals/harness/lib/sandbox-mount.sh:1496, 1503, 1576-1580, 1609-1626, 1707-1731, 1733-1743` | corpus table of every R3/R5 hit by context (§ 11.F); narrowed regexes; verify already covers R5 — recorded as a correction (D-2.1); `cmd_hooks` additionally emits `home_hook_groups` to the § 3.2 grammar (D-2.1a: implementer B owns this file) | FR-5, FR-1 |
| C-5 | Proxy pid limit | `evals/harness/lib/egress-proxy.sh:203-205`; `evals/harness/Dockerfile.proxy:45, 101`; `evals/tests/egress-proxy.bats` | `--pids-limit 256`; documented run line; a pair-pinning test (D-2.2) | FR-6 |
| C-6 | Supervisor job identity | `evals/harness/lib/batch-supervisor.sh:228-260, 400, 449, 512` | `.jobs/<name>.ident` (start_ticks + cmdline sha256); reclaim compares before `kill_group`; identity-less records are stale (D-2.3) | FR-7 |
| C-7 | Seeder fix-diff blobs | `evals/harness/seed-corpus-from-external.sh:400-430, 540-564` | fix-diff paths from trees join the bounded want set; out-of-bounds refuses by name; diff after the fetch (D-2.4) | FR-8 |
| C-8 | Classify guard | `.claude/scripts/classify-merge-pr.sh:86-90, 102-137`; `.github/workflows/post-merge.yml:110, 182`; `tests/unit/classify-merge-pr.bats` | the PR number comes from the subject's trailing `(#NNN)` (GitHub's merge and squash form) validated as a positive decimal, else empty (D-3.2b); empty PR number → `other`; full-pipeline guarded on `pr_number != ''`; tests for both (D-3.1) | FR-3 |
| C-9 | Publish contract | `.claude/scripts/post-merge-orchestrator.sh:44-49, 1062-1110, 1543-1600, 1621-1630, 1896-1920, 2117, 2184` | local and remote tag identity checks in `validate_candidate_v2` (exit 2 pre-write; D-3.2a) using the existing `tag_identity_matches` rule (annotated tag object: object = target, type commit, tag name, subject `Release <tag>`; a lightweight tag never matches → refusal); a failed or timed-out `ls-remote` is `remote unreachable, identity unverified` → exit 2; `phase_tag` re-checks before the push and returns 1 on the race, and a re-run with an identical-identity tag skips the push; `--generate` refuses a non-integer number (no fraction, no exponent, |n| ≤ 2^53−1, −0 refused) with exit 2 and nothing written, and `validate_candidate_v2` enforces the same domain at publish (exit 2); Q-3 resolved (D-3.2, D-3.2b) | FR-9 |
| C-10 | Ship | `record-branch.sh`, `archive-cycle.sh`, the Bridgebuilder, CHANGELOG `[Unreleased]` | one PR for the sprint; non-degraded round; merge; record; archive; no release (DEC-0967) | FR-10 |

> Sources: the file:line reads of 2026-10-25 at branch head `5e7219a3` (files identical to `main 1fc6d150`); prd.md § Functional Requirements

### 1.5 Data Flow

C-1/C-2: `pipeline-run.sh` captures `transcripts/events-<label>.jsonl` and `meta/ps-<label>.txt`; the mount writes `home_hook_counts` into `meta/arm-evidence.txt`; `took-effect.sh` reads all three and the pinned commit. C-3: the driver writes `meta/home-integrity.json` before deleting the HOME; the validator re-derives the manifest digest from the pin. C-7: trees → want set → one fetch → archive bytes → diffs. C-8/C-9: the merge sha → classifier outputs → job guards; the candidate JSON → `validate_candidate_v2` → state PUBLISHING → phases.

> Sources: `evals/harness/pipeline-run.sh:74, 191, 552-576`; `evals/harness/took-effect.sh:590-640`; `.claude/scripts/post-merge-orchestrator.sh:2117-2195`

### 1.6 External Integrations

GitHub Actions (post-merge.yml), the GitHub API through `gh` (classifier enrichment, seeder trees), Docker 26.1 (proxy and sandboxes), the Bridgebuilder on the sprint PR.

> Sources: § 1.4

### 1.7 Deployment Architecture

Framework files ship in the repository; the CI image is the pinned `loa-ablation:259` for harness bats that need a container; the egress bats that assert the pid pair read files only.

> Sources: `evals/harness/README.md` § Pipeline version; prd.md § Technical Considerations / Dependencies

### 1.8 Scalability Strategy

Not applicable beyond C-5 (parallel sandbox capacity: MaxClients 200 with pid headroom).

> Sources: D-2.2

### 1.9 Security Architecture

Fail-closed validators (C-1, C-2, C-3); provenance boundary kept (`GIT_NO_LAZY_FETCH=1`, C-7); no signal to an unverified process group (C-6); the pid limit stays on a NET_ADMIN container (C-5); System Zone writes under the bounded zone marker with `checksums.json` and REPO-MAP regenerated in the same commit (DEC-0824); secret scan before every public push.

> Sources: prd.md § Non-Functional Requirements / Security; DEC-0824

---

## 2. Software Stack

### 2.1 Frontend Technologies

None (command-line tooling and CI).

### 2.2 Backend Technologies

Bash 5.2 with embedded Python 3.12 (`python3 -I`) for the validator, the mount transform and the orchestrator's canonicaliser; jq 1.7; git 2.4x; tinyproxy 1.11 in `Dockerfile.proxy`; GitHub Actions YAML.

### 2.3 Infrastructure & DevOps

`bats-tests.yml` (unit and harness bats, analysis pytest), `post-merge.yml` (candidate preparation), Docker 26.1 on the lead host for the proxy and sandbox bats.

> Sources: `evals/harness/Dockerfile.proxy`; `.github/workflows/bats-tests.yml`; the shebangs and `python3 -I` calls of the files in § 1.4

---

## 3. Database Design

### 3.1 Database Technology

None. Records are JSON and plain-text files under the run directory (`meta/`, `transcripts/`, `.jobs/`) and `.run/` (orchestrator state, progress).

### 3.2 Schema Design

- `meta/arm-evidence.txt`: `home_hook_counts=<event>:<n>,…` stays as it is (event-level aggregate); a new line `home_hook_groups=<event>:<hex12>:<n>;…` lists every pinned group, `hex12` being the first 12 hex digits of the SHA-256 of the group's matcher string (the empty string for a matcher-less group), groups with the same key merged; the grammar has no verbatim matcher text, so colons, commas and regex metacharacters cannot break it. The validator hashes the matcher it parses from `hook_name` and looks the group up; without a `home_hook_groups` line (recorded runs) it falls back to the event-level aggregate with the same equation (C-1, D-1.1a).
- `.jobs/<name>.ident` — one line `<start_ticks>:<sha256 hex of /proc/<pgid>/cmdline>`, written before the `.pgid` file is published (so a record without `.ident` is either legacy or partial, both stale) (C-6).
- `meta/home-integrity.json` — unchanged `{files, tampered, missing, manifest_sha256, first}`; the validator now binds `manifest_sha256` and `files` to the pin (C-3).
- `.run/post-merge-candidate.json` — unchanged schema 2; the value domain is enforced at generation (C-9).

### 3.3 Data Modeling Approach

Append-only evidence lines and single-purpose record files, as today.

### 3.4 Migration Strategy

Recorded runs without `home_hook_groups` validate at event-level aggregates with the new equation (k·n over the event's summed commands; triggers summed over the event's groups); `.jobs` records without `.ident` are stale (not signalled, removed) and the first `reclaim` that meets them prints a one-time warning listing them (pgid, record name) so an operator can inspect live groups left by the pre-upgrade supervisor.

### 3.5 Data Access Patterns

Read-once at validation; no indexes.

### 3.6 Caching Strategy

None.

### 3.7 Backup and Recovery

The orchestrator's state and progress files keep their existing recovery semantics; the exit-code contract (§ 5.4) is what the runbook relies on.

> Sources: `evals/harness/took-effect.sh:1102-1110`; `evals/harness/lib/batch-supervisor.sh:56, 449`; `.claude/scripts/post-merge-orchestrator.sh:15-49`

---

## 4. UI Design

### 4.1 Design System

Plain-text evidence lines; every rule prints what it checked and how (the existing `(f)`/`(g)` format).

### 4.2 Key User Flows

See prd.md § User Experience: validate a session; publish an rc; ship the sprint.

### 4.3 Page/View Structure

Not applicable.

### 4.4 Component Architecture

Not applicable.

### 4.5 Responsive Design Strategy

Not applicable.

### 4.6 Accessibility Standards

Plain text; no colour-only signals.

### 4.7 State Management

Not applicable.

> Sources: prd.md § User Experience

---

## 5. API Specifications

### 5.1 API Design Principles

Command-line contracts: arguments, exit codes, evidence lines. No network API is added.

### 5.2 Endpoints

| Script | Change to its contract |
|---|---|
| `took-effect.sh --run-dir <run> --suite-file <suite>` | clause (g) evidence gains `hooks: <event>[:<matcher>] c=<count> n=<n> k=<k> triggers=<t|n/a>…`, `transcripts: <label> lines=<n> init=1 result=last …`, and `integrity: independent walk | record cross-checked against the pin (HOME deleted at exit)`; failures name the phase or group and the line |
| `sandbox-mount.sh hooks <settings>` | prints the `home_hook_counts` value as today and, on a second line, the `home_hook_groups` value (§ 3.2) |
| `egress-proxy.sh up` | `--pids-limit 256` |
| `batch-supervisor.sh` | writes `.jobs/<name>.ident`; `reclaim` identity-checks every group |
| `seed-corpus-from-external.sh` | the want set includes the fix diff's paths; new refusal text `fix diff needs N blob(s) outside the fetch bounds: <paths>` |
| `classify-merge-pr.sh` | the PR number is the subject's trailing `(#NNN)`, a positive decimal, else empty; `pr_type=other` when `pr_number` is empty (stderr note `no associated PR: a push, not a merge`); `--pr-number` still honoured |
| `post-merge-orchestrator.sh --publish` | a local or remote tag of another identity, a lightweight tag, an unreachable remote (`identity unverified`) or a non-integer number in the candidate refuses with exit 2 before any write; a tag appearing between validation and the push exits 1 (state FAILED); a re-run with an identical-identity tag skips the push and continues |
| `post-merge-orchestrator.sh --generate` | refuses a non-integer number in `prepared_state` with exit 2 and the JSON path, nothing written |

### 5.3 Contracts

The finding contract of cycle-133 (`finding.schema.json` v1) is untouched; the review and audit of this sprint use it.

### 5.4 Exit codes (authoritative for every script this cycle touches)

| Code | Meaning | Examples |
|---|---|---|
| 0 | completed as asked | validator ok; publish done; classifier answered |
| 1 | a step failed or a named difference | a publish phase failed after a write (a tag appearing between validation and the push); a validator FAIL line |
| 2 | refusal before any write (usage, precondition, policy) | candidate digest, schema, ancestry, local or remote tag identity mismatch, lightweight tag, unreachable remote, a non-integer number at generate or publish; seeder bounds refusal |
| 3 | completed, degraded, reason named | Bridgebuilder `degraded_reason` |

> Sources: `.claude/scripts/post-merge-orchestrator.sh:44-49`; cycle-133 sdd.md § 5.4 (archived); § 1.4

---

## 6. Error Handling Strategy

### 6.1 Error Categories

Refusal before write (2), failure after write (1), degraded completion (3); validator failures are `FAIL (g) <phase>: <reason>` lines.

### 6.2 Error Response Format

Plain text on stderr for scripts; evidence lines on stdout for the validator; `::error::` annotations in the workflow preflight.

### 6.3 Logging Strategy

Unchanged: `[TAG]`, `[PUBLISH]`, `[classify-merge-pr]` prefixes; the supervisor's `log` lines gain the stale-identity message.

> Sources: `.claude/scripts/post-merge-orchestrator.sh:1062-1110`; `.claude/scripts/classify-merge-pr.sh:118`; `evals/harness/lib/batch-supervisor.sh:243`

---

## 7. Testing Strategy

### 7.1 Testing Pyramid

Unit bats per component (fixtures that fail before and pass after), the existing harness and workflow suites unchanged and green, one host-local regression (D-4.2), CI as the gate.

### 7.2 Testing Guidelines

Every fixture encodes one direction; a change without a failing-before fixture is not accepted at review. `npx --no-install bats` on this host; the Docker 26.1-dependent egress bats keep their container job.

### 7.3 Traceability matrix (defect → reproducing test → component)

| Defect / requirement | Test | Component |
|---|---|---|
| F-001 recurring hooks false-fail (bd-bex39) | `evals/tests/took-effect-hooks.bats`: 1 configured PreToolUse hook, 2 Bash invocations → pass (k = 2 ≤ 2); 0 hook events with 66 Bash uses → pass (k = 0); a `hook_started` naming a group absent from the pin → fail; c not a whole multiple of n → fail; k above the trigger count → fail; two pinned groups with the same key merge; a matcher with colons and pipes round-trips through `home_hook_groups`; a recorded run with only `home_hook_counts` (several matchers under one event) → event-level aggregate | C-1 |
| F-002 missing transcript passes (bd-k3dia) | `evals/tests/took-effect-transcripts.bats`: executed label (from `pipeline.json`) without a transcript / with no init / with no result / with a malformed interior line / with a result that is not the final line / with an init after the result / with a foreign `session_id` → fail naming the phase and line; complete → pass; a transcript whose label is not in `labels_run` is reported | C-2 |
| integrity record trusted (bd-htzy2) | `evals/tests/took-effect-integrity.bats`: record digest ≠ the pin's manifest digest → fail; `files` ≠ entry count → fail; retained HOME with a tampered file → fail; clean → pass with the mode named | C-3 |
| R3/R5 breadth (bd-kgfh5) | `evals/tests/sandbox-mount-rules.bats`: one case per corpus-table row; `evals/tests/sandbox-mount-home-scope.bats` and the negative control unchanged | C-4 |
| pids < MaxClients (bd-1br0v) | `evals/tests/egress-proxy.bats`: pid limit ≥ MaxClients + 16, both read from the files | C-5 |
| reclaim without identity (bd-ruo5b) | `evals/tests/batch-supervisor.bats`: stale identity → not signalled, record removed; matching identity → terminated; no `.ident` → stale with the one-time warning listing it; `.ident` written before `.pgid`; the identity is re-read before TERM and before KILL (the residual numeric-pgid window is documented in the lib header) | C-6 |
| fix diff over unfetched blobs (bd-kdk3l) | `evals/tests/seed-corpus-from-external.bats`: a fix touching a file outside the PR set is fetched within bounds; outside the bounds → refusal naming the path | C-7 |
| red pipeline on the ledger push (bd-hyx0n, KF-063) | `tests/unit/classify-merge-pr.bats`: `chore(ledger): archive … after merge` → other; `feat(cycle-134): …` without `(#NNN)` → other; `fix: … closes #12 (#345)` → pr_number 345; `(#0)` and `(#12a)` → empty; `--pr-number` explicit → cycle; `tests/unit/post-merge-workflow-guards.bats`: both job guards name `pr_number`, and a push without a PR runs neither job (stated as intended) | C-8 |
| exit 2 after a write; floats (bd-4pv1j) | `tests/unit/post-merge-publication.bats`: pre-existing local or remote tag of another identity → exit 2, no state file; a lightweight tag → exit 2; an unreachable remote → exit 2 `identity unverified`; a tag appearing between validation and the push → exit 1, state FAILED; a re-run with an identical-identity tag skips the push; a float (also nested), an exponent form or `-0` in `prepared_state` → `--generate` exit 2 with the path, with and without `rfc8785`; the same value in a candidate at `--publish` → exit 2; the integer domain agrees across both paths; the rc.8 candidate (10 integers) passes | C-9 |
| the sprint ships as one PR with a non-degraded verdict | the Bridgebuilder summary on the PR; `record-branch.sh` and `archive-cycle.sh` runs | C-10 |

Host-local regression (D-4.2, pre-registered in D-4.3): `took-effect.sh --run-dir <run> --suite-file grimoires/loa/reports/ablation-2.0/c133-smoke/suite.yaml` over `evals/results/ablation-2.0/smoke-c133-s274/a1_full/smoke-review-c133-t1` and `smoke-c133-s274-r2/a1_full/smoke-review-c133b-t1`. Baseline 2026-10-25 (identical to the recorded `meta/took-effect.json`): run 1 fails `oracle_closed` on clause (f) (`pinned_bytes_read`, +34 more; KF-060) and `dissent_present`, `integrity_clean` passes (2073 entries); run 2 fails `oracle_closed` on (f) (+11 more), `integrity_clean` passes. Expected after C-1/C-2/C-3: the same failing sets and passes; run 1's REVIEW capture (845 lines, init 1, result 0) adds a (g) `transcript REVIEW: no result event` entry to the `+N more` list — the one pre-explained change; hook groups pass with k = 1 for `SessionStart:startup` (8 of 8 per init) and k = 0 elsewhere; `integrity_clean` passes as `record cross-checked against the pin`. Any other difference is a shipping gate (DEC row and bead before merge).

### 7.4 CI/CD Integration

`bats-tests.yml` runs the unit and harness bats; `post-merge.yml` prepares the candidate on the merge (left unpublished, DEC-0967).

> Sources: prd.md § Functional Requirements (acceptance criteria); `.github/workflows/bats-tests.yml`; D-4.2 (DEC-0980)

---

## 8. Development Phases

### Sprint 1 (global 276) — the nine fixes

Four implementers in parallel, each in a worktree from the sprint base, each with a code-only diff and a "Judgment calls" section in its report:

- **A — validator:** C-1, C-2, C-3 (`took-effect.sh` only), the three took-effect bats files, the host-local regression (D-4.3), the Q-1 grammar confirmation (a one-turn `claude -p` on the lead host under a settings file with a matcher-less and a regex PreToolUse group; the real events become fixtures).
- **B — mount rules and hook-group evidence:** C-4 (the corpus table § 11.F, the narrowed regexes, `sandbox-mount-rules.bats`, the bead correction) and `cmd_hooks` → `home_hook_groups` to the § 3.2 grammar with its own bats case (D-2.1a); B owns every change to `sandbox-mount.sh`.
- **C — publish path (System Zone):** C-8, C-9 (`classify-merge-pr.sh`, `post-merge.yml`, `post-merge-orchestrator.sh`, their bats), under the zone marker with `checksums.json` and REPO-MAP regenerated.
- **D — harness libraries:** C-5, C-6, C-7 and their bats.

The lead lands A, then B, then C and D; after A and B it runs the home-scope bats and a hook-grammar round trip (`sandbox-mount.sh hooks` → `took-effect.sh` on a fixture); then the suites, CHANGELOG `[Unreleased]`, review and audit (dissent ≤ 3), the host-local regression against D-4.3, and the ship (C-10).

> Sources: prd.md § Timeline & Milestones; cycle-134-brief.md § Sprint breakdown

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| `hook_name` grammar differs for matcher-less or tool-event hooks (only `SessionStart:startup` is observed; the retained sessions emitted no tool-hook events at all beside 31–66 Bash uses) | C-1 parses `<event>` alone and `<event>:<matcher>`; a hook_name that parses but names no pinned group fails; k = 0 is legal so an un-emitting group never false-fails; the grammar confirmation on a real one-turn session is a pre-merge gate (Q-1, implementer A) |
| trigger counts are not derivable for rare events | rules (a)+(b) apply (0 ≤ k, divisibility); the evidence line says `triggers: n/a` for that group; § 11.H lists the derivable events |
| narrowing R3/R5 drops a rewrite the mount needs | the corpus table with every difference explained; the home-scope bats and the negative control gate the change |
| the classifier change misroutes a real cycle merge | the fixture for a cycle subject with `(#NNN)` stays `cycle`; the job guard is additive |
| moving the tag check pre-write misses a tag created between validation and the tag phase | `phase_tag` keeps its check and returns 1 (failed after write), the honest code for that race |
| the host-local regression cannot run in CI | recorded in the sprint report with the verdict lines; the fixtures carry the same cases into CI |
| the fixed validator legitimately changes a recorded smoke verdict | investigated, recorded as a DEC row and a bead; never accepted silently (prd.md FR-1 AC) |

> Sources: prd.md § Risks & Mitigation; § 11 D-1.1, D-2.1, D-3.1, D-3.2, D-4.2

---

## 10. Open Questions

| # | Question | Owner | Resolution path |
|---|---|---|---|
| Q-1 | What `hook_name` does Claude Code emit for a matcher-less PreToolUse group and for a regex matcher such as `Write|Edit|MultiEdit|NotebookEdit`? | implementer A | **pre-merge gate:** a one-turn `claude -p` on the lead host under a settings file with both group kinds (the retained batches hold only `SessionStart:startup`); the real events become fixtures; if tool hooks emit no events in `-p` mode, that fact is recorded on bd-bex39 and k = 0 covers it |
| Q-2 | Which R3/R5 contexts does the mount rely on? | implementer B | the corpus table (D-2.1) |
| Q-3 | Does any current `prepared_state` field carry a float? | resolved 2026-10-25 | the rc.8 candidate `post-merge-candidate.json` holds 10 numbers, all integers within 2^53, no float — the refusal is safe for the current producer; the bats keep the real candidate as a passing fixture |

> Sources: § 11 D-1.1, D-2.1, D-3.2

---

## 11. Appendix

### 11.D Design decisions taken on the operator's behalf

| # | Decision | Row |
|---|---|---|
| D-1.1 | FR-1 hook rule: `hook_name` group identity + per-group whole-multiple count bounded by transcript triggers | DEC-0971 |
| D-1.2 | FR-2: transcript + init + final result per executed phase | DEC-0972 |
| D-1.3 | FR-4: recompute the pin's manifest digest; bind record, arm_evidence and entry count; walk a retained HOME | DEC-0973 |
| D-2.1 | FR-5: verify already round-trips R5 (correction); corpus table narrows R3/R5 | DEC-0974 |
| D-2.2 | FR-6: proxy `--pids-limit 256`; pair-pinning test | DEC-0975 |
| D-2.3 | FR-7: `.jobs/<name>.ident`; identity-checked reclaim | DEC-0976 |
| D-2.4 | FR-8: fix-diff paths join the bounded fetch; refuse by name | DEC-0977 |
| D-3.1 | FR-3: empty PR number → other; cycle job guarded on `pr_number`; `[skip ci]` rejected | DEC-0978 |
| D-3.2 | FR-9: tag identity check pre-write (exit 2); remote mismatch → 1; `--generate` refuses non-integer numbers | DEC-0979 |
| D-4.2 | took-effect regression on the retained smoke batches (host-local); amends DEC-0970 | DEC-0980 |
| D-3.2a | FR-9 amendment (Flatline IMP-014): the remote tag identity check also runs pre-write; `phase_tag` re-checks for the race | DEC-0981 |
| D-1.1a | FR-1 equation c = k·n, 0 ≤ k ≤ triggers, k = 0 allowed; merged groups; `home_hook_groups` hex evidence; grammar gate | DEC-0982 |
| D-1.2a | FR-2 JSONL policy: every line parses, init before the unique final result, shared session_id | DEC-0983 |
| D-2.1a | implementer B owns every `sandbox-mount.sh` change incl. the evidence emitter; landing order A → B | DEC-0984 |
| D-3.2b | `--generate` refusal exits 2; integer domain at generate and publish; unreachable remote exits 2; annotated-tag identity; trailing `(#NNN)` | DEC-0985 |
| D-4.3 | regression baseline and expected after-state pre-registered | DEC-0986 |

### 11.E Grounding reads

| Component | File:line | Quote |
|---|---|---|
| C-1 | `evals/harness/took-effect.sh:624-625` | `elif st == "hook_started": k = (tn, str(ev.get("hook_event") or "")); hook_counts[k] = hook_counts.get(k, 0) + 1` |
| C-1 | `evals/harness/lib/sandbox-mount.sh:1733-1743` | `def cmd_hooks(settings): """<event>:<n>,… — the hook commands per event the pinned user settings declare (home_hook_counts)"""` |
| C-1 | retained cycle-130 smoke transcript | `{"type":"system","subtype":"hook_started","hook_id":"…","hook_name":"SessionStart:startup","hook_event":"SessionStart",…}` |
| C-2 | `evals/harness/took-effect.sh:601` | `tfiles = sorted(n for n in (os.listdir(tdir) if os.path.isdir(tdir) else []) if re.match(r"^events-[A-Za-z0-9_-]+\.jsonl$", n))` |
| C-3 | `evals/harness/pipeline-run.sh:552-554` | `home_integrity — home-scope: the HOME framework copy against its manifest (the HOME is deleted at exit, so took-effect.sh integrity_clean reads this record)` |
| C-4 | `evals/harness/lib/sandbox-mount.sh:1707-1709` | `def cmd_verify(home_root, source_root, home): """reverse(every copied file) == the pinned bytes …"""` |
| C-4 | `evals/harness/lib/sandbox-mount.sh:1613` | `text = R5_REV.sub(lambda m: m.group(1), text)` |
| C-5 | `evals/harness/lib/egress-proxy.sh:205` / `Dockerfile.proxy:101` | `--security-opt no-new-privileges --pids-limit 128 --memory 256m` / `MaxClients 200` |
| C-6 | `evals/harness/lib/batch-supervisor.sh:237-238` | `Same boot: the recorded runner (identity-checked) and every .jobs/ group still alive are terminated` |
| C-7 | `evals/harness/seed-corpus-from-external.sh:562` | `fix_diff = g("diff", *DIFF_OPTS, "-U0", FIX_PARENT, FIX_LAST).stdout` |
| C-8 | `.claude/scripts/classify-merge-pr.sh:88` | `PR_NUMBER=$(echo "$MERGE_MSG" | grep -oE '#[0-9]+' | head -1 | tr -d '#' || true)` |
| C-8 | `.github/workflows/post-merge.yml:182` | `if: needs.classify.outputs.pr_type == 'cycle'` |
| C-9 | `.claude/scripts/post-merge-orchestrator.sh:1091-1093` | `fail_phase tag "Existing local tag ${tag} differs from the candidate (target or release identity)"; return 2` |
| C-9 | `.claude/scripts/post-merge-orchestrator.sh:2184` | `atomic_state_update --arg digest "$APPROVED_DIGEST" '.candidate_digest = $digest | .state = "PUBLISHING"'` |

> Sources: direct reads on 2026-10-25; `grimoires/loa/decisions.yaml` DEC-0971 … DEC-0980


### 11.F R3/R5 corpus table (implementer B fills this in Sprint 1)

Current patterns (sandbox-mount.sh:1496, 1503 at the sprint base f17bfe0e4; after Task 1.5 R3 sits at :1501 and R5 at :1557):

```
R3 = re.compile(r"(?<![A-Za-z0-9_./$~{}\\-])\.claude/")                                  # markdown: a relative .claude/ path → <home>/.claude/
R5 = re.compile(r"(?<!/ )(?<!/)(['\"])(\.claude/[A-Za-z0-9_./-]*)\1")                      # python: a string literal that is exactly a .claude/… path → os.path.join(<env>, it)
```

Narrowing criterion: a rewrite is kept only where the pinned framework's text is *resolved as a path at run time* (a hook command, a skill's `Base directory`, a script path a Bash line executes, an `os.path.join`/`open`/`subprocess` operand); prose mentions, documentation examples and message strings are not rewritten. The table groups the 1216 R3/R5 hits over the pinned framework (f17bfe0e4) by context class and decision, each row with a count, an example and its bats case; the per-hit list is `evals/tests/fixtures/sandbox-mount/r3r5-corpus.tsv`, pinned byte-exactly by MR-24 (I-1.5a):

| # | Path | Context class | Current rewrite | Keep? | Case |
|---|------|---------------|-----------------|-------|------|
| 1 | R3, 469 hits, e.g. `.claude/commands/feedback.md:175`; every hit is listed under row 1 of `evals/tests/fixtures/sandbox-mount/r3r5-corpus.tsv` (1216 hits at f17bfe0e4, one line each) | code span naming a pinned file or directory | `.claude/` → `<home>/.claude/` | keep: an instruction the agent runs or reads | MR-01 |
| 2 | R3, 416 hits, e.g. `.claude/protocols/reference/helper-scripts.md:94` (TSV row 2) | fenced code block naming a pinned path (a command) | `.claude/` → `<home>/.claude/` | keep: a Bash line executes it | MR-02 |
| 3 | R3, 80 hits, e.g. `.claude/subagents/documentation-coherence.md:51` (TSV row 3) | table cell (code span) naming a pinned path | `.claude/` → `<home>/.claude/` | keep: a lookup table the agent resolves | MR-03 |
| 4 | R3, 84 hits, e.g. `.claude/skills/butterfreezone-gen/SKILL.md:49` (TSV row 4) | bare prose or frontmatter value naming a pinned path (`EXECUTE:`, `allowed-tools: Bash(…)`, `script:`, `paths:`) | `.claude/` → `<home>/.claude/` | keep: executed, permitted or loaded by path | MR-04 |
| 5 | R3, 3 hits: `.claude/commands/update-loa.md:409`, `:410`, `.claude/protocols/reference/recommended-hooks.md:512` (TSV row 5) | fenced command line: an absent path (a `.tmp`, a `.bak`) beside a pinned one | `.claude/` → `<home>/.claude/` | keep: a command is rewritten whole, so source and target stay on one side | MR-05 |
| 6 | R3, 25 hits, e.g. `.claude/commands/loa-eject.md:33` (TSV row 6) | code span naming the zone (`.claude/` alone) | `.claude/` → `<home>/.claude/` | keep: under home-scope the System Zone is the HOME copy; "never edit" and the audit scope (`auditing-security/SKILL.md:93`) resolve it against paths | MR-06 |
| 7 | R3, 10 hits, e.g. `.claude/commands/update-loa.md:279` (TSV row 7) | fenced code naming the zone (a `case` pattern, a tree diagram, an `echo` message) | `.claude/` → `<home>/.claude/` | keep (as row 6) | MR-07 |
| 8 | R3, 7 hits, e.g. `.claude/commands/ride.md:283` (TSV row 8) | table cell (code span) naming the zone | `.claude/` → `<home>/.claude/` | keep (as row 6) | MR-08 |
| 9 | R3, 6 hits, e.g. `.claude/commands/loa-eject.md:230` (TSV row 9) | table cell (bare): an error or message string naming the zone | `.claude/` → `<home>/.claude/` | keep: a message string, but rewriting it is harmless and a zone-name rule stays uniform | MR-09 |
| 10 | R3, 5 hits, e.g. `.claude/rules/zone-system.md:3` (TSV row 10) | bare prose or frontmatter naming the zone (`.claude/`, `.claude/**`) | `.claude/` → `<home>/.claude/` | keep (as row 6) | MR-10 |
| 11 | R3, 16 hits, e.g. `.claude/protocols/reference/recommended-hooks.md:363` (TSV row 11) | code span naming a path the pinned tree does not hold (a documentation example, a project-owned file such as `settings.local.json`, `constructs/packs/`) | `.claude/` → `<home>/.claude/` | drop (absent): nothing pinned to resolve; a project path stays the project's | MR-11 |
| 12 | R3, 13 hits, e.g. `.claude/protocols/reference/constructs-integration.md:25` (TSV row 12) | fenced code naming an absent path | `.claude/` → `<home>/.claude/` | drop (absent) | MR-12 |
| 13 | R3, 9 hits, e.g. `.claude/protocols/reference/constructs-integration.md:48` (TSV row 13) | table cell (code span) naming an absent path or a placeholder under an absent directory | `.claude/` → `<home>/.claude/` | drop (absent) | MR-13 |
| 14 | R3, 2 hits: `.claude/commands/constructs.md:33`, `.claude/skills/rtfm-testing/SKILL.md:5` (TSV row 14) | bare prose or frontmatter naming an absent path or a glob that matches nothing | `.claude/` → `<home>/.claude/` | drop (absent) | MR-14 |
| 15 | R3, 4 hits, e.g. `.claude/commands/archive-cycle.md:121` (TSV row 15) | heading | `.claude/` → `<home>/.claude/` | keep: names a pinned script the agent may run | MR-15 |
| 16 | R3, 60 hits, e.g. `.claude/loa/CLAUDE.loa.md:73` (TSV row 16) | HTML comment (`DO NOT EDIT — generated from …`, `@skill-include` markers) | `.claude/` → `<home>/.claude/` | keep: a provenance marker; rewriting it is harmless, and the executing skills carry these markers (HS-11 pins that their text holds no relative `.claude/` path) | MR-16 |
| 17 | R3, 3 hits under `.claude/skills/bridgebuilder-review/resources/__tests__/fixtures/` (TSV row 17) | test-fixture data (JSON review comments) | `.claude/` → `<home>/.claude/` | drop (data): never read as an instruction | MR-17 |
| 18 | R5 `.claude/adapters/cheval.py:176` `".claude/skills"` | `Path` operand (`Path(search_dir) / agent / "persona.md"`) | `os.path.join(<env>, '.claude/skills')` | keep (the bare `".claude"` beside it is a name, never rewritten) | MR-18 |
| 19 | R5 `.claude/adapters/loa_cheval/audit/modelinv.py:355` | other: a module constant joined as `repo_root / _WRITER_VERSION_PATH` (:402) | `os.path.join(<env>, '.claude/data/cycle-108/…')` | keep | MR-19 |
| 20 | R5 `.claude/adapters/loa_cheval/config/advisor_strategy.py:219` | other: a module constant joined as `repo_root / SCHEMA_PATH_REL` (:382) | `os.path.join(<env>, '.claude/data/schemas/…')` | keep | MR-20 |
| 21 | R5 `.claude/adapters/loa_cheval/economy.py:42` | other: an argparse `--model-config` default (:772), opened as a path | `os.path.join(<env>, '.claude/defaults/model-config.yaml')` | keep | MR-21 |

### 11.G Flatline SDD review dispositions (1.1 → 1.2)

Two voices (codex-headless, claude-headless), cross-scoring degraded (KF-041 shape), 0 high-consensus items, 49 medium items, 12 skeptic blockers. Every item was read:

| Item | Concern (short) | Disposition |
|---|---|---|
| SKP-002 (gpt), SKP-003 (gpt) | 0 is a whole multiple; no positive-count requirement | **Rejected with reasoning, semantics made explicit (D-1.1a):** clause (g) asks whether a hook of the PR ran, not whether the pinned hooks fired; the retained sessions show 0 tool-hook events beside 31–66 Bash uses, so k ≥ 1 would false-fail legitimate runs |
| SKP-001 (gpt), SKP-007 (opus) | source of truth for executed labels; binding init/result to the phase | **Accepted** (C-2: `pipeline.json` non-skipped phases; shared `session_id`) |
| SKP-003 (opus) | Q-3 open while the float refusal ships | **Accepted and resolved:** the rc.8 candidate has 10 integers, no float; the bats keep it as a fixture |
| SKP-009, gpt IMP-011 | TOCTOU with numeric pgids; record lifecycle | **Accepted in part:** `.ident` before `.pgid`, re-read before TERM/KILL, the residual window documented; atomicity is not available for pgids |
| SKP-012, gpt IMP-014, opus IMP-012 | remote lookup failure vs absence; annotated-tag identity | **Accepted** (D-3.2b) |
| SKP-013 | concurrent publishers | **Out of scope, documented:** a single operator publishes; `main` is lease-protected; concurrent publishers are not a supported mode |
| SKP-004, gpt IMP-002, opus IMP-018 | duplicate (event, matcher) groups; settings sources; grammar unresolved | **Accepted** (D-1.1a: groups merge; HOME user settings only; grammar gate) |
| SKP-002 (opus), gpt IMP-001, gpt IMP-018 | verbatim matcher encoding; legacy aggregation | **Accepted** (`home_hook_groups` hex ids; § 3.4) |
| SKP-006, gpt IMP-005, opus IMP-002 | "last parseable line" permits malformed trailing content | **Accepted** (D-1.2a) |
| SKP-001 (opus), gpt IMP-009 | record cross-check is not content proof | **Accepted, stated:** the evidence mode names it; a claimed home-scope measurement retains the HOME (or an independent pre-session listing) — recorded on bd-ivmtk |
| gpt IMP-003, opus IMP-019 | acceptance equation and trigger derivation table | **Accepted** (D-1.1a; § 11.H) |
| gpt IMP-004 | grammar confirmation as a pre-merge gate | **Accepted** (Q-1) |
| gpt IMP-006 | failed/interrupted/retried phases | **Accepted:** every non-skipped label requires a complete transcript; a killed phase fails (g) as unexamined |
| gpt IMP-007, IMP-008; opus IMP-026 | digest algorithm and inputs; retained-HOME walk rules and location | **Accepted:** SHA-256 of the pin's `.claude/checksums.json` blob bytes; entry count = its `files` map size; the walk mirrors the sandbox walk (regular files only, symlink = fail, extra files reported); the retained copy lives at `<run>/home/.claude` and `home-integrity.json` records `retained: true` |
| gpt IMP-010, opus IMP-020 | the corpus table and the narrowing criterion | **Accepted** (§ 11.F) |
| gpt IMP-012, IMP-013; opus IMP-016 | seeder discovery over both trees; fail-closed; bounds | **Accepted:** `changed(FIX_PARENT, FIX_LAST)` with `--no-renames` (adds and deletes), NUL-safe, blob ids deduplicated and charged once against `--max-files`/`--max-bytes`; any enumeration or fetch failure refuses |
| gpt IMP-015, opus IMP-013 | race through the push; re-run contract | **Accepted** (D-3.2b items 3 and 5) |
| gpt IMP-016, opus IMP-014 | integer domain definition; enforce at publish | **Accepted** (D-3.2b item 2) |
| gpt IMP-017, opus IMP-001 | `--generate` exit code vs § 5.4 | **Accepted:** exit 2 |
| gpt IMP-019 | validate the PR number; routing semantics | **Accepted in part:** positive decimal validated; the guard test reads the workflow text (no expression evaluator) |
| gpt IMP-020, opus IMP-021 | shared-file edit between A and B | **Accepted** (D-2.1a) |
| gpt IMP-021, opus IMP-017 | expected regression verdicts | **Accepted** (D-4.3) |
| gpt IMP-022, opus IMP-024 | D-3.2a row bookkeeping; version/status | **Accepted** (fixed) |
| opus IMP-011 | anchor the PR number to the trailing `(#NNN)` | **Accepted** (D-3.2b item 6) |
| opus IMP-015 | Dockerfile naming | **Accepted** (fixed) |
| opus IMP-022 | legacy `.jobs` records warning | **Accepted** (§ 3.4) |
| opus IMP-023 | § 5.4 examples | **Accepted** (fixed) |
| opus IMP-025 | a push without a PR runs neither job | **Accepted, stated as intended** (§ 7.3 C-8) |
| remaining medium items | restatements or wording | **Noted** |

### 11.H Trigger derivation (C-1 rule (c))

| Event | Transcript signal for the trigger count | Matcher evaluation |
|---|---|---|
| SessionStart | `system`/`init` events | matcher is the source (`startup`, `resume`, `clear`, `compact`); `startup` ↔ init |
| UserPromptSubmit | `user` events whose content is text (not `tool_result`) | none |
| PreToolUse, PostToolUse | `tool_use` blocks in `assistant` messages whose `name` matches the matcher as a regex (empty matcher = every tool) | regex, full match on the tool name |
| Stop | `result` events | none |
| PreCompact, Setup, PermissionRequest, Notification, SubagentStop | not derivable | `triggers: n/a` — rules (a) and (b) only |

> Sources: the retained smoke transcripts (events-REVIEW.jsonl, events-AUDIT.jsonl); `evals/harness/took-effect.sh:600-660`; the SDK message types for hook events


### 11.I Implementation amendments (Sprint 276; the DEC rows I-1.x)

| Design row | Amendment | Row |
|---|---|---|
| D-1.3 / DEC-0973 (integrity binding) | the HOME manifest is regenerated over the transformed copy with a `generated` timestamp, so digest equality with the pin blob is infeasible; the binding is coverage (record.files ≥ the pin's entry count), `arm_evidence` equality and the pin match (suite/batch pin = `pipeline.json`'s); the pin's digest is shown in the evidence | DEC-0990 (I-1.3a) |
| D-1.1a (hook identity) | the `hook_name` suffix is the trigger's query (`startup`), not the configured matcher: a `<event>:<q>` event maps to sha(q) plus the matcher-less group; regex-only groups fail closed until a real tool-hook event exists (none is emitted in `-p` mode on Claude Code 2.1.310) | DEC-0987 (I-1.1a) |
| § 11.H (trigger evaluation) | tool triggers compare names as text (equal to the query or a `\|`-alternative); transcript strings are never compiled as regex | DEC-0988 (I-1.1b) |
| D-3.2b item 6 (PR number) | the anchored `Merge pull request #N` prefix is accepted beside the trailing `(#NNN)` — this repository merges with merge commits, and a trailer-only rule would have disabled every release | DEC-0993 (I-1.6a) |
| D-2.3 (job identity) | `record-job` in the supervisor lib writes `.ident` then `.pgid`; the identity is read after the leader's exec settles (≤ 5 s); `run-ablation.sh`'s writers call it (lead-landed) | DEC-0995 (I-1.9a) |
| D-2.4 (seeder) | bounds and missing-object refusals exit 2; a failed fetch exits 1 naming paths; symlink blobs in the fix range are fetched | DEC-0996 (I-1.10a) |

> Sources: the four implementer reports (`~/.cache/loa/cycle-134/reports/s1-{a,b,c,d}.md` § Judgment calls); `grimoires/loa/decisions.yaml` DEC-0987 … DEC-0997; `grimoires/loa/a2a/sprint-276/regression.md`
