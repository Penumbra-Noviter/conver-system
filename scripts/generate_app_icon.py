"""M7-01 自适应启动图标源图生成器（程序化品牌占位稿）。

在 Windows + PIL 下确定性渲染 1024px 图标三件套：

1. `ic_launcher_source.png`——全幅源图（实心底 #784E14 + 白色「汇」字形 #FFFBF4），
   供 flutter_launcher_icons 生成 legacy 五档 PNG；
2. `ic_launcher_foreground.png`——自适应前景（透明底 + 字形），供 adaptive 图标；
3. `ic_launcher_monochrome.png`——单色变体（单通道 L + tRNS：黑字形 / 透明底），
   供 Android 13+ 主题化（monochrome）图标。系统只取 alpha，换色由系统着色。

字形几何契约（工单 01 验收标准，脚本自身带守卫，测试双保险）：

- ink bbox 宽与高均 ≤ 画布 40%；
- bbox 中心落在画布中心 3% 内；
- 全部不透明像素落在中央 66% 安全区（bbox 整框落入即等价）。

确定性：PIL 12 保存 PNG 不写时间戳等非确定性元数据，同输入两次运行字节级一致，
因此每次提交前重跑脚本即可再生成——换正式品牌稿只改 GLYPH / 颜色常量 / 源图，
不触碰 AndroidManifest.xml（仅读引用 @mipmap/ic_launcher）。

字体解析：优先 msyhbd.ttc（微软雅黑 Bold），失败枚举系统字体目录回退
（_FALLBACK_FONTS 序列逐条 try `ImageFont.truetype` 加载，能加载即用）；
全部不可用抛 FileNotFoundError。
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

__all__ = [
    "CANVAS_SIZE",
    "GLYPH",
    "BG_HEX",
    "FG_HEX",
    "TARGET_GLYPH_RATIO",
    "GLYPH_MAX_RATIO",
    "CENTER_TOLERANCE_RATIO",
    "SAFE_ZONE_RATIO",
    "FONT_PATH",
    "OUTPUT_FILES",
    "GlyphGeometry",
    "hex_to_rgb",
    "resolve_font_path",
    "render_glyph_mask",
    "fit_glyph_font_size",
    "place_glyph",
    "glyph_geometry",
    "assert_glyph_geometry",
    "make_icon_images",
    "generate_icons",
    "main",
]

CANVAS_SIZE = 1024
GLYPH = "汇"
BG_HEX = "#784E14"  # 背景琥珀褐
FG_HEX = "#FFFBF4"  # 字形暖白
# 字形目标占比：留 3% 裕量给 ≤40% 契约与 AA 边缘像素
TARGET_GLYPH_RATIO = 0.37
GLYPH_MAX_RATIO = 0.40  # bbox 宽/高上限（占总画布比例）
CENTER_TOLERANCE_RATIO = 0.03  # 中心偏移上限
SAFE_ZONE_RATIO = 0.66  # 中央安全区占比
FONT_PATH = "C:/Windows/Fonts/msyhbd.ttc"
_FONT_DIR = "C:/Windows/Fonts"
# 回退候选：中文 Bold 常见字体名（按序尝试，能加载即用）
_FALLBACK_FONTS: Sequence[str] = (
    "msyhbd.ttc",  # 微软雅黑 Bold
    "msyh.ttc",  # 微软雅黑 Regular
    "simhei.ttf",  # 黑体
    "Dengb.ttf",  # 等线 Bold
    "simsun.ttc",  # 宋体
    "msjhbd.ttc",  # 微软正黑 Bold
)

OUTPUT_FILES = (
    "ic_launcher_source.png",
    "ic_launcher_foreground.png",
    "ic_launcher_monochrome.png",
)

_FONT_PROBE_SIZE = 24
_FIT_ITERATIONS = 8
_FIT_TOLERANCE = 0.005


@dataclass(frozen=True)
class GlyphGeometry:
    """字形 ink 几何指标（几何契约的机器可读形态，守卫与测试共用）。"""

    bbox: tuple[int, int, int, int] | None
    opaque_count: int
    width_ratio: float
    height_ratio: float
    center_dx: float
    center_dy: float
    in_safe_zone: bool


def hex_to_rgb(hex_str: str) -> tuple[int, int, int]:
    """解析 #RRGGBB 为 (r, g, b)；非 6 位十六进制抛 ValueError。"""
    value = hex_str.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"非法颜色值「{hex_str}」，应为 #RRGGBB")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def _try_load_font(path: Path) -> bool:
    """字体能否被 PIL 正常加载（加载失败 = 不可用，供回退枚举过滤）。"""
    try:
        ImageFont.truetype(str(path), _FONT_PROBE_SIZE, index=0)
    except OSError:
        return False
    return True


