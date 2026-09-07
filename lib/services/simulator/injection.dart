/// Key 注入桥 · 纯函数层（F-M5-04）——按钮态解析 / config 三元组完整性 /
/// endpointMode 口径转换 / 凭证组装 / 官方端点检测，全部纯 Dart 可单测。
///
/// 桌面权威源（只读，语义逐字锚点）：
/// - `desktop/frontend/js/key-injector.js`：resolveButtonState（三种态契约）/
///   hasConfigTriplet（F-91 多候选）/ convertEndpoint（SIM-API-1 口径）；
/// - `desktop/backend/app/services/setting.py` `credentials()`：key 只取 openai
///   协议槽位、claude key 恒空串、model 门控（TD-66）。
///
/// 安全契约（ADR 锚定）：`protocol=claude/none` 时 key 恒为空串——claude key
/// **绝不进入游戏**；本模块只转发凭证组装结果，不做任何跨协议兜底。
///
/// 协议表面（深模块，外部只通过这些符号与本模块交互）：
/// `InjectedCredentials` / `ButtonState` / `CredentialSettings` /
/// `assembleCredentials` / `resolveButtonState` / `hasConfigTriplet` /
/// `convertEndpoint` / `endpointSuffix` / `isOfficialEndpoint`。
library;

import '../../models/model_catalog.dart' show ModelCatalog;
import '../secure_store.dart' show SecretStore;

/// OpenAI 兼容协议聊天补全路径后缀（endpointMode 口径转换用；桌面
/// key-injector.js `ENDPOINT_SUFFIX = '/chat/completions'` 逐字）。
const String endpointSuffix = '/chat/completions';

/// 注入凭证组装结果（含协议能力标志）。`protocol=claude/none` 时 [key] 恒空串。
class InjectedCredentials {
  /// 构造凭证三元组 + 协议标志。
  const InjectedCredentials({
    required this.protocol,
    required this.key,
    required this.endpoint,
    required this.model,
  });

  /// 协议标志：`openai`（有 openai 兼容 key）/ `claude`（仅 claude key）/
  /// `none`（皆无）。
  final String protocol;

  /// API Key（只取 openai 协议槽位；claude key 恒为空串——绝不进游戏）。
  final String key;

  /// OpenAI 兼容端点 base URL（openai 协议链解析，跨协议兜底与桌面 base_url
  /// 语义一致；claude/none 态恒空串）。
  final String endpoint;

  /// 默认模型（经 model 门控；门控不通过恒空串——游戏保持默认模型）。
  final String model;
}

/// 按钮可用态解析结果（镜像桌面 resolveButtonState 返回 `{enabled, reason}`）。
class ButtonState {
  /// 构造按钮态；[enabled] 为 true 时 [reason] 恒为 null。
  const ButtonState({required this.enabled, this.reason});

  /// 是否可注入（可点）。
  final bool enabled;

  /// 禁用原因：`claude`（游戏仅支持 OpenAI 兼容 Key）或 `none`（未配置）；
  /// 可注入状态为 null。
  final String? reason;
}

/// 凭证组装输入的设置面（纯数据；由装配方从 [SettingsRepository] 读取构造）。
///
/// 字段语义对齐桌面 `setting.py credentials()`（provider / default_model /
/// base_url 门控依赖）：
/// - [defaultProvider]：设置键 `default_provider`（含缺省兜底）；
/// - [defaultModel]：设置键 `default_model` 的解析值（含缺省兜底，如
///   claude-sonnet-5）；
/// - [configuredModel]：设置键 `default_model` 的**原始显式值**（未配置为空串，
///   供 model 门控「显式配置即放行」判定——不能与解析值混为一谈）；
/// - [baseUrl]：openai 协议链解析的端点 base URL（`base_url(db, 'openai')`
///   语义，跨协议兜底），即注入游戏的 endpoint 值。
class CredentialSettings {
  /// 构造设置面。
  const CredentialSettings({
    required this.defaultProvider,
    required this.defaultModel,
    required this.configuredModel,
    required this.baseUrl,
  });

  /// 默认 provider 键（缺省兜底后的解析值）。
  final String defaultProvider;

  /// 默认模型解析值（含缺省兜底）。
  final String defaultModel;

  /// 默认模型原始显式配置值（未配置 = 空串）。
  final String configuredModel;

  /// openai 协议链解析的端点 base URL。
  final String baseUrl;
}

/// 组装注入凭证（桌面 setting.py `credentials()` 逐字语义）。
///
/// - protocol：[SecretStore] openai 槽位非空 → `openai`；否则 claude 槽位非空
///   → `claude`；皆无 → `none`（与 default_provider 无关，键存在性判定）；
/// - key：**只取 openai 协议槽位**。`protocol=claude/none` → 恒空串——
///   claude key 绝不进入游戏（ADR 安全契约，不做跨协议兜底）；
/// - endpoint：openai 态取 [CredentialSettings.baseUrl]（openai 协议链解析），
///   claude/none 态恒空串；
/// - model：openai 态经 model 门控（TD-66）：默认 provider 解析为 openai 协议且
///   （模型显式配置过 或 解析模型名 ∈ openai 协议模型集）→ 返回，否则空串；
///   claude/none 态恒空串。
Future<InjectedCredentials> assembleCredentials(
  SecretStore secretStore,
  CredentialSettings settings,
) async {
  final openaiKey = await secretStore.read(SecretStore.openaiApiKeySlot);
  final claudeKey = await secretStore.read(SecretStore.claudeApiKeySlot);
  if (openaiKey.isNotEmpty) {
    return InjectedCredentials(
      protocol: 'openai',
      key: openaiKey,
      endpoint: settings.baseUrl,
      model: _modelForOpenaiProtocol(settings),
    );
  }
  if (claudeKey.isNotEmpty) {
    return const InjectedCredentials(
      protocol: 'claude',
      key: '',
      endpoint: '',
      model: '',
    );
  }
  return const InjectedCredentials(
    protocol: 'none',
    key: '',
    endpoint: '',
    model: '',
  );
}

