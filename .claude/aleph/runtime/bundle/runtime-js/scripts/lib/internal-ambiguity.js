import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { bundleLockBytes, canonicalJsonBytes, resealBundleLock, } from './bundle-format.js';
import { findTables, normalizeHeader, parseBulletFields, parseTables, } from './markdown.js';
export const INTERNAL_AMBIGUITY_FORMAT = 'aleph-internal-ambiguity/v1';
export const INTERNAL_AMBIGUITY_SEARCH_BASIS_FORMAT = 'aleph-internal-ambiguity-search-basis/v1';
export const INTERNAL_AMBIGUITY_REVIEW_SUBJECT_FORMAT = 'aleph-internal-ambiguity-review-subject/v1';
export const MATERIAL_IMPACT_SUBJECT_FORMAT = 'aleph-internal-ambiguity-material-impact-review-subject/v1';
export const PROCEDURAL_SUBJECT_FORMAT = 'aleph-internal-ambiguity-procedural-subject/v1';
export const AUTHORITY_REQUEST_FORMAT = 'aleph-internal-ambiguity-authority-request/v1';
export const AUTHORITY_RESPONSE_FORMAT = 'aleph-internal-ambiguity-authority-response/v1';
export const T5_1_HEADER = [
    'ambiguity_id',
    'source_entity_kind',
    'source_entity_id',
    'source_id',
    'expression_locator',
    'expression_start_byte',
    'expression_end_byte',
    'expression_sha256',
    'expression_bytes_base64',
    'basis_packet_ids',
    'detected_by',
];
export const T5_2_HEADER = [
    'ambiguity_id',
    'assessment_seq',
    'predecessor_assessment_seq',
    'search_scope_kind',
    'search_source_id',
    'search_completion_ref',
    'search_basis_digest',
    'candidate_state',
    'candidate_refs',
    'affected_relation_ids',
    'resolution_state',
    'carry_state',
    'proposed_by',
    'review_subject_digest',
    'reviewed_by',
];
export const T5_3_HEADER = [
    'ambiguity_id',
    'authority_seq',
    'assessment_seq',
    'action',
    'selected_candidate_ref',
    'authority_subject_digest',
    'authority_ref',
    'closure_provenance',
];
export const SEARCH_SCOPE_KINDS = ['local-intervals', 'full-same-source'];
export const CANDIDATE_STATES = [
    'single',
    'multiple',
    'null-no-candidate',
    'null-cannot-determine',
];
export const RESOLUTION_STATES = ['unresolved', 'resolved-local'];
export const CARRY_STATES = ['none', 'explicit'];
export const MATERIALITY_CLASSES = ['B', 'C'];
export const OPERATION_KINDS = [
    'load-bearing-reasoning',
    'unique-relation-or-referent',
    'disposition-validity',
    'contradiction-or-reconciliation-strength',
    'interpretation-dependent-synthesis',
    'required-barrier-dod',
];
export const UNRESOLVED_TREATMENTS = [
    'carry-only',
    'restriction-only',
    'carry-or-restriction',
    'resolution-required',
];
export const PROCEDURAL_ACTIONS = [
    'carry-unresolved',
    'restrict-downstream-use',
    'inspect-source',
    'block-at-current-barrier',
    'request-successor-corpus-run',
    'record-human-observation',
];
export const PROCEDURAL_FOLLOWUP_REASONS = [
    'nonterminal-response',
    'material-impact-revision',
    'presentation-only-replacement',
    'actual-resume-after-suspensive-block',
];
export const CLOSURE_PHASES = [
    'S4-C1-relations-closed',
    'S4-C2-ambiguities-finalized',
    'S4-C3-exit',
];
export function loadPinnedCoreAuthority(options) {
    const lockPath = resolve(options.bundle_lock_path);
    const root = dirname(lockPath);
    const raw = readFileSync(lockPath);
    let lock;
    try {
        lock = JSON.parse(raw.toString('utf8'));
    }
    catch {
        throw new Error('retained bundle lock is not valid JSON');
    }
    if (!raw.equals(bundleLockBytes(lock))) {
        throw new Error('retained bundle lock is not canonical');
    }
    const resealed = resealBundleLock(lock);
    if (resealed.lock_digest !== lock.lock_digest
        || resealed.bundle.digest !== lock.bundle.digest) {
        throw new Error('retained bundle lock does not reproduce its sealed identity');
    }
    if (lock.bundle.digest !== options.expected_bundle_digest
        || lock.core.tree_digest !== options.expected_core_digest) {
        throw new Error('retained bundle/Core identity disagrees with the run pin');
    }
    if (lock.source.manifest_projection_digest
        !== sha256Digest(canonicalJsonBytes(lock.source.manifest_projection))) {
        throw new Error('retained Core manifest projection digest is invalid');
    }
    const files = new Map();
    const fileBytes = new Map();
    for (const record of lock.files) {
        if (files.has(record.path)) {
            throw new Error(`retained bundle inventory duplicates ${record.path}`);
        }
        files.set(record.path, record);
        if (record.classification !== 'core')
            continue;
        const path = join(root, record.path);
        if (!existsSync(path))
            throw new Error(`retained Core file is absent: ${record.path}`);
        const bytes = readFileSync(path);
        if (sha256Digest(bytes) !== record.digest) {
            throw new Error(`retained Core file disagrees with its inventory: ${record.path}`);
        }
        fileBytes.set(record.path, bytes);
    }
    return {
        source_kind: 'retained-immutable-bundle',
        root,
        lock,
        expected_bundle_digest: options.expected_bundle_digest,
        expected_core_digest: options.expected_core_digest,
        files,
        file_bytes: fileBytes,
    };
}
function rowValues(table, keys) {
    return (table?.rows || []).map((row) => {
        const values = {};
        keys.forEach((key, index) => { values[key] = row.cells[index] || ''; });
        return { ...row, values };
    });
}
export function parseInternalAmbiguities(model) {
    const document = model.documents.get('ledgers/internal-ambiguities.md') || null;
    if (!document) {
        return {
            document: null,
            format: '',
            t5_1Tables: [],
            t5_2Tables: [],
            t5_3Tables: [],
            t5_1Rows: [],
            t5_2Rows: [],
            t5_3Rows: [],
        };
    }
    const t5_1Tables = findTables(document.tables, T5_1_HEADER);
    const t5_2Tables = findTables(document.tables, T5_2_HEADER);
    const t5_3Tables = findTables(document.tables, T5_3_HEADER);
    return {
        document,
        format: parseBulletFields(document.text).fields.get('internal ambiguity format') || '',
        t5_1Tables,
        t5_2Tables,
        t5_3Tables,
        t5_1Rows: rowValues(t5_1Tables[0], [
            'ambiguityId', 'sourceEntityKind', 'sourceEntityId', 'sourceId',
            'expressionLocator', 'expressionStartByte', 'expressionEndByte',
            'expressionSha256', 'expressionBytesBase64', 'basisPacketIds', 'detectedBy',
        ]),
        t5_2Rows: rowValues(t5_2Tables[0], [
            'ambiguityId', 'assessmentSeq', 'predecessorAssessmentSeq', 'searchScopeKind',
            'searchSourceId', 'searchCompletionRef', 'searchBasisDigest', 'candidateState',
            'candidateRefs', 'affectedRelationIds', 'resolutionState', 'carryState',
            'proposedBy', 'reviewSubjectDigest', 'reviewedBy',
        ]),
        t5_3Rows: rowValues(t5_3Tables[0], [
            'ambiguityId', 'authoritySeq', 'assessmentSeq', 'action',
            'selectedCandidateRef', 'authoritySubjectDigest', 'authorityRef',
            'closureProvenance',
        ]),
    };
}
export function sha256Digest(bytes) {
    return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}
