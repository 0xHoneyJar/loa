# Cycle-114 SDD — Harness Modernization: Opus 4.8

> **Version**: 1.0
> **Cycle**: cycle-114-harness-modernization-opus-4.8
> **PRD**: `grimoires/loa/prd.md` (FR-1 … FR-10)
> **Status**: Draft (awaiting operator sign-off)
> **Design stance**: surgical, test-first, additive-only. Every new field is
> optional; absent → today's behavior byte-for-byte (NFR-2). No file outside the
> PRD §0 authorized surfaces is touched (NFR-6).

---

## 1. Architecture Overview

Cycle-114 is a set of **localized, low-blast-radius edits** to existing Loa
subsystems. There is no new subsystem and no cross-cutting refactor. The work
divides along three independent seams that land as three sequential sprints:

```
S1 Model substrate     model-config.yaml → gen-adapter-maps.sh → {bash maps, BB config}
                       loa_cheval/types.py (effort field) → anthropic_adapter.py (output_config)
                       deep-reasoning SKILL.md frontmatter (effort:)

S2 Gate & safety       review SKILL.md frontmatter (disallowed-tools:) + validator rule
                       run-mode-stop-guard.sh (parse background_tasks/session_crons)
                       block-destructive-bash.sh (BLOCK regex precision)
                       hooks-reference.md (egress scope note)

S3 Economy/UX/ADR      MODELINV schema (effort field) + economy.py roll-up
                       new session-start hook (sessionTitle)
                       proposals/native-workflow-adoption.md (ADR, no code)
```

Dependency: **FR-3 depends on FR-2** (skills can't declare `effort:` meaningfully
until the substrate threads it). FR-2 is independent of FR-1. All else parallel.

---

## 2. Component Design

### 2.1 FR-1 — Opus 4.8 in the model registry

**Source of truth**: `.claude/defaults/model-config.yaml`. Generated artifacts
(`generated-model-maps.sh`, BB `config.generated.*`) are **outputs of**
`gen-adapter-maps.sh` and MUST NOT be hand-edited (NFR-1).

**Design** — model entry modeled on the existing `claude-opus-4-7` block (L343):

```yaml
# under providers.anthropic.models (insert above claude-opus-4-7)
claude-opus-4-8:
  auth_type: http_api
  dispatch_group: anthropic-claude
  capabilities: [chat, tools, function_calling, thinking_traces]
  context_window: 200000
  token_param: max_tokens
  fallback_chain:
    - anthropic:claude-opus-4-7
    - anthropic:claude-sonnet-4-6
    - anthropic:claude-headless
  params:
    temperature_supported: false   # adaptive-thinking model (mirror 4.7)
  pricing:
    input_per_mtok:  5000000        # $5.00 / Mtok  (== 4.7)
    output_per_mtok: 25000000       # $25.00 / Mtok (== 4.7)
  # fast-mode pricing recorded where 4.7 records its fast variant ($10/$50)
```

- **Alias retarget**: `opus: "anthropic:claude-opus-4-8"` (was 4-7, L578). Leave a
  comment noting the cycle-114 retarget (mirror the cycle-082 comment style).
- **Backward-compat aliases** — BOTH forms (cycle-108 BB alias-gap learning):
  `"claude-opus-4-8": "anthropic:claude-opus-4-8"` and
  `"claude-opus-4.8": "anthropic:claude-opus-4-8"`. Also add the self-map in the
  BB `backward_compat_aliases` so `config.generated.js` dash-form resolves.
- **Bedrock**: add `us.anthropic.claude-opus-4-8` inference-profile entry modeled
  on the existing 4-7 Bedrock profile, `fallback_to: anthropic:claude-opus-4-8`.
- **Regeneration**: run `bash .claude/scripts/gen-adapter-maps.sh` (or the
  documented codegen entrypoint), then verify the four bash maps
  (`MODEL_PROVIDERS`, `MODEL_IDS`, `COST_INPUT*`, `COST_OUTPUT*`) and BB
  `config.generated.*` all contain 4.8.

**Verification**: `validate_model_registry()` exit 0; `model-resolver.sh`
resolves `opus`, `claude-opus-4-8`, `claude-opus-4.8`; existing model-registry
drift gate green. Regenerate is the ONLY writer of generated files.

**Risk control**: order = *edit YAML → regenerate → validate → test*; never edit a
generated file directly (the exact failure mode flagged in the audit and in
MEMORY: "must stay in sync across 4 maps").

