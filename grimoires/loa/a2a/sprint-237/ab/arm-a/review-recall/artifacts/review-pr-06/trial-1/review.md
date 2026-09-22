# Sprint Review: chore(cheval,flatline,constructs) — remove spawn-failure handlers, skeptic normalization, membrane overlays

## Overall Assessment

CHANGES REQUIRED. This is a small, surgical-looking diff (133 lines across 3 files), but it removes three independent pieces of error-classification / normalization logic, and at least one of the removals reintroduces an unhandled-crash bug that the removed code existed specifically to prevent. The other two removals are plausible-but-unverifiable regressions given this fixture only contains the touched files, not the full framework tree or any consumers of the affected data shapes.

## Critical Issues

### 1. Unhandled `OSError`/`ValueError` will crash the cheval multi-model substrate instead of chain-walking

`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:150-192`

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

from the `except` chain that wraps `run_subprocess_pgkill(...)` inside `complete()` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-165`). The surrounding `try` block (`:150`) only catches `_SemaphoreExhausted` (`:183`), and `complete()` has no other enclosing `try`/`except` (verified — the only other `try` blocks in this file are in `health_check()` at `:253` and unrelated helpers at `:325`/`:408`).

`subprocess`-style spawn calls raise `OSError` for exec failures (ENOMEM, ARG_MAX, missing interpreter, etc.) and Python's own argv marshalling raises `ValueError` when a prompt contains an embedded NUL byte. Both are exactly the failure modes the removed handlers' own error messages describe — this is not dead code, it was purpose-built for these two failure modes. With the handlers gone, either exception now propagates as a raw, unclassified Python exception out of `complete()` instead of a `ProviderUnavailableError`.

This matters because `ProviderUnavailableError` is the signal the cheval substrate uses to chain-walk to the next provider on a retryable failure (per `CLAUDE.loa.md` "Multi-Model Activation": *"the cheval Python substrate is the unconditional dispatch path... chain-walk on retryable errors"*). An uncaught `OSError`/`ValueError` will instead abort the whole invocation, taking down Flatline/BB/red-team/post-pr-triage calls that happen to hit a transient spawn failure (e.g. host under memory pressure) with a hard crash rather than falling back to the next model in the chain — the opposite of the documented behavior.

**Fix**: restore the two `except` clauses (or fold them into `except (OSError, ValueError) as exc:` if the goal was line-count reduction — see Adversarial Analysis).

## Non-Critical Improvements (verify before merge)

### 2. `normalize_skeptic_envelope` removed without confirming the replacement covers its case

`head/.claude/scripts/flatline-orchestrator.sh:294` (function no longer present; call sites removed from around what were lines 1596-1598 and 1624 in `base/.claude/scripts/flatline-orchestrator.sh`)

The removed function normalized skeptic-concern JSON so that a bare top-level array response (`[{...}, {...}]`) was wrapped into `{"concerns": [...]}"` before being passed to `--skeptic-gpt`/`--skeptic-opus`/`--skeptic-tertiary` (`head/.claude/scripts/flatline-orchestrator.sh:1636-1637`). `extract_json_content` (`head/.claude/scripts/flatline-orchestrator.sh:261-295`) only normalizes *encoding* concerns (BOM, code fences, prose wrapping) via `normalize_json_response` — nothing in the code present in this diff normalizes *shape* (array vs. object). `lib/normalize-json.sh` is not part of this change set, so I can't confirm from the given files whether it independently guards against a bare-array skeptic response. If it doesn't, a model that returns a top-level array for its skeptic concerns will now pass an array where the consensus builder expects `{"concerns": [...]}"`.

**Ask**: confirm (or point to) where array-shaped skeptic responses are now handled, or restore the normalization.

### 3. `construct.yaml`'s explicit `compose_with` declarations are now silently dropped

`head/.claude/scripts/construct-index-gen.sh:396` (`composes_with: []` hardcoded in the per-pack builder) and `head/.claude/scripts/construct-index-gen.sh:404-421` (`compute_composition`)

`base/.claude/scripts/construct-index-gen.sh` read `construct.yaml`'s `.compose_with[].slug` (`base:330`) and merged it with the auto-derived read/write-overlap composition (`base:421` — `+ ($current.composes_with // [])`). The new code drops the manual overlay entirely: `composes_with` is now purely auto-computed from write/read overlap (`head:414-421`), and any pack author who explicitly declared a `compose_with:` relationship in `construct.yaml` (e.g., a composition based on shared events rather than read/write overlap) loses that declaration with no warning. This fixture doesn't ship any `construct.yaml` files, so I can't confirm whether this field is live anywhere in the broader framework — see Adversarial Analysis.

### 4. Event-name extraction fallback narrowed, and `construct.yaml` event overrides removed

`head/.claude/scripts/construct-index-gen.sh:302-303`

```bash
emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" ...)
consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" ...)
```

`base/.claude/scripts/construct-index-gen.sh:301-302` tried `(.name // .event // .type)` / `(.event // .name // .type)` — a 3-way fallback. The new code only checks a single field name per direction. Any `manifest.json` that keys its emitted/consumed events as `.type` (or an emit event as `.event`/`.type`, or a consume event as `.name`/`.type`) will now silently produce an empty entry instead of the event name — a silent-data-loss failure mode (empty array/entry, no warning) rather than a loud one. The `construct.yaml`-level event overlay (`cy_emits`/`cy_consumes`, `base:336-340`) that let a pack override manifest-declared events is also deleted outright, so any pack relying on that override loses it silently.

## Adversarial Analysis

### Concerns Identified
1. `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:178-183` — removing the `OSError`/`ValueError` handlers turns two named, previously-handled failure modes into uncaught crashes, contradicting the framework's own documented chain-walk-on-retryable-errors contract.
2. `head/.claude/scripts/flatline-orchestrator.sh:294` (function removed) — skeptic-envelope shape normalization is gone with no visible replacement in the files provided; unverifiable whether `normalize_json_response` (out of scope of this diff) already subsumes it.
3. `head/.claude/scripts/construct-index-gen.sh:396` — explicit author-declared `compose_with` relationships in `construct.yaml` are now unconditionally discarded rather than merged with the auto-derived overlap set.
4. `head/.claude/scripts/construct-index-gen.sh:302-303` — event extraction fallback narrowed from a 3-key union to a single key, which fails silently (empty array) rather than loudly for manifests using the dropped key names.

### Assumptions Challenged
- **Assumption**: The PR title ("reverts construct-index-gen.sh event extraction and composition to the manifest-only form") implies the author believes the `construct.yaml` `compose_with`/event-overlay fields are unused/dead weight safe to delete.
- **Risk if wrong**: This fixture is a trimmed snapshot containing only the files touched by the PR — it contains zero `construct.yaml` files, so "nothing references this field" can't actually be confirmed here. If any pack in the live framework tree declares `compose_with:` or event overlays, this change silently drops that metadata from the generated index with no error or warning.
- **Recommendation**: Before merging, grep the full framework repository (not this fixture) for `construct.yaml` files using `compose_with:` or `events:` keys, and state the result in the PR description. If genuinely zero hits, this concern is resolved and the removal is reasonable cleanup.

### Alternatives Not Considered
- **Alternative**: For the adapter change, keep the failure classification but consolidate it — `except (OSError, ValueError) as exc:` raising one `ProviderUnavailableError` with a merged message — rather than deleting the classification outright.
- **Tradeoff**: This achieves the same line-count reduction the PR appears to be going for while preserving the chain-walk contract; the only cost is a couple more lines than a bare removal.
- **Verdict**: The current full removal is not justified purely by a desire to simplify — the consolidation gets the same simplicity without reintroducing the crash bug. Recommend this alternative over the as-submitted removal.

## Next Steps

1. Restore `OSError`/`ValueError` handling around the `run_subprocess_pgkill` call in `claude_headless_adapter.py` (full restore, or the consolidated `except (OSError, ValueError)` alternative above) — blocking.
2. Confirm (with a pointer to the relevant code, since `lib/normalize-json.sh` isn't in this diff) that bare-array skeptic responses are still normalized somewhere, or restore `normalize_skeptic_envelope`.
3. Confirm no live `construct.yaml` declares `compose_with` or event overlays before dropping that code path; if any do, either preserve the merge behavior or migrate those packs first.
4. If the narrowed `.name`/`.event` extraction is intentional (i.e., `.type` was never a valid manifest key), say so in the PR description so reviewers aren't left inferring it from an empty diff context.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":0,"medium":3,"low":0},"sprint_id":"pr-review","ts":"2026-09-21T00:00:00Z"} -->
