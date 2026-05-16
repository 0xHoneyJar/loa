# Cycle Archive Runbook

Operator-facing reference for `.claude/scripts/archive-cycle.sh` and the BB
`dist/` build hygiene gate that lands alongside it in cycle-104 Sprint 1.

> **Source**: cycle-104 multi-model-stabilization Sprint 1 — closes #848
> (`archive-cycle.sh` per-cycle-subdir + retention semantics) and the
> cycle-103 BB dist near-miss. See
> `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint.md`.

---

## TL;DR

| Task | Command |
|------|---------|
| Preview cycle archive | `.claude/scripts/archive-cycle.sh --cycle 104 --dry-run` |
| Archive a cycle | `.claude/scripts/archive-cycle.sh --cycle 104` |
| Keep newest N archives only | `.claude/scripts/archive-cycle.sh --cycle 104 --retention 5` |
| Keep all archives | `.claude/scripts/archive-cycle.sh --cycle 104 --retention 0` |
| Verify BB dist is fresh | `tools/check-bb-dist-fresh.sh` |
| Rebuild BB and refresh manifest | `cd .claude/skills/bridgebuilder-review && npm run build` |

---

## What changed in cycle-104

### `archive-cycle.sh` per-cycle-subdir resolution

Cycles ≤097 stored `prd.md` / `sdd.md` / `sprint.md` at the grimoire root
(`grimoires/loa/`). Cycles ≥098 moved them under per-cycle subdirs
(`grimoires/loa/cycles/cycle-NNN-slug/`). The archive script was still
copying from the root, producing **empty archives** for every cycle from
098 onward (#848 reproduction).

`archive-cycle.sh` now resolves the cycle's artifact source via ledger
lookup with multi-step fallback:

1. `ledger.cycles[].cycle_folder` (canonical for cycles ≥102)
2. `dirname(ledger.cycles[].prd)` (covers older entries where `cycle_folder`
   is unset but `prd` path is)
3. `${GRIMOIRE_DIR}/cycles/<cycle_id>/` (constructed path; covers
   cycles where the dir exists on disk but the ledger entry is sparse)
4. `${GRIMOIRE_DIR}` root (legacy fallback for cycles ≤097)

The resolved source is shown explicitly in `--dry-run` output as
`[DRY-RUN] Artifact source: <path>` so operators can verify the right
directory is being archived.

### `--retention N` semantics

Cycle-104 fixes the retention bug from #848: previously, `load_config`
ran AFTER `parse_args` and unconditionally overwrote the `--retention`
flag with the yaml default (5), so `--retention 5` and `--retention 50`
produced the same deletion set.

After cycle-104:

- `--retention N` → keep the **newest N** archives by mtime; delete the rest
- `--retention 0` → keep **all** archives; skip cleanup entirely
- yaml `compound_learning.archive.retention_cycles` → used only when
  `--retention` is not supplied on the CLI

The "newest N" decision is by filesystem mtime (`find -printf '%T@'`),
not alphabetic sort, so renamed/recently-touched archives are preserved
correctly.

### Modern per-cycle subdir copies

For cycles ≥098, the archive now includes:

- `prd.md` / `sdd.md` / `sprint.md` (from the per-cycle subdir)
- `ledger.json` (always from grimoire root)
- `handoffs/` (modern handoff documents)
- `a2a/` (per-cycle agent-to-agent artifacts)
- `flatline/` (per-cycle Flatline review outputs, when present)

For cycles ≤097, the legacy `a2a/compound/` directory from the grimoire
root is preserved (backward compat).

---

## Common operations

### Archiving a freshly-closed cycle

```bash
# 1. Verify the ledger has the cycle marked status: "archived"
jq '.cycles[] | select(.id | startswith("cycle-104")) | .status' grimoires/loa/ledger.json

# 2. Preview the archive (no writes)
.claude/scripts/archive-cycle.sh --cycle 104 --dry-run

# 3. Run the archive
.claude/scripts/archive-cycle.sh --cycle 104

# 4. Verify the archive landed
ls -la grimoires/loa/archive/cycle-104-multi-model-stabilization/
```

### Recovering from a failed archive

If `archive-cycle.sh` fails for any reason, the documented escape hatch is
to flip the ledger entry directly:

```bash
# Mark the cycle archived and clear active_cycle
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --arg ts "$ts" '
  (.cycles[] | select(.id == "cycle-NNN-name") | .status) = "archived"
  | (.cycles[] | select(.id == "cycle-NNN-name") | .archived) = $ts
  | .active_cycle = null
' grimoires/loa/ledger.json > /tmp/ledger.new && mv /tmp/ledger.new grimoires/loa/ledger.json

# Verify
jq '.active_cycle, (.cycles[-1] | {id, status, archived})' grimoires/loa/ledger.json
```

This is what cycle-103 closure used (`f6d9a763`) before the cycle-104 fix
landed. It remains the documented fallback for any future archive-script
breakage — the ledger is the source of truth; the archive is a snapshot.

### Inspecting an existing archive

```bash
ls -la grimoires/loa/archive/cycle-103-provider-unification/
cat grimoires/loa/archive/cycle-103-provider-unification/.archive-meta.json
```

---

## BB `dist/` build hygiene gate

### Why

Cycle-103 nearly shipped BB TypeScript changes without the corresponding
`dist/` regenerate. Because BB is dispatched via the compiled `dist/main.js`,
source-only changes would have looked correct in the diff but not actually
run in production. The drift gate makes this class of mistake CI-fatal.

### How it works

`tools/check-bb-dist-fresh.sh` enumerates every source `.ts` / `.tsx` file
under `.claude/skills/bridgebuilder-review/resources/` (excluding tests,
state dirs, and `node_modules/`), hashes each file with SHA-256, sorts the
list deterministically by path, and produces a single combined source hash.

That combined hash is written into `dist/.build-manifest.json` at build
time (`npm run build` calls `tools/check-bb-dist-fresh.sh --write-manifest`
as its final step). The CI gate later recomputes the hash and compares to
the committed manifest. If they differ, the build is stale.

The hash is over **source files only**, not `dist/` output. This is
deliberate: it means legitimate hand-edits to `dist/` (e.g., a quick
fix-and-test cycle, or a sourcemap fixup) do not trigger false positives.
The tradeoff is documented in `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md`
§1.4.4 R6.

### Operator-side fast feedback

For local development, install the optional pre-commit hook:

```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash
bash "$(git rev-parse --show-toplevel)/.claude/hooks/pre-commit/bb-dist-check.sh" || true
```

The hook only fires when staged paths touch
`.claude/skills/bridgebuilder-review/`, soft-fails with stderr instructions
to run `npm run build`, and exits 0 in all cases. CI is the hard gate.

### When the gate fires

```
[FAIL] BB dist is stale — source files have changed since last build
       committed source_hash: <hex>
       current   source_hash: <hex>
       Fix:
         cd .claude/skills/bridgebuilder-review
         npm run build
         git add dist/
```

Run the fix command, re-stage, push. The CI gate will pass on the next run.

---

## Related

- Issue: [#848](https://github.com/0xHoneyJar/loa/issues/848) — `archive-cycle.sh` per-cycle-subdir bug + retention bug
- Cycle: cycle-104 Sprint 1 (this work)
- Predecessor near-miss: cycle-103 closure (BB dist source-only shipping risk surfaced during operator review)
- Workaround precedent: cycle-103 closure commit `f6d9a763` (manual ledger flip when script was broken)
- SDD: `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md` §1.4.3, §1.4.4, §5.4, §7.3
