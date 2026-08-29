/// LLMFactory — 具体 [LLMProviderFactory] 实现（T02 装配层）。
///
/// 派生规则逐字对齐 `desktop/backend/app/services/llm/factory.py`
/// （`register_builtin_providers`）：`claude` → [ClaudeProvider]；
/// `ModelCatalog.resolveApiProvider(key) == "openai"`（覆盖 openai 自身与全部
/// OpenAI 兼容第三方，协议解析源头为 model_catalog）→ [OpenAIProvider]；
/// 不匹配任何规则 → [ProviderNotSupportedError]「不支持的 Provider: {provider}」。
///
/// 与桌面差异：桌面为注册表 + 懒加载，移动端以无状态纯函数 create 一笔判定
/// （无内置 Provider 列表概念——provider 键写死于两条派生规则，未知即抛错，
/// 语义一致）。
library;

import 'package:conver_system_mobile/models/model_catalog.dart';

import 'claude_provider.dart';
import 'errors.dart';
import 'llm_provider.dart';
import 'openai_provider.dart';

/// 具体 Provider 工厂（唯一装配入口：ChatService / test_connection 依赖本类）。
class LLMFactory implements LLMProviderFactory {
  const LLMFactory();

  @override
  LLMProvider create({
    required String provider,
    required String apiKey,
    String? baseUrl,
  }) {
    if (provider == 'claude') {
      return ClaudeProvider(apiKey: apiKey, baseUrl: baseUrl);
    }
    if (ModelCatalog.resolveApiProvider(provider) == 'openai') {
      return OpenAIProvider(apiKey: apiKey, baseUrl: baseUrl);
    }
    throw ProviderNotSupportedError(provider);
  }
}