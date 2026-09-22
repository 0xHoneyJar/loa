# Security Audit Report — PR: "remove spawn-failure handlers, skeptic normalization and membrane overlays"

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a artifacts in scope)
**Scope**: 3 files — `claude_headless_adapter.py`, `flatline-orchestrator.sh`, `construct-index-gen.sh`
**Auditor**: auditing-security skill

## Executive Summary

This PR removes three pieces of defensive/normalization code from the multi-model (cheval) and
construct-index subsystems: two `except` clauses around the `claude -p` subprocess spawn, a JSON
envelope-normalization helper on the Flatline skeptic consensus path, and an event/composition
overlay in the construct index generator. The PR description frames all three as intentional
cleanup/reverts, but the removed code was not dead weight: each block existed to convert a
specific, previously-observed failure mode into a controlled, chain-walk-compatible error or a
schema-safe default. Removing them reintroduces the failure modes they were written to close.

The most serious finding is in `claude_headless_adapter.py`: deleting the `OSError`/`ValueError`
handlers means a `claude -p` spawn failure (ARG_MAX, ENOMEM, or an embedded-NUL prompt — all
explicitly named in the deleted code's own error messages) now propagates as an **unhandled
exception** out of `complete()`, instead of the `ProviderUnavailableError` the rest of the cheval
substrate relies on for chain-walk fallback. This directly undermines the chain-walk/voice-drop
guarantee this repository's own instructions describe as the multi-model dispatch contract.

## Overall Risk Level: HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Findings

### [HIGH-1] Removing OSError/ValueError handling breaks the provider chain-walk contract on claude -p spawn failure

**Component**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:150-192`

**Description**: Before this PR, the inner `try` around `run_subprocess_pgkill(...)` caught
`subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`, `FileNotFoundError`, **and** `OSError`
/ `ValueError`, converting every one of them into `ProviderUnavailableError` (or `ConfigError` for
the missing-binary case). This PR deletes only the last two:

```python
                except FileNotFoundError as exc:
                    raise ConfigError(
                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
                    ) from exc
        except _SemaphoreExhausted as exc:
```
(head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:178-183 — the `except OSError` and `except ValueError` blocks that previously sat between these two lines are gone.)

`FileNotFoundError` is itself a subclass of `OSError`, so it is still caught by the more specific
handler above it and is unaffected. But any *other* `OSError` — e.g. `E2BIG`/ARG_MAX when the
rendered prompt makes argv too large, `ENOMEM` under memory pressure, or a generic `exec()`
failure — and any `ValueError` (e.g. an embedded NUL byte in the prompt, which `execve` rejects)
now propagate straight out of the `with _acquire_slot(...)` block, past the outer
`except _SemaphoreExhausted` (which does not match `OSError`/`ValueError`), and out of `complete()`
entirely, unhandled.

The deleted code's own error strings — `"claude -p spawn failed (ARG_MAX / ENOMEM / exec error?)"`
and `"claude -p got un-executable argv (embedded NUL in the prompt?)"` — are direct evidence these
are not hypothetical inputs; they were added to handle failures this exact spawn call had already
hit in practice.

**Impact**: This repository's own instructions (`.claude/loa/CLAUDE.loa.md`, "Multi-Model
Activation") state the cheval substrate provides "chain-walk on retryable errors; voice-drop on
chain exhaustion." That contract depends on every provider failure surfacing as a typed exception
(`ProviderUnavailableError`/`ConfigError`) that the orchestrator above the adapter can catch and
route to the next provider in the chain. An unhandled `OSError`/`ValueError` breaks that contract:
instead of gracefully failing over to the next model in the chain, the whole multi-model
invocation (Flatline review, red-team, BB, post-PR-triage — anything that calls through this
adapter) can crash outright on a single transient spawn failure. This is an availability/
robustness regression (CWE-755: Improper Handling of Exceptional Conditions) on a path this
project treats as safety-critical (adversarial review gating).

*Caveat*: the caller of `ClaudeHeadlessAdapter.complete()` (the cheval dispatch loop) is not part
of this PR's diff and was not available in this audit's file set, so it is possible an even higher
call frame wraps this in a broad `except Exception`. Even if so, that would only downgrade "crashes
the whole chain" to "the model-invocation loop must fall back to a bare `except Exception` instead
of the typed exceptions the rest of the codebase is written against" — itself a maintainability/
consistency regression, since the whole point of the typed-exception design (per the adjacent
`_SemaphoreExhausted` handling and its "C12 closure: distinct exit class so MODELINV records...")
is that failure classification for the MODELINV audit envelope depends on catching these
specific types.

**Remediation**: Restore the `except OSError` and `except ValueError` handlers (or replace them
with a single `except (OSError, ValueError) as exc: raise ProviderUnavailableError(...)`), so every
spawn-time failure of `claude -p` continues to surface as a typed, chain-walk-compatible error.

**References**: CWE-755 (Improper Handling of Exceptional Conditions)

---

### [MEDIUM-1] Removing normalize_skeptic_envelope can feed the consensus scoring engine a malformed skeptic file

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:1593-1598` (function deleted from around former line 294-310 area; call sites at 1597-1598 and 1626)

**Description**: The deleted `normalize_skeptic_envelope()` function existed specifically to
coerce a skeptic model's JSON response into `{"concerns": [...]}` shape, handling the case where
the model returns a bare JSON array instead of an object:

```
elif type == "array" then {concerns: .}
```

That the function explicitly branches on `type == "array"` is direct evidence this shape is a
real, observed skeptic-response variant — not a hypothetical. After this PR,
`extract_json_content` (head/.claude/scripts/flatline-orchestrator.sh:261-295) is the only
processing step left before the file at `$gpt_skeptic_prepared` / `$opus_skeptic_prepared` /
`$tertiary_skeptic_prepared` is handed to `"$SCORING_ENGINE" --skeptic-gpt ... --skeptic-opus ...`
(head/.claude/scripts/flatline-orchestrator.sh:1636-1637). `extract_json_content` only normalizes
markdown fences/BOM/prose-wrapping via `normalize_json_response()` — it does not guarantee an
object shape. If a skeptic model returns a bare array, the prepared file will now contain a raw
JSON array rather than `{"concerns": [...]}`.

**Impact**: `$SCORING_ENGINE` (not part of this diff, so its exact parsing could not be directly
verified in this audit) is invoked expecting `--skeptic-gpt`/`--skeptic-opus` to point at an object
with a `concerns` key, per the `'{"concerns":[]}'` default used everywhere else in this same
function for the *failure* case. If it does a straightforward key lookup, an array-shaped file
causes it to error or to silently coerce to no-concerns — either failing the whole consensus step
or silently dropping a skeptic model's flagged concerns from the security-gating consensus (a
BLOCKER-suppression risk in the Flatline adversarial-review protocol this repo relies on for
autonomous-workflow halting).

