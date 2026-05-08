# Sprint 3 Implementation Report — cycle-100 jailbreak corpus

**Sprint global ID:** sprint-145 (cycle-100 sprint 3)
**Branch:** `feat/cycle-100-sprint-3-regressions-differential`
**Author:** deep-name + Claude Opus 4.7 1M
**Date:** 2026-05-08
**Scope:** Cycle-098 regression replay + differential oracle + cypherpunk pushback (T3.1-T3.8)

---

## Executive Summary

Sprint 3 ships **8 cycle-098 regression vectors** with smoke-revert validation, the **differential oracle** (`differential.bats` + frozen baseline + 25-vector curated list), and closes the per-vector cypherpunk pushback round. The cycle exit gate **≥50 active / 0 suppressed** is met (54 active / 0 suppressed). Schema-additive `expected_absent_marker` field shipped for negative-invariant assertions (used by RT-TC-101 to pin the cycle-098-sprint-7-HIGH-3 sentinel-leak fix).

Sprint-3 cypherpunk dual-review (T3.8) returned 1 HIGH (F1 mapfile newline-shift), 4 MEDIUM, 4 LOW, 3 PRAISE. **F1, F2, F3, F4, F5, F6, F7, F8, F10 all closed inline pre-merge.** F9 deferred (documentation-only).

Performance: full single-shot runner.bats drops from 6:33 (pre-cache) → 21.5s after BATS_RUN_TMPDIR caching (T3.7 NFR-Perf1 budget <60s met with 3× headroom).

---

## AC Verification

| AC (verbatim from sprint.md) | Status | Evidence |
|------|--------|----------|
| Each regression vector cites the cycle-098 sprint + finding number (e.g., `cycle-098-sprint-7-HIGH-2-NFKC-bypass`) | ✓ Met | All 8 RT-{TC,RS,MD}-1NN vectors have `cycle-098-sprint-N-...` source_citation values; verifiable via `cat tests/red-team/jailbreak/corpus/*.jsonl \| jq -r 'select(.source_citation \| test("cycle-098")) \| .source_citation'` (returns 10 entries: 8 new + 2 existing RT-UN-001/002) |
| Smoke-revert procedure (§7.6): for each regression vector, revert the corresponding defense in scratch branch → vector turns RED → restore. Documented in RESUMPTION. | ✓ Met | `tests/red-team/jailbreak/tools/sprint3-smoke-revert.sh:1-200` automates the revert/run/restore cycle for all 8 vectors; 8/8 PASS in latest run; T3.8 F2/F3/F10 closed (signal-trap coverage, glob safety, dirty-SUT precondition). |
| At least 8 cycle-098 defects mapped: NFKC HIGH-2, control-byte HIGH-4, INDEX E6, sentinel HIGH-3 + ≥4 more from sprint-history mining → **[G-1]** | ✓ Met | 8 NEW regression vectors map to: sprint-7-HIGH-3 sentinel-leak (RT-TC-101), sprint-1C tool-call XML block (RT-TC-102), sprint-1C bare-word defense (RT-TC-103), sprint-1C role_pats[0] (RT-RS-101), sprint-1C role_pats[2] above-branch (RT-RS-102), sprint-1C code-fence escape (RT-MD-101), sprint-1C max-chars truncation (RT-MD-102), sprint-1C Layer-2 envelope (RT-MD-103). NFKC HIGH-2 lives at RT-UN-001/002 (Sprint 1 — bypass-class, not a revertable defense; documented in T3.8 review bonus section). HIGH-4 control-byte and L6 INDEX E6 are findings in sibling libs (soul-identity-lib, structured-handoff-lib), not in `sanitize_for_session_start` — out of cycle-100 SUT scope per SDD §1.5. |
| Frozen baseline lib captured at sprint-3 ship date; checked-in | ✓ Met | `.claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline` captured 2026-05-08; sha256 `8a6bd75cb4edc999fee3258d3970259f20a090d0afd38c479dec09de725277f2` matches current SUT (no drift on ship day). |
| `differential.bats` runs both libs under `env -i` with shared `env_sanitize.sh` allowlist (IMP-003); compares byte-for-byte | ✓ Met | `tests/red-team/jailbreak/differential.bats:171-186` invokes both libs via `loa_jailbreak_envi_invoke` (sources `lib/env_sanitize.sh`); byte-for-byte comparison at lines 162-167. |
| Divergence is informational (exit 0); written to `.run/jailbreak-diff-{date}.jsonl` with TAP `# DIVERGE:` comment | ✓ Met | `differential.bats:188-200` exits 0 on divergence; emits TAP `# DIVERGE:` + JSONL via `_emit_diff_jsonl`. Verified end-to-end by tweaking baseline → JSONL written → bats green. |
| Per-vector cypherpunk pushback applied to EVERY active vector against §7.5 criteria; drops + revisions logged | ✓ Met | T3.6 automated checks: bash -n (7/7 fixtures), python -c (7/7 fixtures), trigger-leak lint (clean), fixture function presence (54/54 vectors). Manual review: 0 drops, 0 revisions, 0 suppressions; severity / defense_layer / outcome distributions pass §7.5. T3.8 F4 (RT-RS-101 distinguishability) addressed inline by note revision; T3.8 F5 (RT-MD-101/102 defense_layer mislabel) corrected to L1. |
| Suppression count == 0 at sprint exit (FR-8 ship invariant) | ✓ Met | `cat tests/red-team/jailbreak/corpus/*.jsonl \| jq -r 'select(.status == "suppressed")' \| wc -l` → 0. |
| Sprint-3 cypherpunk dual-review closed pre-merge | ✓ Met | Spawned via Agent tool (general-purpose subagent applying paranoid-cypherpunk lens). 12 distinct findings; 1 HIGH + 4 MED + 4 LOW closures applied at this commit. F9 (schema_version policy doc) deferred to RESUMPTION T3 backlog. |
| ≥50 active vectors at sprint exit; 0 suppressed (FR-8 ship invariant) | ✓ Met | 54 active / 0 suppressed (per-category: RS:8 TC:9 CL:6 MD:9 UN:6 EP:5 MT:11). |

