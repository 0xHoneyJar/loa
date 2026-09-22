# PR Review: refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**Scope:** `head.diff` against `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh` (no sprint plan / grimoires context provided for this review)

---

## Overall Assessment

This PR frames itself as a cleanup ("single code path again", "release-only version parsing"), but the `audit_envelope.py` hunk is a real security regression, not a simplification: it deletes the merge-gate strict-verification path (`verify_for_merge` / `LOA_AUDIT_STRICT_VERIFY`) while leaving the surrounding docstrings and inline comments referencing the exact threats (`ATK-3`, `ATK-4`, issue #690) that path was built to close — the code and its own comments now contradict each other. The `spiral-evidence.sh` change reopens a previously-fixed false-positive class (#1175) for one of its two path-extraction patterns. The `semver-bump.sh` change removes a validation filter that made tag-based version resolution resilient to malformed/legacy tags, not just prerelease ones.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — audit trust-chain verification

- **CRITICAL** (confidence: high) `head/.claude/adapters/loa_cheval/audit_envelope.py:462-473` — `_check_trust_store()` now unconditionally treats `BOOTSTRAP-PENDING` as passing, with no way for a caller to demand `VERIFIED`.
**File:** `head/.claude/adapters/loa_cheval/audit_envelope.py:466-469`
**Issue:** The removed `_strict_verify_enabled()` / `strict_verify` parameter previously let a caller (per the surviving docstring at line 508-518 and the removed function's own docstring, "True when verification is running as a merge gate") require a fully signed, `VERIFIED` trust-store and reject `BOOTSTRAP-PENDING`. That branch is gone; `_check_trust_store()` now has exactly one behavior for every caller, dev and merge-gate alike.
**Why This Matters:** `audit_verify_chain` is a public, exported API (`__all__` at line 642-648) explicitly documented as a "Gate function called at top of audit_emit + audit_verify_chain" for issue #690. If any merge-time or CI caller was invoking `audit_verify_chain(log_path, verify_for_merge=True)` to insist on a bootstrapped, signed trust-store before accepting an audit chain as valid, that caller now (a) gets a `TypeError: audit_verify_chain() got an unexpected keyword argument 'verify_for_merge'` if it still passes the kwarg, or (b) silently downgrades to accepting an unbootstrapped trust-store as valid if the kwarg is dropped elsewhere in the same change. Either way, the ATK-3 threat this code explicitly names ("strict audit verification refuses BOOTSTRAP-PENDING") is no longer mitigated for anyone, including a hypothetical merge gate that most needs it.
**Required Fix:** Either restore the `strict_verify`/`verify_for_merge` parameter and its enforcement, or — if the intent is genuinely to retire the merge-gate mode — grep the rest of the codebase (not included in this diff) for `verify_for_merge=` / `LOA_AUDIT_STRICT_VERIFY` callers and remove/update them in the same PR, and update the docstrings that still reference ATK-3/#690 strict semantics so they don't describe protection the code no longer provides.
**Reference:** CWE-863 (Incorrect Authorization) / OWASP A01:2021 (Broken Access Control) — a security control that silently degrades based on which caller invokes it.

- **CRITICAL** (confidence: high) `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160` — `_resolve_pubkey_pem()` no longer supports refusing the local `<key_id>.pub` fallback, so signature verification can always be satisfied by a locally-planted key file.
**File:** `head/.claude/adapters/loa_cheval/audit_envelope.py:156-159`
**Issue:** The removed `allow_local_fallback` parameter (previously threaded from `audit_verify_chain`'s `strict_verify`) let merge-gate verification refuse the "test/CI fallback" pubkey path and require trust-store-resolved keys only. Now `_resolve_pubkey_pem` always falls back to `<key-dir>/<key_id>.pub` on disk with no way to disable it.
**Why This Matters:** Combined with finding #1 above, an attacker (or a compromised local checkout) who can write a `.pub` file into `LOA_AUDIT_KEY_DIR` can make `audit_verify_chain` "verify" a signature against a key of their choosing, even in what used to be the strict/merge-gate path. This is the same class of trust-boundary bypass the docstring's own "test/CI fallback, refused in strict verify" language was written to prevent.
**Required Fix:** Same as #1 — either restore the strict-mode refusal of the local fallback, or justify in the PR description why local-fallback pubkeys are now safe to accept unconditionally (e.g., if the trust-store is now the sole source of truth and the local `.pub` path is being deprecated entirely, that deprecation should be explicit and verified, not incidental).

- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/audit_envelope.py:476-494` — `_read_trust_cutoff()` silently returns `None` when the trust-store is missing or unreadable, in every mode, disabling the F1 strip-attack cutoff check (`STRIP-ATTACK-DETECTED`) whenever the trust-store can't be read.
**File:** `head/.claude/adapters/loa_cheval/audit_envelope.py:484-486, 493-494`
**Issue:** The removed strict-mode branches raised `[TRUST-STORE-MISSING]` / `[TRUST-STORE-UNREADABLE]` (citing ATK-4) specifically so that a merge-gate verification would fail closed rather than silently grandfather every entry as "pre-cutoff." With those branches gone, `cutoff` is `None` whenever the trust-store is unreadable, `_ts_ge_cutoff` (line 497-505) then always returns `False`, and the strip-attack defense described at line 520-523 ("signature required post-cutoff... Stripping either is a downgrade attack") can never fire against a chain whose trust-store has been deleted or corrupted.
**Why This Matters:** This turns "trust-store unreadable" from a hard failure into a silent downgrade of the exact attack the surrounding code calls out by name (ATK-4, strip-attack). An attacker who can delete or corrupt the trust-store file no longer needs to also forge a valid cutoff bypass — the code does it for them.
**Required Fix:** Restore fail-closed behavior for the merge-gate path (or, if strict mode is being retired outright, make that decision explicit in the PR description and confirm no caller relies on ATK-4 protection).

### 2. Spiral evidence gate — reintroduced false-positive class

- **HIGH** (confidence: medium) `head/.claude/scripts/spiral-evidence.sh:670-703` — removing the `content_bare` backtick-stripped pre-pass means Pattern 2 (bare top-level-prefix paths) now scans text that is still inside backtick spans, without the false-positive guards Pattern 1 applies.
**File:** `head/.claude/scripts/spiral-evidence.sh:697-703`
**Issue:** In `base`, `content_bare` (base line 673-674) stripped every backtick-delimited span out of `$content` before Pattern 2 ran, so bare-prefix matching (`src|tests|.claude/scripts|.claude/hooks|grimoires`) never saw text quoted for other reasons — e.g., a sprint doc's prose like `` `bash .claude/scripts/example-check.sh --dry-run` `` or `` `grimoires/loa/example.md` `` used purely as an illustrative reference, not a deliverable declaration. Pattern 1 has explicit false-positive guards for exactly this (the `grep -v` chain at lines 683-692, citing issue #1175: "backtick prose also wraps shell commands... and CLI flags... failing cycles with IMPL_EVIDENCE_MISSING"), but Pattern 2 has none of those guards. Previously, `content_bare` protected Pattern 2 from ever seeing backtick-quoted prose at all; now Pattern 2 runs on raw `$content` (line 701) and will match any `.claude/scripts/*.sh`-shaped substring inside a backtick span just as readily as a bare one.
**Why This Matters:** This is the same failure mode issue #1175 was opened for: `_pre_check_implementation_evidence` treats every path this function returns as a required deliverable that must exist on disk post-implementation. A sprint.md that merely *mentions* a script path in backtick-quoted prose (common in "Technical Tasks" / "Risks" sections) can now cause a spurious `IMPL_EVIDENCE_MISSING` failure for a file that was never meant to be a deliverable, blocking a legitimate implementation cycle.
**Required Fix:** Either keep stripping backtick spans before Pattern 2 runs, or add the same false-positive guard chain (no whitespace, no globs, no leading `-`/`@`) to Pattern 2's output before the final `sort -u`.

### 3. semver-bump.sh — lost tag-validation safety net

- **HIGH** (confidence: medium) `head/.claude/scripts/semver-bump.sh:53-58` — `get_version_from_tag()` dropped the `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` validation filter entirely, not just the prerelease branch, so it now returns whatever `git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1` produces without checking it's well-formed.
**File:** `head/.claude/scripts/semver-bump.sh:56`
**Issue:** The glob `v[0-9]*.[0-9]*.[0-9]*` matches far more than clean release tags — e.g. `v1.2.3-rc.1`, `v1.2.3.4`, `v1.2.3-anything`, or any other stray/legacy tag a repo has accumulated. In `base`, the `grep` stage filtered the sorted candidate list down to well-formed release/prerelease tags before taking the top one, so a single malformed or leftover tag couldn't derail version resolution — the next valid tag down the list would be picked instead. In `head`, `head -1` is applied directly to the unfiltered, glob-matched list.
**Why This Matters:** `bump_version()` (line ~90) validates its `current` argument against `^[0-9]+\.[0-9]+\.[0-9]+$` and hard-errors (`return 1`) on mismatch. Any tag in the repo's history that loosely matches the glob but isn't a clean `vMAJOR.MINOR.PATCH` — including any prerelease tag left over from before this policy change, per the PR's own description of "release-only version parsing" — now aborts the entire version-bump computation instead of being skipped in favor of the next valid tag. This is release automation the framework explicitly calls out as merge-critical (`CLAUDE.loa.md` "NEVER create tags manually — always use semver-bump.sh for version computation").
**Required Fix:** Keep a validation/filter stage in `get_version_from_tag()` — even a release-only regex (`^v[0-9]+\.[0-9]+\.[0-9]+$`) — so a single non-conforming tag can't hard-fail the whole script; log a warning and continue to the next candidate rather than failing on the first match.

---

## Observations

### 1. Documentation drift

- **LOW** (confidence: high) `head/.claude/adapters/loa_cheval/audit_envelope.py:508-518` — `audit_verify_chain`'s docstring still describes signature/cutoff semantics accurately but no longer mentions that a merge-gate strict mode ever existed; combined with the still-present `# Issue #690 (Sprint 1.5): auto-verify trust-store before chain walk.` comment at line 531, a future reader has no signal that strict verification was removed rather than never having existed. If the removal in this PR is intentional, the module docstring and changelog/CHANGELOG entry should say so explicitly rather than leaving stale references to ATK-3/ATK-4/#690 mitigations that no longer apply.

### 2. semver-bump.sh comment additions are fine

- **LOW** (confidence: high) `head/.claude/scripts/semver-bump.sh:54, 79` — the two new one-line comments ("Get current version from the latest git tag...", "Bump a version string by type") are harmless and in line with the project's "no comments unless non-obvious" norm being slightly relaxed for brief section headers; not blocking.

---

## Security Checklist

- [ ] No hardcoded secrets or credentials — N/A, none introduced
- [x] Input validation and sanitization present — `bump_version` still validates format (partially; see Changes Required #3 for the upstream gap)
- [ ] Authentication/authorization correct — **FAILS**, see Changes Required #1 and #2 (trust-store/signature verification downgraded)
- [ ] No SQL/XSS injection vulnerabilities — N/A
- [ ] Dependencies secure (no known CVEs) — N/A, no dependency changes
- [x] Error messages don't leak sensitive data — unaffected by this diff

---

## Code Quality Summary

**Strengths:**
- The diff is small, focused, and easy to read line-by-line; each file's change matches its stated intent in the PR description.
- `semver-bump.sh`'s two added comments improve readability without violating the "no comments unless non-obvious" convention.

**Areas for Improvement:**
- Deleting a security control should be justified in the PR description with evidence that no caller depends on it (grep results, caller list, or an explicit deprecation note), not left to the reviewer to infer from comments the same commit didn't update.
- When two code paths (Pattern 1 vs Pattern 2 in `spiral-evidence.sh`) share a false-positive concern, a guard removed from a shared pre-processing step needs to be re-verified against *both* consumers, not just the one the PR author was focused on.

---

## Next Steps

1. Restore or explicitly, verifiably retire the merge-gate strict-verification path in `audit_envelope.py` (Changes Required #1-3), updating stale ATK-3/ATK-4/#690 comments either way.
2. Restore the backtick-exclusion guard for Pattern 2 in `spiral-evidence.sh`, or give it its own false-positive guard chain.
3. Restore a validating filter stage in `semver-bump.sh`'s `get_version_from_tag()`.
4. Re-submit for review once addressed.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":3,"medium":0,"low":2},"excluded":0,"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
