import * as fs from "fs";
import * as path from "path";
import * as crypto from "crypto";
import { resolvePath } from "./utils";

interface RawCitation {
  file: string;
  lineNumber: number;
  text: string;
}

interface ClaimGroup {
  citations: RawCitation[];
  keywords: Set<string>;
}

interface Frontmatter {
  created: string;
  updated: string;
  confidence: number;
  decay_class: "fast" | "normal" | "slow" | "frozen";
  last_confirmed: string;
  source_count: number;
  status: "draft" | "active" | "superseded" | "speculative";
  edges: string[];
}

function stripMarkdown(line: string): string {
  return line
    .replace(/^#+\s*/, "")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/^[-*>|]+\s*/, "")
    .trim();
}

function extractKeywords(text: string): Set<string> {
  const words = text.toLowerCase().match(/\b[a-z]{4,}\b/g) ?? [];
  return new Set(words.filter((w) => !STOPWORDS.has(w)));
}

const STOPWORDS = new Set([
  "that", "this", "with", "from", "have", "been", "they", "will",
  "when", "what", "which", "each", "into", "more", "also", "then",
  "than", "where", "some", "only", "other", "over", "such", "their",
  "there", "these", "those", "just", "like", "very", "much", "well",
  "used", "uses", "using", "make", "made", "make", "most", "your",
]);

function cluster(citations: RawCitation[]): ClaimGroup[] {
  const groups: ClaimGroup[] = [];
  for (const cite of citations) {
    const kw = extractKeywords(cite.text);
    let placed = false;
    for (const g of groups) {
      const overlap = [...kw].some((k) => g.keywords.has(k));
      if (overlap) {
        g.citations.push(cite);
        for (const k of kw) g.keywords.add(k);
        placed = true;
        break;
      }
    }
    if (!placed) {
      groups.push({ citations: [cite], keywords: new Set(kw) });
    }
  }
  return groups.filter((g) => g.citations.length >= 3);
}

function toDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function serializeFrontmatter(fm: Frontmatter): string {
  const edgesYaml =
    fm.edges.length === 0
      ? "[]"
      : "\n" + fm.edges.map((e) => `  - "${e}"`).join("\n");
  return [
    "---",
    `created: "${fm.created}"`,
    `updated: "${fm.updated}"`,
    `confidence: ${fm.confidence.toFixed(3)}`,
    `decay_class: ${fm.decay_class}`,
    `last_confirmed: "${fm.last_confirmed}"`,
    `source_count: ${fm.source_count}`,
    `status: ${fm.status}`,
    `edges:${edgesYaml}`,
    "---",
  ].join("\n");
}

export function synthesize(
  seedPaths: string[],
  candidatePath: string,
  oracleExcludedPaths: Set<string>,
  schemaPath: string,
): void {
  const today = toDate(new Date());

  const rawCitations: RawCitation[] = [];
  for (const rawPath of seedPaths) {
    const resolved = resolvePath(rawPath);
    if (oracleExcludedPaths.has(resolved)) {
      throw new Error(`Oracle exclusion violated: attempt to read ${resolved}`);
    }
    const lines = fs.readFileSync(resolved, "utf8").split("\n");
    lines.forEach((line, idx) => {
      const stripped = stripMarkdown(line);
      if (stripped.length >= 20) {
        rawCitations.push({ file: rawPath, lineNumber: idx + 1, text: stripped });
      }
    });
  }

  // Sort for determinism
  rawCitations.sort((a, b) =>
    a.file !== b.file ? a.file.localeCompare(b.file) : a.lineNumber - b.lineNumber,
  );

  const groups = cluster(rawCitations);

  // Select top groups until we have >= 5 distinct file:line tokens
  const selectedGroups: ClaimGroup[] = [];
  const seenTokens = new Set<string>();

  const sorted = [...groups].sort((a, b) => b.citations.length - a.citations.length);
  for (const g of sorted) {
    selectedGroups.push(g);
    for (const c of g.citations) seenTokens.add(`${c.file}:${c.lineNumber}`);
    if (seenTokens.size >= 5) break;
  }

  // If no clusters qualified, fall back to top-N raw citations directly
  if (seenTokens.size < 5) {
    for (const c of rawCitations) {
      const key = `${c.file}:${c.lineNumber}`;
      if (!seenTokens.has(key)) {
        seenTokens.add(key);
        selectedGroups.push({ citations: [c], keywords: extractKeywords(c.text) });
        if (seenTokens.size >= 5) break;
      }
    }
  }

  const distinctFiles = new Set(rawCitations.map((c) => c.file));
  const confidence = Math.min(
    0.95,
    Math.max(0.5, seenTokens.size / Math.max(rawCitations.length, 1)),
  );

  const fm: Frontmatter = {
    created: today,
    updated: today,
    confidence: Math.round(confidence * 1000) / 1000,
    decay_class: "normal",
    last_confirmed: today,
    source_count: distinctFiles.size,
    status: "active",
    edges: [...distinctFiles].map((f) => {
      const base = path.basename(f, path.extname(f));
      return `[[${base}]]`;
    }),
  };

  // Validate frontmatter with AJV
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const Ajv2020 = require("ajv/dist/2020");
  const AjvClass = Ajv2020.default ?? Ajv2020;
  const ajv = new AjvClass({ allErrors: true, strict: false });
  const schema = JSON.parse(fs.readFileSync(schemaPath, "utf8"));
  const validate = ajv.compile(schema);
  const valid = validate(fm);
  if (!valid) {
    const errors = ajv.errorsText(validate.errors);
    throw new Error(`Frontmatter AJV validation failed: ${errors}`);
  }

  // Build body
  const bodyLines: string[] = ["# Rederived Memory Architecture Synthesis", ""];
  for (const g of selectedGroups) {
    if (g.citations.length === 0) continue;
    bodyLines.push(`## ${g.citations[0].text.slice(0, 60).replace(/\n/g, " ")}`);
    bodyLines.push("");
    for (const c of g.citations) {
      bodyLines.push(`- [${c.text.slice(0, 80)}](${c.file}:${c.lineNumber})`);
    }
    bodyLines.push("");
  }

  const content = serializeFrontmatter(fm) + "\n\n" + bodyLines.join("\n");

  // Atomic write
  const tmpPath = candidatePath + ".tmp";
  try {
    const dir = path.dirname(candidatePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(tmpPath, content, "utf8");
    fs.renameSync(tmpPath, candidatePath);
  } catch (err) {
    try { fs.unlinkSync(tmpPath); } catch { /* ignore */ }
    throw err;
  }
}