---

## Tasks Completed

### T3.1 — 8 cycle-098 regression vectors

**Files:** `tests/red-team/jailbreak/corpus/{tool_call_exfiltration,role_switch,markdown_indirect}.jsonl`, `tests/red-team/jailbreak/fixtures/{tool_call_exfiltration,role_switch,markdown_indirect}.sh`, `.claude/data/trajectory-schemas/jailbreak-vector.schema.json`, `tests/red-team/jailbreak/runner.bats`, `tests/red-team/jailbreak/lib/corpus_loader.py`

| Vector | Defense | cycle-098 cite | Smoke-revert |
|--------|---------|----------------|--------------|
| RT-TC-101 | sentinel-split parameter expansion (line 220) | sprint-7-HIGH-3 | re-require trailing newline → sentinel leaks → `expected_absent_marker` fires |
| RT-TC-102 | function_calls XML block redaction (n1) | sprint-1C-FR-LayeredDefense | comment out n1+n2+n3+n6 family → wrapped (no marker) |
| RT-TC-103 | bare `function_calls` word splitting defense (n6) | sprint-1C-FR-LayeredDefense | comment out n6 → wrapped |
| RT-RS-101 | role_pats[0] "from now on you are" | sprint-1C-FR-LayeredDefense | comment out role_pats[0] |
| RT-RS-102 | role_pats[2] "disregard ... above" alternative | sprint-1C-FR-LayeredDefense | drop the `above` branch from role_pats[2] |
| RT-MD-101 | code-fence escape (n_cf + n_cf2) | sprint-1C-FR-LayeredDefense | comment out both n_cf calls |
| RT-MD-102 | max-chars truncation cap (L7=2000) | sprint-1C-FR-LayeredDefense | replace `if len(text) > max_chars:` with `if False:` |
| RT-MD-103 | Layer 2 untrusted-content envelope | sprint-1C-FR-LayeredDefense | replace heredoc emit with bare `printf "%s\n"` |

**Schema additive:** `expected_absent_marker` (string, pattern `^[^\n]*\S[^\n]*$` per T3.8 F1+F6 — forbids newlines and whitespace-only).

