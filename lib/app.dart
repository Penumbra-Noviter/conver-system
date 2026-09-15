import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'data/database/app_database.dart';
import 'data/database/tables.dart' show ProactivePlanStatus;
import 'data/repositories/character_repository.dart';
import 'data/repositories/companion_repository.dart';
import 'data/repositories/conversation_repository.dart';
import 'data/repositories/memory_repository.dart';
import 'data/repositories/message_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'services/chat_service.dart';
import 'services/character_file_exchange.dart';
import 'services/companion/proactive_message_service.dart';
import 'services/companion/relationship_service.dart';
import 'services/companion/stage_upgrade_broker.dart';
import 'services/companion/thought_service.dart';
import 'services/conversation_export_file_exchange.dart';
import 'services/conversation_export_service.dart';
import 'services/document_parse_service.dart';
import 'services/llm/factory.dart';
import 'services/llm/llm_provider.dart';
import 'services/memory/memory_service.dart';
import 'services/memory/reflection_service.dart';
import 'services/notifications/notification_service.dart';
import 'services/onboarding.dart';
import 'services/secure_store.dart';
import 'services/simulator/game_generator.dart';
import 'services/simulator/seed_service.dart';
import 'services/simulator/simulator_contracts.dart';
import 'services/simulator/simulator_data_dir.dart';
import 'services/simulator/simulator_server.dart';
import 'theme/conver_theme.dart';
import 'view_models/shell_navigation.dart';
import 'view_models/simulators_controller.dart';
import 'view_models/theme_controller.dart';
import 'views/characters/characters_controller.dart';
import 'views/chat/chat_controller.dart';
import 'views/home_shell.dart';
import 'views/onboarding/onboarding_page.dart';

/// 应用根组件（入口层）：provider 装配 + MaterialApp 双主题响应式注入。
///
/// 装配契约（M1-T07）：
/// - **数据层**：[AppDatabase.open] 运行态惰性打开（[database] 参数供测试
///   注入内存执行器，复用 M0 seam）+ 四仓储（character / conversation /
///   message / settings）+ [SecretStore] 经 provider 注入；会话仓储以设置
///   仓储为 [SettingsReader] 实现（settings_repository implements 接线）。
/// - **主题**：`theme` = 浅色、`darkTheme` = 深色（工单 07 A3），`themeMode`
///   经 [ListenableBuilder] 响应式绑定 [ThemeController]——切换即时生效。
///   控制器构造后先 [ThemeController.load] 预热恢复持久化偏好；首启设置表
///   无 theme_mode 行（或恢复失败）→ dark 基线（用户拍板①）。
/// - 导航状态在入口装配，全局可读；M0 五 tab 壳导航结构不变。
/// 深链导航意图 seam（PS2-08，可测注入；生产实现包 ShellNavigation +
/// ChatController，测试注入 fake recorder 断言两动作）。
abstract interface class ProactiveDeepLinkNavigator {
  /// 切换到聊天 tab（对话列表）。
  void selectChatTab();

  /// 打开 [conversationId] 对话并（可选）高亮 [highlightMessageId] 消息。
  Future<void> openConversation(
    int conversationId, {
    int? highlightMessageId,
  });
}

/// 深链导航生产接线占位（PS2-08）：`handleProactiveDeepLink` 顶层函数 +
/// [ProactiveDeepLinkNavigator] seam 已就位；冷启动取参通道
/// （`getNotificationAppLaunchDetails`）尚未在 notification_service 封装
/// （PS2-06 未提供、该文件只读）——生产导航实现与真通道接线 PS2-10 补齐，
/// 当前不实例化（避免未引用死代码）。

/// 处理主动消息通知深链（PS2-08 验收 3 + SR-03 归属校验）。
///
/// payload 解析成功且 messageId 属于 payload.conversationId 的对话（经
/// [messageRepository] 既有查询，不直接写库、不发送）→ select chat +
/// openConversation(conversationId, highlightMessageId: messageId)；
/// payload 非法或归属校验失败 → 回落普通导航（仅 select chat 打开对话列表）。
/// 消费端不读任何 content 参数（SR-03 零内容；payload 仅两 id）。
Future<void> handleProactiveDeepLink({
  required String payload,
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
}) async {
  final parsed = ProactiveDeepLink.tryParse(payload);
  if (parsed == null) {
    navigator.selectChatTab();
    return;
  }
  try {
    final messages = await messageRepository.getMessages(parsed.conversationId);
    final belongs = messages.any((m) => m.id == parsed.messageId);
    if (!belongs) {
      navigator.selectChatTab();
      return;
    }
  } catch (e) {
    debugPrint('主动消息深链归属校验失败，回落对话列表: $e');
    navigator.selectChatTab();
    return;
  }
  navigator.selectChatTab();
  await navigator.openConversation(
    parsed.conversationId,
    highlightMessageId: parsed.messageId,
  );
}

