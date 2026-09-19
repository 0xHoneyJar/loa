# fix(#938): butterfreezone-validate skips Express/Fastify route patterns

Route-parameter tokens such as /users/:id were being reported as missing file references. Skip route patterns in the reference check and cover the shapes with a regression suite.