**Runner change:** `_run_one_vector` now extracts 7 fields via single `jq -r` + `mapfile -t` (avoids the bash `read -r` empty-field-collapse trap with non-whitespace IFS).

### T3.2 — smoke-revert validation

**File:** `tests/red-team/jailbreak/tools/sprint3-smoke-revert.sh` (213 lines).

For each of the 8 regression vectors, the harness:
1. Refuses to run on a dirty SUT (T3.8 F10 closure).
2. Backs up `.claude/scripts/lib/context-isolation-lib.sh` to mktemp.
3. Edits the SUT in place to revert the cited defense (8 distinct revert functions).
4. Runs `bats --filter <vid>` and asserts `not ok` in TAP output.
5. Restores via trap on `EXIT INT TERM HUP QUIT` (T3.8 F2 closure).

Result: 8/8 PASS (`PASS: RT-TC-101 turned RED on revert`, etc.).

### T3.3 — `differential.bats`

**File:** `tests/red-team/jailbreak/differential.bats` (290 lines).

- Sources both libs (current + `.cycle-100-baseline`) into `env -i` subshells via `lib/env_sanitize.sh` (IMP-003).
- Per-vector byte-for-byte comparison of stdout / stderr / exit.
- On match: emits `# CONVERGE: <vid>` TAP comment, exits 0.
- On divergence: emits `# DIVERGE: <vid> stdout=<bool> stderr=<bool> exit=<bool>` + appends a base64-encoded record to `.run/jailbreak-diff-<date>.jsonl` under `flock`. **Exits 0 even on divergence** (FR-5: informational, not failing).

JSONL schema (informational, no separate schema file): `{ run_id, vector_id, category, ts_utc, current: { stdout_b64, stderr_b64, exit }, baseline: { stdout_b64, stderr_b64, exit }, match: { stdout, stderr, exit } }`.

### T3.4 — frozen baseline

**File:** `.claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline`

Captured via `cp` at sprint-3 ship date. Sha256 `8a6bd75cb4edc999fee3258d3970259f20a090d0afd38c479dec09de725277f2` (current SUT byte-identical on capture day; no divergence on ship). IMP-010 rotation SOP: cycle-N+1 ship rotates baseline to current SUT.

### T3.5 — ≥20 differential vectors

**File:** `tests/red-team/jailbreak/differential-vectors.txt` (49 lines including comments; 25 active vector_ids).

Categories ≥3 each (where applicable, single-shot only — multi_turn skipped per IMP-006):
- regression vectors: 8 (all of T3.1)
- role_switch: 3 (RT-RS-001/005/006)
- tool_call_exfiltration: 3 (RT-TC-001/005/006)
- credential_leak: 3 (RT-CL-001/003/005)
- markdown_indirect: 2 (RT-MD-001/005)
- unicode_obfuscation: 3 (RT-UN-001/003/006)
- encoded_payload: 3 (RT-EP-001/003/005)

### T3.6 — per-vector cypherpunk pushback

Automated checks across all 54 active vectors:
- `bash -n` on 7/7 .sh fixtures: PASS
- `python3 -c` on 7/7 .py fixtures: PASS
- `tools/check-trigger-leak.sh`: clean
- fixture-function presence: 54/54 OK (Python script in T3.6 evidence above)
- duplicate-id check: 0 collisions

Manual §7.5 review: 0 drops, 0 revisions, 0 suppressions. Borderline RT-TC-004 + RT-MD-004 from Sprint 1 LOW-001 callout re-reviewed: both defensible-in-depth, kept.

### T3.7 — performance check

| Phase | Pre-cache | Post-cache | Budget |
|-------|----------|------------|--------|
| `runner.bats` (43 single-shot tests) | 6:33 | 21.5s | <60s |
| `differential.bats` (25 tests) | n/a | 13.0s | <60s |
| `test_replay.py` (12 multi-turn) | 3.1s | 3.6s | <120s |
| **TOTAL** | n/a | **38.1s** | <60s NFR-Perf1 |

