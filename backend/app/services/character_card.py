"""
SillyTavern Character Card V2 — 角色卡转换层

深模块：协议表面仅两个公开函数（to_v2_card / from_v2_card），
实现内含 V2 信封 / 裸 data / V1 旧卡三种格式识别、字段归一化、
头像往返、extensions.conver_system 命名空间保真。

规格依据见 docs/p2.5-character-import-export.md §3-§4。
"""

from __future__ import annotations

import base64
import binascii

from backend.app.models.character import Character
from backend.app.schemas.character import PRESET_DIALOGUE_MAX, CharacterCreate
from backend.app.services.character_fields import CHARACTER_V2_FIELDS, V2_KEY_MAP, V1_TO_V2_MAP
from backend.app.services.exceptions import CardFormatError, CardValidationError
from backend.app.services.text_utils import as_str_list

__all__ = ["to_v2_card", "from_v2_card"]

# V2 信封标识
SPEC = "chara_card_v2"
SPEC_VERSION = "2.0"

# Conver System 私有命名空间：承载 temperature / URL 头像 / lorebook 等非 V2 标准字段
_NS = "conver_system"

# V1 旧卡字段 → V2/DB 字段映射
def to_v2_card(char: Character) -> dict:
    """角色 ORM → V2 信封 dict（导出用）

    非 V2 标准字段（temperature / URL 头像 / lorebook 等）经
    extensions.conver_system 命名空间保真，保证导出→导入往返不丢数据。

    Args:
        char: 角色 ORM 对象。

    Returns:
        V2 信封 dict（spec + spec_version + data）。
    """
    extensions = dict(char.extensions or {})
    ns = dict(_conver_system(extensions))

    # temperature：以 DB 实时值为准写入命名空间
    ns["temperature"] = char.temperature
    # 采样参数（SP-1）：仅非 None 写入命名空间（None = 未设置，不落卡）
    if char.top_p is not None:
        ns["top_p"] = char.top_p
    if char.presence_penalty is not None:
        ns["presence_penalty"] = char.presence_penalty
    if char.frequency_penalty is not None:
        ns["frequency_penalty"] = char.frequency_penalty
    if char.max_tokens is not None:
        ns["max_tokens"] = char.max_tokens

    # PD-5 专家模式：非默认值写入命名空间（默认 simple / 空串不落卡，对齐采样参数 None 不落卡）
    if char.prompt_mode == "expert":
        ns["prompt_mode"] = char.prompt_mode
    if char.expert_prompt:
        ns["expert_prompt"] = char.expert_prompt

    # PD-4 预设对话：写入 conver_system 命名空间（不落 data 顶层，与 prompt_mode/expert_prompt 同归类）
    if char.preset_dialogues:
        ns["preset_dialogues"] = char.preset_dialogues

    # 头像：base64 data URI → data.avatar（去前缀，ST 兼容）；URL → 命名空间 avatar_url
    data_avatar = None
    if char.avatar and _is_data_uri(char.avatar):
        data_avatar = _extract_raw_base64(char.avatar)
        ns.pop("avatar_url", None)
    elif char.avatar:
        ns["avatar_url"] = char.avatar

    extensions[_NS] = ns

    return {
        "spec": SPEC,
        "spec_version": SPEC_VERSION,
        "data": {
            "name": char.name,
            "description": char.description,
            "personality": char.personality,
            "scenario": char.scenario,
            "first_mes": char.first_mes,
            "mes_example": char.mes_example,
            "system_prompt": char.system_prompt,
            "post_history_instructions": char.post_history_instructions,
            "alternate_greetings": char.alternate_greetings or [],
            "tags": char.tags or [],
            "creator": char.creator,
            "character_version": char.version,
            "creator_notes": char.creator_notes or {},
            "avatar": data_avatar,
            "extensions": extensions,
        },
    }


