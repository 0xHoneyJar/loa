

## P01 — pr-05 · `.claude/scripts/workflow-state.sh` lines 390–390 · region OUTSIDE the PR's diff (nearest changed line 301 lines away) · enclosing symbol: main

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/scripts/workflow-state.sh:83-89` — `get_completed_sprints` counts every `a2a/sprint-*/COMPLETED`, including other cycles' sprints and `sprint-bug-*` micro-sprints, while `get_total_sprints` (`:70-76`) counts only the current `sprint.md`; `determine_state` at `:148` then returns `complete` for an unfinished plan.
**File:** `head/.claude/scripts/workflow-state.sh:83-89`; consumers at `:148`, `:390`, `:401`
**Issue:** The base loop iterated `sprint-1..total` and so was scoped to the current plan. Head replaces it with a directory scan. `completed >= total` is the completion test, `progress_percent` scales `completed/total`, and the result is written to the semantic cache keyed on prd/sdd/sprint/ledger mtimes, so the wrong state persists until one of those files changes.
**Evidence:** Temp grimoire with `sprint.md` declaring three sprints, `sprint-1/COMPLETED`, plus stale `sprint-7/COMPLETED` and `sprint-bug-108/COMPLETED` (the repo creates `sprint-bug-*` dirs, see `.claude/scripts/next-bug-sprint-id.sh:103`):
```

### Head file context (line| text)

```text
  380|                 break
  381|             fi
  382|         done
  383|     fi
  384| 
  385|     local suggested_command
  386|     local progress
  387|     local description
  388| 
  389|     suggested_command=$(get_suggested_command "${state}" "${current_sprint}")
  390|     progress=$(get_progress_percentage "${state}" "${total_sprints}" "${completed_sprints}")
  391|     description=$(get_state_description "${state}" "${current_sprint}")
  392| 
  393|     # Build JSON result (used for both output and caching)
  394|     local json_result
  395|     json_result=$(cat <<EOF
  396| {
  397|   "state": "${state}",
  398|   "description": "${description}",
  399|   "current_sprint": "${current_sprint}",
  400|   "total_sprints": ${total_sprints},
```


## P02 — pr-05 · `.claude/scripts/workflow-state.sh` lines 243–243 · region OUTSIDE the PR's diff (nearest changed line 154 lines away) · enclosing symbol: get_progress_percentage

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/workflow-state.sh:83 — Correctness regression: get_completed_sprints now counts every `a2a/sprint-*` directory with a COMPLETED marker, including sprints from earlier cycles and sprint IDs beyond sprint.md. get_total_sprints still counts only the `## Sprint N` headings in the current sprint.md, so the two numbers no longer measure the same set. With leftover history, completed >= total holds at :148 and the workflow reports `complete` before any current sprint is done. Progress at :243 (`completed*70/total`) can also go past 95%/100%, and "Sprints: X/Y complete" shows nonsense such as 12/3. Base correctly limited the count to sprint-1..sprint-total.
```

### Head file context (line| text)

```text
  233|             ;;
  234|         "${STATE_SDD_CREATED}")
  235|             echo "20"
  236|             ;;
  237|         "${STATE_SPRINT_PLANNED}")
  238|             echo "25"
  239|             ;;
  240|         "${STATE_IMPLEMENTING}"|"${STATE_REVIEWING}"|"${STATE_AUDITING}")
  241|             if [[ "${total_sprints}" -gt 0 ]]; then
  242|                 # 25% base + 70% for sprints (save 5% for deploy)
  243|                 local sprint_progress=$((completed_sprints * 70 / total_sprints))
  244|                 echo $((25 + sprint_progress))
  245|             else
  246|                 echo "30"
  247|             fi
  248|             ;;
  249|         "${STATE_COMPLETE}")
  250|             echo "95"
  251|             ;;
  252|         *)
  253|             echo "0"
```


## P03 — pr-12 · `ADVERSARIAL-REVIEW.md` lines 54–54 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/verdict-derive.sh:137 — The contract is enforced only through the presence of the `## Rejected dissent payloads` heading. An empty section, or one with fewer lines than `rejected_summary` has entries, passes (confirmed: a file with just the heading and no entries comes out CONSISTENT). The docs (`ADVERSARIAL-REVIEW.md:54` / `:64`) say "MUST … one line per entry". Count list items in the section and compare with `n`.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P04 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 1925–1925 · region inside the PR's diff · enclosing symbol: _fold_companion

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:1925 — `metadata.companion_voice` records neither the companion's rejected sidecar (`adversarial-rejected-<type>-companion.jsonl`) nor its path. `metadata.rejected_sidecar` still names only the primary's file, yet the companion's rejected entries are folded into `rejected_summary`/`rejected_count`. A triager sent to the sidecar for those entries cannot find their payloads.
```

### Head file context (line| text)

```text
 1915|       | .metadata.rejected_summary = (($p.metadata.rejected_summary // []) + (($c.metadata.rejected_summary // []) | map(. + {voice: $cv})))
 1916|       | .metadata.rejected_count = (($p.metadata.rejected_count // 0) + ($c.metadata.rejected_count // 0))')
 1917|   else
 1918|     cls=$(_companion_failure_class "$status" "$rc")
 1919|     local synth="$workdir/vq-companion-synthetic.json"
 1920|     jq -nc --arg v "${final:-companion}" --arg r "$(_companion_drop_reason "$cls")" --argjson e "$(( rc <= 255 ? rc : 1 ))"       '{status: "FAILED", consensus_outcome: "consensus", truncation_waiver_applied: false, voices_planned: 1, voices_succeeded: 0,
 1921|         voices_succeeded_ids: [], voices_dropped: [{voice: $v, reason: $r, exit_code: $e, blocker_risk: "unknown"}],
 1922|         chain_health: "exhausted", confidence_floor: "low", rationale: "companion chain did not complete", single_voice_call: true}' > "$synth"
 1923|     result=$(echo "$result" | jq --arg pv "$primary_final" '.findings = ((.findings // []) | map(. + {voice: $pv}))')
 1924|   fi
 1925|   echo "$result" | jq --arg fam "$family" --arg chain "$chain" --arg model "$final" --arg st "$comp_status"       --arg cls "$cls" --argjson cost "$cost_cents" --argjson att "$attempts_json"       '.metadata.companion_voice = {planned: true, family: $fam, family_basis: "configured_primary",
 1926|         chain: ($chain | split(",")), model: (if $model == "" then null else $model end), status: $st,
 1927|         failure_class: (if $cls == "" then null else $cls end), cost_cents: $cost, attempts: $att}'
 1928| }
 1929| 
 1930| main() {
 1931|   local type="" sprint_id="" diff_file="" context_file="" model="" budget="" timeout=""
 1932|   local dry_run="false" json_output="true"
 1933| 
 1934|   # Parse arguments
 1935|   while [[ $# -gt 0 ]]; do
```

### The PR's diff hunk covering these lines

```diff
@@ -1719,6 +1795,138 @@ _extract_result_status() {
   printf '%s' "$status"
 }
 
+# =============================================================================
+# cycle-126 FR-2.1 (SDD D-2.1): the companion voice. A second, independent
+# chain from the OTHER provider family runs in parallel with the primary chain
+# and the two completed envelopes are aggregated (`voices_planned` 2). The
+# family is decided from the configured primary model; credential PRESENCE
+# (env → .env.local → .env, value never read) decides only where the
+# companion chain STARTS (an HTTP voice with no key is skipped straight to the
+# CLI hop); the companion's outcome is its actual completion. A companion whose
+# whole chain fails is a dropped voice (degraded, never blocking a review;
+# audit keeps its degraded rules) with a named failure class. Its rejected
+# payloads land in their own sidecar (`-companion` suffix), never the primary's.
+# =============================================================================
+_adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
+  local m="$1" prov=""
+  if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
+    # shellcheck source=generated-model-maps.sh
+    [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
+  fi
+  if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
+  if [[ -z "$prov" ]]; then
+    case "$m" in
+      anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
+      openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
+      google:*|gemini*|agy*) prov="google" ;;
+      *) prov="unknown" ;;
+    esac
+  fi
+  echo "$prov"
+}
+
+_companion_family() {  # <primary family> → the other family (google/unknown primaries get the Anthropic chain)
+  case "$1" in
+    anthropic) echo "openai" ;;
+    *) echo "anthropic" ;;
+  esac
+}
+
+_companion_chain() {  # <family> → space-separated chain, credential presence deciding the start
+  case "$1" in
+    anthropic) if _adv_cred_present anthropic; then echo "opus claude-headless"; else echo "claude-headless"; fi ;;
+    openai)    if _adv_cred_present openai; then echo "gpt-5.5-pro gpt-5.5 codex-headless"; else echo "codex-headless"; fi ;;
+    *) echo "" ;;
+  esac
+}
+
+_companion_failure_class() {  # <last status> <last exit code> → auth|model_unavailable|quota|timeout|malformed
+  local status="$1" rc="$2"
+  case "$status" in malformed_response) echo "malformed"; return 0 ;; esac
+  case "$rc" in
+    4) echo "auth" ;;
+    6) echo "quota" ;;
+    3|124) echo "timeout" ;;
+    5) echo "malformed" ;;
+    *) echo "model_unavailable" ;;
+  esac
+}
+
+_companion_drop_reason() {  # <failure class> → verdict-quality drop-reason enum
+  case "$1" in
+    quota) echo "RateLimited" ;;
+    auth|model_unavailable) echo "ProviderUnavailable" ;;
+    malformed) echo "EmptyContent" ;;
+    *) echo "Other" ;;
+  esac
+}
+
…[hunk truncated]
```


## P05 — pr-12 · `.loa.config.yaml` lines 113–113 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:1835-1840` — `_companion_chain` plans from the configured primary's *family* only and is never reconciled with the primary's `fallback_chain`.
**Component:** `head/.claude/scripts/adversarial-review.sh:1835-1840` (`_companion_chain`), `:2140-2141` (fork), `:2206-2212` (fail-soft aggregation)
**Criterion:** SEC-AV: Availability/Resilience; ARCH-RE
**Reasoning Trace:**
> `_companion_chain anthropic` returns `"claude-headless"` on a keyless host (`:1837`). This repository's `.loa.config.yaml` (`:402-410`) has `security_audit.model: gpt-5.5-pro` and `fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]` (same for `code_review`), and its own comment says "API path is billing-degraded … CLI subscription path works" (`.loa.config.yaml:113`). Reproduced (R1): HTTP hops `unavailable`, `claude-headless` ok → call log `gpt-5.5-pro claude-headless gpt-5.5 gemini-3.1-pro claude-headless` (the hop runs **twice**), `final_model=claude-headless`, `companion_voice.model=claude-headless`, both findings `voice: claude-headless`, `verdict_quality: null`, stderr `[vq-aggregate] aggregator unavailable or returned no output` — the Python aggregator raised INV-4 (duplicate succeeded id) and `:2206` swallows it with `2>/dev/null`.
**Description:** Nothing in `_walk_companion_chain`, `main` or `_fold_companion` compares the two chains or the two answering ids. The docs promise `voices_planned: 2` from two families (head/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md:49) and the config example promises "a s…
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P06 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 502–502 · region inside the PR's diff · enclosing symbol: _adv_cred_present

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:502 — `_adv_cred_present` does read the credential value: grep/sed extract it into `val`, and only the emptiness check comes after. That contradicts "the value is never read out" (line 485 and both ADVERSARIAL-REVIEW.md docs). A `grep -qE "^…${v}=[^[:space:]#]"` presence test would do the job without ever holding the secret in a shell variable.
```

### Head file context (line| text)

```text
  492|     google) vars=(GOOGLE_API_KEY GEMINI_API_KEY) ;;
  493|     *) return 1 ;;
  494|   esac
  495|   local v f val root="$PROJECT_ROOT"
  496|   for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && return 0; done
  497|   # bats-gated seam: point the dotenv lookup at a fixture directory
  498|   if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_ENV_DIR:-}" ]]; then root="$LOA_ADVERSARIAL_ENV_DIR"; fi
  499|   for f in "$root/.env.local" "$root/.env"; do
  500|     [[ -f "$f" ]] || continue
  501|     for v in "${vars[@]}"; do
  502|       val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | sed -e 's/^[^=]*=//' -e "s/^[\"']//" -e "s/[\"'][[:space:]]*$//" -e 's/[[:space:]]*#.*$//')
  503|       [[ -n "$val" ]] && return 0
  504|     done
  505|   done
  506|   return 1
  507| }
  508| 
  509| _repair_model() {  # <primary model> → the model the repair round-trip uses
  510|   if [[ -n "${LOA_ADVERSARIAL_REPAIR_MODEL:-}" ]]; then echo "$LOA_ADVERSARIAL_REPAIR_MODEL"; return 0; fi
  511|   if _adv_cred_present anthropic; then echo "tiny"; else echo "claude-headless"; fi
  512| }
```

### The PR's diff hunk covering these lines

```diff
@@ -445,9 +451,66 @@ _normalize_finding_for_validation() {
     | (if has("category") and (.category | type) == "string"
        then .category |= (gsub("^\\s+|\\s+$"; "") | ascii_downcase)
        else . end)
+  ' 2>/dev/null | _derive_failure_mode "$index"
+}
+
+# cycle-126 FR-2.2 (SDD D-2.2, KF-004): `failure_mode` is derivable, not
+# required. A finding that carries everything but it gets the first sentence
+# of its `description` (≤ 200 chars) as `failure_mode` and is marked
+# `failure_mode_derived: true`; a missing `id` (the models emit `title`, not
+# `id`) is filled from the position (`DISS-NNN`, `id_derived: true`). Severity,
+# category and description are never touched, so a derived finding is gated
+# exactly like a stated one. Only the unenforced path reaches this (the call
+# site skips normalisation for schema-enforced payloads). stdin → stdout.
+_derive_failure_mode() {
+  local index="${1:-}"
+  jq --arg idx "$index" '
+    (if ((.id // "") | tostring | length) == 0 and ($idx | length) > 0
+     then .id = ("DISS-" + (($idx | tonumber) + 1 | tostring | if length < 3 then ("000" + .)[-3:] else . end))
+          | .id_derived = true
+     else . end)
+    | if ((.failure_mode // "") | tostring | length) == 0
+         and (.description | type) == "string" and (.description | length) > 0
+      then
+        (.description
+          | gsub("\\s+"; " ")
+          | (capture("^(?<s>.*?[.!?])(\\s|$)").s // .)
+          | .[0:200]) as $fm
+        | .failure_mode = $fm | .failure_mode_derived = true
+      else . end
   ' 2>/dev/null
 }
 
+# cycle-126 FR-2.4 (SDD D-2.4): the repair model — `tiny` when an Anthropic
+# credential is PRESENT (env → .env.local → .env; the value is never read
+# out), else the `claude-headless` hop; LOA_ADVERSARIAL_REPAIR_MODEL pins it.
+_adv_cred_present() {  # <provider> → 0 when a credential is present (presence only)
+  local -a vars
+  case "$1" in
+    openai) vars=(OPENAI_API_KEY) ;;
+    anthropic) vars=(ANTHROPIC_API_KEY) ;;
+    google) vars=(GOOGLE_API_KEY GEMINI_API_KEY) ;;
+    *) return 1 ;;
+  esac
+  local v f val root="$PROJECT_ROOT"
+  for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && return 0; done
+  # bats-gated seam: point the dotenv lookup at a fixture directory
+  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_ENV_DIR:-}" ]]; then root="$LOA_ADVERSARIAL_ENV_DIR"; fi
+  for f in "$root/.env.local" "$root/.env"; do
+    [[ -f "$f" ]] || continue
+    for v in "${vars[@]}"; do
+      val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | sed -e 's/^[^=]*=//' -e "s/^[\"']//" -e "s/[\"'][[:space:]]*$//" -e 's/[[:space:]]*#.*$//')
+      [[ -n "$val" ]] && return 0
+    done
+  done
+  return 1
+}
+
+_repair_model() {  # <primary model> → the model the repair round-trip uses
+  if [[ -n "${LOA_ADVERSARIAL_REPAIR_MODEL:-}" ]]; then echo "$LOA_ADVERSARIAL_REPAIR_MODEL"; return 0; fi
+  if _adv_cred_present anthropic; then echo "tiny"; else echo "claude-headless"; fi
+}
+
 # _repair_violated_field <reject_reason>
 # Maps a _validate_finding_reason string to the single field name it
 # names as violated. Unknown/unmapped reasons yield "" (empty) — the
```


## P07 — pr-05 · `.claude/scripts/workflow-state.sh` lines 148–148 · region OUTSIDE the PR's diff (nearest changed line 59 lines away) · enclosing symbol: determine_state

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/workflow-state.sh:83 — Correctness regression: get_completed_sprints now counts every `a2a/sprint-*` directory with a COMPLETED marker, including sprints from earlier cycles and sprint IDs beyond sprint.md. get_total_sprints still counts only the `## Sprint N` headings in the current sprint.md, so the two numbers no longer measure the same set. With leftover history, completed >= total holds at :148 and the workflow reports `complete` before any current sprint is done. Progress at :243 (`completed*70/total`) can also go past 95%/100%, and "Sprints: X/Y complete" shows nonsense such as 12/3. Base correctly limited the count to sprint-1..sprint-total.
```

### Head file context (line| text)

```text
  138|         return
  139|     fi
  140| 
  141|     # Check sprint states
  142|     local total_sprints
  143|     local completed_sprints
  144|     total_sprints=$(get_total_sprints)
  145|     completed_sprints=$(get_completed_sprints)
  146| 
  147|     # All sprints complete?
  148|     if [[ "${completed_sprints}" -ge "${total_sprints}" ]] && [[ "${total_sprints}" -gt 0 ]]; then
  149|         echo "${STATE_COMPLETE}"
  150|         return
  151|     fi
  152| 
  153|     # Find current sprint
  154|     local current_sprint=""
  155|     for i in $(seq 1 "${total_sprints}"); do
  156|         local sprint_id="sprint-${i}"
  157|         local sprint_state
  158|         sprint_state=$(get_sprint_state "${sprint_id}")
```


## P08 — pr-13 · `loa-status.sh` lines 869–869 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/hooks/session-start/loa-context-class.sh:66 — `--show` is documented, and relied on in `loa-status.sh:869`, as never recomputing or rewriting the record. But when `.run/context-class` is missing, or its first line is not `long`/`standard`, the script drops to `MODE=line` and the code below writes a new record. Since `/loa` runs it with `< /dev/null` (no payload, no model), it writes `long`/`default` even in a Haiku session, and the next `--show` reports that invented class as the recorded one (reproduced with a corrupted record: it is overwritten with `long`). `--show` should never write; print the computed line and exit.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P09 — pr-08 · `.claude/scripts/ledger-lib.sh` lines 179–179 · region inside the PR's diff · enclosing symbol: _write_ledger

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/ledger-lib.sh:179 — `printf '%s'` swapped for `echo "$content"` here and at line 157. `echo` treats leading `-n`/`-e`/`-E` as options and adds a trailing newline, so what gets validated and stamped is no longer the exact byte string. This is a gratuitous change to a guard written specifically for byte-exact handling; keep `printf '%s'`.
```

### Head file context (line| text)

```text
  169|         echo "ERROR: Could not acquire ledger lock within ${LEDGER_LOCK_TIMEOUT}s" >&2
  170|         exec 9>&-
  171|         return 1
  172|     fi
  173| 
  174|     # Backup before write
  175|     ensure_ledger_backup
  176| 
  177|     # Update last_updated timestamp
  178|     local updated_content
  179|     updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
  180|     if [[ -z "$updated_content" ]]; then
  181|         echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
  182|         flock -u 9
  183|         exec 9>&-
  184|         return $LEDGER_ERROR
  185|     fi
  186| 
  187|     # SECURITY (HIGH-001): Atomic write via temp file + mv
  188|     local tmp_file="${ledger_path}.tmp.$$"
  189|     if ! echo "$updated_content" > "$tmp_file"; then
```

### The PR's diff hunk covering these lines

```diff
@@ -174,7 +176,7 @@
 
     # Update last_updated timestamp
     local updated_content
-    updated_content=$(printf '%s' "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
+    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
     if [[ -z "$updated_content" ]]; then
         echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
         flock -u 9
```


## P10 — pr-13 · `PARALLEL-REVIEW.md` lines 3–4 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
**Severity:** LOW | **Confidence:** medium
**Component:** `head/.claude/skills/reviewing-code/SKILL.md:202`; same at `head/.claude/skills/auditing-security/SKILL.md:162` and `head/.claude/skills/implementing-tasks/SKILL.md:223`
**Description:** Phase -1 now reads "Parallelise (`parallel_threshold`) when the scope warrants" after the line-count procedure was deleted; the frontmatter values (3000 / 2000 / 3000) have no unit in the prose, and the size tables survive only in each skill's `resources/REFERENCE.md`, which these lines do not point to (the pointer lives in `PARALLEL-REVIEW.md:3-4` / `PARALLEL-SPLIT.md:3`, read after the decision).
**Remediation:** "Parallelise above `parallel_threshold` lines (table: `resources/REFERENCE.md`)".
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P11 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 1314–1322 · region inside the PR's diff · enclosing symbol: process_findings

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:468-470` — the positional id `DISS-<index+1>` is derived without checking the ids the model did supply. Reproduced: findings `[{no id}, {id: "DISS-001"}]` yield two findings both `id: DISS-001` (one `id_derived: true`). Reviewers reference findings by id; the rejected-summary `title` falls back to `id` (`:1316`).
**Suggestion:** Derive into a namespace that cannot collide (`DISS-D-NNN`) or skip ids already present in the document.
**Benefit:** Unique ids per envelope.
```

