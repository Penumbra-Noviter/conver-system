"""
文档解析服务单元测试

覆盖：
- 正常 LLM 响应解析
- JSON 代码块提取
- 花括号范围提取
- 空字段处理
- LLM 调用失败场景
- API Key 缺失场景
"""

from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest

from backend.app.schemas.character import DocParseResponse
from backend.app.services.document_parser import _extract_json, parse_document
from backend.app.services.exceptions import DocParseError, ProviderNotSupportedError

__all__: list[str] = []


# ── _extract_json 测试 ──


class TestExtractJson:
    """测试 LLM 输出中 JSON 提取的三种策略"""

    def test_direct_json(self) -> None:
        """完整 JSON 直接解析"""
        result = _extract_json('{"name": "小红", "personality": "活泼"}')
        assert result == {"name": "小红", "personality": "活泼"}

    def test_json_code_block(self) -> None:
        """从 ```json 代码块中提取"""
        raw = "以下是我提取的结果：\n```json\n{\"name\": \"小红\"}\n```\n请确认。"
        result = _extract_json(raw)
        assert result == {"name": "小红"}

    def test_json_code_block_no_lang(self) -> None:
        """从 ``` 代码块提取（无语言标记）"""
        raw = "结果：\n```\n{\"name\": \"测试\"}\n```"
        result = _extract_json(raw)
        assert result == {"name": "测试"}

    def test_brace_extraction(self) -> None:
        """从花括号范围提取"""
        raw = "前面文字 {\"name\": \"小明\", \"personality\": \"安静\"} 后面文字"
        result = _extract_json(raw)
        assert result == {"name": "小明", "personality": "安静"}

    def test_no_json(self) -> None:
        """无 JSON 内容返回 None"""
        result = _extract_json("纯文本，没有任何 JSON 结构")
        assert result is None

    def test_empty_string(self) -> None:
        """空字符串返回 None"""
        result = _extract_json("")
        assert result is None

    def test_non_dict_json(self) -> None:
        """非 dict 的 JSON 返回 None（但 get 会过）"""
        # 列表 JSON
        result = _extract_json('["a", "b"]')
        assert result is None


# ── parse_document 测试 ──


class MockLLM:
    """模拟 LLM Provider"""

    def __init__(self, response: str | None = None, error: Exception | None = None):
        self._response = response
        self._error = error

    async def generate(self, messages, **kwargs) -> str:
        if self._error:
            raise self._error
        return self._response or "{}"


class TestParseDocument:
    """测试 parse_document 主流程"""

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_success(self, mock_setting, mock_factory) -> None:
        """正常解析返回完整字段"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(response='{"name": "小红", "personality": "活泼开朗", "first_mes": "你好！", "tags": ["可爱", "活泼"]}')
        mock_factory.return_value = llm

        result = await parse_document(None, "小红是一个活泼的角色")

        assert isinstance(result, DocParseResponse)
        assert result.name == "小红"
        assert result.personality == "活泼开朗"
        assert result.first_mes == "你好！"
        assert result.tags == ["可爱", "活泼"]
        assert "name" in result.parsed_fields
        assert "personality" in result.parsed_fields

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_empty_fields(self, mock_setting, mock_factory) -> None:
        """缺失字段应返回空字符串/空列表"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(response='{"name": "测试"}')
        mock_factory.return_value = llm

        result = await parse_document(None, "测试文本")

        assert result.name == "测试"
        assert result.description == ""
        assert result.personality == ""
        assert result.tags == []
        assert result.parsed_fields == ["name"]

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_code_block(self, mock_setting, mock_factory) -> None:
        """LLM 返回代码块也能正确提取"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(response="```json\n{\"name\": \"代码块角色\"}\n```")
        mock_factory.return_value = llm

        result = await parse_document(None, "测试")

        assert result.name == "代码块角色"

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_non_json_response(self, mock_setting, mock_factory) -> None:
        """LLM 返回非 JSON 应抛 DocParseError"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(response="这只是一段普通的文本，没有 JSON")
        mock_factory.return_value = llm

        with pytest.raises(DocParseError, match="无法解析"):
            await parse_document(None, "测试")

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_llm_error(self, mock_setting, mock_factory) -> None:
        """LLM 调用失败应抛 DocParseError"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(error=Exception("API 超时"))
        mock_factory.return_value = llm

        with pytest.raises(DocParseError, match="LLM 调用失败"):
            await parse_document(None, "测试")

    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_no_api_key(self, mock_setting) -> None:
        """未配置 API Key 应抛 DocParseError"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.api_key.return_value = ""

        with pytest.raises(DocParseError, match="未配置 API Key"):
            await parse_document(None, "测试")

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_unsupported_provider(self, mock_setting, mock_factory) -> None:
        """API Key 已配置 + Provider 不支持 → DocParseError：422 + 基线文案逐字

        基线 wire：不支持的 Provider → 422「不支持的 Provider: {provider}」（旧
        document_parser 捕获 ValueError 转 DocParseError）。Key 已配置时 resolver
        抛 ProviderNotSupportedError，此处必须同样转 DocParseError，不得让
        ProviderNotSupportedError 逃逸（那会经 handler 变 400）。
        """
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""
        mock_factory.side_effect = ProviderNotSupportedError("不支持的 Provider: foo")

        with pytest.raises(DocParseError) as exc:
            await parse_document(None, "测试", provider="foo")

        assert str(exc.value) == "不支持的 Provider: foo"

    @patch("backend.app.services.llm.resolver.LLMFactory.get_provider")
    @patch("backend.app.services.llm.resolver.setting_service")
    async def test_parse_tags_as_list(self, mock_setting, mock_factory) -> None:
        """tags 字段应正确处理为列表"""
        mock_setting.default_provider.return_value = "claude"
        mock_setting.default_model.return_value = "claude-sonnet-5"
        mock_setting.api_key.return_value = "sk-test"
        mock_setting.base_url.return_value = ""

        llm = MockLLM(response='{"name": "标签测试", "tags": ["奇幻", "冒险", "魔法"]}')
        mock_factory.return_value = llm

        result = await parse_document(None, "测试")

        assert result.tags == ["奇幻", "冒险", "魔法"]
        assert "tags" in result.parsed_fields