/**
 * Legba Cloudflare Worker Entry Point
 *
 * Wraps the Legba skill for deployment as a Cloudflare Worker.
 * Handles HTTP requests from Moltbot gateway.
 */

import legbaSkill, { type LegbaEnv, type Message, type Context } from './index.js';

/**
 * Worker environment bindings
 */
interface WorkerEnv {
  // R2 buckets
  SESSIONS_BUCKET: R2Bucket;
  STATE_BUCKET: R2Bucket;
  REGISTRY_BUCKET: R2Bucket;

  // Secrets
  ANTHROPIC_API_KEY: string;
  GITHUB_TOKEN: string;
  GITHUB_APP_ID: string;
  GITHUB_APP_PRIVATE_KEY: string;
  DISCORD_BOT_TOKEN?: string;
  TELEGRAM_BOT_TOKEN?: string;

  // Environment variables
  ENVIRONMENT: string;
  LOG_LEVEL: string;
}

/**
 * Request body from Moltbot
 */
interface MoltbotRequest {
  message: {
    text: string;
    from: {
      id: string;
      username?: string;
    };
  };
  context: {
    platform: 'telegram' | 'discord';
    channelId: string;
    messageId: string;
  };
  // Callback URL for async responses
  callbackUrl?: string;
}

/**
 * Worker fetch handler
 */
export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    const url = new URL(request.url);

    // Health check endpoint
    if (url.pathname === '/health' || url.pathname === '/') {
      return new Response(
        JSON.stringify({
          status: 'ok',
          skill: 'legba',
          version: '1.0.0',
          mode: 'test', // Will be 'production' when sandbox is available
        }),
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Ready check - verify dependencies
    if (url.pathname === '/ready') {
      const checks: Record<string, string> = {};

      // Check R2 buckets
      try {
        await env.SESSIONS_BUCKET.list({ limit: 1 });
        checks.sessions_bucket = 'ok';
      } catch {
        checks.sessions_bucket = 'error';
      }

      try {
        await env.REGISTRY_BUCKET.list({ limit: 1 });
        checks.registry_bucket = 'ok';
      } catch {
        checks.registry_bucket = 'error';
      }

      // Check secrets (just existence, not validity)
      checks.anthropic_key = env.ANTHROPIC_API_KEY ? 'configured' : 'missing';
      checks.github_token = env.GITHUB_TOKEN ? 'configured' : 'missing';
      checks.github_app_id = env.GITHUB_APP_ID ? 'configured' : 'missing';
      checks.github_app_key = env.GITHUB_APP_PRIVATE_KEY ? 'configured' : 'missing';

      const allOk = Object.values(checks).every(
        (v) => v === 'ok' || v === 'configured'
      );

      return new Response(
        JSON.stringify({
          status: allOk ? 'ready' : 'not_ready',
          checks,
        }),
        {
          status: allOk ? 200 : 503,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Handle skill invocation
    if (url.pathname === '/invoke' && request.method === 'POST') {
      try {
        const body = (await request.json()) as MoltbotRequest;

        // Initialize the skill with environment
        // Cast R2Bucket to match our internal type definition
        const legbaEnv: LegbaEnv = {
          LEGBA_R2: env.SESSIONS_BUCKET as unknown as LegbaEnv['LEGBA_R2'],
          ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY,
          GITHUB_TOKEN: env.GITHUB_TOKEN,
          GITHUB_APP_ID: env.GITHUB_APP_ID,
          GITHUB_APP_PRIVATE_KEY: env.GITHUB_APP_PRIVATE_KEY,
        };

        legbaSkill.initialize(legbaEnv);

        // Collect responses
        const responses: string[] = [];

        // Create context with response handlers
        const context: Context = {
          platform: body.context.platform,
          channelId: body.context.channelId,
          messageId: body.context.messageId,
          reply: async (text: string) => {
            responses.push(text);
          },
          sendTo: async (channelId: string, text: string) => {
            responses.push(`[To ${channelId}]: ${text}`);
          },
        };

        // Handle the message
        await legbaSkill.handle(body.message, context);

        return new Response(
          JSON.stringify({
            success: true,
            responses,
          }),
          {
            headers: { 'Content-Type': 'application/json' },
          }
        );
      } catch (error) {
        const message =
          error instanceof Error ? error.message : 'Unknown error';
        return new Response(
          JSON.stringify({
            success: false,
            error: message,
          }),
          {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
          }
        );
      }
    }

    // 404 for unknown paths
    return new Response(
      JSON.stringify({
        error: 'Not found',
        endpoints: ['/health', '/ready', '/invoke'],
      }),
      {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  },
};
