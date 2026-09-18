import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        DidReceiveNotificationResponseCallback,
        FlutterLocalNotificationsPlugin;
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
import 'services/embedding/embedding_config.dart';
import 'services/embedding/embedding_service.dart';
import 'services/embedding/openai_compatible_client.dart';
import 'services/llm/factory.dart';
import 'services/llm/llm_provider.dart';
import 'services/memory/memory_service.dart';
import 'services/memory/persona_evolution_service.dart';
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
  Future<void> openConversation(int conversationId, {int? highlightMessageId});
}

/// 深链导航生产实现（PS2-10）：包 [ShellNavigation] + [ChatController]——
/// select chat = 切聊天 tab；openConversation = 打开会话（可高亮消息）。
class AppDeepLinkNavigator implements ProactiveDeepLinkNavigator {
  /// [navigation] tab 状态；[chatController] 会话打开/高亮入口。
  AppDeepLinkNavigator({
    required this.navigation,
    required this.chatController,
  });

  final ShellNavigation navigation;
  final ChatController chatController;

  @override
  void selectChatTab() => navigation.select(ShellTab.chat);

  @override
  Future<void> openConversation(int conversationId, {int? highlightMessageId}) {
    return chatController.openConversation(
      conversationId,
      highlightMessageId: highlightMessageId,
    );
  }
}

/// 冷启动通知 payload 读取薄封装（PS2-10 验收 8）：notification_service 标
/// 只读（PS2-06 未提供取参通道），真通道在此封装——flutter_local_notifications
/// 插件单例调 [FlutterLocalNotificationsPlugin.getNotificationAppLaunchDetails]，
/// 取 `notificationResponse.payload`（SR-03 零 content：payload 仅两 id）。
///
/// 插件缺位（测试环境 MissingPluginException）/ 平台异常 → null 静默返回
/// （验收 8：取参失败静默跳过，不阻塞 App 启动）。
Future<String?> readProactiveLaunchPayload({
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  try {
    final details = await (plugin ?? FlutterLocalNotificationsPlugin())
        .getNotificationAppLaunchDetails();
    return details?.notificationResponse?.payload;
  } catch (e) {
    debugPrint('读取冷启动通知 payload 失败: $e');
    return null;
  }
}

/// 冷启动深链消费（PS2-10 装配层接线）：取参 → 无 payload / 取参失败静默
/// 跳过（验收 8）→ 否则交 [handleProactiveDeepLink]（归属校验 + 导航）。
Future<void> consumeProactiveLaunchDeepLink({
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
  Future<String?> Function()? readPayload,
}) async {
  final String? payload;
  try {
    payload = await (readPayload ?? readProactiveLaunchPayload)();
  } catch (e) {
    debugPrint('读取冷启动通知 payload 失败: $e');
    return;
  }
  if (payload == null || payload.isEmpty) {
    return;
  }
  await handleProactiveDeepLink(
    payload: payload,
    navigator: navigator,
    messageRepository: messageRepository,
    proactiveMessageService: proactiveMessageService,
    relationshipService: relationshipService,
  );
}

/// 全局 ScaffoldMessenger key（F-84 SnackBar 通道）：装配层单点绑定
/// `MaterialApp.scaffoldMessengerKey`——provider create 的 context 位于
/// MaterialApp 之上拿不到 ScaffoldMessenger，故用顶层 key 桥接。
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 通知排程失败站内提示（F-84 P3 站内兜底 + SR-12 摘要）：经
/// [rootScaffoldMessengerKey] 展示固定文案「通知排程失败」，不携带计划内容
/// 原文。messenger 未挂载（装配未完成/测试环境）→ debugPrint 降级不抛。
void showScheduleFailedNotice() {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) {
    debugPrint('proactive schedule failed notice skipped: messenger not ready');
    return;
  }
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('通知排程失败')));
}

