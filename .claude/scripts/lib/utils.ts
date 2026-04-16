import * as fs from "fs";
import * as path from "path";

export function untildify(p: string): string {
  const home = process.env.HOME;
  if (!home) throw new Error("HOME environment variable is not set");
  if (p.startsWith("~/")) return home + "/" + p.slice(2);
  return p;
}

export function resolvePath(p: string): string {
  return path.resolve(untildify(p));
}

export function readSeedPaths(contextFile: string): string[] {
  if (!fs.existsSync(contextFile)) {
    throw new Error(`Seed context file not found: ${contextFile}`);
  }
  const content = fs.readFileSync(contextFile, "utf8");
  const seen = new Set<string>();
  const results: string[] = [];
  const regex = /(~\/[^\s`\)\]'"]+)/g;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(content)) !== null) {
    const p = m[1].replace(/[.,;:]+$/, "");
    if (!seen.has(p)) {
      seen.add(p);
      results.push(p);
    }
  }
  if (results.length === 0) {
    throw new Error(`No tilde-prefixed paths found in: ${contextFile}`);
  }
  return results;
}
