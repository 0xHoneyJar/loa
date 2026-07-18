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
];
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
];
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
];
export const LOA_MODEL_SLOTS = [
    'orchestration',
    'mechanical',
    'recall-critical',
    'judgment',
    'adversarial',
    'assembly',
];
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
];