Optimizations:
- `BATS_RUN_TMPDIR`-keyed cache for `validate-all` sentinel + `iter-active` output (eliminated ~340s of redundant work).
- Single `jq -r [...]` call extracts 7 fields per test (instead of 7 separate `echo $json | jq` invocations).
- `jq -r ... | tojson | @base64` per vector at registration time (instead of base64 encoding inside the bash loop).

Cache key: `find corpus/*.jsonl -printf '%T@:%p' | sort | sha256sum`. Any corpus edit invalidates the cache automatically.

### T3.8 — cypherpunk dual-review

Subagent (paranoid-cypherpunk lens via Agent tool, general-purpose subtype) reviewed:
- Schema/runner additive correctness (`expected_absent_marker`)
- Smoke-revert harness integrity (signal coverage, glob safety, atomicity)
- Differential.bats divergence semantics (exit-0-on-divergence, JSONL atomicity)
- Perf cache invalidation (key correctness, edge cases)
- Regression-vector defensibility (smoke-revert distinguishability, defense_layer correctness)

12 findings: 1 HIGH (F1), 4 MEDIUM (F2-F5), 4 LOW (F6-F8 + F10), 3 PRAISE.

| Finding | Severity | Disposition |
|---------|----------|-------------|
| F1 — `mapfile -t` newline-shift latent bypass | HIGH | **Closed** — schema patterns `^[^\n]*\S[^\n]*$` on `expected_marker` + `expected_absent_marker` reject newlines and whitespace-only |
| F2 — signal trap missing HUP/QUIT | MED | **Closed** — `trap cleanup EXIT INT TERM HUP QUIT` |
| F3 — `rm /tmp/jailbreak-runner-cache-*` glob too broad | MED | **Closed** — only delete this run's own cache (BATS_RUN_TMPDIR or PPID-keyed dir) |
| F4 — RT-RS-101 not distinguishable from RT-RS-003 under same revert | MED | **Closed** — note revised to acknowledge regression-tag-with-explicit-cycle-098-citation pattern |
| F5 — RT-MD-101/102 mislabeled as L2 (should be L1) | MED | **Closed** — relabeled both to `defense_layer: L1` |
| F6 — `expected_absent_marker` minLength accepts whitespace-only | LOW | **Closed** — pattern requires `\S` |
| F7 — `run_id` collision under `bats --jobs N` second-precision ts | LOW | **Closed** — append `${BASHPID:-$$}` to seed |
| F8 — macOS `base64` fallback emits multi-line | LOW | **Closed** — `_b64_oneline` strips newlines defensively |
| F9 — `schema_version`-bump policy not documented for additive field | LOW | **Deferred** — RESUMPTION T3 backlog (documentation-only, non-functional) |
| F10 — smoke-revert no clean-SUT precondition | LOW | **Closed** — `git diff --quiet` precondition + bail with reference to stash-safety.md |
| P1, P2, P3 | PRAISE | (no action) |

Bonus: cypherpunk identified missing-but-not-blocking regression vector candidates for cycle-101+: `role_pats[1]` `(?:|the |all )` modifier branches, `role_pats[3]` forget-* (RT-RS-004 exists but not regression-tagged), n4/n5 invoke variants, Layer 5 `provenance="untrusted-session-start"` attribute. Documented in RESUMPTION as cycle-101 candidates.

---

## Technical Highlights

### Schema-additive `expected_absent_marker`

