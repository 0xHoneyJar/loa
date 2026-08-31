#!/usr/bin/env node

import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import {
  contractExemplarToJsonSchema,
  validateWorkerReturnContract,
  type WorkerJsonValue,
} from './lib/worker-return-contract.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '..');
const PROMPT_FILES = [
  'docs/architecture/prompts/verifier-lenses.md',
  'docs/architecture/prompts/workers-arms-synthesis.md',
  'docs/architecture/prompts/workers-intake-extraction.md',
  'docs/architecture/prompts/workers-judgment.md',
] as const;

interface CaseResult {
  name: string;
  error?: string;
}

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function runCase(results: CaseResult[], name: string, fn: () => void): void {
  try {
    fn();
    results.push({ name });
  } catch (error) {
    results.push({
      name,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

function outputContracts(): unknown[] {
  const contracts: unknown[] = [];
  const pattern = /\*\*Output contract[^*]*\*\*\s*```json\s*([\s\S]*?)\s*```/gu;
  for (const path of PROMPT_FILES) {
    const markdown = readFileSync(join(REPO_ROOT, path), 'utf8');
    for (const match of markdown.matchAll(pattern)) {
      contracts.push(JSON.parse(match[1]) as unknown);
    }
  }
  return contracts;
}

function materialize(example: unknown, key = ''): WorkerJsonValue {
  if (example === null) return null;
  if (typeof example === 'boolean' || typeof example === 'number') return example;
  if (typeof example === 'string') {
    if (key === 'rationale') return 'The attached evidence supports this result.';
    if (!example) return 'value';
    const alternatives = example.includes('|')
      ? example.split('|')
      : example.split('/').every((part) => part.includes('…'))
        ? example.split('/')
        : [example];
    return alternatives[0].replaceAll('…', '001');
  }
  if (Array.isArray(example)) {
    return example.length > 0 ? [materialize(example[0])] : [];
  }
  if (typeof example === 'object' && example !== null) {
    return Object.fromEntries(Object.entries(example).map(
      ([entryKey, value]) => [entryKey, materialize(value, entryKey)],
    )) as { [key: string]: WorkerJsonValue };
  }
  throw new Error(`unsupported exemplar type ${typeof example}`);
}

function json(value: unknown): string {
  return JSON.stringify(value);
}

function main(): number {
  const results: CaseResult[] = [];
  const contracts = outputContracts();

  runCase(results, 'all fourteen pinned prompt contracts accept a valid materialization', () => {
    expect(contracts.length === 14, `expected 14 output contracts, found ${contracts.length}`);
    contracts.forEach((contract, index) => {
      const validation = validateWorkerReturnContract(
        json(materialize(contract)),
        contract,
      );
      expect(
        validation.result === 'PASS',
        `contract ${String(index + 1)} rejected valid data: ${validation.errors.join('; ')}`,
      );
    });
  });

  runCase(results, 'typed-relation producer contract closes adopted vocabularies', () => {
    const relationContract = contracts.find((candidate) => (
      typeof candidate === 'object'
      && candidate !== null
      && 'relation_proposals' in candidate
    ));
    expect(relationContract, 'typed-relation producer contract was not discovered');
    const validRelation = materialize(relationContract) as {
      relation_proposals: Array<Record<string, WorkerJsonValue>>;
    };
    expect(
      validateWorkerReturnContract(json(validRelation), relationContract).result === 'PASS',
      'valid typed-relation producer materialization failed',
    );
    validRelation.relation_proposals[0].family = 'evidence-support';
    const invalid = validateWorkerReturnContract(json(validRelation), relationContract);
    expect(invalid.result === 'FAIL', 'undeclared relation family passed');
    expect(
      invalid.errors.some((error) => /Core literals/u.test(error)),
      'undeclared relation family omitted its closed-vocabulary diagnostic',
    );
  });

  runCase(results, 'schema projection closes objects and requires every key', () => {
    const schema = contractExemplarToJsonSchema({
      verdict: 'upheld|refuted|cannot-determine',
      rationale: '',
      flags: [],
    }) as Record<string, unknown>;
    expect(schema.additionalProperties === false, 'schema permits additional properties');
    expect(
      json(schema.required) === json(['verdict', 'rationale', 'flags']),
      'schema required keys drifted',
    );
  });

  const contract = {
    claim_id: 'CC-…',
    count: 0,
    rationale: '',
    note: null,
    flags: [],
  };
  const valid = {
    claim_id: 'CC-001',
    count: 1,
    rationale: 'The packet supports this result.',
    note: null,
    flags: [],
  };

  runCase(results, 'raw worker return must be JSON', () => {
    const validation = validateWorkerReturnContract('{', contract);
    expect(validation.result === 'FAIL', 'malformed JSON passed');
    expect(validation.errors.some((error) => /invalid JSON/u.test(error)), 'parse error missing');
  });

  runCase(results, 'duplicate keys and invalid Unicode fail closed', () => {
    const duplicate = validateWorkerReturnContract(
      '{"claim_id":"CC-001","count":1,"count":2,"rationale":"Valid.","note":null,"flags":[]}',
      contract,
    );
    expect(duplicate.result === 'FAIL', 'duplicate object key passed');
    expect(
      duplicate.errors.some((error) => /duplicate object key/u.test(error)),
      'duplicate-key error missing',
    );
    const invalidUtf8 = validateWorkerReturnContract(
      Buffer.from([
        ...Buffer.from('{"claim_id":"', 'utf8'),
        0xff,
        ...Buffer.from('","count":1,"rationale":"Valid.","note":null,"flags":[]}', 'utf8'),
      ]),
      contract,
    );
    expect(invalidUtf8.result === 'FAIL', 'invalid UTF-8 passed');
    expect(
      invalidUtf8.errors.includes('worker return is not valid UTF-8'),
      'invalid UTF-8 error missing',
    );
    const unpaired = validateWorkerReturnContract(
      '{"claim_id":"CC-001","count":1,"rationale":"\\ud800","note":null,"flags":[]}',
      contract,
    );
    expect(unpaired.result === 'FAIL', 'unpaired surrogate passed');
    expect(
      unpaired.errors.some((error) => /unpaired UTF-16 surrogate/u.test(error)),
      'unpaired-surrogate error missing',
    );
  });

  runCase(results, 'contract roots must be objects', () => {
    const validation = validateWorkerReturnContract('[]', []);
    expect(validation.result === 'FAIL', 'array contract root passed');
    expect(validation.errors.includes('Core output contract root must be an object'), 'root error missing');
  });

  runCase(results, 'missing and additional fields fail closed', () => {
    const missing = { ...valid } as Record<string, unknown>;
    delete missing.count;
    const missingReport = validateWorkerReturnContract(json(missing), contract);
    expect(missingReport.errors.includes('$.count is missing'), 'missing key passed');
    const extraReport = validateWorkerReturnContract(
      json({ ...valid, surprise: true }),
      contract,
    );
    expect(extraReport.errors.includes('$.surprise is not allowed'), 'extra key passed');
  });

  runCase(results, 'Core literal placeholders and alternatives are enforced', () => {
    const placeholder = validateWorkerReturnContract(
      json({ ...valid, claim_id: 'claim-1' }),
      contract,
    );
    expect(placeholder.result === 'FAIL', 'wrong ID literal passed');
    const alternatives = validateWorkerReturnContract(
      json({ verdict: 'maybe' }),
      { verdict: 'upheld|refuted|cannot-determine' },
    );
    expect(alternatives.result === 'FAIL', 'wrong alternative passed');
  });

  runCase(results, 'judgment rationales require one to three complete sentences', () => {
    const incomplete = validateWorkerReturnContract(
      json({ ...valid, rationale: 'fragment' }),
      contract,
    );
    expect(incomplete.result === 'FAIL', 'incomplete rationale passed');
    const long = validateWorkerReturnContract(
      json({ ...valid, rationale: 'One. Two. Three. Four.' }),
      contract,
    );
    expect(long.result === 'FAIL', 'four-sentence rationale passed');
  });

  runCase(results, 'numbers, optional text, and string arrays retain their exact types', () => {
    expect(
      validateWorkerReturnContract(json({ ...valid, count: -1 }), contract).result === 'FAIL',
      'negative count passed',
    );
    expect(
      validateWorkerReturnContract(json({ ...valid, count: 1.5 }), contract).result === 'FAIL',
      'fractional count passed',
    );
    expect(
      validateWorkerReturnContract(json({ ...valid, note: 'known' }), contract).result === 'PASS',
      'nonempty optional text failed',
    );
    expect(
      validateWorkerReturnContract(json({ ...valid, flags: [1] }), contract).result === 'FAIL',
      'non-string flag passed',
    );
  });

  runCase(results, 'validation is deterministic and returns only a passing canonical value', () => {
    const first = validateWorkerReturnContract(json(valid), contract);
    const second = validateWorkerReturnContract(json(valid), contract);
    expect(json(first) === json(second), 'repeat validation changed');
    expect(first.result === 'PASS' && first.canonicalValue !== null, 'valid value not returned');
    const failed = validateWorkerReturnContract(json({ ...valid, count: -1 }), contract);
    expect(failed.canonicalValue === null, 'failed value escaped validation');
  });

  runCase(results, 'CLI emits digested canonical JSON on pass and exits one on failure', () => {
    const root = mkdtempSync(join(tmpdir(), 'aleph-worker-contract-'));
    try {
      const contractPath = join(root, 'contract.json');
      const returnPath = join(root, 'return.json');
      writeFileSync(contractPath, `${json(contract)}\n`);
      writeFileSync(returnPath, `${json(valid)}\n`);
      const command = [
        join(REPO_ROOT, 'scripts', 'validate-worker-return.ts'),
        '--contract',
        contractPath,
        '--return',
        returnPath,
        '--json',
      ];
      const passed = spawnSync(process.execPath, command, { encoding: 'utf8' });
      expect(passed.status === 0, `valid CLI return failed: ${passed.stderr}`);
      const report = JSON.parse(passed.stdout) as Record<string, unknown>;
      expect(report.result === 'PASS', 'CLI report did not pass');
      expect(
        typeof report.contract_digest === 'string'
          && typeof report.return_digest === 'string',
        'CLI report omitted digests',
      );
      expect(report.canonical_value !== null, 'CLI report omitted canonical value');

      writeFileSync(returnPath, `${json({ ...valid, extra: true })}\n`);
      const failed = spawnSync(process.execPath, command, { encoding: 'utf8' });
      expect(failed.status === 1, `invalid CLI return exited ${String(failed.status)}`);
      const failedReport = JSON.parse(failed.stdout) as Record<string, unknown>;
      expect(failedReport.result === 'FAIL', 'CLI failure report passed');
      expect(failedReport.canonical_value === null, 'CLI failure leaked canonical value');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  const failures = results.filter((result) => result.error);
  for (const result of results) {
    console.log(`${result.error ? 'not ok' : 'ok'} - ${result.name}`);
    if (result.error) console.error(`  ${result.error}`);
  }
  console.log(
    `Worker return contract: ${String(results.length - failures.length)}/`
    + `${String(results.length)} passed`,
  );
  return failures.length === 0 ? 0 : 1;
}

if (resolve(process.argv[1] || '') === SCRIPT_PATH) process.exitCode = main();
