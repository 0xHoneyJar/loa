# Security & Quality Audit Report — Sprint 252 (cycle-128 Sprint 1)

**Auditor:** Paranoid Cypherpunk Auditor (Claude Fable 5.1)
**Date:** 2026-10-13T03:35:38Z
**Scope:** commits 8dc4a49d, 2bcf0e40 and the audit-round fixes (this commit) on feature/cycle-128-decision-surfaces: the decision ledger writer, validator types, SessionStart surface, the operator-only command, the rounds pacing text and checker, the FR-8 flag set, lint and harness test (38 code/test files, ~3,600 lines added)
**Methodology:** Systematic 5-category review (Security, Architecture, Code Quality, DevOps; Blockchain not applicable); scope scan (`security-audit-scope.sh`: 5 sources, 4 sinks, 0 auth, 0 LLM files in the changed surface); recon and investigate passes over every changed file (read in full in the review phase and re-walked here as sources → sinks); cross-model security dissent (two voices, `adversarial-audit.json`, status clean, 0 rejected payloads).

---

## Executive Summary

The sprint adds a tracked, append-only decision ledger and the surfaces around it. The trust model is sound for what it claims: the writer derives attribution from the run context and never from a caller argument; every unattended write lands `proposed`; the verify-before-rename step rejects any content edit, dropped id or duplicate id and runs the validator with the pre-write file as the base; artifact-backed voices carry a sha256 that the validator re-checks; the SessionStart surface is default-off, reads only id/status/summary, strips control characters and prints inside the L6 data fence; the operator command is hidden from the model's Skill tool, and the live harness check proved that refusal. The one trust-boundary weakness is the one the design names as its honest limit: the operator-only operations are authorised by a convention (`--recorded-by decisions-command`) that a Bash-capable skill can imitate. It is recorded as MEDIUM and carried as a follow-up bead; it does not weaken anything that exists today, because no earlier surface recorded operator decisions at all.

The security dissent found no critical or high issue. Its two MEDIUMs are the convention above and a pre-existing weakness in `/contribute`'s secrets check (a file this sprint touched only to add the flag line); its LOWs were sanitisation gaps in two new surfaces (terminal escapes through the round checker's output; unsanitised ledger text in the INDEX family) and an unbounded argv in the checker, all fixed in the audit round with tests, plus a pre-existing unpinned recovery script in `/loa-eject`. The auditor's own LOW (an unrestricted `import --rewrite` path) was fixed in the same round.

**Overall Risk Level:** LOW

**Key Statistics:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 4 |

---

## Category Scores (Rubric-Based Assessment)

| Category | Score | Dimensions |
|----------|-------|------------|
| Security | 4.2/5 | IV:5 AZ:3 CI:4 IN:4 AV:5 |
| Architecture | 4.4/5 | MO:5 SC:4 RE:4 CX:4 ST:5 |
| Code Quality | 4.4/5 | RD:4 TC:5 EH:4 TS:5 DC:4 |
| DevOps | 4.0/5 | AU:4 OB:4 RC:4 AC:4 DS:4 |
| **Overall** | **4.3/5** | LOW |

Authorization scores 3 because operator-only is a convention plus lint, not a mechanism the agent cannot bypass (see MEDIUM-001).

---

## Findings

### [MEDIUM-001] Operator-only ledger operations are authorised by a caller-supplied string

**Severity:** MEDIUM | **Confidence:** high
**Component:** `.claude/scripts/lib/dec-write-lib.sh:303` (`is_operator_call`), `.claude/commands/decisions.md`
**Criterion:** SEC-AZ Authorization

**Reasoning Trace:**
> `confirm`, `reject`/`supersede` of a decided row and `context --clear` check `--recorded-by decisions-command`; `decided_by: operator` derives from an operator-shaped `--answer-ref` (`cli:<iso>`) the same session supplies. Nothing binds either to a human. The Skill tool refusal (`disable-model-invocation`) stops the model from starting `/decisions`, and the lint keeps the operations out of every `allowed-tools` and body, but a skill with unrestricted Bash can run the lib directly. Mitigations in place: `confirm` refuses while any live-run signal stands (so an unattended run cannot confirm its own rows), every transition carries `by` and the HEAD commit, and the ledger is append-only, so a bypass leaves a trace. The SDD states this as the honest limit (§9).

**Description:** Attribution is tamper-evident, not enforced. **Impact:** A misbehaving or injected agent in an interactive session could self-confirm rows; the record would show `by: operator:decisions-command` with a `cli:` ref and no AskUserQuestion evidence. **Remediation:** Follow-up bead bd-g6k3: a Bash fence rule blocking `dec-write-lib.sh (confirm|supersede|context --clear)` and decided-row `reject` outside the `/decisions` step, so a bypass is logged by the fence; longer term, an AskUserQuestion-mediated nonce or signing through the audit chain (PRD D19). Also matches dissent DISS-C-001.

### [MEDIUM-002] `/contribute` secrets check scans only the final diff (pre-existing)

**Severity:** MEDIUM | **Confidence:** medium
**Component:** `.claude/commands/contribute.md` (unchanged logic; this sprint added the `disable-model-invocation` line only)
**Criterion:** SEC-CI Confidentiality

