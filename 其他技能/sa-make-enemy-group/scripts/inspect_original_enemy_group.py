#!/usr/bin/env python3
"""只读检索 SA 8.0 原版敌人组、敌人和成长模板."""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


GROUP_INT_FIELDS = (
    "groupId", "appearByItemId", "notAppearByItemId",
    *(f"enemy{i}" for i in range(1, 11)),
    *(f"probability{i}" for i in range(1, 11)),
)
ENEMY_INT_FIELDS = (
    "enemyId", "templateId", "levelMin", "levelMax", "createMaxNum", "createMinNum",
    "tactics", "exp", "duelPoint", "style", "petFlag",
    *(f"item{i}" for i in range(1, 11)),
    *(f"itemProbability{i}" for i in range(1, 11)),
)
TEMPLATE_CHAR_FIELDS = ("name", "atomName1", "atomName2", "atomName3", "atomName4", "atomName5")
TEMPLATE_INT_FIELDS = (
    "templateId", "initialNumber", "levelUpPoint", "baseVitality", "baseStrength",
    "baseToughness", "baseDexterity", "modAI", "captureRate", "earth", "water", "fire",
    "wind", "poisonResistance", "paralysisResistance", "sleepResistance", "stoneResistance",
    "drunkResistance", "confusionResistance", "skill1", "skill2", "skill3", "skill4",
    "skill5", "skill6", "skill7", "rare", "critical", "counter", "slot", "imageNumber",
    "petFlag", "size", "atomBaseAdd1", "atomFixMin1", "atomFixMax1", "atomBaseAdd2",
    "atomFixMin2", "atomFixMax2", "atomBaseAdd3", "atomFixMin3", "atomFixMax3",
    "atomBaseAdd4", "atomFixMin4", "atomFixMax4", "atomBaseAdd5", "atomFixMin5",
    "atomFixMax5", "limitLevel", "fusionCode",
)


class InspectionError(Exception):
    """输入或原版数据无法可靠解析."""


def decode_original(raw: bytes) -> tuple[str, str]:
    if raw.startswith(b"\xef\xbb\xbf"):
        return raw.decode("utf-8-sig"), "utf-8-sig"
    candidates: list[tuple[int, str, str]] = []
    for encoding in ("utf-8", "gb18030", "cp950"):
        try:
            text = raw.decode(encoding)
        except UnicodeDecodeError:
            continue
        score = -(text.count("\ufffd") * 1000)
        score -= sum(0xE000 <= ord(char) <= 0xF8FF for char in text) * 100
        score -= sum(ord(char) < 32 and char not in "\r\n\t" for char in text) * 100
        candidates.append((score, text, encoding))
    if not candidates:
        return raw.decode("gb18030", errors="replace"), "gb18030-replace"
    _, text, encoding = max(candidates, key=lambda item: item[0])
    return text, encoding


def read_rows(path: Path) -> tuple[list[tuple[int, list[str]]], str]:
    text, encoding = decode_original(path.read_bytes())
    reader = csv.reader(io.StringIO(text))
    rows: list[tuple[int, list[str]]] = []
    for fields in reader:
        line_number = reader.line_num
        values = [value.strip() for value in fields]
        if not values or not any(values) or values[0].lstrip().startswith("#"):
            continue
        rows.append((line_number, values))
    return rows, encoding


def parse_number(value: str | None) -> int | float | None:
    if value is None or not value.strip():
        return None
    raw = value.strip()
    if re.fullmatch(r"[+-]?\d+", raw):
        return int(raw)
    if re.fullmatch(r"[+-]?(?:\d+\.\d*|\d*\.\d+)", raw):
        return float(raw)
    return None


def named_values(raw: list[str], names: Iterable[str]) -> tuple[dict[str, int | float | None], dict[str, str]]:
    name_list = list(names)
    padded = raw + [""] * max(0, len(name_list) - len(raw))
    return (
        {name: parse_number(padded[index]) for index, name in enumerate(name_list)},
        {name: padded[index] for index, name in enumerate(name_list)},
    )


