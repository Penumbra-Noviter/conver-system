import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/database/app_database.dart';
import 'data/repositories/character_repository.dart';
import 'data/repositories/conversation_repository.dart';
import 'data/repositories/message_repository.dart';
import 'data/repositories/settings_repository.dart';
import 'services/chat_service.dart';
import 'services/llm/factory.dart';
import 'services/llm/llm_provider.dart';
import 'services/secure_store.dart';
import 'theme/conver_theme.dart';
import 'view_models/shell_navigation.dart';
import 'view_models/theme_controller.dart';
import 'views/chat/chat_controller.dart';
import 'views/home_shell.dart';

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
        // M2-T04 聊天装配：LLM 工厂 + 回合编排服务 + 聊天控制器。
        // 视图层（ChatView / ChatEntry）只读 ChatController 与仓储抽象，不触碰
        // 数据层 / 平台存储（layer_boundary_test 契约）；装配链单一收编于此。
        Provider<LLMProviderFactory>(
          create: (_) => const LLMFactory(),
        ),
        Provider<ChatService>(
          create: (context) => ChatService(
            database: context.read<AppDatabase>(),
            conversationRepository: context.read<ConversationRepository>(),
            characterRepository: context.read<CharacterRepository>(),
            messageRepository: context.read<MessageRepository>(),
            settingsRepository: context.read<SettingsRepository>(),
            providerFactory: context.read<LLMProviderFactory>(),
          ),
        ),
        ChangeNotifierProvider<ChatController>(
          create: (context) => ChatController(
            chatService: context.read<ChatService>(),
            conversationRepository: context.read<ConversationRepository>(),
            characterRepository: context.read<CharacterRepository>(),
            messageRepository: context.read<MessageRepository>(),
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
              home: const HomeShell(),
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
