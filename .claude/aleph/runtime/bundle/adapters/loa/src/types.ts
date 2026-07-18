import type { BundleLock } from '../../../scripts/lib/bundle-format.ts';

export const LOA_ADAPTER_ID = 'loa';
export const LOA_BUNDLE_ID = 'aleph-for-loa';
export const LOA_PROFILE_FORMAT = 'aleph-loa-profile/v1';
export const LOA_HOST_FORMAT = 'aleph-loa-host-capabilities/v1';
export const LOA_RUN_STATE_FORMAT = 'aleph-loa-run-state/v1';
export const LOA_CORPUS_SNAPSHOT_FORMAT = 'aleph-loa-corpus-snapshot/v1';
export const LOA_RUNTIME_SNAPSHOT_FORMAT = 'aleph-loa-runtime-snapshot/v1';
export const LOA_WORKER_REQUEST_FORMAT = 'aleph-loa-worker-request/v1';
export const LOA_WORKER_VALIDATION_FORMAT = 'aleph-loa-worker-validation/v1';
export const LOA_LEDGER_RECEIPT_FORMAT = 'aleph-loa-ledger-receipt/v1';
export const LOA_CHECK_RECORD_FORMAT = 'aleph-loa-check-record/v1';
export const LOA_COMMAND_RESULT_FORMAT = 'aleph-loa-command-result/v1';
export const LOA_CLAUDE_CODE_RUNTIME_FORMAT = 'aleph-loa-claude-code-runtime/v1';
export const LOA_CLAUDE_CODE_PROBE_FORMAT = 'aleph-loa-claude-code-probe/v1';
export const LOA_CLAUDE_CODE_DISPATCH_FORMAT = 'aleph-loa-claude-code-dispatch/v1';

export const LOA_RUN_ROOT = 'grimoires/loa/aleph/runs';
export const LOA_INSTALLED_BUNDLE_ROOT = '.claude/aleph/runtime/bundle';
export const LOA_INSTALL_LOCK_PATH = '.claude/aleph/install.lock.json';

export const CORE_STAGES = [
  'S0',
  'S1',
  'S2',
  'S3',
  'S4',
  'S5',
  'S6',
  'S7',
  'S8',
  'S9a',
  'S9b',
  'S10',
  'S11',
  'S12',
  'S13',
  'P1',
  'P2',
  'P3',
] as const;

export const CORE_RUN_STATES = [
  'DRAFT',
  'CORPUS-FROZEN',
  'DISTILLING',
  'ASSEMBLED',
  'VERIFIED',
  'ACCEPTED',
  'PROJECTING',
  'PROJECTION-ACCEPTED',
  'BLOCKED',
] as const;

export const LOA_ROLE_IDS = [
  'orchestrator',
  'intake-clerk',
  'extractor',
  'normalizer',
  'merge-judge',
  'disposition-judge',
  'evidence-role-judge',
  'cluster-cartographer',
  'router',
  'adversarial-panel',
  'convergent-reconciler',
  'synthesist',
  'assembler',
  'conformance-runner',
  'scribe',
  'verifier-l1',
  'verifier-l2',
  'verifier-l3',
  'verifier-l4',
  'verifier-l5',
  'verifier-l6',
  'verifier-l7',
  'verifier-l8',
  'verifier-l9',
  'verifier-l10',
] as const;

export const LOA_MODEL_SLOTS = [
  'orchestration',
  'mechanical',
  'recall-critical',
  'judgment',
  'adversarial',
  'assembly',
] as const;

export const LOA_REQUIRED_HOST_CAPABILITIES = [
  'native_slash_commands',
  'native_skills',
  'durable_file_io',
  'fresh_context_workers',
  'context_inheritance_control',
  'read_only_worker_bundles',
  'structured_worker_returns',
  'exact_model_resolution',
  'effort_controls',
  'local_process_execution',
  'human_authority_interaction',
] as const;

