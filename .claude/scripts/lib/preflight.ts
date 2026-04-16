import * as fs from "fs";
import * as path from "path";
import { resolvePath } from "./utils";

const { R_OK } = fs.constants;

export function runPreflight(
  oracle: string,
  candidate: string,
  seedPaths: string[],
  exitFn: (code: number) => never = (code) => process.exit(code) as never,
): void {
  if (!process.env.HOME) {
    console.error("FATAL: HOME environment variable is not set");
    return exitFn(3);
  }

  if (resolvePath(oracle) === resolvePath(candidate)) {
    console.error(`FATAL: oracle and candidate resolve to the same path: ${resolvePath(oracle)}`);
    return exitFn(2);
  }

  const resolvedCandidate = resolvePath(candidate);
  const cwd = process.cwd();
  if (resolvedCandidate === cwd || resolvedCandidate.startsWith(cwd + path.sep)) {
    console.error(`FATAL: candidate path is inside the repo: ${resolvedCandidate}`);
    return exitFn(3);
  }

  const resolvedOracle = resolvePath(oracle);
  try {
    fs.accessSync(resolvedOracle, R_OK);
  } catch {
    console.error(`FATAL: oracle not readable: ${resolvedOracle}`);
    return exitFn(3);
  }

  const bonfireRequired = seedPaths.some((p) => p.startsWith("~/bonfire/"));
  if (bonfireRequired) {
    const bonfirePath = resolvePath("~/bonfire");
    try {
      fs.accessSync(bonfirePath, R_OK);
    } catch {
      console.error(`FATAL: ~/bonfire/ directory does not exist: ${bonfirePath}`);
      return exitFn(1);
    }
  }

  for (const seedPath of seedPaths) {
    const resolved = resolvePath(seedPath);
    try {
      fs.accessSync(resolved, R_OK);
    } catch {
      console.error(`FATAL: seed file not readable: ${resolved}`);
      return exitFn(1);
    }
  }
}
