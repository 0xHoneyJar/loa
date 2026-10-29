# cycle-138 input — the follow-up beads left by cycle-137 and sprint-bug-283

Written 2026-10-29 by the lead as `/plan-and-analyze` context (operator: "proceed with the next cycle"). Fifteen open beads; none is a feature. All are hardening, test-coverage or portability items found by the cycle-137 review/audit/Bridgebuilder rounds. Severity labels come from the finding that filed each bead.

## Candidates, by priority

| Bead | Area | What | Origin | Suggested sprint |
|---|---|---|---|---|
| bd-j34zb | `profile-lib.sh` effective-config cache | apply the decisions-cache trust boundary (uid-owned, not group-writable `.run`; `-f && ! -L`; read through an fd) and `mktemp` + `mv -T` for the writer | Sprint 282 audit MED-001 (DISS-C-001/C-002) | 1 — security |
| bd-qyvju | `post-merge-orchestrator.sh` release POST / notify | bodies travel on jq argv (`--arg body`); above 131 072 bytes `execve` fails (E2BIG) — use `--rawfile` / stdin | sprint-bug-283 review r2 observation 4 | 1 — release path |
| bd-hyah6 | `loa-status.sh` `_an_audit_chain_summary` | report an absent chain file as a third state; never fold absence into "valid" | Sprint 282 audit LOW-001 (DISS-C-004) | 1 — security surface |
| bd-20bh1 | `zone-write-guard` | create `.run/perf-cache` under umask 077 so the D-5.3 tightening is a no-op on fresh mounts | Sprint 282 (A's observation; DEC-1126) | 1 |
| bd-yos4s | karpathy hook | gate `KARPATHY_CHECKPOINT_CMD` on a bats marker or WARN once outside bats | Sprint 282 audit LOW-003 (DISS-C-007) | 2 — hooks |
| bd-kdzc3 | karpathy hook | symlink guards on `TRAJ_DIR` and the per-day trajectory file before the append | Sprint 281 audit LOW-003 | 2 |
| bd-4sikh | `loa-kf-surface.sh` | cap the number of KF rows injected into the session context | Sprint 281 audit LOW-002 | 2 |
| bd-z6gxn | KF parsers `san()` | UTF-8-encoded C1 controls pass through; align with the jq `s` filter | Sprint 282 Task 2.1 (A) | 2 |
| bd-aceil | KF awk programs | verify under BWK awk / macOS BSD `cut`; decide the byte-cap contract on BSD hosts | Sprint 281 audit MED-001 (DEC-1123); BB #1309 R-001 | 2 — portability (needs a BWK build or a macOS host) |
| bd-7utms | `profile-lib.sh` `forbidden()` | descendant clause for a mapping-level floor key (no live floor entry today) | Sprint 282 audit LOW-002 (DISS-C-005) | 3 — tests/guards |
| bd-y5fy4 | `profile-lib.sh` `loa_knob` | presence metadata separate from the rendered value (retire the sentinel-string class) | Sprint 282 review obs 3; BB #1309 R-002 | 3 |
| bd-5v1oa | `perf-spawn-budget.bats` | a warm-cache (hit path) grimoire-index target beside the miss-path one | Sprint 282 review obs 1 | 3 |
| bd-rq6gk | `adversarial-review-companion.bats` CMP-55 | assert the reap was attempted; raise the sleeper margin | Sprint 282 Task 2.5 (C) | 3 |
| bd-3qed8 | `loa-decisions-surface.bats` `_path_without` | build the skip list before switching IFS; add a multi-tool case | Sprint 281 review obs 3; BB #1309 R002 | 3 |
| bd-0h7kq | `providers/__init__.py` | one lazily built dispatch mapping; `cli_adapter_types` from a static auth table | Sprint 281 review obs | 3 — refactor, lowest |

## Constraints the plan must carry forward

- Every change red-first; byte-identical old-vs-new output where output exists (mirror parity in REAL directories); `red-test-check.sh` per red commit (`--env-pass PYTHONUSERBASE` where python helpers need `rfc8785`).
- System Zone edits under the bounded marker with `checksums.json` and REPO-MAP regenerated; `check-loa.sh` green at every fix commit.
- Dissent budget ≤ 3 runs per sprint (the third is the audit's); Bridgebuilder ≤ 2 rounds; decisions as class-S rows via `dec-batch.sh` (summary ≤ 150 code points).
- Hot paths keep their spawn budgets (`perf-spawn-budget.bats`); hooks run per tool call — a refusal mistake in the profile-lib cache (bd-j34zb) silently drops the cache on every PostToolUse, so that task needs mirror parity for the karpathy hook across the config matrix.
- No release in this cycle unless the operator asks; the bugfix PR #1313 (rc.10 candidate prepared by the pipeline, not published) and cycle-138's merge would otherwise prepare rc.10/rc.11 — the operator decides when to publish or to promote rc → 2.0.0.

## Known failures relevant to the work

- KF-064 (publisher read-back; fixed by sprint-bug-283 — the POST side is bd-qyvju), KF-037 (claude-headless companion timeouts under host load), KF-034 (three `semver evidence` tests red on hosts with `tag.gpgsign`), KF-022 (beads sync split-brain), KF-005 (beads `--parent`).
