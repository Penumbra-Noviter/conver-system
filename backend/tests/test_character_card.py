"""
SillyTavern Character Card V2 转换层单元测试

覆盖 spec §7 验收标准（docs/p2.5-character-import-export.md）：
- V2 往返（to_v2_card → from_v2_card 字段保真）
- V1 旧卡归一化（char_name 等旧字段 → V2/DB 字段）
- 裸 data（顶层含 name，无 spec/data 信封）
- 非法卡 → CardFormatError / CardValidationError（路由层统一转 422 友好报错）
- 头像三形态（base64 data URI / URL / 无）

另含：temperature 默认与裁剪、name 截断、extensions.conver_system 保真、
脏数据容错（list/dict 类型矫正）。
"""

from __future__ import annotations

import base64

import pytest

from backend.app.models.character import Character
from backend.app.schemas.character import CharacterCreate
from backend.app.services.character_card import SPEC, from_v2_card, to_v2_card
from backend.app.services.exceptions import CardFormatError, CardValidationError

__all__: list[str] = []

# 极小 PNG / JPEG 裸 base64（供 MIME 推断测试）
_PNG_B64 = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"\x00" * 20).decode()
_JPEG_B64 = base64.b64encode(b"\xff\xd8\xff\xe0" + b"\x00" * 20).decode()


# ── 样例构造 ──


def _v2_data(**overrides: object) -> dict:
    """完整 V2 data 段（可覆盖）"""
    data = {
        "name": "测试角色",
        "description": "一个用于测试的角色",
        "personality": "冷静、睿智",
        "scenario": "月下竹林",
        "first_mes": "你好，久等了。",
        "mes_example": "<START>\n{{user}}: 你好\n{{char}}: 欢迎",
        "system_prompt": "你是测试角色。",
        "post_history_instructions": "保持人设。",
        "alternate_greetings": ["备选开场白"],
        "tags": ["冒险", "奇幻"],
        "creator": "测试作者",
        "character_version": "1.0",
        "creator_notes": {"note": "创作者备注"},
        "avatar": None,
        "extensions": {},
    }
    data.update(overrides)
    return data


def _v2_card(**overrides: object) -> dict:
    """完整 V2 信封（可覆盖 data 段）"""
    return {"spec": SPEC, "spec_version": "2.0", "data": _v2_data(**overrides)}


def _roundtrip(char: Character) -> CharacterCreate:
    """导出 → 导入往返"""
    return from_v2_card(to_v2_card(char))


def _assert_roundtrip_equal(char: Character, result: CharacterCreate) -> None:
    """断言导出→导入往返后字段与源角色一致（extensions 只保内容，temperature 注入/回读）"""
    assert result.name == char.name
    assert result.description == char.description
    assert result.personality == char.personality
    assert result.scenario == char.scenario
    assert result.first_mes == char.first_mes
    assert result.mes_example == char.mes_example
    assert result.system_prompt == char.system_prompt
    assert result.post_history_instructions == char.post_history_instructions
    assert result.alternate_greetings == (char.alternate_greetings or [])
    assert result.tags == (char.tags or [])
    assert result.creator == char.creator
    assert result.version == char.version
    assert result.creator_notes == (char.creator_notes or {})
    assert result.avatar == char.avatar
    assert result.temperature == char.temperature
    for key, value in (char.extensions or {}).items():
        assert result.extensions[key] == value


# ════════════════════════════════════════════════════════════════
# 一、格式识别：V2 信封 / 裸 data / 无 spec 的 data 信封
# ════════════════════════════════════════════════════════════════


def test_from_v2_envelope_full_mapping() -> None:
    """V2 信封完整字段映射到 CharacterCreate"""
    result = from_v2_card(_v2_card())
    assert isinstance(result, CharacterCreate)
    assert result.name == "测试角色"
    assert result.description == "一个用于测试的角色"
    assert result.personality == "冷静、睿智"
    assert result.scenario == "月下竹林"
    assert result.first_mes == "你好，久等了。"
    assert result.mes_example == "<START>\n{{user}}: 你好\n{{char}}: 欢迎"
    assert result.system_prompt == "你是测试角色。"
    assert result.post_history_instructions == "保持人设。"
    assert result.alternate_greetings == ["备选开场白"]
    assert result.tags == ["冒险", "奇幻"]
    assert result.creator == "测试作者"
    assert result.version == "1.0"  # character_version → version
    assert result.creator_notes == {"note": "创作者备注"}
    assert result.temperature == 0.7  # 未指定 → 默认


