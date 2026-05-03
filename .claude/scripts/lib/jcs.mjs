// =============================================================================
// jcs.mjs — RFC 8785 JCS canonicalization for Node callers.
//
// cycle-098 Sprint 1 (IMP-001 HIGH_CONSENSUS 736). Wraps the `canonicalize` npm
// package, which implements RFC 8785 §3.2.2 (number canonicalization via
// ECMAScript ToNumber) and §3.2.3 (string escaping). Per SDD §2.2 stack table,
// `jq -S -c` is NOT a valid substitute for chain hashes or signature inputs.
//
// Install:  npm install canonicalize
//
// The package's CommonJS export is wrapped in `{ default: fn }`; we resolve
// that here so callers always see a plain function.
//
// Public API:
//   canonicalize(obj)       -> Buffer  (UTF-8 canonical bytes; no trailing nl)
//   canonicalizeString(obj) -> string  (canonical JSON as a JS string)
//   available()             -> Promise<boolean>
// =============================================================================

import { Buffer } from "node:buffer";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

/**
 * Walk upward from `start` looking for `node_modules/canonicalize/package.json`.
 * Returns the path to canonicalize/package.json or null if not found.
 *
 * @param {string} start absolute directory to search from.
 * @returns {string | null}
 */
function findCanonicalizeManifest(start) {
  let dir = start;
  // Cap the walk at the filesystem root.
  while (true) {
    const candidate = join(dir, "node_modules", "canonicalize", "package.json");
    if (existsSync(candidate)) return candidate;
    const parent = dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

/**
 * Resolve the underlying canonicalize() function from the npm package via
 * dynamic ESM import. The package is `type: module` and only exports `import`
 * — we cannot use `require` here.
 *
 * Search order for the package:
 *  1) bare `canonicalize` import — succeeds when installed in a node_modules
 *     ancestor of this file (e.g., repo root, .claude/, etc.).
 *  2) Walk upward from the script location, then from process.cwd(), looking
 *     for `node_modules/canonicalize`.
 *
 * @returns {Promise<(obj: unknown) => string>}
 */
async function resolveCanonicalizeFn() {
  let mod;
  try {
    mod = await import("canonicalize");
  } catch (bareImportErr) {
    const scriptDir = dirname(fileURLToPath(import.meta.url));
    const cwd = process.cwd();
    let manifest = findCanonicalizeManifest(scriptDir);
    if (!manifest) manifest = findCanonicalizeManifest(cwd);
    if (!manifest) {
      throw new Error(
        "canonicalize: package not found. Install with: " +
          "`cd tests/conformance/jcs && npm install`. Original error: " +
          bareImportErr.message
      );
    }
    // Read package.json to find the main ESM entry point.
    const pkgDir = dirname(manifest);
    const pkg = JSON.parse(
      await (await import("node:fs/promises")).readFile(manifest, "utf8")
    );
    const entry =
      (pkg.exports && pkg.exports["."] && pkg.exports["."].import) ||
      pkg.module ||
      pkg.main ||
      "lib/canonicalize.js";
    const entryUrl = pathToFileURL(join(pkgDir, entry)).href;
    mod = await import(entryUrl);
  }
  if (typeof mod === "function") return mod;
  if (mod && typeof mod.default === "function") return mod.default;
  throw new Error(
    "canonicalize: unexpected module shape — neither function nor { default: fn }"
  );
}

/**
 * Return a JS string with the canonical RFC 8785 JCS serialization of `obj`.
 *
 * @param {unknown} obj JSON-serializable value.
 * @returns {Promise<string>} canonical JSON string.
 */
export async function canonicalizeString(obj) {
  const fn = await resolveCanonicalizeFn();
  return fn(obj);
}

/**
 * Return a UTF-8 Buffer with the canonical bytes of `obj`. No trailing newline.
 *
 * @param {unknown} obj JSON-serializable value.
 * @returns {Promise<Buffer>} canonical UTF-8 bytes.
 */
export async function canonicalize(obj) {
  return Buffer.from(await canonicalizeString(obj), "utf8");
}

/**
 * Resolve true if the `canonicalize` npm package is installed (anywhere
 * resolvable to `resolveCanonicalizeFn`).
 *
 * @returns {Promise<boolean>}
 */
export async function available() {
  try {
    await resolveCanonicalizeFn();
    return true;
  } catch {
    return false;
  }
}

// CLI entry point.
if (import.meta.url === `file://${process.argv[1]}`) {
  let raw = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) raw += chunk;
  if (!raw) {
    process.stderr.write("jcs.mjs: empty stdin\n");
    process.exit(2);
  }
  let value;
  try {
    value = JSON.parse(raw);
  } catch (err) {
    process.stderr.write(`jcs.mjs: invalid JSON on stdin: ${err.message}\n`);
    process.exit(2);
  }
  process.stdout.write(await canonicalizeString(value));
}
