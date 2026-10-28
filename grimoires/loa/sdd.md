# Software Design Document: Performance follow-ups (cycle-137)

**Version:** 1.1
**Date:** 2026-10-28
**Revision:** 1.1 integrates the Flatline SDD review (5 blockers, 40 medium items — dispositions in § 11.F) and PRD 1.1's release predicate: cache writer/reader hardening, verify-chains protocol and fail-closed rules, allowed-failure policy, jq root preservation, unattended merge/publish safeguards.
**Author:** Architect Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (1.1, FR-1 … FR-8, G-1 … G-6, § Release predicate R-1 … R-8)
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

Eight components, all inside the existing framework. C-1 is a gate pass over code that already exists (the 20 loop commits). C-2, C-4, C-5, C-6 and C-7 are single-lever changes to one file or one lib each; C-3 carries two levers in two files (the loa-status ceiling read and the agy memo in the shared lib) and lands as two commits. All are built the way the loop built its passes: profile, golden capture, change, old-vs-new mirror parity, review. C-8 is the ship. Nothing new is added to the per-tool-call hook chains; every change removes spawns or shortens tests.

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
| `grimoire-index-decisions.v1.tsv` | `v1:<sha256 of decisions.yaml bytes>:<yq major.minor>:<jq major.minor>:<row count>` | the decisions family TSV rows exactly as `emit_decisions` prints them (post-sanitisation, 9 tab-separated fields each) | `grimoire-index.sh` (miss path) | `grimoire-index.sh` |
| `.run/effective-config.json` (existing) | `schema_version: 1`, `id` (content key of config + profiles + floor, unchanged) | gains `knobs["karpathy_principles.diff_lines_per_task"] = {value, source: explicit\|absent, profile_value: null}` | `profile-lib.sh` cache builder | `loa_knob` |

Writer rules (both caches; precedent `zone-write-guard.sh:227-263`, whose `$$` temp the new writer improves on with `mktemp`): `umask 077`; refuse when `.run`, `.run/perf-cache` or the cache file is a symlink (`[[ -L ]]` checked on each, and again on the file immediately before the rename); `mkdir -p` the directory then re-check `-L`; exclusive temp via `mktemp "$cache.XXXXXX"` in the same directory; write; `mv -f -T` (`mv -f` where `-T` is absent); on any failure remove the temp and continue (never fatal); never read or written under `CI`/`GITHUB_ACTIONS` or when `LOA_GRIMOIRE_INDEX_NO_CACHE=1` (decisions cache). Concurrent writers: the rename is atomic, last writer wins, both payloads are correct by construction (same key ⇒ same rows). Reader rules: one `awk` pass accepts the decisions cache only if line 1 equals the computed key, the number of payload rows equals the key's row count, every row has exactly 9 fields and no byte in `[\x00-\x08\x0a-\x1f\x7f<>]` (the sanitiser's output alphabet excludes them); the awk prints the rows only after the whole file validated, so a truncated, altered or wrong-key file prints nothing and is a miss. The decisions key and the rows are derived from one captured byte string of `decisions.yaml` (the file is read once into a variable or temp copy; sha256 and yq both consume that copy), so a rewrite mid-run cannot pair a new key with old rows. `.run/` is gitignored (`git check-ignore .run/perf-cache/x`), so a downstream mount's `git status` stays clean. The `effective-config.json` builder keeps its existing writer (unchanged in this cycle).

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

Shape C requires a space after the label so `**Symptomatic**:` is not a Symptom field; shape B keeps its existing looseness (unchanged). Shape C applies to the `Symptom` and `Recurrence count` labels only (D-2.2): the live file's only qualified `Status` line for a parsed label is `**Status (original)**: OPEN …` in KF-008 — a historical annotation that must never become the entry's status — so `Status` keeps shapes A/B; a decoy fixture places `**Status (original)**:` after `**Status**:` and asserts no change. Heading rule: every `^## ` line resets `cur = ""`; only `^## KF-[0-9]+:` then sets `cur` to the entry id. Consequence on the live file: none (0 shape-C lines; the non-numeric H2 headings — `## Schema`, `## KF-{NNN}: {short title}`, `## Index`, two `## How to …` — carry no first-wins fields that today attach to an entry). The two programs stay textually aligned; the kf-surface copy keeps its `LC_ALL=C awk` and `san()`.

