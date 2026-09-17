/// 聊天对话面板 widget 契约（T04b 切片）。
///
/// 对话面（锚：`desktop/frontend/js/chat.js` 发送↔停止两态 + `stream-session.js`
/// onToken 打字机累积 + streamSettled 终态守卫；spec ID-5/6/7/8）：
/// - 打字机：streaming 占位气泡**纯文本**逐 token 追加（两级降频：streaming
///   期间不渲染 Markdown）+ 单点闪烁光标（非三点 typing）；
/// - 完成态：静态 **Markdown** 渲染（warm_markdown_style 深浅两套）；
/// - 发送 ↔ 停止两态：生成中按钮变红色「停止」，点停止中止并标「已停止」，
///   无部分内容仅保留已发 user；
/// - assistant 气泡底部常驻重生成小图标；成功原位替换、失败旧回复保留 + notice；
/// - 断流非阻塞「回复已中断」（可 dismiss，不挡后续操作）；未配置 Key 映射文案。
///
/// 测试 seam（公共接口边界）：ChatView 公开接口 + ChatController 可观察状态 +
/// 落库结果（经 [ChatTestEnv.messageRepository]）。内存库 + InMemorySecretStore +
/// Fake/Ticking provider 驱动真实 ChatService。
///
/// 环境形态注意（FakeAsync 特性）：ChatService 取消收尾（cancel/close 相互
/// 等待）在 widget 测试的 fake 时钟下会挂起；其**已累积部分落库**在挂起前已
/// 幂等完成，UI 可正常呈现「已停止」。故本文件每个测试体自建 env + 测试体内
/// 显式 `await env.close()`（tearDown 阶段在 fake 时钟边界下可能挂起——实证）。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart' show Message;
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/conversation_export_file_exchange.dart';
import 'package:conver_system_mobile/services/conversation_export_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/colors.dart' show ConverColors;
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:conver_system_mobile/widgets/notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';
import '../../helpers/pump_until.dart';

/// 导出 seam fake（M4-03 widget 层）：记录分享调用并返回固定文案，
/// 不触真平台通道。
class _FakeExportFileExchange extends ConversationExportFileExchange {
  _FakeExportFileExchange({this.message = '已导出 艾莉亚.json（分享面板已打开）'});

  final String message;
  final List<ConversationExportResult> calls = [];
  String? lastFileName;

  @override
  Future<String> exportFile(ConversationExportResult result) async {
    calls.add(result);
    lastFileName = result.fileName;
    return message;
  }
}

