All good

Sprint 281 has been reviewed and approved. All acceptance criteria met. Observations documented and non-blocking. See Observations below.

# Sprint 281 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent (Claude Fable 5.1)
**Date:** 2026-10-28
**Sprint Reference:** grimoires/loa/sprint.md (1.1, Sprint 1 — global 281, cycle-137)
**Implementation Report:** grimoires/loa/a2a/sprint-281/reviewer.md
**reviewed_head:** d005a771a — the 20 loop commits (395795939 … c0d41f5e3) plus the two review fix commits 74790b2d1 (red) and d005a771a (fix) on `tests/unit/perf-spawn-budget.bats`; the planning commits between them (3c6ee9533, 7625d1554, 748d2886c, b49e6310d, e5df3b589) touch only `grimoires/`.

---

## Overall Assessment

The sprint's implementation is the 22-pass optimisation loop: 20 commits over 18 System Zone files, one new test file and three test helpers. I read the complete code diff (`git diff main..c0d41f5e3 -- .claude tests CHANGELOG.md`, 24 files, 766+/221−) rather than the report, re-ran the guard, the integrity check, the two lint tools and the repo-map validation on the head, ran the covering bats suites for every touched file (341/341) and the serial whole-file companion run the G-4 criterion asks for (284/284, 872 s, host fukuoka, started 2026-10-28T02:40:26Z), and ran the two-voice cross-model dissent on the code-only diff with seventeen written concerns (`reviewer-concerns.md`). The "fast path with verbatim fallback" pattern keeps every degraded path's bytes and exit codes, the awk sanitisers are byte-for-byte twins of the pipelines they replace, the four fences keep their fail-open / fail-closed semantics, and the manifests are regenerated per commit. No critical or high finding from either my read or the dissent.

One advisory was real and is fixed in this sprint: the spawn-budget tracer (`tests/unit/perf-spawn-budget.bats`) rode the target's stderr, so every spawn under a `2>/dev/null` and inside a child bash was invisible to the budgets — exactly the shapes the hooks use for their jq/yq calls. The fix (red 74790b2d1 → d005a771a) traces through an inherited `BASH_XTRACEFD` with `SHELLOPTS=xtrace`, widens the tool regex to the awk variants and GNU g-prefixed names, floors the headroom at +3 lines, asserts the live repository config never appears in a trace, and re-measures the budgets (three identical runs; implement-gate 113 → 127 trace lines, external-tool lines unchanged). The remaining observations are medium or low and non-blocking; two become Sprint 2 requirements and three become beads.

**Verdict:** APPROVED

---

## Observations

### 1. Portability of the awk sanitiser (kf-surface, grimoire-index)

- **MEDIUM** (confidence: medium) `.claude/hooks/loa-kf-surface.sh:92-100` — the NUL regex and the byte cap are host-dependent. Failure: when a host's awk rejects `/\000/` or the octal class in a regex constant, the `2>/dev/null || true` turns a valid known-failures.md into the "parsed ZERO KF entries" warning path for every session on that host, and on a BSD-`cut` host (macOS without coreutils) the former cap was 100 characters while `substr` under `LC_ALL=C` caps 100 bytes, so a long non-ASCII symptom can end mid-codepoint in the session context.
**File:** `.claude/hooks/loa-kf-surface.sh:92-100` (twin: `.claude/scripts/grimoire-index.sh:59-66`)
**Suggestion:** Sprint 2 Task 2.1 (which edits both awk programs) runs the golden comparison under every awk available — mawk, busybox awk and a BWK one-true-awk built from source (`~/.cache/loa/bwk-awk/awk/a.out`; the build was started during this review and its result is recorded in `a2a/sprint-281/e2e.md`) — on a fixture with `\001`, `\177`, NUL and a 3-byte-UTF-8 symptom longer than 100 bytes; either state the byte cap as the contract in the comment (GNU `cut -c` was already byte-based on Linux, so Linux output is unchanged) or trim a trailing partial sequence after `substr`. Verified at review: mawk 1.3.4 and busybox awk run both programs identically (pass-4 and pass-6 reviewer fixtures); BWK awk UNVERIFIED on this host.
**Benefit:** the SessionStart surface keeps working on macOS hosts, where `/usr/bin/awk` is BWK awk and `cut` is BSD.

### 2. Provider registry seams (`providers/__init__.py`)

