"""
单元测试 — 游戏生成服务（backend/app/services/game_generator.py）

测试范围：
    1. validate_generated_html — 校验闸门六项检查
    2. _try_extract_scenes — 场景数据提取
    3. _sanitize_title — 标题净化
    4. _build_*_prompt — prompt 构造
    5. _build_suggestion — 修正建议
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend.app.services.game_generator import (
    MAX_RETRIES,
    ScanResult,
    ValidationError,
    _build_suggestion,
    _build_system_prompt,
    _build_user_prompt,
    _sanitize_title,
    _try_extract_scenes,
    generate_game,
    scan_generated_html,
    validate_generated_html,
)

__all__ = [
    "TestValidateGeneratedHtml",
    "TestTryExtractScenes",
    "TestSanitizeTitle",
    "TestSanitizeTitleFalsify",
    "TestBuildSuggestion",
    "TestPromptConstruction",
    "TestGenerateGame",
    "TestGenerateEndpointWire",
    "TestScanGeneratedHtml",
]

# ═══════════════════════════════════════════════════════════
# 辅助：生成测试用的有效 HTML
# ═══════════════════════════════════════════════════════════


def _make_valid_html(*, scenes: list | None = None) -> str:
    """生成一个格式合法的完整 HTML（用于通过校验闸门的基线）"""
    config = json.dumps({"title": "测试世界", "world": "一个用于测试的世界"}, ensure_ascii=False)
    if scenes is None:
        scenes = [
            {"id": "start", "narrative": "你站在一片空地上。", "choices": [{"text": "向前走", "next": "forest"}]},
            {"id": "forest", "narrative": "你走进了一片森林。", "choices": []},
        ]
    scenes_json = json.dumps(scenes, ensure_ascii=False)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>测试游戏</title></head>
<body>
<div id="game-wrap">
<div id="game-narrative"></div>
<div id="game-choices"></div>
</div>
<input type="hidden" id="cfg-endpoint">
<input type="hidden" id="cfg-apikey">
<input type="hidden" id="cfg-model">
<script>
var GAME_CONFIG = {config};
var GAME_SCENES = {scenes_json};
</script>
</body>
</html>"""


# ═══════════════════════════════════════════════════════════
# Test: validate_generated_html
# ═══════════════════════════════════════════════════════════


