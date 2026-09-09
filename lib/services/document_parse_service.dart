/// 文档 LLM 解析纯逻辑（M4-04）— 粘贴文档 → 结构化角色字段。
///
/// 桌面权威源（只读，语义锚点）：`desktop/backend/app/services/document_parser.py`
/// （`_PARSE_SYSTEM_PROMPT` 原文逐字 / `parse_document` / `_extract_json` /
/// `_truncate`）与 `desktop/backend/app/services/character_fields.py::PARSE_FIELDS`
/// （10 项白名单）。
///
/// 深模块：协议表面 = [DocumentParseService.parse]（唯一编排入口）+ 顶层纯函数
/// [extractJsonFromLlm]（可独立测）+ [parseSystemPrompt] / [parseFields] 常量 +
/// [truncateError] 辅助 + [DocParseResult] 值对象。只依赖 LLM 抽象
/// （[LLMProvider] / [LLMProviderFactory]）与设置抽象（[SettingsRepository]），
/// 不触具体 Provider / 平台存储（layer_boundary_test 契约）。
library;

import 'dart:convert';

import '../data/repositories/settings_repository.dart';
import 'llm/credentials_resolver.dart';
import 'llm/errors.dart';
import 'llm/llm_provider.dart';

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 wizard/character 控制器惯例）。
// ignore_for_file: prefer_initializing_formals

/// 解析系统提示词 = 桌面 `_PARSE_SYSTEM_PROMPT` 原文逐字迁移。
///
/// 注意 Dart 三引号字符串紧跟首行内容书写（`'''你…`），首行前无换行，与桌面
/// Python 三引号 `"""` 紧跟内容的语义一致；提示词内含 `{{char}}` / `{{user}}`
/// 模板变量与 `<START>` 标记，原样保留。
const String parseSystemPrompt = '''你是一个角色卡解析器。用户会提供一段关于角色的文字描述（可能是小说片段、设定文档、角色简介等），请从中提取以下字段并以 JSON 格式返回：

{
  "name": "角色名称",
  "description": "简短描述（一句话）",
  "personality": "人格设定、性格特征、说话方式、行为模式等核心设定",
  "scenario": "场景设定（对话发生的背景/世界）",
  "first_mes": "开场白（角色首次见面说的话）",
  "mes_example": "对话范例（展示角色说话风格的示例对话）",
  "system_prompt": "系统提示词（如果有明确的指令性内容）",
  "tags": ["标签1", "标签2"],
  "creator": "作者/来源"
}

规则：
1. name 必须提取，无法确定则留空字符串
2. 不要编造文档中没有的信息
3. personality 是核心字段，尽量详细
4. 对话范例用 <START> 标记开头，{{user}} 表示用户，{{char}} 表示角色
5. 不确定的字段留空字符串或空数组
6. 只返回 JSON，不要其他文字''';

/// 提取字段白名单（锚桌面 `character_fields.py::PARSE_FIELDS` 10 项逐字）。
const List<String> parseFields = <String>[
  'name',
  'description',
  'personality',
  'scenario',
  'first_mes',
  'mes_example',
  'system_prompt',
  'post_history_instructions',
  'tags',
  'creator',
];

/// 文档解析结果值对象：10 个白名单字段 + 成功提取字段清单。
class DocParseResult {
  /// 构造文档解析结果（字段经白名单过滤与类型容错）。
  const DocParseResult({
    required this.name,
    required this.description,
    required this.personality,
    required this.scenario,
    required this.firstMes,
    required this.mesExample,
    required this.systemPrompt,
    required this.postHistoryInstructions,
    required this.tags,
    required this.creator,
    required this.parsedFields,
  });

  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMes;
  final String mesExample;
  final String systemPrompt;
  final String postHistoryInstructions;
  final List<String> tags;
  final String creator;

  /// 成功从 LLM 输出提取（非空默认）的字段名列表。
  final List<String> parsedFields;
}