### 5.2 `_anthropic_ceiling_json` (C-3, `loa-status.sh:848-870`)

One `yq eval -r` program emits six lines in this order: alias (`.aliases.opus // ""`), then for `$m` = the alias with a leading `anthropic:` removed: `effective_input_ceiling`, `probed_ceiling`, `ceiling_calibration.calibrated_at`, `ceiling_calibration.transport`, `context_window`, each `// ""`. The six lines are captured with `mapfile -t` (bash ≥ 4) from the `yq` output — a trailing empty field is a present empty line, and `yq -r` always terminates the last line — and the result is used only when `yq` exits 0 and the array has exactly six elements; otherwise the current per-field reads run verbatim. A multi-line value therefore falls back (as the pass-18 design). Fixtures (fast path or fallback, output identical either way): malformed YAML, a map where a scalar is expected, an embedded newline, explicit `null`, explicit `false`, an empty final field, all optional fields absent, `yq` failing. A bats assertion proves the fast path is taken on the live config (`bash -x` trace: one `yq`, no per-field read). The JSON object `_anthropic_ceiling_json` prints is unchanged.

### 5.3 agy opt-in node memo (C-3, `agy-gate-lib.sh`)

`_agy_opt_in_node` stays the subshell reader (fd-9 open-once semantics, r251-6 V3). A new parent-shell wrapper `_agy_opt_in_node_memo <cfg>` sets `_AGY_NODE_MEMO_VAL` (its result variable — callers read the variable, never `$(...)`, so the memo persists in the calling shell) and returns 0: it computes `id=<cfg>|<dev>:<ino>:<size>:<mtime>` with one portable `stat` (GNU `stat -c '%d:%i:%s:%Y'`, else BSD `stat -f '%d:%i:%z:%m'`); when `stat` fails the memo is dropped and the node re-read every time; when `id` equals `_AGY_NODE_MEMO_KEY` the stored value is returned, else `_agy_opt_in_node <cfg>` runs and both variables are stored. `agy_opted_in` and `agy_gate_warn_once` are rewritten to call the wrapper in the parent shell and read `_AGY_NODE_MEMO_VAL`; their return values and stderr text are unchanged; every other function is untouched. The memo lives only in the calling shell (a `$(...)` caller cannot populate it — same limitation as the pass-14 memo, documented in the comment). Fixtures: hit on an unchanged file; miss after a same-size in-place rewrite `true` → `false` with a distinct mtime (`touch -d`); miss after `mv` replacement (new inode); miss after deletion (node absent); miss after switching `<cfg>`; `$(...)` caller correct. Callers covered: `loa-status.sh` and `run-preflight.sh` by mirror parity (human and `--json`), `flatline-orchestrator.sh` and `adversarial-review.sh` by their existing agy bats suites.

### 5.4 `loa_knob` cached non-profile knobs (C-4, `profile-lib.sh`)

`profiles.yaml` gains a top-level `cached_keys:` list (schema stays 1; unknown top-level keys are ignored by today's reader, verified by the cache builder test). The cache builder adds, for each listed key not already a profile key, `knobs[key] = {value: <explicit config value or null>, source: "explicit" | "absent", profile_value: null}`; `profile_keys` and `overrides` are computed as today from profile keys only (so `loa_profile` output is unchanged). Classification mirrors the live path exactly: the builder evaluates the SAME yq expression `_loa_pl_live` uses for the key; `source: explicit` iff that expression yields what the live path would return as a value today, and the stored `value` is that same string; every other outcome (absent key, explicit `null`, non-scalar, the live path's empty result) is `absent`, so a warm `loa_knob` returns the caller's fallback exactly where the live path does (fixtures: absent, `null`, `""`, `false`, `0`, a map, a multi-line string). `loa_knob` on a warm cache: `source == "absent"` → print the caller's fallback and return 0 without `yq`; `explicit` → the value as today; a cache that lacks the knob entry (built from an older `profiles.yaml`) → the live read as today. The stale (`id` mismatch), missing-cache and missing-`yq` paths are unchanged (live reads). First listed key: `karpathy_principles.diff_lines_per_task`.

