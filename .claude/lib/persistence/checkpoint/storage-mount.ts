/**
 * Mount-based checkpoint storage.
 *
 * ICheckpointStorage interface allows plugging in different backends.
 * MountCheckpointStorage is the default (filesystem mount, e.g. R2 via rclone).
 */

import { createHash } from "crypto";
import { existsSync } from "fs";
import { readFile, writeFile, mkdir, rename, unlink, readdir, stat } from "fs/promises";
import { join, dirname, resolve, normalize } from "path";

export interface ICheckpointStorage {
  isAvailable(): Promise<boolean>;
  readFile(relativePath: string): Promise<Buffer | null>;
  writeFile(relativePath: string, content: Buffer): Promise<boolean>;
  deleteFile(relativePath: string): Promise<boolean>;
  listFiles(prefix?: string): Promise<string[]>;
  verifyChecksum(relativePath: string, expected: string): Promise<boolean>;
  stat(relativePath: string): Promise<{ size: number; mtime: Date } | null>;
}

export class MountCheckpointStorage implements ICheckpointStorage {
  private readonly resolvedRoot: string;

  constructor(
    private readonly mountPath: string,
    private readonly prefix: string = "grimoires",
  ) {
    this.resolvedRoot = resolve(mountPath, prefix);
  }

  async isAvailable(): Promise<boolean> {
    if (!existsSync(this.mountPath)) return false;
    try {
      const entries = await readdir(this.mountPath);
      return entries.length > 0 || existsSync(join(this.mountPath, this.prefix));
    } catch {
      return false;
    }
  }

  /**
   * Resolve a relative path within the mount, with path traversal protection.
   * Rejects any path that would escape the mount root (e.g., ../../etc/passwd).
   */
  private resolvePath(relativePath: string): string {
    const resolved = resolve(this.resolvedRoot, normalize(relativePath));
    if (!resolved.startsWith(this.resolvedRoot)) {
      throw new Error(`Path traversal rejected: ${relativePath}`);
    }
    return resolved;
  }

  async readFile(relativePath: string): Promise<Buffer | null> {
    const path = this.resolvePath(relativePath);
    if (!existsSync(path)) return null;
    try {
      return await readFile(path);
    } catch {
      return null;
    }
  }

  async writeFile(relativePath: string, content: Buffer): Promise<boolean> {
    const path = this.resolvePath(relativePath);
    try {
      await mkdir(dirname(path), { recursive: true });
      const tmpPath = `${path}.tmp.${process.pid}`;
      await writeFile(tmpPath, content);
      await rename(tmpPath, path);
      return true;
    } catch {
      return false;
    }
  }

  async deleteFile(relativePath: string): Promise<boolean> {
    const path = this.resolvePath(relativePath);
    try {
      await unlink(path);
      return true;
    } catch {
      return false;
    }
  }

  async listFiles(subPrefix?: string): Promise<string[]> {
    const dir = subPrefix
      ? join(this.mountPath, this.prefix, subPrefix)
      : join(this.mountPath, this.prefix);

    if (!existsSync(dir)) return [];

    const files: string[] = [];
    const walk = async (d: string, base: string): Promise<void> => {
      const entries = await readdir(d, { withFileTypes: true });
      for (const e of entries) {
        const full = join(d, e.name);
        const rel = base ? `${base}/${e.name}` : e.name;
        if (e.isDirectory()) await walk(full, rel);
        else files.push(rel);
      }
    };
    await walk(dir, "");
    return files;
  }

  async verifyChecksum(relativePath: string, expected: string): Promise<boolean> {
    const content = await this.readFile(relativePath);
    if (!content) return false;
    const actual = createHash("sha256").update(content).digest("hex");
    return actual === expected;
  }

  async stat(relativePath: string): Promise<{ size: number; mtime: Date } | null> {
    const path = this.resolvePath(relativePath);
    try {
      const s = await stat(path);
      return { size: s.size, mtime: s.mtime };
    } catch {
      return null;
    }
  }
}