```text
### [LOW-007] Unbounded untrusted model text enters the envelope the agent must triage
- **LOW** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:1314-1322` — `rejected_summary[]` copies `title` (or `id`) and `anchor` from a payload that *failed* validation with no length or character cap (`description_head` is capped at 160); the skill then instructs the reviewing agent to read and triage every entry. Rejected payloads are the likeliest carrier of garbage or injected instructions. Cap `title`/`anchor` (e.g. 200 chars), strip control characters, and keep the "untrusted body" rule at surfacing. CWE-20 — https://cwe.mitre.org/data/definitions/20.html
```

### Head file context (line| text)

```text
 1304|       fi
 1305| 
 1306|       if [[ "$repair_succeeded" == "true" ]]; then
 1307|         validated_findings=$(echo "$validated_findings" | jq --argjson f "$accepted_finding" '. + [$f]')
 1308|         repaired_count=$((repaired_count + 1))
 1309|       else
 1310|         log "Rejected invalid finding at index $i: ${sidecar_reject_reason:-unknown-reason}"
 1311|         _write_rejected_sidecar "$rejected_sidecar" "$finding" "$sidecar_reject_reason" "$i" "$sprint_id" "$type" "$model" \
 1312|           "$repair_attempted" "$repair_succeeded" "$schema_enforced" "$parse_path" "$resp_stop_reason"
 1313|         rejected_count=$((rejected_count + 1))
 1314|         rejected_summary=$(echo "$rejected_summary" | jq --argjson f "$candidate" --arg r "${sidecar_reject_reason:-unknown-reason}" '. + [{
 1315|           severity: ($f.severity // null),
 1316|           title: ($f.title // $f.id // null),
 1317|           anchor: (if ($f.anchor // null) != null then $f.anchor
 1318|                    elif ($f.location | type) == "object" then "\($f.location.file // "")#\($f.location.anchor // "")"
 1319|                    elif ($f.location // null) != null then $f.location
 1320|                    else ($f.stable_anchor // null) end),
 1321|           reason: $r,
 1322|           description_head: (($f.description // "") | tostring | .[0:160])
 1323|         }]' 2>/dev/null || echo "$rejected_summary")
 1324|       fi
 1325|     fi
 1326|     i=$((i + 1))
 1327|   done
 1328| 
 1329|   # cycle-102 sprint-1F: surface aggregate rejection count in the main
 1330|   # output's metadata so consumers (operator, /audit-sprint, BB triage) see
 1331|   # the rejection signal without needing to grep stderr or open the sidecar.
 1332|   # The sidecar path is also surfaced for one-jump triage.
```

### The PR's diff hunk covering these lines

```diff
@@ -1247,6 +1311,16 @@ while i < len(text):
         _write_rejected_sidecar "$rejected_sidecar" "$finding" "$sidecar_reject_reason" "$i" "$sprint_id" "$type" "$model" \
           "$repair_attempted" "$repair_succeeded" "$schema_enforced" "$parse_path" "$resp_stop_reason"
         rejected_count=$((rejected_count + 1))
+        rejected_summary=$(echo "$rejected_summary" | jq --argjson f "$candidate" --arg r "${sidecar_reject_reason:-unknown-reason}" '. + [{
+          severity: ($f.severity // null),
+          title: ($f.title // $f.id // null),
+          anchor: (if ($f.anchor // null) != null then $f.anchor
+                   elif ($f.location | type) == "object" then "\($f.location.file // "")#\($f.location.anchor // "")"
+                   elif ($f.location // null) != null then $f.location
+                   else ($f.stable_anchor // null) end),
+          reason: $r,
+          description_head: (($f.description // "") | tostring | .[0:160])
+        }]' 2>/dev/null || echo "$rejected_summary")
       fi
     fi
     i=$((i + 1))
```


## P12 — pr-13 · `.claude/skills/implementing-tasks/SKILL.md` lines 221–223 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **LOW** (confidence: medium) `head/.claude/skills/auditing-security/SKILL.md:160`, `head/.claude/skills/implementing-tasks/SKILL.md:221`, `head/.claude/skills/reviewing-code/SKILL.md:200` — GOAL-DRIVEN: Phase -1 went from a mechanical, checkable rule (count lines; SMALL/MEDIUM/LARGE bands) to "Parallelise (`parallel_threshold`) when the scope warrants; the lead decides." The thresholds survive in each `resources/REFERENCE.md`, but the SKILL.md no longer tells the reader to look there, and `parallel_threshold` is `null` in two of the ten skills' frontmatter. Point at the REFERENCE.md table explicitly.
```

```text
### [LOW-015] Phase -1 lost its checkable rule and does not point at where the thresholds went
- **File:** `head/.claude/skills/auditing-security/SKILL.md:162`, `head/.claude/skills/reviewing-code/SKILL.md:202`, `head/.claude/skills/implementing-tasks/SKILL.md:223`; `parallel_threshold: null` in `head/.claude/skills/designing-architecture/SKILL.md:18` and `head/.claude/skills/planning-sprints/SKILL.md:17`
- **Confidence:** medium. "Parallelise (`parallel_threshold`) when the scope warrants; the lead decides" replaces line-count bands that survive only in each `resources/REFERENCE.md`; two skills' `parallel_threshold` is `null`, so the named knob has no value to decide by.
```

### Head file context (line| text)

```text
  211| `HEALTHY` → import state (`br sync --import-only`; `update-beads-state.sh --sync-import`) and proceed. `DEGRADED` → warn, import, proceed. `NOT_INSTALLED`/`NOT_INITIALIZED` → check opt-out (`update-beads-state.sh --opt-out-check`); without one, warn (`cargo install beads_rust && br init` to add it) and fall back to markdown. `MIGRATION_NEEDED`/`UNHEALTHY` → warn, fall back to markdown. Record the outcome: `.claude/scripts/beads/update-beads-state.sh --health "$status"`.
  212| 
  213| Run the full lifecycle per task yourself: health check → `br sync --import-only` → `br ready` → `br update <id> --status in_progress` → implement → `br close <id>` (run mode: then `.claude/scripts/run-checkpoint.sh write --sprint sprint-N --task <id> --phase IMPLEMENT`) → `br sync --flush-only` at session end. Log discovered issues as they surface — this adds a `discovered-during:<parent-id>` label for traceability:
  214| 
  215| ```bash
  216| .claude/scripts/beads/log-discovered-issue.sh "$CURRENT_TASK_ID" "Description of discovered issue" bug 2
  217| ```
  218| 
  219| Spec: `.claude/protocols/beads-preflight.md`; command reference: `resources/REFERENCE.md` §Beads Workflow.
  220| 
  221| ## Phase -1: Scope and Parallel Task Splitting
  222| 
  223| Parallelise (`parallel_threshold`) when the scope warrants; the lead decides. With 3+ independent tasks, split per task: `resources/REFERENCE.md` §Parallel Implementation Guidelines.
  224| 
  225| ## Phase 0: Feedback and Context Check
  226| 
  227| Work through `<grounding_requirements>` above before any new work.
  228| 
  229| ## Phase 1: Implementation
  230| 
  231| Study the existing architecture, patterns, conventions and test patterns first. Then, per task: implement to spec following those patterns (Karpathy principles govern style), with tests for the happy path, error conditions and edge cases — the runnable-check floor from CLAUDE.loa.md applies. Report per Verification above.
  232| 
  233| ## Phase 2: Feedback Integration Loop
```

### The PR's diff hunk covering these lines

```diff
@@ -218,9 +218,9 @@ ### Task Tracking: Beads vs TaskCreate
 
 Spec: `.claude/protocols/beads-preflight.md`; command reference: `resources/REFERENCE.md` §Beads Workflow.
 
-## Phase -1: Context Assessment and Parallel Task Splitting
+## Phase -1: Scope and Parallel Task Splitting
 
-`wc -l grimoires/loa/{prd,sdd,sprint}.md grimoires/loa/a2a/*.md 2>/dev/null`: under 3,000 lines SMALL (sequential); 3,000–8,000 MEDIUM (parallel when 3+ independent tasks); over 8,000 LARGE (split). MEDIUM/LARGE: `resources/REFERENCE.md` §Parallel Implementation Guidelines.
+Parallelise (`parallel_threshold`) when the scope warrants; the lead decides. With 3+ independent tasks, split per task: `resources/REFERENCE.md` §Parallel Implementation Guidelines.
 
 ## Phase 0: Feedback and Context Check
 
```


## P13 — pr-13 · `.claude/data/constraints.json` lines 1235–1235 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `head/.claude/loa/CLAUDE.loa.md:101` — the `agent_teams_constraints` block still carries the hand-set hash `c020-teamcreate` and short hand-written rows; the canonical `generate-constraints.sh` renders the rows from `constraints.json` and takes the file to 9,466 B > 9,216 B.
**File:** `head/.claude/loa/CLAUDE.loa.md:101-108`; `head/.claude/data/constraints.json:1235,1256,1277,1298,1319`; `head/tools/check-prompt-budget.sh:53`
**Suggestion:** Reproduced on a scratch copy of head: run `generate-constraints.sh`, then `check-prompt-budget.sh` → `CLAUDE.loa.md 9466 B (limit 9216) BREACH`. The PR shortens the five C-TEAM `why` strings in `constraints.json` (their only consumer is this block) but does not regenerate the block, so the edit has no effect on the shipped file and the 17-byte headroom hides a latent failure of PB-9 / the CI gate the moment anyone regenerates. The same drift exists in base (10,716 B > 10,240 B after a run), so this is inherited, but the PR touched exactly these strings and lowered the limit. Either regenerate the block (and shorten the C-TEAM texts until the rendered file fits) or raise `LOA_LIMIT` to cover the canonical render; in both cases `--dry-run` should be clean before merge.
**Benefit:** "Lean already" means the generator's output fits, not just the hand-edited file.
```

```text
### [MED-003] The budget gate holds only on the hand-edited file: a canonical `generate-constraints.sh` render breaches it
- **File:** `head/.claude/loa/CLAUDE.loa.md:101-108` (block hash `c020-teamcreate`, hand-written rows); `head/.claude/data/constraints.json:1235,1256,1277,1298,1319` (the five C-TEAM `why` strings the PR shortened); `head/tools/check-prompt-budget.sh:53` (`LOA_LIMIT = 9216`)
- **Confidence:** high
- **Issue:** Reproduced on a scratch copy of head: `generate-constraints.sh` (rc 0) rewrites the `agent_teams_constraints` block from `constraints.json` (hash `12c50d60ff9c0dbf`), the file grows to 9,466 B, and `check-prompt-budget.sh` reports `CLAUDE.loa.md: 9466 B > 9216 B  BREACH`. The PR edits the five C-TEAM `why` strings whose only consumer is this block but never regenerates it, so those edits have no effect on the shipped file, and 17 B of headroom hides a latent PB-9 / CI failure. Inherited (base renders to 10,716 B > 10,240 B), but this PR touched exactly these strings and lowered the limit.
- **Fix:** Regenerate the block and shorten the C-TEAM texts until the rendered file fits, or raise `LOA_LIMIT` to cover the canonical render; `generate-constraints.sh --dry-run` should be clean before merge.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html
```

### Head file context (line| text)

```text
 1225|     },
 1226|     {
 1227|       "id": "C-TEAM-001",
 1228|       "name": "lead_only_planning_skills",
 1229|       "category": "agent_teams",
 1230|       "rule_type": "MUST",
 1231|       "text": "restrict planning, orchestration, deployment, and lifecycle management skills to the team lead — teammates MUST NOT invoke these (see Skill Invocation Matrix for full list; enforced by `team-skill-guard.sh`)",
 1232|       "text_variants": {
 1233|         "claude-loa-md": "MUST restrict planning skills to team lead only — teammates implement, review, and audit only"
 1234|       },
 1235|       "why": "Planning artifacts (PRD, SDD, sprint plan) assume a single writer; concurrent invocation corrupts them.",
 1236|       "order": 0,
 1237|       "layers": [
 1238|         {
 1239|           "target": "claude-loa-md",
 1240|           "section": "agent_teams_constraints",
 1241|           "render_as": "table_row"
 1242|         }
 1243|       ],
 1244|       "severity": "critical",
 1245|       "source_incident": "#337"
```

### The PR's diff hunk covering these lines

```diff
@@ -1232,7 +1232,7 @@
       "text_variants": {
         "claude-loa-md": "MUST restrict planning skills to team lead only — teammates implement, review, and audit only"
       },
-      "why": "Planning skills produce single artifacts (PRD, SDD, sprint plan) that assume single-writer semantics; concurrent invocation would corrupt state",
+      "why": "Planning artifacts (PRD, SDD, sprint plan) assume a single writer; concurrent invocation corrupts them.",
       "order": 0,
       "layers": [
         {
```


## P14 — pr-05 · `grimoires/loa/a2a/sprint-1/reviewer.md` lines 1–1 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `grimoires/loa/a2a/sprint-1/reviewer.md:1` — the report has no `## AC Verification` section, no stated assumptions, no test evidence and no CHANGELOG entry, while all three hunks change runtime behaviour.
**File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (= `pr/PR.md:1`)
**Suggestion:** Describe each behaviour change as such, link the issue that motivates reverting cycle-119 (hook), cycle-109 #883 (adapter) and R-004 bd-m1o6 (state), and add a fixture/test per change.
**Benefit:** Reviewers can tell an intended revert from an accidental one.
```

```text
### [MED-002] Security-relevant behaviour change shipped as "refactor" with no verification or documentation
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (= `pr/PR.md:1`)
- **Issue:** All three hunks revert documented fixes (cycle-119 C15, cycle-109 #883, R-004 bd-m1o6). The diff touches no test, fixture or CHANGELOG (`grep -c CHANGELOG pr/head.diff` → 0). No documentation-coherence report exists under `grimoires/loa/a2a/subagent-reports/`, and `reviewer.md` has no `## AC Verification` section. The hook's new comment documents a different gap than the one introduced.
- **Fix:** Describe each change as a behaviour change with the motivating issue; add a fixture/test per change and a CHANGELOG entry for the hook.
- **Reference:** CWE-1059 https://cwe.mitre.org/data/definitions/1059.html
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P15 — pr-08 · `.claude/scripts/ledger-lib.sh` lines 179–179 · region inside the PR's diff · enclosing symbol: _write_ledger

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/ledger-lib.sh:156 — Regression of the bug 20260808-a008c6 guard: `jq empty` accepts any well-formed JSON stream, not just a single object. `null` passes, and the stamp at :179 turns it into `{"last_updated":"…"}`, which replaces the whole ledger with an empty-ish object while returning success (silent data loss). Multi-document content (`{}{}`) also passes and writes two concatenated objects, leaving the ledger corrupt. Whitespace-only content is no longer rejected up front either. Restore the `jq -es 'length == 1 and (.[0] | type == "object")'` check.
```

### Head file context (line| text)

```text
  169|         echo "ERROR: Could not acquire ledger lock within ${LEDGER_LOCK_TIMEOUT}s" >&2
  170|         exec 9>&-
  171|         return 1
  172|     fi
  173| 
  174|     # Backup before write
  175|     ensure_ledger_backup
  176| 
  177|     # Update last_updated timestamp
  178|     local updated_content
  179|     updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
  180|     if [[ -z "$updated_content" ]]; then
  181|         echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
  182|         flock -u 9
  183|         exec 9>&-
  184|         return $LEDGER_ERROR
  185|     fi
  186| 
  187|     # SECURITY (HIGH-001): Atomic write via temp file + mv
  188|     local tmp_file="${ledger_path}.tmp.$$"
  189|     if ! echo "$updated_content" > "$tmp_file"; then
```

### The PR's diff hunk covering these lines

```diff
@@ -174,7 +176,7 @@
 
     # Update last_updated timestamp
     local updated_content
-    updated_content=$(printf '%s' "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
+    updated_content=$(echo "$content" | jq --arg ts "$(now_iso)" '.last_updated = $ts')
     if [[ -z "$updated_content" ]]; then
         echo "ERROR: timestamp stamping produced empty content, aborting write" >&2
         flock -u 9
```


## P16 — pr-13 · `.claude/data/skill-includes/context_discipline.md` lines 2–2 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/data/skill-includes/context_discipline.md:2 — The new include points to the bare filename `tool-result-clearing.md`; the base version gave the resolvable `.claude/protocols/tool-result-clearing.md`. It also drops the write-routing ("decisions → Decision Log, issues → Technical Debt", line 5). structured-memory.md still names the Decision Log as recovery-critical. This regression ships into all ten SKILL.md files, e.g. head/.claude/skills/implementing-tasks/SKILL.md:124.
```

### Head file context (line| text)

```text
    1| ## Context Discipline
    2| 
    3| Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
    4| ≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
    5| accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
    6| from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
    7| "Session Continuity"; end / pre-compaction: update it.
    8| 
```

### The PR's diff hunk covering these lines

```diff
@@ -1,7 +1,7 @@
 ## Context Discipline
 
-Follow `.claude/protocols/tool-result-clearing.md`: single result >2K tokens / accumulated >5K /
-full file >3K / session >15K → extract findings (≤10 files, ≤20 words, file:line) to NOTES.md
-and reason from that synthesis. Big artefacts: `notes-guard.sh read --file F --section <H>` /
-`--index` before a blind Read. Start: read NOTES.md "Session Continuity"; end / pre-compaction:
-update it (decisions → Decision Log, issues → Technical Debt).
+Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
+≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
+accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
+from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
+"Session Continuity"; end / pre-compaction: update it.
```


## P17 — pr-12 · `auditing-security/resources/ADVERSARIAL-REVIEW.md` lines 58–58 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md:68 — The docs say the sidecar row `payload` is "the model's finding as normalised", but `_write_rejected_sidecar` is still passed the raw `$finding` (adversarial-review.sh:1311). The same mis-statement is in auditing-security/resources/ADVERSARIAL-REVIEW.md:58 and tests/fixtures/dissent-rejected/README.md:15.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P18 — pr-05 · `.claude/scripts/workflow-state.sh` lines 401–401 · region OUTSIDE the PR's diff (nearest changed line 312 lines away) · enclosing symbol: main

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/scripts/workflow-state.sh:83` — `get_completed_sprints` counts every `a2a/sprint-*` directory with a COMPLETED marker, while `get_total_sprints` (`:70`) counts `## Sprint N` headings in the current `sprint.md`; `determine_state` (`:148`) treats `completed >= total` as `STATE_COMPLETE`, so a new cycle with one historical COMPLETED directory reports `complete` and suggests `/deploy-production` before any current sprint has started.
**File:** `head/.claude/scripts/workflow-state.sh:83-89`; consumers `:148`, `:243`, `:401`
**Issue:** Numerator and denominator are drawn from different populations. The base loop `for ((i = 1; i <= total; i++))` was the fix for exactly this (live repo comment R-004 bd-m1o6: "this used to count ALL historical a2a/sprint-* dirs … reported nonsense like completed=100/total=1 (progress 95%)"). The head reverts it. `determine_state` and `main` still iterate `sprint-1..total`, so the script contradicts itself: `Sprints: 5/3 complete`.
**Why This Matters:** `workflow-state.sh --json` feeds `/loa`, status surfaces and run-mode next-step suggestions. A false `complete` state recommends deployment of unimplemented work; the result is also cached (`store_cache`, `:415`) so it persists until prd/sdd/sprint/ledger mtimes change.
**Required Fix:** Restore the loop scoped to `1..$(get_total_sprints)`. If the motivation is that a2a directories carry ledger global IDs, resolve the active cycle's sprint IDs from `ledger.json` (as `get_current_sprint` at `:53` already does) and use that same list in `get_completed_sprints`…
```

### Head file context (line| text)

```text
  391|     description=$(get_state_description "${state}" "${current_sprint}")
  392| 
  393|     # Build JSON result (used for both output and caching)
  394|     local json_result
  395|     json_result=$(cat <<EOF
  396| {
  397|   "state": "${state}",
  398|   "description": "${description}",
  399|   "current_sprint": "${current_sprint}",
  400|   "total_sprints": ${total_sprints},
  401|   "completed_sprints": ${completed_sprints},
  402|   "progress_percent": ${progress},
  403|   "suggested_command": "${suggested_command}",
  404|   "files": {
  405|     "prd_exists": $([ -f "${PRD_FILE}" ] && echo "true" || echo "false"),
  406|     "sdd_exists": $([ -f "${SDD_FILE}" ] && echo "true" || echo "false"),
  407|     "sprint_exists": $([ -f "${SPRINT_FILE}" ] && echo "true" || echo "false")
  408|   }
  409| }
  410| EOF
  411| )
```


## P19 — pr-05 · `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` lines 205–205 · region OUTSIDE the PR's diff (nearest changed line 15 lines away) · enclosing symbol: _complete_nonstreaming

### The reviewer's finding(s) citing this region

```text
**Severity:** HIGH | **Confidence:** high | **Criterion:** CQ-TC Test Coverage
**File:** `head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:41` (former definition site; `class AnthropicAdapter` now follows the logger directly)
**Issue:** `.claude/adapters/tests/test_anthropic_adapter_billing_class.py` exists in the live repository and does `"from loa_cheval.providers.anthropic_adapter import _is_billing_class_error"` at `:205` and `:213`, and asserts `pytest.raises(ProviderUnavailableError)` at `:102-158`. The PR does not touch this file. The imports are function-local, so collection succeeds but nine tests fail at runtime (three `ImportError`, six wrong exception type). This corrects the review's "collection fails" wording; the outcome is still a red adapters suite on merge.
**Fix:** Keep the helper (preferred). If the behaviour change is intentional, update or remove the test in this PR and state the reason in `PR.md`.
**Reference:** CWE-1059 Insufficient Technical Documentation https://cwe.mitre.org/data/definitions/1059.html
```

### Head file context (line| text)

```text
  195|         url: str,
  196|         headers: Dict[str, str],
  197|         body: Dict[str, Any],
  198|     ) -> CompletionResult:
  199|         """Legacy non-streaming path retained behind LOA_CHEVAL_DISABLE_STREAMING=1
  200|         kill switch (Sprint 4A operator backstop)."""
  201|         start = time.monotonic()
  202| 
  203|         status, resp = http_post(
  204|             url=url,
  205|             headers=headers,
  206|             body=body,
  207|             connect_timeout=self.config.connect_timeout,
  208|             read_timeout=self.config.read_timeout,
  209|         )
  210| 
  211|         latency_ms = int((time.monotonic() - start) * 1000)
  212| 
  213|         # Handle errors
  214|         if status == 429:
  215|             raise RateLimitError(self.provider)
```


## P20 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 19–36 · region OUTSIDE the PR's diff (nearest changed line 91 lines away) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
**Severity:** LOW | **Confidence:** high | **Criterion:** CQ-DC Documentation
**Component:** `head/tools/check-no-swallowed-jq.sh:135` (also header `:19-36`; `head/.claude/scripts/ledger-lib.sh:152-156`)
**Description:** The new Step 1 comment documents fixture skipping only; the header's detection-logic list never mentions heredocs; the ledger comment still cites `bug 20260808-a008c6` above a guard that no longer fully prevents it; the adapter's module docstring no longer mentions the NUL case it used to handle. No documentation-coherence report exists for the task.
**Remediation:** Once HIGH-001..003 are fixed, document the exec-heredoc rule in the header list and keep the ledger comment accurate to the check it sits above.
```

### Head file context (line| text)

```text
    9| # behind KF-004 (zero-findings canonical verdicts masking real findings,
   10| # recurrence ≥20) and KF-015 (silent-clean red-team gate pass, 4/4 sprints).
   11| # See grimoires/loa/known-failures.md.
   12| #
   13| # Verdict/finding/count-bearing jq extraction MUST funnel through `jq_strict`
   14| # (.claude/scripts/compat-lib.sh) so parse failures stay LOUD. The repo
   15| # already forbids the analogous shape for `git stash`
   16| # (.claude/rules/stash-safety.md, #555); this scanner fences the jq class.
   17| # Modeled on tools/check-no-raw-sha256sum.sh (KF-012 precedent).
   18| #
   19| # Detection logic (in order):
   20| #   1. Default mode scans the ENFORCED_FILES gate-critical set plus the
   21| #      extension-agnostic .claude/scripts/red-team-* glob (new red-team
   22| #      scripts are auto-enforced even without a .sh extension — DISS-001;
   23| #      the _is_script filter below decides scriptness, not the glob). `--root <dir>` scans a directory tree instead (used
   24| #      by the bats contract tests and the incremental #1025 sweep).
   25| #   2. File-type filter (--root mode): .sh/.bash/.legacy/.bats extensions or
   26| #      a bash/sh shebang — same approach as check-no-raw-sha256sum.sh, so
   27| #      extensionless shell scripts can't slip through (DISS-002 class).
   28| #   3. Skip line-leading comments (`# ...`).
   29| #   4. Skip lines with the `# check-no-swallowed-jq: ok` suppression marker.
   30| #      Un-migrated legacy sites on the enforced set carry this marker with a
   31| #      tracking note (`pending #1025 sweep`); NEW sites are flagged at PR
   32| #      time. Use sparingly, with reviewer rationale.
   33| #   5. Match: a jq invocation followed on the same line by `|| echo` or
   34| #      `|| printf`. `2>/dev/null` is deliberately NOT required for the
   35| #      match — stderr suppression only hides diagnostics; the `||` default
   36| #      is what swallows the verdict.
   37| #
   38| # **Tripwire scope (NOT exhaustive defense)**: same caveats as
   39| # check-no-raw-sha256sum.sh — variable-expanded/eval/printf-assembled jq,
   40| # multi-line forms, and the sibling `|| true` shape are out of scope here.
   41| # The jq_strict helper + its bats contract (tests/unit/compat-lib-jq-strict
   42| # .bats) are the load-bearing boundary; this scanner is one tripwire layer.
   43| # Remaining repo-wide sites are follow-up sweep work tracked in #1025.
   44| #
   45| # Usage:
   46| #   tools/check-no-swallowed-jq.sh                 # scan enforced gate-critical set
```


## P21 — pr-13 · `git-branch-prune.sh` lines 76–76 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/hooks/session-start/loa-context-class.sh:70`
**Criterion:** ARCH-ST: Standards Compliance
**Description:** `payload="$(timeout 2 cat 2>/dev/null || true)"`. `.claude/protocols/cross-platform-shell.md:162` lists "`timeout [0-9]` (bare) | error | Not available on macOS; use `run_with_timeout()`". On a host without GNU coreutils the command fails, `|| true` and `2>/dev/null` swallow it, and the payload is empty. Reproduced: with a PATH lacking `timeout` and `{"model":"claude-haiku-4-5-20251001"}` on stdin the record is `long` / `default` / model `null`; with `timeout` present it is `standard` / `model` / 200000. Today this is masked by MED-001; it becomes live the moment the harness exposes a model.
**Remediation:**
```bash
if command -v timeout >/dev/null 2>&1; then payload="$(timeout 2 cat 2>/dev/null || true)"
else payload="$(cat 2>/dev/null || true)"; fi
```
or source `compat-lib.sh` and use `run_with_timeout 2 cat` (the `command -v timeout` guard is the pattern `git-branch-prune.sh:76` already uses). `post-compact-reminder.sh:224` carries the same bare call; fixing both in one pass is cheap.
**References:** CWE-392 Missing Report of Error Condition — https://cwe.mitre.org/data/definitions/392.html
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P22 — pr-12 · `tests/unit/adversarial-review-companion.bats` lines 72–72 · region inside the PR's diff · enclosing symbol: invoke_dissenter

### The reviewer's finding(s) citing this region

```text
### [LOW-006] Tests miss every path above
- **LOW** (confidence: high) `head/tests/unit/adversarial-review-companion.bats:107-187` — the seven CMP cases cover happy path, failure classes and `false`; none covers the shared hop, an exhausted primary with a completed companion, an interrupted run, the other boolean spellings, a multi-hop companion, or a companion with rejected payloads; the stub `invoke_dissenter` (`:72`) ignores its prompt-file arguments, so a regression that wrote the prompts after the fork would pass CI (they are written before it, `:2032-2033`). Confirmed by cross-model review (DISS-C-009, review-gate run).
```

### Head file context (line| text)

```text
   62|         if [[ "$2" == "ok" ]]; then
   63|             jq -nc --arg v "$1" '{status:"APPROVED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$v],voices_dropped:[],chain_health:"ok",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
   64|         elif [[ "$2" == "walked" ]]; then
   65|             # one voice that walked internally: INV-6 (dropped == planned − succeeded) keeps voices_dropped
   66|             # empty; the walk shows as chain_health degraded, the succeeded id is the hop it landed on
   67|             jq -nc --arg v "$1" --arg hop "$3" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[],chain_health:"degraded",confidence_floor:"low",rationale:("stub inner walk from " + $v),single_voice_call:true}'
   68|         else
   69|             jq -nc --arg v "$1" --arg r "$3" --argjson e "$4" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:$r,exit_code:$e,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
   70|         fi
   71|     }
   72|     invoke_dissenter() {  # <sys> <user> <model> <timeout> <vq_sidecar> <type> [schema]
   73|         local model="$3" sidecar="$5"
   74|         echo "$model" >> "$CALLS"
   75|         local b="${BEHAVIOUR[$model]:-ok}"
   76|         case "$b" in
   77|             ok)
   78|                 [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
   79|                 jq -nc --arg m "$model" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"ADVISORY\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
   80|                 return 0 ;;
   81|             walked:*)
   82|                 local hop="${b#walked:}"
```

### The PR's diff hunk covering these lines

```diff
@@ -0,0 +1,187 @@
+#!/usr/bin/env bats
+# =============================================================================
+# tests/unit/adversarial-review-companion.bats — cycle-126 Sprint 2 (PRD FR-2.1,
+# SDD D-2.1). The companion voice: a dissent plans TWO chains from different
+# provider families, walks them, aggregates both envelopes (voices_planned 2),
+# records the companion's completion-based status and failure class, and can
+# be switched off per block (`companion_voice: false`).
+#
+# Whole-run harness: main() is sourced and run with `invoke_dissenter` replaced
+# by a stub keyed on the model (canned adapter envelopes + a valid single-voice
+# verdict_quality sidecar), a temp .loa.config.yaml, and no credentials present
+# (a keyless host: the Anthropic companion chain is `claude-headless` only).
+# =============================================================================
+
+setup() {
+    export LOA_MODELINV_LOG_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/model-invoke.jsonl"
+    export LOA_COST_LEDGER_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/cost-ledger.jsonl"
+    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
+    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
+    export PROJECT_ROOT
+    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
+    T="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
+    local saved_root="$PROJECT_ROOT"
+    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
+    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
+    PROJECT_ROOT="$saved_root"
+    export PROJECT_ROOT
+    SPRINT="sprint-comp-$$"
+    OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
+    # keyless host: no env keys, an empty dotenv dir (bats-gated seam)
+    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
+    export LOA_ADVERSARIAL_ENV_DIR="$T/env"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
+    # temp config: review enabled, primary gpt-5.5-pro with the OpenAI chain
+    CONFIG_FILE="$T/loa.config.yaml"
+    cat > "$CONFIG_FILE" <<'YAML'
+flatline_protocol:
+  code_review:
+    enabled: true
+    model: gpt-5.5-pro
+    budget_cents: 200
+    timeout_seconds: 30
+    fallback_chain:
+      - gpt-5.5
+      - codex-headless
+  security_audit:
+    enabled: true
+    model: gpt-5.5-pro
+    budget_cents: 200
+    timeout_seconds: 30
+    fallback_chain:
+      - codex-headless
+YAML
+    printf 'diff --git a/x.sh b/x.sh\n--- a/x.sh\n+++ b/x.sh\n@@ -1 +1 @@\n-a\n+b\n' > "$T/diff.patch"
+    CALLS="$T/calls.log"; : > "$CALLS"
+    # behaviour table: model → outcome (ok | walked:<hop> | auth | quota | timeout | malformed | unavailable).
+    # `walked:<hop>` models cheval's INNER fallback chain (one invocation, one sidecar whose
+    # succeeded id is the hop it landed on, the HTTP voice recorded as dropped) — the shape a
+    # keyless host produces (sprint-247: final_model gpt-5.5-pro, voices_succeeded_ids [codex-headless]).
+    declare -gA BEHAVIOUR=()
+    _vq() {  # <voice> <ok|fail|walked> <reason|hop> <exit> → single-voice verdict_quality envelope JSON
+        if [[ "$2" == "ok" ]]; then
+            jq -nc --arg v "$1" '{status:"APPROVED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$v],voices_dropped:[],chain_health:"ok",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
+        elif [[ "$2" == "walked" ]]; then
+            # one voice that walked internally: INV-6 (dropped == planned − succeeded) keeps voices_dropped
+            # empty; the walk shows as chain_health degraded, the succeeded id is the hop it landed on
+            jq -nc --arg v "$1" --arg hop "$3" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[],chain_health:"degraded",confidence_floor:"low",rationale:("stub inner walk from " + $v),single_voice_call:true}'
+        else
+            jq -nc --arg v "$1" --arg r "$3" --argjson e "$4" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:$r,exit_code:$e,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
…[hunk truncated]
```


## P23 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 468–468 · region inside the PR's diff · enclosing symbol: _derive_failure_mode

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:468 — The positional id fill (`DISS-` + index+1) can collide with an id the model stated on another finding. Reproduced: `[{"id":"DISS-002",…}, {no id}]` produces two findings both with `id: "DISS-002"`. Triage, the feedback file and the rejected-payload section all refer to findings by id. Use a namespace that can't collide (for example `DISS-D-NNN`, like the companion's `DISS-C-NNN`) or check against the ids already present.
```

### Head file context (line| text)

```text
  458| # required. A finding that carries everything but it gets the first sentence
  459| # of its `description` (≤ 200 chars) as `failure_mode` and is marked
  460| # `failure_mode_derived: true`; a missing `id` (the models emit `title`, not
  461| # `id`) is filled from the position (`DISS-NNN`, `id_derived: true`). Severity,
  462| # category and description are never touched, so a derived finding is gated
  463| # exactly like a stated one. Only the unenforced path reaches this (the call
  464| # site skips normalisation for schema-enforced payloads). stdin → stdout.
  465| _derive_failure_mode() {
  466|   local index="${1:-}"
  467|   jq --arg idx "$index" '
  468|     (if ((.id // "") | tostring | length) == 0 and ($idx | length) > 0
  469|      then .id = ("DISS-" + (($idx | tonumber) + 1 | tostring | if length < 3 then ("000" + .)[-3:] else . end))
  470|           | .id_derived = true
  471|      else . end)
  472|     | if ((.failure_mode // "") | tostring | length) == 0
  473|          and (.description | type) == "string" and (.description | length) > 0
  474|       then
  475|         (.description
  476|           | gsub("\\s+"; " ")
  477|           | (capture("^(?<s>.*?[.!?])(\\s|$)").s // .)
  478|           | .[0:200]) as $fm
```

### The PR's diff hunk covering these lines

```diff
@@ -445,9 +451,66 @@ _normalize_finding_for_validation() {
     | (if has("category") and (.category | type) == "string"
        then .category |= (gsub("^\\s+|\\s+$"; "") | ascii_downcase)
        else . end)
+  ' 2>/dev/null | _derive_failure_mode "$index"
+}
+
+# cycle-126 FR-2.2 (SDD D-2.2, KF-004): `failure_mode` is derivable, not
+# required. A finding that carries everything but it gets the first sentence
+# of its `description` (≤ 200 chars) as `failure_mode` and is marked
+# `failure_mode_derived: true`; a missing `id` (the models emit `title`, not
+# `id`) is filled from the position (`DISS-NNN`, `id_derived: true`). Severity,
+# category and description are never touched, so a derived finding is gated
+# exactly like a stated one. Only the unenforced path reaches this (the call
+# site skips normalisation for schema-enforced payloads). stdin → stdout.
+_derive_failure_mode() {
+  local index="${1:-}"
+  jq --arg idx "$index" '
+    (if ((.id // "") | tostring | length) == 0 and ($idx | length) > 0
+     then .id = ("DISS-" + (($idx | tonumber) + 1 | tostring | if length < 3 then ("000" + .)[-3:] else . end))
+          | .id_derived = true
+     else . end)
+    | if ((.failure_mode // "") | tostring | length) == 0
+         and (.description | type) == "string" and (.description | length) > 0
+      then
+        (.description
+          | gsub("\\s+"; " ")
+          | (capture("^(?<s>.*?[.!?])(\\s|$)").s // .)
+          | .[0:200]) as $fm
+        | .failure_mode = $fm | .failure_mode_derived = true
+      else . end
   ' 2>/dev/null
 }
 
+# cycle-126 FR-2.4 (SDD D-2.4): the repair model — `tiny` when an Anthropic
+# credential is PRESENT (env → .env.local → .env; the value is never read
+# out), else the `claude-headless` hop; LOA_ADVERSARIAL_REPAIR_MODEL pins it.
+_adv_cred_present() {  # <provider> → 0 when a credential is present (presence only)
+  local -a vars
+  case "$1" in
+    openai) vars=(OPENAI_API_KEY) ;;
+    anthropic) vars=(ANTHROPIC_API_KEY) ;;
+    google) vars=(GOOGLE_API_KEY GEMINI_API_KEY) ;;
+    *) return 1 ;;
+  esac
+  local v f val root="$PROJECT_ROOT"
+  for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && return 0; done
+  # bats-gated seam: point the dotenv lookup at a fixture directory
+  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_ADVERSARIAL_ENV_DIR:-}" ]]; then root="$LOA_ADVERSARIAL_ENV_DIR"; fi
+  for f in "$root/.env.local" "$root/.env"; do
+    [[ -f "$f" ]] || continue
+    for v in "${vars[@]}"; do
+      val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | sed -e 's/^[^=]*=//' -e "s/^[\"']//" -e "s/[\"'][[:space:]]*$//" -e 's/[[:space:]]*#.*$//')
+      [[ -n "$val" ]] && return 0
+    done
+  done
+  return 1
+}
+
+_repair_model() {  # <primary model> → the model the repair round-trip uses
+  if [[ -n "${LOA_ADVERSARIAL_REPAIR_MODEL:-}" ]]; then echo "$LOA_ADVERSARIAL_REPAIR_MODEL"; return 0; fi
+  if _adv_cred_present anthropic; then echo "tiny"; else echo "claude-headless"; fi
+}
+
 # _repair_violated_field <reject_reason>
 # Maps a _validate_finding_reason string to the single field name it
 # names as violated. Unknown/unmapped reasons yield "" (empty) — the
```


## P24 — pr-13 · `constructs-integration.md` lines 4–4 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/protocols/trajectory-evaluation.md:4 — The stubs claim they keep "the old path and its anchors stable", but this stub (and `constructs-integration.md:4`, `helper-scripts.md:4`, and every heading in `session-continuity.md` except the L1–L3 table) has no headings at all, so any `#anchor` into the old path now resolves to nothing. Either keep the headings with one-line pointers or drop the claim.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P25 — pr-05 · `.claude/hooks/safety/block-destructive-bash.sh` lines 811–811 · region inside the PR's diff · enclosing symbol: check_and_block

### The reviewer's finding(s) citing this region

```text
```bash
# head/.claude/hooks/safety/block-destructive-bash.sh:806-808
    if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
      _seg_find_root="${BASH_REMATCH[3]}"
    fi
```
```

### Head file context (line| text)

```text
  801|     # (cursor-advance so a later identical segment doesn't re-match the first
  802|     # occurrence's prefix), then test for a find-exec shape ending right here.
  803|     _seg_prefix="${_fr2_remaining%%"$rm_segment"*}"
  804|     _fr2_remaining="${_fr2_remaining#*"$rm_segment"}"
  805|     _seg_find_root=""
  806|     if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
  807|       _seg_find_root="${BASH_REMATCH[3]}"
  808|     fi
  809| 
  810|     rm_args_raw="${rm_segment#*rm}"
  811|     # shellcheck disable=SC2086,SC2206 — intentional word-split on rm args
  812|     read -r -a rm_args <<<"$rm_args_raw"
  813| 
  814|     # FR-2-REDIR: strip shell-redirect tokens before per-arg classification.
  815|     # A bare operator (empty tail, e.g. "2>", ">", "<<") consumes ITSELF
  816|     # plus the NEXT array element (the separate-word target of "2> /dev/null");
  817|     # an attached operator (non-empty tail glued on, e.g. "2>/dev/null",
  818|     # ">log", "2>&1") consumes only itself. A token that does not start
  819|     # with an optional fd-digit run immediately followed by an operator
  820|     # char is untouched — a real operand named "2" (no operator) or a
  821|     # filename with '>' NOT at the token start (e.g. "./build>x", one
```

### The PR's diff hunk covering these lines

```diff
@@ -800,15 +804,7 @@
     _fr2_remaining="${_fr2_remaining#*"$rm_segment"}"
     _seg_find_root=""
     if [[ "$_seg_prefix" =~ $_re_find_exec_prefix ]]; then
-      read -r -a _find_span_toks <<<"${BASH_REMATCH[3]}"
-      _find_root_count=0
-      for _ftok in ${_find_span_toks[@]+"${_find_span_toks[@]}"}; do
-        case "$_ftok" in
-          -*|'!'*|'('*|')'*|'\'*) break ;;
-          *) _find_root_count=$((_find_root_count + 1)); _seg_find_root="$_ftok" ;;
-        esac
-      done
-      [[ "$_find_root_count" -ne 1 ]] && _seg_find_root=""
+      _seg_find_root="${BASH_REMATCH[3]}"
     fi
 
     rm_args_raw="${rm_segment#*rm}"
```


## P26 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 153–153 · region inside the PR's diff · enclosing symbol: _is_script

### The reviewer's finding(s) citing this region

```text
head/tools/check-no-swallowed-jq.sh:153 — Lines carrying the suppression marker no longer call `_start_heredoc`. A suppressed line that also opens a heredoc (e.g. `jq … <<'EOF' || echo x  # check-no-swallowed-jq: ok`) no longer enters heredoc state, so its fixture/body text gets scanned as code (false positives), and the terminator line is treated as code too.
```

### Head file context (line| text)

```text
  143|         if (no_tabs == hd_term) { in_heredoc = 0; next }
  144|     }
  145|     next
  146| }
  147| 
  148| # Step 2: skip line-leading comments.
  149| /^[[:space:]]*#/ { next }
  150| 
  151| # Step 3: skip lines with the suppression marker. Requires `#` leader so
  152| # string-literal mentions don't silence real invocations.
  153| /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
  154| 
  155| # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
  156| # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
  157| # must be followed by whitespace (an invocation always has arguments, and
  158| # this keeps `jq_strict` from matching). RHS word-boundary on echo/printf
  159| # so `echo_handler` doesn't match.
  160| {
  161|     if (_line_has_swallowed_jq($0)) {
  162|         print FILENAME ":" NR ":" $0
  163|     }
```

### The PR's diff hunk covering these lines

```diff
@@ -155,33 +128,29 @@
         if (term != "") {
             hd_term = term
             in_heredoc = 1
-            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
-            cmd = _hd_command(scan, rs)
-            post = substr(scan, rs + rl)
-            hd_exec = (cmd in INTERP) || !hd_quoted || \
-                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
         }
     }
 }
 
+# Step 1: when in a heredoc body, skip fixture/documentation text until the
+# terminator. Without this, --root scans of bats tests can flag planted bad
+# examples instead of executable scanner code.
 in_heredoc {
-    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
+    if ($0 == hd_term) { in_heredoc = 0; next }
     if (hd_dash) {
         no_tabs = $0
         gsub(/^\t+/, "", no_tabs)
-        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
-    }
-    if (hd_exec) {
-        if ($0 ~ /^[[:space:]]*#/) next
-        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
-        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
+        if (no_tabs == hd_term) { in_heredoc = 0; next }
     }
     next
 }
 
+# Step 2: skip line-leading comments.
 /^[[:space:]]*#/ { next }
 
-/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }
+# Step 3: skip lines with the suppression marker. Requires `#` leader so
+# string-literal mentions don't silence real invocations.
+/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
 
 # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
 # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
```


## P27 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 1910–1927 · region inside the PR's diff · enclosing symbol: _fold_companion

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:1910 — MEDIUM: the companion's spend is copied only into `companion_voice.cost_cents`; `metadata.cost_usd` / tokens stay the primary's, so the envelope and trajectory under-report a two-voice run by about half while `budget_cents` is checked once before the fork (2010-2019)
```

```text
- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:2167-2171` — when every primary hop fails, `result` stays the last `api_failure` envelope; `_fold_companion` (`:1908-1916`) appends the companion's findings into it but never changes `metadata.status`, `degraded` or `error`.
**File:** `head/.claude/scripts/adversarial-review.sh:2167-2171`, `:1908-1916`
**Issue:** Reproduced (primary `gpt-5.5-pro`, `gpt-5.5`, `codex-headless` all `unavailable`; companion `claude-headless` ok): the written envelope is `metadata.status: api_failure`, `error: "API call failed with exit code 1"`, `findings: [DISS-C-001]`, `companion_voice.status: succeeded`, `verdict_quality: {status: DEGRADED, voices_planned: 4, voices_succeeded_ids: [claude-headless]}`. Every consumer keys on `metadata.status`: `write_output` (`:1725`) records the run as DEGRADED/api_failure, the review skill treats it as a failed dissent and falls back to single-model assessment, and the audit gate marks the review degraded — although a full, independent dissent was produced and paid for.
**Why This Matters:** "Nothing dropped" is the sprint's title. A completed voice is the most expensive artefact the script produces and this path discards its verdict while keeping its findings in an envelope that says the run failed.
**Required Fix:** When the primary chain exhausts and the companion completed, promote the envelope: `status: reviewed`, `degraded: true`, `primary_voice: {status: failed, attempts: […]}`, `companion_voice.counted_as: sole_voice`. Keep `api_failure` only when neither voice completed. Add …
```

```text
- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:2167-2171` — when every primary hop fails, `result` stays the last `api_failure` envelope and `_fold_companion` (`:1908-1916`) appends the companion's findings without touching `metadata.status`, `degraded` or `error`.
**Component:** `head/.claude/scripts/adversarial-review.sh:2167-2171`, `:1908-1916`
**Criterion:** ARCH-RE: Resilience; CQ-EH
**Reasoning Trace:**
> Reproduced (R2): primary `gpt-5.5-pro`, `gpt-5.5`, `gemini-3.1-pro` all `unavailable`, companion `claude-headless` ok → `metadata.status: api_failure`, `error: "API call failed with exit code 1"`, `degraded: false`, `findings: [DISS-C-001]`, `companion_voice: {status: succeeded, model: claude-headless}`, `verdict_quality: {status: DEGRADED, voices_planned: 4, voices_succeeded_ids: [claude-headless]}`.
**Description:** Every consumer keys on `metadata.status`: the trajectory/DEGRADED record in `write_output` (`:1725-1733`), the review skill's "unavailable → single-model assessment" rule, and the audit skill's degraded marker. A full, independent, paid-for dissent is filed under a failed run.
**Impact:** The sprint's title is "nothing dropped"; this path drops the most expensive artefact the script produces. On the audit gate it also turns a completed cross-model dissent into a `DEGRADED_SECURITY_REVIEW`.
**Remediation:** When the primary exhausts and the companion completed, promote the envelope: `status: reviewed`, `degraded: true`, `primary_voice: {status: failed, attempts: […]}`, `companion_voice.counted_as: sole_voice`; keep `api_failure…
```

### Head file context (line| text)

```text
 1900|   local final status rc cls="" comp_status="failed" cost_cents="null" attempts_json="[]"
 1901|   final=$(cat "$workdir/companion.final" 2>/dev/null || true)
 1902|   status=$(cat "$workdir/companion.status" 2>/dev/null || true)
 1903|   rc=$(cat "$workdir/companion.rc" 2>/dev/null || echo 1)
 1904|   [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
 1905|   [[ -s "$workdir/companion.attempts" ]] && attempts_json=$(jq -R . < "$workdir/companion.attempts" | jq -s .)
 1906|   rm -f "$workdir/vq-companion-synthetic.json"
 1907|   if [[ -s "$workdir/companion.result.json" ]] && jq empty < "$workdir/companion.result.json" 2>/dev/null; then
 1908|     comp_status="succeeded"
 1909|     local cres; cres=$(cat "$workdir/companion.result.json")
 1910|     cost_cents=$(echo "$cres" | jq -r '((.metadata.cost_usd // 0) * 10000 | round) / 100')
 1911|     result=$(jq -n --argjson p "$result" --argjson c "$cres" --arg pv "$primary_final" --arg cv "$final" '
 1912|       ($c.findings // [] | to_entries | map(.value + {id: ("DISS-C-" + ((.key + 1) | tostring | if length < 3 then ("000" + .)[-3:] else . end)), voice: $cv})) as $cf
 1913|       | $p
 1914|       | .findings = (($p.findings // []) | map(. + {voice: $pv})) + $cf
 1915|       | .metadata.rejected_summary = (($p.metadata.rejected_summary // []) + (($c.metadata.rejected_summary // []) | map(. + {voice: $cv})))
 1916|       | .metadata.rejected_count = (($p.metadata.rejected_count // 0) + ($c.metadata.rejected_count // 0))')
 1917|   else
 1918|     cls=$(_companion_failure_class "$status" "$rc")
 1919|     local synth="$workdir/vq-companion-synthetic.json"
 1920|     jq -nc --arg v "${final:-companion}" --arg r "$(_companion_drop_reason "$cls")" --argjson e "$(( rc <= 255 ? rc : 1 ))"       '{status: "FAILED", consensus_outcome: "consensus", truncation_waiver_applied: false, voices_planned: 1, voices_succeeded: 0,
 1921|         voices_succeeded_ids: [], voices_dropped: [{voice: $v, reason: $r, exit_code: $e, blocker_risk: "unknown"}],
 1922|         chain_health: "exhausted", confidence_floor: "low", rationale: "companion chain did not complete", single_voice_call: true}' > "$synth"
 1923|     result=$(echo "$result" | jq --arg pv "$primary_final" '.findings = ((.findings // []) | map(. + {voice: $pv}))')
 1924|   fi
 1925|   echo "$result" | jq --arg fam "$family" --arg chain "$chain" --arg model "$final" --arg st "$comp_status"       --arg cls "$cls" --argjson cost "$cost_cents" --argjson att "$attempts_json"       '.metadata.companion_voice = {planned: true, family: $fam, family_basis: "configured_primary",
 1926|         chain: ($chain | split(",")), model: (if $model == "" then null else $model end), status: $st,
 1927|         failure_class: (if $cls == "" then null else $cls end), cost_cents: $cost, attempts: $att}'
 1928| }
 1929| 
 1930| main() {
 1931|   local type="" sprint_id="" diff_file="" context_file="" model="" budget="" timeout=""
 1932|   local dry_run="false" json_output="true"
 1933| 
 1934|   # Parse arguments
 1935|   while [[ $# -gt 0 ]]; do
 1936|     case "$1" in
 1937|       --type)       type="$2"; shift 2 ;;
```

### The PR's diff hunk covering these lines

```diff
@@ -1719,6 +1795,138 @@ _extract_result_status() {
   printf '%s' "$status"
 }
 
+# =============================================================================
+# cycle-126 FR-2.1 (SDD D-2.1): the companion voice. A second, independent
+# chain from the OTHER provider family runs in parallel with the primary chain
+# and the two completed envelopes are aggregated (`voices_planned` 2). The
+# family is decided from the configured primary model; credential PRESENCE
+# (env → .env.local → .env, value never read) decides only where the
+# companion chain STARTS (an HTTP voice with no key is skipped straight to the
+# CLI hop); the companion's outcome is its actual completion. A companion whose
+# whole chain fails is a dropped voice (degraded, never blocking a review;
+# audit keeps its degraded rules) with a named failure class. Its rejected
+# payloads land in their own sidecar (`-companion` suffix), never the primary's.
+# =============================================================================
+_adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
+  local m="$1" prov=""
+  if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
+    # shellcheck source=generated-model-maps.sh
+    [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
+  fi
+  if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
+  if [[ -z "$prov" ]]; then
+    case "$m" in
+      anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
+      openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
+      google:*|gemini*|agy*) prov="google" ;;
+      *) prov="unknown" ;;
+    esac
+  fi
+  echo "$prov"
+}
+
+_companion_family() {  # <primary family> → the other family (google/unknown primaries get the Anthropic chain)
+  case "$1" in
+    anthropic) echo "openai" ;;
+    *) echo "anthropic" ;;
+  esac
+}
+
+_companion_chain() {  # <family> → space-separated chain, credential presence deciding the start
+  case "$1" in
+    anthropic) if _adv_cred_present anthropic; then echo "opus claude-headless"; else echo "claude-headless"; fi ;;
+    openai)    if _adv_cred_present openai; then echo "gpt-5.5-pro gpt-5.5 codex-headless"; else echo "codex-headless"; fi ;;
+    *) echo "" ;;
+  esac
+}
+
+_companion_failure_class() {  # <last status> <last exit code> → auth|model_unavailable|quota|timeout|malformed
+  local status="$1" rc="$2"
+  case "$status" in malformed_response) echo "malformed"; return 0 ;; esac
+  case "$rc" in
+    4) echo "auth" ;;
+    6) echo "quota" ;;
+    3|124) echo "timeout" ;;
+    5) echo "malformed" ;;
+    *) echo "model_unavailable" ;;
+  esac
+}
+
+_companion_drop_reason() {  # <failure class> → verdict-quality drop-reason enum
+  case "$1" in
+    quota) echo "RateLimited" ;;
+    auth|model_unavailable) echo "ProviderUnavailable" ;;
+    malformed) echo "EmptyContent" ;;
+    *) echo "Other" ;;
+  esac
+}
+
…[hunk truncated]
```


## P28 — pr-05 · `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` lines 223–223 · region inside the PR's diff · enclosing symbol: _complete_nonstreaming

### The reviewer's finding(s) citing this region

```text
head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:223 — The same regression in the non-streaming path (`LOA_CHEVAL_DISABLE_STREAMING=1`): billing-class 4xx errors become terminal `InvalidInputError` instead of chain-walkable `ProviderUnavailableError`. Removing `_is_billing_class_error`/`_BILLING_CLASS_TOKENS` also breaks any test or caller that imports them. The PR gives no reason for dropping the classification.
```

### Head file context (line| text)

```text
  213|         # Handle errors
  214|         if status == 429:
  215|             raise RateLimitError(self.provider)
  216| 
  217|         if status >= 500:
  218|             msg = _extract_error_message(resp)
  219|             raise ProviderUnavailableError(self.provider, f"HTTP {status}: {msg}")
  220| 
  221|         if status >= 400:
  222|             msg = _extract_error_message(resp)
  223|             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
  224| 
  225|         # Parse response
  226|         return self._parse_response(resp, latency_ms)
  227| 
  228|     def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
  229|         """Extract CompletionResult from Anthropic response (SDD §4.2.5)."""
  230|         content_blocks = resp.get("content", [])
  231| 
  232|         text_parts: List[str] = []
  233|         thinking_parts: List[str] = []
```

### The PR's diff hunk covering these lines

```diff
@@ -257,11 +220,6 @@
 
         if status >= 400:
             msg = _extract_error_message(resp)
-            if _is_billing_class_error(msg):
-                raise ProviderUnavailableError(
-                    self.provider,
-                    f"HTTP {status} billing-class: {msg}",
-                )
             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
 
         # Parse response
```


## P29 — pr-05 · `.claude/scripts/tests/test_dcg.sh` lines 367–382 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
### [MED-002] Security-critical hook change documented wrongly and shipped without fixtures
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/.claude/hooks/safety/block-destructive-bash.sh:773-775`
- **Issue:** The new comment says the only gap is flag-first `find -L root` and calls it "not a fixture requirement". It omits the multi-root shape the removed loop handled, and the PR adds no fixture for either shape. The only existing fixture, `.claude/scripts/tests/test_dcg.sh:367-382`, covers `find / … -exec rm {} \;` and is marked skip-tolerant, so nothing in CI would have caught CRITICAL-001. Documentation-audit red flag: uncommented (here, mis-commented) security-critical code.
- **Fix:** Correct the comment to the actual accepted shapes and add fixtures for multi-root ⇒ BLOCK, flag-first ⇒ BLOCK, single safe root ⇒ allow.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P30 — pr-05 · `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` lines 223–223 · region inside the PR's diff · enclosing symbol: _complete_nonstreaming

### The reviewer's finding(s) citing this region

```text
head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:223 — Same regression on the non-streaming path (LOA_CHEVAL_DISABLE_STREAMING=1): billing-class 4xx errors are now reported as terminal InvalidInputError instead of ProviderUnavailableError, so the fallback chain-walk is lost here too.
```

### Head file context (line| text)

```text
  213|         # Handle errors
  214|         if status == 429:
  215|             raise RateLimitError(self.provider)
  216| 
  217|         if status >= 500:
  218|             msg = _extract_error_message(resp)
  219|             raise ProviderUnavailableError(self.provider, f"HTTP {status}: {msg}")
  220| 
  221|         if status >= 400:
  222|             msg = _extract_error_message(resp)
  223|             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
  224| 
  225|         # Parse response
  226|         return self._parse_response(resp, latency_ms)
  227| 
  228|     def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
  229|         """Extract CompletionResult from Anthropic response (SDD §4.2.5)."""
  230|         content_blocks = resp.get("content", [])
  231| 
  232|         text_parts: List[str] = []
  233|         thinking_parts: List[str] = []
```

### The PR's diff hunk covering these lines

```diff
@@ -257,11 +220,6 @@
 
         if status >= 400:
             msg = _extract_error_message(resp)
-            if _is_billing_class_error(msg):
-                raise ProviderUnavailableError(
-                    self.provider,
-                    f"HTTP {status} billing-class: {msg}",
-                )
             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
 
         # Parse response
```


## P31 — pr-13 · `tools/check-prompt-budget.sh` lines 53–53 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/tools/check-prompt-budget.sh:53 — LOA_LIMIT is lowered to 9,216 B while head CLAUDE.loa.md is 9,199 B, which leaves 17 bytes of headroom. The next generated-constraint or hash change will fail CI. That is a budget cut to fit the current file, not a target, so leave reasonable slack.
```

### Head file context (line| text)

```text
   43|     --quiet|-q) QUIET=1; shift ;;
   44|     --help|-h) sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
   45|     *) echo "check-prompt-budget.sh: unknown arg $1" >&2; exit 2 ;;
   46|   esac
   47| done
   48| [[ -d "$ROOT/.claude" ]] || { echo "check-prompt-budget.sh: no .claude/ under $ROOT" >&2; exit 2; }
   49| 
   50| python3 - "$ROOT" "$JSON" "$QUIET" <<'PY'
   51| import glob, json, os, re, sys
   52| root, as_json, quiet = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
   53| SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 9216, 160000, 114688
   54| IMPERATIVE = re.compile(r"\b(read|load|source|include)\b", re.I)
   55| GUARD = re.compile(r"\b(if|when|only|optional|as needed|on demand|unless|may|see)\b", re.I)
   56| HISTORY = re.compile(r"cycle-[0-9]{3}|#[0-9]{3,4}|KF-[0-9]{3}")
   57| RES = re.compile(r"resources/([A-Za-z0-9_.-]+\.md)")
   58| 
   59| def size(p):
   60|     return os.path.getsize(p)
   61| 
   62| violations, skills = [], []
   63| for skill_md in sorted(glob.glob(os.path.join(root, ".claude/skills/*/SKILL.md"))):
```

### The PR's diff hunk covering these lines

```diff
@@ -50,7 +50,7 @@ done
 python3 - "$ROOT" "$JSON" "$QUIET" <<'PY'
 import glob, json, os, re, sys
 root, as_json, quiet = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
-SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 200000, 143360
+SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 9216, 160000, 114688
 IMPERATIVE = re.compile(r"\b(read|load|source|include)\b", re.I)
 GUARD = re.compile(r"\b(if|when|only|optional|as needed|on demand|unless|may|see)\b", re.I)
 HISTORY = re.compile(r"cycle-[0-9]{3}|#[0-9]{3,4}|KF-[0-9]{3}")

```


## P32 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 166–166 · region inside the PR's diff · enclosing symbol: load_adversarial_config

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:166 — companion_voice opt-out accepts only false|no|off|0; the YAML booleans False/FALSE/No/OFF leave the voice on (reproduced with companion_voice: False → planned true, voices_planned 2)
```

```text
- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:1910` — the companion's spend is converted to `companion_voice.cost_cents` but never added to `metadata.cost_usd`/`tokens_*`, which `write_output` logs to the trajectory (`:1665-1673`) and which the cost ledger reads. Observed: `cost_usd: 0.0123` with `companion_cost_cents: 1.23` extra. The budget pre-check at `:2014` estimates one voice while two are dispatched, and `.loa.config.yaml.example:1394` now claims "each voice ≤ this" with nothing enforcing it. Sum both voices into the envelope totals and estimate the budget for the planned voice count.
- **MEDIUM** (confidence: medium) `head/.claude/scripts/adversarial-review.sh:2182` — `wait "$companion_pid"` is unbounded. The companion chain is up to three hops, each bounded only by cheval's per-hop timeout (600 s floor for CLI hops), plus up to `ADV_REPAIR_MAX_PER_RUN` (5) serial repairs that now also go through `claude-headless` on a keyless host (`:1282`, `:511`). A primary that answered in 60 s can wait 30+ minutes for a stalled companion. Add a wait cap measured from the companion's start and classify the overrun as `failure_class: timeout`.
- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:166` — the opt-out accepts only `false|no|off|0`; the YAML booleans `False`, `FALSE`, `No`, `OFF` keep the voice on. Reproduced: `companion_voice: False` ⇒ `companion_voice.planned: true`, `voices_planned: 2`. Case-fold the comparison and report an unrecognised value.
```

```text
### [MED-002] Default-on egress of the redacted diff to a second provider family the operator did not configure
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/adversarial-review.sh:132` (`CONF_COMPANION_VOICE="true"` default), `:166` (only an explicit lowercase `false|no|off|0` disables), `:1828-1830` (google/unknown primaries are sent to the Anthropic chain), `:1835-1839`
- **Issue:** After upgrade, every dissent sends the full prepared prompt (redacted diff plus escalated files) to a provider family that appears nowhere in the block's `model`/`fallback_chain`, and the repair round-trip (`:509-512`) now sends the offending finding to `tiny`/`claude-headless` rather than the voice that produced it. Secret scanning still runs before both (`:811-816`), so this is a data-governance change, not a secret leak, but it is silent for a single-provider operator and is only announced in `.loa.config.yaml.example:1395-1400`. The dissent's own companion voice raised this (DISS-C-001).
- **Fix:** Log the companion family and provider at plan time at WARN level the first time it is enabled implicitly, document it in the CHANGELOG as a data-flow change, and consider defaulting to `companion_voice: false` on blocks whose chain is single-family.
- **Reference:** CWE-1188 Initialization of a Resource with an Insecure Default — https://cwe.mitre.org/data/definitions/1188.html
```

### Head file context (line| text)

```text
  156|     config_key="security_audit"
  157|   fi
  158| 
  159|   CONF_ENABLED=$(yq eval ".flatline_protocol.${config_key}.enabled // false" "$CONFIG_FILE" 2>/dev/null || echo "false")
  160|   CONF_MODEL=$(yq eval ".flatline_protocol.${config_key}.model // \"gpt-5.3-codex\"" "$CONFIG_FILE" 2>/dev/null || echo "gpt-5.3-codex")
  161|   CONF_TIMEOUT=$(yq eval ".flatline_protocol.${config_key}.timeout_seconds // 60" "$CONFIG_FILE" 2>/dev/null || echo "60")
  162|   CONF_BUDGET_CENTS=$(yq eval ".flatline_protocol.${config_key}.budget_cents // 150" "$CONFIG_FILE" 2>/dev/null || echo "150")
  163|   # `false // true` is true in jq/yq semantics — read the raw value and default only when absent
  164|   local _cv
  165|   _cv=$(yq eval ".flatline_protocol.${config_key}.companion_voice" "$CONFIG_FILE" 2>/dev/null || echo "null")
  166|   case "$_cv" in false|no|off|0) CONF_COMPANION_VOICE="false" ;; *) CONF_COMPANION_VOICE="true" ;; esac
  167|   CONF_ESCALATION_ENABLED=$(yq eval ".flatline_protocol.context_escalation.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  168|   CONF_SECONDARY_BUDGET=$(yq eval ".flatline_protocol.context_escalation.secondary_token_budget // $DEFAULT_SECONDARY_TOKEN_BUDGET" "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_SECONDARY_TOKEN_BUDGET")
  169|   CONF_MAX_FILE_LINES=$(yq eval ".flatline_protocol.context_escalation.max_file_lines // 500" "$CONFIG_FILE" 2>/dev/null || echo "500")
  170|   CONF_MAX_FILE_BYTES=$(yq eval ".flatline_protocol.context_escalation.max_file_bytes // 51200" "$CONFIG_FILE" 2>/dev/null || echo "51200")
  171|   CONF_SECRET_SCANNING=$(yq eval ".flatline_protocol.secret_scanning.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
  172| 
  173|   # Security invariant: secret_scanning MUST be on. Override if config says false.
  174|   if [[ "$CONF_SECRET_SCANNING" != "true" ]]; then
  175|     echo "CRITICAL: secret_scanning.enabled is false — overriding to true. Raw code must never be sent to external providers without redaction." >&2
  176|     CONF_SECRET_SCANNING="true"
```

### The PR's diff hunk covering these lines

```diff
@@ -159,6 +160,10 @@ load_adversarial_config() {
   CONF_MODEL=$(yq eval ".flatline_protocol.${config_key}.model // \"gpt-5.3-codex\"" "$CONFIG_FILE" 2>/dev/null || echo "gpt-5.3-codex")
   CONF_TIMEOUT=$(yq eval ".flatline_protocol.${config_key}.timeout_seconds // 60" "$CONFIG_FILE" 2>/dev/null || echo "60")
   CONF_BUDGET_CENTS=$(yq eval ".flatline_protocol.${config_key}.budget_cents // 150" "$CONFIG_FILE" 2>/dev/null || echo "150")
+  # `false // true` is true in jq/yq semantics — read the raw value and default only when absent
+  local _cv
+  _cv=$(yq eval ".flatline_protocol.${config_key}.companion_voice" "$CONFIG_FILE" 2>/dev/null || echo "null")
+  case "$_cv" in false|no|off|0) CONF_COMPANION_VOICE="false" ;; *) CONF_COMPANION_VOICE="true" ;; esac
   CONF_ESCALATION_ENABLED=$(yq eval ".flatline_protocol.context_escalation.enabled // true" "$CONFIG_FILE" 2>/dev/null || echo "true")
   CONF_SECONDARY_BUDGET=$(yq eval ".flatline_protocol.context_escalation.secondary_token_budget // $DEFAULT_SECONDARY_TOKEN_BUDGET" "$CONFIG_FILE" 2>/dev/null || echo "$DEFAULT_SECONDARY_TOKEN_BUDGET")
   CONF_MAX_FILE_LINES=$(yq eval ".flatline_protocol.context_escalation.max_file_lines // 500" "$CONFIG_FILE" 2>/dev/null || echo "500")
```


## P33 — pr-12 · `.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md` lines 68–68 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md:68 — The docs say the sidecar row `payload` is "the model's finding as normalised", but `_write_rejected_sidecar` is still passed the raw `$finding` (adversarial-review.sh:1311). The same mis-statement is in auditing-security/resources/ADVERSARIAL-REVIEW.md:58 and tests/fixtures/dissent-rejected/README.md:15.
```

### Head file context (line| text)

```text
   58| marked `failure_mode_derived: true` (a missing `id` is filled positionally, `id_derived: true`).
   59| Severity, category and description are never touched. Payloads that still fail go to the
   60| sidecar (`adversarial-rejected-<type>.jsonl`, `-companion` suffix for the second voice) **and**
   61| to `metadata.rejected_summary[]` as `{severity, title, anchor, reason, description_head}`.
   62| 
   63| **The contract (D-2.3).** When `rejected_summary` is non-empty the feedback file MUST contain a
   64| `## Rejected dissent payloads` section with one line per entry — `- <title> (<severity>, <anchor>)
   65| — <reason>: triaged as <real defect → counted under the matching heading | not a defect → why>`.
   66| `verdict-derive.sh` reads the sibling envelope (`adversarial-<gate>.json`, or `--envelope <path>`)
   67| and marks the trailer INCONSISTENT (exit 1) when the section is missing. Reading a sidecar row:
   68| `payload` is the model's finding as normalised, `reject_reason` the clause it failed, and
   69| `repair_attempted` / `repair_succeeded` whether the bounded repair round-trip ran.
   70| 
   71| **Repair loop (D-2.4).** The one bounded repair round-trip goes to `tiny` when an Anthropic
   72| credential is present, else to `claude-headless` (`LOA_ADVERSARIAL_REPAIR_MODEL` pins it) — no
   73| longer to the voice that produced the malformed finding. KF-004 evidence: the three real rejected
   74| payloads under `tests/fixtures/dissent-rejected/` now pass without a repair.
   75| 
```

### The PR's diff hunk covering these lines

```diff
@@ -37,3 +37,38 @@ # Adversarial Cross-Model Review — Phase 2.5 mechanics
 **Output**: Findings written to `grimoires/loa/a2a/{sprint_id}/adversarial-review.json`
 
 **Failure mode**: If adversarial review is unavailable (timeout, API error, budget exceeded), proceed with single-model assessment and log warning. No DEGRADED marker for review (only audit).
+
+## Two voices and the rejected-payload contract (cycle-126 FR-2)
+
+**Companion voice (D-2.1).** Every dissent plans a second chain from the *other* provider
+family — the primary configured on the block decides: an OpenAI-family primary gets the
+Anthropic chain (`opus` → `claude-headless`), an Anthropic-family primary gets the OpenAI chain
+(`gpt-5.5-pro` → `gpt-5.5` → `codex-headless`). Credential *presence* (env → `.env.local` →
+`.env`; the value is never read) decides only where the companion chain starts — with no key it
+starts at the CLI hop. Both chains walk in parallel; the two completed envelopes are aggregated
+(`verdict_quality.voices_planned: 2`, `voices_succeeded_ids` lists only completed voices). The
+companion's findings arrive re-numbered `DISS-C-NNN` with a `voice` field; the primary's carry
+`voice` too. `metadata.companion_voice` records `{planned, family, family_basis, chain, model,
+status: succeeded|failed, failure_class: auth|model_unavailable|quota|timeout|malformed|null,
+cost_cents, attempts}`; a companion whose chain fails is a dropped voice (degraded for an audit,
+never blocking a review). Opt-out per block: `flatline_protocol.{code_review,security_audit}.companion_voice: false`.
+
+**Tolerant schema (D-2.2).** A finding missing only `failure_mode` is no longer dropped: the
+first sentence of its `description` (≤ 200 chars) becomes `failure_mode` and the finding is
+marked `failure_mode_derived: true` (a missing `id` is filled positionally, `id_derived: true`).
+Severity, category and description are never touched. Payloads that still fail go to the
+sidecar (`adversarial-rejected-<type>.jsonl`, `-companion` suffix for the second voice) **and**
+to `metadata.rejected_summary[]` as `{severity, title, anchor, reason, description_head}`.
+
+**The contract (D-2.3).** When `rejected_summary` is non-empty the feedback file MUST contain a
+`## Rejected dissent payloads` section with one line per entry — `- <title> (<severity>, <anchor>)
+— <reason>: triaged as <real defect → counted under the matching heading | not a defect → why>`.
+`verdict-derive.sh` reads the sibling envelope (`adversarial-<gate>.json`, or `--envelope <path>`)
+and marks the trailer INCONSISTENT (exit 1) when the section is missing. Reading a sidecar row:
+`payload` is the model's finding as normalised, `reject_reason` the clause it failed, and
+`repair_attempted` / `repair_succeeded` whether the bounded repair round-trip ran.
+
+**Repair loop (D-2.4).** The one bounded repair round-trip goes to `tiny` when an Anthropic
+credential is present, else to `claude-headless` (`LOA_ADVERSARIAL_REPAIR_MODEL` pins it) — no
+longer to the voice that produced the malformed finding. KF-004 evidence: the three real rejected
+payloads under `tests/fixtures/dissent-rejected/` now pass without a repair.
```


## P34 — pr-13 · `.claude/protocols/tool-result-clearing.md` lines 13–13 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/protocols/tool-result-clearing.md:13 — the `long` column is labelled "≥ 1M" but the rule classes every model above 200K as `long`; the catalog holds six 400K-window models that get the 150K-token session threshold (37% of their window, against 15% for a 1M model). Label the column "> 200K" or add a middle class. (LOW)
```

```text
- **LOW** (confidence: high) `head/.claude/protocols/tool-result-clearing.md:13` — the rule (and the hook, `STANDARD_MAX=200000`) classes every model above 200K as `long`; the catalog holds six models with `context_window: 400000` which therefore get the 150K-token session threshold — 37% of their window, against 15% for the 1M class the label describes. The same wording is in the hook's header comment (`loa-context-class.sh:8`).
**Suggestion:** label the column "> 200K (default)" so it states the actual rule, or accept the 400K case explicitly in the Thresholds prose.
**Benefit:** readers of the protocol can predict the class of a 400K model without reading the hook.
```

```text
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/protocols/tool-result-clearing.md:13` (same wording at `head/.claude/hooks/session-start/loa-context-class.sh:8`)
- **Code:** `| Context Type | \`standard\` (≤ 200K) | \`long\` (≥ 1M, default) | Action |`
- **Issue:** the hook's rule is `(( CW <= STANDARD_MAX )) && CLASS="standard" || CLASS="long"` (line 98, `STANDARD_MAX=200000`). The catalog holds six models with `context_window: 400000`; they get the 150K-token session threshold — 37% of their window, against 15% for the 1M class the label describes.
- **Fix:** label the column "> 200K (default)" so the protocol states the actual rule, or add the 400K case to the Thresholds prose.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html
```

### Head file context (line| text)

```text
    3| The live rule is the 6-line `context_discipline` summary inlined in each SKILL.md. This file holds the shared detail those summaries point to.
    4| 
    5| ## Thresholds
    6| 
    7| Two context classes. `.run/context-class` (written by the SessionStart hook
    8| `loa-context-class.sh`; `/loa` prints it) names the one in force: **`long`** by default — the
    9| Claude 5 generation (≥ 1M context) — and **`standard`** when `LOA_CONTEXT_CLASS=standard` is set
   10| or the session model resolves to a catalog entry with `context_window ≤ 200000`. When unsure,
   11| read the file; when it is absent, assume `long`.
   12| 
   13| | Context Type | `standard` (≤ 200K) | `long` (≥ 1M, default) | Action |
   14| |--------------|---------------------|------------------------|--------|
   15| | Single search result | 2,000 tokens | 20,000 tokens | Apply clearing if exceeded |
   16| | Accumulated results | 5,000 tokens | 50,000 tokens | MANDATORY clearing |
   17| | Full file load | 3,000 tokens | 30,000 tokens | Single file only, synthesize immediately |
   18| | Session total | 15,000 tokens | 150,000 tokens | STOP and synthesize to NOTES.md |
   19| 
   20| ## 4-Step Clearing Process
   21| 
   22| 1. **Extract** high-signal findings: ≤10 files, ≤20 words each, absolute `file:line` references, relevance note.
   23| 2. **Synthesize** to `grimoires/loa/NOTES.md`:
```

### The PR's diff hunk covering these lines

```diff
@@ -4,12 +4,18 @@ # Tool Result Clearing Protocol
 
 ## Thresholds
 
-| Context Type | Threshold | Action |
-|--------------|-----------|--------|
-| Single search result | 2,000 tokens | Apply clearing if exceeded |
-| Accumulated results | 5,000 tokens | MANDATORY clearing |
-| Full file load | 3,000 tokens | Single file only, synthesize immediately |
-| Session total | 15,000 tokens | STOP and synthesize to NOTES.md |
+Two context classes. `.run/context-class` (written by the SessionStart hook
+`loa-context-class.sh`; `/loa` prints it) names the one in force: **`long`** by default — the
+Claude 5 generation (≥ 1M context) — and **`standard`** when `LOA_CONTEXT_CLASS=standard` is set
+or the session model resolves to a catalog entry with `context_window ≤ 200000`. When unsure,
+read the file; when it is absent, assume `long`.
+
+| Context Type | `standard` (≤ 200K) | `long` (≥ 1M, default) | Action |
+|--------------|---------------------|------------------------|--------|
+| Single search result | 2,000 tokens | 20,000 tokens | Apply clearing if exceeded |
+| Accumulated results | 5,000 tokens | 50,000 tokens | MANDATORY clearing |
+| Full file load | 3,000 tokens | 30,000 tokens | Single file only, synthesize immediately |
+| Session total | 15,000 tokens | 150,000 tokens | STOP and synthesize to NOTES.md |
 
 ## 4-Step Clearing Process
 
```


## P35 — pr-08 · `beads/loa-prime.sh` lines 13–14 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
Heredocs fed to an interpreter (`bash <<'EOF'`), piped to a shell, or unquoted with `$(jq … || echo …)` substitutions are executable code. Reproduced with `--root .claude/scripts`: base reports and head misses `anthropic-oracle.sh:300` (`"$(cat … | jq -r '.framework_version' || echo 'unknown')"` inside `cat << EOF`) and `beads/loa-prime.sh:33-35` (`$(br list --json | jq 'length' || echo "0")` inside `cat <<EOF`). Synthetic `bash <<'EOF'` and unquoted `cat <<EOF` bodies: base 1 hit each, head 0. The new Step 1 comment (`:135-137`) says fixture/documentation text is skipped; the code skips executable text too.
**Impact:** Count- and version-bearing extractions that the header (`:13-14`) says MUST go through `jq_strict` are certified clean by the head scanner.
**Fix:** Restore exec-aware classification (interpreter command, unquoted terminator, or pipe to a shell ⇒ scan the body, keeping the comment and marker skips inside that path). If exec heredocs are intentionally out of scope, that is a documented scope reduction: header, bats contract and an issue reference, not a silent change in a chore PR.
**Reference:** CWE-693 Protection Mechanism Failure https://cwe.mitre.org/data/definitions/693.html. Confirmed by cross-model review (DISS-C-003).
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P36 — pr-13 · `context-class.bats` lines 78–78 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/hooks/session-start/loa-context-class.sh:70 — `timeout 2 cat` needs GNU coreutils `timeout`, which stock macOS does not have. There the command is not found, `|| true` hides the error, the payload is always empty, and the model-based rule (the main way a ≤200K model gets `standard`) is silently turned off. The tests already plan for macOS (`stat -f %m` in context-class.bats:78), but the hook does not. Use `cat` alone (Claude Code closes stdin), or a `read -t` loop.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P37 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 811–816 · region OUTSIDE the PR's diff (nearest changed line 295 lines away) · enclosing symbol: assemble_dissent_context

### The reviewer's finding(s) citing this region

```text
### [MED-002] Default-on egress of the redacted diff to a second provider family the operator did not configure
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/.claude/scripts/adversarial-review.sh:132` (`CONF_COMPANION_VOICE="true"` default), `:166` (only an explicit lowercase `false|no|off|0` disables), `:1828-1830` (google/unknown primaries are sent to the Anthropic chain), `:1835-1839`
- **Issue:** After upgrade, every dissent sends the full prepared prompt (redacted diff plus escalated files) to a provider family that appears nowhere in the block's `model`/`fallback_chain`, and the repair round-trip (`:509-512`) now sends the offending finding to `tiny`/`claude-headless` rather than the voice that produced it. Secret scanning still runs before both (`:811-816`), so this is a data-governance change, not a secret leak, but it is silent for a single-provider operator and is only announced in `.loa.config.yaml.example:1395-1400`. The dissent's own companion voice raised this (DISS-C-001).
- **Fix:** Log the companion family and provider at plan time at WARN level the first time it is enabled implicitly, document it in the CHANGELOG as a data-flow change, and consider defaulting to `companion_voice: false` on blocks whose chain is single-family.
- **Reference:** CWE-1188 Initialization of a Resource with an Insecure Default — https://cwe.mitre.org/data/definitions/1188.html
```

### Head file context (line| text)

```text
  801| 
  802|       escalated_content+=$'\n'"--- FULL FILE: $filepath (P0 escalated) ---"$'\n'"$file_content"$'\n'
  803|       escalated_tokens=$(( escalated_tokens + file_tokens ))
  804|       escalated_count=$((escalated_count + 1))
  805|       escalation_used="true"
  806|       log "Escalated P0 file: $filepath ($file_tokens tokens, $escalated_count/$MAX_ESCALATED_FILES)"
  807|     done <<< "$diff_files"
  808|   fi
  809| 
  810|   # Secret scanning
  811|   if [[ "$CONF_SECRET_SCANNING" == "true" ]]; then
  812|     prepared_diff=$(secret_scan_content "$prepared_diff")
  813|     if [[ -n "$escalated_content" ]]; then
  814|       escalated_content=$(secret_scan_content "$escalated_content")
  815|     fi
  816|   fi
  817| 
  818|   # Build system prompt
  819|   local system_prompt
  820|   if [[ "$type" == "review" ]]; then
  821|     system_prompt='You are an adversarial code reviewer. Your role is to find production-impact problems that the primary reviewer may have missed.
  822| 
  823| RULES:
  824| - Find REAL problems: runtime failures, security exposure, spec violations, data corruption
  825| - Every BLOCKING finding MUST include a stable anchor (file:function_name or file:hunk_header)
  826| - Do NOT flag: style preferences, theoretical risks, items outside the provided diff
```


## P38 — pr-08 · `run-preflight.sh` lines 83–83 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/tools/check-no-swallowed-jq.sh:120 — removed arithmetic/here-string pre-strip and quote-parity check: `<<<'x: 1'` (run-preflight.sh:83), `$((1 << attempt))` (flatline-error-handler.sh:202) and `"…<<EOF…"` literals open a phantom heredoc whose terminator never appears, so the scanner skips the rest of the file; real swallow at run-preflight.sh:237 is no longer reported (silent-clean gate, KF-004/KF-015 class)
```

```text
so `<<<'x: 1'` matches as `<<'x`, `$((1 << attempt))` as `<< attempt`, and `"see <<EOF form"` as `<<EOF`. Heredoc mode begins with a terminator that never appears on its own line, and every remaining line is `next`-ed. Reproduced with `--root .claude/scripts`: base reports 248 sites, head 243; `run-preflight.sh:237` (`jq -r '.state // empty' "$f" 2>/dev/null || echo "unparseable"`) disappears because `run-preflight.sh:83` has `yq eval '.x' <<<'x: 1'`; `flatline-error-handler.sh:202` (`$((base_delay * (1 << attempt)))`) opens a phantom heredoc that hides the remainder of that file. Synthetic one-file cases (here-string, arithmetic shift, quoted literal): base 1 hit each, head 0.
**Impact:** A CI tripwire for KF-004 / KF-015 ("silent clean" incidents, header `:5-11`) now has that exact failure mode; one innocuous line disables the check for everything below it. The enforced set (`:60-65`) is unaffected on today's tree only because its here-strings are all `<<< "$var"`, which the regex happens not to match.
**Fix:** Restore the pre-strip and quote-parity logic before matching `<<`, or otherwise restrict the match to an unquoted, non-arithmetic, non-here-string `<<`; add a bats case per shape.
**Reference:** CWE-693 Protection Mechanism Failure https://cwe.mitre.org/data/definitions/693.html. Confirmed by cross-model review (DISS-C-003).
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P39 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 1872–1872 · region inside the PR's diff · enclosing symbol: _walk_companion_chain

### The reviewer's finding(s) citing this region

```text
…ay. `rejected_count` still increments and the sidecar row is written, so the envelope has `rejected_count > 0` with `rejected_summary: []` and `verdict-derive.sh` (which reads only `rejected_summary`) never asks for triage. Fall back to the raw `$finding` (as the sidecar does) or to a `{reason, index}` stub so the summary and the count never disagree.
- **MEDIUM** (confidence: high) `head/.claude/scripts/verdict-derive.sh:137` — the contract check is `grep -qE '^## Rejected dissent payloads'`: the heading alone satisfies it. The documented contract is "one line per entry" (`head/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md:64`); a file with the heading and no bullets passes with `n` rejected payloads untriaged. Count top-level bullets under the section and require `>= n`.
- **MEDIUM** (confidence: high) `head/.claude/scripts/adversarial-review.sh:1911-1916` — the fold drops the companion's `metadata.rejected_sidecar`; the envelope names only the primary's sidecar while the companion's rows live in `adversarial-rejected-<type>-companion.jsonl` (`:1872`, `:1233`). A reviewer following the docs' "Reading a sidecar row" cannot find the companion's file from the envelope, and an empty `-companion.jsonl` is left in the a2a directory on every run (observed: `adversarial-rejected-review-companion.jsonl` beside the envelope after a clean two-voice run). Record `companion_voice.rejected_sidecar` and remove the file when empty.
```

```text
### [MED-007] The companion's rejected sidecar is not named on the envelope, and an empty one is left behind every run
- **Severity:** MEDIUM (confidence: high, reproduced)
- **File:** `head/.claude/scripts/adversarial-review.sh:1911-1915` (fold drops `$c.metadata.rejected_sidecar`), `:1233` (`-companion` suffix), `:1872`
- **Issue:** Reproduced: after a clean two-voice run the a2a directory holds `adversarial-rejected-review-companion.jsonl` (empty) and the envelope's `metadata.rejected_sidecar` names only the primary's file; `companion_voice` has no `rejected_sidecar` key. A reviewer following "Reading a sidecar row" cannot find the companion's rows from the envelope, so a companion payload that failed normalisation is discoverable only by listing the directory.
- **Fix:** Record `companion_voice.rejected_sidecar` (and add it to a `metadata.rejected_sidecars[]` list), and remove the companion sidecar when it is empty.
- **Reference:** CWE-778 — https://cwe.mitre.org/data/definitions/778.html
```

### Head file context (line| text)

```text
 1862| }
 1863| 
 1864| # Walk the companion chain (runs in a background subshell). Writes into
 1865| # $workdir: companion.result.json, companion.final, companion.rc,
 1866| # companion.status, companion.attempts (one per line), companion.vq (paths of
 1867| # the attempts' verdict-quality sidecars).
 1868| _walk_companion_chain() {  # <workdir> <type> <sprint_id> <timeout> <diff_files> <model>...
 1869|   local workdir="$1" type="$2" sprint_id="$3" timeout="$4" diff_files="$5"; shift 5
 1870|   local m raw rc res status final="" last_status="" last_rc=0
 1871|   : > "$workdir/companion.attempts"; : > "$workdir/companion.vq"
 1872|   export _ADV_SIDECAR_TAG="companion"
 1873|   for m in "$@"; do
 1874|     rc=0
 1875|     local vq="$workdir/vq-companion-${m//[^A-Za-z0-9_-]/_}-$$-$RANDOM.json"
 1876|     raw=$(invoke_dissenter "$workdir/system-prompt.txt" "$workdir/user-prompt.txt" "$m" "$timeout" "$vq" "$type" "$SCRIPT_DIR/../schemas/wire/dissent-${type}.wire.json") || rc=$?
 1877|     [[ -s "$vq" ]] && echo "$vq" >> "$workdir/companion.vq"
 1878|     res=$(process_findings "$raw" "$type" "$m" "$sprint_id" "$rc" "$diff_files")
 1879|     status=$(_extract_result_status "$res")
 1880|     echo "${m}:${status}" >> "$workdir/companion.attempts"
 1881|     last_status="$status"; last_rc="$rc"
 1882|     if [[ "$status" != "malformed_response" && "$status" != "api_failure" ]]; then
```

### The PR's diff hunk covering these lines

```diff
@@ -1719,6 +1795,138 @@ _extract_result_status() {
   printf '%s' "$status"
 }
 
+# =============================================================================
+# cycle-126 FR-2.1 (SDD D-2.1): the companion voice. A second, independent
+# chain from the OTHER provider family runs in parallel with the primary chain
+# and the two completed envelopes are aggregated (`voices_planned` 2). The
+# family is decided from the configured primary model; credential PRESENCE
+# (env → .env.local → .env, value never read) decides only where the
+# companion chain STARTS (an HTTP voice with no key is skipped straight to the
+# CLI hop); the companion's outcome is its actual completion. A companion whose
+# whole chain fails is a dropped voice (degraded, never blocking a review;
+# audit keeps its degraded rules) with a named failure class. Its rejected
+# payloads land in their own sidecar (`-companion` suffix), never the primary's.
+# =============================================================================
+_adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
+  local m="$1" prov=""
+  if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
+    # shellcheck source=generated-model-maps.sh
+    [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
+  fi
+  if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
+  if [[ -z "$prov" ]]; then
+    case "$m" in
+      anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
+      openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
+      google:*|gemini*|agy*) prov="google" ;;
+      *) prov="unknown" ;;
+    esac
+  fi
+  echo "$prov"
+}
+
+_companion_family() {  # <primary family> → the other family (google/unknown primaries get the Anthropic chain)
+  case "$1" in
+    anthropic) echo "openai" ;;
+    *) echo "anthropic" ;;
+  esac
+}
+
+_companion_chain() {  # <family> → space-separated chain, credential presence deciding the start
+  case "$1" in
+    anthropic) if _adv_cred_present anthropic; then echo "opus claude-headless"; else echo "claude-headless"; fi ;;
+    openai)    if _adv_cred_present openai; then echo "gpt-5.5-pro gpt-5.5 codex-headless"; else echo "codex-headless"; fi ;;
+    *) echo "" ;;
+  esac
+}
+
+_companion_failure_class() {  # <last status> <last exit code> → auth|model_unavailable|quota|timeout|malformed
+  local status="$1" rc="$2"
+  case "$status" in malformed_response) echo "malformed"; return 0 ;; esac
+  case "$rc" in
+    4) echo "auth" ;;
+    6) echo "quota" ;;
+    3|124) echo "timeout" ;;
+    5) echo "malformed" ;;
+    *) echo "model_unavailable" ;;
+  esac
+}
+
+_companion_drop_reason() {  # <failure class> → verdict-quality drop-reason enum
+  case "$1" in
+    quota) echo "RateLimited" ;;
+    auth|model_unavailable) echo "ProviderUnavailable" ;;
+    malformed) echo "EmptyContent" ;;
+    *) echo "Other" ;;
+  esac
+}
+
…[hunk truncated]
```


## P40 — pr-12 · `.claude/scripts/adversarial-review.sh` lines 1814–1814 · region inside the PR's diff · enclosing symbol: _adv_family_of

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/adversarial-review.sh:1814 — `_adv_family_of` sources `generated-model-maps.sh` straight into the running shell, then indexes `${MODEL_PROVIDERS[$m]}` with an unvalidated model string. This skips the hardening that `_adv_input_budget_for_model` documents for exactly this case (audit slice C: `x[$(touch pwned)]` is evaluated arithmetically when the array ends up indexed). That hardening uses a `^[A-Za-z0-9._:/-]+$` guard and an isolated `bash -c` with pre-declared associative arrays. The new function also skips alias resolution through `MODEL_IDS`, so it can disagree with the budget resolver about which provider a model belongs to. Reuse the hardened resolver.
```

### Head file context (line| text)

```text
 1804| # companion chain STARTS (an HTTP voice with no key is skipped straight to the
 1805| # CLI hop); the companion's outcome is its actual completion. A companion whose
 1806| # whole chain fails is a dropped voice (degraded, never blocking a review;
 1807| # audit keeps its degraded rules) with a named failure class. Its rejected
 1808| # payloads land in their own sidecar (`-companion` suffix), never the primary's.
 1809| # =============================================================================
 1810| _adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
 1811|   local m="$1" prov=""
 1812|   if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
 1813|     # shellcheck source=generated-model-maps.sh
 1814|     [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
 1815|   fi
 1816|   if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
 1817|   if [[ -z "$prov" ]]; then
 1818|     case "$m" in
 1819|       anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
 1820|       openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
 1821|       google:*|gemini*|agy*) prov="google" ;;
 1822|       *) prov="unknown" ;;
 1823|     esac
 1824|   fi
```

### The PR's diff hunk covering these lines

```diff
@@ -1719,6 +1795,138 @@ _extract_result_status() {
   printf '%s' "$status"
 }
 
+# =============================================================================
+# cycle-126 FR-2.1 (SDD D-2.1): the companion voice. A second, independent
+# chain from the OTHER provider family runs in parallel with the primary chain
+# and the two completed envelopes are aggregated (`voices_planned` 2). The
+# family is decided from the configured primary model; credential PRESENCE
+# (env → .env.local → .env, value never read) decides only where the
+# companion chain STARTS (an HTTP voice with no key is skipped straight to the
+# CLI hop); the companion's outcome is its actual completion. A companion whose
+# whole chain fails is a dropped voice (degraded, never blocking a review;
+# audit keeps its degraded rules) with a named failure class. Its rejected
+# payloads land in their own sidecar (`-companion` suffix), never the primary's.
+# =============================================================================
+_adv_family_of() {  # <model alias or id> → anthropic | openai | google | unknown
+  local m="$1" prov=""
+  if ! declare -p MODEL_PROVIDERS >/dev/null 2>&1; then
+    # shellcheck source=generated-model-maps.sh
+    [[ -f "$SCRIPT_DIR/generated-model-maps.sh" ]] && source "$SCRIPT_DIR/generated-model-maps.sh" 2>/dev/null || true
+  fi
+  if declare -p MODEL_PROVIDERS >/dev/null 2>&1; then prov="${MODEL_PROVIDERS[$m]:-}"; fi
+  if [[ -z "$prov" ]]; then
+    case "$m" in
+      anthropic:*|claude*|opus*|sonnet*|haiku*|fable*|tiny|cheap) prov="anthropic" ;;
+      openai:*|gpt-*|codex*|o[0-9]*) prov="openai" ;;
+      google:*|gemini*|agy*) prov="google" ;;
+      *) prov="unknown" ;;
+    esac
+  fi
+  echo "$prov"
+}
+
+_companion_family() {  # <primary family> → the other family (google/unknown primaries get the Anthropic chain)
+  case "$1" in
+    anthropic) echo "openai" ;;
+    *) echo "anthropic" ;;
+  esac
+}
+
+_companion_chain() {  # <family> → space-separated chain, credential presence deciding the start
+  case "$1" in
+    anthropic) if _adv_cred_present anthropic; then echo "opus claude-headless"; else echo "claude-headless"; fi ;;
+    openai)    if _adv_cred_present openai; then echo "gpt-5.5-pro gpt-5.5 codex-headless"; else echo "codex-headless"; fi ;;
+    *) echo "" ;;
+  esac
+}
+
+_companion_failure_class() {  # <last status> <last exit code> → auth|model_unavailable|quota|timeout|malformed
+  local status="$1" rc="$2"
+  case "$status" in malformed_response) echo "malformed"; return 0 ;; esac
+  case "$rc" in
+    4) echo "auth" ;;
+    6) echo "quota" ;;
+    3|124) echo "timeout" ;;
+    5) echo "malformed" ;;
+    *) echo "model_unavailable" ;;
+  esac
+}
+
+_companion_drop_reason() {  # <failure class> → verdict-quality drop-reason enum
+  case "$1" in
+    quota) echo "RateLimited" ;;
+    auth|model_unavailable) echo "ProviderUnavailable" ;;
+    malformed) echo "EmptyContent" ;;
+    *) echo "Other" ;;
+  esac
+}
+
…[hunk truncated]
```


## P41 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 153–153 · region inside the PR's diff · enclosing symbol: _is_script

### The reviewer's finding(s) citing this region

```text
head/tools/check-no-swallowed-jq.sh:153 — A suppression-marker line no longer calls `_start_heredoc`. A heredoc opener with `# check-no-swallowed-jq: ok` on it (e.g. a fixture `cat <<EOF # check-no-swallowed-jq: ok`) is no longer tracked, so its body is scanned as top-level code (false positives on planted fixtures) and its terminator line is treated as code.
```

### Head file context (line| text)

```text
  143|         if (no_tabs == hd_term) { in_heredoc = 0; next }
  144|     }
  145|     next
  146| }
  147| 
  148| # Step 2: skip line-leading comments.
  149| /^[[:space:]]*#/ { next }
  150| 
  151| # Step 3: skip lines with the suppression marker. Requires `#` leader so
  152| # string-literal mentions don't silence real invocations.
  153| /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
  154| 
  155| # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
  156| # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
  157| # must be followed by whitespace (an invocation always has arguments, and
  158| # this keeps `jq_strict` from matching). RHS word-boundary on echo/printf
  159| # so `echo_handler` doesn't match.
  160| {
  161|     if (_line_has_swallowed_jq($0)) {
  162|         print FILENAME ":" NR ":" $0
  163|     }
```

### The PR's diff hunk covering these lines

```diff
@@ -155,33 +128,29 @@
         if (term != "") {
             hd_term = term
             in_heredoc = 1
-            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
-            cmd = _hd_command(scan, rs)
-            post = substr(scan, rs + rl)
-            hd_exec = (cmd in INTERP) || !hd_quoted || \
-                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
         }
     }
 }
 
