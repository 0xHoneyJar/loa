# cycle-099-model-registry — Session Resumption Brief

**Last updated**: 2026-05-05 (Sprint 1 ~92% complete: 1A + 1B + 1C + 1E.a + 1E.b + 1E.c.1 SHIPPED; **next: 1D cross-runtime corpus OR 1E.c.2 DNS rebinding OR 1E.c.3 bash caller migration**)
**Author**: deep-name + Claude Opus 4.7 1M
**Purpose**: Crash-recovery + cross-session continuity. Read first when resuming cycle-099 work.

## 🚨 TL;DR — Sprint 1 is ~92% done; 7 cycle-099 PRs on main

**On main (7 PRs):**
- chore #721 (`9ef33055`) — cycle-099 ledger activation + planning artifacts (mirrors cycle-098 #679 pattern)
- Sprint-1A #722 (`78c59568`) — bridgebuilder codegen foundation (T1.1 + T1.2)
- Sprint-1B #723 (`7140ff1c`) — adapter migrations + drift gate + lockfile (T1.3 + T1.4 + T1.5 + T1.6 + T1.8 + T1.10 partial)
- Sprint-1C #724 (`8b008b9b`) — codegen reproducibility matrix CI + toolchain runbook (T1.7 + T1.9) + latent-drift fix
- Sprint-1E.a #728 (`cd1c2438`) — log-redactor (T1.13) + migrate-model-config CLI (T1.14)
- Sprint-1E.b #729 (`fbd7c048`) — centralized endpoint validator T1.15 partial (Python canonical + bash wrapper + 8-step canonicalization + STRICT urllib.parse import-guard)
- **Sprint-1E.c.1 #730 (`43a60225`)** — TS port via Python+Jinja2 codegen (T1.15 cont.) — 37 cross-runtime parity tests + drift gate with hash cross-check; closes 2 CRITICAL allowlist bypasses caught by dual-review pre-merge

**Cumulative**: ~278 cycle-099 bats tests on main (241 prior + 37 from 1E.c.1), 0 regressions. Drift-gate CI active. Strict v2 schema. Centralized endpoint-validator across Python + bash + TS with cross-runtime parity gate.

### Operator decision needed at session start

> Sprint 1 has T1.10 remaining bats (small) + T1.11/T1.12 cross-runtime corpus + T1.15 remaining follow-ons (DNS rebinding + bash caller migration). Choose Path A, B, or C.

