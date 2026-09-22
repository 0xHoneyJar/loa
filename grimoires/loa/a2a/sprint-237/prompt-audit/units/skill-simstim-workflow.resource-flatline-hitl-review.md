# simstim Flatline HITL review procedure (split from SKILL.md, cycle-124 Sprint 3 prompt audit)

Shared by Phases 2 (PRD), 4 (SDD), and 6 (Sprint plan) — each runs this same procedure against its own artifact and phase tag (`--doc <artifact> --phase <prd|sdd|sprint>`), and the same state-update pair (`--update-flatline-metrics <phase> [integrated] [disputed] [blockers]`, `--update-phase flatline_<phase> completed`).

1. Run Flatline Protocol:
   ```bash
   result=$(.claude/scripts/flatline-orchestrator.sh --doc <artifact> --phase <phase> --json)
   ```

2. Process results in HITL mode:
   - **HIGH_CONSENSUS** (both models >700): Auto-integrate without prompting
   - **DISPUTED** (delta >300): Present to user with options [Accept/Reject/Skip]
   - **BLOCKER** (skeptic concern >700): Present to user with options [Override with rationale/Reject/Defer]
   - **LOW_VALUE** (both <400): Skip silently

3. For each DISPUTED item, ask user:
   ```
   DISPUTED: [suggestion]
   GPT scored [X], Opus scored [Y]
   [A]ccept / [R]eject / [S]kip?
   ```

4. For each BLOCKER item, ask user:
   ```
   BLOCKER: [concern]
   Severity: [score]
   [O]verride (requires rationale) / [R]eject / [D]efer?
   ```

   **BLOCKER Override Handling:**
   - If Override: REQUIRE user to provide rationale
   - Log override to trajectory:
     ```bash
     .claude/scripts/simstim-orchestrator.sh --log-blocker-override \
         --blocker-id "[id]" \
         --decision "override" \
         --rationale "[user rationale]"
     ```
   - If Reject: Mark blocker as rejected, continue to next
   - If Defer: Add to deferred list in state for post-implementation review

5. Update state with metrics:
   ```bash
   .claude/scripts/simstim-orchestrator.sh --update-flatline-metrics <phase> [integrated] [disputed] [blockers]
   .claude/scripts/simstim-orchestrator.sh --update-phase flatline_<phase> completed
   ```

**Skip if Flatline unavailable:** Log warning, continue to the next phase.
