/// 设置仓储 — 白名单键值 CRUD + 类型化便捷读取 + 凭证解析链。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/setting.py`（ALLOWED_KEYS / get_value /
/// get_int / get_all / set_many / _slot_value / api_key / base_url / user_name /
/// sliding_window_rounds / default_provider / default_model）
///
/// 与桌面的协议面差异（M1-T04 拍板，见工单「高不确定实现点」与 spec §SecureStorage）：
/// - **砍 .env 腿**：api_key 解析链止于两个 SecretStore 槽位，无配置文件兜底
/// - **砍 credentials 三元组**：游戏模拟器专用（桌面 credentials()），M1 不迁移
/// - **api_key 两键读写重定向**：白名单成员资格保留（校验语义与桌面一致），
///   但实际存取走 [SecretStore] 槽位（键名逐字相同），设置表不落明文 Key；
///   [getAll] 为桌面 get_all 的严格镜像（设置表查询），因此天然不含 Key 行
/// - **白名单外 per-provider 动态键**（如 deepseek_api_key）：桌面读侧死路径，
///   不采纳（移动端写入被白名单过滤，行不可能存在）
///
/// 类型化读取的缺省常量即桌面 DB→config 回退链的常量等价复刻
/// （desktop/backend/app/config.py：DEFAULT_PROVIDER='claude'、
/// DEFAULT_MODEL='claude-sonnet-5'；user_name 默认 'User'、
/// sliding_window_rounds 默认 30）。
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../models/model_catalog.dart';
import '../../services/llm/credentials_resolver.dart';
import '../../services/secure_store.dart';
import 'settings_reader.dart';

/// 设置能力的单一入口（M1-T04），并作为会话仓储的 [SettingsReader] 实现
/// （M1-T07 装配接线）。
///
/// seam 备注：工单 03 定义了消费方接口 `SettingsReader`
/// （lib/data/repositories/settings_reader.dart，三 getter：
/// defaultProvider / defaultModel / userName）。本类同名成员即其实现。
///
/// 语义收敛注记（M1-T07 → F-24 收敛）：[SettingsReader] 契约原声明「原始值，
/// 兜底由消费方回退」，而本类类型化便捷读取按 spec §设置仓储做缺省填充
/// （'User' / 'claude' / 'claude-sonnet-5'）——两语义此前「经唯一消费方会话
/// 仓储可观察行为逐位一致」靠常量碰巧相等收敛，任一侧改动即静默破约。
/// **2026-09-07 F-24 收敛**：兜底常量单一归属 [SettingsDefaults]
/// （`settings_reader.dart`），本类填充与消费方兜底引用同一常量；契约文档
/// 已对齐「实现方填充」的现状。原始读取仍可经 [getValue] 获得。
class SettingsRepository implements SettingsReader {
  /// 创建仓储；[database] 为 drift 数据库，[secretStore] 缺省用系统安全存储
  /// 薄实现（测试注入 InMemorySecretStore）
  SettingsRepository({required AppDatabase database, SecretStore? secretStore})
    : _db = database,
      _secretStore = secretStore ?? FlutterSecretStore();

  final AppDatabase _db;
  final SecretStore _secretStore;

  /// 白名单键集 — 与桌面 `setting.py::ALLOWED_KEYS` **十键逐字相等**，外加两
  /// mobile 先行键 `temperature` / `max_tokens`（工单 03，桌面无此二键——
  /// 契约漂移显式标注，spec §U-2「mobile 先行差异」）。
  ///
  /// 白名单外的写入一律忽略（[setMany]）；白名单内两 api_key 键重定向到
  /// SecretStore 槽位，其余键落设置表。
  static const Set<String> allowedKeys = <String>{
    'claude_api_key',
    'claude_base_url',
    'openai_api_key',
    'openai_base_url',
    'default_provider',
    'default_provider_name',
    'default_model',
    'sliding_window_rounds',
    'theme_mode',
    'user_name',
    'temperature',
    'max_tokens',
  };

  /// theme_mode 落库键（ThemeController 跨文件契约键名）。
  static const String themeModeKey = 'theme_mode';

  /// 凭证槽位（provider 名）— 与桌面 `_CRED_SLOTS` 同序：claude、openai。
  static const List<String> _credSlots = <String>['claude', 'openai'];

  /// api_key 两键（SecretStore 槽位键）— 白名单内重定向成员。
  static const Set<String> _apiKeyKeys = <String>{
    SecretStore.claudeApiKeySlot,
    SecretStore.openaiApiKeySlot,
  };

