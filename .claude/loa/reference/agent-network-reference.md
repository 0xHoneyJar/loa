# Agent-Network Primitives Reference (L1–L7)

Detailed constraint tables and implementation rules for the agent-network primitives shipped in cycle-098. Moved out of `CLAUDE.loa.md` — consult this file (or the relevant skill) whenever working ON these primitives: their libraries, hooks, schemas, or audit chains.

| Primitive | Skill | Library |
|---|---|---|
| Audit Envelope | — | `.claude/scripts/lib/` (`audit_emit`, `lib/jcs.sh`) |
| L3 Scheduled-Cycle | `scheduled-cycle-template` | `scheduled-cycle-lib.sh` |
| L4 Graduated-Trust | `graduated-trust` | `graduated-trust-lib.sh` |
| L5 Cross-Repo Status | `cross-repo-status-reader` | `cross-repo-status-lib.sh` |
| L6 Structured-Handoff | `structured-handoff` | `structured-handoff-lib.sh` |
| L7 Soul-Identity-Doc | `soul-identity-doc` | `soul-identity-lib.sh` |

## Agent-Network Audit Envelope (cycle-098 Sprint 1)

The L1-L7 audit infrastructure ships in cycle-098. All primitives use a shared envelope at `.claude/data/trajectory-schemas/agent-network-envelope.schema.json` (v1.1.0) with hash-chain + Ed25519 signatures.

### Audit Envelope Constraints

