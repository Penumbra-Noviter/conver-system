"""
工单 03 单元测试 — 模拟器导入（服务层导入族 + 路由 wire）

契约锚点（spec T-02 决策 4/5/6/7/8 + 工单 03 验收标准）：
    POST /api/simulators/import（multipart 字段名 file）：
        - 成功 200：{ ok, game: {id, file, name, type, config?}, renamed, warnings }
        - 校验失败 400（非 .html / 超 5MB / 空文件）；重复 409（SHA-256 命中，文案含「已存在」）
        - warnings 键集：eval / document.cookie / cross-origin-fetch（常量单源，不拦截）
    服务层（simulator_store.py 导入族，路径参数化 seam）：
        sanitize_filename / next_available_filename / slugify / find_duplicate /
        probe_config / scan_suspicious / import_game（编排 + 校验 + 落盘 + manifest 注册）

测试 seam 声明（预约定，公共接口边界）：
    1. import_game(sim_dir, filename, content) — 服务编排（校验矩阵/去重/改名/探测/粗筛/注册）
    2. sanitize_filename / next_available_filename / slugify — 文件名净化与 id 规则（路径安全）
    3. find_duplicate — SHA-256 去重
    4. probe_config / scan_suspicious — 探测与粗筛矩阵
    5. POST /api/simulators/import wire（TestClient）— 状态码 + 响应形状契约
    6. append_manifest_entry — 见 test_simulator_store.py::TestAppendManifestEntry

全部用例用 tmp_path 合成模拟器目录，不触碰真实 frontend/simulators（共享文件只读）。
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.api.routes import simulators as simulators_route
from backend.app.services import simulator_store
from backend.app.services.simulator_store import (
    MAX_IMPORT_BYTES,
    SimulatorDuplicateError,
    SimulatorImportError,
    find_duplicate,
    import_game,
    next_available_filename,
    probe_config,
    sanitize_filename,
    scan_suspicious,
    slugify,
)

__all__ = [
    "TestValidation",
    "TestSanitizeFilename",
    "TestSlugify",
    "TestDedup",
    "TestRenameConflict",
    "TestProbeConfig",
    "TestScanSuspicious",
    "TestImportGame",
    "TestImportEndpointWire",
]

#: 含 cfg- 三元组的样本 HTML（key-injector 契约：input id 即 config 值）
CFG_TRIPLET_HTML = """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>样本游戏</title></head>
<body>
  <h1>样本游戏</h1>
  <input id="cfg-endpoint" type="text" placeholder="接口地址">
  <input id="cfg-apikey" type="password" placeholder="API Key">
  <input id="cfg-model" type="text" placeholder="模型">
  <button onclick="startGame()">开始</button>
  <script>function startGame() { alert("开始"); }</script>
