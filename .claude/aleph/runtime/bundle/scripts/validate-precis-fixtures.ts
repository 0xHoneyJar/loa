#!/usr/bin/env node
// Aleph Slice 3 — v0 Précis Conformance Checker
//
// A narrow, dependency-free, local conformance checker over the already-accepted
// Markdown Précis fixtures (Slice 1 + Slice 2). Node built-ins only. Reads files,
// writes nothing, mutates no repo state, needs no network, spawns no subprocess.
// Fails closed (non-zero exit) on a real invariant violation.
//
// It validates the REAL Aleph invariant:
//   - the Précis does not GENERATE downstream projections,
//   - the corpus does not LEAK answer-key / disposition labels,
//   - no candidate claim is silently dropped (accounting balances).
// It does NOT validate the false invariant that the words PRD / GTM / product
// spec / schema freeze / unresolved / disposition may never appear — they are
// allowed in ordinary prose and in explicit refusal / boundary contexts.
//
// Run:
//   node scripts/validate-precis-fixtures.ts
//   node scripts/validate-precis-fixtures.ts --root /tmp/some-copy
// (--root points at a directory that contains docs/fixtures/… ; used by the
//  negative-test battery to run THIS checker against temporary copies without
//  ever mutating tracked fixtures.)

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import type { Dirent } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateRun } from './validate-run.ts';
import type { CheckRecord, CheckStatus } from './lib/results.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_ROOT = join(__dirname, '..');

interface CheckerOptions {
  root: string;
  json: boolean;
}

function parseOptions(): CheckerOptions {
  const args = process.argv.slice(2);
  let root = DEFAULT_ROOT;
  let json = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--root') {
      root = args[i + 1];
      i++;
    } else if (args[i].startsWith('--root=')) {
      root = args[i].slice('--root='.length);
    } else if (args[i] === '--json') {
      json = true;
    }
  }
  return { root, json };
}

const OPTIONS = parseOptions();
const REPO_ROOT = OPTIONS.root;
const FIXTURES_DIR = join(REPO_ROOT, 'docs', 'fixtures');

type FixtureKind = 'precis' | 'run' | 'evidence-role' | 'routed' | 'projection';
type DelegatedKind = Exclude<FixtureKind, 'precis'>;

interface PrecisFixture {
  name: string;
  dir?: string;
  kind: 'precis';
  srcIds: string[];
  claimIds: string[];
  ledgerTotal: number;
  requireMatrix: boolean;
  matrixIds: string[];
}

interface DelegatedFixture {
  name: string;
  dir: string;
  kind: DelegatedKind;
  fields: Map<string, string>;
  srcIds: string[];
  claimIds: string[];
  matrixIds: string[];
}

type FixtureDeclaration = PrecisFixture | DelegatedFixture;

interface DiscoveryResult {
  precis: PrecisFixture[];
  delegated: DelegatedFixture[];
}

interface PatternRule {
  label: string;
  re: RegExp;
}

interface InventoryResult {
  ids: string[];
  map: Map<string, string>;
}

interface LedgerResult {
  declaredTotal: number | null;
  counts: Map<string, number>;
}

interface LedgerRow {
  disposition: string;
  claimIds: string[];
}

interface MergeRow {
  canonical: string;
  absorbs: string[];
}

interface MatrixReference {
  stm: string | null;
  id: string;
}

