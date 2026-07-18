import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { isAbsolute, join, normalize, relative, resolve } from 'node:path';
import { idsIn, normalizeHeader } from './markdown.js';
export function location(row) {
    const located = row;
    return `${located.file}:${located.line}`;
}
export function pathIsWithin(parent, child) {
    const rel = relative(resolve(parent), resolve(child));
    return rel === '' || (!rel.startsWith('..') && !isAbsolute(rel));
}
export function normalizeSha256(value) {
    const match = String(value || '').trim().match(/^(?:sha256:)?([a-fA-F0-9]{64})$/);
    return match ? match[1].toLowerCase() : null;
}
export function sha256(bytes) {
    return createHash('sha256').update(bytes).digest('hex');
}
export function parseTimestamp(value) {
    const match = String(value || '').trim().match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?)?(?:Z| UTC|[+-]\d{2}:\d{2})?$/);
    if (!match)
        return null;
    const parts = match.slice(1, 7).map((part) => Number(part || 0));
    const [year, month, day, hour, minute, second] = parts;
    if (month < 1 || month > 12 || day < 1 || day > 31
        || hour > 23 || minute > 59 || second > 59)
        return null;
    const fractionalNanoseconds = Number((match[7] || '').padEnd(9, '0'));
    return [...parts, fractionalNanoseconds];
}
export function compareTimestamp(left, right) {
    for (let i = 0; i < Math.max(left.length, right.length); i++) {
        const difference = (left[i] || 0) - (right[i] || 0);
        if (difference !== 0)
            return Math.sign(difference);
    }
    return 0;
}
export function sourceFilePath(runDir, locus) {
    const clean = String(locus || '').trim().replace(/^`|`$/g, '');
    if (!clean || isAbsolute(clean))
        return null;
    const candidate = clean.startsWith('corpus/')
        ? join(runDir, clean)
        : join(runDir, 'corpus', clean);
    const normalized = normalize(candidate);
    return pathIsWithin(join(runDir, 'corpus'), normalized) ? normalized : null;
}
export function mdLineSpan(path, start, end) {
    if (!existsSync(path))
        return null;
    const bytes = readFileSync(path);
    const starts = [0];
    for (let i = 0; i < bytes.length; i++) {
        if (bytes[i] === 0x0a)
            starts.push(i + 1);
    }
    let lineCount = starts.length;
    if (bytes.length > 0 && bytes[bytes.length - 1] === 0x0a)
        lineCount -= 1;
    if (bytes.length === 0)
        lineCount = 0;
    if (start < 1 || end < start || end > lineCount) {
        return { bytes: null, lineCount };
    }
    const startOffset = starts[start - 1];
    let endOffset;
    if (end < lineCount) {
        endOffset = starts[end];
    }
    else {
        endOffset = bytes.length > 0 && bytes[bytes.length - 1] === 0x0a
            ? bytes.length - 1
            : bytes.length;
    }
    return { bytes: bytes.subarray(startOffset, endOffset), lineCount };
}
export function makeIndexes(model) {
    const maps = {
        RUN: new Map(),
        SRC: new Map(),
        PKT: new Map(),
        CC: new Map(),
        PC: new Map(),
        RC: new Map(),
        REF: new Map(),
        STM: new Map(),
        VER: new Map(),
        NB: new Map(),
        PRJ: new Map(),
    };
    const manifest = model.manifest;
    if (manifest && /^RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/.test(manifest.runId || '')) {
        maps.RUN.set(manifest.runId, manifest.runIdRow);
    }
    for (const source of model.corpus.sources) {
        if (/^SRC-\d+$/.test(source.values.sourceId))
            maps.SRC.set(source.values.sourceId, source);
    }
    for (const packet of model.packets) {
        if (/^PKT-\d+$/.test(packet.values.packetId))
            maps.PKT.set(packet.values.packetId, packet);
    }
    for (const claim of model.claims) {
        if (/^CC-\d+$/.test(claim.values.claimId))
            maps.CC.set(claim.values.claimId, claim);
    }
    for (const tag of model.tags) {
        if (/^PC-\d+$/.test(tag.values.tag))
            maps.PC.set(tag.values.tag, tag);
    }
    for (const card of model.cards) {
        if (/^RC-\d+$/.test(card.id))
            maps.RC.set(card.id, card);
    }
    for (const referent of model.referents) {
        if (/^REF-\d+$/.test(referent.values.refId))
            maps.REF.set(referent.values.refId, referent);
    }
    for (const row of model.matrix) {
        if (/^STM-\d+$/.test(row.values.stmId))
            maps.STM.set(row.values.stmId, row);
    }
    for (const boundary of model.boundaries) {
        if (/^NB-\d+$/.test(boundary.values.boundaryId)) {
            maps.NB.set(boundary.values.boundaryId, boundary);
        }
    }
    for (const projection of model.projections) {
        if (/^PRJ-\d+$/.test(projection.projectionId)) {
            maps.PRJ.set(projection.projectionId, projection.projectionIdRow);
        }
    }
    for (const file of model.files) {
        if (!file.relativePath.startsWith('verification/harness/'))
            continue;
        for (const id of idsIn(file.text, 'VER')) {
            if (!maps.VER.has(id))
                maps.VER.set(id, { file: file.relativePath, line: 1 });
        }
    }
    return maps;
}
export function duplicateDefinitions(model) {
    const families = [
        {
            family: 'SRC',
            definitions: model.corpus.sources.map((row) => ({ id: row.values.sourceId, row })),
        },
        {
            family: 'PKT',
            definitions: model.packets.map((row) => ({ id: row.values.packetId, row })),
        },
        {
            family: 'CC',
            definitions: model.claims.map((row) => ({ id: row.values.claimId, row })),
        },
        {
            family: 'PC',
            definitions: model.tags.map((row) => ({ id: row.values.tag, row })),
        },
        {
            family: 'REF',
            definitions: model.referents.map((row) => ({ id: row.values.refId, row })),
        },
        {
            family: 'STM',
            definitions: model.matrix.map((row) => ({ id: row.values.stmId, row })),
        },
        {
            family: 'NB',
            definitions: model.boundaries.map((row) => ({ id: row.values.boundaryId, row })),
        },
        {
            family: 'PRJ',
            definitions: model.projections
                .filter((projection) => projection.commission?.fieldTable)
                .flatMap((projection) => projection.commission.fieldTable.table.rows
                .filter((row) => normalizeHeader(row.cells[0]) === 'projection id')
                .map((row) => ({ row, id: row.cells[1] || '' }))),
        },
    ];
    const duplicates = [];
    for (const { family, definitions } of families) {
        const seen = new Map();
        for (const { id, row } of definitions) {
            if (!new RegExp(`^${family}-\\d+$`).test(id))
                continue;
            const first = seen.get(id);
            if (first)
                duplicates.push({
                    family, id, row, first,
                });
            else
                seen.set(id, row);
        }
    }
    const cards = new Map();
    for (const card of model.cards) {
        if (!card.id)
            continue;
        const first = cards.get(card.id);
        if (first)
            duplicates.push({
                family: 'RC', id: card.id, row: card, first,
            });
        else
            cards.set(card.id, card);
    }
    return duplicates;
}
export function activeClaims(model) {
    return model.claims.filter((claim) => claim.values.status === 'active');
}
export function activeRows(rows) {
    return rows.filter((row) => row.values.status === 'active');
}
export function fieldValue(card, name) {
    return card.fieldTable.fields.get(normalizeHeader(name)) || '';
}
export function allStatusRows(model) {
    const rows = [];
    const appendLedgerPaths = new Set([
        'ledgers/packet-index.md',
        'ledgers/claim-inventory.md',
        'ledgers/merge-map.md',
        'ledgers/evidence-roles.md',
        'ledgers/negative-boundaries.md',
    ]);
    for (const [path, document] of model.documents.entries()) {
        if (!appendLedgerPaths.has(path))
            continue;
        if (!document)
            continue;
        for (const table of document.tables) {
            const index = table.normalizedHeader.indexOf('status');
            if (index === -1)
                continue;
            for (const row of table.rows) {
                const id = row.cells.find((cell) => /^(?:PKT|CC|PC|RC|REF|STM|VER|NB)-\d+$/.test(cell)) || '';
                rows.push({
                    ...row,
                    id,
                    status: row.cells[index] || '',
                });
            }
        }
    }
    return rows;
}
export function firstRunLogEntry(document, stage) {
    if (!document)
        return null;
    for (let i = 0; i < document.lines.length; i++) {
        const match = document.lines[i].match(/^##\s+(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d{1,9})?)?)?(?:Z| UTC|[+-]\d{2}:\d{2})?)\s+[—-]\s+(S\d+[ab]?)\s+[—-]\s+(.+)$/);
        if (match && match[2].toUpperCase() === stage.toUpperCase()) {
            return { timestamp: match[1], event: match[3], line: i + 1 };
        }
    }
    return null;
}
export function reachedState(model, state) {
    return Boolean(model.manifest?.states.some((row) => row.values.state.trim() === state));
}
export function resolveRenderedPath(runDir, value) {
    const clean = String(value || '').trim().replace(/^`|`$/g, '');
    if (!clean || isAbsolute(clean))
        return null;
    const path = normalize(join(runDir, clean));
    return pathIsWithin(runDir, path) ? path : null;
}