def from_v2_card(card: dict) -> CharacterCreate:
    """角色卡 dict → 可落库的 CharacterCreate（导入用）

    识别优先级：
        1. V2 信封（spec == "chara_card_v2"，取 data）
        2. 无 spec 的 data 信封（宽容：顶层含 data 且 data 含 name）
        3. 裸 data（顶层含 name）
        4. V1 旧卡（顶层含 char_name，字段归一化）
    无法识别 → 抛 ValueError（路由层转 422 友好报错）。

    Args:
        card: 角色卡原始 JSON（任意 dict）。

    Returns:
        可直接交 create_character 落库的 CharacterCreate。

    Raises:
        CardFormatError: 卡片格式无法识别 / 缺 data 信封。
        CardValidationError: 角色名称不能为空。
    """
    if not isinstance(card, dict):
        raise CardFormatError("角色卡必须是 JSON 对象")

    spec = card.get("spec")

    if spec == SPEC:
        data = card.get("data")
        if not isinstance(data, dict):
            raise CardFormatError("角色卡缺少 data 字段")
    elif spec is not None:
        raise CardFormatError(f"不支持的卡片规格: {spec}")
    elif isinstance(card.get("data"), dict) and "name" in card["data"]:
        data = card["data"]
    elif "char_name" in card:
        data = _normalize_v1(card)  # V1_TO_V2_MAP imported from character_fields
    elif "name" in card:
        data = card
    else:
        raise CardFormatError("无法识别的角色卡格式")

    return _build_create(data)


def _normalize_v1(card: dict) -> dict:
    """V1 旧卡字段名 → V2/DB 字段名（V1_TO_V2_MAP 来自 character_fields.py 单一来源）"""
    return {v2: card[v1] for v1, v2 in V1_TO_V2_MAP.items() if card.get(v1) is not None}


def _build_create(data: dict) -> CharacterCreate:
    """归一化后的 data dict → CharacterCreate（字段清单由 CHARACTER_V2_FIELDS 定义，C5 单一映射深模块）"""
    """归一化后的 data dict → CharacterCreate（含类型容错与边界裁剪）"""
    name = str(data.get("name") or "").strip()[:100]
    if not name:
        raise CardValidationError("角色名称不能为空")

    extensions = _as_dict(data.get("extensions"))
    ns = _conver_system(extensions)

    # 头像：data.avatar（base64 / data URI / URL）优先，其次命名空间 avatar_url
    raw_avatar = data.get("avatar")
    if raw_avatar and isinstance(raw_avatar, str):
        avatar_value = _to_data_uri(raw_avatar)
    else:
        avatar_value = ns.get("avatar_url") or None

    # temperature：命名空间优先，其次裸 data 顶层（容错），无则默认 0.7，并裁剪到 [0, 2] 合法区间
    temperature = _clamp_temperature(ns.get("temperature", data.get("temperature", 0.7)))

    # 采样参数（SP-1）：命名空间优先，其次裸 data 顶层（容错）；可空字段 None/非法值回退 None（不覆盖 provider 默认）
    top_p = _clamp_optional_float(ns.get("top_p", data.get("top_p")), 0.0, 1.0)
    presence_penalty = _clamp_optional_float(
        ns.get("presence_penalty", data.get("presence_penalty")), -2.0, 2.0,
    )
    frequency_penalty = _clamp_optional_float(
        ns.get("frequency_penalty", data.get("frequency_penalty")), -2.0, 2.0,
    )
    max_tokens = _clamp_optional_int(ns.get("max_tokens", data.get("max_tokens")), 1, 131072)

    # PD-5 专家模式：conver_system 命名空间往返（对齐 temperature 既有模式）
    prompt_mode = str(ns.get("prompt_mode") or "simple")
    expert_prompt = str(ns.get("expert_prompt") or "")

    # PD-4 预设对话：conver_system 命名空间往返（对齐 temperature 既有模式），读回并归一化
    preset_dialogues = _normalize_preset_dialogues(ns.get("preset_dialogues"))

    version = data.get("character_version") or data.get("version") or "1.0"

    return CharacterCreate(
        name=name,
        description=str(data.get("description") or ""),
        personality=str(data.get("personality") or ""),
        scenario=str(data.get("scenario") or ""),
        first_mes=str(data.get("first_mes") or ""),
        mes_example=str(data.get("mes_example") or ""),
        system_prompt=str(data.get("system_prompt") or ""),
        post_history_instructions=str(data.get("post_history_instructions") or ""),
        alternate_greetings=as_str_list(data.get("alternate_greetings")),
        tags=as_str_list(data.get("tags")),
        creator=str(data.get("creator") or ""),
        version=str(version)[:50],
        creator_notes=_as_dict(data.get("creator_notes")),
        extensions=extensions,
        avatar=avatar_value,
        temperature=temperature,
        top_p=top_p,
        presence_penalty=presence_penalty,
        frequency_penalty=frequency_penalty,
        max_tokens=max_tokens,
        prompt_mode=prompt_mode,
        expert_prompt=expert_prompt,
        preset_dialogues=preset_dialogues,
    )


