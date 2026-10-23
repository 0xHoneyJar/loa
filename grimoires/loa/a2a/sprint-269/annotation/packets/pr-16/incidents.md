# Incidents — pr-16

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-14

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

## I02 — fix-commit — 2026-10-14

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

## I03 — fix-commit — 2026-10-14

- reference: 07110d7052ea
- files: .loa.config.yaml.example

Summary:

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused…

Evidence:

~~~~diff
commit 07110d7052ea531b190ec58a0f429e0718e2365c
Date: 2026-10-14T21:29:39+11:00

fix(cycle-129): sprint-257 security audit round a257-1 — a declared locality is enforced where the prompt is sent: under hounfour.locality local_voices cheval plans around every chain hop that fails the local-hop rule (one stderr line each, MODELINV models_not_planned reason locality_refused) and refuses an all-hosted chain before any dispatch (LocalityRefusedError, failure_class locality_refused, exit INVALID_CONFIG), the loader refuses a local model whose fallback_chain reaches a hosted or unresolvable hop, and Bridgebuilder walks the chain in the trusted view (MEDIUM-A1; one implementation endpoint_policy.hop_is_local serves cheval, the loader and MODELINV hop_locality); Bridgebuilder refuses trusted-config drift on a pull request — hounfour.providers, aliases, locality and the secret allowlist compared head vs trusted, exit 5 before any voice is planned, because cheval-delegate spawns cheval from the checkout (MEDIUM-A2); localhost is resolved and checked for loopback at request time (LOW-A1); metadata.locality.degraded_security_review is machine-readable on the audit envelope (LOW-A2); a zero price not marked open_weight warns in the budget gate (LOW-A3; metering guard → bd-yzzb9); DISS-001 RFC1918 opt-in accepted by design; tests test_locality_fallback_plan.py (13), test_local_dispatch_group_rule.py (+9), LOC-1/4/10, BUD-3/7, trusted-config.test.ts (35), dist rebuilt; cheval pytest 3277 passed (2 baseline), Sprint 3 bats 137/137, npm 881/882 (KF-036), corpus 99/99 · 184/184; CHANGELOG Fixed entry + two Migration rows; DEC-0340…DEC-0351 (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.loa.config.yaml.example b/.loa.config.yaml.example
index 6fb0676c..68b7ee4a 100644
--- a/.loa.config.yaml.example
+++ b/.loa.config.yaml.example
@@ -1226,8 +1226,10 @@ hounfour:
 # Example 4: Local OpenAI-compatible server (vLLM, llama.cpp, Ollama, LM Studio)
 # Threat model: plain http is admitted only to the one host named in
 # allow_insecure_endpoint, an IP literal or localhost in a loopback or RFC1918
-# range that is never resolved through DNS, so the prompt does not cross a
-# public network unencrypted and the name cannot be rebound. For this provider
+# range. IP literals are never resolved, so the prompt does not cross a public
+# network unencrypted and the address cannot be rebound; localhost is resolved
+# and checked at request time, and any address that is not loopback (or a
+# resolver failure) refuses the request by name. For this provider
 # cheval ignores proxy environment variables, refuses redirects and keeps every
 # request under the declared endpoint path, while every other provider keeps the
 # https, loopback and private-range refusals.
@@ -2512,6 +2514,10 @@ bridgebuilder:
   # 3 and 0; any other integer 0..125 is accepted but reported by them as "the review did not complete" (4 is
   # entry.sh's missing-dependency preflight). On a pull request this key is read from the trusted config
   # (the base branch's .loa.config.yaml or BRIDGEBUILDER_TRUSTED_CONFIG), never from the PR head.
+  # Trusted config drift: cheval reads the checkout's configuration for the dispatch, so a pull request whose
+  # head changes hounfour.providers, hounfour.aliases, hounfour.locality or the secret allowlist is refused by
+  # name before any voice is planned (exit 5): merge the base branch into the head, or set
+  # BRIDGEBUILDER_TRUSTED_CONFIG to the configuration you vouch for.
   exit_on_degraded: 3
 
 # =============================================================================
~~~~

## I04 — issue — 2026-10-14

- reference: #1282
- files: .claude/settings.json,.gitignore

Summary:

feat(cycle-129): earned guards and open voices — guard register with origin and yield, pre-registered control arms, inert controls repaired, file-authoritative run position, heredoc classifier under corpus control, one profile knob, advisory open-weight voices and the local_voices posture — ## Summary cycle-129 "earned guards and open voices" turns the 2026-10-14 paradigm review into measured, ti…

Evidence (first 200 of 290 lines):

~~~~~text
# pull request #1282: feat(cycle-129): earned guards and open voices — guard register with origin and yield, pre-registered control arms, inert controls repaired, file-authoritative run position, heredoc classifier under corpus control, one profile knob, advisory open-weight voices and the local_voices posture

- url: https://github.com/0xHoneyJar/loa/pull/1282
- created_at: 2026-10-14T10:35:05Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

cycle-129 "earned guards and open voices" turns the 2026-10-14 paradigm review into measured, tightened and honestly described guards, and opens the voice path to open-weight and local models without giving them a vote. Every guard now carries its origin and its 30-day yield; pre-registered gate-off control arms measure what the always-on prose buys; the controls that never ran are repaired or demoted; run position derives from files; the fence stops blocking prose in heredocs under corpus control; one profile knob sets the optional surfaces and cannot reach the floor; sprint tasks carry a kind. Advisory open-weight voices reach the reviewer without changing a verdict, and `hounfour.locality: local_voices` refuses every hosted hop by name and says what it costs. The floor — `/review-sprint`, `/audit-sprint`, `verdict-derive.sh` and the one-way rule, the dissent artefact gate, the deny list, fence FR-1.2b, the System-Zone rules and the operator-only commands — is untouched.

Three sprints (global 255, 256, 257), each through implement → review → audit with two-voice dissent at every gate (gpt-5.5-pro via codex-headless + claude-headless; consensus every run; 0 schema-rejected payloads). Sprint 255: review r1 CHANGES_REQUIRED (0/0/3/2) → fix `49895989` → APPROVED; audit r1 CHANGES_REQUIRED (0/0/4/7) → fix `b6802e4f` → APPROVED. Sprint 256: three review rounds (HIGH: a backtick span was inert to the fence while `$( )` blocked, pre-existing on `main`; HIGH: the example pinned the profile keys so a copied example changed nothing) → `3263bbc4`, `b6030e5b`, `77455afb`, `5ecf13f5`; two audit rounds (HIGH: `gh api -X DELETE` on refs had no fence rule → FR-GH-1) → `81005346`, `9c4ed319`; five dissent runs against the ≤3 cap, each finding a real hole (DEC-0310). Sprint 257: review r1 CHANGES_REQUIRED (HIGH: `dispatch_group: local` was trusted, never checked against the endpoint host) → `cf88e427`; r2 APPROVED with three LOW hardenings `4184c052`; audit r1 CHANGES_REQUIRED (two MEDIUM: under `local_voices` a local model's hosted `fallback_chain` left the declared providers inside one cheval call; Bridgebuilder's trusted view governed acceptance while cheval read the checkout's configuration for the dispatch) → `07110d70`, verified directly by the auditor with the three runs spent (DEC-0343). Every finding of every run is fixed with a pinning test, refuted with file:line evidence, or accepted by design with a recorded decision.

## What is in it

- **FR-1 Guard register with origin and yield**: `guard-yield.sh` enumerates every hook registration, `# @guard` marker and gate, joins them with `.claude/data/guard-origins.yaml` and the 30-day block log, writes `grimoires/loa/guards.md` and the host yield; `--check` is the CI drift gate (96 guards, none without an origin). `/loa` prints the Guards line.
- **FR-2 Pre-registered control arms**: `evals/harness/run-arms.sh` runs gate-off arms against a detached worktree pinned at a source commit on a record corpus (eight fixtures from the cycle-126…128 record, `seed-corpus-from-record.sh`); `report.sh --arms` gives the pre-registered verdict with bootstrap intervals and the missed labels. Batch 1 complete: review-recall `no_karpathy` and `no_rule_files` **no recall loss** (drop 0.000), `no_companion` no recall loss (informational, 0.028); audit-recall `no_audit_delta` **no recall loss** (drop 0.000). Batch 2 is cost-gated (DEC-0173).
- **FR-3 Always-on prose ≤ 12 KB**: the two always-loaded rule files are path-scoped; the kernel kept every pinned rationale under the D-2.4 fallback (the arms completed after the gate read; the deletions wait on bead bd-2txz1 with the verdicts now recorded); `CLAUDE.loa.md` ≤ 9,445 B, lint-pinned.
- **FR-4 Inert controls repaired or demoted**: `implement_gate.mode: ask | telemetry | deny` with a real PreToolUse decision, run and implementing-skill sanctions, a logged override row; the dead fences and counters named in the review are repaired or removed and the hooks reference says what each one does.
- **FR-5 File-authoritative run position**: `run-checkpoint.sh derive` rebuilds the run state and the circuit breaker from COMPLETED markers, LOA-VERDICT trailers, the ledger and git; `record-round` is the breaker; `mark`/`unmark` manage the implementing-skill marker.
- **FR-6 Heredoc false positives**: the fence classifies heredoc consumers (grammar stated; nested and variable delimiters; interpreter, wrapper, hook, settings, rc, PATH, `.git/hooks`, workflow and manifest targets are executable content; everything unlisted fails closed) under corpus control — 99 benign, 184 dangerous, 0 misses, `--knob-off` replay identical on the pre-existing rows. The review rounds closed a pre-existing backtick hole (a backtick span was inert while `$( )` blocked) and added FR-GH-1 (`gh api` DELETE/PUT/PATCH on refs, protection, tags, releases, the repository; graphql mutations).
- **FR-7 Advisory open-weight voices**: a local OpenAI-compatible server is a provider (`type: openai_compat`, `keyless`, `allow_insecure_endpoint: "<loopback or RFC1918 IP literal or localhost>"`, declared `context_window`); its findings land only under `advisory_voices[].findings` (`duplicate_of` links) and the counted envelope is byte-identical with or without them; promotion to a counted voice is refused by name. The chat path sends `response_format` json_schema for `structured_json` entries, strips `<think>` / `reasoning_content` before qualification and records `schema_enforced`, `thinking_stripped`, `destination`. The budget gate reads catalog prices (open-weight prices need provenance). Bridgebuilder reads providers from trusted configuration only (base branch or `BRIDGEBUILDER_TRUSTED_CONFIG`; head-only declarations and head drift refused by name), prints completed/planned voices and exits 3 on a DEGRADED consensus (`bridgebuilder.exit_on_degraded: 0` is the rollback).
- **FR-8 Local posture**: `hounfour.locality: local_voices` plans only hops whose provider honours `dispatch_group: local` — an HTTP provider whose endpoint host is a loopback or RFC1918 IP literal or `localhost`, enforced at load, at request time, in the planner, in cheval's chain plan and in Bridgebuilder; every hosted hop (dissent, Flatline, Bridgebuilder, the probe, fallback chains) is refused by name; the one-family DEGRADED audit says so in a machine-readable field; the Claude Code session model is exempt and the docs say so.
- **FR-9 One profile knob**: `loa.profile: lean | standard | full` sets the nine optional-surface knobs through one reader (`profile-lib.sh`); floor keys are unreachable; `/loa` shows the profile and says when a guardrail control is off.
- **FR-10 Task kinds and the ratio line**: every sprint task carries `kind: mechanical | judgment | operator`; `tools/cycle-ratio.sh` prints the kinds and the script / prose / model-call volume (this cycle: mechanical 24 · judgment 5 · operator 0).

## Verification

- **Final tree `757e7043`**: cheval pytest 3277 passed / 6 skipped / 2 baseline failures (`test_claude_headless_adapter.py`, which resolves this host's `claude-fallback` wrapper); Sprint 3 bats plus the four probe suites 137/137; fence corpus 99 benign / 184 dangerous / 0 misses, `--knob-off` row-identical to the pre-change hook on the pre-existing rows; Bridgebuilder `npm test` 881/882 (`persona.test.ts` needs `ANTHROPIC_API_KEY`, KF-036) with `dist/` fresh; TypeScript port `--check` clean; `guard-yield.sh --check` in sync (96 guards, none without an origin); prompt budget (`CLAUDE.loa.md` ≤ 9,445 B, every gate skill ≤ 16,384 B); knob readers, swallowed-jq, raw-sha256, shell-compat and skill-capabilities (37/37) clean. The full bats sweep and the integration suites run with this PR's CI (AC-2.12 Partial by design).
- **E2E** (`grimoires/loa/a2a/sprint-257/e2e.md`, record branch): G-1 … G-9 PASS; G-7 with a stated exception (no local OpenAI-compatible server on this host; the local-hop path is proven by a 127.0.0.1 stub-server test).
- **Control arms** (batch 1: eight record fixtures × three trials, executor `global.anthropic.claude-opus-5-5` pinned at `864069f2`, interleaved, `MANIFEST.json`): review-recall 96/96 — `no_karpathy` and `no_rule_files` **no recall loss** (drop 0.000, 90 % CI [0.000, 0.000]), `no_companion` no recall loss (informational, 0.028); audit-recall 48/48 — `no_audit_delta` **no recall loss** (drop 0.000). The kernel kept every pinned rationale under the D-2.4 fallback; the deletions wait on bead bd-2txz1 with these verdicts recorded.
- **Gate records**: review and audit reports, dissent envelopes and COMPLETED markers for sprints 255–257 under `grimoires/loa/a2a/sprint-25{5,6,7}/` (record branch `record/cycle-129-a2a`, pushed after the merge).
- **Known failures**: KF-043 new (invoking a skill whose frontmatter has `disallowed-tools: Write, Edit, NotebookEdit` in the main session removes those tools for the rest of the agentic turn; not enforced in subagents; Bash stays a write path); KF-036 recurrence 4.
- **This repository**: `implement_gate.mode: deny` is set in the cycle's last commit (`757e7043`) after the E2E derive showed no run-position drift (DEC-0126, DEC-0168); rollback `implement_gate.mode: ask`.

## Migration

See `CHANGELOG.md` `### Migration (cycle-129)` — every behaviour change names its rollback key (`implement_gate.mode: ask`, `destructive_command_guard.heredoc_classifier: false`, `run_mode.file_authoritative: false`, `hounfour.locality: hosted`, `loa.profile: standard`, `bridgebuilder.exit_on_degraded: 0`). cheval now refuses `http`, loopback and private endpoints at load without the per-provider opt-in; a `dispatch_group: local` on a hosted or CLI provider is refused at load.

## Follow-ups (beads)

- **bd-2txz1** — FR-3 kernel text deletions deferred under D-2.4 (the arms completed after the gate read); the review-recall and audit-recall verdicts are recorded on the bead for the next cycle's deletion decision.
- **bd-yzzb9** — metering guard: a zero price on a hosted entry not marked `open_weight` counted as unpriced (the dissent budget gate WARNs today; audit a257-1 LOW-A3).
- **bd-j4lwr** — kem_glitch review follow-ups (claimed paths with a numstat check before `git apply`, `run-arms --max-usd`, `run-arms --screen`, a written dispatch template, per-seat cost attribution); report `grimoires/loa/a2a/kem-glitch-review-2026-10/report.md` on the record branch.
- Carry-overs from earlier cycles stay where they are: bd-akas, bd-g6k3, bd-48ni, bd-xtip (cycle-128), bd-ugmi, bd-9qe2 (cycle-126).

## Decisions taken on your behalf

Every decision of this cycle is a `proposed` row in `grimoires/loa/decisions.yaml` (none `decided`: no operator was present). Confirm, reject or supersede them with `/decisions confirm --cycle cycle-129 --all` (operator-only).

<details>
<summary>227 rows (DEC-0125 … DEC-0351): 226 proposed; DEC-0294 rejected</summary>

| Row | Status | Decision (summary) |
|---|---|---|
| DEC-0125 | proposed | Codebase grounding reuses the 2026-10-14 paradigm-review evidence files instead of re-running /ride on the stale May reality (D1) |
| DEC-0126 | proposed | implement_gate.mode gains telemetry and deny; downstream default telemetry, this repo deny; ask kept; authoritative stays a tighten-only modifier (D2) |
| DEC-0127 | proposed | Advisory-voice promotion threshold is a maintainer-set config value, unset by default, so nothing promotes until it is set (D3) |
| DEC-0128 | proposed | lean profile is opt-in this cycle; standard stays the downstream default; docs recommend lean once the FR-2 arms show no recall loss (D4) |
| DEC-0129 | proposed | Rule path-scoping keys on files: stash-safety for shell sources, skill-invariants for SKILL.md and agent definitions (D5) |
| DEC-0130 | proposed | Fleet block logs are counted later; the register carries scope: host and a follow-up bead for mailbox ingestion (D6) |
| DEC-0131 | proposed | No hosted open-weight catalog price row this cycle; the catalog requires price_source and price_date; the dissent budget gate reads catalog prices (D7) |
| DEC-0132 | proposed | FR-7 family-and-lineage slice not built (no operator need declared); open-weight voices stay advisory_voice, never independent (D8) |
| DEC-0133 | proposed | Carry-over defects fold into sprint tasks with red tests, not separate /bug micro-sprints (D9) |
| DEC-0134 | proposed | KF-041 (recurrence 3) goes to an upstream GitHub issue; the planning Flatline runs are accepted degraded and integrated by judgment (D10) |
| DEC-0135 | proposed | Three sprints 255-257 in the brief's order; Opus 5.5 implementers in worktrees; Fable 5.1 gates; at most three dissent runs per sprint (D11) |
| DEC-0136 | proposed | guards.md is generated by guard-yield.sh from registrations, fence ids, validator rules and a tracked origin map; CI fails on a guard without origin (D12) |
| DEC-0137 | proposed | FR-2 corpus seeded from the round-1 states of sprints 247-254 as commit-pinned manifests with accepted findings as labels (D13) |
| DEC-0138 | proposed | FR-5 derivation keeps the JSON shape: .state canonical, .status mirrored for legacy readers (D14) |
| DEC-0139 | proposed | Input guardrails and danger-level enforcement default off in the example config and this repository; code stays behind the knob (D15) |
| DEC-0140 | proposed | The five C-TEAM rows leave constraints.json and the kernel; guidance moves to agent-teams-reference.md; team hooks stay registered (D16) |
| DEC-0141 | proposed | Karpathy surgical-diff hook resets per beads task and writes a per-task summary the review reads; the running total goes (D17) |
| DEC-0142 | proposed | disallowed-tools strips Write, Edit, NotebookEdit from the four pure-review skills; the invariant doc's claim becomes true (D18) |
| DEC-0143 | proposed | loa.profile offers lean, standard, full; standard equals today; no floor key under profile; per-key overrides win (D19) |
| DEC-0144 | proposed | kind: is required on sprint tasks for plans dated from 2026-10-14; this cycle's own sprint plan carries the tags (D20) |
| DEC-0145 | proposed | FR-6: interpreter-consumed heredocs scan as today; file- or tool-bound heredocs scan for destructive tokens at line start only; every D-row stays (D21) |
| DEC-0146 | proposed | FR-8 is named hounfour.locality: local_voices and covers the voices only; the session remains the platform (D22) |
| DEC-0147 | proposed | No rule text or kernel row deleted before its FR-2 arm result; Sprint 1 only path-scopes; kernel cap lowered in Sprint 2 to the measured size (D23) |
| DEC-0148 | proposed | bd-cq90 and bd-b4ji fold into the plan commit; bd-b4ji's structural fix stays an open bead (D24) |
| DEC-0149 | proposed | FR-2 arms run as a detached driver started at the end of Sprint 1 on an Opus 5.5 executor; Sprint 2 waits and falls back to path-scoping plus pointers (A1) |
| DEC-0150 | proposed | Bridgebuilder exits 3 on a DEGRADED verdict and reports completed/planned voices; both callers accept 3 as completed-degraded (A2) |
| DEC-0151 | proposed | The implement gate reads the derived run-position cache written by run-checkpoint.sh and never computes the derivation itself (A3) |
| DEC-0152 | proposed | Profile defaults live in .claude/data/profiles.yaml with a forbidden-floor-key list; profile-lib.sh resolves explicit key, then profile, then fallback (A4) |
| DEC-0153 | proposed | Corpus fixtures are generated from git and the record branches by a script; the lead curates must_match anchors; labels are finding titles only (A6) |
| DEC-0154 | proposed | kind: sits at the end of the sprint task line after the dependency marker; the validator reuses the Seams gate's date parsing (A7) |
| DEC-0155 | proposed | Advisory voices are declared as flatline_protocol.<gate>.advisory_voices, run after primary and companion, tagged advisory_voice, never in voices_planned (A5) |
| DEC-0156 | proposed | FR-6 fails closed: an unlisted heredoc consumer scans in full; a body written to a file that the same line executes is interpreter-consumed (D25) |
| DEC-0157 | proposed | The tracked register carries origins and the last yield snapshot; the CI check compares structure and origins only; live yield lives under .run (D26) |
| DEC-0158 | proposed | Rollback knob per risky change: implement_gate.mode ask, heredoc classifier off, file-authoritative derivation off, locality hosted, profile standard (D27) |
| DEC-0159 | proposed | The insecure-endpoint opt-in admits only loopback or RFC1918 hosts and must name the exact host; non-loopback endpoints keep TLS; destinations are audited (D28) |
| DEC-0160 | proposed | App-Zone writes are sanctioned by the derived RUNNING state or a fresh marker the implementing skills write; an audited env override exists (D29) |
| DEC-0161 | proposed | Guardrails stay enabled in this repository as telemetry (danger-level enforcement off); the downstream example defaults both off; amends D15 (D30) |
| DEC-0162 | proposed | The tracked register is structural only (ids, class, status, origin, knob, floor, registrations); yield lives untracked under .run; amends D26 (D32) |
| DEC-0163 | proposed | implement_gate.mode keeps ask as the default; telemetry and deny are opt-ins; asks are logged; unknown position under deny falls back to ask (D31) |
| DEC-0164 | proposed | The FR-2 arm executor is Fable 5.1, the production gate model, not an Opus 5.5 subagent (D33) |
| DEC-0165 | proposed | Advisory-voice findings are written only to advisory_voices[].findings, never to the top-level findings array; amends A5 (A8) |
| DEC-0166 | proposed | One tracked floor source .claude/data/floor.yaml lists floor guard ids and floor config keys; the floor tests pin its sha256 (A9) |
| DEC-0167 | proposed | Replay audit rows are marked at the source (LOA_AUDIT_REPLAY=1 -> replay: true); the cwd heuristic stays as the fallback for older rows (A10) |
| DEC-0168 | proposed | Harness-affecting changes land dark for this repository during the run; the deny flip and the classifier default wait for the cycle-end validation (D34) |
| DEC-0169 | proposed | Kernel-row deletions by evidence class: arm verdict for review prose, pointers for mechanism rows, proposed DEC rows for behavioural rows (D35) |
| DEC-0170 | proposed | Bridgebuilder honours keyless or insecure providers only from trusted config (base branch or repo settings), never the PR head (D36) |
| DEC-0171 | proposed | Arm batches start as early as their inputs exist; Task 2.8 runs last; the fallback deletes nothing; amends A1 (D37) |
| DEC-0172 | proposed | The FR-2 arm executor is Opus 5.5 (homogeneous); Fable's safeguard fallback makes a Fable run model-skewed; amends D33 (D38) |
| DEC-0173 | proposed | Arm batches are cost-gated: batch 1 runs now; batch 2 runs at full trials only if its projection from batch 1 stays under the sprint-248 spend (D39) |
| DEC-0174 | proposed | S1 impl A: hook-guard.sh gets its own row (hook:hook-guard.sh, origin #1180) with the four unique registrations it wraps, so the register has 30 ho... |
| DEC-0175 | proposed | S1 impl A: Hook ids for scripts outside .claude/hooks/ are hook:scripts/<name>, keeping them distinct from hooks-dir root files such as hook:loa-kf... |
| DEC-0176 | proposed | S1 impl A: A registration with no matcher is written as the bare event (SessionStart), not SessionStart:. |
| DEC-0177 | proposed | S1 impl A: The fence register has 34 ids: the 32 emit_block ids plus FR-SZ (override bypass row) and FR-SZ2 (bounded-marker allow row), which exist... |
| DEC-0178 | proposed | S1 impl A: The FR-1.2b marker sits above the if that guards the call, 4 lines above emit_block, not directly above it. This keeps my hunk away from... |
| DEC-0179 | proposed | S1 impl A: The replay: true field is added to all four fence audit-row writers (block, FR-MERGE-2 override, FR-SZ bypass, FR-SZ2 marker), not only... |
| DEC-0180 | proposed | S1 impl A: A burst fallback is added to the replay rule: a UTC minute holding 10 or more block rows is a replay. The SDD's cwd fallback caught zero... |
| DEC-0181 | proposed | S1 impl A: outside_repo treats both this checkout and its main worktree (from git rev-parse --git-common-dir) as inside the repository. Other workt... |
| DEC-0182 | proposed | S1 impl A: Gate and policy rows carry an extra script: field naming the implementing file, so the lint can check that each gate's script exists. ga... |
| DEC-0183 | proposed | S1 impl A: Hook rows carry registrations in the map, and the script fails (exit 5) when they differ from settings.json. A new registration therefor... |
| DEC-0184 | proposed | S1 impl A: Status calls: the mutation loggers, permission-audit.sh and the Karpathy diff check are telemetry. The three team guards are dormant wit... |
| DEC-0185 | proposed | S1 impl A: Class calls follow the inventory: blocking or asking hooks are harness; session-start surfaces, reminders and loggers are script; the Ka... |
| DEC-0186 | proposed | S1 impl A: The hook rows for block-destructive-bash.sh and adversarial-review-gate.sh are floor: false; the floor is carried by the fence-id rows a... |
| DEC-0187 | proposed | S1 impl A: Validator rule ids beyond the prompt's minimum list are sprint.goal-ids, sprint.deferred, bug-triage.schema, translation.citations, map.... |
| DEC-0188 | proposed | S1 impl A: --json writes the files and prints the yield JSON on stdout, with the summary on stderr. --check never reads the audit log, so CI needs... |
| DEC-0189 | proposed | S1 impl A: Extra flags --settings, --fence, --validator, --hooks-ref and --now exist for fixture tests and reproducible runs. |
| DEC-0190 | proposed | "S1 impl A: The hooks table's ""## All Hook Registrations"" intro now names .claude/settings.json and the generator. The unregistered stop-input-probe..." |
| DEC-0191 | proposed | S1 impl A: The CI step sits after the yq install, because the script needs yq, and before the first test step. |
| DEC-0192 | proposed | S1 impl B: Labels live in the hidden review-prs/labels/pr-NN.tsv, not pr-NN/labels.tsv, because the sandbox copies the whole fixture directory. |
| DEC-0193 | proposed | S1 impl B: Fixture scope excludes grimoires/, .beads/, .run/, evals/results/, CHANGELOG.md, .claude/checksums.json, REPO-MAP.md, lock files and bin... |
| DEC-0194 | proposed | S1 impl B: fix_commit is the last commit that closed the sprint's feedback, so head..fix covers every round. A label's file must be in the fixture... |
| DEC-0195 | proposed | S1 impl B: A finding's locus is its first path cite. A bullet that opens with prose, a finding that calls itself pre-existing, and later-round sect... |
| DEC-0196 | proposed | S1 impl B: The anchor priority is: a quoted code snippet that is unique in the file (comment lines ignored in code), then fix hunks near the cited... |
| DEC-0197 | proposed | S1 impl B: Curation rows (labels/curation.tsv): pr-11 L04 re-anchored on load_observed; pr-12 L02 on result=$(_fold_companion; pr-12 L04 and L06 on... |
| DEC-0198 | proposed | S1 impl B: Recall counts feedback labels only. fix rows feed refuted share only. The grader moves to 1.2.0, adding fields without changing the reca... |
| DEC-0199 | proposed | S1 impl B: The baseline-spread rule gates recall-rule violations only; a refuted-share violation is recall loss. |
| DEC-0200 | proposed | S1 impl B: Label files stay # approved-by: pending; approval is the lead's (--approve), and run-arms.sh refuses unapproved fixtures unless --allow-... |
| DEC-0201 | proposed | S1 impl B: In arm mode, every arm gets the source tree's .loa.config.yaml, so only the toggled key differs between arms. |
| DEC-0202 | proposed | S1 impl B: Results are per batch (<suite>/<batch>/) with a suite-level aggregate STATUS.json, so a second batch never shares a writer with the first. |
| DEC-0203 | proposed | S1 impl B: Secret-shaped strings in verbatim copies become REDACTED-TEST-SECRET consistently in base/, head/ and head.diff (line numbers unchanged)... |
| DEC-0204 | proposed | S1 impl B: Record-fixture tasks get per_trial: 3600 (pr-01 … pr-10 keep 1500). |
| DEC-0205 | proposed | S1 impl B: I ran a second single real trial after the decoupling fix, with the transcript kept. The first trial's model split had to be explained b... |
| DEC-0206 | proposed | S1 impl B: Batch 1 is pr-01 … pr-08 and excludes the clean controls pr-09/pr-10, keeping the pre-registered 288 runs. |
| DEC-0207 | proposed | S1 impl B: The transport retry waits 300 s by default (a session or rate limit needs time), and the bootstrap seed is fixed per (suite, arm), so re... |
| DEC-0208 | proposed | S1 impl B: Label categories come from a keyword heuristic over the title (security, concurrency, error-handling, test, docs, logic); they are descr... |
| DEC-0209 | proposed | S1 impl B: golden-path.bats is fixed in place (it is under evals/, which this task owns). |
| DEC-0210 | proposed | S1 impl C: The removed bytes are the zone sentence (repeats the frontmatter zones: block and the kernel's Three-Zone table) and the Red Flags paren... |
| DEC-0211 | proposed | "S1 impl C: The axis sentence sits in Phase 2 after the ""check the acceptance criteria"" paragraph, prefixed **Task kinds**:, with the prompt's sente..." |
| DEC-0212 | proposed | S1 impl C: Only top-level checkbox lines are task lines; in a ### Task N.E2E block only - [ ] Task … lines count, so acceptance checkboxes there ar... |
| DEC-0213 | proposed | S1 impl C: Inline code spans are not tokens: they are stripped before counting, and a tag inside backticks does not satisfy the rule. |
| DEC-0214 | proposed | S1 impl C: The kind keyword and its value are lower case only. |
| DEC-0215 | proposed | S1 impl C: A pre-date or undated non-live plan gets one aggregated WARN; a live undated plan gets one violation and the rule stops, as the Seams ga... |
| DEC-0216 | proposed | S1 impl C: The judgment WARN fires when at least one recognised file token is present and all are .sh/.py/.ts, or when script, lint or generate app... |
| DEC-0217 | proposed | S1 impl C: The Seams suite's fixture task line gains · kind: mechanical; without it SEAMS-12's 2026-10-14 plan fails the new rule. |
| DEC-0218 | proposed | S1 impl C: The template tags its Sprint 1 and Sprint 2 example task lines, with the two-line kind explanation as an HTML comment beside the existin... |
| DEC-0219 | proposed | S1 impl C: The eval task uses the .yml extension so evals/suites/review-recall.yaml (include tasks/review-recall/**/*.yaml) does not pick it up; ru... |
| DEC-0220 | proposed | S1 impl C: The eval grader is pattern-match.sh with [*][*]MEDIUM[*][*].*[Mm]echanical, because validate-task.sh refuses \| and \ in grader args and... |
| DEC-0221 | proposed | S1 impl C: The fixture lives under evals/fixtures/review-kinds/, outside B's review-prs/ corpus and its SHA256SUMS. |
| DEC-0222 | proposed | S1 impl C: cycle-ratio.sh uses committer timestamps with both ends inclusive; prose bytes are the byte length of each added or removed .md line wit... |
| DEC-0223 | proposed | S1 impl C: cycle-ratio.sh reports untagged task lines in --json and on stderr, not in the kinds: line, which keeps the specified three counts. |
| DEC-0224 | proposed | S1 impl C: Only rows with primitive_id MODELINV and a parseable ts_utc are counted. |
| DEC-0225 | proposed | S1 impl C: Exit 2 also covers outside a repository, an unreadable plan and missing jq; a SHA starting with - is exit 3. |
| DEC-0226 | proposed | S1 impl C: The new frontmatter uses the same list form with origin: enacted, version: 1, enacted_by: cycle-083, taken from the introducing commits... |
| DEC-0227 | proposed | S1 impl C: The FR-1.2b message already ended Rules: .claude/rules/stash-safety.md; that tail became ; see .claude/rules/stash-safety.md. |
| DEC-0228 | proposed | S1 impl C: The implementing-tasks app-zone value is read-write, from the vocabulary none \| read \| read-write in use; run-bridge uses read-write for... |
| DEC-0229 | proposed | S1 impl C: The stale protocol numbers in prompt-budget.bats's header comment were corrected with the workflow comment; they are the same drift. |
| DEC-0230 | proposed | S1 lead: The validator:sprint.kinds origin row was added by the lead at integration (origin cycle-129 D-10.1 (DEC-0144)) rather than sent back to A... |
| DEC-0231 | proposed | S1 lead: The fixture dist/ copies are re-included in .gitignore (two negation lines mirroring the existing bridgebuilder-review lines) and copied f... |
| DEC-0232 | proposed | "S1 lead: All eight label files were approved after the lead read every label (--approve pr-NN --by ""lead 2026-10-14""); nine machine-chosen anchors ..." |
| DEC-0233 | proposed | S1 lead: The arm executor is Opus 5.5 (DEC-0172) and batch 2 is cost-gated (DEC-0173); batch 1 starts after the sprint commit, not before, because ... |
| DEC-0234 | proposed | S1 lead: The sprint plan's fixture numbering and AC-1.3 wording were amended to the as-built state (pr-11 … pr-18; structural register per DEC-0162... |
| DEC-0235 | proposed | S2 D: A sprint's trailer may name it as sprint-<gid> or its ledger local label (SDD D-5.1); a stale-cycle trailer that happens to use the same local label is... |
| DEC-0236 | proposed | S2 D: The run-state cache is .run/sprint-plan-state.json; JACKED_OUT is matched on .state OR .status, so the cycle-128 kickoff shape (state RUNNING, status J... |
| DEC-0237 | proposed | S2 D: A new incomplete sprint means a ledger sprint whose sprint-<gid> and local label are both absent from derivation.sprint_ids, or from sprints.list[].id ... |
| DEC-0238 | proposed | S2 D: Only APPROVED with verdict-derive exit 0 counts as APPROVED in derive and in record-round; an inconsistent trailer counts as findings, as the run-mode ... |
| DEC-0239 | proposed | S2 D: An APPROVED record-round writes nothing: the breaker file stays byte-identical, and same_issue and no_progress compare only non-APPROVED rounds. |
| DEC-0240 | proposed | S2 D: no_progress starts at 0 on the first round and counts consecutive equal counts; the previous counts are stored as triggers.no_progress.last_counts (a J... |
| DEC-0241 | proposed | S2 D: A record-round on an already-OPEN breaker prints TRIPPED: open: breaker already OPEN and exits 10 without a second history entry, so a caller that miss... |
| DEC-0242 | proposed | S2 D: A record-round call with a missing feedback file exits 2 instead of hashing none, because it is a caller error. |
| DEC-0243 | proposed | S2 D: --reset-ice stamps reset_at and derive ignores rounds at or before it; without this derive would raise the counters right back after a reset. |
| DEC-0244 | proposed | S2 D: derive writes nothing when the cache file is missing (no run) or unparseable (kept as evidence); it creates the breaker file from the schema defaults w... |
| DEC-0245 | proposed | S2 D: derive never touches .sprints.list or .sprints.completed; only .state, .status, derived_at, derivation and a defaulted schema_version are written. |
| DEC-0246 | proposed | S2 D: A cache without derived_at is an unknown position for deny, so it asks; with derived_at present it must also be fresh for the run sanction; when absent... |
| DEC-0247 | proposed | S2 D: Freshness for derived_at and the marker allows at most 300 s of clock skew ahead; the existing 24 h window for last_activity stays symmetric. |
| DEC-0248 | proposed | S2 D: The sanction order is run, then marker, then override; the override row appears only when nothing else sanctioned, so the register counts real override... |
| DEC-0249 | proposed | S2 D: .run/implement-active.json joins the implement gate's trust inputs (a Write-tool write to it asks); the skills write it through run-checkpoint.sh mark,... |
| DEC-0250 | proposed | S2 D: Under claims: authoritative a non-implementation claim is denied, not asked, when deny would deny anyway; an ask there would loosen deny and the modifi... |
| DEC-0251 | proposed | S2 D: The deny reason ends 'or set implement_gate.mode: ask' per D-4.1 and the task prompt; SDD section 4.3 said telemetry, and D-4.1 is the more specific de... |
| DEC-0252 | proposed | S2 D: Trust-input rows keep their compliance.state_write shape and gain hook, action: ask, decision: trust_input and mode, so the register counts those asks ... |
| DEC-0253 | proposed | S2 D: The implementing-skill marker is managed by new verbs run-checkpoint.sh mark\|unmark, which keeps the two skill sentences inside their byte budgets and ... |
| DEC-0254 | proposed | S2 D: To fit its budget implementing-tasks/SKILL.md lost three redundant phrases: the inline br command list the lifecycle line repeats, the second fall-back... |
| DEC-0255 | proposed | S2 D: IG-11 used to pin implement_gate.mode as undocumented (cycle-126); it now pins it as documented, and the README and docs grep was dropped since D-4.1 s... |
| DEC-0256 | proposed | S2 D: The /loa Gate line comes from implement-gate.sh --effective-mode so /loa and the hook share one parser; the LOA_STATUS_CONFIG_FILE seam is reused and a... |
| DEC-0257 | proposed | S2 D: run-checkpoint.sh now runs under set -euo pipefail and LC_ALL=C per the conventions; its bead_closed call was rewritten to capture the exit code safely... |
| DEC-0258 | proposed | S2 D: PRD AC-5.1 says the drift fixture derives to JACKED_OUT while SDD D-5.4 and the task prompt say COMPLETE; the implementation follows the SDD because th... |
| DEC-0259 | proposed | S2 E: Under a quoted heredoc delimiter, $(, backticks and <( in the body are literal text and do not force a full scan; under an unquoted delimiter they do (... |
| DEC-0260 | proposed | S2 E: The exec-shaped flag rule (-c, -e, -x clusters, --exec, --eval, --command) is applied literally, so jq -c, grep -e and wc -c are full-scanned (fail clo... |
| DEC-0261 | proposed | S2 E: br flags other than exec-shaped ones are accepted on the non-executing allowlist, because br runs nothing. |
| DEC-0262 | proposed | S2 E: A variable command word in a heredoc body forces the full scan and is also scanned synthetically as rm, git and kubectl with the same arguments; no new... |
| DEC-0263 | proposed | S2 E: The interpreter, executable-target, nested-heredoc and shebang checks run before the #1245 quoted-cat special case, which tightens that case. |
| DEC-0264 | proposed | S2 E: The classifier's p95 was measured under a load average of about 3 (arm batch running): 45 ms knob on and 45 ms knob off; no quiet-host measurement was ... |
| DEC-0265 | proposed | S2 F: The profile oracle (tests/fixtures/profiles/standard-oracle.json) is each reader's own yq expression evaluated over the shipped example before any read... |
| DEC-0266 | proposed | S2 F: rtfm-testing is reclassified as a report-writing review skill rather than stripped: its Phase 4 writes a State-Zone report, so write_files: true, Write... |
| DEC-0267 | proposed | S2 F: generate-constraints.sh handles an empty class with an OPTIONAL_TABLES prune; agent_teams_constraints stays registered in the SECTIONS of generate-cons... |
~~~~~

## I05 — fix-commit — 2026-10-14

- reference: 2fb03b5c0a7d
- files: .claude/hooks/session-start/loa-decisions-surface.sh

Summary:

fix(cycle-129): Bridgebuilder PR #1282 round 1 — the session-cap dispatcher treats Bridgebuilder exit 3 as completed-degraded only when a run JSON with a verdicts array is on stdout (else ERROR, degraded false, exit 3) and records incomplete_voices as an array (F-001; new callers case); the three profile-governed SessionStart hooks say on stderr when profile-lib.sh cannot be sourced instead of go…

Evidence:

~~~~diff
commit 2fb03b5c0a7dedfbc6ee144c7184e47ac443aaa7
Date: 2026-10-14T21:55:25+11:00

fix(cycle-129): Bridgebuilder PR #1282 round 1 — the session-cap dispatcher treats Bridgebuilder exit 3 as completed-degraded only when a run JSON with a verdicts array is on stdout (else ERROR, degraded false, exit 3) and records incomplete_voices as an array (F-001; new callers case); the three profile-governed SessionStart hooks say on stderr when profile-lib.sh cannot be sourced instead of going dark silently, ASCII-only (F-002, gpt F001/F002); the generated hooks-reference table renders hook matchers with slashes (Write/Edit/MultiEdit/NotebookEdit) — the human format hook-wiring W6 pins, which the FR-1 generator had changed to escaped pipes (guard-yield.bats GY updated, table regenerated, --check in sync); F-004/F-005/F-006/F-007/F-010/F-011/F-012/F-013 refuted with evidence and F-008 filed as bd-8o5rx (triage note in a2a/sprint-257/bb-triage.md) (sprint-3)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/.claude/hooks/session-start/loa-decisions-surface.sh b/.claude/hooks/session-start/loa-decisions-surface.sh
index 3b3f836b..da134f84 100755
--- a/.claude/hooks/session-start/loa-decisions-surface.sh
+++ b/.claude/hooks/session-start/loa-decisions-surface.sh
@@ -47,8 +47,12 @@ elif [[ -f "$config_path" ]]; then
   if [[ $have_yq4 -eq 1 ]]; then
     # Explicit key, else the loa.profile default (cycle-129 D-9.1).
     # shellcheck source=../../scripts/lib/profile-lib.sh
-    source "${REPO_ROOT}/.claude/scripts/lib/profile-lib.sh" 2>/dev/null &&
+    if source "${REPO_ROOT}/.claude/scripts/lib/profile-lib.sh" 2>/dev/null; then
       enabled="$(loa_knob decisions.surface_at_session_start false 2>/dev/null || echo false)"
+    else
+      # Bridgebuilder PR #1282 F-002: off, but said (an explicit decisions.surface_at_session_start is not read then).
+      echo "WARNING: [loa-decisions-surface] profile-lib.sh could not be sourced: the decisions surface is off this session" >&2
+    fi
   else
     # top-level `decisions:` block, then an indented `surface_at_session_start: true`
     enabled="$(awk '
~~~~

## I06 — fix-commit — 2026-10-18

- reference: 463fbda1b101
- files: README.md

Summary:

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283) Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 463fbda1b1016d015067a21826c8dc6290eeef66
Date: 2026-10-18T19:14:03+11:00

fix(cycle-130): README version refs synced to 2.0.0-rc.5 (sync-readme-version.sh --apply; the CI README version sync check on PR #1283)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/README.md b/README.md
index 4d8fb07a..ea9abbdc 100644
--- a/README.md
+++ b/README.md
@@ -6,10 +6,10 @@ # Loa
 Architecture: Three-zone model (System: .claude/, State: grimoires/ + .beads/, App: src/).
 Configuration: .loa.config.yaml (user-owned, never modified by framework).
 Health check: /loa doctor
-Version: 2.0.0-rc.3
+Version: 2.0.0-rc.5
 -->
 
-[![Version](https://img.shields.io/badge/version-2.0.0--rc.3-blue.svg)](CHANGELOG.md)
+[![Version](https://img.shields.io/badge/version-2.0.0--rc.5-blue.svg)](CHANGELOG.md)
 [![License](https://img.shields.io/badge/license-AGPL--3.0-green.svg)](LICENSE.md)
 [![Release](https://img.shields.io/badge/release-v2.0.0--rc.2%20Friction%20floor-purple.svg)](https://github.com/0xHoneyJar/loa/releases/tag/v2.0.0-rc.2)
 
~~~~

## I07 — issue — 2026-10-19

- reference: #1285
- files: .gitignore

Summary:

docs(cycle-130): deep analysis of the review-side lift + out-of-sample replication — ## Summary Analysis only: no shipped number changes. Follow-on to PR #1283 / v2.0.0-rc.6 asking where the review-side lift (+0.263 on `defect_catch_rate`, DEC-0597) comes from, recomputed from the raw run directories, plus a pre-registered out-of-sample replication on two corpus PRs nobody had used (pr-17, pr-18)…

Evidence:

~~~~~text
# pull request #1285: docs(cycle-130): deep analysis of the review-side lift + out-of-sample replication

- url: https://github.com/0xHoneyJar/loa/pull/1285
- created_at: 2026-10-19T04:36:08Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

Analysis only: no shipped number changes. Follow-on to PR #1283 / v2.0.0-rc.6 asking where the review-side lift (+0.263 on `defect_catch_rate`, DEC-0597) comes from, recomputed from the raw run directories, plus a pre-registered out-of-sample replication on two corpus PRs nobody had used (pr-17, pr-18).

**Findings (`grimoires/loa/reports/ablation-2.0/analysis.md`, ELI5 at the top):**
- 57 paired defect-trials: full-only catches 15, bare-only 0; the whole lift sits on pr-12; cluster bootstrap by PR [+0.056, +0.437].
- No dissent envelope carries a numeric line anchor, so the dissent is credited with 0 citations in 36 runs; 10 of the 15 lift catches are the Fable reviewer alone, 2 the audit gate, at most 3 dissent-influenced. Dissent = 17 % of a full run's cost, audit gate 49 %.
- Two measurement artefacts: the ±3-line window (bare cites the bug line, labels sit on function headers; same-function rule → +0.140) and **KF-049**, the mounted-framework oracle (the full arm's sandbox mounts a later copy that already holds every fix; the reviewer diffed against it on planted sites in 1 of 12 original and 2 of 6 replication runs; bare has no such mount).
- 61 "false positives" hand-labelled blind by two Opus labelers (kappa 0.88): wrong ≈ 0; corrected precision bare 0.44 [0.36, 0.51], full 0.16 [0.10, 0.22].
- Replication (`replication-01`, USD 88.81, pre-registered DEC-0602/0603): the lift reappears and is larger (+0.452 [+0.310, +0.595] with two scanner-false-positive rows hand-read in; +0.333 [+0.190, +0.476] with every oracle-exposed catch zeroed), formally inconclusive by degradation under the rule as written (KF-046 recurrence 9). The dissent never ran at a review gate (budget gate), so the comparison is Fable twice with the skill's checklist against Opus once.
- Five ranked `cycle-131-candidate` changes (DEC-0604…0608 + beads bd-mlg9s, bd-5rmmf, bd-pacqf, bd-ba54i, bd-zv4og; harness follow-ups bd-9lfns, bd-1ohfe).

**Tracked in this PR:** `analysis.md`; the replication suite root `grimoires/loa/evals/ablation-2.0-replication/` (frozen `cffc7079`, fairness REVIEW.md PASS); the `priority-v2-p1b` batch `.gitignore`; `decisions.yaml` (DEC-0602…0608); `known-failures.md` (KF-049 new; KF-046 recurrence 9). Working files, data, labels, transcripts readings and the replication batch records go on `record/cycle-130-analysis` after merge.

**Process:** no `.claude/` or `evals/` code edits; the replication batch ran under an out-of-repo copy of `run-ablation.sh` that only adds `--allow-partial` to the freeze check and the grader call (DEC-0603, diff on the record branch); `evals/tests/` run locally at the close.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I08 — issue — 2026-10-20

- reference: #1287
- files: README.md

Summary:

chore(cycle-131): archive the cycle on main — Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`. - `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branc…

Evidence:

~~~~~text
# pull request #1287: chore(cycle-131): archive the cycle on main

- url: https://github.com/0xHoneyJar/loa/pull/1287
- created_at: 2026-10-20T12:28:08Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
Archive of cycle-131 "honest review-catch measurement" after PR #1286 merged as `7b024f5c`.

- `grimoires/loa/archive/cycle-131-honest-measurement/`: `prd.md`, `sdd.md`, `sprint.md`, `ledger.json` (root ledger at the close), `CHANGELOG.md` (the merged `[Unreleased]` section), `README.md` (index: merge, measurement reads, shipped mechanics, record branch, decisions, carry-overs), `.archive-meta.json`.
- `grimoires/loa/ledger.json`: cycle-131 `status: archived`, `archived_at`, `archive_path`; `active_cycle: null`.
- Records live on `record/cycle-131-honest-measurement` (`d6ccba2c`), never on main.

Same shape as the cycle-130 archive (PR #1284). No code changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~
