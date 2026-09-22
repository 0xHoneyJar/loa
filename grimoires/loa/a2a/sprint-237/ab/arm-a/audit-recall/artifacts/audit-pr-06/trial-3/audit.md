# Security Audit Report — PR pr-06

**PR title**: chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays
**Scope**: 3 files (`claude_headless_adapter.py`, `flatline-orchestrator.sh`, `construct-index-gen.sh`)
**Audit type**: Ad-hoc `/audit` — codebase diff audit (no sprint plan / beads / a2a directory present; this report is the entire input and output)

## Executive Summary

This PR is framed as a "chore" cleanup but in fact deletes three independent pieces of defensive/normalization logic that were added deliberately (each removal site carries its own explanatory comment referencing a specific prior incident: ARG_MAX/ENOMEM spawn failures, embedded-NUL argv, and skeptic envelope shape mismatches). None of the removed logic is dead code — each guarded a real failure mode reachable from untrusted/variable model output or OS-level subprocess conditions. Removing them reintroduces the exact failure classes they were built to close, in two cases with availability impact on the multi-model consensus pipeline (Flatline) and in one case with silent, undocumented data loss in construct authoring metadata.

Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## High Priority Issues

### H-1: Removing the `OSError`/`ValueError` handlers around the `claude -p` spawn reintroduces unhandled-exception crashes instead of chain-walk fallback

**Component**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:150-183`

The inner `try/except` around `run_subprocess_pgkill(...)` (lines 150-182) now only catches `subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`, and `FileNotFoundError`:

```
159                    proc = run_subprocess_pgkill(
160                        cmd,
161                        timeout=timeout_s,
162                        # cycle-109 follow-up (#879 / #880): strip ANTHROPIC_API_KEY
163                        # so claude -p uses OAuth subscription, not API mode.
164                        env=build_headless_subprocess_env(),
165                    )
166                except subprocess.TimeoutExpired:
167                    raise ProviderUnavailableError(
...
178                except FileNotFoundError as exc:
179                    raise ConfigError(
180                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
181                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
182                    ) from exc
183        except _SemaphoreExhausted as exc:
```

The diff (`head.diff:8-17`) deletes the two handlers that used to sit between the current lines 182 and 183:

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

`FileNotFoundError` is itself a subclass of `OSError`, so it is still caught — but the *other* members of the `OSError` family that `subprocess`/`os.posix_spawn` can raise (`E2BIG`/ARG_MAX when the prompt is large, `ENOMEM`, `EACCES`, other `exec()` failures) are no longer caught anywhere in this call path. They will now propagate as raw, unhandled exceptions out of `_generate_impl` instead of being converted into `ProviderUnavailableError`. Per `CLAUDE.loa.md`'s Multi-Model Activation section, the cheval substrate's contract is "chain-walk on retryable errors" — an uncaught `OSError`/`ValueError` here does not chain-walk, it crashes the calling Flatline/Bridgebuilder/red-team invocation outright, taking down the whole multi-model review rather than falling back to the next provider in the chain. Since Claude-headless is one sibling in a 3-adapter fallback chain (codex/gemini/claude — see file docstring at `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:1-4`), this converts a single-provider hiccup (e.g., an oversized prompt hitting ARG_MAX) into a hard failure of the entire adversarial-review gate instead of a transparent fallback to the next model.

**Impact**: Availability regression on the Flatline/cheval multi-model dispatch path. A large prompt (common for whole-diff adversarial review) or a prompt containing an embedded NUL byte will crash the calling flow instead of triggering the documented chain-walk-on-retryable-error fallback.

**Remediation**: Restore the two handlers (or a single `except OSError as exc` block that also matches `ValueError` if the intent is to fold them into one), preserving the `ProviderUnavailableError` conversion so the semaphore/chain-walk logic at line 183 and above continues to see a fallback-eligible error type.

### H-2: Removing `normalize_skeptic_envelope` reintroduces the skeptic-shape bug it was written to close — dissenter concerns can be silently dropped from consensus

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:1593-1598`, `1622-1629`

```
1593    # Prepare skeptic files (handles markdown-wrapped JSON)
1594    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
1595    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"
1596
1597    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
1598    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"
```

`extract_json_content` (defined at `head/.claude/scripts/flatline-orchestrator.sh:261-295`) only strips markdown fences/BOM/prose wrapping via `normalize_json_response` — it does **not** enforce that the resulting JSON is an object. If a skeptic model responds with a bare JSON array of concerns (a very common shape for an LLM asked to "list your concerns") rather than the expected `{"concerns": [...]}` envelope, `extract_json_content` will happily pass that array straight through into `gpt-skeptic-prepared.json` / `opus-skeptic-prepared.json`.

The deleted `normalize_skeptic_envelope` function (previously invoked right after each `extract_json_content` call, per `head.diff:52-53` and `:61`) existed specifically to coerce that shape:

```bash
normalize_skeptic_envelope() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    local normalized
    if normalized=$(jq -c '
        if type == "object" then .
        elif type == "array" then {concerns: .}
        else {concerns: []}
        end
    ' "$file" 2>/dev/null) && [[ -n "$normalized" ]]; then
        printf '%s\n' "$normalized" > "$file"
    else
        printf '%s\n' '{"concerns":[]}' > "$file"
    fi
}
```

These prepared files are then handed directly to the scoring engine at `head/.claude/scripts/flatline-orchestrator.sh:1636-1637` (`--skeptic-gpt "$gpt_skeptic_prepared" --skeptic-opus "$opus_skeptic_prepared"`), which per its own default (`'{"concerns":[]}'`) expects an object with a `.concerns` key. Without the normalization step, a bare-array or scalar skeptic response is no longer coerced to `{"concerns": [...]}"`, so the scoring engine will either error on the malformed input or (more likely, given how these engines are typically written defensively against parse failure) silently treat the unexpected shape as "no concerns" — i.e., the dissenter's actual concerns are dropped from the consensus computation without any log or warning.

**Impact**: This directly undermines the Flatline adversarial-review safety mechanism described in `CLAUDE.loa.md` ("HIGH_CONSENSUS auto-integrates, BLOCKER halts autonomous workflows") — a skeptic/dissenter that raises a genuine BLOCKER concern in a shape the pipeline doesn't defensively handle can be silently discarded instead of halting the workflow, which is a security-relevant regression to the review gate itself (a False Negative in a control other code paths rely on for gating).

**Remediation**: Restore `normalize_skeptic_envelope` (or equivalent shape-coercion) and re-insert the calls after each `extract_json_content` invocation for `gpt_skeptic_prepared`, `opus_skeptic_prepared`, and `tertiary_skeptic_prepared`.

## Medium Priority Issues

### M-1: `construct-index-gen.sh` silently discards explicit `construct.yaml` overlays for event names and composition edges

**Component**: `head/.claude/scripts/construct-index-gen.sh:300-336`, `401-426`

Three related narrowings, all silent (no warning/log emitted when data is dropped):

1. **Event key fallback removed** (lines 302-303):
   ```
   302    emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" 2>/dev/null || echo "[]")
   303    consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" 2>/dev/null || echo "[]")
   ```
   previously matched `(.name // .event // .type)` for emits and `(.event // .name // .type)` for consumes. Any pack manifest that declares an emitted event under `.event` or `.type` (rather than `.name`), or a consumed event under `.name`/`.type` (rather than `.event`), will now have that entry silently extracted as empty/omitted from the generated index — with no error, since the `jq` filter succeeds and simply yields `null`/`empty` for the unmatched shape.

2. **`construct.yaml` event overrides removed** (previously present in the diff hunk at `head.diff:90-95`, now entirely absent from `head/.claude/scripts/construct-index-gen.sh:310-336`): a construct author who corrects or overrides the manifest's `events.emits`/`events.consumes` via `construct.yaml` (as they already can for `name`/`version`/`description`/`writes`/`reads`/`gates`/`tags` at lines 317-335) now has no way to do so — the override path was deleted along with `compose_with_json`.

3. **Explicit `compose_with` overlay removed** (line 305-336 shows only `writes_json`, `reads_json`, `gates_json` initialized; `compose_with_json` and its extraction from `construct.yaml` at the old `head.diff:89` are gone entirely), and the merge in `compute_composition` (lines 401-426) now **replaces** rather than **unions** the computed value:
   ```
   413            $current + {
   414                composes_with: [
   415                    $all | to_entries[] |
   416                    select(.key != $i) |
   ...
   421                    .value.slug
   422                ] | unique
   423            }
   ```
   The prior form was `composes_with: (([...]) + ($current.composes_with // [])) | unique` — i.e., automatic write/read-overlap detection was additive to any explicit `compose_with:` list an author declared in `construct.yaml`. Since the per-construct entry now always initializes `composes_with: []` (line 396) and the overlay path that could have populated it from `construct.yaml` was deleted, **any construct author who explicitly declares `compose_with:` for a semantic composition relationship not captured by write/read overlap (e.g., two constructs that must compose for a reason other than shared state paths) will have that declaration silently ignored** in the generated `.run/construct-index.yaml`, with no warning at generation time.

**Impact**: Silent configuration loss. Because there's no validation error, a pack author has no signal that their `construct.yaml` `compose_with`/`events` declarations are being dropped — this is a correctness/maintainability defect, and since the construct index feeds discovery/composition data consumed elsewhere (per `CLAUDE.loa.md`'s Agent-Network Primitives references to composition and gating metadata), incorrect composition data could propagate into features that reason about which constructs are expected to interoperate.

