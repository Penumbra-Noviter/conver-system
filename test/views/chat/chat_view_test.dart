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

import 'package:conver_system_mobile/data/database/app_database.dart' show Message;
import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/colors.dart' show ConverColors;
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/chat/chat_controller.dart';
import 'package:conver_system_mobile/views/chat/chat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/chat_test_env.dart';
import '../../helpers/fake_llm_provider.dart';

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

  /// 循环 pump 直至 [condition] 为真（真实异步落库 / 回合收尾 / 流完成）。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String why = '',
  }) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: why);
  }

  /// 种子角色 + 会话并打开（无开场白 → 空消息列表）；返回控制器。
  Future<ChatController> openConversation(
    WidgetTester tester,
    ChatTestEnv env,
    LLMProvider provider, {
    String firstMes = '',
    int? characterId,
  }) async {
    final char = characterId == null
        ? await env.seedCharacter(firstMes: firstMes)
        : (await env.characterRepository.getCharacter(characterId))!;
    final conv = await env.seedConversation(char.id);
    final c = env.controllerOf(provider);
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
        TickingFakeLLMProvider(
          tokens: const ['你', '好', '！'],
          delay: const Duration(milliseconds: 10),
        ),
      );

      await sendViaUi(tester, '早上好');

      // 发送 ↔ 停止：生成中按钮变停止（tooltip 锚）。
      expect(find.byTooltip('停止'), findsOneWidget,
          reason: '发送↔停止两态：生成中为停止');
      expect(find.byTooltip('发送'), findsNothing);
      expect(find.text('早上好'), findsOneWidget, reason: 'user 消息即时渲染');

      // 第一 token：streaming 占位纯文本 + 单点光标，无 Markdown 渲染。
      await tester.pump(const Duration(milliseconds: 11));
      expect(find.byType(MarkdownBody), findsNothing,
          reason: 'streaming 期间两级降频：不跑 Markdown 渲染');
      expect(find.text('你'), findsOneWidget);
      expect(find.text('▍'), findsOneWidget, reason: '单点闪烁光标（非三点 typing）');

      // 第二 / 第三 token 追加。
      await tester.pump(const Duration(milliseconds: 11));
      expect(find.text('你好'), findsOneWidget, reason: '逐 token 追加');
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump(const Duration(milliseconds: 11));

      // 完成态：静态 Markdown 渲染完整回复，`▍` 光标消失，两态复位。
      await pumpUntil(
        tester,
        () => find.text('你好！', findRichText: true).evaluate().isNotEmpty,
        why: '完整回复完成且静态渲染',
      );
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
      expect(find.byTooltip('发送'), findsOneWidget, reason: '非阻塞：后续操作可用');

      // dismiss 后提示消失，可继续发送（非阻塞语义）。
      await tester.tap(find.byTooltip('关闭提示'));
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
}