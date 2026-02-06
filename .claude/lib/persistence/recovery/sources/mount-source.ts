/**
 * Mount-based recovery source (R2 via rclone/goofys).
 */

import type { CheckpointManifest } from "../../checkpoint/checkpoint-manifest.js";
import type { ICheckpointStorage } from "../../checkpoint/storage-mount.js";
import type { IRecoverySource } from "../recovery-source.js";

export class MountRecoverySource implements IRecoverySource {
  readonly name = "mount";

  constructor(
    private readonly storage: ICheckpointStorage,
    private readonly manifestPath: string = "checkpoint.json",
  ) {}

  async isAvailable(): Promise<boolean> {
    return this.storage.isAvailable();
  }

  async restore(): Promise<Map<string, Buffer> | null> {
    const manifestData = await this.storage.readFile(this.manifestPath);
    if (!manifestData) return null;

    let manifest: CheckpointManifest;
    try {
      manifest = JSON.parse(manifestData.toString());
    } catch {
      return null;
    }

    const files = new Map<string, Buffer>();
    for (const entry of manifest.files) {
      const content = await this.storage.readFile(entry.relativePath);
      if (!content) return null; // Any missing file = source failure
      files.set(entry.relativePath, content);
    }

    return files;
  }
}
