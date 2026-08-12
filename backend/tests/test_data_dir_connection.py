"""
ARC9-T04 连接级消费者测试（契约表 v2；Rust 侧镜像见 src-tauri/tests/server_test.rs）

与 test_data_dir.py 的字符串级契约表不同，本文件做**连接级**验证：以与壳注入 DATABASE_URL
完全相同的消费方式（database.py 移除 `+aiosqlite` 前缀后 `create_engine("sqlite:///…")`）
连接**真实临时数据目录**，断言建表/写入/读回成功——契约表的最终裁判是真实消费者，
不是双端字符串镜像（契约表 v1 双端互证同源，从未对真实消费者做连接级验证，
正是期末四轴审核 Falsify 阻断项的根源）。

契约表 v2 编码集 = {`?` → `%3F`}（唯一 URL 解析器实际分隔符，防御性编码）：
SQLAlchemy sqlite 方言对 DATABASE_URL **零解码**，`%20`/`%23` 等被当字面文件名——
契约表 v1 的全量百分号编码（`urllib.parse.quote(s, safe="/:")`）在真实消费者处报
`OperationalError: unable to open database file`；基线实测空格/中文/`#`/`%` 原样直连可用。
`?` 为 Windows 非法文件名（真实数据目录不可达），编码仅为防御，故不对应解码语义。
"""

from __future__ import annotations

from pathlib import Path
from urllib.parse import quote

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import OperationalError

__all__ = [
    "TestConnectionLevelConsumer",
]


def _url_v2(db_path: Path) -> str:
    """契约表 v2 参考编码（镜像 Rust `encode_url_path`）：仅 `?` → `%3F`，其余原样。

    反斜杠转正斜杠 = 壳侧 database_url 的归一化步骤，与编码互不影响。
    """
    return "sqlite:///" + str(db_path).replace("\\", "/").replace("?", "%3F")


class TestConnectionLevelConsumer:
    """契约表 v2 连接级验证：编码后 URL 必须能被 SQLAlchemy 真实消费（建表/读写）。"""

    @pytest.mark.parametrize(
        ("dir_name",),
        [
            ("My Apps",),  # 空格
            ("数据目录",),  # 中文
            ("Conver 数据#目录My Apps%v1",),  # 空格 + 中文 + # + %
            ("100%25数据",),  # 形似十六进制转义的 %25（零解码消费者不得解码）
            ("plain_ascii",),  # 纯 ASCII 对照组
        ],
    )
    def test_encoded_url_connects_and_reads_back(
        self, tmp_path: pytest.TempPathFactory, dir_name: str
    ) -> None:
        """v2 编码 URL 连接真实数据目录：建表/写入/读回成功，库文件落在真实路径。

        若编码把空格/中文/#/% 变成 `%XX` 字面量（契约表 v1 口径），
        sqlite 方言零解码 → 打不开真实文件（OperationalError），本用例红。
        """
        db = tmp_path / dir_name / "conver_system.db"
        db.parent.mkdir(parents=True)
        engine = create_engine(_url_v2(db))
        with engine.connect() as conn:
            conn.execute(text("CREATE TABLE probe (x INTEGER)"))
            conn.execute(text("INSERT INTO probe (x) VALUES (42)"))
            row = conn.execute(text("SELECT x FROM probe")).scalar()
            conn.commit()
        assert row == 42
        assert db.is_file(), "库文件必须落在真实数据目录内（不得是字面 %XX 名路径）"

    def test_full_percent_encoding_breaks_real_consumer(self, tmp_path) -> None:
        """防回归（期末审核 Falsify 阻断项）：契约表 v1 的全量编码必须不再被采用。

        SQLAlchemy sqlite 方言零解码，`%20` 等被当字面文件名 → 真实数据目录打不开
        （OperationalError: unable to open database file）。本用例与上面正向用例
        一起锁定「v2 编码集 = {?}」这一契约：过编码 = 打不开，欠编码 = 连错文件。
        """
        db = tmp_path / "Conver 数据#目录My Apps%v1" / "conver_system.db"
        db.parent.mkdir(parents=True)
        url = "sqlite:///" + quote(str(db).replace("\\", "/"), safe="/:")
        with pytest.raises(OperationalError):
            create_engine(url).connect()

    def test_literal_question_mark_truncates_url(self) -> None:
        """`?` 是 SQLAlchemy URL 解析器的实际分隔符：字面 `?` 使数据库路径在 `?` 处
        截断（静默连到错误文件）——这正是 `?` 保留编码（→ `%3F`）的原因；
        `?` 为 Windows 非法文件名，含 `?` 的真实数据目录不可达，故编码仅为防御。
        """
        parsed = make_url("sqlite:///C:/some/dir/My?Apps/conver_system.db")
        assert parsed.database == "C:/some/dir/My"
