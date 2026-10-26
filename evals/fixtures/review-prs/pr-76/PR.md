# fix(ext/napi): ignore the callback return value while an exception is pending

Fixes #36941

Two places where Deno did not match Node when a Node-API call leaves an exception pending:

- `call_fn` rethrew the pending exception and then still set the callback's return value. Node ignores the return value in that case ([js_native_api_v8.cc](https://github.com/nodejs/node/blob/5e3bbc4ac4e4f24c41a892948046dbe8de4c2369/src/js_native_api_v8.cc#L515-L517), added in nodejs/node#39476), because addons can return an invalid `napi_value` after throwing. Deno dereferenced it and crashed.
- `napi_create_dataview` with `byte_offset + byte_length` past the end of the buffer threw the RangeError but returned `napi_ok`, leaving `*result` unset. It now returns `napi_pending_exception`, as Node does.

Both crash the Node-API conformance tests `js-native-api/test_function` and `js-native-api/test_dataview`.

Tests: `tests/napi` gets `test_throw_return_invalid` (throws, then returns `0xFFFFFFFFF`, the value Node's own `test_function.c` uses) and `test_dataview_out_of_range` (checks the status, that the exception is pending and that the result is unset).

Without the change in `ext/napi` and with the new tests, `exception_test.js` crashes on the new test (exit 139) and `dataview_test.js` fails with:

```
napi create_dataview out of range returns napi_pending_exception => ./dataview_test.js:17:6
error: AssertionError: Values are not equal.
    [
-     0,
+     10,
      true,
      false,
    ]
```

With it, `tests/napi` passes (`ok | 152 passed | 0 failed | 3 ignored`) and `cargo test -p integration_tests --test integration napi` passes all 6 tests, on Linux x86_64. The standalone addons from the issue now throw the same errors as Node instead of crashing.

This PR was written with help from Claude Opus 5.5. I reproduced both crashes with standalone addons on Linux and Windows, checked the behaviour against Node's source, and ran the napi tests with and without the change.
