# Software Design Document: Performance follow-ups (cycle-137)

**Version:** 1.0
**Date:** 2026-10-28
**Author:** Architect Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.0, FR-1 … FR-8, G-1 … G-6)
**Status:** Draft — autonomous cycle on the operator's instruction of 2026-10-28
**Cycle:** `cycle-137-performance-followups`, branch `feature/cycle-137-performance`

---

## Table of Contents

1. Project Architecture
2. Software Stack
3. Database Design
4. UI Design
5. API Specifications
6. Error Handling Strategy
7. Testing Strategy
8. Development Phases
9. Known Risks and Mitigation
10. Open Questions
11. Appendix

---

## 1. Project Architecture

### 1.1 System Overview

Eight components, all inside the existing framework. C-1 is a gate pass over code that already exists (the 20 loop commits). C-2 … C-7 are single-lever changes to one file or one lib each, built the way the loop built its passes: profile, golden capture, change, old-vs-new mirror parity, review. C-8 is the ship. Nothing new is added to the per-tool-call hook chains; every change removes spawns or shortens tests.

### 1.2 Architectural Pattern

"Fast path with verbatim fallback" (the loop's passes 7, 9, 10, 11, 16, 18): the plain, common input shape takes one process; every other shape runs the original code unchanged, so error text, exit codes and degraded paths stay byte-identical by construction. Caches (C-4, C-5) are pure functions of their inputs, content-keyed, written atomically under `.run/`, and ignored on any defect (the 2026-07 loop's `.run/perf-cache` conventions in `zone-write-guard.sh:81-104, 227-263`).

### 1.3 Component Diagram

```
Sprint 281                               Sprint 282
┌──────────────────────────┐   ┌──────────────────────────────────────────────────────────┐
│ C-1 gate pass            │   │ C-2 KF parsers      loa-kf-surface.sh · grimoire-index.sh│
│  20 loop commits         │   │ C-3 loa-status      one yq ceilings · agy node memo       │
│  reviewer.md → review    │   │ C-4 profile-lib     cached non-profile knobs             │
│  → audit → COMPLETED     │   │ C-5 grimoire-index  decisions cache · one write-mode jq   │
└──────────────────────────┘   │ C-6 tests           corpus-once · bounded waits           │
                               │ C-7 audit-envelope  verify-chains (one process)           │
                               └──────────────────────────────────────────────────────────┘
                                                      │
                                              C-8 ship: PR → BB → merge → record → archive → rc.9
```

### 1.4 Components

| Id | Component | Files | PRD |
|---|---|---|---|
| C-1 | Formal gates on the optimisation loop | `grimoires/loa/a2a/sprint-281/reviewer.md`, fix commits on loop files | FR-1 |
| C-2 | KF field-variant parsing and heading reset | `.claude/hooks/loa-kf-surface.sh`, `.claude/scripts/grimoire-index.sh` | FR-2 |
| C-3 | loa-status single-yq ceiling read; agy opt-in node memo | `.claude/scripts/loa-status.sh`, `.claude/scripts/lib/agy-gate-lib.sh` | FR-3 |
| C-4 | Cached non-profile knobs in profile-lib | `.claude/scripts/lib/profile-lib.sh`, `.claude/data/profiles.yaml` | FR-4 |
| C-5 | grimoire-index decisions cache and one write-mode jq | `.claude/scripts/grimoire-index.sh` | FR-5 |
| C-6 | Test-suite runtime: corpus-once fixture, bounded waits | `tests/unit/block-destructive-bash.bats`, `tests/unit/adversarial-review-companion.bats` | FR-6 |
| C-7 | `verify-chains`: one Python process for every chain file | `.claude/scripts/audit-envelope.sh`, `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/loa-status.sh` | FR-7 |
| C-8 | Ship and publish `v2.0.0-rc.9` | `CHANGELOG.md`, `README.md`, `.loa-version.json`, ship scripts under `~/.cache/loa/cycle-137/ship/` | FR-8 |

---

## 2. Software Stack

### 2.1 Languages and runtimes
bash 5 (hooks and scripts; bash-3.2/BSD-friendly constructs where the surrounding file already is), POSIX awk (mawk, busybox and BWK must all run the KF regexes — no gawk-only syntax), jq 1.7, mikefarah yq v4 (optional where it is optional today), Python 3.13 (`audit_envelope.py`), bats 1.13 via `npx --no-install bats`.

