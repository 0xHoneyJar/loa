# Review: refactor(audit,spiral,semver): drop strict-verify plumbing, backtick masking and prerelease branches

## Overall Assessment

This PR frames itself as pure plumbing removal ("single code path again"), but two of the three
changes are not neutral simplifications — they silently reduce the security/correctness
guarantees the removed code existed to provide, and the docstrings/comments left in place still
reference the very attack IDs (`ATK-3`, `ATK-4`, `#1175`) the removed code was defending against.
No tests were touched in this diff, and none of the three files' surrounding test suites are
included here to confirm the removed behavior is actually dead. **Changes required.**

## Adversarial Analysis

### Concerns Identified

1. **`audit_envelope.py` — merge-gate strict verification is deleted, not just unused knob
   cleanup.** `head/.claude/adapters/loa_cheval/audit_envelope.py:462-473` collapses
   `_check_trust_store()` to accept `BOOTSTRAP-PENDING` unconditionally — the `strict_verify`
   branch that raised `[TRUST-STORE-BOOTSTRAP-PENDING]` "strict audit verification refuses
   BOOTSTRAP-PENDING (ATK-3)" is gone. Likewise `head/.claude/adapters/loa_cheval/audit_envelope.py:476-494`
   (`_read_trust_cutoff`) no longer raises `[TRUST-STORE-MISSING]`/`[TRUST-STORE-UNREADABLE]`
   ("strict audit verification requires a readable trust-store (ATK-4)") — a missing or
   unreadable trust-store now just silently yields `cutoff=None`, which per `_ts_ge_cutoff`
   (`head/.claude/adapters/loa_cheval/audit_envelope.py:497-505`) treats **every** entry as
   pre-cutoff, disabling the strip-attack check entirely. And `_resolve_pubkey_pem`
   (`head/.claude/adapters/loa_cheval/audit_envelope.py:136-160`) drops
   `allow_local_fallback`, so verification can now always resolve a signer's key from the local
   `<key-dir>/<key_id>.pub` file instead of being forced to the trust-store entry — exactly the
   downgrade path strict mode existed to close (an attacker who can write to the key dir can
   plant their own "trusted" pubkey). `audit_verify_chain` itself
   (`head/.claude/adapters/loa_cheval/audit_envelope.py:508`) drops the `verify_for_merge`
   keyword entirely, so any caller that was invoking it as a merge gate with
   `verify_for_merge=True` either breaks with a `TypeError` or — more likely, since this diff
   compiles — was never wired up, meaning the ATK-3/ATK-4 mitigations added under issue #690
   never got exercised by a real caller and are now deleted with no equivalent replacement. This
   is a straight security regression, not a plumbing simplification, and the PR description does
   not mention that it removes attack mitigations.

2. **`spiral-evidence.sh` — removing the backtick mask reopens the exact false-positive class
   issue #1175 was filed for.** `head/.claude/scripts/spiral-evidence.sh:700` now feeds raw
   `$content` (not `content_bare`) into Pattern 2's bare-path grep. The retained comment at
   `head/.claude/scripts/spiral-evidence.sh:683-689` explains *why* `content_bare` existed:
   Pattern 1 (backtick-wrapped paths) has explicit noise filters — `grep -v '[[:space:]]'`,
   `grep -v '[*]'`, `grep -vE '^[-@]'` — specifically because backtick-quoted prose in
   `sprint.md` often contains shell invocations and CLI flags, not deliverable declarations (e.g.
   `` `bash .claude/scripts/foo.sh --dry-run` ``). Pattern 2 has none of those filters and was
   previously restricted to content *outside* backticks for exactly that reason. With the mask
   removed, a prose reference like `` `run .claude/scripts/spiral-evidence.sh --check` `` inside
   a Risks/Technical-Tasks section (not a real `### Deliverables` entry) will now be extracted by
   Pattern 2 as a required deliverable path, because Pattern 2's anchored-prefix regex
   (`(src|tests|\.claude/scripts|\.claude/hooks|grimoires)/...`) matches happily inside backticks
   and stops cleanly at the space before `--check`. This directly reintroduces the
   `IMPL_EVIDENCE_MISSING` false-positive / forgery-invitation failure mode #1175 was written to
   fix, for any backtick example that happens to start with one of the five anchored prefixes.

