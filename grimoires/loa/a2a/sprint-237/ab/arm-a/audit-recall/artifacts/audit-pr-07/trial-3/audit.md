# Security Audit Report — chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present)
**Scope**: `head.diff` touching `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/constructs-lib.sh`, `.claude/scripts/lib/symlink-manifest.sh`
**Auditor**: auditing-security skill

## Executive Summary

This PR makes three changes: (1) it narrows the `rm -rf` guard's hidden-path exclusion list from "every hidden path" to eight named sensitive directories plus `.env*`, so that other bounded hidden subdirectories (e.g. `./.loa/`) are no longer conservatively blocked; (2) it removes slug-verification from `find_local_source()` in the constructs library, making it return the first search-path entry that contains *any* `construct.yaml`/`manifest.json`, regardless of whether it declares the requested slug; and (3) it hardens construct symlink-manifest validation to flat-out reject any `..` segment in either the link or the target, replacing a more permissive normalize-and-resolve check.

Change (3) is a genuine hardening and introduces no issues. Change (1) is a real security regression in a security-critical hook: the new hidden-path allow-list is broader than the named exclusion list it pairs with, so several classes of credential-bearing dotfiles that are **not** one of the eight named entries (`.git`, `.ssh`, `.aws`, `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`) or `.env*` now fall through to ALLOW instead of the previous conservative block/ambiguous path. Change (2) weakens an implicit integrity check that construct code loaded from a local development source actually corresponds to the slug being installed.

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Findings

### [HIGH] FR-2 hidden-path allow-list permits `rm -rf` on credential dotfiles the exclusion list doesn't name

**Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

```bash
_re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
_re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'
```

