# PR Review: chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-21
**Scope:** `head.diff` (3 files) — no sprint plan/beads/a2a artifacts available for this PR-only review

---

## Overall Assessment

The PR removes three independent pieces of error/shape-normalization logic across the cheval headless adapter, the flatline consensus pipeline, and the construct-index generator. Despite being framed as a "chore," all three hunks are behavior changes, not pure cleanup: each removed block was specifically written to guard against a real, previously-anticipated failure mode (spawn errors, malformed skeptic JSON, author-declared compose_with/event overlays), and none of the removals are accompanied by a replacement, a test, or a rationale that the guarded condition can no longer occur. The diff reads as a straight revert of prior defensive code with no evidence the underlying triggers were eliminated.

**Verdict:** CHANGES REQUIRED

---

## Critical Issues (Must Fix Before Approval)

### 1. Spawn-failure exceptions now escape `ClaudeHeadlessAdapter.complete()` unwrapped, breaking the provider-chain-walk fallback contract

**File:** `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-181`
**Issue:** The inner `try` around `run_subprocess_pgkill(...)` (line 159) previously caught `OSError` and `ValueError` in addition to `subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`, and `FileNotFoundError`, wrapping each into a typed cheval exception (`ProviderUnavailableError`/`ConfigError`). This PR deletes only the `OSError` and `ValueError` handlers (base had them at `base/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:183-192`). The comments removed alongside them ("ARG_MAX / ENOMEM / exec error", "embedded NUL in the prompt") describe real `subprocess.Popen`/`os.posix_spawn` failure modes — `OSError` on `E2BIG`/`ENOMEM`/exec failures, `ValueError` when argv contains an embedded NUL byte. Neither is hypothetical; they are exactly the conditions Python's `subprocess` module raises for large-prompt or corrupted-argv cases, which this exact adapter is prone to (it builds `cmd` from a flattened, potentially very large prompt — see the adapter's own docstring on prompt flattening).
**Why This Matters:** With the typed handlers gone, these exceptions now propagate straight out of `complete()` as raw `OSError`/`ValueError`. Every other failure path in this method (timeout, output-cap, missing binary, semaphore exhaustion) is deliberately normalized into `ProviderUnavailableError`/`ConfigError` specifically so the cheval dispatch layer can catch known-provider-failure types and chain-walk to the next provider (per `CLAUDE.loa.md`: "chain-walk on retryable errors; voice-drop on chain exhaustion"). An unwrapped `OSError`/`ValueError` is very unlikely to be one of the caught types at the dispatch layer, so a single provider-local spawn failure (e.g., a temporarily huge prompt during a flatline/bridgebuilder review) now risks crashing the whole multi-model call instead of gracefully falling back to the next model in the chain — a regression in exactly the resiliency behavior this adapter exists to provide.
**Required Fix:** Restore the `except OSError` and `except ValueError` handlers (or otherwise re-verify, with evidence, that `run_subprocess_pgkill`/`build_headless_subprocess_env` now make these conditions unreachable) so all spawn-failure classes are normalized into typed cheval exceptions before leaving `complete()`.
**Reference:** Python docs — `subprocess.Popen` raises `OSError` for exec/resource failures; `ValueError` is raised for arguments containing embedded null bytes.

```python
# Current (problematic) — head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:178-181
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
                    ) from exc
                # OSError / ValueError now fall through uncaught

# Should be (base/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:178-192)
                except FileNotFoundError as exc:
                    raise ConfigError(...) from exc
                except OSError as exc:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"claude -p spawn failed (ARG_MAX / ENOMEM / exec error?): {exc}",
                    ) from exc
                except ValueError as exc:
                    raise ProviderUnavailableError(
                        self.provider,
                        f"claude -p got un-executable argv (embedded NUL in the prompt?): {exc}",
                    ) from exc
```

### 2. Skeptic-envelope shape normalization removed — malformed/array-shaped skeptic output is no longer coerced before reaching the scoring engine

