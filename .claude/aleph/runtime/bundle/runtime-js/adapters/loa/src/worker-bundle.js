import { existsSync, lstatSync, mkdirSync, readFileSync, rmSync, } from 'node:fs';
import { join, resolve } from 'node:path';
import { CORE_STAGES, LOA_WORKER_REQUEST_FORMAT, } from './types.js';
import { assertNoSymlinkComponents, assertPathWithin, assertSafeRelativePath, digestTreeRecords, inventoryTree, makeTreeReadOnly, readJsonFile, readStableRegularFile, sha256Digest, stableJsonBytes, utf8Compare, walkRegularFiles, writeFileAtomic, writeJsonAtomic, } from './fs.js';
import { readRunState } from './run-control.js';
import { loadCorePart, loadOutputContract, } from './core-loader.js';
import { assertDownstreamOperationsAllowed, retainedRestrictionOverlays, } from '../../../scripts/lib/internal-ambiguity.js';
import { loadRun, usesFormalLayoutBindings } from '../../../scripts/lib/run-model.js';
import { materialHash, REPRESENTATION_PATH, validateRepresentationRun } from '../../../scripts/lib/source-representation.js';
import { hasRunCapability } from '../../../scripts/lib/run-model.js';
import { SEMANTIC_LENS, semanticPromptRequirements, validateSemanticAttachmentDelivery, parseSemanticJson, validateSemanticSubject, parseSemanticLedger, SEMANTIC_PATH, validateSemanticProducerDelivery, } from '../../../scripts/lib/semantic-review.js';
const ROLE_SPECS = {
    'intake-clerk': {
        path: 'docs/architecture/prompts/workers-intake-extraction.md',
        heading: 'Role: Intake Clerk (S0–S1)',
        stages: ['S0', 'S1'],
    },
    extractor: {
        path: 'docs/architecture/prompts/workers-intake-extraction.md',
        heading: 'Role: Extractor (S2)',
        stages: ['S2'],
    },
    normalizer: {
        path: 'docs/architecture/prompts/workers-intake-extraction.md',
        heading: 'Role: Normalizer (S3)',
        stages: ['S3'],
    },
    'merge-judge': {
        path: 'docs/architecture/prompts/workers-intake-extraction.md',
        heading: 'Role: Merge Judge (S4, global barrier)',
        stages: ['S4'],
    },
    'ambiguity-producer': {
        path: 'docs/architecture/prompts/workers-internal-ambiguity.md',
        heading: 'Role: Internal Ambiguity Producer (S4-C2)',
        stages: ['S4'],
    },
    'ambiguity-reviewer': {
        path: 'docs/architecture/prompts/workers-internal-ambiguity.md',
        heading: 'Role: Fresh Internal Ambiguity Reviewer (S4-C2)',
        stages: ['S4'],
    },
    'material-impact-producer': {
        path: 'docs/architecture/prompts/workers-internal-ambiguity.md',
        heading: 'Role: Material-Impact Producer (S4-C2)',
        stages: ['S4'],
    },
    'material-impact-reviewer': {
        path: 'docs/architecture/prompts/workers-internal-ambiguity.md',
        heading: 'Role: Fresh Material-Impact Reviewer (S4-C2)',
        stages: ['S4'],
    },
    'disposition-judge': {
        path: 'docs/architecture/prompts/workers-judgment.md',
        heading: 'Role: Disposition Judge (S5)',
        stages: ['S5'],
    },
    'evidence-role-judge': {
        path: 'docs/architecture/prompts/workers-judgment.md',
        heading: 'Role: Evidence-Role Judge (S6)',
        stages: ['S6'],
    },
    'cluster-cartographer': {
        path: 'docs/architecture/prompts/workers-judgment.md',
        heading: 'Role: Cluster Cartographer (S7)',
        stages: ['S7'],
    },
    router: {
        path: 'docs/architecture/prompts/workers-judgment.md',
        heading: 'Role: Router (S8)',
        stages: ['S8'],
    },
    'adversarial-panel': {
        path: 'docs/architecture/prompts/workers-arms-synthesis.md',
        heading: 'Role: Adversarial Panel operation (S9a)',
        stages: ['S9a'],
    },
    'convergent-reconciler': {
        path: 'docs/architecture/prompts/workers-arms-synthesis.md',
        heading: 'Role: Convergent Reconciler (S9b — UNVALIDATED SHAPE)',
        stages: ['S9b'],
    },
    synthesist: {
        path: 'docs/architecture/prompts/workers-arms-synthesis.md',
        heading: 'Role: Synthesist (S10)',
        stages: ['S10'],
    },
    assembler: {
        path: 'docs/architecture/prompts/workers-arms-synthesis.md',
        heading: 'Role: Assembler (S11)',
        stages: ['S11'],
    },
};
const STAGE_HEADINGS = {
    S0: 'S0 — Intake and corpus freeze',
    S1: 'S1 — Source inventory and extraction criteria',
    S2: 'S2 — Extraction pass (packetization)',
    S3: 'S3 — Candidate-claim normalization',
    S4: 'S4 — Duplicate/merge mapping',
    S5: 'S5 — Disposition pass',
    S6: 'S6 — Evidence-role pass',
    S7: 'S7 — Structural pre-clustering',
    S8: 'S8 — Route-cluster formation and routing',
    S9a: 'S9a — Adversarial arm (stress-testing)',
    S9b: 'S9b — Convergent arm (referent reconciliation) — UNVALIDATED',
    S10: 'S10 — Cluster synthesis and unresolved queue',
    S11: 'S11 — Précis assembly',
    S12: 'S12 — Verification gate',
    S13: 'S13 — Acceptance checkpoint',
    P1: 'P1 — Tier-1 projections',
    P2: 'P2 — Tier-2 terminal renderings',
    P3: 'P3 — Projection acceptance',
};
// These headings and stage sets are the exact lens charters in the canonical
// verifier-lenses document. Keep the mapping explicit so a lens cannot be
// silently paired with an unrelated stage contract.
const VERIFIER_SPECS = {
    'verifier-l1': { heading: 'L1 — coverage (S2 DoD)', stages: ['S2'] },
    'verifier-l2': { heading: 'L2 — entailment (S3 DoD)', stages: ['S3'] },
    'verifier-l2f': { heading: 'L2F — formal/table/layout use challenge (S3/S4)', stages: ['S3', 'S4'] },
    'verifier-l2s': { heading: SEMANTIC_LENS, stages: ['S2', 'S3', 'S4'] },
    'verifier-l3': { heading: 'L3 — merge-refuter (S4 DoD)', stages: ['S4'] },
    'verifier-l4': { heading: 'L4 — disposition-refuter (S5 DoD)', stages: ['S5'] },
    'verifier-l5': { heading: 'L5 — contradiction-sweep (S4/S5)', stages: ['S4', 'S5'] },
    'verifier-l6': { heading: 'L6 — evidence-role-refuter (S6/S9a)', stages: ['S6', 'S9a'] },
    'verifier-l7': { heading: 'L7 — posture-refuter (S8 DoD)', stages: ['S8'] },
    'verifier-l8': { heading: 'L8 — reconciliation-refuter (S9b)', stages: ['S9b'] },
    'verifier-l9': { heading: 'L9 — synthesis-faithfulness (S10 DoD)', stages: ['S10'] },
    'verifier-l10': {
        heading: 'L10 — projection-trace (P-stages, alongside K6)',
        stages: ['P1', 'P2', 'P3'],
    },
};
function workerBundleDigest(root, request) {
    const contentRecords = inventoryTree(root).filter((file) => file.path !== 'request.json');
    const requestProjection = {
        ...request,
        bundle_digest: '',
    };
    return digestTreeRecords([
        ...contentRecords,
        {
            path: 'request.json',
            digest: sha256Digest(stableJsonBytes(requestProjection)),
        },
    ]);
}
function validateTaskLine(value) {
    const line = value.trim();
    if (!line || /[\r\n]/u.test(line) || !/[.!?]$/u.test(line)) {
        throw new Error('worker task line must be one nonempty sentence');
    }
    return line;
}
function exactNonemptyContextId(value) {
    return typeof value === 'string'
        && value === value.trim()
        && value.length > 0
        && !/[\u0000-\u001f\u007f]/u.test(value);
}
const FRESH_REVIEWER_ROLES = new Set([
    'ambiguity-reviewer',
    'material-impact-reviewer',
]);
export function assertWorkerRoleIsolation(role, kind, producerContextId) {
    const verifier = role.startsWith('verifier-l');
    const reviewer = FRESH_REVIEWER_ROLES.has(role);
    if (kind !== 'producer' && kind !== 'refuter') {
        throw new Error(`worker kind is invalid for role ${role}`);
    }
    if ((verifier || reviewer) && kind !== 'refuter') {
        throw new Error(`reviewer role cannot be dispatched as a producer: ${role}`);
    }
    if (kind === 'refuter'
        && !verifier
        && role !== 'adversarial-panel'
        && !reviewer) {
        throw new Error(`refuter dispatch requires a verifier or adversarial role: ${role}`);
    }
    if (kind === 'refuter' && !exactNonemptyContextId(producerContextId)) {
        throw new Error('refuter dispatch requires a nonempty producer context ID');
    }
}
function assertDispatchableRoleStage(role, stage) {
    const verifier = VERIFIER_SPECS[role];
    if (verifier) {
        if (!verifier.stages.includes(stage)) {
            throw new Error(`verifier role ${role} cannot run at ${stage}; canonical stages are ${verifier.stages.join(', ')}`);
        }
        return;
    }
    const roleSpec = ROLE_SPECS[role];
    if (!roleSpec)
        throw new Error(`role ${role} is not a dispatchable worker role`);
    if (!roleSpec.stages.includes(stage))
        throw new Error(`role ${role} cannot run at ${stage}`);
}
function runBundleIdentity(state) {
    return {
        bundle: {
            id: state.identity.bundle.id,
            version: state.identity.bundle.version,
            payload_digest: state.identity.bundle.payload_digest,
            digest: state.identity.bundle.digest,
        },
        core: state.identity.core,
        adapter: state.identity.adapter,
        lock_digest: state.identity.bundle.lock_digest,
        checker_digest: state.identity.checker_digest,
        adapter_protocol_version: state.identity.adapter_protocol_version,
        run_format_version: state.identity.run_format_version,
    };
}
function selectedBundleIdentity(bundle) {
    return {
        bundle: bundle.lock.bundle,
        core: bundle.lock.core,
        adapter: bundle.lock.adapter,
        lock_digest: bundle.lock.lock_digest,
        checker_digest: bundle.lock.checker_digest,
        adapter_protocol_version: bundle.lock.adapter_protocol_version,
        run_format_version: bundle.lock.run_format_version,
    };
}
function assertPinnedRunAndModel(runDir, runId, role, modelIdentity, bundle) {
    const state = readRunState(runDir);
    if (state.run_id !== runId) {
        throw new Error(`worker run ID ${runId} does not match pinned run ${state.run_id}`);
    }
    if (!stableJsonBytes(selectedBundleIdentity(bundle)).equals(stableJsonBytes(runBundleIdentity(state)))) {
        throw new Error('worker Core bundle does not match the run-pinned bundle identity');
    }
    const pinnedModel = state.identity.models[role];
    if (!pinnedModel
        || !stableJsonBytes(modelIdentity).equals(stableJsonBytes(pinnedModel))) {
        throw new Error(`worker model identity does not match the run-pinned mapping for role ${role}`);
    }
}
function assertWorkerAttachmentPath(path) {
    assertSafeRelativePath(path, 'worker allowlist path');
    if (path === 'control' || path.startsWith('control/')) {
        throw new Error(`worker allowlist may not expose adapter control state: ${path}`);
    }
}
function roleParts(bundle, role, stage) {
    const semantic = hasRunCapability(bundle.lock.run_format_version, 'semantic-unit-review');
    if (!(semantic && role === 'normalizer' && stage === 'S4'))
        assertDispatchableRoleStage(role, stage);
    if (role === 'verifier-l2s') {
        if (!semantic || !['S2', 'S3', 'S4'].includes(stage))
            throw new Error('L2S requires the pinned semantic capability and stage');
        return {
            parts: semanticPromptRequirements(stage).map((part) => loadCorePart(bundle, part.path, part.selector)),
            policyPartIndex: 2,
            contract: loadOutputContract(bundle, 'docs/architecture/prompts/verifier-lenses.md', SEMANTIC_LENS),
        };
    }
    const common = loadCorePart(bundle, 'docs/architecture/prompts/README.md', 'fence:Common preamble (include verbatim in every call)');
    const material = usesFormalLayoutBindings(bundle.lock.run_format_version) ? [loadCorePart(bundle, 'docs/architecture/prompts/README.md', 'fence:Material constraints (run format 1.6)')] : [];
    const stagePart = loadCorePart(bundle, 'docs/architecture/04-pipeline-stages-and-dod.md', `heading:${semantic && role === 'normalizer' && stage === 'S4' ? 'S4 successor semantic preservation (1.7)' : STAGE_HEADINGS[stage]}`);
    const verifierSpec = VERIFIER_SPECS[role];
    if (verifierSpec) {
        const frame = loadCorePart(bundle, 'docs/architecture/prompts/verifier-lenses.md', 'fence:Common verifier frame (verbatim, after the common preamble)');
        const lens = loadCorePart(bundle, 'docs/architecture/prompts/verifier-lenses.md', `heading:${verifierSpec.heading}`);
        return {
            parts: [common, frame, lens, stagePart, ...material],
            policyPartIndex: 2,
            contract: loadOutputContract(bundle, 'docs/architecture/prompts/verifier-lenses.md', 'file'),
        };
    }
    const spec = semantic && role === 'normalizer' && stage === 'S4'
        ? { path: 'docs/architecture/prompts/workers-intake-extraction.md', heading: 'Role: Successor Semantic Normalizer (S4 pre-C1)', stages: ['S4'] }
        : ROLE_SPECS[role];
    const rolePart = loadCorePart(bundle, spec.path, `heading:${spec.heading}`);
    const semanticParts = semantic && (role === 'extractor' || role === 'normalizer') ? [loadCorePart(bundle, 'docs/architecture/templates/03-extraction-claims.md', 'heading:T3.7 Semantic review (1.7)')] : [];
    return {
        parts: [common, rolePart, stagePart, ...semanticParts, ...material],
        policyPartIndex: 1,
        contract: loadOutputContract(bundle, spec.path, spec.heading),
    };
}
function blindPolicySlice(part) {
    const bundleMarker = Buffer.from('**Bundle:**', 'utf8');
    const shownMarker = Buffer.from('**Shown:**', 'utf8');
    const withholdMarker = Buffer.from('**Withhold:**', 'utf8');
    const withheldMarker = Buffer.from('**Withheld:**', 'utf8');
    const outputMarker = Buffer.from('**Output contract', 'utf8');
    const bundleStart = part.bytes.indexOf(bundleMarker);
    const shownStart = part.bytes.indexOf(shownMarker);
    const start = bundleStart >= 0 ? bundleStart : shownStart;
    if (start < 0)
        throw new Error(`Core role ${part.path} ${part.selector} omits Bundle/Shown`);
    const withholdStart = part.bytes.indexOf(bundleStart >= 0 ? withholdMarker : withheldMarker, start);
    if (withholdStart < 0) {
        throw new Error(`Core role ${part.path} ${part.selector} omits Withhold/Withheld`);
    }
    const outputStart = part.bytes.indexOf(outputMarker, withholdStart);
    const end = outputStart >= 0 ? outputStart : part.bytes.length;
    const bytes = part.bytes.subarray(start, end);
    if (bytes.byteLength === 0)
        throw new Error('Core blind-context directive is empty');
    return { start, end, bytes };
}
function blindPolicyFor(part, materializedPath) {
    const slice = blindPolicySlice(part);
    return {
        core_path: part.path,
        selector: part.selector,
        core_part_path: materializedPath,
        byte_start: String(slice.start),
        byte_end: String(slice.end),
        digest: sha256Digest(slice.bytes),
    };
}
export function coreBlindPolicyReference(bundle, role, stage) {
    const loaded = roleParts(bundle, role, stage);
    const part = loaded.parts[loaded.policyPartIndex];
    const slice = blindPolicySlice(part);
    return `${part.path}#${part.selector}@${sha256Digest(slice.bytes)}`;
}
function canonicalRunFiles(runDir) {
    return walkRegularFiles(runDir)
        .map((path) => path.slice(runDir.length + 1).replaceAll('\\', '/'))
        .filter((path) => path !== 'control' && !path.startsWith('control/'))
        .sort(utf8Compare);
}
export function assembleWorkerBundle(options) {
    if (!CORE_STAGES.includes(options.stage)) {
        throw new Error(`unknown Core stage: ${options.stage}`);
    }
    if (!/^CALL-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(options.callId)) {
        throw new Error(`invalid worker call ID: ${options.callId}`);
    }
    assertWorkerRoleIsolation(options.role, options.kind, options.producerContextId);
    const runDir = resolve(options.runDir);
    const stageIndex = CORE_STAGES.indexOf(options.stage);
    const downstream = stageIndex >= CORE_STAGES.indexOf('S5');
    const restrictions = downstream ? retainedRestrictionOverlays(loadRun(runDir)) : [];
    const downstreamOperations = options.downstreamOperations || [];
    if (!downstream && downstreamOperations.length > 0) {
        throw new Error('typed downstream operations are legal only at S5 or later');
    }
    if (downstream && restrictions.length > 0 && options.downstreamOperations === undefined) {
        throw new Error('retained procedural restrictions require typed downstream operation tuples');
    }
    assertDownstreamOperationsAllowed(restrictions, downstreamOperations);
    assertPinnedRunAndModel(runDir, options.runId, options.role, options.modelIdentity, options.bundle);
    const root = resolve(options.outputDir || join(runDir, 'control', 'worker-bundles', options.callId));
    assertPathWithin(runDir, root, 'worker bundle');
    if (existsSync(root))
        throw new Error(`worker bundle already exists: ${root}`);
    const allowlist = [...new Set(options.allowlist)].sort(utf8Compare);
    if (allowlist.length !== options.allowlist.length) {
        throw new Error('worker allowlist contains duplicate paths');
    }
    if (hasRunCapability(options.bundle.lock.run_format_version, 'semantic-unit-review')
        && (options.role === 'extractor' || options.role === 'normalizer')) {
        validateSemanticProducerDelivery(loadRun(runDir), options.role, options.stage, options.callId, options.taskLine, allowlist.map((path) => ({ path, bytes: readStableRegularFile(join(runDir, path)).bytes })));
    }
    if (options.role === 'verifier-l2f') {
        validateRepresentationRun(loadRun(runDir));
        const match = allowlist.length === 1
            && /^verification\/harness\/material-use-subjects\/([0-9a-f]{64})\.json$/u.exec(allowlist[0]);
        if (!match)
            throw new Error('L2F requires only the exact reserved Core material review view');
        const reservation = readJsonFile(join(runDir, 'control', 'transactions', `RES-material-${match[1]}.json`));
        if (reservation.review_path !== allowlist[0]
            || reservation.inventory_hash !== materialHash(readFileSync(join(runDir, REPRESENTATION_PATH)))
            || reservation.view_hash !== materialHash(readStableRegularFile(join(runDir, allowlist[0])).bytes))
            throw new Error('L2F reserved view or capture changed');
        if (!reservation.producer_context_id || options.producerContextId !== reservation.producer_context_id)
            throw new Error('L2F must withhold the actual reserved producer context');
        if (options.taskLine !== 'Challenge the exact retained representation-use subject.')
            throw new Error('L2F task line must not add producer context');
    }
    if (options.role === 'verifier-l2s') {
        const model = loadRun(runDir);
        const subjectPath = allowlist.find((path) => path.startsWith('verification/harness/semantic-subjects/'));
        if (!subjectPath)
            throw new Error('SEM_ISOLATION L2S requires a sealed semantic subject');
        const subject = parseSemanticJson(readFileSync(join(runDir, subjectPath)));
        validateSemanticSubject(subject, model);
        validateSemanticAttachmentDelivery(subject, options.taskLine, allowlist.map((path) => ({ path, bytes: readStableRegularFile(join(runDir, path)).bytes })));
        const ledger = parseSemanticLedger(readFileSync(join(runDir, SEMANTIC_PATH), 'utf8'));
        const assignmentRow = ledger.assignments.find((row) => {
            const assignment = parseSemanticJson(readFileSync(join(runDir, row.assignment_path)));
            return row.semantic_id === subject.semantic_id && assignment.invocation_id === options.callId;
        });
        if (!assignmentRow)
            throw new Error('SEM_REVIEW L2S dispatch requires retained assignment');
        const producerRow = ledger.subjects.find((row) => row.semantic_id === subject.semantic_id);
        const producerPath = producerRow.producer_receipt_ref.split('@')[0];
        const producer = parseSemanticJson(readFileSync(join(runDir, producerPath)));
        if (options.producerContextId !== producer.context_id)
            throw new Error('SEM_ISOLATION L2S requires actual producer context binding');
    }
    const loadedRole = roleParts(options.bundle, options.role, options.stage);
    const policyPart = loadedRole.parts[loadedRole.policyPartIndex];
    const policyText = blindPolicySlice(policyPart).bytes.toString('utf8');
    const expectedCoreRef = coreBlindPolicyReference(options.bundle, options.role, options.stage);
    const withheldNames = new Set();
    for (const entry of options.withheld) {
        if (!entry || typeof entry !== 'object'
            || Object.keys(entry).sort(utf8Compare).join('\0') !== ['core_ref', 'selector'].join('\0')
            || typeof entry.selector !== 'string'
            || entry.core_ref !== expectedCoreRef) {
            throw new Error('worker withheld selector is not bound to the exact Core blind policy');
        }
        assertSafeRelativePath(entry.selector, 'worker withheld selector');
        if (withheldNames.has(entry.selector)) {
            throw new Error(`worker withheld selector is duplicated: ${entry.selector}`);
        }
        withheldNames.add(entry.selector);
    }
    for (const path of allowlist) {
        assertWorkerAttachmentPath(path);
        if (withheldNames.has(path))
            throw new Error(`allowlist includes withheld path ${path}`);
    }
    const allowlistedSources = allowlist.filter((path) => path.startsWith('corpus/sources/'));
    if (/(?:\bone source (?:file|segment)\b|\ball other sources\b|\brest of the run\b)/iu.test(policyText)
        && allowlistedSources.length > 1) {
        throw new Error('exact Core blind policy permits at most one corpus source in this worker bundle');
    }
    const canonicalFiles = canonicalRunFiles(runDir);
    const requiredWithheld = canonicalFiles.filter((path) => !allowlist.includes(path));
    if (requiredWithheld.length !== withheldNames.size
        || requiredWithheld.some((path) => !withheldNames.has(path))) {
        throw new Error('worker withheld selectors must exactly inventory every canonical run file outside the allowlist');
    }
    const { parts, contract, policyPartIndex } = loadedRole;
    mkdirSync(root, { recursive: true });
    try {
        const coreParts = parts.map((part, index) => {
            const materializedPath = `instructions/${String(index + 1).padStart(2, '0')}.txt`;
            writeFileAtomic(join(root, materializedPath), part.bytes, 0o400);
            return {
                path: part.path,
                selector: part.selector,
                digest: part.digest,
                materialized_path: materializedPath,
            };
        });
        const blindPolicy = blindPolicyFor(policyPart, coreParts[policyPartIndex].materialized_path);
        writeFileAtomic(join(root, 'contracts', 'output.json'), contract.bytes, 0o400);
        const attachments = allowlist.map((runPath, index) => {
            const source = join(runDir, runPath);
            assertPathWithin(runDir, source, 'worker attachment');
            assertNoSymlinkComponents(runDir, source);
            if (!existsSync(source) || !lstatSync(source).isFile() || lstatSync(source).isSymbolicLink()) {
                throw new Error(`worker attachment is missing, non-file, or symlinked: ${runPath}`);
            }
            const bytes = readStableRegularFile(source).bytes;
            const attachmentPath = `files/${String(index + 1).padStart(3, '0')}-${runPath.replaceAll('/', '__')}`;
            writeFileAtomic(join(root, attachmentPath), bytes, 0o400);
            return {
                run_path: runPath,
                attachment_path: attachmentPath,
                digest: sha256Digest(bytes),
            };
        });
        const request = {
            format: LOA_WORKER_REQUEST_FORMAT,
            call_id: options.callId,
            run_id: options.runId,
            stage: options.stage,
            role: options.role,
            kind: options.kind,
            core_parts: coreParts,
            blind_policy: blindPolicy,
            allowlist: attachments,
            withheld: options.withheld,
            procedural_restrictions: restrictions,
            downstream_operations: downstreamOperations,
            task_line: validateTaskLine(options.taskLine),
            output_contract: {
                core_path: contract.path,
                selector: contract.selector,
                digest: contract.digest,
            },
            model_identity: options.modelIdentity,
            bundle_digest: '',
            isolation: {
                fresh_context: true,
                inherit_context: false,
                producer_context_id: options.producerContextId || null,
                filesystem: 'bundle-read-only',
            },
        };
        request.bundle_digest = workerBundleDigest(root, request);
        writeJsonAtomic(join(root, 'request.json'), request, 0o400);
        makeTreeReadOnly(root);
        return { root, request };
    }
    catch (error) {
        rmSync(root, { recursive: true, force: true });
        throw error;
    }
}
export function verifyWorkerBundle(root) {
    const bundleRoot = resolve(root);
    const request = readJsonFile(join(bundleRoot, 'request.json'));
    if (request.format !== LOA_WORKER_REQUEST_FORMAT) {
        throw new Error('worker request format is invalid');
    }
    assertDispatchableRoleStage(request.role, request.stage);
    assertWorkerRoleIsolation(request.role, request.kind, request.isolation?.producer_context_id);
    if (workerBundleDigest(bundleRoot, request) !== request.bundle_digest) {
        throw new Error('worker bundle digest mismatch');
    }
    const runDir = resolve(bundleRoot, '../../..');
    const downstream = CORE_STAGES.indexOf(request.stage) >= CORE_STAGES.indexOf('S5');
    const restrictions = downstream ? retainedRestrictionOverlays(loadRun(runDir)) : [];
    if (JSON.stringify(request.procedural_restrictions) !== JSON.stringify(restrictions)) {
        throw new Error('worker procedural restrictions disagree with retained Core authority');
    }
    if (!downstream && request.downstream_operations.length > 0) {
        throw new Error('worker carries downstream operations before S5');
    }
    if (downstream && restrictions.length > 0 && request.downstream_operations.length === 0) {
        throw new Error('restricted downstream worker omits typed operation tuples');
    }
    assertDownstreamOperationsAllowed(restrictions, request.downstream_operations);
    for (const part of request.core_parts) {
        if (sha256Digest(readFileSync(join(bundleRoot, part.materialized_path))) !== part.digest) {
            throw new Error(`worker Core part changed: ${part.materialized_path}`);
        }
    }
    const policy = request.blind_policy;
    if (!policy
        || typeof policy.byte_start !== 'string'
        || typeof policy.byte_end !== 'string'
        || !/^\d+$/u.test(policy.byte_start)
        || !/^\d+$/u.test(policy.byte_end)) {
        throw new Error('worker blind policy is malformed');
    }
    const policyPart = request.core_parts.find((part) => (part.materialized_path === policy.core_part_path
        && part.path === policy.core_path
        && part.selector === policy.selector));
    if (!policyPart)
        throw new Error('worker blind policy does not name a sealed Core part');
    const policyBytes = readFileSync(join(bundleRoot, policy.core_part_path));
    const start = Number(policy.byte_start);
    const end = Number(policy.byte_end);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end)
        || start < 0 || end <= start || end > policyBytes.byteLength
        || sha256Digest(policyBytes.subarray(start, end)) !== policy.digest) {
        throw new Error('worker blind policy byte slice changed');
    }
    const expectedCoreRef = `${policy.core_path}#${policy.selector}@${policy.digest}`;
    const allowlistedPaths = new Set(request.allowlist.map((entry) => entry.run_path));
    const withheldPaths = new Set();
    for (const withheld of request.withheld) {
        if (withheld.core_ref !== expectedCoreRef || withheldPaths.has(withheld.selector)) {
            throw new Error('worker withheld inventory is unbound or duplicated');
        }
        if (allowlistedPaths.has(withheld.selector)) {
            throw new Error(`worker allowlist includes withheld path ${withheld.selector}`);
        }
        withheldPaths.add(withheld.selector);
    }
    for (const attachment of request.allowlist) {
        assertWorkerAttachmentPath(attachment.run_path);
        if (sha256Digest(readFileSync(join(bundleRoot, attachment.attachment_path)))
            !== attachment.digest) {
            throw new Error(`worker attachment changed: ${attachment.attachment_path}`);
        }
    }
    return request;
}
