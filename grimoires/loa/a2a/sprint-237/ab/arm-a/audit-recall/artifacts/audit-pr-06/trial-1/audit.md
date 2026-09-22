# Security Audit Report

**PR**: `chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays`
**Audit type**: Ad-hoc PR audit (no sprint/beads context — PR files are the entire input)
**Auditor**: auditing-security skill
**Date**: 2026-09-21

## Executive Summary

This PR removes three defensive mechanisms that were previously added to the multi-model
orchestration path (`loa_cheval` headless adapter, Flatline consensus orchestrator, and
construct-index generator), reverting each to an earlier, less-defensive form. None of the
changes touch authentication, secrets, or command construction directly, but two of the three
regressions sit directly on the error-handling and input-normalization path of the framework's
**security review machinery itself** (the Flatline adversarial-review / multi-model chain-walk
system that this very skill's "Phase 1C Security Dissenter Analysis" depends on). Silently
degrading that machinery's robustness to malformed or hostile model output is a materially
different risk class than removing defensive code in an ordinary feature path, because a failure
here can suppress or crash the exact mechanism meant to catch security regressions in other PRs.

The third change (construct-index-gen.sh) is a straightforward metadata/data-loss regression in
non-security-critical fields (`events`, `composes_with`) — `writes`/`reads`/`gates`, the fields
that actually gate permissions, are untouched.

## Overall Risk Level: MEDIUM-HIGH

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## High Priority Issues

### H-1: Removal of `OSError`/`ValueError` handlers breaks the adapter's error contract, allowing raw exceptions to escape the multi-model chain-walk path

**Component**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:159-182`

```python
159:                    proc = run_subprocess_pgkill(
160:                        cmd,
161:                        timeout=timeout_s,
162:                        # cycle-109 follow-up (#879 / #880): strip ANTHROPIC_API_KEY
163:                        # so claude -p uses OAuth subscription, not API mode.
164:                        env=build_headless_subprocess_env(),
165:                    )
166:                except subprocess.TimeoutExpired:
167:                    raise ProviderUnavailableError(
168:                        self.provider,
169:                        f"claude -p timed out after {timeout_s:.0f}s",
170:                    )
171:                except SubprocessOutputCapExceeded as exc:
...
178:                except FileNotFoundError as exc:
179:                    raise ConfigError(
180:                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
181:                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
182:                    ) from exc
```

**Description**: The diff deletes the two `except` clauses (formerly present immediately after
`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:182`, see
`base/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:188-197`) that converted
a bare `OSError` (ARG_MAX / ENOMEM / exec errors from `run_subprocess_pgkill`) and a bare
`ValueError` (an un-executable argv, e.g. an embedded NUL byte in the prompt) into the adapter's
own `ProviderUnavailableError`. `complete()` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:118`)
has no other handler for these exception types — `FileNotFoundError` is caught separately at
line 178, and the outer `except _SemaphoreExhausted` at line 183 does not match `OSError` or
`ValueError`. The result is that these two failure classes now propagate out of `complete()` as
raw, framework-specific-unaware Python exceptions instead of the adapter contract's
`ProviderUnavailableError`.

**Impact**: Per this repository's own documentation (`CLAUDE.loa.md` "Multi-Model Activation"),
the `cheval` substrate is "the unconditional dispatch path for all multi-model consumers (BB,
Flatline, Red-team, adversarial-review, post-pr-triage)" and performs "chain-walk on retryable
errors" plus emits a "verdict-quality envelope on every output." Chain-walk logic in a
multi-provider dispatcher typically distinguishes retryable provider failures from programming
errors by catching the adapter's own exception types (`ProviderUnavailableError`/`ConfigError`).
An adapter that leaks raw `OSError`/`ValueError` instead breaks that contract: the dispatcher
either (a) fails to catch it and the whole multi-model invocation crashes uncaught — aborting an
adversarial-review or audit run mid-flight without ever writing its MODELINV/verdict-quality
envelope, which the framework states should exist "on every output" — or (b) is caught by a
broader `except Exception` somewhere upstream that treats it identically to a benign,
non-retryable error, silently dropping what should have been a retryable chain-walk case (a
transient ENOMEM should not permanently sideline a provider the way a config error should).
Either path degrades the reliability of the security-review pipeline itself.

**Exploitability note**: `ValueError` here is explicitly documented as covering "embedded NUL in
the prompt" (see the removed handler's message in
`base/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py`). Prompts built from
`request.messages` (`head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:123`)
can include untrusted content under review (PR diffs, model output, user-controlled text). Content
containing an embedded NUL — plausible in binary-adjacent diffs or adversarially crafted input
being fed to the very reviewer meant to catch it — can now crash the invocation path instead of
being classified and gracefully failed over, which is a self-defeating failure mode for a
security-review subsystem: an attacker-influenced input can disrupt the review mechanism instead
of merely failing one provider in the fallback chain.