/// 热态通知点按深链消费（F-84 桥接，PS2-10 装配层接线）：与
/// [consumeProactiveLaunchDeepLink] 同构，payload 来源为
/// `NotificationResponse.payload`（同步取值，非 Future 读取）。
///
/// payload null/空 → 静默（零导航）；非空 → [handleProactiveDeepLink]（归属
/// 校验 → markDelivered → recordProactiveMessageOpened +5 → 导航高亮，异常
/// 降级内建）。热态（App 存活）与冷启动（getNotificationAppLaunchDetails）
/// 互斥，共享同一消费函数与装配组件（导航/仓储/两服务）。
Future<void> consumeProactiveNotificationResponse({
  required String? payload,
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
}) async {
  if (payload == null || payload.isEmpty) {
    return;
  }
  await handleProactiveDeepLink(
    payload: payload,
    navigator: navigator,
    messageRepository: messageRepository,
    proactiveMessageService: proactiveMessageService,
    relationshipService: relationshipService,
  );
}

/// 处理主动消息通知深链（PS2-08 验收 3 + SR-03 归属校验）。
///
/// payload 解析成功且 messageId 属于 payload.conversationId 的对话（经
/// [messageRepository] 既有查询，不直接写库、不发送）→ select chat +
/// openConversation(conversationId, highlightMessageId: messageId)；
/// payload 非法或归属校验失败 → 回落普通导航（仅 select chat 打开对话列表）。
/// 消费端不读任何 content 参数（SR-03 零内容；payload 仅两 id）。
///
/// W5 F2（P3）：openConversation 纳入异常保护——导航抛错 debugPrint 降级，
/// 不崩溃、不回退（tab 已切到聊天列表，用户可自行选择会话）。
Future<void> handleProactiveDeepLink({
  required String payload,
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
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
    // C1 送达收口（SR-07）：归属校验通过 = 通知已被用户点按触达 → 置 sent +
    // sentAt（节流计数/冷却口径生产可达），并记录「点开主动消息 +5」
    // （P4 启发式，PS2-03 recordProactiveMessageOpened 消费）。失败仅
    // debugPrint 不阻断导航；缺省 null（测试形态）跳过。
    if (proactiveMessageService != null) {
      try {
        final delivered = await proactiveMessageService
            .markDeliveredByMessageId(parsed.messageId);
        if (delivered != null && relationshipService != null) {
          await relationshipService.recordProactiveMessageOpened(
            delivered.characterId,
          );
        }
      } catch (e) {
        debugPrint('主动消息送达收口失败（不阻断导航）: $e');
      }
    }
  } catch (e) {
    debugPrint('主动消息深链归属校验失败，回落对话列表: $e');
    navigator.selectChatTab();
    return;
  }
  navigator.selectChatTab();
  try {
    await navigator.openConversation(
      parsed.conversationId,
      highlightMessageId: parsed.messageId,
    );
  } catch (e) {
    debugPrint('主动消息深链打开会话失败（已切聊天 tab）: $e');
  }
}

/// 启动排程恢复（SR-08 P0）：只重建「pending 且未过期」的 OS 排程。
///
/// - pending 且 scheduledAt ≤ [now] → 置 expired（不排不发送）；
/// - pending 且未过期 → [scheduler].schedule 重建一次；
/// - sent/expired/dropped 不在 scheduled 列表 → 天然不重排（零触碰）。
/// 单计划排程抛错或置 expired 抛错 → 降级 log 跳过，其余计划继续恢复，
/// 不整体上抛（SR-08：抛错计划保持原状态 scheduled，不重排不置位）。
Future<void> restoreProactiveSchedules({
  required CompanionRepository companion,
  required ProactiveNotificationScheduler scheduler,
  required DateTime now,
}) async {
  final pending = await companion.listPlansByStatus(
    ProactivePlanStatus.scheduled,
  );
  for (final plan in pending) {
    if (!plan.scheduledAt.isAfter(now)) {
      try {
        await companion.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
      } catch (e) {
        debugPrint('启动排程恢复置 expired 失败（计划 ${plan.id} 保持 scheduled）: $e');
      }
      continue;
    }
    try {
      await scheduler.schedule(plan);
    } catch (e) {
      debugPrint('启动排程恢复失败（计划 ${plan.id} 保持 scheduled）: $e');
    }
  }
}

