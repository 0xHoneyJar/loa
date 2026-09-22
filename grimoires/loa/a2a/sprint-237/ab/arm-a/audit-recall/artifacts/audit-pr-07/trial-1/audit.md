# Security Audit Report

**Audit type**: Codebase (PR) audit
**Scope**: `head.diff` — 3 files: `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/constructs-lib.sh`, `.claude/scripts/lib/symlink-manifest.sh`
**PR**: "chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection"

## Executive Summary

This PR bundles three unrelated changes to System Zone safety infrastructure. Two of the three (the `rm -rf` hidden-directory allowlist narrowing, and the symlink-manifest traversal check) are defensible, net-neutral-or-safer simplifications. The third — removing slug verification from `find_local_source()` in `constructs-lib.sh` — silently drops the only check that a "local source" resolved for construct pack `X` actually **is** pack `X`. When a user configures more than one entry under `constructs.local_source_paths` in `.loa.config.yaml` (the documented, supported way to point at local dev checkouts), the function now returns the **first** configured path that merely contains a `construct.yaml`/`manifest.json` — regardless of which slug was requested. This is a construct-identity-confusion bug with real security consequence: it can cause the wrong local package's code to be installed/mounted and trusted under a different pack's name, and it is worsened by the fact that whichever entry happens to be first in the list "wins" for every subsequent request, irrespective of the caller's slug. This is the PR's headline change ("returns the first existing local source path") and is CRITICAL/HIGH depending on downstream trust placed in the return value.

## Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## High Priority Issues

### H-1: `find_local_source()` drops slug verification — construct identity confusion

- **Component**: `head/.claude/scripts/constructs-lib.sh:565-596` (function `find_local_source`), specifically the loop at `head/.claude/scripts/constructs-lib.sh:589-593`
- **Description**: The base version validated every candidate directory with `_local_source_matches_slug()` (base `.claude/scripts/constructs-lib.sh:591-594`, helper at `base/.claude/scripts/constructs-lib.sh:56-77`) before returning it — matching the directory's basename (`construct-$slug` / `$slug`) or the `name`/`slug` field declared inside `construct.yaml`/`manifest.json` against the requested slug. This PR deletes that helper and the call site, so the function now does:
  ```
  for path in "${search_paths[@]}"; do
      if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
          echo "$path"
          return 0
      fi
  done
  ```
  (`head/.claude/scripts/constructs-lib.sh:589-593`). It returns the **first directory in `search_paths` that has any construct/manifest file at all**, with no check that its declared identity matches `$slug`.
- **Why this matters**: `search_paths` is populated in one of two ways (`head/.claude/scripts/constructs-lib.sh:569-583`):
  1. **Default paths** (no config) — these embed `$slug` in the path itself (`"$HOME/Documents/GitHub/construct-$slug"`, etc.), so the missing check is largely inert here.
  2. **Configured paths** — `constructs.local_source_paths[]` from `.loa.config.yaml` (`head/.claude/scripts/constructs-lib.sh:571`). This is exactly the case the removed validation existed to guard: these entries are **not** slug-scoped. Any repo that maintains local checkouts of more than one construct pack (a normal development workflow — e.g. `local_source_paths: ["~/dev/pack-a", "~/dev/pack-b"]`) will now have `find_local_source("pack-b")` silently return `~/dev/pack-a` if it exists and contains a `construct.yaml`, because it's first in the list and satisfies the (now content-blind) existence check.
- **Impact**: Whatever consumer calls `find_local_source(slug)` to decide "install/mount this local checkout instead of the registry copy" will install **the wrong pack's code under the requested pack's name**. Since constructs get symlinked into the System Zone (`.claude/`) per `symlink-manifest.sh` in this same PR, this is not a cosmetic mixup — it is arbitrary local code being trusted and wired into the framework's `.claude/` tree under an identity the user did not ask for. A single stale or unrelated directory sitting first in `local_source_paths` (or an attacker who can add one entry to that config file) hijacks *every* subsequent local-source resolution, for *every* slug, until it's fixed or removed.
- **Proof of concept**:
  ```yaml
  # .loa.config.yaml
  constructs:
    local_source_paths:
      - ~/dev/some-unrelated-pack   # has a construct.yaml declaring name: some-unrelated-pack
      - ~/dev/the-pack-i-actually-want
  ```
  `find_local_source("the-pack-i-actually-want")` returns `~/dev/some-unrelated-pack` — silently.
