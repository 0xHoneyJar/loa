# Reviewer concerns (Phase 2 notes, preliminary)

- pipeline-run.sh: arm-id leak grep (line ~506) scans the whole sandbox including the mounted .claude/ tree; any arm id string in the framework tree refuses the run.
- pipeline-run.sh: pricing via `python3 -I .../pricing.py --alias --json` run from .claude/adapters despite the "no .claude code" trust-boundary note; a silent null disables the cap watchdog (priced:false).
- pipeline-run.sh: snapshot index keys lowercased (implement/fix1) vs header doc (IMPLEMENT|FIX1); check took-effect.sh / ablation-row.sh readers.
- pipeline-run.sh: exit 137 without timeout classified as "interrupted" (could be OOM under --memory 4g).
- sandbox-mount.sh: inline manifest (find .claude -type f) vs tools/gen-checksums.sh format — must match what check-loa.sh integrity verifies.
- sandbox-mount.sh init_sandbox_beads runs the sandbox's own .claude/scripts/beads/update-beads-state.sh (mounted PR code) — trust boundary.
- Secrets: AWS_BEARER_TOKEN_BEDROCK path through env shim and docker -e name-only; argv capture masks <set>.
- check-loa.sh / preflight.sh mount-scope changes (#1267): verify checksums.json format and scope filter.
- spend.sh / took-effect.sh / ablation-row.sh: JSON parsing of ledgers, jq arithmetic, awk float handling.