+# Step 1: when in a heredoc body, skip fixture/documentation text until the
+# terminator. Without this, --root scans of bats tests can flag planted bad
+# examples instead of executable scanner code.
 in_heredoc {
-    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
+    if ($0 == hd_term) { in_heredoc = 0; next }
     if (hd_dash) {
         no_tabs = $0
         gsub(/^\t+/, "", no_tabs)
-        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
-    }
-    if (hd_exec) {
-        if ($0 ~ /^[[:space:]]*#/) next
-        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
-        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
+        if (no_tabs == hd_term) { in_heredoc = 0; next }
     }
     next
 }
 
+# Step 2: skip line-leading comments.
 /^[[:space:]]*#/ { next }
 
-/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }
+# Step 3: skip lines with the suppression marker. Requires `#` leader so
+# string-literal mentions don't silence real invocations.
+/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
 
 # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
 # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
```


## P42 — pr-08 · `.claude/adapters/cheval.py` lines 2585–2752 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157` — with the `except ValueError` branch removed, a prompt containing a NUL byte makes `Popen` raise `ValueError("embedded null byte")`, which is not an `OSError`, so it propagates raw out of `complete()`.
**File:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:132-165`
**Issue:** agy is argv transport: `_build_command` (line 245) puts the whole prompt on argv and `run_subprocess_pgkill` (line 132) exec's it. Verified in this environment: `subprocess.run(['true', 'a\x00b'])` raises `ValueError: embedded null byte`, and `isinstance(exc, OSError)` is `False`, so the remaining `except OSError` on line 157 does not catch it. cheval's walker (`.claude/adapters/cheval.py:2585-2752`) advances the chain only on typed cheval errors; its trailing `except Exception` returns `EXIT_CODES["API_ERROR"]`, so the run ends instead of walking to the gemini-api fallback. The shared base class for the other headless adapters still handles this case (`.claude/adapters/loa_cheval/providers/headless_cli.py:418` catches `(OSError, ValueError)` and `:454` emits the same "embedded NUL in the prompt?" message), so the agy adapter now diverges from the adapter contract.
**Why This Matters:** The prompt is untrusted review content (diffs and file bodies). A single NUL in a reviewed diff turns a recoverable provider failure into a hard crash of the dissent run, which is the degraded-verdict path KF-011 tracks. The PR description gives no reason the handler was considered dead code.
**…
```

