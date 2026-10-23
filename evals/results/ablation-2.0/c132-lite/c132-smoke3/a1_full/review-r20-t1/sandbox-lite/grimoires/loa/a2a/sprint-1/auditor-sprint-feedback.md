# Sprint 1 Security Audit

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md (Task 1.1: the change in `pr/head.diff`)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Review Feedback:** grimoires/loa/a2a/sprint-1/engineer-feedback.md (CHANGES_REQUIRED; review trailer `excluded: 0`)
**Dissent envelope:** grimoires/loa/a2a/sprint-1/adversarial-audit.json (gpt-5.5-pro + companion claude-headless, 6 findings, 0 rejected)

**Verdict:** CHANGES_REQUIRED

---

## Pre-flight note

The review gate returned CHANGES_REQUIRED, not "All good". The task instructions direct this audit to run against the PR files regardless, so the change is audited as it stands and the severity tally decides the verdict. Every counted finding below was re-derived from `pr/head/`; the security findings were reproduced against both the head hook and the base hook from `pr/base/`.

## Executive Summary

Most of this sprint holds up when executed, not just read. The fence corpus passes in full with the classifier on, and the knob-off run reproduces exactly the documented pre-change misses. The profile resolver, the lint invariants and the implement-gate mode matrix are green. Floor keys stay out of reach of the profile mechanism.

One finding blocks the merge. The new heredoc consumer classifier, described by the PR as fail-closed, fails open for a heredoc whose target file is executed later in the same Bash command through a substitution, a pipe into a shell, a variable, a glob or an argument-passing wrapper. The base fence blocks these commands and the head fence allows them. Turning the classifier knob off restores the block, so the regression is introduced by this change. Its blast radius is the System Zone write protection, which is a floor guard.

Five medium findings follow: the classifier's body keep-list and destination test are not conservative, two jq 1.6 portability failures in `run-checkpoint.sh`, the guardrail default flip that also fails open when the profile library is unavailable, and a roughly 5x to 9x latency increase in the per-write karpathy hook.

**Overall Risk Level:** HIGH

## Scope and method

- Read the implementation of every touched script under `pr/head/`: the fence classifier, `implement-gate.sh`, `run-checkpoint.sh`, `profile-lib.sh`, the karpathy hook, the two guardrail scripts, `loa-status.sh`, the surface hooks, `lint-invariants.sh`, `validate-skill-capabilities.sh`, the two new tools, and the config, profile and floor data.
- Executed from a copy of the head tree under `$HOME` because the sandbox mounts `/tmp` noexec and strips exec bits. Ran the fence corpus with the knob on and off, the head and base hooks on hand-built payloads, the PR's bats suites under jq 1.6 and jq 1.7.1, and a per-write latency measurement.
- `security-audit-scope.sh` reports 0 sources and 0 sinks for this shell repository. The recon was done by hand. The untrusted inputs are the Bash command text (fence), the Write/Edit payload and `.run/` files (gate), `.loa.config.yaml` and `.run/effective-config.json` (profile-lib), and feedback files plus the ledger (run-checkpoint).
- Phase 1C ran: `adversarial-review.sh --type audit --sprint-id sprint-1 --diff-file pr/head.diff --json` finished with exit 0.

| Check on the head tree | Result |
|------------------------|--------|
| Fence corpus, classifier on | benign 89/89, dangerous 142/142, p95 76 ms |
| Fence corpus, knob off | misses only D122, D123, D127, D131, D136, D141; blocks B80, B82, B85, B87, B88 |
| `profile-lib.bats` | 17/17 |
| `lint-invariants.bats` | 9/9 |
| `implement-gate.bats` IG-9 to IG-33 | pass (IG-1 to IG-8 and IG-12 need fixtures outside the PR) |
| `run-checkpoint-derive.bats` / `-record-round.bats`, jq 1.7.1 | 22/22, 8/8 |
| Same suites, jq 1.6 | 18 of 22 and 1 of 8 fail (MEDIUM-2, MEDIUM-3) |

---

## Findings

### HIGH-1 — The heredoc classifier drops a body that the same command executes