3. **`semver-bump.sh` — dropping prerelease parsing can hard-crash release automation instead of
   erroring cleanly.** `head/.claude/scripts/semver-bump.sh:55-63` (`get_version_from_tag`) still
   lists tags with the *glob* `v[0-9]*.[0-9]*.[0-9]*`, which still matches a prerelease tag like
   `v1.2.3-alpha.1` (glob `*` matches `-alpha.1` after the trailing `[0-9]`) — the base version's
   second explicit pattern + `grep -E` filter that rejected/normalized those tags is gone. If
   such a tag sorts newest under `--sort=-v:refname` (plausible if the repo or any downstream
   consumer of this script ever cuts an alpha/beta/rc tag), `current` becomes `"1.2.3-alpha.1"`,
   and `bump_version` (`head/.claude/scripts/semver-bump.sh:79-94`) now rejects it via the strict
   `^[0-9]+\.[0-9]+\.[0-9]+$` check and `return 1`. Under `set -euo pipefail`
   (`head/.claude/scripts/semver-bump.sh:19`), the `next=$(bump_version "$current" "$bump")`
   assignment at `head/.claude/scripts/semver-bump.sh:333` then aborts the whole script with a
   raw, uncaught failure instead of the previous graceful "keep bumping the prerelease counter"
   behavior. The PR description calls this "release-only version parsing," but nothing in this
   diff (or the fixture) demonstrates that prerelease tags are actually unused across the
   framework's release history — this is an unverified assumption baked into a `set -e` script
   that other automation (per `CLAUDE.loa.md`'s Post-Merge Automation section) depends on for
   every tag/release cycle.

### Assumptions Challenged

- **Assumption**: The engineer assumed no caller currently depends on `verify_for_merge=True` /
  `LOA_AUDIT_STRICT_VERIFY=1` on `audit_verify_chain`, and no repo tag history contains a
  prerelease version, so removing both is behavior-neutral.
- **Risk if wrong**: If any merge-gate caller does pass `verify_for_merge=True` today, this diff
  breaks that call outright (removed keyword argument); if it doesn't, the ATK-3/ATK-4
  mitigations were dead code and their removal is fine functionally but the PR should say so
  explicitly rather than describe it as inert plumbing. For semver-bump.sh, if any prerelease tag
  exists anywhere in the tag history this script walks, the post-merge release pipeline hard-fails
  the next time that tag sorts newest.
- **Recommendation**: Grep the actual repo (not available in this fixture) for
  `verify_for_merge=`, `LOA_AUDIT_STRICT_VERIFY`, and any `v*-alpha`/`-beta`/`-rc` tags before
  merging. If none exist, say so in the PR description as the justification — "unused, verified
  no callers" is a materially different claim than "plumbing cleanup."

### Alternatives Not Considered

- **Alternative**: If the strict-verify path in `audit_envelope.py` really is unused, the safer
  simplification is to make the *strict* behavior the sole/default path (always require
  trust-store-resolved keys, always reject `BOOTSTRAP-PENDING`/missing-cutoff for verification
  calls) rather than collapsing to the permissive path. That is a breaking change for any
  bootstrap-time caller, but it fails closed instead of failing open.
- **Tradeoff**: Failing closed by default could break early bootstrap flows (issue #690's stated
  reason `BOOTSTRAP-PENDING` exists at all) that legitimately need to operate before a
  trust-store is signed.
- **Verdict**: Current approach (fail open, delete the strict option) should be reconsidered
  unless the PR can show the strict path had zero callers — in which case removing it is fine,
  but should be stated as "removing dead security code, confirmed unused" rather than "dropping
  strictness knobs."

## Non-Critical Improvements

- `head/.claude/scripts/semver-bump.sh:54` and `:79` add one-line "what" comments (`# Get current
  version from the latest git tag matching v*.*.*`, `# Bump a version string by type`) that only
  restate the function name — no WHY, so per the repo's own comment convention these should be
  dropped rather than added. Non-blocking.

## Previous Feedback Status

N/A — no prior `engineer-feedback.md` exists for this change (ad-hoc PR review, no sprint context).

## Next Steps

1. Confirm (via repo-wide grep, not available in this fixture) that no caller passes
   `verify_for_merge=True` / sets `LOA_AUDIT_STRICT_VERIFY=1` to `audit_verify_chain` /
   `_check_trust_store` / `_read_trust_cutoff` / `_resolve_pubkey_pem`. If a caller exists, this
   PR breaks it and must restore the strict path (or migrate the caller first).
2. Either restore the `content_bare` backtick mask in `spiral-evidence.sh`'s Pattern 2, or add
   the same noise filters (`grep -v '[[:space:]]' | grep -v '[*]' | grep -vE '^[-@]'`) to Pattern
   2's output so backtick-quoted CLI examples aren't picked up as deliverable paths.
3. Either restore prerelease tag parsing in `semver-bump.sh`, or confirm no prerelease tags exist
   in this project's/framework's tag history and add a defensive `|| true` / explicit error
   message so a stray prerelease tag produces a clear "unsupported tag format" error instead of
   an unguarded `set -e` abort.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"sprint_id":"pr-02","ts":"2026-09-21T00:00:00Z"} -->
