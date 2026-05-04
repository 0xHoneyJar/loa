# DispatchContract — example phase scripts

This directory ships a copy-and-customize template for the L3 5-phase contract.
The example scripts demonstrate the input/output protocol; replace each with
your own logic to build a real scheduled cycle.

## Phase-script protocol

Every phase script is invoked by `_l3_run_phase` as:

```
<phase_path> <cycle_id> <schedule_id> <phase_index> <prior_phases_json>
```

| `$1` | `cycle_id`         | Content-addressed cycle identifier. Same value every phase. |
| `$2` | `schedule_id`      | Caller-supplied id from ScheduleConfig. |
| `$3` | `phase_index`      | 0=reader, 1=decider, 2=dispatcher, 3=awaiter, 4=logger. |
| `$4` | `prior_phases_json` | JSON array of prior phase records. `[]` for reader. |

**Output contract:**
- `stdout` — arbitrary; sha256 hashed into `output_hash` for replay determinism
- `stderr` — last 4KB captured as `diagnostic` on error (redacted)
- `exit 0` — phase succeeded, cycle proceeds
- `exit non-zero` — phase failed, cycle aborts with `cycle.error{phase_error}`
- `exit 124` / `exit 137` — phase exceeded timeout (timeout TERM / KILL)

## Phase semantics (convention, not enforcement)

| Phase | Convention |
|-------|------------|
| `reader` | Side-effect-free; gathers state. Output describes the world. |
| `decider` | Side-effect-free; reads reader output (via prior_phases_json `output_hash` references) and computes what to do. |
| `dispatcher` | THIS is where mutation happens. Idempotent if possible. |
| `awaiter` | Waits for dispatched work to complete (e.g., poll a job, wait for ACK). |
| `logger` | Records the cycle outcome to a domain-specific destination. |

Cycle-wide state passes via stdout / stderr / `prior_phases_json`. Phases that
need to share large state SHOULD write to a temp file and reference its path
in stdout (the `output_hash` then anchors it for replay determinism).

## Run the example end-to-end

```bash
.claude/scripts/lib/scheduled-cycle-lib.sh invoke \
    .claude/skills/scheduled-cycle-template/contracts/example-schedule.yaml \
    --cycle-id "demo-$(date -u +%Y%m%dT%H%M%SZ)"
```

Then inspect:

```bash
.claude/scripts/lib/scheduled-cycle-lib.sh replay .run/cycles.jsonl
```

## Customizing

1. Copy this directory to your project (e.g., `<project>/contracts/<your-cycle>/`)
2. Replace each `example-*.sh` with your phase logic
3. Edit `example-schedule.yaml` (rename!) with your `schedule_id`, cron expression, and paths
4. Validate with `--dry-run`:
   ```
   cycle_invoke <your-schedule.yaml> --dry-run
   ```
5. Register via `/schedule`

## Testing your contract

A common harness is to substitute mock phase scripts that emit known outputs
and exit with known codes — then assert on the resulting `cycle.phase` events.
See `tests/integration/scheduled-cycle-skill-3D.bats` for an example harness.
