export type CheckStatus = 'PASS' | 'FAIL';

export interface CheckRecord {
  id: string;
  scope: string;
  status: CheckStatus;
  message: string;
}

export type CheckFailure = (message: string) => void;
export type CheckCallback = (fail: CheckFailure) => string | void;

export type CheckReport<TExtra extends object = Record<string, never>> = {
  result: CheckStatus;
  checks: CheckRecord[];
} & TExtra;

export class ResultCollector {
  scope: string;
  checks: CheckRecord[];

  constructor(scope: string) {
    this.scope = scope;
    this.checks = [];
  }

  run(id: string, label: string, check: CheckCallback): void {
    const before = this.checks.length;
    const fail: CheckFailure = (message) => {
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
      if (returned) passMessage = returned;
    } catch (error) {
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

  report<TExtra extends object = Record<string, never>>(
    extra: TExtra = {} as TExtra,
  ): CheckReport<TExtra> {
    return {
      result: this.checks.some((record) => record.status === 'FAIL') ? 'FAIL' : 'PASS',
      checks: this.checks,
      ...extra,
    } as CheckReport<TExtra>;
  }
}