- **Severity:** high · **Confidence:** high · **Category:** security, protection-mechanism failure
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:608-631` (`_bdb_hd_same_line_exec`), with the replacement of the full scan at `head/.claude/hooks/safety/block-destructive-bash.sh:1063`
- **CWE-693** Protection Mechanism Failure: https://cwe.mitre.org/data/definitions/693.html
- **CWE-184** Incomplete List of Disallowed Inputs: https://cwe.mitre.org/data/definitions/184.html

Vulnerable code, `head/.claude/hooks/safety/block-destructive-bash.sh:625` and `:631`:

```bash
u="${_bdb_hd_tok[c]}"; u="${u//[\"\']/}"; u="${u##*/}"
...
if ! _bdb_hd_is_safe_reader "$cw" || [[ "$cw" == "$b" ]]; then return 0; fi
```

The header at `head/.claude/hooks/safety/block-destructive-bash.sh:154-156` claims that a target named anywhere else in the command outside a safe reader makes the heredoc interpreter-class. The code compares each token for exact equality with the basename, then judges only the segment holding that token. A consumer that reaches the file inside a substitution, through a pipe whose reader is `cat`, through a variable or glob, or through an argument-passing wrapper never satisfies both tests. The heredoc stays non-executing, and `_bdb_hd_scan_body` drops every body segment except fence verbs. A System-Zone write or a destructive command in the body is removed before the FR-SZ and FR-2 rules run.

Reproduction: for each consumer shape the base hook exits 2 (FR-SZ2-COPY or FR-2) and the head hook exits 0. With `destructive_command_guard.heredoc_classifier: false` the head hook blocks again. Direct consumers such as `bash <file>` and `./<file>` are still caught. The documented gap at `head/.claude/loa/reference/hooks-reference.md:298` covers a *later* command only, while these run inside one Bash tool call. The review and both dissent voices found the same defect independently.

**Required fix:**
1. When a later line names the target, treat the heredoc as interpreter-class if that line holds any substitution or process-substitution opener, a pipe into an interpreter or wrapper, a glob, or a variable bound to the target. Match by substring, not token equality, in those cases.
2. Treat a pipeline whose downstream member is an interpreter or wrapper as executing its input, whichever member names the target.
3. Add the reproduced shapes to `tests/fixtures/fence-corpus/corpus.jsonl` as `expect: block` rows and rerun the corpus with the knob on and off.

### MEDIUM-1 — Body keep-list and destination test are not conservative

- **Severity:** medium · **Confidence:** high · **Category:** security
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:214-219`, `:538-574`, `:303-322`
- **CWE-184:** https://cwe.mitre.org/data/definitions/184.html

Three gaps make any missed execution path worse than one dropped line:

- `_bdb_hd_is_destructive` keeps only the FR-2 family of verbs. The verbs the floor FR-SZ rules match, such as copy, move, link, tee and in-place sed, are not kept, so those rules never see a System-Zone write inside a kept body.
- `_bdb_hd_segword` does not strip shell keywords, leading redirects or `trap`, so a fence verb after one of them is dropped. A reproduced keyword-prefixed body is blocked by the base hook and allowed by the head hook when it is executed in the same command.
- `_bdb_hd_exec_dest` matches the target path literally at `:311` without collapsing `..`, `//` or `/./`. A git hook path written with a `..` segment is therefore not recognised as executable content. Combined with the keep-list gap, the dissent's same-command git-hook shape reproduces as allowed on head and blocked on base.

**Fix:** keep the FR-SZ verbs, and any segment that names `.claude/` or `.git/`. Skip shell keywords, redirects and `trap` in `_bdb_hd_segword`, or fall back to the full scan when a segment starts with one. Normalise the destination before matching. Add corpus rows for each case.

### MEDIUM-2 — `run-checkpoint.sh derive` does not compile on jq 1.6

- **Severity:** medium · **Confidence:** high · **Category:** code quality, portability
- **File:** `head/.claude/scripts/run-checkpoint.sh:378`
- **CWE-758** Reliance on Undefined, Unspecified, or Implementation-Defined Behavior: https://cwe.mitre.org/data/definitions/758.html

`--arg label "$label"` binds `$label`, and `label` is a jq keyword. jq 1.6 rejects the program (verified: `$label REJECTED` on 1.6, accepted on 1.7.1). Under `set -e`, `derive`, `mark` and the refresh after each checkpoint `write` therefore fail on Debian 12 and Ubuntu 22.04 hosts. The file-authoritative run position (FR-5) never gets written there, and the deny mode of the implement gate falls back to an unknown position. 18 of 22 derive cases fail on jq 1.6.

**Fix:** rename the binding, for example `--arg lbl`, or state and probe a jq 1.7 floor.

### MEDIUM-3 — An empty trailer aborts `fb_parse` on jq 1.6

- **Severity:** medium · **Confidence:** high · **Category:** code quality, portability
- **File:** `head/.claude/scripts/run-checkpoint.sh:226`
- **CWE-754** Improper Check for Unusual or Exceptional Conditions: https://cwe.mitre.org/data/definitions/754.html

```bash
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$pj" || pj='{}'
```

jq 1.6 exits 0 on empty input (1.7.1 exits 4, verified), so a feedback file without a `LOA-VERDICT` trailer leaves `$pj` empty, `--argjson p ''` fails and `record-round` aborts. The circuit breaker then misses that round. RCR-7 fails on jq 1.6.

