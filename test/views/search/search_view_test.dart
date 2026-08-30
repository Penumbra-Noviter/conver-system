/// SearchView widget 行为契约（M3-04b：防抖五态 + 结果列表 + 高亮第一处
/// + onSelectResult 钩子）。
///
/// 验收语义（工单 04b 验收 1/2/3/5/6/7）：
/// - 防抖 300ms：500ms 内连续输入只发一次穷尽查询（timer 复位断言）；Enter
///   立即查询（不等防抖）；Escape 清空输入 + 失焦 + 回空态；清空按钮同 Escape；
/// - 五态文案逐字（空 / <2 字符 / 搜索中… / 未找到 / 失败）；有结果时
///   「共找到 N 条匹配消息」+ 结果列表（role 标签 / 对话标题 / 时间 / 预览）；
/// - 结果点击 → `onSelectResult(conversationId, messageId)` 参数正确；点击
///   空白区不触发；
/// - 查询失败后再次输入可恢复搜索（loading 态不残留）；组件卸载时防抖 timer
///   取消（无泄漏）。
///
/// 测试 seam（公共接口边界）：[SearchView] 公开构造（注入 [SearchService] 与
/// [onSelectResult]）+ 内存 drift 真实契约（结果渲染组）。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/services/search_service.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/search/search_view.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SettingsReader] 的内存假实现（与 search_service_test 同形）。
class FakeSettingsReader implements SettingsReader {
  const FakeSettingsReader([this.values = const {}]);

  final Map<String, String> values;

  @override
  Future<String> get defaultProvider async => values['default_provider'] ?? '';

  @override
  Future<String> get defaultModel async => values['default_model'] ?? '';

  @override
  Future<String> get userName async => values['user_name'] ?? '';
}

/// 可控假服务：记录调用次数 / 查询词，可设返回结果 / 抛错 / 挂起 Completer
/// （用于观测「搜索中…」中间态与失败恢复）。
class _FakeSearchService implements SearchService {
  int callCount = 0;
  final List<String> queries = [];
  List<SearchResult> results = const [];
  Object? error;
  Completer<List<SearchResult>>? pending;

  @override
  Future<List<SearchResult>> search(String query) {
    callCount++;
    queries.add(query);
    final pendingSearch = pending;
    if (pendingSearch != null) {
      pending = null; // 一次性消费：下次查询走正常路径。
      return pendingSearch.future;
    }
    if (error != null) {
      return Future.error(error!);
    }
    return Future.value(results);
  }
}

