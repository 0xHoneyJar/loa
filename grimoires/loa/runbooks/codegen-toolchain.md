# Codegen Toolchain — cycle-099 Sprint 1

**Version:** 1.0 (sprint-1C T1.9)
**Date:** 2026-05-04
**Owner:** @janitooor
**Scope:** the toolchain required to run the cycle-099 model-registry codegen scripts deterministically across linux and macos

## Why this document exists

Cycle-099 consolidates the model registry into a single source of truth at `.claude/defaults/model-config.yaml`. Two codegen scripts derive consumed artifacts from that yaml:

| Script | Output | Sprint |
|---|---|---|
| `.claude/scripts/gen-adapter-maps.sh` | `.claude/scripts/generated-model-maps.sh` | cycle-095 (existing) |
| `.claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts` | `resources/core/truncation.generated.ts` + `resources/config.generated.ts` | cycle-099 sprint-1A |

**Determinism is load-bearing.** PRD G-3 ("zero drift") requires that two operators on different machines, or the same operator on different days, regenerate byte-identical artifacts from an unchanged yaml. The drift gate in `.github/workflows/model-registry-drift.yml` enforces this on every PR — if your local regen produces different bytes than CI's, your PR fails.

This runbook documents the pinned tool versions and verification steps so a fresh checkout (or a CI runner) can install the toolchain reproducibly.

## Pinned tool versions

| Tool | Pinned version | Rationale |
|---|---|---|
| `bash` | ≥ 5.0 | Associative arrays via `declare -A` (used pervasively in `generated-model-maps.sh`); macOS ships bash 3.2 by default — install via `brew install bash` |
| `jq` | ≥ 1.7 | Used by `gen-adapter-maps.sh` for JSON manipulation; 1.7 introduced new function semantics relied on by `flatline-orchestrator.sh` |
| `yq` (mikefarah) | **v4.52.4 exact** (sha256: `0c4d965ea944b64b8fddaf7f27779ee3034e5693263786506ccd1c120f184e8c` for linux_amd64) | YAML→JSON via `yq -o=json`; cycle-099 standardizes on the version used by `bats-tests.yml` to avoid CI lane skew |
| `node` | ≥ 20.0.0 | BB skill `package.json:engines.node`; required for `tsx` and `tsc` |
| `tsx` | ^4.21.0 (pinned in BB skill devDependencies) | Runs `gen-bb-registry.ts` directly without a tsc compile step; supply-chain hardened by being in `package-lock.json` rather than fetched via `npx tsx` on every invocation |
| `typescript` | ^5.9.3 (BB skill devDeps) | Compiles `dist/` from the BB skill's `resources/` |
| `python` | ≥ 3.11 | Required by cheval (`.claude/adapters/loa_cheval/`); cycle-099 sprint-2 will add `model-overlay-hook.py` |

### Future toolchain (sprint-1D forward — do not install yet)

These pins are forward-looking. Operators on the cycle-099 sprint-1C codepath do **not** need to install them; they ship with the consumers in later sprints.

| Tool | Version | When it arrives |
|---|---|---|
| `idna` (Python) | ≥ 3.6 | Sprint-1D centralized endpoint validator (T1.15) — added to install steps when T1.15 lands |
| `bun` | 1.1.x | Optional alternate runtime; the gen-bb-registry.ts script already runs under `npx tsx` (which is what CI + the BB skill `package.json` uses today). Bun migration is a single-line swap when T1.9 toolchain is universally adopted |

## Install on a fresh machine

### macOS (Homebrew)

```bash
brew install bash jq yq node@20 python@3.11

# Verify versions
bash --version | head -1
jq --version
yq --version
node --version
python3 --version
```

Then in the BB skill directory:

```bash
cd .claude/skills/bridgebuilder-review
npm ci
```

### Ubuntu (apt + curl)

