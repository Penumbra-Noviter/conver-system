"""
CG-3 图片任务 + 剧情回顾时间线 — 契约测试

覆盖（验收语义契约，spec §CG-3）：
    1. 任务生命周期：提交 pending → run 成功（succeeded + 出图入资产库）/
       失败（failed + error，不破坏对话——不外抛）
    2. 轮询：get_image_task 返回三态；未知 → 404
    3. 出图锚消息归属守卫（跨会话 404）
    4. 剧情回顾时间线排序：消息 created_at 升序 + 同消息多图入库序（cg.id 升序）
       + 仅已解锁 + 无锚消息按 cg.created_at 参与排序
    5. 路由：POST /api/images/tasks（后台任务注入 no-op）、GET task、GET cg-timeline

依赖：pytest + SQLite 内存库（conftest.db_session）；run 用 local 后端（零网络），
CONVER_DATA_DIR 指到 tmp_path；失败路径用 a1111（无 base_url 构造即错）。
"""

from __future__ import annotations

import json

import pytest
from sqlalchemy.orm import Session

from backend.app.api.routes import images as images_route
from backend.app.models.cg_image import CgImage
from backend.app.models.image_task import ImageTask
from backend.app.models.message import Message, Role
from backend.app.schemas.conversation import ConversationCreate
from backend.app.schemas.image_task import ImageTaskCreate
from backend.app.services import conversation as conversation_service
from backend.app.services import gallery as gallery_service
from backend.app.services import message as message_service
from backend.app.services import setting as setting_service
from backend.app.services.exceptions import (
    ConversationNotFoundError,
    ImageTaskNotFoundError,
    MessageNotFoundError,
)
from backend.app.services.image import tasks as tasks_service

__all__: list[str] = []


# ── 测试基础设施 ──


@pytest.fixture()
def cg_dir_tmp(monkeypatch: pytest.MonkeyPatch, tmp_path) -> None:
    """数据目录指到 tmp_path（CG 落盘零污染）"""
    monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))


def _create_character(db: Session, name: str = "测试角色") -> int:
    from backend.app.models.character import Character

    char = Character(name=name, personality="冷静、睿智")
    db.add(char)
    db.commit()
    db.refresh(char)
    return char.id


def _create_conversation(db: Session, character_id: int):
    return conversation_service.create_conversation(
        db,
        ConversationCreate(character_id=character_id, model_provider="claude", model_name="claude-test"),
    )


def _add_message(db: Session, conversation_id: int, content: str = "问") -> int:
    return message_service.create_message(db, conversation_id, Role.USER, content).id


def _set_message_created_at(db: Session, message_id: int, dt) -> None:
    """显式设置消息 created_at（秒精度默认 now 会同时刻，排序测试须可控）"""
    db.query(Message).filter(Message.id == message_id).update({"created_at": dt})
    db.commit()


def _configure_image_backend(db: Session, provider: str, base_url: str = "") -> None:
    """写 settings 图片后端配置（MD-3）"""
    setting_service.set_many(db, {"image_provider": provider, "image_base_url": base_url})


def _create_task(
    db: Session,
    conv,
    *,
    prompt: str = "一只猫",
    provider: str = "local",
    message_id: int | None = None,
) -> ImageTask:
    return tasks_service.create_image_task(
        db,
        conversation_id=conv.id,
        character_id=conv.character_id,
        prompt=prompt,
        provider=provider,
        message_id=message_id,
    )


# ── 1. 任务创建 / 轮询 ──


class TestImageTaskCreateGet:
    """提交 + 轮询 + 404 守卫"""

    def test_create_pending_with_params_json(self, db_session: Session) -> None:
        """提交 → status=pending，params 为 JSON（ImageGenParams 往返）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)

        task = _create_task(db_session, conv, prompt="雪夜客栈")

        assert task.status == "pending"
        assert task.provider == "local"
        assert task.character_id == char_id
        assert task.conversation_id == conv.id
        params = json.loads(task.params)
        assert params["prompt"] == "雪夜客栈"
        assert params["width"] == 512

    def test_create_unknown_conversation_404(self, db_session: Session) -> None:
        """会话不存在 → ConversationNotFoundError"""
        with pytest.raises(ConversationNotFoundError):
            tasks_service.create_image_task(
                db_session, conversation_id=99999, character_id=1, prompt="猫"
            )

    def test_create_anchor_message_not_in_conversation_404(self, db_session: Session) -> None:
        """锚消息跨会话 → MessageNotFoundError（不得错挂）"""
        char_id = _create_character(db_session)
        conv_a = _create_conversation(db_session, char_id)
        conv_b = _create_conversation(db_session, char_id)
        msg_a = _add_message(db_session, conv_a.id)

        with pytest.raises(MessageNotFoundError):
            tasks_service.create_image_task(
                db_session, conversation_id=conv_b.id, character_id=char_id,
                prompt="猫", message_id=msg_a,
            )

    def test_get_task_returns_state(self, db_session: Session) -> None:
        """轮询返回任务；未知 → ImageTaskNotFoundError"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        task = _create_task(db_session, conv)

        assert tasks_service.get_image_task(db_session, task.id).id == task.id
        with pytest.raises(ImageTaskNotFoundError):
            tasks_service.get_image_task(db_session, 99999)


