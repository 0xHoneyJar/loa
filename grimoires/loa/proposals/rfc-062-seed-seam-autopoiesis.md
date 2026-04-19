# RFC-062: SEED Seam Autopoiesis — Auto-Drafting + Failure-Dependency Gating

**Status**: DRAFT v2 (Flatline round 1 findings addressed)
**Authors**: Claude Opus 4.7 (drafting) on behalf of operator work plan
**Date**: 2026-04-19
**Cycle**: 089 (SEED-seam autopoiesis design)
**Related**:
- #575 (umbrella, 6-primitive RFC from three-lens audit)
- RFC-060 (spiral meta-orchestrator)
- Items 2, 3, 5, 6 shipped in v1.96.2 / v1.99.1 / v1.99.2 / v1.101.0
**Supersedes**: nothing — additive

**v3 revisions** (2026-04-19, post Flatline round 2 with 3-model agreement at 90%):
- **R2-B1**: Defer-with-rationale gaming — TTL + rationale schema + revalidation (§2.10)
- **R2-B2**: Default mode undermines hard-dep claim — startup banner + default-strict for new installs (§2.11)
- **R2-B3**: Lineage binding lacks authenticity — signed metadata with runtime-controlled key (§1.9)
- **R2-B4**: Reconciliation ABANDONED doesn't block in strict — strict mode treats PENDING / FAILED / ABANDONED as blocking (§2.12)
- **R2-B5**: Sanitizer regex-bypassable — structured parse + Unicode NFKC + adversarial test corpus (§1.10)

**v2 revisions** (2026-04-19, post Flatline round 1 with 3-model agreement at 100%):
- **B1**: Rubber-stamp risk — operator intent statement is MANDATORY, not auto-drafted; draft acceptance requires explicit diff review (§1.6)
- **B2**: Beads enforcement when CLI unavailable — strict/warn mode split with startup prerequisite check (§2.6)
- **B3**: Non-atomic bead creation — append-only failure journal + idempotency key + reconciliation on startup (§2.7)
- **B4**: Global blocking too coarse — scope-aware gating via `spiral:scope:<repo>:<area>` labels; blanket block is now opt-in (§2.8, OQ-5 updated)
- **B5**: Stale draft replay — cryptographic lineage binding (source/target cycle IDs + content hash in frontmatter); `--force-stale-draft` override (§1.7)
- **B6**: Prompt injection in auto-ingested text — sanitizer pass with directive stripping + content caps + explicit human confirmation for high-risk surfaces (§1.8)

---

## Problem Statement

After RFC-060 shipped `/spiral` and items 2, 3, 5, 6 from #575 closed the visible friction points, the autopoietic loop is now tight from **SEED-authored → HARVESTed → discovery context** but still **hand-authored at the SEED boundary itself**.

Concretely:

- HARVEST (`spiral-harvest-adapter.sh`) produces a typed `cycle-outcome.json` sidecar with review verdicts, audit verdicts, findings, flatline signatures, content hashes.
- The next cycle's discovery phase can now ingest the prior flight-recorder (#575 item 2) and runs behind a CWD/invariant gate (#575 item 3).
- But the **SEED itself** — the operator's statement of cycle-N+1 intent — is not informed by HARVEST output. Operator hand-composes intent; HARVEST outputs sit in typed queues; no bridge connects them.

The RFC quote:

> *"tool informs build informs tool. Entropy is drift toward one-shot linearity; iteration is the remedy."*

Today the arrow from **build back to tool** is load-bearing at the artifact seam (code + lore + visions + bugs all route back in) but **null at the intent seam**. The operator still carries the cognitive load of "what should cycle-N+1 actually pursue given cycle-N's outcomes." This RFC closes that gap.

Two primitives from #575 address it together:

### Item 1 — Auto-SEED-from-HARVEST

**K-hole's `--trail` as architectural precedent**: in the research-descent tool, each dig's `pull_threads` + `emergence` fields auto-seed the next dig. The operator edits a scaffolded query, doesn't compose one from scratch. Port this to `/spiral`:

- HARVEST emits `pull_threads` (open questions the cycle surfaced but didn't answer) and `emergence` (unexpected patterns / adjacent problems that showed up in review/audit).
- EVALUATE phase writes `.run/cycles/cycle-NNN/seed-draft.md` — a scaffolded successor SEED.
- Next cycle's start reads the draft as the operator's default task-seed (operator can accept / edit / discard).

### Item 4 — Failure-Typed Bead Escalation as SEED Hard-Dep

**"Membrane repair primitive"**: when cycle-N trips a circuit breaker, that failure needs to propagate to cycle-N+1 as a hard precondition — not a soft signal buried in flight-recorder.

- Circuit breaker trip autogenerates a typed beads task with classification (`scope-mismatch` / `cwd-mismatch` / `review-fix-exhausted` / `budget-exhausted` / `flatline-stuck`).
- Next spiral dispatch checks for unresolved failure beads. If any exist and `spiral.seed.skip_failure_deps` ≠ true, the dispatch is blocked with an actionable message.
- Operator must **resolve the bead** (fix or explicit defer-with-rationale) before cycle-N+1 starts. System cannot advance past its own wounds unacknowledged.

### Composition claim

The two primitives together shift operator role from *"composer of intent"* to *"reviewer of auto-drafted successor state with mandatory acknowledgment of prior failures"*. Semantically equivalent to HITL; mechanically autopoietic.

---

## Goals

- **G1** — Close the intent-seam loop: auto-draft cycle-N+1 SEED from cycle-N HARVEST so operator can default-accept instead of default-compose.
- **G2** — Make prior-cycle failures load-bearing on next-cycle dispatch: typed beads + hard dependency gate.
- **G3** — Preserve operator autonomy: every auto-drafted SEED is editable; every failure gate has an explicit defer-with-rationale escape hatch.
- **G4** — Backwards compatibility: existing operators who don't want auto-drafting or failure gating see no behavior change (both features default off).
- **G5** — Schema versioning: HARVEST sidecar extensions follow explicit semver + `$schema_version` bumps with validators accepting both old and new.

## Non-Goals

- **NG1** — Full agency: the system does not dispatch cycle-N+1 without operator trigger. Auto-drafting happens at EVALUATE; dispatching still requires `/spiral --start` or `--resume`.
- **NG2** — Failure auto-fix: the system diagnoses + classifies circuit breaks into beads but does not attempt fixes. Human work remains.
- **NG3** — Vision/lore promotion: already shipped via `post-merge-orchestrator.sh` + `vision-registry` — out of scope here.
- **NG4** — Beads replacement: this RFC extends existing beads patterns, doesn't propose a new tracker.
- **NG5** — Multi-operator coordination: single-operator semantics only. Team-mode considerations deferred.

---

## Design

### Part 1 — Auto-SEED-from-HARVEST (#575 item 1)

#### 1.1 HARVEST sidecar schema extension (`$schema_version: 2`)

Current `cycle-outcome.json` (schema v1):

```jsonc
{
  "$schema_version": 1,
  "cycle_id": "cycle-088",
  "review_verdict": "APPROVED",
  "audit_verdict": "APPROVED",
  "findings": { "blocker": 0, "high": 2, "medium": 5, "low": 3 },
  "artifacts": { "reviewer_md": "...", "auditor_md": "...", "pr_url": "..." },
  "flatline_signature": "...",
  "content_hash": "sha256:...",
  "elapsed_sec": 3421,
  "exit_status": "success"
}
```

Proposed schema v2 adds two optional fields:

```jsonc
{
  "$schema_version": 2,
  "cycle_id": "cycle-088",
  // ... all v1 fields unchanged ...

  "pull_threads": [
    {
      "id": "pt-001",
      "source": "review|audit|flatline|bridgebuilder|operator",
      "question": "string (50-500 chars)",
      "severity": "blocking|high|medium|low|curiosity",
      "cite": "file:line or artifact reference"
    }
  ],

  "emergence": [
    {
      "id": "em-001",
      "source": "review|audit|flatline|bridgebuilder",
      "pattern": "string (50-500 chars) — the unexpected thing",
      "adjacent_to": "string (what problem this is near)",
      "confidence": "speculative|observed|confirmed"
    }
  ]
}
```

Both arrays may be empty. Consumers MUST tolerate missing fields (schema v1 compat).

#### 1.2 Pull-thread + emergence source attribution

Three fields populate automatically at HARVEST time; all via existing infrastructure:

| Source | Signal | Extraction |
|--------|--------|------------|
| **review** | reviewer.md has sections like `## Open Questions` or lines starting with `? ` | Regex scan |
| **audit** | auditor-sprint-feedback.md `DEFERRED` rows | Existing parser extracts already |
| **flatline** | DISPUTED findings that didn't reach consensus | Read `flatline-*.json`, filter consensus !== HIGH_CONSENSUS |
| **bridgebuilder** | `SPECULATION` or `VISION` severity findings | Already classified by `post-pr-triage.sh` |
| **operator** | Operator CAN append `pull_threads` to the sidecar post-hoc via `spiral-harvest-adapter.sh --append-thread` | New CLI flag |

Emergence is narrower — only surfaces when the REVIEW or AUDIT agent explicitly uses a `**Emergence**:` or `**Unexpected**:` markdown label, OR when Bridgebuilder tagged `teachable_moment` on a finding. Conservative default: empty unless agents opt in.

#### 1.3 EVALUATE phase writes `seed-draft.md`

New function `_emit_seed_draft(cycle_dir)` in `spiral-harness.sh` (or a new `spiral-seed-drafter.sh` if scope grows):

```bash
_emit_seed_draft() {
    local cycle_dir="$1"
    local sidecar="$cycle_dir/cycle-outcome.json"

    # Feature gate
    local enabled
    enabled=$(_read_harness_config "spiral.seed.auto_draft" "false")
    [[ "$enabled" != "true" ]] && return 0

    [[ ! -f "$sidecar" ]] && return 0

    # Compose seed-draft.md via templated jq query over the sidecar
    local draft_path="$cycle_dir/seed-draft.md"
    _render_seed_draft "$sidecar" > "$draft_path"
    log "SEED draft written: $draft_path (editable — operator may accept or revise)"
}
```

Template (markdown with jq-produced bullets):

```markdown
# SEED draft — <cycle_id+1>

> Auto-drafted from cycle-<cycle_id> HARVEST output.
> Edit freely. Operator-authored sections override auto-drafted ones.

## Context from prior cycle

- Prior cycle: <cycle_id>, verdict: <review_verdict>/<audit_verdict>
- Elapsed: <elapsed_sec>s, findings: <blocker>B/<high>H/<medium>M/<low>L

## Open threads (from review + audit)

<!-- BEGIN_PULL_THREADS -->
<for each pull_thread:>
- **[<severity>]** <question>
  - Source: <source>, cite: `<cite>`
</for>
<!-- END_PULL_THREADS -->

## Emergence observed

<!-- BEGIN_EMERGENCE -->
<for each emergence:>
- **<pattern>** (adjacent to <adjacent_to>; confidence: <confidence>)
  - Source: <source>
</for>
<!-- END_EMERGENCE -->

## Proposed cycle-<cycle_id+1> intent

<!-- OPERATOR: replace this section with your authored intent, or accept the scaffold below -->

_Auto-scaffold: address blocking pull-threads (<count>) while observing emergence (<count>) for follow-up investigation._

---

## Provenance

- Source sidecar: `<sidecar_path>`
- Schema version: <schema_version>
- Drafted at: <ISO-8601>
```

#### 1.4 Next-cycle dispatch reads the draft

`spiral-orchestrator.sh cmd_start` accepts a new flag:

```bash
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md
```

When present, the harness uses the draft as `SEED_CONTEXT` (standard precedent). The operator can:
- `--seed-from-draft <path>` — explicit acceptance
- `--seed-from-draft <path> --edit` — opens `$EDITOR` for review-and-edit before dispatch
- No flag — existing behavior (operator hand-composes the task argument or uses their own SEED)

Operator role: **editor, not author**. They review the draft's `## Proposed cycle-NNN intent` section, edit if needed, dispatch.

#### 1.5 Vision-registry integration

If the vision registry has entries tagged with `[ACTIONABLE]` and created during cycle-N, the EVALUATE phase optionally includes them in the draft's `## Emergence observed` section. This closes one loop that was called out in #575:

> *"The vision registry captures speculative insights but none have ever been explored."*

Now auto-drafted SEEDs naturally surface actionable visions as emergence for next cycle's consideration.

Feature gate: `spiral.seed.include_visions: true` (distinct from `auto_draft`). Default off initially.

#### 1.6 Anti-rubber-stamp: mandatory operator intent (addresses Flatline B1)

**Flatline round 1 finding (100% model consensus)**: Auto-drafting creates a rubber-stamp dynamic. If the entire SEED is scaffolded, operator attention degrades; scaffolding errors compound across cycles because no human speed bump catches them.

**Mitigation**: make operator attention **mandatory, not optional**. Split the SEED into two sections — one auto-drafted (scaffolded context + threads + emergence) and one operator-required (cycle intent statement). The harness refuses to dispatch a draft where the operator-required section is empty or unchanged from placeholder.

Template v2:

```markdown
## Proposed cycle-<N+1> intent

<!-- OPERATOR-REQUIRED: replace the placeholder below with a ≥ 1-sentence
     intent statement. Dispatch will refuse to proceed until this section
     is edited (hash of this section must differ from the placeholder hash
     that shipped with the template). -->

_(placeholder — replace me)_
```

Dispatch logic (`spiral-orchestrator.sh cmd_start`) checks that the intent section SHA256 does not equal the known placeholder SHA256. Mismatch → dispatch. Match → refuse with:

> `ERROR: cycle-<N+1> intent section still holds the placeholder. Edit seed-draft.md and write what you actually want this cycle to do (one sentence minimum).`

**Diff confirmation**: when `--edit` is used, the flight-recorder records the unified diff between the scaffold and the operator's edits. This makes "how much did the operator actually engage with the draft" observable — and, critically, retrospectively auditable. If several consecutive cycles show minimal edits (< 2 lines), the system emits an advisory warning: "auto-draft may not be serving you; consider disabling or re-authoring intent from scratch."

#### 1.7 Lineage binding to prevent stale draft replay (addresses Flatline B5)

**Flatline round 1 finding**: `--seed-from-draft <path>` accepts any draft without verifying it came from the most recent cycle, risking stale replay.

**Mitigation**: cryptographic lineage binding in `seed-draft.md` frontmatter.

```markdown
---
source_cycle: cycle-088
target_cycle: cycle-089
drafted_at: 2026-04-19T15:22:31Z
source_sidecar_hash: sha256:abc123...
draft_content_hash: sha256:def456...
---
# SEED draft — cycle-089
...
```

`cmd_start --seed-from-draft <path>` validates:
1. `target_cycle` matches the computed next-cycle ID (from ledger + current state)
2. `source_sidecar_hash` matches the actual sidecar file hash at `<source_cycle_dir>/cycle-outcome.json`
3. `draft_content_hash` matches SHA256 of the draft body (everything after the frontmatter close)
4. `drafted_at` is not older than N days (config: `spiral.seed.draft_max_age_days`, default 7)

Any mismatch → refuse with specific reason:
```
ERROR: --seed-from-draft rejected: source_sidecar_hash mismatch
  Expected: sha256:abc123... (current cycle-outcome.json)
  Got:      sha256:xyz789... (from draft frontmatter)
This usually means the source cycle's outputs were modified after the draft
was written. Regenerate the draft with: /spiral --redraft-seed cycle-088
```

Override: `--force-stale-draft` flag bypasses validation (logged in trajectory with `override_reason` field; operator expected to provide via CLI: `--force-stale-draft --reason "re-running with patched outputs"`).

#### 1.8 Sanitization for injected HARVEST content (addresses Flatline B6)

**Flatline round 1 finding**: HARVEST output (reviewer.md, audit-sprint-feedback.md, flatline findings) becomes next-cycle LLM input. These documents contain content from prior LLM runs that, in an adversarial scenario, could contain instruction-like text that the next cycle's discovery phase interprets as instructions rather than as data.

**Mitigation**: explicit sanitizer pass before inclusion in `seed-draft.md` or `SEED_CONTEXT`.

Sanitizer transforms (in order):

1. **Strip HTML/XML directive patterns**: `<script>`, `<style>`, `<!-- INSTRUCT:`, `<!-- SYSTEM:`, `<meta>`, `<iframe>`, and similar.
2. **Strip agent-like directives**: lines matching `^(SYSTEM|USER|ASSISTANT|INSTRUCTION): ` (case-insensitive) → prefixed with literal `> QUARANTINED:`.
3. **Strip prompt-injection tell patterns**: `ignore previous instructions`, `disregard the above`, `you are now`, → replaced with `[redacted]`.
4. **Cap content per field**: existing 2000-char cap on pull-thread question + emergence pattern retained; enforce new 500-char cap per `cite` field.
5. **Markdown-escape `cite` fields**: backticks around to prevent cite strings from becoming executable blocks.
6. **Attribute source with provenance**: each injected block ends with footer `Source: <artifact_path>, sanitizer: v1, sanitized_at: <ISO-8601>`.

High-risk surface escalation: if the sanitizer detects a pattern that matched any directive (step 1-3), the draft frontmatter gains `sanitizer_flags: ["quarantined_directive_found"]` and the harness requires an explicit `--i-have-reviewed-draft` flag at dispatch. This forces a human to visually inspect the draft before dispatch when suspicious content was sanitized.

Sanitizer lives in `.claude/scripts/spiral-seed-sanitizer.sh` and is unit-testable standalone. Feature cannot be disabled (no escape hatch for sanitization) — this is a **defense-in-depth primitive**, not a configurable policy.

#### 1.9 Signed lineage metadata (addresses Flatline R2-B3)

**Flatline round 2 finding**: §1.7's hashes prove integrity (the draft wasn't modified) but not authenticity (the draft wasn't forged). An operator running two spirals concurrently, or a malicious actor with write access to `.run/`, could construct a valid-hash draft that references a different cycle's outputs.

**Mitigation**: HMAC-signed metadata in frontmatter using a runtime-controlled key.

Runtime signing key:
- Path: `.run/.spiral-signing-key` (permission `600`, gitignored)
- Generated on first `/spiral --start` if missing: 32 bytes from `/dev/urandom`
- Rotated on operator request via `/spiral --rotate-signing-key`
- Never committed to git; never shared across machines (each operator's spirals are self-authenticated)

Extended frontmatter:

```yaml
---
source_cycle: cycle-088
target_cycle: cycle-089
drafted_at: 2026-04-19T15:22:31Z
source_sidecar_hash: sha256:abc123...
draft_content_hash: sha256:def456...
signature: hmac-sha256:789...     # HMAC of the concatenated fields above
signature_key_id: spiral-key-2026-04-19
---
```

Signature formula:

```
msg = source_cycle + "\n" + target_cycle + "\n" + drafted_at + "\n"
    + source_sidecar_hash + "\n" + draft_content_hash
signature = HMAC-SHA256(runtime_key, msg)
```

Validation at `--seed-from-draft` (in addition to the §1.7 checks):
1. Signing key file exists + readable → else reject (operator must be owner of this machine's spirals)
2. Recompute HMAC from frontmatter fields; must match `signature`
3. `signature_key_id` logged but not enforced for rotation (future refinement)

Key rotation:
- `/spiral --rotate-signing-key` generates a new key, archives the old one to `.run/.spiral-signing-key.rotated-<ISO-8601>`
- Drafts signed with old keys remain valid for `spiral.seed.signature_grace_period_days` (default 7 days)
- After grace period, old-key drafts require `--force-stale-draft`

Threat model note: this is HMAC (symmetric), not asymmetric signing. Adequate for single-operator trust model (the key is the operator). A future multi-operator team mode would upgrade to asymmetric signing with shared public keys; out of scope for this RFC.

#### 1.10 Sanitizer hardening: structured parsing + Unicode + adversarial corpus (addresses Flatline R2-B5)

**Flatline round 2 finding**: §1.8's regex-based sanitizer is demonstrably bypassable by Unicode obfuscation (e.g., Fullwidth Latin characters, zero-width joiners), indirect injection (`"Write the string 'ignore previous instructions'"` embedded in plausibly-legitimate content), or markdown-tag abuse the regex doesn't cover.

**Mitigation**: three-layer hardening.

**Layer 1 — Unicode normalization (NFKC) before any regex**:

```python
# Pseudocode; actual implementation in bash shells out to python or uses jq's NFKC support
normalized = unicodedata.normalize('NFKC', raw)
# Also: strip zero-width chars, BOMs, direction-override codepoints
normalized = re.sub(r'[\u200B-\u200F\u202A-\u202E\uFEFF]', '', normalized)
```

This collapses Unicode homoglyphs + bidirectional overrides into their canonical ASCII equivalents before pattern matching runs. `ＳＹＳＴＥＭ:` (fullwidth) becomes `SYSTEM:` and is then caught by existing regex.

**Layer 2 — Structured parsing (allowlist, not denylist)**:

Rather than stripping known-bad patterns, parse the source markdown into a structured AST and re-render using only allowlisted constructs:

| Allowed | Disallowed |
|---------|-----------|
| Plain text (normalized) | HTML tags of any kind |
| Code fences (triple backtick) | Raw HTML directives (`<!--`, `<script>`, etc.) |
| Lists (ordered/unordered, 1-level) | Nested markdown with directive-like prefixes |
| Links with literal URLs | Links with `javascript:` / `data:` schemes |
| Emphasis (* and _) | Anchor tags |
| Inline code (single backtick) | Autolinks (`<https://...>`) |

Renderer re-serializes the AST into clean markdown. Anything outside the allowlist is either escaped (literal backticks) or dropped (with a `sanitizer_dropped: ...` flag in the draft frontmatter).

**Layer 3 — Adversarial test corpus**:

Ship `.claude/data/spiral-sanitizer-adversarial-corpus.jsonl` with documented bypass attempts as test fixtures:

```jsonc
{"id": "bypass-001", "category": "unicode-homoglyph", "input": "ＩＧＮＯＲＥ previous", "expected_quarantine": true}
{"id": "bypass-002", "category": "zero-width-join", "input": "sys\u200Btem: echo", "expected_quarantine": true}
{"id": "bypass-003", "category": "indirect-injection", "input": "Consider the string 'disregard all prior instructions'. Does it apply here?", "expected_quarantine": true}
{"id": "bypass-004", "category": "markdown-html-hybrid", "input": "- [x] normal\n- <!-- INSTRUCT:...-->", "expected_quarantine": true}
```

CI step runs the sanitizer against every corpus entry; any entry with `expected_quarantine: true` that passes unredacted → test fails.

**Sunset the regex-only default**: v3 makes the sanitizer opt-in for a grace period. The config field becomes `spiral.seed.sanitizer_mode`:
- `strict` (default after grace): all 3 layers active; any bypass of the corpus fails CI
- `v1-regex` (deprecated): legacy regex-only path for operators mid-migration; emits deprecation warning
- `none`: disables sanitization entirely (hard-deprecated; only for testing)

### Part 2 — Failure-Typed Bead Escalation (#575 item 4)

#### 2.1 Circuit-breaker → bead creation

`spiral-harness.sh _run_gate` currently logs `_record_failure "$gate_name" "CIRCUIT_BREAKER" "Failed after $MAX_RETRIES attempts"` and exits. Extend this path:

```bash
_handle_circuit_break() {
    local gate_name="$1"
    local classification="$2"  # scope-mismatch | cwd-mismatch | review-fix-exhausted | budget-exhausted | flatline-stuck | other
    local detail="$3"

    # Existing flight-recorder action (kept)
    _record_failure "$gate_name" "CIRCUIT_BREAKER" "$detail"

    # New: create typed bead if beads available + enabled
    local enabled
    enabled=$(_read_harness_config "spiral.failure_beads.enabled" "false")
    [[ "$enabled" != "true" ]] && return 0

    if command -v br &>/dev/null; then
        _create_failure_bead "$gate_name" "$classification" "$detail"
    else
        log "WARN: beads not available; failure not persisted as a dependency"
    fi
}

_create_failure_bead() {
    local gate_name="$1"
    local classification="$2"
    local detail="$3"

    local title="Spiral circuit break: $gate_name ($classification)"
    local body
    body=$(cat <<EOF
**Gate**: $gate_name
**Classification**: $classification
**Detail**: $detail
**Cycle**: $CYCLE_ID
**Flight recorder**: $CYCLE_DIR/flight-recorder.jsonl

This bead was auto-created by /spiral on circuit break. It MUST be resolved
or explicitly deferred before the next spiral dispatch.

## Resolution options

1. **Fix**: investigate + patch the root cause, then \`br close <id>\`
2. **Defer with rationale**: \`br update <id> --label spiral:deferred\` +
   comment explaining why this is safe to defer
EOF
)

    br create --type bug \
        --title "$title" \
        --priority high \
        --label "spiral:circuit-break,spiral:$classification" \
        --description "$body"
}
```

#### 2.2 Classification taxonomy

The classification field is a controlled vocabulary (extensible but stable):

| Classification | Trigger | Resolution pattern |
|---------------|---------|-------------------|
| `scope-mismatch` | REVIEW verdict `CHANGES_REQUIRED` persists >= MAX_RETRIES on scope-level critique (not implementation defect) | Split cycle into smaller scope OR escalate to RFC |
| `cwd-mismatch` | `_pre_check_seed` fails (from RFC-062 part 0) | Rerun from correct CWD |
| `review-fix-exhausted` | `_review_fix_loop` hits `REVIEW_MAX_ITERATIONS` without APPROVED | Manual code intervention OR scope-split |
| `budget-exhausted` | `cost_budget_exhausted` fires before phase completion | Increase budget OR reduce scope |
| `flatline-stuck` | Flatline DISPUTED findings don't resolve across iterations | Operator acceptance of disputed state OR RFC for structural fix |
| `other` | Catchall for circuit breaks that don't match above | Investigate, then retroactively add classification |

The controlled vocabulary lives in `.claude/data/spiral-failure-classifications.yaml` with a regex pattern per class used by `_classify_failure()` to auto-populate from flight-recorder verdict text.

#### 2.3 Dispatch-time gate

New `_pre_dispatch_failure_check()` function called at spiral `cmd_start`:

```bash
_pre_dispatch_failure_check() {
    # Feature gate
    local enabled
    enabled=$(_read_harness_config "spiral.failure_beads.enforce_on_dispatch" "false")
    [[ "$enabled" != "true" ]] && return 0

    # Escape hatch
    [[ "${SPIRAL_SKIP_FAILURE_DEPS:-false}" == "true" ]] && {
        log "SPIRAL_SKIP_FAILURE_DEPS=true — skipping failure-bead check (recorded in trajectory)"
        _record_action "DISPATCH" "spiral-orchestrator" "skip_failure_deps" "" "" "" 0 0 0 "operator_override"
        return 0
    }

    # Check for unresolved failure beads
    local unresolved
    if ! command -v br &>/dev/null; then
        log "WARN: beads not installed; cannot enforce failure dependencies (install with: cargo install beads_rust)"
        return 0
    fi

    unresolved=$(br list --label spiral:circuit-break --status "open,in-progress" --json 2>/dev/null || echo "[]")
    local count
    count=$(echo "$unresolved" | jq 'length')

    if [[ "$count" -gt 0 ]]; then
        error "Cannot start spiral: $count unresolved failure bead(s) from prior cycles"
        error ""
        echo "$unresolved" | jq -r '.[] | "  - \(.id) [\(.labels | join(","))]: \(.title)"' >&2
        error ""
        error "Resolution options:"
        error "  1. Fix each: investigate + \`br close <id>\`"
        error "  2. Defer: \`br update <id> --label spiral:deferred\` with rationale comment"
        error "  3. Operator override: SPIRAL_SKIP_FAILURE_DEPS=true (logged in trajectory)"
        return 1
    fi
    return 0
}
```

#### 2.4 Resolution semantics

A failure bead is considered "resolved" if any of:

1. **Closed** (`br close <id>`) — default expectation for fix path
2. **Labeled `spiral:deferred`** (`br update <id> --label spiral:deferred`) — explicit defer with operator-authored comment explaining why

A bead with `spiral:circuit-break` label but no resolution disposition is considered **blocking**.

#### 2.5 Trajectory + observability

All failure-bead interactions emit flight-recorder entries:

- `FAILURE_BEAD_CREATED` — when `_create_failure_bead` fires, records bead ID + classification
- `FAILURE_BEAD_GATE_CHECK` — when `_pre_dispatch_failure_check` runs, records check outcome (PASS / BLOCKED / OVERRIDE)

These surface in the #569 dashboard (`dashboard.jsonl` + `dashboard-latest.json`) under a new top-level `failure_beads` key:

```jsonc
{
  "totals": {
    "actions": 47,
    // ... existing fields ...
    "failure_beads_created": 1,
    "failure_beads_pending": 0
  }
}
```

Adds two integer fields to the existing `_emit_dashboard_snapshot` aggregator. Zero risk to existing consumers (additive only).

#### 2.6 Strict-mode enforcement when beads unavailable (addresses Flatline B2)

**Flatline round 1 finding**: The dispatch gate depends on `br` CLI. If beads isn't installed, the gate silently no-ops — contradicting "hard dependency" semantics. Operators who believe the gate is protecting them aren't.

**Mitigation**: three-mode enforcement config with explicit prerequisite check.

```yaml
spiral:
  failure_beads:
    # Gate semantics when beads is unavailable:
    #   off     — feature disabled entirely; no bead creation, no gating
    #   warn    — best-effort; warns on missing beads but proceeds (current default)
    #   strict  — beads MUST be available for dispatch; gate hard-fails if missing
    enforce_on_dispatch: warn
```

Startup prerequisite check runs at `cmd_start`:

```bash
_check_failure_beads_prerequisite() {
    local mode
    mode=$(_read_harness_config "spiral.failure_beads.enforce_on_dispatch" "warn")

    case "$mode" in
        off)
            return 0  # Not enforcing; no prerequisite
            ;;
        warn)
            if ! command -v br &>/dev/null; then
                log "WARN: spiral.failure_beads.enforce_on_dispatch=warn but beads CLI not found"
                log "WARN: failures will not be recorded as dependencies"
                log "WARN: install: cargo install beads_rust; configure: spiral.failure_beads.enforce_on_dispatch=off"
            fi
            return 0  # warn allows missing beads
            ;;
        strict)
            if ! command -v br &>/dev/null; then
                error "spiral.failure_beads.enforce_on_dispatch=strict but beads CLI not found"
                error "strict mode requires beads. Options:"
                error "  1. Install beads: cargo install beads_rust"
                error "  2. Downgrade to warn: spiral.failure_beads.enforce_on_dispatch=warn"
                error "  3. Disable feature: spiral.failure_beads.enforce_on_dispatch=off"
                return 1  # strict fails closed
            fi
            # Also verify br health
            if ! br health --json 2>&1 | jq -e '.status == "HEALTHY"' >/dev/null; then
                error "strict mode requires healthy beads; current status: $(br health 2>&1 | head -1)"
                return 1
            fi
            return 0
            ;;
        *)
            error "Invalid spiral.failure_beads.enforce_on_dispatch mode: $mode (expected: off|warn|strict)"
            return 1
            ;;
    esac
}
```

Default mode stays `warn` (matches current no-op-when-unavailable behavior, preserving backcompat). Operators who want hard guarantees explicitly opt into `strict`.

#### 2.7 Atomic failure journal with idempotency (addresses Flatline B3)

**Flatline round 1 finding**: `_create_failure_bead` uses two sequential operations — `_record_failure` (flight-recorder) and `br create` (beads DB). If the first succeeds and the second fails (network, SIGINT, crash), the spiral has a recorded failure that the gate won't detect, silently breaking the dependency chain.

**Mitigation**: append-only journal + idempotency key + reconciliation on startup.

```
.run/spiral-failure-journal.jsonl
```

Each circuit break writes an ENTRY in this order:

1. **Pre-escalation entry** (BEFORE calling `br create`):
   ```jsonc
   {"seq": 42, "ts": "...", "cycle_id": "cycle-088", "idempotency_key": "cycle-088:REVIEW_FIX_LOOP:1", "phase": "PENDING", "classification": "review-fix-exhausted", "detail": "..."}
   ```
2. **Post-escalation entry** (AFTER bead created, with bead ID captured):
   ```jsonc
   {"seq": 43, "ts": "...", "idempotency_key": "cycle-088:REVIEW_FIX_LOOP:1", "phase": "ESCALATED", "bead_id": "bug-042"}
   ```
   Or on failure:
   ```jsonc
   {"seq": 43, "ts": "...", "idempotency_key": "cycle-088:REVIEW_FIX_LOOP:1", "phase": "ESCALATION_FAILED", "error": "br create exited 1: network error"}
   ```

Idempotency key format: `<cycle_id>:<gate_name>:<attempt_number>`. Attempt number is the sequence within the cycle (a cycle can have multiple circuit breaks at different gates).

**Reconciliation on startup** (runs in `cmd_start` before dispatch gate):

1. Scan `spiral-failure-journal.jsonl` for entries with `phase: PENDING` that have no matching `ESCALATED` or `ESCALATION_FAILED` entry with the same `idempotency_key`.
2. For each pending entry: attempt to re-create the bead (beads has its own de-dup by `external_ref` — idempotent retry safe).
3. Write `ESCALATED` (or `ESCALATION_FAILED`) follow-up entry.
4. If reconciliation fails after 3 attempts, write `ESCALATION_ABANDONED` and emit a loud warning visible to operator — but do NOT block dispatch (operator can intervene manually).

This gives the transaction semantics Flatline demanded without requiring a transactional DB. The journal is the SoT; beads is a downstream consumer. If beads and journal disagree, journal wins and beads gets reconciled.

#### 2.8 Scope-aware gating (addresses Flatline B4)

**Flatline round 1 finding**: global blocking (all unresolved failure beads block all dispatches across all scopes) creates false blockers and workflow deadlocks. Operator running a spiral on a different project can't dispatch because of failures from an unrelated project.

**Mitigation**: scope metadata on beads + scope-aware gate check.

At bead creation, label with scope:

```bash
br create ... \
  --label "spiral:circuit-break,spiral:$classification,spiral:scope:$REPO:$BRANCH"
```

Scope format: `<repo>:<branch>` (for MVP). Future extension: `<repo>:<branch>:<component>` for finer granularity.

At dispatch gate, filter to current scope:

```bash
local current_scope
current_scope=$(_compute_current_scope)  # e.g., "0xHoneyJar/loa:main"

unresolved=$(br list \
    --label spiral:circuit-break \
    --label "spiral:scope:$current_scope" \
    --status "open,in-progress" \
    --json 2>/dev/null)
```

Operator can configure the scope hierarchy:

```yaml
spiral:
  failure_beads:
    scope_strictness: exact       # exact | repo | project
```

- `exact` — block only on `<repo>:<branch>` match (recommended default)
- `repo` — block on any failure from the same repo (stricter)
- `project` — block on any failure (blanket — preserves original design, backcompat)

**OQ-5 resolution** (updated from draft v1): the `exact` mode is the new recommendation. `project` mode (blanket block) remains available for operators who want the stricter safety contract.

#### 2.9 Trajectory + observability (continued from 2.5)

In addition to the FAILURE_BEAD_CREATED / FAILURE_BEAD_GATE_CHECK actions (§2.5), the journal-based reconciliation emits:

- `FAILURE_JOURNAL_RECONCILE_START` — reconciliation loop begins at cmd_start
- `FAILURE_JOURNAL_RECONCILE_RESULT` — per-idempotency-key outcome: RECONCILED | ABANDONED | ALREADY_ESCALATED
- `FAILURE_JOURNAL_CORRUPTED` — journal has unparseable lines (rare; operator intervention needed)

#### 2.10 Defer-TTL + rationale schema + revalidation (addresses Flatline R2-B1)

**Flatline round 2 finding**: `spiral:deferred` label is too easy to game. Operator defers a failure bead "temporarily", the bead persists forever, the system loses the invariant that failures must be acknowledged. In the limit, every deferred bead becomes a permanent hole in the "membrane-repair" promise.

**Mitigation**: three controls.

**A — Structured rationale schema**:

`spiral:deferred` label alone is insufficient; mandate a structured comment:

```yaml
# Parsed from first `br comments add` after the defer label
defer_reason: "cycle-088 was for feature X; this blocker is from an unrelated experimental branch that we're abandoning"
defer_until: 2026-05-01        # required ISO-8601 date OR literal "indefinite"
defer_scope: "this-cycle"      # this-cycle | this-branch | this-project | permanent
reviewed_by: operator-ref      # free text (e.g., "jani", "SlackHuddle2026-04-19")
```

Enforced via `spiral-failure-bead-validator.sh` which:
- Runs at `cmd_start` gate-check time
- Parses all `spiral:deferred`-labeled beads
- Rejects beads whose defer comments don't parse or lack required fields
- Error message: `"Bead bug-042 has spiral:deferred label but rationale comment is malformed/missing. Run: br comments edit <id> --format rationale"`

**B — TTL enforcement**:

- `defer_until` ISO-8601 → at gate time, if `now() > defer_until`, bead is **re-promoted to blocking** with comment: `"Defer expired; operator must re-defer with updated rationale or close."`
- `defer_until: indefinite` → allowed but logged as `indefinite_defer` in trajectory; weekly advisory on dashboard: "N beads have indefinite defers; consider review"

**C — Periodic revalidation**:

Every 30 days (configurable: `spiral.failure_beads.revalidation_period_days`), the dashboard emits a summary of all deferred beads with ages + `defer_scope`. This surfaces drift without blocking any workflow; operator can bulk-close or re-defer as needed.

#### 2.11 Startup enforcement banner + default-strict for new installs (addresses Flatline R2-B2)

**Flatline round 2 finding**: §2.6's 3-mode config (off/warn/strict) leaves `warn` as default, preserving backcompat but undermining the "hard dependency" framing. If 95% of operators never flip the switch to strict, the feature is marketing not reality.

**Mitigation**: explicit banner + new-install default shift + installer prompt.

**Startup banner** (runs on every `cmd_start`):

```
╔══════════════════════════════════════════════════════════════════════╗
║ Spiral failure dependencies: <MODE>                                  ║
║   Mode: strict | warn | off                                          ║
║   Beads: <HEALTHY | UNAVAILABLE>                                     ║
║   Unresolved blockers: <N>                                           ║
║                                                                      ║
║ Strict mode hard-fails dispatch if any spiral:circuit-break          ║
║ beads are unresolved. Run `/spiral --failure-beads-help` for details ║
╚══════════════════════════════════════════════════════════════════════╝
```

Makes the mode visible at the moment the operator is about to dispatch. Removes the "I didn't realize warn mode does nothing when beads is missing" surprise.

**New-install default**:

- `loa-setup` wizard (new installs) prompts: "Enable failure-dependency gating? (recommended: yes)" with options:
  - Yes → `enforce_on_dispatch: strict` + install beads if missing
  - Soft (default) → `enforce_on_dispatch: warn`
  - Off → `enforce_on_dispatch: off` (documented downside)
- `update-loa.sh` for existing installs: do NOT change existing operator configs; respect current setting.

**Config validation**:

On `cmd_start`, if `enforce_on_dispatch: strict` but beads is unhealthy, emit:

```
ERROR: Configuration inconsistency:
  spiral.failure_beads.enforce_on_dispatch = strict
  beads CLI = <UNAVAILABLE | UNHEALTHY>

strict mode requires beads. Resolve by:
  1. Install/fix beads: cargo install beads_rust && br init
  2. Downgrade to warn: yq '.spiral.failure_beads.enforce_on_dispatch = "warn"' -i .loa.config.yaml
  3. Disable feature:  yq '.spiral.failure_beads.enforce_on_dispatch = "off"'  -i .loa.config.yaml

Dispatch refused.
```

#### 2.12 Strict mode blocks PENDING / FAILED / ABANDONED (addresses Flatline R2-B4)

**Flatline round 2 finding**: §2.7's reconciliation loop allows `ESCALATION_ABANDONED` entries to proceed with just a "loud warning". In strict mode, this is the wrong default — an abandoned escalation is indistinguishable from an unrecorded failure.

**Mitigation**: strict mode treats `PENDING`, `ESCALATION_FAILED`, and `ESCALATION_ABANDONED` as blocking states until manually cleared.

Updated `_pre_dispatch_failure_check` logic:

```bash
_pre_dispatch_failure_check() {
    local mode
    mode=$(_read_harness_config "spiral.failure_beads.enforce_on_dispatch" "warn")

    [[ "$mode" == "off" ]] && return 0

    # ... existing beads check ...

    # NEW: journal-state check (strict mode only)
    if [[ "$mode" == "strict" ]]; then
        local pending_count failed_count abandoned_count
        pending_count=$(_count_journal_entries PENDING)
        failed_count=$(_count_journal_entries ESCALATION_FAILED)
        abandoned_count=$(_count_journal_entries ESCALATION_ABANDONED)

        local blocking=$((pending_count + failed_count + abandoned_count))
        if [[ "$blocking" -gt 0 ]]; then
            error "Cannot dispatch: strict mode has $blocking unresolved journal entries"
            error "  PENDING: $pending_count  ESCALATION_FAILED: $failed_count  ABANDONED: $abandoned_count"
            error ""
            error "Resolution:"
            error "  1. Run reconciliation manually: /spiral --reconcile-failure-journal"
            error "  2. Mark abandoned entries handled: /spiral --clear-journal-entry <idempotency_key>"
            error "  3. Downgrade to warn: yq '.spiral.failure_beads.enforce_on_dispatch = \"warn\"' -i .loa.config.yaml"
            return 1
        fi
    fi

    return 0
}
```

`--clear-journal-entry <idempotency_key>` requires `--reason "<operator rationale>"` and appends a `CLEARED` entry to the journal with the operator's reason. This preserves audit trail while giving strict mode an explicit escape hatch.

---

## Interactions + Dependencies

### Schema compatibility

- HARVEST sidecar schema v1 consumers MUST be tolerant of v2 (missing fields). Current consumers:
  - `spiral-orchestrator.sh EVALUATE phase` — already tolerant (uses `jq -r '... // null'`)
  - `post-merge-orchestrator.sh` — reads findings only, unaffected
  - `bridge-orchestrator.sh` — doesn't read the sidecar directly

- `validate_sidecar_schema` function in `spiral-harvest-adapter.sh` MUST be updated to accept both version 1 and version 2 without version-mismatch error.

### Beads integration

- Depends on beads-first architecture (v1.29.0+). If beads not installed, failure-bead features degrade gracefully (warnings; no hard block).
- Failure-bead labels use the `spiral:` namespace per existing beads label convention (e.g., `spiral:circuit-break`, `spiral:scope-mismatch`).
- New beads view: `br list --label spiral:circuit-break` surfaces all spiral-originated failures.

### CLI compatibility

- `spiral-orchestrator.sh --start` accepts new optional flag `--seed-from-draft <path>`. Existing invocations without the flag: unchanged behavior.
- `SPIRAL_SKIP_FAILURE_DEPS=true` env var is the escape hatch. Default: not set (respects failure gate).

---

## Migration + Backwards Compatibility

### Rollout phases

| Phase | Duration | What | Risk |
|-------|----------|------|------|
| **Phase 1 (shipping)** | 1 sprint | Schema v2 + extension writer/reader + feature gates (all default off) | Low — no behavior change until flags flip |
| **Phase 2 (dogfood)** | 2–4 cycles of operator use | Turn on `spiral.seed.auto_draft` in operator's own `.loa.config.yaml` | Medium — first observations of scaffolded SEED quality |
| **Phase 3 (optional default-on)** | Later cycle | Flip `auto_draft` default to `true` after dogfood validates | Medium — breaking UX change; gated by observation data |
| **Phase 4 (failure beads)** | Separate sprint | Ship failure-bead creation + dispatch gate (default off) | Low — opt-in |
| **Phase 5 (failure beads default-on)** | Later | Enable enforcement after dogfood | Medium — can block dispatches |

### Backwards compat invariants

1. Schema v1 sidecars MUST remain readable after v2 ships (current v1 format remains a valid v2 document with empty arrays).
2. `spiral-orchestrator.sh --start` without `--seed-from-draft` flag MUST work identically to today.
3. All new features are gated by config keys that default to false.
4. `validate_sidecar_schema` MUST accept both v1 and v2 sidecars (extend `SPIRAL_SUPPORTED_SCHEMA_VERSIONS` to `(1 2)`).

### Deprecation plan

None initially. Schema v1 remains supported indefinitely. If schema v3 is ever proposed, v1 deprecation would be a separate RFC with a minimum 6-month runway.

---

## Risks + Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|-----------|
| Scaffolded SEED has low quality (operator ignores it) | Medium | Low | Observability: track `seed_draft_used` vs `seed_draft_discarded` in flight-recorder. If ignore rate > 80% after 10 cycles, revisit extraction logic. |
| Operator over-trusts scaffolding ("looks plausible, dispatch it") | Low | High | `--edit` flag opens `$EDITOR`; trajectory records whether operator edited or dispatched as-is; HITL warning in draft preamble |
| Failure-bead gate produces false blockers (circuit break was transient, now fixed) | Medium | Medium | Explicit `spiral:deferred` label with rationale is always available; escape hatch via env var; beads remain mutable post-creation |
| Classification vocabulary drifts (too many `other`s) | Medium | Low | Quarterly audit: if > 30% of beads classified `other`, extend vocabulary. Controlled vocab lives in YAML so updates are low-friction. |
| Schema v2 breaks an unknown third-party consumer | Low | Medium | Schema v1 remains valid. Version validator permits both. Bump signaled in CHANGELOG with migration notes. |
| Beads not installed degrades feature silently | Medium | Low | Log warning on first use; don't block (degradation is the intent for non-beads environments) |
| Scaffolded SEED leaks sensitive content from prior cycle review | Low | Medium | Existing sanitizer runs on reviewer.md + auditor-sprint-feedback.md already; reuse that path. Pull threads cite file:line, not content body. |
| EDITOR flag dispatch behavior unclear on headless systems | Medium | Low | `--edit` returns error if `$EDITOR` unset; operator can always skip flag |

---

## Open Questions

These need operator decision before implementation:

### OQ-1 — Classification vocabulary ownership

Should the `spiral-failure-classifications.yaml` be framework-owned (System Zone) or user-extensible (State Zone)?

- **Framework-owned**: stable contract, requires PR to extend
- **User-extensible**: flexibility, risk of divergence across operators

**Recommendation**: framework-owned, with PR process for new classifications. Rationale: the classification taxonomy is load-bearing for dispatch-gate semantics; divergence defeats the purpose.

### OQ-2 — Draft lifetime

How long does `seed-draft.md` live before being stale?

- Option A: forever (operator manages lifecycle)
- Option B: auto-delete after next cycle starts
- Option C: explicit TTL config (e.g., 30 days)

**Recommendation**: Option A initially (conservative). Drafts live in `.run/cycles/cycle-NNN/` which is already operator-managed. If cleanup churn becomes a problem, add TTL as a follow-up.

### OQ-3 — Failure bead priority

Should all failure beads be `high` priority (current proposal), or should classification drive priority?

| Classification | Suggested priority |
|---------------|-------------------|
| `scope-mismatch` | critical |
| `cwd-mismatch` | high |
| `review-fix-exhausted` | high |
| `budget-exhausted` | medium |
| `flatline-stuck` | high |
| `other` | medium |

**Recommendation**: use classification-driven priority per above table. Mapping lives in the same YAML as the classification vocab.

### OQ-4 — Emergence field conservatism

Initial design is conservative (only populate `emergence` when agents explicitly tag). Should we also run heuristic extraction (e.g., scan for "surprisingly", "unexpectedly", "pattern we didn't anticipate")?

**Recommendation**: start conservative. Heuristic extraction risks false positives ("the reviewer wrote 'surprisingly clean code'" → emergence event). Wait for real operator feedback on whether explicit-tag coverage is sufficient.

### OQ-5 — Dispatch gate granularity

If cycle-088 trips a circuit break on `REVIEW_FIX_LOOP_EXHAUSTED`, and operator starts a NEW spiral (different scope, different cycle), should the failure bead still block?

- Option A: all unresolved beads block all dispatches (safe, possibly annoying)
- Option B: beads scope by project/repo and only block dispatches in that scope
- Option C: beads have explicit "blocks" metadata (which future cycles they apply to)

**Recommendation**: Option A initially. Option B requires scope inference that's likely error-prone. Operator can always defer-with-rationale if a blocker is from a genuinely unrelated prior cycle.

---

## Rollout Plan + Validation

### Sprint breakdown

**Sprint 1** (~5 tasks) — Schema v2 + auto-draft scaffolding
1. Extend `cycle-outcome.json` schema: add `pull_threads` + `emergence` arrays (empty by default)
2. Update `validate_sidecar_schema` to accept v1 and v2
3. Extract `pull_threads` from reviewer.md + audit-sprint-feedback.md + flatline findings
4. Add `_emit_seed_draft` function writing `seed-draft.md` at EVALUATE
5. BATS tests for schema extension + extraction logic

**Sprint 2** (~3 tasks) — Dispatch integration
1. Add `--seed-from-draft <path>` flag to `spiral-orchestrator.sh cmd_start`
2. Add `--edit` sub-flag that opens `$EDITOR`
3. BATS tests for dispatch integration

**Sprint 3** (~4 tasks) — Failure beads
1. Add `_create_failure_bead` + classification function
2. Ship `spiral-failure-classifications.yaml` (framework-owned)
3. Wire `_handle_circuit_break` into existing `_run_gate` failure path
4. BATS tests

**Sprint 4** (~3 tasks) — Dispatch gate
1. Add `_pre_dispatch_failure_check` to `spiral-orchestrator.sh cmd_start`
2. Add dashboard `failure_beads_created` + `failure_beads_pending` metrics
3. BATS tests + integration test with mock beads

**Sprint 5** (~2 tasks) — Docs + rollout
1. CHANGELOG entry + README update
2. Skill doc updates in `spiraling/SKILL.md`

### Validation criteria

- **Schema backcompat**: all existing spiral BATS tests continue to pass after schema v2 ships (zero regression requirement).
- **Auto-draft correctness**: on 3 dogfood cycles, seed-draft.md surfaces ≥ 80% of the pull-threads a human operator would identify from the same source material.
- **Failure-bead gate safety**: in 10 consecutive dispatch attempts against a fixed state, gate produces identical decisions (deterministic).
- **Escape hatch works**: `SPIRAL_SKIP_FAILURE_DEPS=true` allows dispatch and records the override in trajectory.
- **No regression**: `bats tests/unit/spiral-*.bats` at ≥ 210 passing (current: 223).

### Observation plan

After Phase 2 dogfood:
- Count: % of cycles where operator accepted draft as-is vs edited vs discarded
- Quality: any drafted SEED that led to a circuit break in cycle-N+1 (signal of poor scaffolding)
- UX: time between `seed-draft.md` written and `--start` dispatched (proxy for operator comfort)

---

## Out of Scope

These are mentioned in #575 but deliberately excluded from this RFC:

- **K-hole's `--trail` mechanism itself** — referenced as architectural precedent only. Lives in `construct-k-hole`.
- **Cognition-layer persona** (from #310) — separate construct-level work.
- **Taste loop** (from #310) — requires construct-level integration.
- **Agent team persona inheritance** — distinct concern.
- **Heuristic emergence extraction** — conservative initial design; revisit based on operator feedback (OQ-4).

---

## Alternatives Considered

### Alt-1 — Keep SEED hand-authored, add a "suggestions" CLI

**Shape**: `spiral suggest-seed --from-cycle cycle-088` prints scaffolded content to stdout; operator copy/pastes.

**Rejected because**: doesn't close the loop mechanically. Operator effort per cycle stays the same. The whole point of #575 is the arrow from build back to tool — a print-only suggestion keeps the author role unchanged.

### Alt-2 — Auto-dispatch scaffolded SEED without operator edit

**Shape**: EVALUATE phase not only drafts the SEED but immediately starts cycle-N+1.

**Rejected because**: violates G3 (operator autonomy) and NG1 (full agency). Worse: small scaffolding errors compound across cycles without a human speed bump to catch them.

### Alt-3 — Failure beads as soft warnings, not hard dependencies

**Shape**: circuit breaker creates a bead, but dispatch proceeds with a warning banner. Operator can ignore.

**Rejected because**: contradicts the "membrane repair" framing from #575. If failures are ignorable, they'll be ignored, and the same failures recur. Hard-dep forces acknowledgment; explicit-defer gives the escape hatch.

### Alt-4 — Classify failures post-hoc via LLM rather than taxonomy

**Shape**: at circuit-break time, invoke `claude -p` to classify the failure into free-form text.

**Rejected because**: adds LLM cost to every circuit break; unbounded vocabulary defeats dispatch-gate semantics (can't query `br list --label spiral:scope-mismatch` reliably); classification quality varies with prompt. Controlled vocab is 10 lines of YAML + regex and deterministic.

---

## Effort Estimate

- **Total**: 5 sprints, ~17 tasks, estimated 2-3 cycles of operator time (spread across 2-3 weeks)
- **Biggest risk**: Sprint 1 (schema extension + extraction) — need to handle edge cases where reviewer.md or auditor-sprint-feedback.md are malformed
- **Smallest**: Sprint 5 (docs) — under 1 sprint

Ratio check against precedent:
- RFC-060 (spiral harness initial) took ~3 cycles
- RFC-061 (calibration pack) took ~3 RFC revisions before merge; implementation still pending
- This RFC has smaller scope than either — both touch existing infrastructure rather than inventing new patterns

---

## Appendix A — Worked Example

### Scenario

Cycle-088 runs. REVIEW verdict: APPROVED. AUDIT verdict: APPROVED. But:
- 2 DISPUTED Flatline findings (consensus wasn't reached)
- 1 auditor `[DEFERRED]` row: "Batch writes to JSONL: consider buffering but deferred — out of scope"
- Bridgebuilder flagged a `SPECULATION` finding: "consider migrating append-only logs to event sourcing pattern"
- 1 circuit break during REVIEW_FIX_LOOP (hit REVIEW_MAX_ITERATIONS before converging, but operator accepted partial fix)

### HARVEST sidecar v2 output

```jsonc
{
  "$schema_version": 2,
  "cycle_id": "cycle-088",
  "review_verdict": "APPROVED",
  "audit_verdict": "APPROVED",
  "findings": {"blocker": 0, "high": 2, "medium": 5, "low": 3},
  "artifacts": {...},
  "flatline_signature": "sha256:...",
  "content_hash": "sha256:...",
  "elapsed_sec": 3421,
  "exit_status": "success",
  "pull_threads": [
    {
      "id": "pt-001",
      "source": "audit",
      "question": "Batch writes to JSONL — buffer size and fsync cadence when to revisit?",
      "severity": "medium",
      "cite": "grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md:142"
    },
    {
      "id": "pt-002",
      "source": "flatline",
      "question": "DISPUTED: whether compute_grounding_stats should surface per-category breakdown (GPT:650, Opus:200, no consensus)",
      "severity": "low",
      "cite": "grimoires/loa/a2a/flatline/flatline-sprint.json#/disputed[0]"
    }
  ],
  "emergence": [
    {
      "id": "em-001",
      "source": "bridgebuilder",
      "pattern": "Append-only logs could become event sourcing substrate — flight-recorder + dashboard.jsonl both exhibit the pattern",
      "adjacent_to": "spiral observability infrastructure",
      "confidence": "speculative"
    }
  ]
}
```

### seed-draft.md output

```markdown
# SEED draft — cycle-089

> Auto-drafted from cycle-088 HARVEST output.
> Edit freely. Operator-authored sections override auto-drafted ones.

## Context from prior cycle

- Prior cycle: cycle-088, verdict: APPROVED/APPROVED
- Elapsed: 3421s, findings: 0B/2H/5M/3L

## Open threads (from review + audit)

- **[medium]** Batch writes to JSONL — buffer size and fsync cadence when to revisit?
  - Source: audit, cite: `grimoires/loa/a2a/sprint-1/auditor-sprint-feedback.md:142`
- **[low]** DISPUTED: whether compute_grounding_stats should surface per-category breakdown (GPT:650, Opus:200, no consensus)
  - Source: flatline, cite: `grimoires/loa/a2a/flatline/flatline-sprint.json#/disputed[0]`

## Emergence observed

- **Append-only logs could become event sourcing substrate — flight-recorder + dashboard.jsonl both exhibit the pattern** (adjacent to spiral observability infrastructure; confidence: speculative)
  - Source: bridgebuilder

## Proposed cycle-089 intent

<!-- OPERATOR: replace this section with your authored intent, or accept the scaffold below -->

_Auto-scaffold: address blocking pull-threads (0) while observing emergence (1) for follow-up investigation._

---

## Provenance

- Source sidecar: `.run/cycles/cycle-088/cycle-outcome.json`
- Schema version: 2
- Drafted at: 2026-04-19T15:22:31Z
```

### Operator workflow

```bash
# Option 1: accept the scaffold with light edits
$EDITOR .run/cycles/cycle-088/seed-draft.md  # edit "Proposed cycle-089 intent"
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md

# Option 2: combined flag
/spiral --start --seed-from-draft .run/cycles/cycle-088/seed-draft.md --edit

# Option 3: discard the draft entirely
/spiral --start "Author's own task statement"
```

---

## Appendix B — Interaction with #569 Dashboard

The observability dashboard schema gains two fields:

```jsonc
{
  "totals": {
    // ... existing ...
    "failure_beads_created": 1,        // NEW
    "failure_beads_pending": 0         // NEW
  }
}
```

And per-phase rollup gains no new fields (failure beads are cycle-level, not phase-level).

`/spiral --status` pretty mode gains one line in the Metrics block:

```
Metrics (as of 2026-04-19T15:22:31Z, dashboard current: COMPLETE):
  Actions:         47  (failures: 2)
  Cost (USD):      3.21  (cap: 12, remaining: 8.79)
  Duration:        185.4s
  Fix-loops:       3  (BB cycles: 2, circuit-breaks: 1)
  Failure beads:   1 created, 0 pending       ← NEW
```

---

## Appendix C — Failure-bead UX walkthrough

### Cycle-N trips circuit break

```
[spiral-harness] CIRCUIT_BREAKER: REVIEW_FIX_LOOP_EXHAUSTED
[spiral-harness] Classification: review-fix-exhausted
[spiral-harness] Creating failure bead...
[br] Created bead bug-042: "Spiral circuit break: REVIEW_FIX_LOOP (review-fix-exhausted)"
[spiral-harness] HALTED. Failure bead bug-042 must be resolved or deferred before next dispatch.
```

### Operator attempts cycle-N+1

```
$ /spiral --start "New feature"
ERROR: Cannot start spiral: 1 unresolved failure bead(s) from prior cycles

  - bug-042 [spiral:circuit-break,spiral:review-fix-exhausted]: Spiral circuit break: REVIEW_FIX_LOOP (review-fix-exhausted)

Resolution options:
  1. Fix each: investigate + `br close <id>`
  2. Defer: `br update <id> --label spiral:deferred` with rationale comment
  3. Operator override: SPIRAL_SKIP_FAILURE_DEPS=true (logged in trajectory)
```

### Resolution path A — operator fixes the root cause

```
$ br show bug-042
# ... reads the detail, traces root cause ...
$ # operator patches the implementation / scope
$ br close bug-042
$ /spiral --start "New feature"   # now succeeds
```

### Resolution path B — defer with rationale

```
$ br update bug-042 --label spiral:deferred
$ br comments add bug-042 "Deferring: this was scope-mismatch on cycle-088 for a DIFFERENT feature; unrelated to new cycle intent. Will revisit if cycle-090 touches same area."
$ /spiral --start "New feature"   # now succeeds (deferred bead does not block)
```

### Resolution path C — operator override

```
$ SPIRAL_SKIP_FAILURE_DEPS=true /spiral --start "New feature"
[spiral-orchestrator] SPIRAL_SKIP_FAILURE_DEPS=true — skipping failure-bead check (recorded in trajectory)
```

All three paths visible in flight-recorder + dashboard.

---

## Changelog (for this RFC)

- v1.0.0 — 2026-04-19 — Initial draft authored by Claude Opus 4.7 against #575 items 1 + 4, building on work shipped in v1.99.1 / v1.99.2 / v1.101.0

## Signoff

Awaiting operator (@janitooor) review. Ready to scope into sprints once direction confirmed.
