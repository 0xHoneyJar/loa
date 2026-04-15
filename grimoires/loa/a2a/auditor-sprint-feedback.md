# Security Audit — Cycle-073

**Sprint**: Config Documentation + Onboarding Wizard + Cost Awareness
**Auditor**: Security Auditor (independent review)
**Date**: 2026-04-15
**Verdict**: **APPROVED** (3 advisory findings, 0 blockers)

---

## Scope

Files reviewed from git diff:

| File | Type | Risk |
|------|------|------|
| `.claude/commands/loa.md` (cost awareness section) | Prompt instruction | Low |
| `.claude/skills/loa-setup/SKILL.md` | Prompt instruction (new) | Medium |
| `.claude/skills/loa-setup/index.yaml` | Skill manifest (new) | Low |
| `.claude/scripts/loa-setup-check.sh` | Shell script (new) | Medium |
| `docs/CONFIG_REFERENCE.md` | Documentation (new) | Low |
| `.claude/skills/red-teaming/SKILL.md` | Cost annotation | Low |
| `.claude/skills/run-bridge/SKILL.md` | Cost annotation | Low |
| `.claude/skills/run-mode/SKILL.md` | Cost annotation | Low |
| `.claude/skills/simstim-workflow/SKILL.md` | Cost annotation | Low |
| `.claude/skills/spiraling/SKILL.md` | Cost annotation | Low |
| `.claude/skills/rtfm-testing/SKILL.md` | Scope annotation | Low |
| `README.md` | Cost warning banner | Low |

---

## Security Checklist

### 1. Hardcoded Secrets — PASS

- `loa-setup-check.sh:11-15` — checks `${ANTHROPIC_API_KEY:-}` with `-n` (non-empty test), never echoes the value. Detail string says `"ANTHROPIC_API_KEY is set"`, not the key itself.
- `SKILL.md:50` — explicit CRITICAL block: "You MUST NOT read, echo, print, or log the value of any environment variable."
- Config templates use `{env:OPENAI_API_KEY}` and `{env:GOOGLE_API_KEY}` — runtime-resolved placeholders, not actual values.
- `SKILL.md:348` — redundant safeguard: "NEVER substitute actual key values."
- No secrets in CONFIG_REFERENCE.md, README.md, or any cost annotation.

### 2. Input Validation — PASS

- **User input (wizard questionnaire)**: `SKILL.md:100` — "Enumerated choices only — if the user provides a free-form answer that does not match a valid option, re-present the valid options without accepting the free-form text." Prevents injection via free-form responses.
- **yq output validation**: `loa-setup-check.sh:51-53` — `case` statements constrain yq output to `true|false` with safe defaults before passing to `--argjson`. Prevents invalid JSON from reaching jq.
- **Write confirmation gate**: `SKILL.md:395-397` — config is written only on explicit "yes". Validation-skipped path requires a second explicit "yes" (`SKILL.md:389-393`).

### 3. Command Injection — PASS

- **jq parameterization**: `loa-setup-check.sh:21-22,24-25,33,40,54-58` — all JSON construction uses `jq -n --arg` (strings) and `--argjson` (validated booleans). No string interpolation into jq filters.
- **Hardcoded loop values**: `loa-setup-check.sh:18` — `for dep in jq yq git` uses a hardcoded list, no user input.
- **Version capture**: `loa-setup-check.sh:20` — `$("$dep" --version 2>&1 | head -1)` — `$dep` comes from the hardcoded loop. Safe.
- **deny_raw_shell**: Both `SKILL.md:15` and `index.yaml:22` declare `deny_raw_shell: true`, restricting execution to whitelisted commands only (`loa-setup-check.sh --json`, `yq`, `jq`).
- **yq expressions**: All yq invocations use hardcoded filter strings (e.g., `.flatline_protocol.enabled // false`), no user-controlled input.

### 4. File Permissions — PASS

- No `chmod`, `chown`, or permission manipulation in any file.
- `loa-setup-check.sh` creates no files.
- SKILL.md writes only to `.loa.config.yaml` — a user-owned, repo-root config file.
- `hounfour.metering.ledger_path` defaults to `.run/cost-ledger.jsonl` — a known writable State Zone directory.

### 5. Path Traversal — PASS

- `loa-setup-check.sh:46` — `[[ -f ".loa.config.yaml" ]]` — relative to CWD, no user-controlled component.
- All SKILL.md file paths are hardcoded constants (`.loa.config.yaml`, `.loa.config.yaml.example`, `docs/CONFIG_REFERENCE.md`).
- No user-controlled path construction anywhere in the diff.

### 6. OWASP Top 10 Relevance — PASS

