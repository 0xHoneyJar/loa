# Cycle 115 Proposal: Aleph Immutable Release Ingestion

> **Cycle:** `cycle-115-aleph-release-ingestion`
> **Status:** Authorized for implementation and publication
> **Authorization:** Operator confirmation on 2026-07-17
> **Branch:** `agent/aleph-bundle-ingestion`
> **Upstream:** `0xHoneyJar/loa-aleph`
> **Initial release:** `aleph-for-loa-sha256-dbd613c9564a5a96540a1bf5811cf1b3105a279ae27d4eaea481159a76727c29`

## 0. Exact authorization

The operator authorizes this second Cycle 115 slice after publication of the
immutable upstream `aleph-for-loa` release. It may write only these new or
generated surfaces in addition to the separately authorized framework seam:

| Authorized path | Ownership and purpose |
|---|---|
| `grimoires/loa/proposals/cycle-115-aleph-release-ingestion.md` | This authorization and trust-boundary record |
| `tools/aleph-release-ingest.py` | Loa-owned, dependency-free, network-free verifier and candidate writer |
| `.loa-aleph.lock.json` | Canonical consumer pin for one immutable upstream release |
| `.github/workflows/aleph-release-sync.yml` | Read-only preparation plus sealed, exact-path pull-request proposal |
| `.github/workflows/aleph-bundle-integrity.yml` | Push and pull-request integrity verification and runtime smoke tests |
| `tests/unit/aleph-release-ingestion.bats` | Adversarial release, archive, pin, candidate, and workflow tests |
| `.claude/aleph/runtime/bundle/**` | Verifier-authenticated upstream bundle bytes |
| `.claude/aleph/bin/loa-aleph.mjs` | Installer-generated launcher |
| `.claude/aleph/install.lock.json` | Installer-generated exact receipt |
| `.claude/commands/loa-aleph.md` | Installer-generated command surface |
| `.claude/skills/loa-aleph/SKILL.md` | Installer-generated skill surface |

`.claude/settings.json` and `.claude/checksums.json` remain explicitly
unauthorized. The sync workflow must reject any candidate containing either
path and must never auto-merge its pull request.

## 1. Trust anchor and pin

The initial upstream release is a published prerelease with `immutable=true`.
Its tag resolves to commit `c86f0a02aa01d2b8304b62ff8406dcc31ad0af83`.
The consumer pin contains no timestamp or mutable download URL. It binds the
exact repository, tag, commit, three release asset names and raw SHA-256
digests, release version and maturity, bundle aggregates, adapter identity and
lifecycle, provenance, and dependency-closure commit.

The adapter lifecycle is exactly `implemented`. Empty upstream validation and
sanction evidence remain empty downstream; release ingestion is not evidence
of validation or sanction.

## 2. Verification and execution boundary

Before any upstream JavaScript executes, the sync preparation job must:

1. require the exact repository, an immutable published prerelease, a full
   digest tag, exactly three assets, and a tag commit matching the pin;
2. verify the release and each local asset through GitHub release attestations;
3. enforce descendant-only updates from an existing pin;
4. run the Loa-owned verifier offline against canonical metadata and checksum
   bytes and a bounded normalized gzip/ustar archive;
5. reject traversal, links, devices, duplicates, extensions, abnormal metadata,
   size/count bombs, missing/extra files, and every aggregate-digest mismatch;
6. authenticate the compiled installer against the verified bundle lock;
7. only then run that installer in a temporary destination with `NODE_OPTIONS`
   and `NODE_PATH` removed; and
8. seal the resulting allowlisted candidate by path, mode, and SHA-256.

The write-capable job consumes the sealed candidate using trusted Loa code. It
does not execute candidate or upstream code. It revalidates every byte, copies
only the pin and authorized managed paths, compares the staged inventory to the
allowlist, and opens or updates a digest-keyed human-reviewed pull request.

## 3. Workflow permissions and update policy

The sync workflow separates authority by job:

- `prepare` has `contents: read` and performs discovery, download, attestation,
  offline verification, authenticated temporary installation, and sealing;
- `propose` has only `contents: write` and `pull-requests: write`, revalidates
  the sealed candidate, stages exact paths, and publishes a pull request.

No `pull_request_target`, third-party pull-request action, mutable action tag,
automatic merge, or direct main-branch write is allowed. A repeated digest is a
no-op. A different release is eligible only when its tag commit descends from
the current pin and all verification succeeds.

Deployment requires the repository setting that permits `GITHUB_TOKEN` to
create pull requests. GitHub couples that switch to permission for Actions to
submit approving reviews, so the workflow itself contains no review or merge
operation. Pull-request workflow runs created by this token remain subject to
explicit approval by a write user, preserving the intended human gate.

## 4. Acceptance and non-claims

This slice is complete when the real immutable release is pinned, its installed
tree passes the Loa-owned verifier and upstream receipt verifier, Node 20 and 22
can run `status`, the focused and adjacent test batteries pass, workflow syntax
and static trust-boundary checks pass, and `.claude/settings.json` retains its
pre-existing bytes. `start` may remain blocked without real host-capability
evidence. Nothing in this slice claims adapter validation or sanction.