def resolve_font_path(
    primary: str | Path | None = None,
    fonts_dir: str | Path = _FONT_DIR,
    fallbacks: Sequence[str] = _FALLBACK_FONTS,
) -> Path:
    """解析可用 Bold 字体路径：优先 primary，失败则枚举 fonts_dir 回退。

    回退序列为常见中文 Bold 字体文件名；每个候选须真实存在、后缀为
    .ttc/.ttf/.otf 且能被 PIL 加载。全部不可用抛 FileNotFoundError。
    """
    candidates: list[Path] = []
    if primary:
        candidates.append(Path(primary))
    directory = Path(fonts_dir)
    for name in fallbacks:
        candidates.append(directory / name)
    for path in candidates:
        if path.suffix.lower() not in (".ttc", ".ttf", ".otf"):
            continue
        if not path.is_file():
            continue
        if _try_load_font(path):
            return path
    raise FileNotFoundError(f"未找到可用中文 Bold 字体（搜索目录 {directory}）")


def render_glyph_mask(
    canvas_size: int,
    font_size: int,
    glyph: str = GLYPH,
    font_path: str | Path | None = None,
    center: tuple[float, float] | None = None,
) -> Image.Image:
    """在 canvas_size 画布上以 font_size 渲染字形，返回 L 掩码（字形=255）。"""
    font = ImageFont.truetype(str(font_path), font_size, index=0)
    mask = Image.new("L", (canvas_size, canvas_size), 0)
    cx, cy = center if center is not None else (canvas_size / 2, canvas_size / 2)
    ImageDraw.Draw(mask).text((cx, cy), glyph, font=font, fill=255, anchor="mm")
    return mask


def fit_glyph_font_size(
    glyph: str,
    font_path: str | Path,
    canvas_size: int = CANVAS_SIZE,
    target_ratio: float = TARGET_GLYPH_RATIO,
) -> int:
    """迭代求 font_size，使字形 ink 最大边 ≈ target_ratio × canvas_size。

    收敛判据：当前 ink 占比落在 [1-ε, 1+ε]（ε=_FIT_TOLERANCE）；
    最多 _FIT_ITERATIONS 轮，防字体 hinting 震荡不收敛。
    """
    target = target_ratio * canvas_size
    font_size = int(canvas_size * target_ratio)
    for _ in range(_FIT_ITERATIONS):
        mask = render_glyph_mask(canvas_size, font_size, glyph, font_path)
        bbox = mask.getbbox()
        if bbox is None:
            raise ValueError(f"字形「{glyph}」在字体 {font_path} 下未渲染出像素")
        dim = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
        if dim <= 0:
            raise ValueError(f"字形「{glyph}」在字体 {font_path} 下 bbox 为空")
        ratio = target / dim
        if 1 - _FIT_TOLERANCE <= ratio <= 1 + _FIT_TOLERANCE:
            break
        font_size = max(2, int(round(font_size * ratio)))
    return font_size


def place_glyph(
    glyph: str,
    font_path: str | Path,
    canvas_size: int = CANVAS_SIZE,
) -> Image.Image:
    """渲染字形掩码：字号适配 ≤40%，并把 ink bbox 中心校正到画布中心。"""
    font_size = fit_glyph_font_size(glyph, font_path, canvas_size)
    center = (canvas_size / 2, canvas_size / 2)
    mask = render_glyph_mask(canvas_size, font_size, glyph, font_path, center)
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError(f"字形「{glyph}」在字体 {font_path} 下未渲染出像素")
    dx = center[0] - (bbox[0] + bbox[2]) / 2
    dy = center[1] - (bbox[1] + bbox[3]) / 2
    if abs(dx) >= 1 or abs(dy) >= 1:
        mask = render_glyph_mask(
            canvas_size, font_size, glyph, font_path, (center[0] + dx, center[1] + dy)
        )
    return mask


def _alpha_band(image: Image.Image) -> Image.Image:
    """统一取「不透明掩码」：L 掩码直返；带 tRNS/alpha 的图像转 RGBA 取 alpha。"""
    if image.mode in ("1", "L") and "transparency" not in image.info:
        return image
    return image.convert("RGBA").getchannel("A")


def glyph_geometry(image: Image.Image, safe_zone_ratio: float = SAFE_ZONE_RATIO) -> GlyphGeometry:
    """提取字形 ink 几何：bbox、占比、中心偏移、安全区判定（按不透明像素）。"""
    width, height = image.size
    alpha = _alpha_band(image)
    bbox = alpha.getbbox()
    if bbox is None:
        return GlyphGeometry(
            bbox=None,
            opaque_count=0,
            width_ratio=0.0,
            height_ratio=0.0,
            center_dx=0.0,
            center_dy=0.0,
            in_safe_zone=False,
        )
    x0, y0, x1, y1 = bbox
    ink_w, ink_h = x1 - x0, y1 - y0
    lo_x = width * (1 - safe_zone_ratio) / 2
    lo_y = height * (1 - safe_zone_ratio) / 2
    hi_x = width * (1 + safe_zone_ratio) / 2
    hi_y = height * (1 + safe_zone_ratio) / 2
    in_safe_zone = x0 >= lo_x and y0 >= lo_y and x1 <= hi_x and y1 <= hi_y
    hist = alpha.histogram()
    return GlyphGeometry(
        bbox=bbox,
        opaque_count=sum(hist) - hist[0],  # 总数 - 0 值像素
        width_ratio=ink_w / width,
        height_ratio=ink_h / height,
        center_dx=(bbox[0] + bbox[2]) / 2 - width / 2,
        center_dy=(bbox[1] + bbox[3]) / 2 - height / 2,
        in_safe_zone=in_safe_zone,
    )


