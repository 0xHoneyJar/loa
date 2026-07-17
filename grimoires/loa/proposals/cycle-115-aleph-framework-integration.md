# Cycle 115 Proposal and Implementation Plan: Aleph Framework Integration

> **Cycle:** `cycle-115-aleph-framework-integration`
> **Status:** Authorized for this framework-integration slice
> **Authorization:** Operator confirmation on 2026-07-17
> **Branch:** `agent/aleph-bundle-ingestion`

## 0. System Zone authorization

Loa's `.claude/` tree is the framework System Zone and is not writable merely
because a feature would benefit from a framework change. For this cycle, the
operator explicitly authorizes writes to the following exact System Zone
surfaces and no others:

| Authorized path | Purpose |
|---|---|
| `.claude/scripts/lib/symlink-manifest.sh` | Exclude the receipt-managed `loa-aleph` command and skill from dynamic submodule symlinks |
| `.claude/scripts/mount-submodule.sh` | Install or verify Aleph from the pinned submodule bundle during mount and reconcile |
| `.claude/scripts/update-loa.sh` | Stage the selected gitlink trust anchor, then refresh Aleph fail-loud after submodule reconciliation |
| `.claude/scripts/check-loa.sh` | Delegate Aleph managed-tree integrity to its compiled receipt verifier |

The following non-System-Zone writes are also authorized for this slice:

| Authorized path | Purpose |
|---|---|
| `grimoires/loa/proposals/cycle-115-aleph-framework-integration.md` | This tracked proposal, authorization record, and implementation plan |
| `.gitignore` | Keep local Aleph runs and host-capability receipts out of version control |
| `.github/workflows/ci.yml` | Add only the two Aleph privacy paths to the existing template guard |
| `tests/unit/aleph-framework-integration.bats` | Focused topology, integrity, collision, tamper, and idempotency tests |

Explicitly unauthorized in this slice:

- `.claude/settings.json` and `.claude/checksums.json`;
- `.claude/aleph/**`, `.claude/commands/loa-aleph.md`, and
  `.claude/skills/loa-aleph/**` until a clean immutable upstream bundle exists;
- release, synchronization, or bundle-integrity workflows;
- any network fetch, artifact ingestion, or release within this preparatory
  slice. The operator's 2026-07-17 confirmation separately authorizes committing,
  pushing, and publishing this reviewed slice through a pull request;
- any claim that the Loa adapter is validated or sanctioned.

## 1. Problem

Loa's submodule mount normally exposes framework commands and skills as
symlinks. The Aleph adapter instead treats its command, skill, launcher,
runtime, and install receipt as one exact managed tree and rejects symlinks in
those paths. A normal dynamic symlink would therefore make `/loa-aleph` fail its
own integrity preflight.

The framework needs a narrow integration seam before the immutable bundle can
be ingested:

1. reserve the command and skill names from dynamic symlink discovery;
2. on mount, reconcile, or submodule update, invoke the compiled installer
   inside the bundle pinned by the `.loa` submodule;
3. verify an existing installation before permitting an update;
4. fail closed on collisions, symlinks, missing receipts, or tampered bytes;
5. make clean consumers on Loa versions that predate the bundle a no-op while
   rejecting stale managed surfaces after downgrade;
6. keep sensitive run evidence out of the repository template.

## 2. Ownership and invariants

The future upstream installation owns exactly these consumer paths:

- `.claude/aleph/**`;
- `.claude/commands/loa-aleph.md`;
- `.claude/skills/loa-aleph/**`.

This cycle does not create them. When a later Loa version contains
`.loa/.claude/aleph/runtime/bundle`, the mount hook invokes the bundle-pinned
compiled installer at `runtime-js/adapters/loa/src/installer.js`. Before
execution, Loa requires the entire source bundle to be a real, symlink-free,
tracked tree with no content, mode, or extra-file drift from the authorized
submodule commit. It then checks the real compiled installer's SHA-256 against
the pinned bundle lock and invokes Node with preload and module-search
environment overrides cleared. The installer remains responsible for full
bundle verification, transactional publication, obsolete-managed-file cleanup,
and the final exact install receipt.