/// model 门控（TD-66 逐字）：默认 provider 解析为 openai 协议 + （模型显式
/// 配置过 或 解析模型名 ∈ openai 协议模型集）→ 返回解析模型；否则空串。
/// 防 .env 默认 claude 模型名混入 openai 三元组（注入后游戏拿 claude 模型名
/// 打 openai 端点必失败）。
String _modelForOpenaiProtocol(CredentialSettings settings) {
  if (ModelCatalog.resolveApiProvider(settings.defaultProvider) != 'openai') {
    return '';
  }
  final resolved = settings.defaultModel;
  return settings.configuredModel.isNotEmpty ||
          ModelCatalog.openaiProtocolModels.contains(resolved)
      ? resolved
      : '';
}

/// 解析凭证的按钮可用态（openai / claude / none 三态纯函数，桌面
/// key-injector.js resolveButtonState 逐字）。
///
/// 契约：`protocol=openai` 且 key 非空 → enabled；`claude` → 禁用
/// （reason='claude'，文案「游戏仅支持 OpenAI 兼容 Key」）；否则（none /
/// openai 但空 key / 未知 protocol / null 输入）→ 禁用 reason='none'（防御：
/// 端点契约被破坏时行为不崩）。
ButtonState resolveButtonState(InjectedCredentials? credentials) {
  final c = credentials;
  if (c == null) {
    return const ButtonState(enabled: false, reason: 'none');
  }
  if (c.protocol == 'openai' && c.key.isNotEmpty) {
    return const ButtonState(enabled: true, reason: null);
  }
  return ButtonState(
    enabled: false,
    reason: c.protocol == 'claude' ? 'claude' : 'none',
  );
}

/// 校验 manifest config 三元组完整性（三个字段均含 ≥1 非空候选 id）。
///
/// 桌面 hasConfigTriplet 逐字（含 F-91 多候选：字段值可为单 id 字符串或 id
/// 数组）。三元组不完整视为无 config（「重新同步」按钮条依渲染条件展示）。
bool hasConfigTriplet(Map<String, dynamic>? config) {
  if (config == null) {
    return false;
  }
  return _configIdCandidates(config['endpoint']).isNotEmpty &&
      _configIdCandidates(config['apikey']).isNotEmpty &&
      _configIdCandidates(config['model']).isNotEmpty;
}

/// 把 config 字段值归一为候选 id 列表（F-91 多候选契约：单 id 字符串或 id
/// 数组；非字符串 / 空串 / 空数组 → 空列表）。注入/就绪轮询按候选逐个尝试，
/// 命中的第一套生效。
List<String> _configIdCandidates(Object? id) {
  if (id is String) return id.isEmpty ? const [] : [id];
  if (id is List) {
    return [
      for (final x in id) if (x is String && x.isNotEmpty) x,
    ];
  }
  return const [];
}

/// 按 manifest endpointMode 把凭证端点 base URL 转换为游戏所需形态
/// （SIM-API-1，桌面 convertEndpoint 逐字）。
///
/// 契约：`full` → 追加 `/chat/completions`（尾斜杠先归一；已含后缀不重复
/// 追加）；`base` → 剥除 `/chat/completions` 后缀（已是 base 形态保持原样）；
/// 其余值（含 null——manifest 未声明）→ 原样返回（兼容旧数据）。空串 /
/// null 端点非字符串处理即原样返回。
String? convertEndpoint(String? endpoint, String? mode) {
  if (endpoint == null || endpoint.isEmpty) {
    return endpoint;
  }
  final trimmed = endpoint.replaceAll(RegExp(r'/+$'), '');
  if (mode == 'full') {
    return trimmed.endsWith(endpointSuffix)
        ? trimmed
        : '$trimmed$endpointSuffix';
  }
  if (mode == 'base') {
    return trimmed.endsWith(endpointSuffix)
        ? trimmed.substring(0, trimmed.length - endpointSuffix.length)
        : trimmed;
  }
  return endpoint;
}

/// 官方端点检测（共识 Q8）：默认 provider=claude 或 base url 命中官方域 →
/// true，运行页顶部提示条；国产兼容 / 自配 → false。
///
/// 域判定边界（锚桌面 `claude.ai` 域族 + 工单边界矩阵）：host 恰为
/// `api.anthropic.com` / `api.openai.com` 或以 `.anthropic.com` / `.openai.com`
/// 结尾（**结尾匹配不误伤** `openai.com.evil.com`）；大小写 / http(s) 协议 /
/// 端口 / 路径 / 子域按 host 提取后归一判定。provider=claude 短路恒 true
/// （claude 协议无国产兼容直连语义）。base url 非 URL / 空串 → false
/// （不误拦）。
bool isOfficialEndpoint(String provider, String baseUrl) {
  if (provider == 'claude') {
    return true;
  }
  final url = baseUrl.trim().toLowerCase();
  if (url.isEmpty) {
    return false;
  }
  final uri = Uri.tryParse(url);
  final host = (uri != null && uri.host.isNotEmpty) ? uri.host : null;
  if (host == null) {
    return false;
  }
  return host == 'api.anthropic.com' ||
      host == 'api.openai.com' ||
      host.endsWith('.anthropic.com') ||
      host.endsWith('.openai.com');
}