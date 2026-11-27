#!/usr/bin/env python3
"""从品牌图形生成各平台的应用图标。

源图 `assets/branding/sonata-mark.webp` 是纯图形（圆环 + 音符，1600x1600，
无文字）。用它而不是带「SONATA」字样那张 lockup：应用图标在系统里会被裁成
圆角矩形或圆形，60pt 下文字完全看不清，Android 的 maskable 还会把四周切掉。

图形外接框是 x 262..1344 / y 288..1356。这里以它的中心为准裁一个略大的
正方形（四周留 ~4% 呼吸），再按各平台要求导出。

用法：
    python3 tool/generate_app_icons.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/branding/sonata-mark.webp"

# 图形外接框 262..1344 / 288..1356，中心 (803, 822)。
# 边长 1180 → 左右各留 49px、上下各留 56px，接近满幅的图标比例。
SIDE = 1180
LEFT = 803 - SIDE // 2  # 213
TOP = 822 - SIDE // 2  # 232


def load_mark() -> Image.Image:
    """裁出图形，返回 RGB（App 图标不能带透明通道）。"""
    src = Image.open(SRC).convert("RGB")
    # 裁之前先确认图形完整落在画布里，越界会得到黑边。
    if LEFT < 0 or TOP < 0 or LEFT + SIDE > src.width or TOP + SIDE > src.height:
        raise SystemExit(f"裁剪区越界：{LEFT},{TOP} {SIDE}x{SIDE}，源图 {src.size}")
    return src.crop((LEFT, TOP, LEFT + SIDE, TOP + SIDE))


def _corner_color(mark: Image.Image) -> tuple[int, int, int]:
    """取四角平均色作为留白填充，能和渐变边缘接上。"""
    w, h = mark.size
    px = mark.load()
    pts = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]
    r = sum(px[x, y][0] for x, y in pts) // 4
    g = sum(px[x, y][1] for x, y in pts) // 4
    b = sum(px[x, y][2] for x, y in pts) // 4
    return (r, g, b)


def resized(mark: Image.Image, size: int, pad_ratio: float = 0.0) -> Image.Image:
    """缩放到 size；pad_ratio > 0 时四周留白（macOS 与 maskable 图标用）。"""
    if pad_ratio <= 0:
        return mark.resize((size, size), Image.LANCZOS)
    inner = int(size * (1 - pad_ratio * 2))
    canvas = Image.new("RGB", (size, size), _corner_color(mark))
    canvas.paste(
        mark.resize((inner, inner), Image.LANCZOS),
        ((size - inner) // 2, (size - inner) // 2),
    )
    return canvas


def write_ios(mark: Image.Image) -> None:
    """iOS：25 个尺寸，不透明、不预裁圆角（系统自己裁）。"""
    base = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-50x50@1x.png": 50,
        "Icon-App-50x50@2x.png": 100,
        "Icon-App-57x57@1x.png": 57,
        "Icon-App-57x57@2x.png": 114,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-72x72@1x.png": 72,
        "Icon-App-72x72@2x.png": 144,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }.items():
        mark.resize((px, px), Image.LANCZOS).save(base / name, optimize=True)


def write_macos(mark: Image.Image) -> None:
    """macOS 图标系统不加遮罩，四周留 10% 才不会顶满。"""
    base = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, px in {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }.items():
        resized(mark, px, pad_ratio=0.10).save(base / name, optimize=True)


def write_android(mark: Image.Image) -> None:
    base = ROOT / "android/app/src/main/res"
    for folder, px in {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }.items():
        mark.resize((px, px), Image.LANCZOS).save(
            base / folder / "ic_launcher.png", optimize=True
        )


def write_web(mark: Image.Image) -> None:
    base = ROOT / "web/icons"
    mark.resize((192, 192), Image.LANCZOS).save(base / "Icon-192.png", optimize=True)
    mark.resize((512, 512), Image.LANCZOS).save(base / "Icon-512.png", optimize=True)
    # maskable 会被裁成圆形/水滴，图形要缩进中间 60%。
    resized(mark, 192, pad_ratio=0.20).save(
        base / "Icon-maskable-192.png", optimize=True
    )
    resized(mark, 512, pad_ratio=0.20).save(
        base / "Icon-maskable-512.png", optimize=True
    )


def write_app_assets(mark: Image.Image) -> None:
    """App 内用的两份：1024 图标 + 播放页无封面时的占位图。"""
    mark.resize((1024, 1024), Image.LANCZOS).save(
        ROOT / "assets/branding/sonata-icon-1024.png", optimize=True
    )
    # 占位图会被圆形裁切（播放页唱片圆盘）。这里不能用 pad_ratio：
    # 补边是纯色，裁成圆之后会露出一圈方形边界，很难看。
    # 图形本身在裁切区里已经留了 ~4% 的边，直接满幅即可。
    mark.resize((1024, 1024), Image.LANCZOS).save(
        ROOT / "assets/app_icon.png", optimize=True
    )


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f"找不到源图：{SRC}")
    mark = load_mark()
    write_ios(mark)
    write_macos(mark)
    write_android(mark)
    write_web(mark)
    write_app_assets(mark)
    print(f"图标已生成（裁剪区 {LEFT},{TOP} {SIDE}x{SIDE}）")


if __name__ == "__main__":
    main()
