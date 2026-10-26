# fix(optimizer): fall back to yarn.lock for lockfile hash

Yarn v4 with `nodeLinker: pnpm` doesnt write the hash files that Vite uses. With this setup the lockfile hash is always empty string and prebundled devs never update after `yarn install`.
The fix is to fallback to `yarn.lock` (same way it does for Bun), when no lockfile is found.

I also added tests that confirm this new fix.

AI was used to write the code, but I reviewed it.

Closes #23666
