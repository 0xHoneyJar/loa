# Bug Triage: Aleph gates block Loa — managed-file digest and release-ingestion tests sit in required CI and the mount path; Aleph must be opt-in

## Metadata
- **schema_version**: 1
- **bug_id**: 20260922-13a3d1
- **classification**: regression / integration-boundary defect (third-party component constrains the host framework)
- **severity**: high
- **eligibility_score**: 9
- **eligibility_reasoning**: Observed failure with exact error text on PR #1266 (two CI checks red, one of them a required status check); reproducible offline with `tools/aleph-release-ingest.py verify-installed`; a second observed failure in the framework review of 2026-09-17 ("mounting the latest tag fails its Aleph step"). No disqualifier: not feature work, no schema migration, no data model change. Maintainer directive 2026-09-22: Aleph was not authored by the Loa maintainer and must be opt-in, never a constraint on Loa's own gates or consumers.
- **test_type**: unit
- **risk_level**: medium
- **created**: 2026-09-22T10:07:10Z

## Reproduction
### Steps
1. On `feature/cycle-124-model-generation-floor` (head `5543b413`), Loa's own lint `validate-skill-capabilities.sh` requires a `capabilities:` block in every SKILL.md; Sprint 3 added it to `.claude/skills/loa-aleph/SKILL.md` (commit `12a83a87`, 11 lines).
2. Open PR #1266 → CI runs `.github/workflows/aleph-bundle-integrity.yml` (`Verify install and status (Node 20/22)`) and `bats-tests.yml` (`Shell Tests`, a required status check on `main`).
3. Locally: `python3 tools/aleph-release-ingest.py verify-installed --root . --pin .loa-aleph.lock.json`; `npx --no-install bats tests/unit/aleph-release-ingestion.bats`.

### Expected Behavior
Loa's CI and mount/update path are green whenever Loa's own rules are satisfied. A third-party, vendored component (Aleph) is verified only where it has been explicitly enabled, and never turns a Loa PR red or blocks a consumer mount.

