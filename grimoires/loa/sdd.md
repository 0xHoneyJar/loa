# Software Design Document: The follow-through (cycle-133)

**Version:** 1.2
**Date:** 2026-10-23
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-133, 1.1, FR-1 … FR-14, Appendix A D-1 … D-12 = DEC-0827 … DEC-0838)
**Status:** Draft 1.1 — autonomous run; design-level decisions taken on the operator's behalf are §11.D D-1.1 … D-4.2 (DEC-0839 … DEC-0852) and, from the Flatline SDD review, D-1.6, D-1.7, D-2.5, D-3.4, D-3.5, D-3.6 (DEC-0856, DEC-0853, DEC-0854, DEC-0855, DEC-0857, DEC-0858), each with the alternatives rejected; the FR-10 and FR-3 choices are the operator-visible ones (D-3.1 as amended by D-3.6, D-1.3 as amended by D-1.6); §11.E lists every review concern and where it landed
**Branch:** `feature/cycle-133-follow-through` from `main a82ec556`
**Pins:** the cycle-132 pipeline pin `fbd36a0c`, its record branch and registered reads are untouched; the Sprint 2 head is an intermediate pipeline version (image 259 built, self-check recorded); the pin the smoke and any later measurement cite is the Sprint 3 head, after the mount mode, the took-effect clauses, grader 1.5 and registration v2 land (D-3.4); the cycle-132 reproduction runs from a worktree at `fbd36a0c` because the new tooling replaces the same paths on `main`

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

Four surfaces of the framework change, each in place, plus two shared contracts:

- **Reviewer tooling** — the Bridgebuilder skill (`.claude/skills/bridgebuilder-review/resources/**`, compiled to `dist/`): a paged, SHA-pinned file fetch (FR-1) and a guarded consensus writer with a block-derived verdict (FR-2).
- **Release path** — `post-merge-orchestrator.sh`: the candidate targets the merge commit; the ledger-archive change rides as a patch applied by a conditional fast-forward after the release (FR-3).
- **Framework scripts and hooks** — a new `record-branch.sh`; `notes-guard.sh rotate`, `pre-compact-marker.sh`, `dec-write-lib.sh`, `security-audit-scope.sh`, `ledger-lib.sh validate_ledger` fixed (FR-4); CI and quarantine (FR-5).
- **Harness and analysis** — the session library hardened and shared (FR-6); reproduction and analysis tooling hardened (FR-7); grader 1.4 and the refusal policy (FR-8); supervisor and egress (FR-9); the mount that lets Loa review Loa (FR-10); grader 1.5 with the judge hook (FR-11); the external seeder and registration v2 (FR-12).
- **Contracts** — one canonical finding schema at the four gates (FR-11) and the process of the beads sweep (FR-13) and the release (FR-14).

> From prd.md: "Every recorded defect is fixed in the framework with a test that fails when it returns and a line of documentation."

### 1.2 Architectural Pattern

Surgical change within existing components, each guarded by the test that reproduces its defect; new components only where none exists (`record-branch.sh`, `lib/corpus-seed.sh`, `seed-corpus-from-external.sh`, the egress proxy sidecar, the supervisor mode, `finding.schema.json`, `tests/QUARANTINE.tsv`). Fail-closed everywhere a value feeds a decision: a sentinel the consumer cannot mistake for data (pricing), a refusal with repair text (exit 2), a degraded result with a named reason (exit 3).

### 1.3 Component Diagram

```
 operator ──/bridgebuilder──▶ [C-1 paged fetch] ─▶ [truncation per page] ─▶ voices ─▶ [C-2 guarded writer] ─▶ GitHub comment + verdict JSON
 merge ──post-merge.yml──▶ [--generate: target = merge, ledger patch] ─▶ artifact ─▶ operator ──[--publish: remote-main check → tag → release → ledger ff → notify]
 cycle close ──▶ [C-4 record-branch.sh: manifest → temp index → staged-tree scan → commit-tree] ─▶ ICE push
 batch ──▶ [C-9 supervisor (systemd-run --user | watchdog)] ─▶ run-ablation.sh --resume ─▶ pipeline-run.sh ─▶ docker 26.1.5 (internal net) ─▶ [proxy sidecar: allowlist] ─▶ model endpoints
 review-catch trial ──▶ [C-10 mount: HOME-scope pinned framework; root .claude/ = PR data; executable surface absent] ─▶ claude -p (user scope) ─▶ transcript ─▶ [took-effect clause (e) + grader oracle scan]
 gate outputs (review, audit, BB, dissent) ──▶ [C-11 finding.schema.json v1] ──▶ verdict-derive / schema validators ──▶ [grader 1.5 --judge-verdicts]
 external repo ──▶ [C-12 seed-corpus-from-external.sh ← lib/corpus-seed.sh] ─▶ fixture (temp or committed under the SPDX allowlist)
 tracker ──▶ [C-13 sweep: inventory → Explore batches → manifest → lead applies → 10 % re-verify]
```

### 1.4 System Components

**C-1 Paged PR fetch (FR-1; D-1.1 DEC-0839).** `adapters/github-cli.ts`: `getPR(owner, repo, n)` returns `{base_sha, head_sha, changed_files}` from `pulls/N`. The fetch is two-pass: pass 1 pages `pulls/N/files?per_page=100&page=K` (no `--paginate`) keeping filename, status, additions, deletions and `patch` length only, deduplicating by filename, re-reading `pulls/N` before every page and discarding everything on a base or head change (`PrHeadMoved`; one restart, then `degraded_reason: pr_head_moved`); `truncateFiles` then runs once over the complete filename list with the global limits (Loa tier, `exclude_patterns`, `max_files_per_pr`, tier ordering), producing the selection; pass 2 re-pages only the pages that hold selected files and retains their `patch` text up to `max_diff_bytes` (a selected file whose patch exceeds the remaining budget is retained cut and recorded `patch_truncated`); after pass 2 both SHAs are revalidated and the result is discarded on change. Received bytes are bounded per page; `gh_max_buffer_bytes` (config, default 64 MiB) is the per-call buffer. GitHub omissions are recorded, never silent: a file without `patch` (binary, generated, GitHub-truncated) → `no_patch`; `changed_files > 3000` → `files_list_truncated` with the unknown count `changed_files − listed` kept separate from named omissions; an incomplete page request → `page_incomplete` and degraded. "Reviewable code file" = a file not excluded by the Loa tier or `exclude_patterns` whose extension is in the review set (code, scripts, config, docs); omission of any reviewable code file sets `degraded: true` and `mergeBlocked: true` with `mergeBlockedReason: incomplete_coverage`; files omitted by pattern never degrade. Default `exclude_patterns` gain `evals/fixtures/review-prs/**` and `grimoires/loa/reports/ablation-2.0/*-grades/**`. Coverage record `{base_sha, head_sha, reviewed: [{file, bytes, hunks}], omitted: [{file, reason}], unknown_omitted}` lives in full in the summary JSON and the marker; the posted comment shows counts per reason plus the first 20 paths. Callers `core/reviewer.ts:820` and `main.ts:614` switch to the two-pass path.

