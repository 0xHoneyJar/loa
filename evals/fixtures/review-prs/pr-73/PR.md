# fix(build): wait for in-flight stylesheets in preload helper (fix #23652)

### Description

Fixes #23652.

In the build preload helper (`packages/vite/src/node/plugins/importAnalysisBuild.ts`), `seen[dep.href]` was set to `true` synchronously as soon as a stylesheet `<link>` was created and appended. 

If another dynamic import requested the same chunk (or another chunk sharing that stylesheet) while the stylesheet was still loading, it hit `if (dep.href in seen) return` and resolved immediately without awaiting the in-flight `load` event, causing a flash of unstyled content (FOUC).

This PR retains the pending CSS preload `Promise` in `seen[dep.href]` while in-flight so subsequent imports share and wait for the same loading promise. Once settled (`load` or `error`), `seen[dep.href]` resets to `undefined`, allowing any later imports after load to resolve immediately without delay or duplicate link insertions.

### Additional context

- Added unit tests in `importAnalysisBuild.spec.ts` testing in-flight stylesheet waiting, deduplication, and error propagation.
- Exported `getPreloadCode` with explicit return type annotation for testing.

---

### What is the purpose of this pull request?

- [x] Bug fix
- [ ] Feature
- [ ] Documentation update
- [ ] Code style update (formatting, local variables)
- [ ] Refactoring (no functional changes, no api changes)
- [ ] Build / CI related changes
- [ ] Other, please describe:

### Before submitting the PR, please make sure you do the following

- [x] Read the [Contributing Guidelines](https://github.com/vitejs/vite/blob/main/CONTRIBUTING.md).
- [x] Read the [AI Policy](https://github.com/vitejs/vite/blob/main/CONTRIBUTING.md#ai-policy).
- [x] Check that there isn't already a PR that solves the problem the same way.
- [x] Provide an explanation in the PR description above.
- [x] Add relevant tests.
