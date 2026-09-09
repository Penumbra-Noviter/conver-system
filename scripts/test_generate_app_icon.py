"""generate_app_icon 的 pytest 契约测试（几何 / 颜色 / 确定性 / 错误路径）。

契约数字来自工单 01《自适应启动图标生成管线》验收标准原文（独立来源），
逐字落在断言里，不用实现重算：

- 字形 ink bbox 宽与高均 ≤ 画布 40%（1024px → 410px 上限）
- bbox 中心落在画布中心 3% 内（±32px）
- 全部不透明像素落在中央 66% 安全区（[174, 849] 正方形框）
- 全幅源图背景实心 RGB(120,78,20)（#784E14）、字形 RGB(255,251,244)（#FFFBF4）
- monochrome 变体单通道（黑字形 / 透明底）
- 同输入两次运行字节级一致（确定性契约）

运行：python -m pytest scripts/test_generate_app_icon.py --cov=scripts/generate_app_icon.py
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from PIL import Image, ImageDraw

import generate_app_icon as gen

# ---- spec 字面量（工单原文，非实现重算）----
CANVAS = 1024
HALF = 512
MAX_INK = int(CANVAS * 0.40) + 1  # 410：bbox 宽/高上限
CENTER_TOL = int(CANVAS * 0.03) + 1  # 32：中心偏移上限
SAFE_LO = int(CANVAS * (1 - 0.66) / 2)  # 174：中央 66% 安全区下界
SAFE_HI = int(CANVAS * (1 + 0.66) / 2)  # 849：中央 66% 安全区上界
BG_RGB = (120, 78, 20)
FG_RGB = (255, 251, 244)

SOURCE = "ic_launcher_source.png"
FOREGROUND = "ic_launcher_foreground.png"
MONOCHROME = "ic_launcher_monochrome.png"

FONT_PRIMARY = "C:/Windows/Fonts/msyhbd.ttc"
FONT_BACKUP = "C:/Windows/Fonts/arial.ttf"


def _alpha_band(image: Image.Image) -> Image.Image:
    """取「不透明掩码」：L 掩码直返；tRNS/带 alpha 图像转 RGBA 取 alpha 通道。"""
    if image.mode in ("1", "L") and "transparency" not in image.info:
        return image
    return image.convert("RGBA").getchannel("A")


def _ink_box(alpha: Image.Image) -> tuple[int, int, int, int]:
    bb = alpha.getbbox()
    assert bb is not None, "字形未渲染出任何不透明像素"
    return bb


def _core_pixels(alpha: Image.Image) -> list[tuple[int, int]]:
    """字形实心核心像素（alpha=255，排除 AA 边缘）。"""
    bb = _ink_box(alpha)
    x0, y0, x1, y1 = bb
    px = alpha.load()
    return [(x, y) for y in range(y0, y1) for x in range(x0, x1) if px[x, y] == 255]


def _rect_mask(size: int, box: tuple[int, int, int, int]) -> Image.Image:
    """合成矩形字形掩码（负样本用，不依赖字体）。"""
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rectangle(box, fill=255)
    return mask


@pytest.fixture(scope="module")
def written(tmp_path_factory):
    """真实跑一次 generate_icons 的落盘产物（即 flutter_launcher_icons 的消费面）。"""
    out = tmp_path_factory.mktemp("icons")
    paths = gen.generate_icons(out)
    assert set(paths) == set(gen.OUTPUT_FILES)
    return paths


@pytest.fixture(scope="module")
def images(written):
    """按磁盘打开的三张图标图（含 tRNS 等落盘元数据）。"""
    return {name: Image.open(path) for name, path in written.items()}


class TestGeometry:
    """字形几何契约：bbox ≤ 40%、中心偏移 ≤ 3%、全部不透明像素在中央 66%。"""

    def test_foreground_ink_bbox_within_40_percent(self, images):
        bb = _ink_box(_alpha_band(images[FOREGROUND]))
        assert bb[2] - bb[0] <= MAX_INK
        assert bb[3] - bb[1] <= MAX_INK

    def test_foreground_ink_centered_within_3_percent(self, images):
        bb = _ink_box(_alpha_band(images[FOREGROUND]))
        assert abs((bb[0] + bb[2]) / 2 - HALF) <= CENTER_TOL
        assert abs((bb[1] + bb[3]) / 2 - HALF) <= CENTER_TOL

    def test_foreground_all_opaque_in_safe_zone(self, images):
        bb = _ink_box(_alpha_band(images[FOREGROUND]))
        # bbox 整框在安全区内 ⇔ 全部不透明像素在安全区内（不透明像素 ⊆ bbox）
        assert bb[0] >= SAFE_LO
        assert bb[1] >= SAFE_LO
        assert bb[2] <= SAFE_HI
        assert bb[3] <= SAFE_HI

    def test_monochrome_shares_glyph_geometry(self, images):
        fg_bb = _ink_box(_alpha_band(images[FOREGROUND]))
        mono_bb = _ink_box(_alpha_band(images[MONOCHROME]))
        assert fg_bb == mono_bb  # 单色与前景同一字形、同一几何


class TestColors:
    """颜色常量与三张图的像素级颜色断言（实心核心 = alpha 255，排除 AA 边缘）。"""

    def test_hex_to_rgb_parses_constants(self):
        assert gen.hex_to_rgb(gen.BG_HEX) == BG_RGB
        assert gen.hex_to_rgb(gen.FG_HEX) == FG_RGB

    def test_hex_to_rgb_rejects_bad_shape(self):
        with pytest.raises(ValueError):
            gen.hex_to_rgb("#FFF")
        with pytest.raises(ValueError):
            gen.hex_to_rgb("1234567")

    def test_source_is_full_bleed(self, images):
        src = images[SOURCE]
        assert src.mode == "RGB"
        assert src.size == (CANVAS, CANVAS)
        assert src.getpixel((0, 0)) == BG_RGB
        assert src.getpixel((CANVAS - 1, CANVAS - 1)) == BG_RGB

    def test_source_glyph_core_is_fg_color(self, images):
        src = images[SOURCE]
        for x, y in _core_pixels(_alpha_band(images[FOREGROUND]))[:500]:
            assert src.getpixel((x, y)) == FG_RGB

    def test_foreground_transparent_bg(self, images):
        fg = images[FOREGROUND]
        assert fg.mode == "RGBA"
        assert fg.getpixel((0, 0)) == (0, 0, 0, 0)
        assert fg.getpixel((CANVAS - 1, CANVAS - 1)) == (0, 0, 0, 0)

    def test_foreground_glyph_core_is_fg_color_opaque(self, images):
        fg = images[FOREGROUND]
        for x, y in _core_pixels(_alpha_band(fg))[:500]:
            assert fg.getpixel((x, y))[:3] == FG_RGB
            assert fg.getpixel((x, y))[3] == 255

    def test_monochrome_single_channel_black_glyph(self, images):
        mono = images[MONOCHROME]
        assert mono.mode == "L"  # 单通道
        assert mono.info.get("transparency") == 255  # 透明底（tRNS）
        rgba = mono.convert("RGBA")
        assert rgba.getpixel((0, 0))[3] == 0
        assert rgba.getpixel((CANVAS - 1, CANVAS - 1))[3] == 0
        for x, y in _core_pixels(_alpha_band(mono))[:500]:
            assert rgba.getpixel((x, y))[:3] == (0, 0, 0)  # 黑字形


class TestDeterminism:
    """确定性契约：同输入两次运行字节级一致（PIL 12 保存 PNG 不含时间戳元数据）。"""

    def test_two_runs_produce_identical_bytes(self, tmp_path):
        d1, d2 = tmp_path / "run1", tmp_path / "run2"
        gen.generate_icons(d1)
        gen.generate_icons(d2)
        for name in gen.OUTPUT_FILES:
            b1 = (d1 / name).read_bytes()
            b2 = (d2 / name).read_bytes()
            assert hashlib.md5(b1).hexdigest() == hashlib.md5(b2).hexdigest()
            assert b1 == b2


class TestGeneratedFiles:
    """产物形态：文件命名、尺寸、generate_icons / main 入口。"""

    def test_output_files_constant_is_the_three_icon_names(self):
        assert gen.OUTPUT_FILES == (SOURCE, FOREGROUND, MONOCHROME)

    def test_all_images_are_1024_square(self, images):
        for name, img in images.items():
            assert img.size == (CANVAS, CANVAS), name

    def test_generate_icons_accepts_prebuilt_images(self, tmp_path):
        prebuilt = gen.make_icon_images()
        paths = gen.generate_icons(tmp_path, images=prebuilt)
        for name, path in paths.items():
            assert path.is_file()
            assert path.read_bytes() == (tmp_path / name).read_bytes()

    def test_main_writes_default_outputs(self, tmp_path):
        ret = gen.main(["--output-dir", str(tmp_path)])
        assert ret == 0
        for name in gen.OUTPUT_FILES:
            assert (tmp_path / name).is_file()

    def test_main_accepts_font_path_flag(self, tmp_path):
        ret = gen.main(["--output-dir", str(tmp_path), "--font-path", FONT_PRIMARY])
        assert ret == 0
        assert (tmp_path / SOURCE).is_file()

    def test_module_runs_as_cli_entrypoint(self, tmp_path):
        # 以 `python scripts/generate_app_icon.py` 真实执行（__main__ 守卫路径）。
        # 与直接调 main() 互补：验证脚本本体可独立运行且定义行为一致。
        proc = subprocess.run(
            [sys.executable, str(Path(gen.__file__)), "--output-dir", str(tmp_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert proc.returncode == 0, proc.stderr
        for name in gen.OUTPUT_FILES:
            assert (tmp_path / name).is_file()

    def test_module_entry_guard_via_run_as_main(self, tmp_path):
        # 进程内以 __main__ 名义执行 → 覆盖 `if __name__ == "__main__"` 与 sys.exit(main())
        import runpy

        old_argv = sys.argv
        try:
            sys.argv = ["generate_app_icon.py", "--output-dir", str(tmp_path)]
            with pytest.raises(SystemExit) as exc_info:
                runpy.run_path(str(Path(gen.__file__)), run_name="__main__")
        finally:
            sys.argv = old_argv
        assert exc_info.value.code == 0
        assert (tmp_path / SOURCE).is_file()


class TestFontResolution:
    """字体解析：优先 primary，失败按 fallbacks 序列回退枚举，全败抛错。"""

    def test_prefers_primary_when_valid(self, tmp_path):
        got = gen.resolve_font_path(primary=FONT_PRIMARY, fonts_dir=tmp_path)
        assert Path(got) == Path(FONT_PRIMARY)

    def test_falls_back_to_first_usable_candidate(self, tmp_path):
        # 不可加载的候选先被跳过，命中真实可加载候选（用非系统文件名避免
        # PIL 按 basename 静默回退系统字体，证明加载校验真实生效）
        (tmp_path / "broken.ttf").write_bytes(b"not a font")
        shutil.copyfile(FONT_BACKUP, tmp_path / "usable.ttf")
        got = gen.resolve_font_path(
            primary=tmp_path / "gone.ttf",
            fonts_dir=tmp_path,
            fallbacks=("broken.ttf", "usable.ttf"),
        )
        assert str(got) == str(tmp_path / "usable.ttf")

    def test_skips_non_font_extension_candidates(self, tmp_path):
        # 扩展名不在 .ttc/.ttf/.otf 内的候选直接跳过（后缀守卫分支）
        (tmp_path / "notes.txt").write_text("not a font candidate")
        shutil.copyfile(FONT_BACKUP, tmp_path / "usable.ttf")
        got = gen.resolve_font_path(
            primary=tmp_path / "gone.ttf",
            fonts_dir=tmp_path,
            fallbacks=("notes.txt", "usable.ttf"),
        )
        assert str(got) == str(tmp_path / "usable.ttf")

    def test_raises_when_all_candidates_unusable(self, tmp_path):
        (tmp_path / "broken.ttf").write_bytes(b"not a font")
        with pytest.raises(FileNotFoundError):
            gen.resolve_font_path(
                primary=tmp_path / "gone.ttf",
                fonts_dir=tmp_path,
                fallbacks=("broken.ttf", "also_gone.ttf"),
            )

    def test_default_fallbacks_find_system_yahei(self):
        if not Path(FONT_PRIMARY).exists():
            pytest.skip("本机无 msyhbd.ttc")
        got = gen.resolve_font_path(primary=Path("__missing____.ttf"))
        assert Path(got) == Path(FONT_PRIMARY)

    def test_fallback_font_still_meets_geometry(self, tmp_path):
        # 回退字体渲染结果同样满足几何契约（工单 spike 分流句）
        shutil.copyfile(FONT_PRIMARY, tmp_path / "fallback.ttc")
        images = gen.make_icon_images(font_path=tmp_path / "fallback.ttc")
        fg = images[FOREGROUND]
        bb = _ink_box(_alpha_band(fg))
        assert bb[2] - bb[0] <= MAX_INK
        assert bb[3] - bb[1] <= MAX_INK
        assert abs((bb[0] + bb[2]) / 2 - HALF) <= CENTER_TOL


class TestGeometryGuard:
    """assert_glyph_geometry 守卫：合法通过，负样本逐条拒绝（不依赖字体）。"""

    def test_valid_centered_glyph_passes(self):
        gen.assert_glyph_geometry(_rect_mask(CANVAS, (310, 310, 714, 714)))

    def test_oversized_glyph_rejected(self):
        with pytest.raises(ValueError):
            gen.assert_glyph_geometry(_rect_mask(CANVAS, (256, 256, 768, 768)))

    def test_off_center_glyph_rejected(self):
        with pytest.raises(ValueError):
            gen.assert_glyph_geometry(_rect_mask(CANVAS, (100, 400, 400, 700)))

    def test_outside_safe_zone_rejected(self):
        # 放宽中心/尺寸阈值后，几何仍须兜住安全区（冗余守卫的可达分支）
        with pytest.raises(ValueError):
            gen.assert_glyph_geometry(
                _rect_mask(CANVAS, (500, 500, 950, 600)),
                glyph_max_ratio=0.6,
                center_tolerance_ratio=0.25,
            )

    def test_relaxed_thresholds_accept(self):
        gen.assert_glyph_geometry(
            _rect_mask(CANVAS, (300, 400, 700, 600)),
            glyph_max_ratio=0.6,
            center_tolerance_ratio=0.25,
        )

    def test_blank_canvas_rejected(self):
        with pytest.raises(ValueError):
            gen.assert_glyph_geometry(Image.new("L", (CANVAS, CANVAS), 0))

    def test_rgba_image_accepted_via_alpha_band(self):
        # RGBA 输入走模块 _alpha_band 的 alpha 通道分支（公共 API 兜住）
        fg = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        ImageDraw.Draw(fg).rectangle((310, 310, 714, 714), fill=(255, 251, 244, 255))
        gen.assert_glyph_geometry(fg)

    def test_render_glyph_mask_default_center_not_blank(self):
        mask = gen.render_glyph_mask(64, 24, "汇", FONT_PRIMARY)
        assert _ink_box(_alpha_band(mask)) is not None