def test_from_v2_uses_character_version() -> None:
    """character_version 优先于 version 字段"""
    result = from_v2_card(_v2_card(character_version="3.1", version="9.9"))
    assert result.version == "3.1"


def test_from_v2_envelope_missing_data() -> None:
    """V2 信封缺 data → ValueError"""
    with pytest.raises(CardFormatError, match="缺少 data 字段"):
        from_v2_card({"spec": SPEC})


def test_from_bare_data() -> None:
    """裸 data（顶层含 name，无 spec/data 信封）"""
    result = from_v2_card({"name": "裸角色", "personality": "直接", "temperature": 0.5})
    assert result.name == "裸角色"
    assert result.personality == "直接"
    assert result.temperature == 0.5


def test_from_data_envelope_without_spec() -> None:
    """无 spec 的 data 信封（宽容分支）"""
    result = from_v2_card({"data": {"name": "宽容信封"}})
    assert result.name == "宽容信封"


def test_from_unrecognizable() -> None:
    """结构无法识别 → ValueError"""
    with pytest.raises(CardFormatError, match="无法识别的角色卡格式"):
        from_v2_card({"foo": "bar"})
    with pytest.raises(CardFormatError, match="无法识别的角色卡格式"):
        from_v2_card({})


def test_from_unsupported_spec() -> None:
    """spec 非 v2 → ValueError「不支持的卡片规格」"""
    with pytest.raises(CardFormatError, match="不支持的卡片规格"):
        from_v2_card({"spec": "chara_card_v1", "data": {}})


@pytest.mark.parametrize("bad", [None, "字符串", ["list"], 123, 1.5, True])
def test_from_non_dict_body(bad: object) -> None:
    """非 dict 请求体 → ValueError「必须是 JSON 对象」"""
    with pytest.raises(CardFormatError, match="必须是 JSON 对象"):
        from_v2_card(bad)  # type: ignore[arg-type]


# ════════════════════════════════════════════════════════════════
# 二、V1 旧卡归一化
# ════════════════════════════════════════════════════════════════


def test_from_v1_card_full() -> None:
    """V1 旧卡全字段归一化"""
    v1 = {
        "char_name": "旧角色",
        "char_persona": "旧人格",
        "char_greeting": "旧开场",
        "example_dialogue": "旧范例",
        "world_scenario": "旧场景",
        "creatorcomment": "旧备注",
        "char_version": "2.0",
        "description": "旧描述",
    }
    result = from_v2_card(v1)
    assert result.name == "旧角色"
    assert result.personality == "旧人格"
    assert result.first_mes == "旧开场"
    assert result.mes_example == "旧范例"
    assert result.scenario == "旧场景"
    assert result.creator_notes == {"text": "旧备注"}  # 纯文本 creatorcomment → dict
    assert result.version == "2.0"
    assert result.description == "旧描述"


def test_from_v1_card_partial_fields() -> None:
    """V1 卡仅含部分旧字段 → 其余字段默认空值，版本默认 1.0"""
    result = from_v2_card({"char_name": "半卡", "char_greeting": "你好"})
    assert result.name == "半卡"
    assert result.first_mes == "你好"
    assert result.personality == ""
    assert result.version == "1.0"


# ════════════════════════════════════════════════════════════════
# 三、name 校验与截断
# ════════════════════════════════════════════════════════════════


def test_from_missing_name() -> None:
    """data 缺 name → ValueError「角色名称不能为空」"""
    with pytest.raises(CardValidationError, match="角色名称不能为空"):
        from_v2_card({"spec": SPEC, "data": {"personality": "只有人格"}})


def test_from_blank_name() -> None:
    """name 为空白 → ValueError（strip 后为空）"""
    with pytest.raises(CardValidationError, match="角色名称不能为空"):
        from_v2_card({"name": "   "})


def test_from_name_truncated_to_100() -> None:
    """超长 name 截断到 100 字符"""
    long_name = "名" * 150
    result = from_v2_card(_v2_card(name=long_name))
    assert result.name == "名" * 100


# ════════════════════════════════════════════════════════════════
# 四、头像三形态（导入侧）
# ════════════════════════════════════════════════════════════════


