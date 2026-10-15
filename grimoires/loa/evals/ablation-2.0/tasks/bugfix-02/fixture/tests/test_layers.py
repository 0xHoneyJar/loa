from layercfg import Store, get, lookup_stats


def make():
    s = Store({"db": {"host": "localhost", "port": 5432}, "debug": False})
    s.load({"db": {"port": 6543}, "name": "svc"})
    return s


def test_layers_merge_nested():
    s = make()
    assert get(s, "db.host") == "localhost"
    assert get(s, "db.port") == 6543
    assert get(s, "name") == "svc"


def test_override_wins_and_is_seen_after_a_read():
    s = make()
    assert get(s, "debug") is False
    s.set("debug", True)
    assert get(s, "debug") is True


def test_missing_key_gives_default():
    s = make()
    assert get(s, "db.user") is None
    assert get(s, "nope.deeper", "x") == "x"


def test_repeated_reads_hit_the_memo():
    s = make()
    before = lookup_stats()
    for _ in range(5):
        get(s, "db.port")
    after = lookup_stats()
    assert after["misses"] - before["misses"] == 1
    assert after["hits"] - before["hits"] == 4


def test_merged_is_a_copy():
    s = make()
    m = s.merged()
    m["db"]["port"] = 1
    assert get(s, "db.port") == 6543