**C-2 Guarded consensus writer and verdict (FR-2; D-1.2 DEC-0840, D-1.7 DEC-0853).** Writer eligibility: the default `writer_role_allowlist` is claude-headless (`--tools ""` + plan mode, `claude_headless_adapter.py:143-155`) and the API adapters; codex-headless joins only after a vitest proves its native shell, file and network tools cannot execute under its dispatch (`codex_headless_adapter.py:18-27, 83-114` describes a posture, not a tested restriction); every adapter reports its enforced no-tool stance in the dispatch result and the role check verifies that report; an ineligible writer is `degraded_reason: writer_not_eligible` (exit 3, un-enriched consensus posted). The findings themselves are never produced by the writer: the posted block is rendered deterministically from the consensus (every canonical field — id, file, anchor_line, anchor_line_end, severity, confidence, failure_scenario, suggestion, blocking — byte for byte, same multiplicity, no duplicate ids) and the writer's output is commentary placed in a separate section. The guard (`core/enrichment-guard.ts`, new) rejects writer output that contains a findings block of its own, that alters or omits any canonical field if it echoes findings, or that carries provider tool grammar matched structurally (a line-start XML tag `<invoke`/`<function_calls`, or a top-level JSON key `tool_use`/`function_call`/`tool_calls`, outside fenced code spans and outside quoted string values) → `enrichment_guard_rejected`, exit 3. `core/review-verdict.ts summarizeReviewVerdict` decision table: (1) any finding with `blocking: true` or severity CRITICAL or HIGH → REQUEST_CHANGES; (2) a guard rejection or `incomplete_coverage` → `UNKNOWN`, `degraded: true`, `mergeBlocked: true` with the reason; (3) exactly one valid consensus block → its `verdict`; (4) no block → the prose rule; (5) two blocks, a malformed block, or a block verdict contradicting (1) → `verdict_conflict`, `UNKNOWN`, `mergeBlocked: true`. INFO, PRAISE, SPECULATION and REFRAME never block. `degraded_reason` is an exported enum in `core/run-outcome.ts` (`files_payload_oversize`, `files_list_truncated`, `page_incomplete`, `patch_fetch_rate_limited`, `pr_head_moved`, `incomplete_coverage`, `enrichment_guard_rejected`, `writer_not_eligible`, `verdict_conflict`).

**C-3 Release publish (FR-3; D-1.3 DEC-0846, D-1.6 DEC-0856).** `post-merge-orchestrator.sh --generate` writes candidate schema_version 2 with an immutable sealed object — `merge_sha`, `target_commit = merge_sha`, `target_tree`, `tag`, `prerelease`, `release_body` + `release_notes_sha256`, `post-merge-ledger.patch` bytes digest `ledger_patch_sha256`, `ledger_commit: {author, committer, dates}` fixed so the resulting commit id is deterministic and recorded as `ref_updates[].new`, `ref_updates: [{ref: refs/heads/main, expected_old: merge_sha, new}]`, `remote_origin`, `remote_push_url` — canonicalised through `lib/jcs.sh` for the approval digest, and a separate mutable `progress` file for publish state. `--publish`: refuse a schema_version 1 candidate with a regeneration instruction (`--allow-v1` with a logged reason is the only exception); verify the digest; verify `git merge-base --is-ancestor <merge_sha> <remote main>` (equality is not required: a later merge must not make the candidate unpublishable); re-verify the ancestry immediately before each externally visible step; tag the merge (an existing tag is accepted only when its target and release identity match the candidate, else refusal); create the release (an existing release accepted on the same identity match); then the ledger step, whose patch is validated to touch only `grimoires/loa/ledger.json` and to express the cycle's active → archived transition: apply the patch onto the observed remote `main` in a detached worktree with the recorded identity, push with `--force-with-lease=refs/heads/main:<observed sha>`; a lease failure records `ledger_commit: deferred` and `--publish --ledger-only` completes it later (re-applying onto the then-current `main`), or `archive-cycle.sh` discovers the deferred patch under `.run/post-merge-ledger-deferred.json` and applies it with the same lease rule; the recovery state machine re-runs each phase only when its post-condition is unmet and accepts remote `main` at the original merge or at the published ledger commit. Sprint 1 reads `branches/main/protection` with the operator token and records whether a direct fast-forward is permitted (if not, the deferral path is the documented default). Exit codes follow §5.4.

**C-4 Framework ergonomics (FR-4; D-1.4 DEC-0841, D-1.5 DEC-0842).** `record-branch.sh`: `--cycle N --head SHA --prev REF --stage LABEL [--manifest FILE] [--add PATH]… [--dry-run] [--accept-scan TREE_SHA]`; the default manifest is derived from the ledger cycle (its a2a sprint dirs, `a2a/audits/<dates>`, `flatline`, `prompts`, NOTES, `archive/notes`, results roots `evals/results/ablation-2.0/<cycle batches>` minus `sandbox/ snapshots/ grading/pr/`, a record_lite tree); symlinks and any path resolving outside the repository are refused before staging (the check walks the complete final tree, inherited `head` entries and the lite tree included); `GIT_INDEX_FILE` temp index → `read-tree <head>` → `add -f` → `write-tree`; the secret scan runs over the paths that differ between `<head>` and the staged tree (`git diff-tree -r --name-only <head> <tree>`, exported to a bounded temporary directory) with `audit-secret-redaction-scan.sh`; credential-shaped classes stop the build unconditionally (exit 2), other classes stop unless `--accept-scan <that tree sha>` names this tree, and the acceptance (`scan_tree`, `accepted_scan`) goes into the commit message and the manifest; `commit-tree -p <prev> -p <head>`; `update-ref <record ref> <new> <expected old>` (compare-and-swap against the previous record); the push stays the operator's ICE call. `notes-guard.sh cmd_rotate`: build the retained file section by section in the template's order — `## Blockers` and `## Active Sub-Goals` whole, `## Session Continuity` newest block whole, `## Decision Log` newest three blocks, `## Session Log` newest 20 entries — then the archive pointer; a section whose header is missing from the source is emitted with its header and no body. `pre-compact-marker.sh`: read `.state` and `timestamps.last_activity`; RUNNING → active; HALTED, INTERRUPTED → awaiting resume; COMPLETED, JACKED_OUT, an absent or unreadable file, an unknown state, or `last_activity` older than `LOA_HOOK_LIVE_WINDOW_DAYS` (7) → silent. `dec-write-lib.sh:471`: the refusal prints `N code points (limit 160): <first 160>…`. `security-audit-scope.sh`: `--help`, `--files FILE`, `--paths P…` restrict the walk. `ledger-lib.sh validate_ledger`: `schema_version` required, `version` accepted as alias.

