import * as fs from "fs";
import * as path from "path";

export interface ArchivistHarnessState {
  version: number;
  mode: string;
  active_digests: string[];
  last_ingest_cursor: string | null;
  initialized_at: string;
}

const STATE_PATH = path.resolve(process.cwd(), ".run/archivist-state.json");

function bootstrapped(): ArchivistHarnessState {
  return {
    version: 1,
    mode: "bootstrapped",
    active_digests: [],
    last_ingest_cursor: null,
    initialized_at: new Date().toISOString(),
  };
}

export function initState(statePath = STATE_PATH): ArchivistHarnessState {
  const dir = path.dirname(statePath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  if (!fs.existsSync(statePath)) {
    const state = bootstrapped();
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2), "utf8");
    return state;
  }

  const raw = fs.readFileSync(statePath, "utf8");
  try {
    return JSON.parse(raw);
  } catch {
    console.error(`WARN: ${statePath} contains invalid JSON — reinitializing`);
    const state = bootstrapped();
    fs.writeFileSync(statePath, JSON.stringify(state, null, 2), "utf8");
    return state;
  }
}
