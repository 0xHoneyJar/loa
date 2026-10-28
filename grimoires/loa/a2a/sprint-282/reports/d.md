# cycle-137 Sprint 282 — Task 2.6 (implementer D): `audit-envelope.sh verify-chains`

Bead bd-09z1i. FR-7 option (a) is IMPLEMENTED, not deferred. No STOP condition was hit.
Worktree `/home/merlin/Documents/thj/code/loa-wt-c137-d`, base `747b5db0d`. B's 2.3 fix was NOT in this worktree. My `loa-status.sh` hunk touches only `_an_audit_chain_summary()` (lines 421–455), so it should not conflict with B's `_anthropic_ceiling_json` edit.

## Deliverables

| File | sha256 |
|---|---|
| `.cycle137/task-2.6-red.patch` (new: `tests/unit/audit-envelope-verify-chains.bats`, `tests/unit/test_audit_verify_chains.py`) | `bb0be32113efc2cc73981b4936572cded2d73be45c563ffabdbdea4ab1cf59d8` |
| `.cycle137/task-2.6-fix.patch` (`.claude/adapters/loa_cheval/audit_envelope.py`, `.claude/scripts/audit-envelope.sh`, `.claude/scripts/loa-status.sh`) | `f1fb6cb4d739708ce3861572b04b7d4ba1ff5f8e1114ca2309689ae151812f3b` |

Both patches are `git diff` of the working tree against HEAD, with standard `a/` and `b/` prefixes. I applied red, then fix, to a `git archive HEAD` copy; both applied cleanly and all five resulting files are byte-identical to the worktree. The two new test files are intent-to-add (`git add -N`) in the worktree index. Nothing was committed, stashed or pushed.

Contents of `.cycle137/fixtures/`:
- `make_fixtures.py <outdir> <repo>` builds the fixture set. It contains a root-signed trust store (writer `w1`, cutoff 2020), a tampered store (rogue key appended, not re-signed) and a store that revokes `w1`. It also contains five valid signed chains, tampered, broken-link and empty chains, and the loa-status roots r0, r3 and r5. `gen/` is the generated set behind every number below.
- `parity.sh <worktree> <gen> <outdir>` compares an OLD mirror (`git archive HEAD .claude lib`) with a NEW mirror (tar of the working tree), both in REAL directories. It checks 141 artefact pairs (stdout, stderr, rc). `golden-old-vs-old/` holds the golden capture (old vs old, which proves the outputs are deterministic). `parity-old-vs-new/` holds the run on the final code.
- `measure.sh <parity-out> <gen> <prefix>` runs hyperfine and the PS4 spawn count. Outputs are in `measure.txt` and `measure.loa-status.json`.
- `pytest-schedule.txt` is a verbose pytest run that prints every batch record for each schedule.
- `c137d-suite-final.tsv` and `c137d-suite-final.fail` hold the final bats sweep.

## What changed and why

1. **Python.** New `audit_verify_chains(paths, *, verify_for_merge=False) -> list` in `audit_envelope.py`, plus `__all__`, one docstring line and a `Sequence` import. For each path in order it calls the UNCHANGED `audit_verify_chain` inside its own `try/except Exception`. The fix patch has no hunk in `_check_trust_store`, `_trust_store_snapshot`, `audit_verify_chain` or `_TRUST_STORE_CACHE`. The docstring states the snapshot semantics and the TOCTOU argument.
2. **Shell.** New subcommand `verify-chains [--verify-for-merge] <path>…` in `audit-envelope.sh`, with:
   - a case arm and `--help` lines;
   - the wrapper `audit_verify_chains`;
   - `_audit_verify_chains_py`, the single `python3 -` process. It is a function rather than a heredoc inside `$(...)`, so bash 3.2 can parse it.

   Strict folding is the same as the singular form: `--verify-for-merge` or `LOA_AUDIT_STRICT_VERIFY=1`. The singular `verify-chain` is unchanged.