**C-5 CI and quarantine (FR-5; D-4.2 DEC-0852).** `tests/QUARANTINE.tsv` (`test_id\towner\texpiry\tbead\treason`); `tools/check-quarantine-expiry.sh` validates every row (the test id exists in a bats file, owner non-empty, the bead exists and is open, expiry an ISO date within one day of the row's quarantine date plus 30 (quarantine date = the UTC committer date of the commit that last wrote the row, per git blame — author dates survive rebase, cherry-pick and squash; an uncommitted row is dated today; a depth-1 CI checkout blames every line on the boundary commit, whose date says nothing about the row, so there the rule is expiry ≤ today + 31) and never more than 60 days out, no duplicate ids) and fails on an expired row, printing executed / skipped / quarantined counts; `tests/unit/helpers/quarantine.bash` skips a listed test with the reason and refuses a row whose test id does not match the running test; at most 4 of the 10 bd-tgn04 failures may be quarantined at Sprint 1 exit, the rest repaired; the isolation, egress-denial and mount-provenance tests (C-9, C-10) may never appear in the file (the helper refuses them by name pattern). `bats-tests.yml`: the pytest step globs `evals/analysis/*/tests`; the quarantine step runs before the unit suite; the tripwire `tests/unit/lint-walk-excludes-fixtures.bats` plants a known violation under `evals/fixtures/review-prs/pr-99/` in a temp copy and asserts that `check-no-swallowed-jq.sh` and every `find "$ROOT"` lint walk report zero for it. `.gitattributes` gains `evals/fixtures/review-prs/pr-*/**` (the frozen PR trees only — `corpus.tsv`, `labels/`, `manifests/`, `incidents/` stay reviewable; Sprint 272 implementation decision, see decisions.yaml) and `grimoires/loa/reports/ablation-2.0/*-grades/**` and `grimoires/loa/reports/ablation-2.0/*-grades/** linguist-generated -diff` (the workflows `merge=ours` rule untouched; `-diff` also hides these paths in local `git diff`, intended for frozen fixtures and noted in the harness README).

**C-6 Session library (FR-6; D-2.1 DEC-0843).** `lib/session-exec.sh`: `price_for` prints `ERR` and returns non-zero when the model id is absent from the table or any of `in/out/cr/cc` is null, negative or non-finite; `price_events` prints `ERR` and returns non-zero on jq failure, an invalid token count or a completed assistant turn without usage; callers check both the sentinel and the status (`blind-session.sh`: no launch; `pipeline-run.sh`: stop the phase, `status infrastructure_error`, reason `metering_incomplete`); zero prices pass; metering rules: every attempt is priced (streaming deltas summed per message id, cached-read and cache-write tokens priced by their own rates, an interrupted turn priced on the usage received, a refusal rerun priced as a second attempt), and an attempt that consumed tokens without a usage event is persisted as an `unmetered_attempt` row so accounting failure is distinguishable from zero spend. `ENV_SHIM` lists `/proc/self/fd` and closes every descriptor above 2 except the listing handle and any descriptor named in `LOA_KEEP_FDS` (default empty, documented); when `/proc` is unavailable it falls back to `os.closerange(3, hard RLIMIT_NOFILE)` and, for an infinite or unusable hard limit, to a fixed 1,048,576; a subprocess test inherits a descriptor above 65535. Startup assertion `assert_secret_keys`: `SECRET_KEY_PATTERN='(KEY|TOKEN|SECRET|PASSWORD|PASS|CREDENTIAL|AUTH)'` (a documented constant with its own unit vector) over `PASS_KEYS`; a match must be in `SECRET_KEYS` or `NON_SECRET_ALLOWLIST`. `pipeline-run.sh` sources the lib by a literal relative path (eval.yml trust boundary) and its bats harness stages `lib/`; the drift test is kept until the Sprint 3 smoke is green on the measurement pin, then deleted in a versioned commit.

**C-7 Reproduction and analysis (FR-7; D-2.2 DEC-0844).** `reproduce.sh`: `pinned_trees_identical_to_worktree` = `git diff --quiet <pin> -- evals/harness evals/suites evals/fixtures <suite>/tasks <suite>/MANIFEST.sha256 evals/analysis/c132` plus `git status --porcelain -- <same>` empty; `git describe --always --dirty` recorded; exit table 0/1/2/3; `--live-sample` requires rc 0 and a matched environment, reads the registration hash from `$REG`, filters the recorded range to valid rows, marks the live table with the environment verdicts. `record_lite.py`: `sha256_file(path, verify=True)` bypasses the cache on verification paths; `safe_rel` on symlink targets; REPRODUCE.md names `INDEX.json` / `INDEX-only.json`. `judge_defects.py`: `sample_id = sha256(key.json without the field)[:12]` written into every packet header and `labels.json`; `write_sample` refuses an existing `key.json` without `--force`; `aggregate` rejects a mismatched `sample_id` and loads grades for validity; `run-judge-defects.sh` chunk dir keyed by the key sha. `final.sh`, `run-judge-defects.sh`: `REG`, `PIN`, `REG_SHA` parsed by whitelist from `registration.txt` or passed as flags; root from `BASH_SOURCE`. Power-mini fixtures generated in a pytest fixture by `synth.py --seed 20261023`. `spend.sh` dedups anonymous rows by `(run_id, batch)`. The new tooling replaces the same paths on `main`; reproducing cycle-132 (including `--live-sample`) runs from a worktree checked out at pin `fbd36a0c`, and the new `REPRODUCE.md` says so; the record branch's copies are untouched.

**C-8 Grader 1.4 and refusal policy (FR-8; D-2.3 DEC-0845).** `ablation-grade.sh` 1.4: class 7 exempts a heredoc-written report whose quoted token is PR-native (the same exemption the Write tool path already has); `outside_path` exempts the container-mode bare `/home` probe shape; per-class fixtures. Suite key `refusal_policy: exclude | keep | rerun-once` per arm (default `exclude`); `run-ablation.sh` writes `refusal_policy_applied` and `attempt` beside `refusal_fallbacks` in every row and, for `rerun-once`, relaunches the trial once with the same plan index, retaining the refused attempt's transcript and meta and charging both attempts. Outcome rules: `exclude` — a row with a fallback is invalid (cycle-132 behaviour) and the denominator excludes it; `keep` — the row is valid and flagged and the denominator includes it; `rerun-once` — the second attempt's row is the cell when it has no fallback, else the cell is invalid; a second refusal or an infrastructure failure on the retry leaves the cell invalid with both attempts recorded. `ablation-row.sh` emits a per-arm `refusal_rate`; above 0.2 the arm is flagged in the report. The denominator rules live here and are mirrored in `evals/harness/README.md`.

**C-9 Supervisor and egress (FR-9; D-2.4 DEC-0847, D-2.5 DEC-0854).** Supervisor: `run-ablation.sh --supervised [--max-retries N]` refuses unless `loginctl show-user --property=Linger` is `yes` or the batch is launched inside a lingering scope (repair text names `loginctl enable-linger`); with `systemd-run` the batch runs as `systemd-run --user --unit loa-batch-<name> --collect`, otherwise `lib/batch-supervisor.sh` runs a `setsid` loop; the supervisor takes `flock <batch>/supervisor.lock` before daemonising and holds it; STATUS.json updates go through the runner's existing flock; it declares the runner dead on process exit or when STATUS.json has not been updated for 30 minutes while a run is marked running; before every `--resume` it stops containers named `loa-abl-<run_id>-*`; it retries only retryable classes (`infrastructure_error`, a container exit with no STATUS update) and never `metering_incomplete`, budget exhaustion, refusals (the policy owns them) or an intentional stop; ownership is durable — `supervisor: {owner_pid, boot_id, start_time, unit, attempt_id, retries: [{at, reason_class, retry_id, provider_request_ids}], cap}` — so a PID reused after a reboot is not mistaken for the owner; before a retry the supervisor reconciles uncertain provider requests from the cost ledger and terminates the whole owned process group; run arguments are persisted in MANIFEST so a reboot restores the batch; stops after `--max-retries` (default 3); tests cover reboot, PID reuse and cancellation during an active request. Egress (threat model: repository and arbitrary-destination egress from the sandbox is denied; exfiltration through the allowlisted model API is out of scope and left to the class-9 tripwire, stated in the README): `lib/egress-proxy.sh up|down|self-check` creates a docker internal network `loa-egress-<batch>` and a sidecar `loa-proxy-<batch>` (tinyproxy 1.11, `Dockerfile.proxy`) attached to the internal network and to an external one; the allowlist is generated from a new `egress_hosts[]` per provider in `model-config.yaml` (model endpoints plus auth and token-refresh hosts such as `sts.amazonaws.com`, `auth.openai.com`); the proxy validates every CONNECT and plain HTTP destination by resolved address at connect time against the allowlist and denies private, loopback, link-local and metadata ranges, restricts CONNECT to port 443, and re-validates on redirects; the sandbox runs `--network loa-egress-<batch> --dns 0.0.0.1` (DNS sinkholed; the proxy resolves) with `HTTPS_PROXY/HTTP_PROXY=http://loa-proxy-<batch>:8888`, `NO_PROXY=`; each run's container address is recorded in meta at launch and denials are attributed by source address into `<run>/meta/egress-denied.jsonl`; `self-check` exercises an allowed model call per planned model, a direct connection attempt, DNS, denied HTTP and CONNECT, alternate hostname encodings and denial attribution, and `down` removes the network and sidecar. The suite key `egress: blocked | bridge` per arm (default blocked) is recorded in MANIFEST and meta; the open-mount control keeps `blocked` unless a batch records `bridge` as a factor. `Dockerfile.ablation` → `loa-ablation:259` (CA/proxy env defaults; the Claude Code version pinned and recorded in MANIFEST); the isolation and egress-denial tests are release gates that QUARANTINE.tsv may not list.

**C-10 Loa reviews Loa (FR-10; D-3.1 DEC-0848 as amended by D-3.6 DEC-0858).** Design (a′) in `lib/sandbox-mount.sh` as a new mount mode `home-scope`: the pinned framework is materialised under the sandbox HOME (`$HOME_DIR/.claude/{CLAUDE.md,settings.json,skills/,scripts/,hooks/,rules/,…}`, `CLAUDE.md` importing `~/.claude/loa/CLAUDE.loa.md` by absolute path, every hook `command` and every framework script or skill reference to `.claude/` resolved through one root variable set by the mount — audited once across hooks, skills and scripts in the spike), the session launched with settings restricted to the user scope (`--setting-sources user` or the equivalent the spike confirms) and the project trust accepted; the workspace root receives `overlay_answer_paths` for every changed `.claude/` path of the PR except the executable and prompt surface — `.claude/skills/`, `commands/`, `agents/`, `hooks/`, `settings.json`, `settings.local.json`, `*.local.*` under `.claude/`, `.claude/rules/**`, `.claude/CLAUDE.md`, the root `CLAUDE.md` and `CLAUDE.local.md`, `.mcp.json`, `.claude/output-styles/`, `.claude/plugins/`, and any file an `@` import in those names — the list is derived from the pinned Claude Code version's documented load paths and re-derived when that version changes — which is removed from the root and stays readable under `pr/head/`; `check_mount_closed` clause (e): every surface path is absent at the root and every other changed `.claude/` path at the root hashes to the PR's bytes. `took-effect.sh oracle_closed` gains clause (e) and a positive read clause (f): the transcript parser (versioned, `transcript_schema` recorded) collects Read results (gutter stripped, offset/limit windows concatenated) and Grep results per path; a changed PR `.claude/` file counts as read when the normalised Read content covers at least 60 % of its lines or the whole file, hashed line-set against the PR bytes (Grep alone never counts); `pr_bytes_read: [paths]` must be non-empty and cover every changed `.claude/` file the review's findings cite; a clause (g) asserts no project hook, MCP server or planted canary executed (process list, hook log, canary side effect). The grader's `oracle_scan` keeps firing on pinned-byte reads; the negative-control fixture holds distinct PR and pinned bytes for the same path and the cycle-132 mount must still fire. **Spike (first task of Sprint 3, ≤ USD 2):** in `loa-ablation:259` with its Claude Code version recorded, `claude -p` with the HOME-scope layout and a planted canary for every surface item (hook, skill, command, agent, settings, `.mcp.json`, root `CLAUDE.md`, `.claude/rules/` file, an `@` import, a `.claude/scripts/` file at the root) must show the pinned skill loaded and no canary loaded or executed: each canary has a deterministic filesystem effect (a marker file it would write) and the session runs under process-execution capture (hook log, a one-second `ps` sampler, `LOA_CANARY` markers); the spike runs inside the egress block with its own `--max-usd 2`, records the image digest, Claude Code version, scope flags, effective settings and framework content hashes, and is repeated if any of those inputs change before the smoke; an observed project-scope execution is a containment failure. **If the spike fails, the run HALTS with the spike record; adopting fallback (c) — a reviewer read contract enforced by clauses (f) and (g) with hooks, settings and `.mcp.json` still stripped from the root — is the operator's decision, never an autonomous amendment (D-3.6).**

**C-11 Finding contract and grader 1.5 (FR-11; D-3.2 DEC-0849, D-3.5 DEC-0857).** `.claude/schemas/finding.schema.json` v1: `{id, file, anchor_line, anchor_line_end?, failure_scenario, severity ∈ {CRITICAL, HIGH, MEDIUM, LOW, PRAISE, SPECULATION, REFRAME, INFO}, blocking: boolean (default false; a voice's blocking mark maps here), confidence ∈ {high, medium, low} (a number 0–1 normalises: ≥ 0.75 high, ≥ 0.45 medium, else low; validators emit the enum), title?, suggestion?}`; `id` is given, else derived `F-<first 6 hex of sha256(file:anchor_line:title)>`; `file` is repository-relative POSIX with no `..` or leading `/`; anchors are positive integers with `anchor_line_end ≥ anchor_line`. `failure_scenario` rule for defect severities (CRITICAL, HIGH, MEDIUM, LOW): at least 12 whitespace-separated tokens or a `when … then …` shape, none of the denylist (`TODO`, `n/a`, `see above`, `as described`, `placeholder`); PRAISE, INFO, REFRAME and SPECULATION are exempt. Markdown grammar for review/audit bullets: `- **SEV** (confidence: c) \`file:line[-end]\` <dash> <title>. Failure: <scenario>.` where the dash is any of `—`, `–`, `-`, `--` and the clause starts at the last `Failure:` token outside backticks. `verdict-derive.sh`: a defect-severity bullet without a valid clause is a violation; **a CRITICAL, HIGH or `blocking` bullet without a valid clause is still counted in the blocking tally**, so the file is inconsistent and can never derive APPROVED (red test: one malformed CRITICAL bullet must not yield APPROVE). Shared conformance vectors under `.claude/schemas/finding.vectors/{valid,invalid}/*.json` are run by the zod suite, the jq/bash validator and the python validator and must agree. The reviewing-code and auditing-security templates and the Bridgebuilder persona emit the clause; `adversarial-finding.schema.json` and `FindingsBlockSchema` reference the canonical schema; aliases `failure_mode`, `description` normalise (precedence: `failure_scenario` > `failure_mode` > `description`) with the warning "`failure_mode` is an alias of `failure_scenario`; removed in 2.1.0"; both present and different → rejected. `ablation-grade.sh` 1.5: `--judge-verdicts FILE` (JSONL: `{finding_id, finding_sha256, defect_key, fixture_sha256, grader_version, verdict ∈ {describes, does_not_describe}, judge_model, judge_prompt_sha256, blind, ts, supersedes?}`); eligibility: credited pairs of valid cells under grader 1.5; pair key `(run_id, finding_id, defect_key)`; hashes are JCS of the canonical finding and of the fixture manifest; a duplicate verdict for a pair is refused unless the later row names the earlier in `supersedes`; `blind: false` rows are excluded from `recall_judged` and reported in `recall_judged_unblind`; stale hashes or version → the run is rejected; outputs `recall_judged`, `judged_pairs`, `unjudged_pairs`, provenance (judge model, prompt hash) in `grade.json`. `reads-c132.py --judge-defects` registers the read under a new chain version (`registration.py` schema v2).

**C-12 External seeder and registration v2 (FR-12; D-3.3 DEC-0851).** `lib/corpus-seed.sh` extracted from `seed-corpus-from-record.sh` (fixture layout, labels grammar, exposure block, SHA256SUMS freeze, corpus.tsv row); `seed-corpus-from-external.sh <repo-url> <pr> --fix <sha>|<range> [--incident REF] [--licence SPDX] [--commit-trees] [--dry-run] [--check]`: accepts `https://` URLs only, strips credentials and logs the sanitised form; reads the PR's base and head SHAs through `gh api` and verifies them against the clone; `base/` is the fix commit's parent (`fix^`, or the range start's parent) and `head/` the PR head, with the relation `head ⊂ fix^..fix` checked; limits (`--max-files 5000 --max-bytes 200M`) are checked from tree metadata (`git ls-tree -r -l`) before any blob is fetched; clones with `--filter=blob:none --no-recurse-submodules`, materialises with `git archive` (no hooks run), refuses symlinks, submodules and non-regular entries before extraction, bounds the fix-diff size; `PR.md` is built from the PR title and body only and the leakage test refuses when any added or removed fix-diff line of at least 20 non-whitespace characters (whitespace-normalised, a stop-list of braces, blank lines and import lines excluded) appears in it, reporting the matching lines; the same scanner as C-4 runs over the materialised trees; licensing uses the GitHub license API SPDX id (a conflicting declaration or a missing licence refuses; `--licence` cannot override contrary evidence) and `--commit-trees` commits the upstream LICENSE/NOTICE files and an attribution row with the fixture, otherwise a fetch manifest with hashes is written; `--dry-run` leaves only the temp tree and a report. `registration.py` v2: optional `looks_seen: [{look, suite, registration_sha256, rows_sha256}]`, strictly increasing look index, no self-reference, each entry validated against the committed looks inventory (`<reports>/c*-looks/*/rows.jsonl`) and completeness verified against that inventory, not merely declared; v1 documents verify unchanged. Guidance: `evals/harness/README.md` § Shipping a measurement cycle (four PR kinds, when one PR is acceptable) and `planning-sprints/resources/REFERENCE.md` pointer.

**C-13 Beads sweep (FR-13; D-4.1 DEC-0850).** `.claude/scripts/beads/sweep-inventory.sh` exports the open beads to `grimoires/loa/a2a/sprint-<N>/sweep/inventory.jsonl` with its sha256 (the frozen snapshot); Explore batches (≤ 40 beads, read-only) return `manifest-<k>.jsonl` rows `{id, category ∈ {closed-implemented, closed-obsolete, kept, pulled-in}, evidence, confidence}`; category → action: closed-implemented → `br close --reason "implemented: <evidence>"`; closed-obsolete → `br close --reason "obsolete: <evidence>"`; kept → `br label add backlog-2026-10` + status comment + review-by date; pulled-in → `br label add sprint:<n>` + comment; `sweep-apply.sh` validates every manifest row (id in the snapshot and still open, each id once, evidence a resolvable reference — a commit sha in the repository, a PR number, or a path that exists at head — for both closure categories) and writes an append-only `applied.jsonl` so a re-run skips applied rows; the manifests must form a complete partition of the frozen inventory (duplicate, missing, unknown or conflicting ids are rejected before any mutation; an inventory above seven batches of 40 gets more batches); `sweep-sample.sh` draws `ceil(10 %)` of the proposed closures with seed 20261023 for the second Explore BEFORE anything is applied, and a disagreement sends that batch back for a re-sweep; `applied.jsonl` keeps every mutation reversible (`br reopen` with a comment); the report table counts the five categories (opened-during-cycle from the ledger) and names the sample result.

**C-14 Release (FR-14).** CHANGELOG `[Unreleased]` → `## [2.0.0-rc.8]`; `update-loa-bump-version.sh --target 2.0.0-rc.8` under the zone marker; checksums; README pin; release notes; the PR; the Bridgebuilder built from the cycle branch reviews it; CI; admin merge; `record-branch.sh --stage "stage 1"`; publish through C-3; `archive-cycle.sh --cycle 133`.

### 1.5 Data Flow

PR → C-1 pages → selected patches → voices → consensus → C-2 guard → posted review + verdict JSON. Merge → C-3 candidate (merge-targeted, ledger patch) → publish → tag, release, ledger ff. Batch → C-9 supervisor → runner → sandbox (internal net, proxy) → transcripts → took-effect (clauses a–f) → grader 1.4/1.5 → rows → reads (registration v2). Gate outputs → C-11 schema → validators → trailers. Tracker → C-13 inventory → manifests → applied closures → report.

### 1.6 External Integrations

GitHub REST through `gh` (PR metadata, paged files, reviews, releases, conditional ref update via `git push --force-with-lease`); Docker 26.1.5 (sandbox, internal network, proxy sidecar); systemd user units; model endpoints through the proxy allowlist; the beads CLI `br`.

### 1.7 Deployment Architecture

Host: the lead's checkout (worktrees per implementer under `../loa-wt-s<N><letter>`), `~/.cache/loa/cycle-133/` for logs, patches and briefs. CI: `bats-tests.yml` (unit bats, analysis pytest glob, quarantine expiry, lint tripwire, Bridgebuilder vitest and `check-bb-dist-fresh`); container bats run in the Docker 26.1.5-enabled job or locally with a dated quarantine row. Container: `loa-ablation:259` plus the proxy sidecar image.

### 1.8 Scalability Strategy

Per-page processing bounds Bridgebuilder memory by page, not by PR size; the supervisor and the proxy are per batch; the sweep is batched at 40 beads per subagent.

### 1.9 Security Architecture

PR-supplied `.claude/` content is data only (C-10: executable surface absent at the root, framework in HOME scope, settings restricted to user scope; the spike proves it before use). Egress default-deny through the proxy with denial logs (C-9). The writer has no tools and its output is validated semantically (C-2). Credential-shaped secret hits are non-bypassable in the record build (C-4). Metering fails closed (C-6). The refusal list of PRD § Authorization basis binds every automated git and GitHub action; `--force-with-lease` is the only write to `main` and only inside publish.

> Sources: prd.md FR-1 … FR-14 and the file:line reads it cites; `github-cli.ts:235-277`, `review-verdict.ts:12-57`, `multi-model-pipeline.ts:882-940`, `truncation.ts:1140-1175`, `post-merge-orchestrator.sh:998-1046, 1360-1400, 1455-1520`, `notes-guard.sh:222-255`, `pre-compact-marker.sh:35-39`, `session-exec.sh:21-68`, `blind-session.sh:286-332`, `pipeline-run.sh:120-170, 960-1000`, `sandbox-mount.sh:85-140`, `took-effect.sh:39-72, 400`, `ablation-grade.sh:154-319, 2492-3240`, `run-ablation.sh:1332-1344`, `seed-corpus-from-record.sh:25-90`, `registration.py:204-258`, `claude_headless_adapter.py:136-155`, `codex_headless_adapter.py:18-114`

---

## 2. Software Stack

### 2.1 Frontend Technologies
None (CLI, GitHub comments, markdown reports).

### 2.2 Backend Technologies
Bash 5.2 (scripts, harness, hooks); Python 3.13.5 standard library only (analysis, record tooling, grader helpers); Node.js 22.22.2 with TypeScript 5.9.3 and zod 4.3.6 for the Bridgebuilder skill (vitest for tests; `dist/` compiled and tracked); jq 1.7 and yq 4.44.1 for JSON/YAML; git 2.47.

### 2.3 Infrastructure & DevOps
Docker 26.1.5 (ablation image 259, proxy sidecar tinyproxy 1.11); systemd user units for supervised batches; GitHub Actions (`bats-tests.yml`, `post-merge.yml`); bats 1.13.0 (`npx --no-install bats` locally).

> Sources: tool versions read on the host 2026-10-23; `.claude/skills/bridgebuilder-review/package.json`; `.github/workflows/bats-tests.yml`

---

## 3. Database Design

### 3.1 Database Technology
None. State lives in tracked files and JSON/TSV artefacts.

### 3.2 Schema Design

| Artefact | Owner | Shape |
|---|---|---|
| `post-merge-candidate.json` v2 | C-3 | sealed: v1 fields + `ledger_patch_sha256`, `release_notes_sha256`, `ledger_commit{author,committer,dates}`, `ref_updates[]`, `target_on_main: true`; mutable `progress` file beside it |
| `tests/QUARANTINE.tsv` | C-5 | `test_id, owner, expiry (ISO date), bead, reason` |
| `finding.schema.json` v1 | C-11 | see C-11 |
| judge verdicts JSONL | C-11 | `finding_id, finding_sha256, defect_key, fixture_sha256, grader_version, verdict, judge_model, blind, ts` |
| `REGISTRATION-N.json` v2 | C-12 | v1 + optional `looks_seen[]` |
| STATUS.json `supervisor` | C-9 | `owner_pid, unit, retries[{at, reason, retry_id}], cap` |
| MANIFEST.json `egress`, `refusal_policy` | C-8, C-9 | per arm |
| record manifest | C-4 | `{cycle, head, prev, stage, paths[], results_roots[], lite_tree, scan_tree, accepted_scan[]}` |
| sweep inventory / manifests | C-13 | `{id, title, labels, created}` / `{id, category, evidence, confidence}` |
| coverage record (BB) | C-1 | `{base_sha, head_sha, reviewed[], omitted[{file, reason}]}` |

### 3.3 Data Modeling Approach
Append-only where a record is evidence (rows, registrations, candidates); replace-in-place only for derived state (STATUS.json, caches).

### 3.4 Migration Strategy
Candidate v1 files remain publishable (the v1 path is kept behind `schema_version`); registration v1 verifies unchanged; the finding aliases normalise until 2.1.0.

### 3.5 Data Access Patterns
jq/yq reads; Python `json`; no concurrent writers except STATUS.json under the runner's flock.

### 3.6 Caching Strategy
`record_lite.py`'s digest cache is build-side only (verification paths hash afresh).

### 3.7 Backup and Recovery
Record branches and the archive directory are the backups; the publish sequence is resumable; the supervisor resumes batches.

> Sources: prd.md § Technical Considerations; `post-merge-orchestrator.sh:1455-1500`; `run-ablation.sh:1332-1344`

---

## 4. UI Design

### 4.1 Design System
Plain text: CLI output with `exit 2` refusals naming the repair and `exit 3` degradations naming the reason; GitHub comments in the existing Bridgebuilder layout plus a coverage table.

### 4.2 Key User Flows
See §1.5 and prd.md § User Experience.

### 4.3 Page/View Structure
Bridgebuilder comment: `[1/3] … [3/3]`, the consensus block, a `## Coverage` table (reviewed, omitted with reasons), the verdict line.

### 4.4 Component Architecture
Not applicable.

### 4.5 Responsive Design Strategy
Not applicable.

### 4.6 Accessibility Standards
No colour-only signalling; every refusal is a sentence with the repair.

### 4.7 State Management
Run state in `.run/*.json` as today; the hook reads it (C-4).

> Sources: prd.md § User Experience

---

## 5. API Specifications

### 5.1 API Design Principles
Flags over environment variables for new behaviour; every new flag documented in the script header; refusals before any write.

### 5.2 Endpoints

| Interface | Signature | Notes |
|---|---|---|
| `record-branch.sh` | `--cycle N --head SHA --prev REF --stage L [--manifest F] [--add P]… [--dry-run] [--accept-scan TREE]` | exit 0 built; 2 usage/refusal; 3 scan hit |
| `reproduce.sh` | as today + exit 0/1/2/3 table | `--live-sample` needs rc 0 and a match |
| `run-ablation.sh` | `--supervised [--max-retries N]` | STATUS.json `supervisor` |
| `lib/egress-proxy.sh` | `up <batch> <allowlist-file>` / `down <batch>` / `self-check <batch>` | self-check runs the denial tests |
| `seed-corpus-from-external.sh` | `<repo-url> <pr> --fix SHA|RANGE [--incident R] [--licence SPDX] [--commit-trees] [--dry-run] [--check]` | exit 0; 1 refused (licence, leakage, limits); 2 usage |
| `ablation-grade.sh` | `--judge-verdicts FILE` | grader 1.5; `recall_judged`, `unjudged_pairs` |
| `post-merge-orchestrator.sh` | `--generate` (candidate v2) / `--publish FILE --approve-sha256 HEX` | remote-main check; `--force-with-lease` ledger ff |
| Bridgebuilder config | `gh_max_buffer_bytes`, `writer_role_allowlist`, default `exclude_patterns` | `.loa.config.yaml bridgebuilder:` |
| GitHub endpoints | `pulls/N`; `pulls/N/files?per_page=100&page=K`; reviews; releases | no `--paginate` on files |
| `verdict-derive.sh` | unchanged flags; new violation class `finding-without-failure-clause` | |
| `registration.py` | v2 `--looks-seen JSON` (optional) | v1 verifies |
| `sweep-inventory.sh` / `sweep-apply.sh MANIFEST` / `sweep-sample.sh` | | manifests under `a2a/sprint-275/sweep/` |

### 5.3 Contracts
`finding.schema.json` v1 is the contract every gate validates against; the markdown grammar is its textual projection.

### 5.4 Exit codes (authoritative for every script this cycle touches)

| Code | Meaning | Examples |
|---|---|---|
| 0 | completed as asked | review posted and complete; publish done; record built; fixture seeded |
| 1 | a step failed or a named difference | reproduce.sh difference; a publish phase failed after a write |
| 2 | refusal before any write (usage, precondition, policy) | record-branch scan hit; seeder licence or leakage refusal; `--supervised` without linger; v1 candidate; dirty worktree for the attestation |
| 3 | completed, degraded, reason named | Bridgebuilder `degraded_reason`; `writer_not_eligible`; reproduce.sh live sample requested but not run |

The §5.2 rows for `record-branch.sh` (scan hit → 2) and `seed-corpus-from-external.sh` (refusals → 2) follow this table.

> Sources: §1.4; prd.md FR-1 … FR-14

---

## 6. Error Handling Strategy

### 6.1 Error Categories
Refusal (exit 2: usage, precondition, policy) before any write; degraded (exit 3: review completed but incomplete, with `degraded_reason`); failure (exit 1: a named difference or a failed step); fail-closed sentinels (`ERR` in pricing).

### 6.2 Error Response Format
One stderr line naming the condition and the repair; JSON summaries carry `degraded`, `degraded_reason`, `mergeBlockedReason`.

### 6.3 Logging Strategy
Egress denials to `meta/egress-denied.jsonl`; supervisor retries to STATUS.json; publish steps to the candidate's `phases`; record-branch scan results to the commit message.

> Sources: prd.md § Non-Functional Requirements; `.claude/protocols/agent-ergonomics.md`

---

## 7. Testing Strategy

### 7.1 Testing Pyramid
Unit: vitest (C-1, C-2), bats (C-3 … C-9, C-11, C-13), pytest (C-7, C-11, C-12). Integration: the container bats (C-9, C-10) in the Docker 26.1.5-enabled CI job or a dated quarantine; the Sprint 3 smoke (one `a1_full` trial). System: the cycle's own PR reviewed by the fixed Bridgebuilder; the rc.8 publish.

### 7.2 Testing Guidelines
Every defect gets the test that reproduces it before the fix (red → green, `red-test-check.sh`); fixtures are generated deterministically; no network in unit tests (mocked `gh`, mocked model adapters).

### 7.3 Traceability matrix (defect → reproducing test → component)

| Defect / requirement | Test | Component |
|---|---|---|
| KF-054 large-PR Fatal | `__tests__/paged-fetch.test.ts` (2,000 and 3,001 files; head moved; oversize patch) | C-1 |
| KF-055 writer transcript; UNKNOWN verdict | `__tests__/enrichment-guard.test.ts`, `review-verdict.test.ts` (round replays) | C-2 |
| rc.6/rc.7 unreachable tags | `tests/unit/post-merge-publication.bats` (ancestor precondition, lease, deferral, v1 refusal, idempotent re-run) | C-3 |
| record built by hand each cycle | `tests/unit/record-branch.bats` (refusals, credential hit, CAS) | C-4 |
| NOTES rotation drift; stale simstim; dec-write length; scope help; ledger validator | `tests/unit/{notes-guard-rotate,pre-compact-liveness,dec-write-length,security-audit-scope,ledger-validate}.bats` | C-4 |
| ten failing unit tests; analysis pytest absent from CI | `tests/QUARANTINE.tsv` + `check-quarantine-expiry` tests; CI run | C-5 |
| fail-open pricing; descriptors; secrecy | `evals/tests/session-exec.bats` | C-6 |
| attestation of the wrong tree; live sample ungated; sample binding; digest cache | `evals/analysis/c132/tests/test_{reproduce,record_lite,judge_defects}.py` | C-7 |
| two benign shapes; refusal policy | grader 1.4 fixtures; `evals/tests/refusal-policy.bats` | C-8 |
| dead batches; repository egress | `evals/tests/batch-supervisor.bats`, `egress-proxy.bats` (container job; never quarantined) | C-9 |
| oracle exposure on `.claude/` PRs | `evals/tests/sandbox-mount-home-scope.bats`; the smoke; the negative control | C-10 |
| findings without a scenario | conformance vectors across four validators; `verdict-derive-failure-clause.bats` | C-11 |
| corpus from Loa's own history | `evals/tests/seed-corpus-from-external.bats`; three dry-runs | C-12 |
| 310 open beads | `sweep-apply` validation tests; the sample | C-13 |

Egress precondition: the complete container egress suite passes on the actual image, network and endpoints before the intermediate pin is recorded and before the spike or the smoke launches — on the operator host when the Docker CI job is unavailable, with the bats output and `meta/egress-denied.jsonl` attached as evidence; a quarantine row never satisfies it. Smoke pass criteria (Sprint 3): took-effect clauses (a)–(g) satisfied; `oracle_exposed_defects` 0 and `pr_bytes_read` covering every changed `.claude/` file the findings cite; `grade.json` under grader 1.5 with the measurement pin recorded; spend within the USD 40 share (spike ≤ 2 inside it; one verification rerun reserved for a fix); a launch is a session that reached the model (spend above USD 0.50) — an infrastructure abort below that may be relaunched within the share; a failed smoke leaves G-4 incomplete, blocks the drift-test deletion and the FR-10 release claim, and the feature is deferred with a DEC row rather than claimed. Mandatory release gates that may never be quarantined: egress isolation, mount provenance (clauses e–g), writer tool disabling, the finding-clause blocking rule.

### 7.4 CI/CD Integration
`bats-tests.yml`: analysis pytest glob, quarantine expiry gate, lint tripwire, Bridgebuilder vitest + `check-bb-dist-fresh`, unit bats; `post-merge.yml` prepares the candidate v2.

> Sources: prd.md § Non-Functional Requirements / Reliability; `.github/workflows/bats-tests.yml:170-200`

---

## 8. Development Phases

### Sprint 1 (global 272) — the framework's own defects
Implementers in parallel: A — C-1 + C-2 (Bridgebuilder, vitest, dist rebuild); B — C-3 (publish, candidate v2, bats) plus the branch-protection read recorded in the sprint report; C — C-4 (record-branch.sh, notes-guard, hook, dec-write, scope, ledger validator; bats); D — C-5 (CI glob, quarantine mechanism, the ten failing tests with at most four quarantined, gitattributes + tripwire). Exit: review and audit APPROVED; CI green including the analysis pytest; `tests/unit` green.

### Sprint 2 (global 273) — harness and reproduction hardening
A — C-6 (session lib; first, the others rebase on it); B — C-7 (reproduce, record_lite, judge_defects, drivers, synth, spend); C — C-8 (grader 1.4, refusal policy); D — C-9 (supervisor, egress proxy, image 259). Exit: bats/pytest green; the intermediate pipeline version recorded (the Sprint 2 head, image 259 digest, self-check log).

### Sprint 3 (global 274) — the product
Spike first (C-10 scope facts in the image with a canary per surface item, ≤ USD 2; a failure HALTS the run for the operator, D-3.6); then A — C-10 mount mode + clauses (e)–(g); B — C-11 schema, grammar, validators, templates, grader 1.5; C — C-12 lib extraction, external seeder, registration v2, guidance; then the lead records the measurement pin (the Sprint 3 head after A–C land, D-3.4) and A runs the smoke (≤ USD 30) at that pin; D — the drift-test removal after the smoke and the harness README. Exit: the smoke's grade at the recorded pin; the four validators; three dry-runs.

### Sprint 4 (global 275) — hygiene and ship
A/B — C-13 sweep (seven Explore batches, apply, sample); lead — docs, CHANGELOG, rc.8 bump, PR, Bridgebuilder, merge, record, publish, archive.

> Sources: prd.md § Timeline & Milestones; D-8 (DEC-0834)

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Claude Code scope facts do not support design (a′) (project skills or hooks still load) | the Sprint 3 spike runs first; fallback (c) is specified in C-10; D-3.1 amended |
| `--force-with-lease` push to `main` blocked by branch protection for the token | Sprint 1 reads the protection rules and records the answer; the ancestor precondition and the deferral path keep the tag valid either way |
| The spike fails and the fallback would change the threat model | the run HALTS; the choice of (c) is the operator's (D-3.6) |
| Proxy allowlist misses an endpoint (model fallbacks, auth and refresh hosts) | `egress_hosts[]` per provider in the registry; `self-check` runs one request per planned model before the batch |
| Bridgebuilder `dist/` drift | rebuild in the same commit; `check-bb-dist-fresh` |
| The ten unit failures hide deeper regressions | repairs preferred; quarantine rows expire at the next cycle's close |
| Sweep false closures | evidence rule, manifest review, 10 % sample, `backlog-2026-10` when unsure |
| Dissent voice budget on large sprint diffs (KF-004) | code-only diffs per implementer; ≤ 3 runs per sprint |

> Sources: prd.md § Risks & Mitigation; KF-004, KF-034, KF-041, KF-054, KF-055

---

## 10. Open Questions

| Question | Status | DEC |
|---|---|---|
| Does `--setting-sources user` (or an equivalent) exclude project-scope hooks, skills, `.mcp.json` and the root CLAUDE.md in the image's Claude Code version? | Unresolved — the Sprint 3 spike answers it with a canary per surface item; a failure HALTS for the operator (D-3.6) | — |
| Can the operator token fast-forward `main` under the current branch protection without a PR? | Unresolved — Sprint 1 reads the protection rules and records the answer; the publish design does not depend on it (D-1.6) | — |
| Is codex-headless a tool-free writer? | Resolved — not by default; it joins the allowlist only after a vitest proves its native tools cannot execute | DEC-0853 |
| Is the refusal policy default `exclude`? | Resolved | DEC-0845 |
| Which commit is the measurement pin? | Resolved — the Sprint 3 head after every harness change; Sprint 2 is intermediate | DEC-0855 |

---

## 11. Appendix

### A. Glossary
Executable surface — the `.claude/` paths a session may load or run: `skills/`, `commands/`, `agents/`, `hooks/`, `settings*.json`. HOME scope — the user-level Claude Code configuration under the sandbox HOME. Degraded — a completed review or run that names what it omitted. Sentinel — the `ERR` value the pricing helpers return on any failure.

### B. References
PRD 1.1 and the file:line reads listed in §1.9 Sources; cycle-132 report § Honest caveats; PREREGISTRATION addendum 9; KF-041, KF-051 … KF-055; PR #1289 Bridgebuilder rounds (`a2a/sprint-271/bridgebuilder/` on the record branch).

### C. Change Log
1.0 (2026-10-23) — initial design for cycle-133.
1.1 (2026-10-23) — Flatline SDD review integrated (16 skeptic blockers, 31 + 41 reviewer items; §11.E); D-1.6, D-1.7, D-2.5, D-3.4, D-3.5, D-3.6 added; §5.4 exit codes; §7.3 traceability and smoke criteria.
1.2 (2026-10-23) — sprint Flatline review folded (D-S.1): ledger patch restriction and identity-matched existing tag (C-3); durable supervisor identity (C-9); surface derived from the pinned Claude Code version plus output-styles and plugins, canaries with filesystem effects under process capture, spike inside the egress block (C-10); ISO quarantine expiry (C-5); sample before apply (C-13); egress precondition and smoke failure rule (§7.3).

### D. Design decisions taken on the operator's behalf
- **D-1.1** (DEC-0839) — paged, SHA-pinned Bridgebuilder fetch; per-page filtering; retained patches bounded.
- **D-1.2** (DEC-0840) — writer-role allowlist of no-tool adapters; schema and semantic-equality guard; block-derived verdict with precedence.
- **D-1.3** (DEC-0846) — publish tags the merge; ledger patch applied by a conditional fast-forward after the release, else deferred.
- **D-1.4** (DEC-0841) — `record-branch.sh` from the cycle-132 cache script: manifest, staged-tree scan, tree-bound acceptance.
- **D-1.5** (DEC-0842) — hook liveness by state allowlist and recency.
- **D-2.1** (DEC-0843) — `ERR` sentinel, `/proc/self/fd` closing, startup secrecy assertion, lib sourced.
- **D-2.2** (DEC-0844) — worktree attestation over harness, suites, fixtures and analysis; exit table.
- **D-2.3** (DEC-0845) — refusal policy suite key, default `exclude`.
- **D-2.4** (DEC-0847) — supervisor as a user systemd unit with a watchdog fallback; internal network plus proxy sidecar.
- **D-3.1** (DEC-0848) — design (a′) for Loa reviews Loa, spike first, (c) as fallback.
- **D-3.2** (DEC-0849) — canonical finding schema, markdown Failure clause, grader 1.5 judge hook.
- **D-3.3** (DEC-0851) — shared seeding lib, git-archive materialisation, SPDX allowlist, registration v2.
- **D-4.1** (DEC-0850) — sweep through inventory, manifests, lead-applied closures, 10 % re-verification.
- **D-4.2** (DEC-0852) — `tests/QUARANTINE.tsv` with CI-enforced expiry; pytest glob.
- **D-1.6** (DEC-0856) — publish precondition is ancestry, the lease applies only to the ledger fast-forward, the ledger commit is deterministic, `--ledger-only` completes a deferral, v1 candidates are refused.
- **D-1.7** (DEC-0853) — codex-headless is out of the default writer allowlist until a test proves its native tools cannot execute; adapters self-report the stance.
- **D-2.5** (DEC-0854) — egress threat model stated; resolved-address and port validation; DNS sinkholed; `egress_hosts[]` in the registry; isolation checks never quarantined.
- **D-3.4** (DEC-0855) — the measurement pin is the Sprint 3 head; Sprint 2 is an intermediate version; the smoke asserts the exact tree.
- **D-3.5** (DEC-0857) — a blocking bullet without a valid Failure clause still blocks; non-defect severities exempt; `blocking` flag and confidence normalisation in the schema.
- **D-3.6** (DEC-0858) — amends D-3.1: a failed spike HALTS for an operator decision; (c) is never adopted autonomously; the surface covers every instruction and configuration path.

### E. Flatline integration (SDD review, `a2a/flatline/cycle-133-sdd-review.json`)

Run: claude-headless + gpt-5.5, cross-scoring degraded (KF-041, recurrence 10), 16 skeptic blockers (two CRITICAL), 31 + 41 reviewer items; every one dispositioned.

| Concern | Where it landed |
|---|---|
| SKP-004, SKP-006, gpt 07–10, opus 04–06, 32 — equality precondition, deferred ledger, approval binding, v1 path | C-3 rewritten; D-1.6 |
| SKP-001 (CRITICAL), SKP-010, SKP-003/011, gpt 19–20, opus 02–03, 24–25 — surface gaps, fallback (c), clause (f) comparison, canaries, version pin | C-10 rewritten; D-3.6 |
| SKP-013, gpt 21, opus 01 — pin at the wrong sprint | header Pins; §8 Sprint 2/3; D-3.4 |
| SKP-002 (CRITICAL), SKP-021, opus 08–11, 40, gpt 22 — malformed blocking bullets, severity vocabulary, confidence, vectors, grammar details | C-11 rewritten; D-3.5 |
| SKP-003b, gpt 02–03, 06, opus 13–15 — coverage, degradation blocking merge, two-pass selection, final revalidation | C-1 and C-2 rewritten |
| SKP-001b, gpt 04, opus 38 — codex writer, self-reported stance, `writer_not_eligible` | C-2; D-1.7 |
| SKP-002a, gpt 05, opus 07, 09 — enrichment preserving fields, structural grammar check | C-2 |
| SKP-014, SKP-015, gpt 16–17, opus 21–23 — threat model, resolved addresses, DNS, `egress_hosts`, attribution | C-9; D-2.5 |
| SKP-016, gpt 18, opus 20, 41 — supervisor lock, hangs, retry classes, linger | C-9 |
| SKP-012, gpt 13–14, opus 17–19 — RLIMIT, keep-list, exit status, pattern, metering rules | C-6 |
| gpt 15, opus 26 — refusal policy outcomes, attempts, rate | C-8 |
| gpt 11, opus 36, 39 — record scan scope, CAS, manifest fields | C-4; §3.2 |
| gpt 12, opus 31, SKP-031 — quarantine validation, limits, mandatory gates, tripwire mechanism | C-5; §7.3 |
| gpt 24–28, opus 27–29 — seeder binding, limits order, base definition, leakage test, licence API, secret scan, `looks_seen` integrity | C-12 |
| gpt 29, opus 30 — sweep categories, resolvable evidence, sample rule | C-13 |
| gpt 31, opus 16 — one exit-code table | §5.4 |
| gpt 30, opus 33 — traceability matrix, smoke criteria, mandatory gates | §7.3 |
| opus 34 — branch protection read early | C-3; §8 Sprint 1; §10 |
| opus 35 — notes-guard and hook unspecified values | C-4 |
| opus 37 — reproducing cycle-132 from a pinned worktree | C-7; header Pins |
| SKP-015 (credential-owning gateway) | recorded as out of scope with the threat model (D-2.5) |
