/**
 * Two-Phase Checkpoint Protocol
 *
 * Flow: write-intent → upload segments → verify → finalize manifest
 *
 * If any step fails, the intent remains and is cleaned up by
 * cleanStaleIntents() on the next run.
 */

import { createHash } from "crypto";
import type { ICheckpointStorage } from "./storage-mount.js";
import { PersistenceError } from "../types.js";
import {
  createManifest,
  verifyManifest,
  type CheckpointManifest,
  type CheckpointFileEntry,
  type WriteIntent,
} from "./checkpoint-manifest.js";

export interface CheckpointProtocolConfig {
  /** Storage backend */
  storage: ICheckpointStorage;
  /** Stale intent timeout in ms. Default: 10 minutes */
  staleIntentTimeoutMs?: number;
}

const MANIFEST_PATH = "checkpoint.json";
const INTENTS_DIR = "_intents";
const DEFAULT_STALE_TIMEOUT = 10 * 60 * 1000;

export class CheckpointProtocol {
  private readonly storage: ICheckpointStorage;
  private readonly staleTimeoutMs: number;

  constructor(config: CheckpointProtocolConfig) {
    this.storage = config.storage;
    this.staleTimeoutMs = config.staleIntentTimeoutMs ?? DEFAULT_STALE_TIMEOUT;
  }

  /**
   * Phase 1: Begin checkpoint — create write intent and upload files.
   * Returns an intent ID that must be passed to finalize().
   */
  async beginCheckpoint(files: Array<{ relativePath: string; content: Buffer }>): Promise<string> {
    const hex4 = Math.floor(Math.random() * 0xffff)
      .toString(16)
      .padStart(4, "0");
    const intentId = `intent-${Date.now()}-${process.pid}-${hex4}`;

    // Write intent marker
    const intent: WriteIntent = {
      id: intentId,
      startedAt: new Date().toISOString(),
      files: files.map((f) => f.relativePath),
      pid: process.pid,
    };

    const ok = await this.storage.writeFile(
      `${INTENTS_DIR}/${intentId}.json`,
      Buffer.from(JSON.stringify(intent)),
    );
    if (!ok) {
      throw new PersistenceError("CHECKPOINT_FAILED", "Failed to create write intent.");
    }

    // Upload each file
    for (const file of files) {
      const uploaded = await this.storage.writeFile(file.relativePath, file.content);
      if (!uploaded) {
        throw new PersistenceError(
          "CHECKPOINT_FAILED",
          `Failed to upload file: ${file.relativePath}`,
        );
      }
    }

    return intentId;
  }

  /**
   * Phase 2: Finalize checkpoint — verify uploads and write manifest atomically.
   */
  async finalizeCheckpoint(
    intentId: string,
    files: Array<{ relativePath: string; content: Buffer }>,
  ): Promise<CheckpointManifest> {
    // Verify each uploaded file
    const fileEntries: CheckpointFileEntry[] = [];

    for (const file of files) {
      const expectedChecksum = createHash("sha256").update(file.content).digest("hex");
      const verified = await this.storage.verifyChecksum(file.relativePath, expectedChecksum);

      if (!verified) {
        throw new PersistenceError(
          "CHECKPOINT_VERIFY_FAILED",
          `Verification failed for: ${file.relativePath}`,
        );
      }

      fileEntries.push({
        relativePath: file.relativePath,
        size: file.content.length,
        checksum: expectedChecksum,
      });
    }

    // Get previous version
    const prevManifest = await this.getManifest();
    const manifest = createManifest(fileEntries, prevManifest?.version);

    // Write manifest atomically
    const ok = await this.storage.writeFile(
      MANIFEST_PATH,
      Buffer.from(JSON.stringify(manifest, null, 2)),
    );
    if (!ok) {
      throw new PersistenceError("CHECKPOINT_FAILED", "Failed to write manifest.");
    }

    // Clean up the intent
    await this.storage.deleteFile(`${INTENTS_DIR}/${intentId}.json`);

    return manifest;
  }

  /**
   * Get the current manifest.
   */
  async getManifest(): Promise<CheckpointManifest | null> {
    const data = await this.storage.readFile(MANIFEST_PATH);
    if (!data) return null;

    try {
      const manifest = JSON.parse(data.toString()) as CheckpointManifest;
      if (!verifyManifest(manifest)) return null;
      return manifest;
    } catch {
      return null;
    }
  }

  /**
   * Clean up stale intents older than the configured timeout.
   */
  async cleanStaleIntents(): Promise<number> {
    const intentFiles = await this.storage.listFiles(INTENTS_DIR);
    let cleaned = 0;

    for (const file of intentFiles) {
      const data = await this.storage.readFile(`${INTENTS_DIR}/${file}`);
      if (!data) continue;

      try {
        const intent = JSON.parse(data.toString()) as WriteIntent;
        const age = Date.now() - new Date(intent.startedAt).getTime();

        if (age > this.staleTimeoutMs) {
          await this.storage.deleteFile(`${INTENTS_DIR}/${file}`);
          cleaned++;
        }
      } catch {
        // Corrupt intent — remove it
        await this.storage.deleteFile(`${INTENTS_DIR}/${file}`);
        cleaned++;
      }
    }

    return cleaned;
  }
}
