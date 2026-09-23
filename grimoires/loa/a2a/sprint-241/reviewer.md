# Implementation Report — Sprint 1: Fence precision (cycle-125, global sprint 241)

**Cycle:** cycle-125 friction-floor · **PRD:** `grimoires/loa/prd.md` FR-1 · **SDD:** `grimoires/loa/sdd.md` §1.2 D-1.1–D-1.7 · **Plan:** `grimoires/loa/sprint.md` Sprint 1
**Implementer:** Fable 5.1 lead (`/run sprint-plan`, run-20260923-282c32ce, unattended per `grimoires/loa/a2a/prompts/cycle-125-friction-floor-2026-09-23.md`) · **Date:** 2026-09-23 · **Epic:** bd-c061 (tasks bd-stvh, bd-ic5v, bd-la6c, bd-d901, bd-evsy, bd-ygzz, bd-z9jw)

## Summary

Fleet usage mining (`grimoires/loa/reports/usage-mining-2026-09-23.md` F1) showed the destructive-command fence blocking benign commands at a rate that made agents route around it. This sprint turns the observed false positives into a committed, scrubbed corpus that replays through the hook, then relaxes four classes on positively established predicates only. The corpus went from 14/46 benign passing to 46/46 with every dangerous row (24 seeded, 32 after the twins added this sprint) still blocked, the existing 216 fence cases stay green, and the hook runtime over the corpus fell rather than rose. Nothing in the catastrophic list, the hidden-path rule, the `..` guard, or the remote-payload behaviour changed.

Assumptions (Karpathy rule 1), recorded as design and as tests: a relaxation is safe only when the hook can *prove* the operand is disposable from the command text plus local, offline state; the hook's own working directory is not evidence (a project checked out under `/tmp` must keep `rm -rf src` blocked — the corpus caught exactly this regression mid-sprint, row D32); network access does not belong in a fail-open hook, so the merged-PR probe lives in the sanctioned helper; a SQL statement without a sink is text, not a query; `git restore` was never fenced, so the D-1.5 wording "checkout/restore" resolves to `git checkout --` only.

## Changes

| File | Change |
|---|---|
| `.claude/hooks/safety/block-destructive-bash.sh:45-70` | header: the precision pass and the accepted residuals (remote payloads, SQL through a script file, substitution as a `cd` target, `$PWD` never consulted) |
| `:238-241` | grep-family carrier scrub (`grep|rg|ag|ack … 'quoted'`): a quoted search term is not a command (D-1.7 carrier class) |
| `:625-659` | D-1.4 `_fr11_all_merged()`: every named branch must exist, match `^[A-Za-z0-9][A-Za-z0-9._/-]*$`, and be an ancestor of `origin/main`, `main`, `origin/master` or `master`; offline, no `gh`; the FR-1.1 message names `git-branch-prune.sh` |
| `:729-760` | D-1.5 `_fr13_all_generated()`: every `git checkout --` operand must be under `dist|build|out|coverage|_generated|__generated__|generated`, a lockfile / `.tsbuildinfo`, or `linguist-generated` per `git check-attr`; `..` segments refuse |
| `:788-800` and the P8/P9/P10 conditions | D-1.3 `_sql_runner`: DROP / TRUNCATE / DELETE-FROM fire only when a SQL runner (`psql`, `mysql`, `sqlite3`, `prisma`, `flyway`, … 30 names) or an inline interpreter program (`python -c`, `node -e`, `python3 -`) is in the command |
| `:1193` | `_re_allow_list` gains `/var/tmp/.+` and `/private/tmp/.+` |
| `:1213-1330` | D-1.1 helpers: `_fr2_temp_root_re` / `_fr2_temp_path_re` (a `cd` target may be the root; an `rm` operand must be strictly below it), `_fr2_vocab_re` (last-segment cache/build vocabulary), `_fr2_plain_relative()` (no globs, `$`, `~`, spaces, `.`/`..` segments; hidden middle segments flagged), `_fr2_var_value()` (a name bound exactly once, voided by `eval`/`read`/`declare`/`local`/`unset`/`source`/`printf -v`/`for NAME in`/`${NAME:=`), `_fr2_value_allowed()` (strict `$(mktemp -d …)`, temp paths, `$TMPDIR` only with a real temp `TMPDIR` and no inline `TMPDIR=`, once-bound variables one level deep, never HOME/TMPDIR/PWD/OLDPWD), `_fr2_scratch_cwd()` (last statement-initial `cd` before the segment; `$PWD` deliberately not consulted), `_fr2_extra_allow()` |
| `:1486-1494` | per-operand: temp paths pass before the catastrophic list (which owns the `/var/` prefix); the four allowances run after the existing allow/exclude ladder and before the ambiguous fallback |
| `:1525` | FR-2-AMBIGUOUS message lists the accepted forms |
| `.claude/scripts/git-branch-prune.sh` (new, 121 lines) | `[--dry-run] [--base <ref>] [--json]`; deletes branches that are ancestors of the base, whose upstream is `[gone]`, or that have a merged PR (`timeout 5 gh pr list --state merged --head <name>`; skipped when `gh` is absent or `LOA_FENCE_NO_NETWORK=1`; any probe failure keeps the branch); never the current branch, the base, `main`, `master`; prints the pre-delete SHA and the `git branch <name> <sha>` restore command; exit 0 / 1 nothing to do / 2 usage |
| `tests/fixtures/fence-corpus/corpus.jsonl` (new) | 81 rows: 46 benign (B01–B46), 32 dangerous (D01–D32), 3 residual (R01–R03); fields `id, cmd, expect, rule, why, cwd, env`; paths and names neutralised |
| `tests/fixtures/fence-corpus/run-corpus.sh` (new) | replays each row through the hook in a throwaway work dir (`repo` / `scratch` cwd per row, `TMPDIR` per row), prints mismatches and `benign P/T dangerous B/T residual R/T runtime_ms N`; `--json` |
| `tests/fixtures/fence-corpus/baseline.json` (new) | pre-fix measurement: benign 14/46, dangerous 24/24, runtime 4061 ms |
| `tests/unit/block-destructive-bash.bats` (+49 cases, Group Z) | 4 corpus gates (dangerous 100 %, benign ≥ 80 %, lint: no `://`, IPs, `user@host`, key shapes, public TLDs; runtime ≤ 1.5× baseline) and 45 named cases: one per D-1.1 class (vocabulary, scratch cwd, temp roots, `$TMPDIR`, mktemp variables) with its twins, D-1.3 sink twins, D-1.4 fixture-repo merged/unmerged/metachar/non-repo, D-1.5 generated/attribute/hand-written/`..` |
| `tests/unit/git-branch-prune.bats` (new, 13 cases) | fixture repo with bare origin; merged, squash-merged (stub `gh`), gone-upstream, unmerged, `--dry-run`, `LOA_FENCE_NO_NETWORK`, failing probe, `--json`, `--base`, exit 1 / 2, non-repo, and the fence allowing the helper's invocation shape |
| `CHANGELOG.md` `[Unreleased]` | one entry |
| `grimoires/loa/REPO-MAP.md` (+checksum), `.claude/checksums.json` | regenerated (`repo-map-gen.sh --validate`: consistent; checksum regen `--check`: 3258 tracked, 0 drift) |

