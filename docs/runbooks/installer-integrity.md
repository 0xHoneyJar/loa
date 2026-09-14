# Installer download and relocation checks

The Linux dependency installer downloads yq v4.40.5 without privileges, checks
its SHA-256 against the architecture-specific pin in `mount-loa.sh`, then uses
`sudo install` to place the verified file. Failed downloads or mismatched bytes
never reach installation. The pins were checked against both the upstream
release's `checksums` asset and the downloaded binaries:

| Asset | SHA-256 |
|---|---|
| `yq_linux_amd64` | `0d6aaf1cf44a8d18fbc7ed0ef14f735a8df8d2e314c4cc0f0242d35c0a440c95` |
| `yq_linux_arm64` | `9431f0fa39a0af03a152d7fe19a86e42e9ff28d503ed4a70598f9261ec944a97` |

Rotate the version and both pins together. The macOS package-manager path is
unchanged. Every auxiliary script in the pipe installer is required; a failed
download stops before the downloaded installer is executed.

Memory Stack relocation requires Python 3 for content verification. It copies
`.loa/` into a private directory on the destination filesystem, compares file
hashes, modes (including the root), directories and symlink targets, and renames the verified copy
to `.loa-state/` before removing the logical source path. Existing targets are
refused and preserved. Copy, verification or publication failure preserves the
source. A source symlink is removed only after success; its external target
is not deleted. Publication uses an exclusive native rename (`renameat2` on
Linux, `renamex_np` on macOS), so a target appearing during publication is also
preserved. Platforms without that operation stop with the source intact.

Stop Memory Stack writers before migration. The migration lock serializes
installer invocations; it does not freeze unrelated writers with open files.
The destination appears atomically, but publication and source removal are
separate operations. If interrupted after publication, inspect both locations
before retrying. Without `flock`, an atomic lock directory under Git metadata
provides exclusion; a stale directory requires operator inspection.

Offline regression coverage:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_installer_epic_remaining.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/security/test_installer_epic_proofs.py
bats tests/unit/installer-safety.bats tests/unit/mount-loa-pipe-download-complete.bats
```

The cross-filesystem test uses disposable `/tmp` and `/dev/shm` fixtures and
skips explicitly when a second writable filesystem is unavailable. No test
performs a network download or privileged installation.
