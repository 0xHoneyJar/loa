# Sprint 75 (Sprint 2) — Paranoid Cypherpunk Security Audit

**Auditor**: Paranoid Cypherpunk Auditor
**Date**: 2026-02-26
**Sprint**: 75 (cycle-041, Sprint 2 — Vision-Aware Active Presentation)
**Verdict**: APPROVED - LETS FUCKING GO

---

## Audit Scope

Security-focused review of content sanitization, shell injection surfaces, path traversal defenses, JSONL integrity, config parsing safety, flock atomicity, and test coverage for the Vision Registry active presentation layer.

### Files Reviewed

| File | Focus |
|------|-------|
| `.claude/scripts/vision-lib.sh` | Content sanitization (`vision_sanitize_text`), path traversal (`_vision_validate_dir`), atomic writes |
| `.claude/scripts/vision-registry-query.sh` | Shell injection via CLI args, JSONL append integrity, `yq` config parsing |
| `.claude/skills/discovering-requirements/SKILL.md` | Step 0.5 integration, template-based output (no LLM-fabricated relevance) |
| `tests/integration/vision-planning-integration.bats` | E2E coverage of security-critical paths |
| `tests/fixtures/vision-registry/entry-semantic-threat.md` | Adversarial fixture for case-insensitive injection |
| `tests/fixtures/vision-registry/entry-injection.md` | Original injection fixture (HTML entities, system/prompt tags, code fences) |

### Prior Review Acknowledgment

Senior technical lead review (engineer-feedback.md) returns "All good" with detailed task-by-task analysis confirming 63/63 tests passing. Two non-blocking portability observations noted (GNU sed `I` flag, dead code in regression test).

---

## Security Checklist

### [PASS] Content Sanitization — Injection Vector Coverage

**vision-lib.sh lines 323-375** — `vision_sanitize_text()` implements defense-in-depth:

1. **Primary defense** (line 331): `awk` allowlist extraction. Only text between `## Insight` and the next `## ` heading is extracted. Content outside this section (including `## Potential`, `## Connection Points`) is never passed through. This is the strongest control — even if all downstream filters fail, only the Insight section is exposed.

2. **HTML entity decode** (lines 338-347): Decodes `&lt;`, `&gt;`, `&amp;`, `&quot;` BEFORE tag stripping. This closes the classic double-encoding bypass (`&lt;system&gt;` decoded to `<system>` which is then caught by subsequent filters). Also strips zero-width characters (U+200B, U+200C, U+200D) and BOM (U+FEFF) which can be used to break pattern matching.

3. **Tag stripping — character-class patterns** (lines 351-354): Portable case-insensitive patterns using `[sS][yY][sS]...` for `<system>`, `<prompt>`, `<instructions>` tag pairs including content between open/close tags. Also strips code fences. These work on ALL sed implementations.

4. **Tag stripping — catch-all** (line 358): GNU sed `I` flag for remaining bare tags (`<context>`, `<role>`, `<user>`, `<assistant>`). Secondary defense — character-class patterns already caught the critical tags.

5. **Indirect instruction stripping** (line 361): Case-insensitive `grep -viE` removes entire lines containing: `ignore previous`, `forget all`, `you are now`, `act as`, `pretend to be`, `disregard`, `override`, `ignore all`, `ignore the above`, `do not follow`, `new instructions`, `reset context`. The `|| true` prevents `set -e` exit when grep finds zero matches.

6. **Truncation** (lines 367-372): Hard cap at 500 chars. Even if something slips through, the attack surface is bounded.

**Finding**: No gaps detected. The decode-then-strip ordering is correct. The allowlist extraction + blocklist stripping is the right layered approach. Case-insensitive coverage confirmed via both character-class patterns (portable) and `I` flag (GNU secondary).

**Test coverage**: `entry-injection.md` tests HTML entities + system/prompt/code-fence injection. `entry-semantic-threat.md` tests 10 case-insensitive semantic attack vectors (UPPERCASE, Mixed Case, Title Case variants). Unit test assertions verify all are stripped.

### [PASS] Path Traversal — `_vision_validate_dir()`

**vision-lib.sh lines 111-132**: Canonical path resolution via `cd "$dir" && pwd` followed by prefix check against `$PROJECT_ROOT`. The trailing-slash check on line 127 (`$canon_dir != "$canon_root"/*`) prevents the classic `/home/user/project-evil` matching `/home/user/project` attack.

**vision-registry-query.sh line 133-135**: Validates `--visions-dir` argument against `_vision_validate_dir()` when the directory exists.