def first_index(records: list[dict[str, Any]], key: str) -> tuple[dict[int, dict[str, Any]], dict[int, list[int]]]:
    result: dict[int, dict[str, Any]] = {}
    duplicates: dict[int, list[int]] = {}
    for record in records:
        record_id = record.get(key)
        if not isinstance(record_id, int):
            continue
        if record_id in result:
            duplicates.setdefault(record_id, [result[record_id]["sourceLine"]]).append(record["sourceLine"])
            continue
        result[record_id] = record
    return result, duplicates


def parse_groups(path: Path) -> tuple[list[dict[str, Any]], str]:
    rows, encoding = read_rows(path)
    records: list[dict[str, Any]] = []
    for line_number, fields in rows:
        values, raw_values = named_values(fields[1:], GROUP_INT_FIELDS)
        members = []
        for index in range(1, 11):
            enemy_id = values[f"enemy{index}"]
            if not isinstance(enemy_id, int) or enemy_id <= 0:
                continue
            members.append({"slot": index, "enemyId": enemy_id, "weight": values[f"probability{index}"]})
        records.append({
            "sourceLine": line_number, "name": fields[0] or None, "groupId": values["groupId"],
            "appearByItemId": values["appearByItemId"], "notAppearByItemId": values["notAppearByItemId"],
            "members": members, "rawValues": raw_values, "rawFields": fields,
        })
    return records, encoding


def parse_tactics(value: str | None) -> dict[str, list[int]]:
    result: dict[str, list[int]] = {}
    if not value:
        return result
    for segment in value.split("|"):
        if ":" not in segment:
            continue
        key, raw_values = segment.split(":", 1)
        key = key.strip().lower()
        if key:
            result[key] = [int(part) for part in re.findall(r"[+-]?\d+", raw_values)]
    return result


def parse_enemies(path: Path) -> tuple[list[dict[str, Any]], str]:
    rows, encoding = read_rows(path)
    records: list[dict[str, Any]] = []
    for line_number, fields in rows:
        chars = (fields + ["", "", ""])[0:3]
        values, raw_values = named_values(fields[3:], ENEMY_INT_FIELDS)
        drops = []
        for index in range(1, 11):
            item_id = values[f"item{index}"]
            if isinstance(item_id, int) and item_id > 0:
                drops.append({
                    "slot": index, "originalItemId": item_id,
                    "probabilityPerThousand": values[f"itemProbability{index}"],
                })
        records.append({
            "sourceLine": line_number, "name": chars[0] or None, "tacticsOption": chars[1] or None,
            "parsedTactics": parse_tactics(chars[1]), "actCondition": chars[2] or None,
            **values, "drops": drops, "rawValues": raw_values, "rawFields": fields,
        })
    return records, encoding


def parse_templates(path: Path) -> tuple[list[dict[str, Any]], str]:
    rows, encoding = read_rows(path)
    records: list[dict[str, Any]] = []
    for line_number, fields in rows:
        chars = (fields + [""] * len(TEMPLATE_CHAR_FIELDS))[: len(TEMPLATE_CHAR_FIELDS)]
        values, raw_values = named_values(fields[len(TEMPLATE_CHAR_FIELDS):], TEMPLATE_INT_FIELDS)
        records.append({
            "sourceLine": line_number, "name": chars[0] or None,
            "atomNames": [name for name in chars[1:] if name], **values,
            "skills": [values[f"skill{index}"] for index in range(1, 8)],
            "growthAttribute": {
                "elemental": {key: values[key] for key in ("earth", "water", "fire", "wind") if values[key] not in (None, 0)},
                "attribute": {
                    "poisonResist": values["poisonResistance"], "paralysisResist": values["paralysisResistance"],
                    "sleepResist": values["sleepResistance"], "stoneResist": values["stoneResistance"],
                    "drunkResist": values["drunkResistance"], "confusionResist": values["confusionResistance"],
                    "critical": values["critical"], "counter": values["counter"],
                    "rate": values["rare"], "get": values["captureRate"],
                },
                "growth": {
                    "initNum": values["initialNumber"], "lvupPointSource": values["levelUpPoint"],
                    "baseVital": values["baseVitality"], "baseStr": values["baseStrength"],
                    "baseTough": values["baseToughness"], "baseDex": values["baseDexterity"],
                },
            },
            "rawValues": raw_values, "rawFields": fields,
        })
    return records, encoding


