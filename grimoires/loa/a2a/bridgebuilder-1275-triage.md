# Bridgebuilder pass on PR #1275 (cycle-127): triage

- **Run.** `bridgebuilder-20261007T193359-e8bf`, 2026-10-07T19:33:59Z, on `c2ef7581`, `BRIDGEBUILDER_MODEL=codex-headless`, two voices planned and both answered: anthropic/claude-headless (Bedrock) and openai/gpt-5.5-pro; the google voice was **not planned** (`agy opt-in off (hounfour.headless.agy_opt_in)`) — the first production run of FR-1: verdict quality **APPROVED 2/2 voices, chain ok**, where #1274 ran DEGRADED 2/3 on the same host. Consensus: 19 items — 1 HIGH_CONSENSUS, 2 DISPUTED, 0 blocker; BB's verdict REQUEST_CHANGES on its F-001 (refuted below).
- **Posted.** Three PR comments (`[1/3]` claude-headless, `[2/3]` gpt-5.5-pro, `[3/3]` consensus) plus the Verdict Quality line; local copies in `~/.cache/loa/cycle-127/bb-1275/`.
- **Budget.** One pass, per the standing directive. Fixes land as round r251-6; CI re-runs; no second pass.

## Rulings

| ID | Sev | Where | Title | Ruling | Action |
|---|---|---|---|---|---|
| BB-001 | MEDIUM | `.claude/adapters/loa_cheval/config/loader.py` | Unconditional group-writable refusal silently disables the opt-in on umask-002 hosts after every checkout | REAL — MEDIUM | FIX (V1): a correct user-private-group exception in all three readers (file gid = owner's primary gid, group name = user name, no supplementary members); shared primary groups and world-writable stay refused. The r251-5 strict rule would have read Ubuntu UPG hosts back to off after every checkout. |
| BB-002 | LOW | `.claude/adapters/loa_cheval/config/loader.py` | Trust check stats the path after the content was read (TOCTOU window) | REAL — LOW | FIX (V3): fstat the opened descriptor (Python, TS); bash compares `stat -L` before/after the read. |
| BB-003 | LOW | `.claude/adapters/loa_cheval/config/loader.py` | Project-alias overlay for agy routing uses the unanchored cwd walk the opt-in read was anchored away from | REAL — LOW | FIX (V4): the provider-map overlay anchors to the same install root as the opt-in read. |
| BB-004 | LOW | `.claude/adapters/cheval.py` | `_plan_around_agy` rebuilds `ResolvedChain` by enumerating fields instead of `dataclasses.replace` | REAL — NIT | FIX (V8): `dataclasses.replace`. |
| BB-005 | LOW | `.claude/adapters/loa_cheval/config/loader.py` | An alias on a parent of the opt-in path reads as absent with no diagnostic in all three readers | REAL — LOW | FIX (V5): an alias/non-mapping ancestor of the key WARNs once in all three readers (value stays off). |
| BB-006 | LOW | `.claude/adapters/loa_cheval/config/loader.py` | Python no-PyYAML fallback shells `yq eval` without the yq-flavour check the bash lib applies | REAL — LOW | FIX (V6): the Python no-PyYAML fallback applies the yq-flavour check. |
| BB-007 | LOW | `tests/unit/agy-gate-conformance.bats` | AGC-19/AGC-21 skip only on missing `npx`; a missing `tsx` fails opaquely | REAL — LOW (the CI failure) | FIXED by the lead: the TS leg runs the BB skill's pinned `node_modules/.bin/tsx` and skips with a clear message when it is absent — `npx --no-install tsx` on a bare runner asked to fetch a release and printed nothing (Shell Tests: AGC-19/AGC-21). |
| BB-008 | LOW | `.claude/adapters/tests/test_claude_headless_cont` | Cross-test imports of private helpers couple test modules | DECLINED | test-module coupling through a private helper import is the repo's existing pattern; a shared `tests/_helpers` module is a later tidy-up. |
| BB-009 | LOW | `.claude/checksums.json` | Checksum manifest tracks volatile runtime artifacts (pre-existing) | DECLINED (pre-existing) | `.claude/checksums.json` is the System-Zone lint manifest; which generated artefacts it tracks predates the cycle — bead-worthy tidy-up, not this PR. |
| BB-010 | LOW | `.claude/adapters/cheval.py` | 'Both rungs set' effort warning fires for HTTP entries whose `extra.effort` is never read | REAL — LOW | FIX (V7): the 'both rungs set' WARN only for CLI entries. |
| BB-011 | SPECULATION | `.claude/defaults/model-config.yaml` | 936K HTTP bound now shipped in framework defaults while keyless hosts still gate on the under-counting heurist | NOTED (speculation) | keyless hosts do not use the HTTP route; the headless route carries no HTTP ceiling (the CLI pre-flight is the backstop, mapped to the context-limit class); bd-c2rd tracks the estimator. |
| BB-012 | PRAISE | `.claude/scripts/lib/agy-gate-lib.sh` | One routing predicate across three runtimes with adversarial YAML conformance | PRAISE | — |
| BB-013 | PRAISE | `.claude/adapters/tests/test_ceiling_probe_cli_tr` | Probe test suite is fail-closed against live spend | PRAISE | — |
| BB-014 | PRAISE | `tools/ceiling-probe-live.py` | Catalog writer validates provenance, dry-runs with real kwargs, and re-parses before replace | PRAISE | — |
| BB-015 | PRAISE | `.claude/adapters/cheval.py` | MODELINV envelope stays truthful and disjoint under the gate | PRAISE | — |
| BB-016 | HIGH | `.claude/adapters/cheval.py:1815` | Empty planned chain can crash after agy filtering | REFUTED (claimed HIGH) | `_plan_around_agy` returns an all-agy chain WHOLE (`if len(agy) == len(chain.entries): return chain, []`), and `kept` is non-empty whenever `skipped` is; the agy-alone path ends in the adapter's INVALID_CONFIG refusal (pinned by `test_cli_only_google_voice_is_agy_alone_and_refuses`). V9 adds a regression test asserting the invariant and the no-IndexError refusal. |
| BB-017 | MEDIUM | `.claude/adapters/loa_cheval/config/loader.py:135` | Config permission check can crash on platforms without geteuid | REAL — MEDIUM (portability) | FIX (V2): `getattr(os, "geteuid", None)`; without it the mode check alone applies (the TS reader already guards `process.getuid`). |
| BB-018 | LOW | `.claude/checksums.json:4` | Generated checksum file includes volatile runtime artifacts | DECLINED (dup of 9) | — |
| BB-019 | PRAISE | `.claude/adapters/tests/test_agy_chain_walk_opt_i` | Good separation of planned versus refused agy hops | PRAISE | — |

**Counts.** FIX 9 (BB-001, 002, 003, 004, 005, 006, 007, 010, 017), REFUTED 1 (BB-016 — the only HIGH), DECLINED 3 (BB-008, 009, 018), NOTED 1 (BB-011), PRAISE 5.

## Round r251-6 outcome

Committed as `263a8d4c` (pushed). One Opus 5.5 implementer in `wt-127-12`; the lead fixed BB-007 directly (the Shell Tests failure), regenerated the artefacts, REPO-MAP and checksums, rebuilt the dist, ran the suites and the lints.

| ID | Outcome |
|---|---|
| BB-001 | **Fixed (V1).** `_config_untrusted_reason` / `_agy_config_untrusted` / `agyConfigUntrustedReason`: a group-writable config is trusted only when its gid is the owner's primary gid, the group is named like the user and has no supplementary members (`pwd`/`grp`; `getent group` + `id -un`; `execFileSync('getent')` + `os.userInfo()`); world-writable and foreign owner stay refused; AGC rows for a private group (on), a group with a member (off), a differently named group (off). |
| BB-002 | **Fixed (V3).** Python opens once and `fstat`s the descriptor it reads; TS `openSync` + `fstatSync` + `readFileSync(fd)`; bash compares `stat -L` before and after the yq read. |
| BB-003 | **Fixed (V4).** The provider-map overlay reads from the same install root as the opt-in; a planted ancestor alias no longer changes `routes_to_agy`. |
| BB-004 | **Fixed (V8).** `dataclasses.replace(chain, entries=kept)`. |
| BB-005 | **Fixed (V5).** An alias / non-mapping ancestor of the key WARNs once in all three readers ("the opt-in cannot be read; write the mapping inline"); conformance rows pin the WARN. |
| BB-006 | **Fixed (V6).** The no-PyYAML fallback applies the yq-flavour check (shim test). |
| BB-007 | **Fixed (lead).** The TS leg runs `.claude/skills/bridgebuilder-review/node_modules/.bin/tsx` and skips with a clear message when it is absent. |
| BB-010 | **Fixed (V7).** The "both rungs set" WARN only for CLI entries. |
| BB-016 | **Refuted (V9).** Probe: an all-agy chain is returned whole (identity), `kept` is non-empty whenever `skipped` is; a Google voice under `cli-only` with no fallback ends in the adapter's INVALID_CONFIG refusal with no IndexError — regression tests added. |
| BB-017 | **Fixed (V2).** `getattr(os, "geteuid", None)`; without it the mode check alone applies. |
| BB-008, 009, 018 | Declined (test-module coupling is the repo's pattern; the checksum manifest's contents predate the cycle — tidy-up beads later). |
| BB-011 | Noted (keyless hosts do not use the HTTP route; bd-c2rd). |

**Suites, real tree, serial (ok / not ok / skip):** adapters pytest 3078 / 0 / 6 (279 subtests); bats agy-gate-conformance 26/0 twice, run-preflight 22/0, loa-status-providers 13/0, adversarial-review-companion (filtered) 47/0, flatline-tertiary-agy-opt-in 5/0; Bridgebuilder 837/838 (`persona.test.ts` = KF-036); lints clean; `regen-model-artifacts --check` drift-free, dist fresh; `regen-checksums --check` changed=0.

**Not re-run:** the directive allows one Bridgebuilder pass; CI re-runs on `263a8d4c` and the merge follows CI.
