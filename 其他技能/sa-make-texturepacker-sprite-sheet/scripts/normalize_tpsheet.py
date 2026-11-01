#!/usr/bin/env python3
"""Normalize a TexturePacker Godot 3 sheet with frame IDs and offsets."""

from __future__ import annotations

import argparse
import json
import os
import re
import tempfile
import uuid
from pathlib import Path
from typing import Any


OFFSET_PATTERN = re.compile(
    r"^\s*(\d+)\s*:\s*\[\s*([+-]?\d+)\s*,\s*([+-]?\d+)\s*,\s*([+-]?\d+)\s*,\s*([+-]?\d+)\s*\]\s*$"
)
SPRITES_PLACEHOLDER = "__SPRITES_PLACEHOLDER__"


def load_offsets(path: Path) -> dict[int, list[int]]:
    offsets: dict[int, list[int]] = {}
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8-sig").splitlines(), start=1
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = OFFSET_PATTERN.fullmatch(raw_line)
        if match is None:
            raise ValueError(f"offset.yaml format is invalid at line {line_number}")
        frame_id = int(match.group(1))
        if frame_id <= 0:
            raise ValueError(f"frame ID must be positive at line {line_number}")
        if frame_id in offsets:
            raise ValueError(f"duplicate frame ID in offset.yaml: {frame_id}")
        offsets[frame_id] = [int(match.group(2)), int(match.group(3))]
    return offsets


def parse_frame_id(value: Any) -> int:
    if isinstance(value, bool):
        raise ValueError(f"invalid frame ID: {value}")
    try:
        frame_id = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"invalid frame ID: {value}") from error
    if frame_id <= 0 or str(value) != str(frame_id):
        raise ValueError(f"frame ID must be a canonical positive integer: {value}")
    return frame_id


def normalize(
    sheet_path: Path,
    texture_file_name: str,
    expected_frame_ids: set[int],
    offset_path: Path,
) -> None:
    sheet = json.loads(sheet_path.read_text(encoding="utf-8-sig"))
    textures = sheet.get("textures")
    if not isinstance(textures, list) or len(textures) != 1:
        raise ValueError("tpsheet must contain exactly one texture")
    texture = textures[0]
    if not isinstance(texture, dict):
        raise ValueError("tpsheet texture must be an object")
    sprites = texture.get("sprites")
    if not isinstance(sprites, list) or not sprites:
        raise ValueError("tpsheet sprites must be a non-empty array")

    offsets = load_offsets(offset_path)
    normalized_sprites: list[dict[str, Any]] = []
    seen_frame_ids: set[int] = set()
    for raw_sprite in sprites:
        if not isinstance(raw_sprite, dict):
            raise ValueError("tpsheet sprite must be an object")
        frame_id = parse_frame_id(raw_sprite.get("frameid", raw_sprite.get("filename")))
        if frame_id in seen_frame_ids:
            raise ValueError(f"duplicate frame ID in tpsheet: {frame_id}")
        if frame_id not in offsets:
            raise ValueError(f"offset.yaml is missing frame ID: {frame_id}")
        region = raw_sprite.get("region")
        margin = raw_sprite.get("margin")
        if not isinstance(region, dict) or not isinstance(margin, dict):
            raise ValueError(f"invalid region or margin for frame ID: {frame_id}")
        normalized_sprites.append(
            {
                "frameid": frame_id,
                "region": region,
                "margin": margin,
                "offset": offsets[frame_id],
            }
        )
        seen_frame_ids.add(frame_id)

    if seen_frame_ids != expected_frame_ids:
        missing = sorted(expected_frame_ids - seen_frame_ids)
        extra = sorted(seen_frame_ids - expected_frame_ids)
        raise ValueError(f"tpsheet frame IDs differ: missing={missing}, extra={extra}")

    texture["image"] = texture_file_name
    texture["sprites"] = [SPRITES_PLACEHOLDER]
    formatted = json.dumps(sheet, ensure_ascii=False, indent="\t")
    placeholder = '\t\t\t"sprites": [\n\t\t\t\t"' + SPRITES_PLACEHOLDER + '"\n\t\t\t]'
    sprite_lines = []
    for index, sprite in enumerate(normalized_sprites):
        suffix = "," if index + 1 < len(normalized_sprites) else ""
        sprite_lines.append(
            "\t\t\t\t"
            + json.dumps(sprite, ensure_ascii=False, separators=(", ", ": "))
            + suffix
        )
    replacement = '\t\t\t"sprites": [\n' + "\n".join(sprite_lines) + '\n\t\t\t]'
    if formatted.count(placeholder) != 1:
        raise ValueError("could not locate sprites formatting placeholder")
    formatted = formatted.replace(placeholder, replacement, 1) + "\n"

    temporary_path = sheet_path.with_name(sheet_path.name + ".tmp." + uuid.uuid4().hex)
    try:
        temporary_path.write_text(formatted, encoding="utf-8", newline="\n")
        os.replace(temporary_path, sheet_path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def run_self_test() -> None:
    with tempfile.TemporaryDirectory(prefix="sa-tpsheet-normalize-") as directory:
        root = Path(directory)
        sheet_path = root / "sample.tpsheet"
        offset_path = root / "offset.yaml"
        sheet_path.write_text(
            json.dumps(
                {
                    "textures": [
                        {
                            "image": "old.png",
                            "size": {"w": 4, "h": 4},
                            "sprites": [
                                {
                                    "filename": "101",
                                    "region": {"x": 0, "y": 0, "w": 2, "h": 2},
                                    "margin": {"x": 0, "y": 0, "w": 0, "h": 0},
                                },
                                {
                                    "filename": "202",
                                    "region": {"x": 2, "y": 0, "w": 2, "h": 2},
                                    "margin": {"x": 0, "y": 0, "w": 0, "h": 0},
                                },
                            ],
                        }
                    ]
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        offset_path.write_text(
            "101: [-1,-2,2,2]\n202: [3,4,2,2]\n",
            encoding="utf-8",
        )
        normalize(sheet_path, "sample.png", {101, 202}, offset_path)
        content = sheet_path.read_text(encoding="utf-8")
        result = json.loads(content)
        assert result["textures"][0]["image"] == "sample.png"
        assert [row["frameid"] for row in result["textures"][0]["sprites"]] == [101, 202]
        assert result["textures"][0]["sprites"][0]["offset"] == [-1, -2]
        assert len(re.findall(r'^\s*\{[^\r\n]*"frameid"[^\r\n]*"offset"[^\r\n]*\},?\s*$', content, re.MULTILINE)) == 2
    print("normalize_tpsheet self-test passed.")


def parse_frame_ids(raw_value: str) -> set[int]:
    values = raw_value.split(",")
    frame_ids = {parse_frame_id(value.strip()) for value in values if value.strip()}
    if not frame_ids or len(frame_ids) != len(values):
        raise ValueError("frame IDs must be non-empty and unique")
    return frame_ids


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheet", type=Path)
    parser.add_argument("--texture-file-name")
    parser.add_argument("--frame-ids")
    parser.add_argument("--offset-config", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()
        return 0
    if not all((args.sheet, args.texture_file_name, args.frame_ids, args.offset_config)):
        parser.error("publish mode requires --sheet, --texture-file-name, --frame-ids and --offset-config")
    normalize(
        args.sheet,
        args.texture_file_name,
        parse_frame_ids(args.frame_ids),
        args.offset_config,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
