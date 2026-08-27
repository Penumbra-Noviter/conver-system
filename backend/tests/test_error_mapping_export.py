"""
T-01: LLM 错误映射迁移至 error_mapping.py — 验证新导出结构

覆盖：
    1. error_mapping 导出 llm_error_response（在 __all__ 中）
    2. llm_error_response 映射正确（401/429/504/400/502 逐字）
    3. Provider 空时 401 无前缀基础文案；非空时带 "{provider} " 前缀
    4. chat.py 不再定义 _LLM_ERROR_MAP 和 llm_error_response
"""

from __future__ import annotations

import pytest

from backend.app.services.error_mapping import llm_error_response
from backend.app.services.llm.errors import (
    LLMAuthError,
    LLMContentFilterError,
    LLMError,
    LLMRateLimitError,
    LLMTimeoutError,
)

__all__: list[str] = []


class _UnregisteredLLMError(LLMError):
    """未注册的 LLMError 子类（验证「基类兜底」契约：未知子类恒 502 + str(e)）"""

    pass


class TestErrorMappingExports:
    """error_mapping 导出验证"""

    def test_llm_error_response_in_all(self) -> None:
        """llm_error_response 在 error_mapping 的 __all__ 中"""
        import backend.app.services.error_mapping as em

        assert "llm_error_response" in em.__all__

    def test_llm_error_response_importable(self) -> None:
        """from backend.app.services.error_mapping import llm_error_response 可用"""
        from backend.app.services.error_mapping import llm_error_response  # noqa: F811

        assert callable(llm_error_response)


class TestLLMErrorResponseMapping:
    """llm_error_response 全映射表逐字验证"""

    def test_auth_with_provider(self) -> None:
        """LLMAuthError + provider → 401 + {provider} API Key 无效，请在设置中更新"""
        e = LLMAuthError("Claude API Key 无效或未配置")
        assert llm_error_response(e, "claude") == (
            401,
            "claude API Key 无效，请在设置中更新",
        )

    def test_auth_without_provider(self) -> None:
        """LLMAuthError + provider=None → 401 + 基础文案，无前导空格"""
        e = LLMAuthError("x")
        status_code, message = llm_error_response(e, None)
        assert not message.startswith(" ")
        assert (status_code, message) == (401, "API Key 无效，请在设置中更新")

    def test_auth_with_empty_provider(self) -> None:
        """LLMAuthError + provider="" → 401 + 基础文案，无前导空格"""
        e = LLMAuthError("x")
        status_code, message = llm_error_response(e, "")
        assert not message.startswith(" ")
        assert (status_code, message) == (401, "API Key 无效，请在设置中更新")

    def test_rate_limit(self) -> None:
        """LLMRateLimitError → 429 + 固定消息"""
        assert llm_error_response(LLMRateLimitError("x"), "claude") == (
            429,
            "API 请求频率超限，请稍后再试",
        )

    def test_timeout(self) -> None:
        """LLMTimeoutError → 504 + 固定消息"""
        assert llm_error_response(LLMTimeoutError("x"), "claude") == (
            504,
            "API 请求超时，请检查网络后重试",
        )

    def test_content_filter(self) -> None:
        """LLMContentFilterError → 400 + str(e)"""
        e = LLMContentFilterError("内容被内容过滤器拦截")
        assert llm_error_response(e, "claude") == (400, str(e))

    def test_base_llm_error(self) -> None:
        """LLMError 基类 → 502 + str(e)"""
        e = LLMError("Claude API 调用失败: boom")
        assert llm_error_response(e, "claude") == (502, str(e))

    def test_unknown_subclass_fallback_502(self) -> None:
        """Falsify：未知 LLMError 子类 → 502 + str(e) 兜底"""

        class _MysteryLLMError(LLMError):
            pass

        e = _MysteryLLMError("未知 LLM 错误")
        assert llm_error_response(e, "claude") == (502, "未知 LLM 错误")


class TestLLMErrorMappingMatrix:
    """全映射矩阵：显式声明「顺序即优先级 / 基类兜底」契约

    以参数化表格覆盖全部映射（含未注册子类 → 502 兜底），逐字断言 (status, msg)。
    本表即映射契约的单一事实来源：新增 LLMError 子类时应在此显式声明其落点，
    而不依赖实现内部「dict 插入顺序 + isinstance 遍历」的隐式行为。
    """

    @pytest.mark.parametrize(
        "exc, provider, expected",
        [
            pytest.param(
                LLMAuthError("x"),
                "claude",
                (401, "claude API Key 无效，请在设置中更新"),
                id="auth-with-provider",
            ),
            pytest.param(
                LLMAuthError("x"),
                "",
                (401, "API Key 无效，请在设置中更新"),
                id="auth-with-empty-provider",
            ),
            pytest.param(
                LLMAuthError("x"),
                None,
                (401, "API Key 无效，请在设置中更新"),
                id="auth-without-provider",
            ),
            pytest.param(
                LLMRateLimitError("x"),
                "claude",
                (429, "API 请求频率超限，请稍后再试"),
                id="rate-limit",
            ),
            pytest.param(
                LLMTimeoutError("x"),
                "claude",
                (504, "API 请求超时，请检查网络后重试"),
                id="timeout",
            ),
            pytest.param(
                LLMContentFilterError("内容被内容过滤器拦截"),
                "claude",
                (400, "内容被内容过滤器拦截"),
                id="content-filter",
            ),
            pytest.param(
                LLMError("Claude API 调用失败: boom"),
                "claude",
                (502, "Claude API 调用失败: boom"),
                id="base-llm-error",
            ),
            pytest.param(
                _UnregisteredLLMError("未知 LLM 错误"),
                "claude",
                (502, "未知 LLM 错误"),
                id="unregistered-subclass-502",
            ),
        ],
    )
    def test_mapping_matrix(self, exc: LLMError, provider: str | None, expected: tuple[int, str]) -> None:
        """映射表逐字：(status, msg) 与契约一致"""
        assert llm_error_response(exc, provider) == expected


class TestChatServiceNoLongerDefines:
    """chat.py 不再定义 _LLM_ERROR_MAP 和 llm_error_response（通过源码文件检查确认）"""

    @staticmethod
    def _chat_source() -> str:
        """返回 chat.py 源码文本"""
        import inspect
        from pathlib import Path

        import backend.app.services.chat as chat_mod

        src_path = Path(inspect.getsourcefile(chat_mod))
        return src_path.read_text(encoding="utf-8")

    def test_llm_error_map_not_defined(self) -> None:
        """chat.py 没有 _LLM_ERROR_MAP 定义"""
        assert "_LLM_ERROR_MAP" not in self._chat_source()

    def test_llm_error_response_not_defined(self) -> None:
        """chat.py 没有 def llm_error_response（已迁至 error_mapping.py）"""
        assert "def llm_error_response" not in self._chat_source()