</body></html>
"""


def _cfg_inputs_html(*ids: str) -> str:
    """按给定 id 集合构造仅含输入框的样本 HTML（探测矩阵用）"""
    inputs = "".join(f'<input id="{i}">' for i in ids)
    return f"<html><body>{inputs}</body></html>"


class TestValidation:
    """校验矩阵：非 .html / 超 5MB / 空文件 → SimulatorImportError（400 文案源）"""

    @pytest.mark.parametrize(
        "filename",
        [
            "game.txt",
            "game.html.exe",
            "game.htm",
            "game",
            "game.HTML.exe",
        ],
    )
    def test_non_html_rejected(self, tmp_path: Path, filename: str) -> None:
        """非 .html（含伪装扩展名）→ 明确报错"""
        with pytest.raises(SimulatorImportError, match="仅支持 .html"):
            import_game(tmp_path / "sim", filename, b"<html>x</html>")

    def test_uppercase_extension_accepted(self, tmp_path: Path) -> None:
        """.HTML 大小写不敏感接受"""
        result = import_game(tmp_path / "sim", "GAME.HTML", b"<html>x</html>")
        assert result.game["file"] == "GAME.html"  # 扩展名归一化为小写

    def test_oversize_rejected(self, tmp_path: Path) -> None:
        """超过 5MB → 明确报错（不落盘）"""
        with pytest.raises(SimulatorImportError, match="5MB"):
            import_game(tmp_path / "sim", "big.html", b"x" * (MAX_IMPORT_BYTES + 1))
        assert not (tmp_path / "sim").exists(), "校验失败不得产生任何落盘副作用"

    def test_exactly_5mb_accepted(self, tmp_path: Path) -> None:
        """恰好 5MB（≤ 上限）→ 接受"""
        result = import_game(tmp_path / "sim", "max.html", b"x" * MAX_IMPORT_BYTES)
        assert result.game["file"] == "max.html"

    def test_empty_content_rejected(self, tmp_path: Path) -> None:
        """空文件 → 明确报错"""
        with pytest.raises(SimulatorImportError, match="空"):
            import_game(tmp_path / "sim", "empty.html", b"")

    def test_blank_filename_rejected(self, tmp_path: Path) -> None:
        """未提供文件名 → 明确报错"""
        with pytest.raises(SimulatorImportError, match="文件名"):
            import_game(tmp_path / "sim", "", b"<html>x</html>")


class TestSanitizeFilename:
    """文件名净化（防目录穿越 + Windows 非法字符）：净化后恒为单段安全文件名"""

    @pytest.mark.parametrize(
        ("raw", "expected"),
        [
            ("..\\evil.html", "evil.html"),
            ("../evil.html", "evil.html"),
            ("a/b/c.html", "c.html"),
            ("a\\b\\c.html", "c.html"),
            ("..\\..\\escape.html", "escape.html"),
            ("bad%name.html", "badname.html"),  # % 在前端 file 判据中整体拒绝，必须剔除
            ("game#1.html", "game1.html"),  # # 是 URL fragment 分隔符（iframe src 截断 → 404），必须剔除
            ("a<b>c:d|e?f*.html", "abcdef.html"),  # Windows 非法字符剔除
            ("  My Game v1.html  ", "My Game v1.html"),
            ("..", "imported-game.html"),  # 纯点 → 保底名
            (".hidden.html", "hidden.html"),  # 隐藏文件点前缀剔除
            # Windows 保留设备名（大小写不敏感、± .html）：加 _ 前缀（_con 非保留名；
            # 大小写保留——净化不重写既有大小写语义，与 "My Game v1" 一致）
            ("con.html", "_con.html"),
            ("con", "_con.html"),
            ("CON.HTML", "_CON.html"),
            ("CoN", "_CoN.html"),
            ("prn.html", "_prn.html"),
            ("PRN", "_PRN.html"),
            ("aux.html", "_aux.html"),
            ("Aux", "_Aux.html"),
            ("nul.html", "_nul.html"),
            ("NUL", "_NUL.html"),
            ("com1.html", "_com1.html"),
            ("COM1", "_COM1.html"),
            ("com9.html", "_com9.html"),
            ("Com9", "_Com9.html"),
            ("lpt1.html", "_lpt1.html"),
            ("LPT1", "_LPT1.html"),
            ("lpt9.html", "_lpt9.html"),
            ("Lpt9", "_Lpt9.html"),
            # 非保留邻近名不受影响（非精确匹配）
            ("mycon.html", "mycon.html"),
            ("com10.html", "com10.html"),
            ("lpt10.html", "lpt10.html"),
            ("console.html", "console.html"),
            ("printer.html", "printer.html"),
            ("auxiliary.html", "auxiliary.html"),
            ("conman.html", "conman.html"),
            # 255 字节上限（含 .html 后缀）：>255 按字节截断 stem，不劈裂多字节字符
            ("a" * 260 + ".html", "a" * 250 + ".html"),  # ASCII 260 字节 → 截 250，总长 255
            ("中" * 90 + ".html", "中" * 83 + ".html"),  # 中文 270 字节 → 截 249（整字符），总长 254
            ("😀" * 63 + ".html", "😀" * 62 + ".html"),  # 4 字节 emoji 252 字节 → 劈裂回退整字符，总长 253
            ("a" * 250 + ".html", "a" * 250 + ".html"),  # 恰好 255 字节 → 不截断
        ],
    )
    def test_sanitize_matrix(self, raw: str, expected: str) -> None:
        """净化矩阵：穿越/非法字符/空名/保留设备名/超长名全部收敛为安全名"""
        assert sanitize_filename(raw) == expected

    def test_sanitize_never_contains_forbidden_chars(self) -> None:
        """不变量：净化结果不含 / \\ % # 与 Windows 非法字符（与前端 isValidSimulatorFile 兼容）"""
        for raw in ["..\\..\\x.html", "a/b%c<d.html", "game#1.html", "..", ".", ""]:
            name = sanitize_filename(raw)
            assert "/" not in name and "\\" not in name and "%" not in name and "#" not in name

    def test_sanitize_reserved_name_writable(self, tmp_path: Path) -> None:
        """保留设备名净化结果可真实落盘（Windows 上 con.html 写盘 OSError，_con.html 可写）"""
        safe = sanitize_filename("con.html")
        assert safe == "_con.html"
        target = tmp_path / safe
        target.write_text("<html>x</html>", encoding="utf-8")
        assert target.read_text(encoding="utf-8") == "<html>x</html>"


