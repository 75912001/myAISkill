#!/usr/bin/env python3
"""只读生成角色骑宠 TexturePacker 发布计划."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import yaml


COLOR_MAP = {
    "红": "red",
    "蓝": "blue",
    "橙": "orange",
    "棕": "brown",
    "黑": "black",
    "黄": "yellow",
    "绿": "green",
    "粉": "pink",
    "白": "white",
}

MOUNT_FAMILY_MAP = {
    "虎": "老虎系",
    "雷龙": "雷龙系",
}

SHARED_MOUNT_NAMES = {
    "左迪洛斯",
    "巴朵兰恩",
    "帖拉所伊朵",
    "玛恩摩洛斯",
    "朵拉比斯",
    "拉奇鲁哥",
    "扬奇洛斯",
    "卡达鲁卡斯",
    "卡卡金宝",
    "格尔格",
}


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as stream:
        value = yaml.safe_load(stream)
    if not isinstance(value, dict):
        raise ValueError(f"YAML 顶层必须是对象: {path}")
    return value


def require_unique(values: list[Any], message: str) -> Any:
    if len(values) != 1:
        raise ValueError(f"{message}, 实际匹配 {len(values)} 个")
    return values[0]


def build_pet_index(pet_config: dict[str, Any]) -> dict[int, dict[str, Any]]:
    groups = pet_config.get("pet")
    if not isinstance(groups, dict):
        raise ValueError("pet.yaml 缺少 pet 对象")

    pets: dict[int, dict[str, Any]] = {}
    for family_name, entries in groups.items():
        if not isinstance(entries, list):
            raise ValueError(f"pet.{family_name} 必须是数组")
        for entry in entries:
            pet_id = int(entry["id"])
            if pet_id in pets:
                raise ValueError(f"pet.yaml 宠物 ID 重复: {pet_id}")
            pets[pet_id] = {
                "name": str(entry["name"]),
                "family_name": str(family_name),
            }
    return pets


def make_specific_item(
    source_directory: Path,
    role_name: str,
    mount_directory_name: str,
    character: dict[str, Any],
    mount: dict[str, Any],
    pets: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    character_id = int(character["id"])
    pet_id = int(mount["petId"])
    sprite_id = int(mount["spriteId"])
    if pet_id not in pets:
        raise ValueError(f"mounts.petId 未在 pet.yaml 定义: {pet_id}")
    pet_name = pets[pet_id]["name"]
    output_base = f"{role_name}.{character_id}.{pet_name}.{pet_id}"
    if output_base.count(".") != 3:
        raise ValueError(f"输出基名必须恰好包含四段: {output_base}")
    return {
        "source_directory": str(source_directory.resolve()),
        "role_name": role_name,
        "mount_directory_name": mount_directory_name,
        "character_id": character_id,
        "mount_sprite_id": sprite_id,
        "pet_name": pet_name,
        "pet_id": pet_id,
        "output_base": output_base,
        "shared": False,
    }


def make_shared_item(
    source_directory: Path,
    role_name: str,
    mount_directory_name: str,
    mounts: list[dict[str, Any]],
    pets: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    pet_ids = {int(mount["petId"]) for mount in mounts}
    sprite_ids = {int(mount["spriteId"]) for mount in mounts}
    if len(pet_ids) != 1 or len(sprite_ids) != 1:
        raise ValueError(
            "共用骑宠的 petId 和 spriteId 必须在同名角色中完全一致: "
            f"{role_name}/{mount_directory_name}"
        )
    pet_id = next(iter(pet_ids))
    sprite_id = next(iter(sprite_ids))
    if pet_id not in pets:
        raise ValueError(f"mounts.petId 未在 pet.yaml 定义: {pet_id}")
    pet_name = pets[pet_id]["name"]
    if pet_name not in SHARED_MOUNT_NAMES:
        raise ValueError(f"无颜色目录不在共用骑宠白名单: {role_name}/{pet_name}")
    output_base = f"{role_name}.{pet_name}.{pet_id}"
    if output_base.count(".") != 2:
        raise ValueError(f"共用输出基名必须恰好包含三段: {output_base}")
    return {
        "source_directory": str(source_directory.resolve()),
        "role_name": role_name,
        "mount_directory_name": mount_directory_name,
        "character_id": 0,
        "mount_sprite_id": sprite_id,
        "pet_name": pet_name,
        "pet_id": pet_id,
        "output_base": output_base,
        "shared": True,
    }


def build_plan(
    role_pet_root: Path,
    character_config_path: Path,
    pet_config_path: Path,
    role_name_filter: str | None,
    mount_directory_filter: str | None,
) -> dict[str, Any]:
    if not role_pet_root.is_dir():
        raise ValueError(f"角色骑宠源根目录不存在: {role_pet_root}")

    character_config = load_yaml(character_config_path)
    characters = character_config.get("character")
    if not isinstance(characters, list):
        raise ValueError("character.yaml 缺少 character 数组")
    role_characters = [entry for entry in characters if entry.get("isRole") is True]
    pets = build_pet_index(load_yaml(pet_config_path))

    items: list[dict[str, Any]] = []
    source_directories: set[str] = set()
    role_directories = sorted(path for path in role_pet_root.iterdir() if path.is_dir())
    for role_directory in role_directories:
        role_name = role_directory.name
        if role_name_filter and role_name != role_name_filter:
            continue
        matching_characters = sorted(
            [entry for entry in role_characters if entry.get("name") == role_name],
            key=lambda entry: int(entry["id"]),
        )
        if not matching_characters:
            raise ValueError(f"character.yaml 未找到角色: {role_name}")

        mount_directories = sorted(path for path in role_directory.iterdir() if path.is_dir())
        for mount_directory in mount_directories:
            directory_name = mount_directory.name
            if mount_directory_filter and directory_name != mount_directory_filter:
                continue
            source_directories.add(str(mount_directory.resolve()))

            if "." in directory_name:
                color_name, mount_kind = directory_name.split(".", 1)
                color = COLOR_MAP.get(color_name)
                family_name = MOUNT_FAMILY_MAP.get(mount_kind)
                if color is None:
                    raise ValueError(f"未知中文颜色: {role_name}/{directory_name}")
                if family_name is None:
                    raise ValueError(f"未知颜色骑宠类别: {role_name}/{directory_name}")
                character = require_unique(
                    [entry for entry in matching_characters if entry.get("color") == color],
                    f"角色颜色无法唯一映射: {role_name}/{directory_name}",
                )
                mount = require_unique(
                    [
                        entry
                        for entry in character.get("mounts", [])
                        if pets.get(int(entry["petId"]), {}).get("family_name")
                        == family_name
                    ],
                    f"颜色骑宠无法唯一映射: {role_name}/{directory_name}",
                )
                items.append(
                    make_specific_item(
                        mount_directory,
                        role_name,
                        directory_name,
                        character,
                        mount,
                        pets,
                    )
                )
                continue

            mounts = []
            for character in matching_characters:
                mounts.append(require_unique(
                    [
                        entry
                        for entry in character.get("mounts", [])
                        if pets.get(int(entry["petId"]), {}).get("name")
                        == directory_name
                    ],
                    (
                        "骑宠名称无法在角色配置中唯一映射: "
                        f"{role_name}/{directory_name}, character:{character['id']}"
                    ),
                ))
            items.append(
                make_shared_item(
                    mount_directory,
                    role_name,
                    directory_name,
                    mounts,
                    pets,
                )
            )

    output_bases = [item["output_base"] for item in items]
    duplicate_bases = sorted(
        {value for value in output_bases if output_bases.count(value) > 1}
    )
    if duplicate_bases:
        raise ValueError(f"输出基名重复: {', '.join(duplicate_bases)}")

    return {
        "source_directory_count": len(source_directories),
        "output_group_count": len(items),
        "items": items,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role-pet-root", required=True, type=Path)
    parser.add_argument("--character-config", required=True, type=Path)
    parser.add_argument("--pet-config", required=True, type=Path)
    parser.add_argument("--role-name")
    parser.add_argument("--mount-directory-name")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plan = build_plan(
        args.role_pet_root,
        args.character_config,
        args.pet_config,
        args.role_name,
        args.mount_directory_name,
    )
    print(json.dumps(plan, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
