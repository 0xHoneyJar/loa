# Security Audit — chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays

**Scope**: 3 files, 133-line diff (unified). No sprint plan / beads / a2a directory present — audited directly from `PR.md`, `head.diff`, `base/`, `head/` per audit instructions.

- `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py`
- `.claude/scripts/flatline-orchestrator.sh`
- `.claude/scripts/construct-index-gen.sh`

## Summary

This PR is framed as a "chore" revert, but it removes three pieces of defensive
code whose commit-adjacent comments show they were added to close specific,
previously-observed failure modes. Two of the three regressions land inside
security-relevant control paths: the `cheval` multi-model dispatch layer (used
by Flatline's adversarial consensus/dissenter mechanism, which this very audit
workflow depends on per `CLAUDE.loa.md` Phase 1C) and the Flatline consensus
scorer itself. Removing them reintroduces crash / silent-degradation paths in
those controls rather than in ordinary application logic.

## Findings

### 1. [HIGH] Uncaught `OSError`/`ValueError` from subprocess spawn crashes the cheval dispatch path instead of degrading to the typed fallback chain

**Location**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:150-192`

```python
        try:
            with _acquire_slot("claude-headless", n_slots=n_slots):
                try:
                    proc = run_subprocess_pgkill(
                        cmd,
                        timeout=timeout_s,
                        env=build_headless_subprocess_env(),
                    )
                except subprocess.TimeoutExpired:
                    raise ProviderUnavailableError(...)
                except SubprocessOutputCapExceeded as exc:
                    raise ProviderUnavailableError(...) from exc
                except FileNotFoundError as exc:
                    raise ConfigError(...) from exc
        except _SemaphoreExhausted as exc:
            raise ProviderUnavailableError(...) from exc
```

The diff (`head.diff:8-17`) deletes two `except` clauses that used to sit
directly after the `FileNotFoundError` handler:

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

Every remaining `except` clause in this function names a specific exception
type (`subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`,
`FileNotFoundError`, `_SemaphoreExhausted`) — there is no catch-all. The
adapter's whole design, per its own inline comments ("`#982`: … the fallback
chain advances instead of hanging", "C12 closure: distinct exit class so
MODELINV records semaphore_exhausted=true and the caller routes the failure
separately"), depends on every subprocess failure mode being translated into
one of cheval's typed exceptions (`ProviderUnavailableError`, `ConfigError`,
`AuthRevokedError`, `RateLimitError`) so the orchestrator can fail over to the
next provider in the chain and record the outcome.

`subprocess.Popen`/`subprocess.run`-style spawn calls raise plain `OSError`
for `E2BIG` (argument list / `ARG_MAX` too long), `ENOMEM`, and other
`exec()`-family failures, and plain `ValueError` when the argv contains an
embedded NUL byte — the exact two conditions named in the deleted handlers'
messages. `cmd` in `_build_command` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-165`,
`273-342`) embeds the flattened prompt directly into argv (`"-p", prompt, ...`),
and the prompt is built from `request.messages`
(`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:387-422`) — content that, per this
repository's own Agent-Network guidance, includes cross-agent/skeptic bodies
that must be "treated as UNTRUSTED". A sufficiently large or NUL-containing
prompt is therefore attacker/environment-influenceable, and after this change
it raises an untyped exception that neither inner `except` nor the outer
`except _SemaphoreExhausted:` catches — it propagates straight out of
`complete()`.

**Failure scenario**: A prompt built during multi-model consensus (e.g. a
large accumulated skeptic/dissent transcript, or one containing a stray NUL
from upstream tool output) exceeds `ARG_MAX` or trips `exec()` failure. Before
this change, that became a normal `ProviderUnavailableError` and the chain
failed over to the next provider, exactly like a timeout. After this change,
it is an unhandled `OSError`/`ValueError` bubbling out of the adapter — at
best it aborts the whole cheval call (and, depending on the caller not shown
in this diff, potentially the whole Flatline consensus run) instead of
degrading gracefully; at worst it produces an unstructured traceback in place
of the typed, audit-logged failure the rest of the system expects. This is
CWE-703 (Improper Check or Handling of Exceptional Conditions,
https://cwe.mitre.org/data/definitions/703.html) reintroduced into a control
that a prior fix (visible only via the deleted comments/messages) had already
closed.

**Note**: the actual blast radius (crash vs. caught-and-swallowed elsewhere)
depends on the caller of `ClaudeHeadlessAdapter.complete()`, which is not part
of this PR's touched files and so is out of scope for this audit — flagged as
an assumption. What is confirmed by the code present here is that the local
typed-error contract this file otherwise maintains is broken for these two
cases.

### 2. [MEDIUM] Removing `normalize_skeptic_envelope` lets a skeptic model's bare-array response reach the consensus scorer unnormalized

**Location**: `head/.claude/scripts/flatline-orchestrator.sh:1593-1598` (call sites), function deleted at `head.diff:28-43` (formerly directly above `log_trajectory()`, i.e. right after `extract_json_content()` at `head/.claude/scripts/flatline-orchestrator.sh:261-295`)

```bash
    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"