def read_setup(setup_path: Path) -> dict[str, str]:
    text, _ = decode_original(setup_path.read_bytes())
    result: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key.strip().casefold()] = value.strip()
    return result


def resolve_configured_file(gmsv_root: Path, setup: dict[str, str], key: str, fallbacks: tuple[str, ...]) -> Path:
    configured = setup.get(key.casefold())
    if configured:
        candidate = (gmsv_root / configured.replace("\\", "/")).resolve()
        if candidate.is_file():
            return candidate
    for fallback in fallbacks:
        candidate = gmsv_root / "data" / fallback
        if candidate.is_file():
            return candidate.resolve()
    raise InspectionError(f"未找到 {key}: {', '.join(fallbacks)}")


def compact_enemy(enemy: dict[str, Any], template: dict[str, Any] | None) -> dict[str, Any]:
    return {
        "enemyId": enemy.get("enemyId"), "name": enemy.get("name"), "sourceLine": enemy.get("sourceLine"),
        "templateId": enemy.get("templateId"), "templateName": template.get("name") if template else None,
        "templateSourceLine": template.get("sourceLine") if template else None,
        "levelMin": enemy.get("levelMin"), "levelMax": enemy.get("levelMax"),
        "createMinNum": enemy.get("createMinNum"), "createMaxNum": enemy.get("createMaxNum"),
        "tactics": enemy.get("tactics"), "tacticsOption": enemy.get("tacticsOption"),
        "parsedTactics": enemy.get("parsedTactics"),
    }