/// 启动路径主动通知初始化（PS2-08 验收 4 + F-84 热态接线 + F-92 告警接线）：
/// scheduler 初始化（幂等；首次调用即透传热态回调，晚到装配经重挂生效）
/// + SR-08 排程恢复；任一失败 debugPrint 降级，不阻断 App 启动。恢复路径
/// 不接失败回调（SR-08 保持静默）。
///
/// F-92：热态回调丢失告警 seam 在此接线消费——不可补救路径（重挂失败）经
/// [FlutterLocalNotificationsScheduler.initialize] 的 onHotCallbackLost
/// 上达装配方并 debugPrint 记录（不得静默）；reason 为失败摘要，不含
/// payload 内容（SR-12）。
Future<void> _startProactiveNotifications(
  FlutterLocalNotificationsScheduler scheduler,
  CompanionRepository companion, {
  DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
}) async {
  try {
    await scheduler.initialize(
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onHotCallbackLost: (reason) => debugPrint('主动通知热态回调丢失（不可补救）: $reason'),
    );
    await restoreProactiveSchedules(
      companion: companion,
      scheduler: scheduler,
      now: DateTime.now(),
    );
  } catch (e) {
    debugPrint('主动通知启动初始化失败: $e');
  }
}

/// 装配层 LLM 凭据解析 + 工厂创建单一落点（F-120）。
///
/// ReflectionService / PersonaEvolutionService 两处 reflector 装配闭包中
/// 的「wireCredentialsResolver().resolve() → factory.create()」同构段收敛
/// 于此：第三处反射器装配出现时直接复用，不再复制样板；凭据解析链
/// （wireCredentialsResolver）单一落点约束保持不扩散。
Future<({LLMProvider llm, String model})> _resolveLlm(
  BuildContext context,
) async {
  final settings = context.read<SettingsRepository>();
  final factory = context.read<LLMProviderFactory>();
  final resolved = await settings.wireCredentialsResolver().resolve();
  return (
    llm: factory.create(
      provider: resolved.provider,
      apiKey: resolved.apiKey,
      baseUrl: resolved.baseUrl,
    ),
    model: resolved.model,
  );
}

class ConverApp extends StatelessWidget {
  const ConverApp({super.key, this.database, this.scheduler});

  /// 数据库注入点：缺省运行态真实库（惰性打开）；测试注入
  /// `AppDatabase(NativeDatabase.memory())` 以获得确定性行为。
  final AppDatabase? database;

