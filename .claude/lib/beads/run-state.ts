/**
 * Beads Run State Manager
 *
 * Manages run-mode execution state using beads as the backing store.
 * Replaces .run/ state files with beads as single source of truth.
 *
 * SECURITY: All user-controllable values are validated and shell-escaped
 * before being used in commands to prevent command injection.
 *
 * OPTIMIZATION (RFC #198):
 * - getSprintPlan(): Batch query replaces N+1 pattern (1 query per epic -> 2 queries total)
 * - getSameIssueCount(): Targeted query by issueHash instead of scanning all circuit breakers
 *
 * @module beads/run-state
 * @version 1.1.0
 * @origin Extracted from loa-beauvoir production implementation
 */

import { exec } from "child_process";
import { existsSync, readFileSync } from "fs";
import { promisify } from "util";

import {
  type SprintState,
  type CircuitBreakerRecord,
  type MigrationResult,
  type BeadsRunStateConfig,
  type IBeadsRunStateManager,
  type IBrExecutor,
  type BrCommandResult,
  type Bead,
} from "./interfaces";
import {
  LABELS,
  type RunState,
  deriveRunState,
  createSameIssueLabel,
  parseSameIssueCount,
  getLabelsWithPrefix,
} from "./labels";
import { validateBeadId, validateLabel, shellEscape, validatePath, validateBrCommand } from "./validation";

const execAsync = promisify(exec);

// =============================================================================
// Default BR Executor
// =============================================================================

/**
 * Default br CLI executor
 * @internal
 */
class DefaultBrExecutor implements IBrExecutor {
  constructor(private readonly brCommand: string) {}

  async exec(args: string): Promise<BrCommandResult> {
    try {
      const { stdout, stderr } = await execAsync(`${this.brCommand} ${args}`);
      return {
        success: true,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        exitCode: 0,
      };
    } catch (e) {
      const error = e as { stdout?: string; stderr?: string; code?: number };
      return {
        success: false,
        stdout: error.stdout?.trim() ?? "",
        stderr: error.stderr?.trim() ?? "",
        exitCode: error.code ?? 1,
      };
    }
  }

  async execJson<T = unknown>(args: string): Promise<T> {
    const result = await this.exec(args);
    if (!result.success) {
      throw new Error(`br command failed: ${result.stderr}`);
    }
    if (!result.stdout) {
      return [] as unknown as T;
    }
    return JSON.parse(result.stdout) as T;
  }
}

// =============================================================================
// BeadsRunStateManager
// =============================================================================

/**
 * Manager for run-mode state using beads as backing store
 *
 * Provides a unified interface for run state management, replacing
 * the previous .run/ file-based system with beads queries.
 *
 * @example
 * ```typescript
 * const manager = new BeadsRunStateManager({ verbose: true });
 *
 * // Check current state
 * const state = await manager.getRunState();
 * if (state === "READY") {
 *   // Start a new run
 *   const runId = await manager.startRun(["sprint-1", "sprint-2"]);
 * }
 *
 * // Handle failures
 * if (state === "HALTED") {
 *   const cbs = await manager.getActiveCircuitBreakers();
 *   // Review and resolve...
 *   await manager.resumeRun();
 * }
 * ```
 */
export class BeadsRunStateManager implements IBeadsRunStateManager {
  private readonly executor: IBrExecutor;
  private readonly verbose: boolean;

  constructor(config?: BeadsRunStateConfig) {
    const brCommand = config?.brCommand ?? "br";
    // SECURITY: Validate brCommand to prevent command injection via config
    validateBrCommand(brCommand);
    this.executor = config?.executor ?? new DefaultBrExecutor(brCommand);
    this.verbose = config?.verbose ?? process.env.DEBUG === "true";
  }

  /**
   * Query current run state from beads
   *
   * State mapping:
   * - READY: No beads with run:current label
   * - RUNNING: Has run:current bead with sprint:in_progress child
   * - HALTED: Has run:current bead with circuit-breaker label
   * - COMPLETE: Has run:current bead with no pending sprints
   */
  async getRunState(): Promise<RunState> {
    try {
      // Check for in-progress runs
      const runs = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.RUN_CURRENT}' --json`,
      );

      if (!runs || runs.length === 0) {
        return "READY";
      }

      const currentRun = runs[0];

      // Use deriveRunState for consistent state derivation
      const derivedState = deriveRunState(currentRun.labels || []);
      if (derivedState === "HALTED" || derivedState === "COMPLETE") {
        return derivedState;
      }