```text
**Reasoning Trace:**
> `_build_command` places the flattened prompt on argv. `python3 -I -c "subprocess.run(['true','a\x00b'])"` raises `ValueError: embedded null byte`; `isinstance(exc, OSError)` is `False`. `subprocess.Popen` is invoked at `.claude/adapters/loa_cheval/providers/base.py:996`, before the helper's `try`, so nothing in `run_subprocess_pgkill` converts it. The cheval walker advances only on typed errors (`.claude/adapters/cheval.py:2681` `except ProviderUnavailableError … continue`); its catch-all at `:2777-2796` prints `API_ERROR` and returns. The sibling base class still handles this case: `.claude/adapters/loa_cheval/providers/headless_cli.py:418` catches `(OSError, ValueError)` and `:454` emits the same "embedded NUL in the prompt?" message.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P43 — pr-05 · `.claude/scripts/workflow-state.sh` lines 70–76 · region inside the PR's diff · enclosing symbol: get_total_sprints

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/scripts/workflow-state.sh:83-89` — `get_completed_sprints` counts every `a2a/sprint-*/COMPLETED`, including other cycles' sprints and `sprint-bug-*` micro-sprints, while `get_total_sprints` (`:70-76`) counts only the current `sprint.md`; `determine_state` at `:148` then returns `complete` for an unfinished plan.
**File:** `head/.claude/scripts/workflow-state.sh:83-89`; consumers at `:148`, `:390`, `:401`
**Issue:** The base loop iterated `sprint-1..total` and so was scoped to the current plan. Head replaces it with a directory scan. `completed >= total` is the completion test, `progress_percent` scales `completed/total`, and the result is written to the semantic cache keyed on prd/sdd/sprint/ledger mtimes, so the wrong state persists until one of those files changes.
**Evidence:** Temp grimoire with `sprint.md` declaring three sprints, `sprint-1/COMPLETED`, plus stale `sprint-7/COMPLETED` and `sprint-bug-108/COMPLETED` (the repo creates `sprint-bug-*` dirs, see `.claude/scripts/next-bug-sprint-id.sh:103`):
```

```text
counts every `a2a/sprint-*` directory with a `COMPLETED` marker (other cycles, `sprint-bug-*`, `sprint-archive`), while `get_total_sprints` (`:70-76`) still counts only `## Sprint N` headings in the current `sprint.md`. `determine_state` (`:148`) tests `completed >= total` **before** inspecting any per-sprint state, so stale or planted markers short-circuit the state machine to `complete`. The live repository's own `workflow-state.sh:84-88` carries the R-004 (bd-m1o6) comment naming this exact behaviour as the bug that produced "completed=100/total=1"; the PR reinstates it.
```

### Head file context (line| text)

```text
   60|                 .cycles[] | select(.id == $cycle) | .sprints[]? |
   61|                 select(.status != "completed" and .status != "archived") |
   62|                 .global_id
   63|             ' "${LEDGER_FILE}" 2>/dev/null | head -1
   64|         fi
   65|     fi
   66|     echo ""
   67| }
   68| 
   69| # Function: Get sprint count from sprint.md
   70| get_total_sprints() {
   71|     if [[ -f "${SPRINT_FILE}" ]]; then
   72|         grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
   73|     else
   74|         echo "0"
   75|     fi
   76| }
   77| 
   78| # Function: Count completed sprints
   79| get_completed_sprints() {
   80|     local count=0
   81|     local sprint_dirs
   82|     local a2a_dir="${_GRIMOIRE_DIR}/a2a"
   83|     sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)
   84| 
   85|     for dir in ${sprint_dirs}; do
   86|         if [[ -f "${dir}/COMPLETED" ]]; then