export type CoreStage = typeof CORE_STAGES[number];
export type CoreRunState = typeof CORE_RUN_STATES[number];
export type LoaRoleId = typeof LOA_ROLE_IDS[number];
export type LoaModelSlot = typeof LOA_MODEL_SLOTS[number];
export type LoaRequiredHostCapability = typeof LOA_REQUIRED_HOST_CAPABILITIES[number];
export type JsonPrimitive = null | boolean | number | string;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

export interface LoaRoleMapping {
  model_slot: LoaModelSlot;
  effort: string;
  context_policy: string;
  budget_policy: string;
  cache_policy: string;
  batch_policy: string;
}

export interface LoaModelSlotPolicy {
  capability_class: string;
  exact_identity_required: true;
  fallback_allowed: false;
}

export interface LoaProfile {
  profile_format: typeof LOA_PROFILE_FORMAT;
  id: string;
  host: typeof LOA_ADAPTER_ID;
  runtime_requirements: {
    node_min_version: string;
    required_capabilities: LoaRequiredHostCapability[];
  };
  paths: {
    run_root: string;
    installed_bundle_root: string;
    install_lock: string;
  };
  role_mappings: Record<LoaRoleId, LoaRoleMapping>;
  model_slots: Record<LoaModelSlot, LoaModelSlotPolicy>;
}

export interface ExactModelIdentity {
  provider: string;
  model_id: string;
  resolved_version: string;
  identity_kind: 'provider-pinned-snapshot' | 'fixture-simulated';
  immutable: true;
  context: string;
  effort: string;
  budget: string;
  cache: string;
  batch: string;
  fallback: false;
}

export interface HostExecutableIdentity {
  path: string;
  version: string;
  digest: string;
}

export interface ClaudeCodeUsageEvidence {
  input_tokens: string;
  output_tokens: string;
  cache_read_input_tokens: string;
  cache_creation_input_tokens: string;
}

export interface ClaudeCodeModelUsageEvidence extends ClaudeCodeUsageEvidence {
  cost_usd: number;
  context_window: string;
  max_output_tokens: string;
}

export interface ClaudeCodeProbeEvidence {
  format: typeof LOA_CLAUDE_CODE_PROBE_FORMAT;
  slots: LoaModelSlot[];
  requested_model: string;
  observed_model: string;
  effort: string;
  session_id: string;
  claude_code_version: string;
  event_stream: string;
  event_stream_digest: string;
  event_count: string;
  structured_output_digest: string;
  total_cost_usd: number;
  usage: ClaudeCodeUsageEvidence;
  model_usage: ClaudeCodeModelUsageEvidence;
  stop_reason: 'tool_use';
  terminal_reason: 'completed';
}

export interface ClaudeCodeRuntimeAttestation {
  format: typeof LOA_CLAUDE_CODE_RUNTIME_FORMAT;
  provider: 'amazon-bedrock';
  attested_at: string;
  claude: HostExecutableIdentity;
  sandbox: HostExecutableIdentity & {
    kind: 'bubblewrap';
    policy_digest: string;
    read_only_mounts: Array<{
      source: string;
      destination: string;
    }>;
  };
  fallback_policy: {
    allowed: false;
    controls: {
      CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK: '1';
      CLAUDE_CODE_NO_MODEL_FALLBACK: '1';
      CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK: '1';
    };
  };
  credential_environment: [
    'AWS_BEARER_TOKEN_BEDROCK',
    'AWS_REGION',
    'CLAUDE_CODE_USE_BEDROCK',
  ];
  dispatch: {
    timeout_ms: string;
    max_output_bytes: string;
    max_budget_usd: string;
  };
  probes: ClaudeCodeProbeEvidence[];
}

export interface LoaHostCapabilities {
  host_format: typeof LOA_HOST_FORMAT;
  host: {
    id: typeof LOA_ADAPTER_ID;
    version: string;
    build_id: string;
  };
  capabilities: Record<LoaRequiredHostCapability, true>;
  models: Record<LoaModelSlot, ExactModelIdentity>;
  runtime: ClaudeCodeRuntimeAttestation | null;
  simulation: null | {
    kind: 'fixture-simulated';
  };
}

