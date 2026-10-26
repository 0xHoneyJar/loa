# fix(runtime-dom): treat playsinline as a boolean attribute

`<video :playsinline="false">` renders `playsinline="false"`, both on the client and in SSR output. `playsinline` is a boolean attribute in the HTML spec, so its presence means true whatever the value, and the video still plays inline on iOS.

Its DOM property is `playsInline`, so the lowercase key fails the `key in el` check and goes through `patchAttr`, but unlike `readonly` it isn't in `specialBooleanAttrs`, so `false` gets written as a string. Adding it to that list fixes both paths (the SSR `isBooleanAttr` list is built from it), and it now behaves like `readonly`. Added a test in `patchAttrs.spec.ts` and one in `ssrRenderAttrs.spec.ts`.

Playground: https://play.vuejs.org/#eNptUk1PhDAQ/SuTxsiaIBzUC1YSDyaa6M1jE0UYXGJ32kDB3RD+u9N2vw7eeI83b2bedBaP1mbTiKIQcqj7zjoY0I22VNRtrOkdzNBjm8Jv5ep1CobezEgOG1ig7c0GEi5OFCmqDQ0OOtIdITz4olVb6QGvDr+mPXskzOj2VJIwqagdqXadIeaqZnUFsyLwqmyq9OhNPxlg//z+9lrAxTxFPjuSi1I0dQ2azOpqN7yEWc6VZ/TyqWhRdNxn5XvyFGHPVVwjDYOkHEGrx2FdQGLN4BJYWCfzGBcHxcDhhr0dMgKQuvpCXcqOLG/odhYflKjXWP98ma0SMF1vTIOaydiGqbw8JTfPh+9lkXn0CrZhNSjCElFxbsE5MpyUKGUelLHI9liyo8/a23kY+fJpa7H2l/zt3PrUPhytAFnzjOWldvfB7PLb3XsQrT2SeVBARc1e/E/0wWyv5ObcWuZnWYlUfEzYD3xzfoA32V12eyOWP4I05oU=


<!-- This is an auto-generated comment: release notes by coderabbit.ai -->

## Summary by CodeRabbit

* **Bug Fixes**
  * The `playsinline` attribute on video elements is now handled consistently: enabled values render as an empty attribute, while disabled values omit it.

<!-- end of auto-generated comment: release notes by coderabbit.ai -->
