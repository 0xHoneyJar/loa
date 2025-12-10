import express, { Request, Response } from 'express';
import { logger } from './logger';
import { getLinearServiceStats } from '../services/linearService';

/**
 * Monitoring and Health Check System
 *
 * SECURITY FIX: MEDIUM #15
 * - Health check endpoint
 * - Metrics collection
 * - System status monitoring
 * - Service availability checks
 */

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  timestamp: string;
  uptime: number;
  checks: {
    memory: HealthCheck;
    linearApi: HealthCheck;
    filesystem: HealthCheck;
  };
  metrics?: SystemMetrics;
}

export interface HealthCheck {
  status: 'pass' | 'warn' | 'fail';
  message?: string;
  value?: any;
}

export interface SystemMetrics {
  memory: {
    used: number;
    total: number;
    percentage: number;
  };
  process: {
    uptime: number;
    pid: number;
    nodeVersion: string;
  };
  linear: {
    rateLimiter: any;
    circuitBreaker: any;
  };
}

const START_TIME = Date.now();

/**
 * Check memory health
 */
function checkMemory(): HealthCheck {
  const memUsage = process.memoryUsage();
  const percentUsed = (memUsage.heapUsed / memUsage.heapTotal) * 100;

  if (percentUsed > 90) {
    return {
      status: 'fail',
      message: 'Memory usage critically high',
      value: `${percentUsed.toFixed(1)}%`,
    };
  }

  if (percentUsed > 75) {
    return {
      status: 'warn',
      message: 'Memory usage elevated',
      value: `${percentUsed.toFixed(1)}%`,
    };
  }

  return {
    status: 'pass',
    message: 'Memory usage normal',
    value: `${percentUsed.toFixed(1)}%`,
  };
}

/**
 * Check Linear API health
 */
