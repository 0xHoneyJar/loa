from helpers import run_cli, write_config


def test_config_apply_used_without_apply_option(tmp_path):
    cfg = write_config(tmp_path, {"apply": ["strip", "upper"]})
    assert run_cli(["--config", cfg], " a \n") == (0, "A\n", "")


def test_apply_option_wins_over_config(tmp_path):
    cfg = write_config(tmp_path, {"apply": ["upper"]})
    assert run_cli(["--config", cfg, "--apply", "rev"], "ab\n") == (0, "ba\n", "")


def test_config_unknown_key(tmp_path):
    cfg = write_config(tmp_path, {"aply": ["upper"]})
    assert run_cli(["--config", cfg], "x\n") == (2, "", "textpipe: config: unknown key aply\n")


def test_config_apply_unknown_filter(tmp_path):
    cfg = write_config(tmp_path, {"apply": ["nope"]})
    assert run_cli(["--config", cfg], "x\n") == (2, "", "textpipe: config: unknown filter: nope\n")


def test_config_apply_shape(tmp_path):
    cfg = write_config(tmp_path, {"apply": "upper"})
    assert run_cli(["--config", cfg])[2] == "textpipe: config: apply must be a list of filter names\n"


def test_config_not_json(tmp_path):
    path = tmp_path / "bad.json"
    path.write_text("{nope", encoding="utf-8")
    assert run_cli(["--config", str(path)]) == (2, "", "textpipe: config: not valid JSON\n")
    assert run_cli(["--config", str(tmp_path / "none.json")])[2].startswith("textpipe: config: cannot read ")