/// 启动排程恢复（SR-08 P0）：只重建「pending 且未过期」的 OS 排程。
///
/// - pending 且 scheduledAt ≤ [now] → 置 expired（不排不发送）；
/// - pending 且未过期 → [scheduler].schedule 重建一次；
/// - sent/expired/dropped 不在 scheduled 列表 → 天然不重排（零触碰）。
/// 单计划排程抛错 → 降级 log 跳过，其余计划继续恢复，不整体上抛。
Future<void> restoreProactiveSchedules({
  required CompanionRepository companion,
  required ProactiveNotificationScheduler scheduler,
  required DateTime now,
}) async {
  final pending = await companion.listPlansByStatus(ProactivePlanStatus.scheduled);
  for (final plan in pending) {
    if (!plan.scheduledAt.isAfter(now)) {
      await companion.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
      continue;
    }
    try {
      await scheduler.schedule(plan);
    } catch (e) {
      debugPrint('启动排程恢复失败（计划 ${plan.id} 保持 scheduled）: $e');
    }
  }
}

/// 启动路径主动通知初始化（PS2-08 验收 4）：scheduler 初始化（幂等）+
/// SR-08 排程恢复；任一失败 debugPrint 降级，不阻断 App 启动。
Future<void> _startProactiveNotifications(
  FlutterLocalNotificationsScheduler scheduler,
  CompanionRepository companion,
) async {
  try {
    await scheduler.initialize();
    await restoreProactiveSchedules(
      companion: companion,
      scheduler: scheduler,
      now: DateTime.now(),
    );
  } catch (e) {
    debugPrint('主动通知启动初始化失败: $e');
  }
}

class ConverApp extends StatelessWidget {
  const ConverApp({super.key, this.database});

