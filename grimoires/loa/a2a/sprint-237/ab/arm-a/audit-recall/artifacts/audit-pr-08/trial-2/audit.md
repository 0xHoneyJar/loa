# Security Audit Report

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present — audited directly from `PR.md` + `head.diff` + `base/`/`head/` snapshots)
**Scope**: `.claude/scripts/ledger-lib.sh`, `tools/check-no-swallowed-jq.sh`, `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py`
**PR**: "chore(ledger,tools,cheval): lighter ledger content check, simpler heredoc skipping, fewer except clauses"

## Executive Summary

This PR presents itself as a pure simplification ("lighter", "simpler", "fewer"), but each of its three hunks removes a piece of defense-in-depth that was added deliberately, with a documented incident behind it, and each removal reintroduces a variant of the exact failure it was protecting against. The ledger-content guard is weakened from "exactly one JSON object" back to "any parseable JSON stream", which lets `_write_ledger` silently corrupt `ledger.json` into multiple concatenated JSON documents — the same class of silent, caller-visible-as-success corruption that bug `20260808-a008c6` (cited in the PR's own retained comment) was written to prevent. The `check-no-swallowed-jq.sh` heredoc simplification removes the executed-vs-fixture distinction entirely, creating a blind spot in a tripwire that exists specifically to catch silent-failure/false-clean gate results (KF-004/KF-015) in the four gate-critical scripts it enforces. The `agy_headless_adapter.py` change removes the `ValueError` handler around subprocess exec, so a NUL byte in an oversized/adversarial prompt now raises an unhandled exception instead of `ProviderUnavailableError`, breaking the "chain-walk on retryable errors" guarantee this repo's own instructions declare unconditional for the multi-model dispatch path (BB, Flatline, red-team, adversarial-review, post-pr-triage).

None of the three changes are justified by the PR description or by any test/behavior change described in the diff; they read as scope creep on top of legitimate simplification, and two of the three re-open previously-fixed bug classes.

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 1 |
| Low | 0 |

## High Priority Issues

### H-1: Ledger write guard no longer rejects multi-document / non-object JSON, reintroducing silent ledger corruption

**Component**: `head/.claude/scripts/ledger-lib.sh:157-158` (guard), `head/.claude/scripts/ledger-lib.sh:179` (stamping)

```
157	    if [[ -z "$content" ]] || ! echo "$content" | jq empty 2>/dev/null; then
158	        echo "ERROR: refusing to write empty or unparseable ledger content" >&2
```
and
```
179	    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
```

**What changed**: The base version's guard was
`printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")'` — it slurps the input (`-s`) into a single array and requires exactly one element that is a JSON object. The head version replaced this with `jq empty`, which only validates that the input is a stream of zero-or-more syntactically valid JSON values — it does not require exactly one value, and does not require that value to be an object.

**Impact**: `jq` (without `-s`) applies its filter independently to *each* JSON value in a multi-document input stream and prints one output per value. If `_write_ledger` is ever called with content that is two (or more) concatenated JSON objects — e.g. from a caller that accidentally double-emits, from a `cat`'d fragment, or from any bug in an upstream caller that constructs `content` — the new guard at line 157 accepts it (each object individually parses fine under `jq empty`), and the stamping step at line 179 then emits **multiple** `{"...", "last_updated": "..."}` documents concatenated in `$updated_content`, which is written verbatim to `ledger.json` (see `mv "$tmp_file" "$ledger_path"` further down). This corrupts the ledger into a non-single-JSON-document file while `_write_ledger` still returns success (`$LEDGER_OK`) — exactly the "every caller reported success" failure mode called out in the retained comment two lines above (`bug 20260808-a008c6`). Every downstream reader that does `jq -r '.field' "$ledger_path"` (used throughout this file, e.g. `jq -r '.version // "missing"'` pattern used elsewhere) will silently read only the first document and ignore the rest, or behave unpredictably depending on which consumer reads the file.

Reproduced during this audit: given a file with two concatenated JSON objects, `jq empty` exits 0, and `jq --arg ts X '.last_updated=$ts'` on that same file produces two stamped objects, not one.

The original fix (`jq -es 'length == 1 and (.[0] | type == "object")'`) exists precisely to make this shape rejected; the new `jq empty` guard does not preserve that property despite the surrounding comment (`# GUARD (bug 20260808-a008c6): refuse empty/unparseable content BEFORE touching lock, backup, or ledger`) being left in place and now describing a guarantee the code no longer provides. Additionally, a bare JSON scalar (e.g. `"x"` or `42` or `null`) now also passes the guard at line 157 where it previously did not; those cases happen to be caught later by the `[[ -z "$updated_content" ]]` check at the empty-content failure branch (jq errors indexing a scalar with `.last_updated`, producing empty `updated_content`), so they are not silently corrupting — the exploitable gap is specifically the multi-document case.

**Remediation**: Restore the single-object requirement, e.g. revert to
`printf '%s' "$content" | jq -es 'length == 1 and (.[0] | type == "object")'`
(or equivalently `jq -e 'type == "object"' <<< "$content"` combined with a document-count check such as piping through `jq -s 'length == 1'`). If the intent was genuinely just to drop the "must be an object" requirement (not stated in the PR description), at minimum restore `-s`/slurp semantics so multi-document input is rejected rather than silently multiplied through the stamping step.

**References**: CWE-704 (Incorrect Type Conversion or Cast) / OWASP A04:2021 (Insecure Design — the guard's postcondition no longer matches its stated purpose); this repo's own precedent at `.claude/rules/stash-safety.md` and `known-failures.md` KF-004/KF-015 for "operation reports success while corrupting/losing state."

---

### H-2: `check-no-swallowed-jq.sh` now blanket-skips all heredoc bodies, regardless of whether they are executed — blind spot in a gate-critical tripwire

**Component**: `head/tools/check-no-swallowed-jq.sh:130-139` (heredoc-body handling), contrast with `base/tools/check-no-swallowed-jq.sh:127-187` (removed `hd_exec`/`_hd_command` logic)

```
130	in_heredoc {
131	    if ($0 == hd_term) { in_heredoc = 0; next }
132	    if (hd_dash) {
133	        no_tabs = $0
134	        gsub(/^\t+/, "", no_tabs)
135	        if (no_tabs == hd_term) { in_heredoc = 0; next }
136	    }
137	    next
138	}
```

**What changed**: The base version computed `hd_exec` per heredoc — true when the heredoc's terminator word was unquoted, or when the command preceding the heredoc redirection was a known interpreter (`sh`, `bash`, `zsh`, `python`, `perl`, `node`, etc. via the `INTERP` table and `_hd_command()`), or when the heredoc was piped into such an interpreter. Only when `hd_exec` was true did the scanner continue to check lines *inside* the heredoc body for the swallowed-jq pattern (`if (hd_exec) { ... if (_line_has_swallowed_jq($0)) print ... }`). Lines inside a heredoc that was pure static text (e.g. a quoted-terminator fixture, `<<'EOF'`, or documentation block) were correctly skipped.

The head version deletes `hd_exec`, `_hd_command`, and the `INTERP` table entirely. Every line inside *any* heredoc — executed or not — now hits the unconditional `in_heredoc { ... next }` block and is skipped from scanning, with no distinction based on whether the heredoc content is ever run.

**Impact**: This tool's entire purpose (per its own header, lines 4-16) is to tripwire the `jq ... || echo <default>` silent-failure shape in `ENFORCED_FILES` (`adversarial-review.sh`, `flatline-orchestrator.sh`, `scoring-engine.sh`, `post-pr-triage.sh`) and `red-team-*` scripts — the scripts that back this repo's multi-model verdict pipeline (per `CLAUDE.loa.md`: "verdict-quality envelope on every output — `status: clean | APPROVED` is impossible when verdict quality is degraded"). Any of those scripts that constructs and executes a script via heredoc (a common shell pattern — e.g. `bash <<EOF ... jq -r '.verdict' out.json || echo "clean" ... EOF`, or a heredoc piped to `ssh host` / `python3` / `node`) now has its body completely invisible to the scanner, including genuine `jq ... || echo`/`|| printf` swallow occurrences. Previously such executed-heredoc content was exactly the case the `hd_exec` branch was added to catch (the base code's `hd_exec` computation explicitly treats an unquoted-terminator or interpreter-piped heredoc as "will run, must scan"). The stated rationale for the change ("Without this, `--root` scans of bats tests can flag planted bad examples instead of executable scanner code") only supports skipping *non-executed, fixture/documentation* heredocs (which `hd_exec` already handled by being false for quoted terminators / non-interpreter commands) — it does not support skipping executed heredocs, which the new code also does.

This is a silent regression in a security-tooling detector: it will not fail any existing test (bats fixtures presumably use quoted terminators, which were already skipped under the old logic too), but it removes real detection coverage for the exact swallow pattern the tool exists to catch, in a class of file (gate-critical, verdict-bearing) that this repo's own conventions treat as maximally sensitive.

**Remediation**: Restore the `hd_exec` determination (executed heredoc = unquoted terminator, or heredoc piped/redirected into a known shell/script interpreter) and continue scanning heredoc bodies when `hd_exec` is true, exactly as the base version did. If the goal is specifically to suppress bats-fixture false positives, scope the suppression to quoted-terminator heredocs (`<<'EOF'`) only, which was already the base behavior's effect for static fixtures — do not widen it to all heredocs.

**References**: CWE-693 (Protection Mechanism Failure) — the detector class itself is degraded; this repo's own `known-failures.md` KF-004/KF-015 describe exactly the failure mode (silent-clean verdict) this tool exists to prevent, and this change reopens the detection gap for it.

## Medium Priority Issues

### M-1: `except ValueError` removed from `agy` exec path — embedded-NUL prompts now crash instead of chain-walking

**Component**: `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157-165` (surviving `OSError` handler, with the removed `ValueError` handler previously immediately following it), contrast with `base/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:163-172`

```
157	                except OSError as exc:
158	                    # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
159	                    # --prompt-file exists) or another exec failure → WALK the chain,
160	                    # never crash with a raw OSError. The gemini-api HTTP fallback
161	                    # covers oversized diffs. (FileNotFoundError is handled above.)
162	                    raise ProviderUnavailableError(
163	                        self.provider,
164	                        f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
165	                    ) from exc
166	        except _SemaphoreExhausted as exc:
```

**What changed**: The base version additionally caught `ValueError` immediately after the `OSError` handler and converted it into `ProviderUnavailableError(self.provider, f"agy -p got un-execable argv (embedded NUL in the prompt?): {exc}")`. The head version deletes that handler outright; there is no other `except ValueError` anywhere else in this method or its enclosing `try` blocks (the only outer handler is `except _SemaphoreExhausted` at line 166, a different exception type).

**Impact**: CPython's subprocess machinery raises `ValueError` (not `OSError`) when argv/env contains an embedded NUL byte, which is a real, reachable condition here since `prompt` is built from `request.messages` — i.e., from PR-diff / review content that this adapter is invoked on (per its own docstring, this is the `agy` headless provider used by the cheval multi-model substrate for adversarial review / audit / red-team dispatch). A prompt containing an embedded NUL byte (plausible in diffs touching binary content, or from adversarially-crafted input given this is explicitly a "dual-use"-adjacent security review pipeline) now propagates an unhandled `ValueError` out of `_invoke_agy`/`_invoke` uncaught by any of the surrounding `except` clauses, instead of being converted into `ProviderUnavailableError` and chain-walked to the next provider. This breaks the repo's own stated invariant for this exact dispatch path: `CLAUDE.loa.md` → Multi-Model Activation: "chain-walk on retryable errors; voice-drop on chain exhaustion (never cross-company substitution)". An unhandled exception here does not chain-walk — it crashes the calling review/audit/red-team invocation instead of falling back to the next model in the chain, which is a reliability regression for the quality-gate pipeline (worse verdict availability), not a memory-safety or injection vulnerability per se.

**Remediation**: Restore the `except ValueError as exc: raise ProviderUnavailableError(...)` handler removed from this method, or fold NUL-byte detection into the existing `OSError` handler with an explicit `except (OSError, ValueError) as exc:` if the intent is to consolidate exception handling (the PR description says "removes the ValueError handler" with no stated reason — if this was accidental scope creep from an unrelated cleanup, revert it outright).

**References**: CWE-248 (Uncaught Exception) — this is a resilience/availability regression against the repo's declared chain-walk contract, not a direct exploit primitive.

## Security Checklist Status

- [x] Secrets & credentials — N/A, none touched by this diff
- [ ] Input validation — FAIL (H-1: ledger content validation weakened)
- [x] Authentication & authorization — N/A, none touched by this diff
- [ ] Error handling — FAIL (M-1: exception handling narrowed on an untrusted-input-adjacent path)
- [ ] Supply chain / tooling integrity — FAIL (H-2: security tripwire detection coverage reduced)
- [x] Injection — N/A, no new injection surface introduced (jq/shell quoting unchanged in the affected lines beyond the `printf` → `echo` reversion noted below)

**Note (not separately scored, folded into H-1 discussion)**: `head/.claude/scripts/ledger-lib.sh:157` and `:179` also revert `printf '%s' "$content"` back to `echo "$content"`. `echo` (particularly the bash builtin) can interpret a leading `-e`/`-n`/`-E` in `$content` as an option rather than data, mangling or dropping content that happens to start with those two characters — `printf '%s'` does not have this hazard. This alone would only be Low severity, but it stacks with H-1's loss of the object/single-document guarantee.

## Overall Risk Level: **HIGH**

Two of the three changes (H-1, H-2) reopen previously-fixed, previously-incident-tied failure classes in gate-critical / state-integrity code paths, and the PR description does not acknowledge or justify any of the three behavioral narrowings — it frames all three as neutral simplifications ("lighter", "simpler", "fewer") when in fact each removes a specific guarantee that was added for a specific, documented reason.

## Recommendations

**Immediate (before merge)**:
1. Revert the `_write_ledger` content guard to require a single JSON object (H-1).
2. Revert the heredoc `hd_exec` executed/static distinction in `check-no-swallowed-jq.sh` (H-2).

**Short-term**:
3. Restore the `ValueError` handler in `agy_headless_adapter.py`, or explicitly justify its removal with an argument for why embedded-NUL prompts can no longer occur (M-1).
4. Revert `echo "$content"` back to `printf '%s' "$content"` in the two call sites touched in `ledger-lib.sh` (noted under H-1).

## Verdict

**CHANGES_REQUIRED**

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":0},"sprint_id":"N/A","ts":"2026-09-22T00:00:00Z"} -->
