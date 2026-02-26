# Sprint 78 (Cycle-042, Sprint 2) — Security Hardening

## Implementation Report

### S2-T1: Fix gpt-review-api.sh template rendering (FR-3, vision-002)

**Status**: COMPLETED

Fixed unsafe bash parameter expansion at `.claude/scripts/gpt-review-api.sh:88`:
- Old: `rp="${rp//\{\{PREVIOUS_FINDINGS\}\}/$2}"` — expands `${...}` in replacement string
- New: `printf '%s' "$rp" | awk -v iter="$1" -v findings="$2" '{gsub(...); print}'` — no shell expansion

### S2-T2: Fix bridge-vision-capture.sh unquoted heredoc (FR-3, vision-002)

**Status**: COMPLETED

Fixed unsafe heredoc at `.claude/scripts/bridge-vision-capture.sh:244-266`:
- Old: `cat > "$entries_dir/${vision_id}.md" <<EOF` — shell expands `${title}`, `${description}`
- New: `jq -n --arg` pipeline — constructs markdown through jq string concatenation

### S2-T3: Create context-isolation-lib.sh (FR-4, vision-003)

**Status**: COMPLETED

New file: `.claude/scripts/lib/context-isolation-lib.sh`
- `isolate_content()` wraps untrusted content in de-authorization envelope
- `_isolation_enabled()` checks `prompt_isolation.enabled` config via yq
- Envelope includes warning header, content, and end marker

### S2-T4: Integrate into flatline-orchestrator.sh (FR-4, vision-003)

**Status**: COMPLETED

Modified `.claude/scripts/flatline-orchestrator.sh`:
- Added `source "$SCRIPT_DIR/lib/context-isolation-lib.sh"` at line 50
- Wraps `doc_content` and `extra_context` with `isolate_content()` before inquiry prompts

### S2-T5: Integrate into proposal-review and validate-learning (FR-4)

**Status**: COMPLETED

Modified 2 files:
- `.claude/scripts/flatline-proposal-review.sh`: Added source, wrapped trigger/solution, fixed `<<EOF` to `<<'PROMPT_EOF'` with printf
- `.claude/scripts/flatline-validate-learning.sh`: Same pattern

### S2-T6: Config keys for new features

**Status**: COMPLETED

Updated `.loa.config.yaml`:
- Added `vision_registry.bridge_auto_capture: false`
- Added `prompt_isolation.enabled: true`

Updated `.loa.config.yaml.example` with documentation comments.

### S2-T7: Template safety tests

**Status**: COMPLETED

New file: `tests/unit/template-safety.bats` with 4 tests:
1. gpt-review-api.sh re-review with `${EVIL}` in findings does not expand
2. bridge-vision-capture.sh jq handles adversarial content safely
3. context-isolation-lib.sh wraps content with correct envelope
4. injection-like strings preserved literally in envelope

All 4 pass.

## Files Changed

| File | Change |
|------|--------|
| `.claude/scripts/gpt-review-api.sh` | Fixed template rendering with awk |
| `.claude/scripts/bridge-vision-capture.sh` | Replaced heredoc with jq |
| `.claude/scripts/lib/context-isolation-lib.sh` | NEW — context isolation library |
| `.claude/scripts/flatline-orchestrator.sh` | Integrated context isolation |
| `.claude/scripts/flatline-proposal-review.sh` | Integrated context isolation + heredoc fix |
| `.claude/scripts/flatline-validate-learning.sh` | Integrated context isolation + heredoc fix |
| `.loa.config.yaml` | Added bridge_auto_capture + prompt_isolation keys |
| `.loa.config.yaml.example` | Documented new config keys |
| `grimoires/loa/ledger.json` | Sprint 78 status |
| `tests/unit/template-safety.bats` | NEW — 4 template safety tests |

## Test Summary

| Suite | Total | Pass | Fail | New |
|-------|-------|------|------|-----|
| template-safety | 4 | 4 | 0 | 4 |
