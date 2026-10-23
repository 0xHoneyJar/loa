/**
 * cycle-133 C-2 (sdd.md § 1.4, FR-2 AC 2; KF-055): the enrichment guard.
 *
 * Writer output is commentary. The guard rejects it (→ `enrichment_guard_rejected`, exit 3, un-enriched consensus
 * posted) when it:
 *  - carries provider tool-call grammar, matched structurally: a line-start XML tag (`<invoke`, `<function_calls`, …,
 *    namespaced or not) or a JSON object key (`tool_use`, `tool_calls`, `function_call`, `toolUse`, `functionCall`,
 *    or `"type": "tool_use"`), both outside fenced code spans and inline code, and never inside a JSON string value;
 *  - contains more than one findings block, a malformed one, or a findings JSON outside the markers;
 *  - echoes findings that are not exactly the consensus findings (an added, omitted or duplicated id → own block);
 *  - alters or omits any canonical field of an echoed finding, or echoes a different verdict.
 * A faithful echo is accepted and stripped from the commentary: the posted block is always the rendered consensus.
 */
import { CANONICAL_FIELDS, FINDINGS_END, FINDINGS_START, canonicalize } from "./finding-canonical.js";
import type { ConsensusFindingsBlock } from "./consensus-findings.js";

export type GuardRejection =
  | "tool_grammar"
  | "multiple_findings_blocks"
  | "malformed_findings_block"
  | "own_findings_block"
  | "duplicate_id"
  | "altered_field"
  | "altered_verdict";

export type GuardResult =
  | { accepted: true; echoed: boolean; commentary: string }
  | { accepted: false; reason: GuardRejection; detail: string };

const XML_TOOL_TAG = /^[ \t]{0,3}<\/?(?:[A-Za-z_][\w.-]*:)?(invoke|function_calls|function_call|tool_use|tool_calls|tool_call)\b/i;
const JSON_TOOL_KEYS = new Set(["tool_use", "tool_calls", "tool_call", "function_call", "toolUse", "functionCall"]);
const JSON_TOOL_TYPES = new Set(["tool_use", "tool_call", "function_call"]);

interface Fence {
  /** Line indexes [open, close] inclusive (close = last line when unclosed). */
  open: number;
  close: number;
}

/** CommonMark fenced code blocks (``` or ~~~, ≥ 3, up to 3 spaces of indent; an unclosed fence runs to the end). */
function findFences(lines: string[]): Fence[] {
  const fences: Fence[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = /^ {0,3}(`{3,}|~{3,})/.exec(lines[i]);
    if (!m || (m[1][0] === "`" && lines[i].slice(m[0].length).includes("`"))) continue;
    const ch = m[1][0];
    const len = m[1].length;
    let close = lines.length - 1;
    for (let j = i + 1; j < lines.length; j++) {
      const c = /^ {0,3}(`{3,}|~{3,})\s*$/.exec(lines[j]);
      if (c && c[1][0] === ch && c[1].length >= len) {
        close = j;
        break;
      }
    }
    fences.push({ open: i, close });
    i = close;
  }
  return fences;
}

/** Blank out fenced blocks and inline code spans (newlines kept, so line starts and line numbers survive). */
function maskCode(text: string): string {
  const lines = text.split("\n");
  for (const f of findFences(lines)) for (let i = f.open; i <= f.close; i++) lines[i] = "";
  return lines.map(maskInlineCode).join("\n");
}

/** Blank out inline code spans on one line: a run of N backticks up to the next run of exactly N. */
function maskInlineCode(line: string): string {
  let out = "";
  let i = 0;
  while (i < line.length) {
    if (line[i] !== "`") {
      out += line[i++];
      continue;
    }
    let n = 0;
    while (line[i + n] === "`") n++;
    let j = i + n;
    let close = -1;
    while (j < line.length) {
      if (line[j] !== "`") {
        j++;
        continue;
      }
      let m = 0;
      while (line[j + m] === "`") m++;
      if (m === n) {
        close = j;
        break;
      }
      j += m;
    }
    if (close === -1) {
      out += line.slice(i, i + n);
      i += n;
      continue;
    }
    out += " ".repeat(close + n - i);
    i = close + n;
  }
  return out;
}

/** The end index (exclusive) of the balanced JSON value starting at `start`, string-aware; -1 when unbalanced. */
function balancedEnd(text: string, start: number, budget: { left: number }): number {
  let depth = 0;
  let inString = false;
  for (let j = start; j < text.length; j++) {
    if (--budget.left < 0) return -2;
    const c = text[j];
    if (inString) {
      if (c === "\\") j++;
      else if (c === '"') inString = false;
      continue;
    }
    if (c === '"') inString = true;
    else if (c === "{" || c === "[") depth++;
    else if (c === "}" || c === "]") {
      depth--;
      if (depth === 0) return j + 1;
      if (depth < 0) return -1;
    }
  }
  return -1;
}

/** A tool-call key anywhere in the parsed structure's objects (keys and `type` values only — never string contents). */
function toolKeyIn(value: unknown): string | null {
  if (Array.isArray(value)) {
    for (const v of value) {
      const hit = toolKeyIn(v);
      if (hit) return hit;
    }
    return null;
  }
  if (value === null || typeof value !== "object") return null;
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (JSON_TOOL_KEYS.has(k)) return k;
    if (k === "type" && typeof v === "string" && JSON_TOOL_TYPES.has(v)) return `type: ${v}`;
    const hit = toolKeyIn(v);
    if (hit) return hit;
  }
  return null;
}