  /// 全局采样温度缺省（0.7）——对齐桌面角色字段 DB 默认（tables.dart
  /// `withDefault(Constant(0.7))`）与 character_wizard 的 `temperatureDefault`。
  ///
  /// 工单 03 判定契约（spec §U-2 高不确定点）：角色 `temperature ==
  /// defaultTemperature` 判定为「未显式覆盖」→ 回退全局温度；接受「显式设 0.7
  /// 会被全局覆盖」的边界。
  static const double defaultTemperature = 0.7;

  /// 全局采样温度合法区间 [0, 2]（对齐 character_wizard temperatureMin/Max）。
  static const double temperatureMin = 0;
  static const double temperatureMax = 2;

  /// 全局 max_tokens 缺省（2048）——对齐当前调用级硬编码（`LLMProvider` 缺省）。
  static const int defaultMaxTokens = 2048;

  /// max_tokens 输入合法区间 [1, maxTokensMax]（mobile 先行，无桌面锚点；
  /// 见工单 03 高不确定点：负数/非数字回退 [defaultMaxTokens]、超上限 clamp）。
  /// clamp 落 UI 输入层（conversation_settings_page），仓储读取保持 getInt 语义。
  static const int maxTokensMin = 1;
  static const int maxTokensMax = 100000;

  // ── 键值 CRUD ──

  /// 读取单个设置值；不存在或值为空返回 [defaultValue]。
  ///
  /// 空串语义（镜像桌面 get_value：`row.value if row and row.value else default`）。
  /// api_key 两键的读取重定向到 SecretStore 槽位（与写入重定向对称，
  /// 使 `getValue('claude_api_key')` 的可观察结果与桌面读 DB 行一致）。
  Future<String> getValue(String key, {String defaultValue = ''}) async {
    if (_apiKeyKeys.contains(key)) {
      return _secretStore.read(key);
    }
    final row =
        await (_db.select(_db.settings)..where((t) => t.key.equals(key)))
            .getSingleOrNull();
    return (row == null || row.value.isEmpty) ? defaultValue : row.value;
  }

  /// 读取整型设置；缺失或非数字回退 [defaultValue]（镜像桌面 get_int，防崩溃）。
  Future<int> getInt(String key, {required int defaultValue}) async {
    final value = await getValue(key);
    return int.tryParse(value) ?? defaultValue;
  }

  /// 读取白名单内所有设置行（key → value，含空串值行）。
  ///
  /// 严格镜像桌面 get_all 的设置表查询；api_key 两键因写入重定向而不落表，
  /// 结果天然只含八非敏感键的已有行（设置表无明文 Key）。
  Future<Map<String, String>> getAll() async {
    final rows =
        await (_db.select(_db.settings)
              ..where((t) => t.key.isIn(allowedKeys)))
            .get();
    return {for (final row in rows) row.key: row.value};
  }