```

### The PR's diff hunk covering these lines

```diff
@@ -75,13 +75,15 @@
     fi
 }
 
+# Function: Count completed sprints
 get_completed_sprints() {
-    local count=0 total i
+    local count=0
+    local sprint_dirs
     local a2a_dir="${_GRIMOIRE_DIR}/a2a"
-    total=$(get_total_sprints)
+    sprint_dirs=$(find "${a2a_dir}" -maxdepth 1 -type d -name "sprint-*" 2>/dev/null || true)
 
-    for ((i = 1; i <= total; i++)); do
-        if [[ -f "${a2a_dir}/sprint-${i}/COMPLETED" ]]; then
+    for dir in ${sprint_dirs}; do
+        if [[ -f "${dir}/COMPLETED" ]]; then
             count=$((count + 1))
         fi
     done

```


## P44 — pr-05 · `.claude/scripts/tests/test_dcg.sh` lines 367–382 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:807` — `.claude/scripts/tests/test_dcg.sh:367-382` holds a single find-exec fixture (`find / -name "*.tmp" -exec rm {} \;`) and no multi-root or allow-listed-root case, so the regression in finding 1 is invisible to the hook's own suite.
**File:** `.claude/scripts/tests/test_dcg.sh:367`
**Suggestion:** Add the eight fixtures in the table under finding 1 with expected exit codes; the allow case (`find ./dist -type f -exec rm -rf {} +` exit 0) guards against over-tightening.
**Benefit:** GOAL-DRIVEN: non-trivial regex logic gets a runnable check that fails when it breaks.
```

```text
**Severity:** MEDIUM | **Confidence:** high
**Component:** `head/.claude/hooks/safety/block-destructive-bash.sh:773-775`; `.claude/scripts/tests/test_dcg.sh:367-382` (only existing find-exec fixture, single root `/`)
**Criterion:** CQ-DC: Documentation; CQ-TC: Test Coverage
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P45 — pr-12 · `.claude/scripts/verdict-derive.sh` lines 89–89 · region inside the PR's diff · enclosing symbol: show_help

### The reviewer's finding(s) citing this region

```text
### [LOW-009] Process: no acceptance walkthrough, test evidence or CHANGELOG entry
- **Severity:** LOW (confidence: high)
- **File:** `head/.loa.config.yaml.example:1400` (new config key), `head/.claude/scripts/verdict-derive.sh:89` (new `--envelope` flag), `head/.claude/scripts/adversarial-review.sh:510` and `:498` (new env vars `LOA_ADVERSARIAL_REPAIR_MODEL`, `LOA_ADVERSARIAL_ENV_DIR`)
- **Issue:** The implementation report (`pr/PR.md`) is a one-line title; no `## AC Verification`, no test evidence, no CHANGELOG line for the new key, flag and env vars. No documentation-coherence report exists under `grimoires/loa/a2a/subagent-reports/`; documentation coherence was verified manually for this audit (both skills' new doc blocks are byte-identical; the drift is itemised in LOW-008, MED-006 and MED-009).
```

### Head file context (line| text)

```text
   79| TRAILER_DETECT='<!--[^A-Za-z0-9]{0,4}LOA[^A-Za-z0-9]{0,4}VERDICT'
   80| TRAILER_CANON='^<!-- LOA-VERDICT \{.*\} -->$'
   81| 
   82| while [[ $# -gt 0 ]]; do
   83|     case "$1" in
   84|         --file) FILE="${2:-}"; shift 2 ;;
   85|         --gate) GATE="${2:-}"; shift 2 ;;
   86|         --json) JSON_OUTPUT=true; shift ;;
   87|         --require-trailer) REQUIRE_TRAILER=true; shift ;;
   88|         --review-file) REVIEW_FILE="${2:-}"; shift 2 ;;
   89|         --envelope) ENVELOPE_FILE="${2:-}"; shift 2 ;;
   90|         -h|--help) show_help; exit 0 ;;
   91|         *) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
   92|     esac
   93| done
   94| 
   95| if [[ -z "$FILE" || -z "$GATE" ]]; then
   96|     echo "Error: --file and --gate are required" >&2
   97|     show_help >&2
   98|     exit 2
   99| fi
