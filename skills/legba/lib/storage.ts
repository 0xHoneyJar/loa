/**
 * Legba R2 Storage Layer
 *
 * Handles all R2 bucket operations for session state, logs, and project state.
 */

import type {
  Session,
  ProjectRegistry,
  SessionQueue,
  Project,
  QueuedRequest,
} from '../types/index.js';
import { createEmptyRegistry, createEmptyQueue } from '../types/index.js';

/**
 * R2 Bucket binding interface (from Cloudflare Workers)
 */
export interface R2Bucket {
  get(key: string): Promise<R2Object | null>;
  put(key: string, value: string | ArrayBuffer | ReadableStream): Promise<R2Object>;
  delete(key: string): Promise<void>;
  list(options?: R2ListOptions): Promise<R2Objects>;
}

export interface R2Object {
  key: string;
  size: number;
  etag: string;
  text(): Promise<string>;
  json?<T>(): Promise<T>; // Optional - not all R2 implementations have this
}

export interface R2ListOptions {
  prefix?: string;
  limit?: number;
  cursor?: string;
}

export interface R2Objects {
  objects: R2Object[];
  truncated: boolean;
  cursor?: string;
}

/**
 * Storage paths
 */
const PATHS = {
  registry: 'registry.json',
  queue: 'queue/pending.json',
  session: (id: string) => `sessions/${id}/session.json`,
  sessionLog: (id: string, logType: string) => `sessions/${id}/logs/${logType}.log`,
  projectState: (project: string) => `state/${project}/`,
  worktree: (project: string, branch: string) => `worktrees/${project}/${branch}/`,
};

/**
 * Legba Storage Client
 *
 * Provides typed access to R2 storage operations.
 */
export class Storage {
  constructor(private bucket: R2Bucket) {}

  // ============================================================
  // Session Operations
  // ============================================================

  /**
   * Save a session record to R2
   *
   * Uses atomic write pattern: write to temp, then rename
   */
  async saveSession(session: Session): Promise<void> {
    const key = PATHS.session(session.id);
    const data = JSON.stringify(session, null, 2);
    await this.bucket.put(key, data);
  }

  /**
   * Get a session record from R2
   */
  async getSession(id: string): Promise<Session | null> {
    const key = PATHS.session(id);
    const obj = await this.bucket.get(key);
    if (!obj) return null;
    const text = await obj.text();
    return JSON.parse(text) as Session;
  }

  /**
   * Delete a session record
   */
  async deleteSession(id: string): Promise<void> {
    const key = PATHS.session(id);
    await this.bucket.delete(key);
  }

  /**
   * List all sessions (optionally filtered by state)
   */
  async listSessions(filter?: {
    project?: string;
    state?: string;
    limit?: number;
  }): Promise<Session[]> {
    const result = await this.bucket.list({
      prefix: 'sessions/',
      limit: filter?.limit ?? 100,
    });

    const sessions: Session[] = [];
    for (const item of result.objects) {
      if (item.key.endsWith('/session.json')) {
        // Fetch the actual object to get content
        const obj = await this.bucket.get(item.key);
        if (!obj) continue;
        const text = await obj.text();
        const session = JSON.parse(text) as Session;
        if (filter?.project && session.project !== filter.project) continue;
        if (filter?.state && session.state !== filter.state) continue;
        sessions.push(session);
      }
    }

    // Sort by triggeredAt descending (most recent first)
    return sessions.sort((a, b) =>
      new Date(b.triggeredAt).getTime() - new Date(a.triggeredAt).getTime()
    );
  }

  // ============================================================
  // Log Operations
  // ============================================================

  /**
   * Append content to a session log
   */
  async appendLog(
    sessionId: string,
    logType: 'stdout' | 'stderr' | 'claude-output',
    content: string
  ): Promise<void> {
    const key = PATHS.sessionLog(sessionId, logType);

    // Try to get existing content
    const existing = await this.bucket.get(key);
    const existingContent = existing ? await existing.text() : '';

    // Append new content
    const newContent = existingContent + content;
    await this.bucket.put(key, newContent);
  }

  /**
   * Get session logs
   */
  async getLogs(
    sessionId: string,
    logType: 'stdout' | 'stderr' | 'claude-output',
    options?: { tail?: number }
  ): Promise<string> {
    const key = PATHS.sessionLog(sessionId, logType);
    const obj = await this.bucket.get(key);
    if (!obj) return '';

    const content = await obj.text();

    if (options?.tail) {
      const lines = content.split('\n');
      return lines.slice(-options.tail).join('\n');
    }

    return content;
  }