export function parseOrderedIds(value, family, allowNone = false) {
    if (allowNone && value === 'none')
        return { ids: [], clean: true };
    const parts = value.split(',');
    const ids = parts.map((part) => part.trim()).filter(Boolean);
    const number = (id) => Number(id.slice(id.indexOf('-') + 1));
    return {
        ids,
        clean: ids.length > 0
            && ids.length === parts.length
            && ids.every((id) => new RegExp(`^${family}-\\d{4,}$`, 'u').test(id))
            && new Set(ids).size === ids.length
            && ids.every((id, index) => index === 0 || number(ids[index - 1]) < number(id)),
    };
}
export function legalResolutionCarryState(resolutionState, carryState, affectedRelationCount) {
    const nonempty = affectedRelationCount > 0;
    return ((resolutionState === 'resolved-local' && carryState === 'none')
        || (resolutionState === 'unresolved' && carryState === 'none' && !nonempty)
        || (resolutionState === 'unresolved' && carryState === 'explicit' && nonempty));
}
function exactObjectKeys(value, keys) {
    return Object.keys(value).join('\0') === keys.join('\0');
}
function numericSuffix(id) {
    return BigInt(id.slice(id.indexOf('-') + 1));
}
function compareCandidates(left, right) {
    if (left.kind !== right.kind)
        return left.kind === 'PKT' ? -1 : 1;
    if (left.kind === 'PKT' && right.kind === 'PKT') {
        const leftNumber = numericSuffix(left.id);
        const rightNumber = numericSuffix(right.id);
        return leftNumber < rightNumber ? -1 : leftNumber > rightNumber ? 1 : 0;
    }
    if (left.kind === 'source-locus' && right.kind === 'source-locus') {
        const leftNumber = numericSuffix(left.source_id);
        const rightNumber = numericSuffix(right.source_id);
        if (leftNumber !== rightNumber)
            return leftNumber < rightNumber ? -1 : 1;
        return Buffer.compare(Buffer.from(left.locator, 'utf8'), Buffer.from(right.locator, 'utf8'));
    }
    return 0;
}
export function parseCandidateRefs(raw) {
    let parsed;
    try {
        parsed = JSON.parse(raw);
    }
    catch {
        return { candidates: [], clean: false, error: 'candidate_refs is not valid JSON' };
    }
    if (!Array.isArray(parsed) || JSON.stringify(parsed) !== raw) {
        return { candidates: [], clean: false, error: 'candidate_refs must be compact canonical JSON' };
    }
    const candidates = [];
    for (const value of parsed) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) {
            return { candidates: [], clean: false, error: 'candidate_refs contains a non-object' };
        }
        const candidate = value;
        if (candidate.kind === 'PKT') {
            if (!exactObjectKeys(candidate, ['kind', 'id'])
                || typeof candidate.id !== 'string'
                || !/^PKT-\d{4,}$/u.test(candidate.id)) {
                return { candidates: [], clean: false, error: 'PKT candidate grammar is invalid' };
            }
            candidates.push({ kind: 'PKT', id: candidate.id });
        }
        else if (candidate.kind === 'source-locus') {
            if (!exactObjectKeys(candidate, ['kind', 'source_id', 'locator', 'span_hash'])
                || typeof candidate.source_id !== 'string'
                || !/^SRC-\d{4,}$/u.test(candidate.source_id)
                || typeof candidate.locator !== 'string' || candidate.locator.length === 0
                || typeof candidate.span_hash !== 'string'
                || !/^sha256:[a-f0-9]{64}$/u.test(candidate.span_hash)) {
                return { candidates: [], clean: false, error: 'source-locus candidate grammar is invalid' };
            }
            candidates.push({
                kind: 'source-locus',
                source_id: candidate.source_id,
                locator: candidate.locator,
                span_hash: candidate.span_hash,
            });
        }
        else {
            return { candidates: [], clean: false, error: 'candidate kind is not permitted' };
        }
    }
    const serialized = candidates.map((candidate) => JSON.stringify(candidate));
    if (new Set(serialized).size !== serialized.length) {
        return { candidates: [], clean: false, error: 'candidate_refs contains duplicates' };
    }
    for (let index = 1; index < candidates.length; index += 1) {
        if (compareCandidates(candidates[index - 1], candidates[index]) >= 0) {
            return { candidates: [], clean: false, error: 'candidate_refs is not in canonical order' };
        }
    }
    return { candidates, clean: true };
}
export function searchBasisJson(basis) {
    return JSON.stringify({
        format: INTERNAL_AMBIGUITY_SEARCH_BASIS_FORMAT,
        source_id: basis.source_id,
        source_hash: basis.source_hash,
        source_length_bytes: basis.source_length_bytes,
        scope_kind: basis.scope_kind,
        scope_refs: basis.scope_refs,
        completion_ref: basis.completion_ref,
        expression_start_byte: basis.expression_start_byte,
        expression_end_byte: basis.expression_end_byte,
        expression_sha256: basis.expression_sha256,
        basis_packet_ids: basis.basis_packet_ids,
        candidate_state: basis.candidate_state,
        candidate_refs: basis.candidate_refs,
    });
}
export function searchBasisDigest(basis) {
    return sha256Digest(Buffer.from(searchBasisJson(basis), 'utf8'));
}
export function ambiguityReviewSubjectJson(subject) {
    return JSON.stringify({
        format: INTERNAL_AMBIGUITY_REVIEW_SUBJECT_FORMAT,
        source_entity_kind: subject.source_entity_kind,
        source_entity_id: subject.source_entity_id,
        source_id: subject.source_id,
        expression_locator: subject.expression_locator,
        expression_start_byte: subject.expression_start_byte,
        expression_end_byte: subject.expression_end_byte,
        expression_sha256: subject.expression_sha256,
        expression_bytes_base64: subject.expression_bytes_base64,
        basis_packet_ids: subject.basis_packet_ids,
        search_scope_kind: subject.search_scope_kind,
        search_completion_ref: subject.search_completion_ref,
        search_basis_digest: subject.search_basis_digest,
        candidate_state: subject.candidate_state,
        candidate_refs: subject.candidate_refs,
        affected_relation_ids: subject.affected_relation_ids,
        resolution_state: subject.resolution_state,
        carry_state: subject.carry_state,
        proposed_by: subject.proposed_by,
    });
}
export function ambiguityReviewSubjectDigest(subject) {
    return sha256Digest(Buffer.from(ambiguityReviewSubjectJson(subject), 'utf8'));
}
const ACTION_CONSEQUENCES = {
    'carry-unresolved': {
        action: 'carry-unresolved', terminality: 'progression-enabling-terminal',
        c2_effect: 'eligible-if-all-other-dod-pass', current_run_effect: 'continue-where-otherwise-legal',
        scope_effect: 'carry-reviewed-unresolved-dependencies', next_request: 'none',
        successor_run: 'not-required',
    },
    'restrict-downstream-use': {
        action: 'restrict-downstream-use', terminality: 'progression-enabling-terminal',
        c2_effect: 'eligible-if-all-other-dod-pass', current_run_effect: 'continue-where-otherwise-legal',
        scope_effect: 'prohibit-canonical-scope-operations', next_request: 'none',
        successor_run: 'not-required',
    },
    'inspect-source': {
        action: 'inspect-source', terminality: 'nonterminal', c2_effect: 'not-eligible',
        current_run_effect: 'blocked-at-s4-c2', scope_effect: 'none',
        next_request: 'Q+1-after-basis-verification', successor_run: 'not-required',
    },
    'block-at-current-barrier': {
        action: 'block-at-current-barrier', terminality: 'nonterminal-suspensive',
        c2_effect: 'not-eligible', current_run_effect: 'blocked-at-s4-c2', scope_effect: 'none',
        next_request: 'Q+1-after-actual-resume', successor_run: 'not-required',
    },
    'request-successor-corpus-run': {
        action: 'request-successor-corpus-run',
        terminality: 'current-request-terminal-current-run-non-progressing', c2_effect: 'not-eligible',
        current_run_effect: 'halted-successor-required', scope_effect: 'none', next_request: 'none',
        successor_run: 'required',
    },
    'record-human-observation': {
        action: 'record-human-observation', terminality: 'nonterminal', c2_effect: 'not-eligible',
        current_run_effect: 'blocked-at-s4-c2', scope_effect: 'retain-observation-bytes-only',
        next_request: 'Q+1-after-basis-verification', successor_run: 'not-required',
    },
};
export function projectProceduralActions(scope) {
    if (scope.impact_rows.length === 0) {
        return { allowed_actions: [], action_consequences: [] };
    }
    const allowed = PROCEDURAL_ACTIONS.filter((action) => {
        if (action === 'carry-unresolved') {
            return scope.impact_rows.every((row) => (row.unresolved_treatment === 'carry-only'
                || row.unresolved_treatment === 'carry-or-restriction'));
        }
        if (action === 'restrict-downstream-use') {
            return scope.impact_rows.every((row) => (row.unresolved_treatment === 'restriction-only'
                || row.unresolved_treatment === 'carry-or-restriction'));
        }
        return true;
    });
    return {
        allowed_actions: allowed,
        action_consequences: allowed.map((action) => structuredClone(ACTION_CONSEQUENCES[action])),
    };
}
function affectedIdOrder(id) {
    const match = id.match(/^(PKT|CC|REL)-(\d{4,})$/u);
    return match ? [['PKT', 'CC', 'REL'].indexOf(match[1]), BigInt(match[2])]
        : [99, BigInt('999999999999999999999999999999999999')];
}
function compareAffectedIds(left, right) {
    const leftOrder = affectedIdOrder(left);
    const rightOrder = affectedIdOrder(right);
    if (leftOrder[0] !== rightOrder[0])
        return leftOrder[0] - rightOrder[0];
    return leftOrder[1] < rightOrder[1] ? -1 : leftOrder[1] > rightOrder[1] ? 1 : 0;
}
function compareImpactRows(left, right) {
    const idOrder = compareAffectedIds(left.affected_id, right.affected_id);
    if (idOrder !== 0)
        return idOrder;
    const operationOrder = OPERATION_KINDS.indexOf(left.operation_kind)
        - OPERATION_KINDS.indexOf(right.operation_kind);
    if (operationOrder !== 0)
        return operationOrder;
    return Buffer.compare(Buffer.from(left.requirement_ref, 'utf8'), Buffer.from(right.requirement_ref, 'utf8'));
}
export function operativeScopeProblems(scope) {
    const problems = [];
    if (!exactObjectKeys(scope, ['affected_ids', 'impact_rows'])
        || !Array.isArray(scope.affected_ids) || !Array.isArray(scope.impact_rows)) {
        return ['operative_scope must contain exactly affected_ids and impact_rows arrays'];
    }
    if (scope.affected_ids.some((id) => !/^(?:PKT|CC|REL)-\d{4,}$/u.test(id))) {
        problems.push('operative_scope affected_ids contains an illegal ID kind');
    }
    if (new Set(scope.affected_ids).size !== scope.affected_ids.length) {
        problems.push('operative_scope affected_ids contains duplicates');
    }
    for (let index = 1; index < scope.affected_ids.length; index += 1) {
        if (compareAffectedIds(scope.affected_ids[index - 1], scope.affected_ids[index]) >= 0) {
            problems.push('operative_scope affected_ids is not in canonical order');
            break;
        }
    }
    const tuples = new Map();
    const projected = new Set();
    let previousRow = null;
    for (const row of scope.impact_rows) {
        if (!row || typeof row !== 'object' || !exactObjectKeys(row, [
            'affected_id', 'operation_kind', 'requirement_ref',
            'unresolved_treatment', 'consequence_if_unresolved',
        ])) {
            problems.push('impact row fields are malformed');
            continue;
        }
        projected.add(row.affected_id);
        if (!OPERATION_KINDS.includes(row.operation_kind)) {
            problems.push(`${row.affected_id || 'impact row'} has illegal operation_kind`);
        }
        if (!UNRESOLVED_TREATMENTS.includes(row.unresolved_treatment)) {
            problems.push(`${row.affected_id || 'impact row'} has illegal unresolved_treatment`);
        }
        try {
            parseRequirementRef(row.requirement_ref);
        }
        catch {
            problems.push(`${row.affected_id || 'impact row'} has malformed requirement_ref`);
        }
        if (!row.consequence_if_unresolved
            || row.consequence_if_unresolved !== row.consequence_if_unresolved.trim()) {
            problems.push(`${row.affected_id || 'impact row'} has malformed consequence prose`);
        }
        const tuple = `${row.affected_id}\0${row.operation_kind}\0${row.requirement_ref}`;
        const prior = tuples.get(tuple);
        if (prior) {
            problems.push(prior.unresolved_treatment === row.unresolved_treatment
                && prior.consequence_if_unresolved === row.consequence_if_unresolved
                ? 'impact rows contain a duplicate tuple'
                : 'impact rows contain contradictory duplicate tuples');
        }
        else
            tuples.set(tuple, row);
        if (previousRow && compareImpactRows(previousRow, row) >= 0) {
            problems.push('impact rows are not in canonical order');
        }
        previousRow = row;
    }
    if (projected.size !== scope.affected_ids.length
        || scope.affected_ids.some((id) => !projected.has(id))) {
        problems.push('operative_scope affected_ids must equal the impact-row ID projection');
    }
    return problems;
}
export function materialImpactSubjectJson(subject) {
    return JSON.stringify({
        format: subject.format,
        run_id: subject.run_id,
        ambiguity_id: subject.ambiguity_id,
        assessment_seq: subject.assessment_seq,
        material_impact_seq: subject.material_impact_seq,
        t5_2_assessment_ref: subject.t5_2_assessment_ref,
        t5_2_review_subject_digest: subject.t5_2_review_subject_digest,
        t5_2_review_ref: subject.t5_2_review_ref,
        c1_relation_basis_ref: subject.c1_relation_basis_ref,
        materiality_class: subject.materiality_class,
        operative_scope: orderedOperativeScope(subject.operative_scope),
        source_locators: subject.source_locators,
        reviewed_unaffected_ids: subject.reviewed_unaffected_ids,
        unresolved_statement: subject.unresolved_statement,
        review_proposition: subject.review_proposition,
        proposed_by: subject.proposed_by,
    });
}
export function materialImpactSubjectDigest(subject) {
    return sha256Digest(Buffer.from(materialImpactSubjectJson(subject), 'utf8'));
}
export function materialImpactSubjectProblems(subject) {
    const problems = [];
    if (subject.format !== MATERIAL_IMPACT_SUBJECT_FORMAT)
        problems.push('material-impact format is invalid');
    if (!/^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/u.test(subject.run_id))
        problems.push('run_id is invalid');
    if (!/^AMB-\d{4,}$/u.test(subject.ambiguity_id))
        problems.push('ambiguity_id is invalid');
    if (!Number.isSafeInteger(subject.assessment_seq) || subject.assessment_seq < 1
        || !Number.isSafeInteger(subject.material_impact_seq) || subject.material_impact_seq < 1) {
        problems.push('assessment/material-impact sequence is invalid');
    }
    const expectedAssessmentPrefix = `internal-ambiguity:T5.2:${subject.ambiguity_id}:A${String(subject.assessment_seq)}@`;
    if (!subject.t5_2_assessment_ref.startsWith(expectedAssessmentPrefix)
        || !/^internal-ambiguity:T5\.2:AMB-\d{4,}:A[1-9]\d*@sha256:[a-f0-9]{64}$/u.test(subject.t5_2_assessment_ref)) {
        problems.push('t5_2_assessment_ref is invalid');
    }
    if (!/^sha256:[a-f0-9]{64}$/u.test(subject.t5_2_review_subject_digest)) {
        problems.push('t5_2_review_subject_digest is invalid');
    }
    if (!/^ambiguity-review-verdict:VER-\d{4,}@sha256:[a-f0-9]{64}$/u.test(subject.t5_2_review_ref)) {
        problems.push('t5_2_review_ref is invalid');
    }
    if (subject.c1_relation_basis_ref !== 'none'
        && subject.c1_relation_basis_ref
            !== 'relations-basis:closure_phase=S4-C1-relations-closed;artifact=ledgers/relations.md') {
        problems.push('c1_relation_basis_ref is invalid');
    }
    const scopeProblems = operativeScopeProblems(subject.operative_scope);
    problems.push(...scopeProblems);
    if (subject.materiality_class === 'B') {
        if (subject.operative_scope.affected_ids.length || subject.operative_scope.impact_rows.length) {
            problems.push('Class B operative scope must be empty');
        }
    }
    else if (subject.materiality_class === 'C') {
        if (!subject.operative_scope.affected_ids.length || !subject.operative_scope.impact_rows.length) {
            problems.push('Class C operative scope must be nonempty');
        }
    }
    else
        problems.push('materiality_class is invalid');
    for (const [label, values] of [
        ['source_locators', subject.source_locators],
        ['reviewed_unaffected_ids', subject.reviewed_unaffected_ids],
    ]) {
        if (!Array.isArray(values)
            || values.some((value) => typeof value !== 'string' || !value || value !== value.trim())
            || new Set(values).size !== values.length) {
            problems.push(`${label} is malformed or duplicated`);
        }
    }
    if (!subject.unresolved_statement || subject.unresolved_statement !== subject.unresolved_statement.trim()) {
        problems.push('unresolved_statement is malformed');
    }
    if (subject.review_proposition
        !== 'class-B-or-C-and-canonical-operative-scope-complete-and-accurate-under-cited-Core-requirements') {
        problems.push('review_proposition is invalid');
    }
    if (!/^(?:human|invocation):\S+$/u.test(subject.proposed_by))
        problems.push('proposed_by is invalid');
    return problems;
}
function orderedOperativeScope(scope) {
    return {
        affected_ids: [...scope.affected_ids],
        impact_rows: scope.impact_rows.map((row) => ({
            affected_id: row.affected_id,
            operation_kind: row.operation_kind,
            requirement_ref: row.requirement_ref,
            unresolved_treatment: row.unresolved_treatment,
            consequence_if_unresolved: row.consequence_if_unresolved,
        })),
    };
}
function orderedCandidate(candidate) {
    return candidate.kind === 'PKT'
        ? { kind: candidate.kind, id: candidate.id }
        : {
            kind: candidate.kind,
            source_id: candidate.source_id,
            locator: candidate.locator,
            span_hash: candidate.span_hash,
        };
}
function orderedActionConsequence(consequence) {
    return {
        action: consequence.action,
        terminality: consequence.terminality,
        c2_effect: consequence.c2_effect,
        current_run_effect: consequence.current_run_effect,
        scope_effect: consequence.scope_effect,
        next_request: consequence.next_request,
        successor_run: consequence.successor_run,
    };
}
function orderedProceduralAuthoritySubject(subject) {
    return {
        format: subject.format,
        decision_category: subject.decision_category,
        run_id: subject.run_id,
        ambiguity_id: subject.ambiguity_id,
        assessment_seq: subject.assessment_seq,
        t5_2_assessment_ref: subject.t5_2_assessment_ref,
        t5_2_review_subject_digest: subject.t5_2_review_subject_digest,
        t5_2_review_ref: subject.t5_2_review_ref,
        prior_indeterminate_review_refs: subject.prior_indeterminate_review_refs,
        resolution_state: subject.resolution_state,
        candidate_state: subject.candidate_state,
        candidate_refs: subject.candidate_refs.map(orderedCandidate),
        carry_state: subject.carry_state,
        affected_relation_ids: subject.affected_relation_ids,
        c1_relation_basis_ref: subject.c1_relation_basis_ref,
        material_impact_seq: subject.material_impact_seq,
        material_impact_subject_ref: subject.material_impact_subject_ref,
        material_impact_review_ref: subject.material_impact_review_ref,
        material_impact_review_verdict: subject.material_impact_review_verdict,
        materiality_class: subject.materiality_class,
        operative_scope: orderedOperativeScope(subject.operative_scope),
        source_locators: subject.source_locators,
        reviewed_unaffected_ids: subject.reviewed_unaffected_ids,
        unresolved_statement: subject.unresolved_statement,
        allowed_actions: subject.allowed_actions,
        action_consequences: subject.action_consequences.map(orderedActionConsequence),
    };
}
export function proceduralAuthoritySubjectJson(subject) {
    return JSON.stringify(orderedProceduralAuthoritySubject(subject));
}
export function proceduralAuthoritySubjectDigest(subject) {
    return sha256Digest(Buffer.from(proceduralAuthoritySubjectJson(subject), 'utf8'));
}
export function buildProceduralAuthoritySubject(input) {
    const problems = operativeScopeProblems(input.operative_scope);
    if (problems.length || input.operative_scope.impact_rows.length === 0) {
        throw new Error(`Class C operative scope is invalid: ${problems.join('; ') || 'empty impact rows'}`);
    }
    const projection = projectProceduralActions(input.operative_scope);
    return {
        format: PROCEDURAL_SUBJECT_FORMAT,
        decision_category: 'internal-ambiguity-procedural-decision',
        run_id: input.run_id,
        ambiguity_id: input.ambiguity_id,
        assessment_seq: input.assessment_seq,
        t5_2_assessment_ref: input.t5_2_assessment_ref,
        t5_2_review_subject_digest: input.t5_2_review_subject_digest,
        t5_2_review_ref: input.t5_2_review_ref,
        prior_indeterminate_review_refs: input.prior_indeterminate_review_refs,
        resolution_state: 'unresolved',
        candidate_state: input.candidate_state,
        candidate_refs: input.candidate_refs,
        carry_state: input.carry_state,
        affected_relation_ids: input.affected_relation_ids,
        c1_relation_basis_ref: input.c1_relation_basis_ref,
        material_impact_seq: input.material_impact_seq,
        material_impact_subject_ref: input.material_impact_subject_ref,
        material_impact_review_ref: input.material_impact_review_ref,
        material_impact_review_verdict: 'upheld',
        materiality_class: 'C',
        operative_scope: input.operative_scope,
        source_locators: input.source_locators,
        reviewed_unaffected_ids: input.reviewed_unaffected_ids,
        unresolved_statement: input.unresolved_statement,
        allowed_actions: projection.allowed_actions,
        action_consequences: projection.action_consequences,
    };
}
export function proceduralRequestId(ambiguityId, assessmentSeq, requestSeq) {
    if (!/^AMB-\d{4,}$/u.test(ambiguityId)
        || !Number.isSafeInteger(assessmentSeq) || assessmentSeq < 1
        || !Number.isSafeInteger(requestSeq) || requestSeq < 1) {
        throw new Error('procedural request identity components are invalid');
    }
    return `GATE-S4-${ambiguityId}-A${String(assessmentSeq)}-Q${String(requestSeq)}`;
}
export function proceduralResponseId(requestId) {
    if (!/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*$/u.test(requestId)) {
        throw new Error('procedural request identity is invalid');
    }
    return requestId.replace(/^GATE/u, 'RESP');
}
export function proceduralPresentation(subject) {
    return {
        classification: 'NON-OPERATIVE-DETERMINISTIC-PROJECTION',
        authority_subject_digest: proceduralAuthoritySubjectDigest(subject),
        unresolved_statement: subject.unresolved_statement,
        operative_scope: orderedOperativeScope(subject.operative_scope),
        source_locators: [...subject.source_locators],
        reviewed_unaffected_ids: [...subject.reviewed_unaffected_ids],
        allowed_actions: [...subject.allowed_actions],
        action_consequences: subject.action_consequences.map(orderedActionConsequence),
    };
}
export function buildProceduralAuthorityRequest(options) {
    if (!options.required_authority_identity
        || options.required_authority_identity !== options.required_authority_identity.trim()
        || !/^(?:human|invocation):\S+$/u.test(options.prepared_by)
        || !options.requested_at || options.requested_at !== options.requested_at.trim()) {
        throw new Error('procedural request authority, producer, or timestamp is invalid');
    }
    return {
        format: AUTHORITY_REQUEST_FORMAT,
        request_id: proceduralRequestId(options.subject.ambiguity_id, options.subject.assessment_seq, options.request_seq),
        decision_category: 'internal-ambiguity-procedural-decision',
        run_id: options.subject.run_id,
        stage: 'S4',
        barrier: 'S4-C2',
        ambiguity_id: options.subject.ambiguity_id,
        assessment_seq: options.subject.assessment_seq,
        authority_subject: options.subject,
        authority_subject_digest: proceduralAuthoritySubjectDigest(options.subject),
        presentation: options.presentation ? proceduralPresentation(options.subject) : null,
        required_authority: { kind: 'human', identity: options.required_authority_identity },
        prepared_by: options.prepared_by,
        requested_at: options.requested_at,
    };
}
export function proceduralAuthorityRequestJson(request) {
    return JSON.stringify({
        format: request.format,
        request_id: request.request_id,
        decision_category: request.decision_category,
        run_id: request.run_id,
        stage: request.stage,
        barrier: request.barrier,
        ambiguity_id: request.ambiguity_id,
        assessment_seq: request.assessment_seq,
        authority_subject: orderedProceduralAuthoritySubject(request.authority_subject),
        authority_subject_digest: request.authority_subject_digest,
        presentation: request.presentation === null ? null : {
            classification: request.presentation.classification,
            authority_subject_digest: request.presentation.authority_subject_digest,
            unresolved_statement: request.presentation.unresolved_statement,
            operative_scope: orderedOperativeScope(request.presentation.operative_scope),
            source_locators: [...request.presentation.source_locators],
            reviewed_unaffected_ids: [...request.presentation.reviewed_unaffected_ids],
            allowed_actions: [...request.presentation.allowed_actions],
            action_consequences: request.presentation.action_consequences.map(orderedActionConsequence),
        },
        required_authority: {
            kind: request.required_authority.kind,
            identity: request.required_authority.identity,
        },
        prepared_by: request.prepared_by,
        requested_at: request.requested_at,
    });
}
export function validateProceduralAuthorityRequest(request) {
    const requestSeq = Number(request.request_id.match(/-Q([1-9]\d*)$/u)?.[1] || '0');
    const projection = projectProceduralActions(request.authority_subject.operative_scope);
    const expectedPresentation = proceduralPresentation(request.authority_subject);
    if (request.format !== AUTHORITY_REQUEST_FORMAT
        || request.decision_category !== 'internal-ambiguity-procedural-decision'
        || request.stage !== 'S4' || request.barrier !== 'S4-C2'
        || request.request_id !== proceduralRequestId(request.ambiguity_id, request.assessment_seq, requestSeq)
        || request.run_id !== request.authority_subject.run_id
        || request.ambiguity_id !== request.authority_subject.ambiguity_id
        || request.assessment_seq !== request.authority_subject.assessment_seq
        || request.authority_subject_digest !== proceduralAuthoritySubjectDigest(request.authority_subject)
        || JSON.stringify(request.authority_subject.allowed_actions) !== JSON.stringify(projection.allowed_actions)
        || JSON.stringify(request.authority_subject.action_consequences) !== JSON.stringify(projection.action_consequences)
        || (request.presentation !== null
            && JSON.stringify(request.presentation) !== JSON.stringify(expectedPresentation))
        || request.required_authority.kind !== 'human' || !request.required_authority.identity
        || !/^(?:human|invocation):\S+$/u.test(request.prepared_by) || !request.requested_at) {
        throw new Error('procedural authority request is inconsistent');
    }
    const text = proceduralAuthorityRequestJson(request);
    if (text !== JSON.stringify(request)
        || proceduralAuthoritySubjectJson(request.authority_subject)
            !== JSON.stringify(request.authority_subject)) {
        throw new Error('procedural authority request keys are not in exact canonical order');
    }
    return Buffer.from(text, 'utf8');
}
export function buildProceduralAuthorityResponse(options) {
    const canonical = Buffer.from(proceduralAuthorityRequestJson(options.request), 'utf8');
    if (!canonical.equals(options.request_bytes)) {
        throw new Error('procedural response request bytes are not exact canonical retained bytes');
    }
    if (options.authority_identity !== options.request.required_authority.identity
        || !options.request.authority_subject.allowed_actions.includes(options.selected_action)
        || !options.recorded_at || options.recorded_at !== options.recorded_at.trim()) {
        throw new Error('procedural response authority, action, or timestamp is invalid');
    }
    if (options.observation !== null)
        validateTextBlob(options.observation);
    if (options.comment !== null)
        validateTextBlob(options.comment);
    if ((options.selected_action === 'record-human-observation') !== (options.observation !== null)) {
        throw new Error('record-human-observation is exactly the action that requires observation bytes');
    }
    return {
        format: AUTHORITY_RESPONSE_FORMAT,
        response_id: proceduralResponseId(options.request.request_id),
        request_id: options.request.request_id,
        request_ref: `control/gates/${options.request.request_id}-request.json`,
        request_digest: sha256Digest(options.request_bytes),
        authority_subject_digest: options.request.authority_subject_digest,
        authority: { kind: 'human', identity: options.authority_identity },
        selected_action: options.selected_action,
        observation: options.observation,
        comment: options.comment,
        recorded_at: options.recorded_at,
    };
}
export function proceduralAuthorityResponseJson(response) {
    const textBlob = (value) => value === null ? null : {
        encoding: value.encoding,
        media_type: value.media_type,
        bytes_base64: value.bytes_base64,
        sha256: value.sha256,
    };
    return JSON.stringify({
        format: response.format,
        response_id: response.response_id,
        request_id: response.request_id,
        request_ref: response.request_ref,
        request_digest: response.request_digest,
        authority_subject_digest: response.authority_subject_digest,
        authority: { kind: response.authority.kind, identity: response.authority.identity },
        selected_action: response.selected_action,
        observation: textBlob(response.observation),
        comment: textBlob(response.comment),
        recorded_at: response.recorded_at,
    });
}
export function validateProceduralAuthorityResponse(request, requestBytes, response) {
    const rebuilt = buildProceduralAuthorityResponse({
        request,
        request_bytes: requestBytes,
        authority_identity: response.authority.identity,
        selected_action: response.selected_action,
        observation: response.observation,
        comment: response.comment,
        recorded_at: response.recorded_at,
    });
    if (JSON.stringify(rebuilt) !== JSON.stringify(response)) {
        throw new Error('procedural authority response does not equal the exact Core projection');
    }
    const text = proceduralAuthorityResponseJson(response);
    if (text !== JSON.stringify(response)) {
        throw new Error('procedural authority response keys are not in exact canonical order');
    }
    return Buffer.from(text, 'utf8');
}
function proceduralRequestSequence(requestId) {
    const match = requestId.match(/^GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q([1-9]\d*)$/u);
    const sequence = Number(match?.[1] || '0');
    if (!Number.isSafeInteger(sequence) || sequence < 1) {
        throw new Error('procedural request sequence is invalid');
    }
    return sequence;
}
function immutableProceduralBasis(subject) {
    return JSON.stringify({
        run_id: subject.run_id,
        ambiguity_id: subject.ambiguity_id,
        assessment_seq: subject.assessment_seq,
        t5_2_assessment_ref: subject.t5_2_assessment_ref,
        t5_2_review_subject_digest: subject.t5_2_review_subject_digest,
        t5_2_review_ref: subject.t5_2_review_ref,
        prior_indeterminate_review_refs: subject.prior_indeterminate_review_refs,
        resolution_state: subject.resolution_state,
        candidate_state: subject.candidate_state,
        candidate_refs: subject.candidate_refs,
        carry_state: subject.carry_state,
        affected_relation_ids: subject.affected_relation_ids,
        c1_relation_basis_ref: subject.c1_relation_basis_ref,
    });
}
export function planProceduralAuthorityFollowup(options) {
    const canonicalRequest = validateProceduralAuthorityRequest(options.current_request);
    if (!canonicalRequest.equals(options.current_request_bytes)) {
        throw new Error('procedural follow-up requires exact retained current request bytes');
    }
    if ((options.current_response === null) !== (options.current_response_bytes === null)) {
        throw new Error('procedural follow-up response value/bytes are inconsistent');
    }
    if (options.current_response && options.current_response_bytes) {
        const canonicalResponse = validateProceduralAuthorityResponse(options.current_request, options.current_request_bytes, options.current_response);
        if (!canonicalResponse.equals(options.current_response_bytes)) {
            throw new Error('procedural follow-up requires exact retained current response bytes');
        }
    }
    const currentSequence = proceduralRequestSequence(options.current_request.request_id);
    const expectedIds = Array.from({ length: currentSequence }, (_, index) => proceduralRequestId(options.current_request.ambiguity_id, options.current_request.assessment_seq, index + 1));
    if (JSON.stringify(options.existing_request_ids) !== JSON.stringify(expectedIds)) {
        throw new Error('procedural follow-up request Q history is forked, reused, or noncontiguous');
    }
    if (options.retained_material_impact_seqs.some((value, index) => (!Number.isSafeInteger(value) || value !== index + 1)) || !options.retained_material_impact_seqs.includes(options.current_request.authority_subject.material_impact_seq)) {
        throw new Error('procedural follow-up material-impact M history is forked or noncontiguous');
    }
    if (immutableProceduralBasis(options.next_subject)
        !== immutableProceduralBasis(options.current_request.authority_subject)) {
        throw new Error('procedural follow-up attempted to change immutable T5.2/C1 basis');
    }
    const action = options.current_response?.selected_action || null;
    const sameSubject = proceduralAuthoritySubjectDigest(options.next_subject)
        === options.current_request.authority_subject_digest;
    if (options.reason === 'nonterminal-response') {
        if (action !== 'inspect-source' && action !== 'record-human-observation') {
            throw new Error('nonterminal-response follow-up requires an applied nonterminal response');
        }
        if (!sameSubject)
            throw new Error('nonterminal-response follow-up must preserve the authority subject');
    }
    else if (options.reason === 'actual-resume-after-suspensive-block') {
        if (action !== 'block-at-current-barrier') {
            throw new Error('actual resume follow-up requires a suspensive block response');
        }
        if (!sameSubject)
            throw new Error('suspensive resume follow-up must preserve the authority subject');
    }
    else if (options.reason === 'presentation-only-replacement') {
        if (options.current_response !== null || !sameSubject) {
            throw new Error('presentation-only replacement requires an unanswered unchanged authority subject');
        }
        const projected = options.presentation
            ? proceduralPresentation(options.next_subject)
            : null;
        if (JSON.stringify(projected) === JSON.stringify(options.current_request.presentation)) {
            throw new Error('presentation-only replacement must change only the non-operative presentation');
        }
    }
    else if (options.reason === 'material-impact-revision') {
        if (action === 'carry-unresolved' || action === 'restrict-downstream-use'
            || action === 'request-successor-corpus-run') {
            throw new Error('material-impact revision is forbidden after a terminal authority consequence');
        }
        const latestMaterialSequence = options.retained_material_impact_seqs.at(-1) || 0;
        if (options.next_subject.material_impact_seq !== latestMaterialSequence
            || latestMaterialSequence <= options.current_request.authority_subject.material_impact_seq) {
            throw new Error('material-impact revision must bind the latest contiguous new M subject');
        }
        if (sameSubject)
            throw new Error('material-impact revision must change the authority subject digest');
    }
    else {
        throw new Error('procedural follow-up reason is invalid');
    }
    return buildProceduralAuthorityRequest({
        request_seq: currentSequence + 1,
        subject: options.next_subject,
        presentation: options.presentation,
        required_authority_identity: options.required_authority_identity,
        prepared_by: options.prepared_by,
        requested_at: options.requested_at,
    });
}
export function nextProceduralAuthoritySequence(rows, ambiguityId) {
    const sequences = rows
        .filter((row) => row.ambiguityId === ambiguityId)
        .map((row) => Number(row.authoritySeq))
        .sort((left, right) => left - right);
    if (sequences.some((value, index) => !Number.isSafeInteger(value) || value !== index + 1)) {
        throw new Error(`${ambiguityId} authority history is forked or noncontiguous`);
    }
    return sequences.length + 1;
}
export function buildProceduralAuthorityLedgerRow(options) {
    const canonicalRequest = validateProceduralAuthorityRequest(options.request);
    const canonicalResponse = validateProceduralAuthorityResponse(options.request, options.request_bytes, options.response);
    if (!canonicalRequest.equals(options.request_bytes)
        || !canonicalResponse.equals(options.response_bytes)) {
        throw new Error('procedural authority ledger row requires exact retained request/response bytes');
    }
    if (!Number.isSafeInteger(options.authority_seq) || options.authority_seq < 1) {
        throw new Error('procedural authority_seq must be a positive integer');
    }
    const requestDigest = sha256Digest(options.request_bytes);
    const responseDigest = sha256Digest(options.response_bytes);
    return {
        ambiguityId: options.request.ambiguity_id,
        authoritySeq: String(options.authority_seq),
        assessmentSeq: String(options.request.assessment_seq),
        action: options.response.selected_action,
        selectedCandidateRef: 'none',
        authoritySubjectDigest: options.request.authority_subject_digest,
        authorityRef: `authority-response:${options.response.response_id}@${responseDigest}`,
        closureProvenance: `request:${options.request.request_id}@${requestDigest};response:${options.response.response_id}@${responseDigest}`,
    };
}
export function proceduralAuthorityLedgerRowMarkdown(row) {
    return `| ${row.ambiguityId} | ${row.authoritySeq} | ${row.assessmentSeq} | ${row.action} | `
        + `${row.selectedCandidateRef} | ${row.authoritySubjectDigest} | ${row.authorityRef} | `
        + `${row.closureProvenance} |`;
}
export function exactTextBlob(bytes) {
    return {
        encoding: 'base64',
        media_type: 'text/plain; charset=utf-8',
        bytes_base64: bytes.toString('base64'),
        sha256: sha256Digest(bytes),
    };
}
export function validateTextBlob(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)
        || !exactObjectKeys(value, ['encoding', 'media_type', 'bytes_base64', 'sha256'])) {
        throw new Error('human text blob fields are malformed');
    }
    const blob = value;
    if (blob.encoding !== 'base64' || blob.media_type !== 'text/plain; charset=utf-8'
        || typeof blob.bytes_base64 !== 'string' || typeof blob.sha256 !== 'string'
        || !/^sha256:[a-f0-9]{64}$/u.test(blob.sha256)) {
        throw new Error('human text blob contract is invalid');
    }
    const bytes = Buffer.from(blob.bytes_base64, 'base64');
    const text = bytes.toString('utf8');
    if (bytes.toString('base64') !== blob.bytes_base64
        || sha256Digest(bytes) !== blob.sha256
        || text.includes('\uFFFD')
        || !Buffer.from(text, 'utf8').equals(bytes)) {
        throw new Error('human text blob bytes are not exact canonical UTF-8');
    }
    return bytes;
}
export function closurePhasesFromText(text) {
    const phases = [];
    for (const line of text.split(/\r?\n/u)) {
        const match = line.match(/^\s*closure_phase:\s*(\S+)\s*$/u);
        if (match && CLOSURE_PHASES.includes(match[1])) {
            phases.push(match[1]);
        }
    }
    return phases;
}
export function closurePhases(document) {
    return document ? closurePhasesFromText(document.text) : [];
}
export function highestClosurePhase(document) {
    return closurePhases(document).at(-1) || null;
}
export function nextClosurePhase(phases) {
    if (phases.some((phase, index) => phase !== CLOSURE_PHASES[index])) {
        throw new Error('retained closure phases are duplicated, skipped, or out of order');
    }
    const next = CLOSURE_PHASES[phases.length];
    if (!next)
        throw new Error('S4 composite barrier is already complete');
    return next;
}
function parseRequirementRef(requirementRef) {
    if (!requirementRef.startsWith('core:') || requirementRef !== requirementRef.trim()
        || requirementRef.includes('\\') || requirementRef.includes('%')
        || requirementRef.includes('://') || requirementRef.includes('\0')) {
        throw new Error('requirement_ref must use exact core:<path>#<selector> grammar');
    }
    const parts = requirementRef.slice('core:'.length).split('#');
    if (parts.length !== 2 || !parts[0] || !parts[1]) {
        throw new Error('requirement_ref must contain exactly one nonempty selector');
    }
    const [path, selector] = parts;
    if (path.startsWith('/') || path.startsWith('./') || path.includes('//')
        || path.split('/').some((part) => !part || part === '.' || part === '..')
        || selector !== selector.trim() || /^(?:L|line:|lines:)\d/iu.test(selector)) {
        throw new Error('requirement_ref path or selector is noncanonical');
    }
    return { path, selector };
}
function headingMatches(bytes, selector) {
    const lines = bytes.toString('utf8').split(/(?<=\n)/u);
    const matches = [];
    let offset = 0;
    let fence = null;
    for (let index = 0; index < lines.length; index += 1) {
        const line = lines[index];
        const noEnding = line.replace(/\r?\n$/u, '');
        const fenceMatch = noEnding.match(/^\s*(`{3,}|~{3,})/u);
        if (fenceMatch) {
            const marker = fenceMatch[1][0];
            if (!fence)
                fence = { marker, length: fenceMatch[1].length };
            else if (fence.marker === marker && fenceMatch[1].length >= fence.length)
                fence = null;
            offset += Buffer.byteLength(line, 'utf8');
            continue;
        }
        const heading = fence ? null : noEnding.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/u);
        if (heading && heading[2] === selector) {
            const level = heading[1].length;
            let end = bytes.byteLength;
            let innerOffset = offset + Buffer.byteLength(line, 'utf8');
            let innerFence = null;
            for (let next = index + 1; next < lines.length; next += 1) {
                const candidate = lines[next].replace(/\r?\n$/u, '');
                const candidateFence = candidate.match(/^\s*(`{3,}|~{3,})/u);
                if (candidateFence) {
                    const marker = candidateFence[1][0];
                    if (!innerFence)
                        innerFence = { marker, length: candidateFence[1].length };
                    else if (innerFence.marker === marker && candidateFence[1].length >= innerFence.length)
                        innerFence = null;
                }
                else if (!innerFence) {
                    const nextHeading = candidate.match(/^(#{1,6})\s+/u);
                    if (nextHeading && nextHeading[1].length <= level) {
                        end = innerOffset;
                        break;
                    }
                }
                innerOffset += Buffer.byteLength(lines[next], 'utf8');
            }
            matches.push(bytes.subarray(offset, end));
        }
        offset += Buffer.byteLength(line, 'utf8');
    }
    return matches;
}
function tokenMatches(bytes, selector) {
    if (!/^[A-Za-z][A-Za-z0-9]*(?:[-_.][A-Za-z0-9]+)+$/u.test(selector))
        return [];
    const text = bytes.toString('utf8');
    const matches = [];
    let offset = 0;
    while (offset <= text.length - selector.length) {
        const index = text.indexOf(selector, offset);
        if (index < 0)
            break;
        const before = index > 0 ? text[index - 1] : '';
        const beforeBefore = index > 1 ? text[index - 2] : '';
        const afterIndex = index + selector.length;
        const after = afterIndex < text.length ? text[afterIndex] : '';
        const afterAfter = afterIndex + 1 < text.length ? text[afterIndex + 1] : '';
        const joinedOnLeft = /[A-Za-z0-9_-]/u.test(before)
            || (before === '.' && /[A-Za-z0-9]/u.test(beforeBefore));
        const joinedOnRight = /[A-Za-z0-9_-]/u.test(after)
            || (after === '.' && /[A-Za-z0-9]/u.test(afterAfter));
        if (!joinedOnLeft && !joinedOnRight) {
            matches.push(Buffer.from(selector, 'utf8'));
        }
        offset = index + 1;
    }
    return matches;
}
const STRUCTURED_VERIFIER_FIELDS = [
    'target',
    'lens',
    'stage',
    'shown',
    'withheld',
    'verdict',
    'consequence',
];
export function parseStructuredVerifierRecord(bytes, path = 'verifier record') {
    const tables = findTables(parseTables(bytes.toString('utf8'), path), ['field', 'value']);
    if (tables.length !== 1) {
        throw new Error('verifier requires exactly one canonical field/value table');
    }
    const values = new Map();
    for (const row of tables[0].rows) {
        if (row.cells.length !== 2)
            continue;
        const field = normalizeHeader(row.cells[0]);
        if (!STRUCTURED_VERIFIER_FIELDS.includes(field))
            continue;
        const bucket = values.get(field) || [];
        bucket.push((row.cells[1] || '').trim());
        values.set(field, bucket);
    }
    for (const field of STRUCTURED_VERIFIER_FIELDS) {
        const retained = values.get(field) || [];
        if (retained.length !== 1 || retained[0] === '') {
            throw new Error(`verifier field ${field} must occur exactly once and be nonempty`);
        }
    }
    const verdict = values.get('verdict')[0];
    if (!['upheld', 'refuted', 'cannot-determine'].includes(verdict)) {
        throw new Error('verifier verdict is outside the closed vocabulary');
    }
    return {
        target: values.get('target')[0],
        lens: values.get('lens')[0],
        stage: values.get('stage')[0],
        shown: values.get('shown')[0],
        withheld: values.get('withheld')[0],
        verdict: verdict,
        consequence: values.get('consequence')[0],
    };
}
export function validateMaterialImpactAuthorityBasis(options) {
    let material;
    try {
        material = JSON.parse(options.material_subject_bytes.toString('utf8'));
    }
    catch {
        throw new Error('retained material-impact subject is not valid JSON');
    }
    const problems = materialImpactSubjectProblems(material);
    if (problems.length > 0
        || materialImpactSubjectJson(material) !== options.material_subject_bytes.toString('utf8')) {
        throw new Error(`retained material-impact subject is not exact canonical Core state: ${problems.join('; ')}`);
    }
    const subject = options.authority_subject;
    const digest = materialImpactSubjectDigest(material);
    const subjectRef = `material-impact-subject:${material.ambiguity_id}:A${String(material.assessment_seq)}:M${String(material.material_impact_seq)}@${digest}`;
    if (material.materiality_class !== 'C'
        || subject.material_impact_subject_ref !== subjectRef
        || subject.material_impact_seq !== material.material_impact_seq
        || material.t5_2_assessment_ref !== subject.t5_2_assessment_ref
        || material.t5_2_review_subject_digest !== subject.t5_2_review_subject_digest
        || material.t5_2_review_ref !== subject.t5_2_review_ref
        || material.c1_relation_basis_ref !== subject.c1_relation_basis_ref
        || JSON.stringify(material.operative_scope) !== JSON.stringify(subject.operative_scope)
        || JSON.stringify(material.source_locators) !== JSON.stringify(subject.source_locators)
        || JSON.stringify(material.reviewed_unaffected_ids)
            !== JSON.stringify(subject.reviewed_unaffected_ids)
        || material.unresolved_statement !== subject.unresolved_statement) {
        throw new Error('procedural authority subject disagrees with its retained Class C material-impact basis');
    }
    const reviewMatch = subject.material_impact_review_ref.match(/^material-impact-verdict:(VER-\d{4,})@(sha256:[a-f0-9]{64})$/u);
    if (!reviewMatch) {
        throw new Error('procedural authority subject has an invalid material-impact review ref');
    }
    const matches = options.verifier_files.filter((file) => basename(file.path) === `${reviewMatch[1]}.md`);
    if (matches.length !== 1 || sha256Digest(matches[0].bytes) !== reviewMatch[2]) {
        throw new Error('material-impact review ref does not resolve to one exact retained verifier');
    }
    const review = parseStructuredVerifierRecord(matches[0].bytes, matches[0].path);
    const target = `internal-ambiguity-material-impact-review-subject:${digest}`;
    if (review.target !== target || review.verdict !== 'upheld') {
        throw new Error('material-impact verifier target or verdict does not authorize a request');
    }
    return {
        material_subject: material,
        material_subject_digest: digest,
        material_subject_ref: subjectRef,
        material_review_id: reviewMatch[1],
        material_review_ref: subject.material_impact_review_ref,
        material_review: review,
    };
}
export function resolvePinnedCoreRequirement(authority, requirementRef) {
    if (authority.source_kind !== 'retained-immutable-bundle') {
        throw new Error('requirement_ref authority is not a retained immutable bundle');
    }
    if (authority.lock.bundle.digest !== authority.expected_bundle_digest
        || authority.lock.core.tree_digest !== authority.expected_core_digest) {
        throw new Error('run-pinned bundle/Core identity does not match retained lock authority');
    }
    if (authority.lock.source.manifest_projection_digest
        !== sha256Digest(canonicalJsonBytes(authority.lock.source.manifest_projection))) {
        throw new Error('retained Core manifest projection digest is invalid');
    }
    const { path, selector } = parseRequirementRef(requirementRef);
    const corePaths = authority.lock.source.manifest_projection.files.core;
    if (!corePaths.includes(path))
        throw new Error('requirement_ref path is not Core-classified');
    const records = authority.files
        ? [...authority.files.values()].filter((record) => record.path === path)
        : authority.lock.files.filter((record) => record.path === path);
    if (records.length !== 1 || records[0].classification !== 'core') {
        throw new Error('requirement_ref path does not resolve uniquely in the pinned Core inventory');
    }
    const bytes = authority.file_bytes?.get(path)
        || (existsSync(join(authority.root, path)) ? readFileSync(join(authority.root, path)) : null);
    if (!bytes || sha256Digest(bytes) !== records[0].digest) {
        throw new Error('retained Core bytes are absent or disagree with the pinned inventory');
    }
    const headings = headingMatches(bytes, selector);
    const tokens = tokenMatches(bytes, selector);
    if (headings.length + tokens.length !== 1) {
        throw new Error('requirement_ref selector does not resolve to one exact heading or durable token');
    }
    const selectorKind = headings.length === 1 ? 'heading' : 'token';
    const selected = headings[0] || tokens[0];
    return {
        requirement_ref: requirementRef,
        path,
        selector,
        selector_kind: selectorKind,
        bytes: selected,
        digest: sha256Digest(selected),
    };
}
export function restrictionOverlay(scope) {
    return scope.impact_rows.map((row) => ({
        affected_id: row.affected_id,
        operation_kind: row.operation_kind,
        requirement_ref: row.requirement_ref,
    }));
}
function restrictionTupleKey(value) {
    return `${value.affected_id}\0${value.operation_kind}\0${value.requirement_ref}`;
}
export function retainedRestrictionOverlays(model) {
    const retained = new Map();
    const ambiguity = parseInternalAmbiguities(model);
    for (const row of ambiguity.t5_3Rows) {
        if (row.values.action !== 'restrict-downstream-use')
            continue;
        const provenance = row.values.closureProvenance.match(/^request:(GATE-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*)@(sha256:[a-f0-9]{64});response:(RESP-S4-AMB-\d{4,}-A[1-9]\d*-Q[1-9]\d*)@(sha256:[a-f0-9]{64})$/u);
        if (!provenance) {
            throw new Error(`${row.values.ambiguityId} retained restriction has invalid closure provenance`);
        }
        const requestPath = join(model.runDir, 'control', 'gates', `${provenance[1]}-request.json`);
        const responsePath = join(model.runDir, 'control', 'gates', `${provenance[1]}-response.json`);
        if (!existsSync(requestPath) || !existsSync(responsePath)) {
            throw new Error(`${row.values.ambiguityId} retained restriction lacks exact request/response bytes`);
        }
        const requestBytes = readFileSync(requestPath);
        const responseBytes = readFileSync(responsePath);
        if (sha256Digest(requestBytes) !== provenance[2]
            || sha256Digest(responseBytes) !== provenance[4]) {
            throw new Error(`${row.values.ambiguityId} retained restriction request/response digest is wrong`);
        }
        let request;
        let response;
        try {
            request = JSON.parse(requestBytes.toString('utf8'));
            response = JSON.parse(responseBytes.toString('utf8'));
        }
        catch {
            throw new Error(`${row.values.ambiguityId} retained restriction request/response is not JSON`);
        }
        if (response.response_id !== provenance[3]
            || response.selected_action !== 'restrict-downstream-use') {
            throw new Error(`${row.values.ambiguityId} retained restriction response does not select restriction`);
        }
        const projected = buildProceduralAuthorityLedgerRow({
            request,
            request_bytes: requestBytes,
            response,
            response_bytes: responseBytes,
            authority_seq: Number(row.values.authoritySeq),
        });
        if (JSON.stringify(projected) !== JSON.stringify(row.values)) {
            throw new Error(`${row.values.ambiguityId} retained restriction is not the exact Core T5.3 projection`);
        }
        for (const restriction of restrictionOverlay(request.authority_subject.operative_scope)) {
            retained.set(restrictionTupleKey(restriction), restriction);
        }
    }
    return [...retained.values()].sort((left, right) => (Buffer.from(restrictionTupleKey(left), 'utf8')
        .compare(Buffer.from(restrictionTupleKey(right), 'utf8'))));
}
export function assertDownstreamOperationsAllowed(restrictions, operations) {
    const prohibited = new Set(restrictions.map(restrictionTupleKey));
    const seen = new Set();
    for (const operation of operations) {
        if (!/^(?:PKT|CC|REL)-\d{4,}$/u.test(operation.affected_id)
            || !OPERATION_KINDS.includes(operation.operation_kind)) {
            throw new Error('downstream operation tuple is malformed');
        }
        parseRequirementRef(operation.requirement_ref);
        const key = restrictionTupleKey(operation);
        if (seen.has(key))
            throw new Error('downstream operation tuple is duplicated');
        seen.add(key);
        if (prohibited.has(key)) {
            throw new Error(`downstream operation is prohibited by retained procedural restriction: `
                + `${operation.affected_id} + ${operation.operation_kind} + ${operation.requirement_ref}`);
        }
    }
}
export function tableLooksLike(table, first) {
    return normalizeHeader(table.header[0]) === normalizeHeader(first);
}
