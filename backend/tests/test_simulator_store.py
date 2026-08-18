"""
T-02 单元测试 — 模拟器数据存储（backend/app/services/simulator_store.py）

首启种子契约（spec T-02 决策 3 + 工单 02 验收）：

    1. 种子标记 = 数据目录 simulators 的 manifest.json 存在（幂等；不做逐文件自愈，
       用户删了就是删了——用户管理优先）。
    2. 全新目录：从内置目录整目录拷贝（html + manifest 字节一致），返回 True。
    3. 二次启动 / 半损坏（manifest 在、文件缺）：返回 False，绝不触碰已有内容。
    4. 半拷无 manifest：按标记语义整体重种（manifest 最后落盘，标记最晚生效）。
    5. 种子源缺失（打包态文件缺失）：降级不崩溃（返回 False，不建目录）。
    6. 数据目录不可写：明确报错（不静默吞掉，启动期可闻）。

manifest 读写工具（工单 02 声明，工单 03 导入族继续扩展）：
    原子写 = 同目录临时文件 + os.replace（ensure_ascii=False 中文保真）；
    读 = 解析 dict；缺失抛 FileNotFoundError。

测试 seam：ensure_seeded(builtin_dir, target_dir) 路径参数化，全部用例用
tmp_path 合成内置/数据目录，不触碰真实 frontend/simulators（共享文件只读）。
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from backend.app.services import simulator_store

__all__ = [
    "TestEnsureSeeded",
    "TestManifestTools",
]

#: 种子矩阵内置目录最小样本（html + manifest；真实 22 款由冒烟脚本覆盖）
BUILTIN_FILES: dict[str, str] = {
    "manifest.json": json.dumps(
        {
            "version": 2,
            "simulators": [
                {
                    "id": "life-sim",
                    "file": "人生模拟器v3.html",
                    "name": "人生模拟器 v3",
                    "type": "ai",
                }
            ],
        },
        ensure_ascii=False,
        indent=2,
    ),
    "人生模拟器v3.html": "<html><body>人生模拟器 v3</body></html>",
    "仙途.html": "<html><body>仙途</body></html>",
}


def _make_builtin(tmp_path: Path, files: dict[str, str] | None = None) -> Path:
    """在 tmp_path 下构造内置种子源目录（仅文件，与 frontend/simulators 形态一致）"""
    d = tmp_path / "builtin"
    d.mkdir()
    for name, content in (files if files is not None else BUILTIN_FILES).items():
        (d / name).write_text(content, encoding="utf-8")
    return d


class TestEnsureSeeded:
    """种子矩阵：全新目录 / 二次启动幂等 / 半损坏 / 种子源缺失 / 不可写"""

    def test_fresh_dir_seeds_all_files(
        self, tmp_path: Path
    ) -> None:
        """全新数据目录 → 拷贝内置全部文件（html + manifest 字节一致），返回 True"""
        builtin = _make_builtin(tmp_path)
        target = tmp_path / "out" / "simulators"
        assert simulator_store.ensure_seeded(builtin, target) is True
        assert sorted(p.name for p in target.iterdir()) == sorted(BUILTIN_FILES)
        for name, content in BUILTIN_FILES.items():
            assert (target / name).read_text(encoding="utf-8") == content
        # manifest 合法 JSON（可被前端 parseManifest 读取）
        manifest = json.loads((target / "manifest.json").read_text(encoding="utf-8"))
        assert manifest["version"] == 2
        assert len(manifest["simulators"]) == 1

    def test_second_call_idempotent_noop(self, tmp_path: Path) -> None:
        """二次启动：返回 False 且不重复拷贝（文件内容逐字节不变）"""
        builtin = _make_builtin(tmp_path)
        target = tmp_path / "out" / "simulators"
        assert simulator_store.ensure_seeded(builtin, target) is True
        before = {
            p.name: p.read_text(encoding="utf-8")
            for p in target.iterdir()
        }
        assert simulator_store.ensure_seeded(builtin, target) is False
        after = {p.name: p.read_text(encoding="utf-8") for p in target.iterdir()}
        assert after == before
        assert sorted(after) == sorted(BUILTIN_FILES)

    def test_user_managed_dir_untouched(self, tmp_path: Path) -> None:
        """用户已管理（manifest 存在 + 追加用户游戏 + 改动 manifest）→ 绝不自动改动"""
        builtin = _make_builtin(tmp_path)
        target = tmp_path / "out" / "simulators"
        assert simulator_store.ensure_seeded(builtin, target) is True
        # 用户删掉一款内置、加入一款自加游戏、并向 manifest 追加条目
        (target / "仙途.html").unlink()
        user_game = "<html>用户自加</html>"
        (target / "user-game.html").write_text(user_game, encoding="utf-8")
        manifest_path = target / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["simulators"].append({"id": "user-game", "file": "user-game.html"})
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False), encoding="utf-8")

        assert simulator_store.ensure_seeded(builtin, target) is False
        assert not (target / "仙途.html").exists(), "用户删除的内置不得被种子恢复"
        assert (target / "user-game.html").read_text(encoding="utf-8") == user_game
        current = json.loads(manifest_path.read_text(encoding="utf-8"))
        assert [g["id"] for g in current["simulators"]] == ["life-sim", "user-game"]

    def test_half_corrupt_manifest_exists_no_repair(self, tmp_path: Path) -> None:
        """半损坏（manifest 在、部分 html 缺）：不炸、不覆盖、不逐文件自愈"""
        builtin = _make_builtin(tmp_path)
        target = tmp_path / "out" / "simulators"
        assert simulator_store.ensure_seeded(builtin, target) is True
        (target / "人生模拟器v3.html").unlink()  # 模拟半拷/用户删除缺文件

        assert simulator_store.ensure_seeded(builtin, target) is False
        assert not (target / "人生模拟器v3.html").exists()
        assert (target / "仙途.html").exists()

    def test_partial_copy_without_manifest_reseeds(self, tmp_path: Path) -> None:
        """半拷无 manifest（中断于 manifest 落盘前）→ 按标记语义整体重种"""
        builtin = _make_builtin(tmp_path)
        target = tmp_path / "out" / "simulators"
        target.mkdir(parents=True)
        (target / "仙途.html").write_text("半拷残留", encoding="utf-8")

        assert simulator_store.ensure_seeded(builtin, target) is True
        assert (target / "manifest.json").exists()
        assert (target / "人生模拟器v3.html").read_text(encoding="utf-8") == (
            BUILTIN_FILES["人生模拟器v3.html"]
        )

    def test_builtin_missing_degrades(self, tmp_path: Path) -> None:
        """种子源缺失（打包态文件缺失）→ 降级不崩溃：返回 False 且不建目标目录"""
        missing = tmp_path / "no-such-builtin"
        target = tmp_path / "out" / "simulators"
        assert simulator_store.ensure_seeded(missing, target) is False
        assert not target.exists()

    def test_target_unwritable_raises_clear_error(self, tmp_path: Path) -> None:
        """数据目录不可写（父路径被文件占位）→ 明确报错，不静默吞掉"""
        builtin = _make_builtin(tmp_path)
        blocker = tmp_path / "blocker"
        blocker.write_text("x", encoding="utf-8")
        target = blocker / "simulators"  # 父路径是文件 → mkdir 必败（跨平台确定）
        with pytest.raises(OSError, match="模拟器数据目录不可用"):
            simulator_store.ensure_seeded(builtin, target)


class TestManifestTools:
    """manifest 读取 / 原子写工具（工单 03 导入族继续扩展的底座）"""

    def test_read_manifest_parses_dict(self, tmp_path: Path) -> None:
        """read_manifest → 解析后的 dict"""
        builtin = _make_builtin(tmp_path)
        manifest = simulator_store.read_manifest(builtin)
        assert manifest["version"] == 2
        assert manifest["simulators"][0]["id"] == "life-sim"

    def test_read_manifest_missing_raises(self, tmp_path: Path) -> None:
        """manifest 不存在 → FileNotFoundError（调用方决定降级/报错）"""
        empty = tmp_path / "empty"
        empty.mkdir()
        with pytest.raises(FileNotFoundError):
            simulator_store.read_manifest(empty)

    def test_write_manifest_roundtrip_preserves_chinese(self, tmp_path: Path) -> None:
        """原子写往返：中文保真（ensure_ascii=False）+ version 字段保持 + 可再读回"""
        sim_dir = tmp_path / "simulators"
        data = {
            "version": 2,
            "simulators": [
                {"id": "life-sim", "file": "人生模拟器v3.html", "name": "人生模拟器 v3"}
            ],
        }
        simulator_store.write_manifest(sim_dir, data)
        raw = (sim_dir / "manifest.json").read_text(encoding="utf-8")
        assert "人生模拟器 v3" in raw, "manifest 必须以 UTF-8 明文保存中文（ensure_ascii=False）"
        assert json.loads(raw) == data
        assert simulator_store.read_manifest(sim_dir) == data

    def test_write_manifest_atomic_no_temp_leftover(self, tmp_path: Path) -> None:
        """原子写：完成后目录仅 manifest.json，无临时文件残留"""
        sim_dir = tmp_path / "simulators"
        simulator_store.write_manifest(sim_dir, {"version": 2, "simulators": []})
        assert sorted(p.name for p in sim_dir.iterdir()) == ["manifest.json"]

    def test_write_manifest_creates_dir(self, tmp_path: Path) -> None:
        """目标目录不存在 → 原子写自动创建（parents）"""
        sim_dir = tmp_path / "a" / "b" / "simulators"
        simulator_store.write_manifest(sim_dir, {"version": 2, "simulators": []})
        assert (sim_dir / "manifest.json").is_file()
