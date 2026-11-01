#!/usr/bin/env python3
"""把角色骑宠 tpsheet 规范化为 frameid、内联 offset 和单帧单行格式."""

from __future__ import annotations

import argparse
import json
import os
import re
import uuid
from pathlib import Path
from typing import Any


OFFSET_PATTERN = re.compile(
    r"^\s*(\d+)\s*:\s*\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]\s*$"
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
            raise ValueError(f"offset.yaml 格式非法: line:{line_number}")
        frame_id = int(match.group(1))
        if frame_id in offsets:
            raise ValueError(f"offset.yaml 帧 ID 重复: {frame_id}")
        offsets[frame_id] = [int(match.group(2)), int(match.group(3))]
    return offsets


def parse_frame_id(sprite: dict[str, Any]) -> int:
    value = sprite.get("frameid", sprite.get("filename"))
    if isinstance(value, bool):
        raise ValueError(f"帧 ID 非法: {value}")
    try:
        frame_id = int(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"帧 ID 非法: {value}") from error
    if str(value) != str(frame_id):
        raise ValueError(f"帧 ID 必须是整数: {value}")
    if frame_id <= 0:
        raise ValueError(f"帧 ID 必须大于0: {frame_id}")
    return frame_id


def normalize(
    sheet_path: Path,
    texture_file_name: str,
    source_directory: Path,
    offset_path: Path,
) -> None:
    sheet = json.loads(sheet_path.read_text(encoding="utf-8-sig"))
    textures = sheet.get("textures")
    if not isinstance(textures, list) or len(textures) != 1:
        raise ValueError("tpsheet 必须只有一个 texture")
    texture = textures[0]
    if not isinstance(texture, dict):
        raise ValueError("tpsheet texture 必须是对象")
    sprites = texture.get("sprites")
    if not isinstance(sprites, list) or not sprites:
        raise ValueError("tpsheet sprites 必须是非空数组")

    source_frame_ids = {
        int(path.stem)
        for path in source_directory.iterdir()
        if path.is_file() and path.suffix.lower() == ".png"
    }
    offsets = load_offsets(offset_path)
    normalized_sprites: list[dict[str, Any]] = []
    seen_frame_ids: set[int] = set()
    for raw_sprite in sprites:
        if not isinstance(raw_sprite, dict):
            raise ValueError("tpsheet sprite 必须是对象")
        frame_id = parse_frame_id(raw_sprite)
        if frame_id in seen_frame_ids:
            raise ValueError(f"tpsheet 帧 ID 重复: {frame_id}")
        if frame_id not in offsets:
            raise ValueError(f"offset.yaml 缺少帧 ID: {frame_id}")
        region = raw_sprite.get("region")
        margin = raw_sprite.get("margin")
        if not isinstance(region, dict) or not isinstance(margin, dict):
            raise ValueError(f"tpsheet region 或 margin 非法: {frame_id}")
        normalized_sprites.append(
            {
                "frameid": frame_id,
                "region": region,
                "margin": margin,
                "offset": offsets[frame_id],
            }
        )
        seen_frame_ids.add(frame_id)

    if seen_frame_ids != source_frame_ids:
        missing = sorted(source_frame_ids - seen_frame_ids)
        extra = sorted(seen_frame_ids - source_frame_ids)
        raise ValueError(f"tpsheet 与源图片帧号不一致: missing:{missing} extra:{extra}")

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
        raise ValueError("无法定位 sprites 格式化占位符")
    formatted = formatted.replace(placeholder, replacement, 1) + "\n"

    temporary_path = sheet_path.with_name(sheet_path.name + ".tmp." + uuid.uuid4().hex)
    try:
        temporary_path.write_text(formatted, encoding="utf-8", newline="\n")
        os.replace(temporary_path, sheet_path)
    finally:
        if temporary_path.exists():
            temporary_path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sheet", required=True, type=Path)
    parser.add_argument("--texture-file-name", required=True)
    parser.add_argument("--source-directory", required=True, type=Path)
    parser.add_argument("--offset-config", required=True, type=Path)
    args = parser.parse_args()
    normalize(
        args.sheet,
        args.texture_file_name,
        args.source_directory,
        args.offset_config,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
