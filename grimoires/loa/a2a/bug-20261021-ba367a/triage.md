# Bug Triage: `archive-cycle.sh` archives the wrong cycle by default, deletes git-tracked archives by default, and never updates the live ledger

## Metadata
- **schema_version**: 1
- **bug_id**: 20261021-ba367a
- **classification**: logic_bug (wrong default derivation, destructive default, missing documented state write)
- **severity**: high
- **eligibility_score**: 3
- **eligibility_reasoning**: Reproducible steps with exact output (+2): `bash .claude/scripts/archive-cycle.sh --dry-run` on main `16e0b48b` prints `Would create archive at: …/grimoires/loa/archive/cycle-92` / `Cycle id: (not found in ledger; using legacy fallback)` and `Would delete 10 old archive(s) (retention=5, keep-newest-N)` naming two git-tracked directories (reproduced 2026-10-21T00:40Z). Incident record (+1): the cycle-131 archive on 2026-10-20 had to be run as `--cycle 131 --retention 50` to avoid both faults (NOTES 2026-10-20T12:28:29Z; memory "archive-cycle.sh default --cycle = ledger entry count (92) → legacy fallback"), and issue #1263 (open since 2026-09-15) reports the ledger never being updated, reproduced across downstream mounts. No disqualifier: no new endpoint, UI, schema or configuration key (the retention default changes behaviour under the existing key).
- **test_type**: unit
- **risk_level**: medium
- **created**: 2026-10-21T00:40:00Z

## Reproduction
### Steps
1. On main `16e0b48b` (ledger: 92 cycles, `active_cycle: null`, newest `cycle-131-honest-measurement` archived), run `bash .claude/scripts/archive-cycle.sh --dry-run`.
2. Run `bash .claude/scripts/archive-cycle.sh --cycle 131 --retention 5 --dry-run`.
3. `git ls-files grimoires/loa/archive | cut -d/ -f4 | sort -u` — note `2026-02-25-organizational-memory-sovereignty`, `2026-02-26-cycle-042-vision-activation`, `cycle-131-honest-measurement` are tracked.
4. In a scratch ledger with `active_cycle: "cycle-005-x"` and that cycle `status: active` with every sprint `completed`, run `archive-cycle.sh --cycle 5 --retention 0` (not dry-run) and inspect `grimoires/loa/ledger.json`.

### Expected Behavior
- Step 1: the default `--cycle` is the ledger's active cycle, else the newest cycle (131 → `archive/cycle-131-honest-measurement`); no legacy fallback on a modern ledger.
- Steps 1–2: nothing git-tracked is ever deleted; with no `--retention` and no `compound_learning.archive.retention_cycles` key the script keeps every archive (`retention 0` semantics); a pruning run skips tracked directories with a WARN naming them.
- Step 4: after a real archive the live ledger shows that cycle `status: "archived"`, an `archived` timestamp and `archive_path`, and `active_cycle: null` (the contract in `.claude/commands/archive-cycle.md` § Ledger Changes); `--dry-run` changes nothing.

