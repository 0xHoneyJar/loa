# Security Audit — PR: "chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection"

## Scope

PR touches three files:

- `.claude/hooks/safety/block-destructive-bash.sh` — replaces the blanket "block every hidden path" exclusion in the `rm -rf` guard with a named exclusion list, so bounded hidden subdirectories (e.g. `./.loa/`, `./.cache/`) can be deleted while a named set of sensitive dot-dirs stays blocked.
- `.claude/scripts/constructs-lib.sh` — `find_local_source()` no longer verifies that a candidate local directory's name/declared manifest slug matches the requested pack slug; it now returns the first existing candidate with a `construct.yaml`/`manifest.json`.
- `.claude/scripts/lib/symlink-manifest.sh` — replaces path-normalization + resolved-escape detection with a direct string check for a `..` segment in either the link or the target.

No sprint plan, beads database, or `grimoires/loa/a2a/` directory is present; this audit is scoped to `head.diff` / `head/` / `base/` only, per `AUDIT-INSTRUCTIONS.md`.

## Findings

### 1. [CRITICAL] `rm -rf` guard's new hidden-dir exclusion list is case-sensitive — trivially bypassed on case-insensitive filesystems to delete `.git`, `.ssh`, `.env*`, `.claude` (System Zone), and other protected dirs

**Location:** `head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

```bash
_re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
_re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'
```

`_re_allow_exclude` (the "stays blocked" list) matches the protected names (`.git`, `.ssh`, `.aws`, `.kube`, `.gnupg`, `.docker`, `.config`, `.claude`, `.env`) with **case-sensitive** literals — `[[ ... =~ ... ]]` in bash never folds case unless `nocasematch` is set, and this file sets no such option. `_re_allow_list`'s new hidden-dir branch, `\./\.[A-Za-z0-9_-][^*]*`, accepts **any** case in `[A-Za-z0-9_-]`, including uppercase.

Consequence: an argument like `./.Git/`, `./.CLAUDE/`, `./.SSH/`, `./.Env`, `./.Config/`, `./.AWS/`, `./.Kube/`, `./.Gnupg/`, or `./.Docker/` fails every alternative in `_re_allow_exclude` (case mismatch) and falls straight into `_re_allow_list`'s new hidden-dir branch, which matches unconditionally — so `rm -rf ./.Git/` (or any of the others) is **allowed to execute**, not blocked or flagged ambiguous.

On the default filesystem for macOS (APFS, case-insensitive by default) and on Windows, `./.Git/` and `./.git/` refer to the **same directory on disk**. So this is not merely "a differently-named directory slips through" — it is a direct path to destroying the actual `.git` history, the actual `.ssh` keys, the actual `.env` secrets, or the actual `.claude/` System Zone (whose protection this exact hook exists to enforce, per `CLAUDE.loa.md`'s Three-Zone Model and `zone-system.md`), using nothing more than a capitalization difference an agent or user could type by accident, let alone deliberately.

**Regression, not pre-existing behavior:** the prior exclusion regex on `base/.claude/hooks/safety/block-destructive-bash.sh` was `_re_allow_exclude='^\./($|\*|\.|\.git$|\.git/|\.ssh$|\.ssh/|\.env)'`. Its bare `\.` alternative unconditionally matched **any** path of the form `./.*` — i.e. every hidden path, regardless of case, was excluded (and thus fell to conservative-block/ambiguous). That blanket exclusion is exactly what this PR intentionally removes (per its own inline comment at `block-destructive-bash.sh:846-855`, citing the 2026-07-10 incident where the blanket rule wrongly caught `./.loa/qmd/`). The fix correctly narrows the false-positive block for benign hidden dirs, but the replacement named list omits case-insensitivity, so it reopens exactly the destructive-delete path the guard is designed to prevent, for every name on the protected list.

**Failure scenario:** an agent (or a hook rewriting/normalizing a path) runs `rm -rf ./.Claude/` on a stock macOS checkout. The guard evaluates this as an allowed hidden-dir deletion (no block, no prompt) and bash then executes it; APFS resolves `.Claude` to the same inode as `.claude`, deleting the System Zone outright. The identical scenario applies to `.Git`, `.SSH`, `.Env`, `.Aws`, `.Kube`, `.Gnupg`, `.Docker`, `.Config`.

**Remediation:** add case-insensitive matching for the exclusion alternatives only (e.g. `shopt -s nocasematch` scoped around just the exclusion test, or an explicit `[Gg][Ii][Tt]`-style character-class expansion for each protected name), or lowercase the candidate argument before testing against `_re_allow_exclude` (matching the case-folding the old `_local_source_matches_slug` used elsewhere in this same PR, ironically, before it was deleted). Add a regression test asserting `rm -rf ./.GIT/`, `./.Claude/`, `./.SSH/`, `./.ENV`, etc. are blocked/ambiguous, not allowed.

**CWE:** [CWE-178: Improper Handling of Case Sensitivity](https://cwe.mitre.org/data/definitions/178.html); this is also a direct security-control bypass — [CWE-693: Protection Mechanism Failure](https://cwe.mitre.org/data/definitions/693.html).

---

### 2. [MEDIUM] `find_local_source()` no longer verifies the returned local directory matches the requested construct slug — construct/pack confusion

**Location:** `head/.claude/scripts/constructs-lib.sh:565-597` (removed validation previously at `base/.claude/scripts/constructs-lib.sh:591-616`, the deleted `_local_source_matches_slug` function)

```bash
for path in "${search_paths[@]}"; do
    if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
        echo "$path"
        return 0
    fi
