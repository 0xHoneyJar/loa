import {
  existsSync,
  readFileSync,
  readdirSync,
} from 'node:fs';
import { join, resolve } from 'node:path';
import {
  LOA_LEDGER_RECEIPT_FORMAT,
  type Clock,
  type JsonValue,
  type LedgerReceipt,
} from './types.ts';
import {
  assertNoSymlinkComponents,
  assertPathWithin,
  assertSafeRelativePath,
  nextDecimal,
  sha256Digest,
  stableJson,
  stableJsonBytes,
  writeFileAtomic,
} from './fs.ts';
import {
  acquireDurableProcessLock,
  readRunState,
  updateRunState,
} from './run-control.ts';
import { ValidatedWorkerReturn } from './worker-return.ts';

const CANONICAL_PREFIXES = [
  'arms/',
  'clusters/',
  'ledgers/',
  'projections/',
  'synthesis/',
  'verification/',
] as const;

const CANONICAL_FILES = new Set([
  'precis.md',
  'run-log.md',
  'run-manifest.md',
]);

export type LedgerRenderer<T extends JsonValue = JsonValue> = (data: T) => string;

function defaultClock(): Clock {
  return { now: () => new Date().toISOString() };
}

function canonicalRunPath(path: string): boolean {
  return CANONICAL_FILES.has(path)
    || CANONICAL_PREFIXES.some((prefix) => path.startsWith(prefix));
}

function appendedBytes(before: Buffer, addition: string): Buffer {
  if (!addition.trim()) throw new Error('ledger append must not be empty');
  const prefix = before.byteLength === 0 || before[before.byteLength - 1] === 0x0a
    ? ''
    : '\n';
  const suffix = addition.endsWith('\n') ? '' : '\n';
  return Buffer.concat([before, Buffer.from(`${prefix}${addition}${suffix}`, 'utf8')]);
}