Not changed: any other hook file; `.claude/hooks/settings.hooks.json`; the catastrophic list `_re_block_list`; `_re_dotdot`; `emit_block` and the audit row; `log-redactor.sh`.

## Test-first record

- Task 1.1 ran the corpus red against the unmodified hook: `benign 14/46 dangerous 24/24 residual 0/3 runtime_ms 4061` (recorded in `baseline.json`). The bats gate "benign rows pass at or above 80 %" failed at that point (30 %).
- Mid-sprint regression the corpus caught: after the first `_fr2_scratch_cwd` draft (which fell back to `[[ "$PWD" =~ temp-root ]]`), rows D07 `rm -rf src` and D19 `rm -rf grimoires` flipped to ALLOWED because the replay harness runs the hook under a `mktemp -d` cwd — precisely the "project under /tmp" case Flatline SKP-002 warned about. The `$PWD` fallback was removed; only a textual statement-initial `cd <temp>` establishes scratch. Row D32 (`rm -rf src` with `cwd: tmp`) and the named case "the hook's own cwd under /tmp is not scratch" pin it.
- B21 `rm -rf /var/tmp/loa-cache-probe` stayed blocked because `_re_block_list` owns the `/var/` prefix and ran first; the temp-path test now precedes it, with `rm -rf /var/tmp` and `/var/tmp/` (bare roots) and `/var/tmp/../lib` as twins.
- After the fix: corpus `benign 46/46 dangerous 32/32 residual 0/3 runtime_ms 2104–4401` (three runs; the baseline gate limit is 6091 ms). `bats tests/unit/block-destructive-bash.bats tests/unit/hook-wiring.bats tests/unit/git-branch-prune.bats` → 288/288 (`GIT_CONFIG_GLOBAL=/dev/null`, KF-034; run in the background with exit captured to file, not piped). `lint-invariants.sh`: 11 pass, 1 pre-existing warn (`post-session-limit-reminder.sh:82`), 0 error. `tools/check-prompt-budget.sh`: unchanged (no skill or protocol touched). `bash -n` clean.

## AC Verification (sprint.md)