/// 文档 LLM 解析服务：按默认 Provider/模型把文档文本发往 LLM 提取角色字段。
///
/// 装配（B2）：经 [CredentialsResolver]（AR-3，缺省由 [SettingsRepository]
/// 装配 reader）解析凭据组合序，经 [LLMProviderFactory] 创建 Provider；消息
/// `[system, user]` → `generate(maxTokens: 4096, model)`（**不传
/// temperature**，R8 定案）。错误面（B9）全部折叠为 [DocParseError] 的桌面
/// 一致文案。
class DocumentParseService {
  /// [settings] 提供默认 Provider/模型与凭证解析链；[providerFactory] 装配 LLM；
  /// [credentialsResolver] 解析凭据组合序（AR-3：缺省由 [settings] 装配
  /// reader，测试可注入）。
  DocumentParseService({
    required SettingsRepository settings,
    required LLMProviderFactory providerFactory,
    CredentialsResolver? credentialsResolver,
  })  : _settings = settings,
        _providerFactory = providerFactory {
    _credentialsResolver = credentialsResolver ?? _wireCredentialsResolver();
  }

  final SettingsRepository _settings;
  final LLMProviderFactory _providerFactory;

  /// 凭据解析链（AR-3）：组合序单一归属 [CredentialsResolver]。
  late final CredentialsResolver _credentialsResolver;

  /// 从设置仓储装配缺省解析器 reader——委托仓储的
  /// [SettingsRepository.wireCredentialsResolver]（C2 装配收敛：四 reader 接线
  /// 单一归属仓储，本类仅消费，构造签名零改动）。
  CredentialsResolver _wireCredentialsResolver() =>
      _settings.wireCredentialsResolver();

  /// 解析 [text] 中的角色字段。
  ///
  /// 编排（对齐桌面 `parse_document`）：[CredentialsResolver] 解析凭据组合序
  /// （AR-3；空 key → [ApiKeyMissingError] catch 转换 → DocParseError「未配置
  /// API Key，请先在设置中填写」逐字）→ 工厂装配（未知 provider → DocParseError
  /// 「不支持的 Provider: {provider}」）→ `[system, user]` 消息 →
  /// generate(maxTokens: 4096, model)（失败 → DocParseError
  /// 「LLM 调用失败：{截断200}」）→ 三级 JSON 提取（不可解析 → DocParseError
  /// 「LLM 返回了无法解析的响应，请重试或手动创建」）→ 白名单过滤。
  ///
  /// 抛出：[DocParseError]（唯一错误面）。
  Future<DocParseResult> parse(String text) async {
    // 1. 凭据解析（AR-3：默认 provider/model + apiKey 链 + base_url 归一
    //    组合序单一归属解析器；空 key → ApiKeyMissingError 转 DocParseError）。
    final ResolvedCredentials resolved;
    try {
      resolved = await _credentialsResolver.resolve();
    } on ApiKeyMissingError {
      throw DocParseError('未配置 API Key，请先在设置中填写');
    }
    final provider = resolved.provider;
    final model = resolved.model;

    // 2. 工厂装配（未知 provider → ProviderNotSupportedError 转 DocParseError）。
    final LLMProvider llm;
    try {
      llm = _providerFactory.create(
        provider: provider,
        apiKey: resolved.apiKey,
        baseUrl: resolved.baseUrl,
      );
    } on ProviderNotSupportedError catch (e) {
      throw DocParseError(e.message);
    }

    // 4. 组装 [system, user] 消息并调用 LLM（maxTokens 4096；不传 temperature）。
    final String raw;
    try {
      raw = await llm.generate(
        messages: [
          LlmMessage(role: 'system', content: parseSystemPrompt),
          LlmMessage(role: 'user', content: text),
        ],
        maxTokens: 4096,
        model: model,
      );
    } catch (e) {
      throw DocParseError('LLM 调用失败：${truncateError(e.toString())}');
    }

    // 5. 三级 JSON 提取；不可解析 → 错误。
    final parsed = extractJsonFromLlm(raw);
    if (parsed == null) {
      throw DocParseError('LLM 返回了无法解析的响应，请重试或手动创建');
    }

    // 6. 白名单过滤 + 类型容错。
    return _buildResult(parsed);
  }

