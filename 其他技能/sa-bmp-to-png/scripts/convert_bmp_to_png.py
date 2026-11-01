#!/usr/bin/env python3
"""递归转换 BMP 为 PNG, 校验成功后移除对应 BMP。"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import tempfile
from io import BytesIO
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:
    print(
        "错误: 缺少 Pillow 依赖。请在获得用户确认后执行: "
        f"{sys.executable} -m pip install Pillow",
        file=sys.stderr,
    )
    sys.exit(2)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="递归转换目录中的 BMP 为透明 PNG, 成功后移除源 BMP。"
    )
    parser.add_argument("directory", help="需要递归处理的目标文件夹")
    return parser.parse_args()


def collect_files(root: Path) -> list[Path]:
    """收集 BMP 普通文件, 且不跟随目录符号链接。"""
    bmp_files: list[Path] = []

    for current_dir, dir_names, file_names in os.walk(root, followlinks=False):
        dir_names.sort(key=str.casefold)
        file_names.sort(key=str.casefold)
        parent = Path(current_dir)

        for file_name in file_names:
            file_path = parent / file_name
            if not file_path.is_file() or file_path.is_symlink():
                continue

            if file_path.suffix.casefold() == ".bmp":
                bmp_files.append(file_path)

    return bmp_files


def preflight(bmp_files: list[Path]) -> list[tuple[Path, Path]]:
    """在产生修改前检查多个 BMP 是否映射到同一输出。"""
    conversions: list[tuple[Path, Path]] = []
    outputs: dict[str, Path] = {}

    for bmp_path in bmp_files:
        png_path = bmp_path.with_suffix(".png")
        output_key = str(png_path).casefold()

        if output_key in outputs:
            raise ValueError(
                f"多个 BMP 映射到同一 PNG: {outputs[output_key]} 和 {bmp_path}"
            )
        outputs[output_key] = bmp_path
        conversions.append((bmp_path, png_path))

    return conversions


def calculate_md5(file_path: Path) -> str:
    """分块计算文件 MD5, 避免大文件一次性载入内存。"""
    digest = hashlib.md5()
    with file_path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_existing_png(png_path: Path) -> None:
    """确保同名输出是本地普通文件, 避免跟随符号链接或覆盖目录。"""
    if not png_path.is_file() or png_path.is_symlink():
        raise ValueError(f"目标 PNG 不是普通文件, 拒绝处理: {png_path}")


def convert_one(bmp_path: Path, png_path: Path) -> tuple[str, Path]:
    """校验转换结果, 按 MD5 去重或分流后移除源 BMP。"""
    temp_path: Path | None = None

    try:
        # 先关闭源文件句柄再交给 Pillow 解码, 避免 Windows 内存映射阻止删除 BMP。
        source_bytes = bmp_path.read_bytes()
        with Image.open(BytesIO(source_bytes)) as source:
            source.load()
            original_size = source.size
            with source.convert("RGBA") as rgba:
                # 灰度值仅在 RGB 三通道均为 0 时等于 0, 因此可精确定位纯黑像素。
                with rgba.convert("RGB") as rgb:
                    with rgb.convert("L") as grayscale:
                        with grayscale.point(
                            lambda value: 0 if value == 0 else 255
                        ) as non_black_mask:
                            with rgba.getchannel("A") as original_alpha:
                                with ImageChops.multiply(
                                    original_alpha, non_black_mask
                                ) as output_alpha:
                                    rgba.putalpha(output_alpha)

                with tempfile.NamedTemporaryFile(
                    prefix=f".{png_path.stem}.",
                    suffix=".png.tmp",
                    dir=png_path.parent,
                    delete=False,
                ) as temp_file:
                    temp_path = Path(temp_file.name)

                rgba.save(temp_path, format="PNG")

        with Image.open(temp_path) as converted:
            if converted.format != "PNG":
                raise ValueError(f"输出格式不是 PNG: {converted.format}")
            if converted.size != original_size:
                raise ValueError(
                    f"图片尺寸发生变化: {original_size} -> {converted.size}"
                )
            converted.verify()

        output_path = png_path
        result = "converted"

        if png_path.exists():
            validate_existing_png(png_path)
            if calculate_md5(temp_path) == calculate_md5(png_path):
                bmp_path.unlink()
                return "deduplicated", png_path

            new_dir = png_path.parent / "new"
            if new_dir.exists() and (not new_dir.is_dir() or new_dir.is_symlink()):
                raise ValueError(f"分流目录不是本地普通目录: {new_dir}")
            new_dir.mkdir(exist_ok=True)
            output_path = new_dir / png_path.name
            result = "diverted"

            if output_path.exists():
                validate_existing_png(output_path)
                if calculate_md5(temp_path) == calculate_md5(output_path):
                    bmp_path.unlink()
                    return "deduplicated", output_path
                raise ValueError(f"分流 PNG 已存在且内容不同: {output_path}")

        os.replace(temp_path, output_path)
        temp_path = None
        bmp_path.unlink()
        return result, output_path
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    root = Path(args.directory).expanduser().resolve()

    if not root.is_dir():
        print(f"错误: 指定路径不存在或不是文件夹: {root}", file=sys.stderr)
        return 2

    bmp_files = collect_files(root)
    print(f"目标文件夹: {root}")
    print(f"发现 BMP: {len(bmp_files)}")

    try:
        conversions = preflight(bmp_files)
    except ValueError as error:
        print(f"错误: {error}", file=sys.stderr)
        return 2

    converted_count = 0
    diverted_count = 0
    deduplicated_count = 0
    failures: list[tuple[Path, str]] = []

    for bmp_path, png_path in conversions:
        try:
            result, output_path = convert_one(bmp_path, png_path)
            if result == "converted":
                converted_count += 1
                print(f"成功: {bmp_path} -> {output_path}")
            elif result == "diverted":
                diverted_count += 1
                print(f"分流: {bmp_path} -> {output_path}")
            else:
                deduplicated_count += 1
                print(f"去重: {bmp_path} == {output_path}")
        except Exception as error:
            failures.append((bmp_path, str(error)))
            print(f"失败: {bmp_path}: {error}", file=sys.stderr)

    remaining_bmp = collect_files(root)
    print(
        f"完成: 正常转换 {converted_count} 个, 分流 {diverted_count} 个, "
        f"去重 {deduplicated_count} 个, "
        f"失败 {len(failures)} 个, 剩余 BMP {len(remaining_bmp)} 个。"
    )

    return 1 if failures or remaining_bmp else 0


if __name__ == "__main__":
    sys.exit(main())
