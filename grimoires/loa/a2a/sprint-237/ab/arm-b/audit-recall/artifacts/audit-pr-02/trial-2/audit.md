# Security & Quality Audit Report

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-09-22
**Scope:** PR "refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches" — `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh` (base → head, `head.diff`)
**Methodology:** Diff-focused review of the three touched files against their pre-change behavior; no sprint plan, beads DB, or `grimoires/loa/a2a/` artifacts exist for this input — audited from `PR.md` + `head.diff` + `base/`/`head/` alone.

---

## Executive Summary

This PR frames itself as a plumbing simplification ("single code path again"), but two of its three hunks quietly remove security controls that were added, by their own in-code comments, to close specific named attacks (`ATK-3`, `ATK-4`, `STRIP-ATTACK-DETECTED`, `#690`, `#1175`). The audit-envelope change deletes the only mechanism by which a caller could force "verified or refuse" semantics on the audit hash-chain: it makes `BOOTSTRAP-PENDING` trust-stores unconditionally acceptable, makes the local-file pubkey fallback unconditionally available (removing the "refused in strict verify" guarantee), and turns "trust-store missing/unreadable" from a hard failure into a silent `None`/pass-through in all contexts, not just the non-strict one. Because none of these three code paths retain *any* way to require stricter behavior, any caller that previously opted into `verify_for_merge=True` (or `LOA_AUDIT_STRICT_VERIFY=1`) for a merge-time integrity gate now silently gets the permissive behavior instead — with no error, no warning, and no configuration knob left to restore it. The spiral-evidence.sh change reverts the exact backtick-masking fix that issue #1175 added, reopening a documented false-positive/forgery vector in the implementation-evidence gate.

The callers of `audit_verify_chain(..., verify_for_merge=True)` are not present in this narrow PR snapshot, so exploitability against a specific merge pipeline cannot be fully confirmed here — that uncertainty is reflected in the severities below (HIGH, not CRITICAL). But the removed parameters, their docstrings ("True when verification is running as a merge gate"), and the attack IDs referenced in the deleted code are strong, specific evidence that this is a deliberate security feature being deleted, not dead code being swept up.

**Overall Risk Level:** HIGH

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 3 |
| Medium | 1 |
| Low | 1 |

---

## High Priority Issues (Fix Before Production)

### [HIGH-001] Trust-store `BOOTSTRAP-PENDING` state is now unconditionally accepted, deleting the merge-gate refusal (ATK-3)

**Component:** `head/.claude/adapters/loa_cheval/audit_envelope.py:462-473`

```python
def _check_trust_store() -> None:
    """
    Gate function called at top of audit_emit + audit_verify_chain.
    Raises RuntimeError with [TRUST-STORE-INVALID] on tampered trust-stores.
    """
    status = _trust_store_status()
    if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
        return
    raise RuntimeError(
        "[TRUST-STORE-INVALID] trust-store root_signature does NOT verify "
        "against pinned root pubkey; refusing all writes/reads (issue #690)"
    )
```

**Description:** In `base/`, `_check_trust_store(*, strict_verify: bool = False)` treated `BOOTSTRAP-PENDING` as acceptable only when `strict_verify` was false; when `strict_verify` was true (merge gate) it raised `[TRUST-STORE-BOOTSTRAP-PENDING]`, explicitly citing `ATK-3`:

```python
# base/.claude/adapters/loa_cheval/audit_envelope.py:466-479 (removed)
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
    raise RuntimeError(...)
```

The head version deletes the `strict_verify` parameter entirely and folds `BOOTSTRAP-PENDING` into the always-accepted branch. The only caller-facing lever that could force "an unsigned/never-bootstrapped trust-store must not pass a merge gate" is gone — there is no environment variable, argument, or code path left in this function that can reproduce the old strict behavior.

**Impact:** `ATK-3` (per the deleted comment) was specifically the scenario where a trust-store is kept in — or forced back into — the unsigned bootstrap state so that all audit-chain reads/writes are accepted without any root-of-trust check. Whatever caller previously passed `verify_for_merge=True`/set `LOA_AUDIT_STRICT_VERIFY=1` to close this hole at merge time now gets silently downgraded to the permissive path, with no error surfaced. An attacker (or a broken bootstrap step) that keeps the trust-store's `root_signature`/`keys`/`revocations` empty causes `_trust_store_status()` to return `BOOTSTRAP-PENDING` indefinitely, and that is now accepted everywhere, including whatever call site this PR's own commit message implies was gating merges.

