# Sprint 282 (cycle-137 sprint-2) — goal validation (Task 2.E2E)

**Written:** 2026-10-28 by the lead at `COMPLETED`. **Final Sprint 2 head:** 03f910129 (last System Zone change c31089280; 03f910129 is the audit's test-only strengthening; the commits after it — 2832bacce, e4dacaec9, 3215c141f — are `grimoires/` docs and the ledger). Measurement protocol for every number: `hyperfine -N -i --warmup 3 --runs 10`, mean ± σ, host `fukuoka` (Linux 6.16, bash 5.2, mawk 1.3.4, jq 1.7, mikefarah yq 4.44.1, Python 3.13), serial on the idle host unless stated; mirrors in REAL directories.

## G-2 — the six beads closed with commit + test, or the deferral row

| Bead | FR | Red → fix | Tests | red-test-check | Status |
|---|---|---|---|---|---|
| bd-atk7q | FR-2 KF parser shape C | 980013b87 → 2944f4b55 | `kf-surface.bats`, `grimoire-index.bats` (9 new cases; mawk + busybox byte-identical; BWK UNVERIFIED → bd-aceil) | VERIFIED | closed provisionally |
| bd-1mfm7 | FR-5 decisions cache | 87f5ee362 → 937b87ee0; lead D-5.3 3d8e520a2 → e5f751ac0 | `grimoire-index.bats` 46 cache cases (+2 FIFO / hard-link at 03f910129) | VERIFIED ×2 | closed provisionally |
| bd-gv5jf | FR-3 loa-status one yq + agy memo | 462c8b0dd → 67276f62a; 92dfbbc34 → 268bc2f1b; review fixes 57e38f8c0 → c31b9e03c, c69059546 → c31089280 | `loa-status-providers.bats` LSP-9a; `agy-gate-conformance.bats` AGC-27 … AGC-36 | VERIFIED ×4 | closed provisionally |
| bd-h5tcn | FR-4 profile-lib cached_keys | cbdb5ef96 → cb46eabac | `profile-lib.bats` PL-20 … PL-25; `perf-spawn-budget.bats` karpathy target | VERIFIED | closed provisionally |
| bd-wctli | FR-6 test-suite runtime | 55f82c534 (single commit, exempt) | TAP set identical ×7; negative control per shortened hold; floor 667 s median → DEC-1130; CMP-55 exempt DEC-1131 → bd-rq6gk | N/A (exempt) | closed provisionally |
| bd-09z1i | FR-7 verify-chains | d1e49e920 → bf96f91cb | `audit-envelope-verify-chains.bats` 18; `test_audit_verify_chains.py` 15; six store-mutation schedules = two oracles | VERIFIED ×2 (bats, pytest) | closed provisionally |

No deferral row was needed. Every red commit fails only its own cases and every fix commit is green (`~/.cache/loa/cycle-137/logs/rtc-282*.log`, `rtc-282-r1fix.json`, `rtc-282-r2fix.json`); manifests regenerated under the bounded marker at every System Zone commit, `check-loa.sh` All checks passed at each fix and at c31089280.

## Gates

| Gate | Verdict | `reviewed_head` | Rounds | Dissent |
|---|---|---|---|---|
| `/review-sprint sprint-2` | All good — 0/0/1/5 | 03f910129 | r1 CHANGES_REQUIRED (agy memo whole-second window → AGC-33, DEC-1132) · r2 CHANGES_REQUIRED (ctime, flaky stamp, 4 advisories → AGC-34/35/36, DEC-1133) · r3 All good (lead-only, DEC-1134) · r4 verify-only on the audit's test-only commit (DEC-1138) | run 1: primary only (companion timeout, KF-037 class), 1 BLOCKING; run 2: 2/2, 6 findings; 0 rejected |
| `/audit-sprint sprint-2` | APPROVED — 0/0/2/3 | 03f910129 | one round | run 3: 2/2, status clean, 8 companion findings (MED-001 pre-existing → bd-j34zb; MED-002 fixed 03f910129; 3 LOW pre-existing → beads; 2 refuted by probe, DEC-1137); 0 rejected |

Circuit breaker after the sprint: cycle 3/20 (rounds recorded), same_issue 1/3, no_progress 0/5; never tripped.

## Measurements (lead, same session, old mirror 747b5db0d vs new)

| Target | Old | New | Δ | Cache state / note |
|---|---:|---:|---:|---|
| `loa-status.sh` (human, project root) | 1 124 ms | 1 020 ms | −104 ms | FR-3; one yq for the six ceiling reads + memoised agy read; host load 5–6 (both mirrors measured under it) |
| `grimoire-index.sh` warm | 826 ms | 196 ms | −630 ms | FR-5; live `.run/perf-cache` (tightened 775 → 755 by D-5.3, so the cache went from inert to active) |
| `grimoire-index.sh` cold (paired) | — | +24 ms | ≤ +40 | FR-5 AC; snapshot + key + write |
| `grimoire-index.sh` warm (fixture) | — | 310 ms | ≤ 650 | FR-5 AC |
| karpathy hook warm path | — | 0 yq | — | FR-4; trace shows no yq on the warm cache path; spawn-budget target added |
| `audit-envelope.sh` verify-chains, 5-chain fixture root | — | −1.15 s | ≥ 100 ms | FR-7; python3 processes 5 → 1 |
| `adversarial-review-companion.bats` serial (`bats -T`, median of 3) | 872 s | 667 s | −205 s | FR-6 floor (≤ 300 s unreachable by test edits → DEC-1130); TAP set identical ×7 |
| `block-destructive-bash.bats` corpus | 95 s | 62 s | −33 s | FR-6; corpus once per file (`setup_file`) |

Re-baseline on 55f82c534 under load 5–6 (`~/.cache/loa/cycle-137/logs/rebaseline-55f82c534.tsv`): grimoire-index 826 → 195.5 ms, stop-runmode 23.6 → 7.1, kf-surface 14.9; loa-status 1 277 ms and repo-map 1 342 ms were load-inflated (the OLD mirror measured 1 124 ms too). **Idle-host re-baseline on the final head:** `~/.cache/loa/eso-loop/rebaseline.sh` on 03f910129 (copy: `evidence/probes/rebaseline-final.tsv`), 2026-10-28 ~09:20Z, host load 6–8 from OTHER sessions on the machine (not idle — `loa-claude-ws-28` and `mirror` peers busy; the lead has no control over them). Means in ms, baseline = the 2026-10-27 loop baseline:

| Command | Baseline | Final (loaded) | Note |
|---|---:|---:|---|
| repo-map-gen | 4658.4 | 1063.7 | gain holds under load |
| grimoire-index | 1818.9 | 258.8 | live cache active (D-5.3); 195.5 under load 5–6 earlier |
| loa-status | 899.0 | 2441.3 | LOAD-INFLATED: the same-session paired A/B (old 747b5db0d mirror 1124 ms vs new 1020 ms, −104 ms, both under load 5–6) is the FR-3 measurement; the old mirror measured 1277 ms under the earlier re-baseline too |
| beads-health / upgrade-health / cheval-help | 207.6 / 214.8 / 128.6 | 270.2 / 232.9 / 123.3 | untouched rows: host noise |
| SessionStart kf-surface | 487.6 | 19.6 | |
| SessionStart run-state / context-class / decisions | 29.7 / 24.2 / 17.1 | 24.7 / 30.2 / 22.6 | untouched rows: host noise |
| PreToolUse implement-gate / notes-size / zone / destructive-bash | 35.4 / 21.5 / 12.3 / 15.5 | 28.5 / 25.6 / 15.7 / 21.6 | untouched rows: host noise |
| PostToolUse karpathy | 96.0 | 60.4 | FR-4: no yq on the warm path |
| Stop run-mode-stop-guard | 23.6 | 17.0 | |

Reading: every touched row keeps its gain except the absolute `loa-status` figure, which the PRD's protocol does not use (it requires old and new mirrors in the SAME session — done, −104 ms). An idle re-run is attempted before S-8 if the peers go quiet; otherwise this table stands with its load caveat (class S, recorded in Part 2).

## Whole-head parity gate (sdd.md § 7)

Old mirror from the Sprint 1 final head 747b5db0d vs new mirror from the working tree, every touched entry point: `loa-kf-surface.sh` (stdout/stderr/rc), `grimoire-index.sh` (`--tsv`, `--json`, `--validate`, cold and warm), `loa-status.sh` (human with ages/sizes normalised, stderr, rc, `--json` modulo time keys and the mirror path), `run-preflight.sh` (human, stderr, rc, `--json`), `karpathy-surgical-diff-check.sh` (three payloads incl. the state dir) — all identical. The two agy callers were re-run after each review fix (c31b9e03c, c31089280): identical; the live config is read once for two `agy_opted_in` calls.

## G-4 — full `tests/unit` under PRD R-4

| Run | Head | Result | File |
|---|---|---|---|
| Full `tests/unit` TAP (Sprint 281 loop head, baseline) | c0d41f5e3 | 7224 tests, 7220 ok, 133 skipped, 4 not ok (3 KF-034 + load-induced CMP-37) | `a2a/sprint-281/evidence/tap/unit-final-c0d41f5e3.tap` |
| Full `tests/unit` TAP (last head before the review fixes) | 8d63417b0 | 7309 planned, 7306 ok, 3 not ok (exactly the KF-034 `semver evidence` list), 135 skipped — the two skips absent from the 281 head are this sprint's host-conditional awk tests (`BWK awk absent`, `gawk absent`; DEC-1135) | `evidence/tap/unit-8d63417b0.tap` |
| Full `tests/unit` TAP (final head) | 03f910129 | 7315 planned (six new cases since 8d63417b0), 7312 ok, 3 not ok = exactly the KF-034 `semver evidence` allowed-failure list (identical on `main`), 135 skipped — skip NAMES identical to the 8d63417b0 run (0 new, 0 gone); rc 1 from the three allowed reds | `evidence/tap/unit-03f910129.tap` |

Covering suites at the final head: `agy-gate-conformance.bats` 36/36, `grimoire-index.bats` 48/48, `loa-status-providers.bats` 17/17 (the 273/273 covering set of the landing re-run per fix); security pytest 40 passed; `test_audit_verify_chains.py` 15 passed.

## Meter checkpoint

`.run/cost-ledger.jsonl` rows since 2026-10-27: 53 at the Sprint 282 audit, `cost_usd` 0 (every dissent and Flatline run on subscription routes: codex-headless, claude-headless); Bridgebuilder rounds likewise. Implementers (four Opus 5.5 Claude Code agents) are not metered in the ledger; wall time ≈ 2 h 10 min from dispatch (03:33Z) to the last patch. Cap USD 30: untouched.

## External, unversioned artefacts (sha256 at `COMPLETED`)

Copies of the TAP, red-test-check logs, dissent envelopes and probes live under `a2a/sprint-282/evidence/`; the ship scripts are copied at S-4 with their digests in Part 2.

| File | sha256 |
|---|---|
| `~/.cache/loa/cycle-137/logs/adv-audit-282.json` | `74b3c9c85db247793eebfeca308a8f22facfa2d97482c71c7c9687869f509447` |
| `~/.cache/loa/cycle-137/logs/adv-audit-282.log` | `93405784249e22486d93ce27f05665558d1a6e6bef6399208ddc56948f287994` |
| `~/.cache/loa/cycle-137/logs/adv-review-282-r2.json` | `9f62fe792dd91a9c55caba73cc80d4e24d1ad410ec5fe1de1e698199dd712807` |
| `~/.cache/loa/cycle-137/logs/adv-review-282-r2.log` | `a5d1f824eb01deebb8e6513c1fecf7375182182ed84da13c2e621c2a72d265c6` |
| `~/.cache/loa/cycle-137/logs/adv-review-282.err` | `600581bf730dd4884ddfc4a711ca06ac952db0e2721688dbb52b66dc34e9ec02` |
| `~/.cache/loa/cycle-137/logs/adv-review-282.out` | `127dbd5baea13ed49c0d27d9263673805fab275fb549e5afae114c2823a349c8` |
| `~/.cache/loa/cycle-137/logs/auditor-282-draft.md` | `0fe6e121e2167007807469e79548e5ba64c493398c4f1622dd1b72b8ba675831` |
| `~/.cache/loa/cycle-137/logs/bb-1309-r1.log` | `322c5824c179ed6854c8cc983f3a65482df479b38869fe1ea724deab4e92fd02` |
| `~/.cache/loa/cycle-137/logs/diff-audit-282.patch` | `040c9bdecf5ccf2f47d845b3555038d1573f2c9f62ce7f2cdc29a334db285961` |
| `~/.cache/loa/cycle-137/logs/diff-r2-fix.patch` | `28502922f53f3c29454311d53a0324ce878fc3a5db4a83e80c00b472eb980857` |
| `~/.cache/loa/cycle-137/logs/engineer-feedback-282-draft.md` | `8a26bbbeb47e0168e97764a27c3183e13d923959d08bf7b60d3e91772588c440` |
| `~/.cache/loa/cycle-137/logs/rebaseline-55f82c534.tsv` | `a9401e2a60bcf66dcb50c04468b446954d169b70356b0b7d668721c9f8995e75` |
| `~/.cache/loa/cycle-137/logs/rtc-282-bats.log` | `3c11ef9ce348793273b3b0f6baff6ddf830f795ccb1e8cc69a51da0d0c021c0d` |
| `~/.cache/loa/cycle-137/logs/rtc-282-r1fix.err` | `eb922d504ef39934922c080b2a720809412e7fde74cd9c4fdb2c14d26b4e4854` |
| `~/.cache/loa/cycle-137/logs/rtc-282-r1fix.json` | `b0e74d273d640b1c035b7f0b9dc03e2973466e166628e8aa7f80038061ad0088` |
| `~/.cache/loa/cycle-137/logs/rtc-282-r2fix.err` | `a8c23d2ea4ccd7f9385b45ad8056c55e13b35d4ac7dc0b1e59be8378991d422f` |
| `~/.cache/loa/cycle-137/logs/rtc-282-r2fix.json` | `accf2149e3bb9313cb6bed05dd54cdf3597fdae486d0af2e2a6d37b2f7561728` |
| `~/.cache/loa/cycle-137/logs/rtc-282.log` | `e510ed7e8e4836dcea0e92ec17a2f4064a90f7a263ed71f2fd286f62d171d9d8` |
| `~/.cache/loa/cycle-137/logs/unit-8d63417b0.tap` | `b9ae0e9b93743b3fadfc847fb28043934471ffc687e31d35b8a32131206be2a2` |
| `~/.cache/loa/cycle-137/scripts/agc33-red.py` | `b86515f364df27d2701db8b4a21255244559b34ef88315c118a7d4f902375df5` |
| `~/.cache/loa/cycle-137/scripts/agc34-red.py` | `661eb1eb389a42b37c06df4becb5e5c01f14594312fad1b3e5c23072ca6a9546` |
| `~/.cache/loa/cycle-137/scripts/agy-r2-fix.py` | `beadbb2d59ac5329f86469547d6166813d6fc581302761e945d8efe5d5557a88` |
| `~/.cache/loa/cycle-137/scripts/agy-r2-tests-settle.py` | `da22dfc4db8fefd158e5bfc4408d2c95d89a925c49156da9c65b6b68b098d67c` |
| `~/.cache/loa/cycle-137/scripts/audit-tests-282.py` | `50dd3fdcbc267e105ee486cd64bccb7786745c056d79d9aafdaa484ecec5c43a` |
| `~/.cache/loa/cycle-137/scripts/cache-fifo-probe.py` | `bd9f75ffc868128d51dcffa040f47fb68c868e3e70c3a59ca5b493607634959a` |
| `~/.cache/loa/cycle-137/scripts/dec-batch.sh` | `ce1bc934341f059f36d2dc1ca07743b124655b527cd843700cd9c974d152ae8d` |
| `~/.cache/loa/cycle-137/scripts/fill-282.py` | `94529b2f68e4233c7ec68a6e346a71b5ea7625ad07032996f6a7f9c079f87f3f` |
| `~/.cache/loa/cycle-137/scripts/fill-d-section.py` | `ff612a29665cadb95f76a1cff063f7ef53995916f5acfedc48d3513aad73780e` |
| `~/.cache/loa/cycle-137/scripts/fill-pr-body.py` | `8d4ccc9c56fdd0ea51bfaec7b3c5e114603e3b46610c84f69e8623f9ecd73671` |
| `~/.cache/loa/cycle-137/scripts/fill-ship-inputs.py` | `26a8ccade549beac0edc8dd673d0d2475fac0fe0555adc2fe1d3ba9e6d446b24` |
| `~/.cache/loa/cycle-137/scripts/land.sh` | `f59e665ab71fcf903db3fa515651e9459d05b7e87ff85c6939c2d2d347412a02` |
| `~/.cache/loa/cycle-137/scripts/mirror-ls.py` | `2ed075b1000374754e1c565786b2e7dc602ac14d499e23d4e5b426fe0b951a48` |
| `~/.cache/loa/cycle-137/scripts/notes-gates282.py` | `cb1a45d886145964c812a50155d2a5487fe3325237305370428939bfbee5415e` |
| `~/.cache/loa/cycle-137/scripts/notes-landing.py` | `45172bb52ca0d0ecd0d12a5a8172a2260be4983293a90c0f99ae057244304c71` |
| `~/.cache/loa/cycle-137/scripts/prd-1.1.py` | `1acb71f15681954c150bf293a3b4c56c8609a58696be0fb2a5df29db52ed4e26` |
| `~/.cache/loa/cycle-137/scripts/regen-manifests.sh` | `f8af15f901125358faae64e55d1b3b3e13ebea68d6b38f833e1b1f77402dbbc5` |
| `~/.cache/loa/cycle-137/scripts/review3-postlude.py` | `3cf5bb14e6c9b828aba266994c263458ed8f516fe3afe82b384e0ed0d869e65f` |
| `~/.cache/loa/cycle-137/scripts/run-start-137.sh` | `67af1d99a9b2e155c2069f471cf5d7838b5821f4ea7afe7e5f3806ee2f30b234` |
| `~/.cache/loa/cycle-137/scripts/sdd-1.1.py` | `e96efeb45594ad27f66b1e8509d9ef0c184f4fe6c319c9a0c6470c5dd9b62ca8` |
| `~/.cache/loa/cycle-137/scripts/sprint-1.1.py` | `f53ca92f1e87114b54f4248345f8a78ddf3f430d97bd609d0e50974d148ed8df` |
| `~/.cache/loa/cycle-137/scripts/write-sprint.py` | `9e32d47a0b6307a67b5138bddf7d7649d736277200517cd6927f03f59cc9ce69` |
| `~/.cache/loa/cycle-137/spec-dec-audit.json` | `9f6ceaf28d1fa6dabb5be4cf2c811b5dacc60bc7e25506173bef7a84e981ae93` |
| `~/.cache/loa/cycle-137/spec-dec-r1fix.json` | `7c2f4490237973788c48e23daacb596d2d0d8d221bbf3e0a3cb01378a21a4489` |
| `~/.cache/loa/cycle-137/spec-dec-r2.json` | `8584447061033857ecbfe3099980d42ce9274ae5420234d2d056c2c1e4ccb96c` |

## Part 2 — the Ship section (appended by S-8)

{PART_2}