class TestSlugify:
    """id slug 规则（定版，工单 03/04 共享）：仅保留 [a-z0-9-]、折叠分隔符、回退 imported-game"""

    @pytest.mark.parametrize(
        ("stem", "expected"),
        [
            ("My Game v1", "my-game-v1"),
            ("my--game", "my-game"),
            ("--leading--", "leading"),
            ("  spaced  ", "spaced"),
            ("v3", "v3"),
            ("游戏", "imported-game"),  # 无 ASCII 回退
            ("", "imported-game"),
            ("A__B--C", "a-b-c"),
        ],
    )
    def test_slug_matrix(self, stem: str, expected: str) -> None:
        """slug 矩阵：大小写折叠 / 分隔符折叠 / 空回退"""
        assert slugify(stem) == expected


class TestDedup:
    """SHA-256 内容去重：命中现存文件（含内置种子内容）→ 409 语义异常"""

    def test_duplicate_second_import(self, tmp_path: Path) -> None:
        """同一内容二次导入 → SimulatorDuplicateError 且文案含「已存在」"""
        sim = tmp_path / "sim"
        content = "<html>同一款游戏</html>".encode("utf-8")
        import_game(sim, "game.html", content)
        with pytest.raises(SimulatorDuplicateError, match="已存在"):
            import_game(sim, "game.html", content)

    def test_duplicate_against_existing_file(self, tmp_path: Path) -> None:
        """与现存文件（如种子内置）内容相同 → 报错并指明命中文件"""
        sim = tmp_path / "sim"
        sim.mkdir(parents=True)
        (sim / "内置游戏.html").write_bytes(b"<html>seed</html>")
        with pytest.raises(SimulatorDuplicateError, match="内置游戏.html"):
            import_game(sim, "other.html", b"<html>seed</html>")

    def test_duplicate_ignores_non_html_files(self, tmp_path: Path) -> None:
        """去重仅比对 *.html：与现存 .css（per-game 覆盖层）字节相同 → 不命中 409，正常导入"""
        sim = tmp_path / "sim"
        sim.mkdir(parents=True)
        css_content = b"body { color: red; }"
        (sim / "tricky.css").write_bytes(css_content)
        result = import_game(sim, "tricky.html", css_content)
        assert result.game["file"] == "tricky.html"
        assert (sim / "tricky.html").read_bytes() == css_content

    def test_different_content_not_duplicate(self, tmp_path: Path) -> None:
        """同名不同内容 → 非重复（走改名路径）"""
        sim = tmp_path / "sim"
        import_game(sim, "game.html", "<html>内容A</html>".encode("utf-8"))
        result = import_game(sim, "game.html", "<html>内容B</html>".encode("utf-8"))
        assert result.renamed is True


