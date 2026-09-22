# Security Audit: chore(hooks,constructs) — bounded hidden dirs, first-match local sources, strict traversal rejection

**Scope**: `head.diff` touching 3 files — `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/constructs-lib.sh`, `.claude/scripts/lib/symlink-manifest.sh`. No sprint plan / beads / implementation report available; audited directly against `base/` → `head/` diff per AUDIT-INSTRUCTIONS.md.

## Findings

### CRITICAL — Case-sensitive exclusion list lets `rm -rf` delete protected dot-directories (`.claude`, `.git`, `.ssh`, `.env`, …) via alternate case

**Location**: `head/.claude/hooks/safety/block-destructive-bash.sh:856-857`

```
856:  _re_allow_exclude='^\./($|\*|\.$|\.\.($|/)|\.git($|/)|\.ssh($|/)|\.aws($|/)|\.kube($|/)|\.gnupg($|/)|\.docker($|/)|\.config($|/)|\.claude($|/)|\.env)'
857:  _re_allow_list='^(\./[^/*.][^*]*|\./\.[A-Za-z0-9_-][^*]*|node_modules$|node_modules/|dist$|dist/|build$|build/|target$|target/|\.next$|\.next/|/tmp/.+|out$|out/|coverage$|coverage/)'
```

Before this PR, `_re_allow_exclude` contained a bare `\.` alternative that matched **any** hidden path (`./.anything`) unconditionally, so every dot-directory was routed to `FR-2-AMBIGUOUS` (blocked) regardless of name or case. This PR replaces that blanket rule with an enumerated, name-specific exclusion list, and simultaneously adds a new hidden-directory branch to `_re_allow_list` (`\./\.[A-Za-z0-9_-][^*]*`) that explicitly *allows* `rm -rf` on any other hidden directory.

Both regexes are matched with plain `[[ "$unquoted" =~ $_re_allow_exclude ]]` (`head/.claude/hooks/safety/block-destructive-bash.sh:1023`) with no `shopt -s nocasematch` anywhere in the file (confirmed via grep — no occurrences), so matching is **case-sensitive**. The new allow-list character class `[A-Za-z0-9_-]` explicitly accepts uppercase letters, but the exclusion list only spells out lowercase names (`\.git`, `\.ssh`, `\.aws`, `\.kube`, `\.gnupg`, `\.docker`, `\.config`, `\.claude`, `\.env`).

Consequence: `rm -rf ./.CLAUDE/`, `rm -rf ./.Git/`, `rm -rf ./.SSH/`, `rm -rf ./.ENV`, `rm -rf ./.Config/`, etc. do **not** match `_re_allow_exclude` (wrong case) but **do** match the new hidden-dir `_re_allow_list` branch (character class is case-insensitive by construction) — the loop at `head/.claude/hooks/safety/block-destructive-bash.sh:1027-1029` hits `continue` for these tokens, so `any_block`/`any_ambiguous` are never set and the command falls through to `exit 0` (allowed) at line 1047.

This is not a theoretical filesystem quirk: macOS' default APFS/HFS+ volumes are case-insensitive-but-case-preserving, meaning `./.CLAUDE/` and `./.claude/` refer to the **exact same directory on disk**. On the platform most Claude Code users run on, `rm -rf ./.CLAUDE/` executed by an agent (e.g. from a prompt-injected instruction, or a typo/paraphrase in generated shell) is silently permitted by this hook and physically deletes the System Zone (`.claude/`) that `.claude/rules/zone-system.md` and this very hook are designed to protect — along with `.git`, `.ssh`, `.env`, `.aws`, `.kube`, `.gnupg`, `.docker`, `.config` under the same bypass. Even on case-sensitive Linux filesystems, a directory or symlink deliberately created with alternate case reproduces the same bypass.

**Failure scenario**: an agent (or any bash command an agent is induced to run, including via prompt injection from untrusted file/tool content) executes `rm -rf ./.CLAUDE/` on a macOS checkout. The hook's exclude regex fails to match (case mismatch), the new hidden-dir allow branch matches, and the command executes unblocked — deleting the actual `.claude/` System Zone (hooks, skills, safety fences) or, with `./.SSH/` / `./.ENV`, deleting/exfiltration-adjacent-enabling credential material.

**Remediation**: anchor the exclusion match case-insensitively (`shopt -s nocasematch` around the match, or lowercase `$unquoted` before comparison against `_re_allow_exclude` — but NOT against `_re_dotdot`/other patterns that don't need it), or fold case explicitly into the alternation (`\.[Cc][Ll][Aa][Uu][Dd][Ee]…`). Prefer lowercasing the comparison copy once, since the intent (per the PR's own comment block, `head/.claude/hooks/safety/block-destructive-bash.sh:846-855`) is clearly to keep these specific sensitive roots blocked regardless of how they're spelled in the command.