**Proof of Concept:** With `LOA_TRUST_STORE_FILE` pointing at a trust-store containing no `root_signature.signature`, no `keys`, and no `revocations` (or with the file simply absent), `_check_trust_store()` (and therefore `audit_verify_chain()`/`audit_emit()`) now returns/succeeds unconditionally. In `base/`, the same setup would raise `[TRUST-STORE-BOOTSTRAP-PENDING]` when invoked with `verify_for_merge=True`.

**Remediation:** Restore a `strict` parameter (or equivalent config surface) on `_check_trust_store`/`audit_verify_chain`/`audit_emit` and re-raise on `BOOTSTRAP-PENDING` when the caller has requested strict/merge-time verification. If the intent is genuinely to retire the merge-gate feature, that should be an explicit, reviewed decision documented in the PR description (and any caller that set `LOA_AUDIT_STRICT_VERIFY=1` should be located and updated), not an incidental consequence of "single code path again."

**References:** CWE-295 (Improper Certificate/Trust Validation), CWE-306 (Missing Authentication for Critical Function), OWASP A07:2021 (Identification and Authentication Failures).

---

### [HIGH-002] Local pubkey-file fallback is now always available, removing the strict-verify prohibition that closed a key-injection path

**Component:** `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160`

```python
def _resolve_pubkey_pem(key_id: str) -> Optional[str]:
    """
    Resolve the PEM-encoded pubkey for <key_id>:
      1. Trust-store entry (when YAML + yaml package available)
      2. <key-dir>/<key_id>.pub (test/CI fallback)
    Returns the PEM string or None if unresolvable.
    """
    ts_path = _trust_store_path()
    if ts_path.is_file():
        ...
    # Local fallback.
    pub_path = _key_dir() / f"{key_id}.pub"
    if pub_path.is_file():
        return pub_path.read_text(encoding="utf-8")
    return None
```

**Description:** `base/` took `allow_local_fallback: bool = True` and, at the one call site (`audit_verify_chain`), passed `allow_local_fallback=not strict_verify` (`base/.claude/adapters/loa_cheval/audit_envelope.py:594-597`, deleted here at `head.diff:123-127`). That meant: in a merge-gate/strict-verify context, only trust-store-registered keys could verify a signature — a key dropped into `<key-dir>/<key_id>.pub` (default `~/.config/loa/audit-keys`, or wherever `LOA_AUDIT_KEY_DIR` points) was explicitly refused. The head version deletes the parameter, so the local-file fallback is reachable unconditionally, in every calling context.

**Impact:** `_key_dir()` (`head/.claude/adapters/loa_cheval/audit_envelope.py:67-74`) resolves from `LOA_AUDIT_KEY_DIR`, an environment variable — and even at its default path, anything able to write to that directory (a compromised CI step, a malicious dependency running in the same job, a shared build host) can drop a `<forged-key-id>.pub` file and have `audit_verify_chain` treat signatures made with the matching private key as trusted for that `signing_key_id`, *without* that key ever being registered in the signed trust-store. Previously this exact bypass was closed off specifically for the strict/merge-gate case. Combined with HIGH-001 (trust-store need not even be present/verified) and HIGH-003 (cutoff enforcement silently disabled), an attacker who controls the key directory can forge chain entries that `audit_verify_chain` will accept as validly signed.

**Remediation:** Reintroduce an `allow_local_fallback` (or equivalent) gate keyed off the same strict/merge flag reinstated in HIGH-001, and refuse the local-file fallback whenever strict verification is requested.

**References:** CWE-347 (Improper Verification of Cryptographic Signature), CWE-295, OWASP A02:2021 (Cryptographic Failures).

---

### [HIGH-003] Missing/unreadable trust-store now silently disables `STRIP-ATTACK-DETECTED` post-cutoff enforcement instead of failing closed

**Component:** `head/.claude/adapters/loa_cheval/audit_envelope.py:476-494`, consumed at `head/.claude/adapters/loa_cheval/audit_envelope.py:538` and `566`