def inspect(args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    client_root = Path(args.client_root).expanduser().resolve()
    gmsv_root = client_root / "gmsv"
    setup_path = gmsv_root / "setup.cf"
    if not setup_path.is_file():
        raise InspectionError(f"缺少原版 setup.cf: {setup_path}")
    setup = read_setup(setup_path)
    group_path = resolve_configured_file(gmsv_root, setup, "groupfile", ("group1.txt", "group.txt"))
    enemy_path = resolve_configured_file(gmsv_root, setup, "enemyfile", ("enemy1.txt", "enemy.txt"))
    template_path = resolve_configured_file(gmsv_root, setup, "enemybasefile", ("enemybase1.txt", "enemybase.txt"))

    groups, group_encoding = parse_groups(group_path)
    enemies, enemy_encoding = parse_enemies(enemy_path)
    templates, template_encoding = parse_templates(template_path)
    group_by_id, duplicate_groups = first_index(groups, "groupId")
    enemy_by_id, duplicate_enemies = first_index(enemies, "enemyId")
    template_by_id, duplicate_templates = first_index(templates, "templateId")
    result: dict[str, Any] = {
        "sources": {
            "setup": str(setup_path), "group": {"path": str(group_path), "encoding": group_encoding},
            "enemy": {"path": str(enemy_path), "encoding": enemy_encoding},
            "template": {"path": str(template_path), "encoding": template_encoding},
        },
        "anomalies": {
            "duplicateGroupIds": duplicate_groups, "duplicateEnemyIds": duplicate_enemies,
            "duplicateTemplateIds": duplicate_templates, "missingEnemyReferences": [], "missingTemplates": [],
        },
        "query": args.query, "candidateGroups": [], "candidateEnemies": [],
        "selectedGroups": [], "selectedEnemies": [], "errors": [],
    }

    def template_for(enemy: dict[str, Any]) -> dict[str, Any] | None:
        template_id = enemy.get("templateId")
        template = template_by_id.get(template_id) if isinstance(template_id, int) else None
        if template is None and isinstance(template_id, int):
            missing = {"enemyId": enemy.get("enemyId"), "templateId": template_id}
            if missing not in result["anomalies"]["missingTemplates"]:
                result["anomalies"]["missingTemplates"].append(missing)
        return template

    if args.query:
        query = args.query.casefold().strip()
        for group in groups:
            if query in str(group.get("groupId", "")).casefold() or query in str(group.get("name") or "").casefold():
                result["candidateGroups"].append({
                    "groupId": group.get("groupId"), "name": group.get("name"),
                    "sourceLine": group.get("sourceLine"),
                    "memberIds": [member["enemyId"] for member in group["members"]],
                })
        matched_enemy_ids: set[int] = set()
        for enemy in enemies:
            template = template_for(enemy)
            haystacks = (str(enemy.get("enemyId", "")), str(enemy.get("name") or ""),
                         str(enemy.get("templateId", "")), str(template.get("name") if template else ""))
            if any(query in value.casefold() for value in haystacks):
                enemy_id = enemy.get("enemyId")
                if isinstance(enemy_id, int) and enemy_id not in matched_enemy_ids:
                    matched_enemy_ids.add(enemy_id)
                    result["candidateEnemies"].append(compact_enemy(enemy, template))
        result["candidateGroups"] = result["candidateGroups"][: args.limit]
        result["candidateEnemies"] = result["candidateEnemies"][: args.limit]

    for group_id in args.group_id:
        if group_id <= 0:
            result["errors"].append(f"原版组 ID 必须为正整数: {group_id}")
            continue
        group = group_by_id.get(group_id)
        if group is None:
            result["errors"].append(f"未找到原版组 ID: {group_id}")
            continue
        expanded_members = []
        for member in group["members"]:
            enemy = enemy_by_id.get(member["enemyId"])
            if enemy is None:
                result["anomalies"]["missingEnemyReferences"].append({"groupId": group_id, **member})
                expanded_members.append({**member, "enemy": None, "template": None})
            else:
                expanded_members.append({**member, "enemy": enemy, "template": template_for(enemy)})
        result["selectedGroups"].append({**group, "members": expanded_members})

    seen_direct: set[int] = set()
    for enemy_id in args.enemy_id:
        if enemy_id in seen_direct:
            continue
        seen_direct.add(enemy_id)
        if enemy_id <= 0:
            result["errors"].append(f"敌人 ID 必须为正整数: {enemy_id}")
            continue
        enemy = enemy_by_id.get(enemy_id)
        if enemy is None:
            result["errors"].append(f"未找到敌人 ID: {enemy_id}")
            continue
        result["selectedEnemies"].append({"enemy": enemy, "template": template_for(enemy)})

    has_result = bool(result["candidateGroups"] or result["candidateEnemies"] or result["selectedGroups"] or result["selectedEnemies"])
    if result["errors"]:
        return result, 2
    if args.query and not has_result:
        return result, 1
    return result, 0


def display(value: Any) -> str:
    if value is None:
        return "-"
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return str(value).replace("|", "\\|")


def markdown(result: dict[str, Any]) -> str:
    lines = ["# 原版敌人组检索结果", "", "## 来源", ""]
    for key, source in result["sources"].items():
        if isinstance(source, dict):
            lines.append(f"- {key}: `{source['path']}` ({source['encoding']})")
        else:
            lines.append(f"- {key}: `{source}`")
    if result["errors"]:
        lines.extend(["", "## 错误", ""] + [f"- {error}" for error in result["errors"]])
    anomaly_items = [(key, value) for key, value in result["anomalies"].items() if value]
    if anomaly_items:
        lines.extend(["", "## 异常", ""])
        lines.extend(f"- {key}: `{display(value)}`" for key, value in anomaly_items)
    if result["candidateGroups"]:
        lines.extend(["", "## 候选原版组", "", "| 组ID | 名称 | 敌人ID | 来源行 |", "|---:|---|---|---:|"])
        for group in result["candidateGroups"]:
            lines.append(f"| {display(group['groupId'])} | {display(group['name'])} | {display(group['memberIds'])} | {group['sourceLine']} |")
    if result["candidateEnemies"]:
        lines.extend(["", "## 候选敌人", "", "| 敌人ID | 名称 | 模板 | 等级 | AI | 来源行 |", "|---:|---|---|---|---|---:|"])
        for enemy in result["candidateEnemies"]:
            template = f"{display(enemy['templateId'])} {display(enemy['templateName'])}"
            level = f"{display(enemy['levelMin'])}-{display(enemy['levelMax'])}"
            lines.append(f"| {enemy['enemyId']} | {display(enemy['name'])} | {template} | {level} | {display(enemy['tacticsOption'])} | {enemy['sourceLine']} |")

    def append_enemy_detail(entry: dict[str, Any], heading: str) -> None:
        enemy, template = entry["enemy"], entry["template"]
        lines.extend(["", f"### {heading}", ""])
        if enemy is None:
            lines.append("- 敌人记录缺失")
            return
        lines.extend([
            f"- 敌人: `{enemy.get('enemyId')}` {display(enemy.get('name'))}, enemy 行 {enemy.get('sourceLine')}",
            f"- 等级/数量: `{display(enemy.get('levelMin'))}-{display(enemy.get('levelMax'))}`, `{display(enemy.get('createMinNum'))}-{display(enemy.get('createMaxNum'))}`",
            f"- AI: tactics=`{display(enemy.get('tactics'))}`, option=`{display(enemy.get('tacticsOption'))}`, condition=`{display(enemy.get('actCondition'))}`",
            f"- AI解析: `{display(enemy.get('parsedTactics'))}`", f"- 掉落: `{display(enemy.get('drops'))}`",
        ])
        if template is None:
            lines.append(f"- 模板 `{display(enemy.get('templateId'))}` 缺失")
            return
        lines.extend([
            f"- 模板: `{template.get('templateId')}` {display(template.get('name'))}, enemybase 行 {template.get('sourceLine')}",
            f"- 图像号: `{display(template.get('imageNumber'))}`; 原版技能槽: `{display(template.get('skills'))}`",
            f"- 成长属性: `{display(template.get('growthAttribute'))}`",
        ])

    for group in result["selectedGroups"]:
        lines.extend(["", f"## 原版组 {group.get('groupId')} {display(group.get('name'))}", ""])
        lines.append(f"- 来源行: {group.get('sourceLine')}")
        lines.append(f"- 出现/禁止道具: `{display(group.get('appearByItemId'))}` / `{display(group.get('notAppearByItemId'))}`")
        for member in group["members"]:
            append_enemy_detail(member, f"槽位 {member['slot']}, 权重 {display(member.get('weight'))}")
    for entry in result["selectedEnemies"]:
        enemy = entry["enemy"]
        append_enemy_detail(entry, f"直接敌人 {enemy.get('enemyId')} {display(enemy.get('name'))}")
    if not any((result["candidateGroups"], result["candidateEnemies"], result["selectedGroups"], result["selectedEnemies"], result["errors"])):
        lines.extend(["", "未找到匹配记录."])
    return "\n".join(lines) + "\n"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-root", default=r"D:\csa_8.0", help="8.0 原版客户端根目录")
    parser.add_argument("--query", help="模糊搜索组名、敌人名、模板名或对应ID")
    parser.add_argument("--group-id", type=int, nargs="*", default=[], help="groupfile 中的原版组ID")
    parser.add_argument("--enemy-id", type=int, nargs="*", default=[], help="enemyfile 中的敌人ID")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--limit", type=int, default=50, help="每类候选最多输出数量")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if not args.query and not args.group_id and not args.enemy_id:
        parser.error("必须提供 --query、--group-id 或 --enemy-id")
    if args.limit <= 0:
        parser.error("--limit 必须为正整数")
    try:
        result, exit_code = inspect(args)
    except (InspectionError, OSError, csv.Error) as error:
        result = {"errors": [str(error)]}
        if args.format == "json":
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print(f"# 原版敌人组检索失败\n\n- {error}")
        return 2
    if args.format == "json":
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print(markdown(result), end="")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