```

### The PR's diff hunk covering these lines

```diff
@@ -86,6 +86,7 @@ while [[ $# -gt 0 ]]; do
         --json) JSON_OUTPUT=true; shift ;;
         --require-trailer) REQUIRE_TRAILER=true; shift ;;
         --review-file) REVIEW_FILE="${2:-}"; shift 2 ;;
+        --envelope) ENVELOPE_FILE="${2:-}"; shift 2 ;;
         -h|--help) show_help; exit 0 ;;
         *) echo "Unknown option: $1" >&2; show_help >&2; exit 2 ;;
     esac
```


## P46 — pr-13 · `.claude/settings.json` lines 514–514 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
| Criterion | Status | Notes |
|-----------|--------|-------|
| `tool-result-clearing.md` carries two classes (long 20K/50K/30K/150K, standard 2K/5K/3K/15K) and the selection rule | Pass | `head/.claude/protocols/tool-result-clearing.md:7-18` |
| A SessionStart hook records the class to `.run/context-class`; `/loa` shows it | Partial | Hook and `display_context_line` wired in both settings files (`head/.claude/settings.json:514`, `head/.claude/hooks/settings.hooks.json:45`); detection fails open for Bedrock ids and on macOS (HIGH ×2) |
| Ten skills' context-discipline include regenerated | Pass | `generate-skill-includes.sh --check`: no drift for `context_discipline` on head |
| Instruction diet: CLAUDE.loa.md ≤ 9,216 B, protocols ≤ 160,000 B, reference/ excluded | Pass (fragile) | 9,199 B and 131,333 B on head; 9,466 B after `generate-constraints.sh` (MEDIUM); protocols still above the warn line |
| Five protocols moved to `reference/` with stubs; inbound references updated | Pass | Reference copies byte-identical to base apart from intended path/class rewordings; all path-qualified inbound references resolve; `validate-ck-integration.sh` failure set identical to base |
| Tests | Partial | CC-1…CC-8 pass; CC-9 fails when `TMPDIR` is inside the checkout (MEDIUM); PB-1…PB-7, PB-9 pass; PB-8 needs fixtures absent from this checkout (environment) |
```

### Head file context (line| text)

```text
  504|             "command": "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/loa-kf-surface.sh",
  505|             "once": true
  506|           },
  507|           {
  508|             "type": "command",
  509|             "command": "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/hook-guard.sh \"$(git rev-parse --show-toplevel)\"/.claude/hooks/session-start/loa-run-state-surface.sh",
  510|             "once": true
  511|           },
  512|           {
  513|             "type": "command",
  514|             "command": "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/hook-guard.sh \"$(git rev-parse --show-toplevel)\"/.claude/hooks/session-start/loa-context-class.sh",
  515|             "once": true
  516|           }
  517|         ]
  518|       }
  519|     ],
  520|     "PreCompact": [
  521|       {
  522|         "matcher": "",
  523|         "hooks": [
  524|           {
```

### The PR's diff hunk covering these lines

```diff
@@ -508,6 +508,11 @@
             "type": "command",
             "command": "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/hook-guard.sh \"$(git rev-parse --show-toplevel)\"/.claude/hooks/session-start/loa-run-state-surface.sh",
             "once": true
+          },
+          {
+            "type": "command",
+            "command": "\"$(git rev-parse --show-toplevel)\"/.claude/hooks/hook-guard.sh \"$(git rev-parse --show-toplevel)\"/.claude/hooks/session-start/loa-context-class.sh",
+            "once": true
           }
         ]
       }
```


## P47 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 153–153 · region inside the PR's diff · enclosing symbol: _is_script

### The reviewer's finding(s) citing this region

```text
head/tools/check-no-swallowed-jq.sh:153 — marker rule no longer calls `_start_heredoc`, so `cat <<'EOF' # check-no-swallowed-jq: ok` fixture bodies are scanned and reported (false positive; clean under base)
```

```text
- **MEDIUM** (confidence: high) `head/tools/check-no-swallowed-jq.sh:153` — the marker rule changed from `{ _start_heredoc($0); next }` to `{ next }`, so `cat <<'EOF'  # check-no-swallowed-jq: ok (fixture)` no longer opens heredoc state and its planted body is reported as a violation.
**File:** `head/tools/check-no-swallowed-jq.sh:153`
**Suggestion:** Reproduced: a fixture with the marker on the opener and a swallowed jq in the body was clean under base and flagged under head. Restore `_start_heredoc($0)` before `next` in the marker rule.
**Benefit:** `--root` scans of test trees stop failing on explicitly suppressed fixtures, and the marker keeps its documented contract.
```

```text
**Severity:** MEDIUM | **Confidence:** high | **Criterion:** CQ-EH
**Component:** `head/tools/check-no-swallowed-jq.sh:153`
**Description:** The marker rule changed from `{ _start_heredoc($0); next }` to `{ next }`. Fixture `cat <<'EOS'  # check-no-swallowed-jq: ok (fixture)` with a swallowed jq in the body: base clean, head reports the body line (`rc=1`).
**Impact:** `--root` scans of test trees fail on explicitly suppressed fixtures; the marker's documented contract (header L29-32) is broken.
**Remediation:** Restore `_start_heredoc($0)` before `next` in the marker rule; add a bats case.
**References:** CWE-684 Incorrect Provision of Specified Functionality https://cwe.mitre.org/data/definitions/684.html
```

### Head file context (line| text)

```text
  143|         if (no_tabs == hd_term) { in_heredoc = 0; next }
  144|     }
  145|     next
  146| }
  147| 
  148| # Step 2: skip line-leading comments.
  149| /^[[:space:]]*#/ { next }
  150| 
  151| # Step 3: skip lines with the suppression marker. Requires `#` leader so
  152| # string-literal mentions don't silence real invocations.
  153| /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
  154| 
  155| # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
  156| # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
  157| # must be followed by whitespace (an invocation always has arguments, and
  158| # this keeps `jq_strict` from matching). RHS word-boundary on echo/printf
  159| # so `echo_handler` doesn't match.
  160| {
  161|     if (_line_has_swallowed_jq($0)) {
  162|         print FILENAME ":" NR ":" $0
  163|     }
```

### The PR's diff hunk covering these lines

```diff
@@ -155,33 +128,29 @@
         if (term != "") {
             hd_term = term
             in_heredoc = 1
-            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
-            cmd = _hd_command(scan, rs)
-            post = substr(scan, rs + rl)
-            hd_exec = (cmd in INTERP) || !hd_quoted || \
-                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
         }
     }
 }
 
+# Step 1: when in a heredoc body, skip fixture/documentation text until the
+# terminator. Without this, --root scans of bats tests can flag planted bad
+# examples instead of executable scanner code.
 in_heredoc {
-    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
+    if ($0 == hd_term) { in_heredoc = 0; next }
     if (hd_dash) {
         no_tabs = $0
         gsub(/^\t+/, "", no_tabs)
-        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
-    }
-    if (hd_exec) {
-        if ($0 ~ /^[[:space:]]*#/) next
-        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
-        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
+        if (no_tabs == hd_term) { in_heredoc = 0; next }
     }
     next
 }
 
+# Step 2: skip line-leading comments.
 /^[[:space:]]*#/ { next }
 
-/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }
+# Step 3: skip lines with the suppression marker. Requires `#` leader so
+# string-literal mentions don't silence real invocations.
+/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
 
 # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
 # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
```


## P48 — pr-12 · `.loa.config.yaml` lines 2206–2206 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **HIGH** (confidence: high) `head/.claude/scripts/adversarial-review.sh:1835-1840` — `_companion_chain` plans from the configured primary's *family* only and is never reconciled with the primary's `fallback_chain`.
**Component:** `head/.claude/scripts/adversarial-review.sh:1835-1840` (`_companion_chain`), `:2140-2141` (fork), `:2206-2212` (fail-soft aggregation)
**Criterion:** SEC-AV: Availability/Resilience; ARCH-RE
**Reasoning Trace:**
> `_companion_chain anthropic` returns `"claude-headless"` on a keyless host (`:1837`). This repository's `.loa.config.yaml` (`:402-410`) has `security_audit.model: gpt-5.5-pro` and `fallback_chain: [gpt-5.5, gemini-3.1-pro, claude-headless]` (same for `code_review`), and its own comment says "API path is billing-degraded … CLI subscription path works" (`.loa.config.yaml:113`). Reproduced (R1): HTTP hops `unavailable`, `claude-headless` ok → call log `gpt-5.5-pro claude-headless gpt-5.5 gemini-3.1-pro claude-headless` (the hop runs **twice**), `final_model=claude-headless`, `companion_voice.model=claude-headless`, both findings `voice: claude-headless`, `verdict_quality: null`, stderr `[vq-aggregate] aggregator unavailable or returned no output` — the Python aggregator raised INV-4 (duplicate succeeded id) and `:2206` swallows it with `2>/dev/null`.
**Description:** Nothing in `_walk_companion_chain`, `main` or `_fold_companion` compares the two chains or the two answering ids. The docs promise `voices_planned: 2` from two families (head/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md:49) and the config example promises "a s…
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P49 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 135–135 · region inside the PR's diff · enclosing symbol: _is_script

### The reviewer's finding(s) citing this region

```text
head/tools/check-no-swallowed-jq.sh:135 — The new Step 1 comment says heredoc bodies are "fixture/documentation text" to skip. That states the reverse of the base design (scan bodies that are executed) and documents the false-negative hole above as intended behaviour. No test coverage is updated or added for any of the scanner semantics that changed.
```

### Head file context (line| text)

```text
  125|         if (substr(term, 1, 1) == "\047" || substr(term, 1, 1) == "\"") term = substr(term, 2)
  126|         if (substr(term, length(term), 1) == "\047" || substr(term, length(term), 1) == "\"") term = substr(term, 1, length(term) - 1)
  127|         sub(/[[:space:]].*$/, "", term)
  128|         if (term != "") {
  129|             hd_term = term
  130|             in_heredoc = 1
  131|         }
  132|     }
  133| }
  134| 
  135| # Step 1: when in a heredoc body, skip fixture/documentation text until the
  136| # terminator. Without this, --root scans of bats tests can flag planted bad
  137| # examples instead of executable scanner code.
  138| in_heredoc {
  139|     if ($0 == hd_term) { in_heredoc = 0; next }
  140|     if (hd_dash) {
  141|         no_tabs = $0
  142|         gsub(/^\t+/, "", no_tabs)
  143|         if (no_tabs == hd_term) { in_heredoc = 0; next }
  144|     }
  145|     next
```

### The PR's diff hunk covering these lines

```diff
@@ -155,33 +128,29 @@
         if (term != "") {
             hd_term = term
             in_heredoc = 1
-            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
-            cmd = _hd_command(scan, rs)
-            post = substr(scan, rs + rl)
-            hd_exec = (cmd in INTERP) || !hd_quoted || \
-                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
         }
     }
 }
 
+# Step 1: when in a heredoc body, skip fixture/documentation text until the
+# terminator. Without this, --root scans of bats tests can flag planted bad
+# examples instead of executable scanner code.
 in_heredoc {
-    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
+    if ($0 == hd_term) { in_heredoc = 0; next }
     if (hd_dash) {
         no_tabs = $0
         gsub(/^\t+/, "", no_tabs)
-        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
-    }
-    if (hd_exec) {
-        if ($0 ~ /^[[:space:]]*#/) next
-        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
-        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
+        if (no_tabs == hd_term) { in_heredoc = 0; next }
     }
     next
 }
 
+# Step 2: skip line-leading comments.
 /^[[:space:]]*#/ { next }
 
-/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }
+# Step 3: skip lines with the suppression marker. Requires `#` leader so
+# string-literal mentions don't silence real invocations.
+/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
 
 # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
 # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
