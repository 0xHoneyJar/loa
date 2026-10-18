# Sprint 258 audit fix round 1 (implementer afix) — report

Worktree `loa-wt-s1-afix` at `0c200dd6`. Scope: MEDIUM-A1, MEDIUM-A2, LOW-A1 … LOW-A6 of `auditor-sprint-feedback.md`, nothing else. No commit, no docker, no claude or codex call.

## What was changed (per finding)

- **MEDIUM-A1.** `evals/harness/pipeline-run.sh:817`: the every-phase copy loop is gone. REVIEW copies `adversarial-review.json`, AUDIT copies `adversarial-audit.json` to eval/ only when the eval copy is absent; a symlink is never copied. Gate records carry `envelope_copied` and `envelope_sha256` (`:901`). Header updated. `ablation-row.sh:228` and `took-effect.sh:87` read eval/ first, the sandbox only when eval/ has none. `ablation-row.sh:235` sets `zone_violations.envelope_mismatch` via `cmp -s`.
- **MEDIUM-A2.** `evals/harness/run-arms.sh:526`: a non-completed row with a missing, 0 or malformed cost charges `RUN_CAP` to `SPENT` (never to the arm/pool means) and counts `ASSUMED_CAP`; the no-row branch (`:547`) does the same. `STATUS.json.spend.assumed_cap_trials` (`:377`). Header paragraph `:28-33`.
- **LOW-A1.** `evals/harness/execute-agent.sh:275`: effort whitelist after `arm_effort=`, exit 2.
- **LOW-A2.** `pipeline-run.sh:537`: `claude_md_sha256` / `loa_config_sha256` evidence lines; `compute_mount_integrity` (`:339`) in `finish()` and `on_exit` writes `pipeline.json.mount_integrity`. `ablation-row.sh:387`: `bash_mount_refs`, `mount_changed`; `--validate` (`:138`) requires the four arrays.
- **LOW-A3.** `execute-agent.sh:217`: the unset runs in every mode, before the toggles; `executor.json.adversarial_review_enforce` (`:227`, `:410`).
- **LOW-A4.** `evals/harness/fingerprint.sh:53`: the dotfiles fallback is deleted; header updated.
- **LOW-A5.** `ablation-row.sh`: writer grammar check (exit 2) after arm resolution; `--validate` check (`:137`).
- **LOW-A6.** `evals/harness/Dockerfile.ablation:68` exact pins; `:71` `ARG BATS_COMMIT`; `:73` rev-parse check before install.sh. `git ls-remote` shows `v1.13.0^{}` peels to `3bca150e…`.
- **Stub.** `claude-stub-pipeline.sh` gains `STUB_TAMPER_ENVELOPE_<PHASE>` and `STUB_APPEND_CLAUDE_MD_<PHASE>`. Fixture runs are unchanged.

## Tests added (all fail on the pre-change scripts, pass after)

Method: a scratch copy of the worktree with the seven harness files restored from `git show HEAD:…` and the new tests in place; the filtered cases were all `not ok` there and all `ok` in the worktree.

All 15 new cases and the 3 changed ones fail on the pre-change scripts and pass after:
- pipeline-run (+5): envelope copied once with `envelope_sha256`, FIX rewrite leaves eval/ unchanged (A1); AUDIT rewrite and symlinked envelope never copied (A1); mount integrity ok/changed/absent/null (L-A2); fingerprint `bats=absent` without PATH bats, no `dotfiles` (L-A4); Dockerfile exact pins, 40-hex `BATS_COMMIT`, rev-parse before install.sh (L-A6).
- ablation-row (+5): tampered sandbox → eval/ values and `envelope_mismatch` (A1); `bash_mount_refs` with the 160-char cut (L-A2); `mount_changed` (L-A2); `--validate` needs the four arrays; arm grammar in the writer (exit 2) and `--validate` (exit 1, `:2:` named) (L-A5). Changed: the DEGRADED-envelope and empty-finished cases now edit eval/, plus a legacy sandbox-fallback check.
- took-effect (+1): `one_voice_planned` reads eval/ first, the sandbox only without an eval/ copy.
- run-arms (+2): RA-13 assumed cap (pre-change: 7 launched, cut at trial 8; after: 4 launched, cut at trial 5, spent 11, `assumed_cap_trials 1`, `est_next 2`); RA-14 `assumed_cap_trials 0` when every trial reports its cost.
- execute-agent (+2): EA-13 baseline env leak (pre-change fails on the env check itself) and `"unset"`; EA-14 `effort: maximum` through a stub library → exit 2, no CLI call.
- arm-toggles (changed AT-17): `adversarial_review_enforce` `"false"` for a4, `"unset"` for a1.

