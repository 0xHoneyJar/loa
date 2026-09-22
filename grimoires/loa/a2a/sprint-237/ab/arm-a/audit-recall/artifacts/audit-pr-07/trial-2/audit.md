# Security Audit Report

**Audit type**: Ad-hoc PR audit (no sprint plan / beads DB / a2a directory present)
**Scope**: `head.diff` — 3 files touched:
- `.claude/hooks/safety/block-destructive-bash.sh`
- `.claude/scripts/constructs-lib.sh`
- `.claude/scripts/lib/symlink-manifest.sh`

**PR title**: "chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection"

## Executive Summary

This PR bundles three unrelated changes into one commit. Two of them are genuine
security regressions relative to the pre-PR behavior, and the third
(`symlink-manifest.sh`) is a safe simplification.

The headline change — relaxing `block-destructive-bash.sh`'s hidden-path exclusion
from "block every dotfile" to "block a named list, allow everything else" — is a
reasonable ergonomics fix for the stated incident (agents unable to `rm -rf
./.loa/qmd/`), but the named list is (a) matched case-sensitively, which silently
reverts to full exposure on any case-insensitive filesystem (default macOS APFS,
exFAT, NTFS), and (b) incomplete — well-known credential dotfiles such as
`.netrc`, `.npmrc`, and `.git-credentials` are not in the protected set and are
now allowed `rm -rf` targets, where before this PR *no* dotfile could be deleted
through this path. Both defects directly undermine the "NEVER edit `.claude`"
Three-Zone Model guarantee this same hook is chartered to enforce, and the
credential-directory protections this very diff claims to add.

The `constructs-lib.sh` change is a separate, undocumented regression: it deletes
the slug-verification step from `find_local_source()`, so the function now
returns the *first* configured local-source directory that merely contains a
`construct.yaml`/`manifest.json` — with no check that it corresponds to the
construct actually being requested. Combined with the fact that
`constructs.local_source_paths` is a static (non-templated) list read from the
state-zone `.loa.config.yaml`, this allows one local checkout to be silently
substituted for every other slug's install, which is a construct/dependency
confusion vector with code-execution impact.

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## High Priority Issues

### H-1: Case-sensitive protected-path list re-exposes `.claude`, `.git`, `.ssh`, `.env` on case-insensitive filesystems

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:856`
- **Description**: The new `_re_allow_exclude` regex enumerates the sensitive
  paths that must stay blocked from `rm -rf`:
  ```
  _re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
  ```
  Bash's `[[ =~ ]]` matching is case-sensitive by default (no `nocasematch`
  is set anywhere in this file). Before this PR, the exclude pattern's bare
  `\.` alternative matched *any* string starting with a dot, so case never
  mattered — every hidden path was conservatively blocked or ambiguous
  regardless of spelling. This PR replaces that catch-all with an exact,
  case-sensitive enumeration, and simultaneously introduces a new permissive
  branch, `_re_allow_list` at `head/.claude/hooks/safety/block-destructive-bash.sh:857`
  (`\./\.[A-Za-z0-9_-][^*]*`), that allows deletion of *any* hidden path not
  caught by the exclude list.
- **Impact**: On any case-insensitive-but-case-preserving filesystem (macOS
  APFS default, exFAT, NTFS/WSL), `.Claude`, `.CLAUDE`, `.Git`, `.SSH`,
  `.Env`, `.Aws`, `.Config`, etc. all resolve on-disk to the *same directory*
  as their lowercase counterparts, but none of them match the exclude
  regex. Such a path falls straight into the new `_re_allow_list` branch and
  is allowed straight through — meaning `rm -rf ./.Claude/` (or `./.Git/`,
  `./.Ssh/`, `./.Env`) is **not blocked**, silently deleting the System Zone,
  git history, SSH keys, or environment secrets on these platforms. This
  precisely defeats both the "NEVER edit `.claude`" Three-Zone Model
  guarantee this hook exists to enforce, and the credential-directory
  protections (`.ssh`, `.aws`, `.kube`, `.gnupg`, `.docker`) this same diff
  claims to add.
- **PoC**: On macOS (default APFS) or any WSL/NTFS checkout:
  ```bash
  rm -rf ./.Claude/          # or ./.CLAUDE/, ./.Git/, ./.Ssh/, ./.Env
  ```
  neither `_re_allow_exclude` (case-sensitive, no match) nor the block/
  ambiguous branches fire; the argument matches `_re_allow_list` and the
  command falls through to the "every arg matched the allow list → fall
  through" branch (`head/.claude/hooks/safety/block-destructive-bash.sh:1044`),
  i.e. **allowed**.
- **References**: CWE-178 (Improper Handling of Case Sensitivity), OWASP
  A01:2021 (Broken Access Control — the hook is the access-control layer
  here).
- **Remediation**: Add an explicit case-insensitive comparison for the
  protected-name segment before falling through to the new hidden-dir allow
  branch, e.g. lowercase the candidate segment (`tr '[:upper:]'
  '[:lower:]'`) and compare against the protected-name list, or set
  `shopt -s nocasematch` around just that comparison. Do not rely on the
  ERE alone for names that must be protected regardless of case.

### H-2: `find_local_source()` no longer verifies the returned directory matches the requested construct slug

- **Component**: `head/.claude/scripts/constructs-lib.sh:565-596` (function
  body); removed verification previously at
  `base/.claude/scripts/constructs-lib.sh:591-614` (`_local_source_matches_slug`).
- **Description**: The pre-PR function iterated `search_paths` and only
  accepted a candidate directory if its basename matched
  `construct-$slug`/`$slug`, or its declared `construct.yaml` `.name` /
  `manifest.json` `.slug`/`.name` matched the requested slug
  (`_local_source_matches_slug`, deleted in this diff). The post-PR version
  (`head/.claude/scripts/constructs-lib.sh:589-594`) accepts the *first*
  path in `search_paths` that merely exists and contains a
  `construct.yaml` or `manifest.json` — with no relationship to the
  requested `slug` at all:
  ```bash
  for path in "${search_paths[@]}"; do
      if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
          echo "$path"
          return 0
      fi
  done
  ```
  This is safe only for the *default* search paths (which are templated
  with `$slug`, e.g. `$HOME/Documents/GitHub/construct-$slug`), but
  `search_paths` can instead come entirely from the user/state-controlled
  `.constructs.local_source_paths` list in `.loa.config.yaml`
  (`head/.claude/scripts/constructs-lib.sh:568-580`), which is a flat list
  of directories with **no per-slug templating**.
- **Impact**: When `constructs.local_source_paths` is configured (a normal,
  documented workflow for developing/testing a local construct checkout),
  requesting *any* slug now resolves to whichever configured directory
  happens to exist and look like a construct first — regardless of whether
  it declares that slug. A stale or unrelated local checkout silently
  shadows the real construct for every future install, and because
  `.loa.config.yaml` lives in the read/write State Zone, an agent or
  compromised workflow step that can edit it can force *all* subsequent
  construct installs onto a single attacker-controlled local directory
  without any name-mismatch warning being emitted (the removed function was
  the only place that produced such a warning path). This is a construct/
  dependency-confusion vector with code-execution impact, since constructs
  are installed and presumably executed as trusted framework code.
- **PoC**: With `.loa.config.yaml`:
  ```yaml
  constructs:
    local_source_paths:
      - ~/dev/scratch-construct   # attacker/stale directory with a construct.yaml
  ```
  `find_local_source "totally-different-slug"` returns
  `~/dev/scratch-construct` even though its `construct.yaml` declares an
  unrelated name — pre-PR this returned 1 (not found) and no substitution
  occurred.
- **References**: CWE-706 (Use of Incorrectly-Resolved Name or Reference),
  supply-chain/dependency-confusion class.
- **Remediation**: Restore a slug-verification step before accepting a
  candidate path from `search_paths` (the deleted `_local_source_matches_slug`
  logic, or equivalent), or explicitly document/require that configured
  `local_source_paths` entries are slug-specific — but the code must not
  silently return a directory whose declared identity contradicts the
  requested slug. This removal also carries none of the explanatory
  rationale comments the other two changes in this diff have; there is no
  stated justification for dropping the check.

## Medium Priority Issues

### M-1: Protected-dotfile enumeration omits common credential files

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:856-857`
- **Description**: The new exclusion list only names `.git`, `.ssh`, `.aws`,
  `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`, and `.env*`. Other
  widely-used credential dotfiles that live directly in a repo/home root —
  `.netrc`, `.npmrc`, `.pypirc`, `.git-credentials`, `.pgpass` — are not on
  the list. Before this PR, the bare `\.` catch-all blocked deletion of
  *every* hidden path, so these files were incidentally protected; after
  this PR they fall into the new permissive `_re_allow_list` branch
  (`head/.claude/hooks/safety/block-destructive-bash.sh:857`) and can be
  removed by `rm -rf ./.netrc` etc. without triggering FR-2-BLOCK or
  FR-2-AMBIGUOUS.