### 5.5 `grimoire-index.sh` decisions cache (C-5)

```
emit_decisions():
  f = decisions.yaml; [[ -f ]] || return
  yq gate (unchanged: NOTE + return when not mikefarah v4; yq major.minor parsed from the gate's own --version output)
  caching = LOA_GRIMOIRE_INDEX_NO_CACHE != 1 and CI/GITHUB_ACTIONS unset and ! -L .run and ! -L .run/perf-cache
  snap = one read of f (temp copy under mktemp -d, or a variable when NUL-free)   # key and rows from the same bytes
  key = "v1:$(sha256_portable < snap):$(yq maj.min):$(jq maj.min from the one existing `jq --version` capture or a single spawn)"
  cache = $PROJECT_ROOT/.run/perf-cache/grimoire-index-decisions.v1.tsv
  if caching and -f cache and ! -L cache: rows = awk-validate(cache, key)  # header, row count, 9 fields, alphabet; prints only if all valid
     if rows non-empty or (validated and the row count is 0): print rows; return
  rows = (today's yq → jq pipeline over snap, unchanged, including the unparsable-ledger NOTE path which caches nothing)
  print rows
  if caching: write cache (umask 077; mkdir -p dir; re-check -L dir; tmp=$(mktemp "$cache.XXXXXX");
     printf "%s:%d\n%s" key-prefix nrows rows > tmp; re-check -L cache; mv -f -T tmp cache) || rm -f tmp; true   # never fatal
```
Write-mode checks: the `bad` count and `.total` are read from `$JSON` with ONE jq program that preserves the root object — `jq -r '. as $root | ([$root.families[][] | select((.id|length)==0 or (.path|length)==0 or (.family|test("[^a-z]")))] | length), $root.total'` — captured into two variables with `mapfile -t`; a jq failure or a line count other than two is treated as `bad != 0` (refuse to write, as today's error path) and the bats cases cover a valid and an invalid index for both emitted values and the exit status (`validate` mode keeps its own jq calls: it is not hot). Modes consuming the cache: `--tsv`, `--json`, write (all through `collect`); `--validate` also goes through `collect` and therefore also consumes it; the JSON output is derived from the same cached TSV rows. `--help`, `--tsv`, `--json`, `--validate` outputs unchanged; the env knob `LOA_GRIMOIRE_INDEX_NO_CACHE=1` (disables read and write) is documented in the header comment (no new CLI flag, so `--help` is byte-identical). The `v1:` prefix constant sits adjacent to the `s` filter with a comment binding them (a sanitiser change bumps the prefix in the same commit) and a bats test asserts the prefix changes when the filter text changes (hash of the filter literal pinned next to the prefix).

### 5.6 Test-suite runtime (C-6)

`block-destructive-bash.bats`: `setup_file()` runs `run-corpus.sh --hook "$HOOK" --json` once into `$BATS_FILE_TMPDIR/corpus.json`; `corpus_json()` prints that file; the three corpus tests are otherwise unchanged (the runtime test keeps reading `runtime_ms` from the same JSON, which is the one measured run). `block-destructive-bash.bats` `setup_file` captures without failing: `run-corpus.sh … > corpus.json 2> corpus.err; echo $? > corpus.status` (`|| true`); each corpus test first asserts `corpus.status` is `0` and `jq -e . corpus.json` succeeds, then reads its field, so a runner failure fails the three tests with the runner's stderr, not `setup_file`; `-f` selection and `--jobs` still run `setup_file` once per file process. `adversarial-review-companion.bats`: the env knob `CMP_STUB_HOLD_S` (default 300 = today) is read only by the `cheval` shim the bats file itself defines (lines 160–240: behaviours `stubborn`, `slow`, `unavailable-companion-slow`) and by the holder lines in test bodies (`sleep 30` holders at 1253, 1310, 1594, 1613, 1624, 1719, 1741, 1749; the `sleep 20` sleeper at 183); no production script reads it. Baseline procedure: `bats -T` serial on the idle ship host, median of three totals, before and after. Rules: a fixed sleep no test waits on shortens to the minimum its own bound requires; a hold that exists to be reaped keeps ≥ 2× the longest wait any test places on it (the affected tests and their bounds are listed by name in the implementer's report); polls keep their bounds; the synchronisation states each test demonstrates before asserting (holder ready, lock contended, released, timed out, cleaned up) are preserved and the negative control proves it (holder exits early / reaper disabled → the test fails); no assertion, expected value or skip condition changes. CMP-37 is left as is (out of scope for determinism); its acceptance evidence is the serial whole-file run (PRD R-4). The engineering floor is the script's own per-test runtime; if the measured floor exceeds the PRD's 300 s, a `proposed` decision row written before `/review-sprint sprint-2` moves FR-6's acceptance to the measured floor and names the improvement achieved.

