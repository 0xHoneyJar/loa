# Security Audit Report

**Audit type**: Ad-hoc PR audit (no sprint/beads context — standalone diff review per AUDIT-INSTRUCTIONS.md)
**Scope**: `head.diff` touching 3 files — `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh`
**PR title**: refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

## Executive Summary

This PR bills itself as a simplification/refactor ("single code path again", "release-only version parsing"), but two of its three hunks silently remove previously-shipped, explicitly-labeled attack mitigations rather than dead code. The `audit_envelope.py` change deletes the entire strict-verification code path used for merge-gate audit-chain verification — a path that exists specifically to defend against two named threats (ATK-3, ATK-4) tied to issue #690 — with no replacement and no updated threat-model note. The `spiral-evidence.sh` change reintroduces a previously-fixed false-positive defect class (#1175) into the deliverable-path extractor, which the code's own comments say "invit[es] stub/symlink forgery" against the implementation-evidence gate. The `semver-bump.sh` change is a comparatively low-risk feature removal (prerelease tag support) that is defended by pre-existing downstream validation.

Given the removal of named, issue-tracked security controls without any compensating control or documented rationale in the PR description, this change should not merge as-is.

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Findings

### [HIGH-1] Merge-gate strict audit-chain verification removed; named attack mitigations (ATK-3, ATK-4) silently dropped

**Component**: `head/.claude/adapters/loa_cheval/audit_envelope.py:136` (`_resolve_pubkey_pem`), `:462` (`_check_trust_store`), `:476` (`_read_trust_cutoff`), `:508` (`audit_verify_chain`)

**Description**: The base version of `audit_verify_chain()` accepted a `verify_for_merge: bool` kwarg (also settable via `LOA_AUDIT_STRICT_VERIFY=1`) that, when true, tightened three independent checks used when this function runs as a merge gate:

1. `_check_trust_store(strict_verify=True)` — previously raised `[TRUST-STORE-BOOTSTRAP-PENDING]` and refused to proceed if the trust-store had never been signed (ATK-3). Now (`head/.claude/adapters/loa_cheval/audit_envelope.py:465-471`) `_check_trust_store()` unconditionally treats `BOOTSTRAP-PENDING` the same as `VERIFIED`:
   ```python
   status = _trust_store_status()
   if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
       return
   ```
2. `_read_trust_cutoff(strict_verify=True)` — previously raised `[TRUST-STORE-MISSING]`/`[TRUST-STORE-UNREADABLE]` if the trust-store couldn't be read (ATK-4). Now (`head/.claude/adapters/loa_cheval/audit_envelope.py:483-497`) an unreadable or missing trust-store just silently yields `cutoff = None`, which disables the post-cutoff signature-strip defense (`_ts_ge_cutoff` returns `False` for every entry when `cutoff` is `None`).
3. `_resolve_pubkey_pem(kid, allow_local_fallback=not strict_verify)` — previously refused the `<key-dir>/<key_id>.pub` local-file fallback during strict verification, forcing merge-gate verification to resolve keys only from the trust-store. Now (`head/.claude/adapters/loa_cheval/audit_envelope.py:136-160`) the local-file fallback is unconditional — any signing key that can be dropped into `LOA_AUDIT_KEY_DIR` (or the default `~/.config/loa/audit-keys/`) will verify successfully, trust-store membership or not.

The function signature itself changed (`audit_verify_chain(log_path, *, verify_for_merge: bool = False)` → `audit_verify_chain(log_path)`), so this is not a dead-parameter cleanup: any caller elsewhere in the framework that still invokes `audit_verify_chain(path, verify_for_merge=True)` will now raise `TypeError`, and any caller that only sets `LOA_AUDIT_STRICT_VERIFY=1` will have that env var silently ignored and get the weakened path with no error at all — a fail-open regression for exactly the workflow (merge-gate attestation) this code exists to protect, per the framework's own documentation of MODELINV/audit-envelope usage for merge/verdict integrity.

**Impact**: An attacker (or a misconfigured/compromised CI runner) who can (a) prevent the trust-store from being present/readable, or (b) drop a `.pub` file into the key directory, can now make `audit_verify_chain()` report a chain as verified during what is meant to be the *strict* merge-time check, defeating the ATK-3/ATK-4 mitigations that issue #690 was opened to close. Because the strict path is deleted rather than merely unused, there is no way to restore this behavior short of reverting the diff — it cannot be re-enabled via configuration.

**Remediation**: If strict-verify is genuinely obsolete (e.g., superseded by a different merge-gate mechanism elsewhere), the PR description must say so explicitly and reference what replaces ATK-3/ATK-4 coverage, and the removal should be accompanied by a search for/update of all `verify_for_merge=`/`LOA_AUDIT_STRICT_VERIFY` call sites outside this diff to confirm none rely on it. Absent that, restore the `verify_for_merge` parameter and the three strict-mode branches it guards.

**References**: CWE-295 (Improper Certificate/Trust Validation), CWE-306 (Missing Authentication for Critical Function); repo-internal issue #690, attack IDs ATK-3/ATK-4 (as named in the removed code's own error messages, `head/.claude/adapters/loa_cheval/audit_envelope.py` git history).

---

