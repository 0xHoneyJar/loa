#!/usr/bin/env node

import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  attestClaudeCodeHost,
  buildClaudeCodeWorkerPrompt,
  invokeClaudeCodeWorker,
  isProviderPinnedClaudeModelId,
  parseClaudeCodeStream,
  validateClaudeCodeHostCapabilities,
  type ClaudeCodeSpawn,
  type HostSpawnOptions,
  type HostSpawnResult,
} from '../src/claude-code-host.ts';
import {
  sha256Digest,
  stableJson,
  stableJsonBytes,
} from '../src/fs.ts';
import { runLoaPreflight } from '../src/preflight.ts';
import { loadLoaProfile } from '../src/runtime-snapshot.ts';
import {
  LOA_WORKER_REQUEST_FORMAT,
  type JsonValue,
  type WorkerRequest,
} from '../src/types.ts';
import { contractExemplarToJsonSchema } from '../src/worker-return.ts';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = resolve(dirname(SCRIPT_PATH), '../../..');
const MODEL = 'claude-opus-4-8';
const CLAUDE_VERSION = '2.1.214';
const SESSION_ID = '123e4567-e89b-42d3-a456-426614174000';
const TEST_ENVIRONMENT = {
  AWS_BEARER_TOKEN_BEDROCK: 'fixture-secret-not-a-real-token',
  AWS_REGION: 'us-east-1',
  CLAUDE_CODE_USE_BEDROCK: '1',
  SHOULD_NOT_CROSS_SANDBOX: 'forbidden',
};

interface CaseResult {
  name: string;
  status: 'PASS' | 'FAIL';
  error?: string;
}

