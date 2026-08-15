"""
Provider 清单单一来源测试 — 工厂注册与设置映射均从 model_data.AVAILABLE_MODELS 派生

覆盖：
    1. register_builtin_providers() 从 AVAILABLE_MODELS 派生注册（类映射 / 顺序 / 幂等）
    2. _CLASS_OVERRIDES 显式覆盖 dict 优先于默认规则
    3. 模拟在 AVAILABLE_MODELS 新增 Provider → 派生注册自动生效（新增只改一处）
    4. setting._PROVIDER_API_MAP 派生内容（与现状 6 项逐项一致）与 _resolve_api_provider 语义
    5. 畸形数据（空清单 / 缺 key / 无可解析实现类）的行为

依赖：pytest + monkeypatch（不建库、不发网络请求）。
LLMFactory 类级状态（_providers / _builtins_loaded）跨测试共享，autouse fixture 负责恢复。
"""

from __future__ import annotations

import importlib

import pytest

from backend.app.services import provider_registry as provider_registry_module
from backend.app.services.exceptions import ProviderNotSupportedError
from backend.app.services.llm import factory as factory_module
from backend.app.services.llm.base import BaseLLM
from backend.app.services.llm.claude import ClaudeProvider
from backend.app.services.llm.errors import LLMError
from backend.app.services.llm.factory import LLMFactory
from backend.app.services.llm.openai import OpenAIProvider
from backend.app.services.model_data import AVAILABLE_MODELS
from backend.app.services.provider_registry import resolve_api_provider

__all__: list[str] = []

# 注册顺序契约：与 AVAILABLE_MODELS["providers"] 声明顺序一致（现状逐项比对）
EXPECTED_ORDER = ["claude", "openai", "deepseek", "qwen", "kimi", "glm", "minimax", "step"]


class _OverrideProvider(BaseLLM):
    """测试用假实现类：验证 _CLASS_OVERRIDES 显式覆盖生效"""

    def _translate_error(self, error: Exception) -> LLMError:
        """stub：本测试不产生 SDK 调用，翻译仅满足抽象契约"""
        return LLMError(str(error), error)

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> str:
        """最小非流式实现"""
        return ""

    async def stream_generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> object:
        """最小流式实现（async generator）"""
        yield ""


@pytest.fixture(autouse=True)
def _restore_factory_state() -> object:
    """每个测试前后恢复 LLMFactory 类级注册状态，避免污染既有测试"""
    providers = dict(LLMFactory._providers)
    builtins_loaded = LLMFactory._builtins_loaded
    yield
    LLMFactory._providers = providers
    LLMFactory._builtins_loaded = builtins_loaded


def _reset_registry() -> None:
    """清空注册状态，模拟冷启动"""
    LLMFactory._providers = {}
    LLMFactory._builtins_loaded = False