interface MatrixReferences {
  present: boolean;
  ccCol?: number;
  srcCol?: number;
  ccRefs: MatrixReference[];
  srcRefs: MatrixReference[];
  stmRowIds: Set<string>;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function isFixtureKind(value: string): value is FixtureKind {
  return ['precis', 'run', 'evidence-role', 'routed', 'projection'].includes(value);
}

// ---------------------------------------------------------------------------
// Constants: the accepted provisional v0 vocabulary (NOT a frozen schema)
// ---------------------------------------------------------------------------

const VALID_DISPOSITIONS = [
  'carried',
  'merged',
  'deferred',
  'excluded-with-reason',
  'backgrounded',
  'judged-non-load-bearing',
  'unresolved',
];

const DEFERRED_BUSINESS_INTELLIGENCE_CONSUMER_PATTERN =
  new RegExp(`\\b${['sense', 'net'].join('')}\\b`, 'i');

// Absolute zero-tolerance tokens — hard failure anywhere under a fixture dir.
const ABSOLUTE_FORBIDDEN: PatternRule[] = [
  { label: 'Phase', re: /\bphase\b/i },
  {
    label: 'deferred business-intelligence consumer name',
    re: DEFERRED_BUSINESS_INTELLIGENCE_CONSUMER_PATTERN,
  },
];

// The EXACT set of direct entries allowed in a fixture directory.
const EXPECTED_FILES = ['README.md', 'corpus.md', 'precis.md'];

// Per-slice expectations.
const SLICES: PrecisFixture[] = [
  {
    name: 'slice-1',
    kind: 'precis',
    srcIds: ['SRC-001', 'SRC-002', 'SRC-003'],
    claimIds: range(1, 10).map((n) => `CC-${String(n).padStart(3, '0')}`),
    ledgerTotal: 10,
    requireMatrix: false,
    matrixIds: [],
  },
  {
    name: 'slice-2',
    kind: 'precis',
    srcIds: ['SRC-101', 'SRC-102', 'SRC-103', 'SRC-104'],
    claimIds: range(101, 114).map((n) => `CC-${n}`),
    ledgerTotal: 14,
    requireMatrix: true,
    matrixIds: range(1, 7).map((n) => `STM-${n}`),
  },
];

// ---------------------------------------------------------------------------
// Projection-boundary vocabulary (context-aware, NOT naive word absence)
// ---------------------------------------------------------------------------

// Downstream-artifact nouns. Presence alone is fine; only generation matters.
const PROJECTION_TERMS = [
  /\bPRD\b/,
  /\bGTM\b/,
  /\bmarket landscape\b/i,
  /\bproduct spec\b/i,
  /\bpitch deck\b/i,
  /\bdownstream projection\b/i,
  /\badjacent-consumer formalization\b/i,
  /\bprojection\b/i,
];

// Verbs that imply GENERATING / PRODUCING / FORMALIZING such an artifact.
// Note: precise verb inflections only — must NOT match the nouns "product"
// (in "product spec") or "deliverable", which legitimately appear in refusal prose.
const GENERATION_VERBS =
  /\b(generat(?:e|es|ing|ed|ion)|produc(?:e|es|ing|ed|tion)|emit(?:s|ting|ted)?|formaliz(?:e|es|ing|ed|ation)|render(?:s|ed|ing)? into|ship(?:s|ped|ping)?|deliver(?:s|ed|ing)?\b|projects|projecting|project into)\b/i;

// Cues that mark a line as a genuine refusal / negation / boundary / hypothetical
// — i.e. NOT an actual generation assertion. NOTE: "deliberately" is deliberately
// NOT in this list: "deliberately generates a PRD" is still generation. The cue
// must be a real negation / refusal / hypothetical word.
const EXEMPTION_CUES =
  /\b(no|not|never|none|neither|nor|without|cannot|can't|don't|doesn't|won't|could|would|may|might|should not|stops?|stopped|refus\w*|defer(?:s|red|ring)?|projection-neutral)\b|out[ -]of[ -]scope/i;

// Real-export markers (genuine ChatGPT export artifacts) — must not appear.
const REAL_EXPORT_MARKERS = [/chatgpt said:/i, /\[oai_citation/i, /^\s*user:\s*$/i];

// ---------------------------------------------------------------------------
// Corpus answer-key / label-leakage detectors (corpus.md only)
// ---------------------------------------------------------------------------

const CORPUS_LEAKS: PatternRule[] = [
  { label: 'candidate-claim ID (CC-NNN)', re: /\bCC-\d{3}\b/ },
  { label: 'stress-test-matrix ID (STM-N)', re: /\bSTM-\d+\b/ },
  { label: 'phrase "candidate claim"', re: /\bcandidate claim\b/i },
  { label: 'phrase "stress-test matrix"', re: /\bstress-test matrix\b/i },
  { label: 'compound disposition "excluded-with-reason"', re: /\bexcluded-with-reason\b/i },
  { label: 'compound disposition "judged-non-load-bearing"', re: /\bjudged-non-load-bearing\b/i },
  { label: 'disposition label ("disposition: <value>")', re: /\bdisposition:\s*\S/i },
  { label: 'disposition column header ("| disposition |")', re: /\|\s*disposition\s*\|/i },
];

// ---------------------------------------------------------------------------
// Result accumulation
// ---------------------------------------------------------------------------

const failures: string[] = [];
const passes: string[] = [];
const checks: CheckRecord[] = [];

function inferScope(msg: string): string {
  return msg.match(/^([^ :]+)/)?.[1] || 'fixtures';
}

function inferCheckId(msg: string): string {
  if (msg.includes('cross-section consistency')) return 'C1-C8';
  const explicit = msg.match(/\b(K\d+(?:\.\d+)?|C\d+)\b/);
  if (explicit) return explicit[1];
  const label = msg.replace(/^[^ :]+[: ]+/, '');
  if (label.startsWith('files')) return 'P1';
  if (label.startsWith('forbidden token')) return 'P2';
  if (label.startsWith('projection boundary') || label.startsWith('real-export marker')) return 'P3';
  if (label.startsWith('schema wording')) return 'P4';
  if (label.startsWith('corpus boundary')) return 'P5';
  if (label.startsWith('envelope')) return 'P6';
  if (label.startsWith('inventory')) return 'P7';
  if (label.startsWith('coverage')) return 'P8';
  if (label.startsWith('accounting')) return 'P9';
  if (label.startsWith('matrix')) return 'P10';
  if (label.startsWith('consistency')) return 'C1-C8';
  return 'PRECIS';
}

function record(
  status: CheckStatus,
  msg: string,
  id = inferCheckId(msg),
  scope = inferScope(msg),
): void {
  checks.push({ id, scope, status, message: msg });
}

function fail(
  msg: string,
  id = inferCheckId(msg),
  scope = inferScope(msg),
): void {
  failures.push(msg);
  record('FAIL', msg, id, scope);
}

function pass(
  msg: string,
  id = inferCheckId(msg),
  scope = inferScope(msg),
): void {
  passes.push(msg);
  record('PASS', msg, id, scope);
}

function sliceHasFailure(name: string, ...prefixes: string[]): boolean {
  return failures.some((m) => prefixes.some((p) => m.startsWith(`${name} ${p}`)));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function range(a: number, b: number): number[] {
  const out: number[] = [];
  for (let i = a; i <= b; i++) out.push(i);
  return out;
}

function readMaybe(path: string): string | null {
  if (!existsSync(path)) return null;
  return readFileSync(path, 'utf8');
}

function parseIdList(value: string): string[] {
  if (!value || !value.trim()) throw new Error('empty id list');
  const ids: string[] = [];
  for (const part of value.split(',').map((item) => item.trim())) {
    const match = part.match(/^([A-Z]+)-(\d+)(?:\.\.([A-Z]+)-(\d+))?$/);
    if (!match) throw new Error(`malformed id or range "${part}"`);
    const [, startPrefix, startDigits, endPrefix, endDigits] = match;
    if (!endPrefix) {
      ids.push(`${startPrefix}-${startDigits}`);
      continue;
    }
    if (startPrefix !== endPrefix) throw new Error(`mixed-prefix range "${part}"`);
    const padded = startDigits.startsWith('0') || endDigits.startsWith('0');
    if (padded && startDigits.length !== endDigits.length) {
      throw new Error(`mixed zero-padding range "${part}"`);
    }
    const start = Number(startDigits);
    const end = Number(endDigits);
    if (start > end) throw new Error(`descending range "${part}"`);
    for (let n = start; n <= end; n++) {
      const suffix = padded ? String(n).padStart(startDigits.length, '0') : String(n);
      ids.push(`${startPrefix}-${suffix}`);
    }
  }
  const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index);
  if (duplicates.length) throw new Error(`duplicate id(s): ${[...new Set(duplicates)].join(', ')}`);
  return ids;
}

function parseFixtureDeclaration(name: string, dir: string): FixtureDeclaration | null {
  const readme = readMaybe(join(dir, 'README.md'));
  if (readme === null) {
    fail(`${name} K1.1 (declaration): README.md is missing`, 'K1.1', name);
    return null;
  }
  const blocks = [...readme.matchAll(/```aleph-fixture\s*\n([\s\S]*?)```/g)];
  if (blocks.length !== 1) {
    fail(
      `${name} K1.1 (declaration): expected exactly one aleph-fixture block in README.md, found ${blocks.length}`,
      'K1.1',
      name,
    );
    return null;
  }
  const fields = new Map<string, string>();
  for (const rawLine of blocks[0][1].split('\n')) {
    const line = rawLine.replace(/\s+#.*$/, '').trim();
    if (!line) continue;
    const match = line.match(/^([a-z_]+):\s*(.*?)\s*$/);
    if (!match || !match[2]) {
      fail(`${name} K1.1 (declaration): malformed line "${rawLine.trim()}"`, 'K1.1', name);
      return null;
    }
    if (fields.has(match[1])) {
      fail(`${name} K1.1 (declaration): duplicate field "${match[1]}"`, 'K1.1', name);
      return null;
    }
    fields.set(match[1], match[2]);
  }
  const kind = fields.get('kind');
  if (!kind) {
    fail(`${name} K1.1 (declaration): required field "kind" is missing`, 'K1.1', name);
    return null;
  }
  if (!isFixtureKind(kind)) {
    fail(`${name} K1.2 (unknown kind): "${kind}"`, 'K1.2', name);
    return null;
  }

  let srcIds: string[] = [];
  let claimIds: string[] = [];
  let matrixIds: string[] = [];
  try {
    if (fields.has('src_ids')) srcIds = parseIdList(fields.get('src_ids') ?? '');
    if (fields.has('cc_ids')) claimIds = parseIdList(fields.get('cc_ids') ?? '');
    if (fields.has('stm_rows')) matrixIds = parseIdList(fields.get('stm_rows') ?? '');
  } catch (error) {
    fail(`${name} K1.3 (range): ${errorMessage(error)}`, 'K1.3', name);
    return null;
  }

  if (kind === 'precis') {
    const ledgerTotal = Number(fields.get('ledger_total'));
    if (!srcIds.length || !claimIds.length || !Number.isInteger(ledgerTotal) || ledgerTotal < 0) {
      fail(
        `${name} K1.1 (declaration): kind precis requires src_ids, cc_ids, and a non-negative integer ledger_total`,
        'K1.1',
        name,
      );
      return null;
    }
    return {
      name,
      dir,
      kind,
      srcIds,
      claimIds,
      ledgerTotal,
      requireMatrix: matrixIds.length > 0,
      matrixIds,
    };
  }

  return {
    name,
    dir,
    kind,
    fields,
    srcIds,
    claimIds,
    matrixIds,
  };
}

function discoverFixtures(): DiscoveryResult {
  let entries: Dirent[];
  try {
    entries = readdirSync(FIXTURES_DIR, { withFileTypes: true });
  } catch {
    return { precis: [], delegated: [] };
  }
  const legacy = new Set(SLICES.map((slice) => slice.name));
  const precis: PrecisFixture[] = [];
  const delegated: DelegatedFixture[] = [];
  for (const entry of entries.filter((item) => item.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
    if (legacy.has(entry.name)) continue;
    const dir = join(FIXTURES_DIR, entry.name);
    const declaration = parseFixtureDeclaration(entry.name, dir);
    if (!declaration) continue;
    if (declaration.kind === 'precis') precis.push(declaration);
    else delegated.push(declaration);
  }
  if (!failures.some((message) => /\bK1\.[123]\b/.test(message))) {
    pass(
      `discovery: ${SLICES.length + precis.length + delegated.length} fixture director${SLICES.length + precis.length + delegated.length === 1 ? 'y' : 'ies'} recognized; declarations valid`,
      'K1',
      'fixtures',
    );
  }
  return { precis, delegated };
}

// Split a Markdown table row into trimmed content cells. Outer pipes are
// OPTIONAL: we strip a leading/trailing split fragment ONLY when it is
// genuinely empty (i.e. the row was written with outer pipes). A non-empty
// leading/trailing fragment is a real cell and is PRESERVED — so a row with a
// missing outer pipe but an extra trailing cell (e.g.
// "| a | b | c | d | extra") is NOT silently truncated to the expected width.
// Returns null if the line is not a pipe-delimited row.
function tableCells(line: string): string[] | null {
  if (!line.includes('|')) return null;
  const raw = line.split('|');
  if (raw.length < 2) return null;
  // Remove only a genuinely-empty leading fragment (left outer pipe).
  if (raw.length > 0 && raw[0].trim() === '') raw.shift();
  // Remove only a genuinely-empty trailing fragment (right outer pipe).
  if (raw.length > 0 && raw[raw.length - 1].trim() === '') raw.pop();
  if (raw.length === 0) return null;
  return raw.map((c) => c.trim());
}

function isSeparatorRow(cells: readonly string[]): boolean {
  return cells.length > 0 && cells.every((c) => /^:?-{3,}:?$/.test(c.replace(/\s/g, '')) || /^-+$/.test(c));
}

// Return the body of numbered envelope section `n` (## n. ...) up to the next
// "## " heading. Returns '' if not found.
function envelopeSection(text: string, n: number): string {
  return headingSection(text, new RegExp(`^##\\s+${n}\\.\\s`));
}

// Return the body of the first heading matching `startRe`, up to the next
// same-or-higher-level "## " heading. Includes the heading line itself.
function headingSection(text: string, startRe: RegExp): string {
  const lines = text.split('\n');
  let start = -1;
  for (let i = 0; i < lines.length; i++) {
    if (startRe.test(lines[i])) { start = i; break; }
  }
  if (start === -1) return '';
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^##\s/.test(lines[i])) { end = i; break; }
  }
  return lines.slice(start, end).join('\n');
}

// ---------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------

// FIX 1: require the EXACT file set — reject any extra direct entry (incl .md).
function checkFilesPresentAndMarkdown(slice: PrecisFixture, dir: string): void {
  let entries: string[] = [];
  try { entries = readdirSync(dir); } catch {
    fail(`${slice.name} files: fixture directory "${dir}" is unreadable`);
    return;
  }
  const expected = new Set(EXPECTED_FILES);
  const present = new Set();

  for (const e of entries) {
    const full = join(dir, e);
    if (statSync(full).isDirectory()) {
      fail(`${slice.name} files: unexpected subdirectory "${e}" (fixtures are flat: README.md, corpus.md, precis.md only)`);
      continue;
    }
    if (!expected.has(e)) {
      fail(`${slice.name} files: unexpected extra entry "${e}" (fixture dir must contain exactly README.md, corpus.md, precis.md)`);
      continue;
    }
    present.add(e);
  }
  for (const f of EXPECTED_FILES) {
    if (!present.has(f)) fail(`${slice.name} files: required fixture file "${f}" is missing`);
  }
  if (!sliceHasFailure(slice.name, 'files')) {
    pass(`${slice.name} files: exactly README.md, corpus.md, precis.md present; Markdown-only`);
  }
}

function checkAbsoluteForbidden(slice: PrecisFixture, dir: string): void {
  const entries = readdirSync(dir).filter((e) => e.endsWith('.md'));
  let hit = false;
  for (const e of entries) {
    const text = readFileSync(join(dir, e), 'utf8');
    const lines = text.split('\n');
    for (const { label, re } of ABSOLUTE_FORBIDDEN) {
      for (let i = 0; i < lines.length; i++) {
        if (re.test(lines[i])) {
          hit = true;
          fail(`${slice.name} forbidden token: "${label}" found in ${e}:${i + 1}`);
        }
      }
    }
  }
  if (!hit) pass(`${slice.name} forbidden tokens: zero configured absolute-forbidden occurrences`);
}

function checkProjectionBoundary(slice: PrecisFixture, dir: string): void {
  let hit = false;
  for (const f of ['precis.md', 'README.md']) {
    const text = readMaybe(join(dir, f));
    if (text === null) continue;
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const hasTerm = PROJECTION_TERMS.some((re) => re.test(line));
      if (!hasTerm) continue;
      const hasGenVerb = GENERATION_VERBS.test(line);
      if (!hasGenVerb) continue; // naming a projection is fine; only generation matters

      // Exemption is judged on the LINE ITSELF and requires a genuine
      // negation / refusal / hypothetical cue — not merely a word like
      // "deliberately". "deliberately generates a PRD" is still generation.
      if (EXEMPTION_CUES.test(line)) continue;

      hit = true;
      fail(`${slice.name} projection boundary: ${f}:${i + 1} appears to GENERATE a downstream projection rather than refuse it -> ${line.trim()}`);
    }
    for (let i = 0; i < lines.length; i++) {
      for (const re of REAL_EXPORT_MARKERS) {
        if (re.test(lines[i])) {
          hit = true;
          fail(`${slice.name} real-export marker: ${f}:${i + 1} -> ${lines[i].trim()}`);
        }
      }
    }
  }
  if (!hit) pass(`${slice.name} projection boundary: no downstream-projection generation / no real-export markers`);
}

function checkSchemaWording(slice: PrecisFixture, dir: string): void {
  const precis = readMaybe(join(dir, 'precis.md')) || '';
  const readme = readMaybe(join(dir, 'README.md')) || '';
  const blob = `${precis}\n${readme}`;
  const re = /no schema freeze|no schema is frozen|not a final schema|accepted provisional v0 envelope|field structure is provisional/i;
  if (re.test(blob)) {
    pass(`${slice.name} schema wording: explicitly rejects schema finality (provisional v0)`);
  } else {
    fail(`${slice.name} schema wording: no explicit "no schema freeze" / provisional-envelope disclaimer found in precis.md or README.md`);
  }
}

function checkCorpusBoundary(slice: PrecisFixture, dir: string): void {
  const text = readMaybe(join(dir, 'corpus.md'));
  if (text === null) { fail(`${slice.name} corpus boundary: corpus.md missing`); return; }
  const lines = text.split('\n');
  let hit = false;

  for (const id of slice.srcIds) {
    if (!new RegExp(`\\b${id}\\b`).test(text)) {
      hit = true;
      fail(`${slice.name} corpus boundary: required source id ${id} not found in corpus.md`);
    }
  }

  for (let i = 0; i < lines.length; i++) {
    for (const { label, re } of CORPUS_LEAKS) {
      if (re.test(lines[i])) {
        hit = true;
        fail(`${slice.name} corpus boundary: ${label} leaked in corpus.md:${i + 1} -> ${lines[i].trim()}`);
      }
    }
    // Disposition CLASSIFICATION row: a pipe line carrying >= 2 disposition labels.
    const cells = tableCells(lines[i]);
    if (cells) {
      const lc = cells.map((c) => c.toLowerCase());
      const found = VALID_DISPOSITIONS.filter((d) => lc.includes(d));
      if (found.length >= 2) {
        hit = true;
        fail(`${slice.name} corpus boundary: disposition classification row leaked in corpus.md:${i + 1} -> ${lines[i].trim()}`);
      }
    }
  }
  if (!hit) pass(`${slice.name} corpus boundary: source IDs present; no answer-key/label leakage`);
}

function checkEnvelope17(slice: PrecisFixture, dir: string): void {
  const text = readMaybe(join(dir, 'precis.md'));
  if (text === null) { fail(`${slice.name} envelope: precis.md missing`); return; }
  const present = new Set();
  for (const line of text.split('\n')) {
    const m = line.match(/^##\s+(\d+)\.\s/);
    if (m) present.add(Number(m[1]));
  }
  const missing = range(1, 17).filter((n) => !present.has(n));
  if (missing.length === 0) {
    pass(`${slice.name} envelope: all 17 accepted provisional v0 sections present`);
  } else {
    fail(`${slice.name} envelope: missing v0 envelope section(s) ${missing.join(', ')} (of 17)`);
  }
}

// FIX 2: parse §4 inventory rows STRICTLY as 4-column Markdown table rows.
// Reject too many / too few cells, missing/invalid disposition, or more than
// one valid disposition appearing across the row's cells.
function parseInventory(slice: PrecisFixture, precisText: string): InventoryResult {
  const body = envelopeSection(precisText, 4);
  const ids: string[] = [];
  const map = new Map<string, string>();
  for (const rawLine of body.split('\n')) {
    const cells = tableCells(rawLine);
    if (!cells) continue;
    if (isSeparatorRow(cells)) continue;
    // header row: first cell is the literal column name
    if (/^claim[_ ]?id$/i.test(cells[0])) continue;
    // Only treat as a candidate row if it carries a CC-id anywhere.
    const looksLikeClaim = cells.some((c) => /\bCC-\d{3}\b/.test(c));
    if (!looksLikeClaim) continue;

    if (cells.length !== 4) {
      fail(`${slice.name} inventory: malformed candidate row (expected exactly 4 columns, got ${cells.length}) -> ${rawLine.trim()}`);
      continue;
    }
    const id = cells[0];
    if (!/^CC-\d{3}$/.test(id)) {
      fail(`${slice.name} inventory: candidate row id column is not a bare CC-NNN id -> ${rawLine.trim()}`);
      continue;
    }
    // Count valid dispositions across ALL cells; must be exactly one, in col 4.
    const dispInCells = cells.filter((c) => VALID_DISPOSITIONS.includes(c.toLowerCase()));
    if (dispInCells.length !== 1) {
      fail(`${slice.name} inventory: candidate ${id} must have exactly one valid disposition cell, found ${dispInCells.length} (${dispInCells.join(', ') || 'none'}) -> ${rawLine.trim()}`);
      continue;
    }
    const disp = cells[3].toLowerCase();
    if (!VALID_DISPOSITIONS.includes(disp)) {
      fail(`${slice.name} inventory: candidate ${id} disposition column "${cells[3]}" is not a valid disposition -> ${rawLine.trim()}`);
      continue;
    }
    ids.push(id);
    map.set(id, disp);
  }
  return { ids, map };
}

function parseLedger(precisText: string): LedgerResult {
  const body = envelopeSection(precisText, 5);
  const counts = new Map<string, number>();
  let declaredTotal: number | null = null;
  for (const line of body.split('\n')) {
    const tot = line.match(/\|\s*\*\*total\*\*\s*\|\s*\*\*(\d+)\*\*/i);
    if (tot) { declaredTotal = Number(tot[1]); continue; }
    const m = line.match(/^\|\s*([a-z-]+)\s*\|\s*(\d+)\s*\|/);
    if (m && VALID_DISPOSITIONS.includes(m[1])) {
      counts.set(m[1], Number(m[2]));
    }
  }
  return { declaredTotal, counts };
}

function checkInventoryAndAccounting(slice: PrecisFixture, dir: string): void {
  const text = readMaybe(join(dir, 'precis.md'));
  if (text === null) { fail(`${slice.name} inventory: precis.md missing`); return; }

  const { ids, map } = parseInventory(slice, text);

  const dupes = ids.filter((id, idx) => ids.indexOf(id) !== idx);
  if (dupes.length) fail(`${slice.name} inventory: duplicate candidate-claim ID(s): ${[...new Set(dupes)].join(', ')}`);

  const idSet = new Set(ids);
  const missing = slice.claimIds.filter((id) => !idSet.has(id));
  const extra = ids.filter((id) => !slice.claimIds.includes(id));
  if (missing.length) fail(`${slice.name} inventory: missing candidate claim(s): ${missing.join(', ')}`);
  if (extra.length) fail(`${slice.name} inventory: unexpected candidate claim(s): ${extra.join(', ')}`);

  for (const [id, disp] of map.entries()) {
    if (!VALID_DISPOSITIONS.includes(disp)) {
      fail(`${slice.name} inventory: claim ${id} has invalid disposition "${disp}"`);
    }
  }

  const seen = new Set(map.values());
  const uncovered = VALID_DISPOSITIONS.filter((d) => !seen.has(d));
  if (uncovered.length) {
    fail(`${slice.name} coverage: disposition(s) never used: ${uncovered.join(', ')}`);
  }

  const { declaredTotal, counts } = parseLedger(text);
  const invCount = ids.length;
  if (declaredTotal === null) {
    fail(`${slice.name} accounting: no declared ledger total (** total ** row) found in §5`);
  } else if (declaredTotal !== invCount) {
    fail(`${slice.name} accounting: disposition ledger total ${declaredTotal} does not equal inventory count ${invCount}`);
  }
  if (slice.ledgerTotal !== invCount) {
    fail(`${slice.name} accounting: inventory count ${invCount} does not match expected ${slice.ledgerTotal}`);
  }

  let ledgerSum = 0;
  for (const v of counts.values()) ledgerSum += v;
  if (ledgerSum !== invCount) {
    fail(`${slice.name} accounting: ledger disposition counts sum to ${ledgerSum}, not inventory count ${invCount}`);
  }

  const actual = new Map<string, number>();
  for (const disp of map.values()) actual.set(disp, (actual.get(disp) || 0) + 1);
  for (const disp of VALID_DISPOSITIONS) {
    const declared = counts.get(disp) || 0;
    const real = actual.get(disp) || 0;
    if (declared !== real) {
      fail(`${slice.name} accounting: disposition "${disp}" declared ${declared} in ledger but ${real} in inventory`);
    }
  }

  if (!sliceHasFailure(slice.name, 'inventory', 'accounting', 'coverage')) {
    pass(`${slice.name} inventory & accounting: ${invCount} unique claims, each exactly one valid disposition, all 7 dispositions covered, ledger balances (${invCount}=${invCount})`);
  }
}

// FIX 3: STM rows must be ACTUAL table rows inside the isolated matrix section.
function checkStressMatrix(slice: PrecisFixture, dir: string): void {
  if (!slice.requireMatrix) return;
  const text = readMaybe(join(dir, 'precis.md'));
  if (text === null) { fail(`${slice.name} matrix: precis.md missing`); return; }

  const section = headingSection(text, /^##\s+stress-test matrix\s*$/i);
  if (!section) {
    fail(`${slice.name} matrix: no clearly named "## Stress-test matrix" section`);
    return;
  }

  // Collect STM ids that appear as the FIRST cell of a table row in the section.
  const rowCounts = new Map<string, number>();
  for (const line of section.split('\n')) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    const m = cells[0].match(/^(STM-\d+)$/);
    if (m) rowCounts.set(m[1], (rowCounts.get(m[1]) || 0) + 1);
  }

  let hit = false;
  for (const id of slice.matrixIds) {
    const c = rowCounts.get(id) || 0;
    if (c === 0) {
      hit = true;
      fail(`${slice.name} matrix: required stress-test row ${id} not present as a table row in the matrix section`);
    } else if (c > 1) {
      hit = true;
      fail(`${slice.name} matrix: stress-test row ${id} appears ${c} times as a matrix row (expected exactly once)`);
    }
  }
  if (!hit) pass(`${slice.name} matrix: stress-test matrix section present with table rows STM-1..STM-7 (each once)`);
}

// ---------------------------------------------------------------------------
// Slice 4 — cross-section consistency (reference-level, NOT semantic truth)
// ---------------------------------------------------------------------------
// These checks prove the Précis is internally consistent across its sections:
// no phantom / orphan / drifting references. They deliberately do NOT judge
// whether a human disposition is CORRECT — only that references resolve and the
// section accounting agrees. See PRECIS-CONFORMANCE-CHECKER.md for the deferred
// (brittle, prose-policing) checks that are intentionally NOT implemented.

// Lenient §4 collector (does NOT emit failures — strict validation already lives
// in parseInventory/checkInventoryAndAccounting; here we just need the id-set and
// the per-claim source provenance for the consistency checks). For each §4 table
// row whose first cell is a bare CC-NNN, capture its id and the SRC-NNN tokens in
// its source(s) column (col index 2).
function collectInventory(precisText: string): {
  idSet: Set<string>;
  sources: Map<string, Set<string>>;
} {
  const body = envelopeSection(precisText, 4);
  const idSet = new Set<string>();
  const sources = new Map<string, Set<string>>(); // CC-NNN -> Set(SRC-NNN)
  for (const line of body.split('\n')) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    if (!/^CC-\d+$/.test(cells[0])) continue;
    const id = cells[0];
    idSet.add(id);
    const srcCol = cells[2] || '';
    sources.set(id, new Set(srcCol.match(/SRC-\d+/g) || []));
  }
  return { idSet, sources };
}

// Declared source IDs from §2 source inventory (first column SRC-NNN rows).
function collectSourceInventory(precisText: string): Set<string> {
  const body = envelopeSection(precisText, 2);
  const set = new Set<string>();
  for (const line of body.split('\n')) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    if (/^SRC-\d+$/.test(cells[0])) set.add(cells[0]);
  }
  return set;
}

// §5 ledger rows -> [{ disposition, claimIds: [...] }]. Each data row is
// "| <disposition> | <count> | <CC-NNN, CC-NNN, ...> |"; the **total** row and
// the header row are skipped.
function collectLedgerRows(precisText: string): LedgerRow[] {
  const body = envelopeSection(precisText, 5);
  const rows: LedgerRow[] = [];
  for (const line of body.split('\n')) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    if (cells.length < 3) continue;
    const disp = cells[0].toLowerCase();
    if (!VALID_DISPOSITIONS.includes(disp)) continue; // skips header + **total**
    const claimIds = (cells[2].match(/CC-\d+/g) || []);
    rows.push({ disposition: disp, claimIds });
  }
  return rows;
}

