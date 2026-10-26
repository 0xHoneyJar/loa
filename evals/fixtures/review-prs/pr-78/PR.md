# fix: resolve reply.mediaType from raw response headers

#### Description

When inspecting `reply.mediaType`, the getter in `lib/reply.js` directly accessed `this[kReplyHeaders]['content-type']`.

However, `reply.getHeader()`, `reply.hasHeader()`, `reply.getHeaders()`, and `reply.send()` (line 177: `ContentType.from(this.getHeader('content-type'))`) all resolve headers from both Fastify's internal reply headers (`this[kReplyHeaders]`) and fallback to Node's raw response headers (`this.raw.getHeader(key)`).

If a plugin, hook, or middleware sets the content type on `reply.raw` (e.g. `reply.raw.setHeader('content-type', 'application/json')`):
- `reply.getHeader('content-type')` returns `'application/json'`.
- `reply.send()` parses `ContentType.from(this.getHeader('content-type'))`.
- But `reply.mediaType` returned `undefined`.

This updates the `mediaType` getter in `lib/reply.js` to read `this.getHeader('content-type')`, aligning it with `reply.send()` and properly supporting headers set via `reply.raw.setHeader()`.

#### Checklist

- [x] run `npm run test && npm run benchmark --if-present`
- [x] tests and/or benchmarks are included
- [ ] documentation is changed or added
- [x] commit message and code follows the [Developer's Certificate of Origin](https://github.com/fastify/.github/blob/main/CONTRIBUTING.md#developers-certificate-of-origin-11) and the [Code of conduct](https://github.com/fastify/.github/blob/main/CODE_OF_CONDUCT.md)