```python
def _read_trust_cutoff() -> Optional[str]:
    ts_path = _trust_store_path()
    if not ts_path.is_file():
        return None
    try:
        import yaml
        with ts_path.open("r", encoding="utf-8") as f:
            doc = yaml.safe_load(f) or {}
        cutoff = ((doc.get("trust_cutoff") or {}).get("default_strict_after") or "").strip()
        return cutoff or None
    except Exception:  # pragma: no cover — defensive
        return None
```

**Description:** `base/` raised `[TRUST-STORE-MISSING]`/`[TRUST-STORE-UNREADABLE]` (citing `ATK-4`) when `strict_verify` was true and the trust-store couldn't be read, specifically because `_ts_ge_cutoff()` (`head/.claude/adapters/loa_cheval/audit_envelope.py:497-505`) treats a `None` cutoff as "no cutoff configured — grandfather everything," which means the `STRIP-ATTACK-DETECTED` check at `head/.claude/adapters/loa_cheval/audit_envelope.py:566-575` (requiring both `signature` and `signing_key_id` past the cutoff) never fires. The head version always returns `None` on a missing/unreadable file, in every context, so an attacker who can make the trust-store disappear or become unreadable (e.g. permissions, transient I/O error, partial write) silently disables strip-attack detection for the whole chain walk — precisely the scenario `ATK-4` was named to prevent from doing so in a merge gate.

**Impact:** An attacker able to transiently remove/corrupt the trust-store file at verification time causes every subsequent chain entry to be treated as "pre-cutoff" (never required to carry a signature), enabling a strip-attack (dropping `signature`/`signing_key_id` from previously-signed entries and having the chain still verify) to go undetected. This compounds HIGH-001/HIGH-002: the same missing/degraded trust-store that unlocks `BOOTSTRAP-PENDING` and the local-key fallback also disables the one check designed to catch signature stripping after the fact.

**Remediation:** Reinstate the strict/merge branch that raises rather than returns `None` when the trust-store cannot be read, gated on the same flag as HIGH-001/HIGH-002.

**References:** CWE-345 (Insufficient Verification of Data Authenticity), CWE-703 (Improper Check or Handling of Exceptional Conditions), OWASP A08:2021 (Software and Data Integrity Failures).

---

## Medium Priority Issues (Address in Next Sprint)

### [MED-001] Removing the backtick-masking pre-pass reopens the documented forgery/false-positive vector from issue #1175

**Component:** `head/.claude/scripts/spiral-evidence.sh:700`

```bash
        echo "$content" | grep -oE "(^|[^a-zA-Z0-9_/.-])(src|tests|\.claude/scripts|\.claude/hooks|grimoires)/[a-zA-Z0-9_/.+()-]+\.${ext_re}" \
            2>/dev/null | \
            sed -E 's/^[^a-zA-Z.]//'
```