// §11 merge-map rows -> [{ canonical, absorbs: [...] }]. Columns:
// "| canonical | absorbs | basis | provenance retained |".
function collectMergeMap(precisText: string): MergeRow[] {
  const body = envelopeSection(precisText, 11);
  const rows: MergeRow[] = [];
  for (const line of body.split('\n')) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    if (!/^CC-\d+$/.test(cells[0])) continue; // skips header row
    const canonical = cells[0];
    const absorbs = ((cells[1] || '').match(/CC-\d+/g) || []);
    rows.push({ canonical, absorbs });
  }
  return rows;
}

// Stress-test matrix rows with their dedicated CC / SRC reference columns,
// located by HEADER NAME (not a fixed index) so column re-ordering can't fool it.
function collectMatrixRefs(precisText: string): MatrixReferences {
  const section = headingSection(precisText, /^##\s+stress-test matrix\s*$/i);
  if (!section) return { present: false, ccRefs: [], srcRefs: [], stmRowIds: new Set() };
  const lines = section.split('\n');
  let ccCol = -1, srcCol = -1, headerSeen = false;
  const ccRefs: MatrixReference[] = []; // { stm, id }
  const srcRefs: MatrixReference[] = []; // { stm, id }
  const stmRowIds = new Set<string>();
  for (const line of lines) {
    const cells = tableCells(line);
    if (!cells || isSeparatorRow(cells)) continue;
    if (!headerSeen && /case[_ ]?id/i.test(cells[0])) {
      headerSeen = true;
      for (let i = 0; i < cells.length; i++) {
        if (/candidate claim id/i.test(cells[i])) ccCol = i;
        if (/source ref/i.test(cells[i])) srcCol = i;
      }
      continue;
    }
    const stm = /^STM-\d+$/.test(cells[0]) ? cells[0] : null;
    if (stm) stmRowIds.add(stm);
    if (ccCol >= 0 && cells[ccCol]) {
      for (const id of cells[ccCol].match(/CC-\d+/g) || []) ccRefs.push({ stm, id });
    }
    if (srcCol >= 0 && cells[srcCol]) {
      for (const id of cells[srcCol].match(/SRC-\d+/g) || []) srcRefs.push({ stm, id });
    }
  }
  return { present: true, ccCol, srcCol, ccRefs, srcRefs, stmRowIds };
}

// Build the body of precis.md with §4 and §5 removed, so C2 (orphan) can test
// that a claim appears at least once OUTSIDE the inventory + ledger. Loose by
// design: presence of the CC-NNN token anywhere outside §4/§5, no heading,
// wording, or disposition-themed location is required.
function textOutsideInventoryAndLedger(precisText: string): string {
  const s4 = envelopeSection(precisText, 4);
  const s5 = envelopeSection(precisText, 5);
  let out = precisText;
  if (s4) out = out.replace(s4, '');
  if (s5) out = out.replace(s5, '');
  return out;
}

function checkCrossSectionConsistency(slice: PrecisFixture, dir: string): void {
  const text = readMaybe(join(dir, 'precis.md'));
  if (text === null) { fail(`${slice.name} consistency: precis.md missing`); return; }

  const { idSet, sources } = collectInventory(text);
  const srcSet = collectSourceInventory(text);
  let hit = false;

  // C1 — no phantom CC-NNN: every CC token in precis.md exists in §4 inventory.
  for (const m of text.matchAll(/\bCC-\d+\b/g)) {
    if (!idSet.has(m[0])) {
      hit = true;
      fail(`${slice.name} consistency C1 (phantom CC): ${m[0]} is referenced but not in the §4 candidate-claim inventory`);
    }
  }

  // C2 — no orphan claim: every §4 claim appears at least once OUTSIDE §4+§5.
  const outside = textOutsideInventoryAndLedger(text);
  for (const id of idSet) {
    if (!new RegExp(`\\b${id}\\b`).test(outside)) {
      hit = true;
      fail(`${slice.name} consistency C2 (orphan claim): ${id} is in the §4 inventory but never referenced outside §4/§5`);
    }
  }

  // C3 — §5 ledger ↔ §4 disposition consistency + id-set equality.
  const ledgerRows = collectLedgerRows(text);
  const ledgerIds = new Set<string>();
  for (const row of ledgerRows) {
    for (const cid of row.claimIds) {
      ledgerIds.add(cid);
      if (!idSet.has(cid)) {
        hit = true;
        fail(`${slice.name} consistency C3 (ledger drift): §5 lists ${cid} under "${row.disposition}" but ${cid} is not in the §4 inventory`);
      }
    }
  }
  // disposition agreement: build §4 id->disposition from the lenient §4 parse
  const invDisp = new Map<string, string>();
  {
    const body = envelopeSection(text, 4);
    for (const line of body.split('\n')) {
      const cells = tableCells(line);
      if (!cells || isSeparatorRow(cells)) continue;
      if (!/^CC-\d+$/.test(cells[0])) continue;
      const d = (cells[3] || '').toLowerCase();
      if (VALID_DISPOSITIONS.includes(d)) invDisp.set(cells[0], d);
    }
  }
  for (const row of ledgerRows) {
    for (const cid of row.claimIds) {
      if (!idSet.has(cid)) continue; // already reported by C3 phantom branch
      const d4 = invDisp.get(cid);
      if (d4 && d4 !== row.disposition) {
        hit = true;
        fail(`${slice.name} consistency C3 (disposition drift): §5 ledger lists ${cid} under "${row.disposition}" but §4 records it as "${d4}"`);
      }
    }
  }
  for (const id of idSet) {
    if (!ledgerIds.has(id)) {
      hit = true;
      fail(`${slice.name} consistency C3 (ledger coverage): §4 claim ${id} does not appear in any §5 ledger disposition row`);
    }
  }

  // C4 — no phantom SRC-NNN: every SRC token in precis.md exists in §2.
  for (const m of text.matchAll(/\bSRC-\d+\b/g)) {
    if (!srcSet.has(m[0])) {
      hit = true;
      fail(`${slice.name} consistency C4 (phantom SRC): ${m[0]} is referenced but not in the §2 source inventory`);
    }
  }

  // C5 / C6 — matrix CC and SRC reference columns must resolve.
  const matrix = collectMatrixRefs(text);
  if (slice.requireMatrix && matrix.present) {
    for (const { stm, id } of matrix.ccRefs) {
      if (!idSet.has(id)) {
        hit = true;
        fail(`${slice.name} consistency C5 (matrix CC ref): ${stm || 'matrix row'} references ${id}, not in the §4 inventory`);
      }
    }
    for (const { stm, id } of matrix.srcRefs) {
      if (!srcSet.has(id)) {
        hit = true;
        fail(`${slice.name} consistency C6 (matrix SRC ref): ${stm || 'matrix row'} references ${id}, not in the §2 source inventory`);
      }
    }
  }

  // C7 — no phantom STM-N: every STM token in precis.md is a real matrix row.
  // (For a slice with no matrix, the valid set is empty: any STM token is phantom.)
  for (const m of text.matchAll(/\bSTM-\d+\b/g)) {
    if (!matrix.stmRowIds.has(m[0])) {
      hit = true;
      fail(`${slice.name} consistency C7 (phantom STM): ${m[0]} is referenced but is not an actual stress-test matrix row`);
    }
  }

  // C8 — merge provenance retention: canonical claim's §4 source-set must be a
  // superset of every absorbed claim's §4 source-set (no provenance dropped).
  for (const { canonical, absorbs } of collectMergeMap(text)) {
    const canonSrc = sources.get(canonical) || new Set();
    for (const absorbed of absorbs) {
      const absSrc = sources.get(absorbed) || new Set();
      const dropped = [...absSrc].filter((s) => !canonSrc.has(s));
      if (dropped.length) {
        hit = true;
        fail(`${slice.name} consistency C8 (merge provenance): canonical ${canonical} drops source provenance ${dropped.join(', ')} retained by absorbed claim ${absorbed}`);
      }
    }
  }

  if (!hit) {
    pass(`${slice.name} cross-section consistency: no phantom/orphan CC·SRC·STM refs, §5↔§4 dispositions agree, matrix refs resolve, merge provenance retained (C1–C8)`);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

if (!OPTIONS.json) {
  console.log('Aleph Précis Conformance Checker — v0 envelope (Slice 3) + cross-section consistency (Slice 4)');
  console.log('(validates the accepted provisional v0 envelope; this is NOT a schema freeze)');
  if (REPO_ROOT !== DEFAULT_ROOT) console.log(`(root override: ${REPO_ROOT})`);
  console.log('');
}

if (!existsSync(FIXTURES_DIR)) {
  const message = `fixtures K1.1 (declaration): fixtures directory not found at ${FIXTURES_DIR}`;
  fail(message, 'K1.1', 'fixtures');
  if (OPTIONS.json) {
    console.log(JSON.stringify({ result: 'FAIL', checks }, null, 2));
  } else {
    console.error(`FAIL: fixtures directory not found at ${FIXTURES_DIR}`);
  }
  process.exit(1);
}

const discovered = discoverFixtures();
const legacyOnly = discovered.precis.length === 0 && discovered.delegated.length === 0;

for (const slice of [...SLICES, ...discovered.precis]) {
  const dir = slice.dir || join(FIXTURES_DIR, slice.name);
  if (!existsSync(dir)) {
    fail(`${slice.name}: fixture directory missing at ${dir}`);
    continue;
  }
  checkFilesPresentAndMarkdown(slice, dir);
  checkAbsoluteForbidden(slice, dir);
  checkProjectionBoundary(slice, dir);
  checkSchemaWording(slice, dir);
  checkCorpusBoundary(slice, dir);
  checkEnvelope17(slice, dir);
  checkInventoryAndAccounting(slice, dir);
  checkStressMatrix(slice, dir);
  checkCrossSectionConsistency(slice, dir);
}

for (const fixture of discovered.delegated) {
  const report = validateRun({
    root: REPO_ROOT,
    run: fixture.dir,
    kind: fixture.kind,
  });
  for (const check of report.checks) {
    checks.push(check);
    const message = `${check.scope} ${check.id} ${check.message}`;
    if (check.status === 'PASS') passes.push(message);
    else failures.push(message);
  }
}

if (failures.length) {
  if (OPTIONS.json) {
    console.log(JSON.stringify({ result: 'FAIL', checks }, null, 2));
  } else {
    console.log('PASSED CHECKS:');
    for (const p of passes) console.log(`  PASS ${p}`);
    console.log('');
    console.log('FAILURES:');
    for (const f of failures) console.log(`  FAIL ${f}`);
    console.log(`\nRESULT: FAIL (${failures.length} failure${failures.length === 1 ? '' : 's'})`);
  }
  process.exit(1);
}

if (OPTIONS.json) {
  console.log(JSON.stringify({ result: 'PASS', checks }, null, 2));
} else {
  console.log('PASSED CHECKS:');
  for (const p of passes) console.log(`  PASS ${p}`);
  console.log('');
  console.log(
    legacyOnly
      ? 'RESULT: PASS — both fixtures conform to the accepted provisional v0 envelope.'
      : 'RESULT: PASS — all discovered fixtures conform to their declared kernels.',
  );
}
process.exit(0);