3. **loa-status.sh** `_an_audit_chain_summary()`. The `[[ -f ]]` pre-filter stays, so missing files still count as valid by absence. Existing paths are collected into an array, passed to ONE `verify-chains` call, and counted with ONE `jq` over the records.

## Record protocol as implemented

The output is one JSON line per input path, in argument order:

    {"i":<0-based index>,"path":"<the argument, byte-exact>","ok":<bool>,"error":<null when ok | str>}

- `error` is the verifier's own message, for example `BROKEN line N: …`, `[TRUST-STORE-INVALID] …`, `[TRUST-STORE-BOOTSTRAP-PENDING] …` or `[TRUST-CUTOFF-INVALID] …`.
- A path that does not exist gives `"missing"`, the SDD § 5.7 text. The batch maps exactly the function's returned `file not found: <path>` to it and does no existence check of its own.
- A per-path exception gives `"<ExceptionType>: <message>"`, for example `IsADirectoryError: [Errno 21] Is a directory: '<p>'`. The next path still runs.
- **The wrapper in audit-envelope.sh fails closed.** One jq keyed on the index keeps the record for index k only when two conditions hold:
  - exactly one well-formed record has `i == k` (well-formed: `i` a number, `path` a string, `ok` a boolean, `error` a string or null, and `ok` true exactly when `error` is null);
  - its `path` equals argument k.

  Otherwise index k gets `{"i":k,"path":<arg k>,"ok":false,"error":"[VERIFY-CHAINS-NO-RECORD] the verifier returned no single valid record for this path (exit <rc>)"}`. Stdout therefore always carries exactly N records.
- **Exit codes:**
  - 0 only when the verifier process exited 0 AND every record is ok.
  - 1 when any record is not ok. This includes a verifier crash that left partial output.
  - 2 on zero paths: a usage line on stderr and nothing on stdout.
  - 2 on an import failure: the error on stderr and N FAILED records on stdout.
  - 2 when the wrapper's own jq fails: nothing on stdout.
- **The loa-status consumer** counts index k as valid only when exactly one record for k says `ok:true` and echoes path k. Unrecorded, duplicated or path-mismatched indices count as invalid. An exit other than 0 or 1, or output that does not parse, counts NONE of the passed paths. This is more conservative than the per-call loop only in that abnormal-exit case, and a code comment says so.

## Store-mutation equivalence test (pytest)

**How the hook works.** It monkeypatches `audit.audit_verify_chain` with a wrapper that calls the ORIGINAL and then applies the mutation scheduled after path k. The batch looks the function up through the module global, so the hook runs between paths without editing any protected function.

**Oracles.** There are two, and they must agree with each other and with the batch:
- a fresh `python3` process per call (`subprocess`);
- an in-process sequential loop that clears nothing. This is valid because the cache is keyed by content.

Each schedule also has outcomes stated by hand. All 6 schedules were run in both modes (default and `verify_for_merge`), and all pass.

| Schedule (mutation after path) | Expected per path (a, b, c) | Result |
|---|---|---|
| unchanged | ok, ok, ok | batch = fresh = in-process |
| revoke after a (signed store revoking w1 at 2021) | ok, then `BROKEN line 1: cannot resolve public key for signing_key_id=w1` twice | equal |
| revoke after b | ok, ok, cannot resolve | equal |
| tamper after a (rogue key, not re-signed) | ok, then `[TRUST-STORE-INVALID] …` twice | equal |
| delete after a | ok, then `BROKEN line 1: [TRUST-STORE-BOOTSTRAP-PENDING] signed history requires a verified store` twice; in strict mode `[TRUST-STORE-BOOTSTRAP-PENDING] trust-store is not signed…` | equal |
| tamper after a, repair after b | ok, `[TRUST-STORE-INVALID]`, ok | equal |

