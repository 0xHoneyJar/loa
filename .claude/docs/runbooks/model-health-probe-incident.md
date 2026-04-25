# Model Health Probe — Incident Runbook

**Last reviewed:** 2026-04-25 (cycle-093 sprint-3B)
**Owners:** @janitooor, framework maintainers
**Scope:** failure modes of the `model-health-probe.sh` gate, the `.run/model-health-cache.json` it writes, and the `model-adapter.sh` runtime consult.

This runbook covers diagnosis, short-term unblock, rollback, key rotation, and bypass-governance decision making. It is written as a flat, time-pressed checklist — read top-to-bottom during an incident.

---

## 1. Symptoms

Pick the row that matches what you're seeing.

| Symptom | Likely cause | Jump to |
|---|---|---|
| PR CI fails with `model-health-probe` workflow citing `UNAVAILABLE` | Provider returned NOT_FOUND for a model in registry | [§2 Diagnosis](#2-diagnosis) → [§3 Short-term unblock](#3-short-term-unblock) |
| Local invocation: `Model 'X' marked UNAVAILABLE by probe …` from `model-adapter.sh` | Cached UNAVAILABLE entry is fresh | [§3.2 Cache override](#32-cache-override) |
| `model-health-drift` issue auto-opened on main | Daily cron detected drift | [§2 Diagnosis](#2-diagnosis) → [§4 Long-term remediation](#4-long-term-remediation) |
| Probe takes >120s and exits 5 | Hard-stop budget hit (Flatline IMP-006) | [§5 Probe-infra failures](#5-probe-infra-failures) |
| Suspected secret leak in probe output | Possible `_redact_secrets` regression | [§6 Key rotation](#6-key-rotation) **immediately** |
| You need to roll the probe back to pre-cycle-093 behavior | Unrecoverable defect or prod escalation | [§7 Rollback](#7-rollback) |
| `LOA_PROBE_BYPASS=1` works locally but PR still blocked | Label dual-approval not satisfied | [§8 Bypass governance](#8-bypass-governance) |

---

## 2. Diagnosis

```bash
# 1. Read the human-readable summary.
.claude/scripts/model-health-probe.sh --once --output text

# 2. Read the cache directly to see the persisted state for a specific model.
jq '.entries["openai:gpt-5.5"]' .run/model-health-cache.json

# 3. Replay the reason for one model in JSON.
.claude/scripts/model-health-probe.sh --provider openai --model gpt-5.5 --output json --quiet | jq

# 4. Audit-log query: review override / bypass history.
jq -c 'select(.action | startswith("probe_"))' .run/audit.jsonl | tail -20
```

The probe's stdout summary ends with `summary: N AVAILABLE, M UNAVAILABLE, K UNKNOWN`. UNAVAILABLE means the provider explicitly rejected the model (hard 404 / model-field 400). UNKNOWN means transient/auth — usable with `degraded_ok=true`.

**Key-line in the cache entry:** `reason`. It carries the provider's actual rejection (e.g., `not present in /v1/models across 3 pages` or `400 invalid_request_error on model field`). This is what to escalate to the provider; do **not** paste raw payloads (they may contain identifiers).

---

## 3. Short-term unblock

You have two paths. Pick by question: *is the provider actually broken, or do I just need to ship?*

### 3.1 PR label override (provider outage suspected — 24h max)

1. Add label `override-probe-outage` to the PR.
2. Get a CODEOWNER **and** a framework maintainer to approve. **Both** are required by the workflow's dual-approval gate (Flatline SKP-003).
3. CI re-runs and skips the probe for this PR. The override is logged to `.run/audit.jsonl` automatically.
4. **Mandatory follow-up:** within 24h, post a PR comment explaining the root cause (e.g., link to the provider status page or upstream issue). Failure to post a follow-up is a release-blocker for the next merge.

### 3.2 Cache override (you know the cache is wrong)

If the probe ran against a transient blip and cached a stale UNAVAILABLE:

```bash
# Invalidate one model:
.claude/scripts/model-health-probe.sh --invalidate gpt-5.5

# Or wipe and re-probe everything:
.claude/scripts/model-health-probe.sh --invalidate
.claude/scripts/model-health-probe.sh --once
```

### 3.3 Runtime bypass (env var, 24h TTL, audit-logged)

Only if the local `model-adapter.sh` keeps refusing and you cannot fix the cache:

```bash
export LOA_PROBE_BYPASS=1
export LOA_PROBE_BYPASS_REASON="<ticket #> — provider returning intermittent 404 since YYYY-MM-DD"
```

Both `LOA_PROBE_BYPASS=1` and a non-empty `LOA_PROBE_BYPASS_REASON` are required. The bypass auto-expires after **24 hours** (re-probe re-engages on next call). Every set / re-use is appended to `.run/audit.jsonl` as `probe_bypass_set` / `probe_bypass_active` / `probe_bypass_expired`.

**Reason string conventions:** include a ticket reference, the provider, and the suspected start date. "I just want it to work" is not a valid reason — it will appear in audit logs and be reviewed during the post-incident review.

---

## 4. Long-term remediation

If the model is genuinely retired upstream:

1. Open a tracking issue with label `model-health-drift`.
2. Remove the model from `.claude/defaults/model-config.yaml` `providers.<provider>.models` (along with its alias).
3. Re-run `.claude/scripts/gen-adapter-maps.sh` to refresh `generated-model-maps.sh`.
4. Land both files in one PR. The probe gate will go green automatically once the model is no longer in registry.

If the model is still listed but the API is intermittently 5xx-ing:

1. Increase `model_health_probe.retry_attempts` in `.loa.config.yaml` (default 3 → 5).
2. The probe's exponential backoff (1s, 2s, 4s, 8s, 16s, ±25% jitter) will handle most blips without operator intervention.

---

## 5. Probe-infra failures

The probe itself can break. Common modes:

| Diagnostic | Cause | Fix |
|---|---|---|
| `flock not found. On macOS: brew install util-linux` | macOS without `util-linux` | `brew install util-linux` |
| `cache lock timeout after 5s` | Stuck process holding lock; or filesystem with broken `flock` | `lsof .run/model-health-cache.json.lock`; kill stale process; consider `degraded_ok=true` |
| `cache file corrupt, auto-rebuild failed` | Disk full or read-only filesystem | Free disk space; check `.run/` mount |
| `yq not found; required for registry parsing` | yq not installed (require ≥4) | `brew install yq` / `snap install yq` |
| `LOA_PROBE_BYPASS=1 set without LOA_PROBE_BYPASS_REASON. Bypass denied` | Bypass requested without reason | Set `LOA_PROBE_BYPASS_REASON` per [§3.3](#33-runtime-bypass-env-var-24h-ttl-audit-logged) |
| `circuit breaker tripped` (in cache `provider_circuit_state[…].open_until`) | 5 consecutive failures across all probes for that provider | Wait 5min for auto-reset, or `--invalidate` to force re-probe |

---

## 6. Key rotation playbook

**Trigger criteria (any one suffices):**
- `gitleaks` post-job scanner caught a real secret pattern in CI logs
- A probe stdout/stderr line shows an unmasked `sk-...` / `AIza...` / `ghp_...` / `-----BEGIN ...`
- A team member or external researcher reports a leaked key

**Steps (do these in order, do not skip):**

1. **Revoke the leaked key** at the provider:
   - OpenAI: <https://platform.openai.com/api-keys> → revoke
   - Google: <https://console.cloud.google.com/apis/credentials> → delete API key
   - Anthropic: <https://console.anthropic.com/settings/keys> → delete
2. **Issue a replacement** at the same provider; copy the new value.
3. **Update GitHub Secrets** for `0xHoneyJar/loa`:
   ```
   gh secret set OPENAI_API_KEY     # paste replacement
   gh secret set GOOGLE_API_KEY
   gh secret set ANTHROPIC_API_KEY
   ```
4. **Invalidate cache** so the probe re-authenticates with the new key:
   ```
   .claude/scripts/model-health-probe.sh --invalidate
   ```
5. **Identify the leak source.** Run `git log --all -p -- .claude/scripts/model-health-probe.sh .claude/scripts/lib/secret-redaction.sh` and look for missed redaction patterns. If the leak escaped via a log path that doesn't route through `_redact_secrets`, file a bug under `audit-fix` priority.
6. **Search public exposure.** Use [GitGuardian](https://www.gitguardian.com/) or `trufflehog` against the public mirror. If found, follow GitHub's [removing-sensitive-data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) guidance. **Note:** rotation always comes first; rewriting history before rotation is reversible by anyone with a clone.
7. **Post-mortem.** Draft a postmortem inside 5 days. Identify which redaction pattern was missing, add a regression test to `tests/unit/secret-redaction.bats`, and update `.claude/scripts/lib/secret-redaction.sh` with the new pattern.

---

## 7. Rollback (Flatline IMP-001)

If the probe is causing systemic failures and you need to restore pre-cycle-093 behavior:

### 7.1 Trigger criteria

- ≥2 unrelated PRs blocked by probe in <24h with no clear provider-side cause
- Probe is generating spurious UNAVAILABLE for verified-working models on multiple providers
- The probe itself is crashing (exit 1 with no actionable diagnostic)
- A security review identifies an exploitable defect in the probe

### 7.2 Steps

```bash
# 1. Disable feature flag in .loa.config.yaml (operator-only path).
yq -i '.model_health_probe.enabled = false' .loa.config.yaml

# 2. (CI) Disable the workflows by adding a `[skip-probe]` marker to the
#    PR title, or temporarily rename the workflow files to .yml.disabled
#    and land that change as a hotfix PR.
git mv .github/workflows/model-health-probe.yml .github/workflows/model-health-probe.yml.disabled
git mv .github/workflows/model-health-drift-daily.yml .github/workflows/model-health-drift-daily.yml.disabled

# 3. As an emergency runtime fallback, set LOA_PROBE_LEGACY_BEHAVIOR=1
#    on the affected operator's shell. This makes the probe short-circuit
#    every model to AVAILABLE (sprint-3A escape hatch). Audit-logged.
export LOA_PROBE_LEGACY_BEHAVIOR=1
```

### 7.3 Verification

- `model-adapter.sh` calls succeed without consulting the cache (probe disabled → fail-open path).
- CI workflows do not run the probe step.
- Affected PRs unblock on next push.

### 7.4 Rollback exit criteria

Rollback should be **temporary**. Cycle-093's invariants (drift detection, currency gating) cannot be restored without the probe. Open a follow-up cycle ticket within 5 business days that either:
- patches the defect that triggered rollback and re-enables, OR
- re-architects the probe with the failure mode in mind.

---

## 8. Bypass governance

### 8.1 Decision tree

```
Q1: Is this a CI-side block (PR not merging) or a runtime block (script fails locally)?
    ├── CI-side  → use `override-probe-outage` LABEL (dual-approval gate, audit-logged)
    └── Runtime  → use `LOA_PROBE_BYPASS=1` ENV VAR (24h TTL, mandatory reason, audit-logged)

Q2: Is the cache definitely wrong (stale or corrupt)?
    └── Yes → `--invalidate` first; let the probe re-cache. If still wrong, escalate to Q1.

Q3: Is `degraded_ok=true` enough?
    └── Cache UNKNOWN with degraded_ok=true is the lowest-friction path. Set
        `model_health_probe.degraded_ok: true` in .loa.config.yaml and the
        adapter will warn-and-proceed. Use this for transient provider issues.
```

### 8.2 What each level grants

| Bypass level | Scope | Approval | TTL | Audit |
|---|---|---|---|---|
| `degraded_ok: true` (config) | UNKNOWN states only | None (operator) | Persistent (until config change) | Single audit on first use |
| `--invalidate` (CLI) | Cache reset | None (operator) | Per-run | Trajectory log |
| `LOA_PROBE_BYPASS=1` + reason (env) | Runtime cache consult | None (operator); reason mandatory | **24h** | `probe_bypass_set/active/expired` events |
| `override-probe-outage` label (PR) | CI gate skip | **2 approvers** (CODEOWNER + maintainer) | Per-PR | `probe_gate_override` event |

**Anti-patterns (do NOT do these):**
- Set `LOA_PROBE_BYPASS=1` without `LOA_PROBE_BYPASS_REASON` — the probe refuses with exit 64 and audit-logs the denial.
- Apply `override-probe-outage` label without dual-approval review — CI workflow rejects with `::error::… need ≥2 approvals`.
- Manually edit `.run/model-health-cache.json` to flip a state to AVAILABLE — the probe is the source of truth; manual edits are clobbered on next run.
- Hand-edit `.claude/scripts/generated-model-maps.sh` — that file is generated by `gen-adapter-maps.sh`. Edits will be detected by the SKP-002 invariant test.

---

## 9. Table-top exercise (Sprint 3B review gate)

Run this once during sprint-3B review to verify the runbook end-to-end:

1. Mock a UNAVAILABLE on `openai:gpt-5.5` by writing `.run/model-health-cache.json` directly.
2. Try to invoke `model-adapter.sh --model gpt-5.5 --mode review --input /tmp/foo`. Confirm fail-fast with cache reason + invalidate hint.
3. Apply the runtime bypass (§3.3) with a valid reason. Confirm the call succeeds and `.run/audit.jsonl` carries `probe_bypass_set`.
4. `--invalidate gpt-5.5` and re-probe. Confirm the cache entry comes back AVAILABLE (or stays UNAVAILABLE with the real provider reason).
5. Walk the rollback steps (§7) end-to-end on a throwaway branch. Confirm the workflow `.yml.disabled` rename works and the runtime fallback fires with `LOA_PROBE_LEGACY_BEHAVIOR=1`.
6. Walk the key-rotation steps (§6) — except do not actually rotate; verify each command's syntax against the dashboards.

Sign-off: review the table-top transcript with the framework maintainer; commit the runbook changes (if any) to NOTES.md under "Decision Log".

---

## 10. Related references

- **PRD §3 G5** — health-probe invariant goal
- **SDD §3.5** — caching strategy (TTLs, max_stale_hours, alert_on_stale_hours)
- **SDD §3.6** — concurrency discipline (atomic write, reader retry, PID sentinel)
- **SDD §4.1** — config surface (`model_health_probe` block)
- **SDD §4.3 Flow 4** — enterprise/offline deployment (endpoint overrides)
- **SDD §6.2** — error-category table (UNAVAILABLE → fail-fast contract)
- **Flatline SKP-003** — bypass governance (label + env var + audit)
- **Flatline SKP-005** — secrets discipline (centralized scrubber + post-job scanner)
- `.claude/scripts/model-health-probe.sh` — probe implementation
- `.claude/scripts/lib/secret-redaction.sh` — centralized scrubber
- `.claude/scripts/model-adapter.sh` — runtime cache consult (Sprint 3B Task 3B.7)
