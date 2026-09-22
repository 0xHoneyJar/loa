# Review: refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification

## Summary

This PR removes validation code from three security/reliability-sensitive scripts under the
banner of "simplification." Two of the three changes are real regressions, not simplifications:
the ledger-write guard removal reopens a previously-fixed data-corruption bug (explicitly marked
`SECURITY (HIGH-001)` in the code it deletes), and the symlink-target resolution "fix" actually
breaks the security check it's part of (`MED-004 FIX`) for every nested symlink the mount script
creates. The PR description does not mention either as an intentional risk tradeoff, which reads
as unreviewed collateral damage from a refactor rather than a deliberate decision.

## Changes Required

- **CRITICAL** (confidence: high) `head/.claude/scripts/ledger-lib.sh:379` (and identically at
  lines 418, 459, 511, 601, 822) — `_write_ledger "$ledger_content"` is called with no
  `|| return $LEDGER_ERROR` check, immediately followed by an unconditional `return $LEDGER_OK`
  (e.g. line 382 for `start_cycle`, line 419 for `update_cycle_field`, line 602 for
  `update_sprint_status`). If `_write_ledger` fails — lock timeout (line 158-161), temp-file write
  failure (line 173-178), or `mv` failure (line 182-187) — the caller now reports success anyway.
  Any code path that depends on the ledger write succeeding (cycle creation, sprint status
  transitions, cycle archival) will silently believe it worked while the ledger is left stale or
  the lock contended. This is a direct behavioral regression, not just a style cleanup — the
  removed `||` was the only thing propagating `_write_ledger`'s failure signal.

- **CRITICAL** (confidence: high) `head/.claude/scripts/ledger-lib.sh:146-169` — the deleted guard
  (base `.claude/scripts/ledger-lib.sh:152-156`, `"refusing to write empty or unparseable ledger
  content"`) protected against writing invalid content to `ledger.json`. It is not merely
  redundant: `jq` writes nothing to stdout on a parse/filter error, so any upstream `jq` failure
  (e.g. `update_sprint_status` at line 592-594/596-598 with a malformed `global_id`, or any other
  caller's `jq … "$ledger_path"` failing because the on-disk ledger is transiently invalid) now
  produces an empty `ledger_content`. Combined with the finding above, that empty string is piped
  straight through `_write_ledger` (line 169: `updated_content=$(echo "$content" | jq --arg ts …)`,
  which also produces empty output for empty/invalid input) and atomically **overwrites
  `ledger.json` with essentially empty content** (`echo "$updated_content" > "$tmp_file"` at line
  173 succeeds trivially on an empty string) — with the caller still reporting `$LEDGER_OK`. This
  guard is explicitly commented `SECURITY (HIGH-001)` two lines below where it was removed (line
  171 in head), i.e. it was added as a deliberate hardening fix for a known corruption scenario;
  removing it reintroduces that exact scenario with no replacement mitigation.

- **HIGH** (confidence: high) `head/.claude/scripts/mount-submodule.sh:370-390` — `validate_symlink_target` used to resolve a relative `target` against the directory containing the
  symlink itself (`resolve_base=$(cd "$(dirname "$source")" …)` in base, since a relative symlink
  target is resolved by the OS/filesystem relative to the symlink's own directory, not the
  process's cwd). The new version drops the `source` parameter entirely (also removed at line 371,
  and at the call site `mount-submodule.sh:414`) and resolves `target` directly against the
  current working directory instead. Every real caller passes a manifest-derived relative target
  for a symlink that lives in a subdirectory — e.g. `mount-submodule.sh:487`
  (`.claude/settings.local.json` → `../.loa/.claude/settings.local.json`) or the
  `MANIFEST_SKILL_SYMLINKS`/`MANIFEST_CMD_SYMLINKS` loops at lines 471-486, where `link_path` is
  nested under `.claude/skills/...` or `.claude/commands/...`. For any such entry, resolving the
  `../`-relative target against cwd (repo root) instead of the symlink's directory computes a
  path that doesn't exist on disk. That falls through to the `else` branch at
  `mount-submodule.sh:379-389`, and since the (wrongly-computed) parent directory almost never
  exists relative to cwd either, it hits `warn "Cannot resolve symlink target: $target"; return 0`
  at lines 386-388 — i.e. the validation is **silently skipped and the symlink is always allowed**
  for essentially every nested manifest entry, while `ln -sf` at line 418 still creates the
  (actually-fine) symlink using real relative-symlink semantics. The function whose entire purpose
  is "Security: Symlink target escapes repository bounds" (line 398) is a no-op for the very inputs
  it's meant to protect (`MED-004 FIX` comment at line 358-359 in the surrounding block). It won't
  break the mount itself, but it silently defeats the security check for the common case, and
  masks the "cannot resolve" path from ever surfacing a real escape attempt.

## Observations

- **MEDIUM** (confidence: medium) `head/.claude/scripts/classify-pr-type.sh:61-64` — the removed
  rule (base `classify-pr-type.sh:66-69`: `grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"`
  → `cycle`) classified release-merge titles (e.g. a merge from an `org/release/x.y.z` branch, or
  a title starting `Release:`/`Release(scope):`) as `cycle`. After this change such titles fall
  through to `other` (they don't start with `fix`), so `post-merge-orchestrator.sh` (per the
  header comment at `classify-pr-type.sh:26`, `cycle` triggers "CHANGELOG, GT, RTFM, Release run")
  would skip the full pipeline for a release-merge PR. Note the docstring's "Rules (in precedence
  order)" list at lines 27-34 never enumerated this rule even in the base version, so it's
  plausible it was genuinely dead/unused (e.g. no real PR titles ever matched it, or it was
  superseded by the `cycle-NNN` and label-based rules above it) — but the PR description doesn't
  say that, and there's no test evidence here confirming which is true. Worth a one-line
  justification in the PR body, or a regression test asserting a `release/` merge title still
  isn't silently misrouted.
- **LOW** (confidence: medium) `head/.claude/scripts/mount-submodule.sh:377-378, 384` — the `cd`
  calls lost the `2>/dev/null` present on the equivalent base-version `cd` calls
  (base:381,388,393). Low risk since the `[[ -e ]]`/`[[ -d ]]` guards make the directory very
  likely to exist when reached, but any transient failure (permissions, race) would now leak a raw
  `bash: cd: ...` line to stderr instead of failing through the intended warning path.

## Verdict

The `ledger-lib.sh` and `mount-submodule.sh` changes both silently reintroduce previously-fixed
failure modes (labeled `SECURITY (HIGH-001)` and `MED-004 FIX` in the surrounding code) rather
than simplifying dead code. Request changes.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":2,"high":1,"medium":1,"low":1},"excluded":0,"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
