import * as fs from "fs";
import * as path from "path";

export interface TrajectoryEvent {
  event: "forge.archivist.page_synthesized";
  timestamp: string;
  oracle_path: string;
  candidate_path: string;
  fidelity: number;
  pass: boolean;
  oracle_integrity: boolean;
  seed_count: number;
}

export function appendTrajectoryEvent(
  trajectoryPath: string,
  event: TrajectoryEvent,
): void {
  const line = JSON.stringify(event) + "\n";
  const resolved = path.isAbsolute(trajectoryPath)
    ? trajectoryPath
    : path.resolve(process.cwd(), trajectoryPath);
  try {
    fs.appendFileSync(resolved, line, { encoding: "utf8" });
  } catch (err) {
    console.error(`WARN: failed to append trajectory event to ${resolved}: ${err}`);
  }
}
