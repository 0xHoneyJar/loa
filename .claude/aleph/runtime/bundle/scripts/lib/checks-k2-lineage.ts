import {
  firstRunLogEntry,
  location,
  makeIndexes,
  reachedState,
} from './check-helpers.ts';
import {
  LINEAGE_FORMAT,
  LINEAGE_TYPES,
  lineageCurrentClaimIds,
  lineageCurrentPacketIds,
  parseLineage,
  parseUnitIds,
} from './lineage.ts';
import { idsIn } from './markdown.ts';
import type { ResultCollector } from './results.ts';
import {
  SUPPORTED_RUN_FORMAT_VERSIONS,
  usesLineage,
} from './run-model.ts';
import type { ClaimRow, RunModel } from './run-model.ts';

function sameSet(left: readonly string[], right: readonly string[]): boolean {
  const a = new Set(left);
  const b = new Set(right);
  return a.size === b.size && [...a].every((value) => b.has(value));
}

function isSubstantive(value: string): boolean {
  const clean = value.trim();
  return Boolean(clean) && clean !== 'none';
}

function claimPackets(claim: ClaimRow | undefined): Set<string> {
  return new Set(claim ? idsIn(claim.values.packets, 'PKT') : []);
}

function setContainsAll(container: ReadonlySet<string>, required: ReadonlySet<string>): boolean {
  return [...required].every((id) => container.has(id));
}

function lineageApplies(model: RunModel): boolean {
  return reachedState(model, 'DISTILLING')
    || reachedState(model, 'ASSEMBLED')
    || reachedState(model, 'VERIFIED')
    || reachedState(model, 'ACCEPTED')
    || reachedState(model, 'PROJECTING')
    || reachedState(model, 'PROJECTION-ACCEPTED')
    || Boolean(firstRunLogEntry(model.runLog, 'S2'))
    || model.packets.length > 0;
}