**Description**: Before this change, the exclusion regex contained a bare `\.` alternative that (per the PR's own commit message and in-code comment at `head/.claude/hooks/safety/block-destructive-bash.sh:846-848`) matched the leading dot of *every* hidden path, so all `./.foo` arguments fell to `FR-2-AMBIGUOUS` (conservative block). This PR replaces that blanket exclusion with eight explicitly named, directory-bounded entries (`($|/)` — matches only the bare name or `name/…`) plus an unbounded `.env` alternative, and simultaneously adds a new ALLOW branch, `\./\.[A-Za-z0-9_-][^*]*`, that matches *any* other hidden path made of alnum/`_`/`-` characters.

The exclusion list only protects directories by name; it does not protect single-file dotfiles that commonly hold credentials and are not literally named `.git`/`.ssh`/`.aws`/`.kube`/`.gnupg`/`.docker`/`.config`/`.claude`/`.env*`. Because the boundary character class after each protected name is `($|/)`, near-miss names that merely start with a protected prefix (e.g. `.git-credentials`, `.dockercfg`) also fail to match the exclusion and fall through to the new hidden-dir ALLOW branch.

**Failure scenario (PoC)**: An agent (or a prompt-injected instruction reaching the agent) runs:
```bash
rm -rf ./.netrc
rm -rf ./.npmrc
rm -rf ./.pgpass
rm -rf ./.git-credentials
```
Trace each through the classification ladder at `head/.claude/hooks/safety/block-destructive-bash.sh:1003-1032`:
1. `_re_dotdot` (`.844`) — no match, no `..` segment.
2. `_re_block_list` (`.845`) — no match.
3. `_re_allow_exclude` (`.856`) — `./.netrc` does not start with any of `./`, `./*`, `./.`, `./..`, `.git`, `.ssh`, `.aws`, `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`, or `.env` followed by the required boundary — no match. Same for `.npmrc`, `.pgpass`; `.git-credentials` fails the `\.git($|/)` boundary because `-credentials` follows `git`, not `$` or `/`.
4. `_re_allow_list` (`.857`) — `./.netrc` matches `\./\.[A-Za-z0-9_-][^*]*` (`.` then `n` then `etrc`) — **ALLOWED**, the loop `continue`s past this arg with no block/ambiguous flag set.

Every one of these files is force-deleted with no hook interception, whereas before this PR any of them (like all hidden paths) would have hit `FR-2-AMBIGUOUS` and been refused. This is a direct weakening of a defense-in-depth guard whose explicit purpose (per the header doc at `head/.claude/hooks/safety/block-destructive-bash.sh:783`, and the PR's own stated goal) is to stop exactly this class of destructive, credential-adjacent deletion.

**Remediation**: Either (a) extend `_re_allow_exclude` with the additional single-file credential patterns actually seen in the wild (`\.netrc$`, `\.npmrc$`, `\.pgpass$`, `\.git-credentials$`, `\.pypirc$`, `\.htpasswd$`, shell history files, etc.), acknowledging this is an incomplete enumeration that will always lag new tools; or (b) invert the allow-list design for hidden paths so that instead of allow-listing an open-ended character class (`[A-Za-z0-9_-]`) for "any other hidden path," only a closed set of specifically vetted hidden directories the framework itself creates (`.loa`, `.cache`, `.run`, `.ck`, `.beads`) are allow-listed, and every other hidden path — file or directory — still falls to `FR-2-AMBIGUOUS` by default. Option (b) preserves the ergonomics fix this PR was written for (`./.loa/qmd/` etc.) without reopening the door for arbitrary hidden credential files.

**References**: CWE-732 (Incorrect Permission Assignment for Critical Resource), OWASP A01:2021 (Broken Access Control — here, a broken guard rather than a broken ACL).

---

### [MEDIUM] `find_local_source()` no longer verifies the discovered construct matches the requested slug

**Component**: `head/.claude/scripts/constructs-lib.sh:565-597`

```bash
find_local_source() {
    local slug="$1"
    ...
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
            echo "$path"
            return 0
        fi
    done
    return 1
}
```

**Description**: The removed helper `_local_source_matches_slug` (previously at this location, deleted by the diff) checked that either the directory's basename matched `construct-$slug`/`$slug`, or the `name`/`slug` field declared inside `construct.yaml`/`manifest.json` matched the requested slug (case-insensitively), before accepting a candidate path. `find_local_source` now accepts the **first** path in `search_paths` that merely contains a construct manifest file of some kind, with no check that it is the manifest for the slug being requested.

For the default search paths (`head/.claude/scripts/constructs-lib.sh:581-586`) this is low-risk because the slug is baked into the path itself (`construct-$slug`). But `search_paths` can instead come entirely from `constructs.local_source_paths` in `.loa.config.yaml` (`head/.claude/scripts/constructs-lib.sh:571-578`), which is a flat, slug-agnostic list of directories the user configures once for all constructs. In that mode, calling `find_local_source "pack-b"` when `local_source_paths` lists `~/dev/pack-a` before `~/dev/pack-b` (or before any other directory that happens to contain a leftover/unrelated `construct.yaml`) will silently return `~/dev/pack-a` as the "local source" for `pack-b`.

**Failure scenario**: A developer configures two local construct checkouts for convenience:
```yaml
constructs:
  local_source_paths:
    - ~/dev/experimental-fork
    - ~/dev/construct-payments
```
Any call to `find_local_source "payments"` (or any other slug) returns `~/dev/experimental-fork` first, as long as that directory has a `construct.yaml` — regardless of what it declares. Whatever consumes this path (install/symlink/update tooling downstream of this function, not present in this diff) then operates on code that was never verified to belong to the requested pack. If `~/dev/experimental-fork` is attacker-influenced (e.g. a shared machine, a compromised dependency checked out nearby, or a malicious pull of a sibling repo), this becomes a construct-substitution vector rather than a mere developer footgun.

**Remediation**: Restore the slug-verification step (basename match or declared-name match) before accepting a candidate path, or at minimum keep iterating `search_paths` and only accept a path whose contained manifest declares the requested slug, falling through to the next candidate otherwise — matching the previous behavior removed by this diff.

**References**: CWE-706 (Use of Incorrectly-Resolved Name or Reference); relevant given the stated NEVER-add-supply-chain-risk posture in this repo's own auditor guidance.

---

### [LOW] Stale header comment no longer reflects the FR-2 exclusion list

**Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:783-785`

```
# - The ALLOW list now EXCLUDES `./`, `./*`, `./.git`, `./.ssh`, `./.env`
#   (SKP-002 round-3 closure) — these were dangerous shapes that v1.0
#   incorrectly hit the `^\./` allow-prefix.
```

**Description**: This pre-existing comment (not touched by the diff) documents the exclusion list as it existed before this PR. It is now inaccurate: the exclusion set has grown to include `.aws`, `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`, and dot-root/dot-dot forms, and a new hidden-path ALLOW branch now exists that this comment doesn't mention at all. A future maintainer skimming this header for the ground truth of what's excluded will get a wrong and incomplete picture, which is exactly the kind of drift that produced the HIGH finding above.

**Remediation**: Update this comment block to reference the current named exclusion set and the new hidden-dir allow branch, or delete it in favor of the newer inline comment already added at `head/.claude/hooks/safety/block-destructive-bash.sh:846-855`.

**References**: N/A (documentation hygiene).

## Security Checklist Status

- [x] Reviewed full diff and all three touched files in `head/`
- [x] Traced every branch of the modified `rm -rf` classification ladder
- [x] Constructed concrete PoC command lines for the allow-list gap
- [x] Verified the symlink-manifest traversal change is a strict tightening, not a regression
- [ ] Could not verify downstream consumers of `find_local_source()` (not part of this diff/PR scope) — flagged as [ASSUMPTION] risk pending caller review

## Verdict

CHANGES_REQUIRED

The HIGH finding is a direct, easily reproduced weakening of an existing destructive-command safety hook and must be closed (or the allow-list scoped down per the remediation options above) before merge. The MEDIUM finding should be fixed in the same PR since it reverts an existing safety check with no replacement.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-22T00:00:00Z"} -->