**Finding**: Solid. Symlink traversal is also handled because `cd && pwd` resolves symlinks to their canonical target.

### [PASS] Shell Injection — Variable Quoting

**Systematic review of all `$()` expansions and variable usage**:

- All variables in `vision-registry-query.sh` argument parsing use `"${2:-}"` pattern (quoted with default).
- `jq` invocations use `--arg` parameter binding throughout (lines 227-234, 267, 272-282, 323-331, 337-341) — no raw interpolation into jq filter strings.
- `yq eval` on line 352 reads from the config file path, not from user input. The YAML key path is hardcoded (`'.vision_registry.shadow_cycles_before_prompt // 2'`).
- `sed` substitutions in `_do_update_status()` (lines 457-459) use `printf '%s' | sed 's/[\\/&]/\\\\&/g'` to escape sed metacharacters in vision ID and status — this prevents sed injection via crafted vision IDs.
- Tag validation (vision-registry-query.sh lines 121-130) enforces `^[a-z][a-z0-9_,-]*$` regex before any tag is used in operations.

**`xargs` usage** (lines 186-191, 264, 364, etc.): Used solely for whitespace trimming (`echo "$var" | xargs`). When the piped input comes from controlled sources (table columns parsed via `awk`, pre-validated tags), this is safe. `xargs` with no arguments just trims — it does not execute commands unless given `-I` or explicit command. The data flowing through `xargs` is either from the index.md table (which is project-owned, not user-uploaded) or from pre-validated tag strings. Acceptable risk level.

**Finding**: No shell injection vectors detected. All user-controllable inputs are validated before use.

### [PASS] JSONL Integrity — Shadow Log Append

**vision-registry-query.sh line 333**: `echo "$shadow_entry" >> "$shadow_log"` — bare append without flock.

**Risk assessment**: The shadow log is an append-only diagnostic log. It is written by a single-invocation script (not a daemon), called from the SKILL.md workflow which executes sequentially (one planning session at a time). Concurrent appends to the same JSONL file are theoretically possible if two planning sessions run simultaneously, but:

1. The log filename includes the date (`vision-shadow-{date}.jsonl`), so concurrent sessions on different days write different files.
2. `echo` of a single line followed by `\n` is atomic on Linux for writes under PIPE_BUF (4096 bytes). The compact JSON entry is well under this limit.
3. The shadow state file (`.shadow-state.json`) IS flock-guarded (lines 345-349), which is the critical state that must be consistent.

**Finding**: The JSONL append is practically atomic for the expected payload size. The shadow state update correctly uses `vision_atomic_write()` with flock. No corruption risk under normal usage.

### [PASS] Config Parsing — yq Injection

**vision-registry-query.sh line 352**: `yq eval '.vision_registry.shadow_cycles_before_prompt // 2' "${PROJECT_ROOT}/.loa.config.yaml" 2>/dev/null || echo "2"`

**SKILL.md lines 673, 693-695**: Multiple `yq eval` calls with hardcoded YAML key paths.

**Finding**: All `yq eval` calls use hardcoded key paths (string literals in single quotes). No user input is interpolated into yq expressions. The `2>/dev/null || echo "default"` pattern provides safe fallback for missing config. No injection possible.

### [PASS] Flock Race Conditions

**vision-lib.sh lines 144-159**: `vision_atomic_write()` uses `flock -w 5 200` with a 5-second timeout. The lock file is `${target_file}.lock`, colocated with the target.

- `_do_update_status()` (lines 456-474): Uses `sed ... > tmp && mv tmp orig` inside the flock — correct tmp+mv atomic replacement pattern.
- `_do_record_ref()` (lines 504-537): Same tmp+mv pattern inside flock.
- `_do_update_shadow_state()` (lines 336-343): Uses `> tmp && mv tmp orig` inside flock.

**Finding**: All mutating operations use the flock+tmp+mv pattern. The `exit 1` (not `return 1`) on flock failure (line 155) is correct because it's inside a flock subshell (per PR #215 convention). No TOCTOU windows detected within locked regions.

### [PASS] Test Coverage — Security-Critical Paths

