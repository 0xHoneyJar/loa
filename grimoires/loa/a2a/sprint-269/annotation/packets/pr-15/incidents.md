# Incidents — pr-15

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-13

- reference: 2bcf0e40401d
- files: .loa.config.yaml.example

Summary:

fix(cycle-128): sprint-252 review round r252-1 — the Fable review's three requested changes and one observation fix: the shipped .loa.config.yaml.example leaves interview.pacing commented so the per-mode default (rounds for thorough, batch for minimal) applies, with REFERENCE §Interview Modes stating the unset rule; dec-write-lib.sh classifies an explicit --file by its canonical path (live ledger…

Evidence:

~~~~diff
commit 2bcf0e40401df71bad441813e36840f22ab6c333
Date: 2026-10-13T14:00:27+11:00

fix(cycle-128): sprint-252 review round r252-1 — the Fable review's three requested changes and one observation fix: the shipped .loa.config.yaml.example leaves interview.pacing commented so the per-mode default (rounds for thorough, batch for minimal) applies, with REFERENCE §Interview Modes stating the unset rule; dec-write-lib.sh classifies an explicit --file by its canonical path (live ledger, a2a/*/decisions-pending.yaml, or fixture) so naming the live ledger never bypasses the CI/hook refusal, and a linked worktree refuses a live --file (two new bats incl. relative, absolute and dot-dot paths under CI, GITHUB_ACTIONS and LOA_HOOK_CONTEXT, plus import --from into the live ledger); the FR-8 operative-reference lint judges the clause before the verb in awk, so an exempt word after the command name no longer hides an operative line (fixture with seven sentences); tools/check-round-independence.sh rejects a multi-value capture as a malformed-block violation (exit 1) instead of a jq crash (RI-11b). Dissent DISS-001 (jq index([x]) "never matches") refuted with evidence; DISS-C-001/002/003/004 fixed. Sprint 1 tasks ticked in sprint.md. Verification: 347/347 across 14 suites; budgets, sha256 lint, decisions validator and agents-md-gen --check green.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index a91cb9d6..1a9d5f32 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -97,7 +97,7 @@ plan_and_analyze:
 # Interview Depth Configuration (v1.41.0)
 # -----------------------------------------------------------------------------
 # Controls question depth, input style, and pacing across planning skills.
-# Default: thorough mode with rounds of plain-text discovery questions.
+# Default: thorough mode; pacing unset, so rounds of plain-text discovery questions.
 #
 # Construct override: Schema supports future construct manifest interview
 # overrides gated by trust tier (RFC #379). Not wired yet.
@@ -124,7 +124,8 @@ interview:
 
   # Question pacing. One key for the discovery interview, /architect Phase 2,
   # /sprint-plan Phase 2 and /chart; per_skill above still picks the mode.
-  # Unset: rounds for thorough, batch for minimal. An explicit value always wins.
+  # Left unset (the shipped default), it is rounds for thorough and batch for
+  # minimal; uncomment and set a value to pin it for every mode.
   #   rounds: each turn asks the whole frontier, every open question whose
   #     prerequisites are settled; a question that depends on another one still
   #     open waits for a later round. Questions are numbered across the session
@@ -137,7 +138,7 @@ interview:
   #   sequential: one question per turn, wait for the answer (the supported
   #     opt-out if you prefer one question at a time)
   #   batch: 3-6 numbered questions per turn, user responds freely
-  pacing: rounds   # sequential | batch | rounds
+  # pacing: rounds   # sequential | batch | rounds; unset = rounds for thorough, batch for minimal
 
   # Phase transition gates
   phase_gates:
~~~~

## I02 — fix-commit — 2026-10-13

- reference: befd511de798
- files: .loa.config.yaml.example

Summary:

fix(cycle-128): sprint-254 audit round r254-2 — the Paranoid Cypherpunk audit's HIGH, three MEDIUMs and three LOWs closed with tests: red-test-check.sh accepts only a listed runner as the first word of the test command and of --setup (bats, pytest, python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test, bundle exec rspec; a ./ or tests/ script only when .loa.config.yaml red…

Evidence:

~~~~diff
commit befd511de798c140ba28819fd0617c8c707f3f76
Date: 2026-10-13T18:58:27+11:00

fix(cycle-128): sprint-254 audit round r254-2 — the Paranoid Cypherpunk audit's HIGH, three MEDIUMs and three LOWs closed with tests: red-test-check.sh accepts only a listed runner as the first word of the test command and of --setup (bats, pytest, python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test, bundle exec rspec; a ./ or tests/ script only when .loa.config.yaml red_test.allowed_runners names it; the exact red_test.command / red_test.setup strings) and refuses shells, env, eval, exec, inline-code interpreters and the listed runners' inline-code flags with exit 2 naming the config key; every run and --setup starts from env -i with PATH (absolute entries outside the repository and the scratch), a fresh HOME and TMPDIR per run under the scratch, LANG, LC_ALL, TERM, CI=1, no global or system git config, no terminal prompt, a failing askpass and ssh transport, plus --env-pass NAME for one caller variable (credential-shaped and contract names refused); the test runs red, green, then red again and a passing second red is DECOY (a stateful decoy); the output tails are control-stripped (C0, C1, U+2028/9), capped at 400 bytes per line and wrapped in the L6 untrusted-content fence with the authoritative verdict line printed last (--json adds red_again_exit); every git call runs with core.hooksPath=/dev/null and core.fsmonitor=false, and a snapshot of refs, HEAD, the git config files and the hooks directory taken before the runs is compared after each phase, a difference exiting 2 with the changed entries; the header states the runner, environment, shared-.git and untrusted-output contracts; .loa.config.yaml.example documents the red_test block; reviewing-code takes only the red commit SHA from reviewer.md, the test command from sprint.md or red_test.command, runs only a listed runner with --json, treats the tails as untrusted data, and its execute_commands grant is explicit (--red *), with the trust rules in resources/REFERENCE.md and the qmd step's (paths only) cue kept (RTC-1, RTC-4/5/7 re-pinned, RTC-19…26, RTC-17 extended); validate_sprint_seams tracks fences through lib/md-fence.awk and a live plan under grimoires/loa/ (not its archive) without a parseable header Date fails instead of warning (SEAMS-11/12); validate_glossary fails a glossary with more than 40 aliases in total and WARNs on a non-ASCII letter in a term or alias name (GV-25/26/27); check-glossary-terms.sh --report and --json list resolution-only and unreferenced entries, exit code unchanged (GT-29/30/31); symlink-manifest.sh links .claude/loa/GLOSSARY.md only when the pinned framework ships it and prints one notice otherwise, so an older pin gets no dangling link (symlink-manifest-glossary.bats SMG-1…5). Also: the Sprint 3 acceptance-criteria boxes ticked in sprint.md; REPO-MAP regenerated with its checksum over the final .claude/ code (--validate exit 0); .claude/checksums.json refreshed for the changed tracked files. Verification on the final tree: the 23-suite run recorded in the audit report; check-prompt-budget exit 0 (reviewing-code 16,306 of 16,384); validate-skill-capabilities 37/37; agents-md-gen --check 51 commands; check-no-swallowed-jq and check-no-raw-sha256sum OK; sync-fixtures --check current; bash -n on every changed script; shell-compat greps clean; check-glossary-terms.sh PASS on the live kernel; both glossaries, the sprint plan, the PRD and the SDD validate; a shell test command is refused with exit 2 on a throwaway repository.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index 2215de7d..bf3e473b 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -2891,3 +2891,23 @@ structured_handoff:
   # skip). Read-path only — INDEX.md and read_by are untouched; old handoffs
   # stay recoverable via the structured-handoff skill.
   surface_max_age_days: 30
+
+# =============================================================================
+# red_test — inputs to .claude/scripts/red-test-check.sh (the /bug red-before-green check)
+# =============================================================================
+# The check runs a test command at the red commit and at the fix, under `env -i`, and accepts
+# only a known runner as the first word of the command and of --setup: bats, pytest,
+# python -m pytest, npm/pnpm/yarn test|run, cargo test, go test, make, mix test,
+# bundle exec rspec. Shells, env, eval, exec and inline-code interpreters (python -c, node -e,
+# perl -e, ruby -e) are always refused. This block widens that list for one project. Edit it as
+# the operator: the file is tracked, and a red_test change on the branch under review makes the
+# check WARN.
+#
+# red_test:
+#   # The project's test command; the exact string (whitespace-normalised) is accepted.
+#   command: "make test"
+#   # The exact --setup string accepted besides the runner list (e.g. a dependency install).
+#   setup: "npm ci"
+#   # ./... or tests/... scripts accepted as the first word, matched exactly.
+#   allowed_runners:
+#     - ./scripts/run-tests.sh
~~~~

## I03 — issue — 2026-10-13

- reference: #1279
- files: tools/ceiling-probe-live.py

Summary:

feat(cycle-128): decision surfaces — interview rounds with fact/decision attribution, the decision ledger, /chart decision maps, spike tickets, glossaries, seams and red-before-green, operator-only commands — ## Summary cycle-128 "decision surfaces" turns the planning conversation into attributable, inspectable decisions. The interview asks in prerequisite-ordered rounds and separates facts (look…

Evidence:

~~~~~text
# pull request #1279: feat(cycle-128): decision surfaces — interview rounds with fact/decision attribution, the decision ledger, /chart decision maps, spike tickets, glossaries, seams and red-before-green, operator-only commands

- url: https://github.com/0xHoneyJar/loa/pull/1279
- created_at: 2026-10-13T08:01:48Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