```bash
sudo apt-get update
sudo apt-get install -y bash jq python3

# Node 20 via NodeSource
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# yq pinned (mikefarah v4.52.4)
curl -fsSL --retry 3 --max-time 60 \
    -o /tmp/yq \
    https://github.com/mikefarah/yq/releases/download/v4.52.4/yq_linux_amd64
echo "0c4d965ea944b64b8fddaf7f27779ee3034e5693263786506ccd1c120f184e8c  /tmp/yq" \
    | sha256sum -c -
sudo install -m 0755 /tmp/yq /usr/local/bin/yq
rm /tmp/yq

# Verify
bash --version | head -1
jq --version
yq --version
node --version
python3 --version

# BB skill devDeps
cd .claude/skills/bridgebuilder-review
npm ci
```

### CI (GitHub Actions)

The workflows under `.github/workflows/` install the toolchain reproducibly:

- `model-registry-drift.yml` — pinned yq v4.52.4 with SHA256 verification
- `bats-tests.yml` — pinned yq v4.52.4 (same SHA256)

If you bump a pinned version, update **all three** workflows (and this runbook) atomically. The `paths:` filter in `model-registry-drift.yml` re-triggers the gate when this runbook changes, so version-drift across the four files surfaces in CI.

## Verification — run the codegen

Once the toolchain is in place, regenerate from yaml:

```bash
# Bash codegen
bash .claude/scripts/gen-adapter-maps.sh

# TS codegen (from BB skill dir)
cd .claude/skills/bridgebuilder-review
npm run gen-bb-registry
```

If your working tree has any diff in the generated files post-regen, your toolchain is producing different output than the committed artifacts. Investigate:

1. Tool version skew — compare your installed versions against the pinned values above
2. Locale / line-ending — both codegen scripts canonicalize, but a system shimming `sort` to use a locale-specific collation could cause divergence
3. Filesystem case sensitivity — irrelevant for content, but watch for it on macos APFS

## `loa doctor`-style verification

The framework's `loa doctor` (cycle-072) does NOT yet check codegen-toolchain versions. Sprint-1D follow-up may integrate this. For now, sprint-1C ships a standalone helper at `tools/check-codegen-toolchain.sh`:

```bash
bash tools/check-codegen-toolchain.sh
```

Output:

```
Cycle-099 codegen toolchain check
=================================
OK    bash         5.2.37(1)-release (need 5.x)
OK    jq           1.7 (need 1.7+)
OK    yq           4.52.4 (need v4.52.4)
OK    node         v20.x (need v20+)
OK    python       3.11.x (need 3.11+)
=================================
OK: all pinned tools present
```

The script exits 0 if all tools are present, 1 if any are missing. The CI workflow (`.github/workflows/model-registry-drift.yml`) re-runs the drift gate when this script changes, so version-drift across the pin sites (script + runbook + workflows) surfaces in CI.

## Drift between this runbook and the workflows

If you find that this runbook's pinned version differs from `.github/workflows/model-registry-drift.yml` or `.github/workflows/bats-tests.yml`, file a bug — the runbook is the operator-facing source of truth and the workflows must mirror it.

## Refresh cadence

Bump the pinned versions when a security patch lands in any of the listed tools. Coordinate the bump across all four pin sites in a single PR:

1. This runbook
2. `.github/workflows/model-registry-drift.yml`
3. `.github/workflows/bats-tests.yml`
4. `tools/check-codegen-toolchain.sh`

The `model-registry-drift.yml` workflow's `paths:` filter triggers the drift gate when this runbook OR the check script changes, so the gate runs end-to-end and confirms the new toolchain still produces byte-equal output.

## Cycle-099 references

- **PRD G-3**: Zero drift (`grimoires/loa/cycles/cycle-099-model-registry/prd.md`)
- **SDD §1.4.3**: Codegen design (`grimoires/loa/cycles/cycle-099-model-registry/sdd.md`)
- **SDD §2.1**: Tech stack pinning rationale
- **NFR-Op-5**: Codegen reproducibility matrix CI requirement
- **Sprint plan T1.7 + T1.9**: Matrix CI + this runbook (sprint-1C)