### Actual Behavior
- Step 1 (observed 2026-10-21T00:40Z): `[DRY-RUN] Would create archive at: /home/merlin/Documents/thj/code/loa/grimoires/loa/archive/cycle-92` / `[DRY-RUN] Cycle id: (not found in ledger; using legacy fallback)` / `[DRY-RUN] Artifact source: …/grimoires/loa` — `get_current_cycle` returns `jq '.cycles | length'` (`archive-cycle.sh:131-138`), the count of cycles, not a cycle number; cycle ids were renumbered/zero-padded long ago so the count (92) names no cycle.
- Steps 1–2: `[DRY-RUN] Would delete 10 old archive(s) (retention=5, keep-newest-N):` listing `…/archive/2026-02-25-organizational-memory-sovereignty` and `…/archive/2026-02-26-cycle-042-vision-activation` (both tracked) among eight untracked local archives; `RETENTION=5` is the hard default (`:26`) and the yaml default (`:73`), `cleanup_old_archives` sorts by mtime and `rm -rf`s without consulting git (`:231-299`).
- Step 4: the live ledger is untouched; `create_archive` copies `ledger.json` into the archive and returns (`:140-225`); `ledger-lib.sh archive_cycle` (`:811-895`) performs the documented mutation but is never called (two divergent implementations, issue #1263).

### Environment
Linux 6.16, bash 5, jq 1.6, yq v4; repository `0xHoneyJar/loa` main `16e0b48b`, branch `fix/cycle-132-bugs`; `.loa.config.yaml` has no `compound_learning.archive` key (`yq '.compound_learning.archive'` → null).

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/archive-cycle.sh` | 131-138 | high | `get_current_cycle` returns `.cycles \| length`, not the active or newest cycle's number |
| `.claude/scripts/archive-cycle.sh` | 26, 66-76 | high | `RETENTION=5` default; `load_config` falls back to 5 when the yaml key is absent |
| `.claude/scripts/archive-cycle.sh` | 231-299 | high | `cleanup_old_archives` deletes by mtime with `rm -rf`, never checks `git ls-files` |
| `.claude/scripts/archive-cycle.sh` | 140-225 | high | `create_archive` never writes the ledger mutation documented in `archive-cycle.md:121-150` |
| `.claude/scripts/ledger-lib.sh` | 811-895 | medium | `archive_cycle` holds the correct ledger mutation (lock, `_write_ledger`) but a different archive layout; its mutation step is the one to reuse |
| `.claude/commands/archive-cycle.md` | 121-150 | medium | the documented ledger contract the script must meet |
| `tests/unit/archive-cycle-retention.bats` | 84-140 | low | pins `--retention N` semantics on untracked scratch dirs — must keep passing |
| `tests/unit/archive-cycle-per-subdir.bats` | 108-180 | low | pins per-cycle-subdir resolution with explicit `--cycle` — must keep passing |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/archive-cycle-retention.bats` | `--retention 5/50/0` deletion sets on 10 untracked scratch archives (dry-run) |
| `tests/unit/archive-cycle-per-subdir.bats` | artifact-root resolution for cycles 097/103/104 with explicit `--cycle` |
| `tests/unit/post-merge-archive-gate.bats` | the post-merge orchestrator's own ledger archive gate (separate code path) |
| (none) | default `--cycle` derivation, tracked-archive protection, live-ledger mutation |

### Test Target
New `tests/unit/archive-cycle-default-and-ledger.bats`, failing first, on a scratch git repo with a modern ledger (zero-padded ids, `cycle_folder` entries):
- ACL-1 no `--cycle`, `active_cycle` set → the dry run names the active cycle's archive path (fails today: `cycle-<count>` legacy fallback).
- ACL-2 no `--cycle`, `active_cycle: null` → the newest cycle by number (fails today).
- ACL-3 no `--retention`, no yaml key, 10 archives → "Nothing to delete" (fails today: deletes 5).
- ACL-4 `--retention 2` with 10 archives of which 3 are git-tracked → the dry run lists the tracked ones as kept with a WARN and deletes only untracked ones; the real run leaves every tracked directory in place (fails today).
- ACL-5 real archive of an active cycle whose sprints are complete → live ledger: `status: archived`, `archived` RFC 3339, `archive_path`, `active_cycle: null`; the ledger copy inside the archive is the pre-archive ledger (fails today).
- ACL-6 `--dry-run` leaves the ledger byte-identical (passes today; pins the fix).
- ACL-7 an active cycle with an incomplete sprint → the archive is refused (exit 1, nothing written) unless the operator passes `--force` (new flag, documented in the header); matches the `ledger-lib.sh archive_cycle` gate.

### Constraints
- No new configuration key: the yaml key `compound_learning.archive.retention_cycles` keeps its meaning; an absent key now means keep-all (0), and `--retention N` on the CLI still wins.
- Tracked content is never deleted by this script: a directory with any `git ls-files` entry is skipped with a WARN (`tracked archive kept: <path>; prune it with git`); outside a git work tree the previous mtime rule stands.
- Ledger writes go through `ledger-lib.sh` primitives (`_lock_ledger_transaction`, `_write_ledger`) — never a raw `jq > ledger.json`; the mutation matches `archive-cycle.md` § Ledger Changes field for field; `--dry-run` never writes.
- Existing exit codes and flags keep their meaning; `--cycle N` explicit continues to override everything; bash 3.2-safe; `bash -n`; `shellcheck`-clean where the file already is.
- System Zone edit under `/bug` (framework self-development): `.claude/scripts/archive-cycle.sh`, its header, `.claude/commands/archive-cycle.md`, `.claude/checksums.json` and `grimoires/loa/REPO-MAP.md` regeneration.

## Fix Strategy
Derive the default cycle from the ledger the way every other tool does: `active_cycle`'s numeric part when set, else the highest cycle number among `.cycles[].id`, else (no ledger) 1. Make the retention default keep-all (0) when neither the CLI nor the yaml names a value, and teach `cleanup_old_archives` to skip any directory that holds a tracked file (`git -C "$ARCHIVE_DIR" ls-files --error-unmatch -- "$dir" >/dev/null 2>&1`), printing the skipped paths in dry-run and real runs. After a successful (non-dry-run) archive, mutate the live ledger through `ledger-lib.sh` (source it; lock; jq sets `status: archived`, `archived`, `archive_path` on the cycle entry and `active_cycle: null` when that cycle was active; `_write_ledger`), refusing when the cycle has an incomplete sprint unless `--force`. Update the header usage, `archive-cycle.md`, and add the bats file; regenerate `.claude/checksums.json` and the repo map.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/archive-cycle.sh` | fix | `get_current_cycle` → active cycle number, else max cycle number, else 1 | jq only; numeric output; `_resolve_cycle_id` unchanged |
| `.claude/scripts/archive-cycle.sh` | fix | `RETENTION` default 0 when neither CLI nor yaml sets it | `--retention N` still wins; yaml key unchanged |
| `.claude/scripts/archive-cycle.sh` | add | tracked-directory skip in `cleanup_old_archives` | `git ls-files` check per candidate; WARN names the path; dry-run lists kept dirs |
| `.claude/scripts/archive-cycle.sh` | add | ledger mutation after `create_archive` (+ `--force` flag, completeness gate) | through `ledger-lib.sh` lock + `_write_ledger`; never under `--dry-run` |
| `.claude/commands/archive-cycle.md` | fix | document default cycle, keep-all default, tracked protection, `--force` | contract section stays authoritative |
| `tests/unit/archive-cycle-default-and-ledger.bats` | add | ACL-1 … ACL-7 | scratch git repo + ledger fixture; no live files touched |