### 5.7 `audit-envelope.sh verify-chains` (C-7)

New subcommand `verify-chains <path>…` → one Python invocation that imports `loa_cheval.audit_envelope` once and calls `audit_verify_chain(path)` per argument in order, wrapping each call in its own try/except so one path's exception becomes that path's FAIL and the next path still runs; it prints one JSON record per input path in argument order — `{"i": <0-based index>, "path": <str>, "ok": <bool>, "error": <str|null>}` — and exits 0 when every record is `ok`, 1 when any is not, 2 on usage (zero arguments) or import failure. A missing path is `ok: false, error: "missing"`. The shell wrapper parses the records with one `jq` keyed on `i` (so paths with spaces, colons or newlines are safe) and is fail-closed: any input index without a record, a non-zero exit other than 1, or unparsable output marks every unrecorded path FAILED. Snapshot semantics: each path is verified exactly as a per-call invocation would at that moment — `_check_trust_store` runs per path and its in-process `_TRUST_STORE_CACHE` re-authenticates through the subprocess snapshot whenever the store path or content changed since the previous path; a store that becomes INVALID or disappears between paths fails every later path while earlier results stand. Equivalence proof: a pytest case in `tests/unit/` (D may not touch `tests/security/`) drives the batch over three fixture chains with a hook that mutates the trust store between paths (replace with a store revoking the signing key; tamper the signature; delete the file) and asserts the batch records equal fresh per-call `audit_verify_chain` results under the same schedule; if it cannot pass without touching `_check_trust_store`, C-7 is deferred (FR-7(b)). `_check_trust_store` is unchanged: its in-process `_TRUST_STORE_CACHE` (keyed by the store path and content key, `audit_envelope.py:411, 414-440`) makes the `audit-signing-helper.py trust-store-verify` subprocess run once per process for an unchanged store and again if the store's content key changes between files — the TOCTOU snapshot defence pinned by `tests/security/test_audit_trust_policy.py:147-165` is untouched. `loa-status.sh:415-435` collects the chain paths that exist (today's `[[ -f ]]` pre-filter stays, so missing files keep counting as valid by absence) and makes one `verify-chains` call; the per-index parse reproduces today's `valid` count exactly; a fail-closed wrapper result (no records) counts every passed path invalid, which is more conservative than today only in the abnormal-exit case and is recorded in the comment. Mutation check: the bats case runs `verify-chains` against a read-only chain tree and compares the sha256 of every chain file before and after. `verify-chain <path>` (singular) stays for every other caller.

### 5.8 Ship (C-8)