| Security Path | Test | File |
|---------------|------|------|
| Content sanitization (basic injection) | `vision_sanitize_text: strips injection patterns` | `tests/unit/vision-lib.bats` |
| Content sanitization (HTML entities) | `vision_sanitize_text: strips decoded HTML entities` | `tests/unit/vision-lib.bats` |
| Content sanitization (case-insensitive) | `vision_sanitize_text: strips case-insensitive injection patterns` | `tests/unit/vision-lib.bats` |
| Truncation boundary | `vision_sanitize_text: respects max character limit` | `tests/unit/vision-lib.bats` |
| Shadow JSONL write | `integration: shadow mode writes JSONL and updates state` | `tests/integration/vision-planning-integration.bats` |
| Graduation detection | `integration: graduation triggers after threshold cycles` | `tests/integration/vision-planning-integration.bats` |
| Ref tracking atomicity | `integration: ref tracking increments on active mode interaction` | `tests/integration/vision-planning-integration.bats` |
| Active mode scoring | `integration: active mode query returns scored results with text` | `tests/integration/vision-planning-integration.bats` |
| Cross-sprint regression | 2 regression tests re-run Sprint 1 unit suites | `tests/integration/vision-planning-integration.bats` |

**63 total tests, 0 failures** (53 unit + 10 integration).

---

## Advisories (Non-Blocking)

### ADVISORY-1: `xargs` for whitespace trimming (LOW)

`xargs` is used throughout for trimming whitespace from parsed table columns and tags. While safe in this context (controlled input sources, no `-I` flag), it is a minor code smell — `xargs` can interpret quotes and backslashes in input. A dedicated trim function (`${var## }` parameter expansion or `sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`) would be more explicit. Not a blocking concern since all inputs flowing through `xargs` are either from project-owned index.md tables or pre-validated tag strings.

### ADVISORY-2: Dead code in regression test (TRIVIAL)

`tests/integration/vision-planning-integration.bats` line 250: `run bats "$PROJECT_ROOT/../../tests/unit/vision-lib.bats"` uses the overridden `$PROJECT_ROOT` (which is `$TEST_TMPDIR`), producing an invalid path. Its result is discarded. Line 253 correctly uses `$REAL_ROOT`. The dead `run` on 250 wastes a few milliseconds. Consider removing it.

### ADVISORY-3: GNU sed `I` flag portability (LOW)

Line 358 of vision-lib.sh uses the `I` flag for case-insensitive matching, which is GNU sed-only. This is a secondary defense — the character-class patterns on lines 351-355 provide the portable primary defense. On macOS, line 358 would silently fail to strip bare `<context>`, `<role>`, `<user>`, `<assistant>` tags, but these are lower-risk than `<system>`/`<prompt>`/`<instructions>` (which ARE covered by the portable patterns). Note for future macOS work only.

### ADVISORY-4: Shadow JSONL append without flock (LOW)

Line 333 uses bare `>>` append for the shadow JSONL log. While practically atomic for sub-4096-byte writes on Linux, a `vision_atomic_write()` wrapper would provide defense-in-depth. The shadow state JSON file correctly uses flock. This is informational — the shadow log is diagnostic-only and a partially-written line would not affect system behavior.

---

## SKILL.md Integration Review

Step 0.5 (SKILL.md lines 666-789) is correctly placed between Context Synthesis (Phase 0) and Targeted Interview (Phase 0.5). Key security observations:

1. **Config gate** (line 673): `yq eval '.vision_registry.enabled // false'` with `2>/dev/null || echo "false"` — fails closed.
2. **No LLM-fabricated relevance** (line 742): Explicit `IMPORTANT` note that relevance explanations are template-based (tag match + score), not LLM-generated. This prevents hallucinated rationale injection.
3. **Shadow mode isolation** (line 711): Results piped to `/dev/null` — guaranteed no user-visible output in shadow mode.
4. **Controlled vocabulary** (lines 682-684): Tag derivation maps against a fixed set of 9 tags. No user-supplied free-text tags.
5. **Decision audit trail** (lines 754-764): All user decisions logged to JSONL with timestamp, cycle, phase, vision ID, and score. Full provenance.

---

## Summary

The implementation is security-sound. The defense-in-depth approach to content sanitization (allowlist extraction + HTML decode + case-insensitive tag stripping + indirect instruction filtering + truncation) is well-layered. Path traversal is blocked by canonical path validation. Shell injection is prevented by consistent quoting, `--arg` parameter binding in jq, and input validation. Atomic operations use flock+tmp+mv correctly.

63 tests pass. Security-critical paths are covered by both unit and integration tests. The adversarial test fixture (`entry-semantic-threat.md`) covers real-world attack patterns.

4 non-blocking advisories filed for future hardening. None affect the security posture of this sprint.

**Verdict: APPROVED - LETS FUCKING GO**
