/**
 * Legba Sandbox Executor
 *
 * Wraps Cloudflare Sandbox SDK for Loa-specific execution patterns.
 */

import { detectCircuitBreaker, type CircuitBreakerResult } from './circuit-breaker.js';
import { type Storage } from './storage.js';
import {
  validateProjectId,
  validateSessionId,
  validateBranchName,
  validateSprintNumber,
  sanitizeForShell,
  sanitizeEnvValue,
  escapeShellArg,
  redactSecrets,
} from './validation.js';

/**
 * Sandbox SDK types (from @cloudflare/sandbox-sdk)
 */
export interface Sandbox {
  exec(command: string, options?: ExecOptions): Promise<ExecResult>;
  gitCheckout(repo: string, options?: GitCheckoutOptions): Promise<void>;
  setEnvVars(vars: Record<string, string>): Promise<void>;
  readFile(path: string): Promise<string>;
  writeFile(path: string, content: string): Promise<void>;
  listDir(path: string): Promise<string[]>;
  destroy(): Promise<void>;
}

export interface ExecOptions {
  timeout?: number;
  cwd?: string;
}

export interface ExecResult {
  exitCode: number;
  stdout: string;
  stderr: string;
}

export interface GitCheckoutOptions {
  targetDir?: string;
  branch?: string;
  depth?: number;
}

export interface SandboxBinding {
  create(options?: SandboxCreateOptions): Promise<Sandbox>;
}

export interface SandboxCreateOptions {
  mounts?: Array<{
    bucket: unknown;
    path: string;
  }>;
}

/**
 * Configuration for execution
 */
export interface ExecutionConfig {
  /** Session ID */
  sessionId: string;

  /** Project ID */
  project: string;

  /** Sprint number */
  sprint: number;

  /** Git branch */
  branch: string;

  /** Repository URL */
  repoUrl: string;

  /** R2 bucket reference */
  r2Bucket: unknown;

  /** Anthropic API key */
  anthropicKey: string;

  /** GitHub token for PR operations */
  githubToken: string;

  /** Execution timeout in milliseconds (default: 8 hours) */
  timeout?: number;
}

/**
 * Result of execution
 */
export interface ExecutionResult {
  /** Whether execution completed successfully */
  success: boolean;

  /** Combined stdout/stderr logs */
  logs: string;

  /** Git diff of changes */
  diff: string;

  /** Circuit breaker detection result */
  circuitBreaker: CircuitBreakerResult;

  /** Exit code from Claude Code */
  exitCode: number;

  /** Execution duration in milliseconds */
  duration: number;
}

/**
 * Paths within the sandbox
 */
const SANDBOX_PATHS = {
  mount: '/mnt/legba',
  worktree: (project: string, branch: string) =>
    `/mnt/legba/worktrees/${project}/${branch}`,
  state: (project: string) => `/mnt/legba/state/${project}`,
};

/**
 * Default timeout: 8 hours
 */
const DEFAULT_TIMEOUT = 8 * 60 * 60 * 1000;

/**
 * Sandbox Executor
 *
 * Executes Claude Code with Loa in an isolated Cloudflare Sandbox.
 */
export class SandboxExecutor {
  constructor(
    private sandboxBinding: SandboxBinding,
    private storage: Storage
  ) {}