void main() {
  Future<void> pumpChat(WidgetTester tester, ChatController controller) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: ChatView(controller: controller)),
      ),
    );
    await tester.pump();
  }

  /// 种子角色 + 会话并打开（无开场白 → 空消息列表）；返回控制器。
  Future<ChatController> openConversation(
    WidgetTester tester,
    ChatTestEnv env,
    LLMProvider provider, {
    String firstMes = '',
    int? characterId,
    List<Duration> connectRetryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  }) async {
    final char = characterId == null
        ? await env.seedCharacter(firstMes: firstMes)
        : (await env.characterRepository.getCharacter(characterId))!;
    final conv = await env.seedConversation(char.id);
    final c = env.controllerOf(provider, connectRetryDelays: connectRetryDelays);
    await c.loadEntry();
    await c.openConversation(conv.id);
    await pumpChat(tester, c);
    return c;
  }

  /// 经 UI 发送一条消息（输入框 + 发送按钮）。
  Future<void> sendViaUi(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
  }

  group('打字机 · 逐 token 追加 + 单点光标（R4 两级降频）', () {
    testWidgets('发送 → 两态；token 追加为纯文本占位（无 MarkdownBody）；完成态静态渲染',
        (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        // M6-07：token 间隔拉长至 200ms——流式窗口（3×200ms）须大于按钮
        // AnimatedSwitcher 过渡窗口（140ms），使「发送→停止」切换的稳态可被
        // 观测（过渡期新旧按钮并存属动效固有行为）。
        TickingFakeLLMProvider(
          tokens: const ['你', '好', '！'],
          delay: const Duration(milliseconds: 200),
        ),
      );

      await sendViaUi(tester, '早上好');

      // 发送 ↔ 停止：分步 pump 完成 AnimatedSwitcher 过渡（>140ms）后断言
      // 稳态（过渡期新旧按钮并存属动效固有行为；首个 token 200ms 后才到，
      // 150ms 采样安全）。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.byTooltip('停止'), findsOneWidget,
          reason: '发送↔停止两态：生成中为停止');
      expect(find.byTooltip('发送'), findsNothing);
      expect(find.text('早上好'), findsOneWidget, reason: 'user 消息即时渲染');

      // 第一 token（200ms 到点流式占位出现）：纯文本 + 单点光标，无 Markdown。
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(MarkdownBody), findsNothing,
          reason: 'streaming 期间两级降频：不跑 Markdown 渲染');
      expect(find.text('你'), findsOneWidget);
      expect(find.text('▍'), findsOneWidget, reason: '单点闪烁光标（非三点 typing）');

      // 第二 / 第三 token 追加。
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('你好'), findsOneWidget, reason: '逐 token 追加');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      // 完成态：静态 Markdown 渲染完整回复，`▍` 光标消失；pump 完成
      // 停止→发送切换的 AnimatedSwitcher 过渡后再断言稳态。
      await pumpUntil(
        tester,
        () => find.text('你好！', findRichText: true).evaluate().isNotEmpty,
        why: '完整回复完成且静态渲染',
      );
      // M6-07：分步 pump 完成停止→发送 AnimatedSwitcher 过渡后断言稳态。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsWidgets,
          reason: '已完成 assistant 静态 Markdown');
      expect(find.text('▍'), findsNothing);
      expect(find.byTooltip('发送'), findsOneWidget);
      expect(find.byTooltip('停止'), findsNothing);

      // 落库权威：user + assistant 完整内容。
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, '早上好'), (Role.assistant, '你好！')]);
      await env.close();
    });

    testWidgets('已完成 Markdown 静态渲染（加粗/列表 hits 渲染链路）', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await env.seedMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '如何实现？',
      );
      await env.seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '**重点** 见下：\n\n- 第一点\n- 第二点',
      );
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await c.openConversation(conv.id);
      await pumpChat(tester, c);

      expect(find.byType(MarkdownBody), findsOneWidget);
      expect(find.textContaining('重点', findRichText: true), findsOneWidget,
          reason: 'Markdown 加粗文本可渲染');
      expect(find.textContaining('第一点', findRichText: true), findsOneWidget);
      await env.close();
    });
  });

  group('停止 · 已累积部分保留 +「已停止」标记（A3 UI 面）', () {
    testWidgets('停止 → 部分内容落库 + 标记「已停止」；两态复位', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['t0', 't1', 't2', 't3', 't4'],
          delay: const Duration(milliseconds: 100),
        ),
      );

      await sendViaUi(tester, 'hi');

      // 观测两个 token（t0t1）出现后点停止。
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.text('t0t1'), findsOneWidget, reason: '已累积 t0t1');

      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      // 耗尽剩余 provider 的 pending token timers（ChatService 取消收尾中
      // async* 挂起的 delay；另见文件头 note）。
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(find.byTooltip('发送'), findsOneWidget, reason: '停止后复位发送');
      expect(c.notice, isNull, reason: '主动停止非错误，无提示');
      expect(find.text('已停止'), findsOneWidget);
      expect(find.textContaining('t0t1', findRichText: true), findsOneWidget,
          reason: '部分内容保留（呈现于 UI）');
      // 落库：user + 部分 assistant（DB 存纯文本部分内容）。
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 't0t1')]);
      await env.close();
    });

    testWidgets('无部分内容停止 → 仅保留已发 user，无「已停止」标记', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['a'],
          delay: const Duration(milliseconds: 100),
        ),
      );
      // 对话无开场白 → 空消息列表；发送后首 token 未到即停止。
      await sendViaUi(tester, 'hi');
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byTooltip('停止'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200)); // 耗尽 token timer
      await tester.pump();
      await tester.pump();

      expect(find.text('hi'), findsOneWidget, reason: '已发 user 仍在列表');
      // 无部分内容 → 仅保留已发 user（落库权威；「已停止」标记的 UI 面
      // 无部分场景已在 chat_controller_test 断言 stopped=false）。
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) m.role], [Role.user]);
      await env.close();
    });
  });

  group('断流 · 非阻塞「回复已中断」（A5 UI 面）', () {
    testWidgets('断流 → 部分落库 + 提示可 dismiss；随后可继续发送', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['a', 'b'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 5),
        ),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流 notice 出现');

      expect(c.isStreaming, isFalse);
      expect(find.textContaining('ab', findRichText: true), findsOneWidget,
          reason: '断流已累积部分落库后呈现');
      // M6-07：停止→发送切换 AnimatedSwitcher 过渡完成后再断言稳态。
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(find.byTooltip('发送'), findsOneWidget, reason: '非阻塞：后续操作可用');

      // dismiss 后提示消失，可继续发送（非阻塞语义）。W5 B1：关闭先经
      // 140ms 出口淡出，过渡完成后再卸载。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(find.text('回复已中断'), findsNothing);

      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'ab')]);
      await env.close();
    });

    testWidgets('未配置 Key → 映射文案提示（不渲染 assistant）', (tester) async {
      final env = await ChatTestEnv.create();
      await env.secretStore.delete(SecretStore.claudeApiKeySlot);
      final c = await openConversation(
        tester,
        env,
        FakeLLMProvider(tokens: const ['x']),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(
        tester,
        () => find.text('未配置 claude API Key，请在设置中填写').evaluate().isNotEmpty,
        why: '未配置 Key 映射文案',
      );
      expect(find.byType(MarkdownBody), findsNothing);
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) m.role], [Role.user]);
      await env.close();
    });

    // W5 审核 B1 防复发：NoticeBanner「消失」应有 140ms 出口过渡（验收 3
    // 完整达成），而非 dismiss 后即时硬切卸载。
    testWidgets('dismiss → 出口过渡中旧提示仍在树中（Fade 渐隐）→ 过渡完成后卸载',
        (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['a', 'b'],
          errorAfter: LLMConnectionInterruptedError(),
          delay: const Duration(milliseconds: 5),
        ),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流 notice 出现');
      await tester.pump();
      expect(find.text('回复已中断'), findsOneWidget);

      // 点关闭 → 过渡进行中（~70ms）旧 child 仍在树中（退出动画未完成）。
      // （IconButton 的 tooltip 在 AnimatedOpacity 外包下坐标偏移，直接用
      // 图标定位并容忍命中告警。）
      final closeFinder = find.byTooltip('关闭提示');
      await tester.tapAt(tester.getCenter(closeFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.text('回复已中断'), findsOneWidget,
          reason: '出口过渡进行中：旧提示仍在树中（Fade 渐隐，非即时卸载）');

      // 过渡完成后（>140ms）提示卸载消失。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('回复已中断'), findsNothing,
          reason: '出口过渡完成：提示卸载');
      await env.close();
    });
  });

  group('断流「回复中断」标记 + NoticeBanner 重试（M6-08）', () {
    testWidgets('断流有部分内容 → 气泡「回复中断」小标 + 提示条「重试」「关闭」'
        '共存；「已停止」不出现（验收 1/2）', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        InterruptStreamRetryProvider(reply: '新回复'),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流提示出现');
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();

      expect(find.text('回复中断'), findsOneWidget,
          reason: '截断回复气泡「回复中断」小标');
      expect(find.text('已停止'), findsNothing,
          reason: '断流非主动停止，「已停止」不出现（两标互斥）');
      expect(find.text('重试'), findsOneWidget,
          reason: '「回复已中断」提示条含「重试」动作');
      expect(find.byTooltip('关闭提示'), findsOneWidget,
          reason: '重试按钮与关闭按钮共存');
      expect(c.messages.last.interrupted, isTrue, reason: '控制器消息面打「回复中断」标');
      expect(c.messages.last.stopped, isFalse);
      expect(c.hasRetryableInterrupted, isTrue, reason: '存在可重试截断目标');
      await env.close();
    });

    testWidgets('点「重试」→ regenerate replace：截断行替换、标记与提示消失、'
        '不新增 user 行（验收 3/6）', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        InterruptStreamRetryProvider(reply: '新回复'),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流提示出现');
      expect(find.text('回复中断'), findsOneWidget);
      expect(find.text('hi'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.text('新回复', findRichText: true).evaluate().isNotEmpty &&
            find.text('回复中断').evaluate().isEmpty,
        why: '重试完成：截断行替换、标记消失',
      );

      expect(find.text('回复已中断'), findsNothing, reason: '中断已解决，提示消失');
      expect(find.text('重试'), findsNothing, reason: '无可重试目标后动作消失');
      expect(c.hasRetryableInterrupted, isFalse);
      expect(c.messages.last.interrupted, isFalse, reason: '新回复无「回复中断」标');
      // replace 语义：无重复 user 输入行。
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: '图标 regenerate replace 成功、无重复 user 行');
      await env.close();
    });

    testWidgets('双截断 → 横幅重试后持续可点（指向最近剩余截断）→ 再重试 → 全清'
        '（F-65① UI 面 + 重写语义）', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        InterruptStreamRetryProvider(reply: '新回复'),
      );

      // 两次发送各断流 → A/B 双截断。
      await sendViaUi(tester, '第一问');
      await pumpUntil(
          tester,
          () => find.text('回复中断').evaluate().length == 1,
          why: '截断 A 标记就绪');
      // 完成停止→发送 AnimatedSwitcher 过渡（防双按钮歧义）。
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      await sendViaUi(tester, '第二问');
      await pumpUntil(
          tester,
          () => find.text('回复中断').evaluate().length == 2,
          why: '双截断标记就绪');
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(c.hasRetryableInterrupted, isTrue, reason: '横幅含可重试目标');

      // 重试最近截断（B）→ 横幅保持（余标 A 推进为 notice 目标）。
      await tester.tap(find.text('重试'));
      await tester.pump();
      await pumpUntil(tester, () => !c.isRegenerating, why: '第一次重试收尾');
      expect(c.hasRetryableInterrupted, isTrue,
          reason: 'F-65①：余标推进后横幅仍可重试');
      expect(c.notice, '回复已中断');
      expect(find.text('重试'), findsOneWidget, reason: '横幅持续（不消失）');
      await pumpUntil(
          tester,
          () => find.text('回复中断').evaluate().length == 1,
          why: 'B 已替换，仅余 A 小标');

      // 再重试（推进目标 A）→ 全清、横幅消失。
      await tester.tap(find.text('重试'));
      await tester.pump();
      await pumpUntil(
          tester,
          () => !c.isRegenerating && find.text('回复已中断').evaluate().isEmpty,
          why: '第二次重试完成且横幅消失',
      );
      expect(c.hasRetryableInterrupted, isFalse);
      expect(c.notice, isNull);
      expect(find.text('回复中断'), findsNothing, reason: '全部截断已解决');
      final settled =
          await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, '第一问'), (Role.assistant, '新回复')],
          reason: '重写语义：从 A 截断点重写后续全部');
      await env.close();
    });

    testWidgets('重试失败 → 旧截断行保留 + 提示保持「回复已中断」（先错者胜）'
        '，无未处理异常（验收 4）', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        InterruptThenAuthFailProvider(),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流提示出现');

      await tester.tap(find.text('重试'));
      await tester.pump();
      await pumpUntil(tester, () => !c.isRegenerating, why: '重试收尾');

      expect(find.text('回复中断'), findsOneWidget, reason: '旧截断行保留、标记保留');
      expect(find.text('回复已中断'), findsOneWidget,
          reason: '先错者胜：既有提示不被失败文案覆盖');
      expect(find.text('API Key 无效，请在设置中更新'), findsNothing,
          reason: '先错者胜：重试失败文案不覆盖「回复已中断」');
      final settled = await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, 'a')],
          reason: '失败不删行、旧截断行保留');
      expect(tester.takeException(), isNull, reason: '无未处理异常');
      await env.close();
    });

    testWidgets('断流后点气泡图标「重生成」→ 标记清除 + 横幅消失 + 无可重试目标'
        '（B1=W6 F-1 死重试按钮回归）', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        InterruptStreamRetryProvider(reply: '新回复'),
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流提示出现');
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pump();
      expect(find.text('回复中断'), findsOneWidget, reason: '前置：截断标记');
      expect(find.text('重试'), findsOneWidget, reason: '前置：横幅含重试');
      expect(c.hasRetryableInterrupted, isTrue);

      // 用户点气泡「重生成」图标（非横幅重试）→ 缺省末条 = 截断消息。
      await tester.tap(find.byTooltip('重生成'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.text('新回复', findRichText: true).evaluate().isNotEmpty &&
            find.text('回复中断').evaluate().isEmpty,
        why: '图标 regenerate 替换完成、标记清除',
      );

      expect(find.text('回复已中断'), findsNothing,
          reason: '横幅消失（F-1：regenerate 路径不再残留死重试提示）');
      expect(find.text('重试'), findsNothing, reason: '死重试按钮不复存在');
      expect(c.hasRetryableInterrupted, isFalse);
      expect(c.notice, isNull);
      expect(c.messages.last.interrupted, isFalse);
      final settled =
          await env.messageRepository.getMessages(c.activeConversationId!);
      expect([for (final m in settled) (m.role, m.content)],
          [(Role.user, 'hi'), (Role.assistant, '新回复')],
          reason: '图标 regenerate replace 成功、无重复 user 行');
      await env.close();
    });

    testWidgets('断流零部分内容 → 无「回复中断」标、提示条无「重试」（验收 7）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const [],
          errorAfter: LLMConnectionInterruptedError(),
        ),
        // 无 token 连接中断属首 token 前重试窗口：注入空退避直接收束。
        connectRetryDelays: const [],
      );

      await sendViaUi(tester, 'hi');
      await pumpUntil(tester, () => find.text('回复已中断').evaluate().isNotEmpty,
          why: '断流提示出现');

      expect(find.text('回复中断'), findsNothing, reason: '零部分无截断回复可标记');
      expect(find.text('重试'), findsNothing, reason: '无截断目标不出现重试动作');
      expect(find.byTooltip('关闭提示'), findsOneWidget, reason: '仅关闭仍可用');
      await env.close();
    });
  });

  group('重生成 · 常驻小图标（A4 UI 面）', () {
    Future<int> seedConversationWithReply(
        ChatTestEnv env, {String reply = '旧回复'}) async {
      // 角色无开场白 → 会话里仅 [user, assistant] 两条，assistant 恰为末条
      // （A4 重生成仅末条已结算 assistant，测试锚用）。
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await env.seedMessage(
          conversationId: conv.id, role: Role.user, content: '你好');
      await env.seedMessage(
          conversationId: conv.id, role: Role.assistant, content: reply);
      return conv.id;
    }

    Future<ChatController> openSeeded(WidgetTester tester, ChatTestEnv env,
        LLMProvider provider,
        {required int convId}) async {
      final c = env.controllerOf(provider);
      await c.loadEntry();
      await c.openConversation(convId);
      await pumpChat(tester, c);
      return c;
    }

    testWidgets('重生成成功 → 新回复原位替换（旧回复消失）', (tester) async {
      final env = await ChatTestEnv.create();
      final convId = await seedConversationWithReply(env);
      await openSeeded(
        tester,
        env,
        FakeLLMProvider(tokens: const ['新回复']),
        convId: convId,
      );

      expect(find.text('旧回复', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('重生成'));
      await tester.pump();
      await pumpUntil(
        tester,
        () => find.text('新回复', findRichText: true).evaluate().isNotEmpty,
        why: '重生成完成',
      );

      expect(find.text('旧回复', findRichText: true), findsNothing,
          reason: '成功替换旧回复');
      final settled = await env.messageRepository.getMessages(convId);
      expect([for (final m in settled) (m.role, m.content)],
          contains((Role.assistant, '新回复')));
      await env.close();
    });

    testWidgets('重生成失败 → 旧回复保留 + 非阻塞 notice', (tester) async {
      final env = await ChatTestEnv.create();
      final convId = await seedConversationWithReply(env);
      final c = await openSeeded(
        tester,
        env,
        FakeLLMProvider(
          tokens: const [],
          error: LLMAuthError('claude'),
          generateDelay: const Duration(milliseconds: 400),
        ),
        convId: convId,
      );

      expect(find.text('旧回复', findRichText: true), findsOneWidget);
      await tester.tap(find.byTooltip('重生成'));
      await tester.pump();
      // 重生成进行中（generateDelay 400ms 保持 in-flight）：图标禁用。
      final regenButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(regenButton.onPressed, isNull, reason: '重生成期间图标禁用');

      await pumpUntil(
        tester,
        () => find.text('API Key 无效，请在设置中更新').evaluate().isNotEmpty,
        why: '重生成失败 notice',
      );
      expect(find.text('旧回复', findRichText: true), findsOneWidget,
          reason: '失败旧回复保留（延迟删除）');
      expect(c.isRegenerating, isFalse);
      final recovered = tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh));
      expect(recovered.onPressed, isNotNull, reason: '图标恢复可用');
      await env.close();
    });
  });

  group('导航 · 返回入口', () {
    testWidgets('返回按钮 → 回入口并刷新最近列表', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await c.openConversation(conv.id);
      await pumpChat(tester, c);
      expect(c.activeConversationId, conv.id);

      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      await pumpUntil(tester, () => c.isEntry, why: '返回入口');

      expect(find.text('聊天'), findsOneWidget);
      expect(find.text('新建对话'), findsOneWidget);
      expect(find.text('与 艾莉亚 的对话'), findsOneWidget, reason: '入口列表刷新');
      await env.close();
    });
  });

  group('跳转定位高亮 · GlobalObjectKey + ensureVisible + 3s 清除（M3-04c）', () {
    /// 目标消息 GlobalObjectKey 判定器（GlobalObjectKey 按 value 判等，测试
    /// 用 value 字符串比较，不依赖实例同一性）。
    Finder msgKeyOf(int id) => find.byWidgetPredicate(
          (w) => w.key is GlobalObjectKey && (w.key as GlobalObjectKey).value == 'msg-$id',
        );

    /// 渲染中带琥珀底（ConverColors.accentSoft）的气泡容器数。
    int amberBubbleCount(WidgetTester tester) {
      var count = 0;
      for (final w in tester.widgetList<Container>(find.byType(Container))) {
        final deco = w.decoration;
        if (deco is BoxDecoration && deco.color == ConverColors.accentSoft) {
          count++;
        }
      }
      return count;
    }

    /// 种子多消息会话（无开场白 → 列表即 DB 消息），返回 (会话 id, 目标 id)。
    Future<(int, int)> seedManyMessages(
      ChatTestEnv env, {
      int count = 12,
      int targetIndex = 8,
    }) async {
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      Message? target;
      for (var i = 0; i < count; i++) {
        final role = i.isEven ? Role.user : Role.assistant;
        final msg = await env.seedMessage(
          conversationId: conv.id,
          role: role,
          content: '消息 ${i + 1} 号内容',
        );
        if (i == targetIndex) {
          target = msg;
        }
      }
      return (conv.id, target!.id);
    }

    /// 打开会话并带高亮目标，等待定位帧完成（post-frame ensureVisible）。
    Future<ChatController> openWithHighlight(
      WidgetTester tester,
      ChatTestEnv env,
      int convId,
      int targetId,
    ) async {
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await c.openConversation(convId, highlightMessageId: targetId);
      await pumpChat(tester, c);
      await tester.pump(); // ensureVisible 帧
      return c;
    }

    testWidgets('目标命中 → GlobalObjectKey 挂载 + 琥珀高亮 + 滚至视口中部（验收 2/3）',
        (tester) async {
      final env = await ChatTestEnv.create();
      final (convId, targetId) = await seedManyMessages(env);
      final c = await openWithHighlight(tester, env, convId, targetId);

      // GlobalObjectKey('msg-<id>') 存在性。
      expect(msgKeyOf(targetId), findsOneWidget, reason: '目标气泡挂 GlobalObjectKey');

      // 高亮样式：恰一个琥珀底气泡（目标气泡）。
      expect(amberBubbleCount(tester), 1, reason: '目标气泡琥珀高亮');

      // ensureVisible(alignment 0.5) 落位：目标中心位于消息列表视口的中部带。
      final listRect = tester.getRect(find.byType(ListView));
      final targetRect = tester.getRect(msgKeyOf(targetId));
      final relativeY =
          (targetRect.center.dy - listRect.top) / listRect.height;
      expect(relativeY, inInclusiveRange(0.3, 0.7),
          reason: 'ensureVisible 将目标滚至视口中部（非顶部非底部）');

      expect(c.highlightMessageIds, {targetId});
      // 让 3s 高亮 timer 走完（避免测试结束 pending timer 断言失败）。
      await tester.pump(const Duration(seconds: 3));
      await env.close();
    });

    testWidgets('3 秒后高亮自动清除（对齐桌面 3000ms 语义，验收 3）', (tester) async {
      final env = await ChatTestEnv.create();
      final (convId, targetId) = await seedManyMessages(env);
      final c = await openWithHighlight(tester, env, convId, targetId);
      expect(amberBubbleCount(tester), 1);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(amberBubbleCount(tester), 0, reason: '3s 后琥珀高亮熄灭');
      expect(c.highlightMessageIds, isEmpty, reason: '控制器高亮集合同步移除');
      await env.close();
    });

    testWidgets('目标消息不存在 → 无高亮、回落滚到底部（验收 4）', (tester) async {
      final env = await ChatTestEnv.create();
      final (convId, _) = await seedManyMessages(env);
      await openWithHighlight(tester, env, convId, 999999); // 不存在 id

      expect(amberBubbleCount(tester), 0, reason: '目标不存在无高亮');

      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable))
            .first,
      );
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent,
          reason: '目标缺失回落滚动到底部');
      expect(tester.takeException(), isNull, reason: '不出错不挂起');
      // 让 3s 高亮 timer 走完（避免测试结束 pending timer 断言失败）。
      await tester.pump(const Duration(seconds: 3));
      await env.close();
    });

    testWidgets('合成负 id 不干扰：流式占位负 id 不高亮（验收 5）', (tester) async {
      final env = await ChatTestEnv.create();
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      await env.seedMessage(
          conversationId: conv.id, role: Role.user, content: '命中消息');
      final target = await env.seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '目标气泡');
      final c = env.controllerOf(TickingFakeLLMProvider(
        tokens: const ['流', '式'],
        delay: const Duration(milliseconds: 50),
      ));
      await c.loadEntry();
      await c.openConversation(conv.id, highlightMessageId: target.id);
      await pumpChat(tester, c);
      await tester.pump();
      expect(amberBubbleCount(tester), 1, reason: '目标气泡高亮');

      // 发送 → 流式占位（合成负 id）持续在列表中；仍只目标气泡高亮。
      await sendViaUi(tester, '流式触发');
      await pumpUntil(tester, () => c.streamingText == '流', why: '首 token 到达');
      await tester.pump(const Duration(milliseconds: 10));

      final syntheticIds = [
        for (final m in c.messages)
          if (m.id < 0) m.id,
      ];
      expect(syntheticIds, isNotEmpty, reason: '流式占位负 id 存在（场景前提）');
      expect(c.highlightMessageIds.single, greaterThan(0),
          reason: '高亮集合只含 DB 正 id');
      expect(amberBubbleCount(tester), 1,
          reason: '流式占位（负 id）不被高亮');

      // 回合收尾 + 3s 高亮 timer 走完（防 pending timer 断言失败）。
      await pumpUntil(tester, () => !c.isStreaming, why: '回合完成');
      await tester.pump(const Duration(seconds: 3));
      await env.close();
    });

    testWidgets('视图 dispose → 取消高亮 Timer（无后置 setState，验收 3）',
        (tester) async {
      final env = await ChatTestEnv.create();
      final (convId, targetId) = await seedManyMessages(env);
      await openWithHighlight(tester, env, convId, targetId);
      expect(amberBubbleCount(tester), 1);

      // 卸载视图（控制器存活，其 3s Timer 仍在）：dispose 取消视图侧 timer。
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '无后置 setState / 无泄漏异常');
      await env.close();
    });
  });

  group('导出菜单 · 顶栏 PopupMenuButton（M4-03）', () {
    /// 装配带导出依赖（真实导出服务 + fake seam）的控制器并打开会话。
    Future<ChatController> openWithExport(
      WidgetTester tester,
      ChatTestEnv env,
      _FakeExportFileExchange seam,
    ) async {
      final char = await env.seedCharacter();
      final conv = await env.seedConversation(char.id);
      final service = ConversationExportService(
        conversationRepository: env.conversationRepository,
        characterRepository: env.characterRepository,
        messageRepository: env.messageRepository,
        settingsReader: const FakeSettingsReader(),
      );
      final c = env.controllerOf(
        FakeLLMProvider(tokens: const []),
        exportService: service,
        exportFileExchange: seam,
      );
      await c.loadEntry();
      await c.openConversation(conv.id);
      await pumpChat(tester, c);
      return c;
    }

    testWidgets('对话页顶栏出现 ⋯ 菜单，两项逐字「导出 JSON」「导出 Markdown」',
        (tester) async {
      final env = await ChatTestEnv.create();
      final seam = _FakeExportFileExchange();
      await openWithExport(tester, env, seam);

      expect(find.byTooltip('导出对话'), findsOneWidget,
          reason: '对话态顶栏有导出菜单（⋯）');
      await tester.tap(find.byTooltip('导出对话'));
      await tester.pumpAndSettle();

      expect(find.text('导出 JSON'), findsOneWidget);
      expect(find.text('导出 Markdown'), findsOneWidget);
      await env.close();
    });

    testWidgets('点「导出 JSON」→ controller.exportJson → seam 收到调用 → notice 显示 seam 文案',
        (tester) async {
      final env = await ChatTestEnv.create();
      final seam = _FakeExportFileExchange();
      final c = await openWithExport(tester, env, seam);

      await tester.tap(find.byTooltip('导出对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();

      expect(seam.calls, hasLength(1));
      expect(seam.lastFileName, endsWith('.json'));
      expect(find.text('已导出 艾莉亚.json（分享面板已打开）'), findsOneWidget,
          reason: '非阻塞 notice 展示 seam 返回文案');
      expect(c.exporting, isFalse, reason: '完成后复位');
      await env.close();
    });

    testWidgets('点「导出 Markdown」→ seam 收到 .md 调用', (tester) async {
      final env = await ChatTestEnv.create();
      final seam = _FakeExportFileExchange(message: '已导出 艾莉亚.md（分享面板已打开）');
      await openWithExport(tester, env, seam);

      await tester.tap(find.byTooltip('导出对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 Markdown'));
      await tester.pumpAndSettle();

      expect(seam.calls, hasLength(1));
      expect(seam.lastFileName, endsWith('.md'));
      expect(find.text('已导出 艾莉亚.md（分享面板已打开）'), findsOneWidget);
      await env.close();
    });

    testWidgets('NoticeBanner 收到控制器 noticeId（F-65④ seq 接线：视图传 id）',
        (tester) async {
      final env = await ChatTestEnv.create();
      final seam = _FakeExportFileExchange();
      final c = await openWithExport(tester, env, seam);

      await tester.tap(find.byTooltip('导出对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();

      final banner = tester.widget<NoticeBanner>(find.byType(NoticeBanner));
      expect(c.noticeId, isNotNull, reason: 'notice 置位即分配身份 seq');
      expect(banner.noticeId, c.noticeId,
          reason: 'chat_view 把控制器 noticeId 传给 NoticeBanner（seq 接线）');
      await env.close();
    });

    testWidgets('④ 同文案新旧 notice：出口过渡窗口内同文案新 notice 到达 → 陈旧 '
        'dismiss 不误清新 notice（notice 身份 seq end-to-end）', (tester) async {
      final env = await ChatTestEnv.create();
      final seam = _FakeExportFileExchange();
      final c = await openWithExport(tester, env, seam);

      const notice = '已导出 艾莉亚.json（分享面板已打开）';
      // 第一次导出 → notice（seam 固定文案，id=1）。
      await tester.tap(find.byTooltip('导出对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出 JSON'));
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      final firstId = c.noticeId;
      expect(firstId, isNotNull, reason: 'notice 置位即分配身份');

      // 点关闭 → 140ms 出口过渡开始（分步 pump，不 pumpAndSettle——settle 会
      // 跑完整个过渡）。
      await tester.tap(find.byTooltip('关闭提示'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(c.noticeId, firstId, reason: '过渡完成前 onDismiss 未触发，身份不变');

      // 过渡窗口内同文案新 notice：再次导出 → NoticeRunner 分配新 seq（同文案
      // 也分新身份）。小步 pump（合计 <140ms，过渡 timer 未触发）。
      unawaited(c.exportJson());
      for (var i = 0; i < 60 && c.noticeId == firstId; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(c.noticeId, isNot(firstId),
          reason: '窗口内同文案新 notice 分配新身份 seq');
      expect(c.notice, notice, reason: '新 notice 文案不变（同文案重现值）');

      // 越过 140ms 计时 → 陈旧 dismiss（id1）不得误清新 notice（id2）。
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(c.noticeId, isNot(firstId), reason: '新 notice 未被陈旧 dismiss 清掉');
      expect(c.notice, notice, reason: '陈旧 dismiss 不误清新 notice');
      expect(find.text(notice), findsOneWidget, reason: '新 notice 持续呈现');
      expect(tester.takeException(), isNull, reason: 'zone 零未处理异常');
      await env.close();
    });

    testWidgets('入口页（无会话）不出现导出菜单', (tester) async {
      final env = await ChatTestEnv.create();
      final c = env.controllerOf(FakeLLMProvider(tokens: const []));
      await c.loadEntry();
      await pumpChat(tester, c);

      expect(c.isEntry, isTrue, reason: '停留在入口页');
      expect(find.byTooltip('导出对话'), findsNothing,
          reason: '无会话不出现导出菜单（入口页零菜单）');
      expect(find.text('导出 JSON'), findsNothing);
      await env.close();
    });
  });

  group('语义覆盖（M6-03 验收 1/2/3）', () {
    testWidgets('user 气泡 MergeSemantics label「你: 内容」整体朗读', (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(tester, env, FakeLLMProvider(tokens: const []));
      await sendViaUi(tester, '早上好');

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('你: 早上好'), findsOneWidget,
          reason: 'user 气泡 label「你: 内容」');
      handle.dispose();
      await env.close();
    });

    testWidgets('assistant 气泡 MergeSemantics label「角色名: 内容」（角色名取当前会话角色）',
        (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['早上好', '！'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await sendViaUi(tester, 'hi');
      await pumpUntil(
        tester,
        () => find.text('早上好！', findRichText: true).evaluate().isNotEmpty,
        why: 'assistant 完整回复完成',
      );

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('艾莉亚: 早上好！'), findsOneWidget,
          reason: 'assistant 气泡 label「角色名: 内容」（默认 seed 角色名艾莉亚）');
      handle.dispose();
      await env.close();
    });

    testWidgets('▍光标 ExcludeSemantics：语义树无「▍」噪音', (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['早', '上'],
          delay: const Duration(milliseconds: 10),
        ),
      );
      await sendViaUi(tester, 'hi');
      await tester.pump(const Duration(milliseconds: 11));

      // streaming 占位气泡含 ▍ 光标。
      expect(find.text('▍'), findsOneWidget);

      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('▍'), findsNothing,
          reason: '▍ 光标被 ExcludeSemantics 排除，不产生朗读噪音');
      expect(
        find.descendant(
          of: find.byType(ExcludeSemantics),
          matching: find.text('▍'),
        ),
        findsOneWidget,
        reason: '▍ 光标被 ExcludeSemantics 包裹',
      );
      handle.dispose();

      // 让流式跑完（drain FakeAsync timers，防 dispose 时 Timer pending）。
      await pumpUntil(
        tester,
        () => find.byType(MarkdownBody).evaluate().isNotEmpty,
        why: '流式完成后光标消失',
      );
      expect(find.text('▍'), findsNothing);
      await env.close();
    });
  });

  group('动效（M6-07 验收 4：发送↔停止图标过渡 140ms）', () {
    testWidgets('按钮区 AnimatedSwitcher 时长消费 ConverDurations.fast', (tester) async {
      final env = await ChatTestEnv.create();
      await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 200),
        ),
      );

      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, const Duration(milliseconds: 140),
          reason: '按钮图标过渡 140ms（消费 ConverDurations.fast，非硬编码）');
      expect(switcher.transitionBuilder, isNotNull,
          reason: '过渡为 Fade（两态图标淡入淡出）');
      await env.close();
    });

    testWidgets('进入生成 → 停止按钮 Key 保留；完成态复位发送按钮 Key 保留', (tester) async {
      final env = await ChatTestEnv.create();
      final c = await openConversation(
        tester,
        env,
        TickingFakeLLMProvider(
          tokens: const ['早', '上', '好', '啊', '这', '条', '长'],
          delay: const Duration(milliseconds: 200),
        ),
      );

      await sendViaUi(tester, 'hi');
      // 过渡完成（160ms）后：停止按钮存在且 Key 保留。
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.byKey(const Key('stop-button')), findsOneWidget,
          reason: '生成中 stop-button Key 保留（验收 4）');
      expect(find.byKey(const Key('send-button')), findsNothing);

      // 完成态复位：send-button Key 恢复（等流完成信号）。
      await pumpUntil(
        tester,
        () => !c.isStreaming,
        why: '流式完成（isStreaming 复位）',
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.byKey(const Key('send-button')), findsOneWidget,
          reason: '完成态 send-button Key 恢复（验收 4）');
      expect(c.isStreaming, isFalse);
      await env.close();
    });
  });
}