```

The deleted function was:

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

`extract_json_content()` (`head/.claude/scripts/flatline-orchestrator.sh:261-295`) only
strips markdown fences/BOM/prose wrapping via `normalize_json_response()`; it
does not enforce any particular top-level JSON *type*. If a skeptic model
emits a bare JSON array of concern objects (a common LLM deviation — which is
presumably why `normalize_skeptic_envelope` existed at all, given its
if/elif/else explicitly special-cases `type == "array"`), the prepared file at
`$gpt_skeptic_prepared` / `$opus_skeptic_prepared` /
`$tertiary_skeptic_prepared` (`head/.claude/scripts/flatline-orchestrator.sh:1594-1598,
1625-1627`) now contains that raw array instead of `{"concerns": [...]}`. This
is then handed to `"$SCORING_ENGINE"` via `--skeptic-gpt` /
`--skeptic-opus` / `--skeptic-tertiary`
(`head/.claude/scripts/flatline-orchestrator.sh:1632-1640`) — the component that
computes Flatline's consensus/blocker verdict.

**Failure scenario**: `scoring-engine.sh` is not part of this PR's touched
files, so its exact handling of a top-level array under `--skeptic-*` cannot
be confirmed from this diff — flagged as an assumption, marked plausible
rather than confirmed. Two outcomes are both plausible and both bad for a
security-review gate: (a) it errors/crashes attempting `.concerns` on an
array, aborting the consensus phase entirely, or (b) it silently treats the
malformed/undestructured payload as containing no `concerns`, which would
mean a skeptic model's dissent/concerns are dropped from the Flatline
verdict without any error surfaced — a silent bypass of the adversarial
review gate. This is CWE-20 (Improper Input Validation,
https://cwe.mitre.org/data/definitions/20.html): the removed code was the
sole point performing shape validation/canonicalization on skeptic output
before it reaches a security-decision consumer.

### 3. [LOW] Construct index generation silently drops admin-declared `compose_with` and schema-variant event keys

**Location**: `head/.claude/scripts/construct-index-gen.sh:301-303, 305-308, 396, 401-426`

```bash
emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" 2>/dev/null || echo "[]")
consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" 2>/dev/null || echo "[]")
...
            composes_with: [],
...
compute_composition() {
    ...
                composes_with: [
                    $all | to_entries[] |
                    select(.key != $i) |
                    select(
                        (.value.writes as $w | $current.reads | any(. as $r | $w | index($r))) or
                        (.value.reads as $r | $current.writes | any(. as $w | $r | index($w)))
                    ) |
                    .value.slug
                ] | unique
```

Compared to `base/.claude/scripts/construct-index-gen.sh`, this drops the
`.event`/`.type` fallback keys when extracting `emits`/`consumes` from
`manifest.json` (any construct describing an event only via `.event` or
`.type` now silently produces an empty list for that field, since
`[.[].name // empty]` yields nothing for entries lacking `.name`), and it
removes the explicit `construct.yaml` `compose_with:` overlay entirely —
`composes_with` on the final index entry is now *purely* the write/read-path
overlap inference in `compute_composition()`, with no path for an operator to
hand-declare an additional compose relationship.

**Failure scenario**: this is a data-completeness/functional regression, not
a new escalation path — the effect of dropping the explicit `compose_with:`
overlay is that the computed `composes_with` set can only shrink relative to
`base/`, never grow, so it does not introduce an over-broad trust grant.
However, any downstream consumer of the construct index that relies on
`events.emits`/`events.consumes` being complete, or on an operator's
explicit `compose_with:` declaration being honored (e.g. for
composition/trust decisions outside this diff's scope), will now see
silently incomplete data with no warning logged. Not independently
verifiable against a consumer within this PR's file set — recorded as an
observation rather than a confirmed high-severity finding.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Recommendations

- **Immediate (24h)**: Restore the `OSError`/`ValueError` handlers in
  `claude_headless_adapter.py`, or replace them with an equivalent catch-all
  that maps any non-typed exception from `run_subprocess_pgkill` to
  `ProviderUnavailableError` before it leaves `complete()`.
- **Immediate (24h)**: Restore `normalize_skeptic_envelope()` (or move
  equivalent type-canonicalization into `extract_json_content()` for the
  skeptic call sites) so a bare-array skeptic response cannot reach
  `scoring-engine.sh` unnormalized. Verify `scoring-engine.sh`'s actual
  handling of a top-level array under `--skeptic-*` to confirm whether this
  is a crash or a silent-bypass risk.
- **Short-term (1wk)**: If the `construct.yaml` `compose_with:` overlay and
  the `.event`/`.type` event-key fallbacks were genuinely obsolete (per the
  PR's "revert to manifest-only form" framing), confirm no in-repo
  `construct.yaml` currently uses them before merging, since this diff
  otherwise removes their effect with no deprecation warning.

## Overall Risk Level: MEDIUM-HIGH

The change set is small, but two of its three deletions remove
purpose-built error handling for previously-identified failure modes in
components that back this repository's own security-review/consensus
machinery (Flatline, cheval). Recommend changes required before merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