**Remediation**: If dropping the `compose_with` overlay and the alternate event-key fallback is intentional (the PR description frames it as "reverts... to the manifest-only form"), this should (a) be called out explicitly in the PR description as a breaking change to `construct.yaml` schema support rather than described as a no-op revert, and (b) emit a `warn` when a `construct.yaml` on disk contains a `compose_with:` or `events:` key that is no longer honored, so authors relying on the old behavior get an actionable signal instead of silent divergence.

## Security Checklist Status

- [x] Input validation at trust boundaries — not touched by this diff
- [ ] Error handling preserves fail-safe behavior — **regressed** (H-1)
- [ ] Adversarial-review / consensus integrity preserved — **regressed** (H-2)
- [x] No secrets/credentials introduced
- [ ] Configuration overlays behave as documented — **regressed** (M-1, silent)
- [x] No injection vectors introduced (jq `--arg`/`--argjson` usage remains safe throughout)

## Verdict

**CHANGES_REQUIRED**

Two High findings (unhandled-exception crash path replacing documented chain-walk fallback; silent dissenter-concern loss undermining the Flatline adversarial-review gate) and one Medium (silent construct-authoring data loss) must be addressed before this PR merges. At minimum, H-1 and H-2 should be reverted unless the PR author can demonstrate the failure modes they guarded against are provably unreachable now (no such justification is present in the PR description, which frames all three removals as unqualified cleanup).

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"pr-06","ts":"2026-09-22T00:00:00Z"} -->
