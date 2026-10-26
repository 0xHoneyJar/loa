# fix(types): custom logger instance not assignable to FastifyInstance

Proposal:

- `childLoggerFactory` (on `FastifyInstance`, `setChildLoggerFactory`, and `RouteShorthandOptions`) was parameterized with the instance's own `Logger` generic. This placed a user-supplied logger type (e.g., a `pino.Logger` instance passed via `loggerInstance`) in a contravariant position, nested within `route()` and `RouteOptions`. Under TypeScript strict mode, this caused a `FastifyInstance` created with a custom logger to be non-assignable to the default `FastifyInstance<..., FastifyBaseLogger>` type.
- Pin `childLoggerFactory` to `FastifyBaseLogger` instead of the instance’s `Logger` generic, since the child logger factory only needs to operate on the base logger interface. This keeps `FastifyInstance` variance-safe regardless of which concrete logger implementation was passed in.
- Added a regression test using loggerInstance, the officially typed API for passing a pre-built logger instance.

Note:
- Closes #4960
- This PR closes the following PRs: https://github.com/fastify/fastify/pull/6534 and https://github.com/fastify/fastify/pull/6750, as they are no longer up to date and contain conflicts since it still uses `tsd` for type testing