**Fix:** test `[[ -n "$pj" ]]` before the jq check, and do the same for `$vj`.

### MEDIUM-4 — Guardrail defaults flip off, and enforcement fails open when the profile library is unavailable

- **Severity:** medium · **Confidence:** medium · **Category:** security configuration
- **File:** `head/.claude/scripts/danger-level-enforcer.sh:138-141`, `head/.claude/data/profiles.yaml:40-41`
- **CWE-1188** Initialization of a Resource with an Insecure Default: https://cwe.mitre.org/data/definitions/1188.html
- **CWE-636** Not Failing Securely: https://cwe.mitre.org/data/definitions/636.html

```bash
source "$SCRIPT_DIR/lib/profile-lib.sh"
...
    enforce=$(loa_knob guardrails.danger_level.enforce false)
```

Installs without an explicit key move from enforced (the old `// true` and `return 0`) to off under `standard`. The decision is recorded as DEC-0161, but nothing at runtime announces it. The `/loa` Profile line lists explicit overrides only. In addition, the old code fell back to `true` when yq failed. The new code falls back to `false`, and the unguarded `source` under `set -euo pipefail` aborts the script if the library is missing, which the orchestrator treats as fail-open. The same pattern applies to `guardrails.input.enabled` in `guardrails-orchestrator.sh`.

**Fix:** keep the intended default, but fail toward enforcement when resolution is impossible (`|| enforce=true`, guarded `source`). Emit a one-time notice when the effective value differs from the pre-cycle default.

### MEDIUM-5 — The per-write karpathy hook is roughly 5x to 9x slower

- **Severity:** medium · **Confidence:** medium · **Category:** performance
- **File:** `head/.claude/hooks/quality/karpathy-surgical-diff-check.sh:131`, with the knob reads at `:74` and `:78`

The PostToolUse hook now forks `run-checkpoint.sh read --json` on every Write, Edit and NotebookEdit. That costs several jq calls, plus `br show` when beads is installed. Two knob resolutions through `profile-lib.sh` add to it.

| Hook, five writes averaged | ms per write |
|----------------------------|--------------|
| base | 28 |
| head, no checkpoint | 152 |
| head, with a checkpoint | 260 |

**Fix:** read `.checkpoint.task` and `.checkpoint.sprint` from the state file with one jq, and resolve both knobs in one call.

### LOW-1 — The knob comment is wrong, and the config root falls back to the cwd

- **Severity:** low · **Confidence:** high
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:732-734`, `head/.loa.config.yaml.example:1243`

Both comments say that turning `heredoc_classifier` off "only tightens". The corpus shows knob-off misses six dangerous rows that the classifier catches, so the knob is a rollback, not a tightening. The config path falls back to `.` and so follows the process cwd, the same concern `implement-gate.sh` already handles by resolving from its own location. CWE-1188: https://cwe.mitre.org/data/definitions/1188.html

### LOW-2 — A new environment override sanctions writes under deny

- **Severity:** low · **Confidence:** medium
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:590`

`LOA_IMPLEMENT_GATE_OVERRIDE=1` is new in this PR (no occurrence in the base file). It allows every App-Zone write in every mode, including `deny`. The fence states the opposite stance for itself at `head/.claude/hooks/safety/block-destructive-bash.sh:760-761`. The variable is operator-set and logged, so the risk is low. Restricting it to `ask` and `telemetry`, or reading it from outside the repository, would keep `deny` a fence. CWE-807 Reliance on Untrusted Inputs in a Security Decision: https://cwe.mitre.org/data/definitions/807.html

### LOW-3 — The marker sanction can be forged through the Bash tool

- **Severity:** low · **Confidence:** high
- **File:** `head/.claude/hooks/compliance/implement-gate.sh:545-550`

`.run/implement-active.json` sanctions App-Zone writes for two hours, and nothing ties it to the harness. The Write tool path asks, but a Bash write does not. `head/.claude/loa/reference/hooks-reference.md:273` documents this as the accepted gap bead bd-taee, and the repository stays on `ask`, so this is counted low. Before `deny` is promoted to a default, the marker needs integrity, for example an HMAC with a key held outside the tree. CWE-345 Insufficient Verification of Data Authenticity: https://cwe.mitre.org/data/definitions/345.html

### LOW-4 — The destination list misses other executed or loaded files

