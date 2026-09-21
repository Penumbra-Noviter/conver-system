/// 「对话」设置子页（工单 03）——全局 temperature / max_tokens 编辑、保存与回显。
///
/// 语义锚点（spec §U-2 / US-2.1 / US-2.4）：
/// - temperature：slider 0–2（对齐 character_wizard temperatureMin/Max），缺省
///   0.7；写入 `temperature` 键（mobile 先行，桌面 ALLOWED_KEYS 无此键）。
/// - max_tokens：数字输入，缺省 2048；合法区间
///   [SettingsRepository.maxTokensMin, SettingsRepository.maxTokensMax]
///   （mobile 先行，无桌面锚点；负数/非数字回退缺省、超上限 clamp）。
///
/// 视图层只做展示编排 + 输入校验，读写经 [SettingsRepository]（数据层），
/// 不触碰平台存储。
///
/// 阶段 2（PS2-09）：「主动消息」与「内心独白」两开关，沿「后台反思」先例
/// 同构——加载回显、即时写入 `proactive_message_enabled` /
/// `inner_thought_enabled` 键、写失败回滚 + SnackBar。
///
/// F-84：开关 true 且落库成功后，请求 Android 13+ 运行时通知权限——优先
/// 走 [ConversationSettingsPage.requestNotificationsPermission] seam，未注入
/// 时经 `FlutterLocalNotificationsScheduler` provider 兜底（对齐 characters_view
/// `_maybeProvider` 先例）；权限被拒/平台异常仅 debugPrint 降级，开关语义与
/// 权限正交（不回滚）。
///
/// 阶段 3（VR-09）：embedding 配置区——开关 `embedding_enabled`（默认关 +
/// SR-19 外发告知副标题）/ base_url / model / key 三输入 + 测试连接。
/// - 开关即时写入 `embedding_enabled`（对齐 `_setReflection`：写失败回滚 +
///   SnackBar）；
/// - 三输入随底部「保存」落库：key 经 `setMany` 白名单重定向 SecretStore
///   槽位（SR-16 不落设置表）；base_url 保存前经 `validateEmbeddingBaseUrl`
///   强制 https（SR-20，http → SnackBar 拒绝并中止整次保存）；model 缺省
///   `text-embedding-3-small`（U1）回显，空输入不落行；
/// - 测试连接：表单现值（key/url/model 三权）组装 [EmbeddingEndpointConfig]
///   经 [ConversationSettingsPage.embeddingClientFactory] 构造 client 后
///   `embed(['ping'])` 直连——成功 SnackBar 含 dims 摘要；失败按
///   [EmbeddingFailure] 分类文案上屏（message 固定摘要，SR-16 不含 key/原文，
///   非 EmbeddingFailure 兜底固定文案）；全程只读验证路径（不写库）。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repository.dart';
import '../../services/embedding/embedding_client.dart';
import '../../services/embedding/embedding_config.dart';
import '../../services/embedding/openai_compatible_client.dart';
import '../../services/notifications/notification_service.dart';
import '../../services/secure_store.dart';
import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 「对话」设置子页。
class ConversationSettingsPage extends StatefulWidget {
  const ConversationSettingsPage({
    super.key,
    required this.settingsRepository,
    this.requestNotificationsPermission,
    this.embeddingClientFactory,
  });

  /// 设置仓储（应用级统一实例，settings_view 注入）。
  final SettingsRepository settingsRepository;

  /// 通知权限请求 seam（F-84）：注入时优先；未注入时经
  /// [FlutterLocalNotificationsScheduler] provider 兜底。返回
  /// true = 已授予；false = 被拒；null = 平台无此能力。结果与开关状态正交。
  final Future<bool?> Function()? requestNotificationsPermission;

  /// Embedding 客户端构造 seam（VR-09）——测试连接用表单三权现值组装
  /// [EmbeddingEndpointConfig] 后经本工厂实例化 [EmbeddingClient] 直连
  /// `embed(['ping'])`。未注入时生产缺省构造
  /// [OpenAICompatibleEmbeddingClient]；测试注入 fake 不触真实网络
  /// （对齐 api_config_section `providerFactory` seam 模式）。
  final EmbeddingClient Function(EmbeddingEndpointConfig)? embeddingClientFactory;