**Re-authentication count.** `test_store_reauthenticated_only_when_its_content_changes` counts the `trust-store-verify` helper subprocesses. An unchanged store over 3 paths runs the helper once. Tamper-then-repair runs it 3 times: good, tampered, then good again. This measures the claim that the store is re-authenticated whenever it changes.

**Other cases.** Exception isolation: path b raises `ValueError: boom`, path c is still ok and a missing path reports `missing`. An empty input returns no records.

## python3 spawn count in loa-status (whole script, r5 root)

Measured with a PS4='+' xtrace and `SHELLOPTS=xtrace`, which child shells inherit.

| | `python3` lines | `verify-chain` calls | `verify-chains` calls |
|---|---|---|---|
| old | 5 | 5 | 0 |
| new | 1 | 0 | 1 |

## Measurement

**Setup:**
- Host `fukuoka`, 8 cores. It was LOADED by the other implementers' runs: load average 9.1–10.5 during the final run.
- Command: `hyperfine -N -i --warmup 3 --runs 10 'bash <mirror>/.claude/scripts/loa-status.sh --no-stale-check'`.
- cwd is the r5 fixture root: 5 chain files, all valid, VERIFIED store.
- `LOA_TRUST_STORE_FILE` and `LOA_PINNED_ROOT_PUBKEY_PATH` point at the fixture store and pin.
- Baseline revision is HEAD `747b5db0d`, the old mirror. No caches are involved.

| | runs | mean ± σ |
|---|---|---|
| old | 10 | 2107 ms ± 197 ms |
| new | 10 | 960 ms ± 82 ms |

The fall is about 1.15 s, against the AC bar of ≥ 100 ms. An earlier run, at load around 12, gave old 2851 ± 356 ms and new 1361 ± 291 ms. On the same host the singular `verify-chain <valid chain>` costs 236.1 ms ± 38.3 ms per call (10 runs). Both means are inflated by host load, so re-run `measure.sh` on the idle ship host for the release table.

## Parity

**Method.** `parity.sh` compares the old and new mirrors in REAL directories over 141 artefact pairs. Only two things are normalised: the mirror path, and `"age_s"` in the live `--json`, which the golden old-vs-old run showed changing between runs. **140 pairs are identical. The one difference is intended:** the `--help` stdout gains the four `verify-chains` lines.

| Input | loa-status human + `--json` (stdout, stderr, rc) | Audit chain cell, old = new |
|---|---|---|
| live snapshot (see note below) | identical | 6/7 |
| r0: 5 broken or tampered chains | identical | 2/7 |
| r3: 3 valid, 2 bad | identical | 5/7 |
| r5: 5 valid | identical | 7/7 |
| r3-partial: 2 valid, 1 bad, 2 missing | identical | 6/7 |
| none: no chain files | identical | 7/7 |
| r5 with a tampered, revoking or missing store | identical | 2/7 |
| singular `verify-chain` (see note below) | identical | — |

The live snapshot is a copy of the main checkout's `.run`, top-level `grimoires/loa` files, `handoffs/` and config, run against the LIVE trust-store path read-only. The singular row covers 9 chain fixtures and a missing path, each in default mode, strict mode and with the tampered store, plus the live `INDEX.md`.

**Why a snapshot for the live case.** bwrap is unavailable because unprivileged namespaces are disabled on this host. `loa-status.sh` must never write into the main checkout's `.run`.

**Per-path vs per-call:**
- **Fixture chains.** Bats test VC-9 checks every fixture chain under both stores and both modes. A singular rc of 0 matches `ok:true`, and otherwise the singular message equals the batch `error`.
- **Live chains**, read-only. Of the five, only `grimoires/loa/handoffs/INDEX.md` exists. Singular: `rc=1 BROKEN line 1: invalid JSON (Expecting value: line 1 column 1 (char 0))`. Batch: one record with `ok:false` and the identical error, exit 1.

## Red-first evidence

