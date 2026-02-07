/**
 * Consumer Compatibility Harness (T3.10)
 *
 * Validates that all 5 new module barrel exports resolve correctly and
 * factory functions are callable. Catches import extension mismatches,
 * missing exports, and ESM/CJS issues before downstream repos migrate.
 */

export interface HarnessResult {
  module: string;
  ok: boolean;
  factories: string[];
  error?: string;
}

export interface HarnessReport {
  results: HarnessResult[];
  passed: number;
  failed: number;
  allPassed: boolean;
}

/**
 * Verify a module's factory functions are importable and callable.
 */
async function checkModule(
  name: string,
  importFn: () => Promise<Record<string, unknown>>,
  factories: string[],
): Promise<HarnessResult> {
  try {
    const mod = await importFn();
    const missing = factories.filter((f) => typeof mod[f] !== "function");
    if (missing.length > 0) {
      return {
        module: name,
        ok: false,
        factories,
        error: `Missing factories: ${missing.join(", ")}`,
      };
    }
    return { module: name, ok: true, factories };
  } catch (err) {
    return {
      module: name,
      ok: false,
      factories,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

/**
 * Run the full consumer compatibility harness.
 */
export async function runConsumerHarness(): Promise<HarnessReport> {
  const results: HarnessResult[] = [];

  // 5 new modules
  results.push(
    await checkModule(
      "security",
      () => import("../security/index.js"),
      ["createPIIRedactor", "createAuditLogger"],
    ),
  );

  results.push(
    await checkModule(
      "memory",
      () => import("../memory/index.js"),
      ["createContextTracker", "createCompoundLearningCycle"],
    ),
  );

  results.push(
    await checkModule(
      "scheduler",
      () => import("../scheduler/index.js"),
      [
        "createScheduler",
        "createWebhookSink",
        "createHealthAggregator",
        "createTimeoutEnforcer",
        "createBloatAuditor",
      ],
    ),
  );

  results.push(
    await checkModule(
      "bridge",
      () => import("../bridge/index.js"),
      ["createBeadsBridge"],
    ),
  );

  results.push(
    await checkModule(
      "sync",
      () => import("../sync/index.js"),
      [
        "createRecoveryCascade",
        "createInMemoryObjectStore",
        "createObjectStoreSync",
        "createWALPruner",
        "createGracefulShutdown",
      ],
    ),
  );

  // Best-effort: existing modules (skip with warning if unresolvable)
  try {
    results.push(
      await checkModule(
        "beads/interfaces (legacy)",
        () => import("../beads/interfaces.js"),
        [],
      ),
    );
  } catch {
    // Skip — preexisting module, best-effort only
  }

  const passed = results.filter((r) => r.ok).length;
  const failed = results.filter((r) => !r.ok).length;

  return {
    results,
    passed,
    failed,
    allPassed: failed === 0,
  };
}