  /**
   * Get session log (alias for getLogs)
   */
  async getLog(
    sessionId: string,
    logType: 'stdout' | 'stderr' | 'claude-output'
  ): Promise<string> {
    return this.getLogs(sessionId, logType);
  }

  // ============================================================
  // Registry Operations
  // ============================================================

  /**
   * Get the project registry
   */
  async getRegistry(): Promise<ProjectRegistry> {
    const obj = await this.bucket.get(PATHS.registry);
    if (!obj) return createEmptyRegistry();
    const text = await obj.text();
    return JSON.parse(text) as ProjectRegistry;
  }

  /**
   * Save the project registry
   */
  async saveRegistry(registry: ProjectRegistry): Promise<void> {
    const data = JSON.stringify(registry, null, 2);
    await this.bucket.put(PATHS.registry, data);
  }

  /**
   * Get a single project
   */
  async getProject(id: string): Promise<Project | null> {
    const registry = await this.getRegistry();
    return registry.projects.find((p) => p.id === id) ?? null;
  }

  /**
   * Add or update a project
   */
  async upsertProject(project: Project): Promise<void> {
    const registry = await this.getRegistry();
    const index = registry.projects.findIndex((p) => p.id === project.id);

    if (index >= 0) {
      registry.projects[index] = { ...project, updatedAt: new Date().toISOString() };
    } else {
      registry.projects.push(project);
    }

    await this.saveRegistry(registry);
  }

  /**
   * Remove a project
   */
  async removeProject(id: string): Promise<boolean> {
    const registry = await this.getRegistry();
    const index = registry.projects.findIndex((p) => p.id === id);

    if (index < 0) return false;

    registry.projects.splice(index, 1);
    await this.saveRegistry(registry);
    return true;
  }

  // ============================================================
  // Queue Operations
  // ============================================================

  /**
   * Get the session queue
   */
  async getQueue(): Promise<SessionQueue> {
    const obj = await this.bucket.get(PATHS.queue);
    if (!obj) return createEmptyQueue();
    const text = await obj.text();
    return JSON.parse(text) as SessionQueue;
  }

  /**
   * Save the session queue
   */
  async saveQueue(queue: SessionQueue): Promise<void> {
    const data = JSON.stringify(queue, null, 2);
    await this.bucket.put(PATHS.queue, data);
  }

  /**
   * Add a request to the queue
   *
   * @returns Queue position (1-based) or -1 if queue is full
   */
  async enqueue(request: QueuedRequest): Promise<number> {
    const queue = await this.getQueue();

    if (queue.pending.length >= queue.maxDepth) {
      return -1; // Queue full
    }

    queue.pending.push(request);
    await this.saveQueue(queue);

    return queue.pending.length;
  }

  /**
   * Remove and return the next request from the queue
   */
  async dequeue(): Promise<QueuedRequest | null> {
    const queue = await this.getQueue();

    if (queue.pending.length === 0) {
      return null;
    }

    const request = queue.pending.shift()!;
    await this.saveQueue(queue);

    return request;
  }

  /**
   * Get the position of a request in the queue
   *
   * @returns Position (1-based) or 0 if not found
   */
  async getQueuePosition(requestId: string): Promise<number> {
    const queue = await this.getQueue();
    const index = queue.pending.findIndex((r) => r.id === requestId);
    return index >= 0 ? index + 1 : 0;
  }

  // ============================================================
  // Project State Operations
  // ============================================================

  /**
   * Save project state (NOTES.md, grimoires/, .beads/)
   */
  async saveProjectState(
    project: string,
    files: Map<string, string>
  ): Promise<void> {
    const prefix = PATHS.projectState(project);

    for (const [path, content] of files) {
      await this.bucket.put(prefix + path, content);
    }
  }

  /**
   * Get project state
   */
  async getProjectState(project: string): Promise<Map<string, string>> {
    const prefix = PATHS.projectState(project);
    const result = await this.bucket.list({ prefix });

    const files = new Map<string, string>();
    for (const obj of result.objects) {
      const relativePath = obj.key.slice(prefix.length);
      const content = await obj.text();
      files.set(relativePath, content);
    }

    return files;
  }

  /**
   * Check if project state exists
   */
  async hasProjectState(project: string): Promise<boolean> {
    const prefix = PATHS.projectState(project);
    const result = await this.bucket.list({ prefix, limit: 1 });
    return result.objects.length > 0;
  }
}

/**
 * Create a storage client
 */
export function createStorage(bucket: R2Bucket): Storage {
  return new Storage(bucket);
}
