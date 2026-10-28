# Common rules for every cycle-137 Sprint 282 implementer (read first, then your own brief)

You are an Opus 5.5 implementer working in a linked git worktree of the loa repository (path given in your brief). You return PATCHES and a REPORT; the lead lands, reviews, audits and ships. You never commit, push, stash, rebase or tag. You never run anything with the live push configuration, never make live model or GitHub calls, never write under `.run/` of the MAIN checkout (`/home/merlin/Documents/thj/code/loa/.run`), never delete anything under `.claude/`, never touch credentials or `.env*`.

## Method (the loop's discipline — every change)
1. **Profile first**: `hyperfine -N -i --warmup 3 --runs 10 '<cmd>'` (hyperfine 2.0 JSON: `.results[0].measurements[].time_wall_clock.value`) and a `PS4='+' bash -x` trace counting external-tool lines (`jq|yq|awk|sed|tr|cut|grep|realpath|stat|date`). Record host (`hostname`), command line, run count, mean ± σ.
2. **Golden capture** of today's outputs on the live inputs AND on your fixture matrix BEFORE changing anything: stdout, stderr, exit code, every written file.
3. **One lever per commit** (your brief says how many commits). A behaviour change is a failure even when it is an improvement, unless your brief names it as intended and tested.
4. **Red-first**: the test patch comes first and must FAIL on the unchanged code for exactly its new cases (`bash .claude/scripts/red-test-check.sh --red <red-commit> -- npx --no-install bats <file>` is how the lead checks; you report which new test names fail before and pass after). Test-only tasks are told their substitute in their brief.
5. **Parity**: old-vs-new mirrors in REAL directories. Hooks and scripts resolve their libs via `$(dirname "${BASH_SOURCE[0]}")/../..` and `..` resolves PHYSICALLY: a symlinked directory escapes the mirror (you would compare new with new). Recipe: `mkdir -p "$M/x/y"`, copy the file under test and the libs it sources into real directories at the same relative depth, point PROJECT_ROOT/config env at fixture copies. Build an OLD mirror from `git show HEAD:<path>` and a NEW mirror from your working tree; run both over the live inputs and the fixture matrix; `cmp` stdout, stderr, rc and written files (normalise only what your brief names).
6. **Fast path with verbatim fallback** (passes 7, 9, 10, 11, 16, 18): the plain shape takes the new path; everything else runs the ORIGINAL code unchanged, so error text and exit codes stay byte-identical by construction.
7. **Tests**: `npx --no-install bats <file>` (never bare `bats`). Run the files your brief names; report counts.
8. **Portability**: bash 3.2 / BSD-friendly constructs where the surrounding file already is; no `readlink -f`, no raw `sha256sum` (use `sha256_portable` from `compat-lib.sh`), no swallowed jq (`tools/check-no-swallowed-jq.sh --quiet` must stay clean), no bare `sed -i` (use `sed_inplace`), POSIX awk only (mawk and busybox awk must run it; `gawk` is not installed here).
9. **Untrusted bodies** (KF text, decisions rows, config values) stay sanitised at surfacing; never widen what is done with them.
10. **zsh note**: the lead's shell is zsh; your commands run in bash — but if you write helper scripts, quote and word-split explicitly.

## Patch contract
Only the paths on your allowlist. A patch touching anything else is returned unlanded. You do not edit `CHANGELOG.md`, `.claude/checksums.json` or `grimoires/loa/REPO-MAP.md` — the lead regenerates manifests; you RETURN your CHANGELOG line(s) as text in the report.

## Deliverables (write them to disk; your final chat message may never reach the lead)
- `<worktree>/.cycle137/<task>-red.patch` — `git diff` of the test-only change (red), and `<worktree>/.cycle137/<task>-fix.patch` — `git diff` of the fix (the lead applies red then fix). For a test-only task: one patch.
- `<worktree>/.cycle137/REPORT.md` — per task: what changed and why; the measurement table (host, command, runs, old mean ± σ, new mean ± σ, spawn counts); the parity matrix (inputs × modes, all `cmp` identical, or the enumerated intended differences); the red-first evidence (test names failing before, passing after); bats counts per file; CHANGELOG line(s) as text; anything UNVERIFIED (say so plainly); the STOP reason if you stopped.
- `<worktree>/.cycle137/fixtures/` — your fixture files and the harness script that reproduces the parity run, so the lead can re-run it.

## STOP conditions (write the REPORT with the reason and stop; do not improvise around them)
- The change needs a file outside your allowlist.
- Parity cannot be made byte-identical except for differences your brief names as intended.
- A required test or the security suite cannot stay green without touching a protected function named in your brief.
- Two hours of wall time have passed (time-box; report what you have).