def test_from_avatar_bare_base64_png() -> None:
    """裸 base64（PNG 魔数）→ 包装为 data:image/png 前缀"""
    result = from_v2_card(_v2_card(avatar=_PNG_B64))
    assert result.avatar == f"data:image/png;base64,{_PNG_B64}"


def test_from_avatar_bare_base64_jpeg() -> None:
    """裸 base64（JPEG 魔数）→ 包装为 data:image/jpeg 前缀"""
    result = from_v2_card(_v2_card(avatar=_JPEG_B64))
    assert result.avatar == f"data:image/jpeg;base64,{_JPEG_B64}"


def test_from_avatar_data_uri_preserved() -> None:
    """已带 data:image 前缀 → 原样保留"""
    uri = "data:image/webp;base64,UklGR"
    result = from_v2_card(_v2_card(avatar=uri))
    assert result.avatar == uri


def test_from_avatar_url_preserved() -> None:
    """data.avatar 为 URL → 原样保留（不包装 base64）"""
    url = "https://example.com/avatar.png"
    result = from_v2_card(_v2_card(avatar=url))
    assert result.avatar == url


def test_from_avatar_url_from_namespace() -> None:
    """data.avatar 缺省 → 回读 extensions.conver_system.avatar_url"""
    url = "https://example.com/remote.png"
    card = _v2_card(avatar=None, extensions={"conver_system": {"avatar_url": url}})
    result = from_v2_card(card)
    assert result.avatar == url


def test_from_avatar_none() -> None:
    """两种来源均缺 → avatar None"""
    assert from_v2_card(_v2_card()).avatar is None


@pytest.mark.parametrize(
    ("raw", "expected_mime"),
    [
        (base64.b64encode(b"GIF89a" + b"\x00" * 20).decode(), "gif"),   # GIF 魔数
        (base64.b64encode(b"RIFF\x00\x00\x00\x00WEBP" + b"\x00" * 20).decode(), "webp"),  # RIFF+WEBP
        (base64.b64encode(b"\x00\x01\x02\x03" + b"\x00" * 20).decode(), "png"),  # 未知魔数 → 回退 png
        ("@@@@invalid-base64", "png"),  # 非法 base64 → binascii.Error → 回退 png
    ],
)
def test_from_avatar_mime_inference(raw: str, expected_mime: str) -> None:
    """裸 base64 按魔数推断 MIME，未知/非法回退 png"""
    result = from_v2_card(_v2_card(avatar=raw))
    assert result.avatar == f"data:image/{expected_mime};base64,{raw}"


# ════════════════════════════════════════════════════════════════
# 五、temperature：默认 / 命名空间 / 裁剪 / 容错
# ════════════════════════════════════════════════════════════════


def test_from_temperature_default() -> None:
    """命名空间缺 temperature → 默认 0.7"""
    assert from_v2_card(_v2_card()).temperature == 0.7


def test_from_temperature_from_namespace() -> None:
    """命名空间 temperature 生效"""
    card = _v2_card(extensions={"conver_system": {"temperature": 0.9}})
    assert from_v2_card(card).temperature == 0.9


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        (5, 2.0),        # 超上限 → 2.0
        (-1, 0.0),       # 低于下限 → 0.0
        ("abc", 0.7),    # 非法 → 默认
        ("1.2", 1.2),    # 数字字符串 → 正常解析
        (None, 0.7),     # None → 默认
    ],
)
def test_from_temperature_clamped(raw: object, expected: float) -> None:
    """temperature 越界/非法值裁剪或回退"""
    card = _v2_card(extensions={"conver_system": {"temperature": raw}})
    assert from_v2_card(card).temperature == expected


# ════════════════════════════════════════════════════════════════
# 六、extensions / 集合字段容错
# ════════════════════════════════════════════════════════════════


def test_from_extensions_preserved() -> None:
    """未知 extensions + conver_system 命名空间原样保留"""
    card = _v2_card(
        extensions={
            "custom_key": {"a": 1},
            "conver_system": {"character_book": {"entries": []}},
        }
    )
    result = from_v2_card(card)
    assert result.extensions["custom_key"] == {"a": 1}
    assert result.extensions["conver_system"] == {"character_book": {"entries": []}}


