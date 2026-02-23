/**
 * Route table executor for declarative review routing.
 * @module route-executor
 */

const VALID_VERDICTS = new Set([
  'APPROVED',
  'CHANGES_REQUIRED',
  'DECISION_NEEDED',
  'SKIPPED',
]);

class RouteTable {
  constructor(routes = []) {
    this.routes = routes;
    this.backends = new Map();
    this.conditions = new Map();
  }

  registerBackend(name, handler) {
    this.backends.set(name, handler);
  }

  registerCondition(name, evaluator) {
    this.conditions.set(name, evaluator);
  }

  async execute(context) {
    for (const route of this.routes) {
      const conditionsMet = route.when.every((cond) => {
        const evaluator = this.conditions.get(cond);
        return evaluator ? evaluator(context) : false;
      });

      if (!conditionsMet) continue;

      const handler = this.backends.get(route.backend);
      if (!handler) {
        console.error(`Unknown backend: ${route.backend}`);
        if (route.fail_mode === 'hard_fail') throw new Error('Hard fail');
        continue;
      }

      try {
        const result = await handler(context);
        if (this.validateResult(result)) return result;
      } catch (err) {
        console.error(`Backend ${route.backend} failed:`, err.message);
        if (route.fail_mode === 'hard_fail') throw err;
      }
    }
    throw new Error('All routes exhausted');
  }

  validateResult(result) {
    if (!result || typeof result !== 'object') return false;
    if (!VALID_VERDICTS.has(result.verdict)) return false;
    if (result.findings && !Array.isArray(result.findings)) return false;
    return true;
  }
}

module.exports = { RouteTable, VALID_VERDICTS };
