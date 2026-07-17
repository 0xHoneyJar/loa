---
description: Run the installed Loa Aleph adapter against its immutable bundle.
argument-hint: start <files-or-directories...> | status [RUN-id] | resume <RUN-id> | validate <RUN-id>
---

Use the installed `loa-aleph` skill for this command. Forward `$ARGUMENTS`
unchanged to `.claude/aleph/bin/loa-aleph.mjs`. Treat its structured result as
authoritative adapter state, and do not replace a failed preflight, pinned
runtime, worker-isolation requirement, or human gate with an inferred fallback.
