/**
 * File Watcher — fs.watch primary with fs.watchFile polling fallback.
 *
 * Provides cross-platform file change detection with configurable
 * debounce to coalesce rapid writes into a single callback.
 *
 * @module .claude/lib/persistence/identity/file-watcher
 */

import type { FSWatcher } from "fs";
import { watch, watchFile, unwatchFile, existsSync } from "fs";

export interface FileWatcherConfig {
  /** Path to watch */
  filePath: string;
  /** Debounce interval in ms (default: 1000) */
  debounceMs?: number;
  /** Use polling fallback only (default: false) */
  forcePolling?: boolean;
  /** Polling interval in ms for watchFile fallback (default: 2000) */
  pollIntervalMs?: number;
}

export type FileChangeCallback = (filePath: string) => void | Promise<void>;

/**
 * FileWatcher with fs.watch primary and fs.watchFile polling fallback.
 *
 * fs.watch is inode-based and fast but unreliable on network mounts.
 * fs.watchFile uses stat() polling — slower but universally reliable.
 */
export class FileWatcher {
  private readonly filePath: string;
  private readonly debounceMs: number;
  private readonly forcePolling: boolean;
  private readonly pollIntervalMs: number;

  private watcher: FSWatcher | null = null;
  private polling = false;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private callback: FileChangeCallback | null = null;
  private stopped = false;

  constructor(config: FileWatcherConfig) {
    this.filePath = config.filePath;
    this.debounceMs = config.debounceMs ?? 1000;
    this.forcePolling = config.forcePolling ?? false;
    this.pollIntervalMs = config.pollIntervalMs ?? 2000;
  }

  /**
   * Start watching for changes.
   */
  start(callback: FileChangeCallback): void {
    this.callback = callback;
    this.stopped = false;

    if (this.forcePolling) {
      this.startPolling();
      return;
    }

    try {
      this.watcher = watch(this.filePath, { persistent: false }, () => {
        this.onChangeDetected();
      });

      // Fallback if watcher errors
      this.watcher.on("error", () => {
        this.watcher?.close();
        this.watcher = null;
        this.startPolling();
      });
    } catch {
      // fs.watch failed (e.g. ENOSYS on network mount)
      this.startPolling();
    }
  }

  /**
   * Stop watching.
   */
  stop(): void {
    this.stopped = true;

    if (this.watcher) {
      this.watcher.close();
      this.watcher = null;
    }

    if (this.polling) {
      unwatchFile(this.filePath);
      this.polling = false;
    }

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
  }

  /** Whether the watcher is using polling fallback. */
  isPolling(): boolean {
    return this.polling;
  }

  private startPolling(): void {
    if (this.stopped) return;
    this.polling = true;
    watchFile(this.filePath, { interval: this.pollIntervalMs }, () => {
      this.onChangeDetected();
    });
  }

  private onChangeDetected(): void {
    if (this.stopped || !this.callback) return;

    // Debounce: reset timer on each event
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer);
    }

    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null;
      if (!this.stopped && this.callback) {
        this.callback(this.filePath);
      }
    }, this.debounceMs);
  }
}
