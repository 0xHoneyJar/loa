import json

import pytest

from ledgerio import RecordError, create_entry, read_csv, read_json, update_entry

GOOD = {"id": "t1", "amount": 12.5, "currency": "EUR", "date": "2026-10-01"}

BAD = [
    ("not a dict", "record must be a mapping"),
    ({"id": "t1", "amount": 1, "currency": "EUR"}, "missing field: date"),
    ({**GOOD, "id": "  "}, "id must be a non-empty string"),
    ({**GOOD, "amount": -1}, "amount must be a non-negative number"),
    ({**GOOD, "amount": True}, "amount must be a non-negative number"),
    ({**GOOD, "amount": "12"}, "amount must be a non-negative number"),
    ({**GOOD, "currency": "eur"}, "currency must be a three-letter ISO code"),
    ({**GOOD, "currency": "EURO"}, "currency must be a three-letter ISO code"),
    ({**GOOD, "date": "2026-02-30"}, "date must be an ISO date (YYYY-MM-DD)"),
    ({**GOOD, "date": None}, "date must be an ISO date (YYYY-MM-DD)"),
]


def test_csv_reads_and_converts():
    rows = read_csv("id,amount,currency,date\nt1,12.5,EUR,2026-10-01\nt2,3,USD,2026-10-02\n")
    assert rows == [GOOD, {"id": "t2", "amount": 3, "currency": "USD", "date": "2026-10-02"}]


def test_csv_names_the_line():
    with pytest.raises(RecordError, match=r"^line 3: currency must be a three-letter ISO code$"):
        read_csv("id,amount,currency,date\nt1,1,EUR,2026-10-01\nt2,1,usd,2026-10-01\n")
    with pytest.raises(RecordError, match=r"^line 2: missing field: date$"):
        read_csv("id,amount,currency\nt1,1,EUR\n")
    with pytest.raises(RecordError, match=r"^line 2: amount must be a non-negative number$"):
        read_csv("id,amount,currency,date\nt1,lots,EUR,2026-10-01\n")


def test_json_reads():
    assert read_json(json.dumps([GOOD])) == [GOOD]


@pytest.mark.parametrize("record,message", BAD)
def test_json_rules(record, message):
    with pytest.raises(RecordError) as ei:
        read_json(json.dumps([GOOD, record]))
    assert str(ei.value) == f"item 1: {message}"


@pytest.mark.parametrize("record,message", BAD)
def test_api_rules(record, message):
    with pytest.raises(RecordError) as ei:
        create_entry([], record)
    assert str(ei.value) == message


def test_api_create_and_update():
    ledger = []
    create_entry(ledger, GOOD)
    with pytest.raises(RecordError, match="duplicate id"):
        create_entry(ledger, GOOD)
    assert update_entry(ledger, "t1", {"amount": 20})["amount"] == 20
    with pytest.raises(RecordError, match=r"^currency must be a three-letter ISO code$"):
        update_entry(ledger, "t1", {"currency": "E1R"})
    assert ledger[0]["amount"] == 20
    with pytest.raises(RecordError, match="no such entry"):
        update_entry(ledger, "t9", {})


def test_newline_in_currency_is_rejected_everywhere():
    bad = {**GOOD, "currency": "EUR\n"}
    with pytest.raises(RecordError):
        create_entry([], bad)
    with pytest.raises(RecordError):
        read_json(json.dumps([bad]))