CHANGELOG: `[Unreleased]` content moves under `## [2.0.0-rc.9] — 2026-10-2x — Performance follow-ups (release candidate)`; version markers as the rc.8 heading (`git log -p` of the rc.8 commit is the template); `.loa-version.json` `framework_version` → `2.0.0-rc.9`; README install pin → `--tag v2.0.0-rc.9`. The ship scripts are the cycle-135 set with cycle, branch, PR and `--prev origin/record/cycle-136-bridgebuilder-followups` substituted. Ship files (CHANGELOG heading, README pin, `.loa-version.json`) are committed BEFORE the final review/audit of Sprint 282 so the reviewed head is the merged head (PRD R-1, R-3). Unattended merge and publish are authorised by the operator's instruction (PRD § Authorization): merge only via the ship recipe under R-3; publish only after the publish-summary stage — `a2a/sprint-282/publish-summary.md` lists the prepared candidate path, the pipeline's printed digest, the digest the lead recomputes with `sha256_portable` over the fetched candidate bytes (must be equal), the candidate's `merge_sha` (must equal the merge commit on `origin/main`), the tag and the CHANGELOG heading, and ticks R-1 … R-7. Publish: from a non-shallow clone, `post-merge-orchestrator.sh --publish <candidate> --approve-sha256 <digest>`; verify `git merge-base --is-ancestor v2.0.0-rc.9 origin/main`, the release page, and the install smoke test (`git clone --depth 1 --branch v2.0.0-rc.9` into a scratch directory → `check-loa.sh` and the kf-surface hook succeed). Rollback (written before publishing): revert the merge commit on `main` with manifests regenerated; mark the GitHub release as a withdrawn pre-release (tag never deleted); reopen the beads; decision row. The ship scripts are copied to `a2a/sprint-282/ship/` with their sha256 listed in `e2e.md`.

---

## 6. Error Handling Strategy

- Fast paths accept only the plain shape; any failure (`yq`/`jq` nonzero, wrong line count, unreadable file) runs the original code, so messages and exit codes are the originals.
- Caches are never fatal: a write failure is ignored (`|| true`), a bad cache is a miss; `CI`/`GITHUB_ACTIONS` never write a cache.
- `verify-chains` reports per path; a trust-store refusal (`[TRUST-STORE-INVALID]`, bootstrap-pending under strict) fails every path verified while the store is in that state, as the per-call form would; a per-path exception is that path's FAIL; missing records or an abnormal exit are fail-closed in the wrapper (every unrecorded path FAILED).
- Allowed-failure policy (PRD R-4): the only tests that may fail on the ship host are the three KF-034 `semver evidence` tests named there, and they must fail identically on `main` under the same `tag.gpgsign`; every other failure, skip change or changed failure signature blocks; the policy is applied on the exact final head and again on the merge commit's CI run (CI carries no KF-034).
- The gate pass (C-1) fixes land red-first; a finding that cannot be fixed within the sprint reverts that single loop commit — after checking that no later pass depends on it (shared helpers such as `compat-lib.sh`, cache conventions, mirror-harness assumptions; a dependent later pass is reverted together or the finding is fixed forward) — with manifests regenerated in the revert commit and a decision row.
- Verdict binding: every review/audit verdict names `reviewed_head: <sha>`; a code commit after it re-runs the gate (verify-only pass for a gate or Bridgebuilder fix); docs-only commits (`grimoires/**`, `CHANGELOG.md`, `README.md`, `.loa-version.json`, `.skill-loop-progress.md`) do not.
- The ship refuses to merge with a pending or red required check and refuses to publish a candidate whose digest does not re-canonicalise (the rc.6/rc.7 lesson, KF-063).

---

## 7. Testing Strategy

