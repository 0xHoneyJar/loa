# Golden outputs — Loa hook behavior proofs

One `<combo>.golden` file per hook × payload combination, captured by
`capture.sh` inside a fresh `bench-env.sh` mirror. Each file contains the
combo name, the hook's exit code, and its full (normalized) stdout + stderr.
`golden_checksums.txt` is `sha256sum` over the set.

## How later optimization passes verify parity

```bash
grimoires/loa/perf/skill-loop-2026-07-05/golden/capture.sh --verify
```

Rebuilds the mirror from the CURRENT working tree (so your edited hooks are
what gets executed), recaptures all 32 combos into a temp dir, and diffs
against the committed goldens. Non-zero exit = behavior drift. This is the
`sha256sum -c` step of the extreme-software-optimization loop; run it after
EVERY hook change, before committing.

To intentionally re-baseline after an approved behavior change:
`capture.sh` (no flag) rewrites the goldens and `golden_checksums.txt`.

## Normalization applied before checksumming

Hook outputs contain three classes of nondeterminism. `capture.sh`
normalizes them (in this order) so checksums are stable across runs,
machines, and dates:

| Raw token                                   | Replaced with |
|---------------------------------------------|---------------|
| the mirror root path (e.g. `/tmp/loa-hookbench-1000`) | `__ROOT__` |
| ISO-8601 UTC timestamps `YYYY-MM-DDTHH:MM:SSZ`        | `__TS__`   |
| bare dates `YYYY-MM-DD`                                | `__DATE__` |

Nothing else is rewritten. Session ids do not appear because every payload
pins `session_id: bench0000-0000-4000-8000-000000000000` and the harness
sets deterministic env (`HOME`/`PROJECT_ROOT` point into the mirror where a
hook consults them).

## Side-effect containment (why the mirror exists)

These hooks write state when they run: `block-destructive-bash.sh` and the
two mutation loggers append `.run/audit.jsonl`; `zone-write-guard.sh` and
`karpathy-surgical-diff-check.sh` append trajectory JSONL under
`grimoires/loa/a2a/trajectory/`; `karpathy` appends
`.run/karpathy-task-state.jsonl`; `post-compact-reminder.sh` DELETES the
compact marker; `settings-cleanup.sh` rewrites `settings.local.json` (>64KB
path); `cleanup-context.sh` archives and deletes the context dir. All of
that happens inside the disposable mirror (`bench-env.sh`), never in the
real repo. Several hooks derive `PROJECT_ROOT` from `BASH_SOURCE`, which is
why the live hook files are *copied into* the mirror on every build.

## Combos that are environment-coupled (expected drift sources)

| Combo | Legitimate reason it may change |
|-------|--------------------------------|
| `adversarial-gate__write-completed` | reads live `.loa.config.yaml` (`flatline_protocol.*.enabled`, both `true` at capture time) |
| `zone-write-guard__*` | reads live `grimoires/loa/zones.yaml` zone globs |
| `karpathy-diff__*` | reads live `.loa.config.yaml` (`karpathy_principles` absent at capture time → enabled, threshold 100); warn lines embed the running line total (deterministic given the seeded fixture) |
| `settings-cleanup__large` | log line embeds entry counts from the synthetic fixture (941 → 940) |

If one of those repo files changes for unrelated reasons, regenerate the
affected goldens deliberately and note it — do not let a drift slide through
inside an optimization commit.

## Notes

- `post-compact-reminder__marker` exercises the full reminder path but the
  mirror does not contain `.claude/scripts/trajectory-gen.sh`, so Step 5
  (trajectory context, spawned with `timeout 2`) is skipped. Production
  marker-path cost is therefore HIGHER than the benchmark row; the marker
  path is one-shot-after-compaction, not per-call.
- `cleanup-context__full-archive` runs under `setsid` so its
  `read < /dev/tty` prompt fails fast into the auto-"Y" branch (that is also
  what happens under real hook execution, which has no tty).