export interface LockedExecutionIdentity {
  core: BundleLock['core'];
  adapter: BundleLock['adapter'];
  bundle: BundleLock['bundle'] & {
    lock_digest: string;
    lock_ref: string;
    installation_ref: string;
  };
  checker_digest: string;
  adapter_protocol_version: string;
  run_format_version: string;
  host: LoaHostCapabilities['host'];
  profile: {
    id: string;
    digest: string;
  };
  models: Record<LoaRoleId, ExactModelIdentity>;
  runtime: {
    snapshot_ref: string;
    digest: string;
  };
}

export interface AuthorityGateState {
  id: string;
  type: string;
  status: 'awaiting-authority' | 'approved' | 'declined';
  request_ref: string;
  response_ref: string | null;
}

export interface HaltState {
  code: string;
  reason: string;
  at: string;
  blocking: true;
}

export interface LoaRunState {
  format: typeof LOA_RUN_STATE_FORMAT;
  run_id: string;
  mode: 'agent';
  full_mode: 'full-aleph' | 'fixture-simulated';
  identity: LockedExecutionIdentity;
  corpus: {
    state: 'staged' | 'frozen';
    inventory_ref: string;
    tree_digest: string;
  };
  execution: {
    core_state: CoreRunState;
    stage: CoreStage;
    stage_status: 'entered' | 'running' | 'awaiting-authority' | 'closed';
    gate: AuthorityGateState | null;
    halt: HaltState | null;
    resume: {
      sequence: string;
      checkpoint_digest: string;
      last_verified_at: string;
    };
  };
  ledger: {
    writer_id: 'loa-orchestrator';
    sequence: string;
    chain_head: string;
  };
}

export interface InputRootRecord {
  argument_index: string;
  argument: string;
  resolved_path: string;
  kind: 'file' | 'directory';
}

export interface FrozenSourceRecord {
  source_id: string;
  input_root_index: string;
  original_path: string;
  relative_path: string;
  frozen_path: string;
  byte_length: string;
  digest: string;
  mode: string;
  scheme: 'md-lines' | 'text-lines';
}

export interface CorpusSnapshot {
  format: typeof LOA_CORPUS_SNAPSHOT_FORMAT;
  run_id: string;
  status: 'staged' | 'frozen';
  captured_at: string;
  frozen_at: string | null;
  roots: InputRootRecord[];
  files: FrozenSourceRecord[];
  tree_digest: string;
}

export interface S0AuthorityResponse {
  format: 'aleph-loa-authority-response/v1';
  gate_id: 'S0';
  run_id: string;
  authority: {
    kind: 'human';
    identity: string;
  };
  decision: 'approve-freeze' | 'reject';
  declared_scope: string;
  exclusions: string[];
  sensitivity_rulings: Array<{
    source_id: string;
    labels: string[];
    decision: 'admit-exact-bytes' | 'exclude';
  }>;
  freeze: boolean;
  recorded_at: string;
  simulation: null | {
    kind: 'fixture-simulated';
  };
}

export interface RuntimeFileRecord {
  path: string;
  digest: string;
  byte_length: string;
}

export interface RuntimeSnapshot {
  format: typeof LOA_RUNTIME_SNAPSHOT_FORMAT;
  run_id: string;
  captured_at: string;
  bundle: {
    id: string;
    digest: string;
    lock_digest: string;
    root: string;
  };
  profile: {
    id: string;
    path: string;
    digest: string;
  };
  host: LoaHostCapabilities;
  host_receipt: RuntimeFileRecord;
  node: {
    version: string;
    executable: string;
    executable_digest: string;
    platform: string;
    arch: string;
  };
  files: RuntimeFileRecord[];
  tree_digest: string;
}

export interface CoreBytePart {
  path: string;
  selector: string;
  digest: string;
  materialized_path: string;
}