**Description:** `base/` computed `content_bare` by stripping all backtick-delimited spans (`sed 's/`[^`]*`//g'`) before running the "bare path" Pattern 2 regex, so paths that only appear as substrings of an inline-code shell example (e.g. `` `mv src/old.ts src/new.ts` ``) were excluded — this is exactly the fix the adjacent, still-present comment describes for Pattern 1 ("False-positive guard (#1175): backtick prose also wraps shell commands ... and matched as deliverable paths, failing cycles with IMPL_EVIDENCE_MISSING and inviting stub/symlink forgery," `head/.claude/scripts/spiral-evidence.sh:682-687`). The diff deletes the `content_bare` computation (`head.diff:138-139`) and switches Pattern 2 to scan the raw, backtick-intact `$content` again. Pattern 2 has no whitespace/glob filtering (unlike Pattern 1), so a path-like substring embedded in an inline-code shell example — even one containing no spaces itself, or one where only part of the backtick span matches — can now be picked up by Pattern 2 as if it were a declared deliverable, even though Pattern 1 already covers legitimate backtick-wrapped deliverable declarations.

**Impact:** This is the same failure mode the comment at line 684-687 explicitly warns about: a spurious "deliverable" path extracted from prose causes the evidence-existence gate to fail with `IMPL_EVIDENCE_MISSING` for a file that was never meant to be a deliverable, and the documented consequence is that engineers/agents work around it by creating a stub or symlink just to make the path resolve — defeating the purpose of the implementation-evidence anti-forgery gate for the *real* deliverables in the same sprint section. The PR reverts a numbered, comment-documented fix without updating or removing the comment that explains why the fix exists, which suggests the regression is unintentional.

**Remediation:** Restore the `content_bare` backtick-stripped variable and feed it to Pattern 2 (as `base/` did), or move Pattern 2 to run before Pattern 1 masks/consumes backtick spans, keeping the documented false-positive guard intact for both patterns.

**References:** CWE-345 (Insufficient Verification of Data Authenticity) — applied to the evidence-existence gate itself; project issue #1175 (referenced in-line at `head/.claude/scripts/spiral-evidence.sh:684`).

---

## Low Priority Issues (Technical Debt)

### [LOW-001] Tag-format validation dropped from `get_version_from_tag`, widening accepted tag shapes before `bump_version` rejects them

**Component:** `head/.claude/scripts/semver-bump.sh:55-63`

```bash
get_version_from_tag() {
  local tag
  tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
  if [[ -n "$tag" ]]; then
    echo "${tag#v}"
    return 0
  fi
  return 1
}
```

**Description:** `base/` matched candidate tags with `git tag -l 'v[0-9]*.[0-9]*.[0-9]*' 'v[0-9]*.[0-9]*.[0-9]*-*'` and then filtered through `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` before taking the top tag, so only strictly-formed release/prerelease tags could be returned. The head version relies solely on the shell glob `v[0-9]*.[0-9]*.[0-9]*`, which is looser than it looks (`[0-9]*` matches one digit followed by *any* characters, e.g. `v1abc.2xyz.3def` would match the glob but was rejected by the deleted regex). A malformed tag matching the glob but not `^[0-9]+\.[0-9]+\.[0-9]+$` will now be returned by `get_version_from_tag` and only fail later, inside `bump_version` (`head/.claude/scripts/semver-bump.sh:80-86`), with a generic `ERROR: Invalid version format`. Also, since only release-shaped tags are globbed at all now, any existing `-alpha./-beta./-rc.` prerelease tag is silently invisible to this function (falls through to `return 1`, `get_version_from_changelog` fallback), consistent with the PR's stated intent to go "release-only" but not called out as a behavior change for repos that still have prerelease tags in their history.

**Impact:** Availability/correctness only (a malformed or prerelease tag causes the release-bump script to fail loudly rather than compute a wrong version) — no confidentiality/integrity impact, since git tags in this repository are maintainer-created via this same tooling, not attacker-controlled input.

**Remediation:** Keep an explicit `grep -E` (or `[[ =~ ]]`) validation step against `^v[0-9]+\.[0-9]+\.[0-9]+$` in `get_version_from_tag` itself so malformed tags are rejected at the point of selection with a clear message, and document the prerelease-tag removal as an intentional breaking change if any consumer still relies on it.

---

## Security Checklist Status

### Authentication & Authorization
- [ ] No privilege escalation paths — **FAILS**: HIGH-001/002/003 collectively allow the audit-chain integrity gate to be silently downgraded from "verify against pinned trust-store" to "accept unsigned/locally-forged keys," with no reachable configuration left to restore the stricter behavior.

### Input Validation
- [ ] Webhook/signature verification robust to stripping — **FAILS**: HIGH-003 disables the strip-attack detector whenever the trust-store is unreadable.

### Supply Chain / Integrity
- [ ] Version/tag parsing is strict at the point of selection — **FAILS** (LOW-001, minor).
- [ ] Anti-forgery evidence gates resistant to prose false-positives — **FAILS** (MED-001, reverts #1175).

All other checklist categories (secrets, data privacy, API rate limiting) are out of scope for this three-file diff.

---

## Recommendations

**Immediate (24h):** Do not merge as-is. Reinstate the `strict_verify`/`verify_for_merge`/`allow_local_fallback` plumbing in `audit_envelope.py` (HIGH-001/002/003) unless the removal is a deliberate, separately-reviewed decision to retire the merge-gate feature — in which case say so explicitly and confirm no caller still expects strict semantics.

**Short-term (1wk):** Restore the `content_bare` backtick-masking step in `spiral-evidence.sh` (MED-001) so the still-present in-line comment describing the #1175 fix matches the code again.

**Long-term (1mo):** Re-add explicit tag-format validation in `semver-bump.sh::get_version_from_tag` (LOW-001) and document the prerelease-tag removal as an intentional scope change.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
