# Copy-Set Un-Gitignore Decision — options A/B/C

**Status:** Decision doc — awaiting operator sign-off. No code changes in this doc; nothing here un-gitignores anything or alters consumer git behavior.
**Cycle:** cycle-118 follow-up (bead `bd-copyset-ungitignore-decision-i1hb`, child of the closed epic `bd-c117-se-orvg`).
**Source:** KF-021 (`grimoires/loa/known-failures.md`) names this as an open follow-up; cycle-117 item G (PR #1177, commit `2fa79061`) fixed the *detection* half of KF-021 but left the *passive-signal* half (this decision) unresolved.

## The gap this doc resolves

The #842 copy set (`.claude/hooks`, `.claude/settings.json`) is content that is **copied, not symlinked**, into every submodule-mode consumer — copied because macOS hook executors can't traverse `..` symlinks (comment at `.claude/scripts/lib/symlink-manifest.sh:37-42`). `mount-submodule.sh:update_gitignore_for_submodule` conflates the copy-set with the true symlink set into one `symlink_entries[]` array (lines 812-824, header comment at line 836 reads "Symlinks to .loa/ submodule — recreated on mount") and gitignores both. True symlinks have zero independent content, so gitignoring them is correct. The copy-set entries carry independent byte content and DO drift — but because they're gitignored, drift produces **zero `git status`/CI-diff signal** in any consumer repo.

Cycle-117 item G already fixed the companion bug: `--check-symlinks` (`check_symlinks_subcommand`, `mount-submodule.sh:1097-1122`) now does real content-diff detection via `cmp -s`/`diff -rq` plus a `jq -S` structural diff of `settings.json`'s `permissions.allow`/`deny` (`_refresh_copy_entry`, lines 881-919), and no longer dies early under `set -e` before reaching the copy-set check. That detection is real and exits non-zero on `COPY-DRIFT`/`COPY-STALE`/`COPY-MISSING`. **What's still missing is that nothing invokes it automatically** — it is 100% opt-in per-invocation (`/update-loa`, or `--check-symlinks` run by hand). `check-symlinks` appears in zero `.yml`/`.yaml` files fleet-side (grep-verified) and `.claude/commands/update-loa.md`'s existing Submodule Mode section (lines 158-176) has no CI-automation guidance. This is exactly KF-021's named root cause: "operators bump the `.loa` gitlink by hand ... and never invoke `update_submodule` at all."

## Option A — un-gitignore the copy set fleet-wide

Remove `.claude/hooks` and `.claude/settings.json` from `symlink_entries[]` (`mount-submodule.sh:812-824`) so ordinary `git status` / CI-diff surfaces drift automatically in every consumer, with no opt-in step required.

**Tradeoffs:**
- Architecturally clean — draws the git-tracking boundary exactly at the existing copy-vs-symlink split already encoded in `MANIFEST_COPY_DIRS`/`MANIFEST_COPY_FILES` vs `MANIFEST_DIR_SYMLINKS`/`MANIFEST_FILE_SYMLINKS` (`symlink-manifest.sh:43-65`).
- **One-way, fleet-wide git-tracking migration.** Every already-mounted consumer needs a one-time add-commit (32 files under `.claude/hooks` + a several-hundred-line `settings.json` newly tracked). Reverting later means re-gitignoring plus `git rm --cached` across every consumer — a second churn event, not a rollback.
- **`refresh_copy_set(apply=true)` does a blind `rm -rf` + `cp -R`/`cp` with no merge** (`mount-submodule.sh:922-930). Once tracked, this produces a git-dirty tree on **every legitimate framework bump** that touches a hook or `settings.json` — not just on drift. `settings.json` alone changed twice in one cycle per #1045 history, so this is common, not rare.
- That git-dirty diff is signal-shaped noise for the common case: it only discriminates "drift" from "intended update" if operators diligently review and commit every bump's diff. A repo that already skips `--reconcile`/`/update-loa` (the exact discipline gap that caused KF-021) will just as easily skip reviewing/committing the resulting diff — Option A doesn't fix the underlying discipline gap, it just relocates where the neglect becomes visible (and even then, only to someone who's looking).
- Does not distinguish "matches the current pin" from "stale/hand-edited" — a git-tracked-file diff shows *that* the file differs from the last commit, not whether it matches the submodule's live pinned content. Comparing against the wrong reference (an old commit vs. the current pin) can hide exactly the drift KF-021 cares about.

## Option B — optional CI `--check-symlinks` step (RECOMMENDED)

Ship a documented, copy-pasteable CI step that runs `mount-submodule.sh --check-symlinks` on a schedule or on push, exit-code gated. No fleet-wide git-tracking change. Fully additive and fully reversible (delete the workflow step to remove it).

**Tradeoffs:**
- Zero-churn to adopt: a 4-8 line GitHub Actions step, no migration commit, no change to any consumer's existing gitignore or copy-set behavior.
- **Ref-aware**, which is strictly better precision than Option A's tracked-file diff: `--check-symlinks` always diffs live content against the submodule's *currently pinned* tag (post item-G content-diff logic), so it distinguishes "matches current pin" from "stale" — something a plain `git diff` against an arbitrary prior commit cannot do.
- Slots directly into the exit-code contract item G already hardened (`check_symlinks_subcommand` returns non-zero on any `COPY-DRIFT`/`COPY-STALE`/`COPY-MISSING`, confirmed at `mount-submodule.sh:1097-1122`) — no new detection logic needed, only a caller.
- **Opt-in, same as today** — a consumer that never wires the CI step in gets no more signal than before. This is a real limitation shared with the status quo, just cheaper to adopt than Option A's migration (a doc snippet vs. a fleet-wide commit).
- Does not retroactively fix already-drifted repos (neither does Option A) — each consumer still needs to run `update-loa.sh`/`--reconcile` once to resync.

## Option C — status quo (decline both)

Rely on operators remembering to run `/update-loa` or `--check-symlinks` manually. This is the current state and is what let KF-021 go undetected for up to ~85 releases in some fleet repos (per the cycle-117 fleet audit). Listed for completeness; not recommended — it leaves KF-021's root cause fully unaddressed.

## Recommendation: **Option B**

Ship the optional CI-check snippet now (see `.claude/commands/update-loa.md`'s "CI Drift Detection (optional)" subsection, added alongside this doc). Decline Option A for now — the fleet-wide git-tracking migration's churn-on-every-legitimate-bump property makes it a worse signal-to-noise tradeoff than it first appears, and it's a one-way move while Option B is fully reversible. Record this decision explicitly (this doc + the KF-021 link) so the gap stops being a silently-dangling TODO. Revisit Option A only if CI-check adoption stays low across the fleet after a reasonable trial period.

This doc does not itself change any consumer's git behavior — it is the artifact an operator reads to make the actual go/no-go call. The un-gitignore change (Option A) stays declined pending explicit operator sign-off.

## Open questions carried forward (not blocking this doc)

- Whether the CI-check snippet should eventually be auto-scaffolded (extending `scaffold_post_merge_workflow` to ship a workflow file into consumers automatically) rather than staying copy-paste-only documentation. Auto-scaffolding is itself a System-Zone behavior change needing its own cycle-level review — a separate, smaller follow-up bead once the doc-only version is validated, not part of this decision.
- Whether `update-loa.sh`'s `update_submodule()`/`verify_copyset_gate` already emits a machine-readable summary suitable for a CI log, or whether the CI step needs to parse `--check-symlinks`'s warn/log lines directly. Not required to ship the snippet in this doc (the snippet relies only on the exit code), but relevant if the snippet is later extended to produce a structured CI annotation.

## References

- `grimoires/loa/known-failures.md` KF-021 (this doc is linked from there)
- `.claude/scripts/mount-submodule.sh`: `update_gitignore_for_submodule` (804-851), `_refresh_copy_entry` (881-919), `check_symlinks_subcommand` (1097-1122)
- `.claude/scripts/lib/symlink-manifest.sh`: `MANIFEST_COPY_DIRS`/`MANIFEST_COPY_FILES` vs `MANIFEST_DIR_SYMLINKS`/`MANIFEST_FILE_SYMLINKS` (43-65)
- Cycle-117 item G: PR #1177, commit `2fa79061` (content-drift detection + `set -e` fix + `update_submodule` hard gate)
- Bead: `bd-copyset-ungitignore-decision-i1hb`