### [MEDIUM-1] Backtick-masking removal reintroduces false-positive class #1175 in the sprint-evidence deliverable extractor

**Component**: `head/.claude/scripts/spiral-evidence.sh:673` (Pattern 2 of `_parse_sprint_paths`)

**Description**: The base version computed `content_bare` (`sed 's/`[^`]*`//g'`) specifically so that Pattern 2's bare-path extraction would not see text inside backtick-wrapped spans, per the adjacent comment on Pattern 1 (`head/.claude/scripts/spiral-evidence.sh:691-696`, unchanged) describing false-positive guard #1175: "backtick prose also wraps shell commands (`bash tools/x.sh`, `yq -o=json ... file.yaml`) and CLI flags ... that contain `/`+extension and matched as deliverable paths, failing cycles with IMPL_EVIDENCE_MISSING **and inviting stub/symlink forgery**."

The diff deletes the `content_bare` computation and changes Pattern 2 to scan raw `$content` again:
```bash
echo "$content" | grep -oE "(^|[^a-zA-Z0-9_/.-])(src|tests|\.claude/scripts|\.claude/hooks|grimoires)/[a-zA-Z0-9_/.+()-]+\.${ext_re}" \
```
(`head/.claude/scripts/spiral-evidence.sh:697`)

Unlike Pattern 1, Pattern 2 has no follow-on whitespace/glob/leading-char filters to compensate — it directly feeds `sort -u` and becomes part of the required-deliverables list consumed by `_pre_check_implementation_evidence`. A sprint.md line like `` Run `bash grimoires/loa/scripts/migrate.sh` to apply the change `` will now match `grimoires/loa/scripts/migrate.sh` as a required deliverable, exactly the scenario #1175 was fixed to exclude.

**Impact**: This is a self-inflicted regression of an already-fixed defect. Its consequence, per the code's own comment, is not merely spurious CI failures — it is that operators/agents facing a bogus "missing deliverable" from a shell-command example are incentivized to create a stub or symlink file at that path purely to satisfy the gate, which corrupts the evidence-integrity guarantee the entire gate exists to provide (a file existing is supposed to mean "this deliverable was actually produced").

**Remediation**: Restore the `content_bare` backtick-stripped variable and keep Pattern 2 sourced from it, exactly as in the base version. If the intent was to also catch bare (non-backticked) deliverable declarations, that's still satisfied by `content_bare` — backtick-stripping only removes spans that are *already* inside backticks, which is precisely the class Pattern 2 should not be sourced from.

**References**: repo-internal issue #1175 (named directly in the surrounding comment).

---

### [LOW-1] `semver-bump.sh` tag-glob filtering weakened, but caught by downstream validation

**Component**: `head/.claude/scripts/semver-bump.sh:56`

**Description**: `get_version_from_tag()` previously combined a git glob (`v[0-9]*.[0-9]*.[0-9]*` / `v[0-9]*.[0-9]*.[0-9]*-*`) with a strict `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` filter before taking the top tag. The diff drops the `grep -E` filter entirely, relying solely on the git glob:
```bash
tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
```
Git tag globs are fnmatch-style, not anchored regexes — `[0-9]*` matches one digit followed by *any* characters, so tags such as `v1.2.3-custom.suffix` or `v1.2.3.4.5` still pass the `-l` filter and could be selected as "current version" and passed (with leading `v` stripped) into `bump_version()`.

**Impact**: Low — `bump_version()` (`head/.claude/scripts/semver-bump.sh:83-85`, marked "M-05") independently re-validates the string against `^[0-9]+\.[0-9]+\.[0-9]+$` and hard-fails on anything else. Under `set -euo pipefail` (`head/.claude/scripts/semver-bump.sh:19`), a malformed tag therefore aborts the script rather than silently producing a wrong version. This is an availability/correctness nit (a stray or historical non-canonical tag can break version computation until removed), not an exploitable integrity issue.

**Remediation**: Optional — reinstate the `grep -E` post-filter (updated to release-only form, i.e. drop the `(-(alpha|beta|rc)\.[0-9]+)?` group to match the PR's stated intent) so malformed tags are skipped in favor of the next valid one rather than aborting the whole bump.

## Security Checklist Status

- [ ] Authentication & Authorization — merge-gate strict verification path removed (HIGH-1)
- [x] Secrets & Credentials — no secrets handling changed
- [x] Input Validation — semver `bump_version` validation intact (LOW-1 downstream-mitigated)
- [ ] Data/Evidence Integrity — implementation-evidence gate false-positive regression (MEDIUM-1)
- [x] Supply Chain — no dependency changes
- [x] API Security — n/a, no network-facing surface touched

## Verdict and Next Steps

**Immediate (before merge)**: Resolve HIGH-1 — either restore strict-verify plumbing or provide an explicit, documented replacement for ATK-3/ATK-4 coverage and confirm no external caller depends on `verify_for_merge`/`LOA_AUDIT_STRICT_VERIFY`.

**Short-term**: Fix MEDIUM-1 by restoring `content_bare` for Pattern 2 in `spiral-evidence.sh`.

**Long-term**: Consider reinstating the semver tag regex filter (LOW-1) for defense in depth, even though downstream validation currently contains the risk.

**CHANGES_REQUIRED**

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
