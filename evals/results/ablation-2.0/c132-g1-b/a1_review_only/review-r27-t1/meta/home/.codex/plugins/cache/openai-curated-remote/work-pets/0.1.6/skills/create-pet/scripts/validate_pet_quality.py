#!/usr/bin/env python3
"""Gate a ChatGPT pet on real image geometry and recorded visual QA evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import statistics
from itertools import pairwise
from pathlib import Path

from PIL import Image

CELL_WIDTH = 192
CELL_HEIGHT = 208
LOOK_LABELS = [
    "000",
    "022.5",
    "045",
    "067.5",
    "090",
    "112.5",
    "135",
    "157.5",
    "180",
    "202.5",
    "225",
    "247.5",
    "270",
    "292.5",
    "315",
    "337.5",
]
EXPECTED_DIRECTIONS = {
    "000": "up",
    "022.5": "up-right",
    "045": "up-right",
    "067.5": "up-right",
    "090": "right",
    "112.5": "down-right",
    "135": "down-right",
    "157.5": "down-right",
    "180": "down",
    "202.5": "down-left",
    "225": "down-left",
    "247.5": "down-left",
    "270": "left",
    "292.5": "up-left",
    "315": "up-left",
    "337.5": "up-left",
}
CARDINAL_LABELS = {"000", "090", "180", "270"}


def read_report(path: str, label: str, errors: list[str]) -> dict[str, object]:
    try:
        payload = json.loads(Path(path).expanduser().resolve().read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{label} report could not be read: {exc}")
        return {}
    if not isinstance(payload, dict):
        errors.append(f"{label} report must be a JSON object")
        return {}
    return payload


def cell_bbox(atlas: Image.Image, row: int, column: int) -> tuple[int, int, int, int] | None:
    left = column * CELL_WIDTH
    top = row * CELL_HEIGHT
    alpha = atlas.crop((left, top, left + CELL_WIDTH, top + CELL_HEIGHT)).getchannel("A")
    return alpha.point(lambda value: 255 if value > 16 else 0).getbbox()


def normalize_label(value: object) -> str:
    label = str(value).strip().removesuffix("°")
    aliases = {"0": "000", "22.5": "022.5", "45": "045", "67.5": "067.5", "90": "090"}
    return aliases.get(label, label)


def semantic_records(payload: dict[str, object]) -> dict[str, dict[str, object]]:
    records: object = payload
    for field in ("directions", "reviews", "verdicts", "semantics"):
        if field in payload:
            records = payload[field]
            break

    if isinstance(records, list):
        normalized = {}
        for record in records:
            if not isinstance(record, dict):
                continue
            label = normalize_label(
                record.get("label", record.get("direction", record.get("degree", "")))
            )
            normalized[label] = record
        return normalized

    if isinstance(records, dict):
        return {
            normalize_label(label): record
            for label, record in records.items()
            if isinstance(record, dict)
        }

    return {}


def inspect_semantics(payload: dict[str, object], errors: list[str], warnings: list[str]) -> None:
    records = semantic_records(payload)
    for label in LOOK_LABELS:
        record = records.get(label)
        if record is None:
            errors.append(f"look direction {label} has no recorded semantic review")
            continue

        verdict = str(record.get("verdict", "")).strip().lower()
        expected = str(record.get("expected", "")).strip().lower().replace("screen-", "")
        observed = str(record.get("observed", "")).strip()
        reason = str(record.get("reason", record.get("evidence", ""))).strip()
        if expected != EXPECTED_DIRECTIONS[label]:
            errors.append(
                f"look direction {label} expects {EXPECTED_DIRECTIONS[label]}, got {expected or 'missing'}"
            )
        if verdict not in {"pass", "warning"}:
            errors.append(f"look direction {label} has non-passing verdict {verdict or 'missing'}")
        elif label in CARDINAL_LABELS and verdict != "pass":
            errors.append(f"cardinal direction {label} must pass without ambiguity")
        elif verdict == "warning":
            warnings.append(f"look direction {label} accepted with a reviewed warning")
        if not observed:
            errors.append(f"look direction {label} has no observed visual evidence")
        if not reason:
            errors.append(f"look direction {label} has no concrete landmark evidence")


def inspect_jump(
    atlas: Image.Image,
    minimum_lift: int,
    maximum_landing_delta: int,
    errors: list[str],
) -> dict[str, object]:
    idle_bounds = [cell_bbox(atlas, 0, column) for column in range(6)]
    jump_bounds = [cell_bbox(atlas, 4, column) for column in range(5)]
    if any(bounds is None for bounds in [*idle_bounds, *jump_bounds]):
        errors.append("idle and jumping rows must contain every required pose")
        return {}

    idle_baseline = round(statistics.median(bounds[3] for bounds in idle_bounds if bounds))
    jump_baselines = [bounds[3] for bounds in jump_bounds if bounds]
    jump_ground = max(jump_baselines)
    airborne_lift = jump_ground - min(jump_baselines)
    landing_delta = abs(jump_baselines[-1] - idle_baseline)

    if airborne_lift < minimum_lift:
        errors.append(
            f"jumping never visibly leaves the ground: peak lift is {airborne_lift}px, "
            f"expected at least {minimum_lift}px"
        )
    if landing_delta > maximum_landing_delta:
        errors.append(
            f"jumping lands {landing_delta}px away from the idle baseline, "
            f"expected at most {maximum_landing_delta}px"
        )

    return {
        "idle_baseline": idle_baseline,
        "jump_baselines": jump_baselines,
        "airborne_lift_pixels": airborne_lift,
        "landing_delta_pixels": landing_delta,
    }


def inspect_look_registration(
    atlas: Image.Image,
    continuity: dict[str, object],
    maximum_center_drift: float,
    maximum_width_ratio: float,
    errors: list[str],
    warnings: list[str],
) -> dict[str, object]:
    neutral = cell_bbox(atlas, 0, 0)
    if neutral is None:
        errors.append("the idle neutral frame is empty")
        return {}

    neutral_center = (neutral[0] + neutral[2]) / 2
    bounds = [cell_bbox(atlas, 9 + index // 8, index % 8) for index in range(16)]
    if any(item is None for item in bounds):
        errors.append("every look direction must contain a visible pose")
        return {}

    centers = [(item[0] + item[2]) / 2 for item in bounds if item]
    widths = [item[2] - item[0] for item in bounds if item]
    maximum_drift = max(abs(center - neutral_center) for center in centers)
    width_ratio = max(widths) / max(1, min(widths))
    if maximum_drift > maximum_center_drift:
        errors.append(
            f"look directions drift {maximum_drift:.1f}px from idle registration, "
            f"expected at most {maximum_center_drift:.1f}px"
        )
    if width_ratio > maximum_width_ratio:
        errors.append(
            f"look-direction silhouettes change width by {width_ratio:.2f}x, "
            f"expected at most {maximum_width_ratio:.2f}x"
        )

    material_hole_labels = []
    for item in continuity.get("alphaHoles", []):
        if not isinstance(item, dict):
            continue
        label = normalize_label(item.get("direction", ""))
        if label not in LOOK_LABELS:
            continue
        bounds_for_direction = bounds[LOOK_LABELS.index(label)]
        if bounds_for_direction is None:
            continue
        top, bottom = bounds_for_direction[1], bounds_for_direction[3]
        body_height = bottom - top
        material_rows = []
        for hole in item.get("holes", []):
            if not isinstance(hole, dict):
                continue
            y = hole.get("row")
            transparent = hole.get("transparentPixels")
            span = hole.get("spanPixels")
            if not all(isinstance(value, int) for value in (y, transparent, span)):
                continue
            if y < top + body_height * 0.12 or y > top + body_height * 0.78:
                continue
            if transparent / max(1, span) >= 0.35:
                material_rows.append(y)

        adjacent_rows = any(second - first <= 1 for first, second in pairwise(material_rows))
        if adjacent_rows:
            material_hole_labels.append(label)

    if material_hole_labels:
        labels = ", ".join(material_hole_labels)
        errors.append(f"look directions contain transparent interior holes or seam bands: {labels}")

    for pair in continuity.get("pairs", []):
        if not isinstance(pair, dict):
            continue
        center_delta = pair.get("centerDelta")
        area_ratio = pair.get("areaRatio")
        label = f"{pair.get('from', '?')}->{pair.get('to', '?')}"
        if isinstance(center_delta, (int, float)) and center_delta > maximum_center_drift:
            errors.append(f"adjacent look directions {label} jump {center_delta:.1f}px")
        if isinstance(area_ratio, (int, float)) and area_ratio > maximum_width_ratio:
            errors.append(
                f"adjacent look directions {label} change visible area by {area_ratio:.2f}x"
            )

    for warning in continuity.get("warnings", []):
        warnings.append(str(warning))

    return {
        "neutral_center_x": neutral_center,
        "look_centers_x": centers,
        "look_widths": widths,
        "maximum_center_drift_pixels": maximum_drift,
        "maximum_width_ratio": width_ratio,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("atlas")
    parser.add_argument("--atlas-validation", required=True)
    parser.add_argument("--chroma-report", required=True)
    parser.add_argument("--frame-review", required=True)
    parser.add_argument("--direction-semantics", required=True)
    parser.add_argument("--continuity", required=True)
    parser.add_argument("--json-out", required=True)
    parser.add_argument("--minimum-jump-lift", type=int, default=8)
    parser.add_argument("--maximum-landing-delta", type=int, default=12)
    parser.add_argument("--maximum-look-center-drift", type=float, default=26)
    parser.add_argument("--maximum-look-width-ratio", type=float, default=1.5)
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    atlas_path = Path(args.atlas).expanduser().resolve()
    atlas_validation = read_report(args.atlas_validation, "atlas validation", errors)
    chroma = read_report(args.chroma_report, "chroma cleanup", errors)
    frame_review = read_report(args.frame_review, "standard-frame review", errors)
    semantics = read_report(args.direction_semantics, "direction semantics", errors)
    continuity = read_report(args.continuity, "direction continuity", errors)

    for label, report in (
        ("atlas validation", atlas_validation),
        ("chroma cleanup", chroma),
        ("standard-frame review", frame_review),
        ("direction continuity", continuity),
    ):
        if report.get("ok") is not True:
            errors.append(f"{label} report did not pass")

    try:
        image_bytes = atlas_path.read_bytes()
        with Image.open(atlas_path) as opened:
            atlas = opened.convert("RGBA")
    except OSError as exc:
        errors.append(f"final atlas could not be opened: {exc}")
        atlas = Image.new("RGBA", (CELL_WIDTH * 8, CELL_HEIGHT * 11))
        image_bytes = b""

    digest = hashlib.sha256(image_bytes).hexdigest()
    if atlas_validation.get("sha256") != digest:
        errors.append("final atlas bytes differ from the bytes that passed structural validation")
    if atlas_validation.get("encoded_bytes") != len(image_bytes):
        errors.append("final atlas byte length differs from the structural-validation report")
    if Path(str(atlas_validation.get("file", ""))).expanduser().resolve() != atlas_path:
        errors.append("the validated atlas path does not match the final upload artifact")
    if atlas.size != (CELL_WIDTH * 8, CELL_HEIGHT * 11):
        errors.append(f"final atlas must be 1536x2288, got {atlas.width}x{atlas.height}")

    inspect_semantics(semantics, errors, warnings)
    jump = inspect_jump(atlas, args.minimum_jump_lift, args.maximum_landing_delta, errors)
    look_registration = inspect_look_registration(
        atlas,
        continuity,
        args.maximum_look_center_drift,
        args.maximum_look_width_ratio,
        errors,
        warnings,
    )

    result = {
        "ok": not errors,
        "atlas": str(atlas_path),
        "encoded_bytes": len(image_bytes),
        "sha256": digest,
        "jump": jump,
        "look_registration": look_registration,
        "errors": errors,
        "warnings": warnings,
    }
    output = Path(args.json_out).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["ok"] else 1)


if __name__ == "__main__":
    main()