      // Check for in-progress sprints
      const activeSprints = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.SPRINT_IN_PROGRESS}' --json`,
      );

      if (activeSprints && activeSprints.length > 0) {
        return "RUNNING";
      }

      // Check for pending sprints
      const pendingSprints = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.SPRINT_PENDING}' --json`,
      );

      if (!pendingSprints || pendingSprints.length === 0) {
        return "COMPLETE";
      }

      // Has pending sprints but no in-progress - still considered RUNNING
      return "RUNNING";
    } catch (e) {
      if (this.verbose) {
        console.error(`[beads-run-state] Error getting run state: ${e}`);
      }
      // Default to READY on error (no active run)
      return "READY";
    }
  }

  /**
   * Get current sprint being executed
   * Returns null if no sprint is in progress
   */
  async getCurrentSprint(): Promise<SprintState | null> {
    try {
      const sprints = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.SPRINT_IN_PROGRESS}' --json`,
      );

      if (!sprints || sprints.length === 0) {
        return null;
      }

      const sprint = sprints[0];
      // SECURITY (TS-001): Validate bead ID from query result before shell interpolation
      validateBeadId(sprint.id);
      const sprintNumber = this.extractSprintNumber(sprint.labels || []);

      // Count tasks in this sprint
      const tasks = await this.queryBeadsJson<Bead[]>(
        `list --label 'epic:${sprint.id}' --json`,
      );

      const completedTasks = (tasks || []).filter((t) => t.status === "closed").length;
      const currentTask = (tasks || []).find((t) =>
        t.labels?.includes("in_progress"),
      );

      return {
        id: sprint.id,
        sprintNumber,
        status: "in_progress",
        tasksTotal: (tasks || []).length,
        tasksCompleted: completedTasks,
        currentTaskId: currentTask?.id,
      };
    } catch (e) {
      if (this.verbose) {
        console.error(`[beads-run-state] Error getting current sprint: ${e}`);
      }
      return null;
    }
  }

  /**
   * Get all sprints in the current run plan
   *
   * OPTIMIZATION (RFC #198): Batch query pattern.
   * Previous: 1 query for epics + N queries for tasks (one per epic) = N+1 queries.
   * Now: 1 query for epics + 1 query for all tasks = 2 queries total.
   * With 4 sprints x 5 tasks, this reduces from ~21 subprocess calls to 2.
   */
  async getSprintPlan(): Promise<SprintState[]> {
    try {
      // Get all epic beads
      const epics = await this.queryBeadsJson<Bead[]>(`list --type epic --json`);

      if (!epics) return [];

      // Filter to sprint epics first
      const sprintEpics = epics.filter((epic) => {
        const labels = epic.labels || [];
        return this.extractSprintNumber(labels) !== 0;
      });

      if (sprintEpics.length === 0) return [];

      // OPTIMIZATION: Single batch query for ALL tasks instead of N queries.
      // Fetch all task-type beads and group by parent epic in memory.
      // TODO: If beads database grows large with historical data, consider
      // scoping via compound label filter (e.g. --label 'run:current') if
      // br supports it, to avoid fetching unrelated tasks.
      const allTasks = await this.queryBeadsJson<Bead[]>(`list --type task --json`);
      const tasksByEpic = new Map<string, Bead[]>();

      if (allTasks) {
        for (const task of allTasks) {
          const labels = task.labels || [];
          // Match tasks to epics via "epic:{epicId}" label
          for (const label of labels) {
            if (label.startsWith("epic:")) {
              const epicId = label.slice(5); // "epic:".length
              const existing = tasksByEpic.get(epicId) || [];
              existing.push(task);
              tasksByEpic.set(epicId, existing);
            }
          }
        }
      }

      const sprints: SprintState[] = [];

      for (const epic of sprintEpics) {
        const labels = epic.labels || [];
        const sprintNumber = this.extractSprintNumber(labels);

        let status: SprintState["status"] = "pending";
        if (labels.includes(LABELS.SPRINT_COMPLETE)) {
          status = "completed";
        } else if (labels.includes(LABELS.SPRINT_IN_PROGRESS)) {
          status = "in_progress";
        } else if (labels.includes(LABELS.CIRCUIT_BREAKER)) {
          status = "halted";
        }

        // Look up tasks from pre-fetched map (O(1) instead of subprocess)
        const tasks = tasksByEpic.get(epic.id) || [];

        sprints.push({
          id: epic.id,
          sprintNumber,
          status,
          tasksTotal: tasks.length,
          tasksCompleted: tasks.filter((t) => t.status === "closed").length,
        });
      }

      // Sort by sprint number
      return sprints.sort((a, b) => a.sprintNumber - b.sprintNumber);
    } catch (e) {
      if (this.verbose) {
        console.error(`[beads-run-state] Error getting sprint plan: ${e}`);
      }
      return [];
    }
  }

  /**
   * Start a new run with given sprint IDs
   */
  async startRun(sprintIds: string[]): Promise<string> {
    // Validate all sprint IDs
    for (const id of sprintIds) {
      validateBeadId(id);
    }

    // Create run epic
    const title = `Run: ${new Date().toISOString().split("T")[0]}`;
    const runId = await this.createBead({
      title,
      type: "epic",
      priority: 0,
      labels: [LABELS.RUN_CURRENT, LABELS.RUN_EPIC],
    });

    if (this.verbose) {
      console.log(`[beads-run-state] Created run ${runId}`);
    }

    // Link sprints to run and mark as pending
    for (let i = 0; i < sprintIds.length; i++) {
      const sprintId = sprintIds[i];
      await this.addLabel(sprintId, `sprint:${i + 1}`);
      await this.addLabel(sprintId, LABELS.SPRINT_PENDING);
      await this.addLabel(sprintId, `run:${runId}`);
    }

    console.log(`[beads-run-state] Started run ${runId} with ${sprintIds.length} sprints`);
    return runId;
  }

  /**
   * Start executing a specific sprint
   */
  async startSprint(sprintId: string): Promise<void> {
    validateBeadId(sprintId);

    // Remove pending, add in_progress
    await this.removeLabel(sprintId, LABELS.SPRINT_PENDING);
    await this.addLabel(sprintId, LABELS.SPRINT_IN_PROGRESS);

    console.log(`[beads-run-state] Started sprint ${sprintId}`);
  }

  /**
   * Mark sprint as complete
   */
  async completeSprint(sprintId: string): Promise<void> {
    validateBeadId(sprintId);

    await this.removeLabel(sprintId, LABELS.SPRINT_IN_PROGRESS);
    await this.addLabel(sprintId, LABELS.SPRINT_COMPLETE);
    await this.closeBead(sprintId);

    console.log(`[beads-run-state] Completed sprint ${sprintId}`);
  }

  /**
   * Halt run by creating circuit breaker bead
   */
  async haltRun(reason: string): Promise<CircuitBreakerRecord> {
    const currentSprint = await this.getCurrentSprint();
    const sprintId = currentSprint?.id ?? "unknown";
    return this.createCircuitBreaker(sprintId, reason, 1);
  }

  /**
   * Resume run by resolving all active circuit breakers
   */
  async resumeRun(): Promise<void> {
    const cbs = await this.getActiveCircuitBreakers();
    for (const cb of cbs) {
      await this.resolveCircuitBreaker(cb.beadId);
    }
    console.log(`[beads-run-state] Resumed run, resolved ${cbs.length} circuit breakers`);
  }

  /**
   * Create circuit breaker bead for failure tracking
   */
  async createCircuitBreaker(
    sprintId: string,
    reason: string,
    failureCount: number,
  ): Promise<CircuitBreakerRecord> {
    validateBeadId(sprintId);

    const title = `Circuit Breaker: Sprint ${sprintId}`;
    const beadId = await this.createBead({
      title,
      type: "debt",
      priority: 0,
      labels: [LABELS.CIRCUIT_BREAKER, createSameIssueLabel(failureCount)],
    });

    await this.addComment(beadId, `Triggered: ${reason}`);

    // Also label the run as halted
    try {
      const runs = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.RUN_CURRENT}' --json`,
      );
      if (runs && runs.length > 0) {
        await this.addLabel(runs[0].id, LABELS.CIRCUIT_BREAKER);
      }
    } catch {
      // Ignore if run not found
    }

    const record: CircuitBreakerRecord = {
      beadId,
      sprintId,
      reason,
      failureCount,
      createdAt: new Date().toISOString(),
    };

    console.log(`[beads-run-state] Created circuit breaker ${beadId} for sprint ${sprintId}`);
    return record;
  }

  /**
   * Resolve circuit breaker and allow run to resume
   */
  async resolveCircuitBreaker(beadId: string): Promise<void> {
    validateBeadId(beadId);

    await this.closeBead(beadId);
    await this.addComment(beadId, `Resolved at ${new Date().toISOString()}`);

    // Remove circuit breaker label from run
    try {
      const runs = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.RUN_CURRENT}' --json`,
      );
      if (runs && runs.length > 0) {
        await this.removeLabel(runs[0].id, LABELS.CIRCUIT_BREAKER);
      }
    } catch {
      // Ignore if run not found
    }

    console.log(`[beads-run-state] Resolved circuit breaker ${beadId}`);
  }

  /**
   * Get all active (open) circuit breakers
   */
  async getActiveCircuitBreakers(): Promise<CircuitBreakerRecord[]> {
    try {
      const beads = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.CIRCUIT_BREAKER}' --status open --json`,
      );

      if (!beads) return [];

      return beads
        .filter((b) => b.type === "debt")
        .map((b) => {
          const labels = b.labels || [];
          const sameIssueLabels = getLabelsWithPrefix(labels, LABELS.SAME_ISSUE_PREFIX);
          let failureCount = 1;
          for (const label of sameIssueLabels) {
            const count = parseSameIssueCount(label);
            if (count && count > failureCount) {
              failureCount = count;
            }
          }

          return {
            beadId: b.id,
            sprintId: this.extractSprintId(labels),
            reason: b.description || "Unknown",
            failureCount,
            createdAt: b.created_at,
          };
        });
    } catch (e) {
      if (this.verbose) {
        console.error(`[beads-run-state] Error getting circuit breakers: ${e}`);
      }
      return [];
    }
  }

  /**
   * Get same-issue count from circuit breaker history
   *
   * Used to track how many times the same issue has occurred.
   *
   * OPTIMIZATION (RFC #198): When an issueHash is provided, uses a
   * targeted label query (`issue:{hash}`) to let br (SQLite) do the
   * filtering. Falls back to scanning all circuit breakers if the
   * targeted query returns nothing (backward compatibility with
   * circuit breakers created before issue-hash labeling).
   *
   * Previous: Always fetched ALL circuit breakers and scanned linearly.
   * Now: Single targeted query when issue labels exist, O(1) via SQLite index.
   */
  async getSameIssueCount(issueHash: string): Promise<number> {
    try {
      // Targeted query: look for circuit breakers labeled with this specific issue
      if (issueHash) {
        // SECURITY: Validate constructed label before shell interpolation
        const issueLabel = `issue:${issueHash}`;
        validateLabel(issueLabel);

        const targeted = await this.queryBeadsJson<Bead[]>(
          `list --label '${LABELS.CIRCUIT_BREAKER}' --label '${issueLabel}' --json`,
        );

        if (targeted && targeted.length > 0) {
          let maxCount = 0;
          for (const bead of targeted) {
            const labels = bead.labels || [];
            const sameIssueLabels = getLabelsWithPrefix(labels, LABELS.SAME_ISSUE_PREFIX);
            for (const label of sameIssueLabels) {
              const count = parseSameIssueCount(label);
              if (count && count > maxCount) {
                maxCount = count;
              }
            }
          }
          return maxCount;
        }
      }

      // Fallback: scan all circuit breakers (backward compatibility).
      // NOTE: Returns the global max same-issue count across ALL circuit
      // breakers, not filtered to the specific issueHash. This preserves
      // the original function's behavior which also ignored issueHash.
      // A future fix could filter by issue content here.
      const beads = await this.queryBeadsJson<Bead[]>(
        `list --label '${LABELS.CIRCUIT_BREAKER}' --json`,
      );

      if (!beads) return 0;

      let maxCount = 0;
      for (const bead of beads) {
        const labels = bead.labels || [];
        const sameIssueLabels = getLabelsWithPrefix(labels, LABELS.SAME_ISSUE_PREFIX);
        for (const label of sameIssueLabels) {
          const count = parseSameIssueCount(label);
          if (count && count > maxCount) {
            maxCount = count;
          }
        }
      }

      return maxCount;
    } catch {
      return 0;
    }
  }

  /**
   * Migrate existing .run/ state to beads
   */
  async migrateFromDotRun(dotRunPath: string): Promise<MigrationResult> {
    // Security: Block path traversal attacks
    validatePath(dotRunPath);

    const warnings: string[] = [];
    let migratedSprints = 0;
    let migratedTasks = 0;
    let circuitBreakersCreated = 0;

    try {
      // Read state.json
      const statePath = `${dotRunPath}/state.json`;
      if (!existsSync(statePath)) {
        return {
          success: true,
          migratedSprints: 0,
          migratedTasks: 0,
          circuitBreakersCreated: 0,
          warnings: ["No .run/state.json found - nothing to migrate"],
        };
      }

      // Read sprint-plan-state.json if exists
      const sprintPlanPath = `${dotRunPath}/sprint-plan-state.json`;
      if (existsSync(sprintPlanPath)) {
        const sprintPlanRaw = readFileSync(sprintPlanPath, "utf-8");
        const sprintPlan = JSON.parse(sprintPlanRaw);

        // Create sprint beads
        for (const sprint of sprintPlan.sprints?.list || []) {
          const sprintNum = sprint.id?.replace("sprint-", "") || "0";
          const labels = [`sprint:${sprintNum}`];

          if (sprint.status === "completed") {
            labels.push(LABELS.SPRINT_COMPLETE);
          } else if (sprint.status === "in_progress") {
            labels.push(LABELS.SPRINT_IN_PROGRESS);
          } else {
            labels.push(LABELS.SPRINT_PENDING);
          }

          await this.createBead({
            title: `Sprint: ${sprint.id}`,
            type: "epic",
            priority: 1,
            labels,
          });
          migratedSprints++;
        }
      }

      // Read circuit-breaker.json if exists
      const cbPath = `${dotRunPath}/circuit-breaker.json`;
      if (existsSync(cbPath)) {
        const cbRaw = readFileSync(cbPath, "utf-8");
        const cb = JSON.parse(cbRaw);
        if (cb.state === "open") {
          await this.createCircuitBreaker(
            cb.sprint || "unknown",
            cb.reason || "Migrated from .run/",
            cb.failures || 3,
          );
          circuitBreakersCreated++;
        }
      }

      console.log(
        `[beads-run-state] Migration complete: ${migratedSprints} sprints, ${circuitBreakersCreated} circuit breakers`,
      );

      return {
        success: true,
        migratedSprints,
        migratedTasks,
        circuitBreakersCreated,
        warnings,
      };
    } catch (e) {
      return {
        success: false,
        migratedSprints,
        migratedTasks,
        circuitBreakersCreated,
        warnings: [...warnings, `Migration failed: ${e}`],
      };
    }
  }

  /**
   * Check if .run/ directory exists (for deprecation warning)
   */
  dotRunExists(dotRunPath = ".run"): boolean {
    return existsSync(dotRunPath);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helper Methods
  // ─────────────────────────────────────────────────────────────────────────────

  private async queryBeadsJson<T>(args: string): Promise<T | null> {
    try {
      return await this.executor.execJson<T>(args);
    } catch {
      return null;
    }
  }

  private async createBead(opts: {
    title: string;
    type: string;
    priority: number;
    labels?: string[];
  }): Promise<string> {
    // shellEscape() already wraps in single quotes - don't double-wrap
    const escapedTitle = shellEscape(opts.title);
    const labelArgs =
      opts.labels
        ?.map((l) => {
          validateLabel(l);
          // shellEscape() returns 'label' so don't add extra quotes
          return `--label ${shellEscape(l)}`;
        })
        .join(" ") || "";

    const result = await this.executor.execJson<{ id: string }>(
      `create ${escapedTitle} --type ${opts.type} --priority ${opts.priority} ${labelArgs} --json`,
    );

    return result.id;
  }

  private async addLabel(beadId: string, label: string): Promise<void> {
    validateBeadId(beadId);
    validateLabel(label);
    // beadId is validated (safe chars only), label is shellEscaped
    await this.executor.exec(`label add ${shellEscape(beadId)} ${shellEscape(label)}`);
  }

  private async removeLabel(beadId: string, label: string): Promise<void> {
    validateBeadId(beadId);
    validateLabel(label);
    try {
      await this.executor.exec(`label remove ${shellEscape(beadId)} ${shellEscape(label)}`);
    } catch {
      // Ignore if label doesn't exist
    }
  }

  private async addComment(beadId: string, text: string): Promise<void> {
    validateBeadId(beadId);
    // shellEscape() already wraps in quotes
    await this.executor.exec(`comments add ${shellEscape(beadId)} ${shellEscape(text)}`);
  }

  private async closeBead(beadId: string): Promise<void> {
    validateBeadId(beadId);
    await this.executor.exec(`close ${shellEscape(beadId)}`);
  }

  private extractSprintNumber(labels: string[]): number {
    const sprintLabel = labels?.find((l) => /^sprint:\d+$/.test(l));
    if (sprintLabel) {
      return parseInt(sprintLabel.split(":")[1], 10);
    }
    return 0;
  }

  private extractSprintId(labels: string[]): string {
    const sprintLabel = labels?.find((l) => l.startsWith("sprint:") && !l.includes("_"));
    return sprintLabel?.split(":")[1] || "unknown";
  }
}

// =============================================================================
// Factory Function
// =============================================================================

/**
 * Factory function for creating BeadsRunStateManager
 *
 * @example
 * ```typescript
 * const manager = createBeadsRunStateManager({ verbose: true });
 * ```
 */
export function createBeadsRunStateManager(
  config?: BeadsRunStateConfig,
): BeadsRunStateManager {
  return new BeadsRunStateManager(config);
}