  /**
   * Execute a Loa sprint in the sandbox
   */
  async execute(config: ExecutionConfig): Promise<ExecutionResult> {
    const startTime = Date.now();
    let sandbox: Sandbox | null = null;

    // C-002 FIX: Validate all user-derived inputs before sandbox execution
    this.validateConfig(config);

    try {
      // 1. Create sandbox with R2 mount
      sandbox = await this.sandboxBinding.create({
        mounts: [
          {
            bucket: config.r2Bucket,
            path: SANDBOX_PATHS.mount,
          },
        ],
      });

      // 2. C-002 FIX: Set environment variables with sanitized user-derived values
      // API keys are passed as-is (they come from validated env vars)
      // User-derived values (project, session, sprint) are sanitized
      await sandbox.setEnvVars({
        ANTHROPIC_API_KEY: config.anthropicKey,
        GITHUB_TOKEN: config.githubToken,
        // C-002 FIX: Sanitize user-derived values to prevent shell metacharacter injection
        PROJECT_NAME: sanitizeForShell(config.project),
        SPRINT_NUMBER: config.sprint.toString(), // Already validated as integer
        SESSION_ID: config.sessionId, // Already validated as UUID format
        // Disable interactive prompts
        CI: 'true',
        TERM: 'dumb',
      });

      // 3. Clone repository with shallow clone for speed
      // C-002 FIX: Use sanitized values for path construction
      const sanitizedProject = sanitizeForShell(config.project);
      const sanitizedBranch = sanitizeForShell(config.branch);
      const worktreePath = SANDBOX_PATHS.worktree(sanitizedProject, sanitizedBranch);

      await sandbox.gitCheckout(config.repoUrl, {
        targetDir: worktreePath,
        branch: config.branch, // Git handles branch names safely
        depth: 1,
      });

      // 4. Restore project state from previous sessions
      await this.restoreState(sandbox, config);

      // 5. Build the system prompt for Legba context
      const systemPrompt = this.buildSystemPrompt(config);

      // 6. M-003 FIX: Execute Claude Code with properly escaped command
      const command = this.buildClaudeCommand(systemPrompt, config.sprint, worktreePath);
      const timeout = config.timeout ?? DEFAULT_TIMEOUT;

      const result = await sandbox.exec(command, { timeout });

      // 7. Persist state after execution
      await this.persistState(sandbox, config);

      // 8. M-003 FIX: Use escaped path in git diff command
      const escapedWorktreePath = escapeShellArg(worktreePath);
      const diffResult = await sandbox.exec(
        `cd ${escapedWorktreePath} && git diff HEAD`,
        { timeout: 30000 }
      );

      // 9. Detect circuit breaker
      const combinedOutput = result.stdout + result.stderr;
      const circuitBreaker = detectCircuitBreaker(combinedOutput);

      // M-002 FIX: Redact secrets from logs before returning
      const sanitizedLogs = redactSecrets(combinedOutput);

      return {
        success: result.exitCode === 0 && !circuitBreaker.tripped,
        logs: sanitizedLogs,
        diff: diffResult.stdout,
        circuitBreaker,
        exitCode: result.exitCode,
        duration: Date.now() - startTime,
      };
    } finally {
      // L-003 FIX: Log cleanup errors instead of silently ignoring
      if (sandbox) {
        try {
          await sandbox.destroy();
        } catch (cleanupError) {
          // Log the error for monitoring but don't fail the operation
          console.error('Sandbox cleanup failed:', cleanupError instanceof Error ? cleanupError.message : 'Unknown error');
        }
      }
    }
  }

  /**
   * C-002 FIX: Validate execution configuration before sandbox operations
   */
  private validateConfig(config: ExecutionConfig): void {
    // Validate project ID
    const projectValidation = validateProjectId(config.project);
    if (!projectValidation.valid) {
      throw new Error(`Invalid project ID: ${projectValidation.error}`);
    }

    // Validate session ID (UUID format)
    const sessionValidation = validateSessionId(config.sessionId);
    if (!sessionValidation.valid) {
      throw new Error(`Invalid session ID: ${sessionValidation.error}`);
    }

    // Validate branch name
    const branchValidation = validateBranchName(config.branch);
    if (!branchValidation.valid) {
      throw new Error(`Invalid branch name: ${branchValidation.error}`);
    }

    // L-002 FIX: Validate sprint number range
    const sprintValidation = validateSprintNumber(config.sprint);
    if (!sprintValidation.valid) {
      throw new Error(`Invalid sprint number: ${sprintValidation.error}`);
    }
  }

