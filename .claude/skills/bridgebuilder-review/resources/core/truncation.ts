import type { PullRequestFile } from "../ports/git-provider.js";
import type { BridgebuilderConfig, TruncationResult } from "./types.js";

// Path-segment-aware patterns to avoid false positives on tsconfig.json, keyboard.ts, etc.
// Matches when the keyword is a path segment or filename component, not an arbitrary substring.
const SECURITY_PATTERNS = [
  /(?:^|\/)auth/i,
  /(?:^|\/)crypto/i,
  /(?:^|\/)secret/i,
  /(?:^|\/)\.env/i,
  /(?:^|\/)password/i,
  /(?:^|\/)credential/i,
  /(?:^|\/)security/i,
  /(?:^|\/)acl/i,
  /(?:^|\/)permissions?[./]/i,
  /\.pem$/i,
  /\.key$/i,
];

function isHighRisk(filename: string): boolean {
  return SECURITY_PATTERNS.some((p) => p.test(filename));
}

function matchesExcludePattern(
  filename: string,
  patterns: string[],
): boolean {
  for (const pattern of patterns) {
    if (pattern.startsWith("*")) {
      const suffix = pattern.slice(1);
      if (filename.endsWith(suffix)) return true;
    } else if (pattern.endsWith("*")) {
      const prefix = pattern.slice(0, -1);
      if (filename.startsWith(prefix)) return true;
    } else if (pattern.includes("*")) {
      const [before, after] = pattern.split("*", 2);
      if (filename.startsWith(before) && filename.endsWith(after)) return true;
    } else {
      if (filename === pattern || filename.includes(pattern)) return true;
    }
  }
  return false;
}

function changeSize(file: PullRequestFile): number {
  return file.additions + file.deletions;
}

function patchBytes(file: PullRequestFile): number {
  return file.patch ? new TextEncoder().encode(file.patch).byteLength : 0;
}

export function truncateFiles(
  files: PullRequestFile[],
  config: Pick<
    BridgebuilderConfig,
    "excludePatterns" | "maxDiffBytes" | "maxFilesPerPr"
  >,
): TruncationResult {
  const patterns = config.excludePatterns ?? [];

  // Step 1: Separate files matching excludePatterns (sole enforcement point — IMP-005)
  const afterExclude: PullRequestFile[] = [];
  const excludedByPattern: Array<{ filename: string; stats: string }> = [];
  for (const f of files) {
    if (matchesExcludePattern(f.filename, patterns)) {
      excludedByPattern.push({
        filename: f.filename,
        stats: `+${f.additions} -${f.deletions} (excluded by pattern)`,
      });
    } else {
      afterExclude.push(f);
    }
  }

  // Step 2: Classify into high-risk and normal
  const highRisk: PullRequestFile[] = [];
  const normal: PullRequestFile[] = [];
  for (const file of afterExclude) {
    if (isHighRisk(file.filename)) {
      highRisk.push(file);
    } else {
      normal.push(file);
    }
  }

  // Step 3: Sort each tier by change size (descending)
  highRisk.sort((a, b) => changeSize(b) - changeSize(a));
  normal.sort((a, b) => changeSize(b) - changeSize(a));

  // Interleave: high-risk first, then normal
  const sorted = [...highRisk, ...normal];

  // Apply maxFilesPerPr cap
  const capped = sorted.slice(0, config.maxFilesPerPr);

  // Step 4: Include full diff content until byte budget exhausted
  const included: PullRequestFile[] = [];
  const excluded: Array<{ filename: string; stats: string }> = [];
  let totalBytes = 0;

  for (const file of capped) {
    const bytes = patchBytes(file);

    // Step 6: Handle patch-optional files (binary/large — GitHub omits patch)
    if (file.patch == null) {
      excluded.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions} (diff unavailable)`,
      });
      continue;
    }

    if (totalBytes + bytes <= config.maxDiffBytes) {
      included.push(file);
      totalBytes += bytes;
    } else {
      // Step 5: Remaining files get name + stats only
      excluded.push({
        filename: file.filename,
        stats: `+${file.additions} -${file.deletions}`,
      });
    }
  }

  // Files beyond maxFilesPerPr cap also go to excluded
  for (const file of sorted.slice(config.maxFilesPerPr)) {
    excluded.push({
      filename: file.filename,
      stats: `+${file.additions} -${file.deletions}`,
    });
  }

  return { included, excluded: [...excludedByPattern, ...excluded], totalBytes };
}
