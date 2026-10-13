# Decision maps

One file per multi-cycle effort charted with `/chart` (skill `charting-decisions`). A map is a
`map` epic on beads plus this tracked doc; its tickets are `question` beads, each linked to a
decision-ledger row (`grimoires/loa/decisions.yaml`, `source: map:<slug>/<ticket>`).

- `<slug>.md` follows `.claude/skills/charting-decisions/resources/templates/map.md`: the header
  lines `**Slug**:`, `**Status**:`, `**Epic**:`, then exactly the H2 sections Destination,
  Decisions so far, Not yet specified and Out of scope, plus a final `## Closed` once closed.
  `validate-artifact.sh --type map` checks the shape; a map carries no execution section.
- `**Status**:` is `charting`, `handed-off`, `closed` or `abandoned`. `golden-path.sh` reports
  the `charting` planning phase from this line alone, so it works without `br`.
- Research reports for map tickets live in `grimoires/loa/research/chart-<slug>-<ticket>.md`.
- The hand-off snapshot `/plan-and-analyze` reads is `grimoires/loa/context/chart-<slug>.md`.

This README is not a map; phase detection skips it.
