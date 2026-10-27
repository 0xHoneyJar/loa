# fix(runtime-core): only flush jobs queued by the root render itself

close #6728

A root `render()` ends with `flushPreFlushCbs()` and `flushPostFlushCbs()` so that pre watchers triggered in a new tree's setup run before its `mounted` (#5721). Both drain the whole queue, so `createApp().mount()` inside a pre watcher runs every other pending pre job nested in that callback (#6728), and a plain `mount()` after a state change runs other apps' pending watchers synchronously (mount side of #14215).

A root render now only flushes what it is responsible for:

- **Mount / unmount**: pre jobs of the components it created (`id >= minUid`, a compat root uses its own uid) and the post cbs it queued. Post watcher jobs are judged by owner (`job.i`: instance / `null` for component-less / `undefined` for internal cbs), other cbs by whether they were already pending. Jobs of other components and component-less watchers stay in the queue and run in order after the current job.
- **Root update**: unchanged, still flushes all pending pre jobs and post cbs.
- `flushPreFlushCbs` rescans after running a job when not filtering by instance, since a job can queue a smaller-id job ahead of the scan index (pre-existing hole).
- `apiWatch` marks post watcher jobs with their owner when queued, covering the bound first run of `watchPostEffect`.

Tests cover mount inside pre/post watchers, sync mount/unmount with pending watchers of other apps, component-less watchers, root update ordering (`beforeUpdate` pre, own post watcher, `updated` dedup), compat pre/post watchers from `created()` and `watchPostEffect` in `setup()`, and a mount whose setup flushed the pending post queue.

<!-- This is an auto-generated comment: release notes by coderabbit.ai -->
## Summary by CodeRabbit

* **Bug Fixes**
  * Improved the timing of watchers around app mounts, updates, and lifecycle hooks, including nested mounts and component-less setup.
  * Watchers remain isolated between apps: mounting or unmounting one app no longer triggers another app’s watcher.
  * Post-flush callbacks now run at the expected time when mounting occurs after pending scheduler work has already been processed.
  * Fixed watcher and effect ordering during compatibility-mode instance mounting.
<!-- end of auto-generated comment: release notes by coderabbit.ai -->