- **Impact**: Loss (not disclosure) of credential files via an
  unconfirmed/un-blocked destructive command — lower severity than H-1
  because this is a narrowing of the *known* protected set rather than a
  bypass of an intended protection, but it is a direct, easily-fixed
  regression from the pre-PR "block all dotfiles" behavior.
- **Remediation**: Extend `_re_allow_exclude` (or add a second file-oriented
  exclusion) to cover `.netrc`, `.npmrc`, `.pypirc`, `.git-credentials`,
  `.pgpass`, and any other credential-bearing dotfiles the project wants
  guaranteed protection for, independent of the case-sensitivity fix in H-1.

## Positive / No Action Needed

- `head/.claude/scripts/lib/symlink-manifest.sh:255-262` — replacing the
  resolve-then-check-escape logic (`_normalize_rel_path` +
  parent-relative resolution) with a direct `_path_has_traversal` check on
  **both** `link` and `target` is a net-neutral-to-positive simplification.
  Any target string that resolves outside the repo root via `dirname(link)
  + target` must contain a literal `..` path segment (concatenating two
  strings free of `..` can never produce one), and `_path_has_traversal`
  already rejects any `..` segment in `target` directly
  (`head/.claude/scripts/lib/symlink-manifest.sh:258`) — so this is at
  least as strict as the removed logic, just simpler. It is stricter in one
  edge case (a `target` containing a harmless `../` that would have
  resolved back inside the tree is now rejected outright), which is a
  false-positive/usability regression, not a security one.

## Security Checklist Status

- [x] Input validation reviewed (rm-path classification, construct manifest
  symlink validation)
- [ ] Authorization/identity checks reviewed — **FAIL**: H-2 removes an
  identity check (slug match) with no replacement
- [x] Injection vectors reviewed (regex/glob based path matching, no
  shell-eval of untrusted data introduced)
- [ ] Defense-in-depth for destructive operations — **FAIL**: H-1, M-1
- [x] Path traversal handling reviewed (symlink-manifest.sh change verified
  equivalent-or-stronger)

## Verdict

**CHANGES_REQUIRED**

Two High findings (H-1 case-sensitivity bypass of the System-Zone/credential
protection list; H-2 removal of construct slug verification enabling
construct/dependency confusion) must be fixed before this PR merges. M-1
should be folded into the same fix pass since it touches the same regex.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"n/a","ts":"2026-09-22T00:00:00Z"} -->