def test_from_extensions_not_dict() -> None:
    """extensions 脏数据容错：纯文本 → {"text": ...}（复用 _as_dict），其它非 dict → 空 dict"""
    assert from_v2_card(_v2_card(extensions="abc")).extensions == {"text": "abc"}
    assert from_v2_card(_v2_card(extensions=123)).extensions == {}


def test_from_tags_dirty() -> None:
    """tags 脏数据：None → []；单值 → 包裹；混合类型 → str 化"""
    assert from_v2_card(_v2_card(tags=None)).tags == []
    assert from_v2_card(_v2_card(tags="单标签")).tags == ["单标签"]
    assert from_v2_card(_v2_card(tags=["a", 2])).tags == ["a", "2"]


def test_from_alternate_greetings_dirty() -> None:
    """alternate_greetings 脏数据：None → []；空串 → []"""
    assert from_v2_card(_v2_card(alternate_greetings=None)).alternate_greetings == []
    assert from_v2_card(_v2_card(alternate_greetings="")).alternate_greetings == []


# ════════════════════════════════════════════════════════════════
# 七、导出：to_v2_card 信封结构与字段映射
# ════════════════════════════════════════════════════════════════


def test_to_v2_envelope_structure(make_character) -> None:
    """V2 信封结构 + 字段映射（character_version ← version）"""
    card = to_v2_card(make_character())
    assert card["spec"] == SPEC
    assert card["spec_version"] == "2.0"
    data = card["data"]
    assert data["name"] == "测试角色"
    assert data["character_version"] == "1.0"
    assert data["creator_notes"] == {"note": "创作者备注"}
    assert data["alternate_greetings"] == ["备选开场白"]
    assert data["tags"] == ["冒险", "奇幻"]


def test_to_v2_avatar_data_uri(make_character) -> None:
    """base64 data URI → data.avatar 去前缀存原始 base64，命名空间不留 avatar_url"""
    char = make_character(avatar=f"data:image/png;base64,{_PNG_B64}")
    card = to_v2_card(char)
    data, ns = card["data"], card["data"]["extensions"]["conver_system"]
    assert data["avatar"] == _PNG_B64
    assert "avatar_url" not in ns


def test_to_v2_avatar_url(make_character) -> None:
    """URL 头像 → 命名空间 avatar_url，data.avatar 为 None"""
    url = "https://example.com/a.png"
    card = to_v2_card(make_character(avatar=url))
    data, ns = card["data"], card["data"]["extensions"]["conver_system"]
    assert data["avatar"] is None
    assert ns["avatar_url"] == url


def test_to_v2_avatar_none(make_character) -> None:
    """无头像 → data.avatar None，命名空间不含 avatar_url"""
    card = to_v2_card(make_character(avatar=None))
    data, ns = card["data"], card["data"]["extensions"]["conver_system"]
    assert data["avatar"] is None
    assert "avatar_url" not in ns


def test_to_v2_temperature_wins(make_character) -> None:
    """temperature 以 DB 实时值写入命名空间（覆盖旧值）"""
    char = make_character(temperature=1.1)
    ns = to_v2_card(char)["data"]["extensions"]["conver_system"]
    assert ns["temperature"] == 1.1


def test_to_v2_extensions_merged(make_character) -> None:
    """既有 extensions 内容保留，temperature 注入，base64 头像时移除旧 avatar_url"""
    char = make_character(
        avatar=f"data:image/png;base64,{_PNG_B64}",
        extensions={
            "custom_key": "原样",
            "conver_system": {
                "character_book": {"entries": [1]},
                "avatar_url": "https://old.example/old.png",
            },
        },
    )
    ext = to_v2_card(char)["data"]["extensions"]
    assert ext["custom_key"] == "原样"
    ns = ext["conver_system"]
    assert ns["character_book"] == {"entries": [1]}
    assert ns["temperature"] == 0.7
    assert "avatar_url" not in ns  # base64 优先，旧 URL 被清除


def test_to_v2_extensions_none(make_character) -> None:
    """extensions None → 输出含空 conver_system 命名空间"""
    ext = to_v2_card(make_character(extensions=None))["data"]["extensions"]
    assert ext["conver_system"] == {"temperature": 0.7}


def test_to_v2_none_collections(make_character) -> None:
    """None 集合字段导出为空 list/dict"""
    char = make_character(
        alternate_greetings=None, tags=None, creator_notes=None, extensions=None
    )
    data = to_v2_card(char)["data"]
    assert data["alternate_greetings"] == []
    assert data["tags"] == []
    assert data["creator_notes"] == {}