  /**
   * Restore project state (NOTES.md, grimoires/, .beads/) from R2 to sandbox
   */
  private async restoreState(sandbox: Sandbox, config: ExecutionConfig): Promise<void> {
    const worktreePath = SANDBOX_PATHS.worktree(config.project, config.branch);

    // Check if we have saved state
    const hasState = await this.storage.hasProjectState(config.project);
    if (!hasState) {
      // First session, no state to restore
      return;
    }

    // Get state files from R2
    const stateFiles = await this.storage.getProjectState(config.project);

    // Write files to sandbox
    for (const [path, content] of stateFiles) {
      const fullPath = `${worktreePath}/${path}`;

      // Ensure parent directory exists
      const dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
      await sandbox.exec(`mkdir -p ${dir}`);

      // Write file
      await sandbox.writeFile(fullPath, content);
    }
  }

  /**
   * Persist project state from sandbox to R2
   */
  private async persistState(sandbox: Sandbox, config: ExecutionConfig): Promise<void> {
    const worktreePath = SANDBOX_PATHS.worktree(config.project, config.branch);
    const stateFiles = new Map<string, string>();

    // Files to persist
    const statePaths = [
      'grimoires/loa/NOTES.md',
      'grimoires/loa/prd.md',
      'grimoires/loa/sdd.md',
      'grimoires/loa/sprint.md',
      'grimoires/loa/ledger.json',
    ];

    // Also persist grimoires/loa/a2a/ directory
    const a2aPath = `${worktreePath}/grimoires/loa/a2a`;
    try {
      const a2aFiles = await this.listFilesRecursive(sandbox, a2aPath);
      for (const file of a2aFiles) {
        const relativePath = file.substring(worktreePath.length + 1);
        statePaths.push(relativePath);
      }
    } catch {
      // a2a directory may not exist yet
    }

    // Read each file and add to state
    for (const path of statePaths) {
      try {
        const content = await sandbox.readFile(`${worktreePath}/${path}`);
        stateFiles.set(path, content);
      } catch {
        // File may not exist, skip it
      }
    }

    // Save to R2
    await this.storage.saveProjectState(config.project, stateFiles);
  }

  /**
   * Recursively list files in a directory
   */
  private async listFilesRecursive(sandbox: Sandbox, path: string): Promise<string[]> {
    const files: string[] = [];

    const entries = await sandbox.listDir(path);
    for (const entry of entries) {
      const fullPath = `${path}/${entry}`;

      // Check if directory
      try {
        await sandbox.listDir(fullPath);
        // It's a directory, recurse
        const subFiles = await this.listFilesRecursive(sandbox, fullPath);
        files.push(...subFiles);
      } catch {
        // It's a file
        files.push(fullPath);
      }
    }

    return files;
  }

  /**
   * Build the system prompt for Legba context
   */
  private buildSystemPrompt(config: ExecutionConfig): string {
    return `
You are running in Legba autonomous mode.

Session ID: ${config.sessionId}
Project: ${config.project}
Sprint: ${config.sprint}
Branch: ${config.branch}

CRITICAL INSTRUCTIONS:
1. Do NOT commit changes directly to git
2. Do NOT push to remote
3. All changes will be collected as a diff and submitted via PR
4. If you encounter repeated failures, the circuit breaker will pause the session
5. Focus on completing the sprint tasks as defined in sprint.md
6. Update NOTES.md with progress and decisions
7. Do not use interactive commands - this is a headless environment

The session will be managed by Legba. Your output will be captured and used
to create a draft PR for human review.
`.trim();
  }

  /**
   * M-003 FIX: Build the claude command for execution with proper escaping
   */
  private buildClaudeCommand(systemPrompt: string, sprint: number, cwd: string): string {
    // Use escapeShellArg for all dynamic values
    const escapedCwd = escapeShellArg(cwd);
    const escapedPrompt = escapeShellArg(systemPrompt);
    const escapedCommand = escapeShellArg(`/run sprint-${sprint}`);

    return `cd ${escapedCwd} && claude --append-system-prompt ${escapedPrompt} -p ${escapedCommand} --permission-mode acceptEdits`;
  }
}

/**
 * Create a sandbox executor
 */
export function createSandboxExecutor(
  sandboxBinding: SandboxBinding,
  storage: Storage
): SandboxExecutor {
  return new SandboxExecutor(sandboxBinding, storage);
}