### 2.2 FR-2 — `effort` through the Anthropic HTTP adapter

**Files**: `.claude/adapters/loa_cheval/types.py`,
`.claude/adapters/loa_cheval/providers/anthropic_adapter.py`.

**`CompletionRequest`** (types.py) — add optional canonical field:

```python
effort: Optional[str] = None   # one of: low | medium | high | xhigh | max
```

Keep it last among fields with a default to preserve positional/back-compat.

**`anthropic_adapter.py`** — in the request-body construction (the block that
today builds `messages`/`system`/`max_tokens`, ~L99–123 region), add:

```python
_VALID_EFFORT = {"low", "medium", "high", "xhigh", "max"}

effort = getattr(request, "effort", None) or (
    (request.metadata or {}).get("effort") if request.metadata else None
)
if effort is not None:
    if effort not in _VALID_EFFORT:
        raise ValueError(f"invalid effort {effort!r}; expected one of {_VALID_EFFORT}")
    body.setdefault("output_config", {})["effort"] = effort
# NB: do NOT set thinking.budget_tokens — Opus 4.7/4.8 reject it (HTTP 400).
```

**Invariants**:
- When `effort is None` → body is byte-identical to today (NFR-2).
- The adapter never emits a `thinking` block for effort (NFR-4). Thinking-trace
  *reads* (L316–354) are untouched.
- Precedence: explicit `request.effort` > `metadata["effort"]` (mirror the
  headless-adapter precedence at `claude_headless_adapter.py:_resolve_effort`).

**Tests** (pytest, mirroring existing adapter tests):
1. `effort="xhigh"` → `body["output_config"]["effort"]=="xhigh"`; `"thinking" not in body`.
2. `effort=None` → `"output_config" not in body` (or unchanged baseline).
3. `effort="bogus"` → `ValueError`.

### 2.3 FR-3 — `effort:` frontmatter on deep-reasoning skills

**Files**: SKILL.md of `designing-architecture`, `auditing-security`,
`red-teaming`, `bridgebuilder-review`.

| Skill | effort |
|-------|--------|
| designing-architecture | high |
| auditing-security | high |
| red-teaming | xhigh |
| bridgebuilder-review | xhigh |

**Validator** (`validate-skill-capabilities.sh`): accept an `effort` key whose
value ∈ `{low,medium,high,xhigh,max}`; WARN (not ERROR) on
`cost-profile: lightweight` paired with `effort: xhigh` (suspicious combo).
**Test**: bats fixture with a bad effort enum → validator non-zero; good → zero.

### 2.4 FR-4 — `disallowed-tools` on review skills + validator rule

**Files**: SKILL.md of `reviewing-code`, `auditing-security`, `red-teaming`,
`bridgebuilder-review`; `validate-skill-capabilities.sh`; new bats.

**Frontmatter added to each review skill**:
```yaml
disallowed-tools:
  - Write
  - Edit
  - NotebookEdit
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git push *)
```

**Exclusions (documented in skill-invariants.md)**: `designing-architecture`,
`planning-sprints` (author artifacts → keep Write), and `spiraling` (role:review
but dispatches writes through the harness). The exclusion list is explicit and
commented so a future reader knows it's intentional, not an omission.

**Validator rule** (extends the existing agent-type-invariant check region):
```
IF role == "review" AND capabilities.write_files == true
   AND "Write" NOT IN disallowed-tools
   AND skill NOT IN REVIEW_WRITE_EXCEPTIONS:
     WARN "review skill <name> can Write but does not disallow it (C-PROC-001 mechanical-enforcement gap)"
```
`REVIEW_WRITE_EXCEPTIONS` is a small array near the top of the script (mirrors the
existing `WRITE_CAPABLE_AGENTS` pattern — one-line edit with reviewer visibility).

**Test**: bats — (a) a review skill with the frontmatter validates clean; (b) a
fixture review skill without disallowed Write → WARN line present; (c) excepted
skills don't trigger the WARN.

> **Note**: `disallowed-tools` is a harness-enforced restriction at skill-active
> time; this SDD adds the *declaration* + a static lint. Runtime enforcement is
> provided by Claude Code ≥2.1.152 (local harness 2.1.158).

### 2.5 FR-5 — Stop-guard background-task awareness

**File**: `.claude/hooks/safety/run-mode-stop-guard.sh`.

The hook reads Stop/SubagentStop JSON on stdin. After the existing
`.run/*-state.json` checks, add:

```bash
input="$(cat)"                       # reuse the already-captured stdin
bg_count=$(printf '%s' "$input" | jq -r '(.background_tasks // []) | length' 2>/dev/null || echo 0)
cron_count=$(printf '%s' "$input" | jq -r '(.session_crons // []) | length' 2>/dev/null || echo 0)
if [[ "${bg_count:-0}" -gt 0 ]]; then
  ids=$(printf '%s' "$input" | jq -r '[.background_tasks[]?.id // .background_tasks[]?] | join(", ")' 2>/dev/null)
  emit_block "background tasks still running: [$ids]. Cancel via TaskStop <id>, or stop intentionally."
fi
```

**Invariants** (NFR-5 fail-open): missing fields, non-JSON, or absent `jq` → no
block, exit 0. Never hard-fail a Stop. `session_crons` is parsed and surfaced in
the reason text but, by itself, does NOT block (crons are expected to outlive a
session); only live `background_tasks` block.

**Test**: bats with mocked stdin — non-empty `background_tasks` → `decision==block`;
empty/absent → exit 0; malformed JSON → exit 0.

### 2.6 FR-6 — `block-destructive-bash.sh` `$HOME/` precision

**File**: `.claude/hooks/safety/block-destructive-bash.sh` (BLOCK regex).

Current BLOCK alternation:
```
^(/|\$HOME|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/)
```
`$HOME/` matches neither group (first needs exact `$HOME`; second lacks `\$HOME/`)
→ AMBIGUOUS. Fix: add `$HOME/` and `${HOME}/` to the trailing-slash group; keep
`~/` (already present in group 2):
```
^(/|\$HOME|\$\{HOME\}|~|~/|/etc|/usr|/var|/home|\*|\.)$|^(/etc/|/usr/|/var/|/home/|~/|\$HOME/|\$\{HOME\}/)
```

**Invariants**: `rm -rf ~/subdir`, `rm -rf $HOME/subdir` (a *child*, not home
root) MUST remain AMBIGUOUS — they are not the catastrophic home-root shape; only
bare `$HOME/`, `${HOME}/`, `~/` (home root with trailing slash) escalate to BLOCK.
Both branches still `emit_block` exit 2, so this is a *message-precision* change,
not a new block.

**Test**: bats — `$HOME/`, `${HOME}/`, `~/` → FR-2-BLOCK; `~/subdir`,
`$HOME/projects` → AMBIGUOUS; the full existing BLOCK/ALLOW suite unchanged.

### 2.7 FR-7 — Egress non-guarantee documentation

**File**: `.claude/loa/reference/hooks-reference.md` (Safety Hooks section).

Add a "Known Scope Boundaries" subsection: destructive-bash + `settings.deny.json`
defend filesystem-destruction and credential-read surfaces; they do **not**
monitor or restrict network egress / bulk data exfiltration; that is operator
responsibility (firewall / network policy external to Claude Code). Cross-ref
cycle-111 SDD §11 accepted-bypass list. Documentation only — no behavior change.

### 2.8 FR-8 — Effort in MODELINV envelope + workload_tier_map

**Files**: `.claude/data/trajectory-schemas/model-events/model-invoke-complete.payload.schema.json`,
`.claude/adapters/loa_cheval/economy.py`, `.claude/defaults/model-config.yaml`
(`tier_groups`).

- **Schema**: add optional `"effort": {"type":"string","enum":["low","medium","high","xhigh","max"]}`
  to the payload schema (additive).
- **Emit**: where the MODELINV record is built post-flight, include `effort`
  (from the resolved request) when present.
- **Roll-up** (`economy.py`): extend the group key to `(skill, model, effort)`;
  effort renders as a column (null → `-`). Pure aggregation change; no new I/O.
- **`tier_groups`**: optional `effort:` per tier mapping, **informational only**
  this cycle (Phase-A invariant: `workload_tier_map` is non-binding). A pinning
  test asserts the value is not consumed as a binding control.

**Test**: schema-validate a record with and without `effort`; roll-up unit test
shows the effort grouping; invariant test pins informational-only.

### 2.9 FR-9 — SessionStart sessionTitle recovery

**File**: new `.claude/hooks/session-start/loa-run-mode-session-title.sh`;
register in `.claude/settings.json` SessionStart hooks.