  /// 白名单过滤：只取 [parseFields] 内字段；空值/null/空串/空数组 → 默认
  /// （tags 空列表、其余空串）；tags 必须 list 且元素转 str、过滤空；str 字段
  /// strip；非 str 转 str；成功提取字段记入 parsedFields。
  DocParseResult _buildResult(Map<String, dynamic> parsed) {
    final result = <String, dynamic>{};
    final parsedFields = <String>[];

    for (final field in parseFields) {
      final value = parsed[field];
      if (value == null || value == '' || (value is List && value.isEmpty)) {
        result[field] = field == 'tags' ? const <String>[] : '';
        continue;
      }
      if (field == 'tags') {
        if (value is List) {
          result[field] = [
            for (final t in value)
              if (t != null && t.toString().isNotEmpty) t.toString(),
          ];
        } else {
          result[field] = const <String>[];
        }
      } else if (value is String) {
        result[field] = value.trim();
      } else {
        result[field] = value.toString();
      }
      parsedFields.add(field);
    }

    return DocParseResult(
      name: result['name']! as String,
      description: result['description']! as String,
      personality: result['personality']! as String,
      scenario: result['scenario']! as String,
      firstMes: result['first_mes']! as String,
      mesExample: result['mes_example']! as String,
      systemPrompt: result['system_prompt']! as String,
      postHistoryInstructions: result['post_history_instructions']! as String,
      tags: result['tags']! as List<String>,
      creator: result['creator']! as String,
      parsedFields: parsedFields,
    );
  }
}

/// 从 LLM 输出中提取 JSON dict（三级：直接解析 → ```json 代码块 → 首 `{` 到
/// 末 `}` 范围；全部失败 → null）。
///
/// 对齐桌面 `_extract_json`：直接 jsonDecode（须 dict）→ ```json/``` 代码块
/// 提取 → 花括号范围提取。
Map<String, dynamic>? extractJsonFromLlm(String raw) {
  final text = raw.trim();

  // 第一级：直接 JSON 解析（须 dict）。
  try {
    final data = jsonDecode(text);
    if (data is Map<String, dynamic>) {
      return data;
    }
  } on FormatException {
    // 解析失败 → 尝试下一级。
  }

  // 第二级：```json / ``` 代码块提取。
  if (text.contains('```')) {
    for (final marker in const ['```json\n', '```\n', '```']) {
      final start = text.indexOf(marker);
      if (start >= 0) {
        final end = text.indexOf('```', start + marker.length);
        if (end >= 0) {
          final candidate = text.substring(start + marker.length, end).trim();
          try {
            final data = jsonDecode(candidate);
            if (data is Map<String, dynamic>) {
              return data;
            }
          } on FormatException {
            continue;
          }
        }
      }
    }
  }

  // 第三级：花括号范围提取。
  final braceStart = text.indexOf('{');
  if (braceStart >= 0) {
    final braceEnd = text.lastIndexOf('}');
    if (braceEnd > braceStart) {
      final candidate = text.substring(braceStart, braceEnd + 1);
      try {
        final data = jsonDecode(candidate);
        if (data is Map<String, dynamic>) {
          return data;
        }
      } on FormatException {
        // 解析失败 → 返回 null。
      }
    }
  }

  return null;
}

/// 截断错误消息：超长截断到 [maxLength]（缺省 200）并追加 `…`（对齐桌面
/// `_truncate(msg, 200)` 的「截断 + …」语义；恰好 [maxLength] 不截断）。
String truncateError(String message, [int maxLength = 200]) {
  return message.length <= maxLength
      ? message
      : '${message.substring(0, maxLength)}…';
}