**File:** `head/.claude/scripts/flatline-orchestrator.sh:1597-1598,1626`
**Issue:** `normalize_skeptic_envelope()` (present in `base/.claude/scripts/flatline-orchestrator.sh:297-313`, deleted entirely in this PR) took the output of `extract_json_content` and coerced it: object → pass through, bare array → wrap as `{concerns: .}`, anything else → `{"concerns":[]}`. This PR removes the function and all three call sites (`gpt_skeptic_prepared`, `opus_skeptic_prepared`, `tertiary_skeptic_prepared`). `extract_json_content` (line 261) only strips markdown fences/BOM/prose wrapping via `normalize_json_response` — it does **not** guarantee the result is a JSON object with a `.concerns` key. If a skeptic model emits a bare JSON array (which is exactly the case this function was written to handle) or any other non-object shape, that shape now flows unmodified into `$gpt_skeptic_prepared`/`$opus_skeptic_prepared`/`$tertiary_skeptic_prepared`, which are passed directly to `"$SCORING_ENGINE" --skeptic-gpt/--skeptic-opus/--skeptic-tertiary` at `head/.claude/scripts/flatline-orchestrator.sh:1632-1638`.
**Why This Matters:** `scoring-engine.sh` is not part of this diff, so its exact `--skeptic-*` parsing isn't directly visible in this review, but the call-site default (`'{"concerns":[]}'`) and the deleted normalization function both signal the engine expects an object with a `.concerns` array. Feeding it a bare JSON array reintroduces exactly the malformed-input case `normalize_skeptic_envelope` was built to prevent — best case the engine silently treats it as zero concerns (defeating the skeptic pass entirely and producing false-confidence consensus scores), worst case a `jq` `.concerns` lookup on a top-level array errors out and the whole flatline run fails.
**Required Fix:** Restore `normalize_skeptic_envelope()` and its three call sites, or, if the intent is that `scoring-engine.sh` was changed elsewhere to accept raw shapes, provide that evidence/diff — it is not present here.

### 3. `construct.yaml` no longer overrides manifest events or declares `compose_with` — silently dropped, not just reverted