RA-13 note: the brief said "one trial earlier". With the brief's numbers the assumed USD 5 charge equals 2.5 trials at USD 2, so the cut comes three trials earlier. Pre-change: 0, 2, 4, …, 12 → 7 launched, cut at trial 8. Post-change: 5, 7, 9, 11 → 4 launched, cut at trial 5.

## Commands and results

| Command | Exit | Result |
|---|---|---|
| `bats evals/tests/` at `0c200dd6` (before any edit finished) | 0 | 269/269 |
| `bats evals/tests/` final | 0 | 284/284 (+15 cases) |
| `bats tests/unit/check-loa-mount-scope.bats` | 0 | 6/6 (the file has 6 cases at HEAD; the brief said 7) |
| `bash tools/check-no-raw-sha256sum.sh` | 0 | OK |
| `bash tools/check-no-raw-curl.sh` | 0 | OK |
| shell-compat-lint workflow script (yq-extracted) | 0 | PASSED, 25 pre-existing warnings, none in my files |
| `bash -n` on every edited script | 0 | — |

Trust boundary: no new `source`/`.` line, no `eval`, no `.claude/` code; hashing is `python3 -I` hashlib; bash 3.2-safe (empty-array guard on `mismatch`, `x=$((x + 1))`). The pipeline-run trust-boundary bats case stays green.

## DECISION bullets