On the unchanged code with only the red patch applied:
- `tests/unit/audit-envelope-verify-chains.bats`: 15 of 18 FAIL. They are VC-1 through VC-9, VC-11, VC-12, VC-13, LS-3, LS-4 and LS-5. LS-3 fails on its assertion `python3 lines == 1`, because the old function traces 5.
- The 3 that PASS on old code are regression guards that must stay green:
  - VC-10: singular `verify-chain` stays byte-exact.
  - LS-1: N/7 on every root equals the stated count and a per-call oracle.
  - LS-2: the whole-script Audit chain cell.
- `tests/unit/test_audit_verify_chains.py`: 15 of 15 FAIL with `AttributeError: module 'loa_cheval.audit_envelope' has no attribute 'audit_verify_chains'`.

After the fix, 18/18 bats and 15/15 pytest pass.

**`red-test-check.sh` needs an extra flag on this host.** `cryptography` lives in `~/.local`. Under the check's `env -i` and fresh HOME, every audit test skips, so the red run would read as DECOY. Pass `--env-pass PYTHONUSERBASE` with `PYTHONUSERBASE=$(python3 -m site --user-base)` exported:

    PYTHONUSERBASE=$(python3 -m site --user-base) bash .claude/scripts/red-test-check.sh --red <red-sha> --env-pass PYTHONUSERBASE -- npx --no-install bats tests/unit/audit-envelope-verify-chains.bats
    PYTHONUSERBASE=$(python3 -m site --user-base) bash .claude/scripts/red-test-check.sh --red <red-sha> --env-pass PYTHONUSERBASE -- python3 -m pytest -q -p no:cacheprovider tests/unit/test_audit_verify_chains.py

## Test counts

I used `.venv/bin/python -m pytest`, which is pytest 9.0.2; CI pins 9.0.3. `python3 -m pytest` (system, also 9.0.2) gives the same result on the security file and the new file.

| Suite | Result |
|---|---|
| `tests/unit/test_audit_verify_chains.py` | 15 passed |
| `tests/security/test_audit_trust_policy.py` + `tests/security/test_audit_consumer_snapshots.py` + the new file | 53 passed, 91 subtests |
| `.claude/adapters/tests` | 3332 passed, 6 skipped, 2 failed (see below) |
| `tests/unit/audit-envelope-verify-chains.bats` (new) | 18/18 |
| focused re-run on the final code (see below) | all ok |
| full bats sweep on the final code (see below) | 48 files: 455 ok (5 skipped), 15 not ok, all pre-existing |

**Adapter-test failures.** `test_claude_headless_adapter.py::TestCommandConstruction::test_minimal_command` and `::TestEndToEnd::test_complete_round_trip` fail identically on the HEAD mirror. The host's `CLAUDE_HEADLESS_BIN` (`claude-fallback`) causes them, so they are unrelated to this change.

**Focused re-run, counts per file:** `audit-envelope-schema` 13, `loa-status-artefacts` 3, `loa-status-guards` 3, `loa-status-providers` 13, `loa-status-stale-worktree` 10, `agent-ergonomics-loa-status` 8, `perf-spawn-budget` 8, `integration/audit-envelope-chain` 9, `integration/audit-trust-store-auto-verify` 13, `security/audit-envelope-strip-attack` 7.

**Full sweep scope.** 48 files: the 42 bats files that mention audit-envelope or audit_envelope, plus 6 loa-status and spawn-budget files. It ran with `LOA_AUDIT_SIGNING_KEY_ID` unset.

**The 15 sweep failures are not caused by this change:**
- 12 signed-mode tests fail identically on a `git archive HEAD` copy. They are `cost-budget-enforcer-signed-mode` 4 and 8, `hitl-jury-panel-signed-mode` 2 and 5, `scheduled-cycle-lib-signed-mode` 4, 5, 7 and 8, and `signing-fixtures-smoke` 3, 5, 11 and 12.
- `test_dispatch_unchanged.bats` 2 and 5, and `test_economy_e2e_goals.bats` 11, diff `loa_cheval/providers/` against main. Sprint 281 changed that directory, and this patch does not touch it. I did not re-run these three on HEAD.