The integration obeys these invariants:

- only a parent-authorized pinned Git tree with no Aleph bundle inventory, plus
  absence of all Aleph managed destinations, is treated as an old-version no-op;
- a bundle tracked by the pinned tree but deleted from the working tree fails
  closed instead of impersonating a pre-Aleph version;
- a pre-Aleph/downgraded source with any residual receipt, runtime, command, or
  skill fails closed rather than leaving a stale runnable surface;
- presence of the source bundle requires Node.js 20 or newer;
- the source bundle must match the parent-authorized submodule commit exactly,
  including imported installer dependencies, before any Node process starts;
- `/update-loa` stages its selected submodule commit as the superproject gitlink
  before invoking the hook; `--no-commit` leaves that explicit pin staged;
- the already-running pre-cycle-115 updater reaches Aleph through the newly
  sourced `refresh_copy_set` compatibility surface on its first update;
- a managed destination without a receipt is a collision, not an upgrade;
- an existing receipt must pass `verify-install` before any update runs;
- a failed verifier never falls through to repair or replacement;
- post-install verification is mandatory;
- the installed Aleph root, command, skill, and `SKILL.md` are real paths, not
  symlinks;
- repeated reconciliation with identical bytes is idempotent;
- runs under `grimoires/loa/aleph/runs/` are never installer targets.

## 3. Implementation plan

### T1: Reserve receipt-managed names

Update the authoritative symlink manifest so dynamic discovery skips exactly
the `loa-aleph` skill directory and `loa-aleph.md` command. No other command or
skill topology changes.

### T2: Add the mount/reconcile installation hook

Add one function used by initial mount, `--reconcile`, `--check-symlinks`, and
the submodule path of `/update-loa`. Its modes are:

- **old-version-clean:** source bundle and all managed destinations absent,
  report and return success;
- **downgrade-stale:** source bundle absent but any managed destination remains,
  fail without executing or deleting it;
- **check:** source bundle present, verify the installed receipt and real-path
  topology without writing;
- **reconcile:** authenticate the pinned compiled installer, verify any prior
  installation, run the offline transactional install, then verify again.

The generated consumer `.gitignore` receives the three installer-owned path
families plus `.claude/aleph-install.transaction*` and
`.claude/aleph-install.writer.lock*`, so real managed files and interrupted
recovery state do not pollute the consumer's working tree.

### T3: Delegate integrity and protect private evidence

`check-loa.sh` calls the compiled `verify-install` implementation when an Aleph
bundle exists. The legacy global checksum inventory is not regenerated or
extended in this slice. Static ignore and template-guard entries cover:

- `grimoires/loa/aleph/runs/`;
- `grimoires/loa/aleph/host-capabilities.json`.

### T4: Focused tests

Add Bats coverage proving:

- command and skill symlink exclusion;
- clean old-version no-op and stale downgrade rejection;
- fail-loud `/update-loa` helper loading with bundle-less legacy tolerance;
- first install produces real paths;
- identical reconcile is idempotent;
- check mode delegates to `verify-install` without installing;
- unmanaged collision and failed prior verification stop before install;
- a dirty imported dependency, bundle-lock/installer co-tamper, internal digest
  mismatch, mode drift, ignored extra, wrong gitlink, preload override, or
  intermediate source symlink stops before execution;
- a missing installed bundle or symlinked source bundle fails closed in
  `check-loa`;
- generated consumer ignore and repository privacy guards are present;
- `check-loa.sh` reports verifier success and failure correctly.

## 4. Acceptance and non-claims

This slice is complete when its focused Bats tests pass, Bash syntax checks
pass, `git diff --check` is clean, and the pre-existing
`.claude/settings.json` digest is unchanged. It is framework preparation only:
no Aleph bundle has been ingested, no real host-capability receipt exists, and
no adapter validation or sanction is claimed.
