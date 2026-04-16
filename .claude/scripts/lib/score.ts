import * as crypto from "crypto";
import * as fs from "fs";
import { extractCitations } from "./citations";

export interface ScoringResult {
  oracle_citations: number;
  candidate_citations: number;
  intersection: number;
  fidelity: number;
  pass: boolean;
  oracle_sha256_before: string;
  oracle_sha256_after: string;
  oracle_integrity: boolean;
}

export function sha256File(filePath: string): string {
  const content = fs.readFileSync(filePath, "utf8");
  return crypto.createHash("sha256").update(content, "utf8").digest("hex");
}

/** Extract wikilinks [[name]], map to ~/hivemind/wiki/concepts/name.md, filter to files that exist. */
function extractWikilinks(content: string): Set<string> {
  const result = new Set<string>();
  const home = process.env.HOME ?? "";
  const regex = /\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/g;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(content)) !== null) {
    const name = m[1].trim();
    const tildePath = `~/hivemind/wiki/concepts/${name}.md`;
    const absPath = home + `/hivemind/wiki/concepts/${name}.md`;
    try {
      fs.accessSync(absPath, fs.constants.R_OK);
      result.add(tildePath);
    } catch {
      // file doesn't exist — skip this wikilink
    }
  }
  return result;
}

/** Compute intersection between oracle keys and candidate citation file paths. */
function fileIntersection(oracleKeys: Set<string>, candidateCitations: Set<string>): number {
  const candidateFiles = new Set<string>();
  for (const key of candidateCitations) {
    const colonIdx = key.lastIndexOf(":");
    candidateFiles.add(colonIdx > 0 ? key.slice(0, colonIdx) : key);
  }
  let count = 0;
  for (const key of oracleKeys) {
    const colonIdx = key.lastIndexOf(":");
    const file = colonIdx > 0 ? key.slice(0, colonIdx) : key;
    if (candidateFiles.has(file)) count++;
  }
  return count;
}

export function computeScore(
  oracleContent: string,
  candidateContent: string,
  sha256Before: string,
  sha256After: string,
): ScoringResult {
  let oracleCitations = extractCitations(oracleContent);
  const candidateCitations = extractCitations(candidateContent);

  // Fallback: if oracle has no ~/path:N citations, try wikilinks
  const usingWikilinks = oracleCitations.size === 0;
  if (usingWikilinks) {
    oracleCitations = extractWikilinks(oracleContent);
  }

  let fidelity = 0;
  let intersectionCount = 0;

  if (oracleCitations.size === 0) {
    console.error("WARN: oracle has zero citations — fidelity forced to 0");
  } else {
    if (usingWikilinks) {
      intersectionCount = fileIntersection(oracleCitations, candidateCitations);
    } else {
      for (const key of oracleCitations) {
        if (candidateCitations.has(key)) intersectionCount++;
      }
    }
    fidelity = Math.round((intersectionCount / oracleCitations.size) * 1000) / 1000;
  }

  return {
    oracle_citations: oracleCitations.size,
    candidate_citations: candidateCitations.size,
    intersection: intersectionCount,
    fidelity,
    pass: fidelity >= 0.8,
    oracle_sha256_before: sha256Before,
    oracle_sha256_after: sha256After,
    oracle_integrity: sha256Before === sha256After,
  };
}

export function emitReport(result: ScoringResult): void {
  console.log("=== Archivist Rederivation Report ===");
  console.log(`oracle_citations  : ${result.oracle_citations}`);
  console.log(`candidate_citations: ${result.candidate_citations}`);
  console.log(`intersection      : ${result.intersection}`);
  console.log(`fidelity          : ${result.fidelity.toFixed(3)}`);
  console.log(`pass              : ${result.pass}`);
  console.log(`oracle_integrity  : ${result.oracle_integrity}`);
}