export interface WorkerAttachment {
  run_path: string;
  attachment_path: string;
  digest: string;
}

export interface WithheldSelector {
  selector: string;
  core_ref: string;
}

export interface CoreBlindPolicy {
  core_path: string;
  selector: string;
  core_part_path: string;
  byte_start: string;
  byte_end: string;
  digest: string;
}

export interface WorkerRequest {
  format: typeof LOA_WORKER_REQUEST_FORMAT;
  call_id: string;
  run_id: string;
  stage: CoreStage;
  role: LoaRoleId;
  kind: 'producer' | 'refuter';
  core_parts: CoreBytePart[];
  blind_policy: CoreBlindPolicy;
  allowlist: WorkerAttachment[];
  withheld: WithheldSelector[];
  task_line: string;
  output_contract: {
    core_path: string;
    selector: string;
    digest: string;
  };
  model_identity: ExactModelIdentity;
  bundle_digest: string;
  isolation: {
    fresh_context: true;
    inherit_context: false;
    producer_context_id: string | null;
    filesystem: 'bundle-read-only';
  };
}

export interface WorkerDispatchReceipt {
  format: 'aleph-loa-worker-dispatch/v1';
  call_id: string;
  context_id: string;
  producer_context_id: string | null;
  fresh_context: true;
  inherited_context: false;
  filesystem: 'bundle-read-only';
  model_identity: ExactModelIdentity;
  simulation: null | {
    kind: 'fixture-simulated';
  };
}

export interface ClaudeCodeDispatchEvidence {
  format: typeof LOA_CLAUDE_CODE_DISPATCH_FORMAT;
  session_id: string;
  requested_model: string;
  observed_model: string;
  effort: string;
  claude_code_version: string;
  host_build_id: string;
  claude_executable_digest: string;
  sandbox_executable_digest: string;
  sandbox_policy_digest: string;
  prompt_digest: string;
  output_schema_digest: string;
  event_stream_digest: string;
  event_stream_byte_length: string;
  event_count: string;
  structured_output_digest: string;
  total_cost_usd: number;
  usage: ClaudeCodeUsageEvidence;
  model_usage: ClaudeCodeModelUsageEvidence;
  stop_reason: 'tool_use';
  terminal_reason: 'completed';
}

export interface WorkerValidationReport {
  format: typeof LOA_WORKER_VALIDATION_FORMAT;
  call_id: string;
  contract_digest: string;
  raw_digest: string;
  simulation: WorkerDispatchReceipt['simulation'];
  result: 'PASS' | 'FAIL';
  errors: string[];
}

export interface LedgerReceipt {
  format: typeof LOA_LEDGER_RECEIPT_FORMAT;
  sequence: string;
  path: string;
  before_digest: string;
  after_digest: string;
  return_digest: string;
  previous_chain_digest: string;
  chain_digest: string;
  writer: 'loa-orchestrator';
  written_at: string;
}

export interface CheckerRecord {
  format: typeof LOA_CHECK_RECORD_FORMAT;
  run_id: string;
  checker_digest: string;
  bundle_digest: string;
  command: string[];
  invoked_at: string;
  exit_status: string;
  signal: string | null;
  stdout: string;
  stderr: string;
  result: 'PASS' | 'FAIL';
}

export type LoaCommandName = 'start' | 'status' | 'resume' | 'validate';

export interface LoaCommandResult {
  format: typeof LOA_COMMAND_RESULT_FORMAT;
  command: LoaCommandName;
  result: 'PASS' | 'FAIL' | 'BLOCKED';
  run_id: string | null;
  full_mode: 'full-aleph' | 'fixture-simulated' | 'not-started';
  state: CoreRunState | null;
  stage: CoreStage | null;
  gate: AuthorityGateState | null;
  errors: string[];
  details: JsonValue;
}

export interface Clock {
  now(): string;
}

export interface IdSource {
  nextRunId(corpusHint: string): string;
  nextCallId(runId: string): string;
}
