# PR Review: refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**Scope:** `head.diff` — `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh`

---

## Overall Assessment

This PR touches three files, all inside the System Zone (`.claude/`). Per `zone-system.md`, System Zone writes require explicit cycle-level approval in the PRD — nothing in `PR.md` establishes that authorization, but that is a process gap I can only flag, not adjudicate from the diff alone.

More importantly, the `audit_envelope.py` change is not a simplification — it deletes the only mechanism this file had for enforcing strict trust-store verification at merge time, including two protections that were added against named attack scenarios (ATK-3, ATK-4) and tracked under issue #690. The PR description ("drop strict-verify plumbing") does not explain why those protections are no longer needed, and nothing in the diff shows the threat they defended against has gone away. This is a security regression, not a refactor, and is the primary reason I'm requesting changes.

The `spiral-evidence.sh` change reintroduces a false-positive class (issue #1175) that a prior fix explicitly guarded against, for the bare-path matching branch.

The `semver-bump.sh` change is a legitimate, intentional scope reduction (release-only versioning) with one minor robustness regression in tag selection.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — merge-gate strict verification removed entirely

- **CRITICAL** (confidence: high) `head/.claude/adapters/loa_cheval/audit_envelope.py:469` — `_check_trust_store()` now accepts `BOOTSTRAP-PENDING` (i.e., an unsigned trust-store) unconditionally, with no way to invoke the previously-existing strict/merge-gate behavior.

**File:** `head/.claude/adapters/loa_cheval/audit_envelope.py:459-475` (compare `base/.claude/adapters/loa_cheval/audit_envelope.py:469-486`)
**Issue:** The base version's `_check_trust_store(*, strict_verify: bool = False)` refused an unsigned (`BOOTSTRAP-PENDING`) trust-store when running as a merge gate (`strict_verify=True`), raising `[TRUST-STORE-BOOTSTRAP-PENDING] ... refuses BOOTSTRAP-PENDING (ATK-3)`. The head version drops the `strict_verify` parameter entirely and folds `BOOTSTRAP-PENDING` into the same accept path as `VERIFIED`:
```python
if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
    return
```
There is no longer any code path, parameter, or env var that can make this function refuse an unsigned trust-store. The same is true for `_read_trust_cutoff` (base `head/.claude/adapters/loa_cheval/audit_envelope.py` base:490-517 dropped the `strict_verify` raises for missing/unreadable trust-store, tagged `ATK-4`), and for `_resolve_pubkey_pem` (base `allow_local_fallback` parameter removed at `head/.claude/adapters/loa_cheval/audit_envelope.py:141`, so the `<key-dir>/<key_id>.pub` local-file fallback — documented in the base docstring as "test/CI fallback, refused in strict verify" — is now always available, even for what used to be merge verification).
**Why This Matters:** `audit_verify_chain` is the integrity gate for the audit chain (issue #690, "auto-verify trust-store before chain walk"). The base code's `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY` path existed specifically so that a merge-time verification could refuse: (a) an unsigned trust-store, (b) a missing/unreadable trust-store, (c) a signer key resolved from an unpinned local `.pub` file instead of the trust store. All three are now permitted unconditionally, for every caller, in every context — there is no longer a "strict" mode to opt into. Concrete failure scenario: an actor who can place or leave in place an unsigned `trust-store.yaml` (status `BOOTSTRAP-PENDING`) and drop a `<key_id>.pub` file under the key directory can have arbitrary chain entries verify successfully even during what was previously a hard merge gate — `audit_verify_chain(log_path)` now always takes the permissive path described in the base code as appropriate only for non-merge, non-strict contexts.
**Required Fix:** Restore the `strict_verify`/`verify_for_merge` parameter (or an equivalent explicit strict mode) on `_check_trust_store`, `_read_trust_cutoff`, `_resolve_pubkey_pem`, and `audit_verify_chain`, or provide a documented replacement mechanism for merge-time strict verification. If the intent is genuinely to retire strict verification as a concept, that needs to be justified against issue #690 and the ATK-3/ATK-4 threat model explicitly, not silently dropped in a "plumbing cleanup" PR — and any caller elsewhere in the repo that passes `verify_for_merge=True` needs to be found and updated (none is included in this diff, so either this silently breaks that caller with a `TypeError`, or the strict path was already unused, which itself should be stated and justified rather than inferred).
**Reference:** CWE-295 (Improper Certificate/Trust Validation) / CWE-306 (Missing Authentication for Critical Function) — removing the only path that refused an unsigned trust root at a security-relevant checkpoint.

### 2. Correctness/gate-integrity — backtick pre-pass removal reintroduces issue #1175 false positives

- **HIGH** (confidence: high) `head/.claude/scripts/spiral-evidence.sh:700` — Pattern 2's bare-path match now runs against raw `$content` instead of `$content_bare`, so paths mentioned only inside backtick-quoted command examples (in Risks/Technical Tasks prose, not the Deliverables list) are treated as required deliverables again.

**File:** `head/.claude/scripts/spiral-evidence.sh:670-703` (compare `base/.claude/scripts/spiral-evidence.sh:670-706`)
**Issue:** The base version computed `content_bare` by stripping every backtick-delimited span out of `$content` before running Pattern 2 (the bare, unquoted top-level-prefix path matcher). The head version deletes that step and feeds `$content` directly into Pattern 2. Pattern 2's anchor (`(^|[^a-zA-Z0-9_/.-])`) is satisfied by a leading backtick, so a path with one of the five anchored prefixes (`src|tests|.claude/scripts|.claude/hooks|grimoires`) that appears *inside* a backtick span is matched exactly as if it were bare prose — e.g. `` Run `.claude/scripts/spiral-evidence.sh --check` for details `` in a Risks section now yields `.claude/scripts/spiral-evidence.sh` as a "declared path," even though it's a command reference, not a deliverable.
**Why This Matters:** This is precisely the false-positive class the adjacent comment block (still present, unmodified, at `head/.claude/scripts/spiral-evidence.sh:681-687`) documents as issue #1175: "backtick prose also wraps shell commands ... that contain `/`+extension and matched as deliverable paths, failing cycles with IMPL_EVIDENCE_MISSING." That guard was implemented for Pattern 1 via explicit `grep -v` filters, but the *general* protection for Pattern 2 was the `content_bare` pre-pass this diff removes. The result is a spurious evidence-gate failure (`IMPL_EVIDENCE_MISSING`) whenever a sprint.md Risks/Technical-Tasks section references a `.claude/scripts/`, `.claude/hooks/`, `src/`, `tests/`, or `grimoires/`-rooted file inside backticks as a command example rather than a deliverable declaration. This is fail-closed (blocks merges rather than admits forged evidence), so it is not a security hole, but it directly reintroduces a previously-fixed and issue-tracked correctness bug in a load-bearing CI gate.
**Required Fix:** Keep the `content_bare` pre-pass for Pattern 2 (or otherwise re-derive an equivalent backtick-exclusion for the bare-prefix matcher), or explicitly narrow Pattern 2's anchor so a leading backtick doesn't satisfy the boundary condition. If the backtick pre-pass was removed because it broke something else, that tradeoff needs to be stated — the PR description only says it "lets the spiral evidence gate scan prose without the backtick pre-pass" without explaining why the #1175 protection is being given up.
**Reference:** Issue #1175 (referenced in the unmodified comment at `head/.claude/scripts/spiral-evidence.sh:684`).

---

## Observations

### 1. Robustness — tag-format validation dropped from `get_version_from_tag`

- **MEDIUM** (confidence: medium) `head/.claude/scripts/semver-bump.sh:52-56` — `git tag -l` glob patterns (`v[0-9]*.[0-9]*.[0-9]*`) are not equivalent to the anchored regex the base version applied afterward (`grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'`); a malformed tag (e.g. `v1.2.3.4`, `v1.2.3rc1`) that sorts highest by `--sort=-v:refname` can now be selected as "current" without being filtered out first.
**File:** `head/.claude/scripts/semver-bump.sh:52-56`
**Suggestion:** This fails loud rather than silent — `bump_version`'s `^[0-9]+\.[0-9]+\.[0-9]+$` check (line ~85) will reject a malformed tag and `return 1` with an `ERROR: Invalid version format` message — so it isn't a silent-corruption risk, but it does mean a single stray/malformed tag can block the release script entirely instead of the script skipping to the next well-formed tag as before.
**Benefit:** Re-adding a `grep -E` filter after the `git tag -l` call (or tightening the glob) would restore the old "skip malformed tags" robustness without reintroducing prerelease support.

### 2. Feature removal — prerelease version bumping no longer supported

- **LOW** (confidence: high) `head/.claude/scripts/semver-bump.sh:79-93` — `bump_version` no longer handles `X.Y.Z-alpha.N`/`beta.N`/`rc.N` inputs; any prerelease tag now fails validation instead of incrementing the prerelease counter.
**File:** `head/.claude/scripts/semver-bump.sh:79-93`
**Suggestion:** This appears intentional per the PR title ("returns semver-bump.sh to release-only version parsing") and is consistent with the matching removal of the prerelease tag-list pattern in `get_version_from_tag`. Flagging only so it's a deliberate, confirmed decision rather than an incidental loss — if any existing tags in the repo are prerelease-formatted (`vX.Y.Z-rc.N`), the next bump against them will now hard-fail rather than increment the prerelease counter.
**Benefit:** Worth a one-line confirmation in the PR description that no in-flight prerelease tags exist, since the failure mode is a hard stop rather than silent misbehavior.

### 3. Process — System Zone files modified without visible authorization

- **LOW** (confidence: low) `head/.claude/adapters/loa_cheval/audit_envelope.py:1`, `head/.claude/scripts/spiral-evidence.sh:1`, `head/.claude/scripts/semver-bump.sh:1` — all three changed files sit under `.claude/`, the System Zone, which per `zone-system.md` requires "explicit cycle-level approval in the PRD" for direct edits.
**File:** N/A — process observation, not a code defect
**Suggestion:** `PR.md` gives no cycle/PRD reference. This is out of scope for the code review itself (no sprint plan or PRD was provided for this review), so it's recorded as an observation rather than a blocking finding, but the merge process should confirm this PR carries the required authorization before landing.
**Benefit:** Keeps the framework's own zone-boundary guarantee intact.

---

## Security Checklist

- [ ] No hardcoded secrets or credentials — N/A, none introduced
- [ ] Input validation and sanitization present — `semver-bump.sh` retains format validation; **see Changes Required #1** for the removed trust-store/verification gating
- [ ] Authentication/authorization correct — **FAIL, see Changes Required #1** (strict/merge-gate verification removed)
- [ ] No SQL/XSS injection vulnerabilities — N/A
- [ ] Dependencies secure (no known CVEs) — N/A, no dependency changes
- [ ] Error messages don't leak sensitive data — unaffected

---

## Code Quality Summary

**Strengths:**
- `semver-bump.sh`'s scope reduction is internally consistent (tag-list pattern, `bump_version` logic, and comments all agree) and keeps clear fail-loud error messages.
- New one-line comments added above `get_version_from_tag` and `bump_version` are appropriately terse.

**Areas for Improvement:**
- Security-relevant control removal (`audit_envelope.py`) needs an explicit threat-model justification in the PR description, not a bare "drop strict-verify plumbing" framing — especially when the removed code carries attack-ID references (ATK-3, ATK-4) and an issue number (#690).
- When removing a pre-processing step that exists specifically to prevent a documented false-positive class (`spiral-evidence.sh`, issue #1175), the adjacent comment explaining that class should either be updated to reflect the new scope of protection, or the removal reconsidered.

---

## Next Steps

1. Restore (or explicitly, justifiably retire with sign-off) the strict/merge-gate verification path in `audit_envelope.py`, and confirm no caller elsewhere in the repo depends on the removed `verify_for_merge` parameter.
2. Restore the backtick-exclusion for Pattern 2 in `spiral-evidence.sh`'s `_parse_sprint_paths`, or otherwise re-scope the issue #1175 guard to cover it.
3. Optionally: re-add malformed-tag filtering in `get_version_from_tag`, and confirm no in-flight prerelease tags are affected by dropping prerelease bump support.
4. Resubmit for review.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":2},"excluded":0,"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