export function runK2Lineage(results: ResultCollector, model: RunModel): void {
  results.run('K2.15', 'lineage and lineage-current closure', (fail) => {
    const version = model.manifest?.runFormatVersion || '';
    const lineage = parseLineage(model);
    const structurePresent = Boolean(lineage.document || lineage.format || lineage.table || lineage.rows.length);

    if (!usesLineage(version)) {
      if (structurePresent) {
        fail(
          `run format ${version || '(pre-versioned)'} must not be reinterpreted as ${LINEAGE_FORMAT}`,
        );
      }
      if (version && !(SUPPORTED_RUN_FORMAT_VERSIONS as readonly string[]).includes(version)) {
        fail(`lineage activation cannot determine unsupported run_format_version "${version}"`);
      }
      return `lineage is not applicable to run format ${version || '(pre-versioned)'}`;
    }

    if (!lineage.document) {
      if (lineageApplies(model)) {
        fail(`run format ${version} requires ledgers/lineage.md once S2 begins`);
      }
      return `lineage is not applicable before S2 in run format ${version}`;
    }

    const markerCount = lineage.document.lines.filter(
      (line) => /^\s*-\s*lineage[_ -]format\s*:/i.test(line),
    ).length;
    if (markerCount !== 1 || lineage.format !== LINEAGE_FORMAT) {
      fail(`run format ${version} requires lineage_format ${LINEAGE_FORMAT} exactly once`);
    }
    if (lineage.tables.length !== 1) {
      fail(`run format ${version} requires exactly one canonical lineage event table; found ${lineage.tables.length}`);
      return 'typed lineage rows and lineage-current closure are structurally valid';
    }

    const indexes = makeIndexes(model);
    const claims = indexes.CC;
    const packets = indexes.PKT;
    const lineageIds = new Set<string>();
    const terminalizedBy = new Map<string, string>();
    const parsedRows: Array<{
      id: string;
      type: string;
      predecessors: string[];
      successors: string[];
      family: 'PKT' | 'CC' | null;
    }> = [];

    for (const row of lineage.rows) {
      const {
        lineageId,
        ownerStage,
        type,
        predecessors: predecessorText,
        successors: successorText,
        basis,
        establishedBy,
      } = row.values;
      if (!/^LIN-\d+$/.test(lineageId)) {
        fail(`${lineageId || 'lineage row'} lineage_id must be LIN-<digits> at ${location(row)}`);
      }
      if (lineageIds.has(lineageId)) {
        fail(`${lineageId || 'lineage row'} is defined more than once at ${location(row)}`);
      } else if (lineageId) {
        lineageIds.add(lineageId);
      }
      if (!['S2', 'S3', 'S4'].includes(ownerStage)) {
        fail(`${lineageId || 'lineage row'} owner_stage must be S2, S3, or S4`);
      }
      if (!(LINEAGE_TYPES as readonly string[]).includes(type)) {
        fail(`${lineageId || 'lineage row'} type "${type || '(blank)'}" is unsupported`);
      }
      if (!isSubstantive(basis)) {
        fail(`${lineageId || 'lineage row'} basis must be substantive`);
      }
      if (!isSubstantive(establishedBy)) {
        fail(`${lineageId || 'lineage row'} established_by must be substantive`);
      }

      const predecessors = parseUnitIds(predecessorText);
      const successors = parseUnitIds(successorText, true);
      if (!predecessors.clean || predecessors.ids.length === 0) {
        fail(`${lineageId || 'lineage row'} predecessors must be a nonempty comma-separated PKT/CC list`);
      }
      if (!successors.clean) {
        fail(`${lineageId || 'lineage row'} successors must be a comma-separated PKT/CC list or none`);
      }
      if (new Set(predecessors.ids).size !== predecessors.ids.length) {
        fail(`${lineageId || 'lineage row'} predecessors contain duplicate unit ids`);
      }
      if (new Set(successors.ids).size !== successors.ids.length) {
        fail(`${lineageId || 'lineage row'} successors contain duplicate unit ids`);
      }
      if (predecessors.clean && predecessors.ids.length > 0 && !predecessors.family) {
        fail(`${lineageId || 'lineage row'} predecessors mix packet and claim families`);
      }
      if (successors.clean && successors.ids.length > 0 && !successors.family) {
        fail(`${lineageId || 'lineage row'} successors mix packet and claim families`);
      }

      const family = predecessors.family;
      const predecessorCount = predecessors.ids.length;
      const successorCount = successors.ids.length;
      const sameFamily = successorCount === 0 || family === successors.family;
      if (!sameFamily) {
        fail(`${lineageId || 'lineage row'} changes unit family across one lineage event`);
      }
      if ((type === 'split') && !(predecessorCount === 1 && successorCount >= 2 && sameFamily)) {
        fail(`${lineageId || 'lineage row'} split requires 1 -> 2+ within one unit family`);
      }
      if ((type === 'merge' || type === 'duplicate') && !(
        predecessorCount >= 2
        && successorCount === 1
        && family === 'CC'
        && successors.family === 'CC'
      )) {
        fail(`${lineageId || 'lineage row'} ${type || 'merge/duplicate'} requires 2+ CC -> 1 new CC`);
      }
      if ((type === 'replace' || type === 'supersede') && !(
        predecessorCount === 1 && successorCount === 1 && sameFamily && family !== null
      )) {
        fail(`${lineageId || 'lineage row'} ${type || 'replacement'} requires 1 -> 1 within one unit family`);
      }
      if ((type === 'reject' || type === 'exclude') && !(
        predecessorCount === 1 && successorCount === 0 && family !== null
      )) {
        fail(`${lineageId || 'lineage row'} ${type || 'terminal event'} requires 1 -> 0`);
      }
      if (type === 'no-claim' && !(
        predecessorCount === 1 && successorCount === 0 && family === 'PKT'
      )) {
        fail(`${lineageId || 'lineage row'} no-claim requires exactly one PKT predecessor and no successor`);
      }

      const newlyTerminalized: string[] = [];
      for (const id of predecessors.ids) {
        const home = id.startsWith('PKT-') ? packets : claims;
        if (!home.has(id)) fail(`${lineageId || 'lineage row'} predecessor ${id} does not resolve`);
        const prior = terminalizedBy.get(id);
        if (prior) fail(`${id} is terminalized by both ${prior} and ${lineageId || 'another lineage row'}`);
        else newlyTerminalized.push(id);
      }
      for (const id of successors.ids) {
        const home = id.startsWith('PKT-') ? packets : claims;
        if (!home.has(id)) fail(`${lineageId || 'lineage row'} successor ${id} does not resolve`);
        const terminalizingEvent = terminalizedBy.get(id);
        if (terminalizingEvent) {
          fail(
            `${lineageId || 'lineage row'} resurrects ${id} after it was terminalized by ${terminalizingEvent}; re-establishment requires a new identifier`,
          );
        }
      }
      const overlap = predecessors.ids.filter((id) => successors.ids.includes(id));
      if (overlap.length > 0) {
        fail(`${lineageId || 'lineage row'} uses predecessor(s) as successor(s): ${overlap.join(', ')}`);
      }
      for (const id of newlyTerminalized) {
        terminalizedBy.set(id, lineageId || '(malformed lineage row)');
      }

      if (type === 'no-claim' && predecessors.ids.length === 1) {
        const packetId = predecessors.ids[0];
        const claiming = model.claims.filter((claim) => idsIn(claim.values.packets, 'PKT').includes(packetId));
        if (claiming.length > 0) {
          fail(`${lineageId || 'lineage row'} declares ${packetId} no-claim but ${claiming.map((claim) => claim.values.claimId).join(', ')} cite it`);
        }
      }

      parsedRows.push({
        id: lineageId,
        type,
        predecessors: predecessors.ids,
        successors: successors.ids,
        family,
      });
    }

    const graph = new Map<string, string[]>();
    for (const row of parsedRows) {
      for (const predecessor of row.predecessors) {
        if (!graph.has(predecessor)) graph.set(predecessor, []);
        graph.get(predecessor)!.push(...row.successors);
      }
    }
    const visiting = new Set<string>();
    const visited = new Set<string>();
    const visit = (id: string): boolean => {
      if (visiting.has(id)) return true;
      if (visited.has(id)) return false;
      visiting.add(id);
      for (const next of graph.get(id) || []) {
        if (visit(next)) return true;
      }
      visiting.delete(id);
      visited.add(id);
      return false;
    };
    for (const id of graph.keys()) {
      if (visit(id)) {
        fail(`lineage graph contains a cycle reachable from ${id}`);
        break;
      }
    }

    for (const row of parsedRows) {
      if ((row.type === 'merge' || row.type === 'duplicate') && row.successors.length === 1) {
        const successor = claims.get(row.successors[0]);
        if (!successor) continue;
        const successorPackets = claimPackets(successor);
        const predecessorUnion = new Set<string>();
        for (const predecessorId of row.predecessors) {
          for (const packetId of claimPackets(claims.get(predecessorId))) predecessorUnion.add(packetId);
        }
        if (!setContainsAll(successorPackets, predecessorUnion)) {
          const missing = [...predecessorUnion].filter((id) => !successorPackets.has(id));
          fail(`${row.id || row.type} successor ${row.successors[0]} drops predecessor packet provenance: ${missing.join(', ')}`);
        }
      }
      if (row.type === 'split' && row.family === 'CC' && row.predecessors.length === 1) {
        const predecessorPackets = claimPackets(claims.get(row.predecessors[0]));
        const aggregate = new Set<string>();
        for (const successorId of row.successors) {
          const successorPackets = claimPackets(claims.get(successorId));
          if (successorPackets.size === 0) {
            fail(`${row.id || 'split'} successor ${successorId} has no packet provenance`);
          }
          for (const packetId of successorPackets) aggregate.add(packetId);
        }
        if (!setContainsAll(aggregate, predecessorPackets)) {
          const missing = [...predecessorPackets].filter((id) => !aggregate.has(id));
          fail(`${row.id || 'split'} aggregate successor provenance drops ${missing.join(', ')}`);
        }
      }
      if (row.type === 'split' && row.family === 'PKT' && row.predecessors.length === 1) {
        const predecessor = packets.get(row.predecessors[0]);
        if (!predecessor) continue;
        for (const successorId of row.successors) {
          const successor = packets.get(successorId);
          if (successor && successor.values.sourceId !== predecessor.values.sourceId) {
            fail(`${row.id || 'packet split'} moves ${successorId} to another frozen source`);
          }
        }
      }
    }

    const currentPacketIds = lineageCurrentPacketIds(model);
    const currentClaimIds = lineageCurrentClaimIds(model);
    for (const claimId of currentClaimIds) {
      const claim = claims.get(claimId);
      if (!claim) continue;
      if (claim.values.status !== 'active') {
        fail(`${claimId} is lineage-current but durable status is "${claim.values.status || '(blank)'}"`);
      }
      for (const packetId of idsIn(claim.values.packets, 'PKT')) {
        if (!currentPacketIds.has(packetId)) {
          fail(`${claimId} is lineage-current but cites non-current packet ${packetId}`);
        }
      }
    }

    const s3Closed = Boolean(
      model.runLog?.lines.some((line) => /^##\s+.+\s+[—-]\s+S3\s+[—-]\s+exit\b/iu.test(line))
      || firstRunLogEntry(model.runLog, 'S4')
      || firstRunLogEntry(model.runLog, 'S5')
      || reachedState(model, 'ASSEMBLED')
      || reachedState(model, 'VERIFIED')
      || reachedState(model, 'ACCEPTED')
      || reachedState(model, 'PROJECTING')
      || reachedState(model, 'PROJECTION-ACCEPTED')
    );
    if (s3Closed) {
      const claimedPackets = new Set<string>();
      for (const claim of model.claims) {
        for (const packetId of idsIn(claim.values.packets, 'PKT')) claimedPackets.add(packetId);
      }
      for (const packet of model.packets) {
        const packetId = packet.values.packetId;
        if (!claimedPackets.has(packetId) && !terminalizedBy.has(packetId)) {
          fail(`${packetId} silently disappears after S3 closure: it is cited by no claim and has no lineage closure`);
        }
      }
    }

    const activeMerges = model.merges.filter((row) => row.values.status === 'active');
    for (const merge of activeMerges) {
      const absorbed = idsIn(merge.values.absorbs, 'CC');
      const matches = parsedRows.some((row) => (
        ['merge', 'duplicate'].includes(row.type)
        && row.successors.length === 1
        && row.successors[0] === merge.values.canonical
        && sameSet(row.predecessors, absorbed)
      ));
      if (!matches) {
        fail(`merge-map ${merge.values.canonical} has no matching merge/duplicate lineage event`);
      }
    }
    for (const row of parsedRows.filter((candidate) => ['merge', 'duplicate'].includes(candidate.type))) {
      const matches = activeMerges.some((merge) => (
        row.successors.length === 1
        && merge.values.canonical === row.successors[0]
        && sameSet(idsIn(merge.values.absorbs, 'CC'), row.predecessors)
      ));
      if (!matches) {
        fail(`${row.id || row.type} has no matching active merge-map row`);
      }
    }

    return 'typed lineage, provenance conservation, packet closure, and lineage-current claim/packet closure are structurally valid';
  });
}
