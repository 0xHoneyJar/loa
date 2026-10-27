# feat(hooks): support disposables in onClose hook (#5669)

## What

Enables `fastify.addHook('onClose', disposable)` to accept `AsyncDisposable` and `Disposable` objects implementing `Symbol.asyncDispose` or `Symbol.dispose` (ECMAScript Explicit Resource Management), and ensures non-function, non-disposable handlers throw Fastify's standard `FST_ERR_HOOK_INVALID_HANDLER` error.

Fixes #5669.

## Why

With Explicit Resource Management supported natively in modern Node.js and TypeScript, services and database clients often implement `Symbol.asyncDispose` or `Symbol.dispose`. Previously, passing such an object to `fastify.addHook('onClose', resource)` resulted in an unhandled `TypeError: fn.bind is not a function`.

As suggested in #5669, supporting disposables directly in `onClose`:
- Simplifies registering resources that should be disposed on server shutdown (e.g. `fastify.addHook('onClose', dbClient)`).
- Awaits `[Symbol.asyncDispose]()` or invokes `[Symbol.dispose]()` cleanly during the `avvio` shutdown sequence.
- Standardizes validation error reporting using `FST_ERR_HOOK_INVALID_HANDLER` when an invalid value is provided.

## Testing

- Added `test/close-disposable.test.js` testing:
  - `Symbol.asyncDispose` invocation upon `app.close()`.
  - `Symbol.dispose` invocation upon `app.close()`.
  - Preference of `asyncDispose` over `dispose` when both exist.
  - Error propagation on rejected or thrown disposals.
  - Encapsulated plugin execution ordering.
  - `FST_ERR_HOOK_INVALID_HANDLER` throwing for invalid inputs.
- Added type tests in `test/types/using.tst.ts`.
- Verified `test/close.test.js` and `test/close-pipelining.test.js` all pass (28/28).
- Verified ESLint, TypeScript (`npm run test:types`), and Markdown lint pass.