  /// 数据库注入点：缺省运行态真实库（惰性打开）；测试注入
  /// `AppDatabase(NativeDatabase.memory())` 以获得确定性行为。
  final AppDatabase? database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDatabase>(create: (_) => database ?? AppDatabase.open()),
        Provider<SecretStore>(create: (_) => FlutterSecretStore()),
        Provider<SettingsRepository>(
          create: (context) => SettingsRepository(
            database: context.read<AppDatabase>(),
            secretStore: context.read<SecretStore>(),
          ),
        ),
        Provider<CharacterRepository>(
          create: (context) => CharacterRepository(context.read<AppDatabase>()),
        ),
        Provider<ConversationRepository>(
          create: (context) => ConversationRepository(
            context.read<AppDatabase>(),
            context.read<SettingsRepository>(),
          ),
        ),
        Provider<MessageRepository>(
          create: (context) => MessageRepository(context.read<AppDatabase>()),
        ),
        // AC-01/AC-03 记忆装配：MemoryRepository（数据层）+ MemoryService
        // （注入组装 / 指令解析落库），供 ChatService 与记忆管理页消费。
        Provider<MemoryRepository>(
          create: (context) => MemoryRepository(context.read<AppDatabase>()),
        ),
        Provider<MemoryService>(
          create: (context) =>
              MemoryService(context.read<MemoryRepository>()),
        ),
        // M2-T04 聊天装配：LLM 工厂 + 回合编排服务 + 聊天控制器。
        // 视图层（ChatView / ChatEntry）只读 ChatController 与仓储抽象，不触碰
        // 数据层 / 平台存储（layer_boundary_test 契约）；装配链单一收编于此。
        Provider<LLMProviderFactory>(
          create: (_) => const LLMFactory(),
        ),
        // 人机恋阶段 1.5 后台反思装配（ADR-0004）：ReflectionService 依赖三
        // 仓储 + LLM 工厂 + 凭据解析链（wireCredentialsResolver 单一落点）；
        // 置于 ChatService 之前（后者经 provider 消费，装配单源）。
        Provider<ReflectionService>(
          create: (context) {
            final settings = context.read<SettingsRepository>();
            final factory = context.read<LLMProviderFactory>();
            return ReflectionService(
              characterRepository: context.read<CharacterRepository>(),
              memoryRepository: context.read<MemoryRepository>(),
              messageRepository: context.read<MessageRepository>(),
              extractor: ({
                required String charName,
                required List<String> dialogueLines,
                required List<String> existingFacts,
              }) async {
                final resolved =
                    await settings.wireCredentialsResolver().resolve();
                final llm = factory.create(
                      provider: resolved.provider,
                      apiKey: resolved.apiKey,
                      baseUrl: resolved.baseUrl,
                    );
                return extractPersonaFactsWithProvider(
                  llm: llm,
                  model: resolved.model,
                  charName: charName,
                  dialogueLines: dialogueLines,
                  existingFacts: existingFacts,
                );
              },
            );
          },
        ),
        // 人机恋阶段 2 装配（PS2-08）：CompanionRepository + 三服务 + 通知
        // scheduler + 升级提议 broker。均在 ChatService 之前声明（后者经
        // provider 消费，装配单源）；启动初始化/排程恢复经哑 Provider 触发
        // （unawaited，失败 debugPrint 不阻断构建）。
        Provider<CompanionRepository>(
          create: (context) =>
              CompanionRepository(context.read<AppDatabase>()),
        ),
        Provider<ThoughtService>(
          create: (context) => ThoughtService(
            companionRepository: context.read<CompanionRepository>(),
            settingsRepository: context.read<SettingsRepository>(),
          ),
        ),
        Provider<RelationshipService>(
          create: (context) => RelationshipService(
            companionRepository: context.read<CompanionRepository>(),
            conversationRepository: context.read<ConversationRepository>(),
            messageRepository: context.read<MessageRepository>(),
          ),
        ),
        Provider<FlutterLocalNotificationsScheduler>(
          create: (_) => FlutterLocalNotificationsScheduler(),
        ),
        Provider<ProactiveMessageService>(
          create: (context) {
            final settings = context.read<SettingsRepository>();
            final factory = context.read<LLMProviderFactory>();
            return ProactiveMessageService(
              companionRepository: context.read<CompanionRepository>(),
              settingsRepository: settings,
              conversationRepository: context.read<ConversationRepository>(),
              messageRepository: context.read<MessageRepository>(),
              planner: ({
                required int characterId,
                required int conversationId,
                required List<String> dialogueLines,
              }) async {
                final resolved =
                    await settings.wireCredentialsResolver().resolve();
                final llm = factory.create(
                      provider: resolved.provider,
                      apiKey: resolved.apiKey,
                      baseUrl: resolved.baseUrl,
                    );
                return planProactiveWithProvider(
                  llm: llm,
                  model: resolved.model,
                  characterId: characterId,
                  conversationId: conversationId,
                  dialogueLines: dialogueLines,
                );
              },
              scheduler: context.read<FlutterLocalNotificationsScheduler>(),
            );
          },
        ),
        ChangeNotifierProvider<StageUpgradeBroker>(
          create: (_) => StageUpgradeBroker(),
        ),
        Provider<Object?>(
          create: (context) {
            // 启动路径：通知初始化（幂等）+ SR-08 排程恢复；失败不阻断。
            unawaited(_startProactiveNotifications(
              context.read<FlutterLocalNotificationsScheduler>(),
              context.read<CompanionRepository>(),
            ));
            return null;
          },
        ),
        Provider<ChatService>(
          create: (context) => ChatService(
            database: context.read<AppDatabase>(),
            conversationRepository: context.read<ConversationRepository>(),
            characterRepository: context.read<CharacterRepository>(),
            messageRepository: context.read<MessageRepository>(),
            settingsRepository: context.read<SettingsRepository>(),
            providerFactory: context.read<LLMProviderFactory>(),
            memoryService: context.read<MemoryService>(),
            reflectionService: context.read<ReflectionService>(),
            thoughtService: context.read<ThoughtService>(),
            relationshipService: context.read<RelationshipService>(),
            proactiveMessageService: context.read<ProactiveMessageService>(),
            companionRepository: context.read<CompanionRepository>(),
            onStageUpgradeProposal: (proposal) =>
                context.read<StageUpgradeBroker>().publish(proposal),
          ),
        ),
        // M4-03 导出装配：纯逻辑服务（复用三仓储 + SettingsRepository as
        // SettingsReader）+ 文件 seam（真实现缺省，平台通道收口）。两者均在
        // ChatController 之前声明（provider 嵌套读外层）。
        Provider<ConversationExportService>(
          create: (context) => ConversationExportService(
            conversationRepository: context.read<ConversationRepository>(),
            characterRepository: context.read<CharacterRepository>(),
            messageRepository: context.read<MessageRepository>(),
            settingsReader: context.read<SettingsRepository>(),
          ),
        ),
        Provider<ConversationExportFileExchange>(
          create: (_) => ConversationExportFileExchange(),
        ),
        ChangeNotifierProvider<ChatController>(
          create: (context) => ChatController(
            chatService: context.read<ChatService>(),
            conversationRepository: context.read<ConversationRepository>(),
            characterRepository: context.read<CharacterRepository>(),
            messageRepository: context.read<MessageRepository>(),
            exportService: context.read<ConversationExportService>(),
            exportFileExchange: context.read<ConversationExportFileExchange>(),
          ),
        ),
        ChangeNotifierProvider<ThemeController>(
          create: (context) {
            final controller = ThemeController(
              settingsRepository: context.read<SettingsRepository>(),
            );
            unawaited(_prewarm(controller));
            return controller;
          },
        ),
        ChangeNotifierProvider(create: (_) => ShellNavigation()),
        // M3-01 角色装配：文件交换 seam + 角色列表控制器。依赖
        // ShellNavigation 与 ChatController，故置于两者之后（嵌套 provider
        // 只能读取更外层已声明项）。M3-03 将 Stub 换为真实现
        // [FilePickerShareFileExchange]（file_picker / share_plus /
        // path_provider 平台通道收口于此；测试注入 fake seam 不触真通道）。
        Provider<CharacterFileExchange>(
          create: (_) => FilePickerShareFileExchange(),
        ),
        // C2 文档解析装配：角色向导的 DocumentParseService 由装配图统一持有
        // （视图层只 context.read 消费，不再现造，layer_boundary_test 契约）。
        // 依赖设置仓储（四 reader 接线经 wireCredentialsResolver 单一落点）
        // 与 LLM 工厂，故置于两者声明之后。
        Provider<DocumentParseService>(
          create: (context) => DocumentParseService(
            settings: context.read<SettingsRepository>(),
            providerFactory: context.read<LLMProviderFactory>(),
          ),
        ),
        ChangeNotifierProvider<CharactersController>(
          create: (context) => CharactersController(
            characterRepository: context.read<CharacterRepository>(),
            fileExchange: context.read<CharacterFileExchange>(),
            navigation: context.read<ShellNavigation>(),
            chatController: context.read<ChatController>(),
          ),
        ),
        // M5-03 模拟器装配：唯一一次模拟器接线（app.dart + home_shell.dart）。
        // 懒启动编排（首进模拟器 tab 触发）——seed（幂等）→ server.start(8642)
        // → 回环 HTTP manifest → ready/empty/error；服务器 App 存续期常驻
        // （实例在应用级 provider，不随 tab 销毁）。后续票（04/06/07/08b）经
        // SimulatorsHooks / SimulatorsView 追加接线，不触碰本文件。
        // C2 生成装配：AI 生成的 GameGenerator 由装配图统一持有（视图只
        // context.read 消费，不再现造）。resolveCredentials 闭包经仓储
        // wireCredentialsResolver 解析 → 映射 GenerationCredentials，不现造
        // CredentialsResolver；providerFactory 复用 LLM 工厂（与聊天/文档解析
        // 同源），resolveSimDir 保持 SimulatorDataDir 解析。
        Provider<GameGenerator>(
          create: (context) {
            final settings = context.read<SettingsRepository>();
            return GameGenerator(
              providerFactory: context.read<LLMProviderFactory>(),
              resolveCredentials: () async {
                final resolved =
                    await settings.wireCredentialsResolver().resolve();
                return GenerationCredentials(
                  provider: resolved.provider,
                  apiKey: resolved.apiKey,
                  model: resolved.model,
                  baseUrl: resolved.baseUrl,
                );
              },
              resolveSimDir: () => SimulatorDataDir().resolve(),
            );
          },
        ),
        ChangeNotifierProvider<SimulatorsController>(
          create: (context) {
            final dataDir = SimulatorDataDir();
            final settings = context.read<SettingsRepository>();
            final secretStore = context.read<SecretStore>();
            return SimulatorsController(
              dataDir: dataDir,
              seed: (simDir) => ensureSeeded(
                simDir: simDir,
                assetRoot: 'assets/${SimulatorContracts.simDir}',
                loadAsset: (path) async {
                  final data = await rootBundle.load(path);
                  return data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  );
                },
              ),
              createServer: (simDir) => SimulatorServer(
                simDir,
                // /proxy 反代凭据 seam（T3）：与注入链同源——openai 协议链
                // base_url + SecretStore openai 槽 key（claude key 恒不进）。
                // 每请求读取（桌面 route handler 语义）：用户改端点/key 后
                // 无需重启 server 即生效。
                proxyConfigReader: () async => ProxyRouteConfig(
                  endpoint: await settings.baseUrl('openai'),
                  apiKey: await secretStore
                      .read(SecretStore.openaiApiKeySlot),
                ),
              ),
              loadManifest: loadManifestViaHttp,
            );
          },
        ),
      ],
      child: Builder(
        builder: (context) {
          final themeController = context.read<ThemeController>();
          return ListenableBuilder(
            listenable: themeController,
            builder: (context, _) => MaterialApp(
              title: '汇流',
              theme: ConverTheme.light(),
              darkTheme: ConverTheme.dark(),
              themeMode: themeController.themeMode,
              // 工单 05：home 由启动门决定——首启（标记缺失）展示指引页，
              // 已完成/读失败直接进主壳。
              home: const _StartupGate(),
            ),
          );
        },
      ),
    );
  }

  /// 预热：恢复持久化 theme_mode（装配顺序敏感性——设置仓储就绪后读取初值）。
  ///
  /// 失败（测试环境平台通道缺失、真机存储异常等）保持 dark 基线；
  /// 不静默吞异常，打日志（项目约定：禁止 except: pass）。
  static Future<void> _prewarm(ThemeController controller) async {
    try {
      await controller.load();
    } catch (error) {
      debugPrint('ThemeController.load 失败，保持深色基线: $error');
    }
  }
}

