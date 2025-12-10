/**
 * Logger Service
 *
 * Centralized logging with support for different log levels and security events.
 */

import * as fs from 'fs';
import * as path from 'path';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

export class Logger {
  private logLevel: LogLevel;
  private logPath: string;

  constructor(logLevel: LogLevel = 'info') {
    this.logLevel = logLevel;
    this.logPath = path.join(__dirname, '../../logs/integration.log');
    this.ensureLogDir();
  }

  private ensureLogDir(): void {
    const logDir = path.dirname(this.logPath);
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
  }

  private shouldLog(level: LogLevel): boolean {
    const levels: Record<LogLevel, number> = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    };
    return levels[level] >= levels[this.logLevel];
  }

  private formatMessage(level: LogLevel, message: string, meta?: any): string {
    const timestamp = new Date().toISOString();
    const metaStr = meta ? `\n${JSON.stringify(meta, null, 2)}` : '';
    return `[${timestamp}] [${level.toUpperCase()}] ${message}${metaStr}`;
  }

  private writeLog(level: LogLevel, message: string, meta?: any): void {
    const formatted = this.formatMessage(level, message, meta);

    // Console output
    console.log(formatted);

    // File output
    try {
      fs.appendFileSync(this.logPath, formatted + '\n', 'utf8');
    } catch (error) {
      console.error('Failed to write log:', error);
    }
  }

  debug(message: string, meta?: any): void {
    if (this.shouldLog('debug')) {
      this.writeLog('debug', message, meta);
    }
  }

  info(message: string, meta?: any): void {
    if (this.shouldLog('info')) {
      this.writeLog('info', message, meta);
    }
  }

  warn(message: string, meta?: any): void {
    if (this.shouldLog('warn')) {
      this.writeLog('warn', message, meta);
    }
  }

  error(message: string, meta?: any): void {
    if (this.shouldLog('error')) {
      this.writeLog('error', message, meta);
    }
  }

  // Security logging method (special category for security events)
  security(message: string, meta?: any): void {
    // Security logs are always written regardless of log level
    this.writeLog('error', `[SECURITY] ${message}`, meta);
  }
}

export default new Logger(process.env['LOG_LEVEL'] as LogLevel || 'info');
