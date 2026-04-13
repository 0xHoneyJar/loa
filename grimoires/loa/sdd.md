# SDD: Lore Promoter — HARVEST phase consumer

**PRD**: grimoires/loa/prd.md (v1.0)
**Cycle**: cycle-060
**Issue**: [#481](https://github.com/0xHoneyJar/loa/issues/481)
**Date**: 2026-04-13

---

## 1. Architecture Overview

Single shell script (`.claude/scripts/lore-promote.sh`) driven by `jq` + `yq` + `flock`. Reads candidate queue + decisions journal, prompts user (or auto-decides via threshold), writes atomically to `patterns.yaml` and journal. No daemon, no long-lived state, no network except optional `gh` calls for merge-status gating.

```
┌────────────────────────────────────────────────────────────┐
│  lore-promote.sh [--flags]                                 │
└────────┬───────────────────────────────────────────────────┘
         │
         ├─► Acquire flock on a SHARED lockfile (.run/lore-promote.lock)
         │   covering BOTH patterns.yaml AND journal writes (Flatline SDD blocker #1)
         │   10s timeout → abort with clear error (blocker #2: documented)
         │
         ├─► Load queue (.run/bridge-lore-candidates.jsonl)
         ├─► Load decisions journal (.run/lore-promote-journal.jsonl)
         ├─► Compute undecided candidates = queue - (journal decisions)
         │
         ├─► Mode dispatch:
         │     ├─ --interactive (default): per-candidate prompt
         │     │     user choice: A/R/S/E/Q
         │     │
         │     └─ --threshold N: auto-promote if merged-PR count ≥ N
         │
         ├─► For each Accepted/auto-promoted candidate:
         │     1. Sanitize all free-text fields
         │     2. Check merge status of source PR (gh pr view)
         │     3. Generate id (slugify + collision disambiguation)
         │     4. Append to patterns.yaml.tmp
         │     5. mv patterns.yaml.tmp → patterns.yaml
         │     6. Append {id, action: "promoted", pr, decided_at} to journal
         │
         ├─► For each Rejected candidate:
         │     Append {id, action: "rejected", pr, reason, decided_at} to journal
         │
         ├─► Release flock
         └─► Print summary + exit 0
```

## 2. Component Design

### 2.1 CLI surface
Per PRD FR-1. Standard bash `case` loop, strict validation for each flag (numeric checks, file existence).

### 2.2 Queue state machine (Flatline SDD blocker #4 — accepted)
A candidate is in one of three states at any time:
- **Pending**: in queue, no journal decision yet
- **Promoted**: journal has `{candidate_key, action: "promoted"}`, entry is in `patterns.yaml`
- **Rejected**: journal has `{candidate_key, action: "rejected", reason: "..."}`

**Candidate key**: queue entries do not have a top-level `id` field (they have `finding_id` + `pr_number`). The canonical `candidate_key` is the composite `"{pr_number}:{finding_id}"` — unique per finding per PR. This is the key used for set-difference computation, not the promoted lore `id` (which is generated on promotion per FR-2.1 and is about the *lore entry*, not the *candidate decision*).

Computing pending set:
```bash
all_candidate_keys = [for entry in queue: "${pr_number}:${finding_id}"]
decided_keys       = [for entry in journal: .candidate_key]
pending            = all_candidate_keys - decided_keys
```

Journal entries include both `candidate_key` (for decision tracking) and `id` (for promoted lore entries — null when rejected).

Journal is append-only and the source of truth for what's been decided. Queue file never mutates after `post-pr-triage.sh` writes it.

### 2.3 ID generation with collision handling (PRD FR-2.1)

```bash
generate_id() {
    local term="$1"
    local content_hash="$2"  # sha256 of full candidate content
    local base
    base=$(echo "$term" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-\|-$//g')
    if yq ".[] | select(.id == \"$base\")" "$LORE_PATH" 2>/dev/null | grep -q .; then
        # Collision — append short hash
        local short=${content_hash:0:6}
        echo "${base}-${short}"
    else
        echo "$base"
    fi
}
```

Unit test: two candidates with `term: "Governance Isomorphism"` but different `context` values must produce different ids (second one gets `-<hash>` suffix).

### 2.4 Sanitization pipeline (PRD FR-5)

Applied to every free-text field in order:

```bash
sanitize() {
    local text="$1"
    local max_chars="$2"

    # 1. Strip ANSI escape sequences
    text=$(echo "$text" | sed 's/\x1b\[[0-9;]*m//g')

    # 2. Strip null bytes and control chars (except tab/LF/CR)
    text=$(echo "$text" | tr -d '\000-\010\013\014\016-\037\177')

    # 3. Scan for injection patterns → reject
    for pattern in "${INJECTION_PATTERNS[@]}"; do
        if echo "$text" | grep -qiE "$pattern"; then
            log_rejection "injection pattern matched: $pattern"
            return 1
        fi
    done

    # 4. Enforce length
    if [[ ${#text} -gt $max_chars ]]; then
        log_rejection "exceeds length limit ($max_chars chars)"
        return 1
    fi

    printf '%s' "$text"
}
```

`INJECTION_PATTERNS` = array of regex patterns loaded from `.claude/data/injection-patterns.yaml` (if present) else hardcoded baseline:
- `Ignore previous instructions`
- `You are now|From now on`
- `^(system|user|assistant):`
- `<script|<iframe|javascript:`

### 2.5 Two-phase write with journal (PRD NFR-3)

Per SDD diagram. The key safety property: **any crash between steps leaves the system in a recoverable state** because the journal is the source of truth.

- Crash between step 1 (`.tmp` written) and step 2 (`mv`): `.tmp` file orphaned, next run detects & cleans up, no journal entry means no re-prompt needed
- Crash between step 2 (`mv` done) and step 3 (journal append): `patterns.yaml` has the entry but journal doesn't. Next run recomputes pending = queue - journal and would re-prompt. BUT: checking `id` uniqueness against `patterns.yaml` detects the pre-existing entry → skip + log reconciliation message → journal is back-filled
- Crash between step 3 and 4: journal has decision, queue marker doesn't matter (queue file is effectively read-only post-`post-pr-triage.sh`)

### 2.6 Merge-status gating (PRD NFR-4 defense layer 4)

Before auto-promoting a candidate in threshold mode:
```bash
pr_state=$(gh pr view "$pr_number" --json state --jq '.state' 2>/dev/null || echo "UNKNOWN")
if [[ "$pr_state" != "MERGED" ]]; then
    log "Skipping pr=$pr_number — not merged (state=$pr_state)"
    return 1
fi
```

Interactive mode informs the user of PR state but does not block — human judgment can accept an open PR's finding if appropriate.

## 3. Data Model

### 3.1 Input: candidate queue entry (existing)

Per `.claude/data/trajectory-schemas/bridge-triage.schema.json`. Relevant fields:

```json
{
  "timestamp": "2026-04-13T12:00:00Z",
  "pr_number": 469,
  "finding_id": "F6",
  "severity": "PRAISE",
  "action": "lore_candidate",
  "reasoning": "...",
  "finding_content": {
    "title": "...",
    "description": "...",
    "tags": ["...", "..."]
  }
}
```

### 3.2 Output: lore entry

```yaml
- id: governance-isomorphism-a3b5c2
  term: Governance Isomorphism
  short: Multi-perspective evaluation with fail-closed semantics appears identically across Flatline, Red Team, and vault governance.
  context: |
    The review pipeline and the vault share an identical governance shape: multiple independent evaluators must reach consensus before state changes are permitted. This pattern enables cross-pollination: security review patterns from code review can inform on-chain governance design.
  source:
    pr: 469
    finding_id: F6
    bridge_iteration: "PR #469 pass 2"
    cycle: cycle-060
    promoted_at: "2026-04-13T14:30:00Z"
  tags:
    - governance
    - flatline
    - red-team
    - cross-ecosystem
```

### 3.3 Decisions journal entry

```jsonl
{"decided_at":"2026-04-13T14:30:00Z","id":"governance-isomorphism-a3b5c2","action":"promoted","pr":469,"finding_id":"F6","tool_version":"cycle-060"}
{"decided_at":"2026-04-13T14:31:00Z","id":"bad-pattern-xyz","action":"rejected","pr":470,"finding_id":"F2","reason":"injection_pattern_matched","tool_version":"cycle-060"}
```

## 4. Testing Strategy

BATS suite at `tests/unit/lore-promote.bats`. Minimum 12 cases:

| # | Test | Coverage |
|---|------|----------|
| T1 | Happy path: one candidate, interactive accept | FR-3, FR-8 |
| T2 | Interactive reject logs to journal with reason | FR-3 |
| T3 | Interactive skip leaves candidate pending | FR-3 |
| T4 | Idempotency: re-run doesn't duplicate promoted entries | FR-6 |
| T5 | Sanitization rejects injection pattern | FR-5 |
| T6 | Length limit enforced on `short` and `context` | FR-5 |
| T7 | ID collision triggers hash suffix | FR-2.1 |
| T8 | Empty queue exits 0 with info message | FR-7 |
| T9 | Missing `patterns.yaml` auto-created | FR-7 |
| T10 | Threshold mode requires ≥2 merged PRs | NFR-4 |
| T11 | Unknown flag exits 2 | FR-1 |
| T12 | Crash recovery: journal + yaml desync reconciled | NFR-3 |

## 5. Security Design

Threat model: malicious PR author crafts PRAISE-shaped content designed to inject into future Bridgebuilder/Flatline prompts via `patterns.yaml` → `buildEnrichedSystemPrompt()`.

Defense layers (PRD NFR-4):
1. Pattern scan (FR-5) — primary filter
2. Length limits — blast-radius cap
3. Schema validation — structural guard
4. Merge gating (merge status check) — trust signal
5. Interactive default — human judgment

Each layer alone is defeatable; in combination they raise the adversarial bar significantly. Not proven-secure; documented as Known Limitation.

## 6. Performance

For ≤1000 pending candidates: interactive mode dominated by human decision latency; threshold mode completes in < 5s. Bottleneck is `gh pr view` calls (one per auto-promotion candidate). Cache merge status in a session-local dict to avoid repeated calls for the same PR.

## 7. Rollback

Single script; `git revert` removes it. No schema changes, no migration. Journal + patterns.yaml are additive — rolling back the promoter doesn't invalidate entries already in `patterns.yaml` (they continue to be consumed by `core/lore-loader.ts`).

## 8. Integration Points

- **Input**: `.run/bridge-lore-candidates.jsonl` (produced by `post-pr-triage.sh` since v1.73.0) + new `.run/lore-promote-journal.jsonl` (written by this script)
- **Output**: `grimoires/loa/lore/patterns.yaml` (consumed by v1.75.0 `core/lore-loader.ts`)
- **Observability**: `bridge-triage-stats.sh --since ...` shows the producer side; this cycle adds the consumer side
- **Cross-reference**: run-bridge SKILL.md should link to this as the HARVEST-phase consumer pattern
- **Required follow-up (Bridgebuilder Design Review F1-REFRAME)**: wire `lore-promote.sh --threshold 2` into `post-merge-orchestrator.sh` so promotion becomes as continuous as the producer. Without this hook, the consumer remains operator-triggered and the spiral never closes. Not in scope for this cycle (MVP delivers the script itself), but MUST be the next cycle. Tracked separately.

---

*Sources: PRD cycle-060 §§1-7, existing trajectory schema, existing `patterns.yaml` as format anchor, Flatline PRD review (6 blockers addressed in PRD revisions).*