- **Remediation**: Restore slug verification before returning a candidate path. At minimum, re-add the equivalent of the deleted `_local_source_matches_slug` check inside the loop:
  ```bash
  for path in "${search_paths[@]}"; do
      if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
          if _local_source_matches_slug "$path" "$slug"; then
              echo "$path"
              return 0
          fi
      fi
  done
  ```
  If the intent (per the PR title, "first-match local sources") is deliberately to relax matching, that decision needs to be scoped to defaults only, and the configured-path case must keep an explicit per-entry slug/name check — "first path that exists" is not an acceptable substitute for "first path that IS this construct" when the list is user-configured and multi-entry.
- **References**: CWE-706 (Use of Incorrectly-Resolved Name or Reference), CWE-829 (Inclusion of Functionality from Untrusted Control Sphere, in the sense of trusting unverified local content under a false identity).

## Medium Priority Issues

### M-1: Narrowed `rm -rf` hidden-directory exclusion list omits common credential files

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:800`
- **Description**: The new `_re_allow_exclude` protects `.git`, `.ssh`, `.aws`, `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`, and `.env*`, and now permits `rm -rf` on any other `./.hidden-dir` shape via the new `_re_allow_list` branch `\./\.[A-Za-z0-9_-][^*]*` (`head/.claude/hooks/safety/block-destructive-bash.sh:801`). Credential-bearing files that are common in developer home/repo trees but not directories under the protected names — e.g. `.netrc`, `.npmrc`, `.pgpass`, `.git-credentials`, `.pypirc` — are not covered by the exclusion, so `rm -rf ./.netrc` is now allowed where before the (overly broad) bare `\.` exclusion blocked it.
- **Impact**: This is a destructive-command guard rail for an autonomous agent, not an access-control boundary — a permitted `rm -rf` only deletes, it does not exfiltrate. Still, silently widening what a fully autonomous run is allowed to delete to include unlisted credential files reduces the guard's defense-in-depth value versus a broader set. This is a deliberate, documented trade-off of the PR (fixing the "blocks every hidden path" bug), but the specific named set should be reviewed for complete credential-file coverage, not just credential *directories*.
- **Remediation**: Consider adding an explicit-file (not just directory) exclusion branch for common single-file credential stores (`.netrc`, `.npmrc`, `.pgpass`, `.git-credentials`, `.pypirc`, `.docker/config.json` is already covered via `.docker($|/)`), or document why file-level credentials are considered out of scope for this hook.
- **References**: CWE-732 (Incorrect Permission Assignment), OWASP A05:2021 Security Misconfiguration.

## Low Priority Issues

### L-1: Comment/behavior drift risk in `_re_allow_exclude` `.git` sub-match

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:800`
- **Description**: `\.git($|/)` only matches an exact `./.git` or `./.git/...`; a directory literally named `./.gitbackup` or `./.git-old` is not excluded and falls through to the new hidden-dir allow branch (`\./\.[A-Za-z0-9_-][^*]*`), permitting `rm -rf ./.git-old`. This is consistent with how every other named exclusion in this list behaves (anchored to the exact name), so it is not a bypass of `.git` itself, but it's worth flagging since a careless reader could assume "anything git-ish" is protected.
- **Impact**: Low — no actual `.git` metadata is exposed to deletion; only similarly-named directories that are not actually version-control state.
- **Remediation**: None required; documenting for reviewer awareness only.

## What Was Reviewed And Found Acceptable

- **`head/.claude/hooks/safety/block-destructive-bash.sh:790-801`** (rm -rf hidden-dir allowlist rewrite): Verified the new `_re_allow_exclude`/`_re_allow_list` pair against traversal (`./..`, `./...`, `./..git`) and confirmed no path containing a real `..` segment can reach the allow branch — `_re_dotdot` is still evaluated first in the per-arg ladder (`head/.claude/hooks/safety/block-destructive-bash.sh:947-949`), and the new allow-list's second alternative structurally requires the character immediately after the leading `.` to be alphanumeric/`_`/`-`, which a literal `.` (as in `..`) can never satisfy. No bypass found.
- **`head/.claude/scripts/lib/symlink-manifest.sh:255-260`**: The replacement of the `_normalize_rel_path`-based "does this resolve outside the repo root" check with a blanket `_path_has_traversal` test on both `link` and `target` is strictly more conservative, not less: any target that can actually escape a `.claude/`-rooted link parent must contain a literal `..` path segment, and the new check rejects all `..` segments outright (including some in-repo-safe ones the old normalizer would have allowed). This trades a false-rejection risk for simpler code with no traversal bypass — acceptable per the framework's "lazy means efficient, not careless" simplicity guidance, and it does not weaken security.

## Verdict

**CHANGES_REQUIRED**

H-1 (loss of slug verification in `find_local_source`) must be fixed before this PR merges — it reintroduces a construct-identity-confusion vector for any repo using multi-entry `constructs.local_source_paths`. M-1 should be addressed or explicitly accepted as a documented trade-off before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"n/a","ts":"2026-09-22T00:00:00Z"} -->