```


## P50 — pr-13 · `.claude/loa/CLAUDE.loa.md` lines 30–32 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/loa/CLAUDE.loa.md:8 — LOW: Reference Files table flattened to a filename list (topic labels gone), phase table to an arrow chain (:30), and the "memory lives in grimoires/loa/NOTES.md" pointer removed (:32)
```

```text
- **LOW** (confidence: medium) `head/.claude/loa/CLAUDE.loa.md:8`, `:30-32` — the Reference Files table became a comma list (topic labels such as "Context/Memory", "Flatline", "Guardrails" are gone, leaving filenames), the phase table became one arrow chain, and the sentence "memory lives in `grimoires/loa/NOTES.md`" was removed. The bytes saved are real; the file is the agent's first-read map, and the labels were doing navigation work. Worth a second look at whether the 1,026 B had to come from here rather than the still-warning protocols.
```

```text
### [LOW-014] The instruction diet flattened the agent's first-read map
- **File:** `head/.claude/loa/CLAUDE.loa.md:8` (Reference Files table → filename list, topic labels gone), `:30` (phase table → arrow chain), `:32` ("memory lives in `grimoires/loa/NOTES.md`" removed)
- **Confidence:** medium. Bytes saved are real (10,225 → 9,199 B); the labels were doing navigation work and the NOTES pointer was the only one in the file.
```

### Head file context (line| text)

```text
   20| ## Golden Path
   21| 
   22| | Command | What It Does | Routes To |
   23| |---------|-------------|-----------|
   24| | `/loa` | Where am I? What's next? | Status + health + next step |
   25| | `/plan` | Plan your project | `/plan-and-analyze` → `/architect` → `/sprint-plan` |
   26| | `/build` | Build the current sprint | `/implement sprint-N` (auto-detected) |
   27| | `/review` | Review and audit your work | `/review-sprint` + `/audit-sprint` |
   28| | `/ship` | Deploy and archive | `/deploy-production` + `/archive-cycle` |
   29| 
   30| `.claude/scripts/golden-path.sh`; truenames: the `/plan` chain → `/implement sprint-N` → `/review-sprint sprint-N` → `/audit-sprint sprint-N` → `/deploy-production`.
   31| 
   32| Run mode: `/run sprint-plan|sprint-N`, `/run-status`, `/run-halt`, `/run-resume`. `br` tracks tasks (`.claude/scripts/beads/beads-health.sh --json`).
   33| 
   34| ## Karpathy Principles
   35| 
   36| Every code-touching turn. Full text: `.claude/protocols/karpathy-principles.md`.
   37| 
   38| 1. **Think before coding** — state assumptions; on ambiguity ask, or in run mode record the chosen reading in NOTES and proceed.
   39| 2. **Simplicity first** — the ladder: needed at all? stdlib? native feature? installed dependency? one line? only then minimum code. Never simplify away: input validation at trust boundaries, data-loss handling, security, accessibility, real-hardware calibration, anything explicitly requested. Code first, then at most three lines on what you skipped and when. `simplicity_intensity` (`full` | `ultra`) never softens that floor.
   40| 3. **Surgical changes** — only what the request requires; mark shortcuts `// loa:shortcut: <what>; <ceiling> — <upgrade trigger>`.
   41| 4. **Goal-driven** — verifiable goals; non-trivial logic leaves a runnable check that fails when it breaks.
   42| 
```

### The PR's diff hunk covering these lines

```diff
@@ -40,19 +27,9 @@ ## Golden Path
 | `/review` | Review and audit your work | `/review-sprint` + `/audit-sprint` |
 | `/ship` | Deploy and archive | `/deploy-production` + `/archive-cycle` |
 
-`.claude/scripts/golden-path.sh`; truenames:
+`.claude/scripts/golden-path.sh`; truenames: the `/plan` chain → `/implement sprint-N` → `/review-sprint sprint-N` → `/audit-sprint sprint-N` → `/deploy-production`.
 
-| Phase | Command | Output |
-|-------|---------|--------|
-| 1 | `/plan-and-analyze` | PRD |
-| 2 | `/architect` | SDD |
-| 3 | `/sprint-plan` | Sprint Plan |
-| 4 | `/implement sprint-N` | Code |
-| 5 | `/review-sprint sprint-N` | Feedback |
-| 5.5 | `/audit-sprint sprint-N` | Approval |
-| 6 | `/deploy-production` | Infrastructure |
-
-Run mode: `/run sprint-plan|sprint-N`, `/run-status`, `/run-halt`, `/run-resume`. `br` tracks tasks (`.claude/scripts/beads/beads-health.sh --json`); memory lives in `grimoires/loa/NOTES.md`.
+Run mode: `/run sprint-plan|sprint-N`, `/run-status`, `/run-halt`, `/run-resume`. `br` tracks tasks (`.claude/scripts/beads/beads-health.sh --json`).
 
 ## Karpathy Principles
 
```


## P51 — pr-12 · `.claude/scripts/verdict-derive.sh` lines 137–137 · region inside the PR's diff · enclosing symbol: rejected_summary_check

### The reviewer's finding(s) citing this region

```text
head/.claude/scripts/verdict-derive.sh:137 — The contract check only greps for the `## Rejected dissent payloads` heading. An empty section, or one that triages only some of the N entries, passes as CONSISTENT, while the skills and resources documents say the section MUST hold one triage line per entry. The check should at least compare the number of list items under the heading with `rejected_summary | length`.
```

### Head file context (line| text)

```text
  127|     ENVELOPE_EXPLICIT=false
  128| else
  129|     ENVELOPE_EXPLICIT=true
  130| fi
  131| rejected_summary_check() {  # appends a violation when the contract is broken; silent otherwise
  132|     [[ -f "$ENVELOPE_FILE" ]] || { [[ "$ENVELOPE_EXPLICIT" == "true" ]] && warnings+=("WARN: --envelope $ENVELOPE_FILE not found; rejected-payload contract not checked"); return 0; }
  133|     local n
  134|     n=$(jq -r '(.metadata.rejected_summary // []) | length' -- "$ENVELOPE_FILE" 2>/dev/null) || n=""
  135|     [[ "$n" =~ ^[0-9]+$ ]] || { warnings+=("WARN: envelope $ENVELOPE_FILE is not parseable JSON; rejected-payload contract not checked"); return 0; }
  136|     (( n > 0 )) || return 0
  137|     if ! grep -qE '^## Rejected dissent payloads' -- "$FILE"; then
  138|         violations+=("the dissent envelope $(basename -- "$ENVELOPE_FILE") carries $n schema-rejected payload(s) in metadata.rejected_summary but this file has no '## Rejected dissent payloads' section — triage each entry there (real defect → count it; not a defect → say why) so a dropped finding is never silently lost (cycle-126 FR-2.3)")
  139|     fi
  140| }
  141| violations=()
  142| warnings=()
  143| t_verdict=""
  144| counts_json="null"
  145| t_excluded=0
  146| t_excluded_confirmed=0
  147| 
```

### The PR's diff hunk covering these lines

```diff
@@ -118,6 +119,25 @@ if [[ -n "$REVIEW_FILE" ]]; then
     fi
 fi
 
+# cycle-126 FR-2.3 (SDD D-2.3): the dissent envelope beside the feedback file
+# (adversarial-<gate>.json, or --envelope) — when its metadata.rejected_summary
+# is non-empty the feedback MUST triage it under "## Rejected dissent payloads".
+if [[ -z "${ENVELOPE_FILE:-}" ]]; then
+    ENVELOPE_FILE="$(dirname -- "$FILE")/adversarial-${GATE}.json"
+    ENVELOPE_EXPLICIT=false
+else
+    ENVELOPE_EXPLICIT=true
+fi
+rejected_summary_check() {  # appends a violation when the contract is broken; silent otherwise
+    [[ -f "$ENVELOPE_FILE" ]] || { [[ "$ENVELOPE_EXPLICIT" == "true" ]] && warnings+=("WARN: --envelope $ENVELOPE_FILE not found; rejected-payload contract not checked"); return 0; }
+    local n
+    n=$(jq -r '(.metadata.rejected_summary // []) | length' -- "$ENVELOPE_FILE" 2>/dev/null) || n=""
+    [[ "$n" =~ ^[0-9]+$ ]] || { warnings+=("WARN: envelope $ENVELOPE_FILE is not parseable JSON; rejected-payload contract not checked"); return 0; }
+    (( n > 0 )) || return 0
+    if ! grep -qE '^## Rejected dissent payloads' -- "$FILE"; then
+        violations+=("the dissent envelope $(basename -- "$ENVELOPE_FILE") carries $n schema-rejected payload(s) in metadata.rejected_summary but this file has no '## Rejected dissent payloads' section — triage each entry there (real defect → count it; not a defect → say why) so a dropped finding is never silently lost (cycle-126 FR-2.3)")
+    fi
+}
 violations=()
 warnings=()
 t_verdict=""
```


## P52 — pr-13 · `.claude/skills/implementing-tasks/SKILL.md` lines 124–124 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/data/skill-includes/context_discipline.md:2 — The new include points to the bare filename `tool-result-clearing.md`; the base version gave the resolvable `.claude/protocols/tool-result-clearing.md`. It also drops the write-routing ("decisions → Decision Log, issues → Technical Debt", line 5). structured-memory.md still names the Decision Log as recovery-critical. This regression ships into all ten SKILL.md files, e.g. head/.claude/skills/implementing-tasks/SKILL.md:124.
```

### Head file context (line| text)

```text
  114| [ASSUMPTION] The database likely needs connection pooling
  115| ```
  116| <!-- @skill-include: end factual_grounding -->
  117| </factual_grounding>
  118| 
  119| <context_discipline>
  120| <!-- @skill-include: start context_discipline | hash:0553383a | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
  121| ## Context Discipline
  122| 
  123| Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
  124| ≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
  125| accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
  126| from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
  127| "Session Continuity"; end / pre-compaction: update it.
  128| <!-- @skill-include: end context_discipline -->
  129| </context_discipline>
  130| 
  131| <trajectory_logging>
  132| <!-- @skill-include: start trajectory_logging | hash:e809010f | DO NOT EDIT — generated from .claude/data/skill-includes/trajectory_logging.md -->
  133| ## Trajectory Logging
  134| 
```

### The PR's diff hunk covering these lines

```diff
@@ -117,14 +117,14 @@ ## Factual Grounding (MANDATORY)
 </factual_grounding>
 
 <context_discipline>
-<!-- @skill-include: start context_discipline | hash:d7adbf89 | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
+<!-- @skill-include: start context_discipline | hash:0553383a | DO NOT EDIT — generated from .claude/data/skill-includes/context_discipline.md -->
 ## Context Discipline
 
-Follow `.claude/protocols/tool-result-clearing.md`: single result >2K tokens / accumulated >5K /
-full file >3K / session >15K → extract findings (≤10 files, ≤20 words, file:line) to NOTES.md
-and reason from that synthesis. Big artefacts: `notes-guard.sh read --file F --section <H>` /
-`--index` before a blind Read. Start: read NOTES.md "Session Continuity"; end / pre-compaction:
-update it (decisions → Decision Log, issues → Technical Debt).
+Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
+≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
+accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
+from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
+"Session Continuity"; end / pre-compaction: update it.
 <!-- @skill-include: end context_discipline -->
 </context_discipline>
 
```


## P53 — pr-13 · `.claude/data/skill-includes/context_discipline.md` lines 7–7 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/data/skill-includes/context_discipline.md:7 — The diet drops "(decisions → Decision Log, issues → Technical Debt)" from the end-of-session instruction rendered into all ten SKILL.md files. That routing is what keeps the Decision Log section populated, and check-loa (structured-memory.md:17) treats that section as recovery-critical. Restore the routing clause; it costs about 50 bytes.
```

### Head file context (line| text)

```text
    1| ## Context Discipline
    2| 
    3| Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
    4| ≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
    5| accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
    6| from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
    7| "Session Continuity"; end / pre-compaction: update it.
    8| 
```

### The PR's diff hunk covering these lines

```diff
@@ -1,7 +1,7 @@
 ## Context Discipline
 
-Follow `.claude/protocols/tool-result-clearing.md`: single result >2K tokens / accumulated >5K /
-full file >3K / session >15K → extract findings (≤10 files, ≤20 words, file:line) to NOTES.md
-and reason from that synthesis. Big artefacts: `notes-guard.sh read --file F --section <H>` /
-`--index` before a blind Read. Start: read NOTES.md "Session Continuity"; end / pre-compaction:
-update it (decisions → Decision Log, issues → Technical Debt).
+Class: `.run/context-class` (`long` default; `standard` via `LOA_CONTEXT_CLASS=standard` or a
+≤200K model). `tool-result-clearing.md` — long 20K/50K/30K/150K, standard 2K/5K/3K/15K (single /
+accumulated / full file / session) → extract ≤10 files, ≤20 words, file:line to NOTES.md; reason
+from it. Big files: `notes-guard.sh read --file F --section <H>` / `--index` first. Start: NOTES.md
+"Session Continuity"; end / pre-compaction: update it.
```


## P54 — pr-08 · `tools/check-no-swallowed-jq.sh` lines 153–153 · region inside the PR's diff · enclosing symbol: _is_script

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `head/tools/check-no-swallowed-jq.sh:153` — the marker rule was `{ _start_heredoc($0); next }` in base (line 184) and is now `{ next }`, so `cat <<'DOC' # check-no-swallowed-jq: ok (fixture)` no longer enters heredoc mode and the planted bad example in the body is reported as a violation. Fixture `e_marker_heredoc.sh`: base `OK`, head flags line 3 (`jq -r .x f 2>/dev/null || echo bad-example`). Inverse of findings 2-3: a false positive rather than a false negative, but it breaks the documented fixture convention (header lines 29-32) and will make `--root` scans of bats test files fail.
**File:** `head/tools/check-no-swallowed-jq.sh:153`
**Suggestion:** Restore `_start_heredoc($0)` before `next` on the marker rule.
**Benefit:** Fixture heredocs annotated with the marker stay skipped as documented.
```

```text
### [MED-001] Suppression-marker line that opens a heredoc no longer starts heredoc mode; fixture bodies are flagged
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `head/tools/check-no-swallowed-jq.sh:153`
- **Issue:** The marker rule is now `/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }` (line 153); base called `_start_heredoc($0)` before `next`. `cat <<'DOC' # check-no-swallowed-jq: ok (fixture)` therefore no longer enters heredoc mode and the planted bad example in the body is reported. Fixture e: base `OK`, head flags `e_marker_heredoc.sh:3:jq -r .x f 2>/dev/null || echo bad-example`. This is the inverse of HIGH-002/003 (a false positive) but breaks the documented fixture convention (header lines 29-32) and will make `--root` scans of bats files fail.
- **Fix:** Restore `_start_heredoc($0)` before `next` on line 153.
```

### Head file context (line| text)

```text
  143|         if (no_tabs == hd_term) { in_heredoc = 0; next }
  144|     }
  145|     next
  146| }
  147| 
  148| # Step 2: skip line-leading comments.
  149| /^[[:space:]]*#/ { next }
  150| 
  151| # Step 3: skip lines with the suppression marker. Requires `#` leader so
  152| # string-literal mentions don't silence real invocations.
  153| /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
  154| 
  155| # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
  156| # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
  157| # must be followed by whitespace (an invocation always has arguments, and
  158| # this keeps `jq_strict` from matching). RHS word-boundary on echo/printf
  159| # so `echo_handler` doesn't match.
  160| {
  161|     if (_line_has_swallowed_jq($0)) {
  162|         print FILENAME ":" NR ":" $0
  163|     }
```

### The PR's diff hunk covering these lines

```diff
@@ -155,33 +128,29 @@
         if (term != "") {
             hd_term = term
             in_heredoc = 1
-            hd_quoted = (substr(rest, 1, 1) == "\047" || substr(rest, 1, 1) == "\"")
-            cmd = _hd_command(scan, rs)
-            post = substr(scan, rs + rl)
-            hd_exec = (cmd in INTERP) || !hd_quoted || \
-                (post ~ /\|[[:space:]]*([^[:space:]|;&]*\/)?(sh|bash|zsh|ksh|dash|ash|python[0-9.]*|perl|ruby|node|deno|php)([[:space:]]|$)/)
         }
     }
 }
 
