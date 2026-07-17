#!/usr/bin/env node
import { existsSync, lstatSync, readFileSync, } from 'node:fs';
import { dirname, isAbsolute, join, posix, resolve, } from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyBundle } from '../../../scripts/assemble-bundles.js';
import { validateCoreBoundary } from '../../../scripts/validate-core-boundary.js';
import { LOA_ADAPTER_ID, LOA_BUNDLE_ID, LOA_HOST_FORMAT, LOA_INSTALLED_BUNDLE_ROOT, LOA_INSTALL_LOCK_PATH, LOA_MODEL_SLOTS, LOA_PROFILE_FORMAT, LOA_REQUIRED_HOST_CAPABILITIES, LOA_ROLE_IDS, LOA_RUN_ROOT, } from './types.js';
const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_ROOT = resolve(dirname(SCRIPT_PATH), '../../..');
const ADAPTER_ID = LOA_ADAPTER_ID;
const ADAPTER_ROOT = 'adapters/loa';
const MANIFEST_PATH = `${ADAPTER_ROOT}/adapter.manifest.json`;
const INSTALLATION_MAP_PATH = `${ADAPTER_ROOT}/installation.map.json`;
const COMMAND_PATH = `${ADAPTER_ROOT}/command/loa-aleph.md`;
const SKILL_PATH = `${ADAPTER_ROOT}/skill/loa-aleph/SKILL.md`;
const PROFILE_PATH = `${ADAPTER_ROOT}/profiles/loa-default.json`;
const CLI_PATH = `${ADAPTER_ROOT}/src/cli.ts`;
const LAUNCHER_PATH = `${ADAPTER_ROOT}/src/launcher.ts`;
const COMPILED_LAUNCHER_PATH = 'runtime-js/adapters/loa/src/launcher.js';
const INSTALLER_PATH = `${ADAPTER_ROOT}/src/installer.ts`;
const PREFLIGHT_PATH = `${ADAPTER_ROOT}/src/preflight.ts`;
const CAPABILITY_KEYS = [
    'durable_file_io',
    'frozen_corpus_snapshots',
    'fresh_context_workers',
    'blind_bundles',
    'validated_structured_returns',
    'single_writer_ledgers',
    'deterministic_checker_invocation',
    'human_authority_gates',
    'durable_pause_resume',
    'exact_model_identity',
    'immutable_runtime_snapshot',
    'host_model_effort_mapping',
    'immutable_bundle_installation',
];
const HOST_CAPABILITY_KEYS = LOA_REQUIRED_HOST_CAPABILITIES;
const MODEL_SLOT_KEYS = LOA_MODEL_SLOTS;
const ROLE_KEYS = LOA_ROLE_IDS;
const REQUIRED_ADAPTER_PATHS = [
    MANIFEST_PATH,
    INSTALLATION_MAP_PATH,
    COMMAND_PATH,
    SKILL_PATH,
    PROFILE_PATH,
    CLI_PATH,
    LAUNCHER_PATH,
    INSTALLER_PATH,
    PREFLIGHT_PATH,
    COMPILED_LAUNCHER_PATH,
];
const REQUIRED_CORE_PATHS = [
    'AGENTS.md',
    'adapter-protocol/README.md',
    'adapter-protocol/adapter.schema.json',
    'adapter-protocol/capability-contract.md',
    'docs/decisions/0004-core-adapter-and-bundle-boundary.md',
    'docs/architecture/02-system-architecture.md',
    'docs/architecture/04-pipeline-stages-and-dod.md',
    'docs/architecture/08-runbook-agent-mode.md',
    'docs/architecture/prompts/README.md',
    'docs/architecture/prompts/orchestrator.md',
    'docs/architecture/prompts/verifier-lenses.md',
    'docs/architecture/prompts/workers-arms-synthesis.md',
    'docs/architecture/prompts/workers-intake-extraction.md',
    'docs/architecture/prompts/workers-judgment.md',
    'docs/architecture/templates/01-run-control.md',
    'docs/architecture/templates/02-corpus-intake.md',
    'docs/architecture/templates/03-extraction-claims.md',
    'docs/architecture/templates/04-evidence-boundaries.md',
    'docs/architecture/templates/05-clustering-routing.md',
    'docs/architecture/templates/06-arms-synthesis.md',
    'docs/architecture/templates/07-verification.md',
    'docs/architecture/templates/08-projection.md',
    'docs/architecture/templates/README.md',
    'scripts/validate-precis-fixtures.ts',
    'scripts/validate-run.ts',
];
const EXPECTED_EXPOSURES = [
    {
        id: 'command',
        source: COMMAND_PATH,
        destination: '.claude/commands/loa-aleph.md',
    },
    {
        id: 'skill',
        source: SKILL_PATH,
        destination: '.claude/skills/loa-aleph/SKILL.md',
    },
    {
        id: 'launcher',
        source: COMPILED_LAUNCHER_PATH,
        destination: '.claude/aleph/bin/loa-aleph.mjs',
    },
];
const PROFILE_FORMAT = LOA_PROFILE_FORMAT;
const HOST_FORMAT = LOA_HOST_FORMAT;
const INSTALLATION_MAP_FORMAT = 'aleph-loa-installation-map/v1';
const RUNTIME_ROOT = LOA_INSTALLED_BUNDLE_ROOT;
const INSTALL_RECORD_PATH = LOA_INSTALL_LOCK_PATH;
const RUN_ROOT = LOA_RUN_ROOT;
const ALIAS_VALUES = new Set([
    'alias',
    'auto',
    'current',
    'default',
    'latest',
    'rolling',
    'stable',
]);
const MUTABLE_ALIAS = /(?:^|[-_.:/])(alias|auto|current|default|latest|recommended|rolling|stable)(?:$|[-_.:/])/iu;
class CheckCollector {
    checks = [];
    run(id, title, operation) {
        const problems = [];
        const fail = (message) => {
            problems.push(message);
        };
        try {
            operation(fail);
        }
        catch (error) {
            fail(error instanceof Error ? error.message : String(error));
        }
        this.checks.push({
            id,
            title,
            status: problems.length === 0 ? 'PASS' : 'FAIL',
            problems: sortedUnique(problems),
        });
    }
}
function isRecord(value) {
    return typeof value === 'object' && value !== null && !Array.isArray(value);
}
function isStringArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item === 'string');
}
function sortedUnique(values) {
    return [...new Set(values)].sort((left, right) => (Buffer.compare(Buffer.from(left), Buffer.from(right))));
}
function sameStrings(left, right) {
    const a = sortedUnique([...left]);
    const b = sortedUnique([...right]);
    return a.length === b.length && a.every((value, index) => value === b[index]);
}
function exactKeys(value, expected) {
    return isRecord(value) && sameStrings(Object.keys(value), expected);
}
function normalizedRelativePath(value) {
    if (!value || isAbsolute(value) || value.includes('\\') || value.includes('\0')) {
        return false;
    }
    if (value.split('/').includes('..'))
        return false;
    return posix.normalize(value) === value && value !== '.';
}
function readJson(path) {
    return JSON.parse(readFileSync(path, 'utf8'));
}
function existingRegularFile(root, path) {
    const absolute = join(root, path);
    return existsSync(absolute)
        && lstatSync(absolute).isFile()
        && !lstatSync(absolute).isSymbolicLink();
}
function stringLeaves(value) {
    if (typeof value === 'string')
        return [value];
    if (Array.isArray(value))
        return value.flatMap((item) => stringLeaves(item));
    if (!isRecord(value))
        return [];
    return [
        ...Object.keys(value),
        ...Object.values(value).flatMap((item) => stringLeaves(item)),
    ];
}
function nonemptyExactString(value) {
    if (typeof value !== 'string' || value.trim() !== value || value.length === 0) {
        return false;
    }
    return !ALIAS_VALUES.has(value.toLowerCase()) && !MUTABLE_ALIAS.test(value);
}
function immutableResolvedIdentity(value) {
    return typeof value === 'string' && /^sha256:[0-9a-f]{64}$/.test(value);
}
function fallbackProblems(value, scope = 'value') {
    const problems = [];
    if (Array.isArray(value)) {
        for (const [index, item] of value.entries()) {
            problems.push(...fallbackProblems(item, `${scope}[${index}]`));
        }
        return problems;
    }
    if (!isRecord(value))
        return problems;
    for (const [key, item] of Object.entries(value)) {
        const childScope = `${scope}.${key}`;
        if (key.toLowerCase().includes('fallback')) {
            const disabledString = typeof item === 'string'
                && ['disabled', 'forbidden', 'none'].includes(item.toLowerCase());
            const disabledCollection = (Array.isArray(item) && item.length === 0)
                || (isRecord(item) && Object.keys(item).length === 0);
            if (!(item === false || item === null || disabledString || disabledCollection)) {
                problems.push(`${childScope} enables or leaves a fallback unresolved`);
            }
        }
        problems.push(...fallbackProblems(item, childScope));
    }
    return problems;
}
function degradedModeProblems(value, scope = 'value') {
    const problems = [];
    if (Array.isArray(value)) {
        for (const [index, item] of value.entries()) {
            problems.push(...degradedModeProblems(item, `${scope}[${index}]`));
        }
        return problems;
    }
    if (!isRecord(value))
        return problems;
    for (const [key, item] of Object.entries(value)) {
        const lower = key.toLowerCase();
        const childScope = `${scope}.${key}`;
        if ((lower.includes('degraded') || lower.includes('partial_mode'))
            && item !== false && item !== null) {
            problems.push(`${childScope} would permit a degraded full-mode execution`);
        }
        problems.push(...degradedModeProblems(item, childScope));
    }
    return problems;
}
function loadBoundaryContext(root, collector) {
    let context = {
        mode: 'unknown',
        corePaths: new Set(),
        adapterPaths: new Set(),
        foreignAdapterIds: [],
    };
    collector.run('LP1', 'verified source or immutable bundle root', (fail) => {
        const lockPath = join(root, 'bundle.lock.json');
        const coreManifestPath = join(root, 'core.manifest.json');
        if (existsSync(lockPath)) {
            const verification = verifyBundle(root);
            if (verification.result !== 'PASS') {
                for (const error of verification.errors)
                    fail(`bundle verification: ${error}`);
            }
            const lock = readJson(lockPath);
            if (!isRecord(lock)) {
                fail('bundle.lock.json must be an object');
                return;
            }
            const adapter = lock.adapter;
            const bundle = lock.bundle;
            if (!isRecord(adapter) || adapter.id !== ADAPTER_ID) {
                fail(`bundle must select adapter ${ADAPTER_ID}`);
            }
            if (!isRecord(bundle) || bundle.id !== LOA_BUNDLE_ID) {
                fail(`bundle must have id ${LOA_BUNDLE_ID}`);
            }
            const source = lock.source;
            const projection = isRecord(source) ? source.manifest_projection : null;
            const files = isRecord(projection) ? projection.files : null;
            const adapters = isRecord(files) ? files.adapter : null;
            const corePaths = isRecord(files) && isStringArray(files.core) ? files.core : [];
            const adapterPaths = isRecord(adapters) && isStringArray(adapters[ADAPTER_ID])
                ? adapters[ADAPTER_ID]
                : [];
            if (corePaths.length === 0 || adapterPaths.length === 0) {
                fail('bundle source projection omits Core or Loa adapter inventory');
            }
            context = {
                mode: 'bundle',
                corePaths: new Set(corePaths),
                adapterPaths: new Set(adapterPaths),
                foreignAdapterIds: isRecord(adapters)
                    ? Object.keys(adapters).filter((id) => id !== ADAPTER_ID)
                    : [],
            };
            return;
        }
        if (!existsSync(coreManifestPath)) {
            fail('root contains neither bundle.lock.json nor core.manifest.json');
            return;
        }
        const boundary = validateCoreBoundary({ root, preflightAdapter: ADAPTER_ID });
        if (boundary.result !== 'PASS') {
            for (const check of boundary.checks.filter((item) => item.status === 'FAIL')) {
                fail(`${check.id} ${check.message}`);
            }
        }
        const manifest = readJson(coreManifestPath);
        const files = isRecord(manifest) ? manifest.files : null;
        const adapters = isRecord(files) ? files.adapter : null;
        const corePaths = isRecord(files) && isStringArray(files.core) ? files.core : [];
        const adapterPaths = isRecord(adapters) && isStringArray(adapters[ADAPTER_ID])
            ? adapters[ADAPTER_ID]
            : [];
        if (corePaths.length === 0 || adapterPaths.length === 0) {
            fail('source manifest omits Core or Loa adapter inventory');
        }
        context = {
            mode: 'source',
            corePaths: new Set(corePaths),
            adapterPaths: new Set(adapterPaths),
            foreignAdapterIds: isRecord(adapters)
                ? Object.keys(adapters).filter((id) => id !== ADAPTER_ID)
                : [],
        };
    });
    return context;
}
function validateManifest(root, boundary, collector) {
    let manifest = null;
    collector.run('LP2', 'implemented full-mode adapter manifest', (fail) => {
        if (!existingRegularFile(root, MANIFEST_PATH)) {
            fail(`${MANIFEST_PATH} is missing or not a regular file`);
            return;
        }
        const value = readJson(join(root, MANIFEST_PATH));
        if (!isRecord(value)) {
            fail('adapter manifest must be an object');
            return;
        }
        manifest = value;
        const adapter = value.adapter;
        if (!isRecord(adapter)
            || adapter.id !== ADAPTER_ID
            || adapter.host !== ADAPTER_ID
            || adapter.lifecycle !== 'implemented') {
            fail('adapter id, host, and lifecycle must be loa, loa, and implemented');
        }
        if (!isRecord(value.full_mode) || value.full_mode.claimed !== true) {
            fail('implemented adapter must claim structurally complete full mode');
        }
        const consumption = value.core_consumption;
        if (!isRecord(consumption)
            || consumption.mode !== 'immutable-complete-core'
            || consumption.allow_overrides !== false
            || consumption.mutable_fetch !== false
            || !Array.isArray(consumption.overrides) || consumption.overrides.length !== 0
            || !Array.isArray(consumption.duplicates) || consumption.duplicates.length !== 0
            || !Array.isArray(consumption.transformations)
            || consumption.transformations.length !== 0) {
            fail('Core consumption must be immutable, complete, unmodified, and offline');
        }
        if (!isStringArray(value.owned_paths)
            || !sameStrings(value.owned_paths, [...boundary.adapterPaths])) {
            fail('owned_paths must exactly equal the selected Loa adapter inventory');
        }
        const capabilities = value.capabilities;
        if (!isRecord(capabilities)
            || !sameStrings(Object.keys(capabilities), CAPABILITY_KEYS)) {
            fail('capabilities must contain exactly the thirteen protocol keys');
        }
        else {
            for (const key of CAPABILITY_KEYS) {
                const capability = capabilities[key];
                if (!isRecord(capability)
                    || capability.state !== 'implemented'
                    || !isStringArray(capability.evidence)
                    || capability.evidence.length === 0) {
                    fail(`capability ${key} must be implemented with nonempty evidence`);
                    continue;
                }
                for (const evidencePath of capability.evidence) {
                    if (!(boundary.corePaths.has(evidencePath)
                        || boundary.adapterPaths.has(evidencePath))
                        || !existingRegularFile(root, evidencePath)) {
                        fail(`capability ${key} has unresolved evidence ${evidencePath}`);
                    }
                }
            }
        }
        const lifecycleEvidence = value.evidence;
        if (!isRecord(lifecycleEvidence)
            || !isStringArray(lifecycleEvidence.implementation)
            || lifecycleEvidence.implementation.length === 0
            || !Array.isArray(lifecycleEvidence.validation)
            || lifecycleEvidence.validation.length !== 0
            || !Array.isArray(lifecycleEvidence.sanction)
            || lifecycleEvidence.sanction.length !== 0) {
            fail('implemented lifecycle needs implementation evidence and empty validation/sanction evidence');
        }
        else {
            for (const evidencePath of lifecycleEvidence.implementation) {
                if (!(boundary.corePaths.has(evidencePath)
                    || boundary.adapterPaths.has(evidencePath))
                    || !existingRegularFile(root, evidencePath)) {
                    fail(`implementation evidence does not resolve: ${evidencePath}`);
                }
            }
        }
        if (!Array.isArray(value.entrypoints) || value.entrypoints.length === 0) {
            fail('implemented adapter needs entrypoints');
        }
        else {
            for (const entrypoint of value.entrypoints) {
                if (!isRecord(entrypoint)
                    || entrypoint.state !== 'implemented'
                    || typeof entrypoint.path !== 'string'
                    || !boundary.adapterPaths.has(entrypoint.path)
                    || !existingRegularFile(root, entrypoint.path)) {
                    fail('every entrypoint must be implemented and resolve to Loa-owned bytes');
                }
            }
            const command = value.entrypoints.find((entrypoint) => (isRecord(entrypoint) && entrypoint.id === '/loa-aleph'));
            if (!isRecord(command)
                || command.kind !== 'slash-command'
                || command.path !== COMMAND_PATH) {
                fail('/loa-aleph must resolve to the canonical Loa command source');
            }
        }
        const installation = value.installation;
        if (!isRecord(installation)
            || installation.state !== 'implemented'
            || installation.path !== INSTALLER_PATH) {
            fail('installation must be implemented by the Loa-owned installer');
        }
        if (!Array.isArray(value.profiles) || value.profiles.length === 0) {
            fail('implemented adapter needs a host profile');
        }
        else {
            const declared = value.profiles.find((profile) => (isRecord(profile) && profile.path === PROFILE_PATH));
            if (!isRecord(declared)
                || declared.id !== 'loa-default'
                || declared.state !== 'implemented'
                || !isStringArray(declared.runtime_requirements)
                || declared.runtime_requirements.length === 0
                || !isRecord(declared.model_mapping)
                || Object.keys(declared.model_mapping).length === 0
                || !isRecord(declared.effort_mapping)
                || Object.keys(declared.effort_mapping).length === 0
                || !isStringArray(declared.evidence)
                || declared.evidence.length === 0) {
                fail('loa-default manifest profile declaration is incomplete');
            }
        }
    });
    return manifest;
}
function validateAdapterInventory(root, boundary, collector) {
    collector.run('LP3', 'Loa ownership and generic foreign-adapter exclusion', (fail) => {
        for (const path of boundary.adapterPaths) {
            if (!path.startsWith(`${ADAPTER_ROOT}/`)
                && !path.startsWith(`runtime-js/${ADAPTER_ROOT}/`)) {
                fail(`selected adapter inventory contains a non-Loa path: ${path}`);
            }
            if (!normalizedRelativePath(path) || !existingRegularFile(root, path)) {
                fail(`adapter inventory path is missing or unsafe: ${path}`);
                continue;
            }
            let text;
            try {
                text = new TextDecoder('utf-8', { fatal: true }).decode(readFileSync(join(root, path)));
            }
            catch {
                fail(`adapter-owned implementation bytes must be valid UTF-8 text: ${path}`);
                continue;
            }
            for (const match of text.matchAll(/adapters\/([a-z][a-z0-9-]*)\//gi)) {
                if (match[1]?.toLowerCase() !== ADAPTER_ID) {
                    fail(`${path} contains a foreign-adapter source path`);
                }
            }
            for (const match of text.matchAll(/aleph-for-([a-z][a-z0-9-]*)/gi)) {
                if (match[1]?.toLowerCase() !== ADAPTER_ID) {
                    fail(`${path} contains a foreign bundle dependency`);
                }
            }
            for (const foreignId of boundary.foreignAdapterIds) {
                const escaped = foreignId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                const token = new RegExp(`(^|[^A-Za-z0-9])${escaped}([^A-Za-z0-9]|$)`, 'i');
                if (token.test(text))
                    fail(`${path} names a foreign adapter or host`);
            }
            if (path.endsWith('.json')) {
                try {
                    const decoded = readJson(join(root, path));
                    for (const leaf of stringLeaves(decoded)) {
                        for (const foreignId of boundary.foreignAdapterIds) {
                            if (leaf.toLowerCase().includes(foreignId.toLowerCase())) {
                                fail(`${path} has a decoded foreign-adapter JSON value`);
                            }
                        }
                    }
                }
                catch {
                    fail(`adapter JSON is malformed: ${path}`);
                }
            }
        }
    });
}
function validateRequiredPaths(root, boundary, collector) {
    collector.run('LP4', 'required command, skill, profile, and runtime sources', (fail) => {
        for (const path of REQUIRED_ADAPTER_PATHS) {
            if (!boundary.adapterPaths.has(path))
                fail(`required path is not Loa-owned: ${path}`);
            if (!existingRegularFile(root, path))
                fail(`required path does not resolve: ${path}`);
        }
    });
}
function validateInstallationMap(root, boundary, collector) {
    collector.run('LP5', 'offline complete-bundle installation map', (fail) => {
        if (!existingRegularFile(root, INSTALLATION_MAP_PATH)) {
            fail(`${INSTALLATION_MAP_PATH} is missing`);
            return;
        }
        const value = readJson(join(root, INSTALLATION_MAP_PATH));
        if (!exactKeys(value, ['format', 'runtime_root', 'record_path', 'exposures'])) {
            fail('installation map top-level fields are malformed');
            return;
        }
        if (!isRecord(value))
            return;
        if (value.format !== INSTALLATION_MAP_FORMAT) {
            fail(`installation map format must be ${INSTALLATION_MAP_FORMAT}`);
        }
        if (value.runtime_root !== RUNTIME_ROOT) {
            fail(`installation runtime root must be ${RUNTIME_ROOT}`);
        }
        if (value.record_path !== INSTALL_RECORD_PATH) {
            fail(`installation record path must be ${INSTALL_RECORD_PATH}`);
        }
        if (!Array.isArray(value.exposures)
            || value.exposures.length !== EXPECTED_EXPOSURES.length) {
            fail('installation map must contain exactly command, skill, and launcher exposures');
            return;
        }
        const seenIds = new Set();
        const seenDestinations = new Set();
        for (const exposure of value.exposures) {
            if (!exactKeys(exposure, ['id', 'source', 'destination']) || !isRecord(exposure)) {
                fail('installation exposure fields are malformed');
                continue;
            }
            if (typeof exposure.id !== 'string'
                || typeof exposure.source !== 'string'
                || typeof exposure.destination !== 'string') {
                fail('installation exposure values must be strings');
                continue;
            }
            if (seenIds.has(exposure.id))
                fail(`duplicate exposure id ${exposure.id}`);
            if (seenDestinations.has(exposure.destination)) {
                fail(`duplicate exposure destination ${exposure.destination}`);
            }
            seenIds.add(exposure.id);
            seenDestinations.add(exposure.destination);
            if (!normalizedRelativePath(exposure.source)
                || !normalizedRelativePath(exposure.destination)) {
                fail(`installation exposure ${exposure.id} contains an unsafe path`);
            }
            if (!boundary.adapterPaths.has(exposure.source)
                || !existingRegularFile(root, exposure.source)) {
                fail(`installation source is not Loa-owned: ${exposure.source}`);
            }
        }
        for (const expected of EXPECTED_EXPOSURES) {
            const match = value.exposures.find((exposure) => (isRecord(exposure) && exposure.id === expected.id));
            if (!isRecord(match)
                || match.source !== expected.source
                || match.destination !== expected.destination) {
                fail(`installation exposure ${expected.id} does not match the required mapping`);
            }
        }
    });
}
function validateCanonicalCore(root, boundary, manifest, collector) {
    collector.run('LP6', 'direct canonical Core contracts and checkers', (fail) => {
        for (const path of REQUIRED_CORE_PATHS) {
            if (!boundary.corePaths.has(path))
                fail(`canonical Core path is not Core-owned: ${path}`);
            if (!existingRegularFile(root, path))
                fail(`canonical Core path does not resolve: ${path}`);
        }
        if (!manifest || !isStringArray(manifest.references)) {
            fail('adapter manifest references must be a path array');
            return;
        }
        for (const path of manifest.references) {
            if (!boundary.corePaths.has(path) || !existingRegularFile(root, path)) {
                fail(`manifest Core reference does not resolve directly: ${path}`);
            }
        }
    });
}
function validateProfile(root, collector) {
    let profile = null;
    collector.run('LP7', 'complete Loa profile and Core role coverage', (fail) => {
        if (!existingRegularFile(root, PROFILE_PATH)) {
            fail(`${PROFILE_PATH} is missing`);
            return;
        }
        const value = readJson(join(root, PROFILE_PATH));
        if (!exactKeys(value, [
            'profile_format',
            'id',
            'host',
            'runtime_requirements',
            'paths',
            'role_mappings',
            'model_slots',
        ])) {
            fail('profile top-level fields are malformed');
            return;
        }
        if (!isRecord(value))
            return;
        profile = value;
        if (value.profile_format !== PROFILE_FORMAT
            || value.id !== 'loa-default'
            || value.host !== ADAPTER_ID) {
            fail('profile format, id, or host is incorrect');
        }
        const requirements = value.runtime_requirements;
        if (!exactKeys(requirements, ['node_min_version', 'required_capabilities'])
            || !isRecord(requirements)
            || requirements.node_min_version !== '20.0.0'
            || !isStringArray(requirements.required_capabilities)
            || !sameStrings(requirements.required_capabilities, HOST_CAPABILITY_KEYS)) {
            fail('profile runtime requirements are incomplete or drifted');
        }
        const paths = value.paths;
        if (!exactKeys(paths, ['run_root', 'installed_bundle_root', 'install_lock'])
            || !isRecord(paths)
            || paths.run_root !== RUN_ROOT
            || paths.installed_bundle_root !== RUNTIME_ROOT
            || paths.install_lock !== INSTALL_RECORD_PATH) {
            fail('profile paths do not match the durable Loa layout');
        }
        const slots = value.model_slots;
        if (!isRecord(slots) || !sameStrings(Object.keys(slots), MODEL_SLOT_KEYS)) {
            fail('profile must declare exactly the six required model slots');
        }
        else {
            for (const slot of MODEL_SLOT_KEYS) {
                const record = slots[slot];
                if (!exactKeys(record, [
                    'capability_class',
                    'exact_identity_required',
                    'fallback_allowed',
                ]) || !isRecord(record)
                    || !nonemptyExactString(record.capability_class)
                    || record.exact_identity_required !== true
                    || record.fallback_allowed !== false) {
                    fail(`model slot ${slot} is incomplete, aliased, or fallback-enabled`);
                }
            }
        }
        const roles = value.role_mappings;
        if (!isRecord(roles) || !sameStrings(Object.keys(roles), ROLE_KEYS)) {
            fail('profile role mappings do not cover every Core producer, refuter, and support role');
        }
        else {
            for (const role of ROLE_KEYS) {
                const mapping = roles[role];
                if (!exactKeys(mapping, [
                    'model_slot',
                    'effort',
                    'context_policy',
                    'budget_policy',
                    'cache_policy',
                    'batch_policy',
                ]) || !isRecord(mapping)) {
                    fail(`role ${role} mapping fields are malformed`);
                    continue;
                }
                for (const field of [
                    'model_slot',
                    'effort',
                    'context_policy',
                    'budget_policy',
                    'cache_policy',
                    'batch_policy',
                ]) {
                    if (!nonemptyExactString(mapping[field])) {
                        fail(`role ${role} has empty or aliased ${field}`);
                    }
                }
                if (typeof mapping.model_slot === 'string'
                    && !MODEL_SLOT_KEYS.includes(mapping.model_slot)) {
                    fail(`role ${role} references unresolved model slot ${mapping.model_slot}`);
                }
                if ((role.startsWith('verifier-') || role === 'adversarial-panel')
                    && typeof mapping.context_policy === 'string'
                    && !/(?:fresh|isolat)/i.test(mapping.context_policy)) {
                    fail(`role ${role} must require fresh isolated context`);
                }
            }
        }
        for (const problem of fallbackProblems(value, 'profile'))
            fail(problem);
        for (const problem of degradedModeProblems(value, 'profile'))
            fail(problem);
    });
    return profile;
}
function validateHostCapabilities(capabilitiesPath, profile, collector) {
    let evidenceClass = 'unresolved';
    let runtimeReady = false;
    collector.run('LP8', 'resolved immutable host and model capabilities', (fail) => {
        if (!capabilitiesPath) {
            fail('--capabilities is required; full-mode preflight never guesses host/model identity');
            return;
        }
        if (!existsSync(capabilitiesPath)
            || !lstatSync(capabilitiesPath).isFile()
            || lstatSync(capabilitiesPath).isSymbolicLink()) {
            fail(`capabilities file is missing, symlinked, or not a regular file: ${capabilitiesPath}`);
            return;
        }
        const value = readJson(capabilitiesPath);
        if (!exactKeys(value, ['host_format', 'host', 'capabilities', 'models', 'simulation'])
            || !isRecord(value)) {
            fail('host capabilities top-level fields are malformed');
            return;
        }
        if (value.host_format !== HOST_FORMAT)
            fail(`host format must be ${HOST_FORMAT}`);
        const simulation = value.simulation;
        if (simulation === null) {
            evidenceClass = 'runtime';
            runtimeReady = true;
        }
        else if (exactKeys(simulation, ['kind'])
            && isRecord(simulation)
            && simulation.kind === 'fixture-simulated') {
            evidenceClass = 'fixture-simulated';
            runtimeReady = false;
        }
        else {
            fail('simulation must be null or explicitly fixture-simulated');
        }
        const host = value.host;
        if (!exactKeys(host, ['id', 'version', 'build_id']) || !isRecord(host)
            || host.id !== ADAPTER_ID
            || !nonemptyExactString(host.version)
            || !immutableResolvedIdentity(host.build_id)) {
            fail('host identity must resolve exact loa version and immutable build id');
        }
        const capabilities = value.capabilities;
        if (!isRecord(capabilities)
            || !sameStrings(Object.keys(capabilities), HOST_CAPABILITY_KEYS)) {
            fail('host capability receipt does not contain the exact required capability set');
        }
        else {
            for (const key of HOST_CAPABILITY_KEYS) {
                if (capabilities[key] !== true)
                    fail(`host capability ${key} is unavailable`);
            }
        }
        const models = value.models;
        if (!isRecord(models) || !sameStrings(Object.keys(models), MODEL_SLOT_KEYS)) {
            fail('host receipt must resolve every and only the profile model slots');
        }
        else {
            for (const slot of MODEL_SLOT_KEYS) {
                const model = models[slot];
                if (!exactKeys(model, [
                    'provider',
                    'model_id',
                    'resolved_version',
                    'immutable',
                    'context',
                    'effort',
                    'budget',
                    'cache',
                    'batch',
                    'fallback',
                ]) || !isRecord(model)) {
                    fail(`resolved model slot ${slot} fields are malformed`);
                    continue;
                }
                for (const field of [
                    'provider',
                    'model_id',
                    'context',
                    'effort',
                    'budget',
                    'cache',
                    'batch',
                ]) {
                    if (!nonemptyExactString(model[field])) {
                        fail(`resolved model slot ${slot} has empty or aliased ${field}`);
                    }
                }
                if (!immutableResolvedIdentity(model.resolved_version)
                    || model.immutable !== true
                    || model.fallback !== false) {
                    fail(`resolved model slot ${slot} is mutable, aliased, or fallback-enabled`);
                }
            }
        }
        if (profile && isRecord(profile.model_slots) && isRecord(models)) {
            for (const slot of Object.keys(profile.model_slots)) {
                if (!isRecord(models[slot]))
                    fail(`profile model slot ${slot} is unresolved`);
            }
        }
        if (profile && isRecord(profile.role_mappings) && isRecord(models)) {
            const mechanicFields = [
                ['effort', 'effort'],
                ['context_policy', 'context'],
                ['budget_policy', 'budget'],
                ['cache_policy', 'cache'],
                ['batch_policy', 'batch'],
            ];
            for (const [role, rawMapping] of Object.entries(profile.role_mappings)) {
                if (!isRecord(rawMapping) || typeof rawMapping.model_slot !== 'string')
                    continue;
                const model = models[rawMapping.model_slot];
                if (!isRecord(model))
                    continue;
                for (const [profileField, hostField] of mechanicFields) {
                    if (rawMapping[profileField] !== model[hostField]) {
                        fail(`role ${role} ${profileField}=${String(rawMapping[profileField])} does not match `
                            + `exact host slot ${rawMapping.model_slot}.${hostField}=${String(model[hostField])}`);
                    }
                }
            }
        }
        for (const problem of fallbackProblems(value, 'host'))
            fail(problem);
        for (const problem of degradedModeProblems(value, 'host'))
            fail(problem);
    });
    return { evidenceClass, runtimeReady };
}
function validateNoSilentDowngrade(manifest, profile, hostState, collector) {
    collector.run('LP9', 'fail-closed full-mode labeling', (fail) => {
        if (!manifest || !isRecord(manifest.full_mode) || manifest.full_mode.claimed !== true) {
            fail('manifest does not claim structurally complete full mode');
        }
        if (!profile)
            fail('profile is unavailable; no partial profile may be relabeled full mode');
        if (hostState.evidenceClass === 'unresolved') {
            fail('host/model identity is unresolved; no fallback or degraded mode is permitted');
        }
        if (hostState.evidenceClass === 'fixture-simulated' && hostState.runtimeReady) {
            fail('fixture-simulated capabilities may never be labeled runtime-ready');
        }
    });
}
export function runLoaPreflight(options = {}) {
    const root = resolve(options.root || DEFAULT_ROOT);
    const capabilitiesPath = options.capabilities
        ? resolve(root, options.capabilities)
        : null;
    const collector = new CheckCollector();
    const boundary = loadBoundaryContext(root, collector);
    const manifest = validateManifest(root, boundary, collector);
    validateAdapterInventory(root, boundary, collector);
    validateRequiredPaths(root, boundary, collector);
    validateInstallationMap(root, boundary, collector);
    validateCanonicalCore(root, boundary, manifest, collector);
    const profile = validateProfile(root, collector);
    const hostState = validateHostCapabilities(capabilitiesPath, profile, collector);
    validateNoSilentDowngrade(manifest, profile, hostState, collector);
    return {
        result: collector.checks.every((check) => check.status === 'PASS') ? 'PASS' : 'FAIL',
        root,
        rootMode: boundary.mode,
        capabilitiesPath,
        evidenceClass: hostState.evidenceClass,
        runtimeReady: hostState.runtimeReady,
        checks: collector.checks,
    };
}
function parseCli(args) {
    const options = {
        root: DEFAULT_ROOT,
        json: false,
        help: false,
        error: '',
    };
    let capabilitiesValue;
    for (let index = 0; index < args.length; index += 1) {
        const arg = args[index];
        if (arg === '--json')
            options.json = true;
        else if (arg === '--help' || arg === '-h')
            options.help = true;
        else if (arg === '--root') {
            const value = args[index + 1];
            if (!value)
                options.error = '--root requires a directory';
            else {
                options.root = resolve(value);
                index += 1;
            }
        }
        else if (arg === '--capabilities') {
            const value = args[index + 1];
            if (!value)
                options.error = '--capabilities requires a JSON file';
            else {
                capabilitiesValue = value;
                index += 1;
            }
        }
        else {
            options.error = `unknown argument "${arg}"`;
        }
    }
    if (capabilitiesValue) {
        options.capabilities = isAbsolute(capabilitiesValue)
            ? capabilitiesValue
            : resolve(options.root, capabilitiesValue);
    }
    return options;
}
function printHuman(report) {
    for (const check of report.checks) {
        if (check.status === 'PASS') {
            console.log(`PASS LOA-PREFLIGHT ${check.id} ${check.title}`);
        }
        else {
            for (const problem of check.problems) {
                console.log(`FAIL LOA-PREFLIGHT ${check.id} ${check.title}: ${problem}`);
            }
        }
    }
    if (report.result === 'PASS' && report.evidenceClass === 'fixture-simulated') {
        console.log('PREFLIGHT loa FIXTURE-SIMULATED (structural only; not validation or sanction)');
    }
    else if (report.result === 'PASS' && report.runtimeReady) {
        console.log('PREFLIGHT loa READY runtime-capabilities-resolved');
    }
    else {
        console.log('PREFLIGHT loa NOT-READY fail-closed');
    }
    console.log(`RESULT: ${report.result}`);
}
function main() {
    const options = parseCli(process.argv.slice(2));
    if (options.help) {
        console.log('Usage: node adapters/loa/src/preflight.ts '
            + '[--root <source-or-bundle>] --capabilities <host-capabilities.json> [--json]');
        process.exit(0);
    }
    if (options.error) {
        console.error(options.error);
        process.exit(2);
    }
    const report = runLoaPreflight({
        root: options.root,
        capabilities: options.capabilities,
    });
    if (options.json)
        console.log(JSON.stringify(report, null, 2));
    else
        printHuman(report);
    process.exit(report.result === 'PASS' ? 0 : 1);
}
if (resolve(process.argv[1] || '') === SCRIPT_PATH)
    main();