- **Severity:** low · **Confidence:** medium
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:303-322`

`_bdb_hd_exec_dest` treats hooks, settings, rc files and PATH directories as executable. It does not treat `.mcp.json`, `.claude/skills|commands|agents|rules/`, `.github/workflows/`, `.husky/`, `.pre-commit-config.yaml`, `Makefile`, `package.json` or `~/.bash_aliases` that way. Writes there are classified as non-executing. CWE-184: https://cwe.mitre.org/data/definitions/184.html

### LOW-5 — The legacy hash uses GNU-only alternation

- **Severity:** low · **Confidence:** low
- **File:** `head/.claude/scripts/run-checkpoint.sh:230`

`grep -A 100 "## Findings\|## Issues\|## Changes Required"` relies on GNU BRE `\|`, while the script otherwise caters to macOS. On BSD grep the fallback hash is computed over nothing. Use `grep -E` with `|`. CWE-758: https://cwe.mitre.org/data/definitions/758.html

### LOW-6 — Report and changelog hygiene

- **Severity:** low · **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1-4`

The implementation report is the PR title and a file count. It has no AC walkthrough and no test-run summary. The PR changes two security defaults and the Bash fence without a CHANGELOG entry. The documentation audit lists a CHANGELOG that omits security changes as a blocker. It is counted low here because HIGH-1 already decides the verdict. The next round should carry the AC table, the commands run and a CHANGELOG entry for the guardrail default flip and the classifier.

---

## Observations (not counted)

- **Snapshot artefact.** `karpathy-surgical-diff.bats` and `karpathy-surgical-diff-hook.bats` do not parse in this checkout. A secret-redaction pass replaced one line with `local REDACTED-TEST-SECRET"`, which leaves an unbalanced quote. The same artefact is in the base file, so this is an environment issue, not a PR defect.
- **PF-1 and PF-5.** These `profile-floor.bats` cases fail here. PF-1 checks a sha256 pin held in `guard-origins.bats`, which is outside the PR. PF-5 depends on the yq flavour used by `adversarial-review-gate.sh`. Both need confirmation in CI.
- **Review demotions.** The review trailer counts `excluded: 0`, so there is nothing to confirm; `excluded_confirmed` is 0.

## Cross-Model Dissent

Two voices completed: gpt-5.5-pro and the companion claude-headless.

- **DISS-001 (HIGH)**: destination paths are not normalised before the executable-location test, and `trap` hides the body. Reproduced: head allows, base blocks. Counted under MEDIUM-1 because it is the same keep-list and destination family, reachable only through a same-command trigger.
- **DISS-C-001 (HIGH)**: the per-segment keep-list misses non-first-word verbs, and same-command execution goes undetected. Reproduced. Counted as HIGH-1 plus MEDIUM-1.
- **DISS-C-002 (HIGH)**: the `.run/implement-active.json` marker is forgeable under deny. Accurate, but it is the documented accepted gap bd-taee and `deny` is opt-in. Counted as LOW-3.
- **DISS-C-003 (MEDIUM)**: the environment override loosens deny. Confirmed new in this PR. Counted as LOW-2.
- **DISS-C-004 (MEDIUM)**: the guardrail defaults flip and enforcement fails open. Counted as MEDIUM-4.
- **DISS-C-005 (MEDIUM)**: the executable-destination list is incomplete. Counted as LOW-4.
- **DISS-C-006 (MEDIUM)**: C-TEAM constraints deleted. Not a defect. The five rules moved to `head/.claude/loa/reference/agent-teams-reference.md:32-44`, the three team hooks stay registered, and `lint-invariants.sh` now checks table presence. Not counted.

## Rejected dissent payloads

None. The envelope's `metadata.rejected_summary` is empty, `rejected_count` is 0, and the sidecar `adversarial-rejected-audit.jsonl` is empty.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 6 |

The one-way rule applies: high > 0, so the verdict is CHANGES_REQUIRED.

## Security Checklist

- [x] No hardcoded secrets or credentials
- [ ] Input validation: the heredoc classifier fails open (HIGH-1, MEDIUM-1)
- [x] Authorization: gate sanctions are fail-ask; the forgeable marker is a documented gap (LOW-3)
- [x] Injection: jq values pass through `--arg` and `--argjson`; key paths are validated before yq
- [x] Dependencies: bash, jq and yq only, but the jq floor is unstated (MEDIUM-2, MEDIUM-3)
- [x] Error output: paths and claims are control-stripped and cut to 256 bytes
- [ ] Secure defaults: guardrails fail open on resolution failure (MEDIUM-4)

## Next Steps

1. Fix HIGH-1 and MEDIUM-1 in `block-destructive-bash.sh`, add the reproduced shapes as corpus `block` rows, and rerun the corpus with the knob on and off.
2. Rename `$label` and guard the empty-trailer path in `run-checkpoint.sh`, or declare and probe jq 1.7.
3. Make the guardrail scripts fail toward enforcement when the profile library cannot resolve.
4. Update `reviewer.md` with an AC table and add a CHANGELOG entry, then run `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

*Generated by Paranoid Cypherpunk Auditor*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":6},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T15:10:21Z"} -->
