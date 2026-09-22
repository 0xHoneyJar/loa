# Security Audit Report

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory available)
**Scope**: `head.diff` — 3 files: `.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/spiral-evidence.sh`, `.claude/scripts/semver-bump.sh`
**PR**: "refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches"

## Executive Summary

This PR is framed as a pure simplification/cleanup ("single code path again"), but it removes three independent safety mechanisms, and in two of the three cases the removal is either incomplete or introduces a functional regression rather than a clean behavior change:

1. It deletes the only "strict" verification mode of the Ed25519 audit-chain verifier (`verify_for_merge` / `LOA_AUDIT_STRICT_VERIFY`), permanently downgrading every caller — including any merge-gate caller that previously requested strict semantics — to the permissive path (BOOTSTRAP-PENDING trust-stores accepted, unpinned local `.pub` key files accepted as a signature source).
2. It removes the backtick-span masking used by the spiral evidence-gate's bare-path matcher, re-opening a false-positive class (documentation/CLI examples matched as "declared deliverables") that the code's own adjacent comment identifies as inviting "stub/symlink forgery" to satisfy the gate — but only re-opens it for the un-guarded of the two extraction patterns.
3. It removes prerelease-tag *parsing* logic from `semver-bump.sh` but leaves the prerelease-tag *matching* glob in place, so a leftover/legacy prerelease tag can now be selected as "current version" and crash the release/version-bump path outright instead of being filtered out as before.

None of the three are classic injection/RCE-class bugs, but #1 is a genuine security-control regression (authentication/trust downgrade) and #2/#3 are process-integrity and availability regressions in gates this repository's own `CLAUDE.md` designates as load-bearing ("ALWAYS use post-merge-orchestrator.sh... NEVER create tags manually — always use semver-bump.sh", and the spiral evidence gate's explicit anti-forgery purpose).

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 0 |

## High Priority Issues

### H-1: Strict merge-time audit-chain verification removed; all callers silently downgraded to permissive trust semantics

**Component**: `head/.claude/adapters/loa_cheval/audit_envelope.py:462-473`, `head/.claude/adapters/loa_cheval/audit_envelope.py:508-538`, `head/.claude/adapters/loa_cheval/audit_envelope.py:136-160`, `head/.claude/adapters/loa_cheval/audit_envelope.py:578`

**Description**: The base version of this module implemented a two-tier verification model, gated by `verify_for_merge=True` (a caller-supplied kwarg on `audit_verify_chain`) or the `LOA_AUDIT_STRICT_VERIFY=1` env var:

- Non-strict (default): a trust-store in `BOOTSTRAP-PENDING` state (unsigned/not-yet-bootstrapped) is accepted, and signatures may be resolved against a local `<key_id>.pub` file under `LOA_AUDIT_KEY_DIR` as a CI/test fallback when the trust-store doesn't list the key.
- Strict (`verify_for_merge=True`): `BOOTSTRAP-PENDING` trust-stores are **refused** (`[TRUST-STORE-BOOTSTRAP-PENDING]`, citing "ATK-3"), a missing/unreadable trust-store raises (`[TRUST-STORE-MISSING]`/`[TRUST-STORE-UNREADABLE]`, citing "ATK-4"), and the local-`.pub`-file fallback is disabled (`allow_local_fallback=not strict_verify`) so a signature can only be validated against a key actually present in the pinned trust-store.

This PR deletes `_strict_verify_enabled`, the `verify_for_merge` parameter of `audit_verify_chain` (`head/.claude/adapters/loa_cheval/audit_envelope.py:508`), the `strict_verify` parameter of `_check_trust_store` (`head/.claude/adapters/loa_cheval/audit_envelope.py:462`) and `_read_trust_cutoff` (`head/.claude/adapters/loa_cheval/audit_envelope.py:476`), and the `allow_local_fallback` parameter of `_resolve_pubkey_pem` (`head/.claude/adapters/loa_cheval/audit_envelope.py:136`, call site at `head/.claude/adapters/loa_cheval/audit_envelope.py:578`). `_check_trust_store` now unconditionally treats `BOOTSTRAP-PENDING` the same as `VERIFIED` (`head/.claude/adapters/loa_cheval/audit_envelope.py:468`), and pubkey resolution always falls back to a local `.pub` file (`head/.claude/adapters/loa_cheval/audit_envelope.py:156-159`).

**Impact**: Anything that previously called `audit_verify_chain(log_path, verify_for_merge=True)` — the natural name for a merge-gate / CI-release check — to get the stricter ATK-3/ATK-4 guarantees now silently receives the permissive path with no error, no deprecation warning, and no way to opt back in (`LOA_AUDIT_STRICT_VERIFY` is also gone). Concretely, post-merge, an attacker (or a misconfigured CI job) who can write a file to `LOA_AUDIT_KEY_DIR` (which is itself env-var-controlled: `head/.claude/adapters/loa_cheval/audit_envelope.py:67-74`) can supply a `<key_id>.pub` that verifies a forged/self-signed audit-chain entry even when the pinned trust-store does not vouch for that key — the exact scenario the removed `allow_local_fallback` gate existed to prevent at merge time. Similarly, a trust-store that has been reset/tampered into `BOOTSTRAP-PENDING` (e.g. by deleting its `keys`/`revocations`/`root_signature` fields) is now accepted at every call site, including whatever previously demanded `VERIFIED`.

