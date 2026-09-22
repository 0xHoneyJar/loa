# Security Audit — refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

**Scope**: `head.diff` / `base/` / `head/` fixture only (no sprint plan, beads DB, or `grimoires/loa/a2a/` present — codebase-audit mode, no pre-flight gates apply).

**Files touched**:
- `.claude/adapters/loa_cheval/audit_envelope.py`
- `.claude/scripts/spiral-evidence.sh`
- `.claude/scripts/semver-bump.sh`

## Executive Summary

The PR removes the merge-gate "strict verification" code path from the audit-chain trust-store
integrity check (`audit_envelope.py`), removes a now-redundant backtick pre-mask from the spiral
evidence-path extractor (`spiral-evidence.sh`, functionally inert — see Observations), and drops
prerelease-version parsing from `semver-bump.sh` (functional regression, not a vulnerability —
the existing `M-05` format validation still blocks unsafe values before they reach arithmetic).

The material finding is the `audit_envelope.py` change: it deletes the only code path capable of
refusing an unsigned/missing/tampered trust-store or an attacker-supplied local public key during
chain verification, and it does so by deleting the parameters themselves rather than just
defaulting them off — so any caller (or `LOA_AUDIT_STRICT_VERIFY=1` operator) that previously
opted into strict verification now silently gets the lenient path instead of an error. This is a
fail-open regression of a control that the removed code explicitly ties to two named attack
scenarios (ATK-3, ATK-4).

## Findings

### [HIGH] Removal of merge-gate strict verification silently reopens ATK-3 / ATK-4 in the audit trust-store gate

`head/.claude/adapters/loa_cheval/audit_envelope.py:462-473` (`_check_trust_store`):

```python
def _check_trust_store() -> None:
    status = _trust_store_status()
    if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
        return
    raise RuntimeError(
        "[TRUST-STORE-INVALID] trust-store root_signature does NOT verify "
        "against pinned root pubkey; refusing all writes/reads (issue #690)"
    )
```

Before this PR (`base/.claude/adapters/loa_cheval/audit_envelope.py:469-483`), the same function
accepted a `strict_verify` flag and, when set, refused `BOOTSTRAP-PENDING` trust-stores with
`[TRUST-STORE-BOOTSTRAP-PENDING] ... strict audit verification refuses BOOTSTRAP-PENDING (ATK-3)`.
That flag was driven by `audit_verify_chain(log_path, *, verify_for_merge=False)`
(`base/.claude/adapters/loa_cheval/audit_envelope.py:532`) via
`_strict_verify_enabled()` (`base/.claude/adapters/loa_cheval/audit_envelope.py:136-138`), which
also honored a `LOA_AUDIT_STRICT_VERIFY=1` environment opt-in. This PR deletes
`_strict_verify_enabled` outright and strips `verify_for_merge` from
`audit_verify_chain` (`head/.claude/adapters/loa_cheval/audit_envelope.py:508`).

The same PR also deletes the strict path in two more places:

- `head/.claude/adapters/loa_cheval/audit_envelope.py:476-494` (`_read_trust_cutoff`): previously
  raised `[TRUST-STORE-MISSING]` / `[TRUST-STORE-UNREADABLE]` (ATK-4) when strict verification
  could not read a cutoff; now it silently returns `None` for a missing or unreadable trust-store
  in every case, which makes `_ts_ge_cutoff` (`head/.claude/adapters/loa_cheval/audit_envelope.py:497-505`)
  always return `False` — i.e. no chain entry is ever treated as "post-cutoff" and the
  `STRIP-ATTACK-DETECTED` signature-required check at
  `head/.claude/adapters/loa_cheval/audit_envelope.py:565-575` can never fire once the trust-store
  is gone or corrupted.
- `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160` (`_resolve_pubkey_pem`): previously
  took `allow_local_fallback` and refused the `<key-dir>/<key_id>.pub` fallback when strict; now
  the local-file fallback (`head/.claude/adapters/loa_cheval/audit_envelope.py:156-159`) is
  reachable unconditionally, including from the merge-gate call site at
  `head/.claude/adapters/loa_cheval/audit_envelope.py:578` (`_resolve_pubkey_pem(kid)`, no keyword
  arg possible anymore).