void main() {
  /// 装配 SearchView（注入可控服务与钩子）。
  Future<void> pumpView(
    WidgetTester tester, {
    required SearchService service,
    void Function(int conversationId, int messageId)? onSelectResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: SearchView(
            service: service,
            onSelectResult: onSelectResult,
          ),
        ),
      ),
    );
  }

  group('防抖 · 300ms 复位 + Enter 立即 + Escape/清空（验收 1）', () {
    testWidgets('500ms 内连续输入只发一次穷尽查询（timer 复位）', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), '星空夜');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(service.callCount, 1, reason: '防抖复位：500ms 内连发只触发一次');
      expect(service.queries.single, '星空夜', reason: '以最后输入值为准');
    });

    testWidgets('Enter 立即查询（不等防抖），且防抖不再补发', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 100)); // 未到 300ms
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(service.callCount, 1, reason: 'Enter 立即查询一次');
      expect(service.queries.single, '星空');

      await tester.pump(const Duration(milliseconds: 400)); // 防抖窗口已过
      expect(service.callCount, 1, reason: 'Enter 后不再补发防抖查询');
    });

    testWidgets('Escape 清空输入 + 失焦 + 回空态', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty, reason: 'Escape 清空输入');
      expect(find.text('输入关键词搜索所有对话中的消息'), findsOneWidget,
          reason: '回空态');
      expect(service.callCount, 0, reason: 'Escape 不触发查询');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isFalse, reason: 'Escape 失焦');
    });

    testWidgets('清空按钮同 Escape：清空 + 回空态', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty);
      expect(find.text('输入关键词搜索所有对话中的消息'), findsOneWidget);
      expect(service.callCount, 0);
    });
  });

  group('五态逐字（验收 2）', () {
    testWidgets('空输入 →「输入关键词搜索所有对话中的消息」', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      expect(find.text('输入关键词搜索所有对话中的消息'), findsOneWidget);
    });

    testWidgets('空白输入 Enter → 空串短路回空态（不触发查询）', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      // 输入纯空白（trim 后空串）后 Enter：走 performSearch 空串短路分支。
      await tester.enterText(find.byType(TextField), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(find.text('输入关键词搜索所有对话中的消息'), findsOneWidget);
      expect(service.callCount, 0, reason: '空串短路，不触仓储');
    });

    testWidgets('<2 字符 →「至少输入 2 个字符」（不触发查询）', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('至少输入 2 个字符'), findsOneWidget);
      expect(service.callCount, 0, reason: '<2 字符拦截，不触仓储');
    });

    testWidgets('查询中 →「搜索中…」', (tester) async {
      final completer = Completer<List<SearchResult>>();
      final service = _FakeSearchService()..pending = completer;
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('搜索中…'), findsOneWidget);

      completer.complete(const []);
      await tester.pump();
    });

    testWidgets('无命中 →「未找到匹配的消息」', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('未找到匹配的消息'), findsOneWidget);
    });

    testWidgets('异常 →「搜索失败: <原因>」（原因来自异常 message）', (tester) async {
      final service =
          _FakeSearchService()..error = Exception('模拟数据库故障');
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('搜索失败: 模拟数据库故障'), findsOneWidget);
    });

    testWidgets('预览无命中 → 纯文本回落（不高亮、不抛错）', (tester) async {
      final service = _FakeSearchService()
        ..results = [
          SearchResult(
            messageId: 7,
            conversationId: 3,
            conversationTitle: '夜话',
            characterId: 1,
            characterName: '艾莉亚',
            characterAvatar: null,
            role: 'assistant',
            content: '一段与查询无关的旧内容',
            createdAt: DateTime(2026, 8, 30, 12, 34),
          ),
        ];
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('共找到 1 条匹配消息'), findsOneWidget);
      expect(find.textContaining('无关的旧内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('system 消息 → role 标签显示角色名（验收 3）', (tester) async {
      final service = _FakeSearchService()
        ..results = [
          SearchResult(
            messageId: 8,
            conversationId: 3,
            conversationTitle: '夜话',
            characterId: 1,
            characterName: '艾莉亚',
            characterAvatar: null,
            role: 'system',
            content: '系统提示：星空观测开始',
            createdAt: DateTime(2026, 8, 30, 12, 34),
          ),
        ];
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('共找到 1 条匹配消息'), findsOneWidget);
      expect(find.text('艾莉亚'), findsOneWidget, reason: 'system → 角色名');
      expect(find.text('你'), findsNothing, reason: '非 user 不显示「你」');
    });

    testWidgets('失败后再次输入可恢复搜索（loading 态不残留）', (tester) async {
      final service =
          _FakeSearchService()..error = Exception('模拟数据库故障');
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('搜索失败: 模拟数据库故障'), findsOneWidget);

      // 恢复：清掉错误后再次输入。
      service
        ..error = null
        ..results = const [];
      await tester.enterText(find.byType(TextField), '银河');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('搜索失败: 模拟数据库故障'), findsNothing);
      expect(find.text('未找到匹配的消息'), findsOneWidget,
          reason: '恢复搜索，loading 态不残留');
    });
  });

  group('卸载时防抖 timer 取消（验收 6）', () {
    testWidgets('输入后立即卸载：防抖 timer 取消，无泄漏异常', (tester) async {
      final service = _FakeSearchService();
      await pumpView(tester, service: service);

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox()); // 卸载组件
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull, reason: '卸载后防抖 timer 已取消');
      expect(service.callCount, 0);
    });
  });

  group('并发竞态 · 请求序号守卫（Falsify 自审）', () {
    testWidgets('较慢的旧查询完成后不覆盖新查询的结果', (tester) async {
      final slow = Completer<List<SearchResult>>();
      final service = _FakeSearchService()..pending = slow;
      await pumpView(tester, service: service);

      // 第一次查询（慢）：防抖触发后挂起在 Completer 上。
      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      // 第二次查询（快）：立即返回新结果。
      service.results = [
        SearchResult(
          messageId: 20,
          conversationId: 3,
          conversationTitle: '夜话',
          characterId: 1,
          characterName: '艾莉亚',
          characterAvatar: null,
          role: 'user',
          content: '银河璀璨的新结果',
          createdAt: DateTime(2026, 8, 30, 12, 34),
        ),
      ];
      await tester.enterText(find.byType(TextField), '银河');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('共找到 1 条匹配消息'), findsOneWidget);
      expect(find.textContaining('新结果'), findsOneWidget);

      // 旧查询此刻才完成：内容不同，必须被请求序号守卫丢弃。
      slow.complete([
        SearchResult(
          messageId: 10,
          conversationId: 3,
          conversationTitle: '夜话',
          characterId: 1,
          characterName: '艾莉亚',
          characterAvatar: null,
          role: 'user',
          content: '星空旧结果',
          createdAt: DateTime(2026, 8, 30, 12, 34),
        ),
      ]);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('新结果'), findsOneWidget,
          reason: '新查询结果保留');
      expect(find.textContaining('星空旧结果'), findsNothing,
          reason: '过期旧查询结果被丢弃');
    });
  });

  group('结果渲染 · 真实 SearchService + 内存库契约（验收 3/5/7）', () {
    testWidgets('渲染头部 + 结果项（role 标签/标题/时间/预览高亮第一处）',
        (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeNow = DateTime(2026, 8, 30, 12, 34);
      final messageRepo = MessageRepository(db, now: () => fakeNow);
      final convRepo = ConversationRepository(db, const FakeSettingsReader());
      final char = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              firstMes: const Value(''),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '夜话',
      );
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '今晚的星空很美',
      );
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '是的，星空如约而至，星空依旧美好',
      );
      final service = SearchService(messageRepo);

      (int, int)? selected;
      await pumpView(
        tester,
        service: service,
        onSelectResult: (c, m) => selected = (c, m),
      );

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('共找到 2 条匹配消息'), findsOneWidget);
      expect(find.text('你'), findsOneWidget, reason: 'user → 你');
      expect(find.text('艾莉亚'), findsOneWidget, reason: 'assistant → 角色名');
      expect(find.text('夜话'), findsNWidgets(2), reason: '两条结果同一对话标题');

      // 时间渲染（固定 now → 2026-08-30 12:34）。
      expect(find.text('2026-08-30 12:34'), findsNWidgets(2));

      // 预览正文含命中词，且每条结果仅高亮第一处（RichText span 中
      // 恰一段带高亮背景；assistant 消息含两处「星空」仍只高亮首处）。
      final richTexts =
          tester.widgetList<RichText>(find.byType(RichText)).toList();
      expect(richTexts, isNotEmpty);
      for (final rt in richTexts) {
        final segments = <String>[];
        _collectHighlighted(rt.text, segments);
        expect(
          segments.length,
          lessThanOrEqualTo(1),
          reason: '每条预览仅高亮第一处（assistant 双命中仍只一段）',
        );
      }
      final allSegments = <String>[];
      for (final rt in richTexts) {
        _collectHighlighted(rt.text, allSegments);
      }
      expect(allSegments, hasLength(2), reason: '两条结果各有一处高亮');

      await tester.tap(find.text('夜话').first);
      await tester.pump();
      expect(selected, isNotNull, reason: '点击结果 → 钩子被调用');
      expect(selected!.$1, conv.id, reason: '钩子收到 conversationId');
      expect(selected!.$2, isNotNull, reason: '钩子收到 messageId');

      await db.close();
    });

    testWidgets('点击空白区（结果头）不触发钩子', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final fakeNow = DateTime(2026, 8, 30, 12, 34);
      final messageRepo = MessageRepository(db, now: () => fakeNow);
      final convRepo = ConversationRepository(db, const FakeSettingsReader());
      final char = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              firstMes: const Value(''),
              createdAt: fakeNow,
              updatedAt: fakeNow,
            ),
          );
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '夜话',
      );
      await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.user,
        content: '星空物语',
      );
      final service = SearchService(messageRepo);

      var triggered = 0;
      await pumpView(
        tester,
        service: service,
        onSelectResult: (_, _) => triggered++,
      );

      await tester.enterText(find.byType(TextField), '星空');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      await tester.tap(find.text('共找到 1 条匹配消息'));
      await tester.pump();

      expect(triggered, 0, reason: '点击结果头（空白区）不触发钩子');

      await db.close();
    });
  });
}

/// 递归收集 [span] 树中带高亮背景色的文本段（用于「高亮仅第一处」断言）。
void _collectHighlighted(InlineSpan span, List<String> out) {
  if (span is TextSpan) {
    final style = span.style;
    if (style != null && style.backgroundColor != null) {
      out.add(span.text ?? '');
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      _collectHighlighted(child, out);
    }
  }
}