Reads `.run/sprint-plan-state.json`, `.run/bridge-state.json`,
`.run/simstim-state.json`. If any is in an active state (`RUNNING`/`HALTED`),
emits:
```json
{"hookSpecificOutput":{"sessionTitle":"LOA: [<mode> <STATE>] <hint>"}}
```
e.g. `LOA: [sprint-plan RUNNING] resume sprint-N`. JACKED_OUT/COMPLETED/absent →
no output, exit 0 (NFR-5).

**Test**: bats — RUNNING sprint-plan fixture → JSON with `sessionTitle`;
all-jacked-out → no title / exit 0; malformed state file → exit 0.

### 2.10 FR-10 — Native Workflow adoption ADR (doc only)

**File**: `grimoires/loa/proposals/native-workflow-adoption.md`. Sections:
Context (native `Workflow` capabilities), Where-it-fits (Claude-only fan-out:
parallel sprint-task impl, parallel audit file review, spiral/run-bridge loops),
Where-Loa-keeps-bespoke (cross-vendor flatline consensus, circuit breakers,
MODELINV audit envelopes), Scoped-pilot design, Decision criteria (go/no-go), and
an explicit **"No orchestration code lands this cycle"** statement. No `.claude/`
changes.

---

## 3. Data Model Changes

| Artifact | Change | Compat |
|----------|--------|--------|
| `model-config.yaml` | +`claude-opus-4-8` entry, +aliases, +Bedrock profile, retarget `opus` | additive (retarget intentional) |
| generated maps / BB config | regenerated | derived |
| `CompletionRequest` | +`effort: Optional[str]=None` | additive optional |
| MODELINV payload schema | +`effort` (optional enum) | additive optional |
| `tier_groups` entries | +`effort` (optional, informational) | additive optional |
| review SKILL.md | +`disallowed-tools`, +`effort` | additive frontmatter |

No migrations. No state-file format changes (`.run/*` read-only here).

## 4. Security Design

- **FR-4** raises the floor: review/audit/red-team skills become *mechanically*
  unable to Write/Edit or run mutating git — closing the instruction-following
  bypass of C-PROC-001.
- **FR-5** prevents Stop from silently orphaning live background agents in
  autonomous runs (lifecycle safety).
- **FR-6** improves destructive-command messaging precision (no security
  regression — both paths already block).
- **FR-7** is honest scoping: documents that egress is *not* guarded so operators
  don't over-trust the hook.
- All new hooks **fail open** (NFR-5): a safety hook must never brick a session.
- No new secrets, no new network calls, no new external dependencies.

## 5. Test Strategy

Test-first per NFR-3. Each FR's failing test is written before its implementation.

| FR | Test kind | Location | Key assertion |
|----|-----------|----------|---------------|
| FR-1 | bash/bats + drift gate | tests/unit/model-registry-*.bats | 4.8 resolves; validate exit 0; maps in sync |
| FR-2 | pytest | cheval tests | `output_config.effort` set; no `thinking` block |
| FR-3 | bats | tests/unit/skill-capabilities.bats | effort enum valid; lightweight+xhigh WARN |
| FR-4 | bats | tests/unit/skill-capabilities.bats | review skill cannot Write; WARN on misconfig |
| FR-5 | bats | tests/unit/run-mode-stop-guard.bats | bg_tasks → block; absent → exit 0 |
| FR-6 | bats | tests/unit/block-destructive-bash.bats | `$HOME/` BLOCK; `~/subdir` AMBIGUOUS |
| FR-7 | doc lint | — | section present + cross-ref |
| FR-8 | pytest + schema | cheval/schema tests | record validates w/ & w/o effort; roll-up column |
| FR-9 | bats | tests/unit/session-title.bats | RUNNING → title; jacked-out → none |
| FR-10 | doc | — | ADR exists + decision criteria + "no code" |

**Regression**: the full existing bats + pytest suites and all drift gates must
remain green (Goal §2 "Zero regressions").

## 6. Rollout / Reversibility

- All changes additive + branch-isolated (`feature/sprint-plan-cycle-114`).
- Rollback = revert the cycle merge commit (model-registry retarget reverts the
  `opus` alias to 4-7; generated maps regenerate from reverted YAML).
- FR-2/FR-8/FR-3/FR-4 fields are optional — reverting frontmatter/schema is inert.

> **Sources**: PRD FR-1…FR-10; audit Verification Notes (model-config.yaml
> L343/L578, anthropic_adapter.py L316–354, block-destructive-bash.sh BLOCK regex,
> claude_headless_adapter.py L293); platform.claude.com effort doc
> (`output_config.effort`, budget_tokens→400 on 4.7/4.8).