- **MEDIUM** (confidence: medium) `.claude/adapters/loa_cheval/providers/__init__.py:45-62` — `_ADAPTER_REGISTRY` is now a derived cache while dispatch reads `_ADAPTER_TYPES` through `_adapter_class`, and `cli_adapter_types()` (line 130-136) imports all ten adapter modules on first call. Failure: a test or downstream harness that patches `_ADAPTER_REGISTRY` to inject an adapter type no longer changes what `get_adapter` returns while `cli_adapter_types()` still honours the patch, and on cheval's custom kind:cli provider path (`.claude/adapters/cheval.py:490`, `if ptype in cli_adapter_types()`) the lazy-import saving is forfeited and a broken adapter module raises inside dispatch instead of at startup.
**File:** `.claude/adapters/loa_cheval/providers/__init__.py:45-62, 130-136`
**Suggestion:** route dispatch and `cli_adapter_types()` through one lazily built mapping, derive the headless set from a static `{type: auth_type}` table asserted equal to the class attributes in a unit test, and use `name in globals()` rather than truthiness in `_adapter_class` so a deliberate `None` replacement is honoured. No in-tree test patches the registry or an adapter attribute (grep over `.claude/adapters/tests`, `tests/`), the adapter modules import their optional SDKs lazily (`bedrock_adapter.py` top-level imports are stdlib), and `pytest` is 3279 passed on the head, so this is a seam change, not a current defect → follow-up bead.
**Benefit:** one dispatch table, laziness preserved on the kind:cli path, mocks behave as before.

### 3. Test helpers (pass 21)

- **LOW** (confidence: high) `tests/unit/loa-decisions-surface.bats:127-131` — `_path_without a b` excludes nothing: `local IFS=:` is in effect when `for t in $skipwords` runs, so a two-word skip list is one token (pre-existing: the former `$(IFS=' '; echo "$*")` was split by the same outer IFS; the rewrite preserved the behaviour and its comment overstates it). Failure: a future multi-tool degraded-path test would run with both tools still on PATH and pass vacuously; the three in-tree calls are single-argument, so nothing is vacuous today.
**Suggestion:** build the skip array before switching IFS (`IFS=' ' read -r -a skips <<<"$*"`) and add a case asserting `_path_without yq jq` removes both → follow-up bead.
- **LOW** (speculative, confidence: low) `tests/unit/red-test-check.bats:160-170` — the batched `ln -s -- "${batch[@]}" "$shim/"` keeps the former hard-fail semantics, but on a host where a PATH directory is case-sensitive and `BATS_TEST_TMPDIR` is not (macOS default), two basenames differing only by case both enter the batch and `ln` reports EEXIST for the second. Failure: a hard setup failure on such a mixed host where the per-file loop's `-e` test tolerated the second name; GNU, BSD and busybox `ln` all continue past the failed source, so nothing else changes. No in-tree PATH carries such a pair.

### 4. Documentation of divergences and lazy flags

- **LOW** (confidence: high) `.claude/scripts/grimoire-index.sh:160-166` — an unreadable vision file now emits one `WARN` line instead of three `grep` permission errors; the per-pass row names it but the report's "Accepted divergences" list did not. Failure: an operator diffing stderr across versions on an unreadable vision file finds the change undocumented in the summary. Fixed during this review: `reviewer.md` § Accepted divergences gains item 6.
- **LOW** (confidence: high) `.claude/scripts/compat-lib.sh:57-70` — the six `_COMPAT_*` flags are empty until a helper's `_compat_need_*` guard runs. Failure: a project-side script that sources the lib and reads `_COMPAT_OS` directly (none in-tree except `lib/dx-utils.sh:427-429`, now guarded) sees `""` where it saw `linux`/`darwin`, so a `[[ "$_COMPAT_OS" == darwin ]]` branch never fires until a helper has run. The lib header documents it; the CHANGELOG bullet should say it in one sentence (added in the release-notes pass of Sprint 2's close).
- **LOW** (confidence: medium) `tests/unit/perf-spawn-budget.bats:1-40` — the budgets were measured on one toolchain (bash 5.2, mawk 1.3.4, jq 1.7, mikefarah yq 4.44; now recorded in the header). Failure: a CI runner whose bash prints a different number of internal trace lines trips a budget that is not a spawn regression; the +10 % / +3 and +2 headroom absorb small differences and the PR's Shell Tests run is the proof.

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and no `adversarial-rejected-review*.jsonl` sidecar exists beside the envelope.

