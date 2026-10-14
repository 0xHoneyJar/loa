# Loa gate yield, cycles 124 to 128 (2026-09-17 to 2026-10-14)

Read range: `main` at `864069f2` (v2.0.0-rc.4). The git log covers 241 commits since 2026-09-17, with merges 867cbc37 (#1266), 5f4a58a5 (#1269), 2079e719 (#1270), e70f2838 (#1274), 2913c026 (#1275), 76e7650b (#1276), 6056a372 (#1279) and 864069f2 (#1280).

Sources were the gitignored a2a records present in this clone and the read-only `.run` ledgers. Paths below are relative to `grimoires/loa/` unless they start with `.run/`, `.claude/` or `~`.

Abbreviations used throughout:
- **PV** is the primary dissent voice, gpt-5.5-pro through codex-headless.
- **CV** is the companion voice, claude-headless.
- **c/h/m/l** are critical, high, medium and low finding counts.

## 0. Two facts that change how the rest reads

**The companion voice is Fable 5.1, the same model as the reviewer and auditor.**
- The cost ledger prices all 629 claude-headless rows as `claude-fable-5-1` or `global.anthropic.claude-fable-5-1` (`.run/cost-ledger.jsonl`, aggregated: 625 Fable rows, `pricing_source: cli_reported` 629).
- The MODELINV ledger records only `anthropic:claude-headless` with no resolved model (`.run/model-invoke.jsonl`, 629 rows).
- So "two-voice cross-model dissent" in this period means one OpenAI model plus a fresh-context copy of the gate model. Most dissent findings came from the CV (sections 1 and 2). This is the strongest measured effect in the record: an independent fresh context of the same frontier model, not model diversity.

**Implementer and gate were the same model in some sprints.**
- In sprints 247 and 248 the Fable 5.1 lead implemented and Fable 5.1 reviewed and audited (`a2a/sprint-247/reviewer.md:4`, `a2a/sprint-248/reviewer.md:4`).
- From sprint 249 on, Opus 5.5 subagents implemented and Fable 5.1 gated (`a2a/sprint-249/reviewer.md:4`, `a2a/sprint-251/reviewer.md:4`, `a2a/sprint-252/reviewer.md:3`, `a2a/sprint-253/reviewer.md:3`, `a2a/sprint-254/reviewer.md:3`).
- So "same-model review" is literally true only for 247 and 248. Later it is same-family.

## 1. Per-sprint table

| Sprint (cycle) | Implementer | Review r1 | Review final | Audit r1 | Audit final | Dissent voices | What the 2nd voice added | Bridgebuilder |
|---|---|---|---|---|---|---|---|---|
| 247 (126) | Fable 5.1 lead (`a2a/sprint-247/reviewer.md:4`) | CHANGES_REQUIRED 0/3/1/2 (`engineer-feedback-round-1.md:60`); r2 CHANGES_REQUIRED 0/1/0/0 (`engineer-feedback-round-2.md:42`) | r3 APPROVED 0/0/1/2 (`engineer-feedback.md:46`) | APPROVED 0/0/0/3, one round (`auditor-sprint-feedback.md:122`) | same | Single voice, PV only, chunked 6 ways after the whole diff saw 24K of 77K tokens (`engineer-feedback-round-1.md:53`) | No second voice | Rolled into PR #1274 |
| 248 (126) | Fable 5.1 lead (`a2a/sprint-248/reviewer.md:4`) | CHANGES_REQUIRED 0/24/190/687 over 39 two-voice runs (`engineer-feedback-round-1.md:1219`) | APPROVED 0/0/1/3 (`engineer-feedback.md:63`) | APPROVED 0/0/1/4; dissent not re-run because of the 3-run cap (`auditor-sprint-feedback.md:20,145`) | same | Two-voice in the final runs; earlier runs lost CV to KF-037/038 | CV found 19 of 24 review HIGHs; 2 joint, 1 PV only, 2 the reviewer's own (`engineer-feedback-round-1.md:22,110,136,321,358`). Final envelopes: review 62 findings (CV 57, PV 5); audit 92 (CV 87, PV 5) | Rolled into #1274 |
| 249 (126) | Opus 5.5 subagent (`a2a/sprint-249/reviewer.md:4`) | APPROVED 0/0/1/5; A/B criterion waived (`engineer-feedback.md:101`) | same | APPROVED 0/0/2/4 (`auditor-sprint-feedback.md:187`) | same | Two-voice, all 7 chunks | CV raised all 4 "AC unmet" BLOCKINGs, rated REAL (`review-dissent-run-1-verifier-B.md:11,15,19`). All 3 PV BLOCKINGs were refuted (`review-dissent-run-1-verifier-A.md:8,14`) | Rolled into #1274 |
| 250 (126) | Opus 5.5 for 4.1 to 4.6, lead for 4.7, 4.8 and E2E (`a2a/sprint-250/reviewer.md:4`) | CHANGES_REQUIRED 0/2/3/7 (`engineer-feedback.md:11`) | APPROVED 0/0/1/4 (`engineer-feedback.md:84`) | 3 audit dissent runs, rounds r250-6 to r250-9 (`reviewer.md:12-23`) | APPROVED; found 0/0/1/5, open 0/0/0/2 (`auditor-sprint-feedback.md:28-33,262`) | Two-voice on every chunk, 3 review and 3 audit runs | PV found all 4 audit-run-1 HIGHs (`audit-dissent-triage-run-1.md:16-21`). CV found the dead `ask` and the non-canonical path bypass (section 2) | #1274: FIX 7, DOC 1, REFUTED 1, DECLINED 3, beads 4, noted 5 (`bridgebuilder-1274-triage.md:30`) |
| 251 (127) | Opus 5.5, 1 to 3 per round (`a2a/sprint-251/reviewer.md:4`) | CHANGES_REQUIRED 1 HIGH / 3 MED / 7 LOW (`reviewer.md:103`) | APPROVED 0/0/1/3; trailer mislabelled `sprint-1` (`engineer-feedback.md:138`) | 2 audit dissent runs, rounds r251-4 and r251-5 | APPROVED 0/0/1/4 (`auditor-sprint-feedback.md:253`) | Two-voice everywhere | PV BLOCKINGs refuted in both review runs (`review-dissent-triage-run-1.md:11`, `run-2.md:11`) | #1275: FIX 9, REFUTED 1, DECLINED 3, NOTED 1 (`bridgebuilder-1275-triage.md:29`) |
| 252 (128) | Opus 5.5 x3 (`a2a/sprint-252/reviewer.md:3`) | CHANGES_REQUIRED 0/0/4/1 (`engineer-feedback-r1.md:89`) | APPROVED 0/0/1/0 (`engineer-feedback.md:63`) | APPROVED 0/0/2/4, one round (`auditor-sprint-feedback.md:131`) | same | Two-voice | CV was the source of all 3 changes-required items; the PV BLOCKING was refuted (`engineer-feedback-r1.md:70-71`) | Rolled into #1279 |
| 253 (128) | Opus 5.5 x2 (`a2a/sprint-253/reviewer.md:3`) | CHANGES_REQUIRED 0/1/1/8 (`engineer-feedback-r1.md:110`) | APPROVED 0/0/0/0 (`engineer-feedback.md:79`) | CHANGES_REQUIRED 0/1/6/8 (`auditor-sprint-feedback-r1.md:157`) | APPROVED 0/0/0/1 (`auditor-sprint-feedback.md:99`) | Two-voice | CV found the out-of-repo blind spot and the `--consumed-by` gap (`engineer-feedback-r1.md:90`) | Rolled into #1279 |
| 254 (128) | Opus 5.5 x3 (`a2a/sprint-254/reviewer.md:3`) | CHANGES_REQUIRED 0/0/1/7 (`engineer-feedback-r1.md:100`) | APPROVED 0/0/0/0 (`engineer-feedback.md:67`) | CHANGES_REQUIRED 0/1/3/3 (`auditor-sprint-feedback-r1.md:109`) | APPROVED 0/0/0/0 (`auditor-sprint-feedback.md:86`) | Two-voice | CV raised every review-round finding; PV raised none (`engineer-feedback-r1.md:80`) | #1279: 17 fixed, 4 refuted (`a2a/sprint-254/bridgebuilder-triage.md:9-33`) |
| bug-245 (125) | Not recorded in the a2a dir; NOTES says it was the lead's own cut (`NOTES.md:128`) | APPROVED, dissent clean (`NOTES.md:127`) | same | HIGH F-1 "ledger inode replaced without flock" (`NOTES.md:127`) | Fixed e577f66f | Single voice (`single_voice_call:true`) | No second voice. One rejected HIGH payload: "Spoofable BATS env enables arbitrary cost-report script execution" (`a2a/sprint-bug-245/adversarial-rejected-audit.jsonl`) | #1270: 3 fixed, 1 praise (`NOTES.md:129`) |
| bug-246 (125) | Not recorded | Dissent: 1 advisory | APPROVED | clean | APPROVED | Single voice | No second voice | #1270, shared with bug-245 |

**Earlier in the period (cycles 124 and 125), from trailers only:**

| Sprint | Review r1 | Audit r1 |
|---|---|---|
| 237 | 0/2/4/3 (`a2a/sprint-237/engineer-feedback.round-1.md`) | 0/1/9/15, executor confinement HIGH (`NOTES.md:220-222`) |
| 241 | 0/6/2/2, six fence predicate holes found by hand-built twins (`a2a/sprint-241/engineer-feedback-round1.md`; `NOTES.md:163`) | 0/1/1/4 |
| 242 | 0/1/3/2 | 0/0/1/3 |
| 238, 243, 244 | Approved in one round (trailers in each `engineer-feedback.md`) | Approved in one round |
| 235 | 0/5/9/9 from a five-lens panel; the PV dissent returned 0 findings on a 24K slice of a 400 KB diff (`NOTES.md:312`) | n/a |

## 2. HIGH and CRITICAL findings

There were no CRITICAL findings in the period. Columns: who caught it, outcome, and class.

| Finding (quoted or close paraphrase) | Cite | Caught by | Outcome | Class |
|---|---|---|---|---|
| unverified-zone flag computed once for the head | `a2a/sprint-247/engineer-feedback-round-1.md:22,24` | PV, and independently the Fable reviewer | Fixed 91838f70 | Fence gap |
| read, append, os.replace with no interprocess lock (ceiling.py) | `round-1.md:30,32` | PV, chunked | Fixed 58a0c2fc | Fence gap (concurrency) |
| premium multiplies already-floored costs | `round-1.md:38,40` | PV | Fixed 58a0c2fc | Test gap (correctness) |
| non-finite multiplier | `engineer-feedback-round-2.md:22,24` | PV on the round-1 fix | Fixed | Fence gap |
| 248 review: 24 HIGHs, e.g. `rejected_summary_check` "only proves the heading exists" and "/tmp/CLAUDE.md entered the review voice's context" | `a2a/sprint-248/engineer-feedback-round-1.md:22,768`; all fixed test-first (`engineer-feedback.md:60`) | 19 CV only, 2 joint, 1 PV, 2 Fable reviewer | All fixed | About 15 fence gaps (signal, lock, reaper), 4 security boundary, 2 test gap, 2 spec drift |
| 248 audit: workspace denylist (e1 DISS-C-001) | `audit-dissent-triage-run-1.md:18` | CV | Real, downgraded to MEDIUM, fixed | Security boundary |
| 248 audit: `agy -p <prompt>` on argv (e1 DISS-001, repeated as e2a DISS-001) | `triage:19-20`; `auditor-sprint-feedback.md:48,100` | PV | Real but pre-existing; MED-001, bead bd-ugmi. Earlier refutations rested on a false premise | Security boundary |
| long thresholds weaken prompt-injection containment | `a2a/sprint-249/audit-dissent-triage-run-1.md:15,32` | PV | Refuted | False positive |
| 250 review: missing `## AC Verification`; CHANGELOG gaps | `a2a/sprint-250/engineer-feedback.md:34-35` | Fable review | Fixed | Docs |
| 250 audit n5, `execution_mode` row | `audit-dissent-triage-run-1.md:16` | PV | Declined | Spec drift, judged by design |
| 250 audit n13, agy argv | `triage:17` | PV | Pre-existing, bd-ugmi | Security boundary (repeat) |
| 250 audit n17, config self-attest allow | `triage:18` | PV | Fixed, tighten-only | Security boundary |
| 250 audit n27, `AGENT_TYPES_FILE` | `triage:21` | PV | Real, downgraded to LOW, fixed | Security boundary |
| `{"decision":"ask"}` is an invalid PreToolUse output, pre-existing since cycle-050 | `a2a/sprint-250/audit-dissent-triage-run-1.md:48`; `audit-dissent-run-1-verifier-A.md:28,46` | CV, filed as MEDIUM, confirmed by an Opus verifier | Fixed r250-6 | Fence gap: a dead fence |
| Textual-prefix App-Zone test bypassed by `/proc/self/cwd`, `//`, `..` and symlinked roots | `audit-dissent-triage-run-2.md:14,35` | CV, MEDIUM | Fixed r250-7. That fix regressed inside-out symlinks; CV caught it in run 3 and r250-8 fixed it (`run-3.md:14`) | Fence gap |
| `${rel,,}` bash-4 expansion; under macOS bash 3.2 the gate fails open | `bridgebuilder-1274-triage.md:11,40`; `NOTES.md:121` | Bridgebuilder, both voices (HIGH_CONSENSUS); r250-8 introduced it after the last dissent run | Fixed 050dde35 | Fence gap (portability) |
| 251: agy hop ends the chain walk (n2) | `a2a/sprint-251/review-dissent-triage-run-1.md:12` | CV BLOCKING, Opus verifier HIGH | Fixed G1 | Spec drift |
| 251: units gap on the 936K bound (n27) | `triage-run-1.md:37,76` | CV; the verifier raised it to HIGH by a different mechanism | Fixed C7/C8 | Spec drift |
| Bedrock token throttle classified as a context limit on the headless route | `a2a/sprint-251/engineer-feedback.md:59` | Fable review; regression from round r251-2 | Fixed r251-3 | Test gap (correctness) |
| Empty planned chain can crash after agy filtering (BB-016) | `bridgebuilder-1275-triage.md:26` | Bridgebuilder | Refuted | False positive |
| jq `index([$x])` never matches (252 DISS-001 BLOCKING) | `a2a/sprint-252/engineer-feedback-r1.md:70` | PV | Refuted by a jq probe | False positive |
| chart-researcher holds Write while fetching arbitrary pages | `a2a/sprint-253/engineer-feedback-r1.md:26` | PV DISS-001 plus CV C-002, adopted by the Fable review | Fixed 30727c95 | Security boundary |
| `chart-unblock-probe.sh` is an arbitrary-execution path with a boundary that checks only the main tree's status | `a2a/sprint-253/auditor-sprint-feedback-r1.md:37` | Fable audit, with PV DISS-002 HIGH and CV C-007 | Fixed 8f7932b2 | Security boundary |
| Untrusted ledger text into planning context (253 audit DISS-001 HIGH) | `auditor-sprint-feedback-r1.md:137` | PV | Refuted in part; folded into MEDIUM-001 | Partial false positive |
| `red-test-check.sh` is an unbounded, credentialed execution path granted to the review role | `a2a/sprint-254/auditor-sprint-feedback-r1.md:33,90` | Fable audit. The review missed it, and the dissent filed it only as MEDIUM | Fixed befd511d | Security boundary |
| Configured red-test commands bypass the runner safety checks (RTC-001) | `a2a/sprint-254/bb-openai.md:10-12` | Bridgebuilder OpenAI voice, on a gap the audit fix left open | Fixed 3758ddd0 | Security boundary |
| Surface hook's jq `clean` regex is malformed (F-001) | `a2a/sprint-254/bb-anthropic.md:9-11`; `bridgebuilder-triage.md:25,31` | Bridgebuilder Anthropic voice | Refuted; regression test added | False positive |
| bug-245 audit F-1: ledger inode replaced without flock | `NOTES.md:127` | Fable audit | Fixed e577f66f | Fence gap (concurrency) |
| Spoofable BATS env enables arbitrary cost-report script execution | `a2a/sprint-bug-245/adversarial-rejected-audit.jsonl` (1 line) | PV payload rejected by the schema | Outcome not recorded in the a2a dir | Security boundary claim, unresolved in the record |
| 241: six HIGH fence predicate holes | `NOTES.md:163` | Fable review using hand-built twins | Fixed | Fence gap |
| 241: a TRUE bypass of the form `if T=/; then rm -rf "$T"` | `NOTES.md:163` | Audit dissent, recovered only from a schema-rejected payload | Fixed | Fence gap |
| 235: `live-floor-check.yml` passed `ANTHROPIC_API_KEY` to PR-controlled code | `NOTES.md:320` | Audit dissent, recovered only from a schema-rejected sidecar | Fixed | Security boundary (secret exposure) |
| 237: executor confinement | `NOTES.md:222` | Fable audit | Fixed in-sprint | Security boundary |
| #1266 BB iterations 2 to 4: F-002 ref/fork guard; trusted refs only and artifact validation; no raw test output in the log | `NOTES.md:200` | Bridgebuilder OpenAI voice | Fixed 1e28a955, adffe433, df0cd2ec, 098d766f | Security boundary (CI) |

**Catches by CI rather than a gate:**
- Five real test failures that pipe-masked local runs hid (`NOTES.md:328`).
- Shell-compat and sha256 lint reds on #1274 (`NOTES.md:120`).
- CMP-188, the grant spelling (`NOTES.md:8`).
- The mount gitignore window (f2ecb25d).

None of these were HIGH.

**Catches by the operator:** none of HIGH severity are recorded. The operator's recorded interventions were the permission-mode switch (`NOTES.md:20-24`) and the release approvals.

## 3. False-positive rates by gate

Here "refuted" means the finding was refuted with evidence by a verifier or by triage. Declined, repeat and pre-existing findings are excluded from the denominator in the last column.

| Gate, run | Raw | Real or doc, fixed | Refuted | Declined / repeat / pre-existing | Refuted share of (real + refuted) |
|---|---|---|---|---|---|
| 248 audit dissent | 92 | 12 | 19 | 61 | 61% (`a2a/sprint-248/audit-dissent-triage-run-1.md:5-14`) |
| 249 review dissent | 33 | 12 | 9 | 12 | 43% (verifier A and B tables) |
| 249 audit dissent | 13 | 2 | 4 | 7 | 67% (`audit-dissent-triage-run-1.md:13-17`) |
| 250 review run 1 | 63 | 16 | 20 | 27 | 56% (`review-dissent-triage-run-1.md:5,15`) |
| 250 review runs 2 and 3 | 20 | Most | n/a | n/a | Run 3: 5 of 5 real or doc (`run-3.md:6`) |
| 250 audit run 1 | 51 | 10 | 6 | 35 | 38% (`audit-dissent-triage-run-1.md:6`) |
| 250 audit runs 2 and 3 | 25 | 19 | Few | n/a | Low (`run-2.md:6`, `run-3.md:6`) |
| 251 review run 1 | 58 | 36 | 12 | 8 | 25% (`review-dissent-triage-run-1.md:3`) |
| 251 review run 2 | 76 | 36 | 30 | 10 | 45% (`run-2.md:3,5`) |
| 251 audit run 1 | 60 | 25 | 16 | 24 | 39% (`a2a/sprint-251/audit-dissent-triage.md:5-7`) |
| BB #1274 | 23 | 8 | 1 | 3 declined, 4 beads, 5 noted | 11% (`bridgebuilder-1274-triage.md:30`) |
| BB #1275 | 19 | 9 | 1 | 3 declined, 1 noted, 5 praise | 10% (`bridgebuilder-1275-triage.md:29`) |
| BB #1279 | 23 unique | 17 | 4 | 5 praise | 19% (`a2a/sprint-254/bridgebuilder-triage.md:9-33`) |
| BB #1269 | 6 | 2 | 2 | 2 praise | 50% (`NOTES.md:134`) |

**PV BLOCKING items specifically:**
- Refuted: 3 of 3 in sprint 249, the n1 BLOCKING in both sprint-251 review runs, and 1 of 1 in sprint 252.
- Real: the sprint-250 audit-run-1 HIGHs, and the sprint-253 audit DISS-002 HIGH.

**Same-model gates.** The record holds no refutation of a Fable review or audit finding. NOTES records "Every finding was accepted; none demoted" (`NOTES.md:312`). The record cannot give a false-positive rate for the Fable gates, because no independent check was run on them.

**Data caveat.** The sprint-248 review dissent sums to about 1,031 findings over runs 16 to 39, about 775 acted on and about 238 refuted or kept. This is a subagent's sum of section headings in `a2a/sprint-248/engineer-feedback-round-1.md`, not a triage table.

## 4. Harness friction incidents

**CLI contention and capacity:**
- **KF-037, recurrence 9** (`known-failures.md:1555`). The claude-headless hop timed out at 610 s, then 910 s, with about 12 interactive Claude sessions live.
  - The sprint-248 attempt rows record four consecutive 910 s timeouts on one chunk, and six on chunk a4.
  - The documented cost of retry-until-two-voice is "about an hour per run under host contention" (`known-failures.md:1571-1581`).
  - One `claude -p` hang ran about 8 h under the usage limit and needed a TERM-to-KILL reaper (`known-failures.md:1572`; `a2a/sprint-248/engineer-feedback-round-1.md:136`).
- **KF-038, recurrence 2** (`known-failures.md:1587-1606`). The companion shares the session's plan window. A RATE_LIMITED result opened the breaker and every later chunk ran single-voice. In one case the window stayed closed about 3 h over 12 attempts (`a2a/sprint-248/engineer-feedback-round-1.md:374`).
- **KF-039, recurrence 1, RESOLVED 398859ad** (`known-failures.md:1608`). E2BIG on a prompt over 128 KiB.
- **KF-040, recurrence 1** (`known-failures.md:1631`). A geo 400 on the subscription route, so the CV was rerouted through claude-bedrock.
- **KF-041, recurrence 3** (`known-failures.md:1654`). Flatline cross-scoring degraded to one scorer on every planning review in cycles 127 and 128. Blockers were then "integrated by judgment" (`NOTES.md:21`). This is a recurrence-3 structural failure of the Flatline scoring gate.
- **KF-036, recurrence 3.** A Bridgebuilder vitest precondition fails without an API key.

**Permission classifier and stop guard:**
- **KF-042, 2026-10-13.** The Claude Code auto-mode classifier denied four Loa cycle operations as Self-Modification: the zone marker, the beads export, the archive preview, and run-preflight plus the PRD write. The cycle stopped at planning until the maintainer switched to bypassPermissions (`known-failures.md:1675-1690`; `NOTES.md:20-24,32`).
- **The run-mode stop guard counts idle teammates as running background tasks.** The lead could not end a turn while subagents existed. This is recorded only in the operator memory, at `~/.claude/projects/-home-merlin-Documents-thj-code-loa/memory/session-2026-10-12-pocock-skills-review.md:29,32`. It is not a KF entry.

**Fence blocks on legitimate commands:**
- Command text that merely quotes a destructive rule was blocked (`NOTES.md:130`).
- Probe commands whose text contains `rm -rf` or `git branch -D` were blocked (`NOTES.md:166`).
- Copies into scratch paths containing `.claude/`, deletes of the form `rm -rf "$VAR"`, and the literal "git tag" in a `br create` title were blocked (`NOTES.md:182`).
- `git checkout -- <file>` was blocked (memory `session-2026-09-25-cycle126-full-size.md:54`). Scratch-dir removals were blocked (same file, line 50).
- SP-1 scans heredoc bodies, so spike-quoting edits had to go through the Write tool (memory `session-2026-10-12-pocock-skills-review.md:29,32`).
- The framework review measured 490 framework BLOCKs against 273 marker or bypass ALLOWs. Its verdict was "the fence is a speed bump against typos" (`a2a/framework-review-2026-09-17.md:152-153`).

**Timeouts and slowness:**
- No "61-minute timeout" appears in any file read. The nearest records are the following.
  - CI Shell Tests takes about 60 min (memory `session-2026-10-12-pocock-skills-review.md:32`).
  - The retry cost under KF-037 is about an hour per run.
  - The 40-minute cap on a background unit run in sprint 253 left 11 failures, which also fail on main (`a2a/sprint-253/reviewer.md:61`).
- Fence corpus slowdown under load ran 85 to 110 ms per row (8f7932b2).

**Stalls and lost work:**
- A usage-credit outage on 2026-09-19 killed six auditors and stalled the A/B arms (`NOTES.md:280`).
- Four audit-slice subagents hit the session cap mid-report (`NOTES.md:322`).
- A host reboot on 2026-10-01 wiped the scratchpad and a detached dissent driver (memory `session-2026-09-25-cycle126-full-size.md:60`).
- Explore teammates' reports were not delivered and had to be recovered from JSONL (`NOTES.md:182`).

## 5. Mechanical controls and data loss or damage

- **Stash safety.** Issue #555 (lost NOTES edits) and fence FR-1.2b both predate the period (`.claude/rules/stash-safety.md:31-35`). No stash incident or FR-1.2b block is recorded in 2026-09-17 to 2026-10-14. The in-period instance of the same swallowed-exit class was the pipe-masked bats runs. A mechanical fence did not catch that one; CI did (`NOTES.md:328`).
- **KF-039.** No data was lost. The failure dropped the CV silently to single voice. A related attempt row found the prompt readable through `/proc/<pid>/cmdline` and moved every prompt to stdin (398859ad; `known-failures.md:1627-1629`).
- **The implement gate's dead `ask`.**
  - The mechanical C-PROC-001 fence had emitted an invalid PreToolUse shape since cycle-050. Ungated App-Zone writes were never actually asked about (`a2a/sprint-250/audit-dissent-triage-run-1.md:48`).
  - Two more defects in the same control followed: non-canonical path bypasses and a bash-3.2 fail-open.
  - All three were found by gates reviewing frontier-model work on the control itself: CV dissent twice, and Bridgebuilder once. No implementer found them.
  - This is evidence the control did not work, not that it prevented damage.
- **Atomic-seeding gate false positive, 79224a9e.** A CI control blocked a legitimate `role: planning` change whose enum was unchanged. It was fixed to compare the enum (`NOTES.md:8`). This was cost without catch.
- **Real damage prevented by a control:**
  - The reaper's TERM-to-KILL change bounded an 8 h hang (`known-failures.md:1572`).
  - Under bats, the enforcer read the live ledger and flipped every allow. A hermetic seam fixed it, and the in-sprint gates caught it (`NOTES.md:142`).
  - A stale `a2a/sprint-1/COMPLETED` from cycle-122 would have satisfied the gates. The lead found it, not a control (`NOTES.md:166`).
  - The record has no case of a fence stopping a destructive command that an agent meant to run.

## 6. Cost signals

**What the ledgers cover.**
- Both ledgers span 2026-09-22T09:19Z to 2026-10-13T08:15Z. Cycle-124 sprints 235 to 237 are not covered.
- Bridgebuilder calls are absent.
- KF-033 (test pollution) and KF-035 (MODELINV silently not written without `cryptography`) bound their completeness.
- Dollar figures are list-price equivalents. Every a2a envelope records `cost_usd` 0, because the work ran on subscription and CLI routes.

**MODELINV by consumer** (`.run/model-invoke.jsonl`, 1,586 rows):

| Consumer | Rows | Median latency | Summed latency |
|---|---|---|---|
| adversarial-review (review dissent) | 1,266 | 25.8 s | 70.8 h |
| adversarial-audit (audit dissent) | 196 | 29.3 s | 5.1 h |
| reviewing-code | 52 | 31.9 s | 1.4 h |
| Flatline (review, skeptic, score, reviewer) | 72 | 37 to 85 s | 2.5 h |

The adversarial-review rows split as 644 PV, 501 CV and 116 failed chains. Bridgebuilder is not in the ledger.

**Cost ledger by sprint window** (`.run/cost-ledger.jsonl`, 1,443 rows, list-price total $1,727):

| Window | Dissent rows | Dissent $ | Other $ (Flatline + reviewing-code) |
|---|---|---|---|
| Cycle 125 (09-22 to 09-24) | 32 | 2.23 | 40.50 |
| 247 | 30 | 13.30 | 0 |
| 248 | 1,055 | 1,447.54 | 0.98 |
| 249 | 28 | 16.70 | 0 |
| 250 | 102 | 79.52 | 23.02 |
| 250 tail and 251 (10-07) | 87 | 59.01 | 7.45 |
| Cycle 128 (10-12 to 10-13) | 12 | 16.84 | 20.17 |

Sprint 248 alone is 84% of the period's metered spend. It ran 39 two-voice review runs over 2026-09-25 to 2026-10-05; run 39 took about 6.5 h for 24 chunks (`a2a/sprint-248/engineer-feedback.md:27`).

**Wall-clock of a review and audit cycle where recorded:**
- **247:** dissent 04:18 to 04:29Z, verdicts 04:40 to 05:40Z, COMPLETED 05:50Z. About 1.5 h for three review rounds and one audit.
- **250:** review dissent run 1 took 70 min for 14 chunks. Audit run 1 took 46 min for 16 chunks. Runs 2 and 3 took 12 to 14 min each (`a2a/sprint-250/review-dissent-triage-run-1.md:3`, `audit-dissent-triage-run-1.md`).
- **Cycle 128, all three sprints** (2026-10-13Z, 6 dissent calls, 12 voice calls):
  - First dissent about 02:32. Last audit verdict 07:59 (`a2a/sprint-252..254` trailers).
  - Per sprint: 252 review r1 02:43 to audit 03:35; 253 04:54 to 06:15; 254 07:01 to 07:59.
  - CI Shell Tests adds about 60 min per push.
- **Bridgebuilder per pass:** about 12.5 min for the claude-headless voice (`NOTES.md:8`) and 45 s to 693 s on #1274 (`bridgebuilder-1274-triage.md:3`).

## 7. What this record supports and what it does not

**What the record supports:**
- Fresh-context review found real defects in frontier-model output throughout the period. Every sprint from 247 to 254 except 249 needed at least one changes-required round. The largest single source of accepted findings was the CV, which is Fable 5.1 in a clean context. Model diversity is not the explanation.
- Security-boundary HIGHs were caught repeatedly, and every one was fixed.
  - Execution paths granted to review roles: sprints 253 and 254.
  - Credential exposure in CI: sprint 235 and #1266.
  - Write capability on a web-fetching agent: sprint 253.
  - The Fable audit, explicitly told to "look for what the review did not", caught the two cycle-128 HIGHs the review missed (`a2a/sprint-254/auditor-sprint-feedback-r1.md:90`). That is direct evidence for keeping a separate audit pass on security-relevant changes.
- Bridgebuilder, run once per PR after review and audit had approved, still found real HIGHs on #1274, #1279 and #1266. Its refuted share was the lowest of any gate, at 10 to 19%. That makes it the cheapest per real finding in this record.
- Defects in Loa's own mechanical controls were found only by adversarial review, never by the implementer: the dead `ask`, the path bypass, the bash-3.2 fail-open, and the predicate holes in 241. A mechanical fence is only as good as the review of the fence.
- Schema-rejected dissent payloads held true HIGHs twice (`NOTES.md:163,320`). Discarding rejected output would have lost real security findings.

**What caught little or cost more than it returned:**
- The PV contributed few unique findings in two-voice runs: 5 of 62 and 5 of 92 in 248, and 0 in 254 review. Its BLOCKINGs were often refuted (249, 251, 252). It did find the sprint-250 audit HIGHs and the 247 HIGHs, where it ran alone.
- Flatline scoring degraded on every run from cycle 127 on (KF-041, recurrence 3). Its output was integrated "by judgment", so the scoring stage gave no measured yield.
- Sprint 248's 39-run dissent loop cost 84% of metered spend and about ten days of wall-clock. It produced 24 fixed HIGHs, but the record shows no saturation point that would justify the later runs over a cap. The 3-run cap was adopted after it.
- Fences produced repeated false blocks on legitimate commands, and the record holds no in-period case of one preventing damage.

**Where the record is silent:**
- **The counterfactual.** No sprint was shipped without a gate, so no measure exists of what a gate's absence would have let through. The only partial evidence is the bugs found later in already-approved code. Two examples: the review-approved 254 HIGH caught by the audit, and the post-audit `${rel,,}` caught by Bridgebuilder.
- **Severity in production.** No finding is tied to an observed user-facing incident. All severities are the reviewers' own judgment.
- **False positives of the Fable gates themselves.** These were never independently checked.
- **Bridgebuilder and Flatline costs.** Bridgebuilder is absent from the ledgers. Flatline cost is metered but its yield is unmeasurable while scoring is degraded.
- **Single-voice runs.** For the single-voice bug sprints and sprint 247, the record cannot show what a second voice would have added.
- **Open-weight models.** None ran as implementer or reviewer anywhere in the period.
