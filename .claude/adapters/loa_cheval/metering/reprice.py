"""Explicit, opt-in re-pricing of historical unpriced cost-ledger rows.

sprint-bug-245 (cycle-125 follow-up, bead bd-ypbg). A ledger row recorded
before the pricing ladder existed carries ``pricing_source: unknown`` and cost
0. The ladder (``find_pricing``: exact → dated → alias → hop, every rung a
config-owned mapping) can now price many of those ids; this module prices
such a row exactly as ``create_ledger_entry`` would price a fresh row with the
same tokens and marks it, so history is never rewritten silently:

    cost_micro_usd      recomputed from the row's tokens at today's catalog rates
    pricing_source      "config"
    pricing_mode        the entry's mode
    pricing_resolution  the ladder rung that matched
    resolved_model      the catalog id the rung priced (when it differs from `model`)
    cost_estimated      True — a price applied after the fact, at current rates
    repriced_at         the pass's UTC timestamp
    repriced_from       {pricing_source, cost_micro_usd} as they were

Only ``(provider, model)`` decides the price (audit F-3): a hint the row
itself carries (``resolved_model``) is never a pricing authority here — it was
written by an adapter for rows that are already priced, and a repaired row
must not be able to nominate its own catalog entry.

Rows that are already priced, rows the ladder still cannot resolve, and rows
that already carry ``repriced_at`` come back unchanged — the same object, so
the file writer can tell by identity which lines to rewrite. The input list
is never mutated.

``reprice_ledger_file`` owns the file handling (audit F-1/F-2): the ledger is
opened ``O_RDWR|O_NOFOLLOW`` and the pass holds the writer's own lock
(``flock(LOCK_EX)`` on the ledger inode, the same lock ``append_ledger``
takes) from the read to the last byte written; the file is rewritten IN
PLACE (``ftruncate`` + write + ``fsync`` on the same inode), so a concurrent
``append_ledger`` blocks and then appends after the new content instead of
landing on an orphaned inode. Untouched lines (priced rows, unresolvable rows,
corrupt lines, blank lines) are written back byte-for-byte. Before the write,
the bytes that were read are copied to ``<ledger>.pre-reprice-<stamp>``
through ``O_CREAT|O_EXCL|O_NOFOLLOW`` (a planted file or symlink of any kind
is never followed; the next ``-N`` name is used) and fsynced — that copy is
the crash-recovery point named in the receipt. The receipt is written the
same way and renamed into place. ``cost-report.sh --reprice [--dry-run]`` is
the caller.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
import time
from typing import Any, Dict, List, Optional, Tuple

from .pricing import calculate_total_cost, find_pricing

Row = Dict[str, Any]

STATS_KEYS = ("rows_scanned", "rows_repriced", "rows_still_unpriced", "rows_skipped_priced", "micro_usd_added")
WRITER = "loa_cheval.metering.reprice.reprice_rows"


class RepriceRefused(RuntimeError):
    """The pass refused to touch the ledger (symlink, missing file)."""


def _int(value: Any) -> int:
    try:
        return int(value) if value is not None else 0
    except (TypeError, ValueError):
        return 0


def is_unpriced(row: Row) -> bool:
    """The report's own definition (cost-report.sh; Bridgebuilder #1269
    FIND-004): ``pricing_source`` is ``unknown``, or absent on a row that
    carries no cost. A pre-metadata row that carries a cost was priced by
    its writer and is not touched."""
    source = row.get("pricing_source")
    if source == "unknown":
        return True
    return source is None and not _int(row.get("cost_micro_usd"))


def reprice_row(row: Row, config: Dict[str, Any], now_iso: str) -> Optional[Row]:
    """A re-priced copy of ``row``, or None when the row is not unpriced,
    was already re-priced, or still cannot be priced through the ladder."""
    if not is_unpriced(row) or row.get("repriced_at"):
        return None
    provider = row.get("provider")
    model = row.get("model")
    if not isinstance(provider, str) or not provider or not isinstance(model, str) or not model:
        return None
    pricing = find_pricing(provider, model, config)
    if pricing is None:
        return None
    breakdown = calculate_total_cost(
        _int(row.get("tokens_in")),
        _int(row.get("tokens_out")),
        _int(row.get("tokens_reasoning")),
        pricing,
        cache_read_tokens=_int(row.get("tokens_cache_read")),
        cache_creation_tokens=_int(row.get("tokens_cache_creation")),
    )
    new = dict(row)
    new["repriced_from"] = {
        "pricing_source": row.get("pricing_source"),
        "cost_micro_usd": _int(row.get("cost_micro_usd")),
    }
    new["cost_micro_usd"] = breakdown.total_cost_micro
    new["pricing_source"] = "config"
    new["pricing_mode"] = pricing.pricing_mode
    new["pricing_resolution"] = pricing.resolution
    if pricing.model != model:
        new["resolved_model"] = pricing.model
    new["cost_estimated"] = True
    new["repriced_at"] = now_iso
    return new


def reprice_rows(rows: List[Row], config: Dict[str, Any], now_iso: str) -> Tuple[List[Row], Dict[str, int]]:
    """Re-price every eligible row in ``rows``.

    Returns ``(out, stats)`` where ``out[i] is rows[i]`` for every row that was
    not changed and ``stats`` counts rows_scanned / rows_repriced /
    rows_still_unpriced / rows_skipped_priced / micro_usd_added.
    """
    stats = {key: 0 for key in STATS_KEYS}
    stats["rows_scanned"] = len(rows)
    out: List[Row] = []
    for row in rows:
        if not is_unpriced(row) or row.get("repriced_at"):
            stats["rows_skipped_priced"] += 1
            out.append(row)
            continue
        new = reprice_row(row, config, now_iso)
        if new is None:
            stats["rows_still_unpriced"] += 1
            out.append(row)
        else:
            stats["rows_repriced"] += 1
            stats["micro_usd_added"] += int(new["cost_micro_usd"])
            out.append(new)
    return out, stats


# ---------------------------------------------------------------------------
# File handling (audit F-1 / F-2)
# ---------------------------------------------------------------------------

def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _write_all(fd: int, data: bytes) -> None:
    view = memoryview(data)
    while view:
        written = os.write(fd, view)
        view = view[written:]


def _create_exclusive(path: str, mode: int = 0o644) -> Tuple[int, str]:
    """Create ``path`` (or ``path-2``, ``path-3``, … when the name is taken by
    a file OR a symlink of any kind — O_EXCL refuses both, O_NOFOLLOW never
    follows) and return (fd, actual_path)."""
    candidate, n = path, 1
    while True:
        try:
            fd = os.open(candidate, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
            return fd, candidate
        except FileExistsError:
            n += 1
            candidate = f"{path}-{n}"
            if n > 1000:
                raise


def write_receipt(receipt_dir: str, basename: str, receipt: Dict[str, Any]) -> str:
    """Write ``receipt`` as ``<receipt_dir>/<basename>[-N].json`` through an
    exclusively created temp file renamed into place; returns the path."""
    os.makedirs(receipt_dir, exist_ok=True)
    final = os.path.join(receipt_dir, f"{basename}.json")
    n = 1
    while os.path.lexists(final):  # two passes in one second never overwrite a receipt
        n += 1
        final = os.path.join(receipt_dir, f"{basename}-{n}.json")
    fd, tmp = _create_exclusive(final + f".tmp.{os.getpid()}")
    try:
        _write_all(fd, (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, final)  # rename never follows a symlink at `final`
    return final


def _split_lines(raw: bytes) -> Tuple[List[bytes], List[Tuple[int, Row]], int]:
    """(lines with their endings, [(line index, parsed row)], corrupt count)."""
    lines = raw.splitlines(keepends=True)
    parsed: List[Tuple[int, Row]] = []
    corrupt = 0
    for i, line in enumerate(lines):
        body = line.rstrip(b"\r\n")
        if not body.strip():
            continue
        try:
            row = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            corrupt += 1
            continue
        if isinstance(row, dict):
            parsed.append((i, row))
        else:
            corrupt += 1
    return lines, parsed, corrupt


def reprice_ledger_file(
    ledger_path: str,
    receipt_dir: str,
    config: Dict[str, Any],
    now_iso: Optional[str] = None,
    dry_run: bool = False,
    stamp: Optional[str] = None,
    catalog_note: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """Re-price ``ledger_path`` in place under the writer's lock.

    Returns the receipt dict (``dry_run: True`` and no file writes when
    ``dry_run``), plus ``receipt_path`` when one was written. Raises
    ``RepriceRefused`` for a symlinked ledger and ``FileNotFoundError`` for a
    missing one; any other failure propagates before the ledger is touched
    (the in-place write starts only after the backup is durable).
    """
    now_iso = now_iso or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    stamp = stamp or time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    flags = (os.O_RDONLY if dry_run else os.O_RDWR) | os.O_NOFOLLOW
    try:
        fd = os.open(ledger_path, flags)
    except OSError as exc:
        if os.path.islink(ledger_path):
            raise RepriceRefused(f"refusing a symlinked ledger: {ledger_path}") from exc
        raise
    try:
        fcntl.flock(fd, fcntl.LOCK_SH if dry_run else fcntl.LOCK_EX)
        chunks = []
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
        raw = b"".join(chunks)
        lines, parsed, corrupt = _split_lines(raw)
        out, stats = reprice_rows([row for _, row in parsed], config, now_iso)
        receipt: Dict[str, Any] = {
            "ts": now_iso,
            "ledger": ledger_path,
            "backup": None,
            "dry_run": dry_run,
            **stats,
            "corrupt_lines_preserved": corrupt,
            "sha256_before": _sha256_bytes(raw),
            "sha256_after": _sha256_bytes(raw),
            "catalog": catalog_note or {},
            "writer": WRITER,
            "lock": "flock(LOCK_SH) on the ledger inode" if dry_run else "flock(LOCK_EX) on the ledger inode, in-place rewrite",
        }
        if dry_run:
            return receipt
        if stats["rows_repriced"]:
            # 1. durable byte copy of what was read, never through a symlink
            bfd, backup = _create_exclusive(f"{ledger_path}.pre-reprice-{stamp}", os.fstat(fd).st_mode & 0o7777)
            try:
                _write_all(bfd, raw)
                os.fsync(bfd)
            finally:
                os.close(bfd)
            receipt["backup"] = backup
            # 2. rewrite the SAME inode under the lock; untouched lines verbatim
            for (i, old), new in zip(parsed, out):
                if new is not old:
                    line = lines[i]
                    ending = b"\r\n" if line.endswith(b"\r\n") else (b"\n" if line.endswith(b"\n") else b"")
                    lines[i] = json.dumps(new, separators=(",", ":")).encode("utf-8") + ending
            data = b"".join(lines)
            os.lseek(fd, 0, os.SEEK_SET)
            os.ftruncate(fd, 0)
            _write_all(fd, data)
            os.fsync(fd)
            receipt["sha256_after"] = _sha256_bytes(data)
        receipt["receipt_path"] = write_receipt(receipt_dir, f"cost-ledger-reprice-{stamp}", receipt)
        return receipt
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)
