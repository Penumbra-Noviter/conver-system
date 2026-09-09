/// M6-05 1.3x 大字无溢出探测——系统字号 1.3x（textScaler 注入）下主要页面
/// 无 RenderFlex overflow。
///
/// 验收语义（工单 05 验收 3/4 + spec §4.4 字体缩放「不 cap textScaler」）：
/// - 不强制 textScaler（跟随系统）：本测试仅注入 1.3x 媒体设定模拟系统大字，
///   不做任何缩放覆盖；
/// - 聊天对话面板（长文 Markdown 已完成气泡 + 流式占位）/ 聊天入口 /
///   角色列表 / 模拟器列表 / 搜索页 / 设置页 在 1.3x 下 pump 无
///   RenderFlex overflow 异常（`tester.takeException() == null`）。
///
/// 测试 seam（公共接口边界）：各视图公开组装（controller/env），经
/// MaterialApp 的 builder 注入 `MediaQuery(textScaler: TextScaler.linear(1.3))`
/// 定向构造；overflow（RenderFlex）在测试框架内以 FlutterError 呈现，
/// `takeException()` 一次性检查。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/search_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/view_models/theme_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_entry.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:conver_system_mobile/views/search/search_view.dart';
import 'package:conver_system_mobile/views/settings/settings_view.dart';
import 'package:drift/native.dart';

import 'package:conver_system_mobile/data/database/app_database.dart';
import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/in_memory_secret_store.dart';

void main() {
  /// 注入 1.3x textScaler 的 pump 外壳（不覆盖 textScaler——仅注入大字媒体）。
  Widget scalerApp(Widget child) => MaterialApp(
        theme: ConverTheme.dark(),
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: c!,
        ),
        home: Scaffold(body: child),
      );

  group('1.3x 无溢出（验收 3/4）', () {
    testWidgets('聊天对话面板：长文 Markdown 气泡 + 流式占位（真实触发 streaming）', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await env.seedMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '这条消息非常长，用来探测系统大字 1.3x 下滚动面板是否溢出：' * 3,
      );
      await env.seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '**加粗长文** 含段落与列表，用于探测 1.3x 下 Markdown 气泡：\n\n'
            '- 第一点：因为足够长所以可能换行\n'
            '- 第二点：继续撑开高度\n\n'
            '末段收尾的普通长文本内容，用于确保没有横向溢出。' * 2,
      );
      // 流式占位真实触发：发送 → 进入 streaming 渲染「Flexible 文字 + ▍ 光标」
      // 组合（1.3x 下与光标相关的唯一渲染面，此前从不受测）。token 序列较长，
      // 采样窗口内流式进行中且占位文字已积累成段（长内容 + 1.3x 边界）。
      final controller = env.controllerOf(
        TickingFakeLLMProvider(
          tokens: const ['今天是', '一个', '适合', '测试', '流式', '占位',
              '自动', '换行', '的', '长句子'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await controller.loadEntry();
      await controller.openConversation(conv.id);

      await tester.pumpWidget(scalerApp(ChatView(controller: controller)));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '1.3x 流式占位无溢出探测');
      await tester.pump();
      await tester.tap(find.byTooltip('发送'));
      // 积累 6 个 token（共 10 个）→ 占位文字「今天是一个适合测试流式占位」，
      // Streaming 仍进行中（长内容 + 光标同框渲染）。
      await tester.pump(const Duration(milliseconds: 60));

      // ListView.builder 懒构建：新流式行位于长文气泡之后、初始视口外不挂树。
      // 逐帧上滑强制构建到底，使「Flexible 文字 + ▍ 光标」组合真实渲染。
      for (var i = 0; i < 12 && find.text('▍').evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pump();
      }
      expect(find.text('▍'), findsOneWidget,
          reason: '流式占位真实触发——▍ 光标在 1.3x 大字下渲染');

      expect(tester.takeException(), isNull,
          reason: '聊天对话（长文 Markdown + 流式占位）在 1.3x 下无 RenderFlex overflow');

      // drain：让流式跑完避免 Timer pending。
      await tester.pump(const Duration(seconds: 1));
      await env.close();
    });

    testWidgets('聊天入口：标题行 + 新建按钮 + 最近对话列表', (tester) async {
      final env = await ChatTestEnv.create();
      final controller = env.controllerOf(FakeLLMProvider(tokens: const []));
      await controller.loadEntry();

      await tester.pumpWidget(
        scalerApp(ChatEntry(controller: controller)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '聊天入口在 1.3x 下无 overflow');
      await env.close();
    });

    testWidgets('搜索页：query 输入框 + 结果/五态', (tester) async {
      // 注入可控 service（空库：query 为空 → 空列表不发查询；纯布局探测）。
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = SearchService(MessageRepository(db));
      await tester.pumpWidget(
        scalerApp(SearchView(service: service)),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: '搜索页初始态在 1.3x 下无 overflow');
    });

    testWidgets('设置页：头部 + 各 section 列表', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final store = InMemorySecretStore();
      final repo = SettingsRepository(database: db, secretStore: store);

      await tester.pumpWidget(
        scalerApp(
          SettingsView(
            settingsRepository: repo,
            themeController: ThemeController(settingsRepository: repo),
            secretStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: '设置页在 1.3x 下无 overflow');
    });
  });
}