#!/usr/bin/env node
/**
 * test_loa_guards.mjs — smoke test for the OMP guard adapter.
 *
 * Drives mock OMP `tool_call` events through the adapter's registered handler
 * and asserts block/allow. Requires a Loa install (the canonical bash guards)
 * at --root or the repo root. Node 18+ (uses node: builtins, dynamic import of
 * the .ts adapter via a runtime that strips types — run with `bun` or a
 * ts-capable node; falls back to skipping if the .ts cannot be imported).
 *
 * Usage:  bun grimoires/loa/proposals/omp-harness-support/kit/tests/test_loa_guards.mjs [--root PATH]
 */
import { existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const argRoot = process.argv.includes("--root") ? process.argv[process.argv.indexOf("--root") + 1] : null;
const ROOT = argRoot ? resolve(argRoot) : resolve(HERE, "../../../../../.."); // repo root from kit/tests/

const guard = resolve(ROOT, ".claude/hooks/safety/block-destructive-bash.sh");
if (!existsSync(guard)) {
  console.error(`SKIP: canonical guards not found at ${guard} (run from a Loa install, or pass --root)`);
  process.exit(0);
}

// The adapter resolves ROOT from cwd; run the test from the repo root.
process.chdir(ROOT);
const adapterPath = resolve(HERE, "../hooks/pre/loa-guards.ts");
const mod = await import(adapterPath + "?t=" + Date.now());

let handler;
mod.default({ on: (ev, fn) => { if (ev === "tool_call") handler = fn; } });
if (!handler) { console.error("FAIL: adapter did not register a tool_call handler"); process.exit(1); }

const drive = async (toolName, input) => (await handler({ toolName, input }, {})) || { allow: true };

let pass = 0, fail = 0;
async function expect(label, got, wantBlock) {
  const isBlock = !!got.block;
  const ok = isBlock === wantBlock;
  console.log(`${ok ? "PASS" : "FAIL"}  ${label}  → ${isBlock ? "block: " + got.reason : "allow"}`);
  ok ? pass++ : fail++;
}

await expect("bash rm -rf /  (expect BLOCK)", await drive("bash", { command: "rm -rf /" }), true);
await expect("bash ls -la    (expect ALLOW)", await drive("bash", { command: "ls -la" }), false);
await expect("write grimoires/x.md (expect ALLOW)", await drive("write", { path: "grimoires/x.md" }), false);
// edit path parse: the adapter must extract the path from the hashline header
const editGot = await drive("edit", { input: "[grimoires/x.md#AB12]\nSWAP 1.=1:\n+x" });
await expect("edit hashline parse (no throw, decision returned)", editGot, !!editGot.block);

console.log(`\n${pass}/${pass + fail} passed`);
process.exit(fail === 0 ? 0 : 1);