### 2.2 Build and verification
`hyperfine -N` for every measurement (hyperfine 2.0 JSON: `.results[0].measurements[].time_wall_clock.value`); `PS4` traces for spawn counts; old-vs-new mirrors built in REAL directories (a symlinked hooks or scripts dir lets `..` escape to the live lib — the pass-18 lesson); `tools/check-no-raw-sha256sum.sh`, `tools/check-no-swallowed-jq.sh --quiet`, `bash .claude/scripts/check-loa.sh`, `repo-map-gen.sh --validate`, `tests/unit/perf-spawn-budget.bats`.

### 2.3 External services
GitHub via `gh` (PR, checks, merge, release); the post-merge pipeline for the rc.9 candidate; Bridgebuilder on `codex-headless`.

---

## 3. Database Design

No database. Two new file caches under `.run/perf-cache/` (gitignored, state zone):

| Cache | Key (first line) | Payload | Writer | Readers |
|---|---|---|---|---|
| `grimoire-index-decisions.v1.tsv` | `v1:<sha256 of decisions.yaml bytes>:<yq major.minor>` | the decisions family TSV rows exactly as `emit_decisions` prints them | `grimoire-index.sh` (miss path) | `grimoire-index.sh` |
| `.run/effective-config.json` (existing) | `schema_version: 1`, `id` (content key of config + profiles + floor, unchanged) | gains `knobs["karpathy_principles.diff_lines_per_task"] = {value, source: explicit\|absent, profile_value: null}` | `profile-lib.sh` cache builder | `loa_knob` |

Both writers: `umask 077`, `$$`-suffixed temp in the same directory, `mv -f -T` (`mv -f` where `-T` is absent), refusal to follow a symlinked cache path (`[[ -L ]]` → skip the cache entirely), never written under `CI`/`GITHUB_ACTIONS`. Readers treat a missing, unreadable, symlinked, key-mismatched or malformed cache as a miss.

---

## 4. UI Design

No user interface changes. Every hook and script keeps its stdout, stderr and exit codes byte-identical on the live inputs; the only new operator-visible text is the CHANGELOG release section, the PR body and the release notes.

---

## 5. API Specifications

### 5.1 KF field parsing (C-2, both awk programs)

`fieldval(line, label)` recognises three line shapes, each with an optional leading `- `:

| Shape | Regex (awk ERE, label interpolated) | Example |
|---|---|---|
| A (existing) | `^(- )?\*\*LABEL\*\*: ?` | `**Symptom**: text` |
| B (existing) | `^(- )?\*\*LABEL[^*]*:\*\* ?` | `**Symptom (short):** text` |
| C (new) | `^(- )?\*\*LABEL( [^*]*)?\*\*: ?` | `**Symptom (short)**: text` |

Shape C requires a space after the label so `**Symptomatic**:` is not a Symptom field; shape B keeps its existing looseness (unchanged). Heading rule: every `^## ` line resets `cur = ""`; only `^## KF-[0-9]+:` then sets `cur` to the entry id. Consequence on the live file: none (0 shape-C lines; the non-numeric H2 headings — `## Schema`, `## KF-{NNN}: {short title}`, `## Index`, two `## How to …` — carry no first-wins fields that today attach to an entry). The two programs stay textually aligned; the kf-surface copy keeps its `LC_ALL=C awk` and `san()`.

### 5.2 `_anthropic_ceiling_json` (C-3, `loa-status.sh:848-870`)

One `yq eval -r` program emits six lines in this order: alias (`.aliases.opus // ""`), then for `$m` = the alias with a leading `anthropic:` removed: `effective_input_ceiling`, `probed_ceiling`, `ceiling_calibration.calibrated_at`, `ceiling_calibration.transport`, `context_window`, each `// ""`. The result is used only when `yq` exits 0 and exactly six lines came back (`IFS= read -r` × 6 plus a seventh read that must fail); otherwise the current per-field reads run verbatim. A multi-line value therefore falls back (as the pass-18 design). The JSON object `_anthropic_ceiling_json` prints is unchanged.

### 5.3 agy opt-in node memo (C-3, `agy-gate-lib.sh`)