  /// 批量写入设置：白名单外键忽略；存在则更新、不存在则创建。
  ///
  /// api_key 两键重定向到 SecretStore 槽位（设置表无明文 Key 行）；
  /// 写空串 = 清空槽位（读回空串，视同未配置，与 SecretStore 契约一致）。
  Future<void> setMany(Map<String, String> data) async {
    for (final entry in data.entries) {
      if (!allowedKeys.contains(entry.key)) {
        continue;
      }
      if (_apiKeyKeys.contains(entry.key)) {
        await _secretStore.write(key: entry.key, value: entry.value);
        continue;
      }
      // upsert：settings 主键即 key，冲突时整行更新（桌面 set_many 的
      // 存在更新/不存在创建等价实现）。
      await _db
          .into(_db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: entry.key,
              value: Value(entry.value),
            ),
          );
    }
  }

  // ── 凭证解析链（镜像桌面 _slot_value，砍 .env 腿）──

  /// 通用槽位解析：provider 特定槽 → 同协议槽 → 跨协议兜底 → 空串。
  ///
  /// 镜像桌面 `_slot_value` 的候选序 `（proto,）+ 其余槽位`：首环 provider
  /// 特定键在移动端两槽位模型下与同协议槽位重合（claude/openai 自身即槽位键；
  /// per-provider 动态键为读侧死路径不采纳），故折叠为同一次读取。
  /// [read] 注入值读取通道：api_key 走 SecretStore，base_url 走设置表。
  Future<String> _slotValue(
    String suffix,
    String provider,
    Future<String> Function(String key) read,
  ) async {
    final proto = ModelCatalog.resolveApiProvider(provider);
    final candidates = <String>[
      proto,
      ..._credSlots.where((slot) => slot != proto),
    ];
    for (final slot in candidates) {
      final value = await read('${slot}_$suffix');
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  /// 读取指定 provider 的 API Key；未配置返回空串。
  ///
  /// 解析链（任一槽位有值即可用；空串视同未配置）：
  /// 1. provider 特定槽位（claude / openai 自身即槽位键）
  /// 2. 同协议槽位（如 deepseek → openai 槽，经 [ModelCatalog.resolveApiProvider]）
  /// 3. 跨协议兜底（另一槽位）
  /// 桌面第 4 腿 .env 兜底不迁移（移动端无服务端配置文件）。
  Future<String> apiKey(String provider) =>
      _slotValue('api_key', provider, _secretStore.read);

  /// 读取指定 provider 的 base_url；未配置返回空串。
  ///
  /// 与 [apiKey] 同形链，但读设置表（非敏感，不进安全存储）。
  Future<String> baseUrl(String provider) =>
      _slotValue('base_url', provider, (key) => getValue(key));

  /// 装配本仓储四 reader 的 [CredentialsResolver]（C2 装配收敛单一落点）。
  ///
  /// 四 reader 即本类 `defaultProvider / defaultModel / apiKey / baseUrl` 的
  /// tear-off——聊天、文档解析、模拟器生成三消费点经本方法委托接线，不再各自
  /// 复制构造；等价性测试保障与手工 tear-off 装配可观察行为逐位一致。
  /// [CredentialsResolver] 为纯 Dart 零 I/O（仅依赖 errors.dart），仓储（数据
  /// 层）引用无环路。
  CredentialsResolver wireCredentialsResolver() => CredentialsResolver(
        defaultProvider: () => defaultProvider,
        defaultModel: () => defaultModel,
        apiKey: apiKey,
        baseUrl: baseUrl,
      );

  // ── 类型化便捷读取（桌面 DB→config 回退链的常量等价复刻）──

  /// 用户昵称；缺省 [SettingsDefaults.userName]（镜像桌面 user_name）。
  ///
  /// @override [SettingsReader.userName]（语义收敛注记见类注释）。
  @override
  Future<String> get userName async {
    final value = await getValue('user_name');
    return value.isEmpty ? SettingsDefaults.userName : value;
  }

  /// 滑动窗口轮数；缺省 30（镜像桌面 sliding_window_rounds）。
  Future<int> get slidingWindowRounds =>
      getInt('sliding_window_rounds', defaultValue: 30);

  /// 全局采样温度；缺省 [defaultTemperature]，clamp 到
  /// [temperatureMin, temperatureMax]。
  ///
  /// 读取 `temperature` 键（mobile 先行键，桌面 ALLOWED_KEYS 无此键）；非数字/
  /// 缺失 → 缺省；越界 → clamp。
  Future<double> getTemperature() async {
    final parsed = double.tryParse(await getValue('temperature'));
    if (parsed == null) {
      return defaultTemperature;
    }
    return parsed.clamp(temperatureMin, temperatureMax).toDouble();
  }

  /// 全局 max_tokens；缺省 [defaultMaxTokens]。
  ///
  /// 读取 `max_tokens` 键（mobile 先行键，桌面无此键）；非数字/缺失回退缺省
  /// （镜像 [getInt] 语义）。合法区间 clamp 由 UI 输入层保证（见
  /// [maxTokensMin] / [maxTokensMax]）。
  Future<int> getMaxTokens() => getInt('max_tokens', defaultValue: defaultMaxTokens);

  /// 默认 provider；缺省 [SettingsDefaults.provider]（镜像桌面
  /// default_provider 的 config 兜底）。
  ///
  /// @override [SettingsReader.defaultProvider]（语义收敛注记见类注释）。
  @override
  Future<String> get defaultProvider async {
    final value = await getValue('default_provider');
    return value.isEmpty ? SettingsDefaults.provider : value;
  }

  /// 默认模型；缺省 [SettingsDefaults.model]（镜像桌面 default_model 的
  /// config 兜底）。
  ///
  /// @override [SettingsReader.defaultModel]（语义收敛注记见类注释）。
  @override
  Future<String> get defaultModel async {
    final value = await getValue('default_model');
    return value.isEmpty ? SettingsDefaults.model : value;
  }
}
