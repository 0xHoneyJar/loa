export class ResultCollector {
    scope;
    checks;
    constructor(scope) {
        this.scope = scope;
        this.checks = [];
    }
    run(id, label, check) {
        const before = this.checks.length;
        const fail = (message) => {
            this.checks.push({
                id,
                scope: this.scope,
                status: 'FAIL',
                message: `(${label}): ${message}`,
            });
        };
        let passMessage = 'check passed';
        try {
            const returned = check(fail);
            if (returned)
                passMessage = returned;
        }
        catch (error) {
            fail(`checker error: ${error instanceof Error ? error.message : String(error)}`);
        }
        const failed = this.checks
            .slice(before)
            .some((record) => record.id === id && record.status === 'FAIL');
        if (!failed) {
            this.checks.push({
                id,
                scope: this.scope,
                status: 'PASS',
                message: `(${label}): ${passMessage}`,
            });
        }
    }
    report(extra = {}) {
        return {
            result: this.checks.some((record) => record.status === 'FAIL') ? 'FAIL' : 'PASS',
            checks: this.checks,
            ...extra,
        };
    }
}
