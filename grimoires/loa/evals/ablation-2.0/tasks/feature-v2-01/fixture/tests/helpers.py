import io
import json

from textpipe.cli import main


def run_cli(argv, text=""):
    out, err = io.StringIO(), io.StringIO()
    code = main(argv, stdin=io.StringIO(text), stdout=out, stderr=err)
    return code, out.getvalue(), err.getvalue()


def write_config(tmp_path, data):
    path = tmp_path / "textpipe.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return str(path)