def assert_glyph_geometry(
    image: Image.Image,
    canvas_size: int = CANVAS_SIZE,
    glyph_max_ratio: float = GLYPH_MAX_RATIO,
    center_tolerance_ratio: float = CENTER_TOLERANCE_RATIO,
    safe_zone_ratio: float = SAFE_ZONE_RATIO,
) -> None:
    """校验字形几何契约（bbox ≤ 40%、中心 ≤ 3%、安全区 66%）；违反抛 ValueError。

    生成与测试双保险：make_icon_images 内守护，负样本测试逐条拒绝。
    """
    geom = glyph_geometry(image, safe_zone_ratio)
    if geom.opaque_count == 0:
        raise ValueError("字形几何契约违反：画布无任何不透明像素")
    problems: list[str] = []
    if geom.width_ratio > glyph_max_ratio or geom.height_ratio > glyph_max_ratio:
        problems.append(
            f"bbox 超出画布 {glyph_max_ratio:.0%}"
            f"（宽 {geom.width_ratio:.3f} 高 {geom.height_ratio:.3f}）"
        )
    tolerance = canvas_size * center_tolerance_ratio
    if abs(geom.center_dx) > tolerance or abs(geom.center_dy) > tolerance:
        problems.append(
            f"中心偏移超 {center_tolerance_ratio:.0%}"
            f"（dx={geom.center_dx:.1f} dy={geom.center_dy:.1f}）"
        )
    if not geom.in_safe_zone:
        problems.append(f"存在不透明像素超出中央 {safe_zone_ratio:.0%} 安全区")
    if problems:
        raise ValueError("字形几何契约违反：" + "; ".join(problems))


def make_icon_images(
    glyph: str = GLYPH,
    canvas_size: int = CANVAS_SIZE,
    font_path: str | Path | None = None,
) -> dict[str, Image.Image]:
    """构建三张 1024px 图标图：source（RGB 全幅）/ foreground（RGBA 透明底）/ monochrome（L 单色）。

    monochrome 以 L 模式构建（灰 255 = 透明背景），落盘时写 tRNS=255 转透明。
    """
    resolved = resolve_font_path(primary=str(font_path) if font_path else None)
    mask = place_glyph(glyph, resolved, canvas_size)
    assert_glyph_geometry(mask, canvas_size=canvas_size)
    bg = hex_to_rgb(BG_HEX)
    fg = hex_to_rgb(FG_HEX)

    source = Image.new("RGB", (canvas_size, canvas_size), bg)
    source.paste(fg, (0, 0), mask)

    foreground = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    foreground.paste(fg, (0, 0), mask)

    monochrome = Image.new("L", (canvas_size, canvas_size), 255)
    # 二值映射：字形 ink（含 AA 边缘）→ 0（黑），背景 → 255（透明）。
    # 单通道 PNG 的 tRNS 是二值透明，L+tRNS 下混合灰会变不透明灰——二值化保证
    # 「黑字形 / 透明底」逐像素成立（Android 主题化只取 alpha，无需 AA 灰阶）。
    binary_alpha = mask.point(lambda value: 255 if value >= 1 else 0)
    monochrome.paste(0, (0, 0), binary_alpha)
    return dict(zip(OUTPUT_FILES, (source, foreground, monochrome)))


def generate_icons(
    output_dir: str | Path,
    images: dict[str, Image.Image] | None = None,
    font_path: str | Path | None = None,
) -> dict[str, Path]:
    """把三张图标 PNG 确定性落盘（同输入 → 字节一致），返回文件名 → 路径。"""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    if images is None:
        images = make_icon_images(font_path=font_path)
    written: dict[str, Path] = {}
    for name, image in images.items():
        path = out / name
        if name == OUTPUT_FILES[2] and image.mode == "L":
            image.save(path, format="PNG", transparency=255)
        else:
            image.save(path, format="PNG")
        written[name] = path
    return written


_DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent.parent / "assets" / "icons"


def main(argv: list[str] | None = None) -> int:
    """CLI 入口：渲染三张 PNG 到 assets/icons（可 --output-dir / --font-path 覆盖）。"""
    parser = argparse.ArgumentParser(
        description="M7-01：确定性生成 1024px 启动图标三件套（source/foreground/monochrome）"
    )
    parser.add_argument("--output-dir", type=Path, default=_DEFAULT_OUTPUT_DIR, help="输出目录")
    parser.add_argument(
        "--font-path", type=Path, default=None, help="字形字体路径（默认 msyhbd.ttc，失败回退枚举）"
    )
    args = parser.parse_args(argv)
    written = generate_icons(args.output_dir, font_path=args.font_path)
    for name in OUTPUT_FILES:
        path = written[name]
        print(f"[generate_app_icon] {name} -> {path} ({path.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())