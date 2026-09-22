# Review: refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

## Overall Assessment

**Changes required.** This PR bundles three independent "simplification" refactors across
`audit_envelope.py`, `spiral-evidence.sh`, and `semver-bump.sh`. All three removals reopen
previously-fixed or previously-hardened behavior:

1. `audit_envelope.py` deletes the entire strict-verify code path (ATK-3/ATK-4 mitigations)
   with no evidence the merge-gate caller that used it was also retired.
2. `spiral-evidence.sh` removes the backtick-masking step that was added specifically to fix
   issue #1175 (false-positive deliverable-path detection), reintroducing that exact bug class
   for Pattern 2.
3. `semver-bump.sh` removes the tag-format validation grep but the underlying `git tag -l` glob
   still matches prerelease tags (glob `*` backtracks across literal `.`), so a prerelease tag can
   still be selected as "current" and then crash `bump_version()` under `set -e`.

None of these are cosmetic — each is a behavioral regression with a concrete failure scenario
below. The PR description undersells the risk by framing all three as "drop plumbing" / "return
to X" rather than acknowledging what protection is being removed.

## Critical Issues

### 1. Security regression: strict-verify (ATK-3/ATK-4) mitigations deleted, and the API break is unverified

`head/.claude/adapters/loa_cheval/audit_envelope.py:462-473` (`_check_trust_store`) now always
treats `BOOTSTRAP-PENDING` as pass:

```python
def _check_trust_store() -> None:
    status = _trust_store_status()
    if status in ("BOOTSTRAP-PENDING", "VERIFIED"):
        return
    raise RuntimeError(...)
```