done
```

Before this PR, each candidate directory was additionally required to pass `_local_source_matches_slug`: its basename had to equal `construct-<slug>`/`<slug>` (case-insensitively), or its `construct.yaml`/`manifest.json` had to declare a `name`/`slug` matching the requested slug. The PR deletes that check entirely, so `find_local_source` now returns the **first directory in `search_paths` that merely exists and contains a manifest file** — regardless of whether it is the construct actually being requested.

`search_paths` is populated in one of two ways (`constructs-lib.sh:568-587`):
- from `.loa.config.yaml`'s `constructs.local_source_paths[]`, a flat, slug-independent list the operator maintains by hand (e.g. while developing multiple local construct packs at once); or
- a slug-templated default (`$HOME/Documents/GitHub/construct-$slug`, etc.), which is self-correct even without the slug check.

The default-path branch is unaffected in practice (the slug is baked into the path), but the config-driven branch is not: if an operator has configured `local_source_paths` for local development of several packs, calling `find_local_source "pack-b"` will silently return `pack-a`'s directory whenever `pack-a` sorts earlier in the list and has a valid manifest — with no warning that the returned source doesn't match what was asked for. Whatever consumes this path (installing, symlinking, or otherwise trusting it as the named construct — not present in this diff's scope) then operates on the wrong, unintended local code under the identity of the requested slug.

**Failure scenario:** a developer has `local_source_paths: ["~/dev/construct-experimental", "~/dev/construct-prod-tool"]` configured while iterating locally. A call for `find_local_source "prod-tool"` returns `~/dev/construct-experimental` instead (first match, valid manifest, wrong pack) with no error — silently substituting one local, possibly half-finished or deliberately-crafted, construct pack for another.

**Remediation:** restore a slug-match check (it need not be the exact removed function, but the "first that exists" behavior described in the PR title should still be scoped to "first that exists **and matches the requested slug**"), or at minimum emit a warning to stderr when a returned path's declared name/slug disagrees with the requested slug so a human can catch the mismatch.

**CWE:** [CWE-706: Use of Incorrectly-Resolved Name or Reference](https://cwe.mitre.org/data/definitions/706.html).

## Observations

- `head/.claude/scripts/lib/symlink-manifest.sh:234-268` — replacing the `_normalize_rel_path` + resolved-path-escape check with a direct `_path_has_traversal` test on the raw `link`/`target` strings is sound: since the removed logic only ever flagged an escape when the *normalized* relative path began with `..`, and a relative path can only ever leave its base through a literal `..` path segment, testing the raw target string for any `..` segment (which the new code also now does on `target`, not just `link`, closing a real gap in the old code) is an equivalent-or-stronger check. No finding here; this part of the diff is a net hardening (both the link *and* the target are now traversal-checked, where before only the link was checked by `_path_has_traversal`, and the target only by the separate resolved-path branch that this PR removes).

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 0 |
| Medium | 1 |
| Low | 0 |

## Verdict

**CHANGES_REQUIRED** — Finding 1 is a confirmed, low-complexity bypass of the exact destructive-delete guard this PR modifies, capable of deleting `.git`, `.ssh`, `.env*`, and the `.claude` System Zone on default macOS/Windows filesystems. This must be fixed (case-insensitive matching on the exclusion list) before merge. Finding 2 should be addressed in the same change or a fast-follow, since it silently defeats the purpose of a source-identity check with no replacement.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":1,"low":0},"ts":"2026-09-22T00:00:00Z"} -->
