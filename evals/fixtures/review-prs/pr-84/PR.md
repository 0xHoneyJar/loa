# fix(format/js): keep parens around an instantiation expression before `!` and heritage type arguments

## Summary

The formatter outputs code which is not valid for two cases:

- `(make<T>)!` → `make<T>!`. Also: `(make<T>)!.b`, `(make<T>)!()` and `(make<T>)!.c<U>`.
- `class D extends (B<T>)<T> {}` → `class D extends B<T><T> {}`.

Prettier has fixed the first case in prettier/prettier#20177, and oxc does both.

Change: two additional cases in `TsInstantiationExpression::needs_parentheses` (`crates/biome_js_syntax/src/parentheses/expression.rs`):

- don't remove the parentheses if the parent is `TsNonNullAssertionExpression`;
- don't remove the parentheses if the parent is `JsExtendsClause` which has type arguments.

`class C extends (B<T>) {}` and `x = make<T>` will still remove parentheses, just like before.

Based on #12496 and #12536 (merged), in the same method.

Found by formatting Prettier's TypeScript test files using Biome, and seeing if the result parses (TypeScript 5.9 compiler).

Changeset included (with a diff).

Claude Code did most of the work on this PR.

## Test Plan

New spec test `ts/expression/instantiation_expression_non_null.ts`.

On main, 7 out of 9 lines of this file have their parentheses stripped, and the resulting output is not parsable (using the TypeScript 5.9 compiler). With the change, the output becomes parsable and consistent after the second formatting run.

Important: this spec test cannot fail on the main branch alone, as the output of main is not parsable and the spec harness ignores them (the expected behavior as per #12498).

All `biome_js_formatter` and `biome_js_syntax` tests succeed.

## Docs

N/A