# ── 内部辅助 ──


def _is_data_uri(value: str) -> bool:
    """判断是否为 data:image/...;base64, 形式的头像"""
    return value.startswith("data:image/")


def _extract_raw_base64(value: str) -> str:
    """从 data URI 提取原始 base64（去 data:image/...;base64, 前缀）"""
    _, _, rest = value.partition(";base64,")
    return rest


def _infer_mime(raw_base64: str) -> str:
    """按 base64 解码后的魔数推断 MIME 类型，失败默认 png"""
    try:
        head = base64.b64decode(raw_base64[:32])
    except (binascii.Error, ValueError):
        # ValueError：b64decode 对非 ASCII str 抛普通 ValueError（非 binascii.Error），
        # 与模块容错哲学一致——脏头像默认 png，不使导入请求 500
        return "png"
    if head.startswith(b"\x89PNG"):
        return "png"
    if head.startswith(b"\xff\xd8"):
        return "jpeg"
    if head.startswith(b"GIF8"):
        return "gif"
    if head.startswith(b"RIFF") and head[8:12] == b"WEBP":
        return "webp"
    return "png"


def _to_data_uri(avatar: str) -> str:
    """头像 → data URI（已含前缀或为 URL 则原样保留；裸 base64 则包装）"""
    if _is_data_uri(avatar) or avatar.startswith(("http://", "https://")):
        return avatar
    return f"data:image/{_infer_mime(avatar)};base64,{avatar}"


def _as_dict(value) -> dict:
    """容忍脏数据：None → {}，dict → 原样，纯文本 → {"text": value}（V1 creatorcomment）"""
    if value is None:
        return {}
    if isinstance(value, dict):
        return value
    if isinstance(value, str) and value.strip():
        return {"text": value}
    return {}


def _conver_system(extensions: dict) -> dict:
    """取 extensions 中的 conver_system 命名空间（不存在 / 非 dict 返回空 dict）"""
    ns = extensions.get(_NS)
    return ns if isinstance(ns, dict) else {}


def _normalize_preset_dialogues(value: object) -> list[dict]:
    """预设对话归一化：非 list → []；逐项 name/content trim 非空；按 name 去重保留首个；截断至 PRESET_DIALOGUE_MAX

    PD-4 预设对话导入侧容错：脏数据（None / 非 list / 空字段 / 同名重复 / 超量）
    全部收敛为「干净 list[dict]」，再交 CharacterCreate 由 Pydantic 转 PresetDialogue。
    """
    if not isinstance(value, list):
        return []
    result: list[dict] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        content = str(item.get("content") or "").strip()
        if not name or not content:
            continue
        if name in seen:
            continue
        seen.add(name)
        result.append({"name": name, "content": content})
        if len(result) >= PRESET_DIALOGUE_MAX:
            break
    return result


def _clamp_temperature(value) -> float:
    """温度值裁剪到 [0, 2] 合法区间，非法值回退默认 0.7"""
    try:
        temp = float(value)
    except (TypeError, ValueError):
        return 0.7
    return min(2.0, max(0.0, temp))


def _clamp_optional_float(value, low: float, high: float) -> float | None:
    """可空浮点采样参数裁剪到 [low, high]；None/非法值回退 None（不覆盖 provider 默认）

    top_p / presence_penalty / frequency_penalty 的往返裁剪：None 表示「未设置」
    直接透传；非 None 时转 float 并夹到合法区间；脏数据（字符串 'abc'/NaN/None
    之外的非数值）回退 None，与 temperature 的「非法回退默认」不同——采样参数
    无「全局默认」概念，None 才是语义上的缺省。
    """
    if value is None:
        return None
    try:
        v = float(value)
    except (TypeError, ValueError):
        return None
    return min(high, max(low, v))


def _clamp_optional_int(value, low: int, high: int) -> int | None:
    """可空整数采样参数（max_tokens）裁剪到 [low, high]；None/非法值回退 None"""
    if value is None:
        return None
    try:
        v = int(value)
    except (TypeError, ValueError):
        return None
    return min(high, max(low, v))
