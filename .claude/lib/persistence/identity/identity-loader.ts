/**
 * Identity Loader — parse and watch BEAUVOIR.md identity documents.
 *
 * Extracted from deploy/loa-identity/identity-loader.ts.
 * Portable: constructor-injected paths, no process.env.
 * Adds hot-reload via FileWatcher integration.
 *
 * @module .claude/lib/persistence/identity/identity-loader
 */

import { createHash } from "crypto";
import { existsSync } from "fs";
import { readFile, appendFile } from "fs/promises";
import { PersistenceError } from "../types.js";
import { FileWatcher, type FileChangeCallback } from "./file-watcher.js";

// ── Types ──────────────────────────────────────────────────

export interface Principle {
  id: number;
  name: string;
  description: string;
  inPractice?: string;
}

export interface Boundary {
  type: "will_not" | "always";
  items: string[];
}

export interface IdentityDocument {
  version: string;
  lastUpdated: string;
  corePrinciples: Principle[];
  boundaries: Boundary[];
  interactionStyle: string[];
  recoveryProtocol: string;
  checksum: string;
}

export interface IdentityLoaderConfig {
  beauvoirPath: string;
  notesPath: string;
  /** Debounce for hot-reload watcher (default: 1000ms) */
  watchDebounceMs?: number;
}

// ── Implementation ─────────────────────────────────────────

export class IdentityLoader {
  private config: IdentityLoaderConfig;
  private identity: IdentityDocument | null = null;
  private lastLoadedChecksum: string | null = null;
  private watcher: FileWatcher | null = null;

  constructor(config: IdentityLoaderConfig) {
    this.config = config;
  }

  /**
   * Load identity from BEAUVOIR.md.
   */
  async load(): Promise<IdentityDocument> {
    if (!existsSync(this.config.beauvoirPath)) {
      throw new PersistenceError(
        "IDENTITY_PARSE_FAILED",
        `BEAUVOIR.md not found at ${this.config.beauvoirPath}`,
      );
    }

    const content = await readFile(this.config.beauvoirPath, "utf-8");
    const checksum = this.computeChecksum(content);

    if (this.lastLoadedChecksum && this.lastLoadedChecksum !== checksum) {
      await this.logIdentityChange(checksum);
    }

    const identity = this.parseDocument(content, checksum);
    this.identity = identity;
    this.lastLoadedChecksum = checksum;

    return identity;
  }

  /**
   * Start watching BEAUVOIR.md for changes. Reloads automatically on change.
   */
  startWatching(callback?: FileChangeCallback): void {
    if (this.watcher) {
      this.watcher.stop();
    }

    this.watcher = new FileWatcher({
      filePath: this.config.beauvoirPath,
      debounceMs: this.config.watchDebounceMs ?? 1000,
    });

    this.watcher.start(async (filePath) => {
      try {
        await this.load();
        if (callback) {
          await callback(filePath);
        }
      } catch {
        // Keep previous state on corrupt file
      }
    });
  }

  /**
   * Stop watching.
   */
  stopWatching(): void {
    if (this.watcher) {
      this.watcher.stop();
      this.watcher = null;
    }
  }

  /**
   * Check if identity document has changed on disk.
   */
  async hasChanged(): Promise<boolean> {
    if (!existsSync(this.config.beauvoirPath)) {
      return true;
    }
    const content = await readFile(this.config.beauvoirPath, "utf-8");
    return this.computeChecksum(content) !== this.lastLoadedChecksum;
  }

  /**
   * Load raw file content without parsing (finn's simpler use case).
   */
  async loadRaw(): Promise<string> {
    if (!existsSync(this.config.beauvoirPath)) {
      throw new PersistenceError(
        "IDENTITY_PARSE_FAILED",
        `BEAUVOIR.md not found at ${this.config.beauvoirPath}`,
      );
    }
    return readFile(this.config.beauvoirPath, "utf-8");
  }

  getIdentity(): IdentityDocument | null {
    return this.identity;
  }

  getPrinciple(id: number): Principle | undefined {
    return this.identity?.corePrinciples.find((p) => p.id === id);
  }

  getBoundaries(type: "will_not" | "always"): string[] {
    const boundary = this.identity?.boundaries.find((b) => b.type === type);
    return boundary?.items ?? [];
  }

  validate(): { valid: boolean; issues: string[] } {
    const issues: string[] = [];
    if (!this.identity) {
      return { valid: false, issues: ["Identity not loaded"] };
    }
    if (this.identity.corePrinciples.length === 0) issues.push("No core principles found");
    if (this.identity.boundaries.length === 0) issues.push("No boundaries defined");
    if (this.identity.interactionStyle.length === 0) issues.push("No interaction style defined");
    if (!this.identity.recoveryProtocol) issues.push("No recovery protocol defined");
    return { valid: issues.length === 0, issues };
  }