**Remediation**: Either restore `normalize_skeptic_envelope()` and its two call sites, or verify
that `$SCORING_ENGINE` itself now performs equivalent array→`{concerns:...}` coercion before
removing this safety net (grep `$SCORING_ENGINE`'s source — outside this PR's diff — for
`concerns` handling before merging).

**References**: CWE-20 (Improper Input Validation) — schema-shape assumption violated

---

### [LOW-1] Narrowed event-key extraction and dropped construct.yaml event/compose_with overlay can silently drop data

**Component**: `head/.claude/scripts/construct-index-gen.sh:302-303`, `396`, `414-422`

**Description**: Two related narrowings:

1. `emits_json`/`consumes_json` extraction changed from a three-way fallback
   (`.name // .event // .type`) to a single fixed key per direction (`.[].name` for emits,
   `.[].event` for consumes):
   ```
   emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" 2>/dev/null || echo "[]")
   consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" 2>/dev/null || echo "[]")
   ```
   (head/.claude/scripts/construct-index-gen.sh:302-303). Any manifest whose event entries use
   `type` (or `name` on the consumes side) instead of the now-hardcoded key will have those events
   silently excluded (`// empty` drops the entry with no warning or error) from the generated
   index rather than erroring.

2. The `construct.yaml` overlay that let authors declare additional `events.emits`/`events.consumes`
   and an explicit `compose_with` list has been fully removed: `composes_with` is now
   unconditionally initialized to `[]` (head/.claude/scripts/construct-index-gen.sh:396) and the
   auto-computed overlap-based `composes_with` in `compute_composition()` no longer unions in any
   manually declared value (head/.claude/scripts/construct-index-gen.sh:414-422 — compare to the
   pre-PR `(...) + ($current.composes_with // [])`). A construct author who relied on
   `construct.yaml: compose_with:` to declare a composition relationship that the automatic
   read/write-overlap heuristic cannot infer (e.g., pure event-driven composition with no shared
   reads/writes) will have that declaration silently dropped from the regenerated index.

**Impact**: This is a data-completeness/correctness regression rather than a directly exploitable
vulnerability — failures are silent (`// empty`, hardcoded `[]`) rather than loud, which is the
main reason to flag it: the generated construct index (consumed elsewhere for construct
composition/dependency reasoning, per the Agent-Network primitives model in this repo's own
instructions) can silently under-report real event and composition relationships with no error
surfaced to the operator regenerating the index.

**Remediation**: If the manifest-only/no-overlay behavior is intentional (the PR description says
it is a deliberate revert), consider at minimum a log line noting how many event entries were
skipped due to key mismatch, so silent data loss remains visible.

**References**: CWE-703 (Improper Check or Handling of Exceptional Conditions) — silent data drop

## Security Checklist Status

- [x] Secrets & credentials — not touched by this diff
- [ ] Error handling — FAIL (HIGH-1: unhandled OSError/ValueError on subprocess spawn)
- [ ] Input/schema validation — FAIL (MEDIUM-1: skeptic envelope shape no longer guaranteed)
- [ ] Data integrity — WARN (LOW-1: silent event/composition data loss)
- [x] Injection (SQL/command/template) — not applicable to this diff
- [x] Authentication/authorization — not touched by this diff
- [x] Supply chain — not touched by this diff

## Recommendations

**Immediate (before merge)**: Restore the `OSError`/`ValueError` handling in
`claude_headless_adapter.py` (HIGH-1). This is the one finding with a direct, well-evidenced
availability blast radius on the multi-model dispatch path this framework depends on for all
adversarial review.

**Short-term**: Confirm `$SCORING_ENGINE`'s expected skeptic-file schema before shipping the
`normalize_skeptic_envelope` removal (MEDIUM-1); if it does not already coerce array-shaped input,
restore the helper.

**Long-term**: Add a log line for skipped event entries in `construct-index-gen.sh` (LOW-1) so
future schema-key mismatches are visible rather than silent.

## Verdict

**CHANGES_REQUIRED**

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T08:54:00Z"} -->
