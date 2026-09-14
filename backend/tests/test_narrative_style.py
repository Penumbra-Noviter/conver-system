"""
01 叙述风格设置键与访问器 — 契约锁

覆盖：
    1. ALLOWED_KEYS 含 narrative_style_enabled / narrative_style_rules 两键
    2. get_all 返回两键、set_many 写两键且忽略白名单外键
    3. narrative_style_enabled 真值口径（"1"/"true"/"yes" 大小写不敏感 → True，
       其余/显式空 → False，缺省 → True 默认启用 opt-out）
    4. narrative_style_rules 默认规则回退（DB 非空返回原值，空/缺省返回默认常量）
    5. NARRATIVE_STYLE_DEFAULT_RULES 覆盖反 AI 味规则清单 + 末尾冲突声明

依赖：pytest + SQLite 内存库（db_session fixture，见 conftest.py）。
"""

from __future__ import annotations

import pytest

from backend.app.models.setting import Setting
from backend.app.services import setting as setting_service

__all__: list[str] = []


def _save_setting(db_session, key: str, value: str) -> None:
    """写入一条设置记录"""
    db_session.add(Setting(key=key, value=value))
    db_session.commit()


class TestNarrativeStyleKeys:
    """两键进入白名单 + get_all/set_many 契约锁"""

    def test_allowed_keys_include_both(self) -> None:
        """ALLOWED_KEYS 含两个叙述风格键"""
        assert "narrative_style_enabled" in setting_service.ALLOWED_KEYS
        assert "narrative_style_rules" in setting_service.ALLOWED_KEYS

    def test_get_all_returns_both_keys(self, db_session) -> None:
        """get_all 能读出两键的值"""
        _save_setting(db_session, "narrative_style_enabled", "1")
        _save_setting(db_session, "narrative_style_rules", "自定义规则")
        result = setting_service.get_all(db_session)
        assert result["narrative_style_enabled"] == "1"
        assert result["narrative_style_rules"] == "自定义规则"

    def test_set_many_writes_both_ignores_outside(self, db_session) -> None:
        """set_many 写两键、忽略白名单外键"""
        setting_service.set_many(
            db_session,
            {
                "narrative_style_enabled": "true",
                "narrative_style_rules": "自定义规则",
                "not_allowed_key": "x",
            },
        )
        result = setting_service.get_all(db_session)
        assert result["narrative_style_enabled"] == "true"
        assert result["narrative_style_rules"] == "自定义规则"
        assert "not_allowed_key" not in result


class TestNarrativeStyleEnabled:
    """访问器真值口径（默认启用 opt-out，与 memory_palace_enabled 的 opt-in 相反）"""

    def test_default_true_when_missing(self, db_session) -> None:
        """键缺省 → True（ADR-1 默认启用降 AI 味）"""
        assert setting_service.narrative_style_enabled(db_session) is True

    def test_true_when_explicit_empty(self, db_session) -> None:
        """显式空串 → True（get_value 空值回退 default "1"，与缺省同义）"""
        _save_setting(db_session, "narrative_style_enabled", "")
        assert setting_service.narrative_style_enabled(db_session) is True

    @pytest.mark.parametrize("value", ["1", "true", "yes", "True", "TRUE", "YES"])
    def test_true_values(self, db_session, value: str) -> None:
        """真值集大小写不敏感 → True"""
        _save_setting(db_session, "narrative_style_enabled", value)
        assert setting_service.narrative_style_enabled(db_session) is True

    @pytest.mark.parametrize("value", ["0", "false", "no", "off", "abc", "2"])
    def test_false_values(self, db_session, value: str) -> None:
        """显式非真值集 → False"""
        _save_setting(db_session, "narrative_style_enabled", value)
        assert setting_service.narrative_style_enabled(db_session) is False


class TestNarrativeStyleRules:
    """规则访问器默认回退语义"""

    def test_default_when_missing(self, db_session) -> None:
        """键缺省 → 返回默认常量"""
        assert (
            setting_service.narrative_style_rules(db_session)
            == setting_service.NARRATIVE_STYLE_DEFAULT_RULES
        )

    def test_default_when_empty(self, db_session) -> None:
        """DB 值为空串 → 返回默认常量"""
        _save_setting(db_session, "narrative_style_rules", "")
        assert (
            setting_service.narrative_style_rules(db_session)
            == setting_service.NARRATIVE_STYLE_DEFAULT_RULES
        )

    def test_custom_rules_returned(self, db_session) -> None:
        """DB 非空 → 原值返回，不回退默认"""
        _save_setting(db_session, "narrative_style_rules", "自定义规则")
        assert setting_service.narrative_style_rules(db_session) == "自定义规则"


class TestNarrativeStyleDefaultRules:
    """默认规则清单覆盖 spec 要求的反 AI 味项 + 末尾冲突声明"""

    def test_contains_conflict_disclaimer(self) -> None:
        """末尾含低优先级声明"""
        assert "若与角色设定冲突，以角色设定为准" in setting_service.NARRATIVE_STYLE_DEFAULT_RULES

    @pytest.mark.parametrize(
        "marker",
        [
            "总之",
            "值得注意的是",
            "首先",
            "其次",
            "emoji",
            "复读",
            "小作文",
            "语气",
        ],
    )
    def test_contains_required_markers(self, marker: str) -> None:
        """覆盖 spec 所列禁止项关键词"""
        assert marker in setting_service.NARRATIVE_STYLE_DEFAULT_RULES