The base version raised `[TRUST-STORE-BOOTSTRAP-PENDING]` when `strict_verify=True` (merge-gate
mode) — this was the ATK-3 mitigation: "an unsigned/unbootstrapped trust-store must not pass a
merge gate." Similarly `_read_trust_cutoff()` (`head/.claude/adapters/loa_cheval/audit_envelope.py:476-494`)
no longer raises `[TRUST-STORE-MISSING]` / `[TRUST-STORE-UNREADABLE]` when the trust-store is
missing/unreadable (ATK-4), and `_resolve_pubkey_pem()`
(`head/.claude/adapters/loa_cheval/audit_envelope.py:136-160`) always permits the local
`<key-dir>/<key_id>.pub` fallback — the exact bypass strict mode was created to forbid ("only
trust-store-pinned keys count when this is a merge gate").

**Failure scenario**: a repo with a tampered or never-bootstrapped trust-store (e.g., an attacker
drops a `.pub` file into the local key directory and points a forged log entry at it) previously
failed `audit_verify_chain(log_path, verify_for_merge=True)` at merge time with
`[TRUST-STORE-BOOTSTRAP-PENDING]` / cannot use local fallback. After this change, the exact same
tampered state now verifies successfully in *every* mode, because there is no longer a stricter
mode to invoke.

**Compounding concern**: `audit_verify_chain` and `_check_trust_store`/`_read_trust_cutoff` had
their signatures changed (the `verify_for_merge` / `strict_verify` keyword-only parameters were
removed outright, not deprecated). This file is a small slice of a larger framework
(`.claude/loa/CLAUDE.loa.md` references a "merge gate" concept extensively, and the docstring at
`head/.claude/adapters/loa_cheval/audit_envelope.py:464` still says "Gate function called at top
of audit_emit + audit_verify_chain"). If any caller elsewhere in the repo (a merge-gate hook, CI
script, or `/audit-sprint`-style skill) still invokes
`audit_verify_chain(log_path, verify_for_merge=True)`, this now raises `TypeError: unexpected
keyword argument 'verify_for_merge'` — a hard crash, not a graceful degrade. This PR's diff does
not touch or search for such callers, and the review sandbox does not contain the rest of the
repo to confirm they don't exist.

**Fix**: Either (a) confirm via full-repo grep for `verify_for_merge=` / `LOA_AUDIT_STRICT_VERIFY`
that no caller depends on strict mode, and get explicit security sign-off that ATK-3/ATK-4 are no
longer needed (e.g., because bootstrap is now enforced elsewhere), documenting that decision; or
(b) keep the keyword-only parameters (even as no-ops with a deprecation warning) so callers don't
crash, and restore the strict checks if the merge-gate use case is still live.

## High-Severity Issues

### 2. `spiral-evidence.sh` reintroduces the #1175 false-positive class it was fixed for

`head/.claude/scripts/spiral-evidence.sh:700` now runs Pattern 2 against raw `$content` instead
of the backtick-stripped `$content_bare` that was deleted from
`head/.claude/scripts/spiral-evidence.sh` (previously present right before line 679 in the base
file, at `base/.claude/scripts/spiral-evidence.sh:673-674`):

```bash
echo "$content" | grep -oE "(^|[^a-zA-Z0-9_/.-])(src|tests|\.claude/scripts|\.claude/hooks|grimoires)/[a-zA-Z0-9_/.+()-]+\.${ext_re}" \
    2>/dev/null | \
    sed -E 's/^[^a-zA-Z.]//'
```

Pattern 1 (`head/.claude/scripts/spiral-evidence.sh:679-689`) has an explicit false-positive guard
labeled "(#1175)" that filters out backtick-wrapped shell commands / CLI flags (anything with
whitespace, a glob, or a leading `-`/`@`) because prose like
`` `bash .claude/scripts/foo.sh --env=prod` `` would otherwise be captured as a deliverable path.
Pattern 2 has **no such guard** — it relies entirely on the (now-removed) backtick masking to
avoid matching path-like substrings embedded inside those same backtick-wrapped commands, since
its anchor char-class treats a backtick as a valid "non-path" boundary character.

**Failure scenario**: a sprint.md "Technical Tasks" or "Risks" prose line containing
`` `bash .claude/scripts/deploy.sh --dry-run` `` will now have `.claude/scripts/deploy.sh`
extracted by Pattern 2 as a required deliverable path (no whitespace/glob filter applies to
Pattern 2's raw match, since the char class stops matching at the extension, discarding the
trailing ` --dry-run`). The evidence gate (`_pre_check_implementation_evidence`) will then treat
`.claude/scripts/deploy.sh` as an enumerated deliverable and fail the cycle with
`IMPL_EVIDENCE_MISSING` if that file doesn't exist — exactly the false-positive class the original
`content_bare` masking, comment, and #1175 reference describe.

**Fix**: restore the `content_bare` backtick-stripped variable and feed it to Pattern 2 as before;
if the goal was only to remove Pattern 1's masking (it never used `content_bare` to begin with),
say so explicitly, because the diff removed the masking used by Pattern 2 too.

### 3. `semver-bump.sh`: loosened tag glob + stricter `bump_version` combine to crash on prerelease tags

`head/.claude/scripts/semver-bump.sh:57`:

```bash
tag=$(git -C "$PROJECT_ROOT" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
```

Git's tag-glob matching (`wildmatch`) treats `.` as a literal character and `*` as unanchored —
it backtracks to satisfy the rest of the pattern. `v[0-9]*.[0-9]*.[0-9]*` therefore still matches
a tag like `v1.3.0-rc.1` (the final `*` absorbs `-rc.1`), exactly like the base version's
identical glob argument did — that's *why* base additionally piped through
`grep -E '^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$'` before `head -1`, restricting the
accepted set to only well-formed release/prerelease tags. That grep is now gone
(`head/.claude/scripts/semver-bump.sh:54-63`), so nothing filters out a malformed or prerelease
tag that happens to satisfy the loose glob and sort highest.

Meanwhile `bump_version()` (`head/.claude/scripts/semver-bump.sh:80-94`) now *only* accepts
`^[0-9]+\.[0-9]+\.[0-9]+$` and returns 1 for anything else (the prerelease branch was deleted).

**Failure scenario**: repo has tags `v1.2.0` and `v1.3.0-rc.1` (version-sort ranks `1.3.0-rc.1`
above `1.2.0` since it compares the numeric triple first). `get_version_from_tag` now returns
`1.3.0-rc.1` unfiltered. At `head/.claude/scripts/semver-bump.sh:333`
(`next=$(bump_version "$current" "$bump")`), `bump_version` prints
`ERROR: Invalid version format: 1.3.0-rc.1` and returns 1; because the script runs under
`set -euo pipefail` (`head/.claude/scripts/semver-bump.sh:19`) and this call is unguarded (no
`||`), the whole script aborts. This is a regression from the base behavior, which correctly
computed the next prerelease version in this scenario, and it's *worse* than a graceful "no
release tags found" — it's a mid-script crash after already computing commit history.

**Fix**: either keep the strict-format grep filter on `get_version_from_tag` (dropping only the
prerelease-parsing *bump* logic, if release-only bumping is truly the intent), or tighten the
`git tag -l` glob itself (e.g. add `--sort` plus a post-filter) so prerelease tags are never
selected as "current" for this release-only code path.

## Non-Critical Improvements

- `head/.claude/scripts/semver-bump.sh:54` and `:79` — the new one-line comments ("Get current
  version from the latest git tag matching `v*.*.*`") describe the intended glob but not the
  actual matching behavior (see Issue 3); if the strict-filter fix above isn't taken, at least
  correct the comment so the next reader doesn't reason from the same false assumption the
  removed code guarded against.
- `head/.claude/adapters/loa_cheval/audit_envelope.py:136` — `_resolve_pubkey_pem`'s docstring
  still says "test/CI fallback" for the local `<key-dir>/<key_id>.pub` path; now that it's
  unconditional, worth noting in the docstring that production writes/reads can also resolve keys
  this way, so a reader auditing the trust model doesn't assume it's test-only.

## Adversarial Analysis

### Concerns Identified (minimum 3 — have 3, all elaborated above as Critical/High)
1. Deleting `verify_for_merge`/`strict_verify` removes ATK-3/ATK-4 mitigations with no
   confirmation the merge-gate caller was also removed or is otherwise safe
   (`head/.claude/adapters/loa_cheval/audit_envelope.py:462-473`).
2. `spiral-evidence.sh` Pattern 2 loses its only false-positive guard against backtick-wrapped
   shell-command prose, reintroducing issue #1175's failure mode
   (`head/.claude/scripts/spiral-evidence.sh:700`).
3. `semver-bump.sh`'s loosened tag selection combined with the stricter `bump_version` produces an
   unguarded crash under `set -e` whenever the highest-sorted tag is a prerelease
   (`head/.claude/scripts/semver-bump.sh:57`, `:333`).

### Assumptions Challenged (minimum 1)
- **Assumption**: The engineer assumed `verify_for_merge=True` / `LOA_AUDIT_STRICT_VERIFY=1` had
  no remaining callers, making the branch dead code safe to delete.
- **Risk if wrong**: Any live caller (a merge-gate script, `/audit-sprint`-adjacent tooling)
  crashes with `TypeError` on the next invocation, or — worse if it catches the exception broadly
  — silently stops enforcing the merge gate at all.
- **Recommendation**: Make this assumption explicit in the PR description with the grep evidence
  ("no remaining callers of `verify_for_merge=`/`LOA_AUDIT_STRICT_VERIFY` found repo-wide"), or
  restore the parameter as a safe no-op.

### Alternatives Not Considered (minimum 1)
- **Alternative**: For `spiral-evidence.sh`, instead of deleting `content_bare` entirely, add
  Pattern 2's own whitespace/glob false-positive guard (mirroring Pattern 1's #1175 guard) so both
  patterns are self-sufficient and backtick-masking becomes unnecessary defense-in-depth rather
  than the sole protection.
- **Tradeoff**: Slightly more filtering logic duplicated across the two patterns, but removes the
  fragile cross-pattern dependency where Pattern 2's correctness silently relied on a variable
  that lived textually next to Pattern 1.
- **Verdict**: Should reconsider — the current fix (this PR) simply deletes the protection instead
  of hardening it, which is a net regression, not a simplification.

## Previous Feedback Status

N/A — this is a standalone PR review with no prior `engineer-feedback.md` / sprint context
(per REVIEW-INSTRUCTIONS.md, no sprint plan/beads/`grimoires/loa/a2a/` directory exists for this
review).

## Incomplete Tasks / AC Verification

N/A — no `sprint.md` or acceptance-criteria document is present in this review's input set; the
PR is reviewed purely against its own stated intent (PR.md) and the diff's correctness.

## Next Steps

1. Restore or explicitly justify removal of the ATK-3/ATK-4 strict-verify checks in
   `audit_envelope.py`, with evidence that no caller still requests strict mode.
2. Restore backtick masking (or an equivalent guard) for Pattern 2 in `spiral-evidence.sh`.
3. Fix `semver-bump.sh`'s tag selection so a prerelease-formatted tag can never reach
   `bump_version()` given its now release-only validation — either restore the filter grep or
   tighten the glob.
4. Re-request review once these are addressed; until then this PR should not merge as-is.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":2,"medium":0,"low":2},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
