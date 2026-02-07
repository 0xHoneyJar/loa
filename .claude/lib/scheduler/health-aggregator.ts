/**
 * Health Aggregator — composite subsystem health reporting.
 *
 * Per SDD Section 4.3.4.
 */

// ── Types ────────────────────────────────────────────

export type HealthState = "healthy" | "degraded" | "unhealthy";

export interface SubsystemHealth {
  name: string;
  state: HealthState;
  message?: string;
}

export interface HealthReport {
  overall: HealthState;
  subsystems: SubsystemHealth[];
}

export interface IHealthReporter {
  name: string;
  check(): SubsystemHealth | Promise<SubsystemHealth>;
}

// ── HealthAggregator ─────────────────────────────────

export class HealthAggregator {
  private readonly reporters: IHealthReporter[] = [];

  addReporter(reporter: IHealthReporter): void {
    this.reporters.push(reporter);
  }

  async check(): Promise<HealthReport> {
    const subsystems = await Promise.all(
      this.reporters.map(async (r) => {
        try {
          return await r.check();
        } catch (err: unknown) {
          return {
            name: r.name,
            state: "unhealthy" as HealthState,
            message: err instanceof Error ? err.message : String(err),
          };
        }
      }),
    );

    let overall: HealthState = "healthy";
    for (const sub of subsystems) {
      if (sub.state === "unhealthy") {
        overall = "unhealthy";
        break;
      }
      if (sub.state === "degraded") {
        overall = "degraded";
      }
    }

    return { overall, subsystems };
  }
}

// ── Factory ──────────────────────────────────────────

export function createHealthAggregator(): HealthAggregator {
  return new HealthAggregator();
}