**Reasoning Trace:**
> Dissent DISS-C-002: the pre-push secrets check is a five-substring list over changed files in the final tree, with `git_safety.bypass: true`; a credential committed and removed within the branch is absent from the final diff yet present in the pushed history. Pre-existing behaviour outside this sprint's scope; now operator-only, which narrows who can trigger it.

**Remediation:** Follow-up bead bd-48ni: scan every commit on the branch (`git log -p main..HEAD`) with a real pattern set before pushing. Not a change to this sprint.

### [LOW-001] Round checker printed untrusted ids unescaped (fixed, audit round)

**Severity:** LOW | **Confidence:** high | **Component:** `tools/check-round-independence.sh`
Dissent DISS-C-003: ids from a model-generated transcript reached the terminal through `jq -r`, decoding `\u001b` into raw bytes. Fixed: ids and depends_on entries must match `^[A-Za-z0-9_.-]{1,64}$` (else a malformed-block violation) and every printed string is control-stripped; a fixture with an ESC id exits 1 with no ESC byte in the output (verified by `od`). `tests/unit/check-round-independence.bats` 18/18.

### [LOW-002] Round checker passed growing JSON through argv (fixed, audit round)

**Severity:** LOW | **Confidence:** medium | **Component:** `tools/check-round-independence.sh`
Dissent DISS-C-004: the accumulated rounds array and each block were single argv strings (128 KiB cap). Fixed: oversized blocks are a clear violation and the accumulation goes through files; bats case with a 200 KiB block.

### [LOW-003] INDEX decisions family emitted ledger text with only `|` escaped (fixed, audit round)

**Severity:** LOW | **Confidence:** high | **Component:** `.claude/scripts/grimoire-index.sh` `emit_decisions()`
Dissent DISS-C-005: summaries and sources (agent-authored, untrusted) reached INDEX.md, TSV and JSON unsanitised while the SessionStart surface cleans the same rows. Fixed: control characters, tabs and newlines stripped, angle brackets replaced, summary capped at 160 characters, `|` escaped for markdown; bats cases for tab, newline, ESC and `<script>` in TSV, JSON and md. INDEX regenerated.

### [LOW-004] `/loa-eject` recovery pipes an unpinned remote script into bash (pre-existing)

**Severity:** LOW | **Confidence:** high | **Component:** `.claude/commands/loa-eject.md` (unchanged logic; flag line added)
Dissent DISS-C-006: the recovery section runs an unpinned `main` script with `--force` and no checksum. Pre-existing; operator-only now. Follow-up bead bd-xtip: pin to a tag and verify a checksum.

### Auditor's own finding, fixed in the audit round

- `dec-write-lib.sh import --rewrite PATH` rewrote any writable file the caller named. Fixed: targets must canonicalise under PROJECT_ROOT, `..` and outside paths exit 1; bats case. Counted under LOW-003's round, not tallied separately (same fix round, same class of path hygiene).

---

## Sources and sinks walked

| Source (untrusted) | Sink | Guard observed |
|---|---|---|
| ledger rows (agent text) | SessionStart stdout | control strip, bracket replace, 100-char cap, L6 fence; nothing printed without the sanitizer |
| ledger rows | INDEX.md / TSV / JSON | now control-stripped, bracket-replaced, capped (LOW-003 fix) |
| `--file`, `--rewrite`, `--from` paths | filesystem writes | canonical-path kind classification; CI/hook refusal by kind; `..` and outside-project refused for rewrite and artifacts |
| `--answer-ref` / `--as` | attribution fields | ignored unattended; grammar-checked; artifacts must exist inside the project with a recorded sha256 |
| row text | YAML | built with `jq --arg`, appended via `env(ROW)`, string style forced; verify-before-rename; validator re-parses |
| transcript blocks | checker output | id charset, size bound, control strip (LOW-001/002 fix) |
| command/skill bodies | lint | read-only awk; clause-scoped exempt judgement |
| `.run/unattended.json` | unattended detection | session id + TTL; stale markers ignored and surfaced; clearing is operator-only by convention (MEDIUM-001) |
| `claude -p` harness run | live test | Skill tool only, fixture commands only, skipped without the CLI |

No secrets in tracked state; `pii-filter.sh` runs on the ledger validator; `check-no-raw-sha256sum.sh` OK.

## Review demotions confirmed

The review trailer records `excluded: 0`; nothing to confirm (`excluded_confirmed: 0`).

## Severity Tally (Phase 2.5)

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 2 |
| Low | 4 |

## Verdict

APPROVED - LET'S FUCKING GO

Zero critical or high findings. Both MEDIUMs are carried as follow-up beads (bd-g6k3, bd-48ni); three of the four LOWs are fixed in this sprint with tests, the fourth is a pre-existing operator-only command (bd-xtip). Verification on the final tree: 353/353 across the 14-suite set, `check-prompt-budget.sh` exit 0, `check-no-raw-sha256sum.sh` OK, `validate-artifact --type decisions` 73 rows exit 0.

## Rejected dissent payloads

None. `adversarial-rejected-audit.jsonl` absent or empty; `metadata.rejected_summary` is `[]`.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":2,"low":4},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-252","ts":"2026-10-13T03:35:38Z"} -->
