const ID_FAMILY_PATTERNS = {
    RUN: String.raw `RUN-[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*`,
    PKT: String.raw `PKT-\d+`,
    CC: String.raw `CC-\d+`,
    SRC: String.raw `SRC-\d+`,
    PC: String.raw `PC-\d+`,
    RC: String.raw `RC-\d+`,
    REF: String.raw `REF-\d+`,
    STM: String.raw `STM-\d+`,
    VER: String.raw `VER-\d+`,
    NB: String.raw `NB-\d+`,
    PRJ: String.raw `PRJ-\d+`,
};
export function normalizeHeader(value) {
    return String(value || '')
        .replace(/[`*]/g, '')
        .replace(/_/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .toLowerCase();
}
// Keep the legacy checker's hardened optional-outer-pipe behavior.
export function tableCells(line) {
    if (!line.includes('|'))
        return null;
    const raw = line.split('|');
    if (raw.length < 2)
        return null;
    if (raw[0].trim() === '')
        raw.shift();
    if (raw.length > 0 && raw[raw.length - 1].trim() === '')
        raw.pop();
    if (raw.length === 0)
        return null;
    return raw.map((cell) => cell.trim());
}
export function isSeparatorRow(cells) {
    return cells.length > 0 && cells.every((cell) => {
        const compact = cell.replace(/\s/g, '');
        return /^:?-{3,}:?$/.test(compact) || /^-+$/.test(compact);
    });
}
export function parseTables(text, file = '') {
    const lines = text.split('\n');
    const tables = [];
    for (let i = 0; i < lines.length - 1; i++) {
        const header = tableCells(lines[i]);
        const separator = tableCells(lines[i + 1]);
        if (!header || !separator || !isSeparatorRow(separator))
            continue;
        const rows = [];
        let end = i + 1;
        for (let j = i + 2; j < lines.length; j++) {
            const cells = tableCells(lines[j]);
            if (!cells || isSeparatorRow(cells))
                break;
            rows.push({ file, line: j + 1, raw: lines[j], cells });
            end = j;
        }
        tables.push({
            file,
            line: i + 1,
            header,
            normalizedHeader: header.map(normalizeHeader),
            rows,
        });
        i = end;
    }
    return tables;
}
export function findTable(tables, expectedHeader) {
    const expected = expectedHeader.map(normalizeHeader);
    return tables.find((table) => (table.normalizedHeader.length === expected.length
        && table.normalizedHeader.every((cell, index) => cell === expected[index]))) || null;
}
export function findTableByFirstHeader(tables, ...names) {
    const expected = new Set(names.map(normalizeHeader));
    return tables.find((table) => {
        const firstHeader = table.normalizedHeader[0];
        return firstHeader !== undefined && expected.has(firstHeader);
    }) || null;
}
export function headingSection(text, startRe) {
    const lines = text.split('\n');
    let start = -1;
    let level = 0;
    for (let i = 0; i < lines.length; i++) {
        if (startRe.test(lines[i])) {
            start = i;
            level = (lines[i].match(/^(#+)/)?.[1] || '##').length;
            break;
        }
    }
    if (start === -1)
        return '';
    let end = lines.length;
    for (let i = start + 1; i < lines.length; i++) {
        const match = lines[i].match(/^(#+)\s/);
        if (match && match[1].length <= level) {
            end = i;
            break;
        }
    }
    return lines.slice(start, end).join('\n');
}
export function envelopeSection(text, number) {
    return headingSection(text, new RegExp(`^##\\s+${number}\\.\\s`));
}
export function parseBulletFields(text) {
    const fields = new Map();
    const locations = new Map();
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].match(/^\s*-\s*([A-Za-z][A-Za-z0-9 _-]*):\s*(.*)$/);
        if (!match)
            continue;
        const key = normalizeHeader(match[1]);
        if (!fields.has(key)) {
            fields.set(key, match[2].trim());
            locations.set(key, i + 1);
        }
    }
    return { fields, locations };
}
export function parseFieldTable(tables) {
    const table = findTable(tables, ['field', 'value']);
    if (!table) {
        return {
            table: null,
            fields: new Map(),
            rows: new Map(),
        };
    }
    const fields = new Map();
    const rows = new Map();
    for (const row of table.rows) {
        if (row.cells.length < 2)
            continue;
        const key = normalizeHeader(row.cells[0]);
        if (!fields.has(key)) {
            fields.set(key, row.cells[1].trim());
            rows.set(key, row);
        }
    }
    return { table, fields, rows };
}
export function parseFencedBlock(text, language) {
    const escaped = language.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    const matches = [...text.matchAll(new RegExp(`^\\\`\\\`\\\`${escaped}\\s*\\n([\\s\\S]*?)^\\\`\\\`\\\`\\s*$`, 'gm'))];
    if (matches.length !== 1)
        return null;
    return matches[0]?.[1] ?? null;
}
export function idsIn(value, family) {
    const source = family
        ? ID_FAMILY_PATTERNS[family]
        : `(?:${Object.values(ID_FAMILY_PATTERNS).join('|')})`;
    if (!source)
        return [];
    const pattern = new RegExp(`\\b(?:${source})\\b`, 'g');
    return [...String(value || '').matchAll(pattern)].map((match) => match[0]);
}
export function commaIds(value, family) {
    const ids = idsIn(value, family);
    const residue = String(value || '')
        .replace(new RegExp(`\\b${family}-\\d+\\b`, 'g'), '')
        .replace(/[,\s;]+/g, '');
    return { ids, clean: residue === '' };
}
export function numberedEnvelopeHeadings(text) {
    const found = [];
    for (const line of text.split('\n')) {
        const match = line.match(/^##\s+(\d+)\.\s/);
        if (match)
            found.push(Number(match[1]));
    }
    return found;
}
export function renderedParagraphs(text) {
    const blocks = text
        .replace(/\r\n?/g, '\n')
        .split(/\n[ \t]*\n/)
        .map((block) => block.trim())
        .filter(Boolean);
    const paragraphs = [];
    let section = '0';
    let paragraph = 0;
    for (const block of blocks) {
        const heading = block.match(/^#{1,6}\s+(.+)$/);
        if (heading && !heading[1].includes('\n')) {
            const headingText = heading[1];
            const numbered = headingText.match(/^(\d+(?:\.\d+)*)[.)]?\s*/);
            section = numbered ? numbered[1] : normalizeHeader(headingText).replace(/\s+/g, '-');
            paragraph = 0;
            continue;
        }
        paragraph += 1;
        paragraphs.push({ anchor: `§${section} ¶${paragraph}`, section, paragraph, text: block });
    }
    return paragraphs;
}