class TestValidateGeneratedHtml:
    """校验闸门六项检查"""

    def test_passes_valid_html(self) -> None:
        """合法 HTML → 空错误列表"""
        html = _make_valid_html()
        errors = validate_generated_html(html)
        assert errors == []

    def test_fails_missing_doctype(self) -> None:
        """缺少 <!DOCTYPE html> 且无 <html> → structure 错误"""
        html = "<div>no html</div>"
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "structure" in fields

    def test_fails_template_marker_left(self) -> None:
        """残留 <!-- GEN: --> 标记 → template 错误"""
        html = _make_valid_html().replace(
            'var GAME_CONFIG =',
            'var GAME_CONFIG = <!-- GEN:config -->',
        )
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "template" in fields

    def test_fails_lowercase_template_marker(self) -> None:
        """残留小写 <!-- gen:config --> 标记 → template 错误（大小写不敏感）"""
        html = _make_valid_html().replace(
            'var GAME_CONFIG =',
            'var GAME_CONFIG = <!-- gen:config -->',
        )
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "template" in fields

    def test_fails_missing_cfg(self) -> None:
        """缺少 cfg-endpoint → cfg 错误"""
        html = _make_valid_html().replace('id="cfg-endpoint"', 'id="not-endpoint"')
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "cfg" in fields

    def test_fails_missing_all_cfg(self) -> None:
        """全部 cfg- 输入框缺失 → cfg 错误"""
        html = _make_valid_html()
        for cid in ["cfg-endpoint", "cfg-apikey", "cfg-model"]:
            html = html.replace(f'id="{cid}"', f'id="x-{cid}"')
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "cfg" in fields

    def test_cfg_in_comment_is_ignored(self) -> None:
        """cfg- id 只出现在 HTML 注释里（假阳性）→ 报 cfg 错误"""
        html = _make_valid_html().replace(
            '<input type="hidden" id="cfg-endpoint">',
            '<!-- <input type="hidden" id="cfg-endpoint"> 注释中的假配置框 -->',
        )
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "cfg" in fields

    def test_html_parseability_no_crash(self) -> None:
        """html.parser 容忍残缺输入：不抛异常（crash 回归测试）"""
        from backend.app.services.game_generator import _check_html_parseability
        # 函数应不抛异常（内部 try/except 兜底）
        _check_html_parseability("<!DOCTYPE html><html><body><script>broken")

    def test_html_parseability_valid(self) -> None:
        """合法 HTML → _check_html_parseability 返回 None"""
        from backend.app.services.game_generator import _check_html_parseability
        result = _check_html_parseability(_make_valid_html())
        assert result is None

    def test_fails_empty_scenes(self) -> None:
        """空场景数组 → data 错误"""
        html = _make_valid_html(scenes=[])
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "data" in fields

    def test_fails_scene_missing_narrative(self) -> None:
        """场景缺少 narrative → data 错误"""
        html = _make_valid_html(scenes=[
            {"id": "start", "narrative": "", "choices": []},
        ])
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "data" in fields

    def test_fails_scene_choice_broken_reference(self) -> None:
        """选项引用不存在的场景 → data 错误"""
        html = _make_valid_html(scenes=[
            {"id": "start", "narrative": "开头", "choices": [{"text": "走", "next": "nonexistent"}]},
        ])
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "data" in fields

    def test_detects_suspicious_patterns(self) -> None:
        """含 eval 模式 → security 错误"""
        html = _make_valid_html().replace(
            '</script>', 'eval("danger");\n</script>',
        )
        errors = validate_generated_html(html)
        fields = {e.field for e in errors}
        assert "security" in fields

    def test_collects_multiple_errors(self) -> None:
        """同时缺失多个条件 → 收集全部错误"""
        html = "not a valid html at all"
        errors = validate_generated_html(html)
        assert len(errors) >= 1
        fields = {e.field for e in errors}
        assert "structure" in fields
        # 也可能同时检出 template（没有 GEN: = 通过）/ cfg（没有 input = 失败）
        assert "cfg" in fields

    # ── precomputed_scan 参数（T-03 双重扫描消除）──

    def test_precomputed_warnings_used_for_security(self) -> None:
        """precomputed_scan 传入 → 检查 5 采用预计算 warnings（HTML 实际干净但 precomputed 报 eval → 报 security）"""
        scan = ScanResult(game_type="ai", config=None, warnings=["eval"])
        html = _make_valid_html()  # 实际无 eval
        errors = validate_generated_html(html, precomputed_scan=scan)
        assert "security" in {e.field for e in errors}

    def test_precomputed_empty_warnings_suppress_rescan(self) -> None:
        """precomputed warnings=[] 而 HTML 实际含 eval → 不报 security（证明检查 5 未重扫）"""
        html = _make_valid_html().replace("</script>", 'eval("x");\n</script>')
        scan = ScanResult(game_type="ai", config=None, warnings=[])
        errors = validate_generated_html(html, precomputed_scan=scan)
        assert "security" not in {e.field for e in errors}
        assert "data" not in {e.field for e in errors}  # 其余检查不受干扰

    def test_no_precomputed_still_scans_security(self) -> None:
        """不传 precomputed → 检查 5 自行扫描（现状逐字一致；HTML 含 eval → security 错误）"""
        html = _make_valid_html().replace("</script>", 'eval("x");\n</script>')
        errors = validate_generated_html(html)
        assert "security" in {e.field for e in errors}


# ═══════════════════════════════════════════════════════════
# Test: scan_generated_html（T-03 单次扫描打包）
# ═══════════════════════════════════════════════════════════


