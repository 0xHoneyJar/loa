# Security & Quality Audit Report

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-09-22
**Scope:** PR "refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches" — `head/.claude/adapters/loa_cheval/audit_envelope.py`, `head/.claude/scripts/spiral-evidence.sh`, `head/.claude/scripts/semver-bump.sh` (base → head diff, 218 lines)
**Methodology:** Line-by-line base/head diff review; trace of every removed conditional to its documented threat (issue #690, ATK-3, ATK-4, #1175, M-05)

---

## Executive Summary

This PR presents itself as a scope-reduction refactor ("single code path again") across three unrelated files. Two of the three changes are benign simplifications. The third — `audit_envelope.py` — is not a simplification, it is the wholesale removal of the only code path that ever enforced strict verification of the audit trust-chain at a merge gate. The removed code was purpose-built and explicitly tagged against two named attack scenarios (`ATK-3`, `ATK-4`) tracked under issue #690. The PR deletes the `verify_for_merge` parameter, the `LOA_AUDIT_STRICT_VERIFY` environment variable, and every branch that behaved differently under strict mode, collapsing to the permissive (non-strict) behavior unconditionally. No replacement control is introduced, and the PR description gives no indication that ATK-3/ATK-4 have been mitigated elsewhere or that the risk has been consciously accepted. Any caller that previously invoked `audit_verify_chain(log_path, verify_for_merge=True)` — e.g. a merge/release gate — now either breaks with `TypeError` (fail-open risk if wrapped in a broad `except`) or, if such call sites were already scrubbed elsewhere, silently loses the only distinction between "verify a log for informational purposes" and "verify a log before trusting it to gate a merge." This is a Critical finding.

The `spiral-evidence.sh` change reopens a narrower, previously-fixed false-positive class (issue #1175) for one of two path-extraction patterns; it is a reliability regression to the sprint evidence gate, not a new exploit primitive, and is rated Medium. The `semver-bump.sh` change removes prerelease-tag handling and the extra tag-format regex, but the remaining strict-format check inside `bump_version` still fails closed on anything that isn't `M.m.p`, so it is a low-severity operational change.

**Overall Risk Level:** CRITICAL

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 1 |
| Low | 1 |

---

## Critical Issues (Fix Immediately)

### [CRITICAL-001] Strict-mode merge-gate verification removed from `audit_verify_chain` — reopens ATK-3/ATK-4

**Severity:** CRITICAL | **Confidence:** high
**Component:** `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160, 462-473, 476-494, 508`
**Criterion:** SEC-IV / SEC-AZ — Integrity Verification, Trust Boundary Enforcement

**Reasoning Trace:**
> Diffed `base/.claude/adapters/loa_cheval/audit_envelope.py` against `head/`. The base file defines `_strict_verify_enabled()`, and threads a `strict_verify`/`verify_for_merge` flag through `_check_trust_store`, `_read_trust_cutoff`, `_resolve_pubkey_pem`, and `audit_verify_chain`, with three branches whose *sole* purpose is to behave more restrictively when verification is gating a merge (`verify_for_merge=True` or `LOA_AUDIT_STRICT_VERIFY=1`). Each of those branches carries an explicit attack-ID comment (`ATK-3`, `ATK-4`) and references issue #690. The head file deletes `_strict_verify_enabled` entirely, drops the `verify_for_merge` keyword from `audit_verify_chain`'s signature, and removes every strict-only branch, leaving only the permissive behavior.

**Description:**
Three independent safety valves collapsed into one, all permissive:

1. **Unsigned trust-store is now always accepted, even at merge gates.**
   `_check_trust_store()` (`head:462-473`):
   ```python
   status = _trust_store_status()
   if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
       return
   ```
   Base (`base:469-487`) refused `BOOTSTRAP-PENDING` (an unsigned/uninitialized trust-store) when `strict_verify` was true, raising `[TRUST-STORE-BOOTSTRAP-PENDING] ... strict audit verification refuses BOOTSTRAP-PENDING (ATK-3)`. That refusal no longer exists in any code path — there is no way, via any parameter or environment variable, to make `_check_trust_store` reject an unsigned trust-store anymore.

2. **Missing/unreadable trust-store cutoff no longer fails closed.**
   `_read_trust_cutoff()` (`head:476-494`) silently returns `None` when the trust-store file is missing or unparsable. Base (`base:490-519`) raised `[TRUST-STORE-MISSING]` / `[TRUST-STORE-UNREADABLE]` ("strict audit verification requires a readable trust-store cutoff (ATK-4)") under `strict_verify`. `None` cutoff means `_ts_ge_cutoff` (line 497-505, unchanged) always returns `False`, so the post-cutoff signature-required check (`STRIP-ATTACK-DETECTED`, line 566-575) can never trigger — an attacker who can make the trust-store disappear or become unreadable at merge time silently disables the strip-attack defense instead of failing the merge.

3. **Local pubkey fallback is now always allowed, even at merge gates.**
   `_resolve_pubkey_pem(key_id)` (`head:136-160`) unconditionally falls back to `<key-dir>/<key_id>.pub` when the trust-store lookup fails. Base (`base:141-166`) took an `allow_local_fallback` flag and refused the fallback when `strict_verify` was true (`allow_local_fallback=not strict_verify` at the `audit_verify_chain` call site). Anyone able to place a file at `<LOA_AUDIT_KEY_DIR>/<key_id>.pub` — e.g. via a writable CI cache, a prior compromised step, or a local dev/test key left on a shared runner — can now have that key trusted for signature verification during a merge-gate check, because the "test/CI fallback, refused in strict verify" carve-out documented in the base docstring is gone.

4. **The API surface for requesting strict verification no longer exists.**
   `audit_verify_chain(log_path: PathLike) -> Tuple[bool, str]` (`head:508`) — the `*, verify_for_merge: bool = False` keyword-only parameter present in base (`base:532`) is deleted outright. Any caller elsewhere in the codebase (not part of this PR's touched-file set, hence out of diff scope, but implied by the very existence of a keyword-only "for merge" parameter and a dedicated `LOA_AUDIT_STRICT_VERIFY` env var) that calls `audit_verify_chain(log_path, verify_for_merge=True)` will now raise `TypeError: audit_verify_chain() got an unexpected keyword argument 'verify_for_merge'`. Depending on how that caller handles exceptions, this is either a hard break (good — visible failure) or, if wrapped in a broad `except Exception` that treats failure-to-verify as "skip verification," a silent fail-open at exactly the checkpoint the parameter was built to protect.

**Impact:** The audit trust-chain's only strict/merge-gate mode is gone. An attacker (or a routine bootstrap-not-yet-signed state, or a transient filesystem hiccup that makes the trust-store briefly unreadable) can cause a merge-time integrity check to pass when it previously would have refused. This defeats the specific, named threat model (`ATK-3`: bootstrap-pending trust-store abuse; `ATK-4`: missing/unreadable trust-store abuse) that issue #690 was opened to close. The PR description ("removes the verify-for-merge strictness knobs... single code path again") gives no indication these attacks were mitigated by other means, and nothing in the diff replaces the removed protections.

**Proof of Concept:**
```python
# Before this PR: a merge-gate caller using verify_for_merge=True would refuse
# an unsigned trust-store outright.
audit_verify_chain(log_path, verify_for_merge=True)
# -> (False, "[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed; ...")

# After this PR: the same intent can no longer even be expressed — the kwarg
# is gone, and even a hand-rolled strict caller inlining the old checks would
# find _check_trust_store() itself now treats BOOTSTRAP-PENDING as fine:
audit_verify_chain(log_path)
# -> (True, "OK N entries")   # even though the trust-store was never signed
```

**Remediation:**
```python
# Restore the strict/merge-gate distinction, or — if the intent is genuinely
# to retire ATK-3/ATK-4 as no-longer-applicable — document why in the PR and
# close issue #690 with that rationale instead of silently deleting the code.

def _check_trust_store(*, strict_verify: bool = False) -> None:
    status = _trust_store_status()
    if status == "VERIFIED":
        return
    if status == "BOOTSTRAP-PENDING" and not strict_verify:
        return
    if status == "BOOTSTRAP-PENDING":
        raise RuntimeError(
            "[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed; "
            "strict audit verification refuses BOOTSTRAP-PENDING (ATK-3)"
        )
    raise RuntimeError("[TRUST-STORE-INVALID] ... (issue #690)")

def audit_verify_chain(log_path: PathLike, *, verify_for_merge: bool = False) -> Tuple[bool, str]:
    ...
```
At minimum, before merging: grep the full repository (outside this PR's file scope) for `verify_for_merge=` and `LOA_AUDIT_STRICT_VERIFY` call sites and confirm none exist, or that whatever gate previously relied on them has an equivalent replacement.

**References:** [CWE-347: Improper Verification of Cryptographic Signature](https://cwe.mitre.org/data/definitions/347.html), [CWE-295: Improper Certificate Validation](https://cwe.mitre.org/data/definitions/295.html), [OWASP A08:2021 – Software and Data Integrity Failures](https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/)

---

## High Priority Issues (Fix Before Production)

None.

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Backtick-masking removal reopens issue #1175 false-positive class for bare-path matching

**Severity:** MEDIUM
**Component:** `head/.claude/scripts/spiral-evidence.sh:672-703`
**Description:** `_parse_sprint_paths()`'s Pattern 2 (bare-path extraction) previously scanned `content_bare` — `content` with every backtick span blanked out (`sed 's/`[^`]*`//g'`, removed at `base/.claude/scripts/spiral-evidence.sh:673-674`). Head now feeds Pattern 2 the raw `content` directly (`head:700`). Because a backtick character satisfies Pattern 2's own boundary class (`[^a-zA-Z0-9_/.-]`), any `<prefix>/....<ext>` path mentioned inside a backtick-wrapped shell command example in `sprint.md` prose (e.g. `` `bash .claude/scripts/foo.sh --flag` ``) is now matched as a required deliverable path, even though Pattern 1's own adjacent false-positive guard (`head:679-694`, citing issue #1175) exists specifically to keep command-example prose like this out of the deliverable set. The comment block directly above the removed line (`base:693` "backtick prose also wraps shell commands... and matched as deliverable paths, failing cycles with IMPL_EVIDENCE_MISSING") describes exactly the bug this change reintroduces for Pattern 2.
**Impact:** Sprint evidence-gate false failures (`IMPL_EVIDENCE_MISSING`) for legitimate sprint.md prose that merely references a script by example rather than declaring it a deliverable — a reliability/availability regression to a quality gate, not a new remote exploit primitive. (The direction of the bug widens what counts as a required file, so it does not create a way to under-report missing deliverables or evade stub/symlink-forgery detection; it creates spurious blocking failures.)
**Remediation:** Keep the `content_bare` backtick-blanking pass and feed it to Pattern 2 as it was, or explicitly scope Pattern 2's regex to only match when not preceded/followed by a backtick.
**References:** Issue #1175 (referenced inline at `head/.claude/scripts/spiral-evidence.sh:684-694`)

---

## Low Priority Issues (Technical Debt)

### [LOW-001] `semver-bump.sh` tag selection no longer format-filters before sort/select

**Severity:** LOW
**Component:** `head/.claude/scripts/semver-bump.sh:54-63, 80-94`
**Description:** `get_version_from_tag()` previously filtered candidate tags through a strict regex (`^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$`, removed — was `base/.claude/scripts/semver-bump.sh:56-58`) before taking the top of the version-sort. Head (`head:57`) takes `git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -1` unfiltered — the glob also matches non-canonical tags (e.g. `v1.2.3-rc.1`, `v1.2.3.4`) that shell `fnmatch` globbing does not distinguish from clean release tags. `bump_version()` (`head:80-94`) does still validate strictly (`^[0-9]+\.[0-9]+\.[0-9]+$`, "Validate version format (M-05)") and fails closed with `ERROR: Invalid version format` rather than mis-parsing, so this does not produce an incorrect version — it produces a hard failure of the release-bump script whenever the highest-sorted tag isn't a clean release tag (e.g. after a prerelease tag was ever pushed). Since `CLAUDE.loa.md` mandates `semver-bump.sh` as the only sanctioned path to version computation, an unexpected hard failure here blocks releases rather than corrupting them — fail-closed, so this is an availability nuisance rather than a security issue.
**Remediation:** Either keep a lightweight format pre-filter on the tag glob (even if prerelease tags are no longer bumped, still exclude them from being selected as "the tag" so `CHANGELOG.md`/git-log fallback paths can be tried instead), or document that any non-canonical tag in the repo blocks `semver-bump.sh` until removed.

---

## Positive Findings

- The signature-verification core (`_verify_signature`, `_chain_input_bytes`, prev-hash chain walk, `STRIP-ATTACK-DETECTED` post-cutoff enforcement) is untouched by this PR — the regression is confined to the strict/merge-gate wrapper, not the underlying crypto.
- `bump_version()`'s strict format validation (`^[0-9]+\.[0-9]+\.[0-9]+$`, M-05) is preserved and still fails closed on malformed input rather than silently mis-computing a version.
- Pattern 1's issue #1175 false-positive guard in `spiral-evidence.sh` (whitespace/glob/leading-char exclusion) is untouched — only Pattern 2 regressed.

---

## Threat Model Summary

**Trust Boundaries:**
- Audit-chain verification at merge time (`audit_verify_chain`, intended caller = merge/release gate) vs. informational/local verification.
- Trust-store signature vs. local `<key-dir>/<key_id>.pub` fallback (test/CI convenience vs. production trust root).

**Attack Vectors:**
- ATK-3 (bootstrap-pending trust-store accepted at a merge gate): now unconditionally possible — CRITICAL.
- ATK-4 (missing/unreadable trust-store silently downgrades cutoff enforcement): now unconditionally possible — CRITICAL.
- Local pubkey substitution at a merge gate: now unconditionally possible (no strict mode to refuse it) — folded into CRITICAL-001.

**Mitigations:**
- None added by this PR; the previously-existing mitigations for the above were removed with no replacement.

**Residual Risks:**
- Until CRITICAL-001 is remediated, `audit_verify_chain` cannot be used to enforce integrity guarantees at any checkpoint stronger than "best effort" — every call behaves as if it were the old non-strict mode.

---

## Recommendations

### Immediate Actions (24 Hours)
1. Revert or restore the `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY` code path in `audit_envelope.py`, or provide documented, reviewed justification (closing issue #690's ATK-3/ATK-4 with rationale) for retiring it.
2. Grep the full repository for any caller passing `verify_for_merge=` to `audit_verify_chain` and confirm the removal doesn't silently fail-open at a real merge gate.

### Short-Term Actions (1 Week)
1. Restore backtick-masking for Pattern 2 in `spiral-evidence.sh`, or add a regression test asserting command-example prose inside backticks is not treated as a declared deliverable.

### Long-Term Actions (1 Month)
1. Add a pre-filter (or at least a warning) to `semver-bump.sh`'s tag selection so a stray non-canonical tag doesn't silently block the release-bump path without explanation.

---

## Verdict

**Overall Risk Level: CRITICAL**

**Next Steps:**
1. Do not merge until CRITICAL-001 is resolved.
2. Address MED-001 and LOW-001 as follow-up work; neither blocks merge on its own.

---

**Audit Completed:** 2026-09-22
**Next Audit Recommended:** After CRITICAL-001 remediation, before merge
**Remediation Tracking:** `grimoires/loa/audits/2026-09-22/` (not created in this fixture — no `grimoires/` present in scope)

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
