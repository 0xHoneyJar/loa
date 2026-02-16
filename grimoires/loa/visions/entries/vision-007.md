# Vision 007: Operator Skill Curve & Progressive Orchestration Disclosure

## Source
- Issue: #344, Comment 3 (Orchestration Philosophy)
- Author: @zkSoju (soju+loa operator)
- Session: 2026-02-15 orchestration philosophy debrief

## Insight

Agent orchestration mastery follows a learning curve analogous to RTS games. The framework should scale friction to the operator's position on that curve:

- **Beginners**: Guardrails on agent count ("are you sure you want 5?"), depth gates proposing research plans
- **Power users**: Rapid-deploy with precision at scale, minimal friction

Key design principles identified:
1. **Persona + Scope**: Both archetype lens (how the agent thinks) AND scope (clear boundaries) for maximum precision
2. **Depth gates**: Before spinning up next swarm, propose: "here's what we know, here's the remaining unknown, recommend N agents at depth X"
3. **RuneScape Wilderness model**: Show risk warning once, then trust the player. Scale friction to risk level, not frequency.
4. **Token visibility**: Expose per-agent token counts to orchestrator for better composition decisions (currently a gap — proxy signals only)

## Applicability

Any agent framework where operator expertise varies. Progressive disclosure prevents beginners from burning tokens on poorly-scoped swarms while letting power users operate at full speed.

## Connection

The "friction at the perfect timing" philosophy connects to game design (RuneScape Wilderness), progressive web apps (increasing capability with trust), and Google's graduated access model in Cloud IAM. The framework should model operator trust level and adjust its intervention frequency accordingly.
