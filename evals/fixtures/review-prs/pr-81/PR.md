# feat: add BATS_ALLOW_EMPTY_SUITE environment variable

Fixes #1239.

`--allow-empty-suite` (added in v1.14.0) can only be used by projects that no longer need to run with bats < 1.14, since older versions abort on the unknown flag. This adds `BATS_ALLOW_EMPTY_SUITE`: set it to any non-empty value and an empty suite exits 0, just like the flag. Older bats versions ignore the variable and already exit 0 on an empty suite, so the same setting works across versions — which is what motivated this, see https://github.com/containers/conmon/pull/672 where pinning bats to v1.13.0 was the only option.

The second commit (feel free to drop if you don't like it) rewords the error message to say what to do instead of asking a question, and mentions the variable next to the flag:

```
ERROR: Found no tests. Use `--allow-empty-suite` or `BATS_ALLOW_EMPTY_SUITE=1` to suppress this error.
```

Tests cover the variable enabling an empty suite, an empty value not enabling it, and no effect when tests exist; the flag's own positive case was missing and is added too. Docs (`--help`, man page, CHANGELOG) updated.

- [x] I have reviewed the [Contributor Guidelines][contributor].
- [x] I have reviewed the [Code of Conduct][coc] and agree to abide by it

[contributor]: https://github.com/bats-core/bats-core/blob/master/docs/CONTRIBUTING.md
[coc]:         https://github.com/bats-core/bats-core/blob/master/docs/CODE_OF_CONDUCT.md
