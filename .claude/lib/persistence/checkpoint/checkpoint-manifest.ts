/**
 * Checkpoint Manifest — tracks checkpoint state and version.
 */

import { createHash } from "crypto";

export interface CheckpointManifest {
  version: number;
  createdAt: string;
  files: CheckpointFileEntry[];
  totalSize: number;
  checksum: string; // SHA-256 of all file checksums concatenated
}

export interface CheckpointFileEntry {
  relativePath: string;
  size: number;
  checksum: string; // SHA-256 of file content
}

export interface WriteIntent {
  id: string;
  startedAt: string;
  files: string[];
  pid: number;
}

/**
 * Create a manifest from a list of file entries.
 */
export function createManifest(
  files: CheckpointFileEntry[],
  previousVersion?: number,
): CheckpointManifest {
  const totalSize = files.reduce((sum, f) => sum + f.size, 0);
  const checksumInput = files
    .map((f) => f.checksum)
    .sort()
    .join("");
  const checksum = createHash("sha256").update(checksumInput).digest("hex");

  return {
    version: (previousVersion ?? 0) + 1,
    createdAt: new Date().toISOString(),
    files,
    totalSize,
    checksum,
  };
}

/**
 * Verify manifest integrity.
 */
export function verifyManifest(manifest: CheckpointManifest): boolean {
  const checksumInput = manifest.files
    .map((f) => f.checksum)
    .sort()
    .join("");
  const expected = createHash("sha256").update(checksumInput).digest("hex");
  return expected === manifest.checksum;
}