### Actual Behavior
- `Verify install and status`: `FAIL managed installation file digest mismatch: .claude/skills/loa-aleph/SKILL.md` (both Node matrices).
- `Shell Tests` (required): `not ok 265/273/274/275/276 cycle-115 release ingestion: …` — the same digest, checked by `tests/unit/aleph-release-ingestion.bats`. Both checks were green at the branch base (PR #1252).
- Locally the ingestion suite also fails on `installed Aleph release pin mode must be 0644` because `.loa-aleph.lock.json` is mode 664 on this host — a host artefact that masked the CI-relevant cause during Sprint 3 ("pre-existing" was misattributed).
- `mount-submodule.sh` / `update-loa.sh` run `refresh_aleph_install` whenever a managed Aleph path or bundle exists (`aleph_refresh_is_applicable`), and `check-loa.sh` runs `check_aleph_integrity` unconditionally; a consumer inherits Aleph verification by mounting Loa.

### Environment
Linux 6.16, bats-core via npx, Node 22, Python 3.13; CI ubuntu-latest Node 20/22. Required checks on `main`: Template Protection, Validate Framework Files, Lint Markdown, Lint YAML, Shell Tests.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/mount-submodule.sh` | 1366-1376, 1408-1411 | high | `aleph_refresh_is_applicable` decides by presence of bundle/managed paths, never by an operator choice; `refresh_copy_set` calls `refresh_aleph_install` on every mount/refresh |
| `.claude/scripts/update-loa.sh` | 222-241 | high | `verify_copyset_gate` runs Aleph verification and aborts the update on failure; guarded only by the same presence predicate |
| `.claude/scripts/check-loa.sh` | 157-235, 550 | high | `check_aleph_integrity` runs unconditionally in the health check |
| `tests/unit/aleph-release-ingestion.bats` | setup 8-17 | high | 20 tests that verify Aleph's pin/digest run in Loa's required `Shell Tests` job |
| `tests/unit/aleph-framework-integration.bats`, `tests/unit/aleph-submodule-real-installer.bats` | setup | high | 41 more Aleph tests in the required job |
| `.github/workflows/aleph-bundle-integrity.yml` | 1-70 | high | runs on every PR touching Aleph paths, digest-checks the managed skill file |
| `.github/workflows/aleph-release-sync.yml` | 1-40 | medium | scheduled upstream sync proposes Aleph bumps on `main` regardless of opt-in |
| `.loa.config.yaml.example` | — | high | no `aleph` section exists; nothing lets an operator opt in or out |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/aleph-release-ingestion.bats` | pin/digest/candidate verification (fails today for the reason above) |
| `tests/unit/aleph-framework-integration.bats` | mount/update refresh of the managed Aleph tree (mock node) |
| `tests/unit/aleph-submodule-real-installer.bats` | real installer against the vendored bundle (Node 22) |
| `tests/unit/skill-capabilities.bats` | Loa's capabilities lint — the rule that required the SKILL.md edit; must keep passing |

### Test Target
`tests/unit/aleph-opt-in.bats` (new): with Aleph not opted in (no `aleph.enabled: true`, no `LOA_ALEPH_ENABLED=1`) the mount predicate refuses, `check-loa.sh` skips the Aleph check, the three Aleph suites skip themselves, and both Aleph workflows carry a config gate; with the opt-in set, the predicate and the suites behave as before. Loa's capabilities lint stays green on `loa-aleph/SKILL.md`.

### Constraints
- Do not revert the `capabilities:` block: Loa's lint is the authority in this repo.
- Do not edit Aleph-managed files (`.claude/aleph/**`, `.claude/commands/loa-aleph.md`, `.claude/skills/loa-aleph/**`, `.loa-aleph.lock.json`); leave the vendored tree in place, inert.
- One switch, default off: `.loa.config.yaml` `aleph.enabled` (plus the test/CI override `LOA_ALEPH_ENABLED=1`); no other knob.
- Keep the existing Aleph behaviour byte-identical when opted in (the predicate is additive: opt-in AND the existing presence logic).
- Fail closed toward "disabled": a missing `yq`, missing config or unparseable value means not enabled.

## Fix Strategy
Introduce an explicit opt-in predicate and put it in front of every place where Aleph reaches into Loa: the mount/update refresh (`aleph_refresh_is_applicable`), the health check (`check_aleph_integrity`), the three Aleph bats suites (skip when not opted in, so the required `Shell Tests` job cannot go red on Aleph bytes), and the two Aleph workflows (a `gate` job that reads the same config key; the verify/prepare jobs run only when enabled). Document the key in `.loa.config.yaml.example` and set it explicitly to `false` in this repository's `.loa.config.yaml`. Tests first.

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/lib/aleph-opt-in.sh` | create | `aleph_opt_in_enabled [repo_root]` → 0 iff `LOA_ALEPH_ENABLED=1` or `.aleph.enabled == true` in `<repo_root>/.loa.config.yaml` | stdlib + optional `yq`; missing yq/config → 1 |
| `.claude/scripts/mount-submodule.sh` | edit | `aleph_refresh_is_applicable`: return 1 unless `aleph_opt_in_enabled "$repo_root"` | source the lib next to the script; existing logic unchanged after the gate |
| `.claude/scripts/check-loa.sh` | edit | wrap the `check_aleph_integrity` call: log "skipped (opt-in)" unless enabled | same predicate |
| `tests/unit/aleph-{release-ingestion,framework-integration,submodule-real-installer}.bats` | edit | `setup()`: `skip` unless enabled | one line each; suites unchanged otherwise |
| `.github/workflows/aleph-bundle-integrity.yml`, `aleph-release-sync.yml` | edit | add `gate` job reading `.aleph.enabled`; downstream jobs `needs: gate` + `if:` | no new secrets or permissions |
| `.loa.config.yaml.example`, `.loa.config.yaml` | edit | `aleph: { enabled: false }` with a comment | default off |
| `tests/unit/aleph-opt-in.bats` | create | the failing tests listed under Test Target | red before, green after |
