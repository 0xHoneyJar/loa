import { createHash } from 'node:crypto';
import { existsSync, lstatSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { hasRunLogEvent, mdLineSpan, reachedState, runLogEvents, sourceFilePath } from './check-helpers.js';
import { closurePhasesFromText, parseStructuredVerifierRecord } from './internal-ambiguity.js';
import { envelopeSection, parseTables } from './markdown.js';
import { parsePacketBasis, parseRelations, relationReviewSubjectJson } from './relations.js';
import { parseStrictJson } from './worker-return-contract.js';
import { usesFormalLayoutBindings } from './run-model.js';
export const REPRESENTATION_PATH = 'corpus/representations.md';
export const REPRESENTATION_ASSET_PATH = 'corpus/representation-assets';
export const REPRESENTATION_USE_PATH = 'ledgers/representation-uses.md';
export const REPRESENTATION_FORMAT = 'aleph-source-representation/v1';
export const REPRESENTATION_USE_FORMAT = 'aleph-representation-use/v1';
export const SUPPLIED_REPRESENTATION_FORMAT = 'aleph-supplied-representation/v1';
export const REPRESENTATION_SUFFIX = '.aleph-representation.json';
export const REPRESENTATION_STATES = ['available', 'degraded', 'unsupported', 'indeterminate'];
export const MATERIAL_FEATURES = [
    'text-bytes', 'table-grid', 'header-association', 'caption-association',
    'formal-structure', 'image', 'chart-values', 'spatial-region',
];
export const MATERIAL_HEADERS = {
    representations: ['representation_id', 'source_id', 'origin_kind', 'extraction_surface', 'state', 'reason', 'provenance_id'],
    assets: ['asset_id', 'representation_id', 'role', 'locus', 'media_type', 'encoding', 'byte_length', 'content_hash'],
    provenance: ['provenance_id', 'representation_id', 'type', 'actor', 'tool', 'tool_version', 'input_refs', 'output_refs', 'parameters_asset_id', 'declaration_asset_id'],
    bindings: ['binding_id', 'representation_id', 'carrier_id', 'start_byte', 'end_byte', 'page_id', 'region_id', 'byte_role', 'fragment_hash', 'exact_bytes_base64'],
    objects: ['object_id', 'representation_id', 'kind', 'parent_id', 'state', 'reason', 'provenance_id', 'binding_ids', 'content_hash', 'coordinates'],
    associations: ['association_id', 'representation_id', 'kind', 'subject_id', 'target_ids', 'state', 'reason', 'provenance_id'],
    uses: ['use_id', 'owner_stage', 'subject_kind', 'subject_id', 'basis_packet_ids', 'requirements', 'use_state', 'fidelity_claim', 'limitation_refs', 'reason', 'established_by', 'review_subject_digest', 'reviewed_by'],
};
export class RepresentationError extends Error {
    constructor(token, subject, field, reason) {
        super(`${token} ${subject} field ${field}: ${reason}`);
    }
}
function requireMaterial(condition, token, subject, field, reason) {
    if (!condition)
        throw new RepresentationError(token, subject, field, reason);
}
export function materialHash(bytes) {
    return `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
}
export function materialFragmentsHash(fragments) {
    const hash = createHash('sha256').update('aleph-material-fragments/v1\0');
    for (const bytes of fragments) {
        const size = Buffer.alloc(8);
        size.writeBigUInt64BE(BigInt(bytes.length));
        hash.update(size).update(bytes);
    }
    return `sha256:${hash.digest('hex')}`;
}
function record(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}
function exactKeys(value, keys) {
    return record(value) && JSON.stringify(Object.keys(value)) === JSON.stringify(keys);
}
function json(value, id, field) {
    let parsed;
    try {
        parsed = parseStrictJson(value);
    }
    catch {
        throw new RepresentationError('FORMAT', id, field, 'invalid JSON or duplicate member');
    }
    requireMaterial(JSON.stringify(parsed) === value, 'FORMAT', id, field, 'noncanonical JSON');
    return parsed;
}
function list(value, id, field, sorted = false) {
    const parsed = json(value, id, field);
    requireMaterial(Array.isArray(parsed) && parsed.every((v) => typeof v === 'string')
        && new Set(parsed).size === parsed.length, 'FORMAT', id, field, 'expected unique string array');
    if (sorted)
        requireMaterial(JSON.stringify([...parsed].sort()) === value, 'FORMAT', id, field, 'set must be ASCII sorted');
    return parsed;
}
function idFor(value, family) {
    return new RegExp(`^${family}-(?=\\d*[1-9])\\d{4,}$`, 'u').test(value);
}
function integer(value, id, field, positive = false) {
    requireMaterial(/^(?:0|[1-9]\d*)$/u.test(value) && Number.isSafeInteger(Number(value))
        && (!positive || Number(value) > 0), 'BINDING', id, field, 'expected canonical safe integer');
    return Number(value);
}
function utf8(bytes) {
    try {
        new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
        return true;
    }
    catch {
        return false;
    }
}
function state(row, key = 'state') {
    requireMaterial(REPRESENTATION_STATES.includes(row[key]), 'STATE', rowId(row), key, 'unknown state');
    requireMaterial(row[key] === 'available' ? row.reason === 'none' : Boolean(row.reason?.trim()) && row.reason !== 'none', 'STATE', rowId(row), 'reason', 'state/reason mismatch');
}
function rowId(row) {
    for (const key of ['use_id', 'asset_id', 'binding_id', 'object_id', 'association_id'])
        if (key in row)
            return row[key];
    return ('origin_kind' in row ? row.representation_id : row.provenance_id) || REPRESENTATION_PATH;
}
function find(rows, id, token = 'IDENTITY') {
    const row = rows.find((candidate) => rowId(candidate) === id);
    requireMaterial(row, token, id, 'reference', 'missing declared row');
    return row;
}
function sameRep(left, right, field) {
    requireMaterial(left.representation_id === right.representation_id, 'IDENTITY', rowId(left), field, 'cross-representation reference');
}
function escapeCell(value) {
    return value.replace(/&/gu, '&amp;').replace(/\|/gu, '&#124;').replace(/\r/gu, '&#13;').replace(/\n/gu, '&#10;');
}
function unescapeCell(value) {
    return value.replace(/&#10;/gu, '\n').replace(/&#13;/gu, '\r').replace(/&#124;/gu, '|').replace(/&amp;/gu, '&');
}
export function materialTableMarkdown(header, rows) {
    return `| ${header.join(' | ')} |\n| ${header.map(() => '---').join(' | ')} |\n`
        + rows.map((row) => `| ${header.map((key) => escapeCell(row[key])).join(' | ')} |\n`).join('');
}
function tableRows(text, name, path) {
    const tables = parseTables(text, path);
    const header = MATERIAL_HEADERS[name];
    const matching = tables.filter((table) => table.header[0] === header[0]);
    requireMaterial(matching.length === 1 && JSON.stringify(matching[0].header) === JSON.stringify(header), 'FORMAT', path, header[0], 'require one table with exact headers');
    return matching[0].rows.map((row) => {
        requireMaterial(row.cells.length === header.length, 'FORMAT', `${path}:${row.line}`, 'columns', 'wrong row width');
        return Object.fromEntries(header.map((key, index) => [key, unescapeCell(row.cells[index])]));
    });
}
export function emptyMaterialInventory() {
    return { representations: [], assets: [], provenance: [], bindings: [], objects: [], associations: [] };
}
export function representationMarkdown(inventory) {
    return `# Source Representations\n\n- source_representation_format: ${REPRESENTATION_FORMAT}\n\n`
        + Object.keys(inventory).map((key) => `## ${key}\n\n${materialTableMarkdown(MATERIAL_HEADERS[key], inventory[key])}`).join('\n');
}
export function representationUsesMarkdown(rows) {
    return `# Representation Uses\n\n- representation_use_format: ${REPRESENTATION_USE_FORMAT}\n\n`
        + materialTableMarkdown(MATERIAL_HEADERS.uses, rows);
}
function marker(text, field, value, path) {
    const candidates = text.split(/\r?\n/u).filter((line) => line.includes(`${field}:`));
    requireMaterial(candidates.length === 1 && candidates[0] === `- ${field}: ${value}`, 'FORMAT', path, field, 'require one exact marker');
}
export function parseRepresentationInventory(text) {
    marker(text, 'source_representation_format', REPRESENTATION_FORMAT, REPRESENTATION_PATH);
    const inventory = emptyMaterialInventory();
    for (const key of Object.keys(inventory))
        inventory[key] = tableRows(text, key, REPRESENTATION_PATH);
    requireMaterial(parseTables(text).length === 6, 'FORMAT', REPRESENTATION_PATH, 'tables', 'exactly six canonical tables required');
    return inventory;
}
export function readMaterialFile(root, path) {
    requireMaterial(path !== '' && !path.startsWith('/') && !/[\\:\0]/u.test(path)
        && path.split('/').every((part) => part && part !== '.' && part !== '..'), 'CAPTURE_HASH', path, 'locus', 'unsafe relative path');
    let current = root;
    for (const part of path.split('/')) {
        current = join(current, part);
        requireMaterial(existsSync(current) && !lstatSync(current).isSymbolicLink(), 'CAPTURE_HASH', path, 'locus', 'missing path or symlink');
    }
    requireMaterial(lstatSync(current).isFile(), 'CAPTURE_HASH', path, 'locus', 'not a regular file');
    return readFileSync(current);
}
function bindingBytes(context, binding) {
    const carrier = context.carriers.get(binding.carrier_id);
    requireMaterial(carrier, 'BINDING', rowId(binding), 'carrier_id', 'unknown carrier');
    return carrier.bytes.subarray(Number(binding.start_byte), Number(binding.end_byte));
}
function objectBindings(context, object) {
    return list(object.binding_ids, rowId(object), 'binding_ids').map((id) => find(context.inventory.bindings, id, 'BINDING'));
}
function ancestors(inventory, object) {
    const result = [object];
    while (result.at(-1).parent_id !== 'none') {
        const parent = find(inventory.objects, result.at(-1).parent_id, 'COORDINATE');
        requireMaterial(!result.includes(parent), 'COORDINATE', rowId(object), 'parent_id', 'cyclic parentage');
        sameRep(object, parent, 'parent_id');
        result.push(parent);
    }
    return result;
}
const COORDINATE_KEYS = {
    source: [], page: ['index', 'label', 'space'], region: ['page_id', 'box'], text: [],
    table: ['row_ids', 'column_ids', 'grid_state'], row: ['index'], column: ['index'],
    cell: ['row_ids', 'column_ids'], header: ['cell_ids'], caption: [],
    formal: ['notation', 'structure_ids', 'structure_state'],
    figure: ['figure_kind', 'image_ids', 'values_ids', 'values_state'], image: [], 'chart-values': [],
};
const PARENTS = {
    source: [], page: ['source'], region: ['source', 'page'],
    text: ['source', 'page', 'region', 'cell', 'header', 'caption', 'formal', 'figure'],
    table: ['source', 'page', 'region'], row: ['table'], column: ['table'], cell: ['table'], header: ['table'],
    caption: ['source', 'page', 'region'], formal: ['source', 'page', 'region', 'cell', 'caption'],
    figure: ['source', 'page', 'region', 'cell', 'caption'], image: ['source', 'page', 'region', 'figure'],
    'chart-values': ['figure'],
};
function coordinates(object) {
    const value = json(object.coordinates, rowId(object), 'coordinates');
    requireMaterial(COORDINATE_KEYS[object.kind] && exactKeys(value, COORDINATE_KEYS[object.kind]), 'COORDINATE', rowId(object), 'coordinates', 'unknown kind or noncanonical coordinate shape');
    return value;
}
function coordinateIds(value, object, field) {
    requireMaterial(Array.isArray(value) && value.every((id) => typeof id === 'string') && new Set(value).size === value.length, 'COORDINATE', rowId(object), field, 'expected ordered unique IDs');
    return value;
}
function positive(value) { return typeof value === 'number' && Number.isSafeInteger(value) && value > 0; }
function coordinateObjects(context) {
    const inv = context.inventory;
    const byId = (id) => find(inv.objects, id, 'COORDINATE');
    for (const object of inv.objects) {
        const id = rowId(object), c = coordinates(object), parents = ancestors(inv, object);
        requireMaterial(object.kind === 'source' ? object.parent_id === 'none'
            : parents.length > 1 && PARENTS[object.kind].includes(parents[1].kind), 'COORDINATE', id, 'parent_id', 'illegal parent kind');
        if (object.kind === 'page') {
            requireMaterial(positive(c.index) && (c.label === null || typeof c.label === 'string'), 'COORDINATE', id, 'index/label', 'invalid supplied page identity');
            requireMaterial(inv.objects.filter((other) => other.kind === 'page' && other.representation_id === object.representation_id
                && coordinates(other).index === c.index).length === 1, 'COORDINATE', id, 'index', 'duplicate page ordinal');
            requireMaterial(c.space === null || (exactKeys(c.space, ['unit', 'width', 'height', 'origin'])
                && c.space.unit === 'pixel' && c.space.origin === 'top-left' && positive(c.space.width) && positive(c.space.height)), 'COORDINATE', id, 'space', 'expected supplied integer pixel space');
        }
        if (object.kind === 'region') {
            requireMaterial(c.page_id === null || typeof c.page_id === 'string', 'COORDINATE', id, 'page_id', 'invalid page');
            const page = c.page_id === null ? null : byId(c.page_id);
            if (page) {
                sameRep(object, page, 'page_id');
                requireMaterial(page.kind === 'page', 'COORDINATE', id, 'page_id', 'not a page');
            }
            requireMaterial(parents[1]?.kind !== 'page' || c.page_id === rowId(parents[1]), 'COORDINATE', id, 'page_id', 'parent page mismatch');
            if (c.box !== null) {
                const space = page && coordinates(page).space;
                requireMaterial(record(space) && exactKeys(c.box, ['x0', 'y0', 'x1', 'y1'])
                    && Object.values(c.box).every((v) => typeof v === 'number' && Number.isSafeInteger(v) && v >= 0), 'COORDINATE', id, 'box', 'box requires declared integer page space');
                const box = c.box;
                requireMaterial(box.x0 < box.x1 && box.y0 < box.y1 && box.x1 <= Number(space.width) && box.y1 <= Number(space.height), 'COORDINATE', id, 'box', 'box outside supplied page space');
            }
        }
        if (object.kind === 'row' || object.kind === 'column')
            requireMaterial(positive(c.index), 'COORDINATE', id, 'index', 'invalid index');
        if (object.kind === 'table') {
            const rows = coordinateIds(c.row_ids, object, 'row_ids'), columns = coordinateIds(c.column_ids, object, 'column_ids');
            requireMaterial(REPRESENTATION_STATES.includes(c.grid_state), 'STATE', id, 'grid_state', 'unknown state');
            requireMaterial(c.grid_state === 'available' || object.state !== 'available', 'STATE', id, 'grid_state', 'unavailable grid cannot be an available object');
            for (const [kind, ids] of [['row', rows], ['column', columns]]) {
                const children = inv.objects.filter((child) => child.parent_id === id && child.kind === kind)
                    .sort((a, b) => Number(coordinates(a).index) - Number(coordinates(b).index));
                requireMaterial(JSON.stringify(children.map(rowId)) === JSON.stringify(ids), 'COORDINATE', id, `${kind}_ids`, 'axis inventory/order mismatch');
                const indices = children.map((child) => coordinates(child).index);
                requireMaterial(new Set(indices).size === indices.length, 'COORDINATE', id, `${kind}_ids`, 'duplicate axis index');
                if (c.grid_state === 'available')
                    requireMaterial(ids.length > 0 && indices.every((v, i) => v === i + 1), 'COORDINATE', id, `${kind}_ids`, 'available axis must be positive and contiguous');
            }
            const occupied = new Set();
            for (const cell of inv.objects.filter((child) => child.parent_id === id && child.kind === 'cell')) {
                const cc = coordinates(cell), rr = coordinateIds(cc.row_ids, cell, 'row_ids'), cs = coordinateIds(cc.column_ids, cell, 'column_ids');
                if (rr.length === 0 || cs.length === 0) {
                    requireMaterial(rr.length === 0 && cs.length === 0 && ['indeterminate', 'unsupported'].includes(cell.state), 'COORDINATE', rowId(cell), 'row_ids/column_ids', 'unpositioned cell must have both axes empty');
                }
                else {
                    for (const [selected, axis] of [[rr, rows], [cs, columns]]) {
                        const start = axis.indexOf(selected[0]);
                        requireMaterial(start >= 0 && JSON.stringify(axis.slice(start, start + selected.length)) === JSON.stringify(selected), 'COORDINATE', rowId(cell), 'span', 'not a contiguous declared axis subsequence');
                    }
                    for (const row of rr)
                        for (const col of cs) {
                            const key = `${row}/${col}`;
                            requireMaterial(!occupied.has(key), 'COORDINATE', rowId(cell), 'span', 'overlapping cells');
                            occupied.add(key);
                        }
                }
            }
            requireMaterial(c.grid_state !== 'available' || occupied.size === rows.length * columns.length, 'COORDINATE', id, 'grid_state', 'available grid has missing cells');
        }
        if (object.kind === 'header') {
            const cells = coordinateIds(c.cell_ids, object, 'cell_ids').map(byId);
            for (const cell of cells)
                requireMaterial(cell.kind === 'cell' && cell.parent_id === object.parent_id, 'COORDINATE', id, 'cell_ids', 'header cell belongs to another table');
            if (cells.length)
                for (const b of objectBindings(context, object)) {
                    const spans = cells.flatMap((cell) => objectBindings(context, cell)).filter((x) => x.carrier_id === b.carrier_id)
                        .map((x) => [Number(x.start_byte), Number(x.end_byte)]);
                    requireMaterial(intervalCovered(Number(b.start_byte), Number(b.end_byte), spans), 'COORDINATE', id, 'binding_ids', 'header bytes outside declared cells');
                }
        }
        if (object.kind === 'formal' || object.kind === 'figure') {
            const formal = object.kind === 'formal', featureState = formal ? c.structure_state : c.values_state;
            requireMaterial(REPRESENTATION_STATES.includes(featureState)
                && (featureState === 'available' || object.state !== 'available'), 'STATE', id, 'feature_state', 'invalid feature/object state');
            requireMaterial(formal ? ['source-markup', 'renderer-export', 'flattened-text', 'unknown'].includes(String(c.notation))
                : ['figure', 'chart', 'unknown'].includes(String(c.figure_kind)), 'COORDINATE', id, 'kind/notation', 'unknown declaration');
            const fields = formal ? [['structure_ids', 'text']] : [['image_ids', 'image'], ['values_ids', 'chart-values']];
            for (const [field, kind] of fields)
                for (const ref of coordinateIds(c[field], object, field)) {
                    const target = byId(ref);
                    sameRep(object, target, field);
                    requireMaterial(target.kind === kind, 'COORDINATE', id, field, 'wrong target kind');
                }
            if (formal && c.notation === 'flattened-text')
                requireMaterial(c.structure_state === 'degraded' && c.structure_ids.length === 0, 'STATE', id, 'structure_state', 'flattened text cannot supply recovered structure');
            if (!formal && featureState === 'available')
                requireMaterial(c.values_ids.length > 0, 'STATE', id, 'values_ids', 'available chart values need declarations');
        }
        const fixedPage = parents.find((x) => x.kind === 'page');
        const fixedRegion = parents.find((x) => x.kind === 'region');
        const ancestorPage = fixedPage ? rowId(fixedPage) : fixedRegion ? coordinates(fixedRegion).page_id : null;
        for (const b of objectBindings(context, object)) {
            if (fixedRegion && b.region_id !== 'none')
                requireMaterial(b.region_id === rowId(fixedRegion), 'COORDINATE', id, 'region_id', 'binding contradicts ancestor');
            const region = b.region_id === 'none' ? null : byId(b.region_id);
            const page = b.page_id === 'none' ? region ? coordinates(region).page_id : null : b.page_id;
            requireMaterial(!ancestorPage || !page || ancestorPage === page, 'COORDINATE', id, 'page_id', 'binding contradicts ancestor page');
        }
    }
}
function intervalCovered(start, end, spans) {
    let cursor = start;
    for (const [a, b] of [...spans].sort((x, y) => x[0] - y[0])) {
        if (a <= cursor && b >= cursor) {
            cursor = Math.max(cursor, b);
            if (cursor >= end)
                return true;
        }
    }
    return false;
}
export function validateMaterialInventory(context) {
    const inv = context.inventory;
    const families = { representations: 'REP', assets: 'AST', provenance: 'RPR', bindings: 'BND', objects: 'OBJ', associations: 'ASC' };
    for (const key of Object.keys(inv)) {
        const ids = new Set();
        for (const row of inv[key]) {
            const id = rowId(row);
            requireMaterial(idFor(id, families[key]) && !ids.has(id), 'IDENTITY', id, MATERIAL_HEADERS[key][0], 'invalid or duplicate ID');
            ids.add(id);
            if (key !== 'representations')
                find(inv.representations, row.representation_id);
            if ('state' in row)
                state(row);
        }
    }
    for (const rep of inv.representations) {
        requireMaterial(['original-capture', 'supplied-extraction', 'unknown-origin'].includes(rep.origin_kind), 'STATE', rowId(rep), 'origin_kind', 'unknown origin');
        requireMaterial(['utf8-text', 'opaque'].includes(rep.extraction_surface) && (rep.extraction_surface !== 'opaque' || rep.state !== 'available'), 'STATE', rowId(rep), 'extraction_surface', 'unsupported or falsely available surface');
        requireMaterial(inv.representations.filter((x) => x.source_id === rep.source_id).length === 1, 'INVENTORY', rowId(rep), 'source_id', 'one REP per SRC required');
        const carrier = context.carriers.get(rep.source_id);
        requireMaterial(carrier && carrier.representation_id === rowId(rep), 'INVENTORY', rowId(rep), 'source_id', 'missing capture');
        const capture = find(inv.provenance, rep.provenance_id, 'PROVENANCE');
        requireMaterial(capture.type === 'capture', 'PROVENANCE', rowId(rep), 'provenance_id', 'capture receipt required');
        sameRep(rep, capture, 'provenance_id');
        const roots = inv.objects.filter((x) => x.representation_id === rowId(rep) && x.kind === 'source');
        requireMaterial(roots.length === 1, 'INVENTORY', rowId(rep), 'root', 'one root source required');
        const rootBindings = objectBindings(context, roots[0]);
        requireMaterial(rootBindings.length === 1 && rootBindings[0].carrier_id === rep.source_id
            && rootBindings[0].start_byte === '0' && Number(rootBindings[0].end_byte) === carrier.bytes.length, 'INVENTORY', rowId(rep), 'root', 'root must bind complete capture');
    }
    const outputs = new Map();
    for (const p of inv.provenance) {
        const id = rowId(p), rep = find(inv.representations, p.representation_id);
        requireMaterial(['capture', 'supplied-structure', 'supplied-rendering'].includes(p.type)
            && [p.actor, p.tool, p.tool_version].every((v) => v?.trim() && v !== 'none'), 'PROVENANCE', id, 'type/actor/tool', 'missing provenance');
        requireMaterial((p.tool === 'unknown') === (p.tool_version === 'unknown'), 'PROVENANCE', id, 'tool_version', 'unknown identity must be explicit in both fields');
        const inputs = list(p.input_refs, id, 'input_refs', true), out = list(p.output_refs, id, 'output_refs', true);
        requireMaterial(out.length > 0 && (p.type === 'capture' ? inputs.length === 0 : inputs.includes(rep.source_id)), 'PROVENANCE', id, 'input_refs/output_refs', 'invalid provenance closure');
        for (const ref of [...inputs, ...out])
            requireMaterial(context.carriers.get(ref)?.representation_id === p.representation_id, 'PROVENANCE', id, 'refs', 'unknown or foreign carrier');
        for (const ref of out) {
            requireMaterial(!inputs.includes(ref) && !outputs.has(ref), 'PROVENANCE', id, 'output_refs', 'self-input or duplicate producer');
            outputs.set(ref, p);
        }
        if (p.type === 'capture') {
            requireMaterial(p.parameters_asset_id === 'none' && out.includes(rep.source_id), 'PROVENANCE', id, 'capture', 'invalid capture');
            for (const ref of out.filter((v) => v !== rep.source_id)) {
                const asset = find(inv.assets, ref, 'PROVENANCE');
                requireMaterial(asset.role === 'upstream-capture' || (ref === p.declaration_asset_id && asset.role === 'render-log'), 'PROVENANCE', id, 'output_refs', 'capture output must be upstream bytes or imported ID map');
            }
        }
        else if (p.type === 'supplied-structure') {
            requireMaterial(p.parameters_asset_id === 'none' && out.includes(p.declaration_asset_id)
                && find(inv.assets, p.declaration_asset_id, 'PROVENANCE').role === 'structure-export', 'PROVENANCE', id, 'declaration_asset_id', 'retained structure declaration required');
        }
        else {
            for (const key of ['parameters_asset_id', 'declaration_asset_id'])
                requireMaterial(out.includes(p[key])
                    && find(inv.assets, p[key], 'PROVENANCE').role === 'render-log', 'PROVENANCE', id, key, 'retained rendering receipt required');
        }
    }
    for (const asset of inv.assets) {
        requireMaterial(outputs.has(rowId(asset)), 'PROVENANCE', rowId(asset), 'output_refs', 'asset has no producer');
        const seen = new Set();
        function visit(ref) {
            requireMaterial(!seen.has(ref), 'PROVENANCE', rowId(asset), 'input_refs', 'cyclic derivation');
            seen.add(ref);
            for (const input of list(outputs.get(ref)?.input_refs || '[]', ref, 'input_refs'))
                visit(input);
            seen.delete(ref);
        }
        visit(rowId(asset));
    }
    for (const b of inv.bindings) {
        const id = rowId(b), carrier = context.carriers.get(b.carrier_id);
        requireMaterial(carrier && carrier.representation_id === b.representation_id, 'BINDING', id, 'carrier_id', 'missing or foreign carrier');
        const start = integer(b.start_byte, id, 'start_byte'), end = integer(b.end_byte, id, 'end_byte');
        requireMaterial(start <= end && end <= carrier.bytes.length, 'BINDING', id, 'offsets', 'out of bounds');
        const bytes = carrier.bytes.subarray(start, end);
        requireMaterial(carrier.encoding !== 'utf8' || (utf8(carrier.bytes.subarray(0, start)) && utf8(bytes)), 'BINDING', id, 'offsets', 'split UTF-8 code point');
        const rep = find(inv.representations, b.representation_id);
        requireMaterial(b.byte_role === (b.carrier_id === rep.source_id ? 'frozen-source-bytes' : 'retained-asset-bytes'), 'BINDING', id, 'byte_role', 'carrier role mismatch');
        requireMaterial(b.exact_bytes_base64 === (bytes.length ? bytes.toString('base64') : '""') && b.fragment_hash === materialHash(bytes), 'BINDING', id, 'exact_bytes_base64/fragment_hash', 'exact bytes disagree');
        let region = null;
        for (const kind of ['page', 'region'])
            if (b[`${kind}_id`] !== 'none') {
                const target = find(inv.objects, b[`${kind}_id`], 'COORDINATE');
                sameRep(b, target, `${kind}_id`);
                requireMaterial(target.kind === kind, 'COORDINATE', id, `${kind}_id`, 'wrong locator kind');
                if (kind === 'region')
                    region = target;
            }
        requireMaterial(!region || b.page_id === 'none' || coordinates(region).page_id === b.page_id, 'COORDINATE', id, 'page_id', 'region page mismatch');
    }
    for (const o of inv.objects) {
        const id = rowId(o), bs = objectBindings(context, o), p = find(inv.provenance, o.provenance_id, 'PROVENANCE');
        sameRep(o, p, 'provenance_id');
        for (const b of bs)
            sameRep(o, b, 'binding_ids');
        requireMaterial(o.content_hash === (bs.length ? materialFragmentsHash(bs.map((b) => bindingBytes(context, b))) : 'none'), 'BINDING', id, 'content_hash', 'ordered fragments disagree');
        if (p.type === 'capture') {
            const rep = find(inv.representations, o.representation_id);
            requireMaterial(o.kind === 'source' || (o.kind === 'text' && rep.extraction_surface === 'utf8-text'
                && inv.objects.filter((x) => x.representation_id === o.representation_id && x.kind === 'text' && x.provenance_id === rowId(p)).length === 1
                && bs.length === 1 && bs[0].carrier_id === rep.source_id && bs[0].start_byte === '0'
                && Number(bs[0].end_byte) === context.carriers.get(rep.source_id).bytes.length), 'PROVENANCE', id, 'provenance_id', 'capture cannot invent structure');
        }
        if (o.state === 'available') {
            if (['text', 'cell', 'header', 'caption', 'formal', 'image', 'chart-values'].includes(o.kind))
                requireMaterial(bs.length > 0, 'BINDING', id, 'binding_ids', 'available leaf needs bytes');
            else if (!['row', 'column'].includes(o.kind))
                requireMaterial(bs.length > 0 || inv.objects.some((child) => child.binding_ids !== '[]' && ancestors(inv, child).some((a) => rowId(a) === id)), 'BINDING', id, 'binding_ids', 'unbound container');
        }
        if (o.kind === 'image')
            requireMaterial(bs.every((b) => {
                const ast = inv.assets.find((a) => rowId(a) === b.carrier_id);
                return context.carriers.get(b.carrier_id)?.encoding === 'opaque' && (!ast || ast.role === 'rendered-image' || ast.role === 'upstream-capture');
            }), 'BINDING', id, 'binding_ids', 'image requires opaque image bytes');
        if (o.kind === 'chart-values')
            requireMaterial(bs.every((b) => context.carriers.get(b.carrier_id)?.encoding === 'utf8'), 'BINDING', id, 'binding_ids', 'chart values require supplied textual bytes');
    }
    coordinateObjects(context);
    for (const o of inv.objects) {
        const kind = o.kind === 'cell' ? 'header-for' : ['table', 'formal', 'figure'].includes(o.kind) ? 'caption-for' : null;
        if (kind)
            requireMaterial(inv.associations.filter((a) => a.subject_id === rowId(o) && a.kind === kind).length === 1, 'ASSOCIATION', rowId(o), kind, 'require one explicit association including absence/candidates');
    }
    for (const a of inv.associations) {
        const id = rowId(a), subject = find(inv.objects, a.subject_id, 'ASSOCIATION'), p = find(inv.provenance, a.provenance_id, 'PROVENANCE');
        sameRep(a, subject, 'subject_id');
        sameRep(a, p, 'provenance_id');
        requireMaterial(p.type !== 'capture', 'PROVENANCE', id, 'provenance_id', 'capture cannot author associations');
        requireMaterial(a.kind === 'header-for' ? subject.kind === 'cell'
            : a.kind === 'caption-for' && ['table', 'formal', 'figure'].includes(subject.kind), 'ASSOCIATION', id, 'kind', 'illegal association');
        const targets = list(a.target_ids, id, 'target_ids');
        requireMaterial((a.state !== 'available' || targets.length > 0) && (a.state !== 'unsupported' || targets.length === 0), 'ASSOCIATION', id, 'target_ids', 'association state/target mismatch');
        for (const ref of targets) {
            const target = find(inv.objects, ref, 'ASSOCIATION');
            sameRep(a, target, 'target_ids');
            requireMaterial(a.kind === 'header-for' ? target.kind === 'header' && target.parent_id === subject.parent_id : target.kind === 'caption', 'ASSOCIATION', id, 'target_ids', 'wrong target kind or table');
        }
    }
}
const IMPORT_TABLES = ['assets', 'provenance', 'bindings', 'objects', 'associations'];
const LIST_FIELDS = ['input_refs', 'output_refs', 'binding_ids', 'target_ids'];
export function representationInputPath(value) {
    requireMaterial(typeof value === 'string' && value.length > 0 && !/^[\\/]/u.test(value)
        && !/[\\:\0]/u.test(value) && value.split('/').every((part) => part && part !== '.' && part !== '..'), 'CAPTURE_HASH', REPRESENTATION_SUFFIX, 'input_path', 'expected normalized relative file path');
    return value;
}
export function parseSuppliedRepresentation(raw) {
    let parsed;
    try {
        parsed = parseStrictJson(raw, true);
    }
    catch {
        throw new RepresentationError('FORMAT', REPRESENTATION_SUFFIX, 'JSON', 'invalid UTF-8/JSON or duplicate key');
    }
    requireMaterial(exactKeys(parsed, ['format', 'source_path', 'origin_kind', 'extraction_surface', 'state', 'reason', ...IMPORT_TABLES])
        && parsed.format === SUPPLIED_REPRESENTATION_FORMAT, 'FORMAT', REPRESENTATION_SUFFIX, 'format/keys', 'unknown or malformed reserved descriptor');
    representationInputPath(parsed.source_path);
    for (const field of ['origin_kind', 'extraction_surface', 'state', 'reason'])
        requireMaterial(typeof parsed[field] === 'string', 'FORMAT', REPRESENTATION_SUFFIX, field, 'expected string');
    for (const key of IMPORT_TABLES) {
        const rows = parsed[key];
        requireMaterial(Array.isArray(rows), 'FORMAT', REPRESENTATION_SUFFIX, key, 'expected array');
        const header = MATERIAL_HEADERS[key].filter((v) => v !== 'representation_id').map((v) => v === 'locus' ? 'input_path' : v);
        const seen = new Set();
        for (const row of rows) {
            requireMaterial(exactKeys(row, header), 'FORMAT', REPRESENTATION_SUFFIX, key, 'unknown, missing, or reordered row fields');
            for (const field of header) {
                if (LIST_FIELDS.includes(field))
                    requireMaterial(Array.isArray(row[field]), 'FORMAT', String(row[header[0]]), field, 'expected JSON array');
                else if (field === 'coordinates')
                    requireMaterial(record(row[field]), 'FORMAT', String(row[header[0]]), field, 'expected coordinate object');
                else
                    requireMaterial(typeof row[field] === 'string', 'FORMAT', String(row[header[0]]), field, 'expected table scalar string');
            }
            const id = String(row[header[0]]);
            const family = { assets: 'AST', provenance: 'RPR', bindings: 'BND', objects: 'OBJ', associations: 'ASC' }[key];
            requireMaterial(idFor(id, family) && !seen.has(id), 'IDENTITY', id, header[0], 'invalid or duplicate local ID');
            seen.add(id);
            if (key === 'assets')
                representationInputPath(row.input_path);
            if (key === 'provenance')
                requireMaterial(row.type !== 'capture', 'PROVENANCE', id, 'type', 'capture is supplied by importer');
        }
    }
    const descriptor = parsed;
    const declarations = descriptor.provenance.filter((p) => Array.isArray(p.output_refs) && p.output_refs.includes('declaration'));
    requireMaterial(declarations.length === 1 && declarations[0].type === 'supplied-structure'
        && declarations[0].declaration_asset_id === 'declaration', 'PROVENANCE', REPRESENTATION_SUFFIX, 'declaration', 'one retained descriptor producer required');
    return descriptor;
}
function tableRecord(name, values) {
    return Object.fromEntries(MATERIAL_HEADERS[name].map((key) => [key, values[key]]));
}
function replaceReference(value, map) {
    if (typeof value === 'string')
        return map[value] || value;
    if (Array.isArray(value))
        return value.map((v) => replaceReference(v, map));
    return value;
}
function importedRow(name, row, rep, map) {
    const result = { representation_id: rep };
    for (const [field, value] of Object.entries(row)) {
        if (field === 'input_path') {
            const ext = String(value).split('.').at(-1) || 'bin';
            const suffix = /^[a-z0-9]{1,12}$/u.test(ext) ? ext : 'bin';
            result.locus = `${REPRESENTATION_ASSET_PATH}/${map[String(row.asset_id)]}.${suffix}`;
        }
        else if (field === 'coordinates') {
            const c = Object.fromEntries(Object.entries(value).map(([key, v]) => [key, key.endsWith('_ids') || key === 'page_id' ? replaceReference(v, map) : v]));
            result[field] = JSON.stringify(c);
        }
        else if (LIST_FIELDS.includes(field)) {
            const refs = replaceReference(value, map);
            result[field] = JSON.stringify(['input_refs', 'output_refs'].includes(field) ? [...refs].sort() : refs);
        }
        else if (field.endsWith('_id'))
            result[field] = String(replaceReference(value, map));
        else
            result[field] = field === 'exact_bytes_base64' && value === '' ? '""' : String(value);
    }
    return tableRecord(name, result);
}
export function prepareRepresentationCapture(inputs) {
    const inventory = emptyMaterialInventory(), assets = new Map();
    const sourceSchemes = new Map();
    const counters = {};
    const allocate = (family) => `${family}-${String(counters[family] = (counters[family] || 0) + 1).padStart(4, '0')}`;
    const carriers = new Map();
    for (const input of inputs) {
        requireMaterial(!sourceSchemes.has(input.source_id), 'INVENTORY', input.source_id, 'source_id', 'duplicate selected source');
        const descriptor = input.descriptor ? parseSuppliedRepresentation(input.descriptor) : null;
        const rep = allocate('REP'), capture = allocate('RPR');
        const extraction = descriptor?.extraction_surface || 'utf8-text';
        requireMaterial(extraction !== 'utf8-text' || utf8(input.bytes), 'CAPTURE_HASH', input.source_id, 'encoding', 'capture is not strict UTF-8');
        sourceSchemes.set(input.source_id, extraction === 'opaque' ? 'opaque-bytes' : 'md-lines');
        carriers.set(input.source_id, { bytes: input.bytes, encoding: extraction === 'opaque' ? 'opaque' : 'utf8', representation_id: rep });
        inventory.representations.push(tableRecord('representations', {
            representation_id: rep, source_id: input.source_id, origin_kind: descriptor?.origin_kind || 'unknown-origin',
            extraction_surface: extraction, state: descriptor?.state || 'available', reason: descriptor?.reason || 'none', provenance_id: capture,
        }));
        const captureRow = tableRecord('provenance', { provenance_id: capture, representation_id: rep, type: 'capture',
            actor: 'capture-importer', tool: 'stable-copy', tool_version: '1', input_refs: '[]', output_refs: JSON.stringify([input.source_id]),
            parameters_asset_id: 'none', declaration_asset_id: 'none' });
        inventory.provenance.push(captureRow);
        if (!descriptor || !input.descriptor) {
            const bnd = allocate('BND'), source = allocate('OBJ'), text = allocate('OBJ');
            inventory.bindings.push(tableRecord('bindings', { binding_id: bnd, representation_id: rep, carrier_id: input.source_id,
                start_byte: '0', end_byte: String(input.bytes.length), page_id: 'none', region_id: 'none', byte_role: 'frozen-source-bytes',
                fragment_hash: materialHash(input.bytes), exact_bytes_base64: input.bytes.length ? input.bytes.toString('base64') : '""' }));
            for (const [id, kind, parent] of [[source, 'source', 'none'], [text, 'text', source]]) {
                inventory.objects.push(tableRecord('objects', { object_id: id, representation_id: rep, kind, parent_id: parent,
                    state: 'available', reason: 'none', provenance_id: capture, binding_ids: JSON.stringify([bnd]),
                    content_hash: materialFragmentsHash([input.bytes]), coordinates: '{}' }));
            }
            continue;
        }
        const declarationId = allocate('AST'), mapId = allocate('AST');
        const localMap = {};
        const locals = IMPORT_TABLES.flatMap((key) => descriptor[key].map((row) => String(Object.values(row)[0]))).sort();
        for (const id of locals)
            localMap[id] = allocate(id.split('-')[0]);
        const mapping = { format: 'aleph-representation-id-map/v1', source_id: input.source_id, representation_id: rep,
            capture_id: capture, declaration_asset_id: declarationId, id_map: localMap };
        const mapBytes = Buffer.from(JSON.stringify(mapping));
        const map = { ...localMap, source: input.source_id, capture, declaration: declarationId };
        for (const [id, bytes, role] of [[declarationId, input.descriptor, 'structure-export'], [mapId, mapBytes, 'render-log']]) {
            const locus = `${REPRESENTATION_ASSET_PATH}/${id}.json`;
            inventory.assets.push(tableRecord('assets', { asset_id: id, representation_id: rep, role, locus,
                media_type: 'application/json', encoding: 'utf8', byte_length: String(bytes.length), content_hash: materialHash(bytes) }));
            assets.set(locus, bytes);
            carriers.set(id, { bytes, encoding: 'utf8', representation_id: rep });
        }
        const upstream = [];
        for (const name of IMPORT_TABLES)
            for (const row of [...descriptor[name]].sort((a, b) => String(Object.values(a)[0]).localeCompare(String(Object.values(b)[0]), 'en'))) {
                const imported = importedRow(name, row, rep, map);
                inventory[name].push(imported);
                if (name === 'assets') {
                    const bytes = input.assets?.get(String(row.input_path));
                    requireMaterial(bytes && bytes.length === Number(imported.byte_length) && materialHash(bytes) === imported.content_hash, 'CAPTURE_HASH', rowId(imported), 'content_hash/byte_length', 'supplied asset bytes disagree');
                    assets.set(imported.locus, bytes);
                    carriers.set(rowId(imported), { bytes, encoding: imported.encoding, representation_id: rep });
                    if (imported.role === 'upstream-capture')
                        upstream.push(rowId(imported));
                }
            }
        captureRow.output_refs = JSON.stringify([input.source_id, mapId, ...upstream].sort());
        captureRow.declaration_asset_id = mapId;
    }
    const context = { inventory, carriers, inventoryHash: materialHash(representationMarkdown(inventory)), uses: [] };
    validateMaterialInventory(context);
    return { inventory, assets, sourceSchemes };
}
function importedCorrespondence(context) {
    const inv = context.inventory;
    for (const rep of inv.representations) {
        const capture = find(inv.provenance, rep.provenance_id);
        if (capture.declaration_asset_id === 'none')
            continue;
        const mapAsset = find(inv.assets, capture.declaration_asset_id, 'INVENTORY');
        requireMaterial(mapAsset.role === 'render-log', 'INVENTORY', rowId(rep), 'declaration_asset_id', 'ID map must be render-log');
        const mapBytes = context.carriers.get(rowId(mapAsset)).bytes;
        const map = json(mapBytes.toString('utf8'), rowId(mapAsset), 'ID map');
        requireMaterial(exactKeys(map, ['format', 'source_id', 'representation_id', 'capture_id', 'declaration_asset_id', 'id_map'])
            && map.format === 'aleph-representation-id-map/v1' && map.source_id === rep.source_id
            && map.representation_id === rowId(rep) && map.capture_id === rowId(capture) && record(map.id_map), 'INVENTORY', rowId(rep), 'ID map', 'invalid map identity');
        const localMap = map.id_map;
        requireMaterial(Object.keys(localMap).join('\0') === Object.keys(localMap).sort().join('\0')
            && new Set(Object.values(localMap)).size === Object.values(localMap).length
            && Object.entries(localMap).every(([a, b]) => typeof b === 'string' && idFor(b, a.split('-')[0])), 'INVENTORY', rowId(rep), 'ID map', 'mapping must be sorted bijection preserving families');
        const raw = context.carriers.get(String(map.declaration_asset_id));
        requireMaterial(raw && raw.representation_id === rowId(rep), 'INVENTORY', rowId(rep), 'declaration', 'missing retained descriptor');
        const descriptor = parseSuppliedRepresentation(raw.bytes);
        for (const field of ['origin_kind', 'extraction_surface', 'state', 'reason'])
            requireMaterial(descriptor[field] === rep[field], 'INVENTORY', rowId(rep), field, 'capture differs from supplied declaration');
        const localIds = IMPORT_TABLES.flatMap((key) => descriptor[key].map((row) => String(Object.values(row)[0]))).sort();
        requireMaterial(JSON.stringify(localIds) === JSON.stringify(Object.keys(localMap)), 'INVENTORY', rowId(rep), 'ID map', 'missing or extra mapping');
        const replacements = { ...localMap, source: rep.source_id, capture: rowId(capture), declaration: String(map.declaration_asset_id) };
        for (const key of IMPORT_TABLES) {
            const expected = descriptor[key].map((row) => importedRow(key, row, rowId(rep), replacements));
            const omitted = new Set(key === 'assets' ? [rowId(mapAsset), String(map.declaration_asset_id)]
                : key === 'provenance' ? [rowId(capture)] : []);
            const actual = inv[key].filter((row) => row.representation_id === rowId(rep) && !omitted.has(rowId(row)));
            requireMaterial(expected.length === actual.length, 'INVENTORY', rowId(rep), key, 'unexplained or missing imported rows');
            for (const row of expected)
                requireMaterial(JSON.stringify(row) === JSON.stringify(actual.find((a) => rowId(a) === rowId(row))), 'INVENTORY', rowId(row), key, 'imported fields differ from raw declaration');
        }
    }
}
export function readRepresentationContext(model) {
    const raw = readMaterialFile(model.runDir, REPRESENTATION_PATH);
    requireMaterial(utf8(raw), 'FORMAT', REPRESENTATION_PATH, 'encoding', 'inventory must be UTF-8');
    const inventory = parseRepresentationInventory(raw.toString('utf8'));
    const context = { inventory, inventoryHash: materialHash(raw), carriers: new Map(), uses: [] };
    requireMaterial(inventory.representations.length === model.corpus.sources.length, 'INVENTORY', REPRESENTATION_PATH, 'source_id', 'one representation per admitted source');
    for (const source of model.corpus.sources) {
        const s = source.values, rep = inventory.representations.find((r) => r.source_id === s.sourceId);
        requireMaterial(rep, 'INVENTORY', s.sourceId, 'source_id', 'no representation');
        const bytes = readMaterialFile(model.runDir, s.locus.startsWith('corpus/') ? s.locus : `corpus/${s.locus}`);
        requireMaterial(materialHash(bytes) === s.contentHash, 'CAPTURE_HASH', s.sourceId, 'content_hash', 'source capture changed');
        requireMaterial(rep.extraction_surface === 'utf8-text' ? s.scheme === 'md-lines' && utf8(bytes) : s.scheme === 'opaque-bytes', 'STATE', s.sourceId, 'scheme', 'capture surface/encoding/scheme mismatch');
        context.carriers.set(s.sourceId, { bytes, encoding: rep.extraction_surface === 'utf8-text' ? 'utf8' : 'opaque', representation_id: rowId(rep) });
    }
    const loci = new Set();
    for (const asset of inventory.assets) {
        const id = rowId(asset);
        requireMaterial(new RegExp(`^${REPRESENTATION_ASSET_PATH}/${id}\\.[a-z0-9]{1,12}$`, 'u').test(asset.locus) && !loci.has(asset.locus), 'CAPTURE_HASH', id, 'locus', 'asset locus must match identity exactly');
        loci.add(asset.locus);
        requireMaterial(['upstream-capture', 'structure-export', 'rendered-text', 'rendered-image', 'render-log'].includes(asset.role)
            && ['utf8', 'opaque'].includes(asset.encoding) && Boolean(asset.media_type?.trim()), 'PROVENANCE', id, 'role/encoding/media_type', 'invalid asset declaration');
        requireMaterial(!['structure-export', 'rendered-text', 'render-log'].includes(asset.role) || asset.encoding === 'utf8', 'PROVENANCE', id, 'encoding', 'textual export requires UTF-8');
        requireMaterial(asset.role !== 'rendered-image' || asset.encoding === 'opaque', 'PROVENANCE', id, 'encoding', 'image must be opaque');
        const bytes = readMaterialFile(model.runDir, asset.locus);
        requireMaterial(integer(asset.byte_length, id, 'byte_length') === bytes.length && asset.content_hash === materialHash(bytes)
            && (asset.encoding !== 'utf8' || utf8(bytes)), 'CAPTURE_HASH', id, 'content_hash/byte_length', 'asset bytes differ or invalid encoding');
        context.carriers.set(id, { bytes, encoding: asset.encoding, representation_id: asset.representation_id });
    }
    if (existsSync(join(model.runDir, REPRESENTATION_ASSET_PATH))) {
        for (const name of readdirSync(join(model.runDir, REPRESENTATION_ASSET_PATH))) {
            requireMaterial(loci.has(`${REPRESENTATION_ASSET_PATH}/${name}`), 'INVENTORY', name, 'asset files', 'unlisted file/directory');
        }
    }
    validateMaterialInventory(context);
    importedCorrespondence(context);
    const usesPath = join(model.runDir, REPRESENTATION_USE_PATH);
    if (existsSync(usesPath)) {
        const bytes = readMaterialFile(model.runDir, REPRESENTATION_USE_PATH);
        requireMaterial(utf8(bytes), 'FORMAT', REPRESENTATION_USE_PATH, 'encoding', 'uses ledger must be strict UTF-8');
        const text = bytes.toString('utf8');
        marker(text, 'representation_use_format', REPRESENTATION_USE_FORMAT, REPRESENTATION_USE_PATH);
        context.uses = tableRows(text, 'uses', REPRESENTATION_USE_PATH);
        requireMaterial(parseTables(text).length === 1, 'FORMAT', REPRESENTATION_USE_PATH, 'tables', 'one use table required');
    }
    return context;
}
export function validateMaterialUseInput(value, canonical = true) {
    const keys = (item, fields) => canonical ? exactKeys(item, fields) : record(item) && JSON.stringify(Object.keys(item).sort()) === JSON.stringify([...fields].sort());
    requireMaterial(keys(value, ['requirements', 'use_state', 'fidelity_claim', 'limitation_refs', 'reason']), 'UNDECLARED_FEATURE', REPRESENTATION_USE_PATH, 'material_use', 'exact material use fields required');
    requireMaterial(Array.isArray(value.requirements) && value.requirements.length > 0, 'UNDECLARED_FEATURE', REPRESENTATION_USE_PATH, 'requirements', 'nonempty requirements required');
    const tuples = new Set();
    for (const req of value.requirements) {
        requireMaterial(keys(req, ['object_id', 'feature', 'binding_ids']) && typeof req.object_id === 'string'
            && idFor(req.object_id, 'OBJ') && MATERIAL_FEATURES.includes(req.feature)
            && Array.isArray(req.binding_ids) && req.binding_ids.every((id) => typeof id === 'string' && idFor(id, 'BND'))
            && new Set(req.binding_ids).size === req.binding_ids.length, 'UNDECLARED_FEATURE', REPRESENTATION_USE_PATH, 'requirements', 'invalid requirement tuple');
        const key = JSON.stringify(req);
        requireMaterial(!tuples.has(key), 'UNDECLARED_FEATURE', req.object_id, 'requirements', 'duplicate tuple');
        tuples.add(key);
    }
    requireMaterial(value.use_state === 'usable' || value.use_state === 'CANNOT_DETERMINE', 'STATE', REPRESENTATION_USE_PATH, 'use_state', 'unknown use state');
    requireMaterial(['none', 'exact-representation', 'gold'].includes(String(value.fidelity_claim))
        && value.fidelity_claim !== 'gold', 'FIDELITY', REPRESENTATION_USE_PATH, 'fidelity_claim', 'unknown or forbidden gold assertion');
    requireMaterial(Array.isArray(value.limitation_refs) && value.limitation_refs.every((id) => typeof id === 'string' && /^(REP|OBJ|ASC)-(?=\d*[1-9])\d{4,}$/u.test(id))
        && JSON.stringify(value.limitation_refs) === JSON.stringify([...new Set(value.limitation_refs)].sort()), 'USE_CLOSURE', REPRESENTATION_USE_PATH, 'limitation_refs', 'expected sorted unique limitations');
    requireMaterial(typeof value.reason === 'string' && (value.use_state === 'usable' ? value.reason === 'none'
        : value.reason.trim() && value.reason !== 'none' && value.limitation_refs.length > 0), 'STATE', REPRESENTATION_USE_PATH, 'reason', 'use state requires honest reason and limitations');
    return {
        requirements: value.requirements.map((req) => {
            const r = req;
            return { object_id: r.object_id, feature: r.feature, binding_ids: r.binding_ids };
        }),
        use_state: value.use_state, fidelity_claim: value.fidelity_claim,
        limitation_refs: value.limitation_refs, reason: value.reason,
    };
}
export function materialFeatureAvailable(context, requirement) {
    const inv = context.inventory, object = find(inv.objects, requirement.object_id, 'UNDECLARED_FEATURE');
    const selected = requirement.binding_ids.map((id) => find(inv.bindings, id, 'UNDECLARED_FEATURE'));
    const owned = list(object.binding_ids, rowId(object), 'binding_ids');
    requireMaterial(selected.every((b) => owned.includes(rowId(b))), 'UNDECLARED_FEATURE', rowId(object), 'binding_ids', 'binding not owned by object');
    requireMaterial(JSON.stringify(owned.filter((id) => requirement.binding_ids.includes(id))) === JSON.stringify(requirement.binding_ids), 'UNDECLARED_FEATURE', rowId(object), 'binding_ids', 'requirements must preserve declared binding order');
    const textual = (o) => objectBindings(context, o).length > 0
        && objectBindings(context, o).every((b) => context.carriers.get(b.carrier_id)?.encoding === 'utf8');
    const c = coordinates(object);
    switch (requirement.feature) {
        case 'text-bytes': return selected.length > 0 && selected.every((b) => context.carriers.get(b.carrier_id)?.encoding === 'utf8');
        case 'table-grid': return object.kind === 'table' && c.grid_state === 'available';
        case 'header-association':
        case 'caption-association': {
            const kind = requirement.feature === 'header-association' ? 'header-for' : 'caption-for';
            const association = inv.associations.find((a) => a.subject_id === rowId(object) && a.kind === kind);
            return Boolean(association && association.state === 'available' && list(association.target_ids, rowId(association), 'target_ids')
                .every((id) => { const target = find(inv.objects, id); return target.state === 'available' && textual(target); }));
        }
        case 'formal-structure': return object.kind === 'formal' && c.structure_state === 'available'
            && ['source-markup', 'renderer-export'].includes(String(c.notation))
            && (textual(object) || coordinateIds(c.structure_ids, object, 'structure_ids').some((id) => textual(find(inv.objects, id))));
        case 'image': return object.kind === 'image' && object.state === 'available' && objectBindings(context, object).length > 0;
        case 'chart-values': return object.kind === 'chart-values' ? textual(object)
            : object.kind === 'figure' && c.values_state === 'available' && coordinateIds(c.values_ids, object, 'values_ids').length > 0
                && coordinateIds(c.values_ids, object, 'values_ids').every((id) => { const target = find(inv.objects, id); return target.state === 'available' && textual(target); });
        case 'spatial-region': return object.kind === 'region' && c.page_id !== null && c.box !== null
            && coordinates(find(inv.objects, String(c.page_id))).space !== null;
        default: throw new RepresentationError('UNDECLARED_FEATURE', rowId(object), 'feature', 'unknown feature');
    }
}
function useInput(row) {
    return validateMaterialUseInput({
        requirements: json(row.requirements, rowId(row), 'requirements'),
        use_state: row.use_state, fidelity_claim: row.fidelity_claim,
        limitation_refs: json(row.limitation_refs, rowId(row), 'limitation_refs'), reason: row.reason,
    });
}
export function representationUseNeedsReview(context, input) {
    return input.requirements.some((req) => req.feature !== 'text-bytes' || req.binding_ids.some((id) => find(context.inventory.bindings, id).byte_role === 'retained-asset-bytes'));
}
export function representationUseSubjectJson(model, context, row) {
    const basis = list(row.basis_packet_ids, rowId(row), 'basis_packet_ids');
    let subject;
    if (row.subject_kind === 'PKT') {
        const p = model.packets.find((p) => p.values.packetId === row.subject_id)?.values;
        requireMaterial(p, 'USE_CLOSURE', rowId(row), 'subject_id', 'missing packet');
        subject = { source_id: p.sourceId, locator: p.locator, span_hash: p.spanHash, criterion: p.criterion };
    }
    else if (row.subject_kind === 'CC') {
        const c = model.claims.find((c) => c.values.claimId === row.subject_id)?.values;
        requireMaterial(c, 'USE_CLOSURE', rowId(row), 'subject_id', 'missing claim');
        subject = { normalized_claim: c.normalizedClaim, packets: c.packets.split(',').map((x) => x.trim()),
            sources: c.sources.split(',').map((x) => x.trim()), claim_type: c.claimType };
    }
    else if (row.subject_kind === 'REL') {
        const r = parseRelations(model).rows.find((r) => r.values.relationId === row.subject_id);
        requireMaterial(r, 'USE_CLOSURE', rowId(row), 'subject_id', 'missing relation');
        subject = JSON.parse(relationReviewSubjectJson(r.values));
    }
    else {
        find(context.inventory.objects, row.subject_id, 'USE_CLOSURE');
        subject = { object_id: row.subject_id, representation_inventory_hash: context.inventoryHash };
    }
    const fields = {};
    for (const field of MATERIAL_HEADERS.uses.slice(1, 11))
        fields[field] =
            ['basis_packet_ids', 'requirements', 'limitation_refs'].includes(field) ? json(row[field], rowId(row), field) : row[field];
    const hashes = basis.map((id) => {
        const records = model.exactEvidence.records.filter((r) => r.values.packetIds.split(',').map((s) => s.trim()).includes(id));
        requireMaterial(records.length === 1 && records[0].values.evidenceState === 'exact', 'USE_CLOSURE', rowId(row), 'basis_packet_ids', 'each packet needs its exact evidence record');
        return records[0].values.exactEvidenceHash;
    });
    return JSON.stringify({ format: 'aleph-representation-use-subject/v1', representation_inventory_hash: context.inventoryHash,
        ...fields, subject, packet_evidence_hashes: hashes });
}
export function representationUseDigest(model, context, row) {
    return materialHash(representationUseSubjectJson(model, context, row));
}
function useSources(model, context, row) {
    if (row.subject_kind === 'OBJ')
        return [find(context.inventory.representations, find(context.inventory.objects, row.subject_id).representation_id).source_id];
    return [...new Set(list(row.basis_packet_ids, rowId(row), 'basis_packet_ids').map((id) => {
            const packet = model.packets.find((p) => p.values.packetId === id);
            requireMaterial(packet, 'USE_CLOSURE', rowId(row), 'basis_packet_ids', 'unknown packet');
            return packet.values.sourceId;
        }))];
}
export function validateRepresentationUse(model, context, row, review = true) {
    requireMaterial(JSON.stringify(Object.keys(row).sort()) === JSON.stringify([...MATERIAL_HEADERS.uses].sort())
        && Object.values(row).every((v) => typeof v === 'string'), 'FORMAT', rowId(row), 'use', 'exact scalar use fields required');
    const id = rowId(row), input = useInput(row), inv = context.inventory;
    requireMaterial(['PKT', 'CC', 'REL', 'OBJ'].includes(row.subject_kind), 'USE_CLOSURE', id, 'subject_kind', 'unknown subject kind');
    requireMaterial(row.subject_kind === 'PKT' ? row.owner_stage === 'S2' : row.subject_kind === 'REL' ? row.owner_stage === 'S4'
        : row.subject_kind === 'CC' ? ['S3', 'S4'].includes(row.owner_stage) : ['S2', 'S3', 'S4'].includes(row.owner_stage), 'USE_CLOSURE', id, 'owner_stage', 'illegal write stage');
    requireMaterial(Boolean(row.established_by?.trim()) && row.established_by !== 'none', 'USE_CLOSURE', id, 'established_by', 'missing producer reference');
    const basis = list(row.basis_packet_ids, id, 'basis_packet_ids'), sources = useSources(model, context, row);
    requireMaterial(row.subject_kind === 'OBJ' || basis.length > 0, 'USE_CLOSURE', id, 'basis_packet_ids', 'empty canonical evidence basis');
    if (row.subject_kind === 'PKT')
        requireMaterial(JSON.stringify(basis) === JSON.stringify([row.subject_id]), 'USE_CLOSURE', id, 'basis_packet_ids', 'packet basis must be itself');
    if (row.subject_kind === 'CC') {
        const c = model.claims.find((c) => c.values.claimId === row.subject_id);
        requireMaterial(c && JSON.stringify(basis) === JSON.stringify(c.values.packets.split(',').map((p) => p.trim())), 'USE_CLOSURE', id, 'basis_packet_ids', 'claim provenance/order mismatch');
    }
    if (row.subject_kind === 'REL') {
        const relation = parseRelations(model).rows.find((r) => r.values.relationId === row.subject_id);
        requireMaterial(relation && JSON.stringify(basis) === JSON.stringify(parsePacketBasis(relation.values.basisPacketIds).ids), 'USE_CLOSURE', id, 'basis_packet_ids', 'relation basis/order mismatch');
    }
    requireMaterial(row.subject_kind === 'OBJ' || input.use_state === 'usable', 'USE_CLOSURE', id, 'use_state', 'CANNOT_DETERMINE candidates require OBJ receipts, not canonical packets/claims/relations');
    for (const ref of input.limitation_refs) {
        const target = find(ref.startsWith('REP-') ? inv.representations : ref.startsWith('OBJ-') ? inv.objects : inv.associations, ref, 'USE_CLOSURE');
        const rep = ref.startsWith('REP-') ? target : find(inv.representations, target.representation_id);
        requireMaterial(sources.includes(rep.source_id), 'USE_CLOSURE', id, 'limitation_refs', 'foreign-source limitation');
    }
    for (const requirement of input.requirements) {
        const object = find(inv.objects, requirement.object_id, 'UNDECLARED_FEATURE'), rep = find(inv.representations, object.representation_id);
        requireMaterial(sources.includes(rep.source_id), 'USE_CLOSURE', id, 'requirements', 'foreign source context');
        const available = materialFeatureAvailable(context, requirement);
        requireMaterial(available || input.use_state === 'CANNOT_DETERMINE', 'UNDECLARED_FEATURE', id, requirement.feature, 'unavailable feature requires CANNOT_DETERMINE');
        for (const bindingId of requirement.binding_ids) {
            const b = find(inv.bindings, bindingId), carrier = context.carriers.get(b.carrier_id);
            if (row.subject_kind !== 'OBJ' && b.byte_role === 'frozen-source-bytes') {
                const spans = [];
                for (const packetId of basis)
                    for (const fragment of model.exactEvidence.fragments.filter((f) => f.values.packetId === packetId && f.values.sourceId === rep.source_id)) {
                        const match = /^L([1-9]\d*)-L([1-9]\d*)$/u.exec(fragment.values.locator);
                        const source = model.corpus.sources.find((s) => s.values.sourceId === rep.source_id);
                        const path = source && sourceFilePath(model.runDir, source.values.locus);
                        const span = match && path ? mdLineSpan(path, Number(match[1]), Number(match[2])) : null;
                        requireMaterial(span?.startByte !== null && span?.endByte !== null && span, 'USE_CLOSURE', id, 'basis_packet_ids', 'unreopenable packet basis');
                        spans.push([span.startByte, span.endByte]);
                    }
                const capture = find(inv.provenance, rep.provenance_id);
                const defaultWhole = capture.declaration_asset_id === 'none' && object.kind === 'text' && b.start_byte === '0'
                    && Number(b.end_byte) === carrier.bytes.length;
                requireMaterial(defaultWhole ? spans.length > 0 : intervalCovered(Number(b.start_byte), Number(b.end_byte), spans), 'USE_CLOSURE', id, 'binding_ids', 'SRC binding outside exact packet-basis union');
                if (row.subject_kind === 'REL' && !defaultWhole) {
                    const relation = parseRelations(model).rows.find((r) => r.values.relationId === row.subject_id).values;
                    if (relation.recordState === 'asserted' && relation.targetKind === 'source-locus'
                        && relation.targetSourceId === b.carrier_id) {
                        const match = /^L([1-9]\d*)-L([1-9]\d*)$/u.exec(relation.targetLocator);
                        const source = model.corpus.sources.find((s) => s.values.sourceId === b.carrier_id);
                        const path = source && sourceFilePath(model.runDir, source.values.locus);
                        const target = match && path ? mdLineSpan(path, Number(match[1]), Number(match[2])) : null;
                        requireMaterial(target?.startByte !== null && target?.endByte !== null && target
                            && Number(b.start_byte) >= target.startByte && Number(b.end_byte) <= target.endByte, 'USE_CLOSURE', id, 'binding_ids', 'selected target SRC binding outside reopened relation target span');
                    }
                }
            }
        }
        if (input.fidelity_claim === 'exact-representation') {
            const named = ancestors(inv, object);
            const associated = inv.associations.filter((a) => a.subject_id === rowId(object));
            requireMaterial(input.use_state === 'usable' && available && rep.origin_kind === 'original-capture' && rep.state === 'available'
                && named.every((o) => o.state === 'available')
                && named.every((o) => objectBindings(context, o).every((b) => b.byte_role === 'frozen-source-bytes'))
                && associated.every((a) => a.state === 'available'), 'FIDELITY', id, 'fidelity_claim', 'capture fidelity preconditions not met');
        }
    }
    requireMaterial(row.review_subject_digest === representationUseDigest(model, context, row), 'USE_CLOSURE', id, 'review_subject_digest', 'reviewed immutable subject differs');
    const requiresReview = ['CC', 'REL'].includes(row.subject_kind) && representationUseNeedsReview(context, input);
    if (!review)
        return;
    requireMaterial(!requiresReview || row.reviewed_by !== 'none', 'USE_CLOSURE', id, 'reviewed_by', 'non-text/asset use requires exact L2F review');
    if (row.reviewed_by !== 'none') {
        const path = `verification/harness/${row.reviewed_by}.md`;
        let verdict;
        try {
            verdict = parseStructuredVerifierRecord(readMaterialFile(model.runDir, path), path);
        }
        catch {
            throw new RepresentationError('USE_CLOSURE', id, 'reviewed_by', 'missing/malformed verifier record');
        }
        requireMaterial(verdict.target === `representation-use-subject:${row.review_subject_digest}`
            && verdict.verdict === 'upheld', 'USE_CLOSURE', id, 'reviewed_by', 'exact upheld verdict required');
        if (requiresReview)
            requireMaterial(verdict.lens === 'L2F' && verdict.stage === row.owner_stage, 'USE_CLOSURE', id, 'reviewed_by', 'L2F stage/charter mismatch');
    }
}
export function representationLimitations(model, context) {
    const rows = [];
    for (const key of ['representations', 'objects', 'associations'])
        for (const r of context.inventory[key]) {
            if (r.state === 'available')
                continue;
            const rep = key === 'representations' ? r : find(context.inventory.representations, r.representation_id);
            rows.push({ limitation_ref: rowId(r), source_id: rep.source_id, representation_state: r.state, reason: r.reason });
        }
    for (const use of context.uses.filter((r) => r.use_state === 'CANNOT_DETERMINE')) {
        for (const source of useSources(model, context, use))
            rows.push({
                limitation_ref: rowId(use), source_id: source, representation_state: 'CANNOT_DETERMINE', reason: use.reason,
            });
    }
    return rows.sort((a, b) => {
        const aa = `${a.limitation_ref}\0${a.source_id}`, bb = `${b.limitation_ref}\0${b.source_id}`;
        return aa < bb ? -1 : aa > bb ? 1 : 0;
    });
}
export const LIMITATION_HEADERS = ['limitation_ref', 'source_id', 'representation_state', 'reason'];
export function representationUseClosureHash(model) {
    const log = model.runLog;
    if (!log)
        return null;
    const events = runLogEvents(log);
    const c1 = events.filter((event, index) => log.lines.slice(event.line, events[index + 1]?.line ? events[index + 1].line - 1 : undefined)
        .some((line) => line.trim() === 'closure_phase: S4-C1-relations-closed'));
    const lines = log.lines.filter((line) => line.includes('representation_use_closure_hash:'));
    if (!c1.length) {
        requireMaterial(lines.length === 0, 'FROZEN_WRITE', 'run-log.md', 'representation_use_closure_hash', 'seal forbidden before C1');
        return null;
    }
    requireMaterial(c1.length === 1 && c1[0].stage === 'S4' && lines.length === 1 && /^representation_use_closure_hash: sha256:[0-9a-f]{64}\r?$/u.test(lines[0]), 'FROZEN_WRITE', 'run-log.md', 'representation_use_closure_hash', 'one exact C1 seal required');
    const index = events.indexOf(c1[0]);
    requireMaterial(log.lines.slice(c1[0].line, events[index + 1]?.line ? events[index + 1].line - 1 : undefined).includes(lines[0]), 'FROZEN_WRITE', 'run-log.md', 'representation_use_closure_hash', 'seal outside C1 event');
    return lines[0].trim().slice('representation_use_closure_hash: '.length);
}
export function validateRepresentationRun(model) {
    requireMaterial(usesFormalLayoutBindings(model.manifest?.runFormatVersion || ''), 'FORMAT', REPRESENTATION_PATH, 'run_format_version', 'material capability is not active');
    const frozen = model.manifest?.states.some((s) => s.values.state !== 'DRAFT' && s.values.state !== 'BLOCKED');
    const sealLines = model.manifest?.lines.filter((line) => line.includes('representation_inventory_hash:')) || [];
    if (frozen || sealLines.length)
        requireMaterial(sealLines.length === 1
            && sealLines[0] === `- representation_inventory_hash: ${materialHash(readMaterialFile(model.runDir, REPRESENTATION_PATH))}`, 'CAPTURE_HASH', 'run-manifest.md', 'representation_inventory_hash', 'missing/mismatched inventory seal');
    const context = readRepresentationContext(model);
    const extracting = reachedState(model, 'DISTILLING') || Boolean(model.packets.length || model.claims.length
        || model.sourceWalk.intervals.length || runLogEvents(model.runLog).some((event) => /^S(?:[2-9]|1[0-3])$/u.test(event.stage)));
    if (extracting) {
        assertRepresentationExtractionSupported(context);
        requireMaterial(existsSync(join(model.runDir, REPRESENTATION_USE_PATH)), 'USE_CLOSURE', REPRESENTATION_USE_PATH, 'uses', 'S2 requires use ledger');
    }
    const ids = new Set(), subjects = new Set();
    for (const row of context.uses) {
        requireMaterial(idFor(rowId(row), 'USE') && !ids.has(rowId(row)), 'IDENTITY', rowId(row), 'use_id', 'invalid or duplicate use ID');
        ids.add(rowId(row));
        const key = `${row.subject_kind}:${row.subject_id}`;
        requireMaterial(row.subject_kind === 'OBJ' || !subjects.has(key), 'USE_CLOSURE', rowId(row), 'subject_id', 'duplicate canonical receipt');
        subjects.add(key);
        validateRepresentationUse(model, context, row);
    }
    for (const [kind, ids] of [
        ['PKT', model.packets.map((p) => p.values.packetId)],
        ['CC', model.claims.map((c) => c.values.claimId)],
        ['REL', parseRelations(model).rows.map((r) => r.values.relationId)],
    ])
        for (const id of ids)
            requireMaterial(subjects.has(`${kind}:${id}`), 'USE_CLOSURE', id, 'receipt', 'canonical subject has no receipt');
    const closure = representationUseClosureHash(model);
    const afterC1 = reachedState(model, 'ASSEMBLED') || hasRunLogEvent(model.runLog, 'S5', 'entry')
        || closurePhasesFromText(model.runLog?.text || '').some((phase) => phase !== 'S4-C1-relations-closed');
    requireMaterial(!afterC1 || closure !== null, 'FROZEN_WRITE', REPRESENTATION_USE_PATH, 'closure_hash', 'C1 or later requires the retained use seal');
    if (closure)
        requireMaterial(closure === materialHash(readMaterialFile(model.runDir, REPRESENTATION_USE_PATH)), 'FROZEN_WRITE', REPRESENTATION_USE_PATH, 'closure_hash', 'uses changed after retained C1');
    if (['ASSEMBLED', 'VERIFIED', 'ACCEPTED', 'PROJECTING', 'PROJECTION-ACCEPTED'].some((s) => reachedState(model, s))) {
        const tables = parseTables(envelopeSection(model.precis?.text || '', 17));
        const matching = tables.filter((t) => t.header[0] === 'limitation_ref');
        const expected = representationLimitations(model, context);
        requireMaterial(matching.length === 1 && JSON.stringify(matching[0].header) === JSON.stringify(LIMITATION_HEADERS), 'USE_CLOSURE', 'precis.md', 'section 17', 'one canonical limitation table required');
        requireMaterial(JSON.stringify(matching[0].rows.map((r) => r.cells.map(unescapeCell)))
            === JSON.stringify(expected.map((r) => LIMITATION_HEADERS.map((k) => r[k]))), 'USE_CLOSURE', 'precis.md', 'section 17', 'limitation union mismatch');
    }
    return context;
}
export function assertRepresentationExtractionSupported(context) {
    requireMaterial(!context.inventory.representations.some((r) => r.extraction_surface === 'opaque'), 'UNSUPPORTED_EXTRACTION_SURFACE', REPRESENTATION_PATH, 'extraction_surface', 'opaque capture cannot progress to S2; retain limitation or use a successor run');
}
export function requiresMaterialUsePlan(path) {
    return ['ledgers/packet-index.md', 'ledgers/claim-inventory.md', 'ledgers/relations.md', REPRESENTATION_USE_PATH].includes(path);
}
export function assertMaterialWriteWindow(model, stage, ownerStage) {
    requireMaterial(usesFormalLayoutBindings(model.manifest?.runFormatVersion || ''), 'FORMAT', REPRESENTATION_USE_PATH, 'version', 'material capability required');
    requireMaterial(stage === ownerStage && ['S2', 'S3', 'S4'].includes(stage) && representationUseClosureHash(model) === null, 'FROZEN_WRITE', REPRESENTATION_USE_PATH, 'owner_stage', 'material write window closed');
}
export function materialSubjectWritePaths(kind) {
    const paths = {
        PKT: ['ledgers/packet-index.md', 'ledgers/source-walk.md', 'ledgers/lineage.md'],
        CC: ['ledgers/claim-inventory.md', 'ledgers/lineage.md'],
        REL: ['ledgers/relations.md'], OBJ: [],
    };
    requireMaterial(kind in paths, 'USE_CLOSURE', kind, 'subject_kind', 'unknown material subject kind');
    return paths[kind];
}
export function validateMaterialPlanIdentity(plan, row, stage) {
    const allowed = row ? [...materialSubjectWritePaths(row.subject_kind), REPRESENTATION_USE_PATH] : ['run-log.md'];
    requireMaterial(row ? row.owner_stage === stage
        && plan.key === `representation-use-subject:${row.review_subject_digest}:${row.subject_kind}:${row.subject_id}`
        : stage === 'S4' && /^representation-use-closure:sha256:[0-9a-f]{64}$/u.test(plan.key), 'FROZEN_WRITE', plan.key, 'identity', 'transaction key or stage differs from reserved subject');
    requireMaterial(plan.writes.length > 0 && new Set(plan.writes.map((w) => w.path)).size === plan.writes.length
        && plan.writes.every((w) => allowed.includes(w.path)), 'FROZEN_WRITE', plan.key, 'paths', 'transaction escaped Core material write surface');
}
export function planRepresentationUseWrite(options) {
    const context = validateRepresentationRun(options.model);
    const { row } = options;
    assertMaterialWriteWindow(options.model, options.stage, row.owner_stage);
    validateRepresentationUse(options.proposedModel, context, row);
    const key = `representation-use-subject:${row.review_subject_digest}:${row.subject_kind}:${row.subject_id}`;
    const previous = context.uses.find((r) => r.review_subject_digest === row.review_subject_digest
        && r.subject_kind === row.subject_kind && r.subject_id === row.subject_id);
    if (previous) {
        requireMaterial(MATERIAL_HEADERS.uses.every((key) => previous[key] === row[key]), 'USE_CLOSURE', rowId(row), 'idempotency', 'same key with different receipt bytes');
        return { key, inventory_hash: context.inventoryHash, writes: [] };
    }
    requireMaterial(!context.uses.some((r) => rowId(r) === rowId(row)
        || (row.subject_kind !== 'OBJ' && r.subject_kind === row.subject_kind && r.subject_id === row.subject_id)), 'USE_CLOSURE', rowId(row), 'reservation', 'canonical identity already has different use');
    const path = join(options.model.runDir, REPRESENTATION_USE_PATH);
    const before = existsSync(path) ? readFileSync(path) : Buffer.alloc(0);
    for (const write of options.subjectWrites) {
        requireMaterial(materialSubjectWritePaths(row.subject_kind).includes(write.path), 'FROZEN_WRITE', write.path, 'subjectWrites', 'outside material subject write surface');
        const current = existsSync(join(options.model.runDir, write.path)) ? readMaterialFile(options.model.runDir, write.path) : Buffer.alloc(0);
        const next = Buffer.from(write.after_base64, 'base64');
        const retained = current.toString('utf8').split('\n');
        const proposed = next.toString('utf8').split('\n');
        let cursor = 0;
        for (const line of proposed)
            if (line === retained[cursor])
                cursor++;
        requireMaterial(write.before_hash === materialHash(current) && write.after_hash === materialHash(next)
            && cursor === retained.length, 'FROZEN_WRITE', write.path, 'preimage', 'subject writes may insert rows but cannot replace retained lines');
    }
    const after = before.length === 0 ? Buffer.from(representationUsesMarkdown([row]))
        : Buffer.concat([before, Buffer.from(`${before.at(-1) === 10 ? '' : '\n'}${materialTableMarkdown(MATERIAL_HEADERS.uses, [row]).split('\n').slice(2).join('\n')}`)]);
    return { key, inventory_hash: context.inventoryHash, writes: [...options.subjectWrites, {
                path: REPRESENTATION_USE_PATH, before_hash: materialHash(before), after_base64: after.toString('base64'), after_hash: materialHash(after),
            }] };
}
export function validateMaterialProducerReturn(value) {
    if (!record(value))
        return;
    const inspect = (item) => {
        if (!record(item))
            return;
        if ('material_use' in item)
            validateMaterialUseInput(item.material_use, false);
        if (Array.isArray(item.flags))
            materialRefusalFlags(item.flags.filter((v) => typeof v === 'string'));
        for (const child of Object.values(item)) {
            if (Array.isArray(child))
                child.forEach(inspect);
            else if (record(child))
                inspect(child);
        }
    };
    inspect(value);
    if (Array.isArray(value.material_findings))
        for (const finding of value.material_findings) {
            requireMaterial(record(finding) && JSON.stringify(Object.keys(finding).sort()) === '["material_use","object_id"]'
                && typeof finding.object_id === 'string' && idFor(finding.object_id, 'OBJ'), 'UNDECLARED_FEATURE', 'worker return', 'material_findings', 'malformed material finding');
            requireMaterial(validateMaterialUseInput(finding.material_use, false).use_state === 'CANNOT_DETERMINE', 'UNDECLARED_FEATURE', finding.object_id, 'material_findings', 'finding must preserve non-affirmative candidate');
        }
}
/** A recognized downstream refusal halts writing; retained raw return is the evidence. */
export function assertMaterialReturnWritable(value) {
    const visit = (item) => {
        if (!record(item))
            return;
        if (Array.isArray(item.flags))
            requireMaterial(materialRefusalFlags(item.flags.filter((v) => typeof v === 'string')).length === 0, 'UNDECLARED_FEATURE', 'worker return', 'flags', 'CANNOT_DETERMINE requires unresolved handling or halt before writing');
        for (const child of Object.values(item)) {
            if (Array.isArray(child))
                child.forEach(visit);
            else
                visit(child);
        }
    };
    visit(value);
}
/** Bind the writer's requirements to an actual retained producer proposal. */
export function assertMaterialUseProduced(value, row) {
    const expected = useInput(row);
    let found = false;
    const visit = (item) => {
        if (!record(item))
            return;
        if ('material_use' in item) {
            const actual = validateMaterialUseInput(item.material_use, false);
            if (JSON.stringify(actual) === JSON.stringify(expected)
                && (row.subject_kind !== 'OBJ' || item.object_id === row.subject_id))
                found = true;
        }
        for (const child of Object.values(item)) {
            if (Array.isArray(child))
                child.forEach(visit);
            else
                visit(child);
        }
    };
    visit(value);
    requireMaterial(found, 'USE_CLOSURE', rowId(row), 'requirements', 'writer requirements absent from producer return');
    assertMaterialReturnWritable(value);
}
export function assertMaterialReviewUpheld(value, digest) {
    requireMaterial(materialReviewUseState(value) !== 'CANNOT_DETERMINE', 'USE_CLOSURE', 'L2F', 'use_state', 'CANNOT_DETERMINE blocks affirmative use; retain the missing-material finding');
    requireMaterial(record(value) && value.verdict === 'upheld'
        && /^sha256:[0-9a-f]{64}$/u.test(digest), 'USE_CLOSURE', 'L2F', 'review', 'review does not uphold this reserved material subject');
}
export function materialReviewUseState(value) {
    requireMaterial(record(value) && ['upheld', 'refuted', 'cannot-determine'].includes(String(value.verdict)), 'STATE', 'L2F', 'verdict', 'unknown material review verdict');
    return value.verdict === 'cannot-determine' ? 'CANNOT_DETERMINE' : value.verdict === 'upheld' ? 'usable' : null;
}
export function materialFindingRows(model, value, stage, establishedBy) {
    validateMaterialProducerReturn(value);
    const context = validateRepresentationRun(model);
    if (!record(value) || !Array.isArray(value.material_findings))
        return [];
    let next = Math.max(0, ...context.uses.map((r) => Number(r.use_id.slice(4))));
    return value.material_findings.flatMap((entry) => {
        const finding = entry, input = validateMaterialUseInput(finding.material_use, false);
        const row = {
            use_id: `USE-${String(++next).padStart(4, '0')}`, owner_stage: stage, subject_kind: 'OBJ', subject_id: String(finding.object_id),
            basis_packet_ids: '[]', requirements: JSON.stringify(input.requirements), use_state: input.use_state,
            fidelity_claim: input.fidelity_claim, limitation_refs: JSON.stringify(input.limitation_refs), reason: input.reason,
            established_by: establishedBy, review_subject_digest: '', reviewed_by: 'none',
        };
        row.review_subject_digest = representationUseDigest(model, context, row);
        if (context.uses.some((r) => r.subject_kind === 'OBJ' && r.subject_id === row.subject_id
            && r.review_subject_digest === row.review_subject_digest))
            return [];
        validateRepresentationUse(model, context, row);
        return [row];
    });
}
/** A derived, bounded reviewer view; never a second representation authority. */
export function representationReviewView(model, context, row) {
    validateRepresentationUse(model, context, row, false);
    const inv = context.inventory, objects = new Set(), bindings = new Set();
    const associations = new Set();
    const add = (id, material) => {
        const object = find(inv.objects, id);
        if (material)
            list(object.binding_ids, id, 'binding_ids').forEach((b) => bindings.add(b));
        if (objects.has(id))
            return;
        objects.add(id);
        if (object.parent_id !== 'none')
            add(object.parent_id, false);
        const coords = coordinates(object);
        for (const value of Object.values(coords))
            for (const ref of Array.isArray(value) ? value : [value]) {
                if (typeof ref === 'string' && idFor(ref, 'OBJ'))
                    add(ref, true);
            }
        for (const assoc of inv.associations.filter((a) => a.subject_id === id)) {
            associations.add(rowId(assoc));
            list(assoc.target_ids, rowId(assoc), 'target_ids').forEach((ref) => add(ref, true));
        }
    };
    for (const req of useInput(row).requirements) {
        add(req.object_id, true);
        req.binding_ids.forEach((b) => bindings.add(b));
    }
    const reps = new Set([...objects].map((id) => find(inv.objects, id).representation_id));
    const packetIds = list(row.basis_packet_ids, rowId(row), 'basis_packet_ids');
    const packets = packetIds.map((id) => ({
        packet_id: id,
        fragments: model.exactEvidence.fragments.filter((f) => f.values.packetId === id).map((f) => {
            const source = model.corpus.sources.find((s) => s.values.sourceId === f.values.sourceId);
            const match = /^L([1-9]\d*)-L([1-9]\d*)$/u.exec(f.values.locator);
            const path = sourceFilePath(model.runDir, source.values.locus);
            requireMaterial(path && match, 'USE_CLOSURE', id, 'locator', 'unreopenable review packet');
            const span = mdLineSpan(path, Number(match[1]), Number(match[2]));
            const bytes = context.carriers.get(f.values.sourceId).bytes.subarray(span.startByte, span.endByte);
            return { source_id: f.values.sourceId, locator: f.values.locator, start_byte: span.startByte, end_byte: span.endByte,
                content_hash: materialHash(bytes), bytes_base64: bytes.toString('base64') };
        }),
    }));
    // Ancestor coordinates are necessary; ancestor whole-source bytes are not.
    const selectedBindings = inv.bindings.filter((b) => bindings.has(rowId(b)));
    const boundAssets = new Set(selectedBindings.filter((b) => b.carrier_id.startsWith('AST-')).map((b) => b.carrier_id));
    const assets = new Set(), provenanceIds = new Set();
    const addAsset = (id) => {
        if (assets.has(id))
            return;
        assets.add(id);
        const producer = inv.provenance.find((p) => list(p.output_refs, rowId(p), 'output_refs').includes(id));
        addProvenance(rowId(producer));
    };
    const addProvenance = (id) => {
        if (provenanceIds.has(id))
            return;
        provenanceIds.add(id);
        const provenance = find(inv.provenance, id);
        list(provenance.input_refs, id, 'input_refs').filter((ref) => ref.startsWith('AST-')).forEach(addAsset);
        for (const field of ['parameters_asset_id', 'declaration_asset_id']) {
            if (provenance[field] !== 'none')
                addAsset(provenance[field]);
        }
        if (provenance.type === 'capture') {
            list(provenance.output_refs, id, 'output_refs').filter((ref) => ref.startsWith('AST-')).forEach(addAsset);
        }
    };
    boundAssets.forEach(addAsset);
    inv.objects.filter((o) => objects.has(rowId(o))).forEach((o) => addProvenance(o.provenance_id));
    inv.associations.filter((a) => associations.has(rowId(a))).forEach((a) => addProvenance(a.provenance_id));
    inv.provenance.filter((p) => p.type === 'capture' && reps.has(p.representation_id)).forEach((p) => addProvenance(rowId(p)));
    const provenance = inv.provenance.filter((p) => provenanceIds.has(rowId(p)));
    // Raw import declarations can disclose unrelated objects. Show their identity;
    // show exact bytes for selected bindings and the retained origin/render logs.
    return JSON.stringify({
        format: 'aleph-representation-review-view/v1',
        target: `representation-use-subject:${row.review_subject_digest}`,
        subject: JSON.parse(representationUseSubjectJson(model, context, row)),
        packets,
        representations: inv.representations.filter((r) => reps.has(rowId(r))),
        objects: inv.objects.filter((o) => objects.has(rowId(o))),
        bindings: selectedBindings.map((b) => b.byte_role === 'frozen-source-bytes'
            ? Object.fromEntries(Object.entries(b).filter(([key]) => key !== 'exact_bytes_base64')) : b),
        associations: inv.associations.filter((a) => associations.has(rowId(a))),
        provenance,
        assets: inv.assets.filter((a) => assets.has(rowId(a))).map((a) => ({
            ...a,
            ...(a.role === 'structure-export' && !boundAssets.has(rowId(a)) ? {}
                : { bytes_base64: context.carriers.get(rowId(a)).bytes.toString('base64') }),
        })),
        limitations: representationLimitations(model, context).filter((l) => useSources(model, context, row).includes(l.source_id)),
    });
}
export function materialRefusalFlags(flags) {
    return flags.filter((flag) => flag.startsWith('CANNOT_DETERMINE:source-representation:')).map((flag) => {
        const match = /^CANNOT_DETERMINE:source-representation:((?:REP|OBJ|ASC|USE)-(?=\d*[1-9])\d{4,}):(.+)$/u.exec(flag);
        requireMaterial(match && MATERIAL_FEATURES.includes(match[2]), 'UNDECLARED_FEATURE', 'worker return', 'flags', 'invalid material refusal');
        return { id: match[1], feature: match[2] };
    });
}
export function selectRepresentationInventory(inventory, sourceIds) {
    const selected = new Set(inventory.representations.filter((r) => sourceIds.includes(r.source_id)).map(rowId));
    requireMaterial(selected.size === sourceIds.length, 'INVENTORY', REPRESENTATION_PATH, 'source_id', 'freeze selection missing source');
    const result = emptyMaterialInventory();
    for (const key of Object.keys(result))
        result[key] = inventory[key].filter((r) => selected.has(r.representation_id));
    return result;
}
