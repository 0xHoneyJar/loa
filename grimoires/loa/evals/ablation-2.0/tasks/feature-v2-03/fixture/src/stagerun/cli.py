"""Command line: ``stagerun run SPEC INPUT OUTPUT``."""
import json
import sys

from .errors import PipelineError
from .pipeline import Pipeline
from .store import read_json, write_json

USAGE = "usage: stagerun run SPEC INPUT OUTPUT"


def main(argv, stdout=None, stderr=None):
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    if len(argv) != 4 or argv[0] != "run":
        print(USAGE, file=stderr)
        return 2
    spec_path, input_path, output_path = argv[1:]
    try:
        with open(spec_path, encoding="utf-8") as fh:
            pipeline = Pipeline.from_spec(fh.read())
        data = read_json(input_path)
        result = pipeline.run(data)
    except OSError as exc:
        print(f"stagerun: {exc.filename}: cannot read", file=stderr)
        return 1
    except json.JSONDecodeError:
        print(f"stagerun: {input_path}: not JSON", file=stderr)
        return 1
    except PipelineError as exc:
        print(f"stagerun: {exc}", file=stderr)
        return 1
    write_json(output_path, result)
    return 0