cycle-128 "decision surfaces" turns the planning conversation into attributable, inspectable decisions. The interview asks in prerequisite-ordered rounds and separates facts (looked up, never asked) from decisions (the operator's); every planning decision becomes a `DEC` row in a tracked, append-only ledger with who decided it; `/chart` maps an effort that spans more than one cycle as decision tickets on beads without building anything; questions that talking cannot settle become spike tickets on branches that are pushed, never merged and never opened as a PR; a framework glossary and a drift gate keep the vocabulary from rotting; sprint plans declare their seams under test and a red-before-green check proves a bug fix's test failed before the fix; and seven operator-only commands are out of the model's reach.

Three sprints (global 252, 253, 254), each through implement → review → audit with two-voice dissent at every gate (gpt-5.5-pro via codex-headless + claude-headless, consensus every run, 0 schema-rejected payloads). Review and audit each took two rounds per sprint; every round-1 finding is closed with a test in the following commit. Full release note: `CHANGELOG.md` `[Unreleased]` (with a Migration section). Maintainer brief and source analysis: `grimoires/loa/a2a/skills-review-2026-10/` (record branch).

## What is in it

- **FR-1 Interview rounds** (`interview.pacing: rounds`, the default for `thorough`): every question whose prerequisites are settled, in one numbered round with a recommended answer; `tools/check-round-independence.sh` scores a transcript's round blocks.
- **FR-2 Fact or decision**: the Backpressure Protocol splits questions into facts and decisions; unattended runs record each decision taken for the operator.
- **FR-3 Decision ledger**: `grimoires/loa/decisions.yaml` through its single writer `dec-write-lib.sh` (derived attribution, unattended writes always `proposed`), `validate-artifact.sh --type decisions`, the INDEX `## decisions` family, a default-off SessionStart surface, and `/decisions` (operator-only) as the only path to `confirm`.
- **FR-4 `/chart` decision maps**: a `map` epic of `question` beads plus a map doc with exactly four sections; `chart-ticket.sh` owns the write order and idempotency; `chart-guard.sh` refuses unattended contexts; the read-only `chart-researcher` agent; `chart-unblock-probe.sh` runs a probe under a scrubbed environment with a refs/config/hooks snapshot; question beads never enter the build path (`create-sprint-task.sh`, `get-ready-work.sh`, the sprint validator); `golden-path.sh` reports a `charting` phase.
- **FR-5 Spike tickets**: `spike/<slug>` branches, ICE spike rules, fence rule SP-1 (merge, rebase, pull, cherry-pick, reset, read-tree, update-ref, branch moves, push refspecs, FETCH_HEAD one-liners, alias definitions, `gh api` pulls), the D-5.9 clean-up unlock for a fully pushed, operator-decided spike, `validate-artifact.sh --type spike`.
- **FR-6 Glossaries**: `.claude/loa/GLOSSARY.md` (33 entries, mounted into every project) and the root `GLOSSARY.md`; `tools/check-glossary-terms.sh` with a CI gate and two controls; `validate-artifact.sh --type glossary`.
- **FR-7 Seams and red-before-green**: `### Seams Under Test` in every sprint block of plans dated from 2026-10-13; `red-test-check.sh` (listed runners only, `env -i`, red-green-red, fenced output, `.git` snapshot); the micro-sprint two-commit rule; `reviewing-code` cites the check.
- **FR-8 Operator-only commands**: `disable-model-invocation: true` on `/loa-eject`, `/toggle-gpt-review`, `/permission-audit`, `/loa-setup`, `/contribute`, `/run-halt`, `/decisions`, pinned by a lint and verified by one live harness run.

## Verification

- Final tree: 23 bats suites, 762/762 (the full cycle-128 set plus every Sprint 1–2 suite the validator or the fence touches); `check-prompt-budget` exit 0; `validate-skill-capabilities` 37/37; `agents-md-gen --check` 51 commands; `repo-map-gen --validate` exit 0; `check-no-swallowed-jq`, `check-no-raw-sha256sum` OK; `sync-fixtures --check` current; `check-glossary-terms.sh` PASS; PRD, SDD, sprint plan, both glossaries and the 122-row decision ledger validate.
- E2E (`grimoires/loa/a2a/sprint-254/e2e.md`, record branch): G-1…G-7 PASS; G-3 scored on a second rounds transcript; G-7 verified by a live `claude -p` run whose stream shows the hidden command refused by the Skill tool and the control running.
- Review and audit reports, dissent envelopes and COMPLETED markers for sprints 252–254: `grimoires/loa/a2a/sprint-25{2,3,4}/` (record branch `record/cycle-128-a2a`).

## Follow-ups (beads)

bd-g6k3 (operator-only convention), bd-48ni (`/contribute` secrets check scans the final diff only), bd-xtip (`/loa-eject` unpinned recovery script), bd-akas (per-agent Read/WebFetch limits for `chart-researcher` once the harness supports them).

## Decisions taken on your behalf

Every planning decision of this cycle is a `proposed` row in `grimoires/loa/decisions.yaml` (none `decided`: no operator was present). Confirm, reject or supersede them with `/decisions`. The table is `dec-write-lib.sh list --not-decided-by operator --format md` at the time of this PR.

<details>
<summary>123 proposed rows (DEC-0001 … DEC-0124; DEC-0123 and DEC-0124 were added by the Bridgebuilder round)</summary>

| Decision | Voice | Status | Why | Source |
|---|---|---|---|---|
| `rounds` becomes the default pacing for `thorough`; `sequential` stays as the documented opt-out (D1) (DEC-0001) | agent | proposed | the brief recommended it; Pocock's 1.2.0 made the same flip with a supported opt-out | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D1) |
| `decisions.yaml` lives at `grimoires/loa/decisions.yaml` and is tracked (D2) (DEC-0002) | agent | proposed | the original spec and two existing readers point there; team surface like `known-failures.md` | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D2) |
| `/chart` is a truename command, not a golden-path porcelain command; `/plan` reports `charting` (D3) (DEC-0003) | agent | proposed | narrow trigger; Pocock calls wayfinder a situational on-ramp | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D3) |
| Research tickets run as Opus subagents via the Agent tool, not cheval (D4) (DEC-0004) | agent | proposed | host-local, no provider dependency | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D4) |
| Pocock's `task` type is named `decision:unblock` (D5) (DEC-0005) | agent | proposed | the type that "goes wrong most often"; the name must not read as a build task | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D5) |
| Spike branches are `spike/<slug>`, pushed, never merged, no PR (D6) (DEC-0006) | agent | proposed | a pushed branch is the pointer the spike report needs; no PR keeps it off review | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D6) |
| `GLOSSARY.md` at the repo root, tracked; Loa dogfoods it (D7) (DEC-0007) | agent | proposed | root is where humans and Pocock's consumer rule look; the kernel drift check needs one path | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D7) |
| FR-8 safe set = zero-reference leaves; the referenced set is triaged per reference (D8) (DEC-0008) | agent | proposed | a flagged command an orchestrator executes as a step would break `/ship` | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D8) |
| B7 two-axis presentation and the LEARN items are future iterations, not this cycle (D9) (DEC-0009) | agent | proposed | simplicity first; the eight FRs are the brief's scope | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D9) |
| Two glossaries: the framework glossary ships at `.claude/loa/GLOSSARY.md` (drift-checked against the kernel i… (D10) (DEC-0010) | agent | proposed | consumer projects need the framework terms mounted, and their own terms must not live in the System Zone (Flatline opus IMP-009) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D10) |
| Unattended prototype-class questions defer by default (`interview.unattended_prototype: defer`): open `DEC` r… (D11) (DEC-0011) | agent | proposed | a halt on every look-and-feel question would stall unattended planning; the deferred requirement is visible in the PRD and the ledger (Flatline gpt IMP-004, opus IMP-004) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D11) |
| `/chart` refuses in unattended mode; research tickets are the only AFK work in a map (D12) (DEC-0012) | agent | proposed | a charted map whose questions the agent answered is the wayfinder failure pattern by construction (Flatline opus IMP-020) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D12) |
| Agent decisions are `status: proposed` until `dec-write-lib.sh confirm` by the operator; the standing admin p… (D13) (DEC-0013) | agent | proposed | confirmation must be explicit and auditable per row (Flatline SKP-001a) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D13) |
| `decided_by` is derived by the writer from run context; `operator` needs an `--answer-ref` (D14) (DEC-0014) | agent | proposed | self-reported attribution is unfalsifiable (Flatline SKP-001b) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D14) |
| Rows are append-only with status transitions; content edits are rejected; `supersede` creates a new row (D15) (DEC-0015) | agent | proposed | a decision history that can be rewritten is not a record (Flatline SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D15) |
| Backfill is forward-only except cycle-127 D1–D3, seeded like every other seed row as `proposed` (D16) (DEC-0016) | agent | proposed | three rows give the validator a live fixture without a migration project, and no seed can claim a confirmation the operator has not given per row (Flatline gpt IMP-001, opus IMP-027; SDD review SKP-001) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D16) |
| Operator transitions (`confirm`, `reject` or `supersede` of a decided row, clearing the unattended marker) ex… (D17) (DEC-0017) | agent | proposed | an agent that can clear its own unattended marker or confirm its own rows makes attribution meaningless (SDD review SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D17) |
| Implementers in linked worktrees write a per-sprint pending file with provisional ids; the lead imports it in… (D18) (DEC-0018) | agent | proposed | an append-only tracked YAML is unmergeable across branches and max+1 ids collide (SDD review SKP-003) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D18) |
| Attribution is tamper-evident (artifact hashes, HEAD commit, append-only transitions), not signed; signing th… (D19) (DEC-0019) | agent | proposed | proportionate to a planning ledger; the signing infrastructure exists and can be attached later (SDD review SKP-002) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D19) |
| Mike Farah yq v4 becomes a hard dependency for the ledger writer; the lock is portable (`flock` or a `mkdir` … (D20) (DEC-0020) | agent | proposed | hand-rolled YAML is the corruption risk the review named; macOS and BSD hosts are supported (SDD review SKP-004) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf (D20) |
| Ledger lock fails closed after 10 s (A1) (DEC-0021) | agent | proposed | a lost update on a tracked ledger is worse than a retry | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A1) |
| Temp file beside the target (A2) (DEC-0022) | agent | proposed | a cross-filesystem `mv` is not atomic | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A2) |
| Verify by row equality plus field classes (A3) (DEC-0023) | agent | proposed | YAML re-serialisation moves lines | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A3) |
| Optional `cycle` field, defaulted from run state (A4) (DEC-0024) | agent | proposed | a run spans days; `--since` is kept as the PRD's equivalent | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A4) |
| `charting` from the map doc Status line (A5) (DEC-0025) | agent | proposed | golden-path must work without `br`; the doc wins on disagreement | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A5) |
| Hand-off context snapshot; chart zones add `context` and `spikes` (A6) (DEC-0026) | agent | proposed | no budget there. Widens the PRD's four-path zone list by two | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A6) |
| `research/chart-*.md` tracked by a negation (A7) (DEC-0027) | agent | proposed | maps need their cites | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A7) |
| Exclude `question` in `get-ready-work.sh` and route `/implement` through it (A8) (DEC-0028) | agent | proposed | `br ready` is unfiltered today | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A8) |
| Fence rule SP-1 plus the ICE spike rules (A9) (DEC-0029) | agent | proposed | ICE covers run mode only | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A9) |
| Seams rule gated by Date ≥ 2026-10-13 (A10) (DEC-0030) | agent | proposed | old fixtures have no Date (PRD adopted it) | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A10) |
| `_Aliases_:` lines; identifier-shaped tokens only (A11) (DEC-0031) | agent | proposed | run states are one concept (PRD adopted it) | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A11) |
| Flag the `loa-setup` skill only if the harness check shows the operator's command still works (A12) (DEC-0032) | agent | proposed | a shared name may leave the skill reachable, but the operator's own command must keep working | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A12) |
| Rounds within a phase (A13) (DEC-0033) | agent | proposed | keeps phase gates and section order | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A13) |
| Claim with `br update --claim` (A14) (DEC-0034) | agent | proposed | atomic assignee plus status | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A14) |
| Synchronous surface after the KF hook (A15) (DEC-0035) | agent | proposed | async output is not reliably injected | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A15) |
| Sprint validator cross-checks beads (A16) (DEC-0036) | agent | proposed | catches a `sprint:` label added by hand | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A16) |
| Map docs allow exactly four H2s plus `## Closed` (A17) (DEC-0037) | agent | proposed | an allowlist cannot be dodged by a new name | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A17) |
| `flatline`/`dissent` attribution needs an existing artifact and its sha256; no orchestrator call site this cy… (A18) (DEC-0038) | agent | proposed | keeps the sanctioned review path unchanged; the hash makes the claim checkable | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A18) |
| `confirm --cycle` previews and needs `--all` or `--id`s for several rows (A19) (DEC-0039) | agent | proposed | batch confirmation stays explicit | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A19) |
| The writer does not require `br` (superseded preflight rule) (A20) (DEC-0040) | agent | proposed | the ledger has no beads dependency; PR bodies render without beads | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A20) |
| The PRD Status line is an unattended signal for the gate and the writer, not for `confirm` (A21) (DEC-0041) | agent | proposed | the writer and the gate agree, and the operator can still confirm later | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A21) |
| Chart ticket rows use `source: map:<slug>/<ticket>`; the bead carries `--external-ref <DEC-id>` (A22) (DEC-0042) | agent | proposed | the row is written before the bead exists and `source` is immutable | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A22) |
| A `chart-researcher` agent without Bash, plus an ignored-files and mtime scope check (A23) (DEC-0043) | agent | proposed | tool removal is mechanical; prompts are not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A23) |
| Spike deletion through a fence predicate on a decided row (A24) (DEC-0044) | agent | proposed | the PRD allows deletion once decided; the predicate is positive and fails closed | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A24) |
| `.run/unattended.json` with session id and TTL, plus a `context` subcommand (A25) (DEC-0045) | agent | proposed | Bash calls do not share env; a stale marker must not outlive its session | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A25) |
| `/plan-and-analyze` closes a consumed map and applies the multi-map rule via command-file steps (A26) (DEC-0046) | agent | proposed | no SKILL budget; the command file is not budgeted | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A26) |
| Each `[ASSUMPTION decision]` line cites its DEC id (A27) (DEC-0047) | agent | proposed | a per-tag link is checkable; counts are not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A27) |
| ICE allows only the default branch into a `spike/*` branch, behind an optional argument (A28) (DEC-0048) | agent | proposed | the narrowest exception, default behaviour unchanged | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A28) |
| The live-harness bats is opt-in (`LOA_LIVE_HARNESS=1`) and every outcome is defined (A29) (DEC-0049) | agent | proposed | a model call per CI run costs money and flakes; a skip is visible, a false pass is not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A29) |
| `red-test-check.sh` timeout is its own exit 5 and dependency linking is on by default (A30) (DEC-0050) | agent | proposed | a hung test is not a failing fix; fresh worktrees mostly fail on missing dependencies | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A30) |
| `proposed_by` records the proposing voice; `decided_by` is set once, by `confirm` (A31) (DEC-0051) | agent | proposed | lets `decided_by` stay null until a human acts, without rewriting a set-once field | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A31) |
| `/decisions` runs operator ops in the session, previewing first; no fence on the writer (A32) (DEC-0052) | agent | proposed | the fence would also block the command itself; the boundary is the allowlists plus tamper evidence | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A32) |
| Linked worktrees write `PEND-` rows to a sprint pending file; the lead imports (A33) (DEC-0053) | agent | proposed | max+1 ids collide and an append-only YAML list does not merge | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A33) |
| `mkdir` lock fallback with a 60 s stale check when `flock` is absent (A34) (DEC-0054) | agent | proposed | macOS ships without `flock` | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A34) |
| `hook-guard.sh` exports `LOA_HOOK_CONTEXT=1`; live-ledger writes refuse under it and under CI (A35) (DEC-0055) | agent | proposed | makes "no bot auto-append" mechanical while fixtures still run in CI | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A35) |
| `BARE_ASSUMPTION_FAILS_FROM=2026-11-13` (A36) (DEC-0056) | agent | proposed | a date is checkable; a release boundary is not | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A36) |
| `get-ready-work.sh` filters out `question` instead of allowlisting types (A37) (DEC-0057) | agent | proposed | new types keep flowing; only decision tickets are excluded | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A37) |
| `decision:unblock` probes run only through `chart-unblock-probe.sh` (A38) (DEC-0058) | agent | proposed | the helper proves the main tree is untouched | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A38) |
| BSD coverage through PATH-shim twins (A39) (DEC-0059) | agent | proposed | follows `validate-artifact-bsd.bats`; no new CI runner | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A39) |
| `run-preflight.sh` P9 fails without yq v4 (A40) (DEC-0060) | agent | proposed | the ledger cannot be written without it | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A40) |
| The append-only base defaults to `git merge-base origin/main HEAD` (A41) (DEC-0061) | agent | proposed | rows added on the branch remain checkable against main | grimoires/loa/sdd.md#113-decisions-taken-on-the-operators-behalf (A41) |
| agy opt-in, default off (c127-D1) (DEC-0062) | agent | proposed | Facts: `gemini-headless` → `AgyHeadlessAdapter` on any host with agy on PATH; hosts without agy (this one) plan a voice that fails (BB #1274 DEGRADED 2/3); the prompt rides on argv. Decision: a config key (default off) gates the agy route; planners (BB voice list, dissent family chain, Flatline tertiary, preflight, `/loa`) treat it as disabled unless opted in; the argv exposure is the documented r | grimoires/loa/NOTES.md#decision-log-2026-10-07 (bd-ugmi) (c127-D1) |
| `claude-opus-5-5` catalog effort default `high` (c127-D2) (DEC-0063) | agent | proposed | Fact (claude-api skill, 2026-10-07): Opus 5.5's vendor effort default is `medium`, one below Opus 5's `high`, so every `opus` caller passing no `--effort` lost a level at the alias retarget; the headless adapter already reads a catalog `extra.effort`, the HTTP adapter does not. Decision: resolve the catalog default once at the cheval chokepoint when the caller passes none; `--effort` overrides; MO | grimoires/loa/NOTES.md#decision-log-2026-10-07 (bd-9qe2) (c127-D2) |
| probe the ceiling through this host's route (c127-D3) (DEC-0064) | agent | proposed | Facts: `tools/ceiling-probe-live.py` uses the direct API (geo-refused here, no key); every Opus 5.5 hop here runs through `claude-bedrock` → `global.anthropic.claude-opus-5-5`. Decision: add `--transport claude-headless` to the probe (mirrors the adapter's CLI flags), bisect 180K→1M (≈ $12–20 Bedrock input, authorized), record a clean bound as `ceiling_calibration.source: operator_set` + `calibrat | grimoires/loa/NOTES.md#decision-log-2026-10-07 (c127-D3) |
| /update-loa: not flagged (deferred) (refs 11, orchestrator steps 0) (fr8-update-loa) (DEC-0065) | agent | proposed | Every reference is advice, but the D-8.3 lint reads `Run /update-loa --force-restore` in the `translate-ride.md:145` troubleshooting table as operative; part C may not edit that file; evidence `translate-ride.md:145`; probe output below | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-update-loa) |
| /mount: not flagged (deferred) (refs 13, orchestrator steps 0) (fr8-mount) (DEC-0066) | agent | proposed | Every reference is advice, but seven user-facing error strings (`error: "... Run /mount first."`, troubleshooting rows) trip the lint; part C may not edit those files; evidence `ride.md:62,66,70,282,283`, `run.md:60`, `run-sprint-plan.md:44` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-mount) |
| /contribute: FLAGGED (refs 1, orchestrator steps 0) (fr8-contribute) (DEC-0067) | agent | proposed | The only reference is advice (`loa-eject.md`); the command opens an upstream PR, an outward-facing act; evidence `loa-eject.md:260` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-contribute) |
| /feedback: not flagged (refs 24 (10 are path matches), orchestrator steps 0 in bodies) (fr8-feedback) (DEC-0068) | agent | proposed | Body references are advice, but `.claude/loa/reference/agent-teams-reference.md:59,278` sanctions teammate invocation of `/feedback`, a model invocation path outside the command and skill bodies; evidence `agent-teams-reference.md:59` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-feedback) |
| /deploy-production: not flagged (refs 12, orchestrator steps 7) (fr8-deploy-production) (DEC-0069) | agent | proposed | `/ship` executes it and the autonomous agent runs it in Phase 6; evidence `ship.md:60`, `autonomous-agent/SKILL.md:180` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-deploy-production) |
| /archive-cycle: not flagged (refs 12, orchestrator steps 7) (fr8-archive-cycle) (DEC-0070) | agent | proposed | `/ship` executes it; `/loa` invokes it after the user confirms; evidence `ship.md:64`, `loa.md:265` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-archive-cycle) |
| /ship: not flagged (refs 16, orchestrator steps 1) (fr8-ship) (DEC-0071) | agent | proposed | `/loa` invokes it when the user picks the menu option; evidence `loa.md:262` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-ship) |
| /run-halt: FLAGGED (refs 9, orchestrator steps 0) (fr8-run-halt) (DEC-0072) | agent | proposed | Every reference is a related-commands list, help line or recovery option for the human; the run-mode circuit breaker halts without the command; evidence `run-mode/SKILL.md:224`, `escalation-report.md:151` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-run-halt) |
| /run-resume: not flagged (refs 29, orchestrator steps 2) (fr8-run-resume) (DEC-0073) | agent | proposed | `/simstim` resume invokes it in place of a fresh run; evidence `simstim.md:462`, `simstim-workflow/resources/resume-support.md:132` | grimoires/loa/a2a/sprint-252/triage-fr8.md#decision-per-command (fr8-run-resume) |
| One helper (chart-ticket.sh) owns the /chart write steps; the SDD's raw br and ledger-writer grants stay in al (S2-D1) (DEC-0074) | agent | proposed | prose cannot prove the write order, idempotency, the research cap or the unattended-close rule in bats; Task 2.4 covers the shell steps | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| A map ticket's ledger row source is map:<slug>/<ticket> (SDD A22), not the bead id (S2-D2) (DEC-0075) | agent | proposed | the row is written before the bead exists and source is immutable; list --source-epic keys on this form | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Claiming a ticket uses br update --claim (D-4.4), not --status in_progress (S2-D3) (DEC-0076) | agent | proposed | --claim also sets the assignee, which the frontier's unclaimed filter relies on | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Map Status has four values (charting, handed-off, closed, abandoned); the epic closes at close, not at hand-of (S2-D4) (DEC-0077) | agent | proposed | D-4.5 puts the epic close in the close step; close sets closed for a consumed map and abandoned for a reason | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Open tickets live on beads only; the map doc gains a line when a ticket is resolved or ruled out, and a new do (S2-D5) (DEC-0078) | agent | proposed | the four allowed sections have no place for open tickets and a list would duplicate beads state | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| chart-frontier.sh inlines the bv --robot-triage ranking instead of calling get-ready-work.sh (S2-D6) (DEC-0079) | agent | proposed | the build path drops question beads by design and its limit would cap the set | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| The unblock probe and research scope check snapshot git status --porcelain --untracked-files=all --ignored=mat (S2-D7) (DEC-0080) | agent | proposed | a write inside an already-untracked or ignored directory is invisible to a collapsed status | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| An unblock ticket requires --unblocks <ticket\|DEC>, appended to the body as Unblocks: X (S2-D8) (DEC-0081) | agent | proposed | makes D-4.12 (the body names the decision it unblocks) mechanical | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| D's suites are charting-decisions.bats and chart-frontier.bats, separate from E's charting-lint.bats (S2-D9) (DEC-0082) | agent | proposed | no collision between the two implementers' suites | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| skill-capabilities.bats SC-T-AGENT-7 and agents-md-gen.bats pins were edited for the new agent type and comman (S2-D10) (DEC-0083) | agent | proposed | the SDD's own additions (a new agent, a new command) require both edits | grimoires/loa/a2a/sprint-253/reviewer-d.md#decisions-taken-beyond-the-sdd-alternatives-and-why |
| Validator beads cross-checks run only when the validated file is inside PROJECT_ROOT (S2-E1) (DEC-0084) | agent | proposed | a /tmp fixture has no relation to the project's beads and an env opt-out is a bypass; keeps every suite off the real database | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| The map validator accepts four Status values including closed (S2-E2) (DEC-0085) | agent | proposed | D-4.5 and D-4.6 define closed as the consumed state | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| A map doc must have exactly one H1 (S2-E3) (DEC-0086) | agent | proposed | a second H1 would dodge the H2 allowlist | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| A missing DEC id under a spike report's Decided by WARNs rather than fails (S2-E4) (DEC-0087) | agent | proposed | the shipped template must pass (D-5.5) and the row may be written after the report | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| SP-1 also blocks git checkout <spike> <path> without --, git -C and -c forms, commit ranges, and a headless gh (S2-E5) (DEC-0088) | agent | proposed | the same copy through the most common alternate spellings; each check is positive and offline | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| ICE safe_merge on a spike head runs git merge --no-edit for an exact allowlist (main, master, origin/main, ori (S2-E6) (DEC-0089) | agent | proposed | the other ICE wrappers perform their operation; an exact list leaves no flag injection | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| The D-5.9 spike unlock requires the last transition to decided to be by operator:* and strips a #anchor from s (S2-E7) (DEC-0090) | agent | proposed | a decided row is operator-confirmed by schema; the anchor form is what the writer records elsewhere | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| planning-sprints budget room came from moving the integration-context list to REFERENCE.md (S2-E8) (DEC-0091) | agent | proposed | the D-5.1 wording stays verbatim in all three skills | grimoires/loa/a2a/sprint-253/reviewer-e.md#decisions-taken-beyond-the-sdd |
| Matching also folds `-`, `_` and spaces, so `run-mode` and `run_mode` resolve to **Run mode**. The plural fold (S3-F1) (DEC-0092) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| Only entries and aliases inside `## Language` resolve tokens or count for duplicates. Other H2 sections are al (S3-F2) (DEC-0093) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| A missing allowlist file is a usage error (exit 2), never an empty allowlist. An allowlist entry is the first (S3-F3) (DEC-0094) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The checker WARNs on a redundant allowlist entry, one the glossary already resolves, in addition to the specif (S3-F4) (DEC-0095) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The validator fails any non-blank line in `## Language` that is not an entry, an `_Avoid_:` or `_Aliases_:` li (S3-F5) (DEC-0096) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| Sentences are counted as runs of `.`, `!` or `?` followed by whitespace; abbreviations like "e.g." count as se (S3-F6) (DEC-0097) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| A non-`# Glossary: <name>` H1 WARNs rather than fails, since D-6.4 asks only for an H1. (S3-F7) (DEC-0098) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The CI gate step also validates both glossaries with `--type glossary`, so a format break fails the same job. (S3-F8) (DEC-0099) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The framework glossary seeds Circuit breaker and Fog of war beyond D-6.1; the PRD Appendix D glossary already (S3-F9) (DEC-0100) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The validator suite is a new file, `glossary-validator.bats`, rather than cases in `validate-artifact.bats`, t (S3-F10) (DEC-0101) | agent | proposed | implementer F's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-f.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-f.md#assumptions |
| The header date is the first `**Date:**` line before the first H2. A date line further down does not gate the (S3-G1) (DEC-0102) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A sprint block runs from its `## Sprint N` heading to the next H2 of any kind. Headings inside fenced code are (S3-G2) (DEC-0103) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A Seams block passes only with at least one table row below its separator line. A heading with only the header (S3-G3) (DEC-0104) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| An earlier or undated plan WARNs once, and only when at least one sprint block lacks the block. (S3-G4) (DEC-0105) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `--setup` is split on whitespace into an argv and never passed to `bash -c`. This keeps the no-`bash -c` rule. (S3-G5) (DEC-0106) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A `--setup` failure or timeout exits 2. TIMEOUT (exit 5) is kept for test runs. (S3-G6) (DEC-0107) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Verdict precedence judges the red side first (timeout, then DECOY, then NOT_A_RED), then the green side (timeo (S3-G7) (DEC-0108) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Both runs always happen, so `--json` reports both exits. (S3-G8) (DEC-0109) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A red exit of 126 or 127 is NOT_A_RED alongside the D-7.6 patterns. The bats patterns also cover the gather fa (S3-G9) (DEC-0110) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| With `timeout` or `gtimeout`, exit 124 means a timeout. So does exit 137 once the limit has elapsed. A test th (S3-G10) (DEC-0111) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Each run gets its own process group through `set -m`, so a timeout or an interrupt stops the whole tree it spa (S3-G11) (DEC-0112) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| A path counts as a test path for the WARN if it is under `test/`, `tests/`, `spec/`, `__tests__/`, `testdata/` (S3-G12) (DEC-0113) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `--test-file` must be relative to the repository root. `--red` and `--green` values starting with `-` are reje (S3-G13) (DEC-0114) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| Exit-2 errors print to stderr only. `--json` emits its object for verdicts 0, 1, 3, 4 and 5, with exits set to (S3-G14) (DEC-0115) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `reviewing-code` gains the allowed-tools and `execute_commands` grant for the script, so the Phase 2 instructi (S3-G15) (DEC-0116) | agent | proposed | implementer G's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-g.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-g.md#assumptions |
| `checksums.json` was refreshed for git-tracked files only: changed tracked files were re-hashed, new tracked f (S3-H1) (DEC-0117) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The fixture sync is in scope as a release surface. Without it, the required `sync-fixtures.sh --check` would f (S3-H2) (DEC-0118) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The CHANGELOG gains a `### Migration` heading, following the release-level "Migration guide" heading already i (S3-H3) (DEC-0119) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The cycle-128 surfaces in hooks-reference get one table of their own. `chart-guard.sh` and the FR-8 lint are g (S3-H4) (DEC-0120) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| Fixed now holds only the fix to pre-existing behaviour (`validate-gitignore-state.sh`). Fixes to code that had (S3-H5) (DEC-0121) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| The E2E rows that H ran with read-only commands are marked H. The lead's G-1 to G-4 and G-7 rows keep the lead (S3-H6) (DEC-0122) | agent | proposed | implementer H's call while building sprint-254, recorded as an [ASSUMPTION decision] line in reviewer-h.md; alternatives not enumerated there | grimoires/loa/a2a/sprint-254/reviewer-h.md#assumptions |
| A `proposed` row carries `proposed_by` (the voice that proposed it) and `decided_by` null; `decided_by` is set (D21) (DEC-0123) | agent | proposed | a decision nobody has confirmed has no decider; attribution of the proposal is what the row records (implementer B following SDD §3.1 and A31) | grimoires/loa/prd.md#e-decisions-taken-on-the-operators-behalf |
| The PRD Status line is a planning-time default only, not a live unattended signal (DEC-0124) | agent | proposed | otherwise every operator confirm after an autonomous cycle records decided_by agent and /chart refuses forever (Bridgebuilder F-003) | grimoires/loa/a2a/sprint-254/bb-anthropic.md#F-003 |
Confirm with /decisions confirm.

</details>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I04 — fix-commit — 2026-10-13

- reference: 3758ddd0edec
- files: .loa.config.yaml.example

Summary:

fix(cycle-128): Bridgebuilder round on PR #1279 — 17 findings fixed with tests, 4 refuted with evidence (triage in the PR comment): dec-write-lib.sh treats the PRD Status line as a planning-time default only (new and decide still land proposed under an autonomous PRD) while the context verdict, attribution and the operator-only operations follow live signals, so /decisions confirm records decided…

Evidence:

~~~~diff
commit 3758ddd0edecb00c459fe5ab26405d6b4fd8e75f
Date: 2026-10-13T20:27:53+11:00

fix(cycle-128): Bridgebuilder round on PR #1279 — 17 findings fixed with tests, 4 refuted with evidence (triage in the PR comment): dec-write-lib.sh treats the PRD Status line as a planning-time default only (new and decide still land proposed under an autonomous PRD) while the context verdict, attribution and the operator-only operations follow live signals, so /decisions confirm records decided_by operator and /chart is not refused in a repository whose last PRD ran unattended (Anthropic F-003; recorded as DEC-0124); validate-artifact.sh --type decisions applies history rules in merge-base mode (an unchanged base prefix, any number of legal appended transitions, a content field set when any appended transition legitimises it; the strict single-write rules stay on --base-file) and no longer uses the jq 1.6-only IN builtin (F-002, F-012); dec-write-lib.sh honours LOA_PROJECT_ROOT and the validator passes its own PROJECT_ROOT to the context probe (F-017); the SessionStart decisions surface prints one WARNING when enabled without yq v4 or jq, reading the config by a plain-text fallback (F-014), plus a regression test that an uppercase summary survives the clean regex (F-001, refuted); red-test-check.sh applies the shell, launcher and inline-code denials before any configured red_test.command or red_test.setup (a configured string only widens the runner list) and refuses a config-only acceptance when .loa.config.yaml differs from the base branch unless --trust-config is given (OpenAI RTC-001; RTC-21 and RTC-27; the example config says so); the review skill's invocation is spelled --red <sha> --json so the explicit grant admits it (CI CMP-188); chart-ticket.sh epic reuses an existing map epic for the slug after a failed doc write and refuses when several exist, close --consumed-by on a closed or abandoned map is a no-op, research-begin waits one second past its marker, and demote_headings uses the shared CommonMark fence tracker (CHART-001/F-005, F-013, CHART-002, F-016); fence SP-1 also blocks git checkout -p|--patch of a spike ref and any HEAD/@ ancestor spelling as a push refspec source from a spike checkout, with format-patch/am and archive added to the documented misses (F-015; corpus D99/D100 block, B77/B78 allow); the SDD Open Questions check matches Resolved as a whole word (F-007); the one GNU-only sed insert in the new tests is a portable prepend (F-008); the validator's usage header and the CHANGELOG Migration note state the live-plan Date rule as implemented (F-004); the PRD's 21 operator-behalf decisions carry [ASSUMPTION decision] tags citing their ledger rows, D21 seeded as DEC-0123, so the PRD gate exercises itself (F-010); sprint.md's seed status reads proposed, the Appendix D free-form sentence records its supersession by the r254-2 runner allowlist, and Appendix A statuses read Complete (F-009). Refuted: F-001 (the surface's jq compiles and keeps A-Z), F-011 (the sanitizer accepts content or a path), SPK-001 and F-006 (documented fence and symlink acceptances). REPO-MAP regenerated with its checksum; checksums.json refreshed for the changed tracked files. Verification: see the PR triage comment.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index bf3e473b..918541d7 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -2904,7 +2904,10 @@ structured_handoff:
 # check WARN.
 #
 # red_test:
-#   # The project's test command; the exact string (whitespace-normalised) is accepted.
+#   # The project's test command; the exact string (whitespace-normalised) is accepted,
+#   # unless it starts with a shell, a launcher or an inline-code interpreter (those are refused
+#   # even here). A red_test change on the branch under review makes the check refuse until the
+#   # reviewer passes --trust-config.
 #   command: "make test"
 #   # The exact --setup string accepted besides the runner list (e.g. a dependency install).
 #   setup: "npm ci"
~~~~

## I05 — issue — 2026-10-13

- reference: #1281
- files: .claude/scripts/flatline-orchestrator.sh

Summary:

KF-041: Flatline Phase 2 cross-scoring degrades to one scorer on every planning review (recurrence 4) — record scorer failure_class in the final JSON — ## Symptom A two-voice Flatline planning review (`codex-headless` + `claude-headless`, Phase 1 reviews fine) ends with Phase 2 cross-scoring degraded: every item carries `gpt_score: null`, `scorers_available: 1`, `source: opus_scored`; the consens…

Evidence:

~~~~~text
# issue #1281: KF-041: Flatline Phase 2 cross-scoring degrades to one scorer on every planning review (recurrence 4) — record scorer failure_class in the final JSON

- url: https://github.com/0xHoneyJar/loa/issues/1281
- created_at: 2026-10-13T22:36:33Z
- state: open

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Symptom

A two-voice Flatline planning review (`codex-headless` + `claude-headless`, Phase 1 reviews fine) ends with Phase 2 cross-scoring degraded: every item carries `gpt_score: null`, `scorers_available: 1`, `source: opus_scored`; the consensus line reads `HIGH=0 DISPUTED=0 LOW=0 BLOCKERS=n (0% agreement)`; status DEGRADED, confidence degraded, exit 6; no HIGH_CONSENSUS set is produced. Phase 2 reports `Total cost: 0 cents`, and the final JSON's `execution` block carries no per-call scorer status, so the cause (empty content, schema rejection, timeout) is never recorded.

## Recurrence

`grimoires/loa/known-failures.md` KF-041, recurrence 4:

- 2026-10-07 cycle-127: prd, sdd and sprint runs (`flatline-28236-11307`, `flatline-19206-31034`, sprint run), all identical shape.
- 2026-10-13 cycle-128: prd, sdd and sprint runs, same shape.
- 2026-10-14 cycle-129: prd (`flatline-24474-6736`), sdd and sprint runs, same shape (claude-headless via `claude-fallback`, codex-headless as `gpt-5.5`).

Every planning review since cycle 127 has run in this shape. By the ledger's own rule (recurrence ≥ 3) this is structural, not a retry candidate; the reading guide says to integrate the raw per-voice improvements by judgment and not to re-run to chase consensus.

## Where

`.claude/scripts/flatline-orchestrator.sh` Phase 2 (`scoring-engine`): the codex-headless scorer returns null scores for every item while its Phase 1 review succeeded. The vq-aggregate envelope names voices; scorers are invisible in the final JSON.

## Candidate fix

1. Record each Phase 2 scorer call's outcome in the final JSON `execution` block: `scorers: [{voice, status, failure_class, latency_ms, schema_enforced}]`, so a null-score run names its cause.
2. Retain the raw scorer output with `--keep-temp` by default when any scorer returns null for every item.
3. Treat "every score null from one scorer" as a scorer failure (`scoring_degraded` with a named class) rather than silent degradation, and surface it in the orchestrator's summary line.
4. Once the cause is recorded, fix the scorer (likely candidates from the ledger's related entries: KF-002 empty content on reasoning-class models, KF-004 schema-rejected payloads).

## Evidence

- `grimoires/loa/known-failures.md` KF-041 (attempts table, recurrence 4)
- cycle-129 planning records: `grimoires/loa/a2a/flatline/*-final_consensus.json` (prd `flatline-24474-6736`), to be preserved on `record/cycle-129-a2a`
- Decision DEC-0134 (cycle-129): route KF-041 through an upstream issue, no further retries
~~~~
~~~~~

## I06 — fix-commit — 2026-10-14

- reference: 3263bbc4ea22
- files: .loa.config.yaml.example

Summary:

fix(cycle-129): sprint-256 review round r256-1 — a backtick pair outside single quotes is a command substitution to the fence (HIGH-1: heredoc-aware normalisation to the dollar-paren form before any rule runs; unquoted heredoc bodies alternate every backtick, quoted bodies and single quotes stay literal, unbalanced shell quotes fail closed; corpus B79/B84 → quoted delimiters, D143–D148 block the…

Evidence:

~~~~diff
commit 3263bbc4ea22bfc0dff03d522d3308005ad60546
Date: 2026-10-14T14:57:42+11:00

fix(cycle-129): sprint-256 review round r256-1 — a backtick pair outside single quotes is a command substitution to the fence (HIGH-1: heredoc-aware normalisation to the dollar-paren form before any rule runs; unquoted heredoc bodies alternate every backtick, quoted bodies and single quotes stay literal, unbalanced shell quotes fail closed; corpus B79/B84 → quoted delimiters, D143–D148 block the unquoted-heredoc, echo, printf, assignment and dollar-paren shapes, B90/B91 pin the literal cases; knob-off differs from the pre-change hook on exactly D143–D147, DEC-0296); LOW-1 check-knob-readers.sh as a Shell Tests step; LOW-2 run-corpus.sh --knob-off self-check on D122; LOW-3 POSIX touch -t in KS-5; LOW-5 LOA_PROFILE_CONFIG_FILE documented in the example; skill-invariants.md records the harness probe (enforced in the main session until the next user prompt, not in subagents); KF-043 scope corrected by an attempt row (DEC-0297); CHANGELOG Fixed entry; corpus 91/91 · 148/148, hook bats 476/0, lints green (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index f2ba980e..a82de682 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -29,6 +29,9 @@
 # config key read the same configuration under every profile
 # (.claude/data/floor.yaml lists them; tests/unit/profile-floor.bats pins it).
 # An unknown value warns and falls back to standard.
+# Seam: the environment variable LOA_PROFILE_CONFIG_FILE points the profile
+# library at another config file (hooks pass their own test config through it);
+# it is honoured outside bats, so treat it as part of the hook environment.
 loa:
   profile: standard   # lean | standard | full
 
~~~~

## I07 — fix-commit — 2026-10-14

- reference: 77455afb372f
- files: .loa.config.yaml.example

Summary:

fix(cycle-129): sprint-256 review round r256-2 — the example ships the nine profile keys only as commented, profile-governed lines so a copied example follows loa.profile (HIGH-2; PL-4 pins null raw keys, standard as the effective value, and lean/full copies with no override; AC-2.4 restated); LI-2/3/5/8 and PL-1 negated assertions as run plus status (LOW-8); check-knob-readers.sh escapes every E…

Evidence:

~~~~diff
commit 77455afb372fbba4a67c51232598d17099a16182
Date: 2026-10-14T15:35:21+11:00

fix(cycle-129): sprint-256 review round r256-2 — the example ships the nine profile keys only as commented, profile-governed lines so a copied example follows loa.profile (HIGH-2; PL-4 pins null raw keys, standard as the effective value, and lean/full copies with no override; AC-2.4 restated); LI-2/3/5/8 and PL-1 negated assertions as run plus status (LOW-8); check-knob-readers.sh escapes every ERE metacharacter, skips binaries and fails on a grep error (LOW-9); run-corpus.sh --knob-off requires the D122 sentinel unless --no-self-check (LOW-10); the review and audit skills grant Bash(.claude/scripts/lib/profile-lib.sh knob *) in allowed-tools and capabilities for the shared include steps (CMP-188; byte-neutral trims in both frontmatters); karpathy-config-schema.bats isolates KARPATHY_STATE_DIR and expects the two profile-governed keys commented; CHANGELOG; DEC-0299…DEC-0301 (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index a82de682..7724ab60 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -29,6 +29,9 @@
 # config key read the same configuration under every profile
 # (.claude/data/floor.yaml lists them; tests/unit/profile-floor.bats pins it).
 # An unknown value warns and falls back to standard.
+# The nine keys appear in this file only as commented lines at their usual
+# place ("Profile-governed … uncomment to pin it"), so a copied example follows
+# the profile you choose; an uncommented key is an explicit override and wins.
 # Seam: the environment variable LOA_PROFILE_CONFIG_FILE points the profile
 # library at another config file (hooks pass their own test config through it);
 # it is honoured outside bats, so treat it as part of the hook environment.
@@ -312,7 +315,8 @@ known_failures:
   # NOTHING while this flag is false. When true it is loud-but-nonblocking: it
   # warns visibly ([KF-SURFACE] WARNING) if the surface is enabled-but-degraded
   # (known-failures.md unreadable or zero entries parsed).
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
 
 # -----------------------------------------------------------------------------
 # Decision ledger (grimoires/loa/decisions.yaml)
@@ -325,7 +329,8 @@ decisions:
   # proposed and open rows (id, status, summary) at session start, inside the L6
   # untrusted-content fence, plus a notice when .run/unattended.json is stale.
   # DEFAULT-OFF: the hook prints nothing while this is false and always exits 0.
-  surface_at_session_start: false
+  # Profile-governed (loa.profile; standard = false). Uncomment to pin it:
+  # surface_at_session_start: false
   # Hours after which `dec-write-lib.sh context --set-unattended`'s marker is stale
   # and ignored (a marker from another session is stale at once).
   unattended_marker_ttl_hours: 24
@@ -1358,7 +1363,8 @@ upstream_proposals:
 guardrails:
   # Input guardrails (pre-execution)
   input:
-    enabled: false
+    # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+    # enabled: false
 
     # PII Filter: Detect and redact sensitive data before processing
     # Actions: redact (replace with placeholder), anonymize (generic value)
@@ -1404,7 +1410,9 @@ guardrails:
   # Danger Level Enforcement: Tool risk classification
   # Levels: safe, moderate, high, critical
   danger_level:
-    enforce: false                # see the default-off note above the block
+    # Profile-governed (loa.profile; standard = false, full = true); see the
+    # default-off note above the block. Uncomment to pin it:
+    # enforce: false
     interactive:
       safe: execute               # Execute immediately
       moderate: execute_with_notice  # Brief notice in output
@@ -1431,8 +1439,9 @@ guardrails:
 # Uses skill postludes to silently scan for discoveries and extract learnings.
 # Mirrors the invisible prompt enhancement pattern from v1.17.0.
 invisible_retrospective:
-  # Master toggle - set to false to disable all invisible retrospective
-  enabled: true
+  # Master toggle - set to false to disable all invisible retrospective.
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # enabled: true
 
   # Always log to trajectory (even when disabled) - useful for debugging
   log_to_trajectory: true
@@ -2932,7 +2941,8 @@ karpathy_principles:
   # G-1 — master switch for the PostToolUse:Write|Edit surgical-diff hook
   # at .claude/hooks/quality/karpathy-surgical-diff-check.sh. When false,
   # the hook fast-paths to exit 0 in <10ms.
-  surgical_diff_warning: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # surgical_diff_warning: true
 
   # G-1 — per-session diff-lines threshold. When the session accumulator
   # exceeds this, the hook emits a [karpathy-surgical-warn] stderr line
@@ -2950,7 +2960,8 @@ karpathy_principles:
   # G-3 — when true, /implement refuses to write code if sprint.md lacks a
   # "Success criteria" / "Acceptance criteria" / "Verification" section.
   # Operator can [Skip with rationale] to override per-invocation.
-  require_success_criteria: true
+  # Profile-governed (loa.profile; standard = true, lean = false). Uncomment to pin it:
+  # require_success_criteria: true
 
   # warn | block. v1 honors only "warn" — block-mode is reserved for v2 to
   # avoid surprise breaking changes during initial rollout. Even with
@@ -2962,7 +2973,8 @@ karpathy_principles:
 # -----------------------------------------------------------------------------
 structured_handoff:
   # Master toggle for the L6 SessionStart surfacing hook.
-  enabled: false
+  # Profile-governed (loa.profile; standard = false, full = true). Uncomment to pin it:
+  # enabled: false
   # Per-handoff body byte cap at surfacing.
   surface_max_chars: 4000
   # cycle-121: skip UNREAD handoffs older than N days at surfacing (0 = never
~~~~

## I08 — fix-commit — 2026-10-14

- reference: 9c4ed3198c78
- files: .claude/scripts/loa-status.sh

Summary:

fix(cycle-129): sprint-256 audit round r256-5 — /loa Profile line reports an off guardrail control (DEC-0161 mitigation; PL-14); shell reserved words are transparent prefixes in the heredoc per-segment scan and Dockerfile, pre-commit and gitlab-ci targets are executable content (D169–D178, B100); FR-GH-1 covers gh api graphql mutations, full-URL and leading-slash paths, --hostname and a non-liter…

Evidence:

~~~~diff
commit 9c4ed3198c7891882ca77847e37bd10475885779
Date: 2026-10-14T16:45:43+11:00

fix(cycle-129): sprint-256 audit round r256-5 — /loa Profile line reports an off guardrail control (DEC-0161 mitigation; PL-14); shell reserved words are transparent prefixes in the heredoc per-segment scan and Dockerfile, pre-commit and gitlab-ci targets are executable content (D169–D178, B100); FR-GH-1 covers gh api graphql mutations, full-URL and leading-slash paths, --hostname and a non-literal method (D179–D184, B98–B99; the corpus lint admits api.github.com); profile-lib WARNs when LOA_PROFILE_CONFIG_FILE redirects a live read; check-knob-readers.sh matches the trailing two components of three-part keys (PL-17 bypass shapes); DEC-0307…DEC-0311 (sprint-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/scripts/loa-status.sh b/.claude/scripts/loa-status.sh
index a4217e7a..00ccb0c1 100755
--- a/.claude/scripts/loa-status.sh
+++ b/.claude/scripts/loa-status.sh
@@ -955,7 +955,12 @@ display_profile_line() {
     note=""
     if [[ "$(loa_profile_source 2>/dev/null)" == "invalid" ]]; then note="unknown loa.profile, using standard; "; fi
     ov=$(loa_profile_overrides 2>/dev/null | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')
-    printf '%s (%sexplicit overrides: %s)' "${name:-standard}" "$note" "${ov:-none}"
+    # cycle-129 audit r256-5 (DEC-0161 mitigation): say so when either guardrail
+    # control resolves to off, whatever turned it off (profile or explicit key).
+    gn=""
+    [[ "$(loa_knob guardrails.input.enabled false 2>/dev/null)" == true ]] || gn="input guardrails off"
+    [[ "$(loa_knob guardrails.danger_level.enforce false 2>/dev/null)" == true ]] || gn="${gn:+$gn, }danger-level enforcement off"
+    printf '%s (%sexplicit overrides: %s)%s' "${name:-standard}" "$note" "${ov:-none}" "${gn:+ · $gn}"
   ) || line=""
   echo -e "${BOLD}Profile:${NC} ${line:-standard (explicit overrides: unavailable)}"
   return 0
~~~~

## I09 — fix-commit — 2026-10-14

- reference: cf88e4270d58
- files: .claude/adapters/loa_cheval/audit/modelinv.py,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts

Summary:

fix(cycle-129): sprint-257 review round r257-1 — a declared dispatch_group: local is enforced, not trusted (HIGH-1: the local-hop rule — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost — stated once in endpoint_policy and applied at load, at request time by TransportPolicy.local, in hop-locality.py (endpoint_not_local / endpoint_missing / cli_provider), in Br…

Evidence (first 200 of 504 lines):

~~~~diff
commit cf88e4270d586cbfd1faab2258edfd3e4e978dfd
Date: 2026-10-14T20:13:12+11:00

fix(cycle-129): sprint-257 review round r257-1 — a declared dispatch_group: local is enforced, not trusted (HIGH-1: the local-hop rule — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost — stated once in endpoint_policy and applied at load, at request time by TransportPolicy.local, in hop-locality.py (endpoint_not_local / endpoint_missing / cli_provider), in Bridgebuilder applyLocality and in MODELINV hop_locality; a CLI provider never carries the label; an https endpoint on a local host needs no opt-in); keyless: false beside auth: local is refused by name (LOW-2); the probe helper CLI turns every load failure into one JSON line and exit 78 (LOW-3); the locality fixtures declare a loader-admissible localbox and load it through the real loader (LOW-1); DISS-C-002 refuted; tests test_local_dispatch_group_rule.py, LOC-9/LOC-10, FLL-8/FLL-9, trusted-config.test.ts (21), dist rebuilt; cheval pytest 3256 passed (2 baseline failures), Sprint 3 bats 136/136, npm 867/868 (KF-036), corpus 99/99 · 184/184; multi-model-reference FR-8 paragraph, CHANGELOG Fixed entry and Migration row; DEC-0331…DEC-0339 (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/loa_cheval/audit/modelinv.py b/.claude/adapters/loa_cheval/audit/modelinv.py
index 1ff0e1ad..acf885d7 100644
--- a/.claude/adapters/loa_cheval/audit/modelinv.py
+++ b/.claude/adapters/loa_cheval/audit/modelinv.py
@@ -471,9 +471,17 @@ def locality_mode_of(hounfour: Dict[str, Any]) -> Optional[str]:
 
 
 def hop_locality_of(provider: str, model_id: Optional[str], hounfour: Dict[str, Any]) -> str:
-    """`local` when the hop's model declares dispatch_group `local` (D-8.0), else `hosted`."""
-    _prov, entry = _provider_model_entry(provider, model_id, hounfour)
-    return "local" if entry.get("dispatch_group") == "local" else "hosted"
+    """`local` when the hop's model declares dispatch_group `local` (D-8.0) AND the provider honours it — an
+    HTTP provider whose endpoint host passes the local-hop rule (D-8.1, r257-1) — else `hosted`, so the record
+    never says local for a hop the rule calls hosted."""
+    from loa_cheval.config.endpoint_policy import local_endpoint_host
+
+    prov, entry = _provider_model_entry(provider, model_id, hounfour)
+    if entry.get("dispatch_group") != "local":
+        return "hosted"
+    if str(prov.get("type") or "").endswith("-headless") or entry.get("kind") == "cli":
+        return "hosted"
+    return "local" if local_endpoint_host(prov.get("endpoint")) is not None else "hosted"
 
 
 def hop_telemetry(hop: Optional[str], hounfour: Dict[str, Any]) -> Dict[str, Any]:
diff --git a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
index 52bbcdd8..84b32fbb 100644
--- a/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
+++ b/.claude/skills/bridgebuilder-review/dist/.build-manifest.json
@@ -1,7 +1,7 @@
 {
   "version": "1.0",
-  "generated_at": "2026-10-14T07:40:42Z",
-  "source_hash": "ffa2ae2ff364c468d601f0fc7a1ff0f21a1495d138efcc18a0e94c0d7b761d54",
+  "generated_at": "2026-10-14T08:50:46Z",
+  "source_hash": "b4e84888ce6f026aa7ffa758e24a1ae7262055fe3bcdebff5a3c49dd5c859cf6",
   "file_count": 43,
   "files": [
     {
@@ -46,7 +46,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/config.ts",
-      "sha256": "4a17672d468d763c6eb9dfe24a9c0ecf1327ab2e22c36b1a3cca454c949b0dce"
+      "sha256": "06f39340b69c9f734738ba739ee4d01be9ab9fbfdf530587541c2f928c5cbcf9"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/cache.ts",
@@ -130,7 +130,7 @@
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
-      "sha256": "b047232236a1219e578fe7151b4aba16ecedcd05ea71931ef9eaf18f9a705af8"
+      "sha256": "1b13a035d7dd98ef48cbec7fd76c96ddc9a6e0e9e40984dcbd03bfee1cb33ec5"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts b/.claude/skills/bridgebuilder-review/dist/config.d.ts
index 87900fe9..b1d8d78a 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts
@@ -198,10 +198,32 @@ export declare function loadTrustedConfig(opts: {
 }, deps?: TrustedConfigDeps): TrustedConfig;
 /** One startup line naming where the trusted config was read from (main.ts prints it with the warnings). */
 export declare function trustedConfigStartupLine(t: TrustedConfig): string;
+/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
+export declare const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
 /**
- * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
- * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
+ * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
+ * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
+ * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
+ * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
+ * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
+ * `host` is the canonical host for a refusal message ("" when there is no endpoint).
  */
+export declare function localEndpointHost(endpoint: unknown): {
+    ok: boolean;
+    host: string;
+};
+/**
+ * The locality decision for one voice. `declared`: the trusted config marks it `dispatch_group: local` (the model's own
+ * entry when declared, else the provider-level key, else every declared model of the provider). `local`: declared AND
+ * the provider honours it — not a CLI provider, and its endpoint host passes the local-hop rule (D-8.1, r257-1: a
+ * declared locality is enforced, not trusted). `reason` names why a declared voice is still hosted.
+ */
+export declare function localVoiceDecision(provider: string, modelId: string, trusted: TrustedConfig): {
+    local: boolean;
+    declared: boolean;
+    reason?: string;
+};
+/** True when the voice is local by `localVoiceDecision` (declared `dispatch_group: local` AND the endpoint honours it). */
 export declare function isLocalVoice(provider: string, modelId: string, trusted: TrustedConfig): boolean;
 /**
  * D-8.1: under `hounfour.locality: local_voices` drop every planned voice whose provider is not local, each with the named
diff --git a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
index 8b3cb0bd..7459b702 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
+++ b/.claude/skills/bridgebuilder-review/dist/config.d.ts.map
@@ -1 +1 @@
-{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
+{"version":3,"file":"config.d.ts","sourceRoot":"","sources":["../resources/config.ts"],"names":[],"mappings":"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"}
\ No newline at end of file
diff --git a/.claude/skills/bridgebuilder-review/dist/config.js b/.claude/skills/bridgebuilder-review/dist/config.js
index 7b105e84..480c2e81 100644
--- a/.claude/skills/bridgebuilder-review/dist/config.js
+++ b/.claude/skills/bridgebuilder-review/dist/config.js
@@ -2,6 +2,7 @@ import { execFile, execFileSync, execSync } from "node:child_process";
 import { promisify } from "node:util";
 import { readFile } from "node:fs/promises";
 import { closeSync, existsSync, fstatSync, openSync, readFileSync, statSync } from "node:fs";
+import { isIPv6 } from "node:net";
 import { join } from "node:path";
 import { z } from "zod/v4";
 import { GENERATED_MODEL_REGISTRY } from "./config.generated.js";
@@ -409,6 +410,8 @@ const ProviderEntrySchema = z.looseObject({
     auth: z.unknown().optional(),
     allow_insecure_endpoint: z.unknown().optional(),
     dispatch_group: z.unknown().optional(),
+    endpoint: z.unknown().optional(),
+    type: z.unknown().optional(),
     models: z.unknown().optional(),
 });
 const ENV_AUTH_RE = /^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/;
@@ -435,18 +438,26 @@ export function parseProviderDecls(raw, label, warnings) {
         const envMatch = auth !== undefined ? ENV_AUTH_RE.exec(auth) : null;
         const literalAuth = auth !== undefined && auth !== "" && !auth.includes("{env:");
         const modelGroups = {};
+        let modelCount = 0;
+        let cliModels = 0;
         if (e.models !== null && typeof e.models === "object" && !Array.isArray(e.models)) {
             for (const [mid, m] of Object.entries(e.models)) {
                 const g = m !== null && typeof m === "object" ? m.dispatch_group : undefined;
                 modelGroups[mid] = typeof g === "string" ? g : undefined;
+                modelCount += 1;
+                if (m !== null && typeof m === "object" && m.kind === "cli")
+                    cliModels += 1;
             }
         }
+        const cli = (typeof e.type === "string" && e.type.endsWith("-headless")) || (modelCount > 0 && cliModels === modelCount);
         out[name] = {
             keyless: e.keyless === true || literalAuth,
             insecure: e.allow_insecure_endpoint !== undefined && e.allow_insecure_endpoint !== null && e.allow_insecure_endpoint !== false,
             ...(envMatch ? { authEnv: envMatch[1] } : {}),
             ...(typeof e.dispatch_group === "string" ? { dispatchGroup: e.dispatch_group } : {}),
             modelGroups,
+            ...(typeof e.endpoint === "string" ? { endpoint: e.endpoint } : {}),
+            ...(cli ? { cli: true } : {}),
         };
     }
     return out;
@@ -648,20 +659,112 @@ export function trustedConfigStartupLine(t) {
     return `[bridgebuilder] Trusted config: ${where} (mode: ${t.mode}); locality: ${t.locality}; exit_on_degraded: ${t.exitOnDegraded}` +
         (keyless.length > 0 ? `; keyless providers: ${keyless.join(", ")}` : "");
 }
+/** The local-hop rule's wording, shared with cheval (endpoint_policy.LOCAL_RULE_TEXT) and the planner. */
+export const LOCAL_RULE_TEXT = "a loopback or RFC1918 IP literal or localhost";
+function ipv4Octets(host) {
+    const m = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
+    if (!m)
+        return undefined;
+    const parts = m.slice(1).map((s) => (s.length > 1 && s.startsWith("0") ? NaN : Number(s))); // no leading zeros, as Python ipaddress
+    return parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : undefined;
+}
 /**
- * True when the trusted config marks this voice's provider `dispatch_group: local` (D-8.0): the model's own entry when
- * declared, else the provider-level key, else every declared model of the provider. Anything undeclared is hosted.
+ * The local-hop rule (D-8.1, review round r257-1) on a provider endpoint: `ok` when it is an http(s) URL whose host is an
+ * IP literal in a loopback (127.0.0.0/8, ::1) or RFC1918 (10/8, 172.16/12, 192.168/16) range, or the literal `localhost`.
+ * Link-local, metadata, unique-local IPv6, public ranges and every other DNS name fail. A stdlib mirror of the canonical
+ * validator's `check_insecure_optin` host acceptance (the generated TypeScript port does not export it): the authority is
+ * split by hand, not by WHATWG `URL`, so a host such as `0x7f.1` stays a DNS name here exactly as it does in Python.
+ * `host` is the canonical host for a refusal message ("" when there is no endpoint).
  */
-export function isLocalVoice(provider, modelId, trusted) {
+export function localEndpointHost(endpoint) {
+    if (typeof endpoint !== "string" || endpoint.trim() === "")
+        return { ok: false, host: "" };
+    const m = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/([^/?#]*)/.exec(endpoint.trim());
+    if (!m)
+        return { ok: false, host: "unparseable" };
+    const scheme = m[1].toLowerCase();
+    let authority = m[2];
+    const at = authority.lastIndexOf("@");
+    if (at >= 0)
+        authority = authority.slice(at + 1);
+    let host;
+    let port;
+    if (authority.startsWith("[")) {
+        const close = authority.indexOf("]");
~~~~

## I10 — fix-commit — 2026-10-14

- reference: 07110d7052ea
- files: .claude/adapters/cheval.py,.claude/adapters/loa_cheval/audit/modelinv.py,.claude/adapters/loa_cheval/config/loader.py,.claude/adapters/loa_cheval/types.py,.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json,.claude/scripts/adversarial-review.sh,.claude/skills/bridgebuilder-review/dist/.build-manifest.json,.claude/skills/bridgebuilder-review/dist/config.d.ts,.claude/skills/bridgebuilder-review/dist/config.d.ts.map,.claude/skills/bridgebuilder-review/dist/config.js,.claude/skills/bridgebuilder-review/dist/config.js.map,.claude/skills/bridgebuilder-review/resources/config.ts,.loa.config.yaml.example

Summary:

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused…

Evidence (first 200 of 920 lines):

~~~~diff
commit 07110d7052ea531b190ec58a0f429e0718e2365c
Date: 2026-10-14T21:29:39+11:00

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused, exit INVALID_CONFIG), the loader refuses a local model whose fallback_chain reaches a hosted or unresolvable hop, and Bridgebuilder walks the chain in the trusted view (MEDIUM-A1; one implementation endpoint_policy.hop_is_local serves cheval, the loader and MODELINV hop_locality); Bridgebuilder refuses trusted-config drift on a pull request — hounfour.providers, aliases, locality and the secret allowlist compared head vs trusted, exit 5 before any voice is planned, because cheval-delegate spawns cheval from the checkout (MEDIUM-A2); localhost is resolved and checked for loopback at request time (LOW-A1); metadata.locality.degraded_security_review is machine-readable on the audit envelope (LOW-A2); a zero price not marked open_weight warns in the budget gate (LOW-A3; metering guard → bd-yzzb9); DISS-001 RFC1918 opt-in accepted by design; tests test_locality_fallback_plan.py (13), test_local_dispatch_group_rule.py (+9), LOC-1/4/10, BUD-3/7, trusted-config.test.ts (35), dist rebuilt; cheval pytest 3277 passed (2 baseline), Sprint 3 bats 137/137, npm 881/882 (KF-036), corpus 99/99 · 184/184; CHANGELOG Fixed entry + two Migration rows; DEC-0340…DEC-0351 (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/adapters/cheval.py b/.claude/adapters/cheval.py
index 2e9e033d..d1b0ed04 100644
--- a/.claude/adapters/cheval.py
+++ b/.claude/adapters/cheval.py
@@ -420,6 +420,43 @@ def _plan_around_agy(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Di
     return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
 
 
+def _entry_is_local(entry: Any, hounfour: Dict[str, Any]) -> bool:
+    """The local-hop rule (SDD D-8.1) for one resolved hop: `endpoint_policy.hop_is_local` on the merged view, and a
+    `kind: cli` hop (the resolver's adapter_kind) is hosted whatever its label says."""
+    from loa_cheval.config.endpoint_policy import hop_is_local
+    if getattr(entry, "adapter_kind", "http") == "cli":
+        return False
+    return hop_is_local(hounfour, getattr(entry, "provider", ""), getattr(entry, "model_id", ""))
+
+
+def _plan_around_locality(chain: Any, hounfour: Dict[str, Any]) -> Tuple[Any, List[Dict[str, Any]]]:
+    """cycle-129 audit a257-1 MEDIUM-A1 (a), SDD D-8.1: under `hounfour.locality: local_voices` cheval — the process
+    that sends the prompt — plans around every hop that fails the local-hop rule, the way `_plan_around_agy` plans
+    around the agy opt-in: the hop is dropped before the walk (never dispatched, not in models_requested) with one
+    stderr line naming it, and returned as `[{model, provider, reason: locality_refused}]` for MODELINV
+    `models_not_planned`. A chain left empty raises `LocalityRefusedError` — never a silent reroute. Under `hosted` (or
+    unset) the chain is returned unchanged."""
+    if not isinstance(hounfour, dict) or hounfour.get("locality") != "local_voices":
+        return chain, []
+    from loa_cheval.types import LocalityRefusedError
+    primary = chain.entries[0] if chain.entries else None
+    hosted = [e for e in chain.entries if not _entry_is_local(e, hounfour)]
+    if not hosted:
+        return chain, []
+    for e in hosted:
+        where = "primary" if e is primary else f"fallback of {chain.primary_alias}"
+        print(f"locality: local_voices refuses hosted hop {e.provider}:{e.model_id} ({where})", file=sys.stderr)
+    if len(hosted) == len(chain.entries):
+        raise LocalityRefusedError(
+            f"locality: local_voices refuses every hop of {chain.primary_alias} "
+            f"({', '.join(e.canonical for e in hosted)}): none passes the local-hop rule (dispatch_group local on an "
+            f"HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or localhost)"
+        )
+    kept = [e for e in chain.entries if e not in hosted]
+    skipped = [{"model": e.canonical, "provider": e.provider, "reason": "locality_refused"} for e in hosted]
+    return _dc_replace(chain, entries=type(chain.entries)(kept)), skipped
+
+
 def _get_adapter_for_entry(entry: Any, hounfour: Dict[str, Any]):
     """Select the adapter for a single ResolvedEntry honoring `adapter_kind`.
 
@@ -1811,6 +1848,33 @@ def cmd_invoke(args: argparse.Namespace) -> int:
     # the full resolved chain (cycle-127 review r251-1 G1: a gated agy hop is
     # planned around before models_requested is taken; r251-4 S8, audit n2).
     _chain, _models_not_planned = _plan_around_agy(_chain, hounfour)
+    # cycle-129 audit a257-1 MEDIUM-A1 (a): under hounfour.locality local_voices the hosted hops are planned around;
+    # a chain with no local hop is refused before any dispatch, with a MODELINV row (failure_class locality_refused).
+    from loa_cheval.types import LocalityRefusedError as _LocalityRefusedError
+    try:
+        _chain, _models_not_planned_loc = _plan_around_locality(_chain, hounfour)
+    except _LocalityRefusedError as _e:
+        print(_error_json(_e.code, _e.detail, retryable=False, failure_class=_e.failure_class), file=sys.stderr)
+        try:
+            _emit_modelinv(
+                models_requested=[e.canonical for e in _chain.entries],
+                models_succeeded=[],
+                models_failed=[{"model": e.canonical, "provider": e.provider, "error_class": "INVALID_CONFIG",
+                                "failure_class": _e.failure_class, "message_redacted": _e.detail}
+                               for e in _chain.entries],
+                operator_visible_warn=True,
+                capability_class=getattr(binding, "capability_class", None),
+                calling_primitive=(getattr(args, "skill", None) or agent_name),
+                models_not_planned=_models_not_planned or None,
+                **_modelinv_hop_telemetry(_chain.entries[0].canonical, hounfour),
+            )
+        except Exception as _emit_err:  # noqa: BLE001 — fail-soft; never mask the refusal
+            print(f"[AUDIT-EMIT-FAILED] {type(_emit_err).__name__}: {_emit_err}", file=sys.stderr)
+        return EXIT_CODES["INVALID_CONFIG"]
+    if _models_not_planned_loc:
+        _models_not_planned = list(_models_not_planned) + _models_not_planned_loc
+        if _auth_type_resolved is not None:
+            _auth_type_resolved = _chain.entries[0].auth_type
     if _models_not_planned and _auth_type_resolved is not None:
         _auth_type_resolved = _chain.entries[0].auth_type
     _modelinv_capability_class = getattr(binding, "capability_class", None)
diff --git a/.claude/adapters/loa_cheval/audit/modelinv.py b/.claude/adapters/loa_cheval/audit/modelinv.py
index acf885d7..b1f24f75 100644
--- a/.claude/adapters/loa_cheval/audit/modelinv.py
+++ b/.claude/adapters/loa_cheval/audit/modelinv.py
@@ -473,15 +473,11 @@ def locality_mode_of(hounfour: Dict[str, Any]) -> Optional[str]:
 def hop_locality_of(provider: str, model_id: Optional[str], hounfour: Dict[str, Any]) -> str:
     """`local` when the hop's model declares dispatch_group `local` (D-8.0) AND the provider honours it — an
     HTTP provider whose endpoint host passes the local-hop rule (D-8.1, r257-1) — else `hosted`, so the record
-    never says local for a hop the rule calls hosted."""
-    from loa_cheval.config.endpoint_policy import local_endpoint_host
+    never says local for a hop the rule calls hosted. ONE implementation: ``endpoint_policy.hop_is_local`` (the
+    rule cheval's planner applies under ``local_voices``, audit a257-1 MEDIUM-A1)."""
+    from loa_cheval.config.endpoint_policy import hop_is_local
 
-    prov, entry = _provider_model_entry(provider, model_id, hounfour)
-    if entry.get("dispatch_group") != "local":
-        return "hosted"
-    if str(prov.get("type") or "").endswith("-headless") or entry.get("kind") == "cli":
-        return "hosted"
-    return "local" if local_endpoint_host(prov.get("endpoint")) is not None else "hosted"
+    return "local" if hop_is_local(hounfour, provider, model_id) else "hosted"
 
 
 def hop_telemetry(hop: Optional[str], hounfour: Dict[str, Any]) -> Dict[str, Any]:
diff --git a/.claude/adapters/loa_cheval/config/loader.py b/.claude/adapters/loa_cheval/config/loader.py
index 8539cac5..15527de1 100644
--- a/.claude/adapters/loa_cheval/config/loader.py
+++ b/.claude/adapters/loa_cheval/config/loader.py
@@ -25,7 +25,7 @@ import sys
 from pathlib import Path
 from typing import Any, Dict, List, Optional, Tuple
 
-from loa_cheval.config.endpoint_policy import normalise_keyless, validate_providers
+from loa_cheval.config.endpoint_policy import normalise_keyless, validate_local_fallbacks, validate_providers
 from loa_cheval.config.interpolation import interpolate_config, redact_config
 from loa_cheval.types import ConfigError
 
@@ -702,6 +702,9 @@ def load_config(
     # and keyless providers must declare context_window and dispatch_group.
     # Runs on the interpolated endpoint so a templated value is checked as sent.
     validate_providers(merged)
+    # cycle-129 audit a257-1 MEDIUM-A1 (b): under hounfour.locality local_voices a
+    # dispatch_group local model whose fallback_chain reaches a hosted hop is refused.
+    validate_local_fallbacks(merged)
 
     return merged, sources
 
diff --git a/.claude/adapters/loa_cheval/types.py b/.claude/adapters/loa_cheval/types.py
index 14e473f2..5d14b314 100644
--- a/.claude/adapters/loa_cheval/types.py
+++ b/.claude/adapters/loa_cheval/types.py
@@ -540,6 +540,18 @@ class AgyOptInRequiredError(ConfigError):
         super().__init__(message, context={"failure_class": self.failure_class})
 
 
+class LocalityRefusedError(ConfigError):
+    """Under ``hounfour.locality: local_voices`` every hop of the resolved chain fails the local-hop rule (cycle-129
+    audit a257-1 MEDIUM-A1, SDD D-8.1): cheval refuses the call before any dispatch — never a silent reroute.
+    ``failure_class: locality_refused`` (also in ``context``) is the machine-readable seam MODELINV records."""
+
+    failure_class = "locality_refused"
+
+    def __init__(self, message: str):
+        super().__init__(message, context={"failure_class": self.failure_class})
+        self.detail = message   # (the bare refusal, `locality: local_voices refuses every hop of <alias> …`)
+
+
 class AuthRevokedError(ChevalError):
     """Runtime auth-credential revocation on a CLI/subscription leg (KF-017/#1071).
 
diff --git a/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json b/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json
index 4ce201c2..c3af4ff7 100644
--- a/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json
+++ b/.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json
@@ -63,8 +63,8 @@
             "type": "boolean"
           },
           "failure_class": {
-            "description": "cycle-127 review r251-2 K2. A finer class under error_class: opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG); context_window_refused (cycle-129 FR-7, SDD D-7.2: the hop's estimated input exceeded its declared context_window, the hop was refused and the input never truncated, error_class ROUTING_MISS). Optional/additive.",
-            "enum": ["opt_in_required", "context_window_refused"]
+            "description": "cycle-127 review r251-2 K2. A finer class under error_class: opt_in_required (an agy-alone chain refused by hounfour.headless.agy_opt_in, error_class INVALID_CONFIG); context_window_refused (cycle-129 FR-7, SDD D-7.2: the hop's estimated input exceeded its declared context_window, the hop was refused and the input never truncated, error_class ROUTING_MISS); locality_refused (cycle-129 audit a257-1 MEDIUM-A1, SDD D-8.1: under hounfour.locality local_voices no hop of the chain passes the local-hop rule, the call was refused before any dispatch, error_class INVALID_CONFIG). Optional/additive.",
+            "enum": ["opt_in_required", "context_window_refused", "locality_refused"]
           },
           "provider": {
             "description": "cycle-104 Sprint 2 (T2.6 / FR-S2.3). Provider key for this entry (e.g. openai, anthropic, google). Optional for backward compat; new emitters MUST populate.",
@@ -758,7 +758,7 @@
       ]
     },
     "models_not_planned": {
-      "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. Optional/additive.",
+      "description": "Cycle-127 review r251-1 G1 (SDD D-1.3/D-1.6): chain hops cheval did NOT plan \u2014 never dispatched, not in models_requested, not a failure (verdict quality counts planned hops only; no circuit-breaker count). `opt_in_required`: an agy (gemini-headless) hop while hounfour.headless.agy_opt_in is not true. Also present on a direct agy call refused by the opt-in. `locality_refused` (cycle-129 audit a257-1 MEDIUM-A1): under hounfour.locality local_voices, a hop that fails the local-hop rule while another hop of the chain passes it. Optional/additive.",
       "type": "array",
       "items": {
         "type": "object",
@@ -778,7 +778,8 @@
           },
           "reason": {
             "enum": [
-              "opt_in_required"
+              "opt_in_required",
+              "locality_refused"
             ]
           }
         }
diff --git a/.claude/scripts/adversarial-review.sh b/.claude/scripts/adversarial-review.sh
index 751cec73..96187f19 100755
--- a/.claude/scripts/adversarial-review.sh
+++ b/.claude/scripts/adversarial-review.sh
@@ -3887,6 +3887,14 @@ _adv_budget_estimate() {  # <estimated input tokens> <role>=<hop>... → _ADV_BU
       log "budget: no catalog price for $_bv_hop ($_bv_role) — the fixed 10 / 30 USD per Mtok applies to this voice"
~~~~

## I11 — fix-commit — 2026-10-14

- reference: 8e9965141be6
- files: .claude/defaults/model-config.yaml.checksum

Summary:

fix(cycle-129): CI — hop-locality.py splits the endpoint authority by hand (scheme://[userinfo@]host[:port], bracketed IPv6, numeric port; the same split as Bridgebuilder's localEndpointHost) because the cycle-099 import guard confines URL parsing to the endpoint validator (T1.15 import-guard red on 757e7043); model-config.yaml.checksum bumped for the Sprint 3 catalog comment (DRIFT-LOCKFILE-MISM…

Evidence:

~~~~diff
commit 8e9965141be6c3cbec24d9661600cc6d8d56d6b9
Date: 2026-10-14T21:39:58+11:00

fix(cycle-129): CI — hop-locality.py splits the endpoint authority by hand (scheme://[userinfo@]host[:port], bracketed IPv6, numeric port; the same split as Bridgebuilder's localEndpointHost) because the cycle-099 import guard confines URL parsing to the endpoint validator (T1.15 import-guard red on 757e7043); model-config.yaml.checksum bumped for the Sprint 3 catalog comment (DRIFT-LOCKFILE-MISMATCH red); checksums.json and REPO-MAP refreshed (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/defaults/model-config.yaml.checksum b/.claude/defaults/model-config.yaml.checksum
index 75c62299..3aa265f5 100644
--- a/.claude/defaults/model-config.yaml.checksum
+++ b/.claude/defaults/model-config.yaml.checksum
@@ -1 +1 @@
-4d17fd65c8e75e71ac2248bd9c7539a64932fc8dadaa2c1b3de3078a19102e93
+35d5f6d2e7914a20f8b92c23fb45822df5adcbbb4a614f39ca632d7cbbd1e46c
~~~~

## I12 — kf — 2026-10-15

- reference: KF-037
- files: .claude/defaults/model-config.yaml,.claude/scripts/adversarial-review.sh,tests/unit/adversarial-review-companion.bats

Summary:

## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1 **Status**: OPEN **Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout **Symptom**: adversarial-review.json: companion_voice.status failed with last_…

Evidence:

~~~~~text
~~~~markdown
## KF-037: A claude-headless dissent hop exceeds cheval's 610 s claude -p timeout when another claude CLI workload shares the host; cheval reports it as PROVIDER_UNAVAILABLE / exit 1

**Status**: OPEN
**Feature**: .claude/scripts/adversarial-review.sh companion voice (any claude-headless hop); cheval CLI adapter timeout
**Symptom**: adversarial-review.json: companion_voice.status failed with last_error 'claude -p timed out after 610s' (failure_class timeout since sprint-248 round 1f; model_unavailable on older envelopes); the MODELINV row's models_failed[].message_redacted reads RETRIES_EXHAUSTED … PROVIDER_UNAVAILABLE … timed out. The same hop answers in ~384 s when the CLI is otherwise idle (sprint-247/248 round 0).
**First observed**: 2026-09-25 (cycle-126 sprint-248 review re-run while the Sprint 3 baseline eval ran claude -p at concurrency 2)
**Recurrence count**: 10
**Current workaround**: Run dissents and other claude CLI workloads (eval harness, Bridgebuilder claude-headless) serially — pause the eval before a review/audit; or raise flatline_protocol.<block>.timeout_seconds (the companion wait cap follows it: timeout × hops + 30 s). The dissent still completes on the primary (voices_planned 2, voices_succeeded 1).
**Upstream issue**: cycle-126 residue: cheval could report a CLI-hop timeout as TIMEOUT (exit 3) rather than PROVIDER_UNAVAILABLE (exit 1); a host-level claude CLI concurrency budget would make the contention visible before the call
**Related visions / lore**: KF-010 (google CLI hops under a concurrent BB sweep), KF-035

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-09-25 | stopped the concurrent eval (TaskStop) mid-run; the next chunk's companion answered in 238 s; classifier + last_error fixed so the envelope says timeout with the provider's line | RESOLVED by serialising the CLI workloads; the class is structural whenever two claude -p consumers overlap | grimoires/loa/a2a/sprint-248 (run 2: adversarial-review-a-dissent-script.json failed at 612 s vs -b-contracts.json 238 s); commits d48328a2 + round-1f; .run/model-invoke.jsonl row 2026-09-25T08:33:06Z |
| 2026-09-25 | fourth live run, CLI idle: the claude-headless companion still timed out at 612 s on a 36 KB chunk — cheval's headless adapter bounds every CLI hop at connect 10 s + max(read_timeout, 600) from the PROVIDER config, so the dissent's --timeout never reached it; added ModelConfig.headless_timeout_seconds (catalog: claude-headless 900 s), the dissent's wait cap follows the catalog, *-headless hops are serialised per binary with a flock, and the failure diagnostic is read from the MODELINV row (the shim discards cheval's stderr) | FIXED at the root for this host (a 900 s bound); contention across processes is now serialised; the class still recurs whenever a CLI hop's real duration exceeds its catalog bound | grimoires/loa/a2a/sprint-248 (run 4: adversarial-review-a-dissent-script.json failed at 612 s with the CLI idle); .claude/adapters/loa_cheval/providers/headless_cli.py _compute_timeout; .claude/defaults/model-config.yaml claude-headless.headless_timeout_seconds |
| 2026-09-25 | sixth live run, chunk c: the companion's claude -p hung ~8 h under the account's usage limit (the session's own limit), the reaper's TERM was ignored and main's wait blocked on the reaped subshell; added TERM→KILL escalation after a grace period (LOA_ADVERSARIAL_REAP_GRACE_SECONDS, default 5), a bounded post-reap wait, and the tree is collected before signalling so orphans cannot escape | MITIGATED: a stuck CLI now costs the review the wait cap plus the grace period, never hours; the root (a CLI that blocks under a usage limit instead of failing) is the operator's account state | grimoires/loa/a2a/sprint-248 (run 6: chunk c exit in 28573 s, companion reaped at the 940 s cap); tests/unit/adversarial-review-companion.bats CMP-30 |
| 2026-10-03 | cycle-126 sprint-248 run 29 (base 621addf7): chunk a3-script-3 retried by run-dissent-two-voice.sh with other interactive claude sessions live on the host | four consecutive companion timeouts at ~910 s (attempts 1-4, 04:33-05:42Z); a later attempt succeeded two-voice once host load eased — retry-until-two-voice remains the workaround | run29.log lines 28-76 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 621addf7 |
| 2026-10-03 | the Current workaround's 'raise flatline_protocol.<block>.timeout_seconds' is HTTP-only: a CLI hop is bounded by the catalog's headless_timeout_seconds (claude-headless 900 s), not the dissent's --timeout, and the companion wait cap follows that per-hop bound — so serialise CLI workloads, or raise headless_timeout_seconds in a catalog override (cycle-126 sprint-248 run 30, e2b DISS-C-006) | workaround corrected by this row (the ledger is append-only); Flatline and BB primaries are claude-headless since 2026-10-01, so their parallel voices contend for the same CLI | run30 chunk e2b-docs-state (~/.cache/loa/cycle-126-dissent/adv-248-review-e2b-docs-state.json); round 1ae |
| 2026-10-03 | cycle-126 sprint-248 run 31 (base 10436350): chunk a2-script-2 retried by run-dissent-two-voice.sh with ~12 interactive claude sessions live on the host; the recurrence count now reaches 3 (runs 21 and 24-28 retried the same class unrecorded) | two consecutive companion timeouts (attempts 1-2, 11:17-11:47Z), attempt 3 succeeded two-voice after a 900 s pause — structural: route through the upstream residue (a host-level claude CLI concurrency budget), retry-until-two-voice stays the run-mode workaround | run31.log lines 27-66 (~/.cache/loa/cycle-126-dissent); branch feature/cycle-126-full-size @ 10436350 |
| 2026-10-04 | thirty-fourth two-voice run (round 1ah bc584653): a2, a3, a4 and c1b first companion attempts passed their cap with ~12 other Claude sessions live | each retry two-voice via the per-chunk-retry driver; the documented workaround holds | commit f32643fc (round 1ai, sprint-248 feedback §38) |
| 2026-10-04 | thirty-fifth two-voice run (round 1ai f32643fc): a4 first companion attempt passed its cap with ~12 other Claude sessions live. SUPERSEDES the header's Current workaround: raising flatline_protocol.<block>.timeout_seconds cannot help a CLI hop (bounded by the catalog's headless_timeout_seconds, claude-headless 900 s); the working remedy is serial CLI workloads plus a per-chunk retry until two-voice (run-dissent-two-voice.sh) | a4 two-voice on attempt 2; the header stays as written (append-only), this row is the operative workaround | run 35 a4 / f32643fc |
| 2026-10-04 | thirty-sixth two-voice run (round 1aj 3509808d): a3-script-3's first two companion attempts timed out at 910 s (claude -p) with ~12 other Claude sessions live; Flatline, BB and the companion all resolve to the one claude binary and only adversarial-review.sh serialises it (e2b DISS-C-002) | attempt 3 two-voice via run-dissent-two-voice.sh; every other chunk two-voice on attempt 1 — structural: the upstream residue is now concrete, a cheval-level per-binary CLI lock (headless_cli.py) so Flatline and BB hops queue behind the dissent's, plus a per-consumer headless breaker (follow-up bead at cycle end) | run36.log a3 attempts 1-3 (~/.cache/loa/cycle-126-dissent/run36-out); branch feature/cycle-126-full-size @ 3509808d |
| 2026-10-04 | thirty-seventh two-voice run (round 1ak 009ee894): a1-script-1's first companion attempt and all six of a4-script-4's (57604 bytes) timed out at 910 s (claude -p) with ~12 other Claude sessions live | a1 attempt 2 two-voice; a4 single-voice after six attempts (driver cap) — the chunk's size compounds the contention, so run 38 splits the script in five (chunk script 248i); every other chunk two-voice on attempt 1; structural residue unchanged (cheval-level per-binary lock + per-consumer breaker, cycle-end bead) | run37.log a1 attempts 1-2, a4 attempts 1-6 (~/.cache/loa/cycle-126-dissent/run37-out); branch feature/cycle-126-full-size @ 009ee894 |
| 2026-10-04 | thirty-eighth two-voice run (round 1al 9bb1fe4c): a3-script-3's first companion attempt and a4-script-4's first three timed out at 910 s (claude -p) with ~12 other Claude sessions live, host load ~1.5 | a3 attempt 2 and a4 attempt 4 two-voice via run-dissent-two-voice.sh; every chunk two-voice; run 39 splits a4 (57 KB) into a4a/a4b to shorten the companion's hop | commit 9bb1fe4c; run38.log (cycle-126 dissent cache) |
| 2026-10-05 | Thirty-ninth two-voice run (24 chunks, companion on claude-bedrock) with about twelve other Claude sessions live: retried each timed-out chunk until two-voice (a1, a2, b1 once; a3 twice; a4b six times at 910 s) | All 24 chunks two-voice; retry-until-two-voice holds but costs about an hour per run under host contention; dissent capped at 3 runs per sprint from here | run39.log on 332f254c (round 1am), sprint-248 feedback §43 |
| 2026-10-15 | cycle-130 Sprint 259 review dissent run 1 on 6be23186: code-only diff of 166 files / 10,298 lines incl. 16 task fixtures; codex-headless gpt-5.5-pro primary succeeded (3 findings), claude-headless companion timed out after 910s (PROVIDER_UNAVAILABLE) → DEGRADED 1/2 | degraded envelope accepted for review round 1 (the primary delivered); run 2 excludes tasks/*/fixture and tasks/*/hidden from the dissent diff so the companion sees the ~3.5k-line harness diff only | grimoires/loa/a2a/sprint-259/adversarial-review.json; ~/.cache/loa/cycle-130/logs/dissent-s2-review.log |

### Reading guide

A companion (or any claude-headless) timeout while an eval or BB sweep is running is CLI contention, not a model outage: check ps for other claude -p processes before retrying, and re-run the dissent only once the CLI is idle. Verdict quality already records the primary alone; the companion's failure_class names the class.

~~~~
~~~~~
