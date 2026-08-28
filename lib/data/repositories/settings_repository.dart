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
import '../../services/secure_store.dart';

/// 设置能力的单一入口（M1-T04）。
///
/// seam 备注：工单 03 定义了消费方接口 `SettingsReader`
/// （lib/data/repositories/settings_reader.dart，三 getter：
/// defaultProvider / defaultModel / userName）。本类的同名成员与其约定一致；
/// `implements SettingsReader` 子句按工单契约由工单 07 装配期补写。
class SettingsRepository {
  /// 创建仓储；[database] 为 drift 数据库，[secretStore] 缺省用系统安全存储
  /// 薄实现（测试注入 InMemorySecretStore）
  SettingsRepository({required AppDatabase database, SecretStore? secretStore})
    : _db = database,
      _secretStore = secretStore ?? FlutterSecretStore();

  final AppDatabase _db;
  final SecretStore _secretStore;

  /// 白名单键集 — 与桌面 `setting.py::ALLOWED_KEYS` **十键逐字相等**。
  ///
  /// 白名单外的写入一律忽略（[setMany]）；白名单内两 api_key 键重定向到
  /// SecretStore 槽位，其余八键落设置表。
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

  // ── 类型化便捷读取（桌面 DB→config 回退链的常量等价复刻）──

  /// 用户昵称；缺省 'User'（镜像桌面 user_name）。
  ///
  /// SettingsReader 约定成员（implements 子句由工单 07 补写）。
  Future<String> get userName async {
    final value = await getValue('user_name');
    return value.isEmpty ? 'User' : value;
  }

  /// 滑动窗口轮数；缺省 30（镜像桌面 sliding_window_rounds）。
  Future<int> get slidingWindowRounds =>
      getInt('sliding_window_rounds', defaultValue: 30);

  /// 默认 provider；缺省 'claude'（镜像桌面 default_provider 的 config 兜底）。
  ///
  /// SettingsReader 约定成员（implements 子句由工单 07 补写）。
  Future<String> get defaultProvider async {
    final value = await getValue('default_provider');
    return value.isEmpty ? 'claude' : value;
  }

  /// 默认模型；缺省 'claude-sonnet-5'（镜像桌面 default_model 的 config 兜底）。
  ///
  /// SettingsReader 约定成员（implements 子句由工单 07 补写）。
  Future<String> get defaultModel async {
    final value = await getValue('default_model');
    return value.isEmpty ? 'claude-sonnet-5' : value;
  }
}