  // ── Private ──────────────────────────────────────────────

  private parseDocument(content: string, checksum: string): IdentityDocument {
    const versionMatch = content.match(/\*\*Version\*\*:\s*(\S+)/);
    const version = versionMatch?.[1] ?? "0.0.0";

    const updatedMatch = content.match(/\*\*Last Updated\*\*:\s*(\S+)/);
    const lastUpdated = updatedMatch?.[1] ?? new Date().toISOString().split("T")[0];

    return {
      version,
      lastUpdated,
      corePrinciples: this.parsePrinciples(content),
      boundaries: this.parseBoundaries(content),
      interactionStyle: this.parseInteractionStyle(content),
      recoveryProtocol: this.parseRecoveryProtocol(content),
      checksum,
    };
  }

  private parsePrinciples(content: string): Principle[] {
    const principles: Principle[] = [];
    const re = /###\s*(\d+)\.\s*([^\n]+)\n\n([^#]+?)(?=###|\n---|\n##|$)/g;
    let match;

    while ((match = re.exec(content)) !== null) {
      const id = parseInt(match[1], 10);
      const name = match[2].trim();
      const body = match[3].trim();

      const inPracticeMatch = body.match(/\*\*In practice\*\*:\s*([^*]+)/);
      let description = body;
      if (inPracticeMatch) {
        description = body.substring(0, body.indexOf("**In practice**")).trim();
      }
      const explanationMatch = description.match(/\*\*([^*]+)\*\*/);
      if (explanationMatch) {
        description = explanationMatch[1];
      }

      principles.push({
        id,
        name,
        description,
        inPractice: inPracticeMatch?.[1]?.trim(),
      });
    }

    return principles;
  }

  private parseBoundaries(content: string): Boundary[] {
    const boundaries: Boundary[] = [];

    const willNotMatch = content.match(/###\s*What I Won't Do\n\n([\s\S]*?)(?=###|---|##|$)/);
    if (willNotMatch) {
      const items = this.parseListItems(willNotMatch[1]);
      if (items.length > 0) boundaries.push({ type: "will_not", items });
    }

    const alwaysMatch = content.match(/###\s*What I Always Do\n\n([\s\S]*?)(?=###|---|##|$)/);
    if (alwaysMatch) {
      const items = this.parseListItems(alwaysMatch[1]);
      if (items.length > 0) boundaries.push({ type: "always", items });
    }

    return boundaries;
  }

  private parseInteractionStyle(content: string): string[] {
    const styles: string[] = [];
    const styleMatch = content.match(/##\s*Interaction Style\n\n([\s\S]*?)(?=\n## [^#]|\n---|$)/);
    if (styleMatch) {
      const re = /###\s*([^\n]+)/g;
      let match;
      while ((match = re.exec(styleMatch[1])) !== null) {
        styles.push(match[1].trim());
      }
    }
    return styles;
  }

  private parseRecoveryProtocol(content: string): string {
    const protocolMatch = content.match(
      /##\s*Recovery Protocol\n\n([\s\S]*?)(?=\n## [^#]|\n---|$)/,
    );
    if (protocolMatch) {
      const codeMatch = protocolMatch[1].match(/```([\s\S]*?)```/);
      if (codeMatch) return codeMatch[1].trim();
    }
    return "";
  }

  private parseListItems(text: string): string[] {
    const items: string[] = [];
    const re = /^\s*(?:\d+\.|[-*])\s*\*\*([^*]+)\*\*\s*[-–]?\s*(.*)$/gm;
    let match;
    while ((match = re.exec(text)) !== null) {
      const title = match[1].trim();
      const desc = match[2].trim();
      items.push(desc ? `${title}: ${desc}` : title);
    }
    return items;
  }

  private async logIdentityChange(newChecksum: string): Promise<void> {
    const timestamp = new Date().toISOString();
    const logEntry = `\n## [Identity Change] ${timestamp}\n\n- Previous checksum: ${this.lastLoadedChecksum}\n- New checksum: ${newChecksum}\n- Document reloaded\n`;

    try {
      if (existsSync(this.config.notesPath)) {
        await appendFile(this.config.notesPath, logEntry, "utf-8");
      }
    } catch {
      // Non-fatal
    }
  }

  private computeChecksum(content: string): string {
    return createHash("sha256").update(content).digest("hex").substring(0, 16);
  }
}

/** Create an IdentityLoader with default paths. */
export function createIdentityLoader(basePath: string): IdentityLoader {
  return new IdentityLoader({
    beauvoirPath: `${basePath}/grimoires/loa/BEAUVOIR.md`,
    notesPath: `${basePath}/grimoires/loa/NOTES.md`,
  });
}