**Failure scenario**: an operator or CI job that previously called
`audit_verify_chain(log, verify_for_merge=True)` — or set `LOA_AUDIT_STRICT_VERIFY=1` — as a
merge/release gate to make sure the audit chain's trust-store is actually signed and unmodifiable,
now gets no error at all: the call signature that accepted `verify_for_merge` no longer exists, so
any such caller either breaks loudly (best case) or — if the calling code was updated in lockstep
outside this diff to simply drop the flag — silently reverts to the always-lenient path with no
behavior change visible in logs. Concretely, an attacker who can (a) delete/withhold the
trust-store file (forcing `BOOTSTRAP-PENDING`) or (b) write a `<key_id>.pub` file into
`LOA_AUDIT_KEY_DIR` matching a `signing_key_id` they control can now get a forged/unsigned audit
chain to verify successfully even under what used to be the strict, merge-time code path — because
that path no longer exists to refuse it. This directly undoes the mitigations the removed code
comments cite by name (`ATK-3`, `ATK-4`, issue `#690`).

Per the grounding requirement: I cannot confirm from this fixture (only three touched files are
in scope) whether a live caller currently passes `verify_for_merge=True` or sets
`LOA_AUDIT_STRICT_VERIFY=1` in CI — that caller, if any, is outside the diff. Given the
docstrings and parameter naming (`verify_for_merge`) are unambiguous about the intended purpose
of the removed code, and the PR removes it as a deliberate simplification ("single code path
again") rather than because it was dead, this is reported at HIGH severity / HIGH confidence as a
regression of a documented security control, with the caveat that confirming real-world
exploitability requires checking callers not present in this fixture.

**Standard**: [CWE-284: Improper Access Control](https://cwe.mitre.org/data/definitions/284.html)
(removal of an authorization/verification tier) and
[OWASP A08:2021 – Software and Data Integrity Failures](https://owasp.org/Top10/A08_2021-Software_and_Data_Integrity_Failures/)
(the audit chain's own integrity-verification gate is weakened without an integrity-verification
mechanism replacing it).

**Remediation**: Restore the strict/merge-gate path (or, if truly unused, prove that with a
repo-wide grep for `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY` across all callers, not just the
three files in this diff, and land the removal with an explicit note that no caller depended on
it). If the intent is genuinely to unify to one lenient code path, that is a security-relevant
policy decision that belongs in an SDD/ADR, not an unannotated "refactor" commit.

## Observations (not tallied)

- `head/.claude/scripts/spiral-evidence.sh:672-703`: the removed `content_bare` backtick-mask was
  only ever fed into Pattern 2 (the bare, non-backtick path matcher). Pattern 1 already operated
  on the unmasked `$content` in both versions. Since backtick characters satisfy Pattern 2's
  non-path-char boundary class the same way whitespace does, and the final `sort -u` dedupes any
  now-redundant match, this removal is a no-op simplification with no observed change in which
  paths are extracted. Speculative/low-confidence, excluded from the tally.
- `head/.claude/scripts/semver-bump.sh:55-94`: dropping prerelease-tag/version support is a
  functional regression (release automation for `-alpha/-beta/-rc` tags will now error via the
  `M-05` format check at `head/.claude/scripts/semver-bump.sh:83-86` rather than bump correctly),
  not a security issue — the validated `current` string is only ever passed to `git rev-list` as
  a ref argument and to bash arithmetic after the strict `^[0-9]+\.[0-9]+\.[0-9]+$` check, so no
  injection path exists either before or after this change.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 0 |
| Low | 0 |

## Verdict

CHANGES_REQUIRED — the HIGH finding is a confirmed removal of a named security control
(ATK-3/ATK-4 trust-store strict-verification) with no replacement mitigation. Restore the
strict/merge-gate path, or land the removal separately with proof (repo-wide, not just this diff)
that no caller/CI gate depends on `verify_for_merge` / `LOA_AUDIT_STRICT_VERIFY`, plus an explicit
ADR/SDD note since this is a security posture change, not a pure refactor.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":0,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