---

### HIGH — `find_local_source` no longer verifies the returned path actually belongs to the requested construct slug

**Location**: `head/.claude/scripts/constructs-lib.sh:565-597` (function `find_local_source`); removed validator was `_local_source_matches_slug` (`base/.claude/scripts/constructs-lib.sh:601-622`)

```
589:    for path in "${search_paths[@]}"; do
590:        if [[ -d "$path" && ( -f "$path/construct.yaml" || -f "$path/manifest.json" ) ]]; then
591:            echo "$path"
592:            return 0
593:        fi
594:    done
```

Before this PR, once a candidate directory in `search_paths` was found to exist and contain a `construct.yaml`/`manifest.json`, `_local_source_matches_slug` additionally confirmed the candidate actually *was* the requested pack — either by directory-name convention (`construct-<slug>` or `<slug>`, case-folded) or by reading the declared `name`/`slug` field out of the manifest and comparing it (case-folded) to the requested slug. This PR deletes that entire check (`base/.claude/scripts/constructs-lib.sh:601-622`) and the diff removes it with no replacement — `find_local_source` now returns the **first** candidate directory that merely contains *some* construct manifest, without checking it is the manifest for `$slug`.

For the default search paths (`head/.claude/scripts/constructs-lib.sh:581-586`) the path names are slug-templated (`$HOME/Documents/GitHub/construct-$slug`, etc.), so identity is usually implied structurally. But when `.loa.config.yaml` supplies `constructs.local_source_paths` (`head/.claude/scripts/constructs-lib.sh:571-578`), those entries are read verbatim from user config and are **not** required to be slug-templated — the surrounding code has no mechanism enforcing that. A config listing shared parent directories (e.g. a local checkout root, a scratch/staging directory, or a directory used across multiple construct packs) will now cause `find_local_source("foo")` to silently return whatever pack happens to occupy the first matching path in that list, even if its `construct.yaml`/`manifest.json` declares itself as an entirely different slug (`bar`).

Since constructs are installed by symlinking/copying their content into `.claude/` (the framework's executable-code System Zone — see `.claude/rules/zone-system.md`), a caller trusting `find_local_source`'s return value to be "the local source for the requested slug" can now be handed the wrong pack's code path and install/link it under the requested slug's identity without any name-mismatch warning — an identity-confusion vector that a compromised, mislabeled, or merely misordered local directory can exploit to substitute unintended (or attacker-authored) code into a construct install. The PR description's framing ("returns the first existing local source path") is exactly this behavior change, applied without any compensating check.

**Failure scenario**: `.loa.config.yaml` (or a future default) lists two or more non-slug-templated local roots; one of them is a stale/experimental/attacker-planted clone whose `construct.yaml` declares a different `name`. A request for the legitimate slug now resolves to that mismatched directory's code, which is then symlinked into the System Zone under the legitimate slug's name — with no error, warning, or log line, since the removed function was the only place this was checked and its `REJECTED`/mismatch path had no replacement logging.

**Remediation**: restore an equivalent identity check (the deleted `_local_source_matches_slug` logic, or a simplified inline equivalent) before accepting a candidate path — either by continuing the loop past non-matching candidates when a manifest declares an inconsistent name/slug, or at minimum emitting a loud warning so a mismatch isn't silently accepted.

---

## Observation (no action needed)

`head/.claude/scripts/lib/symlink-manifest.sh:258-262` replaces the old `_normalize_rel_path`-based "does the resolved target escape repo root" check with a direct `_path_has_traversal` test against **both** `link` and `target` (previously only `link` was checked this way; `target` only went through the resolve-based check). Verified this is not a regression: `_path_has_traversal` rejects any string containing a literal `..` path segment (`^\.\.$`, `^\.\./`, `/\.\./`, `/\.\.$`), and since a relative `target` can only ever traverse *above* the symlink's parent directory by containing at least one literal `..` segment, the new direct check is at least as strict as the removed resolve-then-compare logic (and stricter for interior `..` segments that would previously have resolved harmlessly, e.g. `a/../b`, which are now rejected outright rather than normalized and allowed). No exploitable gap found here.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 1 |
| Medium | 0 |
| Low | 0 |

## Verdict

**CHANGES_REQUIRED** — the case-sensitivity gap in the new hidden-directory allow-list defeats the exact protection (System Zone, `.git`, `.ssh`, `.env`, cloud-credential directories) this hook exists to enforce, and is trivially reachable on the platform's most common case-insensitive filesystem configuration. The `find_local_source` identity-check removal is a second, independent regression that should be fixed in the same pass. Neither the `block-destructive-bash.sh` nor the `constructs-lib.sh` change should merge as-is; the `symlink-manifest.sh` change is sound.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":0,"low":0},"sprint_id":"pr-07","ts":"2026-09-22T00:00:00Z"} -->