| Rule | Why |
|------|-----|
| ALWAYS use `audit_emit` (or `audit_emit_signed`) for L1-L7 audit writes — never `>>` directly | `audit_emit` acquires flock on `<log_path>.lock` for the entire compute-prev-hash → sign → validate → append sequence (CC-3). Direct appends race against concurrent writers and corrupt the hash chain. |
| ALWAYS canonicalize via `lib/jcs.sh` (RFC 8785 JCS) — NEVER substitute `jq -S -c` | JCS is byte-deterministic across adapters (R15: bash + Python + Node identity). `jq -S` orders keys but does not enforce number canonicalization or whitespace identity. |
| ALWAYS check trust-store cutoff before relying on signature absence | Post-trust-cutoff entries REQUIRE both `signature` AND `signing_key_id`. Stripping either is a downgrade attack and produces `[STRIP-ATTACK-DETECTED]` (F1 review remediation). |
| NEVER pass private key passwords via argv or env vars | Use `--password-fd N` or `--password-file <path>` (mode 0600). The legacy `LOA_AUDIT_KEY_PASSWORD` env var is deprecated; helper emits a stderr warning + scrubs after read. |
| ALWAYS exit 78 (EX_CONFIG) when a configured signing key is missing | Distinguishes bootstrap-pending state (operator hasn't generated keys) from data corruption. Caller routes 78 to `grimoires/loa/runbooks/audit-keys-bootstrap.md`. |
| ALWAYS run `audit_recover_chain` before manual log surgery | NFR-R7 recovery walks git history (TRACKED logs L4/L6) or restores from snapshot archive (UNTRACKED L1/L2). Manual surgery breaks the chain unrecoverably. |

**Reference**: `.claude/data/audit-retention-policy.yaml` (per-primitive retention) + `grimoires/loa/runbooks/audit-keys-bootstrap.md` (operator bootstrap).

## L3 Scheduled-Cycle Template (cycle-098 Sprint 3)

The L3 chassis runs scheduled autonomous cycles via a 5-phase DispatchContract (`reader → decider → dispatcher → awaiter → logger`) wrapped in flock + content-addressed idempotency + optional L2 budget gate. Library: `.claude/scripts/lib/scheduled-cycle-lib.sh`. Schemas: `.claude/data/trajectory-schemas/cycle-events/`. Skill: `.claude/skills/scheduled-cycle-template/`.

### Scheduled-Cycle Constraints

| Rule | Why |
|------|-----|
| ALWAYS use `cycle_invoke` (or the lib's `invoke` subcommand) — never call phase scripts directly from cron | Direct invocation bypasses flock, idempotency, audit envelope, and budget gate. The chassis IS the contract; the phase scripts are payload only. |
| ALWAYS treat `cycle.complete` as the ONLY idempotency gate — errored runs MUST retry | Errors are typically transient. The chassis cannot distinguish "transient failure" from "permanent failure" without the domain-specific phase scripts; retrying is the safe default. Permanent-failure detection is the dispatcher/logger's responsibility. |
| ALWAYS hold the flock across the entire cycle (cycle.start → terminal event), not per phase | Per-phase locking allows two cron firings to interleave their phases; only whole-cycle locking prevents the overlap that FR-L3-5 forbids. |
| ALWAYS bound phase invocations with the `timeout` command — never trust phase scripts to self-bound | Phase scripts are caller-supplied and untrusted. Without `timeout`, a hung phase blocks the lock and prevents the next cycle from firing forever. |
| ALWAYS treat phase stdout as opaque (hash for `output_hash`; do not interpret) and stderr as redactable diagnostic | Phase output is unsanitized caller content; interpretation in the chassis would invite injection. Redaction (`_l3_redact_diagnostic`) prevents stack-trace leaks of api keys / tokens. |
| ALWAYS use `--cycle-id` for retries / replay; let the chassis compute it for fresh runs | The default content-addressed `cycle_id` derives from minute-precision `ts_bucket` — two firings within the same minute would collide. Explicit `--cycle-id` is required when the test or operator needs determinism. |
| MAY compose L2 budget pre-check via `LOA_L3_BUDGET_PRECHECK_ENABLED=1` or `.scheduled_cycle_template.budget_pre_check: true` | The CC-9 compose-when-available pattern: L3 ships standalone first, deployments opt in to the cost gate when L2 is enabled and the schedule declares a `budget_estimate_usd`. |
| NEVER write phase scripts that modify shared state under the same lock the cycle holds | The flock guards `.run/cycles/<schedule_id>.lock`; phase scripts that try to acquire the same lock will deadlock waiting on the chassis itself. Phase-internal locks must use a different file. |
| ALWAYS keep `dispatch_contract.<phase>` paths inside one of the configured `phase_path_allowed_prefixes` | The chassis canonicalizes phase paths via `realpath` and rejects anything outside the allowlist (default: `.claude/skills`, `.run/schedules`, `.run/cycles-contracts`). Absolute paths outside the list, and `..`-traversal relative paths, are rejected at register-time AND at every invocation. |
| NEVER export sensitive env vars to the cycle expecting them to flow into phase scripts — phase scripts run under `env -i` with a minimal allowlist | API keys, GitHub tokens, AWS credentials, and arbitrary `LOA_*` vars are stripped by default. Extend the allowlist per-deployment via `LOA_L3_PHASE_ENV_PASSTHROUGH` (env-name regex `[A-Z_][A-Z0-9_]*` enforced) — never assume passthrough. |
| NEVER set `LOA_L3_L2_LIB_OVERRIDE` outside test fixtures | The override `source`s arbitrary bash code into the cycle process. The chassis honors it only when `LOA_L3_TEST_MODE=1` or under bats; production paths emit a warning and ignore it. |
| ALWAYS keep `dispatch_contract.timeout_seconds × 5 ≤ max_cycle_seconds` | The chassis caps total projected cycle time (default 14400s = 4h). A malicious or sloppy YAML setting `timeout_seconds: 86400` would park the lock for 5 days. Raise the cap explicitly via `.scheduled_cycle_template.max_cycle_seconds` if the workload genuinely needs it. |
| ALWAYS rely on the chassis's audit envelope for idempotency reasoning — never inspect `.run/cycles.jsonl` with a hand-rolled jq filter that ignores `primitive_id` / `prev_hash` / signatures | The Sprint 3 remediation tightened `cycle_idempotency_check` to require the full envelope wrapper + `outcome=="success"` + canonical `phases_completed`. Hand-rolled filters re-introduce the audit-log forgery surface that the remediation closed. |

**Reference**: `.claude/skills/scheduled-cycle-template/SKILL.md` (caller-facing usage) + `grimoires/loa/sdd.md` §5.5 (full API spec).

## L4 Graduated-Trust (cycle-098 Sprint 4)

The L4 primitive maintains a per-(scope, capability, actor) trust ledger where tier ratchets up by demonstrated alignment (operator grants) and ratchets down automatically on observed override (record_override → auto_drop + cooldown). Hash-chained for tamper detection; TRACKED in git for reconstructability. Library: `.claude/scripts/lib/graduated-trust-lib.sh`. Schemas: `.claude/data/trajectory-schemas/trust-events/`. Skill: `.claude/skills/graduated-trust/`.

> **⚠ STATUS: EXPERIMENTAL / build-ahead (dormant).** Only slice 4A (foundation) shipped; transitions / integrity / seal (4B/4C/4D) are TODO. L4 is `enabled: false` by default with **no runtime footprint** (no on-disk trust ledger, never ratcheted) — it is **NOT a live control**. Do not reason about graduated-trust as an active guarantee. Retained build-ahead for a future multi-tenant / standards-contribution path (relabel cycle OKF/ICM, 2026-06-28; analysis rec #6).

### Graduated-Trust Constraints

| Rule | Why |
|------|-----|
| ALWAYS use `trust_grant` (not direct `audit_emit "L4" "trust.grant"`) for tier transitions | trust_grant validates the transition against operator-defined transition_rules (FR-L4-2), enforces cooldown (FR-L4-3), and serializes via the .txn.lock. Direct audit_emit bypasses all of these and corrupts the trust contract. |
| ALWAYS configure at least one `auto_drop_on_override` rule when `graduated_trust.enabled: true` | trust_record_override refuses to invent drop semantics. Without an explicit rule (or `from: any, to_lower: true` fallback), every override returns exit 3 — observable as a misconfiguration loop. |
| ALWAYS prefer the FROZEN `payload.cooldown_until` over recomputing from current `cooldown_seconds` config | Audit-immutability: changing cooldown_seconds in operator config later must NOT retroactively shift past windows. The 4A resolver reads the frozen value; tooling that bypasses the lib MUST do the same. |
| NEVER share the audit_emit lock file (`<log>.lock`) with a transaction lock — use `<log>.txn.lock` for read-modify-write atoms | audit_emit's flock guards the chain append; a higher-level transaction (cooldown check vs concurrent writer) needs its own lock. Same lock = deadlock when the transaction calls audit_emit. |
| NEVER call `trust_grant --force` without a `--reason` | Force-grant is the only path that bypasses cooldown. Reason is the auditor's only signal; the lib refuses an empty/missing reason (exit 2). |
| ALWAYS treat `trust.force_grant` as a protected-class operation per `protected-classes.yaml` | Force-grant overrides the safety mechanism; protected-class-router classifies it as operator-bound by definition. Tools that wrap trust_grant --force MUST go through the operator-confirmation flow. |
| ALWAYS reconstruct via `trust_recover_chain` (not by hand) when chain validation fails | trust_recover_chain wraps audit_recover_chain which knows the TRACKED-log git-history walk path. Hand-rolled rebuilds reintroduce path-resolution bugs (cycle-098 Sprint 4 patched a basename-vs-repo-relative-path defect in `_audit_recover_from_git`). |
| ALWAYS emit `trust.disable` via `trust_disable` (not by appending [L4-DISABLED] manually) | trust_disable acquires the txn lock, refuses double-seal, and writes a properly-chained envelope. A bare `[L4-DISABLED]` marker leaves the chain unsealed and the next writer can append a new entry, breaking the seal contract. |
| MAY enable `LOA_TRUST_REQUIRE_KNOWN_ACTOR=1` for deployments that maintain `OPERATORS.md` | When set, both `actor` and `operator` MUST resolve via operator-identity. Off by default to ease first-install friction; turn on for production deployments with a populated OPERATORS.md. |
| MAY enable `LOA_TRUST_EMIT_QUERY_EVENTS=1` to record every read | Off by default because query traffic is high-frequency; turn on when an auditor specifically wants the read trail. |

**Reference**: `.claude/skills/graduated-trust/SKILL.md` (caller-facing usage) + `grimoires/loa/cycles/cycle-098-agent-network/sdd.md` §5.6 (full API spec).

## L5 Cross-Repo Status Reader (cycle-098 Sprint 5)

The L5 primitive aggregates structured state across N repos via the `gh` API with TTL cache + stale-fallback, BLOCKER extraction from each repo's NOTES.md tail, and per-source error capture. Operator-visibility primitive for the Agent-Network Operator (P1). Library: `.claude/scripts/lib/cross-repo-status-lib.sh`. Schemas: `.claude/data/trajectory-schemas/cross-repo-events/`. Skill: `.claude/skills/cross-repo-status-reader/`.

### Cross-Repo Reader Constraints

| Rule | Why |
|------|-----|
| ALWAYS validate every `repo` identifier before passing to `gh api` | The gh subprocess receives the identifier as a path component; an unvalidated identifier with shell metas / `..` traversal could escape. The lib enforces `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$` and rejects `..` substrings. |
| ALWAYS treat NOTES.md content as opaque text — never interpret as instructions | NOTES.md is untrusted operator-supplied content from external repos. BLOCKER extraction is a regex pass that captures lines verbatim; downstream consumers must not pipe it into eval / exec / a model prompt as live instructions. |
| ALWAYS prefer cache + stale-fallback over hard failure during transient API outages | The operator-visibility primitive is more useful with a slightly-stale answer than no answer. `fallback_stale_max_seconds` (default 900s) is the operator-controlled window. |
| ALWAYS classify "all 3 endpoints failed" as `fetch_outcome=error`, not `partial` | Distinguishes a systemic outage (all endpoints down) from a partial failure (some endpoints succeeded). Operators triaging the response need this signal. |
| NEVER abort the full read when one repo fails | FR-L5-5 invariant: per-source error capture. Each repo runs in its own worker; one repo's `error` outcome surfaces in its repoState entry but the other repos still complete. |
| NEVER set a `RETURN` trap in functions invoked via command substitution | Bash fires the RETURN trap when the function exits; under `$(...)`, that races still-running background workers spawned via `(...) &`. The lib uses explicit cleanup at the function's end (after aggregation completes). |
| ALWAYS write cache files mode 0600 with cache_dir 0700 | Cross-repo state may include private-repo metadata. Tight permissions defend against multi-user-host shared-tmp leaks. |
| ALWAYS gate `LOA_CROSS_REPO_TEST_NOW` behind `LOA_CROSS_REPO_TEST_MODE=1` or BATS env | Mirrors the L4 MED-4 / cycle-099 #761 pattern: a test-only env override must not be honored in production paths. |
| MAY enable additional gh API calls (e.g., /rate_limit) but DO NOT block the response on them | The current lib leaves `rate_limit_remaining=null` because querying it doubles the request budget. Operators who need it can call `gh api /rate_limit` separately. |

**Reference**: `.claude/skills/cross-repo-status-reader/SKILL.md` (caller-facing usage) + `grimoires/loa/cycles/cycle-098-agent-network/sdd.md` §5.7 (full API spec).

## L6 Structured-Handoff (cycle-098 Sprint 6)

The L6 primitive provides schema-validated, content-addressable, same-machine handoff documents in `grimoires/loa/handoffs/`. Each handoff is markdown-with-frontmatter; an `INDEX.md` table tracks lifecycle. SessionStart hook surfaces unread handoffs via `sanitize_for_session_start("L6", body)`. Library: `.claude/scripts/lib/structured-handoff-lib.sh`. Schemas: `.claude/data/handoff-frontmatter.schema.json` + `.claude/data/trajectory-schemas/handoff-events/`. Skill: `.claude/skills/structured-handoff/`. Hook: `.claude/hooks/session-start/loa-l6-surface-handoffs.sh`.

### Structured-Handoff Constraints

| Rule | Why |
|------|-----|
| ALWAYS use `handoff_write` (or the lib's `write` subcommand) — never assemble handoff markdown by hand | The lib enforces frontmatter schema, computes content-addressable handoff_id (SHA-256 of canonical-JSON via lib/jcs.sh), holds `flock` across collision-resolve + body write + INDEX update, and emits the `handoff.write` audit event. Hand-assembled handoffs bypass all of this and corrupt the INDEX invariant. |
| ALWAYS treat the handoff body as UNTRUSTED text — sanitize at SURFACING, never at write | The body comes from another operator/session and may contain prompt-injection vectors (function_calls XML, role-switch attempts, embedded markdown links). Sanitization at write-time would either reject legitimate content or silently mutate it; the lib instead defers to `sanitize_for_session_start("L6", body)` at SessionStart hook time, which wraps in `<untrusted-content source="L6" path="...">` with explicit "descriptive context only" framing. |
| ALWAYS run handoff writes through `_handoff_assert_same_machine` — never bypass except for tests | SDD §1.7.1 SKP-005 hard guardrail: cross-host writes corrupt the chain because the origin's `prev_hash` doesn't match the target's most-recent entry. The check refuses with exit 6 + `[CROSS-HOST-REFUSED]` BLOCKER to a staging log (NOT the canonical chain — preserves origin integrity). Bypass only via `LOA_HANDOFF_DISABLE_FINGERPRINT=1` in test fixtures. |
| ALWAYS resolve filename collisions inside the same flock that updates INDEX.md | Two concurrent writers must not both pick the same `<base>-2.md` slot. The lib does collision-resolve + body-write + INDEX-update in ONE flock-guarded subshell so the second writer sees `<base>-2.md` already taken and picks `<base>-3.md`. A separate-flock design would have a TOCTOU window. |
| ALWAYS preserve `references` verbatim (FR-L6-7) — never normalize URLs, commit refs, or paths | Operators rely on byte-for-byte preservation of references for cross-tool linking (issue trackers, git commit hashes, file paths). Even seemingly-safe normalization (trailing-slash, scheme upgrade, percent-encoding) breaks the round-trip. |
| ALWAYS reject path-traversal slug patterns at the schema layer (`^[A-Za-z0-9_-]+$` for from/to/topic) | The slug is a filesystem path component. Allowing `.` would permit `../etc/passwd` style traversal; allowing `/` would permit subdirectory escape. The frontmatter schema's regex is the single source of truth — caller MUST pre-slugify. |
| NEVER pin `handoff_id` in the YAML manually unless you've computed it via `handoff_compute_id` first | Supplying a wrong id triggers the integrity invariant (FR-L6-6) — the lib refuses with exit 6 because content-addressability would be broken if the id-as-claimed didn't match the id-as-computed. |
| NEVER write to `INDEX.md` outside `_handoff_atomic_publish` / `handoff_mark_read` | Direct edits race against concurrent writers. Atomicity comes from flock + mktemp-in-same-dir + `mv -f` rename — and only the lib's helpers obey that protocol. |
| NEVER call `audit_emit` for L6 outside this lib | The lib's audit payload conforms to `handoff-write.payload.schema.json`. Hand-rolled emits would skip schema validation, the operator-verification field, and the file_path provenance. |
| MAY set `LOA_HANDOFF_VERIFY_OPERATORS=0` to skip OPERATORS.md verification (default true). | When true, strict-mode rejects writes whose `from` or `to` slug isn't an active operator in OPERATORS.md (exit 3). Warn-mode accepts but tags `operator_verification: unverified` in the audit payload. Off by default in tests for non-verification scenarios. |
| MAY set `LOA_HANDOFF_SUPPRESS_SURFACE_AUDIT=1` to suppress the `handoff.surface` audit event | Frequent surfacing (every SessionStart) generates audit traffic. Off by default; turn on for low-noise environments where the surface trail isn't needed. |

**Reference**: `.claude/skills/structured-handoff/SKILL.md` (caller-facing usage) + `grimoires/loa/cycles/cycle-098-agent-network/sdd.md` §5.8 + §1.7.1 (full API + same-machine guardrail spec).

## L7 Soul-Identity-Doc (cycle-098 Sprint 7)

The L7 primitive ships a schema-validated descriptive identity document (`SOUL.md`) at project root, distinct from prescriptive `CLAUDE.md`. A SessionStart hook reads, validates, sanitizes via `sanitize_for_session_start("L7", body)`, and surfaces the body wrapped in `<untrusted-content source="L7">` markers. Library: `.claude/scripts/lib/soul-identity-lib.sh`. Schemas: `.claude/data/soul-frontmatter.schema.json` + `.claude/data/trajectory-schemas/soul-events/`. Skill: `.claude/skills/soul-identity-doc/`. Hook: `.claude/hooks/session-start/loa-l7-surface-soul.sh`. Prescriptive-rejection patterns: `.claude/data/lore/agent-network/soul-prescriptive-rejection-patterns.txt`.

### Soul-Identity-Doc Constraints

| Rule | Why |
|------|-----|
| ALWAYS use `soul_validate` (or the CLI shim `.claude/skills/soul-identity-doc/resources/soul-validate.sh`) — never assemble a SOUL.md by hand without running validation | The lib enforces frontmatter schema (Draft 2020-12), required sections, defense-in-depth control-byte rejection in YAML scalars (closes the Python `re.$` trailing-newline bypass class — same defense as L6 sprint 6 CYP-F2), and prescriptive-pattern matching against `soul-prescriptive-rejection-patterns.txt`. Hand-written docs can drift into prescriptive content that bypasses NFR-Sec3. |
| ALWAYS treat the SOUL.md body as UNTRUSTED text — sanitize at SURFACING, never at write | SOUL.md is operator-authored but reaches session context via the SessionStart hook. The lib NEVER interprets the body as instructions. Sanitization happens at surface time via `sanitize_for_session_start("L7", body)` (same mechanism L6 uses for handoff bodies), wrapping the body in `<untrusted-content source="L7" path="SOUL.md">` markers with explicit "descriptive context only" framing. |
| ALWAYS reject prescriptive sections at schema layer (NFR-Sec3) — the descriptive vs prescriptive boundary is load-bearing | Sections opening with imperative verbs (MUST, ALWAYS, NEVER, DO, DON'T) or markdown rule tables are matched by patterns in `.claude/data/lore/agent-network/soul-prescriptive-rejection-patterns.txt`. Strict mode rejects; warn mode loads with `[SCHEMA-WARNING]` marker. Mixing prescriptive content into SOUL.md collapses the boundary that makes both files useful — rules belong in CLAUDE.md, identity belongs in SOUL.md. |
| ALWAYS use `soul_emit` for `soul.surface` / `soul.validate` audit events — never call `audit_emit` directly | `soul_emit` validates the payload against `.claude/data/trajectory-schemas/soul-events/<event>.payload.schema.json` BEFORE delegating to `audit_emit`. Direct calls bypass schema validation, including the outcome-enum check that pins audit-event semantics across primitives. |
| ALWAYS gate SOUL.md path / log overrides behind the strict test-mode env-var gate | `LOA_SOUL_LOG`, `LOA_SOUL_TEST_PATH`, `LOA_SOUL_TEST_CONFIG` are honored ONLY when BOTH `LOA_SOUL_TEST_MODE=1` is set AND a bats marker (`BATS_TEST_FILENAME` or `BATS_VERSION`) is present. Earlier drafts allowed `BATS_TMPDIR` alone — closed in cycle-098 sprint-7 cypherpunk CRIT-1. Same pattern class as L4 cycle-099 #761; the dual-condition (opt-in flag AND bats marker) is the canonical form. Production paths emit a stderr `WARNING: env override ignored` and use defaults. |
| ALWAYS realpath-canonicalize and REPO_ROOT-contain config-supplied SOUL.md paths in production | The `.loa.config.yaml::soul_identity_doc.path` key is operator-controlled but UNTRUSTED at hook-fire time (a malicious PR / poisoned fork / dependency drop can plant a `.loa.config.yaml`). Without containment, an absolute path or `..` traversal lets the attacker surface arbitrary readable files (e.g., `/etc/passwd`, `~/.ssh/id_rsa`) as `<untrusted-content>` markers in the LLM session — and into the audit log. cycle-098 sprint-7 cypherpunk HIGH-1 closure: `realpath -m` + REPO_ROOT-prefix containment + `..` substring rejection. Test-mode is exempt because fixtures live under `mktemp` directories outside REPO_ROOT. |
| ALWAYS NFKC-normalize + zero-width-strip section bodies before prescriptive-pattern matching | Plain `^MUST\b` / `^NEVER\b` regex (case-insensitive) is bypassed by FULLWIDTH (`Ｍ Ｕ Ｓ Ｔ`, U+FF2D etc.) and zero-width insertions (`M​UST`). cycle-098 sprint-7 cypherpunk HIGH-2 closure: `unicodedata.normalize("NFKC", body)` + strip Cf-category zero-width chars before applying regex. Mirrors cycle-099 sprint-1E.c.3.c Unicode-glob bypass closure in `tools/check-no-raw-curl.sh`. |
| ALWAYS scrub C0/C1/control bytes + zero-width chars from section headings before they enter audit payloads | Without scrubbing, an attacker can embed ANSI escapes / control bytes in a section heading; the audit-payload schema regex `^[A-Za-z0-9 _-]{1,64}$` rejects the resulting payload; `soul_emit` exits non-zero; the hook's `\|\| true` silences the failure. Net effect: body still surfaces in warn mode, but the audit chain is blinded to the attempt. cycle-098 sprint-7 cypherpunk HIGH-4 closure: scrub headings in `_soul_classify_sections` before populating `prescriptive_hits` / `unknown_sections`, replacing disallowed characters with `_`. |
| NEVER include keys outside the schema in SOUL.md frontmatter (`additionalProperties: false`) | The frontmatter schema is exhaustive: `schema_version`, `identity_for`, `provenance`, `last_updated`, `tags`. Adding a key like `prescriptive_override: true` would not be a meaningful extension — it would be a bypass attempt. Schema validation rejects extras; future schema bumps follow the L6 precedent (pattern not enum on `schema_version` so new versions don't self-DoS the audit emit). |
| NEVER set `LOA_L7_SURFACED=1` outside the SessionStart hook itself | The cache marker is the hook's single-fire mechanism (FR-L7-5). Setting it from skill code or test fixtures would silently suppress the hook's normal path and mask config / file-presence bugs. Tests that need to verify the cache use the env var deliberately, never as a workaround. |
| MAY add domain-specific patterns to `soul-prescriptive-rejection-patterns.txt` to refine NFR-Sec3 enforcement | The pattern file is editable lore — Sprint 7 ships a conservative starter set (imperative verbs at section start + rule tables + numbered rule lists). Operators may extend with project-specific patterns. Patterns are Python regex, case-insensitive, multiline-anchored. Add patterns sparingly; over-matching produces false positives that erode confidence in the validator. |
| MAY surface a `[SCHEMA-WARNING]` SOUL.md (warn mode) but the operator SHOULD treat warnings as prompts to fix | warn mode is the default per SDD §5.13 — strict mode is opt-in. The intent is to land valid SOUL.md docs on first commit while avoiding hard breakage if a pre-existing doc misses a section. Treat persistent warnings as a signal to fix the doc, not as ambient noise. |

**Reference**: `.claude/skills/soul-identity-doc/SKILL.md` (caller-facing usage) + `grimoires/loa/cycles/cycle-098-agent-network/sdd.md` §5.9 (full API spec) + §1.4.2 (component spec) + §1.9.3.2 (sanitization model).