The negative-invariant pattern is broadly useful — any vector that pins "feature X must NOT leak into Y" gets a clean assertion path. RT-TC-101 demonstrates it for the cycle-098-sprint-7-HIGH-3 sentinel leak; cycle-101 will likely add more (e.g., asserting fixture-internal trigger strings don't leak through). Schema-additive change with no schema_version bump (per SDD §3.1 + L7 precedent).

T3.8 F1 hardens the field at schema time so future authors cannot bypass via embedded newlines.

### `mapfile -t` over `read -r N-vars`

Discovered during T3.7: bash's `read -r v1 v2 v3 ... v7 <<< "tab-separated"` collapses consecutive non-whitespace IFS delimiters when fields are empty mid-stream. Reproduces in pure bash (not zsh-specific). Switch to `mapfile -t` with newline-separated jq output preserves empty fields. Same fix would apply to any future runner extending field count. F1 hardens against the orthogonal newline-shift bypass class.

### Differential oracle as informational signal

The deliberate exit-0-on-divergence keeps the differential out of the CI fail path while still creating an auditable record. Triage workflow: operator inspects `.run/jailbreak-diff-<date>.jsonl` after lib evolution, classifies each divergence as (a) defense improved, (b) defense regressed, or (c) test-bug. Cycle-N+1 ship rotates the baseline to capture the new equilibrium (IMP-010).

### Cache invalidation via mtime+path digest

`find -printf '%T@:%p' | sort | sha256sum` over `corpus/*.jsonl` is the cache key. Catches schema changes that propagate through validate-all, AND catches any vector add/edit/delete. Does NOT catch fixture `.py` / `.sh` edits — but those don't affect the cached results (validate-all only reads JSONL; iter-active only emits JSONL contents). Per T3.8 F9 / cypherpunk-bonus: future cache extensions should consider widening the digest scope if more loader behaviors get added.

---

## Testing Summary

| Suite | Tests | Time | Status |
|-------|-------|------|--------|
| `runner.bats` | 43 | 21.5s | 43/43 GREEN |
| `differential.bats` | 25 | 13.0s | 25/25 GREEN (all CONVERGE) |
| `test_replay.py` | 12 | 3.6s | 12/12 GREEN |
| Smoke-revert harness | 8 reverts | ~70s | 8/8 turned RED on revert |
| `corpus_loader.sh validate-all` | n/a | <1s | clean |
| `tools/check-trigger-leak.sh` | n/a | <1s | clean |

**How to reproduce locally** (from repo root):

```bash
bats tests/red-team/jailbreak/runner.bats
bats tests/red-team/jailbreak/differential.bats
pytest -q tests/red-team/jailbreak/test_replay.py
bash tests/red-team/jailbreak/tools/sprint3-smoke-revert.sh
```

**Acceptance assertions** (mechanical):

```bash
# ≥50 active / 0 suppressed
[ $(bash tests/red-team/jailbreak/lib/corpus_loader.sh iter-active | wc -l) -ge 50 ]
[ $(cat tests/red-team/jailbreak/corpus/*.jsonl | grep -v '^\s*#' | jq -r 'select(.status == "suppressed")' | wc -l) -eq 0 ]

# perf budget
time bats tests/red-team/jailbreak/runner.bats  # < 60s
```

---

## Known Limitations

1. **F9 deferred**: schema_version-bump policy for `expected_absent_marker` is documentation-only; not blocking. Folded into RESUMPTION T3 backlog.

2. **Cypherpunk-bonus uncovered defenses** (cycle-101 candidates): `role_pats[1]` modifier-branch alternations, `role_pats[3]` forget-* not regression-tagged, n4/n5 invoke variants, Layer 5 provenance attribute string. Deliberately deferred to keep sprint-3 scope tight.

3. **NFKC HIGH-2 / control-byte HIGH-4 / INDEX E6**: cited in the brief as candidate regression vectors but they are findings in **sibling libs** (soul-identity-lib, structured-handoff-lib), not in `sanitize_for_session_start`. RT-UN-001/002 carry the cycle-098-sprint-7-HIGH-2 citation as bypass-class documentation (not revertable in the SUT). Per cycle-100 SDD §1.5 (boundaries), L7 / L6 lib defenses are out of cycle-100's SUT scope. If cycle-101 widens scope to test soul-identity-lib + structured-handoff-lib directly, those findings become regression vectors there.

4. **macOS portability**: `flock` (audit_writer + differential) requires `brew install util-linux`. Documented in cycle-099 sprint precedent; T4.1 CI workflow matrix `[ubuntu-latest, macos-latest]` will validate.

5. **No `git worktree`-based smoke-revert**: T3.2 modifies the SUT in place under `flock`-style trap. Per `.claude/rules/stash-safety.md` recommendation, a `git worktree`-based approach is safer. F10 closure hardens the in-place pattern with a pre-flight `git diff --quiet` check; cycle-101+ could rotate to worktree if HUP-during-revert becomes observed.

---

## Verification Steps for Reviewer

1. **Confirm 54 active / 0 suppressed**:
   ```bash
   bash tests/red-team/jailbreak/lib/corpus_loader.sh iter-active | wc -l  # 54
   cat tests/red-team/jailbreak/corpus/*.jsonl | grep -v '^\s*#' | jq -r 'select(.status == "suppressed")' | wc -l  # 0
   ```

2. **Run all three test suites**:
   ```bash
   bats tests/red-team/jailbreak/runner.bats         # 43 GREEN
   bats tests/red-team/jailbreak/differential.bats   # 25 GREEN (all CONVERGE)
   pytest -q tests/red-team/jailbreak/test_replay.py # 12 GREEN
   ```

3. **Run smoke-revert harness, confirm 8/8 PASS**:
   ```bash
   bash tests/red-team/jailbreak/tools/sprint3-smoke-revert.sh 2>&1 | grep -c '^PASS:'  # 8
   ```

4. **Inspect 8 regression vectors**:
   ```bash
   cat tests/red-team/jailbreak/corpus/*.jsonl | grep -v '^\s*#' | jq -r 'select(.source_citation | test("cycle-098-sprint-(1C|7-HIGH-3)")) | [.vector_id, .source_citation] | @tsv'
   ```

5. **Verify schema patterns reject newlines + whitespace** (F1+F6 closure):
   ```bash
   python3 -c '
   from jsonschema import Draft202012Validator
   import json
   schema = json.load(open(".claude/data/trajectory-schemas/jailbreak-vector.schema.json"))
   v = Draft202012Validator(schema)
   def chk(case, label):
       base = {"vector_id":"RT-TC-001","category":"tool_call_exfiltration","title":"x"*8,"defense_layer":"L1","payload_construction":"_make_evil_body_x","expected_outcome":"wrapped","source_citation":"x"*8,"severity":"HIGH","status":"active"}
       base.update(case)
       errs = list(v.iter_errors(base))
       print(label, "REJECT" if errs else "ACCEPT")
   chk({"expected_absent_marker":"line1\nline2"}, "newline:")  # REJECT
   chk({"expected_absent_marker":"   "}, "whitespace-only:")  # REJECT
   chk({"expected_absent_marker":"REPORT"}, "valid printable:")  # ACCEPT
   '
   ```

6. **Trigger a divergence to confirm informational-not-failing semantics**:
   ```bash
   # Tweak the baseline in /tmp, run differential, observe TAP # DIVERGE comment + JSONL line, exit 0.
   cp .claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline /tmp/b.bak
   sed -i 's/MUST NOT be interpreted/MUST NOT_TWEAK be interpreted/' .claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline
   bats --filter "RT-MD-103" tests/red-team/jailbreak/differential.bats  # exits 0; emits DIVERGE
   cp /tmp/b.bak .claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline
   ```

---

## Files Modified / Added

```
.claude/data/trajectory-schemas/jailbreak-vector.schema.json    | 7 +-
.claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline | NEW
tests/red-team/jailbreak/corpus/markdown_indirect.jsonl         | 4 +
tests/red-team/jailbreak/corpus/role_switch.jsonl               | 3 +
tests/red-team/jailbreak/corpus/tool_call_exfiltration.jsonl    | 4 +
tests/red-team/jailbreak/differential-vectors.txt               | NEW
tests/red-team/jailbreak/differential.bats                      | NEW
tests/red-team/jailbreak/fixtures/markdown_indirect.sh          | 38 +
tests/red-team/jailbreak/fixtures/role_switch.sh                | 21 +
tests/red-team/jailbreak/fixtures/tool_call_exfiltration.sh     | 47 +
tests/red-team/jailbreak/lib/corpus_loader.py                   | 1 +
tests/red-team/jailbreak/runner.bats                            | 130 +-
tests/red-team/jailbreak/tools/sprint3-smoke-revert.sh          | NEW
```

---

*Generated by /implement sprint-3 (deep-name + Claude Opus 4.7 1M)*