class TestRenameConflict:
    """文件名冲突自动改名：xxx-2.html 递增 + Windows 大小写不敏感"""

    def test_rename_increments(self, tmp_path: Path) -> None:
        """同名言 → xxx-2.html → xxx-3.html 递增落盘"""
        sim = tmp_path / "sim"
        import_game(sim, "game.html", b"<html>A</html>")
        r2 = import_game(sim, "game.html", b"<html>B</html>")
        r3 = import_game(sim, "game.html", b"<html>C</html>")
        assert r2.renamed is True and r2.game["file"] == "game-2.html"
        assert r3.renamed is True and r3.game["file"] == "game-3.html"
        assert sorted(p.name for p in sim.iterdir() if p.name != "manifest.json") == [
            "game-2.html",
            "game-3.html",
            "game.html",
        ]

    def test_rename_case_insensitive(self, tmp_path: Path) -> None:
        """现存 GAME.HTML → 上传 game.html 视为同名冲突（Windows 大小写不敏感定版）"""
        sim = tmp_path / "sim"
        import_game(sim, "GAME.HTML", b"<html>A</html>")
        result = import_game(sim, "game.html", b"<html>B</html>")
        assert result.renamed is True
        assert result.game["file"] == "game-2.html"

    def test_first_import_no_rename(self, tmp_path: Path) -> None:
        """首次导入无冲突 → renamed False 且原名落盘"""
        result = import_game(tmp_path / "sim", "fresh.html", b"<html>x</html>")
        assert result.renamed is False
        assert result.game["file"] == "fresh.html"

    def test_next_available_filename_returns_desired_when_free(self, tmp_path: Path) -> None:
        """next_available_filename：无冲突直接返回原名"""
        sim = tmp_path / "sim"
        assert next_available_filename(sim, "a.html") == "a.html"


class TestProbeConfig:
    """元数据探测矩阵：cfg- 三元组齐全 → ai + config；否则 local 无 config（条目级降级）"""

    def test_full_triplet_detected(self) -> None:
        """cfg-endpoint/cfg-apikey/cfg-model 三输入框齐全 → type=ai + config 三元组"""
        game_type, config = probe_config(CFG_TRIPLET_HTML)
        assert game_type == "ai"
        assert config == {
            "endpoint": "cfg-endpoint",
            "apikey": "cfg-apikey",
            "model": "cfg-model",
        }

    def test_triplet_with_extra_cfg_ids(self) -> None:
        """三元组 + 额外 cfg- 输入框 → 仍为 ai"""
        game_type, config = probe_config(_cfg_inputs_html("cfg-endpoint", "cfg-apikey", "cfg-model", "cfg-extra"))
        assert game_type == "ai"
        assert config is not None

    @pytest.mark.parametrize(
        "ids",
        [
            ("cfg-endpoint", "cfg-model"),  # 缺 apikey
            ("cfg-endpoint",),  # 只有一项
            ("cfg-foo", "cfg-bar"),  # 全非三元组
            (),  # 无任何输入框
        ],
    )
    def test_incomplete_triplet_degrades_to_local(self, ids: tuple[str, ...]) -> None:
        """三元组不完整 → type=local 且不保留部分 config（降级，记录判断）"""
        game_type, config = probe_config(_cfg_inputs_html(*ids))
        assert game_type == "local"
        assert config is None

    def test_non_cfg_ids_ignored(self) -> None:
        """普通 input（无 cfg- 前缀）→ 不参与探测"""
        game_type, config = probe_config(_cfg_inputs_html("username", "password"))
        assert game_type == "local"
        assert config is None

    def test_id_whitespace_trimmed(self) -> None:
        """id 首尾空白剔除后仍命中三元组"""
        html = '<input id=" cfg-endpoint "><input id="cfg-apikey"><input id="cfg-model">'
        game_type, config = probe_config(html)
        assert game_type == "ai"
        assert config is not None

    def test_id_case_sensitive(self) -> None:
        """id 大小写敏感（key-injector 按精确 id 取元素）：大写三元组 → local"""
        game_type, config = probe_config(_cfg_inputs_html("CFG-ENDPOINT", "CFG-APIKEY", "CFG-MODEL"))
        assert game_type == "local"
        assert config is None

    def test_script_and_comment_content_ignored(self) -> None:
        """script 字符串 / 注释内的伪 input 不参与探测（HTMLParser 语义实测）"""
        html = (
            '<script>var x = "<input id=cfg-endpoint>";</script>'
            '<!-- <input id="cfg-apikey"> -->'
            '<input id="cfg-model">'
        )
        game_type, config = probe_config(html)
        assert game_type == "local"


