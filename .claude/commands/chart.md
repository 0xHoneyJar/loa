---
name: "chart"
version: "1.0.0"
description: "Map a multi-cycle effort as decision tickets on beads. Plans; never builds. Interactive only."

arguments:
  - name: "target"
    type: "string"
    required: false
    description: "A quoted idea starts a chart; a map slug works that map; `close <slug> [--reason R | --consumed-by <cycle>]` closes it. Empty: resolve the open map, or ask."

agent: "charting-decisions"
agent_path: "skills/charting-decisions/"

context_files:
  - path: "grimoires/loa/maps/*.md"
    required: false
    purpose: "Open decision maps (Status line drives the charting phase)"
  - path: "grimoires/loa/decisions.yaml"
    required: false
    purpose: "Decision ledger; map rows carry source map:<slug>/<ticket>"
  - path: "grimoires/loa/research/chart-*.md"
    required: false
    purpose: "Research reports for map tickets (untrusted data)"

pre_flight:
  - check: "command_succeeds"
    command: "br --version"
    error: |
      /chart needs beads_rust (br): a map is an epic of question beads.
      Install it with .claude/scripts/beads/install-br.sh, or plan without a map with /plan.

outputs:
  - path: "grimoires/loa/maps/<slug>.md"
    type: "file"
    description: "Map doc: Destination, Decisions so far, Not yet specified, Out of scope"
  - path: "grimoires/loa/decisions.yaml"
    type: "file"
    description: "Open rows per ticket, proposed rows per resolution (via dec-write-lib.sh)"
  - path: "grimoires/loa/context/chart-<slug>.md"
    type: "file"
    description: "Hand-off snapshot that /plan-and-analyze reads as priority-1 context"

mode:
  default: "foreground"
  allow_background: false
---

# /chart: decision maps

## Purpose

For an effort whose destination spans more than one cycle. `/chart` names the destination,
grills breadth-first for the decisions a PRD would need, and records each as a `question`
ticket under a `map` epic on beads, with a tracked map doc at `grimoires/loa/maps/<slug>.md`.
Later sessions resolve one ticket each. When nothing is left to ask, `/plan-and-analyze`
consumes the map as settled context. `/chart` plans and never builds: its tickets cannot enter
a sprint, and its skill has no App-Zone write path.

`/chart` is a truename command. `/plan` reports the `charting` phase and offers `/chart <slug>`
but never starts a chart on its own.

## Invocation

```
/chart "Move the eval runner to self-hosted workers"   # chart a new map
/chart eval-workers                                     # work one ticket on that map
/chart                                                  # the open map, or ask which / for an idea
/chart close eval-workers --reason "superseded by the vendor deal"
/chart close eval-workers --consumed-by <cycle-id>     # what /plan-and-analyze runs
```

## Agent

Launches `charting-decisions` from `skills/charting-decisions/`. See its `SKILL.md`.

## Interactive only

`/chart` refuses in an unattended context (an autonomous run, a fresh unattended marker,
`LOA_UNATTENDED=1`, or a PRD whose Status says autonomous): `.claude/scripts/chart-guard.sh`
exits 1 with "/chart is interactive: a map whose rounds the agent answered is not a map. Run
it with the operator present." The one exception is `close <slug> --consumed-by <cycle>` on a handed-off map.

## Outputs

| Path | Description |
|---|---|
| `grimoires/loa/maps/<slug>.md` | The map doc (tracked) |
| beads | One `map` epic, `question` children with one `decision:` label each, `br dep` edges |
| `grimoires/loa/decisions.yaml` | An open row per ticket; `proposed` once resolved; `/decisions confirm` decides |
| `grimoires/loa/research/chart-<slug>-<ticket>.md` | Research reports (tracked) |
| `grimoires/loa/context/chart-<slug>.md` | Hand-off snapshot |