class TestScanGeneratedHtml:
    """scan_generated_html（T-03：单次扫描打包 ScanResult，供校验闸门与导入复用）"""

    def test_valid_html_ai(self) -> None:
        """合法生成 HTML → ai + config 三元组 + 无警告"""
        scan = scan_generated_html(_make_valid_html())
        assert scan.game_type == "ai"
        assert scan.config == {
            "endpoint": "cfg-endpoint",
            "apikey": "cfg-apikey",
            "model": "cfg-model",
        }
        assert scan.warnings == []

    def test_suspicious_html_warnings(self) -> None:
        """含 eval / document.cookie → warnings 键集（排序确定，不拦截）"""
        html = _make_valid_html().replace("</script>", 'eval("x"); document.cookie;\n</script>')
        scan = scan_generated_html(html)
        assert scan.game_type == "ai"  # cfg 三元组仍然命中
        assert scan.warnings == ["document.cookie", "eval"]

    def test_local_html_no_cfg(self) -> None:
        """无 cfg 三元组 → local + config None"""
        scan = scan_generated_html("<html><body>纯本地</body></html>")
        assert scan.game_type == "local"
        assert scan.config is None

    def test_probe_and_scan_called_exactly_once(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """mock 计数：probe_config / scan_suspicious 各恰好 1 次（单次扫描契约）"""
        from backend.app.services import game_generator as gg
        calls = {"probe": 0, "scan": 0}
        real_probe, real_scan = gg.probe_config, gg.scan_suspicious

        def counting_probe(text: str) -> object:
            calls["probe"] += 1
            return real_probe(text)

        def counting_scan(text: str) -> object:
            calls["scan"] += 1
            return real_scan(text)

        monkeypatch.setattr(gg, "probe_config", counting_probe)
        monkeypatch.setattr(gg, "scan_suspicious", counting_scan)
        scan_generated_html(_make_valid_html())
        assert calls == {"probe": 1, "scan": 1}


# ═══════════════════════════════════════════════════════════
# Test: _try_extract_scenes
# ═══════════════════════════════════════════════════════════


class TestTryExtractScenes:
    """场景数据提取"""

    def test_extracts_valid_scenes(self) -> None:
        """合法场景数据 → 成功返回场景列表"""
        html = _make_valid_html()
        scenes, error = _try_extract_scenes(html)
        assert error is None
        assert scenes is not None
        assert len(scenes) == 2
        assert scenes[0]["id"] == "start"

    def test_missing_game_scenes(self) -> None:
        """HTML 中无 GAME_SCENES → 报错"""
        html = "<html><body>no scenes</body></html>"
        scenes, error = _try_extract_scenes(html)
        assert scenes is None
        assert error is not None
        assert "未找到" in error

    def test_invalid_scene_json(self) -> None:
        """GAME_SCENES 值不是合法 JSON → 报错"""
        html = """<html><body><script>
var GAME_SCENES = [not json];
</script></body></html>"""
        scenes, error = _try_extract_scenes(html)
        assert scenes is None
        assert error is not None
        assert "JSON 解析失败" in error

    def test_scenes_not_array(self) -> None:
        """GAME_SCENES 是字符串而非数组 → regex 不匹配（非数组形态不在提取契约内）"""
        html = """<html><body><script>
var GAME_SCENES = "not an array";
</script></body></html>"""
        scenes, error = _try_extract_scenes(html)
        assert scenes is None
        assert error is not None
        # 非数组形态不匹配数组字面量正则 → 报「未找到」而非「必须是数组」
        assert "未找到" in error

    def test_scene_missing_choices(self) -> None:
        """场景缺少 choices 字段 → 报错"""
        html = _make_valid_html(scenes=[
            {"id": "start", "narrative": "开头"},
        ])
        scenes, error = _try_extract_scenes(html)
        assert scenes is None
        assert error is not None
        assert "choices" in error

    def test_duplicate_scene_ids(self) -> None:
        """两个场景 id 相同 → 报数据错误（去重）"""
        html = _make_valid_html(scenes=[
            {"id": "start", "narrative": "开头", "choices": []},
            {"id": "start", "narrative": "另一个开头", "choices": []},
        ])
        scenes, error = _try_extract_scenes(html)
        assert scenes is None
        assert error is not None
        assert "重复" in error

    def test_narrative_with_semicolon_bracket(self) -> None:
        """narrative 文本含 '];' 不应导致提前截断（合法游戏应成功解析）"""
        scenes = [
            {"id": "start", "narrative": "他喃喃道：『这不可能…']; 黑暗吞噬了一切。」", "choices": [{"text": "继续", "next": "end"}]},
            {"id": "end", "narrative": "终局。", "choices": []},
        ]
        html = _make_valid_html(scenes=scenes)
        extracted, error = _try_extract_scenes(html)
        assert error is None
        assert extracted is not None
        assert len(extracted) == 2
        assert extracted[0]["id"] == "start"

    def test_self_reference_allowed(self) -> None:
        """自引用 next → 通过校验（无限循环是叙事自由）"""
        scenes = [
            {"id": "start", "narrative": "开头", "choices": [{"text": "永远留下", "next": "start"}]},
        ]
        html = _make_valid_html(scenes=scenes)
        extracted, error = _try_extract_scenes(html)
        assert error is None
        assert extracted is not None
        assert extracted[0]["choices"][0]["next"] == "start"

    def test_mutual_cycle_allowed(self) -> None:
        """双向循环 next → 通过校验（设计允许）"""
        scenes = [
            {"id": "a", "narrative": "A 场景", "choices": [{"text": "去 B", "next": "b"}]},
            {"id": "b", "narrative": "B 场景", "choices": [{"text": "回 A", "next": "a"}]},
        ]
        html = _make_valid_html(scenes=scenes)
        extracted, error = _try_extract_scenes(html)
        assert error is None
        assert extracted is not None
        assert len(extracted) == 2


# ═══════════════════════════════════════════════════════════
# Test: _sanitize_title
# ═══════════════════════════════════════════════════════════


class TestSanitizeTitle:
    """标题净化"""

    def test_normal_title(self) -> None:
        """正常中文标题 → 保留中文"""
        assert _sanitize_title("霓虹追迹") == "霓虹追迹"

    def test_title_with_special_chars(self) -> None:
        """含特殊字符 → 剔除"""
        assert _sanitize_title("测试: 世界!") == "测试 世界"

    def test_title_with_spaces(self) -> None:
        """含空格 → 保留"""
        assert _sanitize_title("My Game") == "My Game"

    def test_empty_title(self) -> None:
        """空标题 → 回退默认名"""
        assert _sanitize_title("") == "generated-game"

    def test_title_with_hyphen(self) -> None:
        """含连字符 → 保留"""
        assert _sanitize_title("test-game") == "test-game"

    def test_title_with_underscore(self) -> None:
        """含下划线 → 保留"""
        assert _sanitize_title("test_game") == "test_game"


class TestSanitizeTitleFalsify:
    """标题净化 — Falsify 边界（证伪：让函数崩溃的输入）"""

    def test_title_with_colon_and_exclamation(self) -> None:
        """标题含冒号、感叹号、括号 → 剔除（保留 Unicode 文字字符）"""
        assert _sanitize_title("Game: V2!") == "Game V2"

    def test_title_all_punctuation(self) -> None:
        """标题全为标点 → 回退"""
        assert _sanitize_title("!!!：（）") == "generated-game"

    def test_title_only_hyphens(self) -> None:
        """标题仅含连字符 → 保留（- 在白名单内）"""
        assert _sanitize_title("---") == "---"

    def test_title_with_emoji(self) -> None:
        """标题含 emoji → 剔除"""
        assert _sanitize_title("🎮 游戏测试") == "游戏测试"

    def test_title_with_leading_trailing_whitespace(self) -> None:
        """标题首尾空白 → 剔除"""
        assert _sanitize_title("  我的游戏  ") == "我的游戏"


# ═══════════════════════════════════════════════════════════
# Test: _build_suggestion
# ═══════════════════════════════════════════════════════════


class TestBuildSuggestion:
    """修正建议"""

    def test_structure_error(self) -> None:
        """structure 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="structure", message="缺少 <!DOCTYPE html>")])
        assert "DOCTYPE" in suggestion

    def test_template_error(self) -> None:
        """template 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="template", message="模板标记未填充")])
        assert "GEN" in suggestion

    def test_cfg_error(self) -> None:
        """cfg 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="cfg", message="缺少 cfg-endpoint")])
        assert "cfg" in suggestion

    def test_syntax_error(self) -> None:
        """syntax 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="syntax", message="未闭合标签")])
        assert "语法" in suggestion

    def test_data_error(self) -> None:
        """data 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="data", message="场景数据无效")])
        assert "场景数据" in suggestion

    def test_security_error(self) -> None:
        """security 错误 → 对应建议"""
        suggestion = _build_suggestion([ValidationError(field="security", message="检测到 eval")])
        assert "可疑" in suggestion

    def test_multiple_errors(self) -> None:
        """多个错误 → 合并建议"""
        errors = [
            ValidationError(field="structure", message="缺少 DOCTYPE"),
            ValidationError(field="cfg", message="缺少 cfg-endpoint"),
        ]
        suggestion = _build_suggestion(errors)
        assert "DOCTYPE" in suggestion
        assert "cfg" in suggestion

    def test_empty_errors_fallback(self) -> None:
        """空错误列表 → 通用建议"""
        suggestion = _build_suggestion([])
        assert "请重新生成" in suggestion


# ═══════════════════════════════════════════════════════════
# Test: Prompt 构造
# ═══════════════════════════════════════════════════════════


class TestPromptConstruction:
    """Prompt 构造"""

    def test_system_prompt_contains_template_markers(self) -> None:
        """系统提示词包含模板标记说明"""
        prompt = _build_system_prompt()
        assert "GEN:config" in prompt
        assert "GEN:scenes" in prompt
        assert "seed_template" in prompt or "模板" in prompt

    def test_system_prompt_contains_example(self) -> None:
        """系统提示词包含示例"""
        prompt = _build_system_prompt()
        assert "示例" in prompt

    def test_user_prompt_with_title(self) -> None:
        """带标题的用户提示词"""
        prompt = _build_user_prompt("一个魔法世界", title="魔法学院")
        assert "魔法学院" in prompt
        assert "魔法世界" in prompt

    def test_user_prompt_without_title(self) -> None:
        """不带标题的用户提示词"""
        prompt = _build_user_prompt("一个赛博朋克世界")
        assert "赛博朋克世界" in prompt
        assert "游戏标题" not in prompt

    def test_max_retries_constant(self) -> None:
        """最大重试次数为 3"""
        assert MAX_RETRIES == 3


# ═══════════════════════════════════════════════════════════
# Test: generate_game（异步编排）
# ═══════════════════════════════════════════════════════════


class _MockLLM:
    """假 LLM，构造时固定返回指定结果（含 None 等非字符串类型）"""

    def __init__(self, result: object = None, raise_error: Exception | None = None) -> None:
        self.result = result
        self.raise_error = raise_error

    async def generate(
        self,
        messages: list[dict],
        temperature: float = 0.7,
        max_tokens: int = 2048,
        model: str | None = None,
    ) -> object:
        if self.raise_error:
            raise self.raise_error
        return self.result


@pytest.mark.asyncio
class TestGenerateGame:
    """generate_game 编排（异步）"""

    async def test_llm_returns_none_no_crash(
        self, db_session, monkeypatch
    ) -> None:
        """LLM 返回 None → 不抛 AttributeError，返回错误结果"""
        mock_llm = _MockLLM(result=None)
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        monkeypatch.setattr(
            "backend.app.services.game_generator._persist_generated_game",
            lambda html, title, **kwargs: {"id": "test", "file": "test.html"},
        )

        result = await generate_game(db=db_session, description="test world")

        assert result.ok is False
        assert result.errors is not None
        assert any("非字符串" in e.message for e in result.errors)

    async def test_llm_returns_bytes_no_crash(
        self, db_session, monkeypatch
    ) -> None:
        """LLM 返回 bytes → 不抛 AttributeError（validate_generated_html 需要 str）"""
        mock_llm = _MockLLM(result=b"<html>bytes</html>")
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        monkeypatch.setattr(
            "backend.app.services.game_generator._persist_generated_game",
            lambda html, title, **kwargs: {"id": "test", "file": "test.html"},
        )

        result = await generate_game(db=db_session, description="test world")

        assert result.ok is False
        assert result.errors is not None
        assert any("非字符串" in e.message for e in result.errors)

    async def test_empty_string_retry_passes_previous_html(
        self, db_session, monkeypatch
    ) -> None:
        """空字符串 previous_html 不应导致重试退化为全新 prompt（is not None 判定）"""
        mock_llm = _MockLLM(result="<!DOCTYPE html><html><body>test</body></html>")
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        monkeypatch.setattr(
            "backend.app.services.game_generator._persist_generated_game",
            lambda html, title, **kwargs: {"id": "test", "file": "test.html"},
        )

        # 重试时 previous_html=""（空字符串）—— 应走 retry prompt 路径
        errors = [ValidationError(field="data", message="场景数据异常")]
        # 令 validate_generated_html 首次返回错误，第二次返回空（通过）
        call_count = 0

        def _validate(html: str, **kwargs: object) -> list:
            nonlocal call_count
            call_count += 1
            if call_count <= 1:
                # 首次调用返回错误
                return errors
            return []

        monkeypatch.setattr(
            "backend.app.services.game_generator.validate_generated_html",
            _validate,
        )

        result = await generate_game(
            db=db_session,
            description="test world",
            previous_html="",  # 空字符串，非 None
            previous_errors=errors,
            previous_suggestion="请修正场景数据",
            retries_left=1,
            attempted=0,
        )

        # 应触发重试（第二次调用时通过），最终成功
        assert result.ok is True
        assert result.game is not None

    async def test_generation_path_scans_only_once(
        self, db_session, monkeypatch, tmp_path: Path
    ) -> None:
        """生成路径单次扫描（T-03 核心验收）：import_game 内部不再重复 probe/scan——
        全链路（真实校验 + 真实落盘）下，simulator_import 层的 probe_config /
        scan_suspicious 调用次数为 0（precomputed 路径生效）
        """
        from backend.app.services import simulator_import as sim_import

        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", _MockLLM(result=_make_valid_html())),
        )

        calls = {"probe": 0, "scan": 0}
        real_probe, real_scan = sim_import.probe_config, sim_import.scan_suspicious

        def counting_probe(text: str) -> object:
            calls["probe"] += 1
            return real_probe(text)

        def counting_scan(text: str) -> object:
            calls["scan"] += 1
            return real_scan(text)

        monkeypatch.setattr(sim_import, "probe_config", counting_probe)
        monkeypatch.setattr(sim_import, "scan_suspicious", counting_scan)

        result = await generate_game(db=db_session, description="test world")

        assert result.ok is True
        # 关键验收：probe/scan 在 import_game 内部各 0 次（precomputed 路径生效，
        # 生成路径的扫描由 scan_generated_html 完成，import_game 不再重复）
        assert calls == {"probe": 0, "scan": 0}
        # 产物落盘（真实 persist 路径）
        assert result.game is not None
        assert result.game["source"] == "generated"
        assert (tmp_path / "simulators").is_dir()


# ═══════════════════════════════════════════════════════════
# Wire: POST /api/simulators/generate（TestClient）
# ═══════════════════════════════════════════════════════════


class TestGenerateEndpointWire:
    """路由 wire（TestClient）：状态码 + 响应形状契约（spec 生成接口）"""

    @pytest.fixture
    def generate_app(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> FastAPI:
        """最小应用（仅模拟器路由 + 错误处理器）；CONVER_DATA_DIR 指向临时目录"""
        monkeypatch.setenv("CONVER_DATA_DIR", str(tmp_path))
        from fastapi import FastAPI
        from backend.app.api.routes import simulators as simulators_route
        from backend.app.api.errors import llm_error_handler
        from backend.app.services.llm.errors import LLMError

        app = FastAPI()
        app.include_router(simulators_route.router)
        app.add_exception_handler(LLMError, llm_error_handler)
        return app

    @pytest.fixture
    def mock_llm(self) -> _MockLLM:
        """返回合法 HTML 的 MockLLM（_make_valid_html 是模块级辅助函数）"""
        return _MockLLM(result=_make_valid_html())

    def _post(self, client: TestClient, description: str = "test world",
              title: str | None = None) -> object:
        body = {"description": description}
        if title:
            body["title"] = title
        return client.post("/api/simulators/generate", json=body)

    def test_happy_path_response_shape(self, generate_app: FastAPI,
                                        db_session, monkeypatch,
                                        mock_llm) -> None:
        """合法描述 → 200 + {ok, game{source:generated}, retries}"""
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        from backend.app.database import get_db
        generate_app.dependency_overrides[get_db] = lambda: db_session

        with TestClient(generate_app) as client:
            resp = self._post(client, "一个赛博朋克世界")

        assert resp.status_code == 200
        body = resp.json()
        assert body["ok"] is True
        assert body["game"]["source"] == "generated"
        assert "id" in body["game"]
        assert "file" in body["game"]
        assert "retries" in body

    def test_validation_failure_422(self, generate_app: FastAPI,
                                     db_session, monkeypatch) -> None:
        """LLM 返回无场景 HTML → 422 + 结构化错误"""
        mock_llm = _MockLLM(result="<html><body>no scene data</body></html>")
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        from backend.app.database import get_db
        generate_app.dependency_overrides[get_db] = lambda: db_session

        with TestClient(generate_app) as client:
            resp = self._post(client, "测试描述")

        assert resp.status_code == 422
        body = resp.json()
        detail = body["detail"]
        assert detail["ok"] is False
        assert isinstance(detail["errors"], list)
        assert len(detail["errors"]) > 0
        assert "suggestion" in detail
        assert "retries" in detail

    def test_llm_returns_none_422(self, generate_app: FastAPI,
                                   db_session, monkeypatch) -> None:
        """LLM 返回 None → 422（非字符串类型错误），不崩溃"""
        mock_llm = _MockLLM(result=None)
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        from backend.app.database import get_db
        generate_app.dependency_overrides[get_db] = lambda: db_session

        with TestClient(generate_app) as client:
            resp = self._post(client, "测试描述")

        assert resp.status_code == 422
        detail = resp.json()["detail"]
        assert detail["ok"] is False
        assert any("非字符串" in e["message"] for e in detail["errors"])

    def test_duplicate_409(self, generate_app: FastAPI,
                            db_session, monkeypatch,
                            mock_llm, tmp_path: Path) -> None:
        """相同内容两次生成 → 第二次 409（SHA-256 重复，detail 含「已存在」）"""
        monkeypatch.setattr(
            "backend.app.services.game_generator.resolve_llm",
            lambda db, provider: ("test", "test-model", mock_llm),
        )
        from backend.app.database import get_db
        generate_app.dependency_overrides[get_db] = lambda: db_session

        with TestClient(generate_app) as client:
            # 第一次：成功
            resp1 = self._post(client, "世界描述")
            assert resp1.status_code == 200

            # 第二次：相同内容 → 重复
            resp2 = self._post(client, "世界描述")
            assert resp2.status_code == 409
            assert "已存在" in resp2.json()["detail"]