class TestDerivedRegistration:
    """派生注册：模型数据驱动 + 类映射 + 顺序 + 幂等"""

    def test_registers_all_providers_from_available_models(self) -> None:
        """AVAILABLE_MODELS 全量派生：8 家键集 + 类映射（claude 专属类、其余 OpenAI 兼容类）"""
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert set(LLMFactory._providers) == set(EXPECTED_ORDER)
        assert LLMFactory._providers["claude"] is ClaudeProvider
        assert LLMFactory._providers["openai"] is OpenAIProvider
        assert LLMFactory._providers["deepseek"] is OpenAIProvider
        assert LLMFactory._providers["qwen"] is OpenAIProvider
        assert LLMFactory._providers["kimi"] is OpenAIProvider
        assert LLMFactory._providers["glm"] is OpenAIProvider
        assert LLMFactory._providers["minimax"] is OpenAIProvider
        assert LLMFactory._providers["step"] is OpenAIProvider

    def test_list_providers_order_matches_available_models(self) -> None:
        """list_providers() 顺序与 AVAILABLE_MODELS 声明顺序逐项一致"""
        _reset_registry()
        assert LLMFactory.list_providers() == EXPECTED_ORDER
        # 懒加载兜底只注册一次：连续调用顺序与结果不变
        assert LLMFactory.list_providers() == EXPECTED_ORDER

    def test_registration_is_idempotent(self) -> None:
        """连续两次注册：键集不变、不报错（幂等）"""
        _reset_registry()
        LLMFactory.register_builtin_providers()
        first = dict(LLMFactory._providers)
        LLMFactory.register_builtin_providers()
        assert LLMFactory._providers == first
        assert LLMFactory.list_providers() == EXPECTED_ORDER

    def test_class_overrides_take_precedence(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """_CLASS_OVERRIDES 显式覆盖优先于默认派生规则"""
        monkeypatch.setitem(factory_module._CLASS_OVERRIDES, "deepseek", _OverrideProvider)
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers["deepseek"] is _OverrideProvider
        # 其余 Provider 仍走默认规则，不受覆盖影响
        assert LLMFactory._providers["claude"] is ClaudeProvider
        assert LLMFactory._providers["step"] is OpenAIProvider


class TestNewProviderDerivation:
    """边界验证：新增 Provider 只改 AVAILABLE_MODELS，派生注册自动生效"""

    def test_new_openai_compatible_provider_auto_registers(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """PROVIDER_KEYS 新增 openai 协议项 → 自动注册为 OpenAIProvider"""
        monkeypatch.setattr(
            factory_module,
            "PROVIDER_KEYS",
            tuple(EXPECTED_ORDER) + ("fake",),
        )
        monkeypatch.setattr(
            factory_module,
            "resolve_api_provider",
            lambda key: "openai" if key == "fake" else resolve_api_provider(key),
        )
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers["fake"] is OpenAIProvider
        assert LLMFactory.list_providers() == EXPECTED_ORDER + ["fake"]

    def test_new_provider_with_class_override(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """key≠claude 且协议非 openai 的新 Provider 经 _CLASS_OVERRIDES 显式声明实现类"""
        monkeypatch.setattr(
            factory_module,
            "PROVIDER_KEYS",
            tuple(EXPECTED_ORDER) + ("fancy",),
        )
        monkeypatch.setattr(
            factory_module,
            "resolve_api_provider",
            lambda key: "proprietary" if key == "fancy" else resolve_api_provider(key),
        )
        monkeypatch.setitem(factory_module._CLASS_OVERRIDES, "fancy", _OverrideProvider)
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers["fancy"] is _OverrideProvider


class TestGetProvider:
    """get_provider 公共路径：注册名实例化 + 未注册名报错（懒加载兜底不变）"""

    def test_get_provider_returns_instance_for_registered_name(self) -> None:
        """注册名返回对应实现类实例（构造客户端不发网络请求）"""
        _reset_registry()
        provider = LLMFactory.get_provider("claude", "test-key")
        assert type(provider) is ClaudeProvider

    def test_get_provider_raises_for_unregistered_name(self) -> None:
        """未注册名报 ProviderNotSupportedError（领域异常，消息与现状逐字一致）"""
        _reset_registry()
        with pytest.raises(ProviderNotSupportedError, match="不支持的 Provider"):
            LLMFactory.get_provider("bogus", "test-key")


class TestMalformedData:
    """Falsify：派生逻辑对畸形输入的行为必须明确、可诊断"""

    def test_empty_providers_list_registers_nothing(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """PROVIDER_KEYS 空：注册为无操作，不报错"""
        monkeypatch.setattr(factory_module, "PROVIDER_KEYS", ())
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers == {}
        assert LLMFactory.list_providers() == []

    def test_unresolvable_provider_raises_with_override_hint(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """key≠claude 且协议非 openai 且无覆盖：报错并提示 _CLASS_OVERRIDES 出路"""
        monkeypatch.setattr(factory_module, "PROVIDER_KEYS", ("weird",))
        monkeypatch.setattr(
            factory_module,
            "resolve_api_provider",
            lambda key: "custom",
        )
        _reset_registry()
        with pytest.raises(ValueError, match="_CLASS_OVERRIDES"):
            LLMFactory.register_builtin_providers()

    def test_missing_key_in_registry_raises(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """provider_registry 派生时条目缺 key：显式 ValueError（与既有注册语义对齐）"""
        from backend.app.services import model_data as model_data_module

        bad = {"providers": [{"id": "openai", "name": "X", "models": []}]}
        monkeypatch.setattr(model_data_module, "AVAILABLE_MODELS", bad)
        with pytest.raises(ValueError, match="key"):
            importlib.reload(provider_registry_module)

    def test_duplicate_protocol_id_registers_all_to_same_class(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """重复 id（多 Provider 共享协议）是合法形态：各自按协议规则注册"""
        monkeypatch.setattr(factory_module, "PROVIDER_KEYS", ("a", "b", "claude"))
        monkeypatch.setattr(
            factory_module,
            "resolve_api_provider",
            lambda key: "claude" if key == "claude" else "openai",
        )
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers == {
            "a": OpenAIProvider,
            "b": OpenAIProvider,
            "claude": ClaudeProvider,
        }

    def test_duplicate_key_last_wins_without_crash(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """PROVIDER_KEYS 重复 key：注册不崩溃，后者覆盖前者（dict 语义）"""
        monkeypatch.setattr(factory_module, "PROVIDER_KEYS", ("dup", "dup"))
        monkeypatch.setattr(
            factory_module,
            "resolve_api_provider",
            lambda key: "openai",
        )
        _reset_registry()
        LLMFactory.register_builtin_providers()

        assert LLMFactory._providers["dup"] is OpenAIProvider


class TestSettingApiMapDerivation:
    """协议映射派生（C6 收敛至 provider_registry）：内容与现状逐项一致，resolve_api_provider 语义不变"""

    def test_provider_api_map_matches_current_six(self) -> None:
        """API_PROVIDER_MAP 派生结果 == 现状 6 项（第三方 → openai）"""
        assert provider_registry_module.API_PROVIDER_MAP == {
            "deepseek": "openai",
            "qwen": "openai",
            "kimi": "openai",
            "glm": "openai",
            "minimax": "openai",
            "step": "openai",
        }

    def test_resolve_api_provider_semantics(self) -> None:
        """claude/openai 回退自身；共享协议者映射到 openai；未知 Provider 原样返回"""
        assert provider_registry_module.resolve_api_provider("claude") == "claude"
        assert provider_registry_module.resolve_api_provider("openai") == "openai"
        assert provider_registry_module.resolve_api_provider("deepseek") == "openai"
        assert provider_registry_module.resolve_api_provider("unknown") == "unknown"


class TestProviderRegistryMeta:
    """provider_registry 深模块契约锁：派生视图与 AVAILABLE_MODELS 源头防漂移比对"""

    def test_provider_keys_match_declaration_order(self) -> None:
        """PROVIDER_KEYS 与 AVAILABLE_MODELS provider 声明序逐项一致（防漂移根 1）"""
        from backend.app.services import provider_registry as registry

        expected = tuple(p["key"] for p in AVAILABLE_MODELS["providers"])
        assert registry.PROVIDER_KEYS == expected
        assert isinstance(registry.PROVIDER_KEYS, tuple)

    def test_api_provider_map_matches_derivation(self) -> None:
        """API_PROVIDER_MAP 与 AVAILABLE_MODELS 派生（key≠id 过滤）逐项一致（防漂移根 2）"""
        from backend.app.services import provider_registry as registry

        expected = {
            p["key"]: p["id"]
            for p in AVAILABLE_MODELS["providers"]
            if p["key"] != p["id"]
        }
        assert registry.API_PROVIDER_MAP == expected

    def test_api_provider_map_excludes_own_protocol(self) -> None:
        """映射不收录 key==id 的自身协议（claude/openai 不在此映射）"""
        from backend.app.services import provider_registry as registry

        assert "claude" not in registry.API_PROVIDER_MAP
        assert "openai" not in registry.API_PROVIDER_MAP

    def test_openai_protocol_models_matches_union(self) -> None:
        """OPENAI_PROTOCOL_MODELS 与 AVAILABLE_MODELS 手工并集逐项一致（防漂移根 3）"""
        from backend.app.services import provider_registry as registry

        expected = frozenset(
            model
            for p in AVAILABLE_MODELS["providers"]
            if p["id"] == "openai"
            for model in p.get("models", [])
        )
        assert registry.OPENAI_PROTOCOL_MODELS == expected
        assert isinstance(registry.OPENAI_PROTOCOL_MODELS, frozenset)

    def test_openai_protocol_models_is_nonempty_and_sensible(self) -> None:
        """openai 协议族模型集非空且含各主流族成员（现状事实锁定）"""
        from backend.app.services import provider_registry as registry

        assert len(registry.OPENAI_PROTOCOL_MODELS) > 10
        assert "deepseek-v4-flash" in registry.OPENAI_PROTOCOL_MODELS
        assert "qwen-max" in registry.OPENAI_PROTOCOL_MODELS
        assert "gpt-5.6-sol" in registry.OPENAI_PROTOCOL_MODELS
        # claude 模型（claude 协议）不得混入 openai 族
        assert not any(m.startswith("claude") for m in registry.OPENAI_PROTOCOL_MODELS)

    def test_resolve_api_provider_semantics(self) -> None:
        """resolve_api_provider：映射者返回协议 id；claude/openai/未知回退自身"""
        from backend.app.services import provider_registry as registry

        assert registry.resolve_api_provider("deepseek") == "openai"
        assert registry.resolve_api_provider("claude") == "claude"
        assert registry.resolve_api_provider("openai") == "openai"
        assert registry.resolve_api_provider("unknown") == "unknown"

    def test_registry_all_exports_are_public(self) -> None:
        """provider_registry __all__ 恰好列出 4 个导出符号（深模块协议表面收缩）"""
        from backend.app.services import provider_registry as registry

        assert sorted(registry.__all__) == [
            "API_PROVIDER_MAP",
            "OPENAI_PROTOCOL_MODELS",
            "PROVIDER_KEYS",
            "resolve_api_provider",
        ]

    def test_registry_derived_at_import_time_and_consistent(self) -> None:
        """派生视图在 import 时固定：模块属性与源头重复读取一致（无懒加载分叉）"""
        from backend.app.services import provider_registry as registry

        assert registry.PROVIDER_KEYS[0] == "claude"
        assert registry.PROVIDER_KEYS[-1] == "step"
        assert list(registry.API_PROVIDER_MAP) == [
            "deepseek",
            "qwen",
            "kimi",
            "glm",
            "minimax",
            "step",
        ]