**The 44-file count in the AC.** I found 42 files under `tests/` that mention audit-envelope (43 with the new one). The lead's list of 44 may be drawn differently. The sweep covers every file I found.

**Host gotcha.** This host exports `LOA_AUDIT_SIGNING_KEY_ID`. With it set, 39 tests across 13 audit files fail on old and new code alike, because `audit_emit` signs entries that the suites' bootstrap stores reject. Unset it before running the audit suites.

**Lints.** On the final code `tools/check-no-swallowed-jq.sh --quiet` exits 0 and `tools/check-no-raw-sha256sum.sh` exits 0. `bash -n` is clean on both scripts.

## UNVERIFIED

- `shellcheck` is not installed on this host, so the two scripts were not shellchecked.
- `red-test-check.sh` was not run, because it needs commits.
- The three dispatch-unchanged failures were not re-run on HEAD.
- The measurement ran on a loaded host. It needs a re-run on the idle ship host.
- Bash 3.2 and BSD behaviour was not exercised; there is no macOS host.
- No test covers a non-UTF-8 path.
- I did not check that the unit bats glob in CI picks up the new bats file.

## Judgment calls (for class-S DEC rows)

- **J-1. The text for a missing path.** The brief says `error: "missing"` and also "keep its text". SDD § 5.7 and the sprint AC say `"missing"`. I used `"missing"`, mapped from the function's exact `file not found: <path>` return.
- **J-2. Abnormal exit in loa-status.** On an exit other than 0 or 1, or unparsable output, I count none of the passed paths. That is stricter than "count every unrecorded path invalid". The wrapper always emits N records unless it exits 2, so in practice this rule fires only on exit 2 or a killed wrapper.
- **J-3. A second validation layer in the wrapper.** The AC says "fail-closed in the wrapper and in loa-status.sh", so the wrapper validates the Python output with one jq, roughly 5 ms. A verifier crash mid-batch still yields N records: the unrecorded ones are FAILED and the exit is 1.
- **J-4. Byte-exact paths.** Python stdout uses `errors="surrogateescape"`, so a non-UTF-8 path cannot crash the batch with `UnicodeEncodeError`. Any path mismatch in jq fails closed.
- **J-5. jq 1.6 or later is required** for `$ARGS` and `--args`. Older jq makes the wrapper exit 2, and loa-status then counts the passed paths invalid, which is fail-closed. `--args` is already used in `loa-status.sh`, `spiral-harness.sh`, `adversarial-review.sh` and `scheduled-cycle-lib.sh`.

## For the lead

- `.github/workflows/bats-tests.yml`, around line 183, runs an EXPLICIT list of pytest files. Add `tests/unit/test_audit_verify_chains.py` to it, or the new test will not run in CI. That file is outside my allowlist.
- I did not regenerate the manifests (`checksums.json`, REPO-MAP), as the patch contract requires.

## CHANGELOG line (text)

- **audit-envelope `verify-chains`: one Python process for every chain file** (cycle-137 FR-7, bd-09z1i). `audit-envelope.sh verify-chains [--verify-for-merge] <path>…` calls the unchanged `audit_verify_chain` once per path inside one process (new `loa_cheval.audit_envelope.audit_verify_chains`) and prints one JSON record per path in argument order (`{"i","path","ok","error"}`; exit 0 all ok, 1 any not ok, 2 usage/import); fail-closed on a missing, duplicate or malformed record. The trust-store check still runs per path, so a store that changes between paths is re-authenticated (store-mutation equivalence test in `tests/unit/test_audit_verify_chains.py`). `loa-status.sh` makes one such call instead of one per chain file (`python3` spawns 5 → 1 on a 5-chain root); the Audit chain count is unchanged. `verify-chain` (singular) is unchanged.
