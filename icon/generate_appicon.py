#!/usr/bin/env python3
"""
macOS App图标生成脚本
将源图片处理成macOS AppIcon.appiconset，应用圆角矩形效果
"""

import os
import json
from PIL import Image, ImageDraw

# 源图片文件名
SOURCE_IMAGE = "pocket_translator_appicon.png"

# 输出目录
OUTPUT_DIR = "AppIcon.appiconset"

# macOS图标尺寸配置: (文件名, 实际像素尺寸, idiom, size, scale)
ICON_SIZES = [
    ("icon_16x16.png", 16, "mac", "16x16", "1x"),
    ("icon_16x16@2x.png", 32, "mac", "16x16", "2x"),
    ("icon_32x32.png", 32, "mac", "32x32", "1x"),
    ("icon_32x32@2x.png", 64, "mac", "32x32", "2x"),
    ("icon_128x128.png", 128, "mac", "128x128", "1x"),
    ("icon_128x128@2x.png", 256, "mac", "128x128", "2x"),
    ("icon_256x256.png", 256, "mac", "256x256", "1x"),
    ("icon_256x256@2x.png", 512, "mac", "256x256", "2x"),
    ("icon_512x512.png", 512, "mac", "512x512", "1x"),
    ("icon_512x512@2x.png", 1024, "mac", "512x512", "2x"),
]

# 圆角半径比例 (Apple设计规范约为22.37%)
CORNER_RADIUS_RATIO = 0.2237


def create_rounded_mask(size, radius):
    """创建圆角矩形蒙版"""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [(0, 0), (size - 1, size - 1)],
        radius=radius,
        fill=255
    )
    return mask


def apply_rounded_corners(image, radius):
    """应用圆角矩形效果"""
    # 确保图片有alpha通道
    if image.mode != "RGBA":
        image = image.convert("RGBA")

    size = image.size[0]
    mask = create_rounded_mask(size, radius)

    # 创建透明背景
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    result.paste(image, (0, 0))

    # 应用蒙版到alpha通道
    result.putalpha(mask)

    return result


def generate_icon(source_image, size, output_path):
    """生成指定尺寸的图标"""
    # 缩放图片
    resized = source_image.resize((size, size), Image.Resampling.LANCZOS)

    # 计算圆角半径
    radius = int(size * CORNER_RADIUS_RATIO)

    # 应用圆角
    rounded = apply_rounded_corners(resized, radius)

    # 保存
    rounded.save(output_path, "PNG")
    print(f"  生成: {output_path} ({size}x{size})")


def generate_contents_json(output_dir):
    """生成Contents.json文件"""
    images = []
    for filename, _, idiom, size, scale in ICON_SIZES:
        images.append({
            "filename": filename,
            "idiom": idiom,
            "scale": scale,
            "size": size
        })

    contents = {
        "images": images,
        "info": {
            "author": "xcode",
            "version": 1
        }
    }

    json_path = os.path.join(output_dir, "Contents.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
    print(f"  生成: {json_path}")


def main():
    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 源图片路径
    source_path = os.path.join(script_dir, SOURCE_IMAGE)

    # 检查源图片是否存在
    if not os.path.exists(source_path):
        print(f"错误: 找不到源图片 {source_path}")
        return

    # 输出目录路径
    output_dir = os.path.join(script_dir, OUTPUT_DIR)

    # 创建输出目录
    os.makedirs(output_dir, exist_ok=True)
    print(f"输出目录: {output_dir}")

    # 加载源图片
    print(f"加载源图片: {source_path}")
    source_image = Image.open(source_path)

    # 确保源图片是RGBA模式
    if source_image.mode != "RGBA":
        source_image = source_image.convert("RGBA")

    print(f"源图片尺寸: {source_image.size[0]}x{source_image.size[1]}")
    print()
    print("生成图标:")

    # 生成各尺寸图标
    for filename, size, _, _, _ in ICON_SIZES:
        output_path = os.path.join(output_dir, filename)
        generate_icon(source_image, size, output_path)

    print()

    # 生成Contents.json
    generate_contents_json(output_dir)

    print()
    print("完成! 图标集已生成到:", output_dir)
    print("请将 AppIcon.appiconset 目录复制到 Xcode 项目的 Assets.xcassets 中")


if __name__ == "__main__":
    main()
