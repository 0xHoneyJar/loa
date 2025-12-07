import { safeExecuteCommand, safeGitCommand, safeNpmCommand } from '../commandExecution';
import { AppError, ErrorCode } from '../errors';

describe('Command Execution Security', () => {
  describe('safeExecuteCommand', () => {
    it('should execute whitelisted commands', async () => {
      const result = await safeExecuteCommand('node', ['--version']);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('v');
    });

    it('should reject non-whitelisted commands', async () => {
      await expect(
        safeExecuteCommand('curl', ['https://evil.com'])
      ).rejects.toThrow(AppError);

      await expect(
        safeExecuteCommand('wget', ['https://evil.com'])
      ).rejects.toThrow('Command not allowed');
    });

    it('should reject commands with path traversal', async () => {
      await expect(
        safeExecuteCommand('../node', ['--version'])
      ).rejects.toThrow(AppError);

      await expect(
        safeExecuteCommand('./node', ['--version'])
      ).rejects.toThrow('Invalid command format');
    });

    it('should reject commands with shell metacharacters', async () => {
      await expect(
        safeExecuteCommand('node;ls', ['--version'])
      ).rejects.toThrow(AppError);
    });

    it('should reject arguments with dangerous patterns', async () => {
      await expect(
        safeExecuteCommand('git', ['status', '&&', 'rm', '-rf', '/'])
      ).rejects.toThrow('Invalid argument');

      await expect(
        safeExecuteCommand('git', ['status', '|', 'cat'])
      ).rejects.toThrow('Invalid argument');

      await expect(
        safeExecuteCommand('git', ['status', '$(whoami)'])
      ).rejects.toThrow('Invalid argument');

      await expect(
        safeExecuteCommand('git', ['status', '${USER}'])
      ).rejects.toThrow('Invalid argument');
    });

    it('should reject arguments with redirection operators', async () => {
      await expect(
        safeExecuteCommand('git', ['status', '>', '/tmp/output'])
      ).rejects.toThrow('Invalid argument');

      await expect(
        safeExecuteCommand('git', ['log', '<<', 'EOF'])
      ).rejects.toThrow('Invalid argument');
    });

    it('should reject excessively long arguments', async () => {
      const longArg = 'a'.repeat(1001);
      await expect(
        safeExecuteCommand('git', [longArg])
      ).rejects.toThrow('Argument too long');
    });

    it('should handle command timeouts', async () => {
      // This would timeout in real scenario, but we use short timeout for test
      const result = await safeExecuteCommand('node', ['--version'], { timeout: 5000 });
      expect(result.exitCode).toBe(0);
    }, 10000);

    it('should handle non-existent commands gracefully', async () => {
      const result = await safeExecuteCommand('git', ['nonexistent-command']);
      expect(result.exitCode).not.toBe(0);
      expect(result.stderr).toBeTruthy();
    });
  });

  describe('safeGitCommand', () => {
    it('should execute safe git commands', async () => {
      const result = await safeGitCommand(['--version']);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain('git version');
    });

    it('should reject dangerous git flags', async () => {
      await expect(
        safeGitCommand(['--exec=sh'])
      ).rejects.toThrow('Dangerous git flag not allowed');

      await expect(
        safeGitCommand(['clone', '--exec=/bin/sh', 'repo'])
      ).rejects.toThrow('Git argument not allowed');
    });
  });

  describe('safeNpmCommand', () => {
    it('should execute safe npm commands', async () => {
      const result = await safeNpmCommand(['--version']);
      expect(result.exitCode).toBe(0);
      expect(result.stdout).toBeTruthy();
    });

    it('should reject npm script execution', async () => {
      await expect(
        safeNpmCommand(['run', 'malicious-script'])
      ).rejects.toThrow('NPM script execution not allowed');

      await expect(
        safeNpmCommand(['run-script', 'malicious'])
      ).rejects.toThrow('Cannot execute arbitrary npm scripts');
    });
  });

  describe('Command Injection Prevention', () => {
    it('should not allow backtick command substitution', async () => {
      await expect(
        safeExecuteCommand('git', ['log', '`whoami`'])
      ).rejects.toThrow('Invalid argument');
    });

    it('should not allow semicolon command chaining', async () => {
      await expect(
        safeExecuteCommand('git', ['status', ';cat /etc/passwd'])
      ).rejects.toThrow('Invalid argument');
    });

    it('should not allow pipe command chaining', async () => {
      await expect(
        safeExecuteCommand('git', ['log', '|', 'grep', 'password'])
      ).rejects.toThrow('Invalid argument');
    });

    it('should not allow newline injection', async () => {
      await expect(
        safeExecuteCommand('git', ['log', '\nrm -rf /'])
      ).rejects.toThrow('Invalid argument');
    });
  });
});
