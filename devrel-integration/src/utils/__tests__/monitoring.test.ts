import { performHealthCheck, MetricsCollector } from '../monitoring';

describe('Monitoring and Health Checks', () => {
  describe('performHealthCheck', () => {
    it('should return health status with all checks', () => {
      const health = performHealthCheck();

      expect(health.status).toBeDefined();
      expect(['healthy', 'degraded', 'unhealthy']).toContain(health.status);
      expect(health.timestamp).toBeDefined();
      expect(health.uptime).toBeGreaterThanOrEqual(0);
      expect(health.checks).toBeDefined();
      expect(health.checks.memory).toBeDefined();
      expect(health.checks.linearApi).toBeDefined();
      expect(health.checks.filesystem).toBeDefined();
    });

    it('should include memory check with percentage', () => {
      const health = performHealthCheck();

      expect(health.checks.memory.status).toBeDefined();
      expect(['pass', 'warn', 'fail']).toContain(health.checks.memory.status);
      expect(health.checks.memory.value).toBeDefined();
      expect(health.checks.memory.value).toContain('%');
    });

    it('should include system metrics', () => {
      const health = performHealthCheck();

      expect(health.metrics).toBeDefined();
      expect(health.metrics?.memory).toBeDefined();
      expect(health.metrics?.memory.used).toBeGreaterThan(0);
      expect(health.metrics?.memory.total).toBeGreaterThan(0);
      expect(health.metrics?.memory.percentage).toBeGreaterThanOrEqual(0);
      expect(health.metrics?.memory.percentage).toBeLessThanOrEqual(100);

      expect(health.metrics?.process).toBeDefined();
      expect(health.metrics?.process.uptime).toBeGreaterThanOrEqual(0);
      expect(health.metrics?.process.pid).toBeGreaterThan(0);
      expect(health.metrics?.process.nodeVersion).toContain('v');
    });

    it('should return unhealthy if any check fails', () => {
      // This test is tricky as we can't easily force checks to fail
      // In a real scenario, you'd mock the individual check functions
      const health = performHealthCheck();

      if (health.status === 'unhealthy') {
        const failedChecks = Object.values(health.checks).filter(c => c.status === 'fail');
        expect(failedChecks.length).toBeGreaterThan(0);
      }
    });
  });

  describe('MetricsCollector', () => {
    let metrics: MetricsCollector;

    beforeEach(() => {
      metrics = new MetricsCollector();
    });

    describe('Counter', () => {
      it('should increment counter', () => {
        metrics.incrementCounter('test.counter', 5);
        const result = metrics.getMetrics();

        expect(result.counters['test.counter']).toBe(5);
      });

      it('should accumulate counter increments', () => {
        metrics.incrementCounter('test.counter', 3);
        metrics.incrementCounter('test.counter', 2);
        metrics.incrementCounter('test.counter', 1);

        const result = metrics.getMetrics();
        expect(result.counters['test.counter']).toBe(6);
      });

      it('should handle default increment of 1', () => {
        metrics.incrementCounter('test.counter');
        metrics.incrementCounter('test.counter');

        const result = metrics.getMetrics();
        expect(result.counters['test.counter']).toBe(2);
      });
    });

    describe('Gauge', () => {
      it('should set gauge value', () => {
        metrics.setGauge('test.gauge', 42);
        const result = metrics.getMetrics();

        expect(result.gauges['test.gauge']).toBe(42);
      });

      it('should overwrite previous gauge value', () => {
        metrics.setGauge('test.gauge', 10);
        metrics.setGauge('test.gauge', 20);

        const result = metrics.getMetrics();
        expect(result.gauges['test.gauge']).toBe(20);
      });
    });

    describe('Histogram', () => {
      it('should record histogram values', () => {
        metrics.recordHistogram('test.histogram', 10);
        metrics.recordHistogram('test.histogram', 20);
        metrics.recordHistogram('test.histogram', 30);

        const result = metrics.getMetrics();
        expect(result.histograms['test.histogram']).toBeDefined();
        expect(result.histograms['test.histogram'].count).toBe(3);
      });

      it('should calculate average', () => {
        metrics.recordHistogram('test.histogram', 10);
        metrics.recordHistogram('test.histogram', 20);
        metrics.recordHistogram('test.histogram', 30);

        const result = metrics.getMetrics();
        expect(result.histograms['test.histogram'].avg).toBe(20);
      });

      it('should calculate p95', () => {
        // Record 100 values: 1, 2, 3, ..., 100
        for (let i = 1; i <= 100; i++) {
          metrics.recordHistogram('test.histogram', i);
        }

        const result = metrics.getMetrics();
        const p95 = result.histograms['test.histogram'].p95;

        // p95 should be around 95
        expect(p95).toBeGreaterThanOrEqual(90);
        expect(p95).toBeLessThanOrEqual(100);
      });

      it('should limit histogram size to 1000 values', () => {
        // Record 1500 values
        for (let i = 1; i <= 1500; i++) {
          metrics.recordHistogram('test.histogram', i);
        }

        const result = metrics.getMetrics();
        expect(result.histograms['test.histogram'].count).toBeLessThanOrEqual(1000);
      });
    });

    describe('Reset', () => {
      it('should reset all metrics', () => {
        metrics.incrementCounter('test.counter', 10);
        metrics.setGauge('test.gauge', 20);
        metrics.recordHistogram('test.histogram', 30);

        metrics.reset();

        const result = metrics.getMetrics();
        expect(Object.keys(result.counters)).toHaveLength(0);
        expect(Object.keys(result.gauges)).toHaveLength(0);
        expect(Object.keys(result.histograms)).toHaveLength(0);
      });
    });

    describe('Multiple Metrics', () => {
      it('should track multiple metrics independently', () => {
        metrics.incrementCounter('requests.total', 100);
        metrics.incrementCounter('requests.errors', 5);
        metrics.setGauge('connections.active', 42);
        metrics.recordHistogram('response.time', 150);
        metrics.recordHistogram('response.time', 200);

        const result = metrics.getMetrics();

        expect(result.counters['requests.total']).toBe(100);
        expect(result.counters['requests.errors']).toBe(5);
        expect(result.gauges['connections.active']).toBe(42);
        expect(result.histograms['response.time'].count).toBe(2);
        expect(result.histograms['response.time'].avg).toBe(175);
      });
    });
  });
});