- DECISION: A symlinked sandbox envelope (or a pre-existing eval/ target that is a symlink) is never copied; the gate records `envelope_copied: false` and `envelope_sha256: null`. Following a symlink would let the agent place an arbitrary host file into eval/.
- DECISION: `envelope_copied` and `envelope_sha256` appear only on REVIEW and AUDIT phase records; other phases carry neither key (the brief's "that phase's record").
- DECISION: `envelope_mismatch` lists gates in fixed order review, audit; byte equality with `cmp -s`; a missing side is not a mismatch.
- DECISION: The "no row written" branch of `collect()` also charges `RUN_CAP` and counts toward `assumed_cap_trials`. It is the same defect class (a trial that died without a reported cost) and otherwise remained a zero-cost hole.
- DECISION: The assumed charge is one `RUN_CAP` per row even when the row records `attempts: 2` (both transport attempts died), as the brief specifies. A strict ceiling would charge `attempts × RUN_CAP`; flagged for the lead.
- DECISION: The assumed charge applies whether or not `--max-usd` is set; `SPENT` only matters to the gate and `spend` stays out of STATUS.json without `--max-usd` (RA-7 unchanged).
- DECISION: RA-13 uses `--trials 8` on one fixture at concurrency 1 so the cut position is exact (4 vs 7 launched); the brief's "one trial earlier" does not hold for a USD 5 charge against USD 2 trials.
- DECISION: `_mount_sha` reports `symlink`, `not-a-file` or `unreadable` instead of following or failing; any of these at finish differs from the hex baseline and reads `changed`.
- DECISION: `mount_integrity` is forced to both `absent` for `loa_mount: false` (per the brief), and is `null` when the run stops before materialisation (refusal, mount failure).
- DECISION: The fixture runs are not regenerated: their pipeline.json lacks `mount_integrity` and the gate fields, which keeps the legacy path tested (rows read `mount_changed: []`).
- DECISION: The arm-grammar check in the writer runs after arm resolution, so it covers meta/arm (whitespace already stripped), manifest `arm_map` and pipeline.json values alike.
- DECISION: EA-13 and AT-17 export the variable instead of using a prefix assignment, because bats `run` does not pass a prefix assignment to the command it runs. AT-17's pre-existing a1 check had that problem too, and I fixed it there.
- DECISION: My new negated assertions end in `|| false`, because a bare `! cmd` that is not the last line never fails a bats test.

## Could not do / known limitations

- The audit is satisfied in full; nothing was skipped.
- 36 pre-existing bare `! cmd` lines in `evals/tests/` are not the last command of their test and so can never fail. They are in arm-toggles 10, pipeline-run 15, execute-agent 5, seed-corpus 4, freeze 2. Fixing them is outside this brief; worth a bead. I only fixed the AT-17 line that tests LOW-A3.
- `bash_mount_refs` is a text match, so it can be evaded by obfuscated commands (variables, base64). `mount_integrity` and took-effect's `integrity_clean` are the after-the-fact backstop.
- I ran no docker build (as instructed). The pinned Dockerfile is verified by text checks only.

## Handoff notes for the lead

- Rebuild `loa-ablation:258` from the pinned Dockerfile before Sprint 260's first batch and record the digest (audit LOW-A6). A build fails loudly if the bats tag moves.
- `zone_violations` gains three keys, so rows written before this patch fail the new `--validate`. The only committed row files are spend.sh fixtures without `zone_violations`; local smoke rows must be rewritten.
- `executor.json` gains `adversarial_review_enforce`; `pipeline.json` gains `mount_integrity`, gate-phase `envelope_copied`/`envelope_sha256`, and arm_evidence `claude_md_sha256`/`loa_config_sha256`; `STATUS.json.spend` gains `assumed_cap_trials`. The SDD and CHANGELOG are yours to update (I did not touch them).

## Addendum: bash_mount_refs narrowed

On the real smoke runs, the first spec listed every Bash command that only read the mount. Now `evals/harness/ablation-row.sh` lists a Bash `tool_use` command only when it is write-shaped toward the mount (jq `test`, Oniguruma):
- Prong 1, a redirect to a mount path: `>>?[[:space:]]*[^[:space:];&|]*(\.claude/|CLAUDE\.md|\.loa\.config\.yaml)`
- Prong 2, a mount path `\.claude/|CLAUDE\.md|\.loa\.config\.yaml` together with a write-capable token at a command position: `(^|[;&|(][[:space:]]*|\bthen[[:space:]]+|\bdo[[:space:]]+)(sed[[:space:]]+-[a-zA-Z]*i|cp|mv|rm|ln|tee|truncate|install|patch|chmod|chown|git[[:space:]]+(checkout|apply|restore)|yq[[:space:]]+-i|python3?|perl)\b`

`{phase, excerpt}`, the 160-character cut, the `[]` default and the `--validate` array requirement are unchanged. The header now calls the list a heuristic that obfuscation can evade, and names `mount_integrity` and took-effect's `integrity_clean` as the authoritative checks. The help range moved to `2,84`.

The bash_mount_refs case in `evals/tests/ablation-row.bats` was rewritten:
- Four commands must be listed: `sed -i … .claude/rules/a.md`, the long `echo … >> CLAUDE.md` (cut to 160), `yq -i '…' .loa.config.yaml` and `tee -a CLAUDE.md <<< x`.
- Seven commands must not be: `cat .claude/skills/auditing-security/SKILL.md`, `ls .claude/skills/ | grep -i audit`, `sed -n '95,400p' .claude/scripts/a.sh | head -40`, `cat .claude/rules/a.md > /tmp/y`, `grep -rn integrity .loa.config.yaml`, `ls src && pytest -q`, and a Read tool call.

Against the version already applied (`git show :evals/harness/ablation-row.sh`), the case fails because the reads are listed. Against the new script it passes.

Counts: ablation-row and pipeline-run together are 86/86. The full `evals/tests/` is 284/284; the case was rewritten, not added.

- DECISION: The four write-shaped entries (yq -i and tee included) are asserted together with the seven reads in one case, so the count stays at 284.
- DECISION: The delta patch is the working tree against the staged index. It touches only `ablation-row.sh` and its bats file.
