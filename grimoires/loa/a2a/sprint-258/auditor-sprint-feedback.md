APPROVED - LET'S FUCKING GO

# Sprint 258 security audit — round 2 (cycle-130 Sprint 1) — APPROVED

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-15
**Implementation:** `ffe162ef` (audit fix round a258-1 by implementer afix on `0c200dd6`; base `252501b4`); review APPROVED (`engineer-feedback.md`, round 2); round 1 audit kept as `auditor-sprint-feedback-r1.md`
**Dissent:** `adversarial-audit.json` (round 1, two voices, consensus, 0 rejected payloads) — the sprint's three dissent runs are spent (review r1, review r2, audit r1); this round is the auditor's direct verification of the fix against the tree, as sprint-257's second audit round was.
**Suites on `ffe162ef`:** `evals/tests/` 284/284 (15 new cases, every one shown failing on `0c200dd6` by restoring the pre-fix scripts), `tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope}.bats` 20/20, trust-boundary scan clean, `tools/check-manifest-paths.sh` and `gen-checksums.sh --check` unchanged, `evals/results/ablation-2.0/smoke-258/rows.jsonl` regenerated from the 20 smoke run directories and 20/20 valid under the new `--validate`; `loa-ablation:258` rebuilt from the pinned Dockerfile (exit 0, id `4e37cb5f…`).

## Round 1 items, verified against the tree

- **MEDIUM-A1 closed.** `pipeline-run.sh` copies a gate's envelope to `eval/adversarial-<gate>.json` only in the REVIEW resp. AUDIT phase, only when no eval copy exists, never through a symlink on either side (`[[ -e dst || -L dst || -L src || ! -f src ]] ||`), and records `envelope_copied` and `envelope_sha256` (hashlib) on that gate's record alone; the every-phase copy loop is gone (`! grep 'for env_f in'` is asserted). `ablation-row.sh` and `took-effect.sh` read `eval/` first and the sandbox only when `eval/` has none; when both exist `cmp -s` decides `zone_violations.envelope_mismatch` in gate order. Verified by the stub pipeline: a FIX or AUDIT phase that rewrites the sandbox envelope leaves `eval/` and the row's `voices_run`/`degraded` on the gate's values and lists the gate under `envelope_mismatch`; a symlinked envelope yields `envelope_copied: false`, `envelope_sha256: null` and no eval file.
- **MEDIUM-A2 closed.** `run-arms.sh collect()` charges `RUN_CAP` to `SPENT` when a row's status is not `completed` and its cost is missing, 0 or malformed, and for a trial that wrote no row at all; `ASSUMED_CAP` reaches `STATUS.json.spend.assumed_cap_trials`; assumed charges never enter `est_next`'s means. RA-13 shows the cut moving from trial 8 to trial 5 for a trial that dies twice without a cost under `--max-usd 12 --run-cap 5` (`spent 11`, `assumed_cap_trials 1`, `est_next 2`). The implementer's note that a strict ceiling would charge `attempts × run_cap` for a twice-dead trial is right; one charge per trial is the brief's choice and `run_cap` already bounds each attempt by the executor's own cap, so the ceiling holds.
- **LOW-A1 closed.** `execute-agent.sh` whitelists `arm_effort` (`""|low|medium|high|xhigh|max`, else exit 2) before it reaches argv; EA-14 proves it through a stub library that accepts anything.
- **LOW-A2 closed.** `pipeline-run.sh` records `claude_md_sha256` and `loa_config_sha256` after materialisation (a symlink reads `symlink`, never followed) and writes `pipeline.json.mount_integrity` at finish and on the abort path (`absent`/`absent` for A0, `null` before materialisation); `ablation-row.sh` adds `mount_changed` and `bash_mount_refs`. The first `bash_mount_refs` spec (any Bash command naming the mount) listed every read a Loa skill performs (30–40 entries per A1 gate row on the smoke runs) and was narrowed in the second patch to write-shaped commands: a redirect whose target is a mount path, or a mount path together with a write-capable command token at a command position; reads (`cat`, `ls`, `grep`, `sed -n`) never match. On the regenerated smoke rows the list is now 0–8 entries per row, the hits being BARE test scripts that name `pr/head/.claude/...` paths in `/tmp`. The header calls the list a heuristic and names `mount_integrity` and took-effect's `integrity_clean` as the authoritative after-the-fact checks, which is the right framing.
- **LOW-A3 closed.** The `unset LOA_ADVERSARIAL_REVIEW_ENFORCE` runs in every mode before the toggles; only `gates: false` sets it again; `executor.json.adversarial_review_enforce` records `"false"` or `"unset"` (EA-13, AT-17; the stub now captures the executor environment, and AT-17's a1 check, which used a prefix assignment `run` never forwarded, is fixed to export).
- **LOW-A4 closed.** `fingerprint.sh` resolves `--bats-bin`, `LOA_EVAL_BATS_BIN`, else `bats` on PATH, else `absent`; `grep dotfiles` finds nothing.
- **LOW-A5 closed.** `^[a-z][a-z0-9_]{0,63}$` is enforced after arm resolution (meta/arm, manifest `arm_map`, pipeline.json alike; exit 2) and in `--validate` (exit 1 naming the line).
- **LOW-A6 closed.** `rfc8785==0.1.4 jsonschema==4.26.0 pyyaml==6.0.3 httpx[http2]==0.28.1`; `ARG BATS_COMMIT=3bca150ec86275d6d9d5a4fd7d48ab8b6c6f3d87` with `git -C /tmp/bats-core rev-parse HEAD` checked before `install.sh`; the image rebuilt cleanly from it.

## Rejected dissent payloads

None: 0 schema-rejected payloads in `adversarial-audit.json` (`rejected_count: 0`, no rejected sidecar); no fourth run.

## Residual observations (not findings)

- `bash_mount_refs` remains a text heuristic; obfuscated commands (variables, base64) evade it. The after-the-fact hashes (`mount_integrity`, `integrity_clean`) are what the report should cite; the list is for triage.
- The accepted risks of round 1 stand: the agent under test can read its own credentials inside the container (DEC-0411; sweep `bd-xj75c`), and the hidden tests sit in a public repository with `WebFetch` available (`bd-eriso`, DEC-0493).
- 36 pre-existing bare `! cmd` assertions in `evals/tests/` that are not the last line of their test can never fail (`bd-mohlw`, Sprint 259); the new cases end theirs in `|| false`.

## Security checklist

Credential handling (no secret in argv, capture, log or committed file) ✓ · container isolation ✓ · sandbox git/gh isolation ✓ · hidden material never materialised, leak guards ✓ · path traversal and symlink guards (mount library, validator, freeze, envelope copy, mount hashes) ✓ · atomic writes ✓ · Python `-I` ✓ · supply chain (base image digest, yq sha256, npm exact, pip exact, bats commit) ✓ · measurement integrity (envelopes copy-once with sha256, eval/-first, mismatch recorded; mount hashes; arm grammar) ✓ · spend ceiling (assumed-cap charge) ✓.

## Verdict

APPROVED — Sprint 258 is complete; Sprint 259 (the frozen task suite and the grader) may begin.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-258","ts":"2026-10-15T03:45:00Z"} -->