| Component | Red-first tests | Parity harness | Measurement |
|---|---|---|---|
| C-1 | review/audit fix commits each carry a test where behaviour changes | the pass's own `~/.cache/loa/eso-loop/pass-K/` harness re-run | `perf-spawn-budget.bats` 6/6 |
| C-2 | `kf-surface.bats`, `grimoire-index.bats`: shape C parsed, shape B still parsed, `**Symptomatic**:` not a field, `## KF-abc:` resets silently, `## Index` fields ignored; drift test extracts the `fieldval` body and heading rule from both files and asserts equality; both programs run under each available awk (mawk, busybox, `gawk --posix`; absent ones skipped by name) | live `known-failures.md`: hook stdout and `--tsv/--json/write` byte-identical | spawn budget unchanged |
| C-3 | `loa-status-providers.bats`: one yq, fast path taken on the live config (trace), six-line protocol fixtures (malformed YAML, map, newline, null, false, empty final field, all absent, yq failure); `agy-gate-conformance.bats`: memo hit, miss after same-size rewrite with distinct mtime, after `mv`, after deletion, after a path switch; `$(...)` caller | old mirror vs new on live/--json/--help/bogus/no-yq and the config matrix for `loa-status.sh` AND `run-preflight.sh` | ≥ 40 ms, `yq` count 1 |
| C-4 | `profile-lib.bats`: cached absent knob returns fallback without yq (trace: `bash -x` of the call with `PS4` naming the command, grep for `yq`), explicit value wins, classification fixtures (null, "", false, 0, map, multi-line), older cache without the entry → live read, stale id → rebuild, `loa_profile` output unchanged, cache JSON differs only by the knob entry | karpathy hook state files across the pass-19 matrix | hook trace: no `yq` on the warm path |
| C-5 | `grimoire-index.bats`: hit skips yq (trace), miss rebuilds, content change invalidates, truncated / altered row / wrong key / wrong count / symlinked dir or file / read-only `.run` ignored, `NO_CACHE=1` disables read and write, CI env disables, yq-absent host never reads, two concurrent writers, mid-run rewrite caches nothing, write-mode jq on a valid and an invalid index (values + exit status), prefix–filter coupling | live grimoire cold and warm, all four modes | warm ≤ 650 ms; cold ≤ old + 40 ms |
| C-6 | negative control per affected test (break the asserted behaviour under the shortened waits → fails; restore → passes); `setup_file` status/stdout/stderr captured and asserted by the corpus tests | serial TAP pass/fail/skip set per test name before and after | corpus runs once; `bats -T` serial median of 3, before and after |
| C-7 | `audit-envelope*.bats`: `verify-chains` on valid/tampered/broken/missing/empty chains, zero args → exit 2, read-only tree with sha256 before/after, wrapper fail-closed on a truncated record set; pytest in `tests/unit/`: batch records equal per-call results under the store-mutation schedule (revoke, tamper, delete); `test_audit_trust_policy.py` unchanged and green | per-path results equal per-call results on the live chains | 5-chain fixture root: ≥ 100 ms |
| C-8 | — | publish-summary.md digest cross-check; install smoke test from a scratch clone | checks green on the exact head; tag reachable from main |

