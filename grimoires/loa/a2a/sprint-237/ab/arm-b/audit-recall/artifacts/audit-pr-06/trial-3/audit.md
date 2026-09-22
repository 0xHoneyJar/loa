# Security Audit — chore(cheval,flatline,constructs): remove spawn-failure handlers, skeptic normalization and membrane overlays

**Scope**: Codebase audit of a single PR (no sprint plan / beads / a2a artifacts present). Three files touched:
- `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py`
- `head/.claude/scripts/flatline-orchestrator.sh`
- `head/.claude/scripts/construct-index-gen.sh`

**Method**: Read `head.diff` against `base/`/`head/` full file contents; traced call sites of each removed function within the three touched files. The consumers of these files' output (`loa_cheval`'s `_acquire_slot`/caller stack, the flatline `SCORING_ENGINE` binary, and any downstream reader of `construct-index.json`) are **not present in this workspace** — all three are out-of-repo for this audit, so impact on those consumers is stated as reasoned inference from the visible contracts, not confirmed by reading their code. This is noted per-finding.

---

## Findings

### 1. [HIGH] Removed `OSError`/`ValueError` handlers around the `claude -p` spawn — crash-on-failure instead of controlled provider fallback

**File**: `head/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:150-183`

The diff removes two `except` clauses that previously converted specific spawn-time failures into `ProviderUnavailableError` so the cheval fallback chain could advance:

```python
150:        start = time.monotonic()
151:        try:
152:            with _acquire_slot("claude-headless", n_slots=n_slots):
153:                try:
159:                    proc = run_subprocess_pgkill(
160:                        cmd,
161:                        timeout=timeout_s,
164:                        env=build_headless_subprocess_env(),
165:                    )
166:                except subprocess.TimeoutExpired:
...
171:                except SubprocessOutputCapExceeded as exc:
...
178:                except FileNotFoundError as exc:
179:                    raise ConfigError(
180:                        f"claude CLI not found on PATH (set CLAUDE_HEADLESS_BIN to override). "
181:                        f"Install with: npm install -g @anthropic-ai/claude-code. Original: {exc}"
182:                    ) from exc
183:        except _SemaphoreExhausted as exc:
```

Base (`base/.claude/adapters/loa_cheval/providers/claude_headless_adapter.py:180-190`) additionally caught, in the same position:

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

