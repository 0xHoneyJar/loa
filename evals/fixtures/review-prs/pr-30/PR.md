# chore(optimizer): add debug log when waiting for dep before init

`transformRequest` against a module containing reference to a dependency in `consumer: 'server'` when dep optimizer is enabled will never be fulfilled until the dependency optimizer is initialized (i.e. the server is listening).
This PR adds a log to detect those cases for easier debug.

refs https://github.com/vitejs/vite/issues/23143
refs https://github.com/vitejs/vite/pull/22852