interface LedgerRecoveryResult {
  committed: LedgerReceipt[];
  alreadyCommitted: LedgerReceipt[];
  rolledBack: string[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

const SHA256_PATTERN = /^sha256:[0-9a-f]{64}$/u;
const LEDGER_RECEIPT_KEYS = [
  'format',
  'sequence',
  'path',
  'before_digest',
  'after_digest',
  'return_digest',
  'previous_chain_digest',
  'chain_digest',
  'writer',
  'written_at',
] as const;

function validatedLedgerReceipt(
  receiptRecord: Record<string, unknown>,
  label: string,
): LedgerReceipt {
  if (Object.keys(receiptRecord).sort().join('\0')
    !== [...LEDGER_RECEIPT_KEYS].sort().join('\0')) {
    throw new Error(`ledger receipt fields are malformed: ${label}`);
  }
  const receipt = receiptRecord as unknown as LedgerReceipt;
  if (receipt.format !== LOA_LEDGER_RECEIPT_FORMAT
    || !/^(0|[1-9][0-9]*)$/u.test(receipt.sequence)
    || receipt.writer !== 'loa-orchestrator'
    || typeof receipt.written_at !== 'string'
    || !receipt.written_at
    || [
      receipt.before_digest,
      receipt.after_digest,
      receipt.return_digest,
      receipt.previous_chain_digest,
      receipt.chain_digest,
    ].some((digest) => !SHA256_PATTERN.test(digest))) {
    throw new Error(`ledger receipt is inconsistent: ${label}`);
  }
  const { chain_digest: _chainDigest, ...base } = receipt;
  if (sha256Digest(stableJsonBytes(base)) !== receipt.chain_digest) {
    throw new Error(`ledger receipt chain digest is invalid: ${label}`);
  }
  assertSafeRelativePath(receipt.path, 'recovered canonical run path');
  if (!canonicalRunPath(receipt.path)) {
    throw new Error(`ledger receipt targets a noncanonical path: ${label}`);
  }
  return receipt;
}

function ledgerTransactionReceipt(
  value: Record<string, unknown>,
  name: string,
): LedgerReceipt {
  if (value.format !== 'aleph-loa-ledger-transaction/v1'
    || !['prepared', 'committed', 'rolled-back'].includes(String(value.status))
    || typeof value.sequence !== 'string'
    || typeof value.path !== 'string'
    || typeof value.before_digest !== 'string'
    || typeof value.after_digest !== 'string'
    || typeof value.chain_before_digest !== 'string'
    || typeof value.chain_after_digest !== 'string'
    || typeof value.prior_state_checkpoint !== 'string'
    || !isRecord(value.receipt)
    || [
      value.chain_before_digest,
      value.chain_after_digest,
      value.prior_state_checkpoint,
    ].some((digest) => !SHA256_PATTERN.test(digest))) {
    throw new Error(`ledger transaction cannot be authenticated: ${name}`);
  }
  const receipt = validatedLedgerReceipt(value.receipt, name);
  if (receipt.sequence !== value.sequence
    || receipt.path !== value.path
    || receipt.before_digest !== value.before_digest
    || receipt.after_digest !== value.after_digest) {
    throw new Error(`ledger transaction receipt is inconsistent: ${name}`);
  }
  if (name !== `TXN-ledger-${receipt.sequence}.json`) {
    throw new Error(`ledger transaction filename disagrees with its receipt: ${name}`);
  }
  return receipt;
}

function readBytesOrEmpty(path: string): Buffer {
  return existsSync(path) ? readFileSync(path) : Buffer.alloc(0);
}

function validatedLedgerChain(runDir: string): LedgerReceipt[] {
  const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
  const bytes = readBytesOrEmpty(chainPath);
  if (bytes.byteLength > 0 && bytes[bytes.byteLength - 1] !== 0x0a) {
    throw new Error('ledger chain is not newline-terminated');
  }
  const text = bytes.toString('utf8');
  const lines = text ? text.slice(0, -1).split('\n') : [];
  if (lines.some((line) => !line)) throw new Error('ledger chain contains an empty record');
  const receipts: LedgerReceipt[] = [];
  const lastByPath = new Map<string, LedgerReceipt>();
  let sequence = '0';
  let head = sha256Digest(Buffer.alloc(0));
  for (const [index, line] of lines.entries()) {
    let value: unknown;
    try {
      value = JSON.parse(line) as unknown;
    } catch {
      throw new Error(`ledger chain record ${String(index + 1)} is invalid JSON`);
    }
    if (!isRecord(value) || stableJson(value) !== line) {
      throw new Error(`ledger chain record ${String(index + 1)} is not canonical`);
    }
    const receipt = validatedLedgerReceipt(value, `chain record ${String(index + 1)}`);
    if (receipt.sequence !== nextDecimal(sequence)
      || receipt.previous_chain_digest !== head) {
      throw new Error(`ledger chain order is invalid at sequence ${receipt.sequence}`);
    }
    const priorForPath = lastByPath.get(receipt.path);
    if (priorForPath && receipt.before_digest !== priorForPath.after_digest) {
      throw new Error(`ledger target digest chain is invalid for ${receipt.path}`);
    }
    receipts.push(receipt);
    lastByPath.set(receipt.path, receipt);
    sequence = receipt.sequence;
    head = receipt.chain_digest;
  }
  const state = readRunState(runDir);
  if (state.ledger.writer_id !== 'loa-orchestrator'
    || state.ledger.sequence !== sequence
    || state.ledger.chain_head !== head) {
    throw new Error('ledger chain head or sequence disagrees with run state');
  }
  for (const receipt of lastByPath.values()) {
    const target = join(runDir, receipt.path);
    assertPathWithin(runDir, target, 'canonical ledger target');
    assertNoSymlinkComponents(runDir, target);
    if (sha256Digest(readBytesOrEmpty(target)) !== receipt.after_digest) {
      throw new Error(`canonical ledger target disagrees with chain: ${receipt.path}`);
    }
  }
  return receipts;
}

function acquireLedgerLock(
  runDir: string,
  acquiredAt: string,
  _recoverDeadOwner: boolean,
): () => void {
  return acquireDurableProcessLock(join(runDir, 'control', 'ledger-writer.lock'), {
    format: 'aleph-loa-ledger-lock/v1',
    label: 'canonical ledger writer lock',
    acquiredAt,
  });
}

function recoverPendingLedgerTransactionsUnlocked(
  runDir: string,
  recoveredAt: string,
): LedgerRecoveryResult {
  const transactionRoot = join(runDir, 'control', 'transactions');
  const result: LedgerRecoveryResult = { committed: [], alreadyCommitted: [], rolledBack: [] };
  const committedCandidates: LedgerReceipt[] = [];
  if (!existsSync(transactionRoot)) {
    validatedLedgerChain(runDir);
    return result;
  }
  for (const name of readdirSync(transactionRoot).sort()) {
    if (!/^TXN-ledger-[0-9]+\.json$/u.test(name)) continue;
    const transactionPath = join(transactionRoot, name);
    let value: unknown;
    try {
      value = JSON.parse(readFileSync(transactionPath, 'utf8')) as unknown;
    } catch {
      throw new Error(`ledger transaction journal is malformed: ${name}`);
    }
    if (!isRecord(value)) throw new Error(`ledger transaction journal is malformed: ${name}`);
    const receipt = ledgerTransactionReceipt(value, name);
    if (value.status === 'committed') {
      const finalizedAt = typeof value.committed_at === 'string'
        ? value.committed_at
        : value.recovered_at;
      if (typeof finalizedAt !== 'string' || !finalizedAt) {
        throw new Error(`committed ledger transaction has no finalization time: ${name}`);
      }
      committedCandidates.push(receipt);
      continue;
    }
    if (value.status === 'rolled-back') continue;
    const target = join(runDir, receipt.path);
    assertPathWithin(runDir, target, 'recovered canonical run path');
    assertNoSymlinkComponents(runDir, target);
    const targetDigest = sha256Digest(readBytesOrEmpty(target));
    const chainPath = join(runDir, 'control', 'ledger-chain.jsonl');
    const chainBefore = readBytesOrEmpty(chainPath);
    const chainDigest = sha256Digest(chainBefore);
    const state = readRunState(runDir);
    const stateIsBefore = state.execution.resume.checkpoint_digest === value.prior_state_checkpoint
      && state.ledger.chain_head === receipt.previous_chain_digest;
    const stateIsAfter = state.ledger.sequence === receipt.sequence
      && state.ledger.chain_head === receipt.chain_digest;

    if (targetDigest === value.before_digest) {
      if (chainDigest !== value.chain_before_digest || !stateIsBefore) {
        throw new Error(`ledger transaction has contradictory pre-write state: ${name}`);
      }
      writeFileAtomic(transactionPath, stableJson({
        ...value,
        status: 'rolled-back',
        recovered_at: recoveredAt,
      }));
      result.rolledBack.push(name);
      continue;
    }
    if (targetDigest !== value.after_digest) {
      throw new Error(`ledger transaction target is neither before nor after image: ${name}`);
    }
    if (chainDigest === value.chain_before_digest) {
      if (!stateIsBefore) {
        throw new Error(`ledger transaction state advanced before its chain: ${name}`);
      }
      const chainText = chainBefore.toString('utf8');
      const chainAfter = `${chainText}${chainText && !chainText.endsWith('\n') ? '\n' : ''}${stableJson(receipt)}\n`;
      if (sha256Digest(Buffer.from(chainAfter, 'utf8')) !== value.chain_after_digest) {
        throw new Error(`ledger transaction cannot reproduce its chain after-image: ${name}`);
      }
      writeFileAtomic(chainPath, chainAfter);
    } else if (chainDigest !== value.chain_after_digest) {
      throw new Error(`ledger transaction chain is neither before nor after image: ${name}`);
    }
    const refreshed = readRunState(runDir);
    const refreshedIsBefore = refreshed.execution.resume.checkpoint_digest
      === value.prior_state_checkpoint
      && refreshed.ledger.chain_head === receipt.previous_chain_digest;
    const refreshedIsAfter = refreshed.ledger.sequence === receipt.sequence
      && refreshed.ledger.chain_head === receipt.chain_digest;
    if (refreshedIsBefore) {
      updateRunState(runDir, recoveredAt, (draft) => {
        draft.ledger.sequence = receipt.sequence;
        draft.ledger.chain_head = receipt.chain_digest;
      });
    } else if (!refreshedIsAfter) {
      throw new Error(`ledger transaction run state is neither before nor after image: ${name}`);
    }
    writeFileAtomic(transactionPath, stableJson({
      ...value,
      status: 'committed',
      recovered_at: recoveredAt,
    }));
    result.committed.push(receipt);
  }
  const chain = validatedLedgerChain(runDir);
  for (const receipt of committedCandidates) {
    const matches = chain.filter((entry) => stableJson(entry) === stableJson(receipt));
    if (matches.length !== 1) {
      throw new Error(
        `committed ledger receipt does not occur exactly once in the validated chain: ${receipt.sequence}`,
      );
    }
    result.alreadyCommitted.push(receipt);
  }
  return result;
}

export function recoverPendingLedgerTransactions(
  runDir: string,
  clock: Clock = defaultClock(),
): LedgerRecoveryResult {
  const root = resolve(runDir);
  const recoveredAt = clock.now();
  const release = acquireLedgerLock(root, recoveredAt, true);
  try {
    return recoverPendingLedgerTransactionsUnlocked(root, recoveredAt);
  } finally {
    release();
  }
}

export class LedgerWriter {
  readonly runDir: string;
  readonly clock: Clock;

  constructor(runDir: string, clock: Clock = defaultClock()) {
    this.runDir = resolve(runDir);
    this.clock = clock;
  }

  append<T extends JsonValue>(
    relativePath: string,
    validated: ValidatedWorkerReturn<T>,
    render: LedgerRenderer<T>,
  ): LedgerReceipt {
    if (!(validated instanceof ValidatedWorkerReturn)) {
      throw new Error('canonical writes require a validated worker return');
    }
    validated.assertAuthenticAndIntact();
    assertSafeRelativePath(relativePath, 'canonical run path');
    if (!canonicalRunPath(relativePath)) {
      throw new Error(`path is outside the canonical writer surface: ${relativePath}`);
    }
    const target = join(this.runDir, relativePath);
    assertPathWithin(this.runDir, target, 'canonical run path');
    assertNoSymlinkComponents(this.runDir, target);
    const release = acquireLedgerLock(this.runDir, this.clock.now(), false);
    try {
      const recovery = recoverPendingLedgerTransactionsUnlocked(this.runDir, this.clock.now());
      const matches = [
        ...recovery.alreadyCommitted,
        ...recovery.committed,
      ].filter((receipt) => (
        receipt.path === relativePath
        && receipt.return_digest === validated.rawDigest
      ));
      if (matches.length > 1) {
        throw new Error('multiple committed ledger receipts claim the same worker return');
      }
      if (matches[0]) return matches[0];
      const state = readRunState(this.runDir);
      if (state.ledger.writer_id !== 'loa-orchestrator') {
        throw new Error('run does not designate the Loa orchestrator as ledger writer');
      }
      if (validated.simulation !== null && state.full_mode !== 'fixture-simulated') {
        throw new Error('fixture-simulated worker return cannot enter a full Aleph run ledger');
      }
      const before = existsSync(target) ? readFileSync(target) : Buffer.alloc(0);
      const beforeDigest = sha256Digest(before);
      const verifiedData = validated.assertAuthenticAndIntact();
      const rendered = render(verifiedData);
      validated.assertAuthenticAndIntact();
      const next = appendedBytes(before, rendered);
      const afterDigest = sha256Digest(next);
      const sequence = nextDecimal(state.ledger.sequence);
      const writtenAt = this.clock.now();
      const base: Omit<LedgerReceipt, 'chain_digest'> = {
        format: LOA_LEDGER_RECEIPT_FORMAT,
        sequence,
        path: relativePath,
        before_digest: beforeDigest,
        after_digest: afterDigest,
        return_digest: validated.rawDigest,
        previous_chain_digest: state.ledger.chain_head,
        writer: 'loa-orchestrator',
        written_at: writtenAt,
      };
      const receipt: LedgerReceipt = {
        ...base,
        chain_digest: sha256Digest(stableJsonBytes(base)),
      };
      const chainPath = join(this.runDir, 'control', 'ledger-chain.jsonl');
      const chainBefore = existsSync(chainPath) ? readFileSync(chainPath, 'utf8') : '';
      const chainAfter = `${chainBefore}${chainBefore && !chainBefore.endsWith('\n') ? '\n' : ''}${stableJson(receipt)}\n`;
      const transactionPath = join(
        this.runDir,
        'control',
        'transactions',
        `TXN-ledger-${sequence}.json`,
      );
      const transaction = {
        format: 'aleph-loa-ledger-transaction/v1',
        status: 'prepared',
        sequence,
        path: relativePath,
        before_digest: beforeDigest,
        after_digest: afterDigest,
        chain_before_digest: sha256Digest(Buffer.from(chainBefore, 'utf8')),
        chain_after_digest: sha256Digest(Buffer.from(chainAfter, 'utf8')),
        prior_state_checkpoint: state.execution.resume.checkpoint_digest,
        receipt,
        prepared_at: writtenAt,
      };
      writeFileAtomic(transactionPath, stableJson(transaction));
      writeFileAtomic(target, next);
      writeFileAtomic(chainPath, chainAfter);
      updateRunState(this.runDir, writtenAt, (draft) => {
        draft.ledger.sequence = sequence;
        draft.ledger.chain_head = receipt.chain_digest;
      });
      writeFileAtomic(transactionPath, stableJson({
        ...transaction,
        status: 'committed',
        committed_at: this.clock.now(),
      }));
      return receipt;
    } finally {
      release();
    }
  }
}