**Remediation**: Restore the two removed `except OSError` / `except ValueError` handlers (or
replace them with an equally-specific classification) so that every failure mode from
`run_subprocess_pgkill` is normalized to the adapter's documented exception contract
(`ProviderUnavailableError`/`ConfigError`) before it can escape `complete()`. If the intent was
to simplify because these paths were believed unreachable, that assumption should be justified
in the PR description with evidence (e.g., that `run_subprocess_pgkill` cannot raise bare
`OSError`/`ValueError` for these causes), not asserted implicitly by deletion.

**References**: CWE-755 (Improper Handling of Exceptional Conditions), OWASP A09:2021
(Security Logging and Monitoring Failures — loss of the audit/MODELINV envelope on crash).

## Medium Priority Issues

### M-1: Removal of `normalize_skeptic_envelope` allows non-conforming skeptic output to reach the Flatline consensus/scoring engine unsanitized

**Component**: `head/.claude/scripts/flatline-orchestrator.sh:1594-1598` (and the tertiary path at
`head/.claude/scripts/flatline-orchestrator.sh:1622-1629`)

```python
1594:    local gpt_skeptic_prepared="$TEMP_DIR/gpt-skeptic-prepared.json"
1595:    local opus_skeptic_prepared="$TEMP_DIR/opus-skeptic-prepared.json"
1596:
1597:    extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
1598:    extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"
```

**Description**: `extract_json_content` (`head/.claude/scripts/flatline-orchestrator.sh:261-295`)
only strips markdown fences/BOM/prose wrapping via `normalize_json_response` and falls back to
the caller-supplied default (`{"concerns":[]}`) solely when normalization *fails outright* or the
`.content` field is empty. It does **not** enforce that the resulting JSON is shaped as an object
with a `concerns` key. Previously, `normalize_skeptic_envelope()` (removed; formerly at
`base/.claude/scripts/flatline-orchestrator.sh:297-317`, called at the two sites now at
`head/.claude/scripts/flatline-orchestrator.sh:1597-1598` and the tertiary call site now at
`head/.claude/scripts/flatline-orchestrator.sh:1626`) provided that guarantee: it re-wrapped a
top-level JSON array into `{"concerns": [...]}` and coerced any other non-object shape to
`{"concerns":[]}`. That guarantee is now gone. If a skeptic model returns a bare JSON array (e.g.
`["concern A", "concern B"]`) or another valid-but-non-object JSON value — plausible LLM output
drift, not a hypothetical — the "prepared" file written to
`$TEMP_DIR/gpt-skeptic-prepared.json`/`opus-skeptic-prepared.json`/`tertiary-skeptic-prepared.json`
now carries that shape unchanged into `--skeptic-gpt`/`--skeptic-opus`/`--skeptic-tertiary`
arguments passed to `"$SCORING_ENGINE"` (`head/.claude/scripts/flatline-orchestrator.sh:1636-1637`).

**Impact**: `scoring-engine.sh` is not part of this PR's touched files, so its exact handling of a
malformed skeptic envelope cannot be directly verified from this diff alone — flagging this as an
area requiring manual verification against that script. However, the skeptic/"concerns" channel
is specifically the adversarial-dissent input that can produce a Flatline `BLOCKER` verdict
(`CLAUDE.loa.md`: "Flatline Protocol... BLOCKER halts autonomous workflows"). If the consumer
expects an object and receives an array (or vice-versa), the most likely outcomes are either a
hard failure of the consensus computation (aborting the review before a verdict is produced) or a
silently-empty concerns list being treated as "no concerns raised" — a false negative in exactly
the mechanism designed to catch dangerous changes. Given that this orchestrator is invoked as part
of the mandatory Security Dissenter Analysis this very skill runs (per `auditing-security`
Phase 1C), a defect that can cause it to lose or misinterpret skeptic concerns is security-relevant
by construction, not merely a code-quality nit.

**Remediation**: Restore `normalize_skeptic_envelope` (or fold its guarantee into
`extract_json_content` when a schema/`agent` hint indicates skeptic-shaped output) before removing
it, or provide evidence that `$SCORING_ENGINE` already tolerates non-object skeptic JSON. Given
"do not skip pre-flight" concerns don't apply here, the safer default is to keep the normalization
step; it is cheap (a single `jq` call) and defends a value that directly affects verdicts.

