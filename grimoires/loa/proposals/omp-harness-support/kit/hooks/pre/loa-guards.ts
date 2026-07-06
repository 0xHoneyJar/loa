/**
 * loa-guards.ts — OMP PreToolUse adapter for Loa's Claude-format safety guards.
 *
 * WHY: OMP ("Oh My Pi", Pi lineage) does NOT discover or execute Loa's
 * `.claude/settings.json` shell hooks. There is no `.claude/hooks` discovery
 * provider in OMP, and OMP hooks are in-process TS/JS factory modules under
 * `.omp/hooks/pre|post/`, not settings.json shell commands (see
 * `omp://hooks.md`, `omp://config-usage.md`). Verified empirically: an OMP
 * Write/Edit produced zero `.run/audit.jsonl` entries while concurrent Claude
 * sessions logged theirs. So every Loa PreToolUse guard is INERT under OMP.
 *
 * This factory restores enforcement by translating OMP `tool_call` events into
 * the Claude PreToolUse wire contract and shelling the *canonical* guard
 * scripts verbatim — the bash guards stay the single source of policy truth;
 * this file is a thin adapter (same pattern as the worldline kit's
 * portable_gate.sh).
 *
 * Claude PreToolUse contract the guards expect:
 *   stdin  = {"tool_name": "...", "tool_input": {"command"|"file_path": ...}}
 *   env    = CLAUDE_TOOL_NAME, CLAUDE_TOOL_INPUT, CLAUDE_TOOL_FILE_PATH,
 *            CLAUDE_PROJECT_DIR
 *   exit 2 = BLOCK · exit 0 = ALLOW · other = non-blocking (allow)
 *
 * OMP tool → guard map:
 *   bash        → .claude/hooks/safety/block-destructive-bash.sh   (input.command)
 *   write/edit  → .claude/hooks/safety/zone-write-guard.sh         (System-Zone)
 * Extend GUARDS to bridge more (team-role-guard, spiral-dispatch-guard, …).
 *
 * Placement: <repo>/.omp/hooks/pre/loa-guards.ts (native, priority 100).
 * Loaded by OMP at startup; active next session.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";

// Nearest ancestor of cwd carrying the guard scripts. LOA_PROJECT_DIR wins.
function projectRoot(): string {
  const env = process.env.LOA_PROJECT_DIR || process.env.CLAUDE_PROJECT_DIR;
  if (env && existsSync(env)) return env;
  let dir = process.cwd();
  for (;;) {
    if (existsSync(resolve(dir, ".claude/hooks/safety/zone-write-guard.sh"))) return dir;
    const up = dirname(dir);
    if (up === dir) break;
    dir = up;
  }
  return process.cwd();
}

const ROOT = projectRoot();

// Extract every target path from a hashline `edit` input ([PATH#TAG] headers).
function hashlinePaths(input: string): string[] {
  const out: string[] = [];
  const re = /\[([^\[\]\n]+?)#[0-9A-Fa-f]{4}\]/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(input)) !== null) out.push(m[1]);
  return out;
}

// One guard invocation. Returns a block reason, or null to allow.
function runGuard(script: string, claudeTool: string, toolInput: Record<string, unknown>): string | null {
  const scriptPath = resolve(ROOT, script);
  if (!existsSync(scriptPath)) return null; // guard not installed → allow
  const payload = JSON.stringify({ tool_name: claudeTool, tool_input: toolInput });
  const filePath = typeof toolInput.file_path === "string" ? toolInput.file_path : "";
  let res;
  try {
    res = spawnSync("bash", [scriptPath], {
      input: payload,
      cwd: ROOT,
      timeout: 5000,
      encoding: "utf8",
      env: {
        ...process.env,
        CLAUDE_TOOL_NAME: claudeTool,
        CLAUDE_TOOL_INPUT: payload,
        CLAUDE_TOOL_FILE_PATH: filePath,
        CLAUDE_PROJECT_DIR: ROOT,
      },
    });
  } catch {
    return null; // infra failure → fail-open (do not brick the session)
  }
  if (res.status === 2) {
    const reason = (res.stderr || res.stdout || "").toString().trim();
    const name = script.split("/").pop();
    return `[loa:${name}] ${reason || "blocked by Loa safety policy"}`;
  }
  return null; // exit 0 or non-blocking error → allow
}

export default function loaGuards(pi: ExtensionAPI): void {
  pi.on("tool_call", async (event) => {
    const tool = String(event.toolName || "").toLowerCase();
    const input = (event.input ?? {}) as Record<string, unknown>;

    // bash → destructive-command guard
    if (tool === "bash") {
      const command = String(input.command ?? "");
      if (!command) return;
      const reason = runGuard(".claude/hooks/safety/block-destructive-bash.sh", "Bash", { command });
      if (reason) return { block: true, reason };
      return;
    }

    // write / edit → System-Zone write guard (one check per target path)
    if (tool === "write" || tool === "edit") {
      let paths: string[] = [];
      if (tool === "write") {
        const p = input.path ?? input.file_path;
        if (typeof p === "string" && p) paths = [p];
      } else {
        paths = hashlinePaths(String(input.input ?? ""));
      }
      for (const p of paths) {
        const abs = isAbsolute(p) ? p : resolve(ROOT, p);
        const reason = runGuard(".claude/hooks/safety/zone-write-guard.sh", "Write", { file_path: abs });
        if (reason) return { block: true, reason };
      }
      return;
    }
  });
}
