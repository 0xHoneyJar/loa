import unicodedata

from tagidx import TagIndex, tag_key

CAFE_NFC = "Café"
CAFE_NFD = "Café"


def test_composed_and_decomposed_accents_are_one_tag():
    assert tag_key(CAFE_NFC) == tag_key(CAFE_NFD)
    idx = TagIndex()
    idx.add(CAFE_NFC)
    idx.add(CAFE_NFD)
    idx.add("CAFÉ")
    assert len(idx) == 1
    assert idx.count("café") == 3


def test_full_case_folding():
    assert tag_key("Straße") == tag_key("STRASSE")
    assert tag_key("ΣΙΣΥΦΟΣ") == tag_key("σισυφος")


def test_compatibility_forms():
    assert tag_key("ＡＢＣ") == tag_key("abc")
    assert tag_key("ﬁle") == tag_key("file")


def test_unicode_whitespace_collapses():
    assert tag_key("new 　york") == tag_key("New York")


def test_key_is_stable():
    for t in (CAFE_NFD, "Straße", "Ａ b", "x"):
        k = tag_key(t)
        assert tag_key(k) == k
        assert unicodedata.is_normalized("NFKC", k)


def test_remove_uses_the_same_key():
    idx = TagIndex()
    idx.add("New  York")
    idx.add(CAFE_NFD)
    assert idx.remove("new york") is True
    assert idx.remove(CAFE_NFC) is True
    assert len(idx) == 0


def test_label_is_first_spelling_and_merge_folds():
    a, b = TagIndex(), TagIndex()
    a.add(CAFE_NFD)
    b.add_text("café, CAFÉ")
    a.merge(b)
    assert a.labels() == [(CAFE_NFD, 3)]
