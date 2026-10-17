# Task: resumable runs for stagerun

`stagerun` (under `src/stagerun/`) runs a pipeline of named steps over JSON data. `stagerun.pipeline.Pipeline(steps)` takes a list of `(name, function)` pairs, and `Pipeline.run(data)` feeds `data` to the first step and each step's output to the next, returning the last output. The command line `stagerun.cli.main(argv, stdout=None, stderr=None)` runs `run SPEC INPUT OUTPUT`: a spec file of built-in step names, a JSON input file and a JSON output file. Add checkpoints, so that a run that failed or was interrupted can resume without redoing the steps that already completed.

## API

`Pipeline.run(data, *, checkpoint=None, resume=False)`. `checkpoint` is a file path (`str` or `os.PathLike`). With `checkpoint=None` a run behaves exactly as today. `resume=True` without a checkpoint raises `ValueError("resume needs a checkpoint")` before any step runs.

After every run, `Pipeline.last_run` is a list of `(name, how)` pairs for the steps that completed in that run, in pipeline order. `how` is `"ran"` when the step's function was called and `"reused"` when its output came from the checkpoint. A run without a checkpoint reports every completed step as `"ran"`.

## The checkpoint file

The file is UTF-8 JSON: `{"version": 1, "steps": [entry, ...]}`. Each entry is `{"name": <step name>, "input": <digest of the step's input>, "output": <the step's output>}`. The entries are the steps completed so far, in pipeline order, starting with the first step. The digest of a value is the lowercase hex SHA-256 of `json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")`.

After every completed step, reused or ran, the whole file is rewritten with the entries completed so far. Write it atomically: write a temporary file in the same directory, then `os.replace` it over the checkpoint. If a step's output cannot be serialised as JSON, the run raises `CheckpointError(f"step {name!r} output is not JSON-serialisable")` right after that step returns. The file then keeps the entries written before.

## Fresh runs and resumed runs

- **A run without `resume`** starts from the first step. It deletes an existing checkpoint file before the first step runs.
- **A run with `resume` and no checkpoint file** is a fresh run.
- **A run with `resume` and an existing file** loads and checks the file before any step runs (see the errors below). Step *i* is reused only when four things hold: every step before it was reused, the file has an entry *i*, that entry names this step, and the entry's input digest equals the digest of the input step *i* receives now. A reused step's function is not called, and its recorded output becomes the next step's input. The first step that is not reused runs, and so does every step after it. Their old entries are replaced as the run goes on. For example, a changed pipeline input reruns everything, even when the first step happens to produce its old output again.
- **A failing step:** when a step raises, the exception propagates unchanged and the file keeps the entries of the steps completed before it. A later resume reruns that step from its input.

## Errors

`stagerun.errors.CheckpointError` is a subclass of `stagerun.errors.PipelineError`. When resuming, the file is checked in this order, and the first problem found raises `CheckpointError` with exactly this message:

1. The file is not valid UTF-8 JSON: `corrupt checkpoint: not JSON`.
2. The top level is not an object: `corrupt checkpoint: not an object`.
3. `version` is not the integer `1` (a string or `true` does not count): `corrupt checkpoint: unsupported version <repr>`. Here `<repr>` is the `repr` of the value, or `None` when the key is missing.
4. `steps` is not a list: `corrupt checkpoint: steps is not a list`.
5. An entry is not an object with exactly the keys `name` (a string), `input` (64 lowercase hex digits) and `output`: `corrupt checkpoint: bad entry <n>`, where `<n>` counts from 1.
6. The file has more entries than the pipeline has steps: `checkpoint has <entries> steps, pipeline has <steps>`.
7. An entry names a different step than the pipeline step at the same position, checked for every entry in order: `checkpoint step <n> is <repr of entry name>, pipeline step <n> is <repr of step name>`.

## Command line

`run SPEC INPUT OUTPUT [--checkpoint PATH] [--resume]` passes the checkpoint and resume flag to `Pipeline.run`. With `--checkpoint`, it prints one line per completed step to standard output: `<how> <name>`, for example `reused strip`. `--resume` without `--checkpoint` is a usage error: exit status 2, nothing on standard output, and the single line `stagerun: --resume needs --checkpoint` on standard error. A `CheckpointError` exits with status 1, prints nothing on standard output and `stagerun: <message>` on standard error, and the output file is not written.

The existing suite must stay green. Run it with `python3 -m pytest -q tests`, and add tests of your own for checkpoints and resuming.
