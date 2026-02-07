/**
 * MECE Validator — detect overlapping/duplicate scheduled tasks.
 *
 * Pure function, no side effects. Per SDD Section 4.3.6.
 */

// ── Types ────────────────────────────────────────────

export interface TaskDefinition {
  id: string;
  intervalMs: number;
  mutexGroup?: string;
}

export interface Overlap {
  taskA: string;
  taskB: string;
  reason: string;
}

export interface MECEReport {
  valid: boolean;
  overlaps: Overlap[];
  gaps: string[];
}

// ── Validator ────────────────────────────────────────

export function validateMECE(tasks: TaskDefinition[]): MECEReport {
  const overlaps: Overlap[] = [];
  const gaps: string[] = [];

  // Detect duplicate IDs
  const idCounts = new Map<string, number>();
  for (const t of tasks) {
    idCounts.set(t.id, (idCounts.get(t.id) ?? 0) + 1);
  }
  for (const [id, count] of idCounts) {
    if (count > 1) {
      overlaps.push({
        taskA: id,
        taskB: id,
        reason: `Duplicate task ID "${id}" (appears ${count} times)`,
      });
    }
  }

  // Detect tasks with same mutex group and overlapping intervals
  // Two tasks in the same mutex group with similar intervals may indicate
  // unintentional duplication
  const byGroup = new Map<string, TaskDefinition[]>();
  for (const t of tasks) {
    if (t.mutexGroup) {
      const group = byGroup.get(t.mutexGroup) ?? [];
      group.push(t);
      byGroup.set(t.mutexGroup, group);
    }
  }

  for (const [group, groupTasks] of byGroup) {
    for (let i = 0; i < groupTasks.length; i++) {
      for (let j = i + 1; j < groupTasks.length; j++) {
        const a = groupTasks[i];
        const b = groupTasks[j];
        // Check if intervals are close enough to overlap
        // Use a 10% tolerance band
        const ratio = Math.max(a.intervalMs, b.intervalMs) /
          Math.min(a.intervalMs, b.intervalMs);
        if (ratio < 1.1) {
          overlaps.push({
            taskA: a.id,
            taskB: b.id,
            reason: `Tasks in mutex group "${group}" with near-identical intervals (${a.intervalMs}ms vs ${b.intervalMs}ms)`,
          });
        }
      }
    }
  }

  return {
    valid: overlaps.length === 0 && gaps.length === 0,
    overlaps,
    gaps,
  };
}