**File:** `head/.claude/scripts/construct-index-gen.sh:302-303,396,414-421`
**Issue:** Three related behaviors are removed simultaneously:
  - `emits_json`/`consumes_json` (lines 302-303) previously fell back across `(.name // .event // .type)` / `(.event // .name // .type)`; now they read **only** `.name` for emits and **only** `.event` for consumes (`base/.claude/scripts/construct-index-gen.sh:301-302` had the 3-way fallback). Any manifest whose event objects use `.type` (or emits using `.event`, consumes using `.name`) will now silently produce empty `emits`/`consumes` arrays for that event — the `// empty` in the jq filter drops the entry rather than warning.
  - The `construct.yaml` overlay for `cy_emits`/`cy_consumes` (present in `base/.claude/scripts/construct-index-gen.sh:333-337`) is gone entirely — a pack author can no longer override/extend manifest-declared events via `construct.yaml`.
  - `compose_with_json` (read from `construct.yaml`'s `.compose_with[].slug` in `base/.claude/scripts/construct-index-gen.sh:309,330`) is deleted. `process_pack` now hardcodes `composes_with: []` (line 396) for every construct, and `compute_composition()` (lines 404-421) computes `composes_with` **purely** from write/read overlap — the base version's `+ ($current.composes_with // [])` merge (`base/.claude/scripts/construct-index-gen.sh:431`) that preserved author-declared relationships is gone, replaced by a bare `| unique` at line 421. An author-declared `compose_with` entry for two constructs that don't happen to share a computed read/write overlap (e.g., an event-based or documentation-only composition relationship) is now silently and unconditionally discarded on every index regen.
**Why This Matters:** This is data loss with no warning, log line, or migration path: any existing `construct.yaml` in the pack tree that declares `events.emits`/`events.consumes` overrides or a `compose_with` list will have that authored intent silently dropped the next time `construct-index-gen.sh` runs, with no error to signal the config is now inert. Since packs live outside this diff's file set, it isn't possible from this review alone to confirm whether any current pack actually relies on these fields — but the removal itself is the kind of change that needs that verification before merge, not after.
**Required Fix:** Either (a) restore the 3-way event-name fallback, the `construct.yaml` event overlay, and the `compose_with` read+merge, or (b) if this is a deliberate schema simplification, grep the actual pack tree (`packs/*/construct.yaml`, `packs/*/manifest.json`) for `compose_with:`, `events.emits`, `events.consumes` usage and confirm zero live packs depend on the removed fields, then note that verification in the PR description. Neither is present in this PR as submitted.

---

## Non-Critical Improvements (Recommended)

### 1. PR description doesn't explain *why* these guards are being removed

**File:** `PR.md`
**Suggestion:** The PR title/body state *what* is removed but not *why* (e.g., "these conditions can no longer occur because X" or "scoring-engine.sh was simplified to accept both shapes"). For a change that's pure removal of defensive/normalization code across three unrelated files, a rationale is the difference between a safe cleanup and a silent regression.
**Benefit:** Reviewers (and future maintainers) can distinguish "this guard is now provably dead code" from "this guard was silently deleted along with the bug it fixed."

---

## Acceptance Criteria Check

No sprint plan or acceptance criteria exist for this PR-only review (per `REVIEW-INSTRUCTIONS.md`); assessed against implied correctness/robustness of the change itself.

| Criterion | Status | Notes |
|-----------|--------|-------|
| Spawn failures in claude-headless adapter remain typed cheval exceptions | Fail | `OSError`/`ValueError` now escape unwrapped — see Critical #1 |
| Skeptic consensus input remains a well-formed `{concerns:[...]}` envelope | Fail | Normalization removed — see Critical #2 |
| construct.yaml-declared events/compose_with continue to be honored | Fail | Silently dropped — see Critical #3 |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] No SQL/XSS injection vulnerabilities
- [N/A] Authentication/authorization — not touched by this diff
- [ ] Error messages don't leak sensitive data — N/A, but note Critical #1 means raw `OSError`/`ValueError` messages (which can include full argv/env details) may now surface uncaught to callers instead of being wrapped in a controlled `ProviderUnavailableError` message
- [x] Dependencies unaffected

---

## Code Quality Summary

**Strengths:**
- Each individual diff hunk is small, easy to read, and self-contained.
- The adapter file retains its excellent docstring/comment discipline even where the diff removes code.

**Areas for Improvement:**
- All three hunks remove error-handling/normalization code without a corresponding test change, changelog entry, or explanation — for a "chore" PR touching resiliency-critical paths (provider fallback, consensus scoring, index generation), that combination is a red flag on its own regardless of intent.

---

## Adversarial Analysis

### Concerns Identified (minimum 3)

1. **Correctness/resiliency** - `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-181`
   Removing the `OSError`/`ValueError` handlers turns a graceful per-provider fallback into a potential hard crash of the whole multi-model dispatch on a single adapter's spawn failure.

2. **Correctness** - `head/.claude/scripts/flatline-orchestrator.sh:1597-1598,1626`
   Skeptic JSON shape is no longer guaranteed to be `{concerns:[...]}` before being handed to `scoring-engine.sh`, reopening the exact malformed-input case the deleted function existed to close.

3. **Data loss / silent config drop** - `head/.claude/scripts/construct-index-gen.sh:396,414-421`
   Author-declared `compose_with` and event overlays in `construct.yaml` are discarded with zero warning on every index regeneration, with no verification in this PR that no live pack depends on them.

4. **Schema narrowing** - `head/.claude/scripts/construct-index-gen.sh:302-303`
   Event field-name fallback narrowed from 3 accepted keys (`name`/`event`/`type`) to 1, which can silently zero out `emits`/`consumes` for manifests using the now-unsupported key names.

### Assumptions Challenged (minimum 1)

- **Assumption**: The author assumes the conditions these three guards protect against either never occur in practice or have been fixed at a different layer (e.g., `scoring-engine.sh` was updated to accept bare arrays, or `run_subprocess_pgkill` was hardened against `ARG_MAX`).
- **Risk if wrong**: Each of the three failure modes (unhandled spawn exception, malformed skeptic envelope, dropped compose_with/events) reintroduces a previously-fixed defect, and because all three are silent (no test failure, no log warning), they'd surface as confusing downstream failures — chain crash, false-confidence consensus, or a stale/incorrect construct index — long after this PR merges, with no trace back to this change.
- **Recommendation**: The PR should state explicitly, per file, why the removed guard is no longer needed (with a pointer to the corresponding fix elsewhere, e.g., a `scoring-engine.sh` diff or a `run_subprocess_pgkill` hardening commit), or the guards should be restored.

### Alternatives Not Considered (minimum 1)

- **Alternative**: If the goal is genuinely to simplify these three files (per the "chore" framing and Karpathy simplicity-first guidance in `CLAUDE.loa.md`), the safer path is a targeted revert of only the pieces that are provably unused/dead (verified via grep against live pack/config data and against `scoring-engine.sh`'s actual input contract), landed as three separate PRs with rationale — rather than one bundled removal across three unrelated subsystems (adapter error handling, consensus normalization, index generation) with no shared root cause given.
- **Tradeoff**: Three small, justified PRs take more review overhead up front but let each removal be verified against its actual blast radius; one bundled "chore" PR is faster to land but makes it much harder for a reviewer (or `git bisect`) to isolate which removal caused a downstream regression.
- **Verdict**: Should reconsider — the current bundling of three independent, unrelated-looking regressions under one "chore" title is itself a review-quality concern, separate from the correctness of each individual removal.

### Adversarial Verdict

BLOCKING — all three concerns above map directly to the Critical Issues section; none are documented as intentional/verified in the PR.

---

## Next Steps

1. Restore (or provide concrete evidence of an equivalent replacement for) the `OSError`/`ValueError` handlers in `claude_headless_adapter.py`.
2. Restore `normalize_skeptic_envelope()` in `flatline-orchestrator.sh`, or show that `scoring-engine.sh` was updated to accept the un-normalized shapes.
3. Restore (or justify with a grep-verified "no live pack depends on this" note) the `construct.yaml` event-overlay and `compose_with` merge logic in `construct-index-gen.sh`, and restore the 3-way event field-name fallback.
4. Split the PR along subsystem boundaries so each removal can be reviewed and bisected independently.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":3,"high":0,"medium":1,"low":0},"sprint_id":"pr-06","ts":"2026-09-21T00:00:00Z"} -->