+# Step 1: when in a heredoc body, skip fixture/documentation text until the
+# terminator. Without this, --root scans of bats tests can flag planted bad
+# examples instead of executable scanner code.
 in_heredoc {
-    if ($0 == hd_term) { in_heredoc = 0; hd_exec = 0; next }
+    if ($0 == hd_term) { in_heredoc = 0; next }
     if (hd_dash) {
         no_tabs = $0
         gsub(/^\t+/, "", no_tabs)
-        if (no_tabs == hd_term) { in_heredoc = 0; hd_exec = 0; next }
-    }
-    if (hd_exec) {
-        if ($0 ~ /^[[:space:]]*#/) next
-        if ($0 ~ /#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/) next
-        if (_line_has_swallowed_jq($0)) print FILENAME ":" NR ":" $0
+        if (no_tabs == hd_term) { in_heredoc = 0; next }
     }
     next
 }
 
+# Step 2: skip line-leading comments.
 /^[[:space:]]*#/ { next }
 
-/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { _start_heredoc($0); next }
+# Step 3: skip lines with the suppression marker. Requires `#` leader so
+# string-literal mentions don't silence real invocations.
+/#[^\n]*check-no-swallowed-jq:[[:space:]]*ok/ { next }
 
 # Step 4: match a jq invocation followed by `|| echo` / `|| printf` on the
 # same line. LHS word-boundary so identifiers like `dijq` don't match; jq
```


## P55 — pr-08 · `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py` lines 245–277 · region OUTSIDE the PR's diff (nearest changed line 77 lines away) · enclosing symbol: _build_command

### The reviewer's finding(s) citing this region

```text
**Severity:** HIGH | **Confidence:** high | **Criterion:** SEC-AV Availability/Resilience; CQ-EH Error Handling
**Component:** `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157` (try block `:125-165`; argv build `:245-277`)
**Confirmed by cross-model review** (DISS-001 gpt-5.5-pro; DISS-C-002 claude-headless).
```

### Head file context (line| text)

```text
  235|             return False
  236| 
  237|     # ---------------------------------------------------------------------
  238|     # Internal: command construction
  239|     # ---------------------------------------------------------------------
  240| 
  241|     def _agy_bin(self) -> str:
  242|         """Resolve the agy CLI binary name (env var override allowed)."""
  243|         return os.environ.get("AGY_HEADLESS_BIN", _AGY_BIN_DEFAULT)
  244| 
  245|     def _build_command(
  246|         self,
  247|         request: CompletionRequest,
  248|         model_config,
  249|         prompt: str,
  250|     ) -> List[str]:
  251|         """Build the agy argv (spike T4.1). Prompt on argv; sandboxed; non-TTY-safe.
  252| 
  253|         The stdin-close is NOT part of this argv — it is a subprocess setting
  254|         (`run_subprocess_pgkill` keeps stdin on DEVNULL when no `input=` is passed).
  255|         """
  256|         # `extra.cli_model` is REQUIRED — an agy MODEL LABEL (e.g. "Gemini 3.1 Pro
  257|         # (High)"), not an api id (agy's `--model` wants the human-readable label).
  258|         # No fallback to request.model: agy rejects internal ids, so a silent fallback
  259|         # would just fail at dispatch with a confusing error (council #1109).
  260|         cli_model = (model_config.extra or {}).get("cli_model")
  261|         if not cli_model:
  262|             raise ConfigError(
  263|                 f"Provider '{self.provider}': model '{request.model}' is missing "
  264|                 f'extra.cli_model (the agy --model LABEL, e.g. "Gemini 3.1 Pro (High)").'
  265|             )
  266| 
  267|         # The argv is FIXED — there is deliberately no operator-supplied extra-flags
  268|         # escape hatch. The prompt is untrusted review content; an extra-flags surface
  269|         # was a sandbox-bypass foothold (council #1109 found a split-token bypass that a
  270|         # denylist can't reliably close). The non-TTY pairing (--sandbox keeps agy
  271|         # terminal-restricted, the read-only analog of gemini's plan mode;
  272|         # --dangerously-skip-permissions + a closed stdin stops the non-TTY hang) is
  273|         # non-negotiable. A genuinely-needed flag is a deliberate, reviewed code change.
  274|         return [
  275|             self._agy_bin(),
  276|             "-p",
  277|             prompt,
  278|             "--model",
  279|             cli_model,
  280|             "--sandbox",
  281|             "--dangerously-skip-permissions",
  282|         ]
  283| 
  284|     def _compute_timeout(self) -> float:
  285|         """Resolve the subprocess timeout. read_timeout wins when set."""
  286|         connect = max(self.config.connect_timeout, _CONNECT_TIMEOUT_FLOOR)
  287|         read = max(self.config.read_timeout, _READ_TIMEOUT_FLOOR)
```


## P56 — pr-13 · `.claude/loa/reference/protocols-summary.md` lines 27–27 · region inside the PR's diff · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
head/.claude/loa/reference/protocols-summary.md:27 — the `reference/session-continuity.md` row still says it is loaded by "skills' context_discipline", but the regenerated include no longer references that protocol (LOW)
```

```text
- **LOW** (confidence: high) `head/.claude/loa/reference/protocols-summary.md:27` — the `reference/session-continuity.md` row still lists "skills' context_discipline" under *Loaded by*; the regenerated include (`head/.claude/data/skill-includes/context_discipline.md`) no longer references the protocol.
```

```text
**Severity:** LOW | **Confidence:** high
**Component:** `head/.claude/loa/reference/protocols-summary.md:27`
**Description:** The row still lists "skills' context_discipline" as a loader, but the regenerated include (`head/.claude/data/skill-includes/context_discipline.md`) no longer references the protocol.
**Remediation:** Replace with "structured-memory.md pointer; NOTES.md.template".
```

### Head file context (line| text)

```text
   17| | `flatline-protocol.md` | Multi-model adversarial review pipeline | flatline skills + orchestrator docs |
   18| | `git-safety.md` | Upstream-detection layers, template protection | git-safety.sh; mounting flows |
   19| | `grounding-enforcement.md` | Grounding-ratio enforcement detail (gated deletion — see cycle-121 Scope Contract) | ck-family survivors; review skills |
   20| | `reference/helper-scripts.md` | Comprehensive script documentation | scripts-reference.md pointer |
   21| | `implementation-compliance.md` | C-PROC enforcement checklist (generated from constraints.json) | CLAUDE.loa.md Process Compliance pointer |
   22| | `input-guardrails.md` | Guardrails orchestrator detail (PII/injection/danger) | guardrails-reference.md; skill preludes |
   23| | `karpathy-principles.md` | Enforcement map + config keys (canonical TEXT lives in CLAUDE.loa.md) | implementing-tasks pointer; CLAUDE.loa.md pointer |
   24| | `reference/recommended-hooks.md` | Optional Claude Code hook patterns | hooks-reference.md; operators |
   25| | `ride-translation.md` | /ride codebase-translation flow | riding-codebase skill |
   26| | `safe-file-creation.md` | Write-tool-vs-heredoc decision tree | shell-conventions.md pointer; implementing-tasks |
   27| | `reference/session-continuity.md` | Tiered recovery (L1/L2/L3), fork detection | structured-memory.md pointer; skills' context_discipline |
   28| | `structured-memory.md` | NOTES.md contract: where durable knowledge goes, required sections, write discipline | notes-template tests; NOTES.md.template pointer |
   29| | `subagent-invocation.md` | Subagent dispatch patterns | parallel-execution sections of skills |
   30| | `synthesis-checkpoint.md` | Pre-clear validation (BLOCKING, 7-step) | check-loa v0.9.0 required; context_discipline |
   31| | `tool-result-clearing.md` | Clearing thresholds + 4-step synthesis + edge cases | 10 skills' context_discipline blocks; validate-ck-integration required |
   32| | `reference/trajectory-evaluation.md` | ADK-style reasoning audit trail | implementing-tasks + reviewing-code resources |
   33| | `visual-communication.md` | Mermaid diagram standards | review feedback authoring |
   34| 
```

### The PR's diff hunk covering these lines

```diff
@@ -17,17 +17,17 @@ # Protocols Summary
 | `flatline-protocol.md` | Multi-model adversarial review pipeline | flatline skills + orchestrator docs |
 | `git-safety.md` | Upstream-detection layers, template protection | git-safety.sh; mounting flows |
 | `grounding-enforcement.md` | Grounding-ratio enforcement detail (gated deletion — see cycle-121 Scope Contract) | ck-family survivors; review skills |
-| `helper-scripts.md` | Comprehensive script documentation | scripts-reference.md pointer |
+| `reference/helper-scripts.md` | Comprehensive script documentation | scripts-reference.md pointer |
 | `implementation-compliance.md` | C-PROC enforcement checklist (generated from constraints.json) | CLAUDE.loa.md Process Compliance pointer |
 | `input-guardrails.md` | Guardrails orchestrator detail (PII/injection/danger) | guardrails-reference.md; skill preludes |
 | `karpathy-principles.md` | Enforcement map + config keys (canonical TEXT lives in CLAUDE.loa.md) | implementing-tasks pointer; CLAUDE.loa.md pointer |
-| `recommended-hooks.md` | Optional Claude Code hook patterns | hooks-reference.md; operators |
+| `reference/recommended-hooks.md` | Optional Claude Code hook patterns | hooks-reference.md; operators |
 | `ride-translation.md` | /ride codebase-translation flow | riding-codebase skill |
 | `safe-file-creation.md` | Write-tool-vs-heredoc decision tree | shell-conventions.md pointer; implementing-tasks |
-| `session-continuity.md` | Tiered recovery (L1/L2/L3), fork detection | structured-memory.md pointer; skills' context_discipline |
+| `reference/session-continuity.md` | Tiered recovery (L1/L2/L3), fork detection | structured-memory.md pointer; skills' context_discipline |
 | `structured-memory.md` | NOTES.md contract: where durable knowledge goes, required sections, write discipline | notes-template tests; NOTES.md.template pointer |
 | `subagent-invocation.md` | Subagent dispatch patterns | parallel-execution sections of skills |
 | `synthesis-checkpoint.md` | Pre-clear validation (BLOCKING, 7-step) | check-loa v0.9.0 required; context_discipline |
 | `tool-result-clearing.md` | Clearing thresholds + 4-step synthesis + edge cases | 10 skills' context_discipline blocks; validate-ck-integration required |
-| `trajectory-evaluation.md` | ADK-style reasoning audit trail | implementing-tasks + reviewing-code resources |
+| `reference/trajectory-evaluation.md` | ADK-style reasoning audit trail | implementing-tasks + reviewing-code resources |
 | `visual-communication.md` | Mermaid diagram standards | review feedback authoring |
```


## P57 — pr-13 · `tests/unit/context-class.bats` lines 34–34 · region inside the PR's diff · enclosing symbol: CC-3 a 200K session model selects standard, a 1M model long, an alias resolves (tiny → Haiku)

### The reviewer's finding(s) citing this region

```text
head/tests/unit/context-class.bats:34 — CC-3, CC-4, CC-6 and CC-7 need `yq` and specific entries in the live `.claude/defaults/model-config.yaml` (`claude-opus-5` at 1,000,000, alias `tiny`, the dated Haiku/Sonnet ids), and skip nothing when yq is missing. On a runner without yq the hook falls back to `long` and these tests fail. A catalog change also breaks them. Use a fixture catalog via `--catalog` and `skip` when yq is absent. No test covers the trailing-flag hang above.
```

### Head file context (line| text)

```text
   24|   [ ! -e "$T/.run/.context-class."* ] || false
   25| }
   26| 
   27| @test "CC-2 LOA_CONTEXT_CLASS=standard selects standard (basis env); =long pins long" {
   28|   LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" < /dev/null
   29|   [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "env" ]
   30|   LOA_CONTEXT_CLASS=long run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
   31|   [ "$(_class)" = "long" ]; [ "$(_basis)" = "env" ]
   32| }
   33| 
   34| @test "CC-3 a 200K session model selects standard, a 1M model long, an alias resolves (tiny → Haiku)" {
   35|   run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
   36|   [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
   37|   run bash "$HOOK" --root "$T" --model claude-opus-5 < /dev/null
   38|   [ "$(_class)" = "long" ]; [ "$(_basis)" = "model" ]
   39|   run bash "$HOOK" --root "$T" --model tiny < /dev/null
   40|   [ "$(_class)" = "standard" ]
   41|   run bash "$HOOK" --root "$T" --model anthropic:claude-sonnet-4-5-20250929 < /dev/null
   42|   [ "$(_class)" = "standard" ]
   43| }
   44| 
```

### The PR's diff hunk covering these lines

```diff
@@ -0,0 +1,115 @@
+#!/usr/bin/env bats
+# =============================================================================
+# tests/unit/context-class.bats — cycle-126 Sprint 3 (PRD FR-3.1, SDD D-3.1)
+# The context class: `long` by default; `standard` under LOA_CONTEXT_CLASS=standard
+# or when the session model resolves to a catalog entry with context_window
+# ≤ 200000 (alias-aware); written to .run/context-class atomically; never a
+# non-zero exit; `--line` is the /loa line.
+# =============================================================================
+
+setup() {
+  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
+  HOOK="$PROJECT_ROOT/.claude/hooks/session-start/loa-context-class.sh"
+  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cc.XXXXXX")"
+  unset LOA_CONTEXT_CLASS
+}
+teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }
+_class() { head -1 "$T/.run/context-class"; }
+_basis() { sed -n 2p "$T/.run/context-class" | grep -o 'basis=[a-z]*' | cut -d= -f2; }
+
+@test "CC-1 default: long, basis default, file written (creating .run), exit 0, silent as a hook" {
+  run bash "$HOOK" --root "$T" < /dev/null
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+  [ ! -e "$T/.run/.context-class."* ] || false
+}
+
+@test "CC-2 LOA_CONTEXT_CLASS=standard selects standard (basis env); =long pins long" {
+  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "env" ]
+  LOA_CONTEXT_CLASS=long run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "env" ]
+}
+
+@test "CC-3 a 200K session model selects standard, a 1M model long, an alias resolves (tiny → Haiku)" {
+  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
+  [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
+  run bash "$HOOK" --root "$T" --model claude-opus-5 < /dev/null
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "model" ]
+  run bash "$HOOK" --root "$T" --model tiny < /dev/null
+  [ "$(_class)" = "standard" ]
+  run bash "$HOOK" --root "$T" --model anthropic:claude-sonnet-4-5-20250929 < /dev/null
+  [ "$(_class)" = "standard" ]
+}
+
+@test "CC-4 the hook payload's .model on stdin is honoured when no --model is given" {
+  run bash -c "printf '%s' '{\"session_id\":\"s\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"model\":\"claude-haiku-4-5-20251001\"}' | bash '$HOOK' --root '$T'"
+  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
+  run bash -c "printf '%s' '{\"session_id\":\"s\",\"source\":\"resume\"}' | bash '$HOOK' --root '$T'"
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+}
+
+@test "CC-5 an unknown model, malformed stdin or a missing catalog all fall back to long, exit 0" {
+  run bash "$HOOK" --root "$T" --model not-a-model < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+  run bash -c "printf 'not json' | bash '$HOOK' --root '$T'"
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
+  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 --catalog "$T/absent.yaml" < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
+}
+
+@test "CC-6 --line prints the /loa line and --json the record; the model id in the payload is sanitised" {
+  run bash "$HOOK" --root "$T" --line < /dev/null
+  [ "$status" -eq 0 ]
+  [[ "$output" == "Context: long (default; thresholds 20K/50K/30K/150K"* ]]
+  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" --line < /dev/null
+  [[ "$output" == "Context: standard (env; thresholds 2K/5K/3K/15K)" ]]
+  run bash "$HOOK" --root "$T" --json --model claude-opus-5 < /dev/null
+  echo "$output" | jq -e '.class == "long" and .basis == "model" and .model == "claude-opus-5" and .context_window == 1000000' >/dev/null
+  # shell metacharacters never reach yq or the record: the id is stripped to its safe characters (and then resolves to nothing)
…[hunk truncated]
```


## P58 — pr-08 · `grimoires/loa/a2a/sprint-1/reviewer.md` lines 1–1 · region OUTSIDE the PR's diff (file not changed by the PR) · enclosing symbol: —

### The reviewer's finding(s) citing this region

```text
- **MEDIUM** (confidence: high) `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:166` — `reviewer.md` is the two-sentence PR description: no `## AC Verification`, no test command or result, no acknowledgement that `test_agy_headless_adapter.py::TestErrors::test_nul_byte_prompt_walks_not_crashes` and `test_headless_argv_nul_robustness.py` assert the deleted behaviour, and no bats run for the scanner (`tests/integration/check-no-swallowed-jq.bats`, line 55). No CHANGELOG entry accompanies the change. `FAST-GATE:` nothing indicates the Python or bats suites were run.
**File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1`
**Suggestion:** Run `pytest .claude/adapters/tests/test_agy_headless_adapter.py .claude/adapters/tests/test_headless_argv_nul_robustness.py` and `bats tests/integration/check-no-swallowed-jq.bats`, and report results plus a per-AC walkthrough in `reviewer.md`.
**Benefit:** The review can verify claims instead of re-deriving them; the two failing tests would have caught finding 1 before review.
```

```text
### [MED-002] No test evidence, no AC verification, no CHANGELOG for security-relevant deletions
- **Severity:** MEDIUM | **Confidence:** high
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:1` (= `pr/PR.md`); code at `head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:166`
- **Issue:** The implementation report is the two-sentence PR description. It names no test run, no `## AC Verification`, and does not acknowledge that two repository tests assert the behaviour HIGH-001 deletes, or that the scanner has a bats contract (`check-no-swallowed-jq.sh:55`). Removing an exception handler on an untrusted-input path and weakening a data-loss guard are security changes; no CHANGELOG entry accompanies them. Documentation audit: no documentation-coherence reports exist under `grimoires/loa/a2a/subagent-reports/`; manually verified that the PR touches no docs and that the only comment it edits (ledger lines 152-156) now overstates the guard it sits above.
- **Fix:** Run `pytest` on `tests/test_agy_headless_adapter.py` and `tests/test_headless_argv_nul_robustness.py` and `bats tests/integration/check-no-swallowed-jq.bats`; report results and a per-AC walkthrough in `reviewer.md`; add a CHANGELOG line.
```

### Head file context (line| text)

```text
(file not present in head/)
```


## P59 — pr-05 · `.claude/adapters/loa_cheval/providers/anthropic_adapter.py` lines 221–221 · region inside the PR's diff · enclosing symbol: _complete_nonstreaming

### The reviewer's finding(s) citing this region

```text
head/.claude/adapters/loa_cheval/providers/anthropic_adapter.py:221 — Same regression in the non-streaming (LOA_CHEVAL_DISABLE_STREAMING=1) path: every 4xx, billing-class included, becomes InvalidInputError, so streaming and kill-switch behavior both lose provider fallback on billing errors. This is a behavior change, not a refactor as the PR describes it.
```

### Head file context (line| text)

```text
  211|         latency_ms = int((time.monotonic() - start) * 1000)
  212| 
  213|         # Handle errors
  214|         if status == 429:
  215|             raise RateLimitError(self.provider)
  216| 
  217|         if status >= 500:
  218|             msg = _extract_error_message(resp)
  219|             raise ProviderUnavailableError(self.provider, f"HTTP {status}: {msg}")
  220| 
  221|         if status >= 400:
  222|             msg = _extract_error_message(resp)
  223|             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
  224| 
  225|         # Parse response
  226|         return self._parse_response(resp, latency_ms)
  227| 
  228|     def _parse_response(self, resp: Dict[str, Any], latency_ms: int) -> CompletionResult:
  229|         """Extract CompletionResult from Anthropic response (SDD §4.2.5)."""
  230|         content_blocks = resp.get("content", [])
  231| 
```

### The PR's diff hunk covering these lines

```diff
@@ -257,11 +220,6 @@
 
         if status >= 400:
             msg = _extract_error_message(resp)
-            if _is_billing_class_error(msg):
-                raise ProviderUnavailableError(
-                    self.provider,
-                    f"HTTP {status} billing-class: {msg}",
-                )
             raise InvalidInputError(f"Anthropic API error (HTTP {status}): {msg}")
 
         # Parse response
```


## P60 — pr-08 · `.claude/adapters/loa_cheval/providers/agy_headless_adapter.py` lines 157–157 · region OUTSIDE the PR's diff (nearest changed line 6 lines away) · enclosing symbol: complete

### The reviewer's finding(s) citing this region

```text
head/.claude/adapters/loa_cheval/providers/agy_headless_adapter.py:157 — Removing the `except ValueError` handler means a prompt with an embedded NUL byte (subprocess/exec raises `ValueError: embedded null byte`, not `OSError`) now escapes as a raw ValueError. The call crashes instead of raising ProviderUnavailableError and moving on to the next provider (the gemini-api HTTP fallback). Prompts are argv-transported untrusted diff content, so this is reachable. Restore the handler.
```

### Head file context (line| text)

```text
  147|                     raise ProviderUnavailableError(
  148|                         self.provider,
  149|                         f"agy -p {exc}",
  150|                     ) from exc
  151|                 except FileNotFoundError as exc:
  152|                     raise ConfigError(
  153|                         f"agy CLI not found on PATH (set AGY_HEADLESS_BIN to override). "
  154|                         f"Install + authenticate the Antigravity CLI on the cheval host. "
  155|                         f"Original: {exc}"
  156|                     ) from exc
  157|                 except OSError as exc:
  158|                     # E2BIG (ARG_MAX — a huge diff on argv; agy is argv-transport, no
  159|                     # --prompt-file exists) or another exec failure → WALK the chain,
  160|                     # never crash with a raw OSError. The gemini-api HTTP fallback
  161|                     # covers oversized diffs. (FileNotFoundError is handled above.)
  162|                     raise ProviderUnavailableError(
  163|                         self.provider,
  164|                         f"agy -p exec failed (likely ARG_MAX on an oversized prompt): {exc}",
  165|                     ) from exc
  166|         except _SemaphoreExhausted as exc:
  167|             raise ProviderUnavailableError(
```


## P61 — pr-13 · `tests/unit/context-class.bats` lines 111–111 · region inside the PR's diff · enclosing symbol: CC-9 the protocol shows both classes, the include cites the rule, /loa prints the recorded class

### The reviewer's finding(s) citing this region

```text
head/.claude/hooks/session-start/loa-context-class.sh:26 — ROOT is the git toplevel of the caller's CWD (or `pwd`), unlike the sibling session-start hook which derives it from its own location; `display_context_line` (head/.claude/scripts/loa-status.sh:873) passes no `--root`, so `/loa` and test CC-9 read whichever repo the CWD sits in. Reproduced: `TMPDIR=<checkout>/.eval-tmp bats tests/unit/context-class.bats` fails CC-9 (head/tests/unit/context-class.bats:111) with the host repo's class. (LOW)
```

```text
- **LOW** (confidence: high) `head/.claude/hooks/session-start/loa-context-class.sh:26` — `ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"` takes the root from the caller's CWD, whereas `loa-run-state-surface.sh` derives it from its own location (`HOOK_DIR/../../..`). `display_context_line` (`head/.claude/scripts/loa-status.sh:873`) calls `--show` without `--root`, so `/loa` reports whichever repo the shell happens to be in. Concrete failure: run the suite with a temp dir inside a checkout — `TMPDIR=<checkout>/.eval-tmp bats tests/unit/context-class.bats` — and CC-9 (`head/tests/unit/context-class.bats:111`) fails because the hook reads the checkout's `.run/context-class` instead of `$T`'s (reproduced here: it printed the host tree's `long (default)`).
**Suggestion:** resolve ROOT from `HOOK_DIR` like the sibling hook (keeping `--root` as the override), and have `display_context_line` pass `--root "$PROJECT_ROOT"` if `loa-status.sh` already knows it.
**Benefit:** one root-resolution rule across the session-start hooks; CC-9 stops depending on where `TMPDIR` points.
```

```text
- **Severity:** LOW | **Confidence:** high
- **File:** `head/.claude/hooks/session-start/loa-context-class.sh:26` (also `head/.claude/scripts/loa-status.sh:873`, `head/tests/unit/context-class.bats:111`)
- **Code:** `ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`
- **Issue:** `loa-run-state-surface.sh:22` derives its root from `HOOK_DIR/../../..`; this hook takes the git toplevel of whatever directory the caller is in, and `display_context_line` calls `--show` with no `--root`. Reproduced: with the bats temp dir inside a checkout (`TMPDIR=<checkout>/.t bats tests/unit/context-class.bats`) CC-9 fails — the hook reads the checkout's `.run/context-class` instead of `$T`'s. In practice `/loa` and the hook agree (both use the CWD's toplevel), so the user-visible effect is confined to the test and to invocations from a nested repo.
- **Fix:** resolve `ROOT` from `HOOK_DIR` as the sibling does, keep `--root` as the override, and have `display_context_line` pass `--root "$PROJECT_ROOT"` (already computed at `loa-status.sh:21`).
- **Reference:** CWE-706 Use of Incorrectly-Resolved Name or Reference — https://cwe.mitre.org/data/definitions/706.html
```

### Head file context (line| text)

```text
  101| @test "CC-9 the protocol shows both classes, the include cites the rule, /loa prints the recorded class" {
  102|   local p="$PROJECT_ROOT/.claude/protocols/tool-result-clearing.md" inc="$PROJECT_ROOT/.claude/data/skill-includes/context_discipline.md"
  103|   grep -q '| Context Type | `standard` (≤ 200K) | `long` (≥ 1M, default) | Action |' "$p"
  104|   grep -q 'LOA_CONTEXT_CLASS=standard' "$p"
  105|   grep -q '.run/context-class' "$inc"; grep -q 'tool-result-clearing.md' "$inc"
  106|   grep -q 'long 20K/50K/30K/150K, standard 2K/5K/3K/15K' "$inc"
  107|   local fn; fn="$(sed -n '/^display_context_line() {/,/^}/p' "$PROJECT_ROOT/.claude/scripts/loa-status.sh")"
  108|   [ -n "$fn" ]
  109|   grep -A1 '^      display_run_line$' "$PROJECT_ROOT/.claude/scripts/loa-status.sh" | grep -q 'display_context_line'
  110|   mkdir -p "$T/.run"; printf 'standard\nbasis=env model=null context_window=null ts=x\n' > "$T/.run/context-class"
  111|   run bash -c "cd '$T' && SCRIPT_DIR='$PROJECT_ROOT/.claude/scripts'; $fn
  112| display_context_line"
  113|   [ "$status" -eq 0 ]
  114|   [ "$output" = "  Context: standard (env; thresholds 2K/5K/3K/15K)" ]
  115| }
  116| 
```

### The PR's diff hunk covering these lines

```diff
@@ -0,0 +1,115 @@
+#!/usr/bin/env bats
+# =============================================================================
+# tests/unit/context-class.bats — cycle-126 Sprint 3 (PRD FR-3.1, SDD D-3.1)
+# The context class: `long` by default; `standard` under LOA_CONTEXT_CLASS=standard
+# or when the session model resolves to a catalog entry with context_window
+# ≤ 200000 (alias-aware); written to .run/context-class atomically; never a
+# non-zero exit; `--line` is the /loa line.
+# =============================================================================
+
+setup() {
+  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
+  HOOK="$PROJECT_ROOT/.claude/hooks/session-start/loa-context-class.sh"
+  T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/cc.XXXXXX")"
+  unset LOA_CONTEXT_CLASS
+}
+teardown() { find "$T" -mindepth 1 -delete 2>/dev/null || true; rmdir "$T" 2>/dev/null || true; }
+_class() { head -1 "$T/.run/context-class"; }
+_basis() { sed -n 2p "$T/.run/context-class" | grep -o 'basis=[a-z]*' | cut -d= -f2; }
+
+@test "CC-1 default: long, basis default, file written (creating .run), exit 0, silent as a hook" {
+  run bash "$HOOK" --root "$T" < /dev/null
+  [ "$status" -eq 0 ]; [ -z "$output" ]
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+  [ ! -e "$T/.run/.context-class."* ] || false
+}
+
+@test "CC-2 LOA_CONTEXT_CLASS=standard selects standard (basis env); =long pins long" {
+  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "env" ]
+  LOA_CONTEXT_CLASS=long run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "env" ]
+}
+
+@test "CC-3 a 200K session model selects standard, a 1M model long, an alias resolves (tiny → Haiku)" {
+  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 < /dev/null
+  [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
+  run bash "$HOOK" --root "$T" --model claude-opus-5 < /dev/null
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "model" ]
+  run bash "$HOOK" --root "$T" --model tiny < /dev/null
+  [ "$(_class)" = "standard" ]
+  run bash "$HOOK" --root "$T" --model anthropic:claude-sonnet-4-5-20250929 < /dev/null
+  [ "$(_class)" = "standard" ]
+}
+
+@test "CC-4 the hook payload's .model on stdin is honoured when no --model is given" {
+  run bash -c "printf '%s' '{\"session_id\":\"s\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\",\"model\":\"claude-haiku-4-5-20251001\"}' | bash '$HOOK' --root '$T'"
+  [ "$status" -eq 0 ]; [ "$(_class)" = "standard" ]; [ "$(_basis)" = "model" ]
+  run bash -c "printf '%s' '{\"session_id\":\"s\",\"source\":\"resume\"}' | bash '$HOOK' --root '$T'"
+  [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+}
+
+@test "CC-5 an unknown model, malformed stdin or a missing catalog all fall back to long, exit 0" {
+  run bash "$HOOK" --root "$T" --model not-a-model < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]; [ "$(_basis)" = "default" ]
+  run bash -c "printf 'not json' | bash '$HOOK' --root '$T'"
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
+  run bash "$HOOK" --root "$T" --model claude-haiku-4-5-20251001 --catalog "$T/absent.yaml" < /dev/null
+  [ "$status" -eq 0 ]; [ "$(_class)" = "long" ]
+}
+
+@test "CC-6 --line prints the /loa line and --json the record; the model id in the payload is sanitised" {
+  run bash "$HOOK" --root "$T" --line < /dev/null
+  [ "$status" -eq 0 ]
+  [[ "$output" == "Context: long (default; thresholds 20K/50K/30K/150K"* ]]
+  LOA_CONTEXT_CLASS=standard run bash "$HOOK" --root "$T" --line < /dev/null
+  [[ "$output" == "Context: standard (env; thresholds 2K/5K/3K/15K)" ]]
+  run bash "$HOOK" --root "$T" --json --model claude-opus-5 < /dev/null
+  echo "$output" | jq -e '.class == "long" and .basis == "model" and .model == "claude-opus-5" and .context_window == 1000000' >/dev/null
+  # shell metacharacters never reach yq or the record: the id is stripped to its safe characters (and then resolves to nothing)
…[hunk truncated]
```