class TestScanSuspicious:
    """恶意模式粗筛矩阵：命中收集键集返回，绝不拦截"""

    @pytest.mark.parametrize(
        ("html", "expected"),
        [
            ('<script>eval("1+1")</script>', ["eval"]),
            ("<script>window.eval(code)</script>", ["eval"]),
            ("<script>var x = document.cookie;</script>", ["document.cookie"]),
            ('<script>fetch("http://evil.com/data")</script>', ["cross-origin-fetch"]),
            ("<script>fetch('https://evil.com')</script>", ["cross-origin-fetch"]),
            ("<script>fetch(`//evil.com/x`)</script>", ["cross-origin-fetch"]),
            (
                '<script>eval(document.cookie); fetch("http://evil.com")</script>',
                ["cross-origin-fetch", "document.cookie", "eval"],
            ),
        ],
    )
    def test_suspicious_patterns_hit(self, html: str, expected: list[str]) -> None:
        """命中矩阵：返回对应键集（排序确定）"""
        assert scan_suspicious(html) == expected

    @pytest.mark.parametrize(
        "html",
        [
            "<html><body>完全正常的游戏</body></html>",
            '<script>fetch("/api/data")</script>',  # 同源相对路径不命中
            '<script>fetch("data:text/html,x")</script>',  # data: 协议不命中
            "<script>var evaluate = 1; evaluate();</script>",  # evaluate 非 eval(
            "<script>document.title = 'cookie';</script>",  # 属性名含 cookie 不命中
            '<script>fetch ( "/x" )</script>',  # 同源不命中
        ],
    )
    def test_clean_html_no_warnings(self, html: str) -> None:
        """干净样本 / 同源引用 → 空键集（粗筛误报不拦截）"""
        assert scan_suspicious(html) == []