---

## Cross-Model Observations

Dissent: `adversarial-review.sh --type review --sprint-id sprint-281 --diff-file <code-only diff of main...HEAD over .claude, tests, CHANGELOG.md> --context-file reviewer-concerns.md --budget 700` (a first run with `--diff-range main...HEAD` was refused `budget_exceeded`: estimate 624c against the 200c config budget, because the range carries 140 KB of planning prose; the code-only diff is 95 KB). Envelope `a2a/sprint-281/adversarial-review.json`: status `clean`, primary gpt-5.5-pro (answered via codex-headless), companion claude-headless `succeeded` / `independent_voice`, 2/2 voices, consensus APPROVED, 6 ADVISORY findings, 0 blocking, `cost_usd` 0 (subscription routes).

| Finding | Voice | Triage |
|---|---|---|
| DISS-C-003 tracer undercounts spawns under `2>/dev/null` and in child shells | claude-headless | CONFIRMED by a probe (plain `bash -x` counted 1 of 3; `BASH_XTRACEFD` 2; plus `SHELLOPTS=xtrace` 3) → fixed red-first: 74790b2d1 (case (g) fails EXT=1) → d005a771a (passes EXT=4; budgets re-measured) |
| DISS-C-004 live config read by the traced hooks; `EXT_RE` misses g-prefixed tools; small-budget headroom | claude-headless | Config claim REFUTED for the three targets: `implement-gate.sh:174,188` honours `PROJECT_ROOT` (the fixture dir has no `.loa.config.yaml`, so defaults apply), `notes-size-guard.sh` reads no config (`LOA_GRIMOIRE_DIR` only), `run-mode-stop-guard.sh` reads `LOA_PUSH_CONFIG`; a trace assertion now fails the test if the live config path appears. `EXT_RE` and headroom parts ADOPTED in d005a771a; the toolchain is recorded in the header |
| DISS-C-005 registry seams; `cli_adapter_types()` eager import on the kind:cli path | claude-headless | Observation 2 (MEDIUM, bead): no in-tree patching; adapters import optional SDKs lazily; cheval.py:490 confirmed as a caller |
| DISS-C-006 `/\000/` under BWK awk; BSD `cut -c` is character-based | claude-headless | Observation 1 (MEDIUM): BWK awk UNVERIFIED here (build started); Sprint 2 Task 2.1 portability matrix extended |
| DISS-C-001 `_path_without` multi-word skip list under `IFS=:` | claude-headless | Observation 3 (LOW, pre-existing, no in-tree multi-argument call) |
| DISS-C-002 batched `ln -s` EEXIST on mixed case-sensitivity hosts | claude-headless | Observation 3 (LOW, speculative) |

The primary voice returned no findings of its own and concurred with the approval.

---

## Acceptance Criteria Check

### Sprint 1 (global 281) — sprint.md 1.1 § Acceptance Criteria

