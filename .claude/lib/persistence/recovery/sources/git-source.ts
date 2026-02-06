/**
 * Git-based recovery source.
 */

import type { IRecoverySource } from "../recovery-source.js";

export interface GitRestoreClient {
  cloneOrPull(): Promise<boolean>;
  listFiles(): Promise<string[]>;
  getFile(path: string): Promise<Buffer | null>;
  isAvailable(): Promise<boolean>;
}

export class GitRecoverySource implements IRecoverySource {
  readonly name = "git";

  constructor(private readonly client: GitRestoreClient) {}

  async isAvailable(): Promise<boolean> {
    return this.client.isAvailable();
  }

  async restore(): Promise<Map<string, Buffer> | null> {
    const pulled = await this.client.cloneOrPull();
    if (!pulled) return null;

    const fileList = await this.client.listFiles();
    const files = new Map<string, Buffer>();

    for (const path of fileList) {
      const content = await this.client.getFile(path);
      if (!content) return null;
      files.set(path, content);
    }

    return files;
  }
}
