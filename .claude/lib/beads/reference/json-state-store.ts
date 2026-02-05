/**
 * Reference Implementation: JSON File State Store
 *
 * A simple JSON file-based state persistence store.
 * This is a REFERENCE IMPLEMENTATION for demonstration and testing.
 * Production deployments may want atomic writes or database backing.
 *
 * @module beads/reference/json-state-store
 * @version 1.0.0
 */

import { readFile, writeFile, unlink, access } from "fs/promises";
import { constants } from "fs";

import type { IStateStore } from "../interfaces";

/**
 * Configuration for JsonStateStore
 */
export interface JsonStateStoreConfig {
  /** Path to the JSON state file */
  path: string;

  /** Pretty-print JSON (default: true for development) */
  pretty?: boolean;
}

/**
 * JSON File State Store
 *
 * Persists typed state to a JSON file.
 * Suitable for simple, single-process state persistence.
 *
 * **Limitations**:
 * - No atomic writes (corruption on crash possible)
 * - No locking (race conditions with multiple processes)
 * - Entire state loaded into memory
 *
 * @example
 * ```typescript
 * interface RunModeState {
 *   state: "READY" | "RUNNING" | "HALTED";
 *   currentSprint?: string;
 *   startedAt?: string;
 * }
 *
 * const store = new JsonStateStore<RunModeState>({ path: ".run/state.json" });
 *
 * // Read state
 * const state = await store.get();
 * if (state?.state === "RUNNING") {
 *   console.log(`Currently on sprint: ${state.currentSprint}`);
 * }
 *
 * // Write state
 * await store.set({
 *   state: "RUNNING",
 *   currentSprint: "sprint-1",
 *   startedAt: new Date().toISOString(),
 * });
 * ```
 */
export class JsonStateStore<T> implements IStateStore<T> {
  private readonly path: string;
  private readonly pretty: boolean;

  constructor(config: JsonStateStoreConfig) {
    this.path = config.path;
    this.pretty = config.pretty ?? true;
  }

  /**
   * Get current state
   */
  async get(): Promise<T | null> {
    try {
      await access(this.path, constants.F_OK);
      const content = await readFile(this.path, "utf-8");
      return JSON.parse(content) as T;
    } catch {
      return null;
    }
  }

  /**
   * Set state
   */
  async set(state: T): Promise<void> {
    const content = this.pretty
      ? JSON.stringify(state, null, 2)
      : JSON.stringify(state);
    await writeFile(this.path, content, "utf-8");
  }

  /**
   * Clear (delete) state
   */
  async clear(): Promise<void> {
    try {
      await unlink(this.path);
    } catch {
      // Ignore if file doesn't exist
    }
  }

  /**
   * Check if state exists
   */
  async exists(): Promise<boolean> {
    try {
      await access(this.path, constants.F_OK);
      return true;
    } catch {
      return false;
    }
  }
}

/**
 * Factory function
 */
export function createJsonStateStore<T>(
  config: JsonStateStoreConfig,
): JsonStateStore<T> {
  return new JsonStateStore<T>(config);
}