  @override
  State<ConversationSettingsPage> createState() =>
      _ConversationSettingsPageState();
}

class _ConversationSettingsPageState extends State<ConversationSettingsPage> {
  double _temperature = SettingsRepository.defaultTemperature;
  final TextEditingController _maxTokensController = TextEditingController();
  final TextEditingController _memoryPalaceRoundsController =
      TextEditingController();
  bool _reflectionEnabled = false;
  bool _proactiveEnabled = false;
  bool _innerThoughtEnabled = false;
  bool _embeddingEnabled = false;
  bool _memoryPalaceEnabled = false;
  bool _embeddingTesting = false;
  final TextEditingController _embeddingApiKeyController =
      TextEditingController();
  final TextEditingController _embeddingBaseUrlController =
      TextEditingController();
  final TextEditingController _embeddingModelController =
      TextEditingController();
  bool _narrativeEnabled = true;
  final TextEditingController _narrativeRulesController =
      TextEditingController();
  bool _simulatorSummaryRefineEnabled = false;
  bool _loaded = false;

  /// 生产缺省 client 工厂（VR-09）：按装配面快照构造 dio 直连实现。
  static EmbeddingClient _defaultEmbeddingClientFactory(
    EmbeddingEndpointConfig config,
  ) => OpenAICompatibleEmbeddingClient(config: config);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxTokensController.dispose();
    _memoryPalaceRoundsController.dispose();
    _embeddingApiKeyController.dispose();
    _embeddingBaseUrlController.dispose();
    _embeddingModelController.dispose();
    _narrativeRulesController.dispose();
    super.dispose();
  }

  /// 加载已保存值回显；读取失败保持缺省（不阻塞页面渲染）。
  Future<void> _load() async {
    try {
      final temperature = await widget.settingsRepository.getTemperature();
      final maxTokens = await widget.settingsRepository.getMaxTokens();
      final reflectionEnabled =
          await widget.settingsRepository.memoryReflectionEnabled;
      final proactiveEnabled =
          await widget.settingsRepository.proactiveMessageEnabled;
      final innerThoughtEnabled =
          await widget.settingsRepository.innerThoughtEnabled;
      final embeddingEnabled =
          await widget.settingsRepository.embeddingEnabled;
      final memoryPalaceEnabled =
          await widget.settingsRepository.memoryPalaceEnabled;
      final memoryPalaceRounds =
          await widget.settingsRepository.memoryPalaceEveryRounds;
      final narrativeEnabled =
          await widget.settingsRepository.narrativeStyleEnabled;
      // 规则原始值（不经 getter 的默认常量回退——空则回显空 + 默认常量 hint；
      // 沿「直读对应键、避免他键值显示进本槽」先例）。
      final narrativeRules = await widget.settingsRepository.getValue(
        SettingsRepository.narrativeStyleRulesKey,
      );
      // key 直读 embedding 槽位（不做 openai 槽兜底，回显对齐
      // api_config_section「直读对应槽位，避免他槽值显示进本槽」先例）。
      final embeddingApiKey =
          await widget.settingsRepository.getValue(
            SecretStore.embeddingApiKeySlot,
          );
      final embeddingBaseUrl =
          await widget.settingsRepository.getValue(
            SettingsRepository.embeddingBaseUrlKey,
          );
      final embeddingModel = await widget.settingsRepository.embeddingModel;
      final simulatorSummaryRefineEnabled =
          await widget.settingsRepository.simulatorLlmDescriptionEnabled;
      if (!mounted) {
        return;
      }
      setState(() {
        _temperature = temperature;
        _maxTokensController.text = maxTokens.toString();
        _reflectionEnabled = reflectionEnabled;
        _proactiveEnabled = proactiveEnabled;
        _innerThoughtEnabled = innerThoughtEnabled;
        _embeddingEnabled = embeddingEnabled;
        _memoryPalaceEnabled = memoryPalaceEnabled;
        _memoryPalaceRoundsController.text = memoryPalaceRounds.toString();
        _narrativeEnabled = narrativeEnabled;
        _narrativeRulesController.text = narrativeRules;
        _embeddingApiKeyController.text = embeddingApiKey;
        _embeddingBaseUrlController.text = embeddingBaseUrl;
        _embeddingModelController.text = embeddingModel;
        _simulatorSummaryRefineEnabled = simulatorSummaryRefineEnabled;
        _loaded = true;
      });
    } catch (e) {
      debugPrint('对话参数加载失败，保持缺省: $e');
      if (!mounted) {
        return;
      }
      setState(() => _loaded = true);
    }
  }

  /// 保存 temperature / max_tokens + embedding 三输入（base_url / key / model）
  /// 到对应存储面；max_tokens 非数字回退缺省、越界 clamp 到合法区间。
  ///
  /// embedding_base_url 保存前经 [validateEmbeddingBaseUrl] 强制 https
  /// （SR-20）：http 或非法端点 → SnackBar 拒绝并中止整次保存（不落任何键）。
  /// 校验通过后：合法非空 base_url 落归一值；空 base_url / 空 model 不落行
  /// （读回缺省）；`embedding_api_key` 经 setMany 白名单重定向 SecretStore
  /// 槽位（空串 = 清空槽位，SR-16 设置表无明文 Key 行）。
  Future<void> _save() async {
    final parsed = int.tryParse(_maxTokensController.text.trim());
    final maxTokens = parsed == null
        ? SettingsRepository.defaultMaxTokens
        : parsed
              .clamp(
                SettingsRepository.maxTokensMin,
                SettingsRepository.maxTokensMax,
              )
              .toInt();
    String? embeddingBaseUrl;
    try {
      embeddingBaseUrl = validateEmbeddingBaseUrl(
        _embeddingBaseUrlController.text.trim(),
      );
    } on EmbeddingConfigException catch (e) {
      debugPrint('embedding base_url 校验拒绝（SR-20）: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API 地址必须以 https:// 开头')));
      return;
    }
    final embeddingModel = _embeddingModelController.text.trim();
    // 记忆宫殿归纳轮数（WL-05）：非数字回退缺省、越界 clamp 到合法区间
    // （对齐 memory_palace_rounds clamp 语义；[memoryPalaceEveryRoundsMin]/
    // [memoryPalaceEveryRoundsMax] 见仓储常量）。
    final palaceParsed = int.tryParse(
      _memoryPalaceRoundsController.text.trim(),
    );
    final memoryPalaceRounds = palaceParsed == null
        ? SettingsRepository.defaultMemoryPalaceEveryRounds
        : palaceParsed
              .clamp(
                SettingsRepository.memoryPalaceEveryRoundsMin,
                SettingsRepository.memoryPalaceEveryRoundsMax,
              )
              .toInt();
    try {
      await widget.settingsRepository.setMany({
        'temperature': _temperature.toString(),
        'max_tokens': maxTokens.toString(),
        SecretStore.embeddingApiKeySlot: _embeddingApiKeyController.text.trim(),
        SettingsRepository.embeddingBaseUrlKey: ?embeddingBaseUrl,
        if (embeddingModel.isNotEmpty)
          SettingsRepository.embeddingModelKey: embeddingModel,
        SettingsRepository.memoryPalaceEveryRoundsKey:
            memoryPalaceRounds.toString(),
        // NPD-01：保存写两键——开关状态 + 规则文本（空 → 写空串，读回回退
        // 默认常量）。
        SettingsRepository.narrativeStyleEnabledKey:
            _narrativeEnabled.toString(),
        SettingsRepository.narrativeStyleRulesKey:
            _narrativeRulesController.text.trim(),
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      debugPrint('对话参数保存失败: $e');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换后台反思开关（即时写入 `memory_reflection_enabled` 键，ADR-0004）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。
  Future<void> _setReflection(bool value) async {
    setState(() => _reflectionEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.memoryReflectionEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('后台反思开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _reflectionEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换主动消息开关（阶段 2，PS2-09，即时写入
  /// `proactive_message_enabled` 键）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。落库成功后
  /// 沿启用路径请求通知权限（F-84），权限结果不影响开关状态。
  Future<void> _setProactiveMessage(bool value) async {
    setState(() => _proactiveEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.proactiveMessageEnabledKey: value.toString(),
      });
      await _requestNotificationPermissionIfNeeded(value);
    } catch (e) {
      debugPrint('主动消息开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _proactiveEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 启用路径的 Android 13+ 通知权限请求（F-84，仅 `value == true`）。
  ///
  /// seam 注入优先；未注入时经 [FlutterLocalNotificationsScheduler] provider
  /// 兜底（缺位 → null 跳过）。请求被拒 / 返回 null / 抛错均只 debugPrint
  /// 降级——权限与开关语义正交，绝不回滚开关也不冒泡到写仓储的 catch。
  Future<void> _requestNotificationPermissionIfNeeded(bool value) async {
    if (!value || !mounted) {
      return;
    }
    try {
      final request =
          widget.requestNotificationsPermission ??
          _maybeSchedulerPermission(context);
      final granted = (request == null) ? null : await request();
      debugPrint('主动消息通知权限请求结果（F-84）: $granted');
    } catch (e) {
      debugPrint('主动消息通知权限请求降级（开关不受影响）: $e');
    }
  }

  /// 从装配图（app.dart 单一落点）读取
  /// [FlutterLocalNotificationsScheduler.requestNotificationsPermission]；
  /// provider 缺位（既有测试无 stage2 装配）→ null，调用方降级（零回归契约，
  /// 对齐 characters_view `_maybeProvider` 先例）。
  Future<bool?> Function()? _maybeSchedulerPermission(BuildContext context) {
    try {
      return context
          .read<FlutterLocalNotificationsScheduler>()
          .requestNotificationsPermission;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 切换内心独白开关（阶段 2，PS2-09，即时写入
  /// `inner_thought_enabled` 键）。
  ///
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。
  Future<void> _setInnerThought(bool value) async {
    setState(() => _innerThoughtEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.innerThoughtEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('内心独白开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _innerThoughtEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换语义检索开关（阶段 3，VR-09，即时写入 `embedding_enabled` 键）。
  ///
  /// 默认关（SR-19 隐私默认：关闭时对话内容不外发远端 embedding 服务）；
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。开启后方可
  /// 编辑配置输入区并执行测试连接。
  Future<void> _setEmbeddingEnabled(bool value) async {
    setState(() => _embeddingEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.embeddingEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('语义检索开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _embeddingEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换记忆宫殿开关（WL-05，即时写入 `memory_palace_enabled` 键）。
  ///
  /// 默认关（成本敏感 opt-in：开启后对话内容将经归纳 LLM 产出世界书条目）；
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。
  Future<void> _setMemoryPalace(bool value) async {
    setState(() => _memoryPalaceEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.memoryPalaceEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('记忆宫殿开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _memoryPalaceEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换叙述风格开关（NPD-01，即时写入 `narrative_style_enabled` 键）。
  ///
  /// 默认开（opt-out，缺省 true——降 AI 味是跨角色通用诉求）；写失败回滚 UI
  /// 状态并提示；开关即时生效，无需点「保存」。规则文本经底部「保存」落库
  /// （两键一并写入，见 [_save]）。
  Future<void> _setNarrativeStyle(bool value) async {
    setState(() => _narrativeEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.narrativeStyleEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('叙述风格开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _narrativeEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 切换模拟器简介 LLM 精修开关（本批次，即时写入
  /// `simulator_llm_description_enabled` 键）。
  ///
  /// 默认关（成本敏感 opt-in：开启后导入游戏简介将调用已配置 LLM 生成）；
  /// 写失败回滚 UI 状态并提示；开关即时生效，无需点「保存」。规则提取兜底
  /// 简介恒执行，与本开关无关。
  Future<void> _setSimulatorSummaryRefine(bool value) async {
    setState(() => _simulatorSummaryRefineEnabled = value);
    try {
      await widget.settingsRepository.setMany({
        SettingsRepository.simulatorLlmDescriptionEnabledKey: value.toString(),
      });
    } catch (e) {
      debugPrint('模拟器简介精修开关保存失败: $e');
      if (!mounted) {
        return;
      }
      setState(() => _simulatorSummaryRefineEnabled = !value);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('保存失败')));
    }
  }

  /// 测试连接（VR-09）：读表单三权现值（key / base_url / model）组装
  /// [EmbeddingEndpointConfig]，经 [ConversationSettingsPage.embeddingClientFactory]
  /// 构造 client 后 `embed(['ping'])` 直连验证。
  ///
  /// 只读验证路径：整个过程不写 SecretStore / 设置表（验收 7）；三权取自
  /// 输入框现值（对齐 api_config_section「表单现值透传」模式——不硬编码
  /// 模型，测用户实际配置）。
  /// - key 缺失 → 提示先配置且不发请求；
  /// - base_url 经 [validateEmbeddingBaseUrl] 强制 https（SR-20），非法 →
  ///   提示且不发请求；
  /// - 成功 → SnackBar 含 dims 摘要；[EmbeddingFailure] → 展示分类摘要
  ///   message（SR-16 固定文案，不含 key 与原文）；其他意外 → 固定兜底文案
  ///   （不拼接异常内容，防 key/原文外泄）；在途期间禁用按钮防重入。
  Future<void> _testEmbeddingConnection() async {
    if (!_embeddingEnabled) {
      return; // 按钮已禁用，防御性早退。
    }
    final key = _embeddingApiKeyController.text.trim();
    if (key.isEmpty) {
      debugPrint('测试连接跳过(embedding): 未提供 API Key');
      _showSnackBar('未提供 API Key，请在设置中填写后再测试');
      return;
    }
    String? baseUrl;
    try {
      baseUrl = validateEmbeddingBaseUrl(_embeddingBaseUrlController.text.trim());
    } on EmbeddingConfigException catch (e) {
      debugPrint('测试连接跳过(embedding): base_url 非法（SR-20）: $e');
      _showSnackBar('API 地址必须以 https:// 开头');
      return;
    }
    final model = _embeddingModelController.text.trim();
    setState(() => _embeddingTesting = true);
    try {
      final client = (widget.embeddingClientFactory ??
          _defaultEmbeddingClientFactory)(
        EmbeddingEndpointConfig(
          enabled: true,
          apiKey: key,
          baseUrl: baseUrl,
          model: model.isEmpty
              ? SettingsRepository.defaultEmbeddingModel
              : model,
        ),
      );
      final vectors = await client.embed(const <String>['ping']);
      debugPrint('测试连接成功(embedding) dims=${vectors.first.dims}');
      _showSnackBar('连接成功（${vectors.first.dims} 维）');
    } on EmbeddingFailure catch (error) {
      // message 为固定分类摘要（SR-16），可安全上屏与打印。
      debugPrint('测试连接失败(embedding): $error');
      _showSnackBar(error.message);
    } catch (error) {
      // 非 EmbeddingFailure 兜底：不拼接异常内容（防 key/原文入日志/文案）。
      debugPrint('测试连接失败(embedding): ${error.runtimeType}');
      _showSnackBar('连接失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() => _embeddingTesting = false);
      }
    }
  }

  /// 展示 SnackBar（先 hide 当前，避免与前一条排队导致反馈延迟）。
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('对话')),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  ConverSpacing.space4,
                  ConverSpacing.space5,
                  ConverSpacing.space4,
                  ConverSpacing.space6,
                ),
                children: [
                  Text(
                    '温度',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '采样随机性（0–2，默认 0.7）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  Slider(
                    value: _temperature,
                    min: SettingsRepository.temperatureMin,
                    max: SettingsRepository.temperatureMax,
                    divisions: 20,
                    label: _temperature.toStringAsFixed(2),
                    onChanged: (value) => setState(() => _temperature = value),
                  ),
                  Text(
                    _temperature.toStringAsFixed(2),
                    style: textTheme.bodyLarge?.copyWith(color: palette.ink2),
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space4),
                  Text(
                    '最大 token 数',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '单次回复长度上限（1–100000，默认 2048）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  const SizedBox(height: ConverSpacing.space2),
                  TextField(
                    key: const ValueKey('max-tokens'),
                    controller: _maxTokensController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '输入最大 token 数'),
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '后台反思',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '每 6 回合后台提炼人格事实，增强记忆（需额外 LLM 调用）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('后台反思记忆'),
                    value: _reflectionEnabled,
                    onChanged: _setReflection,
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '主动消息',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '角色会在合适时机主动发消息',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('主动消息'),
                    value: _proactiveEnabled,
                    onChanged: _setProactiveMessage,
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '内心独白',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '角色以 <thought> 形式表达内心想法',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('内心独白'),
                    value: _innerThoughtEnabled,
                    onChanged: _setInnerThought,
                  ),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '语义检索',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '对话内容将发送至所选 Embedding 服务',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用语义检索'),
                    value: _embeddingEnabled,
                    onChanged: _setEmbeddingEnabled,
                  ),
                  _embeddingFields(textTheme),
                  const SizedBox(height: ConverSpacing.space4),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '记忆宫殿',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '每 6 回合归纳对话要点为世界书条目',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用记忆宫殿'),
                    value: _memoryPalaceEnabled,
                    onChanged: _setMemoryPalace,
                  ),
                  TextField(
                    key: const ValueKey('memory-palace-rounds'),
                    controller: _memoryPalaceRoundsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: '每 N 回合归纳一次',
                    ),
                  ),
                  const SizedBox(height: ConverSpacing.space5),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '模拟器简介',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '导入游戏自动生成简介（规则提取恒开；精修需调用已配置 LLM）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('简介 LLM 精修'),
                    value: _simulatorSummaryRefineEnabled,
                    onChanged: _setSimulatorSummaryRefine,
                  ),
                  const SizedBox(height: ConverSpacing.space5),
                  Divider(thickness: 1, color: palette.border),
                  const SizedBox(height: ConverSpacing.space2),
                  Text(
                    '叙述风格',
                    style: textTheme.titleMedium?.copyWith(color: palette.ink1),
                  ),
                  const SizedBox(height: ConverSpacing.space1),
                  Text(
                    '降低 AI 生成痕迹（默认开启，可自定义规则）',
                    style: textTheme.bodySmall?.copyWith(color: palette.ink4),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用叙述风格'),
                    value: _narrativeEnabled,
                    onChanged: _setNarrativeStyle,
                  ),
                  TextField(
                    key: const ValueKey('narrative-rules'),
                    controller: _narrativeRulesController,
                    maxLines: 6,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: SettingsRepository.narrativeStyleDefaultRules,
                    ),
                  ),
                  const SizedBox(height: ConverSpacing.space5),
                  FilledButton(onPressed: _save, child: const Text('保存')),
                ],
              ),
      ),
    );
  }

  /// embedding 配置输入区（VR-09）：API Key / Base URL / 模型三输入 +
  /// 测试连接按钮。
  ///
  /// 开关关闭时三输入 [TextField.enabled] = false、测试连接按钮 onPressed
  /// = null（验收 2：关闭时输入区禁用）；开启后可用。key 输入密码态
  /// （obscureText，SR-16 精神）；base_url 提示留空 = 官方默认端点；model
  /// 提示缺省 [SettingsRepository.defaultEmbeddingModel]。
  Widget _embeddingFields(TextTheme textTheme) {
    final palette = ConverPalette.of(context);
    final labelStyle = textTheme.bodySmall?.copyWith(color: palette.ink3);
    final enabled = _embeddingEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('API Key', style: labelStyle),
        TextField(
          key: const ValueKey('embedding-api-key'),
          controller: _embeddingApiKeyController,
          enabled: enabled,
          obscureText: true,
          autofillHints: const <String>[],
          decoration: const InputDecoration(isDense: true, hintText: '未配置'),
        ),
        const SizedBox(height: ConverSpacing.space2),
        Text('Base URL', style: labelStyle),
        TextField(
          key: const ValueKey('embedding-base-url'),
          controller: _embeddingBaseUrlController,
          enabled: enabled,
          decoration: const InputDecoration(
            isDense: true,
            hintText: '官方默认（留空）',
          ),
        ),
        const SizedBox(height: ConverSpacing.space2),
        Text('模型', style: labelStyle),
        TextField(
          key: const ValueKey('embedding-model'),
          controller: _embeddingModelController,
          enabled: enabled,
          decoration: const InputDecoration(
            isDense: true,
            hintText: SettingsRepository.defaultEmbeddingModel,
          ),
        ),
        const SizedBox(height: ConverSpacing.space2),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            key: const ValueKey('test-connection-embedding'),
            onPressed: (!enabled || _embeddingTesting)
                ? null
                : _testEmbeddingConnection,
            icon: _embeddingTesting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 16),
            label: const Text('测试连接'),
          ),
        ),
      ],
    );
  }
}
