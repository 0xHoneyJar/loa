/**
 * Adaptive multi-pass review orchestrator.
 * Manages dynamic pass count based on change complexity.
 */

interface ReviewConfig {
  maxPasses: number;
  adaptive: boolean;
  budgets: {
    pass1Input: number;
    pass1Output: number;
    pass2Input: number;
    pass2Output: number;
    overflowPct: number;
  };
  thresholds: {
    lowRiskAreas: number;
    highRiskAreas: number;
    lowScopeTokens: number;
    highScopeTokens: number;
  };
}

type ComplexityLevel = 'low' | 'medium' | 'high';

interface PassResult {
  passNumber: number;
  findings: Finding[];
  tokensUsed: number;
  elapsedMs: number;
}

interface Finding {
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info';
  category: string;
  file: string;
  line: number;
  message: string;
  suggestion?: string;
}

export class MultiPassOrchestrator {
  private config: ReviewConfig;
  private results: PassResult[] = [];

  constructor(config: ReviewConfig) {
    this.config = config;
  }

  async run(diff: string): Promise<PassResult[]> {
    const complexity = this.classifyComplexity(diff);

    if (this.config.adaptive && complexity === 'low') {
      const result = await this.executePass(1, diff);
      return [result];
    }

    for (let pass = 1; pass <= this.config.maxPasses; pass++) {
      const result = await this.executePass(pass, diff);
      this.results.push(result);

      if (this.shouldTerminateEarly(result)) {
        break;
      }
    }

    return this.results;
  }

  private classifyComplexity(diff: string): ComplexityLevel {
    const lines = diff.split('\n');
    const filesChanged = lines.filter((l) => l.startsWith('diff --git')).length;
    const linesChanged = lines.filter(
      (l) => l.startsWith('+') || l.startsWith('-'),
    ).length;

    if (filesChanged > 15 || linesChanged > 2000) return 'high';
    if (filesChanged > 3 || linesChanged > 200) return 'medium';
    return 'low';
  }

  private async executePass(
    passNumber: number,
    diff: string,
  ): Promise<PassResult> {
    const start = Date.now();
    const findings: Finding[] = [];
    // Simulate pass execution
    return {
      passNumber,
      findings,
      tokensUsed: diff.length / 4,
      elapsedMs: Date.now() - start,
    };
  }

  private shouldTerminateEarly(result: PassResult): boolean {
    return result.findings.length === 0;
  }
}