- **A03:2021 Injection**: No SQL, no shell interpolation, no jq filter injection. All parameterized.
- **A04:2021 Insecure Design**: NFR-5 (opt-in only) and NFR-6 (no key logging) enforced. `deny_raw_shell: true` limits attack surface.
- **A05:2021 Security Misconfiguration**: `secret_scanning.enabled: true` in flatline template. CONFIG_REFERENCE.md warns "never disable" at line 659.
- **A09:2021 Logging/Monitoring**: Setup check script logs structured JSONL with no sensitive data.

---

## Advisory Findings (non-blocking)

### F1 — MEDIUM: Budget default inconsistency between CONFIG_REFERENCE.md and wizard template

| Field | Value |
|-------|-------|
| Location | `docs/CONFIG_REFERENCE.md:224` vs `.claude/skills/loa-setup/SKILL.md:327` |
| Severity | MEDIUM |
| Type | Documentation inconsistency |

**Finding**: CONFIG_REFERENCE.md documents `hounfour.metering.budget.daily_micro_usd` default as `500000000` ($500/day). The wizard template in SKILL.md sets `daily_micro_usd: 50000000` ($50/day). This is a 10x discrepancy.

**Impact**: Users who read CONFIG_REFERENCE.md and accept defaults get a $500/day budget cap. Users who run `/loa setup` get a $50/day cap. Not a vulnerability — the wizard path is more conservative — but the inconsistency could confuse users who cross-reference both sources.

**Recommendation**: Align on one default. The wizard's $50/day is the safer choice for most users. If $500/day is the intended framework default, document why the wizard is more conservative.

### F2 — LOW: setup-check.sh missing OPENAI/GOOGLE key detection

| Field | Value |
|-------|-------|
| Location | `.claude/scripts/loa-setup-check.sh:11-15` vs `.claude/skills/loa-setup/SKILL.md:56-60` |
| Severity | LOW |
| Type | Functional gap |

**Finding**: The setup check script only emits a Step 1 entry for `ANTHROPIC_API_KEY`. The SKILL.md (Step 1.2 table) expects Step 1 entries for `OPENAI_API_KEY` and `GOOGLE_API_KEY` as well. Since those entries are never emitted, the wizard will always record `openai_key_present: false` and `google_key_present: false`, which causes Q4 (multi-model confirmation) to be skipped and `multi_model_confirmed` to default to `false`.

**Impact**: Multi-model features (Flatline, Red Team) are never recommended by the wizard even when the user has the required API keys. This **fails safe** (conservative), so it is not a security issue, but it defeats the purpose of the environment detection phase for multi-model features.

**Recommendation**: Add OPENAI_API_KEY and GOOGLE_API_KEY checks to `loa-setup-check.sh` with the same boolean-only pattern used for ANTHROPIC_API_KEY.

### F3 — LOW: run_bridge template comment/value mismatch

| Field | Value |
|-------|-------|
| Location | `.claude/skills/loa-setup/SKILL.md:305` |
| Severity | LOW |
| Type | Cosmetic |

**Finding**: The comment says `run_bridge` "(depth 1 conservative default)" but the template sets `depth: 3`.

**Impact**: None. The template value (3) is what gets written to config. The comment is misleading but harmless.

**Recommendation**: Update comment to "depth 3 default" or remove the parenthetical.

---

## Positive Observations

1. **Defense in depth on API keys**: Three layers protect key material — script emits booleans only (`loa-setup-check.sh:12`), SKILL.md has a CRITICAL block forbidding key access (`SKILL.md:50`), and `deny_raw_shell: true` prevents ad-hoc `echo $KEY` commands.
2. **jq --arg throughout**: Every JSON construction in setup-check.sh uses parameterized binding, consistent with project conventions.
3. **Explicit confirmation gates**: Config is never written without user "yes". Validation-skipped path requires a second "yes". Declining is a graceful exit, not an error.
4. **Fail-safe defaults**: Missing keys -> conservative config. Missing script -> conservative defaults. Missing validation tools -> extra confirmation. All error paths default to the safer option.
5. **`secret_scanning.enabled: true`** in the Flatline template, plus explicit "never disable" warning in CONFIG_REFERENCE.md.
6. **Arithmetic safety**: `loa-setup-check.sh:26` uses `errors=$((errors + 1))` (not `(( errors++ ))`) — correct per project shell conventions to avoid `set -e` trap when `errors=0`.
7. **set -euo pipefail**: Script uses strict mode throughout.

---

## Verdict

**APPROVED**

No CRITICAL or HIGH security findings. 1 MEDIUM (budget default inconsistency — cost confusion, not security risk) and 2 LOW (functional gap in key detection, cosmetic comment). All jq uses `--arg`. No secrets. No injection paths. No path traversal. File permissions correct. Multiple layers of API key protection. Explicit user confirmation before any write.

The implementation is secure for production use.