**References**: CWE-20 (Improper Input Validation), OWASP A04:2021 (Insecure Design — silent
failure mode in a security-decision input).

## Low Priority Issues

### L-1: `construct-index-gen.sh` drops explicit `compose_with` overlay and narrows event-name extraction (data-loss, not a permission/gate regression)

**Component**: `head/.claude/scripts/construct-index-gen.sh:301-303`, `:306-308`, `:396`

```python
301:    local emits_json consumes_json
302:    emits_json=$(jq -c '.events.emits // [] | [.[].name // empty]' "$manifest" 2>/dev/null || echo "[]")
303:    consumes_json=$(jq -c '.events.consumes // [] | [.[].event // empty]' "$manifest" 2>/dev/null || echo "[]")
304:
305:    # Initialize overlay fields
306:    local writes_json="[]"
307:    local reads_json="[]"
308:    local gates_json="{}"
```

and

```python
396:            composes_with: [],
```

**Description**: The extraction of `emits`/`consumes` event names is narrowed from
`(.name // .event // .type)` (accepting three alternative key names) to `.name`-only /
`.event`-only (base:
`base/.claude/scripts/construct-index-gen.sh:302-303`, head as above). Separately, the
`construct.yaml` overlay handling at `head/.claude/scripts/construct-index-gen.sh:311-336` no
longer reads an explicit `compose_with` list from `construct.yaml`
(`base/.claude/scripts/construct-index-gen.sh:329` `compose_with_json=...[.compose_with[].slug]`,
removed) nor lets `construct.yaml` override the manifest's `events.emits`/`events.consumes`
(`base/.claude/scripts/construct-index-gen.sh:331-335` `cy_emits`/`cy_consumes`, removed). The
per-entry `composes_with` field is now unconditionally initialized to `[]`
(`head/.claude/scripts/construct-index-gen.sh:396`) and is populated only by the automatic
write/read-overlap inference in `compute_composition()`
(`head/.claude/scripts/construct-index-gen.sh:404-420`), which still functions correctly on the
narrower input.

**Impact**: This is a functionality/data-loss regression: any manifest that used `.type` (rather
than `.name`/`.event`) for event identification, or any `construct.yaml` that declared an
explicit `compose_with:` or an event-name overlay, will silently lose that information in the
generated construct index rather than erroring. The fields that actually gate write permissions
— `writes`, `reads`, `gates` (`head/.claude/scripts/construct-index-gen.sh:306-308,326-328`) —
are untouched by this diff, so this does not by itself weaken an access-control boundary. It is
flagged at LOW severity because `composes_with`/`events` are discovery/documentation metadata in
the construct index; if any downstream consumer treats `composes_with` as an authorization
allow-list rather than pure metadata, this would need to be re-classified upward — that could not
be confirmed from the files in this PR's scope.

**Remediation**: If this is an intentional simplification back to "manifest-only" composition (as
the PR description states), confirm no `construct.yaml` in the repository currently relies on the
removed `compose_with`/event-overlay keys, and confirm no consumer treats `composes_with` as a
security boundary rather than metadata, before merging.

**References**: CWE-1078 (n/a — general data-integrity note, not a standard CWE-classified
vulnerability).

## Security Checklist Status

- [ ] Error handling preserves fail-safe classification of provider/subprocess failures (H-1)
- [ ] Adversarial-review input normalization preserved (M-1)
- [x] Secrets/credentials handling — unaffected by this diff
- [x] Injection (command/SQL/template) — unaffected; no new string-built commands introduced
- [x] Permission/gate fields (`writes`/`reads`/`gates`) — unaffected (L-1 confirms this)
- [ ] Data-loss / silent-degradation review for removed overlay logic (L-1)

## Threat Model Summary

The primary threat modeled here is not an external attacker directly compromising this code, but
this PR **degrading the framework's own defense-in-depth around its multi-model security-review
machinery** — the chain-walk fallback contract (H-1) and the skeptic/BLOCKER input channel (M-1).
Both are on the critical path of Flatline adversarial review and the mandatory Security Dissenter
Analysis this skill itself performs, so a defect here has second-order impact on every future PR's
review quality, not just this one.

## Verdict

**CHANGES_REQUIRED**

H-1 and M-1 should be addressed (or explicitly justified with evidence that the removed
handling is provably unreachable/redundant) before this PR merges, given both sit on the
multi-model security-review dispatch path. L-1 should be confirmed safe (no consumer depends on
the removed overlay behavior as a security boundary) but does not block on its own.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"N/A","ts":"2026-09-21T00:00:00Z"} -->
