from tagidx import TagIndex, display, parse_tags, tag_key


def test_parse_splits_and_drops_hashes():
    assert parse_tags("#python, data ; ML\n\n,  ") == ["python", "data", "ML"]


def test_ascii_case_and_spacing_are_one_tag():
    assert tag_key("  Machine   Learning ") == tag_key("machine learning")


def test_display_keeps_case():
    assert display("  Machine   Learning ") == "Machine Learning"


def test_counting_and_first_label_wins():
    idx = TagIndex()
    idx.add_text("Python, python, PYTHON, data")
    assert idx.count("python") == 3
    assert idx.labels() == [("Python", 3), ("data", 1)]


def test_remove_plain():
    idx = TagIndex()
    idx.add("rust")
    assert idx.remove("Rust") is True
    assert idx.remove("rust") is False
    assert len(idx) == 0


def test_merge():
    a, b = TagIndex(), TagIndex()
    a.add_text("x, y")
    b.add_text("Y, z")
    a.merge(b)
    assert a.labels() == [("y", 2), ("x", 1), ("z", 1)]