### Corpus run: benign pass rate ≥ 80 %, dangerous block rate 100 %; the existing 216 fence cases stay green (prd.md FR-1 AC 1–2)
- **Status**: ✓ Met
- **Evidence**: `run-corpus.sh` → `benign 46/46 dangerous 32/32`; bats "cycle-125 corpus: every dangerous row still blocks (100 %)" and "benign rows pass at or above 80 %" green; the fence suite is 265 cases (216 pre-existing + 4 gates + 45 named) all `ok`.

### Every relaxation has its dangerous twin in the corpus (prd.md FR-1 AC 3)
- **Status**: ✓ Met
- **Evidence**: vocabulary → D07 `rm -rf src`, D19, `.git/dist`, `node_modules/../src`, `dist /etc`; scratch cwd → D23 `cd /tmp && rm -rf ../etc`, D24 last-cd-wins, D30 quoted `cd`, D32 hook cwd; temp roots → D25 `/tmp`, D26 `/var/tmp`, `/var/tmp/../lib`, `/var/log`; `$TMPDIR` → inline `TMPDIR=/`, non-temp `TMPDIR`, unset, `$TMPDIR/../etc`; mktemp variables → D27 trailing path, D28 compound substitution, D29 `read` rebinding, two assignments, literal `/`, unbound, `H=$HOME`; SQL → D22 heredoc-then-`psql -f`, D31 `python3 -c`, `psql -c`, heredoc into `psql`, `mysql -e`, `sqlite3`, `docker exec … psql`, `prisma db execute`; branch → unmerged, mixed, unknown, metachar, non-repo; checkout → `src/app.ts`, mixed, `../dist/x.js`, fixture `a`.

### Hook runtime over the corpus within 1.5× of the pre-change measurement (prd.md FR-1 AC 4)
- **Status**: ✓ Met
- **Evidence**: baseline 4061 ms; post-fix runs 2104 / 3354 / 4401 ms on 81 rows (the baseline measured 73); bats "hook runtime … within 1.5× the recorded baseline" green (limit 6091 ms). The new predicates run only after a rule would otherwise fire, so benign commands that never reached FR-2 pay nothing.

### `git-branch-prune.sh` bats: merged, squash-merged (stub `gh`), unmerged, gone-upstream cases
- **Status**: ✓ Met
- **Evidence**: `tests/unit/git-branch-prune.bats` 13/13 — cases 1–4 are exactly those four, plus dry-run, network opt-out, failing probe, JSON, `--base`, exit codes, non-repo and the fence check.

### No hook file outside `block-destructive-bash.sh` changed; `hook-wiring.bats` green
- **Status**: ✓ Met
- **Evidence**: `git status` shows one modified file under `.claude/hooks/`; `hook-wiring.bats` 10/10 in the 288-case run.

## Security / trust-boundary notes (sdd.md §6)

- Every predicate returns "not proven" on any error (`git` missing, not a work tree, unreadable attribute, regex mismatch) and the pre-existing block stands. No relaxation reads the network.
- `_fr2_var_value` treats the binding as proof only when the command contains no other way to rebind the name; the rebind vocabulary is a denylist (Flatline SKP-002/003 accepted this as the bounded form for a text fence), and its twins are in the corpus.
- The helper's `gh` probe sends the branch name to GitHub; `LOA_FENCE_NO_NETWORK=1` disables it and the probe is bounded by `timeout 5` (or runs unbounded only where `timeout` is absent, macOS without coreutils — documented in the header as the residual).
- Corpus lint is a bats gate, so a future row with a hostname, IP, credential shape or public TLD fails CI rather than shipping.

## Review round 1 → fixes (2026-09-23, same day)

The round-1 review (`engineer-feedback-round1.md`) replayed hand-built twins against the committed hook and found six HIGH predicate holes plus one BLOCKING cross-model dissent (`adversarial-review.json` DISS-001, gpt-5.5-pro). All are fixed, each with a corpus row and a named twin:

| Finding | Fix | Twin rows |
|---|---|---|
| H-1 newline-initial rebinding not counted (double-quoted `"\n"` = letter n) | `_fr2_var_value` regex in ANSI-C quoting (`:1284-1290`) | D33 |
| H-1 `+=`, `readonly`, `NAME[`, `getopts` rebinding | new `_fr2_rebindable NAME` (`:1273-1283`): eval/read/readarray/mapfile/declare/typeset/local/readonly/unset/source/`.`/getopts/`printf -v`, `for|select NAME in`, `${NAME:=`/`${NAME=`, `NAME+=`, `NAME[` | D34–D37 |
| H-2 `$TMPDIR` branch ignored read / `+=` / unset | `_fr2_rebindable TMPDIR` applied; suffix captured before later `=~` calls clobber `BASH_REMATCH` (`:1323-1333`) | D38–D40 |
| H-3a second identical rm segment judged by the first prefix | `_seg_before` derived from the loop cursor: consumed text + this segment's prefix (`:1437-1441`) | D41 |
| H-3b `pushd` / `eval` / `source` / inline shell after a safe `cd` | `_fr2_scratch_cwd` voids on pushd/popd/eval/source/exec/chdir, `sh -c`, statement-initial `.`, or any `cd` token that is not statement-initial (`:1345-1370`) | D42–D44 |
| H-4 `head -1` in FR-1.1 / FR-1.3 | both helpers iterate every segment; a force-delete segment must name ≥ 1 branch; `main|master|develop|trunk` refused by name (`:631-670`, `:754-770`) | fixture cases; D45 |
| DISS-001 `rm -rf /tmp/*` (pre-sprint behaviour, tightened anyway) | `_fr2_temp_glob_re` (`:1241`) → FR-2-BLOCK before the temp-path allow (`:1551`); `$TMPDIR/*` refused (`:1332`); `/tmp/loa-cache-*` (prefixed glob) stays allowed | B47, D46–D49 |
| Obs-1 SQL runners | `php -r`; `rails`, `manage.py`, `artisan`, `alembic`, `dbt`, `atlas`, `mongosh`, `sqlx` (`:822-826`) | D50 |
| Obs-2 helper `"${timeout_cmd[@]}"` under `set -u` on bash 3.2 | `${timeout_cmd[@]+"${timeout_cmd[@]}"}`; header names the no-`timeout` residual | — |
| Obs-3 runtime gate vs corpus growth | `baseline.json` records `rows: 73`; the bats gate scales the baseline per row | — |

After the fixes: corpus `benign 47/47 dangerous 50/50 residual 0/3 runtime_ms 5314` (100 rows); the review probes all block except the two intended allows (`rm -rf /tmp/x/*`, `T=$(mktemp -d); rm -rf "$T"`); fixture probes: single merged `-D` allowed, every compound or `main` form blocked; `repo-map-gen.sh --validate` consistent; checksum regen `--check` 0 drift; `lint-invariants.sh` 0 error.

## Audit round 1 → fixes (2026-09-23)

The audit (`auditor-sprint-feedback-round1.md`) triaged the two dissent payloads the orchestrator rejected on schema (`adversarial-rejected-audit.jsonl`). Payload 2 was a real bypass at `87b7522c`: an assignment in command position after a reserved word (`T=$(mktemp -d); if T=/; then rm -rf "$T"; fi`, also `while`, `{ }`, `!`) is not statement-initial, so the once-bound counter saw one binding while the shell performed two. Payload 1 (grep carrier hiding `$(…)`) was refuted by probe — `_bdb_scrub` never redacts a value holding `$(` or a backtick.

| Finding | Fix | Twin rows |
|---|---|---|
| HIGH-001 reserved-word rebinding | `_fr2_var_value` also counts every `NAME=` token anywhere (`(^|[^[:alnum:]_])NAME=`) and requires that total to be exactly one (`:1297-1306`) | D51–D54; R05 (`echo T=/` becomes an accepted FP) |
| refuted payload 1 | no change; pinned | D55 + named case (`grep "$(rm -rf /)" file` → block; `rg -n 'rm -rf dist' docs/` → allow) |
| MED-001 helper trusts "a merged PR exists" | `squash_merged` asks for `headRefOid` and requires it to equal the local head; stale OID → branch kept | `git-branch-prune.bats` "a merged PR whose head is not the local head keeps the branch" |
| LOW-003 GNU-only clock in `run-corpus.sh` | `now_ms()` uses `$EPOCHREALTIME` with a `date` fallback | — |
| LOW-004 `--help` exit code | exits 0 | bats "--help exits 0 with usage" |
| LOW-001 (pre-existing variable-content gap), LOW-002 (lint TLDs) | recorded, not changed this sprint | — |

After the fixes (`git log -1`: audit-fix commit): corpus `benign 47/47 dangerous 55/55 residual 0/5 runtime_ms 5636` (107 rows); `git-branch-prune.bats` 15/15; checksum regen 0 drift; REPO-MAP consistent.

## Out of scope, noted

- `git restore <path>` is not fenced today and stays unfenced; only `git checkout -- <path>` carries FR-1.3.
- `cd "$(mktemp -d)" && rm -rf out` stays blocked (the `cd` target is a substitution, not a path); the message tells the agent to bind the path first.
- SQL through a script file (`python app.py`) was never matched and is not; inline programs (`-c`, `-e`, `-`) are.
- The three residual rows (R01–R03: `ssh host 'rm -rf …'`, `docker exec … rm -rf`, `kubectl exec … rm -rf`) remain blocked by design (D-1.2 withdrawn).