# ── 2. run_image_task（成功 / 失败）──


class TestRunImageTask:
    """后台执行：成功入资产库 + 失败不破坏对话"""

    async def test_run_success_adds_cg_and_sets_succeeded(
        self, db_session: Session, cg_dir_tmp
    ) -> None:
        """核心契约 1：local 后端成功 → succeeded + result_url + 出图入资产库（挂锚消息）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        msg_id = _add_message(db_session, conv.id)
        task = _create_task(db_session, conv, message_id=msg_id)

        await tasks_service.run_image_task(task.id, db_session)

        db_session.refresh(task)
        assert task.status == "succeeded"
        assert task.result_url is not None
        # 出图入资产库（挂会话 + 锚消息）
        cg = db_session.query(CgImage).filter(CgImage.url == task.result_url).first()
        assert cg is not None
        assert cg.character_id == char_id
        assert cg.conversation_id == conv.id
        assert cg.message_id == msg_id

    async def test_run_failure_sets_failed_without_breaking(self, db_session: Session, cg_dir_tmp) -> None:
        """核心契约 2（后端侧）：失败 → failed + error 记录，不出图、不外抛（不破坏对话）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        task = _create_task(db_session, conv, provider="a1111")  # 无 base_url 构造即错

        await tasks_service.run_image_task(task.id, db_session)  # 不应外抛

        db_session.refresh(task)
        assert task.status == "failed"
        assert task.error is not None
        assert db_session.query(CgImage).count() == 0  # 不出图

    async def test_run_unknown_task_noop(self, db_session: Session, cg_dir_tmp) -> None:
        """未知任务 → no-op（不抛）"""
        await tasks_service.run_image_task(99999, db_session)

    async def test_run_already_succeeded_noop(self, db_session: Session, cg_dir_tmp) -> None:
        """已终态任务 → no-op（不重复出图）"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        task = _create_task(db_session, conv)
        await tasks_service.run_image_task(task.id, db_session)
        cg_count = db_session.query(CgImage).count()

        await tasks_service.run_image_task(task.id, db_session)  # 再跑 no-op

        assert db_session.query(CgImage).count() == cg_count


# ── 2.5 生图能力门控（MD-3）──


class TestImageAvailability:
    """image_generation_available 判定矩阵（门控单一来源）"""

    def test_unconfigured_false(self, db_session: Session) -> None:
        """未配置（空 provider）→ False"""
        assert tasks_service.image_generation_available(db_session) is False

    def test_local_placeholder_false(self, db_session: Session) -> None:
        """local 占位后端生产不可用 → False"""
        _configure_image_backend(db_session, "local")
        assert tasks_service.image_generation_available(db_session) is False

    def test_http_without_base_url_false(self, db_session: Session) -> None:
        """HTTP 类后端无 base_url → False"""
        _configure_image_backend(db_session, "a1111")
        assert tasks_service.image_generation_available(db_session) is False

    def test_http_with_base_url_true(self, db_session: Session) -> None:
        """a1111 / custom-http + base_url → True"""
        _configure_image_backend(db_session, "a1111", "http://127.0.0.1:7860")
        assert tasks_service.image_generation_available(db_session) is True
        _configure_image_backend(db_session, "custom-http", "http://127.0.0.1:9999")
        assert tasks_service.image_generation_available(db_session) is True

    def test_unknown_provider_false(self, db_session: Session) -> None:
        """未登记 provider → False"""
        _configure_image_backend(db_session, "nope", "http://x")
        assert tasks_service.image_generation_available(db_session) is False


# ── 3. 剧情回顾时间线排序 ──


class TestCgTimeline:
    """时间线：消息 created_at 升序 + 同消息入库序 + 仅解锁 + 无锚按 cg.created_at"""

    def _seed_timeline(self, db_session: Session) -> int:
        import datetime

        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        m1 = _add_message(db_session, conv.id, "第一段")
        m2 = _add_message(db_session, conv.id, "第二段")
        _set_message_created_at(db_session, m1, datetime.datetime(2024, 1, 1))
        _set_message_created_at(db_session, m2, datetime.datetime(2024, 2, 1))

        # 消息 m1 两图（入库序 cg1→cg2）、m2 一图（解锁）、m2 一图（锁定）、无锚一图
        cg1 = gallery_service.add_cg(db_session, char_id, "cg/1.png", conversation_id=conv.id, message_id=m1)
        cg2 = gallery_service.add_cg(db_session, char_id, "cg/2.png", conversation_id=conv.id, message_id=m1)
        cg3 = gallery_service.add_cg(db_session, char_id, "cg/3.png", conversation_id=conv.id, message_id=m2)
        cg4 = gallery_service.add_cg(db_session, char_id, "cg/4.png", conversation_id=conv.id, message_id=m2)
        cg5 = gallery_service.add_cg(db_session, char_id, "cg/5.png", conversation_id=conv.id)  # 无锚
        for cg in (cg1, cg2, cg3, cg4, cg5):
            gallery_service.unlock_cg(db_session, cg.id)
        # cg4 锁定（排除）：直接置 False 模拟未解锁
        db_session.query(CgImage).filter(CgImage.id == cg4.id).update({"unlocked": False})
        db_session.commit()
        return char_id

    def test_timeline_order_and_unlock_filter(self, db_session: Session) -> None:
        """核心契约 3：消息 created_at 升序 + 同消息入库序（cg.id）+ 仅解锁"""
        char_id = self._seed_timeline(db_session)

        items = gallery_service.cg_timeline(db_session, char_id)

        # cg4 锁定 → 排除；无锚 cg5 按自身 created_at（now > t2）排最后
        assert [it["url"] for it in items] == ["cg/1.png", "cg/2.png", "cg/3.png", "cg/5.png"]
        # 同消息 m1 两图入库序（cg.id 升序）
        assert items[0]["message_content"] == "第一段"
        assert items[1]["message_content"] == "第一段"
        assert items[2]["message_content"] == "第二段"
        # 消息 created_at 升序（t1 < t2）
        assert items[0]["message_created_at"] <= items[2]["message_created_at"]

    def test_timeline_empty(self, db_session: Session) -> None:
        """无解锁 CG → 空列表"""
        char_id = _create_character(db_session)
        assert gallery_service.cg_timeline(db_session, char_id) == []


# ── 4. 路由契约 ──


class TestImageRoutes:
    """POST /api/images/tasks、GET task、GET cg-timeline、GET available"""

    async def test_submit_task_route(self, db_session: Session, monkeypatch: pytest.MonkeyPatch, cg_dir_tmp) -> None:
        """POST /api/images/tasks：配置生图后端后创建任务（provider 从 settings 取，后台注入 no-op）"""
        async def _noop(task_id: int) -> None:
            pass

        monkeypatch.setattr(images_route, "_background_run", _noop)
        _configure_image_backend(db_session, "a1111", "http://127.0.0.1:7860")
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)

        resp = await images_route.submit_image_task(
            ImageTaskCreate(conversation_id=conv.id, prompt="一只猫"), db_session
        )

        assert resp.id is not None
        assert resp.status == "pending"
        assert resp.conversation_id == conv.id
        task = db_session.query(ImageTask).one()
        assert task.provider == "a1111"  # provider 来自 settings，非请求体

    async def test_submit_without_backend_400(self, db_session: Session, monkeypatch: pytest.MonkeyPatch, cg_dir_tmp) -> None:
        """核心契约（MD-3）：未配置生图后端 → 400 明确拒绝（不发任务）"""
        from fastapi import HTTPException

        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)

        with pytest.raises(HTTPException) as exc:
            await images_route.submit_image_task(
                ImageTaskCreate(conversation_id=conv.id, prompt="一只猫"), db_session
            )

        assert exc.value.status_code == 400
        assert "未配置图片生成后端" in exc.value.detail
        assert db_session.query(ImageTask).count() == 0

    async def test_available_route(self, db_session: Session, cg_dir_tmp) -> None:
        """GET /api/images/available：反映生图后端配置态"""
        assert images_route.image_available(db_session) == {"available": False}
        _configure_image_backend(db_session, "a1111", "http://127.0.0.1:7860")
        assert images_route.image_available(db_session) == {"available": True}

    async def test_get_task_route(self, db_session: Session, cg_dir_tmp) -> None:
        """GET /api/images/tasks/{id}：返回任务状态"""
        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        task = _create_task(db_session, conv)

        resp = images_route.get_image_task(task.id, db_session)

        assert resp.id == task.id
        assert resp.status == "pending"

    async def test_cg_timeline_route(self, db_session: Session, cg_dir_tmp) -> None:
        """GET /api/characters/{id}/cg-timeline：时间线条目投影（CgTimelineItem）"""
        from backend.app.schemas.image_task import CgTimelineItem

        char_id = _create_character(db_session)
        conv = _create_conversation(db_session, char_id)
        msg = _add_message(db_session, conv.id)
        cg = gallery_service.add_cg(db_session, char_id, "cg/x.png", conversation_id=conv.id, message_id=msg)
        gallery_service.unlock_cg(db_session, cg.id)

        items = images_route.cg_timeline(char_id, db_session)

        assert len(items) == 1
        assert isinstance(items[0], CgTimelineItem)
        assert items[0].url == "cg/x.png"
        assert items[0].message_content is not None