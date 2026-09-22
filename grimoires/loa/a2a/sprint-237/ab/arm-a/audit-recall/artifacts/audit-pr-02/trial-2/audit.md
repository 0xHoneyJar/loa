# Security Audit Report

**Audit type**: PR / diff audit (no sprint plan, beads DB, or `grimoires/loa/a2a/` context available — audited from `PR.md` + `head.diff` + `base/`/`head/` snapshots only)
**Scope**: `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh`
**Date**: 2026-09-21

## Executive Summary

This PR bills itself as a plumbing-simplification refactor ("drop strict-verify plumbing... single code path again"), but the `audit_envelope.py` hunk does not just simplify code — it deletes the entire "strict verification for merge gates" security mode of the audit-chain integrity checker, including two named, comment-documented attack mitigations (ATK-3, ATK-4) and the local-pubkey-fallback restriction used during strict verification. No replacement mechanism is introduced, and the PR description gives no security rationale (threat retired, mitigation superseded, etc.) for removing controls that were clearly added deliberately and referenced by attack ID. This is the kind of change that should never land as an unremarked "refactor."

The `spiral-evidence.sh` change (dropping the backtick pre-pass before the bare-path scan) reintroduces a class of false-positive matching that a prior fix (issue #1175, still documented in the surrounding comments) was written to prevent, weakening the evidence-gate's precision in a way that — per that same comment block — "invit[es] stub/symlink forgery."

The `semver-bump.sh` change is a legitimate, lower-risk narrowing of scope (release-only versioning) with no security impact; it is noted for completeness only.

## Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## High Priority Issues

### H-1: Deletion of strict audit-chain verification mode removes two named attack mitigations with no replacement or justification

**Component**: `head/.claude/adapters/loa_cheval/audit_envelope.py:462-473` (`_check_trust_store`), `head/.claude/adapters/loa_cheval/audit_envelope.py:508-538` (`audit_verify_chain`), `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160` (`_resolve_pubkey_pem`)

**Description**: Before this PR, `audit_verify_chain()` accepted a `verify_for_merge` flag (also settable via `LOA_AUDIT_STRICT_VERIFY=1`, `base/.claude/adapters/loa_cheval/audit_envelope.py:136-138`) that put the chain-integrity checker into a strict mode intended for merge-time gating. In strict mode:

- `_check_trust_store(strict_verify=True)` refused an unsigned (`BOOTSTRAP-PENDING`) trust-store with `[TRUST-STORE-BOOTSTRAP-PENDING] ... strict audit verification refuses BOOTSTRAP-PENDING (ATK-3)` (`base/.claude/adapters/loa_cheval/audit_envelope.py:479-483`).
- `_read_trust_cutoff(strict_verify=True)` refused to proceed if the trust-store was missing or unreadable, raising `[TRUST-STORE-MISSING]` / `[TRUST-STORE-UNREADABLE]` ("strict audit verification requires a readable trust-store (ATK-4)", `base/.claude/adapters/loa_cheval/audit_envelope.py:500-504` and `:513-517`).
- `_resolve_pubkey_pem(kid, allow_local_fallback=not strict_verify)` refused to fall back to the on-disk `<key-dir>/<key_id>.pub` test/CI convenience path when running strict, so a signature could only be validated against a properly trust-store-registered key (`base/.claude/adapters/loa_cheval/audit_envelope.py:141,161-162`).

This PR deletes `_strict_verify_enabled`, removes the `verify_for_merge` parameter from `audit_verify_chain` entirely (`head/.claude/adapters/loa_cheval/audit_envelope.py:508`), removes the `strict_verify` parameter from `_check_trust_store` (`head/.claude/adapters/loa_cheval/audit_envelope.py:462`) and `_read_trust_cutoff` (`head/.claude/adapters/loa_cheval/audit_envelope.py:476`), and removes the `allow_local_fallback` parameter from `_resolve_pubkey_pem` (`head/.claude/adapters/loa_cheval/audit_envelope.py:136`). The post-PR `_check_trust_store` now unconditionally treats `BOOTSTRAP-PENDING` the same as `VERIFIED` (`head/.claude/adapters/loa_cheval/audit_envelope.py:468`), `_read_trust_cutoff` silently returns `None` on a missing/unreadable trust-store instead of raising (`head/.claude/adapters/loa_cheval/audit_envelope.py:485-486,493-494`), and `_resolve_pubkey_pem` always allows the local fallback (`head/.claude/adapters/loa_cheval/audit_envelope.py:156-159`).

**Impact**:
1. **Silent security regression.** ATK-3 and ATK-4 are named attack scenarios that someone previously analyzed and mitigated deliberately. Deleting the mitigations without any accompanying note that the threat model changed, that the attacks are mitigated elsewhere, or that they were false positives, is a red flag on its own — this is exactly the kind of change a "refactor" PR description is used to smuggle past reviewers (CLAUDE.loa.md's own Karpathy §3 "Surgical Changes" principle: unrelated/undiscussed removals belong in the PR description, not silently in the diff — here they aren't even in the PR description).
2. **Merge-gate integrity check is now uniformly the weakest mode.** Any caller that previously ran `audit_verify_chain(log_path, verify_for_merge=True)` as a merge/CI gate to get the stronger guarantees (no unsigned bootstrap trust-store, no missing-trust-store bypass, no local-key fallback) now gets exactly the same lenient behavior as ordinary runtime verification. If such a caller exists elsewhere in the codebase (not included in this PR's file set, but strongly implied by the docstrings — "Gate function called at top of audit_emit + audit_verify_chain", "Issue #690 (Sprint 1.5): auto-verify trust-store before chain walk" — and by the fact `verify_for_merge` was a public kwarg on an exported function, `head/.claude/adapters/loa_cheval/audit_envelope.py:644` `__all__` still lists `audit_verify_chain`), that caller either (a) silently loses its stronger guarantee, or (b) breaks outright with `TypeError: audit_verify_chain() got an unexpected keyword argument 'verify_for_merge'` since the kwarg no longer exists on the function signature at all.
3. **Concretely**: an attacker (or a broken bootstrap process) who can place an unsigned/`BOOTSTRAP-PENDING` trust-store, or who can prevent the trust-store from being read, can no longer be caught by the merge-time gate — the exact scenario ATK-3/ATK-4 were written to catch is now indistinguishable from the normal, permissive runtime path in every mode of this function.

**Proof of concept**: With no trust-store present at all, pre-PR strict mode: `_read_trust_cutoff(strict_verify=True)` raises `RuntimeError("[TRUST-STORE-MISSING] ...")`, and `audit_verify_chain(log, verify_for_merge=True)` returns `(False, "[TRUST-STORE-MISSING] ...")`. Post-PR: `_read_trust_cutoff()` (`head/.claude/adapters/loa_cheval/audit_envelope.py:485-486`) just returns `None`, and the chain walk proceeds as if there were no cutoff, i.e. every entry is "pre-cutoff" and grandfathered regardless of signature status.

**Remediation**:
- Restore `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY` (or a deliberately-designed replacement) if any merge/CI gate in the wider codebase depends on it — check for other callers of `audit_verify_chain(...)` before merging this PR; if none exist, the PR description must say so explicitly and reference why ATK-3/ATK-4 no longer need a dedicated strict mode.
- If the intent is genuinely to retire the strict mode, that decision needs its own justification (e.g., "ATK-3/ATK-4 are now covered by control X") in the PR description, not a bare "single code path again."
- At minimum, do not delete `_resolve_pubkey_pem`'s `allow_local_fallback` guard silently — local-key fallback existing at all in a merge gate is precisely the kind of test/CI convenience that shouldn't be reachable when verifying an actual release artifact.

**References**: CWE-345 (Insufficient Verification of Data Authenticity), CWE-703 (Improper Check or Handling of Exceptional Conditions), OWASP A08:2021 (Software and Data Integrity Failures).

## Medium Priority Issues

### M-1: Removing the backtick pre-pass reintroduces a documented false-positive class in the spiral evidence gate

**Component**: `head/.claude/scripts/spiral-evidence.sh:697` (Pattern 2 bare-path scan)

**Description**: `_parse_sprint_paths()` extracts two kinds of deliverable-path evidence from sprint prose: Pattern 1 (backtick-wrapped paths, with an explicit false-positive guard documented at `head/.claude/scripts/spiral-evidence.sh:679-689` for issue #1175 — "backtick prose also wraps shell commands... and CLI flags... that... matched as deliverable paths, failing cycles with IMPL_EVIDENCE_MISSING and inviting stub/symlink forgery") and Pattern 2 (bare, unquoted paths). Pre-PR, Pattern 2 ran against `content_bare`, which had every backtick-delimited span stripped out first (`base/.claude/scripts/spiral-evidence.sh:673-674`, `sed 's/`[^`]*`//g'`), so text inside code spans could only ever be matched — and filtered — by Pattern 1's guard. This PR removes `content_bare` and runs Pattern 2 against the raw, unstripped `content` (`head/.claude/scripts/spiral-evidence.sh:697`).

**Impact**: Pattern 2's regex (`head/.claude/scripts/spiral-evidence.sh:697`) has no whitespace/glob/leading-char guard the way Pattern 1 does. An illustrative or example path embedded inside a backtick-quoted sentence or command (e.g. a Deliverables-section aside like `` `see src/tests/example.spec.ts for the pattern` ``, which Pattern 1's own whitespace guard would reject) will now also be picked up by Pattern 2 as if it were a bare, declared deliverable path — exactly the class of false positive #1175 was written to eliminate for Pattern 1. Since the gate treats every extracted path as a required deliverable, a spurious match can fail a cycle with `IMPL_EVIDENCE_MISSING` for a path that was never actually promised, which — per the very comment left in this file — creates pressure toward stub/symlink forgery to silence the false failure.

**Remediation**: Keep `content_bare` (or an equivalent guard) feeding Pattern 2, or, if the goal is genuinely to widen Pattern 2's reach into backtick spans, port Pattern 1's false-positive guard (no whitespace, no globs, no leading `-`/`@`) onto Pattern 2's output as well before removing the pre-pass.

**References**: CWE-1023 (Incomplete Comparison with Missing Factors) — the fix relies on incomplete boundary-condition coverage between the two extraction patterns.

## Low Priority Issues

### L-1: `semver-bump.sh` tag selection loses its whitelist validation step

**Component**: `head/.claude/scripts/semver-bump.sh:54-59` (`get_version_from_tag`)

**Description**: Pre-PR, `get_version_from_tag` listed tags with a glob and then piped through `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` (`base/.claude/scripts/semver-bump.sh:56-59`) as an explicit whitelist before accepting a tag as "current". Post-PR, the whitelist grep is gone; the function trusts `head -1` of the raw glob match directly (`head/.claude/scripts/semver-bump.sh:54-59`). This is consistent with the PR's stated intent (release-only versioning, per PR.md) and `bump_version` (`head/.claude/scripts/semver-bump.sh:81-96`) independently re-validates the format and fails closed with `ERROR: Invalid version format`, so a malformed tag cannot silently propagate into a computed version — this is a robustness/fail-fast-location regression, not an exploitable one.

**Impact**: A stray or malformed tag that happens to satisfy the loose `v[0-9]*.[0-9]*.[0-9]*` glob (e.g., something like `v1.2.3.4` or a leftover prerelease tag `v1.2.3-rc.1`, which still matches the glob's `*` wildcards) is now only rejected two stages later inside `bump_version`, producing a harder-to-diagnose pipeline failure instead of a clear "no valid tag found" at the selection site. No security impact.

**Remediation**: Optional — reintroduce a validation grep at selection time, or `continue`/skip non-matching tags rather than taking `head -1` of the unfiltered list, for a clearer failure mode.

## Security Checklist Status

- [x] Secrets & Credentials — no secrets introduced or touched
- [ ] Authentication/Integrity verification — **regressed** (H-1)
- [x] Input Validation — `bump_version` still validates format (M-05 comment retained, `head/.claude/scripts/semver-bump.sh:88-91`)
- [x] Supply Chain — no dependency changes
- [ ] Data integrity gating (evidence/audit gates) — **weakened** (H-1, M-1)

## Threat Model Summary

The audit-chain verification code exists specifically to detect a tampered or bootstrap-stage trust-store being used to smuggle unsigned/unverifiable entries past a merge gate (ATK-3, ATK-4, issue #690). This PR collapses that gate's strict mode into its lenient mode with no compensating control. Whether this is exploitable in practice depends on code outside this PR's scope (whether any caller still invokes `audit_verify_chain(..., verify_for_merge=True)`), which could not be verified from the files provided — this audit could not access the full repository to confirm or rule out a live merge-gate caller. This is flagged explicitly as a scope limitation: **treat H-1 as confirmed at the code level; verify caller impact before merge.**

## Verdict

**CHANGES_REQUIRED**

The `audit_envelope.py` hunk must not merge as-is: either restore the strict-verification path (and its ATK-3/ATK-4 mitigations) or provide an explicit, reviewed justification for retiring it, along with confirmation that no caller still depends on `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY`. The `spiral-evidence.sh` change should be revised to preserve the backtick-guard behavior for Pattern 2. The `semver-bump.sh` change is acceptable as-is.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