`subprocess.run`/`Popen` (which `run_subprocess_pgkill` wraps, per the inline comment at `head/…:153-155`) is documented to raise a bare `OSError` for exec-time failures (`E2BIG`/`ARG_MAX` overflow, `ENOMEM`, permission/exec errors) and a `ValueError` when argv contains an embedded NUL byte, which the CPython posix spawn path (`_posixsubprocess.fork_exec`) rejects before exec. Neither exception class is a subclass of any of the three still-caught types (`subprocess.TimeoutExpired`, `SubprocessOutputCapExceeded`, `FileNotFoundError` — `FileNotFoundError` is only raised pre-exec when the binary path itself doesn't resolve, a different condition from an exec-time OSError).

**Failure scenario**: the prompt text handed to this adapter is built from upstream artifacts the pipeline is specifically designed to be adversarial-tolerant of — skeptic/review transcripts, diff content, construct manifests — i.e., content that can originate from an untrusted PR under review. A sufficiently large assembled prompt (pushing `cmd` past `ARG_MAX`) or a prompt containing an embedded NUL byte (e.g., copied verbatim from a crafted file, log, or model output containing binary/control bytes) now raises an **uncaught** `OSError`/`ValueError` that propagates out of `_acquire_slot`'s context manager and out of this method entirely, instead of becoming a `ProviderUnavailableError` the cheval fallback chain is built to catch and route around. The flatline/cheval consensus pipeline exists precisely to survive a single provider failing; this regression turns one class of provider failure (input-shape-triggered) into a hard crash of the orchestrating process rather than a graceful failover — an availability regression reachable with content the pipeline is explicitly designed to treat as untrusted.

**Standard**: [CWE-248: Uncaught Exception](https://cwe.mitre.org/data/definitions/248.html) (denial of service via unhandled exception on adversarial input); relevant per [OWASP A04:2021 – Insecure Design](https://owasp.org/Top10/A04_2021-Insecure_Design/) in that the pipeline's own resilience design (fallback chain) is what's being bypassed.

**Remediation**: Restore the two removed `except` clauses (or a combined `except (OSError, ValueError) as exc:` if the intent is to simplify), preserving the distinct diagnostic messages — they identify materially different root causes (`ARG_MAX`/`ENOMEM` vs. embedded NUL) that matter for operator triage.

---

### 2. [HIGH] Removed `normalize_skeptic_envelope` — skeptic concern shape no longer enforced before reaching the scoring engine

**File**: `head/.claude/scripts/flatline-orchestrator.sh:295-298` (removal site — `extract_json_content` now falls straight through to `log_trajectory`, with no envelope normalization in between), consumed at `head/.claude/scripts/flatline-orchestrator.sh:1597-1598` and `head/.claude/scripts/flatline-orchestrator.sh:1626-1627`.

Base defined (`base/.claude/scripts/flatline-orchestrator.sh:294-317`):

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

and called it on every skeptic-prepared file right after `extract_json_content`:

```bash
extract_json_content "$gpt_skeptic_file" '{"concerns":[]}' > "$gpt_skeptic_prepared"
extract_json_content "$opus_skeptic_file" '{"concerns":[]}' > "$opus_skeptic_prepared"
normalize_skeptic_envelope "$gpt_skeptic_prepared"
normalize_skeptic_envelope "$opus_skeptic_prepared"
```

`extract_json_content` (`head/.claude/scripts/flatline-orchestrator.sh:261-295`) only unwraps markdown fences / BOM / prose via `normalize_json_response` — it does not enforce that the resulting JSON is an *object* with a `concerns` key. The removed function was the only guarantee that a skeptic model responding with a bare array (`["concern 1", "concern 2"]`) or a non-object scalar got coerced into the `{"concerns": [...]}` shape the scoring engine (`$SCORING_ENGINE`, invoked at `head/.claude/scripts/flatline-orchestrator.sh:1630-1638` with `--skeptic-gpt`/`--skeptic-opus`/`--skeptic-tertiary`) expects.

**Failure scenario**: this is the skeptic path — flatline's dedicated adversarial-dissent mechanism for surfacing concerns/blockers a plain review pass might miss (see `.loa.config.yaml`'s `flatline_protocol.security_audit` gate this very skill depends on). If a skeptic-role model returns its concerns as a top-level array instead of `{"concerns": [...]}` — a plausible format drift, since nothing in this diff's visible surface constrains the model's output shape — the prepared file now silently retains the array shape. Whatever the scoring engine's `--skeptic-*` JSON parsing does with a shape it doesn't expect (silently read `.concerns` as `null`/empty, or error) either drops the skeptic's blockers unnoticed or hard-fails the consensus phase; either way, the safety net this code exists to provide is weakened without any visible error, log line, or fallback default at this layer. `$SCORING_ENGINE` itself is not in this workspace, so the exact downstream behavior can't be directly confirmed — flagged as `[ASSUMPTION]` bridging that gap — but the removed function's entire purpose was to make this exact shape guarantee, and nothing replaces it.

**Standard**: [CWE-390: Detection of Error Condition Without Action](https://cwe.mitre.org/data/definitions/390.html) — a shape mismatch that previously self-healed now propagates silently; relevant to [OWASP A09:2021 – Security Logging and Monitoring Failures](https://owasp.org/Top10/A09_2021-Security_Logging_and_Monitoring_Failures/) in that a security-review signal (skeptic concerns) can be silently lost with no logged warning (contrast with `extract_json_content`'s own `log "WARNING: ..."` on its failure paths, which this removal has no equivalent of).

**Remediation**: Restore `normalize_skeptic_envelope` and its three call sites, or fold the same `type == "object" / array / else` coercion directly into `extract_json_content`'s default-handling path for the skeptic call sites specifically.

---

### 3. [LOW] `construct.yaml` overlay for `events.emits`/`events.consumes`/`compose_with` silently reverted to manifest-only + auto-computed values

**File**: `head/.claude/scripts/construct-index-gen.sh:302-303`, `:396`, `:404-426`

Three related reversions:

- `emits_json`/`consumes_json` (`:302-303`) now extract only `.name` (emits) / `.event` (consumes) from the pack manifest, dropping the base version's fallback chain (`.name // .event // .type` and `.event // .name // .type` respectively). A manifest using an alternate key name for an event now silently yields an empty entry instead of the value.
- The `construct.yaml` overlay block (`:310-336`) no longer reads `.compose_with[].slug` or `.events.emits`/`.events.consumes` from `construct.yaml` at all — those fields, if a construct author declares them, are now silently ignored; the entry is hardcoded to `composes_with: []` at `:396` before the later composition pass runs.
- `compute_composition()` (`:404-426`) now *replaces* `composes_with` with only the write/read-overlap-inferred list (`:414-422`), whereas the base version unioned the inferred list with whatever was already declared (`($current.composes_with // [])`, base `:428-437`). Any `compose_with` a construct author explicitly declared in `construct.yaml` is now unconditionally dropped even though the surrounding code no longer populates it from anywhere else either.

**Failure scenario**: this is a metadata-generation script, not a runtime security boundary, and `writes`/`reads`/`gates` (the fields most likely to matter for permission/trust decisions elsewhere in the framework) are unaffected — only `events.emits`/`events.consumes`/`composes_with` are impacted. The practical effect is silent data loss in the generated `construct-index.json`: a construct author's explicit `compose_with` declaration or non-`.name`/`.event`-keyed event manifest entries vanish from the index with no warning, which could mislead any downstream tooling or reviewer that treats `composes_with`/`events` in the index as authoritative when deciding which constructs compose safely. No exploitable path was identified; flagged as a correctness/observability regression rather than a vulnerability.

**Standard**: [CWE-1078: Inappropriate Source Code Style or Formatting](https://cwe.mitre.org/data/definitions/1078.html) doesn't quite fit; more precisely this is silent data loss with no CWE-specific classification — noted under general data-integrity concerns.

**Remediation**: If this is an intentional simplification (e.g., the overlay/union logic was found to produce incorrect graphs), state that rationale in the PR description — currently it reads as an accidental revert bundled with the other two removals, since the PR title only describes it as "reverts ... to the manifest-only form" without justification. If unintentional, restore the base behavior.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 0 |
| Low | 1 |

## Observations

None excluded from the tally — all three findings above are reported at their assessed severity.

## Verdict

**CHANGES_REQUIRED** — two HIGH findings (Findings 1 and 2) each remove a defensive mechanism that was added to handle a previously-identified failure mode (the code comments and error-message text in the `base/` versions make clear these were deliberate additions — "ARG_MAX / ENOMEM / exec error", "embedded NUL in the prompt", the skeptic-envelope shape coercion), and the PR description does not explain why reverting them is now safe. Recommend restoring Findings 1 and 2's removed code (or providing an explicit rationale for why the failure modes they guarded against are no longer reachable) before merge. Finding 3 is a quality/observability issue that should be called out to the PR author but does not block on its own.

### Recommendations

- **Immediate (24h)**: Restore the `OSError`/`ValueError` handlers in `claude_headless_adapter.py` and `normalize_skeptic_envelope` (or equivalent) in `flatline-orchestrator.sh`, or get an explicit sign-off in the PR description explaining why the guarded failure modes are no longer possible.
- **Short-term (1wk)**: Clarify whether the `construct-index-gen.sh` reversion (Finding 3) is intentional; if so, document it, if not, restore the overlay/union behavior.
- **Long-term (1mo)**: Given all three removals in this PR reduce defensive/normalization code that was added deliberately (per the surrounding comments), consider a lint or PR-template checklist item requiring an explicit "why is this safe to remove" note whenever a diff deletes an `except` clause or a `normalize_*`/coercion helper, to keep this class of silent regression from landing without discussion.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":0,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