`_agy_opt_in_node` stays the subshell reader (fd-9 open-once semantics, r251-6 V3). A new parent-shell wrapper `_agy_opt_in_node_memo <cfg>` returns `$_AGY_NODE_MEMO_VAL` when `$_AGY_NODE_MEMO_KEY` equals `<cfg>|<dev>:<ino>:<size>:<mtime>` of the file (one `stat`), else calls `_agy_opt_in_node`, stores, returns. `agy_opted_in` and `agy_gate_warn_once` call the wrapper; every other caller is untouched. The memo lives only in the calling shell (a `$(...)` caller cannot populate it — same limitation as the pass-14 memo, documented in the comment). Identity key over dev/ino/size/mtime keeps the "config cannot change mid-run" assumption honest: a rewritten file re-reads.

### 5.4 `loa_knob` cached non-profile knobs (C-4, `profile-lib.sh`)

`profiles.yaml` gains a top-level `cached_keys:` list (schema stays 1; unknown top-level keys are ignored by today's reader, verified by the cache builder test). The cache builder adds, for each listed key not already a profile key, `knobs[key] = {value: <explicit config value or null>, source: "explicit" | "absent", profile_value: null}`; `profile_keys` and `overrides` are computed as today from profile keys only (so `loa_profile` output is unchanged). `loa_knob` on a warm cache: `source == "absent"` → print the caller's fallback and return 0 without `yq`; `explicit` → the value as today. The stale (`id` mismatch), missing-cache and missing-`yq` paths are unchanged (live reads). First listed key: `karpathy_principles.diff_lines_per_task`.

### 5.5 `grimoire-index.sh` decisions cache (C-5)

```
emit_decisions():
  f = decisions.yaml; [[ -f ]] || return
  yq gate (unchanged: NOTE + return when not mikefarah v4)
  key = "v1:$(sha256_portable < f):$(yq version major.minor)"
  cache = $PROJECT_ROOT/.run/perf-cache/grimoire-index-decisions.v1.tsv
  if LOA_GRIMOIRE_INDEX_NO_CACHE != 1 and -f cache and ! -L cache and first line == key: print lines 2.. ; return
  rows = (today's yq → jq pipeline, unchanged, including the unparsable-ledger NOTE path which caches nothing)
  print rows
  write cache (umask 077; tmp "$cache.$$"; printf key\n rows; mv -f -T) || true   # never fatal
```
Write-mode checks: the `bad` count and `.total` are read from `$JSON` with ONE `jq -r '[...bad...] | length, .total'` into two variables (`validate` mode keeps its own jq calls: it is not hot). `--help`, `--tsv`, `--json`, `--validate` outputs unchanged; the env knob `LOA_GRIMOIRE_INDEX_NO_CACHE=1` is documented in the header comment (no new CLI flag, so `--help` is byte-identical).

### 5.6 Test-suite runtime (C-6)

`block-destructive-bash.bats`: `setup_file()` runs `run-corpus.sh --hook "$HOOK" --json` once into `$BATS_FILE_TMPDIR/corpus.json`; `corpus_json()` prints that file; the three corpus tests are otherwise unchanged (the runtime test keeps reading `runtime_ms` from the same JSON, which is the one measured run). `adversarial-review-companion.bats`: per-test timing (`bats -T`) decides; fixed `sleep N` in stub behaviours that no test waits on shorten to the minimum a test's own bound requires; hold processes that exist to be reaped keep a hold ≥ 2× the longest wait any test places on them (`CMP_STUB_HOLD_S`, default 300 = today); polls keep their bounds; no assertion, expected value or skip condition changes. The engineering floor is the script's own per-test runtime; the sprint records the measured floor and, if it exceeds the PRD's 300 s, adjusts FR-6's acceptance to the measured floor by a decision row.

### 5.7 `audit-envelope.sh verify-chains` (C-7)

New subcommand `verify-chains <path>…` → one Python invocation that imports `loa_cheval.audit_envelope` once and calls `audit_verify_chain(path)` per argument, printing one line per path `ok <path>` or `FAIL <path>: <message>`, exit 0 when every path verified, 1 otherwise. `_check_trust_store` is unchanged: its in-process `_TRUST_STORE_CACHE` (keyed by the store path and content key, `audit_envelope.py:411, 414-440`) makes the `audit-signing-helper.py trust-store-verify` subprocess run once per process for an unchanged store and again if the store's content key changes between files — the TOCTOU snapshot defence pinned by `tests/security/test_audit_trust_policy.py:147-165` is untouched. `loa-status.sh:415-435` collects the existing chain paths and makes one `verify-chains` call; missing files keep counting as valid by absence as today; the per-path parse of the result reproduces today's `valid` count exactly. `verify-chain <path>` (singular) stays for every other caller.

### 5.8 Ship (C-8)

CHANGELOG: `[Unreleased]` content moves under `## [2.0.0-rc.9] — 2026-10-2x — Performance follow-ups (release candidate)`; version markers as the rc.8 heading (`git log -p` of the rc.8 commit is the template); `.loa-version.json` `framework_version` → `2.0.0-rc.9`; README install pin → `--tag v2.0.0-rc.9`. The ship scripts are the cycle-135 set with cycle, branch, PR and `--prev origin/record/cycle-136-bridgebuilder-followups` substituted. Publish: from a non-shallow clone, `post-merge-orchestrator.sh --publish <candidate> --approve-sha256 <digest>`; verify `git merge-base --is-ancestor v2.0.0-rc.9 origin/main` and the release page.

---

## 6. Error Handling Strategy

- Fast paths accept only the plain shape; any failure (`yq`/`jq` nonzero, wrong line count, unreadable file) runs the original code, so messages and exit codes are the originals.
- Caches are never fatal: a write failure is ignored (`|| true`), a bad cache is a miss; `CI`/`GITHUB_ACTIONS` never write a cache.
- `verify-chains` reports per path; a trust-store refusal (`[TRUST-STORE-INVALID]`, bootstrap-pending under strict) is raised once and fails every path, as the per-call form would.
- The gate pass (C-1) fixes land red-first; a finding that cannot be fixed within the sprint reverts that single loop commit and records a decision row.
- The ship refuses to merge with a pending or red required check and refuses to publish a candidate whose digest does not re-canonicalise (the rc.6/rc.7 lesson, KF-063).

---

## 7. Testing Strategy

| Component | Red-first tests | Parity harness | Measurement |
|---|---|---|---|
| C-1 | review/audit fix commits each carry a test where behaviour changes | the pass's own `~/.cache/loa/eso-loop/pass-K/` harness re-run | `perf-spawn-budget.bats` 6/6 |
| C-2 | `kf-surface.bats`, `grimoire-index.bats`: shape C parsed, shape B still parsed, `## KF-abc:` resets, `## Index` fields ignored | live `known-failures.md`: hook stdout and `--tsv/--json/write` byte-identical | spawn budget unchanged |
| C-3 | `loa-status-providers.bats`: one yq, six-line protocol, fallback on a multi-line value; `agy-gate-conformance.bats`: memo hit/miss on a rewritten file | old mirror vs new on live/--json/--help/bogus/no-yq and the config matrix | ≥ 40 ms, `yq` count 1 |
| C-4 | `profile-lib.bats`: cached absent knob returns fallback without yq, explicit value wins, profile keys unchanged, `loa_profile` output unchanged | karpathy hook state files across the pass-19 matrix | hook trace: no `yq` on the warm path |
| C-5 | `grimoire-index.bats`: hit skips yq, miss rebuilds, content change invalidates, corrupt/symlink/read-only cache ignored, `NO_CACHE=1` | live grimoire cold and warm, all modes | warm ≤ 650 ms |
| C-6 | none (test-only); pass/fail/skip set per test name compared before and after | serial TAP diff | corpus runs once; companion wall time |
| C-7 | `audit-envelope*.bats`: `verify-chains` on valid/tampered/broken/missing/empty chains; `test_audit_trust_policy.py` unchanged and green | per-path results equal per-call results on the live chains | 5-chain fixture root: ≥ 100 ms |
| C-8 | — | — | checks green on the exact head; tag reachable from main |

Full `tests/unit` on the final head (expect only KF-034 reds); `check-loa.sh`; `repo-map-gen.sh --validate`; the two lint tools.

---

## 8. Development Phases

| Phase | Sprint | Content |
|---|---|---|
| 1 | 281 | `reviewer.md` for the loop; `/review-sprint`; fixes; `/audit-sprint`; `COMPLETED` |
| 2 | 282 | C-2 … C-7 (ordered C-2, C-5, C-3, C-4, C-6, C-7 — smallest blast radius first; C-7 after C-3 because both touch `loa-status.sh`); `/review-sprint`; `/audit-sprint`; `COMPLETED` |
| 3 | — | C-8 ship: CHANGELOG/README/version → PR → Bridgebuilder → merge → record → archive → publish rc.9 |

---

## 9. Known Risks and Mitigation

| Risk | Mitigation |
|---|---|
| Shape C regex over-matches a bold label followed by a space in prose | the space-then-qualifier form requires `**Label …**:` at line start; bats negative fixtures (`**Symptom** text`, `**Symptomatic**:`) |
| The six-line yq protocol mis-parses a value containing a newline | line-count check → fallback; fixture with a multi-line `transport` |
| The agy memo hides a config rewritten mid-process | identity key over dev/ino/size/mtime; fixture rewrites the file between two calls |
| `cached_keys` changes `effective-config.json` for existing users | the cache id is content-derived, so the first run after upgrade rebuilds it; `profile_keys`/`overrides` unchanged; bats asserts `loa_profile` output byte-identical |
| The decisions cache serves stale rows | key = sha256 of the file bytes + yq version; invalidation fixture |
| Shortened test waits mask a reaper failure | holds stay ≥ 2× the longest wait on them; the pass/fail set is compared per test name; the reaper tests are listed by name in the task |
| `verify-chains` changes a trust decision | `_check_trust_store` untouched; the security suite is a gate; per-path results compared with per-call results |
| rc.9 publish regressions (KF-034, KF-063) | rc.8 recipe; non-shallow clone; digest approval; ancestry check |

---

## 10. Open Questions

- OQ-1: Should the decisions cache key include the `grimoire-index.sh` sanitiser version? Decided yes via the `v1:` prefix: a later change to the `s` filter bumps the prefix in the same commit. Resolved — D-5.1 (DEC row written at sprint planning).
- OQ-2: Should FR-6's 300 s target for the companion file be an acceptance criterion when the per-test script runtime is the floor? Resolved — D-6.1: the measured floor governs; a decision row adjusts the AC if the floor is higher.
- OQ-3: Should `verify-chains` replace `verify-chain` for other callers? Decided no — D-7.1: only `loa-status.sh` switches; the singular form stays for every other caller and for the bats suites.

---

## 11. Appendix

### 11.D Design decisions taken on the operator's behalf

| # | Decision | Row |
|---|---|---|
| D-2.1 | Shape C requires a space after the label; shape B's looseness is kept; every `## ` heading resets `cur` | at sprint planning |
| D-3.1 | The six-line yq protocol with a line-count gate and verbatim fallback; the agy memo is parent-shell only, keyed by file identity | at sprint planning |
| D-4.1 | Non-profile hot knobs are cached through a `cached_keys` list in `profiles.yaml` with `source: explicit\|absent`; `profile_keys`/`overrides` unchanged | at sprint planning |
| D-5.1 | Decisions cache under `.run/perf-cache/`, content-keyed with a version prefix, env opt-out, never fatal; write-mode `bad`+`total` in one jq | at sprint planning |
| D-6.1 | Corpus-once via `setup_file`; companion waits shortened only below their proven bounds; the measured floor governs the AC | at sprint planning |
| D-7.1 | `verify-chains` implemented (not deferred): the in-process trust-store cache already makes the subprocess run once per process; only `loa-status.sh` switches | at sprint planning |
| D-8.1 | `v2.0.0-rc.9` published through the post-merge candidate recipe from a non-shallow clone; majors stay rc pre-releases | at sprint planning |

### 11.E Grounding reads
`.claude/hooks/loa-kf-surface.sh:96-125`; `.claude/scripts/grimoire-index.sh:93-128, 216-250, 296-330`; `.claude/scripts/loa-status.sh:415-440, 848-870`; `.claude/scripts/lib/agy-gate-lib.sh:122-145, 203-216, 298-325`; `.claude/scripts/lib/profile-lib.sh:28-75, 100-165, 212-260, 289`; `.claude/data/profiles.yaml`; `.claude/hooks/safety/zone-write-guard.sh:81-104, 227-263`; `tests/unit/block-destructive-bash.bats:1540-1600`; `tests/unit/adversarial-review-companion.bats:160-240`; `.claude/adapters/loa_cheval/audit_envelope.py:411-445, 500-545, 580-600, 705-730`; `.claude/scripts/audit-envelope.sh`; `grimoires/loa/known-failures.md` (69 H2 headings, 63 numeric KF headings, 0 shape-C fields); `grimoires/loa/archive/cycle-136-bridgebuilder-followups/sdd.md` (format precedent); `~/.cache/loa/cycle-135/ship/*.sh`.