Whole-head parity gate after C-2 … C-7 land: one old mirror from the pre-sprint head and one new mirror from the sprint head (REAL directories) run every touched entry point over the live inputs; stdout, stderr, rc and written files `cmp` identical (ages/timestamps normalised only where today's output embeds them). Full `tests/unit` on the final head under the allowed-failure policy (§ 6); `check-loa.sh`; `repo-map-gen.sh --validate`; the two lint tools. Measurement protocol for every number: `hyperfine -N -i --warmup 3 --runs 10`, mean ± σ, old and new in the same session on the idle ship host, cache state stated, baseline revision named, host id and command line recorded (PRD § NFR Performance).

---

## 8. Development Phases

| Phase | Sprint | Content |
|---|---|---|
| 1 | 281 | `reviewer.md` for the loop; `/review-sprint`; fixes; `/audit-sprint`; `COMPLETED` |
| 2 | 282 | C-2 … C-7 (ordered C-2, C-5, C-3, C-4, C-6, C-7 — smallest blast radius first; C-7 after C-3 because both touch `loa-status.sh`); `/review-sprint`; `/audit-sprint`; `COMPLETED` |
| 3 | 282 (Tasks 2.9, 2.E2E) | C-8 ship: CHANGELOG/README/version committed before the final gate pass (so the reviewed head is the merged head) → PR → Bridgebuilder (a code fix re-runs the audit as a verify-only pass) → merge under R-3 → record → publish summary → publish rc.9 → smoke test → archive. The ship runs after Sprint 282's `COMPLETED` marker as in cycles 135/136; its evidence lands in `a2a/sprint-282/e2e.md` and the archive. |

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
| rc.9 publish regressions (KF-034, KF-063) | rc.8 recipe; non-shallow clone; lead-recomputed digest equals the printed digest; `merge_sha` equals the merge commit; ancestry check; install smoke test; written rollback (withdrawn pre-release, tag kept, merge reverted) |
| KF-034 on the ship host hides a real red | the allowed-failure list names the three `semver evidence` tests; `main` must fail exactly the same under the same host condition; CI (no KF-034) must be green on the merge commit |
| A cache temp or path is attacked through a symlink | writer refuses symlinked `.run`, `.run/perf-cache` and cache file (re-checked before the rename); `mktemp` exclusive temp; reader validates header, count, fields and alphabet |

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
| D-2.2 | Shape C is recognised for `Symptom` and `Recurrence count` only; `Status` keeps shapes A/B because the live qualified Status forms are historical annotations | 1.1 |
| D-3.1 | The six-line yq protocol with a line-count gate and verbatim fallback; the agy memo is parent-shell only, keyed by file identity | at sprint planning |
| D-4.1 | Non-profile hot knobs are cached through a `cached_keys` list in `profiles.yaml` with `source: explicit\|absent`; `profile_keys`/`overrides` unchanged | at sprint planning |
| D-5.1 | Decisions cache under `.run/perf-cache/`, key `v1:<sha256>:<yq>:<jq>:<rows>`, awk-validated payload, `mktemp` + symlink re-check writer, env opt-out for read and write, never fatal; write-mode `bad`+`total` in one root-preserving jq | at sprint planning (amended 1.1) |
| D-6.1 | Corpus-once via `setup_file` with status capture; companion waits shortened only below their proven bounds with a negative control per test; the measured floor governs the AC by a pre-review decision row | at sprint planning (amended 1.1) |
| D-6.2 | CMP-37 is not made deterministic in this cycle; its acceptance evidence is a serial whole-file run on an idle host (PRD R-4) | 1.1 |
| D-7.1 | `verify-chains` implemented (not deferred) with JSON-lines records in argument order, per-path exception isolation, fail-closed wrapper, and the store-mutation equivalence test as the go/no-go; only `loa-status.sh` switches | at sprint planning (amended 1.1) |
| D-8.1 | `v2.0.0-rc.9` published through the post-merge candidate recipe from a non-shallow clone; majors stay rc pre-releases; unattended merge and publish are authorised by the operator's instruction with the mechanical safeguards of PRD R-3 / R-6 / R-7 (lead-recomputed digest, `merge_sha` check, publish-summary stage) | at sprint planning (amended 1.1) |
| D-1.1 | Every verdict names `reviewed_head`; a later code commit re-runs the gate (verify-only for gate/Bridgebuilder fixes); docs-only commits exempt; ship files committed before the final gate pass | 1.1 |
| D-5.2 | No framework-wide fast-path opt-out switch: the fast paths fall back automatically and the loop's passes carry none; only the decisions cache (the one component that can serve stored state) gets an opt-out | 1.1 |

### 11.F Flatline SDD review dispositions

Review: `flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --budget 300` on SDD 1.0 (commit 748d2886c): 5 blockers, 40 medium items (`~/.cache/loa/cycle-137/logs/flatline-sdd.out`).

| # | Finding (location) | Disposition in 1.1 |
|---|---|---|
| B1 | cache directory / temp-file / no-follow safety (§ 3) | § 3 writer rules: `-L` on `.run`, `.run/perf-cache` and the file (re-checked before rename), `mktemp` exclusive temp, cleanup on failure; fixtures for symlinked parents, pre-existing temp symlinks, concurrent replacement (§ 7 C-5) |
| B2 | verify-chains per-path exceptions, fail-closed, snapshot vs per-path trust (§ 5.7, § 6) | § 5.7: per-path try/except, JSON-lines records, exit 0/1/2, fail-closed wrapper; trust is per path through the untouched cache; store-mutation equivalence test is the go/no-go |
| B3 | expected-failure allowlist (§ 6, § 7, § 9) | § 6 allowed-failure policy (three KF-034 test names, same on `main`, applied on the exact release commit; CI carries no KF-034); § 9 row |
| B4 | write-mode jq loses the root object (§ 5.5) | § 5.5: `. as $root | (...bad... | length), $root.total`, `mapfile` capture, two-line check, tests on valid and invalid indexes for values and exit status |
| B5 | approve-sha256 as operator input or BB required; which of merge/publish unattended (§ 5.8, § 8, D-8.1) | § 5.8 and D-8.1: both unattended per the operator's instruction with mechanical safeguards — lead-recomputed digest must equal the printed one, `merge_sha` must equal the merge commit, publish-summary stage, Bridgebuilder non-degraded with no open blocking finding before merge |
| M1 | root-preserving jq | B4 |
| M2, M17, M23, M33 | per-path semantics, machine-readable results, missing path, zero args | § 5.7 |
| M3, M37 | `setup_file` failure reporting and status capture | § 5.6 |
| M4, M5, M20 | companion tests listed with bounds; baseline procedure; decision gate | § 5.6 |
| M6, M32 | performance gates as absolute + relative with protocol | § 7 measurement protocol; C-5 warm absolute + cold relative; PRD NFR Performance |
| M7 | exact KF-034 failures permitted | § 6 policy |
| M8 | release gate binds merge, candidate, digest, tag | § 5.8; PRD R-3, R-6, R-8 |
| M9 | memo result without command substitution | § 5.3 (`_AGY_NODE_MEMO_VAL`) |
| M10, M35 | portable stat; stat failure invalidates; same-size rewrite fixture | § 5.3 |
| M11, M12, M15 (PRD) | payload validation; key and rows from one snapshot | § 3 reader rules; § 5.5 `snap` |
| M13, M28 | temp-file safety; named helper precedent | § 3 (precedent `zone-write-guard.sh:227-263`, improved with `mktemp`) |
| M14 | NO_CACHE / CI guards placement | § 5.5 `caching` predicate (read and write) |
| M15 | trailing empty record in the six-line protocol | § 5.2 (`mapfile -t`) |
| M16, M36 | non-profile knob classification | § 5.4 (same yq expression as the live path; fixtures) |
| M18 | how bats obtains trace evidence | § 7 C-4 (`bash -x` with `PS4`, grep `yq`) |
| M19 | post-publish rollback | § 5.8 |
| M21 | which modes consume the cache | § 5.5 (all four via `collect`) |
| M22, M29 | jq version in the key; yq version from the gate's capture | § 3 key; § 5.5 |
| M24 | Phase 3 assigned to a sprint | § 8 (Sprint 282 Tasks 2.9 / 2.E2E after `COMPLETED`, cycles 135/136 precedent) |
| M25 | C-3 is two levers | § 1.1 corrected (two commits) |
| M26 | ship scripts outside version control | § 5.8 (copied to `a2a/sprint-282/ship/`, sha256 in e2e) |
| M27 | final line without newline; fast-path assertion | § 5.2 |
| M30 | prefix–filter coupling | § 5.5 (adjacent constant + bats assertion) |
| M31 | parser drift test | § 7 C-2 |
| M34 | run both awk programs under each available awk | § 7 C-2 |
| M38 | whole-head parity gate | § 7 |
| M39 | framework-wide fast-path opt-out | Declined — D-5.2: fast paths fall back automatically; only the decisions cache gets an opt-out |
| M40 | revert rule checks later-pass dependencies | § 6 |

### 11.E Grounding reads
`.claude/hooks/loa-kf-surface.sh:96-125`; `.claude/scripts/grimoire-index.sh:93-128, 216-250, 296-330`; `.claude/scripts/loa-status.sh:415-440, 848-870`; `.claude/scripts/lib/agy-gate-lib.sh:122-145, 203-216, 298-325`; `.claude/scripts/lib/profile-lib.sh:28-75, 100-165, 212-260, 289`; `.claude/data/profiles.yaml`; `.claude/hooks/safety/zone-write-guard.sh:81-104, 227-263`; `tests/unit/block-destructive-bash.bats:1540-1600`; `tests/unit/adversarial-review-companion.bats:160-240`; `.claude/adapters/loa_cheval/audit_envelope.py:411-445, 500-545, 580-600, 705-730`; `.claude/scripts/audit-envelope.sh`; `grimoires/loa/known-failures.md` (69 H2 headings, 63 numeric KF headings, 0 shape-C fields); `grimoires/loa/archive/cycle-136-bridgebuilder-followups/sdd.md` (format precedent); `~/.cache/loa/cycle-135/ship/*.sh`.
