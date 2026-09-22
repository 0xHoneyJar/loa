# Review: chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays

## Overall Assessment

This is a 3-file, ~90-line deletion PR presented as low-risk cleanup ("chore"). One of the three changes — dropping the `OSError`/`ValueError` catch around the `claude -p` subprocess spawn — removes real error-handling for failure modes that are documented as first-class, expected outcomes elsewhere in this same codebase (ARG_MAX/ENOMEM spawn failures, embedded-NUL argv). That regression is enough to block. The other two changes (skeptic envelope normalization, construct composition/event extraction) are framed as intentional reverts, but each quietly narrows behavior in ways that can silently drop or corrupt data rather than fail loudly — worth flagging even though they're consistent with the stated intent.

**Verdict: CHANGES REQUIRED**

## Critical Issues

### 1. Removing the `OSError`/`ValueError` catch breaks the documented chain-walk fallback contract

`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-183`

The diff removes:

```python
except OSError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"claude -p spawn failed (ARG_MAX / ENOMEM / exec error?): {exc}",
    ) from exc
except ValueError as exc:
    raise ProviderUnavailableError(
        self.provider,
        f"claude -p got un-executable argv (embedded NUL in the prompt?): {exc}",
    ) from exc
```

`run_subprocess_pgkill(cmd, ...)` (line 159) wraps `subprocess.Popen`/`subprocess.run`, which can legitimately raise `OSError` (e.g. `E2BIG` when argv exceeds `ARG_MAX`, `ENOMEM` on fork failure, `PermissionError`) and `ValueError` (embedded NUL byte in an argv element — a real risk here since `claude -p reads the prompt from argv`, per the comment two lines above). Both were previously converted into `ProviderUnavailableError` so the multi-model chain-walk could advance to the next provider, exactly like the still-present `TimeoutExpired` and `SubprocessOutputCapExceeded` handlers immediately above them (lines 166-176), and exactly like the pattern the same file still uses elsewhere for `health_check()`: `except (subprocess.TimeoutExpired, OSError): return False` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:262`).

After this change, an `OSError`/`ValueError` from the spawn call is no longer caught anywhere in `generate()`. It propagates as an unhandled exception out of the `_acquire_slot(...)` context manager, past the `except _SemaphoreExhausted` handler (line 183, which only catches that one type), and crashes the caller instead of triggering the documented "chain-walk on retryable errors" behavior (`CLAUDE.loa.md` "Multi-Model Activation": *"chain-walk on retryable errors; voice-drop on chain exhaustion"*). A prompt that's large enough to hit `ARG_MAX` — plausible for this framework given multi-model consensus payloads passed as CLI args — now takes down the whole invocation instead of falling back to the next model in the chain.

**Fix**: restore the two `except` clauses, or if the intent is genuinely to stop special-casing these, fold them into the existing catch-all pattern used at line 262 rather than deleting the handling outright.

## Non-Critical Improvements

### 2. `normalize_skeptic_envelope` removal can hand the scoring engine a raw array where it expects `{"concerns": [...]}`

`head/.claude/scripts/flatline-orchestrator.sh:1597-1598, 1626, 1636-1637`

`extract_json_content` only pulls `.content` out of the model response and substitutes a default when content is empty/null (`head/.claude/scripts/flatline-orchestrator.sh:261-276`) — it does not enforce that the surviving content is an object. The removed `normalize_skeptic_envelope()` was doing exactly that: coercing a bare array response (`[...]`) into `{"concerns": [...]}` and coercing anything else unparseable into `{"concerns": []}`, before the file was handed to `$SCORING_ENGINE --skeptic-gpt/--skeptic-opus/--skeptic-tertiary`. With the normalization step gone, a skeptic model that returns a top-level JSON array (a response shape the removed code explicitly anticipated) now flows straight into the scoring engine unmodified. Since neither `base/` nor `head/` includes `scoring-engine.sh`, I can't confirm how it handles a non-object `--skeptic-*` file, but given the defaults used everywhere else are `{"concerns":[]}` (an object), an array input is a shape it likely doesn't expect.

**Recommendation**: confirm `scoring-engine.sh` tolerates a bare-array skeptic file before merging, or keep a minimal normalization step.

### 3. Event extraction narrowed to drop the `.type` key fallback

`head/.claude/scripts/construct-index-gen.sh:302-303`

Before: `[.[] | (.name // .event // .type) // empty]`. After: `[.[].name // empty]` (emits) and `[.[].event // empty]` (consumes). Any `manifest.json` whose `events.emits`/`events.consumes` entries are keyed by `type` instead of `name`/`event` will now silently produce `empty` for those entries (swallowed by `2>/dev/null || echo "[]"` on parse failure, or by the `// empty` filter on a per-item basis) rather than erroring. If the "manifest-only form" this reverts to still permits `type`-keyed event entries in any existing pack, those events disappear from the generated index without any warning.

### 4. Dropping the `construct.yaml` `compose_with:` override

`head/.claude/scripts/construct-index-gen.sh:396` and the `compute_composition()` rewrite (`head/.claude/scripts/construct-index-gen.sh` end of file)

The manual `compose_with:` field in `construct.yaml`, and the ability for `construct.yaml` to override the manifest's `events.emits`/`events.consumes`, are both removed — `composes_with` is now unconditionally computed from `reads`/`writes` overlap (`compute_composition`), with no way to declare an out-of-band composition relationship (e.g., two constructs that compose without sharing a literal read/write path). This is called out in the PR description as an intentional revert, so it's not a bug, but it is a capability loss: any pack author who previously relied on an explicit `compose_with:` list to link constructs will see those links vanish from the generated index with no error or warning.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-183` — unhandled `OSError`/`ValueError` from `run_subprocess_pgkill` can crash the invocation instead of advancing the fallback chain (Critical Issue #1).
2. `head/.claude/scripts/flatline-orchestrator.sh:1597-1598` — skeptic file content is no longer shape-checked before being passed to `scoring-engine.sh`, and that script isn't in this diff to verify it tolerates the change (Non-Critical #2).
3. `head/.claude/scripts/construct-index-gen.sh:302-303` — narrowing the event-name jq filter from a 3-way fallback to a single key is a silent-drop risk, not a loud failure, for any manifest still using the `type` convention (Non-Critical #3).
4. `head/.claude/scripts/construct-index-gen.sh:396` — removing `compose_with:` override support is a silent capability regression for any pack author currently using it (Non-Critical #4).

### Assumptions Challenged
- **Assumption**: the PR treats all three files as equivalent "remove now-unnecessary complexity" cleanups, bundled under one "chore" commit.
- **Risk if wrong**: the Python change is categorically different from the other two — it removes *error handling for a documented failure mode*, not a data-shape feature. Bundling a behavior-preserving revert (constructs) with a fallback-breaking regression (adapter) in one chore-labeled PR makes it easy for a reviewer to wave through all three on the strength of the other two being clearly intentional and low-risk.
- **Recommendation**: split the adapter change into its own PR with an explicit justification (e.g. "these exceptions are unreachable because X"), or restore it here.

### Alternatives Not Considered
- **Alternative**: if the goal was actually to simplify the exception handling in the adapter, a single `except (OSError, ValueError) as exc: raise ProviderUnavailableError(...)` clause (matching the file's own `health_check()` pattern at line 262) would have kept the fallback guarantee while still reducing the two near-duplicate blocks to one.
- **Tradeoff**: slightly less specific error messages (loses the "ARG_MAX / ENOMEM" vs "embedded NUL" distinction in the raised message) in exchange for keeping the chain-walk contract intact.
- **Verdict**: should reconsider — this get the stated simplification goal without the regression.

## Next Steps

1. Restore exception handling around the `run_subprocess_pgkill` call in `claude_headless_adapter.py` (either the original two clauses or a combined one).
2. Confirm (or add a lightweight guard) that `scoring-engine.sh` handles a non-normalized (array-shaped) skeptic file before shipping the `normalize_skeptic_envelope` removal.
3. If the `construct-index-gen.sh` event/composition reverts are intentional and no in-repo pack relies on the removed `type` key or `compose_with:` override, say so explicitly in the PR description so future reviewers don't need to re-derive it from the diff.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