/// 首启指引装配门（工单 05 / spec §U-4 高不确定点）。
///
/// `MaterialApp.home` 不能 await 异步读标记，故以首帧状态决定：
/// - `null`（读取中）→ 空 `Scaffold`（占位，避免白闪）；
/// - `true`（已完成或读失败）→ [HomeShell]；
/// - `false`（未完成）→ [OnboardingPage]。
///
/// 读失败按「保持不展示指引」（避免首启卡死）处理；完成/跳过走**状态翻转**
/// （`setState` 切 home）而非 `Navigator.pushReplacement`——装配层单源，无导航栈
/// 副作用。落标记经 [OnboardingService]（drift Settings 表单一键）。
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  /// null = 读取中；true = 已完成；false = 展示指引。
  bool? _completed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_completed == null) {
      unawaited(_resolve());
    }
  }

  /// 读 `onboarding_completed` 标记；读失败视为已完成（直接进主界面）。
  Future<void> _resolve() async {
    final service = OnboardingService(
      settings: context.read<SettingsRepository>(),
    );
    var completed = true;
    try {
      completed = await service.isCompleted();
    } catch (error) {
      debugPrint('OnboardingService.isCompleted 失败，直接进入主界面: $error');
    }
    if (mounted) {
      setState(() => _completed = completed);
    }
  }

  /// 「跳过」/「开始使用」落点：落标记后切主界面；落标记失败仍放行进入主界面
  /// （不把用户困在指引页，二次启动会再次展示）。
  Future<void> _finish() async {
    final service = OnboardingService(
      settings: context.read<SettingsRepository>(),
    );
    try {
      await service.markCompleted();
    } catch (error) {
      debugPrint('OnboardingService.markCompleted 失败: $error');
    }
    if (mounted) {
      setState(() => _completed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_completed) {
      null => const Scaffold(),
      true => const HomeShell(),
      false => OnboardingPage(onFinished: _finish),
    };
  }
}
