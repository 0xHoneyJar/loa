# Security Audit — chore(hooks,constructs): allow bounded hidden dirs, first-match local sources, strict traversal rejection

**Scope**: `head.diff` (3 files) — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/constructs-lib.sh`, `.claude/scripts/lib/symlink-manifest.sh`.
**Method**: full-file review of `base/` and `head/` for all three touched files, forward/backward trace of every changed validation branch. No sprint plan, beads DB, or `grimoires/loa/a2a/` present — audited as a standalone PR per `AUDIT-INSTRUCTIONS.md`.

## Summary

The PR intentionally narrows an over-broad `rm -rf` hidden-directory block into a named exclusion list (good direction — the prior bare `\.` alternative blocked every hidden path, per the incident cited in the PR's own inline comment), tightens path-traversal rejection in `symlink-manifest.sh` (also a genuine hardening — see below), but silently drops the only content-integrity check in `constructs-lib.sh`'s `find_local_source`, and the new named exclusion list itself has a boundary-matching gap that undercuts its own stated guarantee for several of the entries.

## Findings

### HIGH — `find_local_source` no longer verifies the returned path matches the requested construct slug

`head/.claude/scripts/constructs-lib.sh:565-597`

```
589    for path in "${search_paths[@]}"; do
590        if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
591            echo "$path"
592            return 0
593        fi
594    done
```

The base version gated this same loop on `_local_source_matches_slug "$path" "$slug"` (`base/.claude/scripts/constructs-lib.sh:591`), which checked either the directory basename (`construct-$slug` / `$slug`) or the slug/name declared inside `construct.yaml`/`manifest.json`. That entire function is deleted in `head/` (compare `base/.claude/scripts/constructs-lib.sh:601-621`, absent from `head/`) and the loop now returns the **first existing directory that merely contains a construct manifest file**, regardless of which construct it actually declares.

**Failure scenario**: `search_paths` is populated in full from `.loa.config.yaml`'s `constructs.local_source_paths` when that key is set (`head/.claude/scripts/constructs-lib.sh:571-578`), and those entries are used verbatim — unlike the default fallback list (lines 581-586), they are **not** templated with `$slug` at all. A user (or a stale/shared config) that lists a single generic local checkout, e.g. `local_source_paths: ["~/dev/my-construct-checkout"]`, will have that exact directory returned as the "local source" for **every** slug requested against `find_local_source`, as long as it contains any `construct.yaml`/`manifest.json` — even one declaring a completely different pack name. The caller (not in this diff's scope, but implied by the function's contract: "Find local source clone for a construct pack") presumably uses the returned path to install/symlink files for the requested slug; this is a silent construct-substitution bug — pack "alpha" silently gets installed/symlinked from whatever pack actually lives at that path (e.g. pack "beta"), with no error, warning, or name-mismatch signal.

Relevant standard: [CWE-706: Use of Incorrectly-Resolved Name or Reference](https://cwe.mitre.org/data/definitions/706.html) (also touches [CWE-829: Inclusion of Functionality from Untrusted Control Sphere](https://cwe.mitre.org/data/definitions/829.html) if the substituted pack's files are subsequently symlinked into `.claude/` per `symlink-manifest.sh`'s validated-boundary path).

**Remediation**: restore a slug/name-match check before accepting a `search_paths` hit — at minimum, compare the manifest's declared name/slug against the requested `$slug` and skip (continue the loop) rather than return on mismatch, so a later, correctly-named entry in `search_paths` is still found.

### MEDIUM — Named hidden-dir exclusion list in the `rm -rf` hook uses inconsistent boundary anchoring, allowing near-miss names of protected credential/config directories to bypass the block

`head/.claude/hooks/safety/block-destructive-bash.sh:856-857, 1039, 1041`

```
856  _re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
857  _re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'
```

The inline comment above this (lines 846-855) states the intent plainly: "credential/config dirs ('.ssh' '.aws' '.kube' '.gnupg' '.docker' '.config'), the System Zone ('.claude'), and '.env*' files stay blocked." The block/ambiguous messages repeat this guarantee verbatim: `"protected: .git .ssh .aws .kube .gnupg .docker .config .claude .env*"` (line 1041) and `"protected dot-dirs like .git/.ssh/.env stay blocked"` (line 1039).

The regex does not deliver on this for most of the named entries. Every alternative except `\.env` requires an exact boundary — `($|/)` — immediately after the literal name, e.g. `\.claude($|/)` matches `./.claude` or `./.claude/...` only. Any hidden directory that merely *starts with* one of these names but isn't an exact match — `./.ssh-backup/`, `./.aws-old/`, `./.dockerignore-cache/`, `./.config-legacy/`, `./.claude2/`, `./.gitmodules-cache/` — fails `_re_allow_exclude`, then matches the new `_re_allow_list` branch `\./\.[A-Za-z0-9_-][^*]*` (added on line 857) and is **allowed** straight through the hook with no block, no ambiguous warning, nothing. `\.env`, by contrast, has no trailing boundary at all in this same list, so `./.environment` or `./.envrc` *are* still caught (an inconsistency in the other direction — over-blocking, which is safe but shows the anchoring was not applied uniformly).

**Failure scenario**: an agent (or a supplied instruction) runs `rm -rf ./.ssh-old/` or `rm -rf ./.aws-backup/` intending to delete what looks like a stale backup directory of credentials; the hook's own documented purpose — blocking recursive deletes of credential/config directories — silently does not apply, and the command executes unblocked. This directly contradicts the fence's stated guarantee and the emitted message text on the very same lines.

Relevant standard: [CWE-697: Incorrect Comparison](https://cwe.mitre.org/data/definitions/697.html) (boundary/prefix comparison defect), [CWE-863: Incorrect Authorization](https://cwe.mitre.org/data/definitions/863.html) (fence intent vs. enforced behavior mismatch).

**Remediation**: normalize anchoring — either require the exact-name boundary for every protected entry (accept the current behavior as intentional and drop the message wording that implies broader coverage) or use a prefix match consistently in one direction (e.g., `\.ssh[^/]*($|/)`) if the goal is genuinely to protect anything that looks credential-adjacent. Whichever direction is chosen, the block message text should match what the regex actually enforces.

## Observations (not tallied)

- `symlink-manifest.sh`'s traversal-rejection change (`head/.claude/scripts/lib/symlink-manifest.sh:258-262`) is a net hardening, not a weakening: it replaces a resolve-and-compare check that only rejected targets whose *normalized* result escaped the repo root with a blanket rejection of any literal `..` segment in either `link` or `target`. This is strictly more conservative than the removed `_normalize_rel_path`/escape-check pair (`base/.claude/scripts/lib/symlink-manifest.sh:240-262`), and the `.claude/`-boundary check on `link` (line 253) and the absolute-path rejection (line 265) are both unchanged. No issue found here.
- The `_re_dotdot` check in `block-destructive-bash.sh` runs before the new exclude/allow branches for every rm operand (line 844, tested at lines 991/1010), so the new hidden-dir allowance does not reopen any `..`-based escape — confirmed by re-reading the full per-arg ladder (lines 889-1036), not just the diff hunk.
- The regex-anchoring gap in the MEDIUM finding above is inherently prefix-based (regex, not path-component matching), so the same class of gap likely exists for any future addition to this exclusion list unless a shared boundary-matching helper is introduced.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 0 |

## Verdict

Sprint/PR audit gate: **CHANGES_REQUIRED** — one HIGH finding (construct-source integrity regression in `find_local_source`) and one MEDIUM finding (protected-directory bypass in the `rm -rf` hook) must be addressed before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":0},"ts":"2026-09-22T01:52:03Z"} -->