| Criterion | Status | Notes |
|-----------|--------|-------|
| FR-1 AC rows all green (walkthrough; review `All good`; audit `APPROVED`; verdict-derive CONSISTENT; `COMPLETED`; ledger 281 `completed`) | Pass (walkthrough and this review); audit, marker and ledger follow | `reviewer.md` per-pass table: 22 rows — 20 productive passes with parity inputs, covering bats and counts, before/after, verdict and commit; passes 12 and 15 with their floors; `## AC Verification` walks the sprint 1.1 criteria verbatim |
| Every gate fix commit red-first / byte-identical; the pass harness re-run; both lint tools clean at every fix commit | Pass | 74790b2d1 adds case (g), which fails on the old tracer (`EXT=1`, expected 4); d005a771a makes it pass; pass 22's harness is the bats file itself (7/7); `tools/check-no-raw-sha256sum.sh` OK and `tools/check-no-swallowed-jq.sh --quiet` rc 0 on d005a771a; no System Zone file changed, so no manifest regeneration was due |
| Each verdict names `reviewed_head`; a later code commit re-runs the gate | Pass | This file: d005a771a |
| Reverted loop pass handling | Pass (vacuous) | No pass reverted |
| Evidence copied to `a2a/sprint-281/evidence/`; external artefact sha256 in `e2e.md` | Pass (copy); sha256 rows at 1.E2E | 98 files + the review's TAPs (`tap/covering-d005a771a.tap`, `tap/companion-serial-c0d41f5e3.tap`); sha256 list drafted in `a2a/sprint-282/prep.md` |
| `perf-spawn-budget.bats` green, `check-loa.sh`, `repo-map-gen.sh --validate` on the final head | Pass | d005a771a: 1..7 ok; "All checks passed"; "REPO-MAP.md consistent with .claude/ code." |
| G-3: no touched row above 110 % of its `final-table.tsv` mean, serial idle host | Pass | `final-table.tsv` is the serial idle-host re-baseline on c0d41f5e3; the fix commits touch only a test file, so no code path changed |
| G-4: only the three R-4 KF-034 tests fail, no new skips; companion file passes serially on the idle host | Pass | `evidence/tap/unit-final-c0d41f5e3.tap`: 7224 tests, not ok = the three `semver evidence` tests (identical set in `unit-baseline-main-9e23cbf84.tap`) + CMP-37 under load; skipped sets identical (133 = 133, same names). Serial whole-file `adversarial-review-companion.bats`: 284/284 ok, 872 s, host fukuoka, 2026-10-28T02:40Z (`evidence/tap/companion-serial-c0d41f5e3.tap`) — CMP-37 passes in the whole-file serial run, so the earlier failure was load |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (full diff read; the only token-shaped strings are pre-existing test-fixture redaction probes)
- [x] Input validation and sanitisation present — `san()` / `SAN_AWK` are byte-for-byte twins of the former `tr | sed | cut` pipelines under `LC_ALL=C`; KF, decisions, handoff and notes bodies stay sanitised at surfacing; no new `eval` or data source
- [x] Fail-open / fail-closed semantics of the four fences unchanged: implement-gate still ASKs on an unparsable payload (mode U) and ALLOWs a parsed payload without a path (`implement-gate.sh:216-241, 261-280`); notes-size-guard's multi-document last-document rule is reproduced by the `reduce` (`notes-size-guard.sh:37-42`); karpathy and the Stop guard take their fast paths only on charset-safe / exactly-N-line shapes with the verbatim fallback
- [x] No SQL/XSS; no network code touched
- [x] Dependencies unchanged (the only new import is stdlib `importlib`)
- [x] Error messages unchanged on every degraded path (per-pass fixture matrices; the enumerated divergences are a dropped bash NUL warning, one WARN for an unreadable vision file, and a shifted bash warning line number)
- [x] Trust surfaces: `_check_trust_store` untouched (pass 12 changed nothing); the lazy adapter import changes no credential handling

---

## Code Quality Summary

**Strengths:**
- One pass = one commit with a parity harness, a fresh-context Opus review and the orchestrator's own re-derivation; divergences enumerated and now complete.
- "Fast path with verbatim fallback" keeps error text and exit codes byte-identical by construction (passes 7, 9, 10, 11, 16, 18).
- The spawn-budget guard turns the gains into a deterministic regression check; after this review's fix it also sees the spawns the hooks hide behind stderr redirects and child shells.
- Manifests regenerated per commit; `check-loa.sh` green.

**Areas for Improvement:**
- The one-jq programs (implement-gate, notes-size-guard, run-checkpoint) are dense; each states the shape it accepts, which is the right mitigation, and the fixture harnesses now live under `a2a/sprint-281/evidence/` for the next editor.
- Complexity: no function grew past its previous size class; `emit_kf`'s awk program is ~60 lines as before; nesting ≤ 3; no duplicate blocks introduced. Over-engineering pass: `Lean already. Ship.`

---

## Next Steps

1. `/audit-sprint sprint-1` on d005a771a (the audit names its own `reviewed_head`).
2. On `APPROVED`: `COMPLETED` marker, ledger sprint 281 `completed`, `a2a/sprint-281/e2e.md` (G-1/G-3/G-4 evidence, the external artefact sha256 list, the BWK awk result).
3. Beads for the observations: registry seams (obs 2), `_path_without` skip list (obs 3), compat-lib CHANGELOG sentence (obs 4); Sprint 2 Task 2.1 brief gains the BWK awk matrix (obs 1).

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":5},"excluded":0,"sprint_id":"sprint-281","ts":"2026-10-28T03:05:00Z"} -->