**Path A (Sprint-1D — cross-runtime corpus)**: T1.11 + T1.12. Highest-value remaining piece per SDD §7.6 (strongest determinism guarantee, unblocks Sprint 2's runtime overlay). Estimated ~4-5 hours. Pre-written brief in §"Brief A — Sprint 1D".

**Path B (Sprint-1E.c.2 — DNS rebinding + redirect enforcement)**: NFR-Sec-1 v1.2. Add `_resolve_and_lock_ip()` to endpoint-validator.py: `socket.getaddrinfo` once, lock the resolved (host, IP) pair, refuse if a subsequent resolution yields different IP within request lifetime. Plus IP-range allowlist check (resolved IP must fall in configured CIDR list per provider). HTTP redirect same-host enforcement. Estimated ~2-3 hours. Pre-written brief in §"Brief B — Sprint 1E.c.2".

**Path C (Sprint-1E.c.3 — bash caller migration)**: migrate existing bash callers (`flatline-*.sh`, `model-health-probe.sh`, `anthropic-oracle.sh`, `gpt-review-api.sh`, `mount-loa.sh`, `constructs-*.sh`, `check-updates.sh`, etc. — ~15 files) to funnel through `endpoint_validator__check` before invoking curl. Flips the CI guard from informational to STRICT after migration. Estimated ~3-4 hours. Pre-written brief in §"Brief C — Sprint 1E.c.3".

Path A gives strongest determinism signal; Path B closes the runtime-only SSRF defenses (DNS rebinding); Path C is the actual SSRF closure for production bash code today.

---

## What's on main (cycle-099 inventory)

### Sprint-1A — codegen foundation (`78c59568`)

| Artifact | Path | Notes |
|---|---|---|
| Bun-compatible codegen | `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` | 549 LOC; reads model-config.yaml via yq subprocess; emits TS |
| Generated truncation | `.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts` | TOKEN_BUDGETS map |
| Generated config registry | `.claude/skills/bridgebuilder-review/resources/config.generated.ts` | MODEL_REGISTRY map |
| Build pipeline | `.claude/skills/bridgebuilder-review/package.json::scripts.build` | `npm run build` invokes codegen before tsc |
| Drift-check entrypoint | `npm run gen-bb-registry:check` (exits 3 on stale) | Consumed by sprint-1B drift-gate |
| 33 bats tests | `tests/unit/gen-bb-registry-codegen.bats` | T1-T12 categories incl. prototype-pollution guard |
| tsx pinned | BB skill `package.json` devDeps | Closes supply-chain via `node_modules/.bin/tsx` |

### Sprint-1B — adapter migrations + drift gate (`7140ff1c`)

| Artifact | Path | Notes |
|---|---|---|
| Resolver lib | `.claude/scripts/lib/model-resolver.sh` | `resolve_alias` / `resolve_provider_id`; override gated behind `LOA_MODEL_RESOLVER_TEST_MODE=1` |
| RT model-adapter migration | `.claude/scripts/red-team-model-adapter.sh` | Sources resolver; prefer-resolver-fallback-to-local |
| RT cvds migration | `.claude/scripts/red-team-code-vs-design.sh` | `--model "$_opus_model_id"` (resolved via resolve_alias) |
| Default adapter migration | `.claude/scripts/model-adapter.sh` | Same pattern; cycle-082 keys preserved |
| Lockfile | `.claude/defaults/model-config.yaml.checksum` | SHA256 hex; verified by drift-gate |
| Drift-gate workflow | `.github/workflows/model-registry-drift.yml` | 3 jobs: lockfile-checksum, bash-codegen-check, ts-codegen-check |
| 6 lockfile tests | `tests/integration/lockfile-checksum.bats` | L1-L5 |
| 25 sentinel tests | `tests/integration/legacy-adapter-still-works.bats` | S1-S6 covering all migrations |

### Sprint-1E.c.1 — TS port via Python+Jinja2 codegen (`43a60225`)

| Artifact | Path | Notes |
|---|---|---|
| Jinja2 template | `.claude/scripts/lib/codegen/endpoint-validator.ts.j2` | ~430 LOC TS validator with `{{ }}` substitutions for canonical-Python constants |
| Python emit module | `.claude/adapters/loa_cheval/codegen/emit_endpoint_validator_ts.py` | spec_loader → constant extraction → render → `--check` mode does byte-diff + canonical-source-hash cross-check (catches tampered-canonical scenario) |
| Generated TS | `.claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts` | 489 LOC; DO NOT EDIT — header carries SHA-256 of canonical Python source |
| 37 parity tests | `tests/integration/endpoint-validator-ts-parity.bats` | 8 acceptance + 28 rejection (E1-E20 + E21-E28 review-remediation: percent-encoded dots, Unicode dots, soft-hyphen, backslash, IPv4-octal, IPv6 zone-id, IPv4-compat IPv6) + 1 drift gate |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-c-ts-tests.yml` | Two jobs: drift gate (--check) + parity tests (bats + tsx via BB skill node_modules) |
| Surrogate-aware filter | `_ts_escape_cp` in emit module | non-BMP codepoints use `\u{XXXXX}` brace form (cypherpunk MEDIUM remediation) |
| Authority pre-parse gate | `_validate_authority` in canonical Python | unified gate rejects `%`/`\\`/Unicode dot equivalents/soft-hyphen/zero-width controls/obfuscated IPv4 octets BEFORE either parser normalizes — closes 2 CRITICAL allowlist bypasses |

### Sprint-1E.b — centralized endpoint validator (`fbd7c048`)

| Artifact | Path | Notes |
|---|---|---|
| Validator (Python canonical) | `.claude/scripts/lib/endpoint-validator.py` | ~370 LOC; 8-step pipeline + IPv4 literal block (incl. AWS IMDS + RFC 1918 + decimal/hex/octal obfuscation) + userinfo reject + raw-control-byte gate (CR/LF/TAB/NUL pre-urlsplit); stdlib + idna 3.13 |
| Validator (bash wrapper) | `.claude/scripts/lib/endpoint-validator.sh` | Subprocess delegate hardened against argv smuggling (`--` separator + python -I) and BASH_SOURCE symlink swap (realpath -e + tree-confinement) |
| Test allowlist fixture | `tests/fixtures/endpoint-validator/allowlist.json` | Mirror of cycle-099 production providers (openai/anthropic/google/bedrock × 3 regions) |
| 72 cross-runtime tests | `tests/integration/endpoint-validator-cross-runtime.bats` | E0 userinfo, E1-E8 step rejection, A1-A9 acceptance, B1-B2 wrapper hardening, C1-C8 stream contract, P1-P2 parity |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-b-tests.yml` | Two jobs: parity tests + STRICT Python urllib.parse import-guard (5 import patterns; scope: .claude/{adapters,scripts,skills,commands,hooks}/ + tests/ + scripts/ if exists) |
| Pre-existing baseline | `.github/workflows/lint-pre-existing-urllib.txt` | 3 entries: bedrock_adapter.py, test_bedrock_redaction_adversarial.py, mock_server.py. Cycle-100 expiry target |

### Sprint-1E.a — hardening primitives (`cd1c2438`)

| Artifact | Path | Notes |
|---|---|---|
| Log-redactor (Python canonical) | `.claude/scripts/lib/log-redactor.py` | Stdlib-only; URL userinfo + 6 query-param secret patterns; case-insensitive name match with case preservation |
| Log-redactor (bash twin) | `.claude/scripts/lib/log-redactor.sh` | POSIX BRE; explicit `[Aa]`-style case classes; sed line-by-line; cross-runtime byte-identical |
| Migrate CLI driver | `.claude/scripts/loa-migrate-model-config.py` | argparse + ruamel.yaml + jsonschema; O_NOFOLLOW + 0o600 output; distinct error codes (MIGRATION-PRODUCED vs CONFIG-V2-INVALID) |
| Migrate lib (pure) | `.claude/scripts/lib/model-config-migrate.py` | `migrate_v1_to_v2()` + `detect_schema_version()`; deepcopy-safe; field-level report list |
| v2 JSON Schema | `.claude/data/schemas/model-config-v2.schema.json` | Strict `additionalProperties:false` at root + providers + modelEntry + agentBinding + permissionsBlock; agentBinding forbids tier-tag in `model:` field |
| 37 log-redactor tests | `tests/integration/log-redactor-cross-runtime.bats` | T1-T12 SDD §5.6.4 corpus + T8.4 caller-contract pin |
| 37 migrate tests | `tests/integration/migrate-model-config.bats` | M1-M18 incl. M13 security (symlink, mode, !!python/object), M14 tier_groups edges, M15 pure-function, M16 distinct error codes, M18 strict-mode |
| Dedicated CI | `.github/workflows/cycle099-sprint-1e-tests.yml` | ruamel.yaml + jsonschema pinned; runs both bats + production smoke against `.claude/defaults/model-config.yaml` + cycle-026 perms |

### Sprint-1C — matrix CI + runbook (`8b008b9b`)

| Artifact | Path | Notes |
|---|---|---|
| Matrix CI | `.github/workflows/model-registry-drift.yml::ts-codegen-check` | `[ubuntu-latest, macos-latest]` with platform-aware SHA256-pinned yq |
| Toolchain runbook | `grimoires/loa/runbooks/codegen-toolchain.md` | 168 lines; per-platform install steps; pinned versions |
| Verification script | `tools/check-codegen-toolchain.sh` | `_version_ge` via `sort -V`; CI invokes it on matrix runners |
| Bash codegen drift fix | `.claude/scripts/generated-model-maps.sh` | +5 lines for `claude-sonnet-4-5-20250929` (sprint-1A latent regression) |

---

## Brief A — Sprint 1D (cross-runtime golden corpus, T1.11 + T1.12)

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief A". Then ship Sprint 1D.

Sprint-1D scope (T1.11 + T1.12 per cycle-099 sprint.md §1):
  - 12 golden fixture files at tests/fixtures/model-resolution/ covering
    SDD §7.6.3 scenarios: happy-path tier-tag, explicit-pin, missing-tier-
    fail-closed, legacy-shape-deprecation, override-conflict, extra-only-
    model, empty-config, unicode-operator-id, prefer-pro-overlay, extra-vs-
    override-collision, tiny-tier-anthropic, degraded-mode-readonly
  - 3 cross-runtime runners that consume the fixture corpus identically:
      tests/python/golden_resolution.py
      tests/bash/golden_resolution.bats
      tests/typescript/golden_resolution.test.ts
  - 4 CI workflows:
      .github/workflows/python-runner.yml
      .github/workflows/bash-runner.yml
      .github/workflows/bun-runner.yml
      .github/workflows/cross-runtime-diff.yml
    The cross-runtime-diff job downloads all three runners' artifacts and
    asserts byte-equality. Mismatch fails the build (SDD §7.6.2).

Caveat — the FR-3.9 6-stage resolver is sprint-2 scope. The 1D runners
should test what CURRENTLY exists (the codegen-derived MODEL_PROVIDERS /
MODEL_IDS lookup and the new generated-model-maps.sh / config.generated.ts
output) — i.e., the SUBSET of FR-3.9 behavior that's already implemented.
Sprint 2 will extend the corpus + runners as the full resolver lands.

Continue Path: cut feat/cycle-099-sprint-1d from main (8b008b9b+).

Tooling already in place from sprint-1C:
  - bats v1.10+ (existing repo dependency)
  - Python 3.13 (cheval venv per .claude/scripts/lib/cheval-venv/)
  - tsx via BB skill node_modules (npx --no-install tsx works after npm ci)
  - pyyaml (cheval requirement) — for the python runner
  - yq pinned v4.52.4 with darwin-arm64 SHA256

Quality-gate chain (sprint-1A/1B/1C precedent):
  1. Implement test-first: write golden_resolution.bats first as the canonical
     reference, then port to python and TS verifying byte-equal output
  2. Subagent review (general-purpose) + audit (paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh --pr <N>
  4. Admin-squash after kaironic plateau (typical: 2 iterations for code PRs)

Slice if needed:
  - 1D.a: 12 fixtures + bats runner + bash-runner.yml (smallest, fastest gate)
  - 1D.b: python runner + python-runner.yml
  - 1D.c: TS runner + bun-runner.yml + cross-runtime-diff.yml

Refs: SDD §7.6.3 (fixture corpus); Flatline SDD pass #1 SKP-002 CRITICAL 890
(this is the resolution).
```

---

## Brief B — Sprint 1E.c.2 (DNS rebinding + redirect enforcement)

Sprint-1E.a (T1.13 + T1.14) SHIPPED at #728 cd1c2438. Sprint-1E.b (T1.15 partial — Python canonical + bash wrapper + 8-step pipeline) SHIPPED at #729 fbd7c048. Sprint-1E.c.1 (T1.15 cont. — TS port via Jinja2 codegen) SHIPPED at #730 43a60225. Remaining T1.15 follow-ons: DNS rebinding (Path B) + bash caller migration (Path C).

Paste into a fresh Claude Code session:

```
Read grimoires/loa/cycles/cycle-099-model-registry/RESUMPTION.md FIRST and the section "Brief B". Then ship Sprint 1E.c.

Sprint-1E.c scope (T1.15 follow-ons per cycle-099 SDD §1.9.1):

  Slice into 2-3 sub-PRs (each ~1-2 hours):

  1E.c.1 — TS port via Python+Jinja2 codegen (per SDD §1.9.1 IMP-002):
    .claude/scripts/lib/codegen/endpoint-validator.ts.j2 — Jinja2 template
    .claude/adapters/loa_cheval/codegen/emit_endpoint_validator_ts.py — emit module
    .claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts
    Codegen invocation:
      python3 -m loa_cheval.codegen.emit_endpoint_validator_ts > <out>
    Build pipeline: codegen runs FIRST in BB build; tsc compiles next;
    golden-corpus parity test runs THIRD (TS produces byte-equal validation
    outcomes vs Python canonical). Adds `jinja2` Python dep (~280KB).
    CI guard: bun build + diff-generated-ts (drift = PR fail).

  1E.c.2 — DNS rebinding defense (NFR-Sec-1 v1.2):
    Add `_resolve_and_lock_ip()` to endpoint-validator.py: socket.getaddrinfo
    once, lock the resolved (host, IP) pair, refuse if a subsequent resolution
    yields different IP within the request lifetime. Plus IP-range allowlist
    check (resolved IP must fall in a configured CIDR list per provider).
    Callers thread the locked-IP through to the HTTP client (httpx + curl).
    HTTP redirect same-host enforcement: 3xx Location header must resolve
    to the same locked IP, else reject with [ENDPOINT-REDIRECT-DENIED].

  1E.c.3 — Bash caller migration (the actual SSRF closure):
    Migrate every existing curl/wget caller to funnel through
    endpoint_validator__check FIRST and only proceed if the validator
    accepts the URL. Affected scripts (informational scan reported in
    sprint-1E.b workflow):
      .claude/scripts/flatline-*.sh        (multi-model API calls)
      .claude/scripts/anthropic-oracle.sh  (Anthropic API)
      .claude/scripts/gpt-review-api.sh    (OpenAI/Codex API)
      .claude/scripts/model-health-probe.sh (provider probes)
      .claude/scripts/check-updates.sh     (loa repo-update check)
      .claude/scripts/constructs-*.sh      (construct registry fetches)
      .claude/scripts/license-validator.sh
      .claude/scripts/lib-curl-fallback.sh (wraps curl with retry)
      .claude/scripts/mount-loa.sh         (loa framework install)
    Strategy: introduce endpoint_validator__guarded_curl() helper that
    validates the URL before calling curl. Update each caller. CI guard
    flips from informational to STRICT once migration is complete.

Continue Path: cut feat/cycle-099-sprint-1e-c (or sub-branches) from main (fbd7c048+).

Reference patterns from Sprint-1E.b (#729):
  - .claude/scripts/lib/endpoint-validator.py canonical pipeline (8 steps
    + IPv4 obfuscation + userinfo reject + control-byte gate)
  - .claude/scripts/lib/endpoint-validator.sh wrapper hardening pattern
    (`--` separator, realpath -e tree-confinement, python -I isolated)
  - tests/integration/endpoint-validator-cross-runtime.bats — 72 tests:
    E1-E8 step rejection codes, B1-B2 wrapper hardening, C6-C8 stream
    contract, P1-P2 byte-equal parity helpers
  - .github/workflows/cycle099-sprint-1e-b-tests.yml — STRICT urllib.parse
    import-guard with scope pre-filter (existing dirs only — closes the
    `set -e` × `grep -2-on-missing-dir` race that bit me locally)
  - .github/workflows/lint-pre-existing-urllib.txt — baseline-with-comments
    pattern for migration debt tracking

Tooling already in place:
  - .venv has idna 3.13 + ruamel.yaml + jsonschema pinned
  - For 1E.c.1 jinja2: pip install jinja2>=3.1 in .venv on first sub-PR
  - For 1E.c.2 socket.getaddrinfo + httpx: stdlib only; no new deps
  - bats v1.10+, jq, yq pinned (cycle-099 sprint-1C runbook)

Quality-gate chain (same as 1A/1B/1C/1E.a/1E.b):
  1. Implement test-first (bats parity test + golden corpus before code)
  2. Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel
  3. Bridgebuilder kaironic INLINE via .claude/skills/bridgebuilder-review/resources/entry.sh
     (typical 2-iter convergence for code PRs)
  4. Admin-squash after plateau
  5. RESUMPTION.md update + memory write

Sprint-1E.b remediation lessons worth carrying forward:
  - `set -e` + `grep -rEln` against a missing dir → exit 2 fatal under bash -e
    Pre-filter scope arrays via `for d in ...; do [[ -d $d ]] && scope+=$d; done`
    BEFORE expanding into argv. Local interactive-shell smoke MISSES this; the
    workflow's default `bash -e` shell is the canonical CI test environment.
  - Stream-contract: rejection JSON to STDERR (per SDD §6.2), acceptance JSON
    to STDOUT. Bats `_validate_both` that does `2>&1` merge HIDES regressions.
    Add explicit C6/C7/C8 tests that capture only one stream at a time.
  - `python -I` (isolated mode) on subprocess invocations: ignores PYTHONPATH
    + user-site to defend against env-var-injected interpreter modules.
  - `realpath -e` + tree-confinement check before sourcing/exec'ing sibling
    scripts: prevents BASH_SOURCE symlink-swap attacks.
  - argv smuggling defense: bash wrappers MUST insert `--` before user-
    supplied URL/path values so argparse can't reinterpret them as flags.
    Pattern: `flags=("${@:1:$last_idx}"); url="${!#}"; "$py" "$tool" "${flags[@]}" -- "$url"`
  - Subagent verdict-counting at iter-2: persistent false-alarm = plateau
    signal. Sprint-1E.b iter-1+iter-2 BB both flagged the same imaginary
    "import urllib.parse" regex miss (verified by manual grep). Document
    the false alarm in commit and admin-squash.
  - Production-yaml smoke gate caught schema-vs-reality drift in 1E.a;
    matches the same pattern in 1E.b (real provider URLs in fixture).

Refs: SDD §1.9.1 (endpoint validator) + §6.5 (8-step canonicalization);
Flatline SDD pass #2 SKP-006 CRITICAL 870 + pass #3 IMP-002 HIGH_CONSENSUS 880.
```

---

## Open backlog at session-end (2026-05-05)

### Sprint 1 remaining

- **T1.10 unfinished bats**: bridgebuilder-dist-drift.bats + perf-bench.bats. Sprint-1A landed gen-bb-registry-codegen.bats; sprint-1B landed legacy-adapter-still-works.bats. Two more deliverables per SDD §7.2 still owed. **Defer to sprint-1D OR sprint-1E.c bundle** (small, can ride alongside).

### Sprint 1 deferred to follow-ups

- **macos arm64 hardcoding** (BB iter-1 F3 + iter-2 F5 from sprint-1C): pin to `macos-14` instead of `macos-latest` for deterministic arch.
- **yq upstream checksums URL** (BB iter-2 F2 from sprint-1C): cross-reference https://github.com/mikefarah/yq/releases/download/v4.52.4/checksums in the workflow comment for audit ergonomics.
- **Composite action for yq install** (BB iter-2 F8 from sprint-1C): three workflows currently duplicate the install step. Repository-local action could DRY this up.
- **`local alias=` shadows builtin** (sprint-1B review H1): cosmetic; rename to `_alias`.
- **Workflow_dispatch trigger for drift gate** (sprint-1C review process): catches "drift introduced before the gate landed" race.
- **Sprint-1E.a leftovers** (BB iter-2, all LOW or recycled, deferred):
  - F4: T8.2/T8.3 caller-contract docs discoverability — log-redactor module docstring already documents the URL-only scope; consider README/operator-doc snippet
  - F5: M13.3 umask defense-in-depth — Python `os.O_CREAT, mode=0o600` ALREADY enforces; the test pins it via the bash-side `stat`. Could add a parallel test that explicitly inspects Python's `os.stat()` result.
  - F6: pip-install-without-hashes — matches existing repo convention (jcs-conformance.yml, bedrock-contract-smoke.yml); deferred as repo-wide hardening cycle
  - F7: T1.2 mixed `_redact_both` + `_assert_parity` — uniformly migrate remaining sites to `_assert_redacts_to`
  - F8: smoke-test partial-write defense — add a `[ -s /tmp/migrated.yaml ]` size check after the migrate call
  - F12: M11.1 brittleness — replace `grep -E '^[a-z_]+:'` with a parser-based first-key check via ruamel.yaml

### Sprint 2+ scope (downstream of Sprint 1 completion)

- Sprint 2 — Config extension (`model_aliases_extra`) + per-skill granularity (`skill_models`) + runtime overlay (`.run/merged-model-aliases.sh`)
- Sprint 3 — Personas + docs migration + DD-1 Option B model-permissions codegen + bridgebuilder dist regen
- Sprint 4 (gated at T4.4) — Legacy adapter sunset

### Beads

UNHEALTHY/MIGRATION_NEEDED ([#661](https://github.com/0xHoneyJar/loa/issues/661)) unchanged across all 7 PRs (#721/#722/#723/#724/#728/#729/#730). `--no-verify` policy active per cycle-099 sprint plan §`--no-verify` Safety Policy. Each PR commit message carries the `[NO-VERIFY-RATIONALE: ...]` audit-trail tag.

---

## Patterns established this session (worth remembering)

1. **Subagent dual-review (general-purpose + paranoid cypherpunk) in parallel** caught real bugs across all four sub-sprints. Paranoid cypherpunk specifically caught: `__proto__` prototype-shadowing (1A), `LOA_MODEL_RESOLVER_GENERATED_MAPS_OVERRIDE` ungated arbitrary-bash-source (1B), unverified macOS yq SHA256 (1C), `additionalProperties` schema gap + symlink-clobber on output write (1E.a). General-purpose specifically caught: silent regression of `claude-sonnet-4-5-20250929` (1A), brittle source-line regex pin (1B), advisory-only version-comparison-script (1C), input-dict mutation in "pure" function + tier_groups absent/partial-fill gaps + tautological assertion (1E.a).

2. **Bridgebuilder kaironic 2-iter convergence** held empirically. Each PR plateaued in 2 iterations including 1E.a.

3. **The vacuous-green-via-fixture-syntax-error pattern** (BB iter-1 F1 on PR #723): a security-test fixture with a bash syntax error means the negative assertion passes for the wrong reason (file fails to parse before the attack code runs). **Fix template**: add a positive-control sentinel that proves the payload WOULD fire if the gate were absent.

4. **The drift-gate-cannot-catch-its-own-introducing-PR race** (sprint-1A → 1B → 1C surfacing): SDD R-5 in the wild. Sprint-1C remediated retroactively via gen-adapter-maps regen. Sprint-1D follow-up should add `workflow_dispatch` post-merge gate.

5. **Inline implementation pattern with subagent quality gates** continues to outperform `/run` autopilot for sliced sub-sprints. Sprint 1A/1B/1C/1E.a all used the inline-then-subagent-review-then-BB-kaironic-then-admin-squash flow.

6. **Conversation-budget discipline**: future sessions should slice sprints further before starting. 1E.a was sliced cleanly from 1E.b at session start, so the remaining endpoint validator can ship as a small follow-up rather than getting bundled in mid-session.

7. **Production-yaml smoke-test in CI catches schema-vs-reality drift** (sprint-1E.a): the strict v2 schema initially rejected legitimate cycle-095 production fields (compliance_profile null, api_format dict for Bedrock per-capability mapping). Without the dedicated CI step that runs the migrator against `.claude/defaults/model-config.yaml`, this would have surfaced only when an operator hit it in the field. **Fix template**: every schema-tightening PR must include a smoke-test step that runs against the most-permissive real-world fixture available.

8. **Heredoc shell-injection-into-Python-source surface** (sprint-1E.a BB iter-1 F2): bats tests using `"$PYTHON" - <<EOF` (unquoted) interpolate every `$VAR` into the embedded Python source. If any path contains a quote, `$`, or `\`, the embedded code can break or be injected. **Fix template**: helper function `_python_assert` that exports paths via env vars + uses quoted heredoc `<<'EOF'`, with the embedded Python reading via `os.environ["PATH_VAR"]`. See `tests/integration/migrate-model-config.bats` for the canonical pattern.

9. **`set -e` × `grep -2-on-missing-dir` interaction** (sprint-1E.b CI fix): GitHub Actions default shell is `bash -e {0}`; `grep -rEln '...' missing-dir/` exits 2 (path-not-found), and `set -e` aborts the workflow step. Local interactive shells without `set -e` swallow the same condition, so the bug surfaces only in CI. **Fix template**: pre-filter scope arrays via `for d in ...; do [[ -d "$d" ]] && scope+=("$d"); done` before expanding into `grep` argv. Robust to repo-level path changes; future scope additions don't require workflow edits to remove non-existent paths.

10. **Stream-contract testing at the CLI surface** (sprint-1E.b gp M1 + cypherpunk LOW 3): bats helpers that capture `2>&1` (merged stdout + stderr) cannot detect regressions in stream-placement contracts. Per SDD §6.2 errors emit on stderr; my JSON-mode rejection-tests would have passed even if the validator emitted JSON-rejection on stdout. **Fix template**: separate test cases that capture only one stream at a time and assert the OTHER is empty: `out=$(... 2>"$WORK_DIR/err"); err=$(cat "$WORK_DIR/err")`. Add C6/C7/C8-style tests at every CLI's stream boundary.

11. **Persistent false-alarm = kaironic plateau** (sprint-1E.b BB iter-1+iter-2 F1): the same finding flagged by BB across two iterations, manually verified to be incorrect, is a strong plateau signal. Don't burn a third iteration trying to "fix" something the regex already handles. Document the false alarm in the commit message + admin-squash.

12. **TS-vs-Python parser-confusion is the central risk of multi-runtime validators** (sprint-1E.c.1 cypherpunk CRITICAL × 2): the URL constructor in JS silently percent-decodes `%2E` to `.`, normalizes Unicode dot equivalents (U+FF0E, U+3002, U+FF61), and folds backslashes — all behaviors that diverge from Python's `urlsplit`. **Fix template**: a unified pre-parse gate (`_validate_authority`) that rejects parser-confusion vectors in BOTH runtimes, applied to the RAW URL string before either parser sees it. Sprint-1E.c.1 ships `_AUTHORITY_FORBIDDEN_CHARS` containing `%`, `\`, three Unicode dots, soft-hyphen, and zero-width / bidi controls. Plus `_has_obfuscated_ipv4_octet` for leading-zero / 0x-prefix octets. Both reviewers (cypherpunk CRITICAL × 2 + general-purpose HIGH × 4) caught this pre-merge — without dual-review, sprint-1E.c.1 would have shipped a working SSRF allowlist bypass.

13. **Codegen surrogate trap for non-BMP codepoints** (sprint-1E.c.1 cypherpunk MEDIUM): naive Jinja2 emission `\u{{ '%04x' | format(cp) }}` works for BMP (≤ U+FFFF) but silently corrupts for non-BMP (e.g., U+E0001 → emits `11`, which JS parses as U+E000 followed by literal "11"). **Fix template**: a `_ts_escape_cp` filter that uses `\u{XXXXX}` brace form for codepoints > 0xFFFF. Latent bug today (Python's `_PATH_CONTROL_CHARS` are all in BMP), but a future addition would silently break the TS port without the filter.

14. **Drift-gate hash cross-check beats text-diff alone** (sprint-1E.c.1 gp MEDIUM): a codegen `--check` mode that only does `fresh_text != committed_text` byte-diff catches the common "forgot to regenerate" case but misses a tampered-canonical-with-matching-regen scenario. **Fix template**: extract the embedded `Source content hash:` header from the committed file and compare against a fresh hash of the canonical Python source — fail with `[BB-CODEGEN-HASH-DRIFT]` if they don't match. Forces operator review of any canonical edit.