def test_to_v2_url_avatar_keeps_lorebook(make_character) -> None:
    """URL 头像 + 命名空间 lorebook → 两者都保留"""
    char = make_character(
        avatar="https://example.com/a.png",
        extensions={"conver_system": {"character_book": {"entries": [2]}}},
    )
    ns = to_v2_card(char)["data"]["extensions"]["conver_system"]
    assert ns["avatar_url"] == "https://example.com/a.png"
    assert ns["character_book"] == {"entries": [2]}
    assert ns["temperature"] == 0.7


# ════════════════════════════════════════════════════════════════
# 八、V2 往返（spec §7 验收）
# ════════════════════════════════════════════════════════════════


def test_v2_roundtrip_full(make_character) -> None:
    """全字段角色导出→导入往返保真"""
    char = make_character(avatar=f"data:image/png;base64,{_PNG_B64}")
    _assert_roundtrip_equal(char, _roundtrip(char))


def test_v2_roundtrip_avatar_jpeg(make_character) -> None:
    """JPEG base64 头像往返 MIME 不变"""
    char = make_character(avatar=f"data:image/jpeg;base64,{_JPEG_B64}")
    _assert_roundtrip_equal(char, _roundtrip(char))


def test_v2_roundtrip_avatar_url(make_character) -> None:
    """URL 头像往返保真"""
    char = make_character(avatar="https://example.com/avatar.png")
    _assert_roundtrip_equal(char, _roundtrip(char))


def test_v2_roundtrip_lorebook(make_character) -> None:
    """lorebook（character_book）+ 自定义 extensions 往返保留"""
    char = make_character(
        extensions={"conver_system": {"character_book": {"entries": [1, 2]}}}
    )
    result = _roundtrip(char)
    assert result.extensions["conver_system"]["character_book"] == {"entries": [1, 2]}
    assert result.extensions["conver_system"]["temperature"] == 0.7


def test_v2_roundtrip_minimal(make_character) -> None:
    """仅 name 的最小角色往返不报错，空字段为默认值"""
    char = make_character(
        name="最小角色",
        description="",
        personality="",
        scenario="",
        first_mes="",
        mes_example="",
        system_prompt="",
        post_history_instructions="",
        alternate_greetings=[],
        tags=[],
        creator="",
        creator_notes={},
        extensions={},
        avatar=None,
    )
    result = _roundtrip(char)
    assert result.name == "最小角色"
    assert result.description == ""
    assert result.avatar is None
    assert result.version == "1.0"


# ── 路由层导入错误引导 ──


class TestImportRouteErrorHint:
    """导入端点 422 错误消息：格式错误附带支持格式说明（引导改用向导）"""

    def test_format_error_includes_hint(self) -> None:
        """无法识别的格式 → 422 detail 含具体原因 + 支持格式说明 + 向导引导"""
        from fastapi import HTTPException

        from backend.app.api.routes.characters import import_character

        with pytest.raises(HTTPException) as exc_info:
            import_character({"foo": "bar"}, None)  # type: ignore[arg-type]
        detail = exc_info.value.detail
        assert detail.startswith("导入失败：")
        assert "无法识别的角色卡格式" in detail
        assert "支持格式" in detail
        assert "chara_card_v2" in detail
        assert "向导" in detail

    def test_unsupported_spec_includes_hint(self) -> None:
        """不认识的 spec → 422 detail 含具体原因 + 说明"""
        from fastapi import HTTPException

        from backend.app.api.routes.characters import import_character

        with pytest.raises(HTTPException) as exc_info:
            import_character({"spec": "chara_card_v9", "data": {}}, None)  # type: ignore[arg-type]
        detail = exc_info.value.detail
        assert "不支持的卡片规格" in detail
        assert "支持格式" in detail

    def test_validation_error_keeps_plain_message(self) -> None:
        """内容校验错误（名称空）→ 422 detail 仅具体原因，不带格式说明"""
        from fastapi import HTTPException

        from backend.app.api.routes.characters import import_character

        with pytest.raises(HTTPException) as exc_info:
            import_character({"spec": "chara_card_v2", "data": {"personality": "x"}}, None)  # type: ignore[arg-type]
        detail = exc_info.value.detail
        assert "导入失败：" in detail
        assert "支持格式" not in detail