function expect(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function expectThrows(
  action: () => unknown,
  pattern: RegExp,
  label: string,
): void {
  try {
    action();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (pattern.test(message)) return;
    throw new Error(`${label} failed with unexpected diagnostic: ${message}`);
  }
  throw new Error(`${label} unexpectedly passed`);
}

function runCase(results: CaseResult[], name: string, action: () => void): void {
  try {
    action();
    results.push({ name, status: 'PASS' });
  } catch (error) {
    results.push({
      name,
      status: 'FAIL',
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

function baseEvents(
  output: JsonValue,
  model = MODEL,
  version = CLAUDE_VERSION,
): Record<string, unknown>[] {
  const toolId = 'toolu_fixture_structured_output';
  return [
    {
      type: 'system',
      subtype: 'init',
      cwd: '/worker',
      session_id: SESSION_ID,
      tools: ['StructuredOutput'],
      mcp_servers: [],
      model,
      permissionMode: 'dontAsk',
      slash_commands: [],
      claude_code_version: version,
      skills: [],
      plugins: [],
    },
    {
      type: 'assistant',
      message: {
        model,
        role: 'assistant',
        content: [{ type: 'text', text: 'Returning the required value.' }],
        stop_reason: null,
        stop_details: null,
      },
      session_id: SESSION_ID,
    },
    {
      type: 'assistant',
      message: {
        model,
        role: 'assistant',
        content: [{
          type: 'tool_use',
          id: toolId,
          name: 'StructuredOutput',
          input: output,
        }],
        stop_reason: null,
        stop_details: null,
      },
      session_id: SESSION_ID,
    },
    {
      type: 'user',
      message: {
        role: 'user',
        content: [{
          type: 'tool_result',
          tool_use_id: toolId,
          content: 'Structured output provided successfully',
        }],
      },
      session_id: SESSION_ID,
    },
    {
      type: 'result',
      subtype: 'success',
      is_error: false,
      result: stableJson(output),
      stop_reason: 'tool_use',
      session_id: SESSION_ID,
      total_cost_usd: 0.001,
      usage: {
        input_tokens: 10,
        output_tokens: 5,
        cache_read_input_tokens: 0,
        cache_creation_input_tokens: 0,
        iterations: [],
      },
      modelUsage: {
        [model]: {
          inputTokens: 10,
          outputTokens: 5,
          cacheReadInputTokens: 0,
          cacheCreationInputTokens: 0,
          costUSD: 0.001,
          contextWindow: 200000,
          maxOutputTokens: 64000,
        },
      },
      permission_denials: [],
      structured_output: output,
      terminal_reason: 'completed',
    },
  ];
}

function stream(events: Record<string, unknown>[]): Buffer {
  return Buffer.from(`${events.map((event) => JSON.stringify(event)).join('\n')}\n`, 'utf8');
}

function fakeExecutable(path: string, contents: string): void {
  writeFileSync(path, contents, { mode: 0o755 });
  chmodSync(path, 0o755);
}

function argValue(args: string[], name: string): string {
  const index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) {
    throw new Error(`fixture spawn omitted ${name}`);
  }
  return args[index + 1];
}

function fixtureSpawn(
  claudePath: string,
  sandboxPath: string,
  invocations: Array<{
    args: string[];
    options: HostSpawnOptions;
  }>,
  outputFor: (args: string[], options: HostSpawnOptions) => JsonValue = () => ({
    attestation: 'ok',
  }),
): ClaudeCodeSpawn {
  return (
    executable: string,
    args: string[],
    options: HostSpawnOptions,
  ): HostSpawnResult => {
    if (executable === claudePath && stableJson(args) === stableJson(['--version'])) {
      return {
        status: 0,
        signal: null,
        stdout: Buffer.from(`${CLAUDE_VERSION} (Claude Code)\n`, 'utf8'),
        stderr: Buffer.alloc(0),
      };
    }
    if (executable === sandboxPath && stableJson(args) === stableJson(['--version'])) {
      return {
        status: 0,
        signal: null,
        stdout: Buffer.from('bubblewrap 0.9.0\n', 'utf8'),
        stderr: Buffer.alloc(0),
      };
    }
    if (executable !== sandboxPath) {
      throw new Error(`fixture spawn received unexpected executable ${executable}`);
    }
    invocations.push({ args: [...args], options });
    const model = argValue(args, '--model');
    return {
      status: 0,
      signal: null,
      stdout: stream(baseEvents(outputFor(args, options), model)),
      stderr: Buffer.alloc(0),
    };
  };
}

function clonedEvents(output: JsonValue = { attestation: 'ok' }): Record<string, unknown>[] {
  return JSON.parse(JSON.stringify(baseEvents(output))) as Record<string, unknown>[];
}

export function runClaudeCodeHostTests(): {
  result: 'PASS' | 'FAIL';
  cases: CaseResult[];
  real_model_calls: 'none';
} {
  const results: CaseResult[] = [];
  const tempRoot = mkdtempSync(join(tmpdir(), 'aleph-claude-host-tests-'));
  try {
    const claudePath = join(tempRoot, 'claude');
    const sandboxPath = join(tempRoot, 'bwrap');
    fakeExecutable(claudePath, 'fixture claude binary\n');
    fakeExecutable(sandboxPath, 'fixture bubblewrap binary\n');
    const profile = loadLoaProfile(
      join(REPO_ROOT, 'adapters', 'loa', 'profiles', 'loa-default.json'),
    ).value;
    const calls: Array<{ args: string[]; options: HostSpawnOptions }> = [];
    const spawn = fixtureSpawn(claudePath, sandboxPath, calls);
    const host = attestClaudeCodeHost({
      profile,
      modelId: MODEL,
      provider: 'amazon-bedrock',
      claudePath,
      sandboxPath,
      attestedAt: '2040-01-02T03:04:05.000Z',
      timeoutMs: '600000',
      maxOutputBytes: '1048576',
      maxBudgetUsd: '1.00',
      spawn,
      environment: TEST_ENVIRONMENT,
    });

    runCase(results, 'provider snapshot IDs reject aliases and preserve exact versions', () => {
      for (const accepted of [
        'claude-opus-4-6',
        'claude-opus-4-8',
        'claude-sonnet-5',
        'claude-sonnet-4-5-20250929',
      ]) {
        expect(isProviderPinnedClaudeModelId(accepted), `rejected pinned ID ${accepted}`);
      }
      for (const rejected of [
        'opus',
        'latest',
        'claude-opus-4-5',
        'claude-opus',
        'us.anthropic.claude-opus-4-8',
      ]) {
        expect(!isProviderPinnedClaudeModelId(rejected), `accepted alias ${rejected}`);
      }
      for (const model of Object.values(host.models)) {
        expect(
          model.identity_kind === 'provider-pinned-snapshot'
            && model.model_id === MODEL
            && model.resolved_version === MODEL
            && model.fallback === false,
          'attested model identity is aliased, fabricated, or fallback-enabled',
        );
      }
    });

    runCase(results, 'attestation binds binaries policy probes and minimal environment', () => {
      validateClaudeCodeHostCapabilities(host);
      expect(host.runtime !== null, 'attestation omitted live runtime');
      expect(host.runtime.probes.length === 3, 'attestation did not probe each distinct effort');
      expect(calls.length === 3, 'attestation made an unexpected number of model probes');
      for (const call of calls) {
        const environmentKeys = Object.keys(call.options.env || {}).sort();
        expect(
          stableJson(environmentKeys) === stableJson([
            'AWS_BEARER_TOKEN_BEDROCK',
            'AWS_REGION',
            'CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK',
            'CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK',
            'CLAUDE_CODE_NO_MODEL_FALLBACK',
            'CLAUDE_CODE_USE_BEDROCK',
            'HOME',
            'PATH',
          ].sort()),
          `sandbox environment widened: ${environmentKeys.join(', ')}`,
        );
        expect(
          !stableJson(call.args).includes('/etc/hostname')
            && call.args.includes('--disable-userns')
            && call.args.includes('--unshare-all')
            && call.args.includes('--share-net')
            && argValue(call.args, '--tools') === ''
            && call.args.includes('--bare')
            && call.args.includes('--no-session-persistence'),
          'sandbox or Claude invocation weakened isolation',
        );
      }
    });

    runCase(results, 'live no-fallback controls pass complete Loa preflight', () => {
      const receiptPath = join(tempRoot, 'host-capabilities.json');
      writeFileSync(receiptPath, stableJsonBytes(host), { mode: 0o600 });
      const preflight = runLoaPreflight({
        root: REPO_ROOT,
        capabilities: receiptPath,
      });
      expect(
        preflight.result === 'PASS'
          && preflight.evidenceClass === 'runtime'
          && preflight.runtimeReady,
        preflight.checks
          .flatMap((check) => check.problems)
          .join('; '),
      );
    });

    runCase(results, 'binary drift invalidates the live host receipt', () => {
      const original = readFileSync(claudePath);
      writeFileSync(claudePath, 'substituted claude binary\n', { mode: 0o755 });
      expectThrows(
        () => validateClaudeCodeHostCapabilities(host),
        /digest changed/iu,
        'substituted Claude binary',
      );
      writeFileSync(claudePath, original, { mode: 0o755 });
      chmodSync(claudePath, 0o755);
      validateClaudeCodeHostCapabilities(host);
    });

    runCase(results, 'Core contract exemplars become closed structured-output schemas', () => {
      const schema = contractExemplarToJsonSchema({
        verdict: 'upheld|refuted|cannot-determine',
        rationale: '',
        attacks_tried: [''],
        missing_for_determination: null,
        flags: [],
      });
      expect(
        isRecord(schema)
          && schema.type === 'object'
          && schema.additionalProperties === false
          && Array.isArray(schema.required)
          && schema.required.length === 5,
        'contract schema is not a closed required object',
      );
    });

    runCase(results, 'valid Claude stream binds session model cost and structured output', () => {
      const raw = stream(baseEvents({ attestation: 'ok' }));
      const parsed = parseClaudeCodeStream(raw, MODEL, CLAUDE_VERSION);
      expect(parsed.evidence.session_id === SESSION_ID, 'session ID was not retained');
      expect(parsed.evidence.observed_model === MODEL, 'observed model was not retained');
      expect(parsed.evidence.total_cost_usd === 0.001, 'cost evidence was not retained');
      expect(
        parsed.evidence.event_stream_digest === sha256Digest(raw),
        'event stream digest is incorrect',
      );
      expect(
        stableJson(parsed.structuredOutput) === stableJson({ attestation: 'ok' }),
        'structured output changed during parsing',
      );
    });

    runCase(results, 'valid Claude stream can return JSON null without losing tool evidence', () => {
      const parsed = parseClaudeCodeStream(stream(baseEvents(null)), MODEL, CLAUDE_VERSION);
      expect(parsed.structuredOutput === null, 'JSON null structured output changed');
    });

    const negativeStreams: Array<{
      name: string;
      pattern: RegExp;
      mutate: (events: Record<string, unknown>[]) => Buffer;
    }> = [
      {
        name: 'fallback event',
        pattern: /forbidden system event/iu,
        mutate(events) {
          events.splice(1, 0, {
            type: 'system',
            subtype: 'model_refusal_fallback',
            original_model: MODEL,
            fallback_model: 'claude-sonnet-4-6',
          });
          return stream(events);
        },
      },
      {
        name: 'wrong init model',
        pattern: /pinned bare worker boundary/iu,
        mutate(events) {
          events[0].model = 'claude-sonnet-4-6';
          return stream(events);
        },
      },
      {
        name: 'non-string init tool',
        pattern: /pinned bare worker boundary/iu,
        mutate(events) {
          events[0].tools = ['StructuredOutput', { name: 'Read' }];
          return stream(events);
        },
      },
      {
        name: 'wrong assistant model',
        pattern: /assistant event changed model/iu,
        mutate(events) {
          (events[1].message as Record<string, unknown>).model = 'claude-sonnet-4-6';
          return stream(events);
        },
      },
      {
        name: 'fallback model usage',
        pattern: /fallback-tainted/iu,
        mutate(events) {
          const result = events[events.length - 1];
          (result.modelUsage as Record<string, unknown>)['claude-sonnet-4-6'] = {
            inputTokens: 1,
            outputTokens: 1,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0,
            costUSD: 0.01,
            contextWindow: 200000,
            maxOutputTokens: 64000,
          };
          return stream(events);
        },
      },
      {
        name: 'refusal',
        pattern: /assistant event changed model|refusal/iu,
        mutate(events) {
          (events[1].message as Record<string, unknown>).stop_reason = 'refusal';
          return stream(events);
        },
      },
      {
        name: 'permission denial',
        pattern: /denied/iu,
        mutate(events) {
          events[events.length - 1].permission_denials = ['Read'];
          return stream(events);
        },
      },
      {
        name: 'missing tool result',
        pattern: /incomplete/iu,
        mutate(events) {
          events.splice(3, 1);
          return stream(events);
        },
      },
      {
        name: 'malformed tool result',
        pattern: /acknowledgement/iu,
        mutate(events) {
          const content = (events[3].message as Record<string, unknown>).content as Array<Record<string, unknown>>;
          content[0].is_error = 'false';
          return stream(events);
        },
      },
      {
        name: 'mismatched structured output',
        pattern: /disagrees/iu,
        mutate(events) {
          events[events.length - 1].structured_output = { attestation: 'wrong' };
          return stream(events);
        },
      },
      {
        name: 'inconsistent aggregate usage',
        pattern: /aggregate usage disagrees/iu,
        mutate(events) {
          const result = events[events.length - 1];
          (result.usage as Record<string, unknown>).input_tokens = 11;
          return stream(events);
        },
      },
      {
        name: 'inconsistent aggregate cost',
        pattern: /aggregate usage disagrees/iu,
        mutate(events) {
          events[events.length - 1].total_cost_usd = 0.002;
          return stream(events);
        },
      },
      {
        name: 'unknown tool',
        pattern: /unapproved/iu,
        mutate(events) {
          const content = (events[2].message as Record<string, unknown>).content as Array<Record<string, unknown>>;
          content[0].name = 'Read';
          return stream(events);
        },
      },
      {
        name: 'truncated stream',
        pattern: /truncated/iu,
        mutate(events) {
          return Buffer.from(events.map((event) => JSON.stringify(event)).join('\n'), 'utf8');
        },
      },
      {
        name: 'malformed JSON',
        pattern: /invalid JSON/iu,
        mutate(events) {
          const valid = stream(events).toString('utf8');
          return Buffer.from(`${valid.slice(0, valid.indexOf('\n'))}\n{\n`, 'utf8');
        },
      },
    ];
    for (const negative of negativeStreams) {
      runCase(results, `stream parser rejects ${negative.name}`, () => {
        expectThrows(
          () => parseClaudeCodeStream(
            negative.mutate(clonedEvents()),
            MODEL,
            CLAUDE_VERSION,
          ),
          negative.pattern,
          negative.name,
        );
      });
    }

    runCase(results, 'worker dispatch prompts only sealed parts and retains native evidence', () => {
      expect(host.runtime !== null, 'live runtime unavailable');
      const workerRoot = join(tempRoot, 'worker-bundle');
      const instructionPath = join(workerRoot, 'instructions', '01.txt');
      const attachmentPath = join(workerRoot, 'files', '001-source.txt');
      const contractPath = join(workerRoot, 'contracts', 'output.json');
      const instruction = Buffer.from('Use the attached source as data.\n', 'utf8');
      const attachment = Buffer.from('allowlisted fixture source\n', 'utf8');
      const contract = stableJsonBytes({ answer: '', flags: [] });
      mkdirSync(dirname(instructionPath), { recursive: true });
      mkdirSync(dirname(attachmentPath), { recursive: true });
      mkdirSync(dirname(contractPath), { recursive: true });
      writeFileSync(instructionPath, instruction);
      writeFileSync(attachmentPath, attachment);
      writeFileSync(contractPath, contract);
      const model = host.models.mechanical;
      const request: WorkerRequest = {
        format: LOA_WORKER_REQUEST_FORMAT,
        call_id: 'CALL-CLAUDE-HOST-FIXTURE',
        run_id: 'RUN-CLAUDE-HOST-FIXTURE',
        stage: 'S1',
        role: 'intake-clerk',
        kind: 'producer',
        core_parts: [{
          path: 'docs/architecture/prompts/workers-intake-extraction.md',
          selector: 'fixture',
          digest: sha256Digest(instruction),
          materialized_path: 'instructions/01.txt',
        }],
        blind_policy: {
          core_path: 'docs/architecture/prompts/workers-intake-extraction.md',
          selector: 'fixture',
          core_part_path: 'instructions/01.txt',
          byte_start: '0',
          byte_end: String(instruction.byteLength),
          digest: sha256Digest(instruction),
        },
        allowlist: [{
          run_path: 'corpus/sources/SRC-001/source.txt',
          attachment_path: 'files/001-source.txt',
          digest: sha256Digest(attachment),
        }],
        withheld: [],
        task_line: 'Return one fixture answer.',
        output_contract: {
          core_path: 'fixture',
          selector: 'output-contract:fixture',
          digest: sha256Digest(contract),
        },
        model_identity: model,
        bundle_digest: `sha256:${'a'.repeat(64)}`,
        isolation: {
          fresh_context: true,
          inherit_context: false,
          producer_context_id: null,
          filesystem: 'bundle-read-only',
        },
      };
      const invocation = {
        invocation_digest: `sha256:${'b'.repeat(64)}`,
        request,
        worker_bundle_root: workerRoot,
        worker_bundle_digest: request.bundle_digest,
        model_identity: model,
        producer_context_id: null,
        simulation: null,
      } as const;
      const prompt = buildClaudeCodeWorkerPrompt(invocation).toString('utf8');
      expect(
        prompt.includes('allowlisted fixture source')
          && prompt.includes('Use the attached source as data.')
          && prompt.includes('Return one fixture answer.'),
        'worker prompt omitted sealed input',
      );
      const dispatchCalls: Array<{ args: string[]; options: HostSpawnOptions }> = [];
      const dispatchSpawn = fixtureSpawn(
        claudePath,
        sandboxPath,
        dispatchCalls,
        () => ({ answer: 'fixture answer', flags: [] }),
      );
      const completed = invokeClaudeCodeWorker(
        invocation,
        host,
        dispatchSpawn,
        TEST_ENVIRONMENT,
      );
      expect(dispatchCalls.length === 1, 'worker dispatch invoked the host more than once');
      expect(
        stableJson(completed.structuredReturn)
          === stableJson({ answer: 'fixture answer', flags: [] }),
        'worker structured return changed',
      );
      expect(
        completed.receipt.context_id === SESSION_ID
          && completed.receipt.model_identity.model_id === MODEL
          && completed.evidence.event_stream_digest === sha256Digest(completed.eventStream),
        'worker dispatch evidence is incomplete',
      );
      const schema = JSON.parse(
        argValue(dispatchCalls[0].args, '--json-schema'),
      ) as Record<string, unknown>;
      expect(
        schema.type === 'object' && schema.additionalProperties === false,
        'worker did not use a closed JSON Schema',
      );
    });

    runCase(results, 'attestation rejects a mutable model alias before any probe', () => {
      const aliasCalls: Array<{ args: string[]; options: HostSpawnOptions }> = [];
      expectThrows(
        () => attestClaudeCodeHost({
          profile,
          modelId: 'opus',
          provider: 'amazon-bedrock',
          claudePath,
          sandboxPath,
          attestedAt: '2040-01-02T03:04:05.000Z',
          timeoutMs: '600000',
          maxOutputBytes: '1048576',
          maxBudgetUsd: '1.00',
          spawn: fixtureSpawn(claudePath, sandboxPath, aliasCalls),
          environment: TEST_ENVIRONMENT,
        }),
        /alias|snapshot/iu,
        'mutable model alias',
      );
      expect(aliasCalls.length === 0, 'alias rejection still made a model call');
    });
  } finally {
    rmSync(tempRoot, { recursive: true, force: true });
  }
  return {
    result: results.every((item) => item.status === 'PASS') ? 'PASS' : 'FAIL',
    cases: results,
    real_model_calls: 'none',
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  const report = runClaudeCodeHostTests();
  for (const item of report.cases) {
    process.stdout.write(
      `${item.status} ${item.name}${item.error ? `: ${item.error}` : ''}\n`,
    );
  }
  process.stdout.write(`REAL MODEL CALLS: ${report.real_model_calls}\n`);
  process.stdout.write(
    `RESULT: ${report.result} (${
      report.cases.filter((item) => item.status === 'PASS').length
    }/${report.cases.length})\n`,
  );
  process.exitCode = report.result === 'PASS' ? 0 : 1;
}