This repo's touched-files-only diff doesn't let me enumerate every caller of `audit_verify_chain` (the base/head snapshot here contains only the three files in the diff), so I can't confirm a specific merge-gate call site broke. That is itself the risk: this is a public-API signature change on a function documented as sharing "the same interface contract as the bash version" (`head/.claude/adapters/loa_cheval/audit_envelope.py:6`) and covered by "behavior identity" integration tests (`head/.claude/adapters/loa_cheval/audit_envelope.py:18-21`) — if the bash sibling (`audit-envelope.sh`, not in this diff) still exposes strict/merge verification, this PR has also broken bash/Python behavior parity for a security-relevant code path.

**Remediation**:
1. Before merging, grep the full repository (not just this diff) for `verify_for_merge=` and `LOA_AUDIT_STRICT_VERIFY` to confirm no caller depended on strict semantics; if any merge/CI/release gate did, this PR silently disables that gate and must not land as-is.
2. Confirm `audit-envelope.sh` (bash counterpart) either also drops strict-verify in the same PR, or this PR reintroduces it in Python — divergence between the two adapters violates the documented "behavior identity" contract and the accompanying bats tests should catch it; if they don't, the test coverage itself has a gap.
3. If strict verification is genuinely obsolete (e.g., because the trust-store bootstrap ceremony from issue #690 is now always complete in every deployment), say so explicitly in the PR description and confirm via the trust-store's actual rollout status — do not infer it from "single code path is simpler."

## Medium Priority Issues

### M-1: `spiral-evidence.sh` bare-path deliverable matcher loses its false-positive guard, reopening the exact "stub/symlink forgery" incentive its own comment warns about

**Component**: `head/.claude/scripts/spiral-evidence.sh:682-703`

**Description**: `_parse_sprint_paths` extracts declared-deliverable file paths from `sprint.md` via two patterns: Pattern 1 matches backtick-wrapped paths (`` `src/foo.ts` ``) and Pattern 2 matches bare (un-backticked) paths rooted at whitelisted prefixes (`src/`, `tests/`, `.claude/scripts/`, `.claude/hooks/`, `grimoires/`). The base version computed `content_bare` — `content` with every backtick-delimited span deleted entirely (`sed 's/`[^`]*`//g'`) — and ran Pattern 2 against `content_bare` instead of `content`. This PR removes `content_bare` and reverts Pattern 2 to scan the raw `content` (`head/.claude/scripts/spiral-evidence.sh:700`).

Pattern 1 carries an explicit false-positive guard, documented in the adjacent comment (`head/.claude/scripts/spiral-evidence.sh:681-687`, "False-positive guard (#1175)"): backtick-quoted prose frequently contains shell commands and CLI examples (`` `bash tools/x.sh` ``, `` `yq -o=json ... file.yaml` ``) that happen to contain a `/` + known extension, and without filtering, these get matched as "declared deliverables," causing the evidence gate to fail with `IMPL_EVIDENCE_MISSING` for a file that was never meant to be a deliverable — the comment states this explicitly "invit[es] stub/symlink forgery" (i.e. engineers create a throwaway file just to satisfy a spurious gate requirement, defeating the gate's actual anti-forgery purpose). Pattern 1 mitigates this with `grep -v '[[:space:]]' | grep -v '[*]' | grep -vE '^[-@]'` (`head/.claude/scripts/spiral-evidence.sh:688-690`). **Pattern 2 has no equivalent guard** — it never did, because `content_bare` was doing that job by removing the entire backtick span (command text and all) before Pattern 2 ever ran over it.

With this change, a sprint.md line like:
```
Run `bash .claude/scripts/foo.sh --check` to validate.
```
now has ` .claude/scripts/foo.sh` extracted by Pattern 2 as a bare path (the leading space satisfies the `(^|[^a-zA-Z0-9_/.-])` boundary), with no space/glob/leading-`-`/`@` filter available to reject it, because Pattern 2's regex boundary only anchors on the *start* of the match, not the rest of the line — a trailing `--check` flag doesn't stop `.claude/scripts/foo.sh` from having already matched.

**Impact**: Re-introduces exactly the failure mode issue #1175 was opened for, but only for the un-guarded pattern: legitimate sprint.md prose (usage examples, command references) can now generate a spurious required-deliverable path, causing `_pre_check_implementation_evidence` to fail the cycle with `IMPL_EVIDENCE_MISSING` for a path nobody declared as a deliverable. Per the codebase's own comment, the practical consequence of recurring spurious gate failures is that engineers are pushed toward creating throwaway stub files/symlinks to make the gate pass — which is precisely the evidence-forgery behavior this gate exists to prevent.

**Remediation**: Restore `content_bare` (or an equivalent backtick-span strip) ahead of Pattern 2, or extend Pattern 2 with the same `grep -v` space/glob/leading-dash guard Pattern 1 already has. If the intent was genuinely to make Pattern 2 backtick-agnostic, add the missing false-positive filter rather than deleting the masking outright.

### M-2: `semver-bump.sh` still *matches* prerelease-suffixed tags but no longer validates/filters them, so a legacy prerelease tag can crash version resolution instead of being safely ignored

**Component**: `head/.claude/scripts/semver-bump.sh:55-63`, `head/.claude/scripts/semver-bump.sh:80-94`

**Description**: The base version listed both release tags (`'v[0-9]*.[0-9]*.[0-9]*'`) and prerelease tags (`'v[0-9]*.[0-9]*.[0-9]*-*'`) via `git tag -l`, then piped the combined, version-sorted list through `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` to strictly validate format before taking the first (highest) match. This PR removes both the second glob and the `grep -E` filter, leaving:

```sh
tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
```

The single remaining glob `'v[0-9]*.[0-9]*.[0-9]*'` is a *shell/git glob*, not an anchored regex: `*` matches any run of characters (including `-`, `.`, letters), so a tag such as `v1.3.0-rc.1` still matches this glob and can still be selected by `git tag -l`. Without the `grep -E` step that previously rejected non-conforming formats, `get_version_from_tag` now returns whatever `head -1` of the version-sorted list is, with **no format validation at all** (`head/.claude/scripts/semver-bump.sh:57-60`) — it simply strips the leading `v` and returns.

Downstream, `bump_version` (`head/.claude/scripts/semver-bump.sh:80-94`) does validate strictly (`^[0-9]+\.[0-9]+\.[0-9]+$`, `head/.claude/scripts/semver-bump.sh:83`) and now has no prerelease-bump branch at all (the base version's `prerelease_re` handling — incrementing `-alpha.N`/`-beta.N`/`-rc.N` — is fully removed).

**Impact**: If the repository has ever created a prerelease tag (`v*-alpha.N`, `v*-beta.N`, `v*-rc.N`) that git's version-sort ranks at or above the latest true release tag, `get_version_from_tag` will now hand that prerelease string straight to `bump_version`, which will reject it and `return 1` with `ERROR: Invalid version format: <tag>`. Previously this was impossible: the `grep -E` filter either matched a fully-valid release/prerelease string (and the old `bump_version` had a working prerelease branch to handle it) or excluded the tag from consideration entirely. Given `CLAUDE.md`'s own framing — "NEVER create tags manually — always use semver-bump.sh for version computation" — a hard failure here breaks the only sanctioned path to computing the next release version, which is an availability/process regression in release tooling, not a memory-safety bug, but still a real production impact for an intentionally-narrowed "release-only" script that no longer defends against the exact tag shapes its own matching glob still admits.

**Remediation**: Either (a) narrow the `git tag -l` glob so it cannot match prerelease-suffixed tags in the first place (e.g. filter out tags containing `-` post-listing), or (b) keep a `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` validation step so any tag that doesn't conform to the now-release-only contract is skipped rather than fatally consumed. Add a regression test with a mixed tag set (one release tag, one higher-sorting prerelease tag) asserting `get_version_from_tag` returns the release tag, not an error.

## Security Checklist Status

- [x] Reviewed all lines touched by the diff (218 lines across 3 files)
- [x] Traced trust/verification control-flow change to concrete impact (H-1)
- [x] Traced gate-matching regex change to concrete impact (M-1)
- [x] Traced version-parsing change to concrete impact (M-2)
- [ ] Confirmed absence of other callers of `verify_for_merge` / `LOA_AUDIT_STRICT_VERIFY` fleet-wide — **not possible from this PR's touched-files-only snapshot; flagged in H-1 as a pre-merge action item**
- [ ] Confirmed bash/Python adapter behavior parity for `audit_verify_chain` — **not possible; `audit-envelope.sh` is not part of this diff**

## Threat Model Summary

The primary asset at risk is the integrity guarantee of the Ed25519-signed audit-envelope chain (`L1`-class primitive per this repo's Agent-Network model) at the moment it matters most — merge/release time. H-1 removes the only code path that hardened that guarantee beyond the day-to-day "don't break normal operation" default, and does so as an undifferentiated deletion with no caller audit visible in the diff. M-1 and M-2 both weaken gates whose entire purpose is to prevent process-level forgery (fake deliverables, malformed release versions) — ironically, M-1's own left-behind comment describes the exact failure mode it reopens.

## Verdict

**CHANGES_REQUIRED**

H-1 must be resolved (confirm no merge-gate caller relied on `verify_for_merge=True`, or restore strict-verify) before this PR can be approved. M-1 and M-2 should be fixed in the same PR since they are small, targeted regressions of previously-fixed issues (#1175 for M-1; the base prerelease-handling logic for M-2).

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":2,"low":0},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