class TestImportGame:
    """导入编排：落盘 + manifest 注册 + 响应形状（服务层）"""

    def test_ai_game_imported_with_config(self, tmp_path: Path) -> None:
        """含 cfg 三元组的样本 → 落盘 + manifest 条目（type=ai + config + source=imported）"""
        sim = tmp_path / "sim"
        content = CFG_TRIPLET_HTML.encode("utf-8")
        result = import_game(sim, "样本游戏.html", content)
        assert result.renamed is False
        assert result.warnings == []
        assert result.game == {
            "id": "imported-game",  # 文件名干「样本游戏」无 ASCII → slug 回退 imported-game
            "file": "样本游戏.html",
            "name": "样本游戏",
            "type": "ai",
            "config": {
                "endpoint": "cfg-endpoint",
                "apikey": "cfg-apikey",
                "model": "cfg-model",
            },
            "source": "imported",
        }
        assert (sim / "样本游戏.html").read_bytes() == content, "文件字节与上传内容一致"

        manifest = json.loads((sim / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["version"] == 2
        assert manifest["simulators"][0] == result.game

    def test_local_game_no_config(self, tmp_path: Path) -> None:
        """无 cfg 输入框 → type=local 且无 config 字段"""
        sim = tmp_path / "sim"
        result = import_game(sim, "local.html", "<html>纯本地</html>".encode("utf-8"))
        assert result.game["type"] == "local"
        assert "config" not in result.game

    def test_suspicious_game_warns_but_imports(self, tmp_path: Path) -> None:
        """含恶意模式 → warnings 非空且导入成功（不拦截）"""
        sim = tmp_path / "sim"
        content = b'<script>eval(document.cookie); fetch("http://evil.com")</script>'
        result = import_game(sim, "risky.html", content)
        assert result.warnings == ["cross-origin-fetch", "document.cookie", "eval"]
        assert (sim / "risky.html").exists()
        assert result.game["id"] == "risky"

    def test_id_uniquified_when_slug_collides(self, tmp_path: Path) -> None:
        """slug 冲突（中文名干无 ASCII）→ id 按 -2/-3 唯一化（manifest id 恒唯一）"""
        sim = tmp_path / "sim"
        r1 = import_game(sim, "游戏一.html", b"<html>A</html>")
        r2 = import_game(sim, "游戏二.html", b"<html>B</html>")
        r3 = import_game(sim, "游戏三.html", b"<html>C</html>")
        assert r1.game["id"] == "imported-game"
        assert r2.game["id"] == "imported-game-2"
        assert r3.game["id"] == "imported-game-3"
        manifest = json.loads((sim / "manifest.json").read_text(encoding="utf-8"))
        ids = [g["id"] for g in manifest["simulators"]]
        assert len(ids) == len(set(ids))

    def test_manifest_entries_accumulate(self, tmp_path: Path) -> None:
        """多次导入 → manifest 逐条追加且既有条目不动"""
        sim = tmp_path / "sim"
        import_game(sim, "a.html", b"<html>A</html>")
        import_game(sim, "b.html", b"<html>B</html>")
        manifest = json.loads((sim / "manifest.json").read_text(encoding="utf-8"))
        assert [g["id"] for g in manifest["simulators"]] == ["a", "b"]
        assert all(g.get("source") == "imported" for g in manifest["simulators"])

    def test_import_after_corrupt_manifest_heals(self, tmp_path: Path) -> None:
        """manifest 损坏时导入 → 自愈重建 + 注册成功（不崩溃）"""
        sim = tmp_path / "sim"
        sim.mkdir(parents=True)
        (sim / "seed.html").write_bytes(b"<html>seed</html>")
        (sim / "manifest.json").write_text("{bad", encoding="utf-8")
        result = import_game(sim, "new.html", b"<html>new</html>")
        assert result.game["id"] == "new"
        manifest = json.loads((sim / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["version"] == 2
        assert [g["id"] for g in manifest["simulators"]] == ["seed", "new"]

    def test_manifest_failure_rolls_back_file(
        self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """manifest 注册失败 → 已落盘文件回滚（不遗留孤儿游戏文件，异常继续传播）"""
        sim = tmp_path / "sim"
        calls = {"n": 0}
        real_write = simulator_store.write_manifest

        def boom(*args: object, **kwargs: object) -> None:
            # 第 1 次调用（自愈落盘）委托真实实现；第 2 次（append 注册）失败——
            # 保证文件已落盘后再触发回滚路径，避免断言恒真
            calls["n"] += 1
            if calls["n"] >= 2:
                raise OSError("磁盘故障（模拟）")
            real_write(*args, **kwargs)

        monkeypatch.setattr(simulator_store, "write_manifest", boom)
        with pytest.raises(OSError):
            import_game(sim, "game.html", b"<html>x</html>")
        assert not (sim / "game.html").exists(), "注册失败必须回滚已落盘文件"
        assert (sim / "manifest.json").exists(), "自愈落盘已成功，仅注册失败"

    def test_non_utf8_content_still_probes(self, tmp_path: Path) -> None:
        """非 UTF-8 字节内容 → 容错解码（errors=replace）后探测仍工作，落盘字节原样"""
        content = (
            b'<html>\xff\xfe<input id="cfg-endpoint"><input id="cfg-apikey">'
            b'<input id="cfg-model"></html>'
        )
        result = import_game(tmp_path / "sim", "gbk.html", content)
        assert result.game["type"] == "ai"
        assert (tmp_path / "sim" / "gbk.html").read_bytes() == content

    def test_unwritable_dir_raises_clear_oserror(self, tmp_path: Path) -> None:
        """数据目录不可写（父路径被文件占位）→ OSError 明确传播（不静默吞掉）"""
        blocker = tmp_path / "blocker"
        blocker.write_text("x", encoding="utf-8")
        with pytest.raises(OSError):
            import_game(blocker / "sim", "game.html", b"<html>x</html>")
        assert not (blocker / "sim" / "game.html").exists()


class TestImportEndpointWire:
    """路由 wire（TestClient）：状态码 + 响应形状契约（spec T-02 决策 4）"""

    @pytest.fixture
    def import_app(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> FastAPI:
        """最小应用（仅导入路由）；CONVER_DATA_DIR 指向临时目录（请求期解析，可 monkeypatch）"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        app = FastAPI()
        app.include_router(simulators_route.router)
        return app

    def _post(self, client: TestClient, filename: str, content: bytes) -> object:
        return client.post(
            "/api/simulators/import",
            files={"file": (filename, content, "text/html")},
        )

    def test_happy_path_response_shape(self, import_app: FastAPI, tmp_path: Path) -> None:
        """合法 .html → 200 + 契约形状 {ok, game{id,file,name,type,config}, renamed, warnings}"""
        with TestClient(import_app) as client:
            resp = self._post(client, "我的游戏.html", CFG_TRIPLET_HTML.encode("utf-8"))
        assert resp.status_code == 200
        body = resp.json()
        assert body == {
            "ok": True,
            "game": {
                "id": "imported-game",
                "file": "我的游戏.html",
                "name": "我的游戏",
                "type": "ai",
                "config": {
                    "endpoint": "cfg-endpoint",
                    "apikey": "cfg-apikey",
                    "model": "cfg-model",
                },
                "source": "imported",
            },
            "renamed": False,
            "warnings": [],
        }
        # 数据目录（CONVER_DATA_DIR/simulators）落盘 + manifest 追加
        sim = tmp_path / "simulators"
        assert (sim / "我的游戏.html").is_file()
        manifest = json.loads((sim / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["simulators"][0]["source"] == "imported"

    def test_validation_400_matrix(self, import_app: FastAPI) -> None:
        """非 .html / 空文件 → 400 明确文案（超 5MB 单列）"""
        with TestClient(import_app) as client:
            assert self._post(client, "game.txt", b"<html>x</html>").status_code == 400
            assert self._post(client, "empty.html", b"").status_code == 400
            resp = self._post(client, "big.html", b"x" * (MAX_IMPORT_BYTES + 1))
        assert resp.status_code == 400
        assert "5MB" in resp.json()["detail"]

    def test_duplicate_409_with_message(self, import_app: FastAPI) -> None:
        """重复导入 → 409 且 detail 含「已存在」"""
        content = "<html>重复内容</html>".encode("utf-8")
        with TestClient(import_app) as client:
            assert self._post(client, "dup.html", content).status_code == 200
            resp = self._post(client, "dup.html", content)
        assert resp.status_code == 409
        assert "已存在" in resp.json()["detail"]

    def test_renamed_flag(self, import_app: FastAPI) -> None:
        """同名不同内容 → renamed:true + file 为改名后文件名"""
        with TestClient(import_app) as client:
            self._post(client, "game.html", b"<html>A</html>")
            resp = self._post(client, "game.html", b"<html>B</html>")
        assert resp.status_code == 200
        body = resp.json()
        assert body["renamed"] is True
        assert body["game"]["file"] == "game-2.html"

    def test_warnings_not_blocking(self, import_app: FastAPI) -> None:
        """恶意模式样本 → 200 + warnings 键集（不拦截）"""
        content = b'<script>eval("x"); document.cookie; fetch("http://evil.com")</script>'
        with TestClient(import_app) as client:
            resp = self._post(client, "risky.html", content)
        assert resp.status_code == 200
        assert resp.json()["warnings"] == ["cross-origin-fetch", "document.cookie", "eval"]

    def test_missing_file_field_422(self, import_app: FastAPI) -> None:
        """缺 file 字段 → 422（FastAPI 校验）"""
        with TestClient(import_app) as client:
            resp = client.post("/api/simulators/import", files={})
        assert resp.status_code == 422

    def test_local_game_no_config_field(self, import_app: FastAPI) -> None:
        """无 cfg 样本 → 200 且 game 无 config 字段（条目级降级）"""
        with TestClient(import_app) as client:
            resp = self._post(client, "plain.html", "<html>纯本地</html>".encode("utf-8"))
        assert resp.status_code == 200
        assert "config" not in resp.json()["game"]
        assert resp.json()["game"]["type"] == "local"