/**
 * The first structural tool-call grammar match, described without quoting the text (`line N: xml tag invoke`,
 * `json key tool_calls`), or null.
 */
export function findToolGrammar(text: string): string | null {
  const masked = maskCode(text);
  const lines = masked.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const m = XML_TOOL_TAG.exec(lines[i]);
    if (m) return `line ${i + 1}: xml tag ${m[1].toLowerCase()}`;
  }
  // JSON values outside code: parse each balanced {…}/[…] once; strings are parsed as values, never scanned for keys
  const budget = { left: Math.max(1_000_000, masked.length * 20) };
  for (let i = 0; i < masked.length; i++) {
    const c = masked[i];
    if (c !== "{" && c !== "[") continue;
    const end = balancedEnd(masked, i, budget);
    if (end === -2) return "json scan budget exceeded (fail closed)";
    if (end < 0) continue;
    let parsed: unknown;
    try {
      parsed = JSON.parse(masked.slice(i, end));
    } catch {
      continue;
    }
    const hit = toolKeyIn(parsed);
    if (hit) return `json key ${hit}`;
    i = end - 1;
  }
  return null;
}

function countOf(text: string, needle: string): number {
  let n = 0;
  for (let i = text.indexOf(needle); i !== -1; i = text.indexOf(needle, i + needle.length)) n++;
  return n;
}

/** A fenced block outside the marker range whose JSON is an object with a `findings` array. */
function unmarkedFindingsJson(text: string): boolean {
  const lines = text.split("\n");
  for (const f of findFences(lines)) {
    const body = lines.slice(f.open + 1, f.close).join("\n");
    try {
      const v = JSON.parse(body) as unknown;
      if (v !== null && typeof v === "object" && Array.isArray((v as { findings?: unknown }).findings)) return true;
    } catch {
      // not JSON
    }
  }
  return false;
}

function safeId(id: string): string {
  return id.replace(/[^\w.~-]/g, "?").slice(0, 40);
}

export function guardEnrichment(output: string, consensus: ConsensusFindingsBlock): GuardResult {
  const reject = (reason: GuardRejection, detail: string): GuardResult => ({ accepted: false, reason, detail });

  const grammar = findToolGrammar(output);
  if (grammar) return reject("tool_grammar", grammar);

  const starts = countOf(output, FINDINGS_START);
  const ends = countOf(output, FINDINGS_END);
  if (starts > 1 || ends > 1) return reject("multiple_findings_blocks", `${starts} start / ${ends} end markers`);
  if (starts !== ends) return reject("malformed_findings_block", "unbalanced findings markers");

  const startIdx = output.indexOf(FINDINGS_START);
  const endIdx = output.indexOf(FINDINGS_END);
  const outside = starts === 0 ? output : output.slice(0, startIdx) + output.slice(endIdx + FINDINGS_END.length);
  if (unmarkedFindingsJson(outside)) return reject("own_findings_block", "a findings JSON outside the markers");
  if (starts === 0) return { accepted: true, echoed: false, commentary: output };
  if (endIdx < startIdx) return reject("malformed_findings_block", "end marker before start marker");

  const raw = output.slice(startIdx + FINDINGS_START.length, endIdx).trim().replace(/^```(?:json)?\s*/, "").replace(/\s*```$/, "");
  let parsed: { findings?: unknown; verdict?: unknown };
  try {
    parsed = JSON.parse(raw) as typeof parsed;
  } catch {
    return reject("malformed_findings_block", "the block is not JSON");
  }
  if (parsed === null || typeof parsed !== "object" || !Array.isArray(parsed.findings) ||
      !parsed.findings.every((f) => f !== null && typeof f === "object" && !Array.isArray(f))) {
    return reject("malformed_findings_block", "the block has no findings array of objects");
  }
  const echoed = parsed.findings as Array<Record<string, unknown>>;

  const ids = echoed.map((f) => String(f.id));
  const dup = ids.find((id, i) => ids.indexOf(id) !== i);
  if (dup !== undefined) return reject("duplicate_id", `id ${safeId(dup)} appears more than once`);
  const consensusById = new Map(consensus.findings.map((f) => [String(f.id), f]));
  const foreign = ids.find((id) => !consensusById.has(id));
  if (foreign !== undefined) return reject("own_findings_block", `id ${safeId(foreign)} is not a consensus finding`);
  if (ids.length !== consensusById.size) {
    return reject("own_findings_block", `${consensusById.size - ids.length} consensus finding(s) omitted`);
  }

  const altered: string[] = [];
  for (const f of echoed) {
    const mine = canonicalize(f);
    const theirs = canonicalize(consensusById.get(String(f.id))!);
    for (const field of CANONICAL_FIELDS) {
      if (JSON.stringify(mine[field]) !== JSON.stringify(theirs[field])) altered.push(`${safeId(String(f.id))}.${field}`);
    }
  }
  if (altered.length > 0) return reject("altered_field", altered.slice(0, 10).join(", "));
  if (parsed.verdict !== undefined && parsed.verdict !== consensus.verdict) {
    return reject("altered_verdict", `echoed verdict differs from the consensus verdict ${consensus.verdict}`);
  }

  const commentary = output.slice(0, startIdx) + "_(The findings block is rendered from the consensus above.)_" +
    output.slice(endIdx + FINDINGS_END.length);
  return { accepted: true, echoed: true, commentary };
}
