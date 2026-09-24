import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, join, relative } from 'node:path';
import { TextDecoder } from 'node:util';
import { mdLineSpan, reachedState, runLogEvents, sourceFilePath } from './check-helpers.js';
import { parseTables, envelopeSection } from './markdown.js';
import { parseStrictJson, contractExemplarToJsonSchema, validateWorkerReturnContract, validateJudgmentRationale } from './worker-return-contract.js';
import { forwardExecutionIdentityProblems, hasRunCapability } from './run-model.js';
import { materialHash, materialTableMarkdown, readMaterialFile, readRepresentationContext, representationUseSubjectJson, representationReviewView, validateMaterialUseInput, validateRepresentationUse, representationUseNeedsReview, materialFeatureAvailable, assertMaterialReviewUpheld, } from './source-representation.js';
import { RELATION_FAMILIES, RELATION_TYPES, RELATION_FAMILY_TYPES, RELATION_RECORD_STATES, parseRelations } from './relations.js';
import { relationProposalProblems } from './checks-k2-relations.js';
import { runK2Lineage } from './checks-k2-lineage.js';
import { ResultCollector } from './results.js';
import { framedExactEvidenceHash } from './checks-k2.js';
import { parseLineage, LINEAGE_TYPES, lineageCurrentClaimIds, lineageCurrentPacketIds } from './lineage.js';
import { parseStructuredVerifierRecord, ambiguityReviewSubjectJson, searchBasisDigest, SEARCH_SCOPE_KINDS, CANDIDATE_STATES, RESOLUTION_STATES, CARRY_STATES, legalResolutionCarryState, parseCandidateRefs, } from './internal-ambiguity.js';
import { bundleLockBytes, canonicalJsonBytes, resealBundleLock } from './bundle-format.js';
export const SEMANTIC_PATH = 'ledgers/semantic-review.md';
export const SEMANTIC_FORMAT = 'aleph-semantic-review/v1';
export const SEMANTIC_SUBJECT_FORMAT = 'aleph-semantic-subject/v1';
export const SEMANTIC_RESULT_FORMAT = 'aleph-semantic-result/v1';
export const SEMANTIC_ASSIGNMENT_FORMAT = 'aleph-semantic-assignment/v1';
export const SEMANTIC_STAGE_SEAL_FORMAT = 'aleph-semantic-stage-seal/v1';
export const SEMANTIC_CONTRACT_FORMAT = 'aleph-semantic-output-contract/v1';
export const SEMANTIC_TASK = 'Challenge only the attached sealed semantic subject under L2S.';
export const SEMANTIC_LENS = 'L2S — atomicity, context, and semantic preservation (S2/S3)';
export const SEMANTIC_FACETS = {
    claim_roles: ['result-observation', 'method-procedure', 'interpretation-inference', 'background-context', 'definition', 'recommendation', 'attribution-report', 'limitation-uncertainty'],
    scope: ['population', 'temporal', 'geographic', 'experiment-task', 'document-universe', 'quantified', 'exclusion-restriction'],
    conditions: ['condition', 'precondition'],
    qualifiers: ['degree', 'frequency', 'approximation', 'limitation', 'comparative', 'exception', 'confidence-uncertainty'],
    modality: ['observed-descriptive', 'possible', 'capable', 'normative-should', 'obligatory-must', 'intended-designed', 'predicted-expected', 'hypothetical', 'counterfactual', 'recommended'],
    attribution: ['source-author', 'quoted-entity', 'cited-external-in-corpus', 'reported-belief-opinion', 'system-model-interpretation'],
    comparator: ['comparison-basis'],
    metric: ['measured-quantity'],
};
export const ATOMICITIES = ['single-assertion', 'multiple-separable', 'inseparable-context', 'CANNOT_DETERMINE', 'no-claim'];
export const CONTEXT_KINDS = ['necessary-local', 'attribution', 'definition-terms', 'condition-scope', 'representation-layout', 'discourse'];
export const CONTEXT_USES = ['required-for-interpretation', 'inspection-only', 'non-evidentiary'];
export const COUPLING_KINDS = ['result-interpretation', 'attribution-content', 'comparison-comparator', 'metric-result', 'condition-claim', 'required-context'];
export const FINDING_CODES = ['atomicity-indeterminate', 'context-insufficient', 'scope-indeterminate', 'condition-indeterminate', 'qualifier-indeterminate', 'modality-indeterminate', 'attribution-indeterminate', 'role-indeterminate', 'referent-unresolved', 'comparator-indeterminate', 'metric-indeterminate', 'material-unavailable', 'relation-deferred', 'interpretation-unsupported'];
export const SEMANTIC_ISSUES = ['none', 'compound-assertion', 'lost-context', 'spurious-context', 'altered-scope', 'lost-condition', 'altered-qualifier', 'altered-modality', 'altered-attribution', 'conflated-role', 'result-interpretation-collapse', 'lost-comparator', 'lost-metric', 'unsupported-interpretation', 'unresolved-referent', 'missing-material', 'illegal-relation-use', 'insufficient-context'];
export const SEMANTIC_EXECUTIONS = ['native-dispatch', 'fixture-simulated', 'static-record', 'manual-separate-pass'];
export const SEMANTIC_OUTPUT_KINDS = ['packet-candidate', 'claim-candidate', 'no-claim-candidate', 'material-candidate'];
export const SEMANTIC_HEADERS = {
    subjects: ['semantic_id', 'owner_stage', 'subject_kind', 'subject_path', 'subject_digest', 'predecessor_semantic_id', 'producer_receipt_ref'],
    assignments: ['review_id', 'semantic_id', 'assignment_path', 'assignment_digest'],
    results: ['review_id', 'semantic_id', 'result_path', 'result_digest', 'execution_kind', 'execution_evidence_ref'],
    resolutions: ['resolution_id', 'semantic_id', 'outcome', 'review_ids', 'canonical_refs', 'origin_unit_refs', 'followup_semantic_ids'],
};
export const SEMANTIC_SUMMARY_HEADERS = ['semantic_id', 'finding_id', 'source_ids', 'state', 'subject_digest'];
function semanticRelationRow(proposal) {
    const s = proposal.subject;
    return { file: 'semantic relation proposal', line: 0, raw: '', cells: [], values: {
            relationId: '', ownerStage: s.owner_stage, family: s.family, type: s.type, sourceKind: s.source_kind,
            sourceId: s.source_id, targetKind: s.target_kind, targetId: s.target_id, targetSourceId: s.target_source_id,
            targetLocator: s.target_locator, targetSpanHash: s.target_span_hash, recordState: s.record_state,
            nullReason: s.null_reason, basisPacketIds: s.basis_packet_ids.join(', '), proposedBy: s.proposed_by,
            reviewSubjectDigest: proposal.review_subject_digest, reviewedBy: '',
        } };
}
export class SemanticError extends Error {
    constructor(token, path, reason) { super(`${token} ${path}: ${reason}`); }
}
export function requireSemantic(condition, token, path, reason) {
    if (!condition)
        throw new SemanticError(token, path, reason);
}
function obj(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function keys(value, expected, path) {
    requireSemantic(obj(value) && JSON.stringify(Object.keys(value)) === JSON.stringify(expected), 'SEM_FORMAT', path, 'exact listed keys and order required');
}
function text(value, path) {
    requireSemantic(typeof value === 'string' && value.trim().length > 0, 'SEM_FORMAT', path, 'nonempty text required');
}
function oneOf(value, choices, path) {
    requireSemantic(choices.includes(value), 'SEM_ENUM', path, 'invalid declared enum');
}
function array(value, path) { requireSemantic(Array.isArray(value), 'SEM_FORMAT', path, 'array required'); }
function hash(value, path) { requireSemantic(typeof value === 'string' && /^sha256:[0-9a-f]{64}$/u.test(value), 'SEM_FORMAT', path, 'exact SHA-256 required'); }
function ordinal(value, positive = false) { return typeof value === 'number' && Number.isSafeInteger(value) && !Object.is(value, -0) && value >= (positive ? 1 : 0); }
export function semanticId(value, prefix) { return typeof value === 'string' && new RegExp(`^${prefix}-(?=\\d*[1-9])\\d{4,}$`, 'u').test(value); }
function existingId(value, prefix) { return typeof value === 'string' && new RegExp(`^${prefix}-[0-9]+$`, 'u').test(value); }
function subset(value, basis, path, nonempty = false) {
    array(value, path);
    requireSemantic((!nonempty || value.length > 0) && value.every((id, i) => basis.includes(id)
        && (i === 0 || basis.indexOf(value[i - 1]) < basis.indexOf(id))), 'SEM_REFERENCE', path, 'ordered unique references required');
}
function uniqueStrings(value, path, nonempty = false) {
    array(value, path);
    requireSemantic((!nonempty || value.length > 0) && value.every((v) => typeof v === 'string' && v.length > 0)
        && new Set(value).size === value.length, 'SEM_REFERENCE', path, 'unique nonempty strings required');
}
export function semanticJson(value) {
    const raw = JSON.stringify(value);
    try {
        parseStrictJson(raw, true);
    }
    catch (error) {
        throw new SemanticError('SEM_FORMAT', 'JSON', String(error));
    }
    return raw;
}
export function parseSemanticJson(bytes) {
    try {
        const value = parseStrictJson(bytes, true);
        requireSemantic(Buffer.from(semanticJson(value)).equals(Buffer.from(bytes)), 'SEM_FORMAT', 'JSON', 'canonical compact UTF-8 bytes required');
        return value;
    }
    catch (error) {
        if (error instanceof SemanticError)
            throw error;
        throw new SemanticError('SEM_FORMAT', 'JSON', String(error));
    }
}
export function semanticSubjectPath(id) { return `verification/harness/semantic-subjects/${id}.json`; }
export function semanticResultPath(id) { return `verification/harness/semantic-results/${id}.json`; }
export function semanticAssignmentPath(id) { return `verification/harness/semantic-assignments/${id}.json`; }
export function semanticCoverage(semantics, kind) {
    return ['/semantics/atomicity', '/semantics/contexts', '/semantics/couplings', '/semantics/relation_proposals', '/semantics/unresolved_findings', '/material_use',
        ...semantics.units.flatMap((_unit, i) => ['proposition', ...Object.keys(SEMANTIC_FACETS)].map((field) => `/semantics/units/${i}/${field}`)),
        ...(kind === 'no-claim' ? ['/output_binding/basis'] : [])];
}
const ANCHOR_INPUT_KEYS = ['anchor_id', 'source_id', 'locator', 'start_byte', 'end_byte', 'exact_bytes_base64'];
const ANCHOR_KEYS = ['anchor_id', 'source_id', 'source_hash', 'locator', 'span_hash', 'start_byte', 'end_byte', 'selection_hash', 'exact_bytes_base64', 'packet_ids'];
function anchorShape(value, i, sealed) {
    keys(value, sealed ? ANCHOR_KEYS : ANCHOR_INPUT_KEYS, `anchors/${i}`);
    requireSemantic(value.anchor_id === `A${i + 1}` && existingId(value.source_id, 'SRC'), 'SEM_REFERENCE', `anchors/${i}`, 'contiguous anchor or existing source ID required');
    requireSemantic(typeof value.locator === 'string' && /^L[1-9]\d*-L[1-9]\d*$/u.test(value.locator), 'SEM_EVIDENCE', `anchors/${i}/locator`, 'existing md-lines locator required');
    requireSemantic(ordinal(value.start_byte) && ordinal(value.end_byte) && value.end_byte > value.start_byte, 'SEM_ENUM', `anchors/${i}`, 'nonempty half-open UTF-8 interval required');
    text(value.exact_bytes_base64, 'anchor bytes');
    const bytes = Buffer.from(value.exact_bytes_base64, 'base64');
    requireSemantic(bytes.toString('base64') === value.exact_bytes_base64 && bytes.length === value.end_byte - value.start_byte, 'SEM_EVIDENCE', `anchors/${i}`, 'noncanonical or length-mismatched base64');
    try {
        new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    }
    catch {
        throw new SemanticError('SEM_EVIDENCE', `anchors/${i}`, 'split code point or invalid UTF-8');
    }
    if (sealed) {
        for (const field of ['source_hash', 'span_hash', 'selection_hash'])
            hash(value[field], `anchors/${i}/${field}`);
        requireSemantic(value.selection_hash === materialHash(bytes), 'SEM_EVIDENCE', `anchors/${i}`, 'selection hash differs');
        uniqueStrings(value.packet_ids, `anchors/${i}/packet_ids`);
    }
}
function sourceSpan(model, sourceId, locator) {
    const row = model.corpus.sources.find((s) => s.values.sourceId === sourceId)?.values;
    requireSemantic(row && row.scheme === 'md-lines', 'SEM_REFERENCE', sourceId, 'unknown frozen source or unsupported locator scheme');
    const path = sourceFilePath(model.runDir, row.locus), match = /^L([1-9]\d*)-L([1-9]\d*)$/u.exec(locator);
    requireSemantic(path && match, 'SEM_EVIDENCE', locator, 'unreopenable source locus');
    const source = readMaterialFile(model.runDir, relative(model.runDir, path));
    requireSemantic(materialHash(source) === row.contentHash, 'SEM_EVIDENCE', sourceId, 'frozen source hash differs');
    const span = mdLineSpan(path, Number(match[1]), Number(match[2]));
    requireSemantic(span?.bytes && span.startByte !== null && span.endByte !== null, 'SEM_EVIDENCE', locator, 'source span absent');
    return { bytes: span.bytes, source, start: span.startByte, end: span.endByte, path: relative(model.runDir, path) };
}
export function completeSemanticAnchors(model, inputs, packetIds) {
    return inputs.map((input, i) => {
        anchorShape(input, i, false);
        const span = sourceSpan(model, input.source_id, input.locator);
        requireSemantic(input.start_byte >= span.start && input.end_byte <= span.end, 'SEM_EVIDENCE', input.anchor_id, 'selection escapes locus');
        const selection = span.source.subarray(input.start_byte, input.end_byte);
        requireSemantic(selection.toString('base64') === input.exact_bytes_base64, 'SEM_EVIDENCE', input.anchor_id, 'selection differs from frozen bytes');
        const covered = packetIds.filter((id) => model.exactEvidence.fragments.some((f) => {
            if (f.values.packetId !== id || f.values.sourceId !== input.source_id)
                return false;
            const fragment = sourceSpan(model, input.source_id, f.values.locator);
            requireSemantic(materialHash(fragment.bytes) === f.values.fragmentHash && fragment.bytes.toString('base64') === f.values.exactBytesBase64, 'SEM_EVIDENCE', id, 'packet fragment changed');
            return fragment.start <= input.start_byte && fragment.end >= input.end_byte;
        }));
        return { anchor_id: input.anchor_id, source_id: input.source_id, source_hash: materialHash(span.source), locator: input.locator,
            span_hash: materialHash(span.bytes), start_byte: input.start_byte, end_byte: input.end_byte,
            selection_hash: materialHash(selection), exact_bytes_base64: selection.toString('base64'), packet_ids: covered };
    });
}
function findingShape(value, i, paths, anchors, requirements, model, legalSources) {
    keys(value, ['finding_id', 'field_path', 'code', 'anchor_ids', 'material_requirement_indexes', 'unknown_dimension', 'missing', 'requested_context'], `findings/${i}`);
    requireSemantic(value.finding_id === `F${i + 1}` && paths.includes(String(value.field_path)), 'SEM_REFERENCE', `findings/${i}`, 'contiguous ID and finite coverage path required');
    oneOf(value.code, FINDING_CODES, `findings/${i}/code`);
    subset(value.anchor_ids, anchors.map((a) => a.anchor_id), `findings/${i}/anchors`);
    subset(value.material_requirement_indexes, typeof requirements === 'number' ? Array.from({ length: requirements }, (_, n) => n) : requirements, `findings/${i}/requirements`);
    requireSemantic(value.anchor_ids.length + value.material_requirement_indexes.length > 0, 'SEM_REFERENCE', `findings/${i}`, 'source or material basis required');
    oneOf(value.unknown_dimension, ['none', ...SEMANTIC_FACETS.scope, 'comparison-dimension', 'measurement-unit'], `findings/${i}/dimension`);
    text(value.missing, `findings/${i}/missing`);
    array(value.requested_context, 'requested_context');
    const seen = new Set();
    for (const request of value.requested_context) {
        keys(request, ['source_id', 'locator', 'purpose'], 'requested_context');
        requireSemantic(existingId(request.source_id, 'SRC') && typeof request.locator === 'string' && /^L[1-9]\d*-L[1-9]\d*$/u.test(request.locator), 'SEM_REFERENCE', 'requested_context', 'exact frozen source locator required');
        oneOf(request.purpose, ['local-context', 'same-source-referent-search', 'material-inspection'], 'requested_context/purpose');
        requireSemantic(!seen.has(semanticJson(request)), 'SEM_REFERENCE', 'requested_context', 'duplicate request');
        seen.add(semanticJson(request));
        if (model) {
            requireSemantic(legalSources?.includes(request.source_id), 'SEM_REFERENCE', 'requested_context', 'source outside role scope');
            sourceSpan(model, request.source_id, request.locator);
        }
    }
}
export function validateSemantics(value, anchors, materialUse, kind, model, legalSources) {
    keys(value, ['atomicity', 'units', 'contexts', 'couplings', 'relation_proposals', 'unresolved_findings'], 'semantics');
    oneOf(value.atomicity, ATOMICITIES, 'atomicity');
    for (const field of ['units', 'contexts', 'couplings', 'relation_proposals', 'unresolved_findings'])
        array(value[field], field);
    const units = value.units, contexts = value.contexts, couplings = value.couplings;
    requireSemantic((!['single-assertion', 'inseparable-context'].includes(value.atomicity) || units.length === 1)
        && (value.atomicity !== 'multiple-separable' || units.length >= 2)
        && (value.atomicity !== 'no-claim' || units.length + contexts.length + couplings.length === 0), 'SEM_ENUM', 'atomicity', 'declared cardinality differs');
    const basis = anchors.map((a) => a.anchor_id), unitIds = units.map((_u, i) => `U${i + 1}`);
    const requirements = materialUse?.requirements.length || 0;
    const indexes = Array.from({ length: requirements }, (_, i) => i);
    const paths = semanticCoverage(value, kind);
    const findings = value.unresolved_findings;
    findings.forEach((finding, i) => findingShape(finding, i, paths, anchors, requirements, model, legalSources));
    const unknown = (path) => requireSemantic(findings.some((f) => f.field_path === path), 'SEM_REFERENCE', path, 'CANNOT_DETERMINE requires matching finding');
    if (value.atomicity === 'CANNOT_DETERMINE')
        unknown('/semantics/atomicity');
    units.forEach((unit, i) => {
        keys(unit, ['unit_id', 'proposition', 'proposition_anchor_ids', ...Object.keys(SEMANTIC_FACETS)], `units/${i}`);
        requireSemantic(unit.unit_id === unitIds[i], 'SEM_REFERENCE', `units/${i}`, 'contiguous unit ID required');
        text(unit.proposition, `units/${i}/proposition`);
        subset(unit.proposition_anchor_ids, basis, `units/${i}/proposition_anchor_ids`, true);
        for (const [name, kinds] of Object.entries(SEMANTIC_FACETS)) {
            const path = `/semantics/units/${i}/${name}`, facet = unit[name];
            keys(facet, ['state', 'items', 'basis_anchor_ids'], path);
            oneOf(facet.state, ['present', 'not-expressed', 'CANNOT_DETERMINE'], path);
            array(facet.items, path);
            subset(facet.basis_anchor_ids, basis, path, true);
            requireSemantic(facet.state === 'present' ? facet.items.length > 0 : facet.items.length === 0, 'SEM_ENUM', path, 'state/items mismatch');
            if (facet.state === 'CANNOT_DETERMINE')
                unknown(path);
            requireSemantic(name !== 'claim_roles' || facet.state !== 'not-expressed', 'SEM_ENUM', path, 'a unit needs proposed roles or indeterminacy');
            let previous = null;
            for (const item of facet.items) {
                const extension = name === 'attribution' ? ['attributed_to'] : name === 'comparator'
                    ? ['subject_anchor_ids', 'baseline_anchor_ids', 'dimension_anchor_ids'] : name === 'metric'
                    ? ['quantity_anchor_ids', 'value_anchor_ids', 'unit_anchor_ids'] : [];
                keys(item, ['kind', 'source_text', ...extension, 'anchor_ids'], path);
                oneOf(item.kind, kinds, path);
                subset(item.anchor_ids, facet.basis_anchor_ids, path, true);
                const first = anchors.find((a) => a.anchor_id === item.anchor_ids[0]);
                requireSemantic(item.source_text === Buffer.from(first.exact_bytes_base64, 'base64').toString('utf8'), 'SEM_EVIDENCE', path, 'source_text must equal first named anchor bytes');
                const order = [basis.indexOf(first.anchor_id), item.kind];
                requireSemantic(!previous || order[0] > previous[0] || (order[0] === previous[0] && order[1] > previous[1]), 'SEM_REFERENCE', path, 'items must be unique in anchor/kind order');
                previous = order;
                if (name === 'attribution') {
                    text(item.attributed_to, path);
                    requireSemantic(item.kind !== 'system-model-interpretation' || item.attributed_to === 'producer-model', 'SEM_ENUM', path, 'model interpretation attribution must be producer-model');
                }
                else
                    extension.forEach((field, n) => subset(item[field], item.anchor_ids, `${path}/${field}`, n < 2));
            }
        }
    });
    contexts.forEach((context, i) => {
        keys(context, ['context_id', 'kind', 'applies_to_unit_ids', 'anchor_ids', 'material_requirement_indexes', 'use'], `contexts/${i}`);
        requireSemantic(context.context_id === `C${i + 1}`, 'SEM_REFERENCE', 'context_id', 'contiguous context ID required');
        oneOf(context.kind, CONTEXT_KINDS, 'context kind');
        oneOf(context.use, CONTEXT_USES, 'context use');
        subset(context.applies_to_unit_ids, unitIds, 'context units', true);
        subset(context.anchor_ids, basis, 'context anchors');
        subset(context.material_requirement_indexes, indexes, 'context requirements');
        requireSemantic(context.anchor_ids.length + context.material_requirement_indexes.length > 0, 'SEM_REFERENCE', 'context', 'nonempty basis required');
        requireSemantic(context.kind === 'representation-layout' || context.material_requirement_indexes.length === 0, 'SEM_ENUM', 'context', 'only representation-layout uses material indexes');
    });
    const tuples = new Set();
    let previousCouplingAnchor = -1;
    couplings.forEach((coupling) => {
        keys(coupling, ['kind', 'unit_ids', 'anchor_ids', 'treatment'], 'coupling');
        oneOf(coupling.kind, COUPLING_KINDS, 'coupling kind');
        oneOf(coupling.treatment, ['keep-distinguishable', 'keep-together', 'CANNOT_DETERMINE'], 'coupling treatment');
        subset(coupling.unit_ids, unitIds, 'coupling units', true);
        subset(coupling.anchor_ids, basis, 'coupling anchors', true);
        const firstAnchor = basis.indexOf(coupling.anchor_ids[0]);
        requireSemantic(firstAnchor >= previousCouplingAnchor, 'SEM_REFERENCE', 'coupling', 'source anchor order required');
        previousCouplingAnchor = firstAnchor;
        requireSemantic(coupling.treatment !== 'keep-distinguishable' || coupling.unit_ids.length >= 2, 'SEM_ENUM', 'coupling', 'distinguishable needs two units');
        requireSemantic(coupling.treatment !== 'keep-together' || coupling.unit_ids.length === 1, 'SEM_ENUM', 'coupling', 'together needs one unit');
        if (coupling.treatment === 'CANNOT_DETERMINE')
            unknown('/semantics/couplings');
        requireSemantic(!tuples.has(semanticJson(coupling)), 'SEM_ENUM', 'coupling', 'duplicate tuple');
        tuples.add(semanticJson(coupling));
    });
    for (const proposal of value.relation_proposals) {
        keys(proposal, ['subject', 'review_subject_digest', 'material_use'], 'relation proposal');
        keys(proposal.subject, ['format', 'owner_stage', 'family', 'type', 'source_kind', 'source_id', 'target_kind', 'target_id', 'target_source_id', 'target_locator', 'target_span_hash', 'record_state', 'null_reason', 'basis_packet_ids', 'proposed_by'], 'relation subject');
        const subject = proposal.subject;
        const indeterminate = subject.record_state === 'indeterminate';
        requireSemantic(subject.format === 'aleph-relation-review-subject/v1' && RELATION_RECORD_STATES.includes(subject.record_state)
            && (indeterminate && subject.family === 'none' && subject.type === 'none'
                || RELATION_FAMILIES.includes(subject.family) && (indeterminate && subject.type === 'none'
                    || RELATION_FAMILY_TYPES[subject.family].includes(subject.type))), 'SEM_REFERENCE', 'relation proposal', 'existing Slice 4 taxonomy required');
        requireSemantic(proposal.review_subject_digest === materialHash(semanticJson(subject)), 'SEM_SUBJECT', 'relation proposal', 'exact Slice 4 subject digest required');
        validateMaterialUseInput(proposal.material_use);
    }
    for (const finding of findings.filter((f) => f.code === 'relation-deferred')) {
        requireSemantic(finding.field_path === '/semantics/relation_proposals'
            && value.relation_proposals.some((p) => ['S2', 'S3'].includes(p.subject.owner_stage)
                && p.subject.record_state === 'unresolved-target' && p.subject.target_kind === 'null'), 'SEM_REFERENCE', finding.finding_id, 'relation-deferred requires an unavailable-target local proposal');
    }
}
export function validateSemanticResult(value, subject) {
    keys(value, ['format', 'subject_digest', 'verdict', 'field_reviews', 'unresolved_findings', 'attacks_tried', 'missing_for_determination', 'rationale', 'candidate_evidence'], 'result');
    requireSemantic(value.format === SEMANTIC_RESULT_FORMAT, 'SEM_FORMAT', 'result', 'wrong format');
    hash(value.subject_digest, 'result/subject_digest');
    oneOf(value.verdict, ['upheld', 'refuted', 'cannot-determine'], 'result/verdict');
    array(value.field_reviews, 'field_reviews');
    array(value.unresolved_findings, 'unresolved_findings');
    array(value.attacks_tried, 'attacks_tried');
    array(value.candidate_evidence, 'candidate_evidence');
    requireSemantic(value.candidate_evidence.length === 0, 'SEM_FORMAT', 'candidate_evidence', 'L2S returns exactly []');
    requireSemantic(value.attacks_tried.length > 0 && value.attacks_tried.every((s) => typeof s === 'string' && s.trim()), 'SEM_REVIEW', 'attacks_tried', 'nonempty attempted attacks required');
    text(value.rationale, 'rationale');
    const rationaleErrors = [];
    validateJudgmentRationale(value.rationale, 'rationale', rationaleErrors);
    requireSemantic(rationaleErrors.length === 0, 'SEM_REVIEW', 'rationale', rationaleErrors.join('; '));
    requireSemantic(value.verdict === 'cannot-determine' ? typeof value.missing_for_determination === 'string' && value.missing_for_determination.trim()
        : value.missing_for_determination === null, 'SEM_REVIEW', 'missing_for_determination', 'verdict and missing basis disagree');
    const paths = [], rows = value.field_reviews;
    for (const row of rows) {
        keys(row, ['field_path', 'verdict', 'issue', 'anchor_ids', 'material_requirement_indexes', 'explanation'], 'field review');
        text(row.field_path, 'field_path');
        text(row.explanation, 'explanation');
        oneOf(row.verdict, ['upheld', 'refuted', 'cannot-determine'], row.field_path);
        oneOf(row.issue, SEMANTIC_ISSUES, row.field_path);
        requireSemantic(row.verdict === 'upheld' ? row.issue === 'none' : row.issue !== 'none', 'SEM_REVIEW', row.field_path, 'issue and verdict disagree');
        uniqueStrings(row.anchor_ids, row.field_path);
        array(row.material_requirement_indexes, row.field_path);
        requireSemantic(row.material_requirement_indexes.every((n, i) => ordinal(n) && (i === 0 || n > row.material_requirement_indexes[i - 1])), 'SEM_REFERENCE', row.field_path, 'ordered requirement indexes required');
        if (subject) {
            subset(row.anchor_ids, subject.anchors.map((a) => a.anchor_id), row.field_path);
            subset(row.material_requirement_indexes, Array.from({ length: subject.material_use?.requirements.length || 0 }, (_, i) => i), row.field_path);
            const emptyCollections = {
                '/semantics/contexts': subject.semantics.contexts.length === 0,
                '/semantics/couplings': subject.semantics.couplings.length === 0,
                '/semantics/relation_proposals': subject.semantics.relation_proposals.length === 0,
                '/semantics/unresolved_findings': subject.semantics.unresolved_findings.length === 0,
            };
            requireSemantic(row.anchor_ids.length + row.material_requirement_indexes.length > 0 || emptyCollections[row.field_path], 'SEM_REVIEW', row.field_path, 'field review needs exact evidence binding');
        }
        requireSemantic(!paths.includes(row.field_path), 'SEM_REVIEW', row.field_path, 'duplicate coverage');
        paths.push(row.field_path);
    }
    requireSemantic(rows.length > 0, 'SEM_REVIEW', 'field_reviews', 'coverage required');
    const overall = rows.some((r) => r.verdict === 'refuted') ? 'refuted' : rows.some((r) => r.verdict === 'cannot-determine') ? 'cannot-determine' : 'upheld';
    requireSemantic(value.verdict === overall, 'SEM_REVIEW', 'verdict', 'must aggregate every declared field verdict');
    if (subject) {
        requireSemantic(value.subject_digest === materialHash(semanticJson(subject)), 'SEM_SUBJECT', 'result', 'different sealed target');
        requireSemantic(semanticJson(paths) === semanticJson(semanticCoverage(subject.semantics, subject.subject_kind)), 'SEM_REVIEW', 'field_reviews', 'exact ordered coverage required');
    }
    else {
        const top = ['/semantics/atomicity', '/semantics/contexts', '/semantics/couplings', '/semantics/relation_proposals', '/semantics/unresolved_findings', '/material_use'];
        requireSemantic(semanticJson(paths.slice(0, 6)) === semanticJson(top), 'SEM_REVIEW', 'field_reviews', 'required top-level coverage');
        const unitPaths = paths.slice(6, paths.at(-1) === '/output_binding/basis' ? -1 : undefined);
        const fields = ['proposition', ...Object.keys(SEMANTIC_FACETS)];
        requireSemantic(unitPaths.length % fields.length === 0 && unitPaths.every((p, i) => p === `/semantics/units/${Math.floor(i / fields.length)}/${fields[i % fields.length]}`), 'SEM_REVIEW', 'field_reviews', 'finite contiguous unit coverage required');
    }
    const findings = value.unresolved_findings;
    findings.forEach((finding, i) => {
        if (subject)
            findingShape(finding, i, paths, subject.anchors, subject.material_use?.requirements.length || 0);
        else {
            requireSemantic(obj(finding), 'SEM_FORMAT', 'finding', 'closed finding required');
            uniqueStrings(finding.anchor_ids, 'finding anchors');
            requireSemantic(finding.anchor_ids.every((id) => /^A[1-9]\d*$/u.test(id)), 'SEM_REFERENCE', 'finding anchors', 'anchor IDs required');
            array(finding.material_requirement_indexes, 'finding requirements');
            requireSemantic(finding.material_requirement_indexes.every((index) => ordinal(index)), 'SEM_REFERENCE', 'finding requirements', 'safe indexes required');
            const anchorIds = [...finding.anchor_ids].sort((a, b) => Number(a.slice(1)) - Number(b.slice(1)));
            const indexes = [...new Set(finding.material_requirement_indexes)].sort((a, b) => a - b);
            findingShape(finding, i, paths, anchorIds.map((anchor_id) => ({ anchor_id })), indexes);
        }
        requireSemantic(finding.code === 'relation-deferred' || rows.some((r) => r.field_path === finding.field_path && r.verdict !== 'upheld'), 'SEM_REVIEW', finding.field_path, 'unexplained reviewer finding');
    });
    for (const row of rows.filter((r) => r.verdict === 'cannot-determine'))
        requireSemantic(findings.some((f) => f.field_path === row.field_path), 'SEM_REVIEW', row.field_path, 'cannot-determine needs matching unresolved finding');
}
function decoded(value) {
    return value.replace(/&#10;/gu, '\n').replace(/&#13;/gu, '\r').replace(/&#124;/gu, '|').replace(/&amp;/gu, '&');
}
function tableProjection(header, cells) {
    return Object.fromEntries(header.map((key, i) => {
        const value = decoded(cells[i]);
        return [key, value.startsWith('[') ? parseSemanticJson(value) : value];
    }));
}
export function semanticPacketBasis(model, ids) {
    return ids.map((id) => {
        const p = model.packets.find((p) => p.values.packetId === id)?.values;
        const records = model.exactEvidence.records.filter((r) => r.values.packetIds.split(',').map((s) => s.trim()).includes(id));
        requireSemantic(p && records.length === 1 && records[0].values.evidenceState === 'exact', 'SEM_REFERENCE', id, 'complete exact packet required');
        const record = records[0], fragments = model.exactEvidence.fragments.filter((f) => f.values.evidenceKey === record.values.evidenceKey);
        const members = record.values.packetIds.split(',').map((s) => s.trim());
        requireSemantic(String(fragments.length) === record.values.fragmentCount && fragments.length > 0
            && fragments.every((f, i) => f.values.fragmentOrder === String(i + 1) && f.values.packetId === members[i])
            && members.length === fragments.length && new Set(members).size === members.length, 'SEM_EVIDENCE', id, 'one ordered packet per exact fragment required');
        const exactBytes = [];
        for (const fragment of fragments) {
            const span = sourceSpan(model, fragment.values.sourceId, fragment.values.locator);
            requireSemantic(materialHash(span.bytes) === fragment.values.fragmentHash && span.bytes.toString('base64') === fragment.values.exactBytesBase64, 'SEM_EVIDENCE', id, 'exact fragment differs');
            exactBytes.push(span.bytes);
        }
        requireSemantic(record.values.exactEvidenceHash === `sha256:${framedExactEvidenceHash(exactBytes)}`, 'SEM_EVIDENCE', id, 'ordered framed evidence hash differs');
        return { packet_id: id, packet: { packet_id: p.packetId, source_id: p.sourceId, locator: p.locator, span_hash: p.spanHash,
                quote: decoded(p.quote), criterion: p.criterion, status: p.status },
            evidence_record: tableProjection(model.exactEvidence.recordTable.header, record.cells),
            fragments: fragments.map((f) => tableProjection(model.exactEvidence.fragmentTable.header, f.cells)),
            transformations: model.exactEvidence.transformations.filter((t) => t.values.evidenceKey === record.values.evidenceKey)
                .map((t) => tableProjection(model.exactEvidence.transformationTable.header, t.cells)) };
    });
}
function outputPackets(output) {
    return output.kind === 'no-claim' ? [output.packet_id] : output.kind === 'material-only' ? [] : output.packet_ids;
}
export function semanticRunBinding(model) {
    const m = model.manifest;
    return { run_id: m.runId, run_format_version: m.runFormatVersion, core_digest: m.forwardIdentity.coreDigest,
        checker_digest: m.forwardIdentity.checkerDigest, bundle_digest: m.forwardIdentity.bundleDigest, runtime_snapshot_digest: m.forwardIdentity.runtimeSnapshotDigest };
}
export function semanticProducerBinding(tuple) {
    keys(tuple, ['call_id', 'context_id', 'raw_return_hash', 'output_kind', 'output_index'], 'producer binding');
    text(tuple.call_id, 'call_id');
    text(tuple.context_id, 'context_id');
    hash(tuple.raw_return_hash, 'raw_return_hash');
    oneOf(tuple.output_kind, SEMANTIC_OUTPUT_KINDS, 'output_kind');
    requireSemantic(ordinal(tuple.output_index), 'SEM_FORMAT', 'output_index', 'safe index required');
    return materialHash(semanticJson(tuple));
}
function subjectOutput(value) {
    requireSemantic(obj(value), 'SEM_FORMAT', 'output_binding', 'closed variant required');
    oneOf(value.kind, ['packet-group', 'claim', 'no-claim', 'material-only'], 'output_binding/kind');
    const fields = { 'packet-group': ['kind', 'evidence_keys', 'packet_ids'],
        claim: ['kind', 'reserved_claim_id', 'normalized_claim', 'packet_ids', 'source_ids', 'claim_type'],
        'no-claim': ['kind', 'packet_id', 'basis'], 'material-only': ['kind', 'object_id'] };
    keys(value, fields[value.kind], 'output_binding');
    if (value.kind === 'claim') {
        requireSemantic(existingId(value.reserved_claim_id, 'CC'), 'SEM_REFERENCE', 'output_binding', 'reserved CC required');
        text(value.normalized_claim, 'normalized_claim');
        oneOf(value.claim_type, ['factual', 'design-intent', 'constraint', 'preference', 'open-question'], 'claim_type');
        uniqueStrings(value.source_ids, 'source_ids', true);
    }
    if (value.kind === 'claim' || value.kind === 'packet-group') {
        uniqueStrings(value.packet_ids, 'packet_ids', true);
        requireSemantic(value.packet_ids.every((id) => existingId(id, 'PKT')), 'SEM_REFERENCE', 'packet_ids', 'existing packet IDs required');
    }
    if (value.kind === 'packet-group')
        uniqueStrings(value.evidence_keys, 'evidence_keys', true);
    if (value.kind === 'no-claim') {
        requireSemantic(existingId(value.packet_id, 'PKT'), 'SEM_REFERENCE', 'packet_id', 'packet ID required');
        text(value.basis, 'basis');
    }
    if (value.kind === 'material-only')
        requireSemantic(semanticId(value.object_id, 'OBJ'), 'SEM_REFERENCE', 'object_id', 'existing object required');
}
const SUBJECT_KEYS = ['format', 'semantic_id', 'owner_stage', 'subject_kind', 'review_mode', 'predecessor_semantic_id', 'producer_binding_hash', 'run_binding', 'prompt_parts', 'reviewer_profile', 'output_binding', 'origin_unit_refs', 'origin_context', 'packet_basis', 'anchors', 'semantics', 'material_use', 'material_views', 'lineage_context', 'relation_context', 'ambiguity_context', 'context_manifest'];
function reviewerProfileShape(value) {
    keys(value, ['profile_id', 'profile_digest', 'role', 'model_identity'], 'reviewer_profile');
    text(value.profile_id, 'profile_id');
    requireSemantic(value.role === 'verifier-l2s', 'SEM_ISOLATION', 'reviewer_profile', 'L2S role required');
    // Shape alone cannot establish execution mode. The retained run selects the
    // variant in validateSemanticReviewerProfile, including for subject creation.
    if (value.profile_digest === null) {
        requireSemantic(value.profile_id === 'n/a (core-manual)' && value.model_identity === 'human', 'SEM_SUBJECT', 'reviewer_profile', 'exact manual profile variant required');
    }
    else {
        hash(value.profile_digest, 'profile_digest');
        requireSemantic(value.profile_id !== 'n/a (core-manual)', 'SEM_SUBJECT', 'reviewer_profile', 'manual profile cannot have a digest');
        requireSemantic(obj(value.model_identity) && semanticJson(Object.keys(value.model_identity).sort()) === semanticJson(['provider', 'model_id', 'resolved_version', 'identity_kind', 'immutable', 'context', 'effort', 'budget', 'cache', 'batch', 'fallback'].sort()), 'SEM_FORMAT', 'model_identity', 'existing closed model identity required');
    }
}
export function validateSemanticReviewerProfile(value, model, stage) {
    reviewerProfileShape(value);
    requireSemantic(model.manifest && forwardExecutionIdentityProblems(model.manifest).length === 0, 'SEM_SUBJECT', 'run identity', 'existing exact execution identity contract required');
    const manifest = model.manifest;
    if (manifest.mode === 'manual') {
        requireSemantic(value.profile_digest === null && value.profile_id === 'n/a (core-manual)' && value.model_identity === 'human', 'SEM_SUBJECT', 'reviewer_profile', 'retained manual mode requires exact manual variant');
        return;
    }
    requireSemantic(['agent', 'hybrid'].includes(manifest.mode) && value.profile_digest !== null && obj(value.model_identity), 'SEM_SUBJECT', 'reviewer_profile', 'retained agent/hybrid mode requires pinned model/profile objects');
    const snapshotBytes = readMaterialFile(model.runDir, manifest.forwardIdentity.runtimeSnapshotRef);
    const snapshot = parseStrictJson(snapshotBytes);
    requireSemantic(obj(snapshot) && obj(snapshot.profile), 'SEM_SUBJECT', 'runtime snapshot', 'profile identity absent');
    const { tree_digest, ...snapshotBasis } = snapshot;
    requireSemantic(tree_digest === manifest.forwardIdentity.runtimeSnapshotDigest && materialHash(canonicalJsonBytes(snapshotBasis)) === tree_digest, 'SEM_SUBJECT', 'runtime snapshot', 'retained runtime snapshot projection digest differs');
    requireSemantic(value.profile_id === snapshot.profile.id && value.profile_digest === snapshot.profile.digest
        && manifest.forwardIdentity.adapterProfile === `${value.profile_id} @ ${value.profile_digest}`, 'SEM_SUBJECT', 'reviewer_profile', 'profile differs from retained snapshot/run');
    let profilePath = String(snapshot.profile.path);
    if (isAbsolute(profilePath)) {
        requireSemantic(obj(snapshot.bundle) && typeof snapshot.bundle.root === 'string', 'SEM_SUBJECT', 'profile', 'retained bundle root required');
        const withinBundle = relative(snapshot.bundle.root, profilePath).replaceAll('\\', '/');
        requireSemantic(withinBundle && !withinBundle.startsWith('../') && !isAbsolute(withinBundle), 'SEM_SUBJECT', 'profile', 'profile must belong to retained bundle');
        // Plans inspect an exact temporary after-image. Resolve the retained
        // bundle-relative file there, without rewriting absolute runtime pins.
        profilePath = `control/runtime/bundle/${withinBundle}`;
    }
    const profileBytes = readMaterialFile(model.runDir, profilePath), profile = parseStrictJson(profileBytes);
    requireSemantic(materialHash(profileBytes) === value.profile_digest && obj(profile) && obj(profile.role_mappings), 'SEM_SUBJECT', 'profile', 'exact profile bytes differ');
    const mapping = profile.role_mappings['verifier-l2s'], l2 = profile.role_mappings['verifier-l2'], producer = profile.role_mappings[stage === 'S2' ? 'extractor' : 'normalizer'];
    requireSemantic(obj(mapping) && obj(l2) && obj(producer) && mapping.model_slot === l2.model_slot && mapping.context_policy === l2.context_policy, 'SEM_ISOLATION', 'profile', 'L2S must use existing L2 slot/context');
    const efforts = ['low', 'medium', 'high', 'xhigh', 'max'];
    requireSemantic(efforts.includes(String(producer.effort)) && efforts.indexOf(String(mapping.effort)) >= efforts.indexOf(String(producer.effort)), 'SEM_ISOLATION', 'profile', 'reviewer effort below producer');
    requireSemantic(value.model_identity.context === mapping.context_policy && value.model_identity.effort === mapping.effort
        && value.model_identity.budget === mapping.budget_policy && value.model_identity.cache === mapping.cache_policy
        && value.model_identity.batch === mapping.batch_policy
        && value.model_identity.immutable === true && value.model_identity.fallback === false, 'SEM_SUBJECT', 'model_identity', 'unpinned role context/effort/fallback');
    const declared = parseStrictJson(manifest.forwardIdentity.modelIds);
    const execution = parseStrictJson(manifest.forwardIdentity.modelExecutionMapping);
    requireSemantic(obj(declared) && semanticJson(declared['verifier-l2s']) === semanticJson(value.model_identity)
        && obj(execution) && semanticJson(execution['verifier-l2s']) === semanticJson(value.model_identity), 'SEM_SUBJECT', 'model_identity', 'model/context/effort not exactly pinned in run');
}
export function validateSemanticSubjectShape(value) {
    keys(value, SUBJECT_KEYS, 'subject');
    requireSemantic(value.format === SEMANTIC_SUBJECT_FORMAT && semanticId(value.semantic_id, 'SEM'), 'SEM_FORMAT', 'subject', 'exact format and semantic ID required');
    oneOf(value.owner_stage, ['S2', 'S3', 'S4'], 'owner_stage');
    oneOf(value.subject_kind, ['packet-group', 'claim', 'no-claim', 'material-only'], 'subject_kind');
    oneOf(value.review_mode, ['proposal', 'unresolved-record'], 'review_mode');
    requireSemantic(value.predecessor_semantic_id === 'none' || semanticId(value.predecessor_semantic_id, 'SEM'), 'SEM_REFERENCE', 'predecessor_semantic_id', 'invalid predecessor');
    hash(value.producer_binding_hash, 'producer_binding_hash');
    keys(value.run_binding, ['run_id', 'run_format_version', 'core_digest', 'checker_digest', 'bundle_digest', 'runtime_snapshot_digest'], 'run_binding');
    requireSemantic(hasRunCapability(String(value.run_binding.run_format_version), 'semantic-unit-review'), 'SEM_COMPATIBILITY', 'run_binding', 'capability required');
    text(value.run_binding.run_id, 'run_id');
    for (const field of ['core_digest', 'checker_digest', 'bundle_digest', 'runtime_snapshot_digest'])
        hash(value.run_binding[field], field);
    reviewerProfileShape(value.reviewer_profile);
    subjectOutput(value.output_binding);
    requireSemantic(value.output_binding.kind === value.subject_kind, 'SEM_ENUM', 'output_binding', 'kind differs');
    for (const name of ['prompt_parts', 'origin_context', 'packet_basis', 'anchors', 'material_views', 'lineage_context', 'relation_context', 'ambiguity_context', 'context_manifest'])
        array(value[name], name);
    uniqueStrings(value.origin_unit_refs, 'origin_unit_refs');
    requireSemantic(value.origin_unit_refs.every((r) => /^SEM-(?=\d*[1-9])\d{4,}\/U[1-9]\d*$/u.test(r)), 'SEM_REFERENCE', 'origin_unit_refs', 'SEM/U references required');
    const subject = value;
    subject.anchors.forEach((a, i) => anchorShape(a, i, true));
    if (value.material_use !== null)
        validateMaterialUseInput(value.material_use);
    requireSemantic((value.subject_kind === 'no-claim') === (value.material_use === null), 'SEM_FORMAT', 'material_use', 'null only for no-claim');
    requireSemantic(value.subject_kind === 'material-only' || subject.anchors.length > 0, 'SEM_REFERENCE', 'anchors', 'exact source basis required');
    validateSemantics(value.semantics, subject.anchors, subject.material_use, subject.subject_kind);
    requireSemantic(subject.review_mode !== 'unresolved-record' || (subject.predecessor_semantic_id !== 'none' && subject.semantics.atomicity === 'CANNOT_DETERMINE'), 'SEM_STATE', 'unresolved-record', 'new linked indeterminate record required');
    requireSemantic(subject.subject_kind !== 'material-only' || subject.semantics.atomicity === 'CANNOT_DETERMINE', 'SEM_STATE', 'material-only', 'cannot invent an affirmative packet/claim');
    requireSemantic(subject.subject_kind !== 'no-claim' || subject.semantics.atomicity === 'no-claim', 'SEM_STATE', 'no-claim', 'reviewed no-claim required');
    requireSemantic(subject.owner_stage !== 'S2' || (['packet-group', 'material-only'].includes(subject.subject_kind) && subject.origin_unit_refs.length === 0), 'SEM_REFERENCE', 'S2', 'packet/material output and empty origins required');
}
export function semanticAdmissionProblems(subject) {
    const s = subject.semantics, problems = [];
    if (subject.review_mode !== 'proposal')
        problems.push('unresolved-record is not an affirmative license');
    if (!['single-assertion', 'inseparable-context', ...(subject.owner_stage === 'S2' ? ['multiple-separable'] : [])].includes(s.atomicity))
        problems.push('atomicity ineligible');
    if (s.unresolved_findings.some((f) => f.code !== 'relation-deferred'))
        problems.push('meaning-bearing unresolved finding');
    if (s.units.some((u) => Object.keys(SEMANTIC_FACETS).some((f) => u[f].state === 'CANNOT_DETERMINE')))
        problems.push('indeterminate facet');
    if (s.couplings.some((c) => c.treatment === 'CANNOT_DETERMINE'))
        problems.push('indeterminate coupling');
    if (subject.material_use?.use_state !== 'usable')
        problems.push('material use is not usable');
    if (subject.subject_kind === 'claim') {
        const output = subject.output_binding;
        if (s.units.length !== 1 || s.units[0].proposition !== output.normalized_claim)
            problems.push('canonical CC must equal sole reviewed proposition');
        if (s.units.some((u) => u.attribution.items.some((item) => item.kind === 'system-model-interpretation')))
            problems.push('producer interpretation is not source-entailed admission');
        const required = new Set(s.units.flatMap((u) => [...u.proposition_anchor_ids,
            ...Object.keys(SEMANTIC_FACETS).flatMap((f) => u[f].state === 'present' ? u[f].items.flatMap((i) => i.anchor_ids) : [])]));
        for (const c of s.contexts.filter((c) => c.use === 'required-for-interpretation'))
            c.anchor_ids.forEach((id) => required.add(id));
        if (subject.anchors.some((a) => required.has(a.anchor_id) && a.packet_ids.length === 0))
            problems.push('required textual content is unpacketed');
    }
    return problems;
}
export function semanticMaterialViews(model, rows, context = readRepresentationContext(model)) {
    return rows.map((row) => {
        validateRepresentationUse(model, context, row, false);
        return { use_subject: JSON.parse(representationUseSubjectJson(model, context, row)),
            use_subject_digest: materialHash(representationUseSubjectJson(model, context, row)),
            view: JSON.parse(representationReviewView(model, context, row)) };
    });
}
export function semanticOriginProjection(subject) {
    return { semantic_id: subject.semantic_id, subject_digest: materialHash(semanticJson(subject)), owner_stage: subject.owner_stage,
        output_binding: subject.output_binding, anchors: subject.anchors, semantics: subject.semantics,
        material_use: subject.material_use, material_views: subject.material_views };
}
export function emptySemanticLedger() { return { subjects: [], assignments: [], results: [], resolutions: [] }; }
export function semanticLedgerMarkdown(ledger) {
    return `# Semantic Review\n\n- semantic_review_format: ${SEMANTIC_FORMAT}\n\n`
        + Object.keys(SEMANTIC_HEADERS).map((key) => `## ${key}\n\n${materialTableMarkdown(SEMANTIC_HEADERS[key], ledger[key])}`).join('\n');
}
export function parseSemanticLedger(raw) {
    requireSemantic(raw.split(/\r?\n/u).filter((s) => s.includes('semantic_review_format:')).length === 1
        && raw.split(/\r?\n/u).includes(`- semantic_review_format: ${SEMANTIC_FORMAT}`), 'SEM_FORMAT', SEMANTIC_PATH, 'one exact marker required');
    const tables = parseTables(raw, SEMANTIC_PATH), ledger = emptySemanticLedger();
    requireSemantic(tables.length === 4, 'SEM_FORMAT', SEMANTIC_PATH, 'exactly four tables required');
    Object.keys(SEMANTIC_HEADERS).forEach((key, i) => {
        const header = SEMANTIC_HEADERS[key], table = tables[i];
        requireSemantic(semanticJson(table.header) === semanticJson(header), 'SEM_FORMAT', key, 'exact unique ordered header required');
        const seen = new Set();
        ledger[key] = table.rows.map((row) => {
            requireSemantic(row.cells.length === header.length && !seen.has(row.cells[0]), 'SEM_FORMAT', key, 'row width or duplicate identity');
            seen.add(row.cells[0]);
            const result = Object.fromEntries(header.map((field, n) => [field, decoded(row.cells[n])]));
            for (const field of ['review_ids', 'canonical_refs', 'origin_unit_refs', 'followup_semantic_ids'])
                if (field in result) {
                    const ids = parseSemanticJson(result[field]);
                    uniqueStrings(ids, `${key}/${field}`);
                }
            return result;
        });
    });
    return ledger;
}
export function semanticPromptRequirements(stage) {
    const stageHeading = stage === 'S2' ? 'S2 — Extraction pass (packetization)' : stage === 'S3' ? 'S3 — Candidate-claim normalization' : 'S4 successor semantic preservation (1.7)';
    return [
        { path: 'docs/architecture/prompts/README.md', selector: 'fence:Common preamble (include verbatim in every call)' },
        { path: 'docs/architecture/prompts/verifier-lenses.md', selector: 'fence:Common verifier frame (verbatim, after the common preamble)' },
        { path: 'docs/architecture/prompts/verifier-lenses.md', selector: `heading:${SEMANTIC_LENS}` },
        { path: 'docs/architecture/04-pipeline-stages-and-dod.md', selector: `heading:${stageHeading}` },
        { path: 'docs/architecture/templates/03-extraction-claims.md', selector: 'heading:T3.7 Semantic review (1.7)' },
        { path: 'docs/architecture/prompts/README.md', selector: 'fence:Material constraints (run format 1.6)' },
    ];
}
export function selectSemanticCorePart(bytes, selector) {
    const colon = selector.indexOf(':'), kind = selector.slice(0, colon), heading = selector.slice(colon + 1);
    requireSemantic(['heading', 'fence'].includes(kind), 'SEM_SUBJECT', selector, 'existing Core selector required');
    const lines = bytes.toString('utf8').split(/(?<=\n)/u);
    let offset = 0, start = -1, end = bytes.length, level = 0, inFence = false, matches = 0;
    for (const line of lines) {
        if (/^\s*```/u.test(line))
            inFence = !inFence;
        const match = !inFence && /^(#{1,6}) (.+?)\r?\n?$/u.exec(line);
        if (match) {
            if (start >= 0 && end === bytes.length && match[1].length <= level)
                end = offset;
            if (match[2] === heading) {
                matches++;
                if (start < 0) {
                    start = offset;
                    level = match[1].length;
                }
            }
        }
        offset += Buffer.byteLength(line);
    }
    requireSemantic(matches === 1 && start >= 0, 'SEM_SUBJECT', selector, 'unique pinned heading required');
    const section = bytes.subarray(start, end);
    if (kind === 'heading')
        return section;
    const match = /(?:^|\n)```[^\r\n]*\r?\n([\s\S]*?)\r?\n```(?:\r?\n|$)/u.exec(section.toString('utf8'));
    requireSemantic(match, 'SEM_SUBJECT', selector, 'pinned fence absent');
    return Buffer.from(match[1]);
}
export function semanticPinnedPrompts(model, stage) {
    const identity = model.manifest.forwardIdentity;
    const root = 'control/runtime/bundle', raw = readMaterialFile(model.runDir, `${root}/bundle.lock.json`);
    const lock = parseStrictJson(raw), sealed = resealBundleLock(lock);
    requireSemantic(raw.equals(bundleLockBytes(lock)) && sealed.lock_digest === lock.lock_digest && sealed.bundle.digest === lock.bundle.digest
        && lock.bundle.digest === identity.bundleDigest && lock.core.tree_digest === identity.coreDigest && lock.checker_digest === identity.checkerDigest, 'SEM_SUBJECT', 'run_binding', 'pinned lock/Core/checker differs');
    return semanticPromptRequirements(stage).map((part) => {
        const records = lock.files.filter((record) => record.path === part.path && record.classification === 'core');
        requireSemantic(records.length === 1, 'SEM_SUBJECT', part.path, 'prompt is outside unique pinned Core inventory');
        const bytes = readMaterialFile(model.runDir, `${root}/${part.path}`);
        requireSemantic(materialHash(bytes) === records[0].digest, 'SEM_SUBJECT', part.path, 'pinned prompt file changed');
        return { ...part, digest: materialHash(selectSemanticCorePart(bytes, part.selector)) };
    });
}
function canonicalClaimModel(model, output) {
    if (output.kind !== 'claim')
        return model;
    const existing = model.claims.find((c) => c.values.claimId === output.reserved_claim_id);
    if (existing) {
        const c = existing.values;
        requireSemantic(decoded(c.normalizedClaim) === output.normalized_claim && c.claimType === output.claim_type
            && semanticJson(c.packets.split(',').map((s) => s.trim())) === semanticJson(output.packet_ids)
            && semanticJson(c.sources.split(',').map((s) => s.trim())) === semanticJson(output.source_ids), 'SEM_SUBJECT', output.reserved_claim_id, 'canonical claim differs from reviewed output');
        return model;
    }
    return { ...model, claims: [...model.claims, { file: 'ledgers/claim-inventory.md', line: 0, cells: [], raw: '', values: {
                    claimId: output.reserved_claim_id, normalizedClaim: semanticClaimCell(output.normalized_claim), packets: output.packet_ids.join(', '),
                    sources: output.source_ids.join(', '), claimType: output.claim_type, disposition: '', rationale: '', judgedBy: '', verified: '', status: 'active',
                } }] };
}
/** Existing Markdown cell encoding, also used by the Slice 6 CC projection. */
export function semanticClaimCell(text) {
    return parseTables(materialTableMarkdown(['normalized claim'], [{ 'normalized claim': text }]))[0].rows[0].cells[0];
}
function useRowFromSubject(value) {
    requireSemantic(obj(value), 'SEM_SUBJECT', 'material view', 'existing use subject required');
    const fields = ['owner_stage', 'subject_kind', 'subject_id', 'basis_packet_ids', 'requirements', 'use_state', 'fidelity_claim', 'limitation_refs', 'reason', 'established_by'];
    return { use_id: 'USE-0001', ...Object.fromEntries(fields.map((field) => [field,
            ['basis_packet_ids', 'requirements', 'limitation_refs'].includes(field) ? semanticJson(value[field]) : String(value[field])])),
        review_subject_digest: materialHash(semanticJson(value)), reviewed_by: 'none' };
}
function subjectSources(subject, material) {
    const ids = subject.packet_basis.map((p) => p.packet.source_id);
    for (const req of subject.material_use?.requirements || []) {
        const object = material.inventory.objects.find((o) => o.object_id === req.object_id);
        requireSemantic(object, 'SEM_REFERENCE', req.object_id, 'unknown material object');
        const source = material.inventory.representations.find((r) => r.representation_id === object.representation_id)?.source_id;
        requireSemantic(source, 'SEM_REFERENCE', req.object_id, 'unknown representation source');
        ids.push(source);
    }
    return [...new Set(ids)];
}
function unitDefinition(model, kind, id) {
    if (kind === 'PKT') {
        const p = model.packets.find((p) => p.values.packetId === id)?.values;
        requireSemantic(p, 'SEM_REFERENCE', id, 'packet endpoint absent');
        return { kind, id, projection: { source_id: p.sourceId, locator: p.locator, span_hash: p.spanHash, criterion: p.criterion } };
    }
    const c = model.claims.find((c) => c.values.claimId === id)?.values;
    requireSemantic(c, 'SEM_REFERENCE', id, 'claim endpoint absent; reservation is not materialization');
    return { kind, id, projection: { normalized_claim: c.normalizedClaim, packets: c.packets.split(',').map((s) => s.trim()),
            sources: c.sources.split(',').map((s) => s.trim()), claim_type: c.claimType } };
}
function selectedSemanticReference(model, reference) {
    const match = /^([^#@]+)#((?:\/(?:[^~@]|~[01])*)?)@(sha256:[0-9a-f]{64})$/u.exec(reference);
    requireSemantic(match, 'SEM_REFERENCE', reference, 'canonical file#JSON-Pointer@file-digest required');
    const bytes = readMaterialFile(model.runDir, match[1]);
    requireSemantic(materialHash(bytes) === match[3], 'SEM_SUBJECT', match[1], 'referenced immutable bytes changed');
    let value = parseSemanticJson(bytes);
    for (const encoded of match[2] === '' ? [] : match[2].slice(1).split('/')) {
        const key = encoded.replace(/~1/gu, '/').replace(/~0/gu, '~');
        requireSemantic(value !== null && typeof value === 'object' && Object.hasOwn(value, key)
            && (!Array.isArray(value) || /^(?:0|[1-9]\d*)$/u.test(key)), 'SEM_REFERENCE', reference, 'JSON Pointer does not select an existing value');
        value = value[key];
    }
    return { path: match[1], pointer: match[2], value };
}
function validateSemanticWorkingAmbiguity(model, s, value) {
    const a = value;
    requireSemantic(obj(value) && semanticJson(value) === ambiguityReviewSubjectJson(a), 'SEM_FORMAT', 'ambiguity context', 'exact existing Slice 5 working subject required');
    oneOf(a.search_scope_kind, SEARCH_SCOPE_KINDS, 'ambiguity scope');
    oneOf(a.candidate_state, CANDIDATE_STATES, 'ambiguity candidate state');
    oneOf(a.resolution_state, RESOLUTION_STATES, 'ambiguity resolution');
    oneOf(a.carry_state, CARRY_STATES, 'ambiguity carry');
    const ids = outputPackets(s.output_binding);
    requireSemantic(a.source_entity_kind === 'PKT' && ids.includes(a.source_entity_id)
        || a.source_entity_kind === 'CC' && s.output_binding.kind === 'claim' && a.source_entity_id === s.output_binding.reserved_claim_id, 'SEM_REFERENCE', 'ambiguity context', 'working subject must concern an output unit');
    subset(a.basis_packet_ids, ids.filter((id) => model.packets.find((p) => p.values.packetId === id)?.values.sourceId === a.source_id), 'ambiguity packet basis', true);
    const input = { anchor_id: 'A1', source_id: a.source_id, locator: a.expression_locator,
        start_byte: a.expression_start_byte, end_byte: a.expression_end_byte, exact_bytes_base64: a.expression_bytes_base64 };
    const anchor = completeSemanticAnchors(model, [input], a.basis_packet_ids)[0];
    requireSemantic(anchor.selection_hash === a.expression_sha256 && anchor.packet_ids.length > 0
        && s.anchors.some((selected) => selected.source_id === a.source_id && selected.start_byte <= anchor.start_byte && selected.end_byte >= anchor.end_byte), 'SEM_EVIDENCE', 'ambiguity expression', 'exact expression must be explicit packet-covered context');
    const candidates = parseCandidateRefs(semanticJson(a.candidate_refs));
    requireSemantic(candidates.clean && (a.candidate_state === 'single' ? candidates.candidates.length === 1
        : a.candidate_state === 'multiple' ? candidates.candidates.length >= 2 : candidates.candidates.length === 0), 'SEM_REFERENCE', 'ambiguity candidates', 'existing candidate grammar and count required');
    const source = sourceSpan(model, a.source_id, a.expression_locator);
    const explicit = (start, end) => s.anchors.some((selected) => selected.source_id === a.source_id
        && selected.start_byte <= start && selected.end_byte >= end);
    for (const candidate of candidates.candidates) {
        const packet = candidate.kind === 'PKT' ? model.packets.find((p) => p.values.packetId === candidate.id)?.values : null;
        requireSemantic(candidate.kind !== 'PKT' || packet?.sourceId === a.source_id, 'SEM_REFERENCE', 'ambiguity candidate', 'same-source packet required');
        const span = sourceSpan(model, candidate.kind === 'PKT' ? packet.sourceId : candidate.source_id, candidate.kind === 'PKT' ? packet.locator : candidate.locator);
        requireSemantic((candidate.kind === 'PKT' || candidate.source_id === a.source_id && candidate.span_hash === materialHash(span.bytes))
            && explicit(span.start, span.end), 'SEM_EVIDENCE', 'ambiguity candidate', 'same-source candidate and its exact context required');
    }
    let scopeRefs = [];
    if (a.search_scope_kind === 'local-intervals') {
        scopeRefs = parseSemanticJson(a.search_completion_ref);
        subset(scopeRefs, model.sourceWalk.intervals.filter((r) => r.values.sourceId === a.source_id).map((r) => r.values.walkId), 'ambiguity local intervals', true);
        requireSemantic(a.candidate_state === 'single' && a.resolution_state === 'resolved-local', 'SEM_STATE', 'ambiguity local search', 'existing bounded local resolution rules required');
        for (const id of scopeRefs) {
            const row = model.sourceWalk.intervals.find((r) => r.values.walkId === id).values;
            requireSemantic(explicit(Number(row.startByte), Number(row.endByte)), 'SEM_REFERENCE', id, 'search interval must be explicit legal context');
        }
    }
    else {
        const completion = model.sourceWalk.completions.find((r) => r.values.sourceId === a.source_id && r.values.completionState === 'complete')?.values;
        const lineCount = source.source.toString('utf8').split('\n').length - (source.source.at(-1) === 10 ? 1 : 0);
        const whole = sourceSpan(model, a.source_id, `L1-L${lineCount}`);
        requireSemantic(completion && a.search_completion_ref === `${a.source_id}@${completion.finalCursorId}@${completion.sourceHash}`
            && explicit(whole.start, whole.end), 'SEM_REFERENCE', 'ambiguity search', 'existing complete same-source search and explicit basis required');
    }
    requireSemantic(searchBasisDigest({ source_id: a.source_id, source_hash: materialHash(source.source), source_length_bytes: source.source.length,
        scope_kind: a.search_scope_kind, scope_refs: scopeRefs, completion_ref: a.search_scope_kind === 'local-intervals' ? 'none' : a.search_completion_ref,
        expression_start_byte: a.expression_start_byte, expression_end_byte: a.expression_end_byte, expression_sha256: a.expression_sha256,
        basis_packet_ids: a.basis_packet_ids, candidate_state: a.candidate_state, candidate_refs: a.candidate_refs }) === a.search_basis_digest, 'SEM_SUBJECT', 'ambiguity search', 'existing Slice 5 search basis digest differs');
    uniqueStrings(a.affected_relation_ids, 'ambiguity affected relations');
    requireSemantic(a.affected_relation_ids.every((id) => parseRelations(model).rows.some((r) => r.values.relationId === id))
        && legalResolutionCarryState(a.resolution_state, a.carry_state, a.affected_relation_ids.length)
        && (a.resolution_state !== 'resolved-local' || a.candidate_state === 'single' && a.carry_state === 'none')
        && (a.resolution_state !== 'unresolved' || a.search_scope_kind === 'full-same-source')
        && /^(?:human|invocation):\S+$/u.test(a.proposed_by), 'SEM_STATE', 'ambiguity context', 'existing Slice 5 working-state rules required');
}
function validateSemanticAmbiguityContext(model, subject) {
    const references = new Set();
    for (const context of subject.ambiguity_context) {
        keys(context, ['kind', 'reference', 'digest', 'projection'], 'ambiguity_context');
        oneOf(context.kind, ['semantic-finding', 'slice5-working-subject'], 'ambiguity kind');
        requireSemantic(!references.has(context.reference), 'SEM_REFERENCE', 'ambiguity context', 'duplicate reference');
        references.add(context.reference);
        const selected = selectedSemanticReference(model, context.reference);
        requireSemantic(semanticJson(selected.value) === semanticJson(context.projection) && context.digest === materialHash(semanticJson(selected.value)), 'SEM_SUBJECT', 'ambiguity context', 'exact selected projection differs');
        if (context.kind === 'slice5-working-subject') {
            requireSemantic(selected.path.startsWith('verification/harness/') && !selected.path.includes('/semantic-results/'), 'SEM_ISOLATION', selected.path, 'only retained working subject context permitted');
            validateSemanticWorkingAmbiguity(model, subject, selected.value);
        }
        else {
            const match = /^verification\/harness\/semantic-(subjects|results)\/((?:SEM|VER)-\d{4,})\.json$/u.exec(selected.path);
            requireSemantic(match && (match[1] === 'subjects' ? /^\/semantics\/unresolved_findings\/(?:0|[1-9]\d*)$/u : /^\/unresolved_findings\/(?:0|[1-9]\d*)$/u).test(selected.pointer), 'SEM_ISOLATION', selected.path, 'only a selected retained finding may be projected');
            const ledger = parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8'));
            const id = match[1] === 'subjects' ? match[2] : ledger.results.find((r) => r.review_id === match[2])?.semantic_id;
            const row = ledger.subjects.find((r) => r.semantic_id === id);
            requireSemantic(row && id !== subject.semantic_id, 'SEM_REFERENCE', selected.path, 'finding must name a prior retained subject');
            const bytes = readMaterialFile(model.runDir, row.subject_path), prior = parseSemanticJson(bytes);
            requireSemantic(materialHash(bytes) === row.subject_digest, 'SEM_SUBJECT', row.subject_path, 'prior finding subject changed');
            const finding = context.projection;
            findingShape(finding, Number(finding.finding_id.slice(1)) - 1, semanticCoverage(prior.semantics, prior.subject_kind), prior.anchors, prior.material_use?.requirements.length || 0, model, subjectSources(subject, readRepresentationContext(model)));
            requireSemantic(finding.anchor_ids.some((id) => {
                const old = prior.anchors.find((a) => a.anchor_id === id);
                return subject.anchors.some((a) => a.source_id === old.source_id && a.start_byte <= old.start_byte && a.end_byte >= old.end_byte);
            }) || finding.material_requirement_indexes.some((i) => subject.material_use?.requirements.some((r) => semanticJson(r) === semanticJson(prior.material_use.requirements[i]))), 'SEM_REFERENCE', selected.path, 'finding must concern explicit subject context');
        }
    }
}
export function semanticContextManifest(model, subject) {
    const entries = [];
    const add = (path, selector, bytes, purpose) => {
        const entry = { path, selector, digest: materialHash(bytes), purpose };
        const prior = entries.find((e) => e.path === path && e.selector === selector);
        requireSemantic(!prior || semanticJson(prior) === semanticJson(entry), 'SEM_SUBJECT', path, 'context selector has conflicting purpose');
        if (!prior)
            entries.push(entry);
    };
    for (const a of subject.anchors)
        add(sourceSpan(model, a.source_id, a.locator).path, `bytes:${a.start_byte}:${a.end_byte}`, Buffer.from(a.exact_bytes_base64, 'base64'), a.packet_ids.length ? 'packet-evidence' : 'inspection-context');
    const packetIds = new Set(subject.packet_basis.map((p) => p.packet_id));
    const evidenceKeys = new Set(subject.packet_basis.map((p) => String(p.evidence_record.evidence_key)));
    const addRows = (path, ids, purpose, related = new Set()) => {
        const raw = readMaterialFile(model.runDir, path).toString('utf8'), lines = raw.split('\n');
        for (const table of parseTables(raw, path)) {
            const heading = lines.slice(0, table.line - 1).reverse().find((line) => /^#{1,6} /u.test(line))?.replace(/^#{1,6} /u, '').replace(/\r$/u, '');
            table.rows.forEach((row, i) => {
                if (!ids.has(decoded(row.cells[0])) && !related.has(decoded(row.cells[1] || '')))
                    return;
                requireSemantic(heading && lines.filter((line) => line.replace(/^#{1,6} /u, '').replace(/\r$/u, '') === heading).length === 1, 'SEM_REFERENCE', path, 'selected row requires unique literal table heading');
                add(path, `row:${heading}:${i}`, semanticJson(row.cells.map(decoded)), purpose);
            });
        }
    };
    addRows('ledgers/packet-index.md', new Set([...packetIds, ...evidenceKeys]), 'packet-evidence', evidenceKeys);
    for (const origin of subject.origin_context)
        for (const field of ['semantic_id', 'subject_digest', 'owner_stage', 'output_binding', 'anchors', 'semantics', 'material_use', 'material_views']) {
            if (field !== 'subject_digest')
                add(semanticSubjectPath(origin.semantic_id), `json:/${field}`, semanticJson(origin[field]), 'inspection-context');
        }
    for (const material of subject.material_views) {
        const view = material.view;
        const selectedIds = new Set();
        for (const name of ['representations', 'objects', 'bindings', 'associations', 'provenance', 'assets']) {
            for (const row of view[name])
                selectedIds.add(String(Object.values(row)[0]));
        }
        addRows('corpus/representations.md', selectedIds, 'material-context');
        const useLimitations = view.limitations.map((r) => String(r.limitation_ref)).filter((id) => id.startsWith('USE-'));
        if (useLimitations.length)
            addRows('ledgers/representation-uses.md', new Set(useLimitations), 'material-context');
        for (const asset of (view.assets || [])) {
            if (typeof asset.bytes_base64 === 'string')
                add(String(asset.locus), `bytes:0:${Buffer.from(asset.bytes_base64, 'base64').length}`, Buffer.from(asset.bytes_base64, 'base64'), 'material-context');
        }
    }
    for (const lineage of subject.lineage_context) {
        const reservedPath = `verification/harness/semantic-process/${lineage.lineage_id}.json`;
        if (existsSync(join(model.runDir, reservedPath)))
            add(reservedPath, 'json:', readMaterialFile(model.runDir, reservedPath), 'lineage-context');
        else
            addRows('ledgers/lineage.md', new Set([lineage.lineage_id]), 'lineage-context');
    }
    for (const relation of subject.relation_context) {
        for (const anchor of relation.target_anchors) {
            const path = sourceSpan(model, anchor.source_id, anchor.locator).path, selector = `bytes:${anchor.start_byte}:${anchor.end_byte}`;
            if (!entries.some((entry) => entry.path === path && entry.selector === selector))
                add(path, selector, Buffer.from(anchor.exact_bytes_base64, 'base64'), 'relation-context');
        }
        const otherPackets = relation.target_packet_context.filter((p) => !packetIds.has(p.packet_id));
        const otherKeys = new Set(otherPackets.map((p) => String(p.evidence_record.evidence_key)).filter((key) => !evidenceKeys.has(key)));
        addRows('ledgers/packet-index.md', new Set([...otherPackets.map((p) => p.packet_id), ...otherKeys]), 'relation-context', otherKeys);
    }
    for (const context of subject.ambiguity_context) {
        const reference = /^([^#@]+)#([^@]*)@(sha256:[0-9a-f]{64})$/u.exec(context.reference);
        requireSemantic(reference, 'SEM_REFERENCE', 'ambiguity_context', 'file#pointer@digest reference required');
        add(reference[1], `json:${reference[2]}`, semanticJson(context.projection), 'ambiguity-context');
        if (context.kind === 'slice5-working-subject') {
            const working = context.projection;
            const ids = working.search_scope_kind === 'local-intervals'
                ? parseSemanticJson(working.search_completion_ref) : [working.source_id];
            addRows('ledgers/source-walk.md', new Set(ids), 'ambiguity-context');
        }
    }
    return entries.sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)) || Buffer.compare(Buffer.from(a.selector), Buffer.from(b.selector)));
}
export function validateSemanticSubject(value, model, visiting = new Set(), newReservation = false) {
    validateSemanticSubjectShape(value);
    const subject = value, digest = materialHash(semanticJson(subject)), id = subject.semantic_id;
    requireSemantic(!visiting.has(id), 'SEM_REFERENCE', id, 'semantic reference cycle');
    visiting.add(id);
    requireSemantic(semanticJson(subject.run_binding) === semanticJson(semanticRunBinding(model)), 'SEM_SUBJECT', id, 'retained run identity differs');
    requireSemantic(semanticJson(subject.prompt_parts) === semanticJson(semanticPinnedPrompts(model, subject.owner_stage)), 'SEM_SUBJECT', id, 'pinned prompt bytes differ');
    validateSemanticReviewerProfile(subject.reviewer_profile, model, subject.owner_stage);
    const packetIds = outputPackets(subject.output_binding);
    requireSemantic(semanticJson(subject.packet_basis) === semanticJson(semanticPacketBasis(model, packetIds)), 'SEM_SUBJECT', id, 'packet evidence or display projection differs');
    const inputs = subject.anchors.map((a) => ({ anchor_id: a.anchor_id, source_id: a.source_id, locator: a.locator, start_byte: a.start_byte, end_byte: a.end_byte, exact_bytes_base64: a.exact_bytes_base64 }));
    requireSemantic(semanticJson(subject.anchors) === semanticJson(completeSemanticAnchors(model, inputs, packetIds)), 'SEM_EVIDENCE', id, 'completed anchors differ');
    const material = readRepresentationContext(model), sources = subjectSources(subject, material);
    requireSemantic(subject.anchors.every((a) => sources.includes(a.source_id)), 'SEM_REFERENCE', id, 'anchor outside output source scope');
    requireSemantic(subject.owner_stage !== 'S2' || sources.length === 1, 'SEM_REFERENCE', id, 'S2 must remain one-source');
    validateSemantics(subject.semantics, subject.anchors, subject.material_use, subject.subject_kind, model, sources);
    const proposed = canonicalClaimModel(model, subject.output_binding);
    if (subject.output_binding.kind === 'claim')
        requireSemantic(semanticJson([...new Set(subject.packet_basis.map((p) => p.packet.source_id))])
            === semanticJson(subject.output_binding.source_ids), 'SEM_REFERENCE', id, 'CC source provenance differs');
    const requiredKinds = subject.output_binding.kind === 'material-only' ? [`OBJ:${subject.output_binding.object_id}`]
        : subject.output_binding.kind === 'claim' ? [`CC:${subject.output_binding.reserved_claim_id}`] : packetIds.map((p) => `PKT:${p}`);
    const seenUses = [];
    for (const entry of subject.material_views) {
        keys(entry, ['use_subject', 'use_subject_digest', 'view'], 'material_views');
        const row = useRowFromSubject(entry.use_subject);
        validateRepresentationUse(proposed, material, row, false);
        // The view seals the USE limitations that existed when it was shown.
        // Later append-only OBJ findings remain separate history, not retroactive
        // attachments to an old review. Every selected earlier limitation reopens.
        const view = entry.view;
        requireSemantic(Array.isArray(view.limitations), 'SEM_SUBJECT', id, 'existing material limitation view required');
        const useIds = view.limitations.map((r) => String(r.limitation_ref)).filter((id) => id.startsWith('USE-'));
        requireSemantic(useIds.every((id) => material.uses.some((use) => use.use_id === id)), 'SEM_SUBJECT', id, 'shown material limitation absent');
        const viewContext = newReservation ? material : { ...material, uses: material.uses.filter((use) => useIds.includes(use.use_id)) };
        const expected = semanticMaterialViews(proposed, [row], viewContext)[0];
        requireSemantic(semanticJson(entry) === semanticJson(expected), 'SEM_SUBJECT', id, 'material subject/view differs');
        seenUses.push(`${row.subject_kind}:${row.subject_id}`);
        if (subject.material_use && requiredKinds.includes(`${row.subject_kind}:${row.subject_id}`)) {
            const use = validateMaterialUseInput({ requirements: parseSemanticJson(row.requirements), use_state: row.use_state, fidelity_claim: row.fidelity_claim,
                limitation_refs: parseSemanticJson(row.limitation_refs), reason: row.reason });
            requireSemantic(semanticJson(use) === semanticJson(subject.material_use), 'SEM_SUBJECT', id, 'material declaration differs from selected output');
        }
    }
    requireSemantic(semanticJson(seenUses) === semanticJson(requiredKinds), 'SEM_SUBJECT', id, 'exact applicable material views required');
    const originIds = [...new Set(subject.origin_unit_refs.map((ref) => ref.split('/')[0]))];
    requireSemantic(semanticJson(subject.origin_context.map((o) => o.semantic_id)) === semanticJson(originIds), 'SEM_REFERENCE', id, 'origin context is not exact direct projection');
    for (const origin of subject.origin_context) {
        const prior = parseSemanticJson(readMaterialFile(model.runDir, semanticSubjectPath(origin.semantic_id)));
        validateSemanticSubject(prior, model, new Set(visiting));
        requireSemantic(semanticJson(origin) === semanticJson(semanticOriginProjection(prior)), 'SEM_SUBJECT', id, 'origin projection differs');
        for (const ref of subject.origin_unit_refs.filter((r) => r.startsWith(`${origin.semantic_id}/`)))
            requireSemantic(prior.semantics.units.some((u) => ref.endsWith(`/${u.unit_id}`)), 'SEM_REFERENCE', ref, 'origin unit absent');
    }
    if (subject.predecessor_semantic_id !== 'none') {
        const previous = parseSemanticJson(readMaterialFile(model.runDir, semanticSubjectPath(subject.predecessor_semantic_id)));
        validateSemanticSubject(previous, model, new Set(visiting));
    }
    for (const context of subject.lineage_context) {
        keys(context, ['lineage_id', 'row_digest', 'event', 'unit_definitions'], 'lineage_context');
        keys(context.event, ['owner_stage', 'type', 'predecessors', 'successors'], 'lineage event');
        oneOf(context.event.type, LINEAGE_TYPES, 'lineage type');
        const row = parseLineage(model).rows.find((r) => r.values.lineageId === context.lineage_id);
        let cells;
        if (row)
            cells = row.cells.map(decoded);
        else {
            const reserved = parseSemanticJson(readMaterialFile(model.runDir, `verification/harness/semantic-process/${context.lineage_id}.json`));
            keys(reserved, ['lineage_id', 'owner_stage', 'type', 'predecessors', 'successors', 'basis', 'established_by'], 'reserved lineage row');
            requireSemantic(existingId(context.lineage_id, 'LIN') && reserved.lineage_id === context.lineage_id
                && context.event.predecessors.every((id) => id.startsWith('PKT-')
                    ? lineageCurrentPacketIds(model).has(id) : lineageCurrentClaimIds(model).has(id)), 'SEM_REFERENCE', context.lineage_id, 'reserved event requires its exact LIN identity and current predecessors');
            cells = Object.values(reserved);
        }
        requireSemantic(materialHash(semanticJson(cells)) === context.row_digest && cells[1] === context.event.owner_stage && cells[2] === context.event.type
            && semanticJson(cells[3].split(',').map((s) => s.trim())) === semanticJson(context.event.predecessors)
            && semanticJson(cells[4] === 'none' ? [] : cells[4].split(',').map((s) => s.trim())) === semanticJson(context.event.successors), 'SEM_SUBJECT', context.lineage_id, 'reserved/current event differs');
        requireSemantic(semanticJson(context.unit_definitions) === semanticJson(context.event.predecessors.map((id) => unitDefinition(model, id.startsWith('PKT-') ? 'PKT' : 'CC', id))), 'SEM_SUBJECT', context.lineage_id, 'direct predecessor definitions differ');
    }
    if (subject.owner_stage === 'S4') {
        requireSemantic(subject.lineage_context.length === 1 && (subject.output_binding.kind === 'claim'
            && subject.lineage_context[0].event.successors.includes(subject.output_binding.reserved_claim_id)
            || subject.output_binding.kind === 'material-only'), 'SEM_WINDOW', id, 'S4 requires exact already-proposed successor or its material refusal');
        const lineage = subject.lineage_context[0];
        requireSemantic(lineage.event.owner_stage === 'S4' && lineage.unit_definitions.every((u) => u.kind === 'CC'), 'SEM_WINDOW', id, 'bounded S4 CC predecessor group required');
        if (subject.output_binding.kind === 'claim') {
            const union = [...new Set(lineage.unit_definitions.flatMap((u) => u.projection.packets))];
            requireSemantic(semanticJson(subject.output_binding.packet_ids) === semanticJson(union), 'SEM_ACCOUNTING', id, 'S4 successor must preserve exact predecessor packet union');
            const origins = lineage.event.predecessors.flatMap((id) => {
                const origin = subject.origin_context.find((o) => o.output_binding.kind === 'claim' && o.output_binding.reserved_claim_id === id);
                requireSemantic(origin, 'SEM_ACCOUNTING', id, 'direct predecessor semantic projection required');
                return origin.semantics.units.map((unit) => `${origin.semantic_id}/${unit.unit_id}`);
            });
            requireSemantic(semanticJson(subject.origin_unit_refs) === semanticJson(origins), 'SEM_ACCOUNTING', id, 'S4 predecessor unit coverage differs');
        }
    }
    requireSemantic(subject.relation_context.length === subject.semantics.relation_proposals.length, 'SEM_REFERENCE', 'relation_context', 'exact proposal context coverage required');
    subject.relation_context.forEach((context, i) => {
        keys(context, ['proposal_index', 'target_units', 'target_anchors', 'target_packet_context'], 'relation_context');
        requireSemantic(context.proposal_index === i, 'SEM_REFERENCE', 'relation_context', 'proposal indexes in order required');
        const relation = subject.semantics.relation_proposals[i].subject;
        const row = semanticRelationRow(subject.semantics.relation_proposals[i]);
        const problems = relationProposalProblems(model, row, true);
        requireSemantic(problems.length === 0, 'SEM_REFERENCE', 'relation proposal', problems.join('; '));
        requireSemantic(packetIds.includes(relation.source_id) || subject.output_binding.kind === 'claim'
            && relation.source_id === subject.output_binding.reserved_claim_id, 'SEM_REFERENCE', 'relation source', 'local proposal must concern this output');
        requireSemantic(relation.owner_stage === subject.owner_stage && (subject.owner_stage !== 'S2'
            || relation.source_kind === 'PKT' && relation.target_kind !== 'CC' && relation.type !== 'semantic-prerequisite'), 'SEM_REFERENCE', 'relation', 'existing source/stage bounds');
        const targets = ['PKT', 'CC'].includes(relation.target_kind) ? [unitDefinition(model, relation.target_kind, relation.target_id)] : [];
        requireSemantic(semanticJson(context.target_units) === semanticJson(targets), 'SEM_SUBJECT', 'relation_context', 'only concrete endpoints allowed');
        const targetPackets = targets.flatMap((t) => t.kind === 'PKT' ? [t.id] : t.projection.packets);
        if (subject.owner_stage === 'S3') {
            const batchPackets = new Set([...packetIds, ...subject.origin_context.flatMap((o) => outputPackets(o.output_binding))]);
            requireSemantic(targetPackets.every((id) => batchPackets.has(id)), 'SEM_REFERENCE', 'relation target', 'S3 target escapes assigned packet/origin group');
            if (relation.target_kind === 'source-locus') {
                const span = sourceSpan(model, relation.target_source_id, relation.target_locator);
                requireSemantic([...subject.anchors, ...subject.origin_context.flatMap((o) => o.anchors)].some((a) => a.source_id === relation.target_source_id && a.start_byte <= span.start && a.end_byte >= span.end), 'SEM_REFERENCE', 'relation target', 'S3 source-locus must be in explicit legal context');
            }
        }
        for (const requirement of subject.semantics.relation_proposals[i].material_use.requirements) {
            const object = material.inventory.objects.find((r) => r.object_id === requirement.object_id);
            const sourceId = material.inventory.representations.find((r) => r.representation_id === object?.representation_id)?.source_id;
            const allowedSources = new Set([...sources, ...targetPackets.map((id) => model.packets.find((p) => p.values.packetId === id).values.sourceId),
                ...(relation.target_kind === 'source-locus' ? [relation.target_source_id] : [])]);
            requireSemantic(sourceId && allowedSources.has(sourceId), 'SEM_REFERENCE', 'relation material', 'only exact proposed endpoint material allowed');
            requireSemantic(materialFeatureAvailable(material, requirement)
                || subject.semantics.relation_proposals[i].material_use.use_state === 'CANNOT_DETERMINE', 'SEM_REFERENCE', 'relation material', 'existing Slice 6 availability forbids usable unavailable material');
        }
        requireSemantic(semanticJson(context.target_packet_context) === semanticJson(semanticPacketBasis(model, [...new Set(targetPackets)])), 'SEM_SUBJECT', 'relation_context', 'target packet context differs');
        const targetLoci = relation.target_kind === 'source-locus' ? [{ source_id: relation.target_source_id, locator: relation.target_locator }]
            : context.target_packet_context.map((p) => ({ source_id: p.packet.source_id, locator: p.packet.locator }));
        requireSemantic(relation.target_kind !== 'null' || context.target_anchors.length === 0, 'SEM_REFERENCE', 'relation context', 'null targets have no target context');
        for (const [index, a] of context.target_anchors.entries()) {
            anchorShape(a, index, true);
            const span = sourceSpan(model, a.source_id, a.locator);
            requireSemantic(targetLoci.some((locus) => {
                if (locus.source_id !== a.source_id)
                    return false;
                const target = sourceSpan(model, locus.source_id, locus.locator);
                return a.start_byte >= target.start && a.end_byte <= target.end;
            }) && (subject.owner_stage !== 'S2' || sources.includes(a.source_id)), 'SEM_REFERENCE', 'relation anchor', 'only proposed concrete target context permitted');
            const input = { anchor_id: 'A1', source_id: a.source_id, locator: a.locator, start_byte: a.start_byte, end_byte: a.end_byte, exact_bytes_base64: a.exact_bytes_base64 };
            const expected = completeSemanticAnchors(model, [input], packetIds)[0];
            requireSemantic(span.start <= a.start_byte && semanticJson({ ...expected, anchor_id: a.anchor_id }) === semanticJson(a), 'SEM_EVIDENCE', a.anchor_id, 'target anchor or output packet coverage differs');
        }
        requireSemantic(relation.target_kind !== 'source-locus' || context.target_anchors.length > 0, 'SEM_REFERENCE', 'relation context', 'source-locus target requires explicit exact anchors');
    });
    validateSemanticAmbiguityContext(model, subject);
    requireSemantic(semanticJson(subject.context_manifest) === semanticJson(semanticContextManifest(model, subject)), 'SEM_SUBJECT', id, 'context manifest differs from exact selected closure');
    requireSemantic(digest === materialHash(semanticJson(subject)), 'SEM_SUBJECT', id, 'validation mutated subject');
}
function referencedBytes(model, reference) {
    const match = /^([^@]+)@(sha256:[0-9a-f]{64})$/u.exec(reference);
    requireSemantic(match, 'SEM_REFERENCE', reference, 'path@sha256 reference required');
    const bytes = readMaterialFile(model.runDir, match[1]);
    requireSemantic(materialHash(bytes) === match[2], 'SEM_SUBJECT', match[1], 'retained reference bytes changed');
    return { path: match[1], bytes };
}
export function semanticAttachmentPaths(subject) {
    const paths = [semanticSubjectPath(subject.semantic_id)];
    for (const entry of subject.material_views) {
        const view = entry.view;
        for (const asset of (view.assets || [])) {
            if (typeof asset.bytes_base64 === 'string' && typeof asset.locus === 'string')
                paths.push(asset.locus);
        }
    }
    return [...new Set(paths)].sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}
export function validateSemanticAttachmentDelivery(subject, task, attachments) {
    requireSemantic(task === SEMANTIC_TASK, 'SEM_ISOLATION', 'task', 'fixed Core sentence required');
    requireSemantic(semanticJson(attachments.map((a) => a.path)) === semanticJson(semanticAttachmentPaths(subject)), 'SEM_ISOLATION', 'attachments', 'exact sealed subject/assets only');
    for (const attachment of attachments) {
        let expected;
        if (attachment.path === semanticSubjectPath(subject.semantic_id))
            expected = Buffer.from(semanticJson(subject));
        else
            for (const entry of subject.material_views) {
                const view = entry.view;
                const asset = view.assets.find((a) => a.locus === attachment.path);
                if (asset && typeof asset.bytes_base64 === 'string')
                    expected = Buffer.from(asset.bytes_base64, 'base64');
            }
        requireSemantic(expected && expected.equals(attachment.bytes), 'SEM_ISOLATION', attachment.path, 'actual attachment bytes differ from subject');
    }
}
export function deriveSemanticExecution(model, subject, assignment, reference, producer) {
    const evidence = referencedBytes(model, reference), digest = materialHash(semanticJson(subject));
    if (evidence.path.startsWith('verification/harness/semantic-process/') && evidence.path.endsWith('.md')) {
        const record = parseStructuredVerifierRecord(evidence.bytes, evidence.path);
        requireSemantic(record.target === `semantic-review-subject:${digest}` && record.lens === 'L2S' && record.stage === subject.owner_stage, 'SEM_REVIEW', evidence.path, 'static record binding differs');
        return 'static-record';
    }
    const record = parseStrictJson(evidence.bytes);
    requireSemantic(obj(record), 'SEM_FORMAT', evidence.path, 'execution evidence object required');
    if (evidence.path.startsWith('verification/harness/semantic-process/')) {
        requireSemantic(model.manifest?.mode === 'manual', 'SEM_ISOLATION', evidence.path, 'manual evidence requires retained manual execution mode');
        keys(record, ['producer_actor', 'reviewer_actor', 'producer_pass_id', 'reviewer_pass_id', 'subject_digest', 'shown_digest', 'withheld_declaration'], 'manual evidence');
        Object.entries(record).forEach(([key, value]) => text(value, key));
        requireSemantic(record.producer_actor !== record.reviewer_actor && record.producer_pass_id !== record.reviewer_pass_id
            && record.producer_pass_id === producer.context_id && record.reviewer_pass_id === assignment.invocation_id
            && record.subject_digest === digest && record.shown_digest === digest, 'SEM_ISOLATION', evidence.path, 'distinct manual actors/passes and exact shown subject required');
        return 'manual-separate-pass';
    }
    requireSemantic(['agent', 'hybrid'].includes(model.manifest?.mode || ''), 'SEM_ISOLATION', evidence.path, 'manual evidence cannot become native or simulated dispatch');
    requireSemantic(evidence.path === `control/worker-returns/${assignment.invocation_id}/native-dispatch.json`
        && record.format === 'aleph-loa-native-worker-dispatch/v1' && obj(record.receipt), 'SEM_ISOLATION', evidence.path, 'actual retained dispatch required');
    const receipt = record.receipt;
    requireSemantic(receipt.call_id === assignment.invocation_id && typeof receipt.context_id === 'string'
        && receipt.context_id !== producer.context_id && receipt.producer_context_id === producer.context_id
        && receipt.fresh_context === true && receipt.inherited_context === false && receipt.filesystem === 'bundle-read-only', 'SEM_ISOLATION', evidence.path, 'dispatch reused producer context or lost isolation');
    requireSemantic(semanticJson(receipt.model_identity) === semanticJson(subject.reviewer_profile.model_identity), 'SEM_SUBJECT', evidence.path, 'reviewer model differs');
    const requestPath = `control/worker-bundles/${assignment.invocation_id}/request.json`;
    const request = parseStrictJson(readMaterialFile(model.runDir, requestPath));
    requireSemantic(obj(request) && request.role === 'verifier-l2s' && request.kind === 'refuter' && request.stage === subject.owner_stage
        && request.run_id === subject.run_binding.run_id && typeof request.bundle_digest === 'string'
        && Array.isArray(request.allowlist) && obj(request.isolation) && request.isolation.fresh_context === true
        && request.isolation.inherit_context === false && request.isolation.producer_context_id === producer.context_id, 'SEM_ISOLATION', requestPath, 'wrong run, role, kind, stage or context');
    requireSemantic(Array.isArray(request.core_parts) && request.core_parts.length === subject.prompt_parts.length, 'SEM_SUBJECT', requestPath, 'exact sealed prompt parts required');
    request.core_parts.forEach((part, i) => {
        const expected = subject.prompt_parts[i];
        requireSemantic(obj(part) && part.path === expected.path && part.selector === expected.selector && part.digest === expected.digest
            && typeof part.materialized_path === 'string'
            && materialHash(readMaterialFile(model.runDir, `control/worker-bundles/${assignment.invocation_id}/${part.materialized_path}`)) === expected.digest, 'SEM_SUBJECT', requestPath, 'actual delivered prompt bytes differ from sealed subject');
    });
    const returnRoot = `control/worker-returns/${assignment.invocation_id}`;
    const invocation = parseStrictJson(readMaterialFile(model.runDir, `${returnRoot}/invocation.json`));
    requireSemantic(obj(invocation) && invocation.invocation_digest === record.invocation_digest
        && materialHash(canonicalJsonBytes({ ...invocation, invocation_digest: '' })) === record.invocation_digest
        && invocation.request_digest === materialHash(canonicalJsonBytes(request))
        && semanticJson(invocation.request) === semanticJson(request) && invocation.worker_bundle_digest === request.bundle_digest
        && record.worker_bundle_digest === request.bundle_digest && invocation.inherit_context === false
        && invocation.require_fresh_context === true && invocation.require_exact_model_identity === true
        && Array.isArray(invocation.writable_paths) && invocation.writable_paths.length === 0
        && Array.isArray(invocation.readable_paths) && semanticJson(invocation.readable_paths) === semanticJson([invocation.worker_bundle_root])
        && semanticJson(invocation.simulation) === semanticJson(receipt.simulation)
        && semanticJson(invocation.model_identity) === semanticJson(receipt.model_identity), 'SEM_ISOLATION', evidence.path, 'retained sealed invocation differs from actual dispatch');
    const hostBytes = readMaterialFile(model.runDir, `${returnRoot}/host-capabilities.json`);
    requireSemantic(obj(invocation.host_capability_receipt)
        && invocation.host_capability_receipt.digest === materialHash(hostBytes)
        && record.host_capability_receipt_digest === materialHash(hostBytes), 'SEM_SUBJECT', evidence.path, 'dispatch host receipt differs');
    const attachments = request.allowlist.map((item) => {
        requireSemantic(obj(item) && typeof item.run_path === 'string' && typeof item.attachment_path === 'string', 'SEM_ISOLATION', requestPath, 'invalid delivered attachment');
        return { path: item.run_path, bytes: readMaterialFile(model.runDir, `control/worker-bundles/${assignment.invocation_id}/${item.attachment_path}`) };
    });
    validateSemanticAttachmentDelivery(subject, String(request.task_line), attachments);
    const raw = readMaterialFile(model.runDir, `control/worker-returns/${assignment.invocation_id}/raw.json`);
    const returned = parseStrictJson(raw, true);
    validateSemanticResult(returned, subject);
    const nativeReturn = readMaterialFile(model.runDir, `${returnRoot}/native-return.json`);
    requireSemantic(materialHash(nativeReturn) === record.structured_return_digest
        && semanticJson(parseStrictJson(nativeReturn, true)) === semanticJson(returned), 'SEM_SUBJECT', evidence.path, 'dispatched structured return differs from accepted raw return');
    requireSemantic(readMaterialFile(model.runDir, semanticResultPath(assignment.review_id)).equals(Buffer.from(semanticJson(returned))), 'SEM_SUBJECT', assignment.review_id, 'retained result differs from actual reviewer return');
    const validation = parseStrictJson(readMaterialFile(model.runDir, `control/worker-returns/${assignment.invocation_id}/validation.json`));
    requireSemantic(obj(validation) && validation.call_id === assignment.invocation_id && validation.result === 'PASS'
        && validation.raw_digest === materialHash(raw) && Array.isArray(validation.errors) && validation.errors.length === 0, 'SEM_REVIEW', assignment.review_id, 'actual accepted-return validation absent or mismatched');
    if (obj(receipt.simulation) && receipt.simulation.kind === 'fixture-simulated') {
        requireSemantic(record.host_evidence === null && record.event_stream_digest === null, 'SEM_ISOLATION', evidence.path, 'simulation cannot claim native host evidence');
        const state = parseStrictJson(readMaterialFile(model.runDir, 'control/run-state.json'));
        requireSemantic(obj(state) && state.full_mode === 'fixture-simulated', 'SEM_ISOLATION', evidence.path, 'simulation outside fixture mode');
        return 'fixture-simulated';
    }
    requireSemantic(receipt.simulation === null && obj(record.host_evidence) && typeof record.event_stream_digest === 'string', 'SEM_ISOLATION', evidence.path, 'missing genuine retained host evidence');
    const state = parseStrictJson(readMaterialFile(model.runDir, 'control/run-state.json'));
    requireSemantic(obj(state) && state.full_mode === 'full-aleph' && obj(receipt.model_identity)
        && receipt.model_identity.identity_kind !== 'fixture-simulated', 'SEM_ISOLATION', evidence.path, 'fixture execution cannot be relabeled native');
    const events = readMaterialFile(model.runDir, `control/worker-returns/${assignment.invocation_id}/claude-stream.jsonl`);
    requireSemantic(materialHash(events) === record.event_stream_digest && record.host_evidence.session_id === receipt.context_id, 'SEM_ISOLATION', evidence.path, 'native event stream/session differs');
    const host = parseStrictJson(hostBytes);
    requireSemantic(obj(host) && obj(host.runtime) && obj(host.runtime.claude) && obj(host.runtime.sandbox)
        && record.host_evidence.event_stream_digest === materialHash(events) && record.host_evidence.event_stream_byte_length === String(events.length)
        && record.host_evidence.observed_model === receipt.model_identity.model_id && record.host_evidence.effort === receipt.model_identity.effort
        && record.host_evidence.claude_executable_digest === host.runtime.claude.digest
        && record.host_evidence.sandbox_executable_digest === host.runtime.sandbox.digest
        && record.host_evidence.sandbox_policy_digest === host.runtime.sandbox.policy_digest
        && record.host_evidence.structured_output_digest === materialHash(canonicalJsonBytes(returned)), 'SEM_ISOLATION', evidence.path, 'native host/model/structured-output evidence differs');
    const eventRows = events.toString('utf8').split('\n').filter((line) => line.trim()).map((line) => parseStrictJson(line));
    requireSemantic(eventRows.some((event) => obj(event) && event.type === 'result' && event.session_id === receipt.context_id
        && semanticJson(event.structured_output) === semanticJson(returned)), 'SEM_ISOLATION', evidence.path, 'native terminal event does not carry the accepted result');
    return 'native-dispatch';
}
export function semanticClosureHash(model) {
    const lines = (model.runLog?.lines || []).filter((line) => /^\s*semantic_review_closure_hash:/u.test(line));
    requireSemantic(lines.length <= 1, 'SEM_WINDOW', 'C1', 'duplicate semantic closure');
    if (!lines.length)
        return null;
    const match = /^semantic_review_closure_hash: (sha256:[0-9a-f]{64})\r?$/u.exec(lines[0]);
    requireSemantic(match, 'SEM_WINDOW', 'C1', 'exact closure hash line required');
    const events = runLogEvents(model.runLog);
    const index = model.runLog.lines.indexOf(lines[0]);
    const event = events.filter((e) => e.line <= index).at(-1);
    const end = events.find((e) => e.line > index)?.line || model.runLog.lines.length + 1;
    const body = model.runLog.lines.slice((event?.line || 1) - 1, end - 1).join('\n');
    requireSemantic(event?.stage === 'S4' && /^closure_phase: S4-C1-relations-closed\r?$/mu.test(body), 'SEM_WINDOW', 'C1', 'seal must belong to retained C1 event');
    return match[1];
}
export function semanticStageSeal(ledger, stage) {
    return { format: SEMANTIC_STAGE_SEAL_FORMAT, stage,
        ...Object.fromEntries(Object.keys(SEMANTIC_HEADERS).map((key) => [key, ledger[key].map((row) => SEMANTIC_HEADERS[key].map((field) => row[field]))])) };
}
export function assertSemanticWindow(model, stage) {
    requireSemantic(hasRunCapability(model.manifest?.runFormatVersion || '', 'semantic-unit-review'), 'SEM_COMPATIBILITY', SEMANTIC_PATH, 'capability required');
    requireSemantic(['S2', 'S3', 'S4'].includes(stage) && semanticClosureHash(model) === null, 'SEM_WINDOW', stage, 'semantic write window closed');
    if (stage === 'S2' || stage === 'S3')
        requireSemantic(!runLogEvents(model.runLog).some((event) => event.stage === stage && /^(?:exit|closed|closure)\b/u.test(event.event)), 'SEM_WINDOW', stage, 'semantic stage is already sealed');
}
function validateProducerSelection(subject, returned, tuple) {
    const member = { 'packet-candidate': 'packets', 'claim-candidate': 'claims', 'no-claim-candidate': 'no_claim_packets', 'material-candidate': 'material_findings' }[tuple.output_kind];
    requireSemantic(member && Array.isArray(returned[member]), 'SEM_REFERENCE', 'producer selector', 'applicable output array required');
    const candidate = returned[member][tuple.output_index], output = subject.output_binding;
    requireSemantic(candidate, 'SEM_REFERENCE', 'producer selector', 'selected candidate absent');
    if (output.kind === 'packet-group') {
        requireSemantic(tuple.output_kind === 'packet-candidate' && candidate.evidence_state === 'exact'
            && subject.packet_basis.length > 0 && subject.packet_basis.every((p) => p.packet.source_id === returned.source_id
            && p.packet.criterion === String(candidate.criterion)), 'SEM_SUBJECT', 'packet group', 'source/criterion differs from selected candidate');
        const record = subject.packet_basis[0].evidence_record, fragments = subject.packet_basis[0].fragments;
        requireSemantic(semanticJson(output.evidence_keys) === semanticJson([record.evidence_key])
            && semanticJson(output.packet_ids) === semanticJson(fragments.map((f) => f.packet_id))
            && record.join_policy === candidate.join_policy
            && semanticJson(fragments.map((f) => ({ fragment_order: Number(f.fragment_order), locator: f.locator, exact_bytes_base64: f.exact_bytes_base64 }))) === semanticJson(candidate.fragments), 'SEM_SUBJECT', 'packet group', 'one-PKT-per-fragment candidate binding differs');
    }
    else if (output.kind === 'claim') {
        requireSemantic(tuple.output_kind === 'claim-candidate' && output.normalized_claim === candidate.normalized_claim
            && output.claim_type === candidate.claim_type && semanticJson(output.packet_ids) === semanticJson(candidate.packets), 'SEM_SUBJECT', 'claim candidate', 'selected text/type/provenance differs');
    }
    else if (output.kind === 'no-claim') {
        requireSemantic(tuple.output_kind === 'no-claim-candidate' && output.packet_id === candidate.packet && output.basis === candidate.basis, 'SEM_SUBJECT', 'no-claim candidate', 'selected packet/basis differs');
    }
    else
        requireSemantic(tuple.output_kind === 'material-candidate' && output.object_id === candidate.object_id, 'SEM_SUBJECT', 'material candidate', 'existing selected OBJ required');
    requireSemantic(semanticJson(subject.material_use) === semanticJson(output.kind === 'no-claim' ? null : candidate.material_use), 'SEM_SUBJECT', 'material_use', 'selected producer declaration differs');
}
export function validateSemanticRun(model) {
    requireSemantic(hasRunCapability(model.manifest?.runFormatVersion || '', 'semantic-unit-review'), 'SEM_COMPATIBILITY', SEMANTIC_PATH, 'capability required');
    let retainedStage = -1, retainedClosed = false;
    if (['agent', 'hybrid'].includes(model.manifest?.mode || '') && existsSync(join(model.runDir, 'control/run-state.json'))) {
        const state = parseStrictJson(readMaterialFile(model.runDir, 'control/run-state.json'));
        requireSemantic(obj(state) && obj(state.identity) && obj(state.execution)
            && state.run_id === model.manifest.runId && state.identity.run_format_version === model.manifest.runFormatVersion
            && typeof state.execution.stage === 'string' && /^S[0-9]+[ab]?$/u.test(state.execution.stage), 'SEM_STATE', 'retained execution', 'semantic stage facts must agree with retained run identity');
        retainedStage = Number.parseInt(state.execution.stage.slice(1), 10);
        retainedClosed = state.execution.stage_status === 'closed';
    }
    const events = runLogEvents(model.runLog), entered = retainedStage >= 2
        || events.some((e) => /^S(?:[2-9]|1[0-3])$/u.test(e.stage)) || model.packets.length > 0 || model.claims.length > 0 || reachedState(model, 'DISTILLING');
    if (!existsSync(join(model.runDir, SEMANTIC_PATH))) {
        requireSemantic(!entered, 'SEM_FORMAT', SEMANTIC_PATH, 'S2 requires semantic ledger');
        return { subjects: 0, assignments: 0, results: 0, pending: [], executions: [] };
    }
    const raw = readMaterialFile(model.runDir, SEMANTIC_PATH), ledger = parseSemanticLedger(raw.toString('utf8'));
    const subjects = new Map(), assignments = new Map(), results = new Map();
    const producers = new Map();
    const executions = [], pending = [], reviewerContexts = new Set();
    for (const row of ledger.subjects) {
        requireSemantic(semanticId(row.semantic_id, 'SEM') && row.subject_path === semanticSubjectPath(row.semantic_id), 'SEM_REFERENCE', row.semantic_id, 'canonical subject path required');
        const bytes = readMaterialFile(model.runDir, row.subject_path), subject = parseSemanticJson(bytes);
        validateSemanticSubject(subject, model);
        requireSemantic(row.subject_digest === materialHash(bytes) && row.semantic_id === subject.semantic_id && row.owner_stage === subject.owner_stage
            && row.subject_kind === subject.subject_kind && row.predecessor_semantic_id === subject.predecessor_semantic_id, 'SEM_SUBJECT', row.semantic_id, 'subject row differs');
        subjects.set(row.semantic_id, subject);
        const receipt = referencedBytes(model, row.producer_receipt_ref), producer = parseSemanticJson(receipt.bytes);
        keys(producer, ['call_id', 'context_id', 'raw_return_hash', 'output_kind', 'output_index'], 'producer receipt');
        requireSemantic(semanticProducerBinding(producer) === subject.producer_binding_hash, 'SEM_SUBJECT', row.semantic_id, 'producer binding differs');
        const tuple = producer;
        producers.set(row.semantic_id, tuple);
        const rawPath = receipt.path.startsWith('verification/harness/semantic-process/')
            ? `verification/harness/semantic-process/${tuple.call_id}.raw.json` : `control/worker-returns/${tuple.call_id}/raw.json`;
        const rawReturn = readMaterialFile(model.runDir, rawPath);
        requireSemantic(materialHash(rawReturn) === tuple.raw_return_hash, 'SEM_SUBJECT', row.semantic_id, 'accepted producer bytes changed');
        const returned = parseStrictJson(rawReturn, true);
        const validation = validateSemanticReturn(subject.owner_stage === 'S2' ? 'extractor' : 'normalizer', subject.run_binding.run_format_version, returned);
        requireSemantic(validation.result === 'PASS', 'SEM_FORMAT', rawPath, validation.errors.join('; '));
        if (['agent', 'hybrid'].includes(model.manifest.mode)) {
            const role = subject.owner_stage === 'S2' ? 'extractor' : 'normalizer', root = `control/worker-bundles/${tuple.call_id}`;
            const request = parseStrictJson(readMaterialFile(model.runDir, `${root}/request.json`));
            const report = parseStrictJson(readMaterialFile(model.runDir, `control/worker-returns/${tuple.call_id}/validation.json`));
            const dispatch = parseStrictJson(readMaterialFile(model.runDir, `control/worker-returns/${tuple.call_id}/native-dispatch.json`));
            requireSemantic(obj(request) && request.kind === 'producer' && request.role === role && request.stage === subject.owner_stage
                && request.run_id === subject.run_binding.run_id && Array.isArray(request.allowlist)
                && obj(report) && report.result === 'PASS' && report.call_id === tuple.call_id && report.raw_digest === tuple.raw_return_hash
                && obj(dispatch) && obj(dispatch.receipt) && dispatch.receipt.call_id === tuple.call_id && dispatch.receipt.context_id === tuple.context_id, 'SEM_ISOLATION', rawPath, 'actual producer request, accepted return and context binding required');
            const attachments = request.allowlist.map((entry) => {
                requireSemantic(obj(entry) && typeof entry.run_path === 'string' && typeof entry.attachment_path === 'string', 'SEM_ISOLATION', root, 'exact producer attachment required');
                return { path: entry.run_path, bytes: readMaterialFile(model.runDir, `${root}/${entry.attachment_path}`) };
            });
            const context = validateSemanticProducerDelivery(model, role, subject.owner_stage, tuple.call_id, String(request.task_line), attachments, true);
            const checked = validateSemanticReturn(role, subject.run_binding.run_format_version, returned, context);
            requireSemantic(checked.result === 'PASS' && checked.binding === 'checked', 'SEM_REFERENCE', rawPath, checked.errors.join('; '));
        }
        const entry = returned.semantic_units.find((e) => e.output_kind === tuple.output_kind && e.output_index === tuple.output_index);
        requireSemantic(entry && semanticJson(entry.semantics) === semanticJson(subject.semantics) && entry.review_mode === subject.review_mode
            && semanticJson(entry.origin_unit_refs) === semanticJson(subject.origin_unit_refs), 'SEM_SUBJECT', row.semantic_id, 'producer candidate differs');
        const completed = completeSemanticAnchors(model, entry.anchors, outputPackets(subject.output_binding));
        requireSemantic(semanticJson(completed) === semanticJson(subject.anchors), 'SEM_SUBJECT', row.semantic_id, 'producer anchor selection differs');
        validateProducerSelection(subject, returned, tuple);
    }
    const invocationIds = new Set();
    for (const row of ledger.assignments) {
        requireSemantic(existingId(row.review_id, 'VER') && subjects.has(row.semantic_id) && row.assignment_path === semanticAssignmentPath(row.review_id), 'SEM_REFERENCE', row.review_id, 'assignment target/path differs');
        const bytes = readMaterialFile(model.runDir, row.assignment_path), assignment = parseSemanticJson(bytes);
        keys(assignment, ['format', 'semantic_id', 'subject_digest', 'review_id', 'role', 'profile_digest', 'invocation_id', 'producer_binding_hash', 'execution_kind'], 'assignment');
        const s = subjects.get(row.semantic_id);
        requireSemantic(assignment.format === SEMANTIC_ASSIGNMENT_FORMAT && assignment.semantic_id === s.semantic_id
            && assignment.review_id === row.review_id && row.assignment_digest === materialHash(bytes)
            && assignment.subject_digest === materialHash(semanticJson(s)) && assignment.profile_digest === s.reviewer_profile.profile_digest
            && assignment.producer_binding_hash === s.producer_binding_hash, 'SEM_SUBJECT', row.review_id, 'assignment seal differs');
        requireSemantic(assignment.role === 'verifier-l2s' && !invocationIds.has(String(assignment.invocation_id)), 'SEM_ISOLATION', row.review_id, 'wrong role or reused invocation');
        text(assignment.invocation_id, 'invocation_id');
        oneOf(assignment.execution_kind, SEMANTIC_EXECUTIONS, 'execution_kind');
        invocationIds.add(assignment.invocation_id);
        assignments.set(row.review_id, assignment);
    }
    for (const row of ledger.results) {
        const assignment = assignments.get(row.review_id), subject = subjects.get(row.semantic_id);
        requireSemantic(assignment && subject && assignment.semantic_id === row.semantic_id && row.result_path === semanticResultPath(row.review_id), 'SEM_REVIEW', row.review_id, 'result without matching assignment');
        requireSemantic(existsSync(join(model.runDir, row.result_path)), 'SEM_REVIEW', row.review_id, 'assigned JSON result missing');
        const bytes = readMaterialFile(model.runDir, row.result_path), result = parseSemanticJson(bytes);
        validateSemanticResult(result, subject);
        result.unresolved_findings.forEach((finding, i) => findingShape(finding, i, semanticCoverage(subject.semantics, subject.subject_kind), subject.anchors, subject.material_use?.requirements.length || 0, model, subjectSources(subject, readRepresentationContext(model))));
        for (const finding of result.unresolved_findings.filter((f) => f.code === 'relation-deferred'))
            requireSemantic(finding.field_path === '/semantics/relation_proposals' && ['S2', 'S3'].includes(subject.owner_stage)
                && subject.semantics.relation_proposals.some((p) => p.subject.record_state === 'unresolved-target'), 'SEM_REFERENCE', finding.finding_id, 'deferred reviewer finding requires unavailable local relation target');
        requireSemantic(row.result_digest === materialHash(bytes), 'SEM_SUBJECT', row.review_id, 'result bytes changed');
        const companionPath = `verification/harness/${subject.owner_stage}/${row.review_id}.md`;
        requireSemantic(existsSync(join(model.runDir, companionPath)), 'SEM_REVIEW', row.review_id, 'VER companion missing');
        const companion = parseStructuredVerifierRecord(readMaterialFile(model.runDir, companionPath), companionPath);
        requireSemantic(companion.target === `semantic-review-subject:${assignment.subject_digest}` && companion.stage === subject.owner_stage
            && companion.lens === 'L2S' && companion.verdict === result.verdict, 'SEM_REVIEW', row.review_id, 'VER companion disagrees');
        const kind = deriveSemanticExecution(model, subject, assignment, row.execution_evidence_ref, producers.get(row.semantic_id));
        const execution = referencedBytes(model, row.execution_evidence_ref);
        const reviewContext = kind === 'native-dispatch' || kind === 'fixture-simulated'
            ? parseStrictJson(execution.bytes).receipt.context_id : assignment.invocation_id;
        requireSemantic(!reviewerContexts.has(reviewContext), 'SEM_ISOLATION', row.review_id, 'previous reviewer context reused');
        reviewerContexts.add(reviewContext);
        requireSemantic(kind === row.execution_kind && kind === assignment.execution_kind, 'SEM_ISOLATION', row.review_id, 'execution kind differs from actual retained evidence');
        requireSemantic(kind !== 'static-record' || model.files.some((f) => f.relativePath === 'README.md') && /aleph-fixture/u.test(readMaterialFile(model.runDir, 'README.md').toString('utf8')), 'SEM_ISOLATION', row.review_id, 'static record only admissible in synthetic fixture');
        requireSemantic(!['agent', 'hybrid'].includes(model.manifest.mode) || ['native-dispatch', 'fixture-simulated'].includes(kind), 'SEM_ISOLATION', row.review_id, 'static/manual evidence does not satisfy agent freshness');
        executions.push(kind);
        results.set(row.review_id, result);
    }
    for (const [id, subject] of subjects)
        for (const origin of subject.origin_context) {
            const assigned = ledger.assignments.filter((a) => a.semantic_id === origin.semantic_id);
            requireSemantic(assigned.length > 0 && assigned.every((a) => results.has(a.review_id)), 'SEM_ACCOUNTING', id, 'origin proposal has not completed its assigned reviews');
            requireSemantic(origin.owner_stage !== 'S2' || assigned.every((a) => results.get(a.review_id).verdict === 'upheld'), 'SEM_ACCOUNTING', id, 'S2 origin must have upheld review');
        }
    const resolved = new Set(), admitted = new Set();
    for (const row of ledger.resolutions) {
        const s = subjects.get(row.semantic_id);
        requireSemantic(s && semanticId(row.resolution_id, 'SMR') && !resolved.has(row.semantic_id), 'SEM_ACCOUNTING', row.semantic_id, 'unknown/duplicate resolution');
        resolved.add(row.semantic_id);
        const assigned = ledger.assignments.filter((a) => a.semantic_id === row.semantic_id).map((a) => a.review_id);
        const completed = assigned.filter((id) => results.has(id));
        requireSemantic(row.review_ids === semanticJson(completed), 'SEM_REVIEW', row.semantic_id, 'resolution must retain all completed assigned reviews in dispatch order');
        const verdicts = completed.map((id) => results.get(id).verdict), allUpheld = assigned.length > 0 && completed.length === assigned.length && verdicts.every((v) => v === 'upheld');
        const refs = parseSemanticJson(row.canonical_refs), followups = parseSemanticJson(row.followup_semantic_ids);
        requireSemantic(row.origin_unit_refs === semanticJson(s.origin_unit_refs), 'SEM_ACCOUNTING', row.semantic_id, 'origin mapping differs');
        for (const id of followups)
            requireSemantic(subjects.get(id)?.predecessor_semantic_id === row.semantic_id, 'SEM_REFERENCE', id, 'followup must link predecessor');
        oneOf(row.outcome, ['admitted', 'no-claim', 'revision-required', 'unresolved-recorded', 'not-admitted'], 'resolution outcome');
        if (['admitted', 'no-claim', 'unresolved-recorded'].includes(row.outcome))
            requireSemantic(allUpheld, 'SEM_REVIEW', row.semantic_id, 'every assigned review must be completed and upheld');
        if (row.outcome === 'admitted') {
            requireSemantic(semanticAdmissionProblems(s).length === 0, 'SEM_STATE', row.semantic_id, semanticAdmissionProblems(s).join('; '));
            const expected = s.output_binding.kind === 'claim' ? [s.output_binding.reserved_claim_id] : outputPackets(s.output_binding);
            requireSemantic(semanticJson(refs) === semanticJson(expected) && followups.length === 0 && refs.every((ref) => !admitted.has(ref)), 'SEM_ACCOUNTING', row.semantic_id, 'canonical output/reservation reused or differs');
            refs.forEach((ref) => admitted.add(ref));
            requireSemantic(refs.every((ref) => ref.startsWith('PKT-') ? model.packets.some((p) => p.values.packetId === ref) : model.claims.some((c) => c.values.claimId === ref)), 'SEM_ACCOUNTING', row.semantic_id, 'admitted canonical output absent');
            const material = readRepresentationContext(model);
            for (const view of s.material_views) {
                const use = material.uses.find((r) => r.review_subject_digest === view.use_subject_digest
                    && r.subject_id === view.use_subject.subject_id);
                requireSemantic(use, 'SEM_SUBJECT', row.semantic_id, 'canonical output requires exact existing USE');
                validateRepresentationUse(model, material, use, true);
            }
        }
        else if (row.outcome === 'no-claim') {
            requireSemantic(s.output_binding.kind === 'no-claim' && refs.length === 2 && refs[0] === s.output_binding.packet_id && followups.length === 0, 'SEM_STATE', row.semantic_id, 'no-claim needs exact PKT/LIN refs');
            const event = parseLineage(model).rows.find((r) => r.values.lineageId === refs[1])?.values;
            requireSemantic(event?.type === 'no-claim' && event.predecessors === refs[0] && event.successors === 'none', 'SEM_ACCOUNTING', row.semantic_id, 'valid no-claim lineage event required');
        }
        else {
            requireSemantic(refs.length === 0, 'SEM_STATE', row.semantic_id, 'non-admitted outcome cannot write canonical refs');
            if (row.outcome === 'unresolved-recorded')
                requireSemantic(s.review_mode === 'unresolved-record' && followups.length === 0, 'SEM_STATE', row.semantic_id, 'unresolved record required');
            if (row.outcome === 'revision-required')
                requireSemantic(followups.length > 0, 'SEM_STATE', row.semantic_id, 'linked revision required');
        }
        if (verdicts.includes('cannot-determine'))
            requireSemantic(assigned.length >= 2, 'SEM_REVIEW', row.semantic_id, 'cannot-determine requires second fresh assignment of identical subject');
    }
    const reviewed = (id) => {
        const assigned = ledger.assignments.filter((a) => a.semantic_id === id);
        return assigned.length > 0 && assigned.every((a) => results.has(a.review_id));
    };
    for (const [id] of subjects)
        if (!resolved.has(id)
            || ledger.assignments.some((a) => a.semantic_id === id && !results.has(a.review_id)))
            pending.push(id);
    const assertCandidateCoverage = (stage) => {
        for (const [id, tuple] of producers)
            if (subjects.get(id).owner_stage === stage) {
                const receipt = ledger.subjects.find((r) => r.semantic_id === id);
                const path = receipt.producer_receipt_ref.startsWith('verification/harness/semantic-process/')
                    ? `verification/harness/semantic-process/${tuple.call_id}.raw.json` : `control/worker-returns/${tuple.call_id}/raw.json`;
                const returned = parseStrictJson(readMaterialFile(model.runDir, path));
                for (const entry of returned.semantic_units)
                    requireSemantic([...producers.entries()].some(([id, p]) => p.call_id === tuple.call_id && p.context_id === tuple.context_id
                        && p.raw_return_hash === tuple.raw_return_hash && p.output_kind === entry.output_kind && p.output_index === entry.output_index && reviewed(id)), 'SEM_ACCOUNTING', path, 'emitted candidate selector has no completed L2S review');
            }
        for (const file of model.files) {
            const manual = /^verification\/harness\/semantic-process\/([^/]+)\.raw\.json$/u.exec(file.relativePath);
            const host = /^control\/worker-returns\/([^/]+)\/raw\.json$/u.exec(file.relativePath);
            if (!manual && !host)
                continue;
            if (host) {
                const reportPath = `control/worker-returns/${host[1]}/validation.json`;
                if (!existsSync(join(model.runDir, reportPath)))
                    continue; // Unaccepted quarantine is not an emitted candidate.
                const accepted = parseStrictJson(readMaterialFile(model.runDir, reportPath));
                if (accepted.result !== 'PASS')
                    continue;
                requireSemantic(accepted.raw_digest === materialHash(readMaterialFile(model.runDir, file.relativePath)), 'SEM_SUBJECT', file.relativePath, 'accepted producer raw bytes differ');
            }
            const returned = parseStrictJson(readMaterialFile(model.runDir, file.relativePath));
            if (!obj(returned) || !Array.isArray(returned.semantic_units))
                continue;
            const callId = (manual || host)[1], rawHash = materialHash(readMaterialFile(model.runDir, file.relativePath));
            const retained = [...producers.entries()].find(([, p]) => p.call_id === callId && p.raw_return_hash === rawHash);
            const producerStage = Object.hasOwn(returned, 'packets') ? 'S2'
                : Object.hasOwn(returned, 'claims') ? host
                    ? parseStrictJson(readMaterialFile(model.runDir, `control/worker-bundles/${host[1]}/request.json`)).stage
                    : retained ? subjects.get(retained[0]).owner_stage : 'S3' : null;
            if (producerStage !== stage)
                continue;
            for (const entry of returned.semantic_units)
                requireSemantic([...producers.entries()].some(([id, p]) => p.call_id === callId && p.raw_return_hash === rawHash && p.output_kind === entry.output_kind && p.output_index === entry.output_index && reviewed(id)), 'SEM_ACCOUNTING', file.relativePath, 'retained emitted producer candidate has no completed L2S review');
        }
    };
    for (const claim of model.claims)
        requireSemantic(admitted.has(claim.values.claimId), 'SEM_ACCOUNTING', claim.values.claimId, 'canonical claim lacks its exact admitted semantic subject and resolution');
    // Files are also enumerated: dropping rows cannot erase retained history.
    for (const file of model.files) {
        if (file.relativePath.startsWith('verification/harness/semantic-subjects/') && file.relativePath.endsWith('.json')) {
            const id = file.relativePath.split('/').at(-1).slice(0, -5);
            requireSemantic(subjects.has(id), 'SEM_ACCOUNTING', id, 'retained subject erased from ledger');
        }
        if (file.relativePath.startsWith('verification/harness/semantic-assignments/') && file.relativePath.endsWith('.json')) {
            const reviewId = file.relativePath.split('/').at(-1).slice(0, -5);
            requireSemantic(assignments.has(reviewId), 'SEM_ACCOUNTING', reviewId, 'retained assignment erased from ledger');
        }
        if (file.relativePath.startsWith('verification/harness/semantic-results/') && file.relativePath.endsWith('.json')) {
            const id = file.relativePath.split('/').at(-1).slice(0, -5);
            requireSemantic(results.has(id), 'SEM_ACCOUNTING', id, 'retained result erased from ledger');
        }
    }
    for (const stage of ['S2', 'S3']) {
        const exits = events.filter((e) => e.stage === stage && /^(?:exit|closed|closure)\b/u.test(e.event));
        const later = retainedStage > Number(stage.slice(1)) || retainedStage === Number(stage.slice(1)) && retainedClosed
            || [...subjects.values()].some((s) => Number(s.owner_stage.slice(1)) > Number(stage.slice(1)))
            || events.some((e) => /^S\d+$/u.test(e.stage) && Number(e.stage.slice(1)) > Number(stage.slice(1))) || reachedState(model, 'ASSEMBLED');
        requireSemantic(exits.length <= 1 && (!later || exits.length === 1), 'SEM_WINDOW', stage, 'one retained semantic stage exit required before later stage');
        if (exits.length) {
            const event = exits[0], end = events.find((e) => e.line > event.line)?.line || model.runLog.lines.length + 1;
            const body = model.runLog.lines.slice(event.line, end - 1);
            requireSemantic(body.filter((s) => s.replace(/\r$/u, '') === `semantic_stage: ${stage}`).length === 1, 'SEM_WINDOW', stage, 'semantic_stage line missing');
            const refs = body.filter((s) => s.startsWith('semantic_review_seal_ref: '));
            requireSemantic(refs.length === 1, 'SEM_WINDOW', stage, 'one stage seal ref required');
            const ref = referencedBytes(model, refs[0].slice('semantic_review_seal_ref: '.length).replace(/\r$/u, ''));
            requireSemantic(ref.path === `verification/harness/semantic-stage-seals/${stage}.json`, 'SEM_WINDOW', stage, 'canonical stage seal path required');
            const seal = parseSemanticJson(ref.bytes);
            keys(seal, ['format', 'stage', 'subjects', 'assignments', 'results', 'resolutions'], 'stage seal');
            requireSemantic(seal.format === SEMANTIC_STAGE_SEAL_FORMAT && seal.stage === stage, 'SEM_WINDOW', stage, 'stage seal identity differs');
            for (const key of Object.keys(SEMANTIC_HEADERS)) {
                array(seal[key], `seal/${key}`);
                const current = ledger[key].map((r) => SEMANTIC_HEADERS[key].map((field) => r[field]));
                requireSemantic(semanticJson(current.slice(0, seal[key].length)) === semanticJson(seal[key]), 'SEM_WINDOW', stage, 'sealed table prefix changed');
                requireSemantic(ledger[key].slice(seal[key].length).every((r) => Number(subjects.get(r.semantic_id).owner_stage.slice(1)) > Number(stage.slice(1))), 'SEM_WINDOW', stage, 'semantic record appended after its stage was sealed');
            }
            requireSemantic(!pending.some((id) => subjects.get(id).owner_stage === stage), 'SEM_ACCOUNTING', stage, 'pending candidate blocks stage exit');
            assertCandidateCoverage(stage);
        }
    }
    const closure = semanticClosureHash(model);
    if (closure !== null) {
        requireSemantic(closure === materialHash(raw) && pending.length === 0, 'SEM_WINDOW', 'C1', 'changed ledger or pending semantic obligation');
        assertCandidateCoverage('S4');
    }
    if (retainedStage >= 5 || reachedState(model, 'ASSEMBLED') || events.some((e) => /^S(?:[5-9]|1[0-3])$/u.test(e.stage)))
        requireSemantic(closure !== null, 'SEM_WINDOW', 'C1', 'later state requires C1 semantic closure');
    for (const stage of ['S2', 'S3'])
        if (events.some((e) => e.stage === stage && /^exit\b/u.test(e.event)) || closure) {
            if (stage === 'S2')
                for (const packet of model.packets)
                    requireSemantic([...subjects.values()].some((s) => s.owner_stage === 'S2'
                        && reviewed(s.semantic_id) && outputPackets(s.output_binding).includes(packet.values.packetId))
                        || parseLineage(model).rows.some((r) => r.values.predecessors.split(',').map((s) => s.trim()).includes(packet.values.packetId)), 'SEM_ACCOUNTING', packet.values.packetId, 'packet has no semantic group or lineage outcome');
            else
                for (const s of subjects.values())
                    if (s.owner_stage === 'S2' && reviewed(s.semantic_id)
                        && ledger.assignments.filter((a) => a.semantic_id === s.semantic_id).every((a) => results.get(a.review_id).verdict === 'upheld')) {
                        for (const unit of s.semantics.units)
                            requireSemantic([...subjects.values()].some((candidate) => candidate.owner_stage === 'S3'
                                && candidate.origin_unit_refs.includes(`${s.semantic_id}/${unit.unit_id}`)
                                && ledger.assignments.some((a) => a.semantic_id === candidate.semantic_id)
                                && ledger.assignments.filter((a) => a.semantic_id === candidate.semantic_id).every((a) => results.has(a.review_id))), 'SEM_ACCOUNTING', `${s.semantic_id}/${unit.unit_id}`, 'origin unit is unaccounted');
                    }
        }
    if (reachedState(model, 'ASSEMBLED')) {
        const expected = semanticFindingRows(model, ledger, subjects, results);
        const tables = parseTables(envelopeSection(model.precis?.text || '', 17)).filter((t) => t.header[0] === 'semantic_id');
        requireSemantic(tables.length === 1 && semanticJson(tables[0].header) === semanticJson(SEMANTIC_SUMMARY_HEADERS)
            && semanticJson(tables[0].rows.map((r) => r.cells.map(decoded))) === semanticJson(expected), 'SEM_ACCOUNTING', 'precis.md section 17', 'historical finding union differs');
    }
    return { subjects: subjects.size, assignments: assignments.size, results: results.size, pending, executions };
}
function semanticFindingRows(model, ledger, subjects, results) {
    const rows = [], material = readRepresentationContext(model);
    for (const [id, s] of subjects) {
        const add = (prefix, findings) => findings.forEach((f) => {
            const sources = f.anchor_ids.map((a) => s.anchors.find((anchor) => anchor.anchor_id === a).source_id);
            for (const index of f.material_requirement_indexes) {
                const req = s.material_use.requirements[index], object = material.inventory.objects.find((o) => o.object_id === req.object_id);
                sources.push(material.inventory.representations.find((r) => r.representation_id === object.representation_id).source_id);
            }
            rows.push([id, `${prefix}:${f.finding_id}`, semanticJson([...new Set(sources)].sort()), 'CANNOT_DETERMINE', materialHash(semanticJson(s))]);
        });
        add('producer', s.semantics.unresolved_findings);
        for (const row of ledger.results.filter((r) => r.semantic_id === id))
            add(row.review_id, results.get(row.review_id).unresolved_findings);
    }
    return rows.sort((a, b) => Buffer.compare(Buffer.from(a[0]), Buffer.from(b[0])) || Buffer.compare(Buffer.from(a[1]), Buffer.from(b[1])));
}
/** Returns the exact section 17 table. This function never writes or changes a Précis. */
export function semanticUnresolvedSummary(model) {
    const ledger = parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8'));
    const subjects = new Map(), results = new Map();
    for (const row of ledger.subjects) {
        const bytes = readMaterialFile(model.runDir, row.subject_path), s = parseSemanticJson(bytes);
        validateSemanticSubject(s, model);
        requireSemantic(materialHash(bytes) === row.subject_digest, 'SEM_SUBJECT', row.subject_path, 'summary subject differs');
        subjects.set(row.semantic_id, s);
    }
    for (const row of ledger.results) {
        const bytes = readMaterialFile(model.runDir, row.result_path), result = parseSemanticJson(bytes);
        requireSemantic(subjects.has(row.semantic_id) && materialHash(bytes) === row.result_digest, 'SEM_SUBJECT', row.result_path, 'summary result differs');
        validateSemanticResult(result, subjects.get(row.semantic_id));
        results.set(row.review_id, result);
    }
    return materialTableMarkdown([...SEMANTIC_SUMMARY_HEADERS], semanticFindingRows(model, ledger, subjects, results)
        .map((cells) => Object.fromEntries(SEMANTIC_SUMMARY_HEADERS.map((key, i) => [key, cells[i]]))));
}
export function buildSemanticSubject(model, input) {
    assertSemanticWindow(model, input.owner_stage);
    for (const proposal of input.semantics.relation_proposals) {
        const problems = relationProposalProblems(model, semanticRelationRow(proposal));
        requireSemantic(problems.length === 0, 'SEM_REFERENCE', 'new relation proposal', problems.join('; '));
    }
    const packetIds = outputPackets(input.output_binding);
    const subject = {
        format: SEMANTIC_SUBJECT_FORMAT, semantic_id: input.semantic_id, owner_stage: input.owner_stage, subject_kind: input.subject_kind,
        review_mode: input.review_mode, predecessor_semantic_id: input.predecessor_semantic_id, producer_binding_hash: input.producer_binding_hash,
        run_binding: semanticRunBinding(model), prompt_parts: semanticPinnedPrompts(model, input.owner_stage), reviewer_profile: input.reviewer_profile,
        output_binding: input.output_binding, origin_unit_refs: input.origin_unit_refs, origin_context: input.origin_context,
        packet_basis: semanticPacketBasis(model, packetIds), anchors: completeSemanticAnchors(model, input.anchors, packetIds),
        semantics: input.semantics, material_use: input.material_use, material_views: input.material_views,
        lineage_context: input.lineage_context, relation_context: input.relation_context, ambiguity_context: input.ambiguity_context, context_manifest: [],
    };
    subject.context_manifest = semanticContextManifest(model, subject);
    validateSemanticSubject(subject, model, new Set(), true);
    return subject;
}
export function validateSemanticAcceptedBindings(model, semanticId, operation, producer, reviews) {
    const ledger = parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8'));
    if (operation === 'seal')
        return;
    const row = ledger.subjects.find((row) => row.semantic_id === semanticId);
    requireSemantic(row, 'SEM_SUBJECT', semanticId, 'accepted return has no reservation');
    const subject = parseSemanticJson(readMaterialFile(model.runDir, row.subject_path));
    const tuple = parseSemanticJson(referencedBytes(model, row.producer_receipt_ref).bytes);
    requireSemantic(tuple.call_id === producer.call_id && tuple.context_id === producer.context_id
        && tuple.raw_return_hash === producer.raw_return_hash && producer.role === (subject.owner_stage === 'S2' ? 'extractor' : 'normalizer'), 'SEM_ISOLATION', semanticId, 'authentic producer belongs to another reservation or role');
    for (const review of reviews) {
        requireSemantic(review.context_id && review.context_id !== producer.context_id, 'SEM_ISOLATION', review.call_id, 'accepted review reused producer context');
        const raw = readMaterialFile(model.runDir, `control/worker-returns/${review.call_id}/raw.json`);
        requireSemantic(materialHash(raw) === review.raw_return_hash, 'SEM_SUBJECT', review.call_id, 'accepted reviewer bytes changed');
        if (review.role === 'verifier-l2s') {
            const result = parseStrictJson(raw, true);
            validateSemanticResult(result, subject);
            const assignment = ledger.assignments.find((row) => {
                const a = parseSemanticJson(readMaterialFile(model.runDir, row.assignment_path));
                return a.semantic_id === semanticId && a.invocation_id === review.call_id;
            });
            requireSemantic(assignment, 'SEM_REVIEW', review.call_id, 'accepted reviewer has no exact assignment');
            const retained = ledger.results.find((r) => r.review_id === assignment.review_id);
            requireSemantic(retained && readMaterialFile(model.runDir, retained.result_path).equals(Buffer.from(semanticJson(result))), 'SEM_REVIEW', review.call_id, 'accepted result differs from retained semantic result');
        }
        else
            requireSemantic(review.role === 'verifier-l2f', 'SEM_ISOLATION', review.call_id, 'unrelated review role');
    }
    if (operation === 'admit' || operation === 'record-review') {
        const relevant = ledger.assignments.filter((r) => r.semantic_id === semanticId
            && ledger.results.some((result) => result.review_id === r.review_id));
        requireSemantic(relevant.length > 0 && (operation === 'admit' ? relevant.every((r) => {
            const a = parseSemanticJson(readMaterialFile(model.runDir, r.assignment_path));
            return reviews.some((review) => review.role === 'verifier-l2s' && review.call_id === a.invocation_id);
        }) : reviews.some((review) => review.role === 'verifier-l2s')), 'SEM_ISOLATION', semanticId, 'canonical admission/result requires actual accepted L2S return bindings');
    }
    if (operation === 'admit' && subject.output_binding.kind === 'claim' && subject.material_use) {
        const material = readRepresentationContext(model);
        if (representationUseNeedsReview(material, subject.material_use)) {
            const claimId = subject.output_binding.reserved_claim_id;
            const use = material.uses.find((r) => r.subject_kind === 'CC' && r.subject_id === claimId);
            requireSemantic(use, 'SEM_ACCOUNTING', claimId, 'composed admission requires its exact material receipt');
            validateRepresentationUse(model, material, use);
            const expectedView = Buffer.from(representationReviewView(model, material, { ...use, reviewed_by: 'none' }));
            const accepted = reviews.filter((r) => r.role === 'verifier-l2f').some((r) => {
                const root = `control/worker-bundles/${r.call_id}`;
                const request = JSON.parse(readMaterialFile(model.runDir, `${root}/request.json`).toString('utf8'));
                if (request.role !== 'verifier-l2f' || request.stage !== subject.owner_stage
                    || request.allowlist?.length !== 1 || request.isolation?.producer_context_id !== producer.context_id)
                    return false;
                const attachment = request.allowlist[0];
                if (attachment.digest !== materialHash(expectedView)
                    || !readMaterialFile(model.runDir, `${root}/${attachment.attachment_path}`).equals(expectedView))
                    return false;
                const value = parseStrictJson(readMaterialFile(model.runDir, `control/worker-returns/${r.call_id}/raw.json`), true);
                assertMaterialReviewUpheld(value, use.review_subject_digest);
                return true;
            });
            requireSemantic(accepted, 'SEM_ISOLATION', claimId, 'required L2F must be an accepted independent return over this exact material view');
        }
    }
}
export function validateSemanticPlan(plan) {
    keys(plan, ['key', 'stage', 'semantic_id', 'subject_digest', 'writes', 'prerequisite_hashes'], 'semantic plan');
    const match = /^semantic:(SEM-(?=\d*[1-9])\d{4,}|none):(sha256:[0-9a-f]{64}):(reserve-subject|assign-review|record-review|resolve|admit|seal):(.+)$/u.exec(plan.key);
    requireSemantic(match && match[1] === plan.semantic_id && match[2] === plan.subject_digest && ['S2', 'S3', 'S4'].includes(plan.stage), 'SEM_STATE', 'plan', 'reservation identity differs');
    const operation = match[3], recordId = match[4];
    requireSemantic(operation === 'seal' ? plan.semantic_id === 'none' && ['S2', 'S3', 'C1'].includes(recordId)
        : semanticId(plan.semantic_id, 'SEM') && (operation === 'reserve-subject' ? recordId === plan.semantic_id
            : operation.includes('review') ? existingId(recordId, 'VER') : semanticId(recordId, 'SMR')), 'SEM_STATE', 'plan', 'operation/record ID differs');
    const allowed = {
        'reserve-subject': [SEMANTIC_PATH, semanticSubjectPath(plan.semantic_id)],
        'assign-review': [SEMANTIC_PATH, semanticAssignmentPath(recordId)],
        'record-review': [SEMANTIC_PATH, semanticResultPath(recordId), `verification/harness/${plan.stage}/${recordId}.md`],
        resolve: [SEMANTIC_PATH],
        admit: [SEMANTIC_PATH, 'ledgers/claim-inventory.md', 'ledgers/lineage.md', 'ledgers/representation-uses.md',
            ...(plan.stage === 'S4' ? ['ledgers/merge-map.md'] : [])],
        seal: ['run-log.md', `verification/harness/semantic-stage-seals/${recordId}.json`],
    };
    requireSemantic(plan.writes.length > 0 && new Set(plan.writes.map((w) => w.path)).size === plan.writes.length, 'SEM_STATE', plan.key, 'nonempty unique writes required');
    for (const write of plan.writes) {
        keys(write, ['path', 'before_hash', 'after_base64', 'after_hash'], 'write');
        requireSemantic(allowed[operation].includes(write.path), 'SEM_WINDOW', write.path, 'outside bounded semantic operation');
        hash(write.before_hash, 'before_hash');
        hash(write.after_hash, 'after_hash');
        const bytes = Buffer.from(write.after_base64, 'base64');
        requireSemantic(bytes.toString('base64') === write.after_base64 && materialHash(bytes) === write.after_hash, 'SEM_SUBJECT', write.path, 'after-image differs');
        if (write.path.startsWith('verification/'))
            requireSemantic(write.before_hash === materialHash(Buffer.alloc(0)) || write.before_hash === write.after_hash, 'SEM_STATE', write.path, 'immutable record cannot be rewritten');
    }
    let previous = '';
    for (const prerequisite of plan.prerequisite_hashes) {
        keys(prerequisite, ['path', 'digest'], 'prerequisite');
        hash(prerequisite.digest, 'prerequisite digest');
        requireSemantic(Buffer.compare(Buffer.from(previous), Buffer.from(prerequisite.path)) < 0, 'SEM_REFERENCE', prerequisite.path, 'sorted unique prerequisite paths required');
        previous = prerequisite.path;
    }
}
export function validateCompletedSemanticPlan(model, plan) {
    validateSemanticPlan(plan);
    validateSemanticRun(model);
    for (const write of plan.writes) {
        const bytes = readMaterialFile(model.runDir, write.path), after = Buffer.from(write.after_base64, 'base64');
        if (write.path === SEMANTIC_PATH) {
            const historical = parseSemanticLedger(after.toString('utf8')), current = parseSemanticLedger(bytes.toString('utf8'));
            for (const table of Object.keys(SEMANTIC_HEADERS))
                requireSemantic(semanticJson(current[table].slice(0, historical[table].length)) === semanticJson(historical[table]), 'SEM_STATE', write.path, 'committed semantic history changed');
        }
        else if (write.path === 'ledgers/claim-inventory.md') {
            // Later S5 disposition fields are excluded from SemanticSubject. Current
            // K2.19 above reopens admitted immutable text/type/provenance bindings.
            const ids = parseTables(after.toString('utf8')).filter((t) => t.header[0] === 'claim_id').flatMap((t) => t.rows.map((r) => r.cells[0]));
            requireSemantic(ids.every((id) => model.claims.some((c) => c.values.claimId === id)), 'SEM_STATE', write.path, 'committed claim erased');
        }
        else
            requireSemantic(write.path.startsWith('verification/') ? bytes.equals(after) : bytes.subarray(0, after.length).equals(after), 'SEM_STATE', write.path, 'committed bytes/prefix changed');
    }
}
export function planSemanticWrite(options) {
    const { model, stage, semantic_id, subject_digest, operation, record_id, writes } = options;
    assertSemanticWindow(model, stage);
    const writtenPaths = new Set(writes.map((write) => write.path));
    const requiredPrerequisites = model.files.map((file) => file.relativePath).filter((path) => !writtenPaths.has(path) && (['run-manifest.md', 'run-log.md', 'ledgers/semantic-review.md', 'ledgers/packet-index.md',
        'ledgers/claim-inventory.md', 'ledgers/lineage.md', 'ledgers/representation-uses.md', 'ledgers/source-walk.md',
        'ledgers/extraction-criteria.md'].includes(path) || path.startsWith('corpus/')
        || path.startsWith('verification/harness/semantic-') || /^verification\/harness\/S[234]\//u.test(path)
        || path.startsWith('control/runtime/') || path.startsWith('control/worker-returns/') || path.startsWith('control/worker-bundles/')));
    const plan = {
        key: `semantic:${semantic_id}:${subject_digest}:${operation}:${record_id}`, stage, semantic_id, subject_digest, writes,
        prerequisite_hashes: [...new Set([...requiredPrerequisites, ...options.prerequisite_paths])].filter((path) => !writtenPaths.has(path)).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)))
            .map((path) => ({ path, digest: materialHash(readMaterialFile(model.runDir, path)) })),
    };
    validateSemanticPlan(plan);
    for (const write of writes) {
        const before = existsSync(join(model.runDir, write.path)) ? readMaterialFile(model.runDir, write.path) : Buffer.alloc(0);
        requireSemantic(write.before_hash === materialHash(before), 'SEM_STATE', write.path, 'write preimage differs');
        requireSemantic(readMaterialFile(options.proposedModel.runDir, write.path).toString('base64') === write.after_base64, 'SEM_SUBJECT', write.path, 'proposed after-image differs');
        if (operation === 'admit' && ['ledgers/claim-inventory.md', 'ledgers/lineage.md', 'ledgers/merge-map.md', 'ledgers/representation-uses.md'].includes(write.path)) {
            const oldTables = parseTables(before.toString('utf8')), newTables = parseTables(Buffer.from(write.after_base64, 'base64').toString('utf8'));
            for (const table of oldTables) {
                const same = newTables.find((t) => semanticJson(t.header) === semanticJson(table.header));
                requireSemantic(same && semanticJson(same.rows.slice(0, table.rows.length).map((r) => r.cells))
                    === semanticJson(table.rows.map((r) => r.cells)), 'SEM_STATE', write.path, 'admission cannot rewrite existing canonical rows');
            }
        }
    }
    const before = existsSync(join(model.runDir, SEMANTIC_PATH)) ? parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8')) : emptySemanticLedger();
    const after = parseSemanticLedger(readMaterialFile(options.proposedModel.runDir, SEMANTIC_PATH).toString('utf8'));
    const addedTable = { 'reserve-subject': 'subjects', 'assign-review': 'assignments', 'record-review': 'results', resolve: 'resolutions', admit: 'resolutions', seal: 'none' }[operation];
    for (const key of Object.keys(SEMANTIC_HEADERS)) {
        requireSemantic(semanticJson(before[key]) === semanticJson(after[key].slice(0, before[key].length)), 'SEM_STATE', key, 'semantic history cannot be erased or replaced');
        const added = after[key].slice(before[key].length);
        requireSemantic(added.length === (key === addedTable ? 1 : 0), 'SEM_STATE', key, 'operation must append exactly its declared record');
        if (added.length)
            requireSemantic(added[0].semantic_id === semantic_id && added[0][SEMANTIC_HEADERS[key][0]] === record_id, 'SEM_STATE', key, 'operation targets another reservation/record');
    }
    if (operation !== 'seal') {
        const row = after.subjects.find((row) => row.semantic_id === semantic_id);
        requireSemantic(row?.subject_digest === subject_digest && row.owner_stage === stage, 'SEM_SUBJECT', semantic_id, 'plan subject/stage differs from sealed reservation');
        if (operation === 'reserve-subject' || operation === 'admit') {
            validateSemanticSubject(parseSemanticJson(readMaterialFile(options.proposedModel.runDir, row.subject_path)), options.proposedModel, new Set(), true);
        }
        if (operation === 'admit' || operation === 'resolve') {
            const resolution = after.resolutions.at(-1);
            requireSemantic(operation === 'admit' ? ['admitted', 'no-claim'].includes(resolution.outcome)
                : !['admitted', 'no-claim'].includes(resolution.outcome), 'SEM_STATE', 'operation', 'canonical outcome requires composed admission');
        }
    }
    else {
        requireSemantic(stage === (record_id === 'C1' ? 'S4' : record_id), 'SEM_WINDOW', 'seal', 'seal stage differs');
        const bytes = readMaterialFile(options.proposedModel.runDir, record_id === 'C1' ? SEMANTIC_PATH : `verification/harness/semantic-stage-seals/${record_id}.json`);
        requireSemantic(materialHash(bytes) === subject_digest, 'SEM_SUBJECT', 'seal', 'seal plan digest differs');
    }
    validateSemanticRun(options.proposedModel);
    if (operation === 'admit' || operation === 'seal') {
        const checks = new ResultCollector(options.proposedModel.manifest?.runId || 'semantic-plan');
        runK2Lineage(checks, options.proposedModel);
        requireSemantic(checks.checks.every((c) => c.status !== 'FAIL'), 'SEM_ACCOUNTING', 'lineage prerequisites', checks.checks.filter((c) => c.status === 'FAIL').map((c) => c.message).join('; '));
    }
    return plan;
}
// Predecessor members are retained verbatim; 1.7 adds only semantic_units.
const SEMANTIC_PRODUCER_BASE_EXEMPLARS = {
    "extractor": {
        "source_id": "",
        "producer_invocation_id": "",
        "walk_intervals": [
            {
                "start_byte": 0,
                "end_byte": 0,
                "outcome": "admitted|no-candidate-observed|excluded|deferred|unsupported",
                "packet_candidate_indexes": [
                    0
                ],
                "criterion_ref": "admission:<n>|exclusion:<class>|none",
                "closure_state": "closed|open|resolved",
                "reason": null,
                "closure_note": null
            }
        ],
        "packets": [
            {
                "evidence_state": "exact|degraded-non-exact",
                "join_policy": "single-fragment|adjacent-fragments|separate-fragments|not-applicable",
                "fragments": [
                    {
                        "fragment_order": 1,
                        "locator": "",
                        "exact_bytes_base64": ""
                    }
                ],
                "rendered_text": "",
                "degraded_source_locator": null,
                "degradation_reason": null,
                "criterion": 0,
                "flags": [],
                "material_use": {
                    "requirements": [
                        {
                            "object_id": "OBJ-…",
                            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                            "binding_ids": [
                                "BND-…"
                            ]
                        }
                    ],
                    "use_state": "usable|CANNOT_DETERMINE",
                    "fidelity_claim": "none|exact-representation|gold",
                    "limitation_refs": [],
                    "reason": ""
                }
            }
        ],
        "extraction_events": [
            {
                "start_byte": 0,
                "end_byte": 0,
                "shared_position_key": "",
                "event_ordinal": 1,
                "packet_candidate_index": 0,
                "origin": "primary"
            }
        ],
        "next_cursor": {
            "byte_offset": 0,
            "shared_position_key": null,
            "next_event_ordinal": null,
            "predecessor_walk_index": null,
            "predecessor_event_index": null,
            "source_hash": "",
            "reason": "initial|progress|bounded-pause|resumed-shared-position|source-complete"
        },
        "walk_exhausted": false,
        "notes": [],
        "material_findings": [
            {
                "object_id": "OBJ-…",
                "material_use": {
                    "requirements": [
                        {
                            "object_id": "OBJ-…",
                            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                            "binding_ids": [
                                "BND-…"
                            ]
                        }
                    ],
                    "use_state": "usable|CANNOT_DETERMINE",
                    "fidelity_claim": "none|exact-representation|gold",
                    "limitation_refs": [],
                    "reason": ""
                }
            }
        ]
    },
    "normalizer": {
        "claims": [
            {
                "normalized_claim": "",
                "packets": [
                    "PKT-…"
                ],
                "claim_type": "",
                "widen_requests": [
                    {
                        "packet": "",
                        "new_locator": ""
                    }
                ],
                "rationale": "",
                "flags": [],
                "material_use": {
                    "requirements": [
                        {
                            "object_id": "OBJ-…",
                            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                            "binding_ids": [
                                "BND-…"
                            ]
                        }
                    ],
                    "use_state": "usable|CANNOT_DETERMINE",
                    "fidelity_claim": "none|exact-representation|gold",
                    "limitation_refs": [],
                    "reason": ""
                }
            }
        ],
        "no_claim_packets": [
            {
                "packet": "PKT-…",
                "basis": ""
            }
        ],
        "lineage_proposals": [
            {
                "type": "split|replace|supersede|reject|exclude",
                "predecessors": [
                    "PKT-…|CC-…"
                ],
                "successor_specs": [],
                "basis": ""
            }
        ],
        "material_findings": [
            {
                "object_id": "OBJ-…",
                "material_use": {
                    "requirements": [
                        {
                            "object_id": "OBJ-…",
                            "feature": "text-bytes|table-grid|header-association|caption-association|formal-structure|image|chart-values|spatial-region",
                            "binding_ids": [
                                "BND-…"
                            ]
                        }
                    ],
                    "use_state": "usable|CANNOT_DETERMINE",
                    "fidelity_claim": "none|exact-representation|gold",
                    "limitation_refs": [],
                    "reason": ""
                }
            }
        ]
    }
};
function semanticFindingExemplar() {
    return { finding_id: 'F1', field_path: '/semantics/atomicity', code: FINDING_CODES.join('|'), anchor_ids: ['A1'],
        material_requirement_indexes: [0], unknown_dimension: ['none', ...SEMANTIC_FACETS.scope, 'comparison-dimension', 'measurement-unit'].join('|'),
        missing: '', requested_context: [{ source_id: 'SRC-…', locator: '', purpose: 'local-context|same-source-referent-search|material-inspection' }] };
}
function semanticSemanticsExemplar() {
    const unit = { unit_id: 'U1', proposition: '', proposition_anchor_ids: ['A1'] };
    for (const [name, kinds] of Object.entries(SEMANTIC_FACETS)) {
        const item = { kind: kinds.join('|'), source_text: '' };
        if (name === 'attribution')
            item.attributed_to = '';
        if (name === 'comparator')
            Object.assign(item, { subject_anchor_ids: ['A1'], baseline_anchor_ids: ['A1'], dimension_anchor_ids: ['A1'] });
        if (name === 'metric')
            Object.assign(item, { quantity_anchor_ids: ['A1'], value_anchor_ids: ['A1'], unit_anchor_ids: ['A1'] });
        item.anchor_ids = ['A1'];
        unit[name] = { state: 'present|not-expressed|CANNOT_DETERMINE', items: [item], basis_anchor_ids: ['A1'] };
    }
    return { atomicity: ATOMICITIES.join('|'), units: [unit],
        contexts: [{ context_id: 'C1', kind: CONTEXT_KINDS.join('|'), applies_to_unit_ids: ['U1'], anchor_ids: ['A1'], material_requirement_indexes: [0], use: CONTEXT_USES.join('|') }],
        couplings: [{ kind: COUPLING_KINDS.join('|'), unit_ids: ['U1'], anchor_ids: ['A1'], treatment: 'keep-distinguishable|keep-together|CANNOT_DETERMINE' }],
        relation_proposals: [{ subject: { format: 'aleph-relation-review-subject/v1', owner_stage: 'S2|S3|S4', family: [...RELATION_FAMILIES, 'none'].join('|'),
                    type: [...RELATION_TYPES, 'none'].join('|'), source_kind: 'PKT|CC', source_id: '', target_kind: 'PKT|CC|source-locus|null', target_id: '',
                    target_source_id: '', target_locator: '', target_span_hash: '', record_state: RELATION_RECORD_STATES.join('|'), null_reason: '', basis_packet_ids: ['PKT-…'], proposed_by: '' },
                review_subject_digest: '', material_use: SEMANTIC_PRODUCER_BASE_EXEMPLARS.normalizer.claims[0].material_use }],
        unresolved_findings: [semanticFindingExemplar()] };
}
export function semanticReturnExemplar(role) {
    if (role === 'verifier-l2s')
        return {
            format: SEMANTIC_RESULT_FORMAT, subject_digest: '', verdict: 'upheld|refuted|cannot-determine',
            field_reviews: [{ field_path: '', verdict: 'upheld|refuted|cannot-determine', issue: SEMANTIC_ISSUES.join('|'), anchor_ids: ['A1'], material_requirement_indexes: [0], explanation: '' }],
            unresolved_findings: [semanticFindingExemplar()], attacks_tried: [''], missing_for_determination: null, rationale: '', candidate_evidence: [],
        };
    return { ...SEMANTIC_PRODUCER_BASE_EXEMPLARS[role],
        semantic_units: [{ output_kind: (role === 'extractor' ? ['packet-candidate', 'material-candidate'] : ['claim-candidate', 'no-claim-candidate', 'material-candidate']).join('|'),
                output_index: 0, review_mode: 'proposal|unresolved-record', origin_unit_refs: ['SEM-0001/U1'],
                anchors: [{ anchor_id: 'A1', source_id: 'SRC-…', locator: '', start_byte: 0, end_byte: 1, exact_bytes_base64: '' }],
                semantics: semanticSemanticsExemplar() }] };
}
export function semanticOutputContract(role) {
    return { contract_format: SEMANTIC_CONTRACT_FORMAT, capability: 'semantic-unit-review', role, shape: semanticReturnExemplar(role) };
}
export function isSemanticOutputContract(value) { return obj(value) && value.contract_format === SEMANTIC_CONTRACT_FORMAT; }
export function validateSemanticOutputContract(value) {
    keys(value, ['contract_format', 'capability', 'role', 'shape'], 'semantic output contract');
    oneOf(value.role, ['extractor', 'normalizer', 'verifier-l2s'], 'contract role');
    requireSemantic(value.contract_format === SEMANTIC_CONTRACT_FORMAT && value.capability === 'semantic-unit-review'
        && semanticJson(value.shape) === semanticJson(semanticReturnExemplar(value.role)), 'SEM_FORMAT', 'output contract', 'descriptor differs from complete Core contract');
    return value.role;
}
function closed(properties) {
    return { type: 'object', additionalProperties: false, required: Object.keys(properties), properties };
}
function items(schema, minItems = 0) { return { type: 'array', items: schema, minItems }; }
function strings(pattern) { return { type: 'string', minLength: 1, ...(pattern ? { pattern } : {}) }; }
function enumeration(values) { return { type: 'string', enum: [...values] }; }
export function semanticReturnJsonSchema(role, runFormatVersion) {
    requireSemantic(hasRunCapability(runFormatVersion, 'semantic-unit-review'), 'SEM_COMPATIBILITY', 'schema', 'pinned semantic capability required');
    const idArray = items(strings('^A[1-9][0-9]*$')), index = { type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER };
    const indexes = items(index), string = strings(), sha = strings('^sha256:[0-9a-f]{64}$');
    const finding = closed({ finding_id: strings('^F[1-9][0-9]*$'), field_path: string, code: enumeration(FINDING_CODES),
        anchor_ids: idArray, material_requirement_indexes: indexes,
        unknown_dimension: enumeration(['none', ...SEMANTIC_FACETS.scope, 'comparison-dimension', 'measurement-unit']), missing: string,
        requested_context: items(closed({ source_id: strings('^SRC-[0-9]+$'), locator: strings('^L[1-9][0-9]*-L[1-9][0-9]*$'),
            purpose: enumeration(['local-context', 'same-source-referent-search', 'material-inspection']) })) });
    if (role === 'verifier-l2s')
        return closed({
            format: { const: SEMANTIC_RESULT_FORMAT }, subject_digest: sha, verdict: enumeration(['upheld', 'refuted', 'cannot-determine']),
            field_reviews: items(closed({ field_path: string, verdict: enumeration(['upheld', 'refuted', 'cannot-determine']), issue: enumeration(SEMANTIC_ISSUES),
                anchor_ids: idArray, material_requirement_indexes: indexes, explanation: string }), 6),
            unresolved_findings: items(finding), attacks_tried: items(string, 1),
            missing_for_determination: { anyOf: [{ type: 'null' }, string] }, rationale: string, candidate_evidence: { type: 'array', items: false, maxItems: 0 },
        });
    const unit = { unit_id: strings('^U[1-9][0-9]*$'), proposition: string, proposition_anchor_ids: { ...idArray, minItems: 1 } };
    for (const [name, kinds] of Object.entries(SEMANTIC_FACETS)) {
        const fields = { kind: enumeration(kinds), source_text: string };
        if (name === 'attribution')
            fields.attributed_to = string;
        if (name === 'comparator')
            Object.assign(fields, { subject_anchor_ids: { ...idArray, minItems: 1 }, baseline_anchor_ids: { ...idArray, minItems: 1 }, dimension_anchor_ids: idArray });
        if (name === 'metric')
            Object.assign(fields, { quantity_anchor_ids: { ...idArray, minItems: 1 }, value_anchor_ids: { ...idArray, minItems: 1 }, unit_anchor_ids: idArray });
        fields.anchor_ids = { ...idArray, minItems: 1 };
        unit[name] = { anyOf: [
                closed({ state: { const: 'present' }, items: items(closed(fields), 1), basis_anchor_ids: { ...idArray, minItems: 1 } }),
                closed({ state: enumeration(name === 'claim_roles' ? ['CANNOT_DETERMINE'] : ['not-expressed', 'CANNOT_DETERMINE']),
                    items: { type: 'array', items: false, maxItems: 0 }, basis_anchor_ids: { ...idArray, minItems: 1 } }),
            ] };
    }
    const exemplar = semanticSemanticsExemplar();
    const semantics = closed({ atomicity: enumeration(ATOMICITIES), units: items(closed(unit)),
        contexts: items(closed({ context_id: strings('^C[1-9][0-9]*$'), kind: enumeration(CONTEXT_KINDS),
            applies_to_unit_ids: items(strings('^U[1-9][0-9]*$'), 1), anchor_ids: idArray, material_requirement_indexes: indexes, use: enumeration(CONTEXT_USES) })),
        couplings: items(closed({ kind: enumeration(COUPLING_KINDS), unit_ids: items(strings('^U[1-9][0-9]*$'), 1),
            anchor_ids: { ...idArray, minItems: 1 }, treatment: enumeration(['keep-distinguishable', 'keep-together', 'CANNOT_DETERMINE']) })),
        relation_proposals: contractExemplarToJsonSchema(exemplar.relation_proposals), unresolved_findings: items(finding) });
    const base = contractExemplarToJsonSchema(SEMANTIC_PRODUCER_BASE_EXEMPLARS[role]);
    if (role === 'extractor') {
        const properties = base.properties;
        const cursor = properties.next_cursor.properties;
        for (const field of ['next_event_ordinal', 'predecessor_walk_index', 'predecessor_event_index']) {
            cursor[field] = { anyOf: [{ ...index, minimum: field === 'next_event_ordinal' ? 1 : 0 }, { type: 'null' }] };
        }
        const walk = properties.walk_intervals.items.properties;
        walk.criterion_ref = strings('^(admission:[1-9][0-9]*|exclusion:[a-z][a-z0-9-]*|none)$');
    }
    base.required.push('semantic_units');
    base.properties.semantic_units = items(closed({
        output_kind: enumeration(role === 'extractor' ? ['packet-candidate', 'material-candidate'] : ['claim-candidate', 'no-claim-candidate', 'material-candidate']),
        output_index: index, review_mode: enumeration(['proposal', 'unresolved-record']), origin_unit_refs: items(strings('^SEM-(?=[0-9]*[1-9])[0-9]{4,}/U[1-9][0-9]*$')),
        anchors: items(closed({ anchor_id: strings('^A[1-9][0-9]*$'), source_id: strings('^SRC-[0-9]+$'), locator: strings('^L[1-9][0-9]*-L[1-9][0-9]*$'),
            start_byte: index, end_byte: index, exact_bytes_base64: string })), semantics,
    }));
    return base;
}
export function semanticProducerViewPaths(callId) {
    requireSemantic(/^[A-Za-z0-9_-]+$/u.test(callId), 'SEM_REFERENCE', 'producer call', 'existing call identifier required');
    return { selections: `control/semantic-producer-context/${callId}.json`,
        view: `verification/harness/semantic-producer-views/${callId}.md` };
}
export function semanticProducerTask(role, stage, referentSearch = false) {
    return referentSearch ? 'Search only the one retained expression in the attached frozen source under the existing Slice 5 bounded search rules. Return a revised semantic proposal or finding.'
        : stage === 'S4' ? 'Express only the already-proposed successor in the attached bounded semantic context.'
            : role === 'extractor' ? 'Extract exact packets and structured semantics from only the attached bounded source context.'
                : 'Normalize only the assigned packet group and named source windows in the attached bounded semantic context.';
}
export function semanticRequiresWritePlan(model, path) {
    return hasRunCapability(model.manifest?.runFormatVersion || '', 'semantic-unit-review')
        && (path === SEMANTIC_PATH || path === 'ledgers/claim-inventory.md'
            || /^verification\/harness\/semantic-(?:subjects|assignments|results|stage-seals)\//u.test(path));
}
function semanticSelectedBytes(model, entry) {
    const bytes = readMaterialFile(model.runDir, entry.path), selector = entry.selector;
    if (selector.startsWith('bytes:')) {
        const match = /^bytes:(0|[1-9]\d*):(0|[1-9]\d*)$/u.exec(selector);
        requireSemantic(match && ordinal(Number(match[1])) && ordinal(Number(match[2])) && Number(match[1]) < Number(match[2])
            && Number(match[2]) <= bytes.length, 'SEM_REFERENCE', entry.path, 'exact nonempty byte selection required');
        return bytes.subarray(Number(match[1]), Number(match[2]));
    }
    if (selector.startsWith('json:')) {
        return Buffer.from(semanticJson(selectedSemanticReference(model, `${entry.path}#${selector.slice(5)}@${materialHash(bytes)}`).value));
    }
    const match = /^row:(.+):(0|[1-9]\d*)$/u.exec(selector), lines = bytes.toString('utf8').split('\n');
    requireSemantic(match, 'SEM_REFERENCE', selector, 'existing exact run-data selector required');
    const tables = parseTables(bytes.toString('utf8')).filter((table) => lines.slice(0, table.line - 1).reverse().find((line) => /^#{1,6} /u.test(line))?.replace(/^#{1,6} /u, '').replace(/\r$/u, '') === match[1]);
    requireSemantic(tables.length === 1 && tables[0].rows[Number(match[2])], 'SEM_REFERENCE', selector, 'unique literal table and row required');
    return Buffer.from(semanticJson(tables[0].rows[Number(match[2])].cells.map(decoded)));
}
function semanticProducerSearch(model, selections) {
    const selected = selections.filter((entry) => entry.purpose === 'ambiguity-context');
    if (selected.length === 0)
        return;
    requireSemantic(selected.length === 2, 'SEM_ISOLATION', 'referent search', 'one selected request and one exact Slice 5 working search basis required');
    const request = selected.find((entry) => /^verification\/harness\/semantic-(subjects|results)\/(?:SEM|VER)-\d{4,}\.json$/u.test(entry.path)
        && /^json:\/(?:semantics\/)?unresolved_findings\/(?:0|[1-9]\d*)$/u.test(entry.selector));
    const working = selected.find((entry) => entry !== request);
    requireSemantic(request && working && /^verification\/harness\/semantic-process\/[^/]+\.json$/u.test(working.path)
        && working.selector === 'json:', 'SEM_ISOLATION', 'referent search', 'only exact retained request and working subject projections allowed');
    const ledger = parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8'));
    const id = request.path.includes('/semantic-results/')
        ? ledger.results.find((r) => r.result_path === request.path)?.semantic_id
        : ledger.subjects.find((r) => r.subject_path === request.path)?.semantic_id;
    const row = ledger.subjects.find((r) => r.semantic_id === id);
    requireSemantic(row, 'SEM_REFERENCE', request.path, 'request must belong to retained semantic history');
    const prior = parseSemanticJson(readMaterialFile(model.runDir, row.subject_path));
    validateSemanticSubject(prior, model);
    const finding = parseSemanticJson(semanticSelectedBytes(model, request));
    findingShape(finding, Number(finding.finding_id.slice(1)) - 1, semanticCoverage(prior.semantics, prior.subject_kind), prior.anchors, prior.material_use?.requirements.length || 0, model, subjectSources(prior, readRepresentationContext(model)));
    const a = parseSemanticJson(semanticSelectedBytes(model, working));
    requireSemantic(a.search_scope_kind === 'full-same-source' && finding.code === 'referent-unresolved'
        && finding.requested_context.some((r) => r.purpose === 'same-source-referent-search' && r.source_id === a.source_id)
        && finding.anchor_ids.some((id) => prior.anchors.some((anchor) => anchor.anchor_id === id && anchor.source_id === a.source_id
            && anchor.start_byte <= a.expression_start_byte && anchor.end_byte >= a.expression_end_byte)), 'SEM_REFERENCE', 'referent search', 'one requested expression and full same-source basis required');
    const source = sourceSpan(model, a.source_id, a.expression_locator);
    const lineCount = source.source.toString('utf8').split('\n').length - (source.source.at(-1) === 10 ? 1 : 0);
    const whole = sourceSpan(model, a.source_id, `L1-L${lineCount}`);
    const anchor = completeSemanticAnchors(model, [{ anchor_id: 'A1', source_id: a.source_id, locator: `L1-L${lineCount}`,
            start_byte: whole.start, end_byte: whole.end, exact_bytes_base64: whole.bytes.toString('base64') }], outputPackets(prior.output_binding))[0];
    validateSemanticWorkingAmbiguity(model, { ...prior, anchors: [...prior.anchors, anchor] }, a);
    return a;
}
/**
 * Producer transport uses the already-adopted context-manifest selectors.
 * The recipe is retained outside the worker; only this exact Core projection
 * is delivered. It carries no new semantic fields or authority choices.
 */
export function semanticProducerView(model, role, stage, selections, retained = false) {
    requireSemantic(hasRunCapability(model.manifest?.runFormatVersion || '', 'semantic-unit-review')
        && (role === 'extractor' ? stage === 'S2' : stage === 'S3' || stage === 'S4'), 'SEM_WINDOW', role, 'legal semantic producer stage required');
    const sourcePaths = new Map(model.corpus.sources.map((s) => {
        const path = sourceFilePath(model.runDir, s.values.locus);
        requireSemantic(path, 'SEM_REFERENCE', s.values.sourceId, 'frozen source path required');
        return [relative(model.runDir, path).replaceAll('\\', '/'), s.values.sourceId];
    }));
    const context = { model, owner_stage: stage, legal_source_ids: [], source_windows: [], packet_ids: [], origin_unit_refs: [] };
    context.referent_search = semanticProducerSearch(model, selections);
    const selected = [];
    const origins = new Map(), lineageFiles = new Set();
    const assets = new Map();
    let previous = '';
    for (const entry of selections) {
        keys(entry, ['path', 'selector', 'digest', 'purpose'], 'producer context selection');
        const order = `${entry.path}\0${entry.selector}`;
        requireSemantic(Buffer.compare(Buffer.from(previous), Buffer.from(order)) < 0, 'SEM_REFERENCE', entry.path, 'sorted unique exact selections required');
        previous = order;
        const bytes = semanticSelectedBytes(model, entry);
        requireSemantic(materialHash(bytes) === entry.digest, 'SEM_SUBJECT', entry.path, 'selected producer context changed');
        if (entry.purpose === 'ambiguity-context') {
            requireSemantic(context.referent_search, 'SEM_ISOLATION', entry.path, 'dedicated search required');
        }
        else if (sourcePaths.has(entry.path)) {
            requireSemantic(entry.selector.startsWith('bytes:') && ['packet-evidence', 'inspection-context'].includes(entry.purpose), 'SEM_ISOLATION', entry.path, 'exact source window required');
            const [, start, end] = entry.selector.split(':');
            context.source_windows.push({ source_id: sourcePaths.get(entry.path), start_byte: Number(start), end_byte: Number(end) });
            try {
                new TextDecoder('utf-8', { fatal: true }).decode(bytes);
            }
            catch {
                throw new SemanticError('SEM_EVIDENCE', entry.path, 'source window splits UTF-8');
            }
        }
        else if (entry.path === 'ledgers/extraction-criteria.md') {
            requireSemantic(entry.selector === `bytes:0:${readMaterialFile(model.runDir, entry.path).length}`, 'SEM_ISOLATION', entry.path, 'exact S1 criteria required');
        }
        else if (entry.path === 'corpus/manifest.md' || entry.path === 'ledgers/source-walk.md') {
            requireSemantic((role === 'extractor' || context.referent_search && entry.path === 'ledgers/source-walk.md')
                && entry.selector.startsWith('row:'), 'SEM_ISOLATION', entry.path, 'only source-local walk/completion rows allowed');
        }
        else if (entry.path === 'corpus/representations.md') {
            requireSemantic(role === 'extractor' && entry.selector.startsWith('row:'), 'SEM_ISOLATION', entry.path, 'only source-local material rows allowed');
        }
        else if (/^verification\/harness\/semantic-subjects\/SEM-\d{4,}\.json$/u.test(entry.path)) {
            requireSemantic(role === 'normalizer' && ['semantic_id', 'owner_stage', 'output_binding', 'anchors', 'semantics', 'material_use', 'material_views']
                .some((field) => entry.selector === `json:/${field}`), 'SEM_ISOLATION', entry.path, 'only direct semantic origin projection allowed');
            const origin = parseSemanticJson(readMaterialFile(model.runDir, entry.path));
            validateSemanticSubject(origin, model);
            origins.set(origin.semantic_id, origin);
        }
        else if (/^verification\/harness\/semantic-process\/LIN-\d+\.json$/u.test(entry.path)) {
            requireSemantic(stage === 'S4' && ['lineage_id', 'owner_stage', 'type', 'predecessors', 'successors']
                .some((field) => entry.selector === `json:/${field}`), 'SEM_ISOLATION', entry.path, 'only already-proposed successor membership allowed');
            lineageFiles.add(entry.path);
        }
        else {
            requireSemantic(entry.path === 'ledgers/packet-index.md' && role === 'normalizer' && entry.selector.startsWith('row:'), 'SEM_ISOLATION', entry.path, 'outside exact Core producer allowlist');
        }
        selected.push([entry, bytes.toString('utf8')]);
    }
    requireSemantic(selections.some((s) => s.path === 'ledgers/extraction-criteria.md'), 'SEM_ISOLATION', 'producer context', 'S1 criteria required');
    if (role === 'extractor') {
        requireSemantic(context.source_windows.length === 1, 'SEM_ISOLATION', role, 'one complete frozen source required');
        const window = context.source_windows[0], path = [...sourcePaths].find(([, id]) => id === window.source_id)[0];
        requireSemantic(window.start_byte === 0 && window.end_byte === readMaterialFile(model.runDir, path).length, 'SEM_ISOLATION', role, 'extractor requires complete source');
        context.legal_source_ids = [window.source_id];
        for (const [entry, text] of selected.filter(([entry]) => ['corpus/manifest.md', 'ledgers/source-walk.md'].includes(entry.path))) {
            const cells = parseSemanticJson(text);
            requireSemantic(cells[entry.path === 'corpus/manifest.md' ? 0 : 1] === window.source_id || entry.path === 'ledgers/source-walk.md' && cells[0] === window.source_id, 'SEM_ISOLATION', entry.path, 'source-local row required');
        }
        const material = readRepresentationContext(model);
        const repIds = material.inventory.representations.filter((r) => r.source_id === window.source_id).map((r) => r.representation_id);
        const legalRows = Object.values(material.inventory).filter(Array.isArray).flat().filter((r) => r.source_id === window.source_id || repIds.includes(r.representation_id));
        for (const [entry, text] of selected.filter(([entry]) => entry.path === 'corpus/representations.md')) {
            const cells = parseSemanticJson(text);
            requireSemantic(legalRows.some((row) => Object.values(row)[0] === cells[0]), 'SEM_ISOLATION', entry.path, 'material from another source');
        }
        for (const asset of material.inventory.assets.filter((a) => repIds.includes(a.representation_id)))
            assets.set(asset.locus, readMaterialFile(model.runDir, asset.locus));
    }
    else {
        requireSemantic(origins.size > 0, 'SEM_ACCOUNTING', role, 'assigned reviewed semantic origins required');
        const ledger = parseSemanticLedger(readMaterialFile(model.runDir, SEMANTIC_PATH).toString('utf8'));
        for (const [id, origin] of origins) {
            const fields = selections.filter((entry) => entry.path === semanticSubjectPath(id)).map((entry) => entry.selector.slice(6));
            requireSemantic(fields.length === 7, 'SEM_ISOLATION', id, 'complete direct origin projection required');
            const assignments = ledger.assignments.filter((r) => r.semantic_id === id);
            requireSemantic(assignments.length > 0 && assignments.every((a) => {
                const row = ledger.results.find((r) => r.review_id === a.review_id);
                return row && (origin.owner_stage !== 'S2' || parseSemanticJson(readMaterialFile(model.runDir, row.result_path)).verdict === 'upheld');
            }), 'SEM_REVIEW', id, 'origins must have completed review; S2 origins require upheld');
            context.packet_ids.push(...outputPackets(origin.output_binding));
            context.origin_unit_refs.push(...origin.semantics.units.map((u) => `${id}/${u.unit_id}`));
        }
        context.packet_ids = [...new Set(context.packet_ids)];
        context.legal_source_ids = [...new Set(context.packet_ids.map((id) => model.packets.find((p) => p.values.packetId === id).values.sourceId))];
        const basis = semanticPacketBasis(model, context.packet_ids);
        const rowsShown = selected.filter(([entry]) => entry.path === 'ledgers/packet-index.md').map(([, text]) => parseSemanticJson(text));
        for (const p of basis)
            for (const record of [p.packet, p.evidence_record, ...p.fragments, ...p.transformations]) {
                requireSemantic(rowsShown.some((cells) => cells[0] === Object.values(record)[0]), 'SEM_ISOLATION', p.packet_id, 'complete exact packet group required');
            }
        for (const [entry, text] of selected.filter(([entry]) => entry.path === 'ledgers/packet-index.md')) {
            const cells = parseSemanticJson(text);
            requireSemantic(basis.some((p) => p.packet_id === cells[0] || p.evidence_record.evidence_key === cells[0]
                || p.fragments.some((f) => f.fragment_key === cells[0]) || p.transformations.some((t) => t.transform_key === cells[0])), 'SEM_ISOLATION', entry.path, 'packet row outside assigned origin group');
        }
        for (const window of context.source_windows) {
            requireSemantic(context.legal_source_ids.includes(window.source_id), 'SEM_ISOLATION', 'producer source window', 'unrelated source');
            const path = [...sourcePaths].find(([, id]) => id === window.source_id)[0];
            const complete = window.start_byte === 0 && window.end_byte >= readMaterialFile(model.runDir, path).length - 1;
            const covered = basis.some((p) => p.packet.source_id === window.source_id && p.fragments.some((f) => {
                const span = sourceSpan(model, window.source_id, String(f.locator));
                return span.start <= window.start_byte && span.end >= window.end_byte;
            }));
            requireSemantic(!complete || covered || context.referent_search?.source_id === window.source_id, 'SEM_ISOLATION', 'producer window', 'whole-source widening requires dedicated Slice 5 search context');
        }
        // Packet bytes embedded in the exact direct origin are also legal windows.
        for (const p of basis)
            for (const fragment of p.fragments) {
                const span = sourceSpan(model, String(fragment.source_id), String(fragment.locator));
                context.source_windows.push({ source_id: String(fragment.source_id), start_byte: span.start, end_byte: span.end });
            }
        for (const origin of origins.values())
            for (const anchor of origin.anchors) {
                context.source_windows.push({ source_id: anchor.source_id, start_byte: anchor.start_byte, end_byte: anchor.end_byte });
            }
        for (const origin of origins.values())
            for (const entry of origin.material_views) {
                for (const asset of entry.view.assets) {
                    if (typeof asset.bytes_base64 === 'string')
                        assets.set(String(asset.locus), Buffer.from(asset.bytes_base64, 'base64'));
                }
            }
        if (stage === 'S4') {
            requireSemantic(lineageFiles.size === 1, 'SEM_WINDOW', 'S4', 'one already-proposed successor event required');
            const path = [...lineageFiles][0], row = parseSemanticJson(readMaterialFile(model.runDir, path));
            keys(row, ['lineage_id', 'owner_stage', 'type', 'predecessors', 'successors', 'basis', 'established_by'], 'successor reservation');
            const predecessors = String(row.predecessors).split(',').map((s) => s.trim()), successors = String(row.successors).split(',').map((s) => s.trim());
            const committed = retained && parseLineage(model).rows.some((r) => r.values.lineageId === row.lineage_id
                && semanticJson(r.cells.map(decoded)) === semanticJson(Object.values(row)));
            requireSemantic(row.owner_stage === 'S4' && successors.every((id) => existingId(id, 'CC'))
                && predecessors.every((id) => [...origins.values()].some((s) => s.output_binding.kind === 'claim' && s.output_binding.reserved_claim_id === id))
                && (committed || predecessors.every((id) => lineageCurrentClaimIds(model).has(id)))
                && origins.size === predecessors.length && selections.filter((e) => e.path === path).length === 5, 'SEM_WINDOW', path, 'exact direct predecessor group and reserved CC successors required');
            context.successor = { lineage_id: String(row.lineage_id), row_digest: materialHash(semanticJson(Object.values(row))),
                event: { owner_stage: 'S4', type: String(row.type), predecessors, successors },
                unit_definitions: predecessors.map((id) => unitDefinition(model, 'CC', id)) };
        }
    }
    if (context.referent_search) {
        const sourceId = context.referent_search.source_id, path = [...sourcePaths].find(([, id]) => id === sourceId)[0];
        requireSemantic(context.legal_source_ids.length === 1 && context.legal_source_ids[0] === sourceId
            && context.source_windows.some((w) => w.source_id === sourceId && w.start_byte === 0 && w.end_byte === readMaterialFile(model.runDir, path).length), 'SEM_ISOLATION', 'referent search', 'exactly one complete frozen source required');
        const completion = model.sourceWalk.completions.find((r) => r.values.sourceId === sourceId && r.values.completionState === 'complete');
        const shown = selected.filter(([entry]) => entry.path === 'ledgers/source-walk.md').map(([, text]) => parseSemanticJson(text));
        requireSemantic(shown.some((cells) => cells[0] === sourceId && cells.includes(completion.values.finalCursorId))
            && shown.every((cells) => cells[0] === sourceId || cells[1] === sourceId), 'SEM_ISOLATION', 'referent search', 'exact source completion and source-local search records required');
    }
    const bytes = Buffer.from(`# Bounded semantic producer context\n\n${selected.map(([entry, value]) => `${semanticJson(entry)}\n${semanticJson(value)}`).join('\n\n')}\n`);
    return { bytes, context, assets: [...assets].map(([path, bytes]) => ({ path, bytes })).sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path))) };
}
export function semanticProducerSelections(model, role, stage, options) {
    const entries = [];
    const add = (path, selector, purpose) => {
        if (entries.some((e) => e.path === path && e.selector === selector))
            return;
        const entry = { path, selector, digest: '', purpose };
        entry.digest = materialHash(semanticSelectedBytes(model, entry));
        entries.push(entry);
    };
    const rows = (path, accept, purpose) => {
        const bytes = readMaterialFile(model.runDir, path), lines = bytes.toString('utf8').split('\n');
        for (const table of parseTables(bytes.toString('utf8'))) {
            const heading = lines.slice(0, table.line - 1).reverse().find((line) => /^#{1,6} /u.test(line))?.replace(/^#{1,6} /u, '').replace(/\r$/u, '');
            requireSemantic(heading, 'SEM_REFERENCE', path, 'literal table heading required');
            table.rows.forEach((row, i) => { if (accept(row.cells.map(decoded)))
                add(path, `row:${heading}:${i}`, purpose); });
        }
    };
    add('ledgers/extraction-criteria.md', `bytes:0:${readMaterialFile(model.runDir, 'ledgers/extraction-criteria.md').length}`, 'inspection-context');
    if (options.referent_search) {
        for (const ref of [options.referent_search.request_ref, options.referent_search.working_subject_ref]) {
            const selected = selectedSemanticReference(model, ref);
            add(selected.path, `json:${selected.pointer}`, 'ambiguity-context');
        }
        const search = semanticProducerSearch(model, entries);
        const source = model.corpus.sources.find((r) => r.values.sourceId === search.source_id).values;
        const path = relative(model.runDir, sourceFilePath(model.runDir, source.locus)).replaceAll('\\', '/');
        add(path, `bytes:0:${readMaterialFile(model.runDir, path).length}`, 'inspection-context');
        rows('ledgers/source-walk.md', (cells) => cells[0] === search.source_id || cells[1] === search.source_id, 'inspection-context');
    }
    if (role === 'extractor') {
        const source = model.corpus.sources.find((s) => s.values.sourceId === options.source_id)?.values;
        requireSemantic(source, 'SEM_REFERENCE', 'producer source', 'exact frozen source required');
        const path = sourceFilePath(model.runDir, source.locus);
        add(relative(model.runDir, path).replaceAll('\\', '/'), `bytes:0:${readFileSync(path).length}`, 'packet-evidence');
        rows('corpus/manifest.md', (cells) => cells[0] === options.source_id, 'inspection-context');
        if (existsSync(join(model.runDir, 'ledgers/source-walk.md')))
            rows('ledgers/source-walk.md', (cells) => cells[0] === options.source_id || cells[1] === options.source_id, 'inspection-context');
        const inventory = readRepresentationContext(model).inventory;
        const repIds = inventory.representations.filter((r) => r.source_id === options.source_id).map((r) => r.representation_id);
        const ids = new Set(Object.values(inventory).filter(Array.isArray).flat().filter((r) => r.source_id === options.source_id || repIds.includes(r.representation_id)).map((r) => String(Object.values(r)[0])));
        rows('corpus/representations.md', (cells) => ids.has(cells[0]), 'material-context');
    }
    else {
        const packetIds = [];
        for (const id of options.origin_semantic_ids || []) {
            const s = parseSemanticJson(readMaterialFile(model.runDir, semanticSubjectPath(id)));
            packetIds.push(...outputPackets(s.output_binding));
            for (const field of ['semantic_id', 'owner_stage', 'output_binding', 'anchors', 'semantics', 'material_use', 'material_views'])
                add(semanticSubjectPath(id), `json:/${field}`, 'inspection-context');
        }
        const basis = semanticPacketBasis(model, [...new Set(packetIds)]), ids = new Set(basis.flatMap((p) => [p.packet, p.evidence_record, ...p.fragments, ...p.transformations].map((row) => String(Object.values(row)[0]))));
        rows('ledgers/packet-index.md', (cells) => ids.has(cells[0]), 'packet-evidence');
        for (const anchor of options.inspection_anchors || []) {
            const complete = completeSemanticAnchors(model, [{ ...anchor, anchor_id: 'A1' }], [])[0];
            add(sourceSpan(model, anchor.source_id, anchor.locator).path, `bytes:${complete.start_byte}:${complete.end_byte}`, 'inspection-context');
        }
        if (options.lineage_id)
            for (const field of ['lineage_id', 'owner_stage', 'type', 'predecessors', 'successors'])
                add(`verification/harness/semantic-process/${options.lineage_id}.json`, `json:/${field}`, 'lineage-context');
    }
    entries.sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)) || Buffer.compare(Buffer.from(a.selector), Buffer.from(b.selector)));
    semanticProducerView(model, role, stage, entries);
    return entries;
}
export function validateSemanticProducerDelivery(model, role, stage, callId, task, attachments, retained = false) {
    const paths = semanticProducerViewPaths(callId);
    const selections = parseSemanticJson(readMaterialFile(model.runDir, paths.selections));
    const view = semanticProducerView(model, role, stage, selections, retained);
    const expected = [{ path: paths.view, bytes: view.bytes }, ...view.assets].sort((a, b) => Buffer.compare(Buffer.from(a.path), Buffer.from(b.path)));
    requireSemantic(task === semanticProducerTask(role, stage, !!view.context.referent_search)
        && attachments.length === expected.length && attachments.every((a, i) => a.path === expected[i].path && a.bytes.equals(expected[i].bytes)), 'SEM_ISOLATION', callId, 'deliver only the exact Core producer projection');
    return view.context;
}
export function validateSemanticReturn(role, runFormatVersion, value, context) {
    try {
        requireSemantic(hasRunCapability(runFormatVersion, 'semantic-unit-review'), 'SEM_COMPATIBILITY', 'return', 'pinned semantic capability required');
        // Strict parsing validates duplicate members before this entrypoint; round-trip
        // here additionally rejects unpaired surrogates/noncanonical numeric values.
        semanticJson(value);
        if (role === 'verifier-l2s') {
            requireSemantic(!context || context.subject, 'SEM_SUBJECT', 'return', 'full reviewer validation needs sealed subject');
            validateSemanticResult(value, context?.subject);
            if (context?.subject) {
                validateSemanticSubject(context.subject, context.model);
                value.unresolved_findings.forEach((finding, i) => findingShape(finding, i, semanticCoverage(context.subject.semantics, context.subject.subject_kind), context.subject.anchors, context.subject.material_use?.requirements.length || 0, context.model, subjectSources(context.subject, readRepresentationContext(context.model))));
            }
        }
        else {
            const base = SEMANTIC_PRODUCER_BASE_EXEMPLARS[role];
            keys(value, [...Object.keys(base), 'semantic_units'], role);
            const previous = Object.fromEntries(Object.keys(base).map((k) => [k, value[k]]));
            // The new closed contract retains the existing cursor/criterion grammar.
            // The predecessor exemplar converter cannot express these two shapes;
            // validate them explicitly, without changing any predecessor validator.
            const shapeInput = structuredClone(previous);
            if (role === 'extractor' && obj(shapeInput.next_cursor) && Array.isArray(shapeInput.walk_intervals)) {
                for (const field of ['next_event_ordinal', 'predecessor_walk_index', 'predecessor_event_index']) {
                    const index = shapeInput.next_cursor[field];
                    requireSemantic(index === null || ordinal(index, field === 'next_event_ordinal'), 'SEM_FORMAT', field, 'nullable cursor index required');
                    shapeInput.next_cursor[field] = index === null ? null : String(index);
                }
                for (const interval of shapeInput.walk_intervals)
                    if (obj(interval)) {
                        requireSemantic(typeof interval.criterion_ref === 'string' && /^(?:admission:[1-9]\d*|exclusion:[a-z][a-z0-9-]*|none)$/u.test(interval.criterion_ref), 'SEM_FORMAT', 'criterion_ref', 'existing explicit criterion selector required');
                        interval.criterion_ref = 'none';
                    }
            }
            const legacy = validateWorkerReturnContract(semanticJson(shapeInput), base);
            requireSemantic(legacy.result === 'PASS', 'SEM_FORMAT', role, legacy.errors.join('; '));
            if (context) {
                requireSemantic(context.source_windows && context.packet_ids && context.origin_unit_refs, 'SEM_ISOLATION', 'producer return', 'full binding requires the Core-projected source windows, packet group and origins');
                if (role === 'extractor')
                    requireSemantic(context.legal_source_ids.length === 1 && value.source_id === context.legal_source_ids[0], 'SEM_REFERENCE', 'source_id', 'extractor must match its one assigned source');
                if (context.owner_stage === 'S4')
                    requireSemantic(context.successor && value.no_claim_packets.length === 0
                        && value.lineage_proposals.length === 0
                        && (value.claims.length === context.successor.event.successors.length
                            || value.claims.length === 0 && value.material_findings.length > 0), 'SEM_WINDOW', 'successor return', 'preserve proposed successor membership or return a material refusal');
            }
            array(value.semantic_units, 'semantic_units');
            const arrays = role === 'extractor' ? ['packets', 'material_findings'] : ['claims', 'no_claim_packets', 'material_findings'];
            const kindFor = { packets: 'packet-candidate', claims: 'claim-candidate', no_claim_packets: 'no-claim-candidate', material_findings: 'material-candidate' };
            const selectors = arrays.flatMap((name) => value[name].map((_output, i) => `${kindFor[name]}:${i}`));
            requireSemantic(value.semantic_units.length === selectors.length, 'SEM_ACCOUNTING', 'semantic_units', 'every applicable output needs exactly one entry');
            value.semantic_units.forEach((entry, i) => {
                keys(entry, ['output_kind', 'output_index', 'review_mode', 'origin_unit_refs', 'anchors', 'semantics'], `semantic_units/${i}`);
                oneOf(entry.output_kind, SEMANTIC_OUTPUT_KINDS, 'output_kind');
                requireSemantic(ordinal(entry.output_index) && `${entry.output_kind}:${entry.output_index}` === selectors[i], 'SEM_ACCOUNTING', 'selector', 'invalid, duplicate, unordered or wrong-role selector');
                oneOf(entry.review_mode, ['proposal', 'unresolved-record'], 'review_mode');
                uniqueStrings(entry.origin_unit_refs, 'origin_unit_refs');
                requireSemantic(entry.origin_unit_refs.every((r) => /^SEM-(?=\d*[1-9])\d{4,}\/U[1-9]\d*$/u.test(r)), 'SEM_REFERENCE', 'origins', 'SEM/U references required');
                requireSemantic(!['packet-candidate', 'material-candidate'].includes(entry.output_kind) || entry.origin_unit_refs.length === 0, 'SEM_REFERENCE', 'origins', 'S2/material-only origins must be empty');
                array(entry.anchors, 'anchors');
                entry.anchors.forEach((a, n) => anchorShape(a, n, false));
                const name = arrays.find((name) => kindFor[name] === entry.output_kind);
                const output = value[name][entry.output_index];
                const use = entry.output_kind === 'no-claim-candidate' ? null : validateMaterialUseInput(output.material_use);
                const kind = entry.output_kind === 'packet-candidate' ? (output.evidence_state === 'exact' ? 'packet-group' : 'material-only')
                    : entry.output_kind === 'claim-candidate' ? 'claim' : entry.output_kind === 'no-claim-candidate' ? 'no-claim' : 'material-only';
                validateSemantics(entry.semantics, entry.anchors, use, kind, context?.model, context?.legal_source_ids);
                requireSemantic(kind !== 'no-claim' || entry.semantics.atomicity === 'no-claim', 'SEM_STATE', 'no-claim', 'no-claim grammar required');
                requireSemantic(kind !== 'material-only' || entry.semantics.atomicity === 'CANNOT_DETERMINE', 'SEM_STATE', 'material-only', 'indeterminate grammar required');
                requireSemantic(kind === 'material-only' || entry.anchors.length > 0, 'SEM_REFERENCE', 'anchors', 'source basis required');
                if (context) {
                    requireSemantic(role === 'extractor' ? context.owner_stage === 'S2' : context.owner_stage === 'S3' || context.owner_stage === 'S4' && context.successor, 'SEM_WINDOW', 'producer', 'exact legal stage and successor reservation required');
                    for (const anchor of entry.anchors) {
                        requireSemantic(context.legal_source_ids.includes(anchor.source_id), 'SEM_REFERENCE', anchor.anchor_id, 'source outside producer allowlist');
                        completeSemanticAnchors(context.model, [{ ...anchor, anchor_id: 'A1' }], []);
                        requireSemantic(context.source_windows.some((window) => window.source_id === anchor.source_id
                            && window.start_byte <= anchor.start_byte && window.end_byte >= anchor.end_byte), 'SEM_REFERENCE', anchor.anchor_id, 'anchor escapes exact shown source window');
                    }
                    requireSemantic(entry.origin_unit_refs.every((ref) => context.origin_unit_refs.includes(ref)), 'SEM_REFERENCE', 'origins', 'unit outside assigned reviewed group');
                    const packets = entry.output_kind === 'claim-candidate' ? output.packets
                        : entry.output_kind === 'no-claim-candidate' ? [String(output.packet)] : [];
                    requireSemantic(packets.every((id) => context.packet_ids.includes(id)), 'SEM_REFERENCE', 'candidate packets', 'packet outside assigned group');
                    if (entry.output_kind === 'packet-candidate')
                        for (const fragment of output.fragments) {
                            const span = sourceSpan(context.model, String(value.source_id), String(fragment.locator));
                            requireSemantic(span.bytes.toString('base64') === fragment.exact_bytes_base64
                                && context.source_windows.some((window) => window.source_id === value.source_id && window.start_byte <= span.start && window.end_byte >= span.end), 'SEM_EVIDENCE', 'producer fragment', 'exact frozen fragment and shown source bounds required before capture');
                        }
                    const material = readRepresentationContext(context.model);
                    for (const requirement of use?.requirements || []) {
                        const object = material.inventory.objects.find((o) => o.object_id === requirement.object_id);
                        requireSemantic(object && material.inventory.representations.some((r) => r.representation_id === object.representation_id && context.legal_source_ids.includes(r.source_id)), 'SEM_REFERENCE', requirement.object_id, 'material outside assigned source scope');
                    }
                }
            });
        }
        return { result: 'PASS', errors: [], canonicalValue: value, binding: context ? 'checked' : 'not-checked' };
    }
    catch (error) {
        return { result: 'FAIL', errors: [error instanceof Error ? error.message : String(error)], canonicalValue: null, binding: context ? 'checked' : 'not-checked' };
    }
}