function checkLinearApi(): HealthCheck {
  try {
    const stats = getLinearServiceStats();

    // Check if circuit breaker is open
    if (stats.circuitBreaker.state === 'open') {
      return {
        status: 'fail',
        message: 'Linear API circuit breaker is open',
        value: stats.circuitBreaker,
      };
    }

    if (stats.circuitBreaker.state === 'half-open') {
      return {
        status: 'warn',
        message: 'Linear API circuit breaker is recovering',
        value: stats.circuitBreaker,
      };
    }

    // Check if queue is backing up
    if (stats.rateLimiter.queued > 50) {
      return {
        status: 'warn',
        message: 'Linear API queue backing up',
        value: stats.rateLimiter,
      };
    }

    return {
      status: 'pass',
      message: 'Linear API healthy',
      value: stats,
    };
  } catch (error) {
    return {
      status: 'fail',
      message: 'Unable to check Linear API status',
      value: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Check filesystem health
 */
function checkFilesystem(): HealthCheck {
  try {
    const fs = require('fs');
    const path = require('path');

    const dataDir = path.join(__dirname, '../../data');
    const logsDir = path.join(__dirname, '../../logs');

    // Check if directories are writable
    fs.accessSync(dataDir, fs.constants.W_OK);
    fs.accessSync(logsDir, fs.constants.W_OK);

    return {
      status: 'pass',
      message: 'Filesystem accessible',
    };
  } catch (error) {
    return {
      status: 'fail',
      message: 'Filesystem access error',
      value: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Get system metrics
 */
function getSystemMetrics(): SystemMetrics {
  const memUsage = process.memoryUsage();
  const linearStats = getLinearServiceStats();

  return {
    memory: {
      used: memUsage.heapUsed,
      total: memUsage.heapTotal,
      percentage: (memUsage.heapUsed / memUsage.heapTotal) * 100,
    },
    process: {
      uptime: process.uptime(),
      pid: process.pid,
      nodeVersion: process.version,
    },
    linear: linearStats,
  };
}

/**
 * Perform health check
 */
export function performHealthCheck(): HealthStatus {
  const checks = {
    memory: checkMemory(),
    linearApi: checkLinearApi(),
    filesystem: checkFilesystem(),
  };

  // Determine overall status
  const hasFailures = Object.values(checks).some(c => c.status === 'fail');
  const hasWarnings = Object.values(checks).some(c => c.status === 'warn');

  let status: 'healthy' | 'degraded' | 'unhealthy';
  if (hasFailures) {
    status = 'unhealthy';
  } else if (hasWarnings) {
    status = 'degraded';
  } else {
    status = 'healthy';
  }

  return {
    status,
    timestamp: new Date().toISOString(),
    uptime: Date.now() - START_TIME,
    checks,
    metrics: getSystemMetrics(),
  };
}

/**
 * Create health check endpoint handler
 */
export function handleHealthCheck(_req: Request, res: Response): void {
  const health = performHealthCheck();

  // Set HTTP status based on health
  const statusCode = health.status === 'unhealthy' ? 503 : 200;

  res.status(statusCode).json(health);
}

/**
 * Create metrics endpoint handler
 */
export function handleMetrics(_req: Request, res: Response): void {
  const metrics = getSystemMetrics();
  res.status(200).json(metrics);
}

/**
 * Create monitoring router
 */
export function createMonitoringRouter(): express.Router {
  const router = express.Router();

  // Health check endpoint
  router.get('/health', handleHealthCheck);

  // Metrics endpoint
  router.get('/metrics', handleMetrics);

  // Readiness probe (for Kubernetes)
  router.get('/ready', (_req, res) => {
    const health = performHealthCheck();
    const statusCode = health.status === 'unhealthy' ? 503 : 200;
    res.status(statusCode).send(health.status);
  });

  // Liveness probe (for Kubernetes)
  router.get('/live', (_req, res) => {
    res.status(200).send('alive');
  });

  return router;
}

/**
 * Start periodic health monitoring
 */
export function startHealthMonitoring(intervalMs: number = 60000): void {
  setInterval(() => {
    const health = performHealthCheck();

    if (health.status === 'unhealthy') {
      logger.error('Health check FAILED:', health.checks);
    } else if (health.status === 'degraded') {
      logger.warn('Health check DEGRADED:', health.checks);
    } else {
      logger.info('Health check passed');
    }

    // Log metrics
    if (health.metrics) {
      logger.info('System metrics:', {
        memoryUsage: `${health.metrics.memory.percentage.toFixed(1)}%`,
        uptime: `${Math.floor(health.metrics.process.uptime / 60)}m`,
        linearQueue: health.metrics.linear.rateLimiter.queued,
      });
    }
  }, intervalMs);

  logger.info(`Health monitoring started (interval: ${intervalMs}ms)`);
}

/**
 * Metrics collector for external monitoring systems (Prometheus, StatsD, etc.)
 */
export class MetricsCollector {
  private counters: Map<string, number> = new Map();
  private gauges: Map<string, number> = new Map();
  private histograms: Map<string, number[]> = new Map();

  /**
   * Increment a counter
   */
  incrementCounter(name: string, value: number = 1): void {
    const current = this.counters.get(name) || 0;
    this.counters.set(name, current + value);
  }

  /**
   * Set a gauge value
   */
  setGauge(name: string, value: number): void {
    this.gauges.set(name, value);
  }

  /**
   * Record a value in histogram
   */
  recordHistogram(name: string, value: number): void {
    const values = this.histograms.get(name) || [];
    values.push(value);
    this.histograms.set(name, values);

    // Keep only last 1000 values
    if (values.length > 1000) {
      values.shift();
    }
  }

  /**
   * Get all metrics
   */
  getMetrics(): {
    counters: Record<string, number>;
    gauges: Record<string, number>;
    histograms: Record<string, { count: number; avg: number; p95: number }>;
  } {
    const histogramStats: Record<string, { count: number; avg: number; p95: number }> = {};

    this.histograms.forEach((values, name) => {
      const sorted = [...values].sort((a, b) => a - b);
      const avg = values.reduce((sum, v) => sum + v, 0) / values.length;
      const p95Index = Math.floor(sorted.length * 0.95);
      const p95 = sorted[p95Index] || 0;

      histogramStats[name] = {
        count: values.length,
        avg,
        p95,
      };
    });

    return {
      counters: Object.fromEntries(this.counters),
      gauges: Object.fromEntries(this.gauges),
      histograms: histogramStats,
    };
  }

  /**
   * Reset all metrics
   */
  reset(): void {
    this.counters.clear();
    this.gauges.clear();
    this.histograms.clear();
  }
}

// Global metrics collector instance
export const metrics = new MetricsCollector();