  /// 通知排程器注入点（F-84 装配接线测试 seam）：缺省生产实现（包真插件
  /// 单例）；测试注入 fake channel 的 scheduler 断言热态回调注册。
  final FlutterLocalNotificationsScheduler? scheduler;

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
        // MemoryService 声明于 EmbeddingService 之后（VR-07 起依赖后者，
        // provider 嵌套序即依赖序）。
        Provider<MemoryRepository>(
          create: (context) => MemoryRepository(context.read<AppDatabase>()),
        ),
        // VR-06 阶段 3 装配腿（P1 端点/凭据独立腿，不并入 CredentialsResolver）：
        // EmbeddingService 依赖 SettingsRepository + MemoryRepository + 可替换
        // client 工厂。配置组装（VR-01 getter + validateEmbeddingBaseUrl）在
        // resolveConfig 闭包内、client 构造（VR-02）在 clientFactory 闭包内，
        // 两者均延迟到服务操作时执行（同步 create 闭包零 I/O——SecretStore
        // 读取只发生在 embedding 已启用后的实际操作路径，默认关（SR-19）下
        // 装配与启动均不触达 SecretStore，测试环境无 MissingPluginException）。
        // lazy:false（W6-F1/persona 教训）：装配腿启动即构造，装配断裂在
        // 启动期暴露而非等消费；无网络/存储副作用。VR-07 起 MemoryService
        // 依赖本 provider（混合检索 seam），声明次序已在下方对齐。
        Provider<EmbeddingService>(
          lazy: false, // W6-F1：装配腿启动副作用必须立即执行（persona 教训）
          create: (context) {
            final settings = context.read<SettingsRepository>();
            return EmbeddingService(
              memoryRepository: context.read<MemoryRepository>(),
              resolveConfig: () async {
                final enabled = await settings.embeddingEnabled;
                if (!enabled) {
                  // SR-19 默认关：禁用态零 SecretStore 触碰。
                  return EmbeddingEndpointConfig(
                    enabled: false,
                    apiKey: '',
                    baseUrl: null,
                    model: SettingsRepository.defaultEmbeddingModel,
                  );
                }
                return EmbeddingEndpointConfig(
                  enabled: true,
                  apiKey: await settings.embeddingApiKey,
                  baseUrl: validateEmbeddingBaseUrl(
                    await settings.embeddingBaseUrl,
                  ),
                  model: await settings.embeddingModel,
                );
              },
              clientFactory: (config) =>
                  OpenAICompatibleEmbeddingClient(config: config),
            );
          },
        ),
        Provider<MemoryService>(
          create: (context) => MemoryService(
            context.read<MemoryRepository>(),
            // VR-07 串行申报：混合检索 seam（关键词零命中 → 语义兜底入队）。
            embeddingService: context.read<EmbeddingService>(),
          ),
        ),
        // M2-T04 聊天装配：LLM 工厂 + 回合编排服务 + 聊天控制器。
        // 视图层（ChatView / ChatEntry）只读 ChatController 与仓储抽象，不触碰
        // 数据层 / 平台存储（layer_boundary_test 契约）；装配链单一收编于此。
        Provider<LLMProviderFactory>(create: (_) => const LLMFactory()),
        // 人机恋阶段 1.5 后台反思装配（ADR-0004）：ReflectionService 依赖三
        // 仓储 + LLM 工厂 + 凭据解析链（wireCredentialsResolver 单一落点）；
        // 置于 ChatService 之前（后者经 provider 消费，装配单源）。
        Provider<ReflectionService>(
          create: (context) {
            return ReflectionService(
              characterRepository: context.read<CharacterRepository>(),
              memoryRepository: context.read<MemoryRepository>(),
              messageRepository: context.read<MessageRepository>(),
              extractor:
                  ({
                    required String charName,
                    required List<String> dialogueLines,
                    required List<String> existingFacts,
                  }) async {
                    final llm = await _resolveLlm(context);
                    return extractPersonaFactsWithProvider(
                      llm: llm.llm,
                      model: llm.model,
                      charName: charName,
                      dialogueLines: dialogueLines,
                      existingFacts: existingFacts,
                    );
                  },
            );
          },
        ),
        // 人机恋阶段 3 装配（F-109）：PersonaEvolutionService 依赖两仓储 +
        // LLM 工厂 + 凭据解析链（wireCredentialsResolver 单一落点）；reflector
        // = buildClusteredReflector（VR-08 聚类注入）经 inner 走
        // reflectPersonaWithProvider，与 ReflectionService 先例同构；默认
        // lazy——服务构造零 I/O 零启动副作用，不满足 W6-F1 哑 Provider 条件。
        Provider<PersonaEvolutionService>(
          create: (context) {
            return PersonaEvolutionService(
              characterRepository: context.read<CharacterRepository>(),
              memoryRepository: context.read<MemoryRepository>(),
              reflector: buildClusteredReflector(
                embeddingService: context.read<EmbeddingService>(),
                inner:
                    ({
                      required String currentPersonality,
                      required String charName,
                      required List<String> personaFacts,
                      List<String> similarClusters = const [],
                    }) async {
                      final llm = await _resolveLlm(context);
                      return reflectPersonaWithProvider(
                        llm: llm.llm,
                        model: llm.model,
                        currentPersonality: currentPersonality,
                        charName: charName,
                        personaFacts: personaFacts,
                        similarClusters: similarClusters,
                      );
                    },
              ),
            );
          },
        ),
        // 人机恋阶段 2 装配（PS2-08）：CompanionRepository + 三服务 + 通知
        // scheduler + 升级提议 broker。均在 ChatService 之前声明（后者经
        // provider 消费，装配单源）；启动初始化/排程恢复经哑 Provider 触发
        // （unawaited，失败 debugPrint 不阻断构建）。
        Provider<CompanionRepository>(
          create: (context) => CompanionRepository(context.read<AppDatabase>()),
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
          create: (_) => scheduler ?? FlutterLocalNotificationsScheduler(),
        ),
        Provider<ProactiveMessageService>(
          create: (context) {
            final settings = context.read<SettingsRepository>();
            final factory = context.read<LLMProviderFactory>();
            return ProactiveMessageService(
              companionRepository: context.read<CompanionRepository>(),
              settingsRepository: settings,
              messageRepository: context.read<MessageRepository>(),
              planner:
                  ({
                    required int characterId,
                    required int conversationId,
                    required List<String> dialogueLines,
                  }) async {
                    final resolved = await settings
                        .wireCredentialsResolver()
                        .resolve();
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
              // F-84 P3 站内兜底：排程失败 → 全局 SnackBar 摘要文案
              // （SR-12：不含计划内容原文）。
              onScheduleFailed: (_) => showScheduleFailedNotice(),
            );
          },
        ),
        ChangeNotifierProvider<StageUpgradeBroker>(
          create: (_) => StageUpgradeBroker(),
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
            // VR-07 串行申报：回合末懒补嵌挂点（有落库/反思成功后触发）。
            embeddingService: context.read<EmbeddingService>(),
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
        // F-84 启动哑 Provider（lazy:false 立即执行）：通知初始化（幂等）+
        // SR-08 排程恢复；热态回调闭包随**首次** initialize 注册，装配晚到
        // 或顺延重挂经再次 initialize 透传新回调（插件 22.3.1 覆盖赋值、支持
        // 重设；F-92/F-97 锁串行 + 重挂语义下 `_initialized` 只防重复初始化
        // 副作用、不再吞回调）。回调复用冷启动装配组件（AppDeepLinkNavigator
        // + 两服务），依赖 ShellNavigation/ChatController 已声明，故置于其后。
        // 失败不阻断。
        Provider<Object?>(
          lazy: false, // W6-F1：无消费者时默认 lazy 永不执行，启动副作用必须立即触发
          create: (context) {
            unawaited(
              _startProactiveNotifications(
                context.read<FlutterLocalNotificationsScheduler>(),
                context.read<CompanionRepository>(),
                onDidReceiveNotificationResponse: (response) {
                  unawaited(
                    consumeProactiveNotificationResponse(
                      payload: response.payload,
                      navigator: AppDeepLinkNavigator(
                        navigation: context.read<ShellNavigation>(),
                        chatController: context.read<ChatController>(),
                      ),
                      messageRepository: context.read<MessageRepository>(),
                      proactiveMessageService: context
                          .read<ProactiveMessageService>(),
                      relationshipService: context.read<RelationshipService>(),
                    ),
                  );
                },
              ),
            );
            return null;
          },
        ),
        // PS2-10 冷启动深链接线：依赖 ShellNavigation + ChatController（均
        // 已声明），故独立哑 Provider 置于其后——取参 → 无 payload/失败
        // 静默；成功 → handleProactiveDeepLink（归属校验 + 导航高亮）。
        // 装配层单点（对齐 _startProactiveNotifications 哑 Provider 先例）。
        Provider<Object?>(
          lazy: false, // W6-F1：冷启动深链接线副作用，必须立即执行（同启动恢复）
          create: (context) {
            unawaited(
              consumeProactiveLaunchDeepLink(
                navigator: AppDeepLinkNavigator(
                  navigation: context.read<ShellNavigation>(),
                  chatController: context.read<ChatController>(),
                ),
                messageRepository: context.read<MessageRepository>(),
                proactiveMessageService: context
                    .read<ProactiveMessageService>(),
                relationshipService: context.read<RelationshipService>(),
              ),
            );
            return null;
          },
        ),
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
                final resolved = await settings
                    .wireCredentialsResolver()
                    .resolve();
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
                  apiKey: await secretStore.read(SecretStore.openaiApiKeySlot),
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
              // F-84 SnackBar 通道：装配层单点绑定（provider create 的
              // context 位于 MaterialApp 之上，经顶层 key 桥接）。
              scaffoldMessengerKey: rootScaffoldMessengerKey,
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
