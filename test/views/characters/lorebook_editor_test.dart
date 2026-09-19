/// LorebookEditor 行为契约（WL-04）：列表 + 编辑表单 CRUD + 校验/归一化 + 泛词告警。
///
/// 语义锚点（工单 09 验收 1~8）：列表渲染五项要素 / 关键词搜索过滤 / 新增编辑
/// 删除走 [LorebookRepository] CRUD（payload 与表字段逐字段一致，字段名映射
/// 单一来源 buildLorebookDraft）/ 表单校验阻止提交给内联错误 / 泛词告警契约锁
/// / chips 录入去重删除 / position·match_mode·group 回显一致 / 删除确认 +
/// 仓库抛错降级不崩溃。
///
/// 纯函数核对齐桌面 `frontend/js/components/lorebook-editor.js`（`__all__`：
/// isGenericKey / addKeyChip / removeKeyChip / validateLorebookEntry /
/// buildLorebookPayload / CONTENT_MAX_LENGTH / GENERIC_KEYS）；
/// parseKeyInput 为移动端增强（工单核心语义「keys 逗号分隔解析」）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/characters/lorebook_editor_controller.dart';
import 'package:conver_system_mobile/views/characters/lorebook_editor_view.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('纯函数核 · 对齐桌面 lorebook-editor.js', () {
    group('isGenericKey', () {
      test('单字符 → 泛词告警', () {
        expect(isGenericKey('猫'), isTrue, reason: '单字符过泛');
        expect(isGenericKey('a'), isTrue);
      });

      test('高频泛词（你/我/他/逗号/句号/空格/空串）→ 告警', () {
        for (final key in const ['你', '我', '他', '的', '，', '。', ' ', '']) {
          expect(isGenericKey(key), isTrue, reason: '泛词 $key 应告警');
        }
      });

      test('多字符有信息量词 → 不告警，前后空白可容忍', () {
        expect(isGenericKey('Alpha'), isFalse);
        expect(isGenericKey('符文石'), isFalse);
        expect(isGenericKey(' 猫娘 '), isFalse, reason: 'trim 后多字符');
        expect(isGenericKey('  '), isTrue, reason: 'trim 后空串单字符归约');
      });
    });

    group('addKeyChip / removeKeyChip（录入/去重/删除）', () {
      test('空输入返回原列表；trim 后空同理', () {
        expect(addKeyChip(const [], ''), isEmpty);
        expect(addKeyChip(const ['a'], '  '), ['a']);
      });

      test('录入 trim + 追加；重复返回原列表', () {
        expect(addKeyChip(const [], ' 猫 '), ['猫']);
        expect(addKeyChip(const ['猫', '狗'], ' 鸟 '), ['猫', '狗', '鸟']);
        expect(addKeyChip(const ['猫'], ' 猫 '), ['猫'], reason: '去重保序');
      });

      test('removeKeyChip 移除等价键（桌面 filter 语义）；未命中返回原列表', () {
        expect(removeKeyChip(const ['猫', '狗'], '猫'), ['狗']);
        expect(removeKeyChip(const ['猫'], '鸟'), ['猫']);
        expect(removeKeyChip(const ['猫', '猫'], '猫'), isEmpty,
            reason: '对齐桌面 filter：移除全部等价键；chips 不变量下无重复');
      });
    });

    group('parseKeyInput（工单核心语义：逗号分隔解析）', () {
      test('逗号分隔 → trim 去空去重保序', () {
        expect(parseKeyInput('猫, 狗, 鸟'), ['猫', '狗', '鸟']);
        expect(parseKeyInput('猫,,狗,'), ['猫', '狗'], reason: '空段忽略');
        expect(parseKeyInput(' 猫 ,猫 '), ['猫'], reason: 'trim + 去重');
      });

      test('无逗号 → 单元素；纯空白/空输入 → 空列表', () {
        expect(parseKeyInput('猫'), ['猫']);
        expect(parseKeyInput(''), isEmpty);
        expect(parseKeyInput(' , , '), isEmpty);
      });
    });

    group('validateLorebookEntry（阻止提交 + 内联错误）', () {
      Map<String, String> validate({
        String content = '',
        List<String> keys = const [],
        bool constant = false,
        String order = '100',
        String probability = '100',
        String groupWeight = '100',
        String depth = '20',
      }) =>
          validateLorebookEntry(
            content: content,
            keys: keys,
            constant: constant,
            order: order,
            probability: probability,
            groupWeight: groupWeight,
            depth: depth,
          );

      test('合法输入 → 空错误', () {
        expect(validate(content: '注入内容', keys: const ['猫']), isEmpty);
        expect(
          validate(
            content: 'x',
            keys: const ['猫'],
            constant: true,
            order: '0',
            probability: '1',
            groupWeight: '100',
            depth: '0',
          ),
          isEmpty,
          reason: '边界值合法',
        );
      });

      test('内容超上限（>20000）→ content 内联错误', () {
        final errors = validate(
          content: '长' * 20001,
          keys: const ['猫'],
        );
        expect(errors.keys, contains('content'));
        expect(errors['content'], contains('20000'));
      });

      test('关键词为空且非常驻 → keys 错误', () {
        final errors = validate(content: '内容', keys: const []);
        expect(errors.keys, contains('keys'));
        expect(errors['keys'], contains('常驻'));
      });

      test('关键词为空但常驻 → 通过', () {
        expect(validate(content: '常驻内容', keys: const [], constant: true),
            isEmpty);
      });

      test('数值空输入不予静默落 0（Falsify 修复锁）', () {
        for (final field in const ['order', 'probability', 'groupWeight', 'depth']) {
          final errors = validate(
            content: 'x',
            keys: const ['猫'],
            order: field == 'order' ? '' : '100',
            probability: field == 'probability' ? '' : '100',
            groupWeight: field == 'groupWeight' ? '' : '100',
            depth: field == 'depth' ? '' : '20',
          );
          expect(errors.keys, contains(field), reason: '$field 空输入必须报错');
        }
      });

      test('数值越界 → 对应字段错误含边界文案', () {
        expect(
          validate(
            content: 'x',
            keys: const ['猫'],
            order: '10000',
            probability: '0',
            groupWeight: '101',
            depth: '21',
          ),
          {
            'probability': contains('1-100'),
            'order': contains('0-9999'),
            'groupWeight': contains('1-100'),
            'depth': contains('0-20'),
          },
        );
      });

      test('非数字输入 → 报错；浮点串 -> 拒绝（int 语义）', () {
        expect(
          validate(content: 'x', keys: const ['猫'], order: 'abc').keys,
          contains('order'),
        );
        expect(
          validate(content: 'x', keys: const ['猫'], depth: '2.5').keys,
          contains('depth'),
        );
      });
    });

    group('buildLorebookDraft（payload 字段映射单一来源）', () {
      test('字符串/列表表单值 → 类型化 draft，逐字段对应 WL-01 表', () {
        final draft = buildLorebookDraft(
          title: '  皇家图书馆  ',
          keys: const ['猫', '图书馆'],
          content: '馆藏与守卫',
          constant: false,
          order: '5',
          probability: '80',
          groupName: ' 禁书区 ',
          groupWeight: '70',
          matchMode: 'and',
          position: 'before_char',
          depth: '3',
          enabled: false,
        );
        expect(draft.title, '皇家图书馆', reason: 'title trim');
        expect(draft.keys, ['猫', '图书馆']);
        expect(draft.content, '馆藏与守卫');
        expect(draft.constant, isFalse);
        expect(draft.order, 5);
        expect(draft.probability, 80);
        expect(draft.groupName, '禁书区');
        expect(draft.groupWeight, 70);
        expect(draft.matchMode, 'and');
        expect(draft.position, 'before_char');
        expect(draft.depth, 3);
        expect(draft.enabled, isFalse);
        expect(draft.source, 'manual', reason: '手动编辑产出 source 固定 manual');
      });

      test('缺省默认值回填（新建表单空态）', () {
        final draft = buildLorebookDraft(
          title: '',
          keys: const [],
          content: '',
          constant: false,
          order: '100',
          probability: '100',
          groupName: '',
          groupWeight: '100',
          matchMode: 'or',
          position: 'world',
          depth: '20',
          enabled: true,
        );
        expect(draft.order, 100);
        expect(draft.probability, 100);
        expect(draft.groupWeight, 100);
        expect(draft.matchMode, 'or');
        expect(draft.position, 'world');
        expect(draft.depth, 20);
        expect(draft.enabled, isTrue);
      });
    });
  });

  group('LorebookEditorController · 真库行为（验收 1/2/6/7/8）', () {
    late AppDatabase db;
    late LorebookRepository repo;
    late int characterId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LorebookRepository(db);
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      characterId = character.id;
    });

    tearDown(() async {
      await db.close();
    });

    LorebookEditorController buildController() =>
        LorebookEditorController(
          lorebookRepository: repo,
          characterId: characterId,
        );

    Future<LorebookEntry> seedEntry({
      String title = '图书馆',
      List<String> keys = const ['猫', '书'],
      int order = 10,
      bool constant = false,
      bool enabled = true,
    }) {
      return repo.createEntry(
        characterId,
        LorebookEntryDraft(
          title: title,
          keys: keys,
          content: '内容',
          constant: constant,
          order: order,
          enabled: enabled,
        ),
      );
    }

    group('load', () {
      test('加载条目列表（(order,id) 升序）', () async {
        await seedEntry(title: 'B', order: 20);
        await seedEntry(title: 'A', order: 10);
        final controller = buildController();

        await controller.load();

        expect(controller.entries.map((e) => e.title), ['A', 'B']);
        expect(controller.loading, isFalse);
      });

      test('失败保留既有列表并置 notice（验收 8 不崩溃）', () async {
        final controller = buildController();
        await controller.load();
        expect(controller.entries, isEmpty);

        await db.close();
        await controller.load();

        expect(controller.notice, contains('加载世界书失败'));
        expect(controller.entries, isEmpty);
      });
    });

    group('搜索过滤（验收 1：关键词搜索过滤结果正确）', () {
      test('标题/关键词子串匹配，大小写不敏感；空查询全量', () async {
        await seedEntry(title: '皇家图书馆', keys: const ['猫']);
        await seedEntry(title: '墓地', keys: const ['亡灵', 'Night']);
        final controller = buildController();
        await controller.load();

        controller.setSearchQuery('图书');
        expect(controller.filteredEntries.map((e) => e.title), ['皇家图书馆']);

        controller.setSearchQuery('night');
        expect(controller.filteredEntries.map((e) => e.title), ['墓地']);

        controller.setSearchQuery('不存在');
        expect(controller.filteredEntries, isEmpty);

        controller.setSearchQuery('  ');
        expect(controller.filteredEntries.length, 2, reason: '纯空白回退全量');
      });
    });

    group('CRUD（验收 2：走 LorebookRepository，payload 逐字段）', () {
      test('createEntry 落库 + snackMessage + 列表刷新', () async {
        final controller = buildController();
        await controller.load();

        await controller.createEntry(
          buildLorebookDraft(
            title: '档案馆',
            keys: const ['卷宗'],
            content: '历史记录',
            constant: false,
            order: '3',
            probability: '90',
            groupName: '',
            groupWeight: '100',
            matchMode: 'and',
            position: 'world',
            depth: '10',
            enabled: true,
          ),
        );

        expect(controller.snackMessage, '已新增条目');
        expect(controller.entries.single.title, '档案馆');
        final row = await repo.listEntries(characterId);
        expect(row.single.keys, ['卷宗']);
        expect(row.single.content, '历史记录');
        expect(row.single.order, 3);
        expect(row.single.probability, 90);
        expect(row.single.matchMode, 'and');
        expect(row.single.position, 'world');
        expect(row.single.depth, 10);
        expect(row.single.enabled, isTrue);
        expect(row.single.source, 'manual');
      });

      test('updateEntry 全字段写回（回显一致，验收 6）', () async {
        final seeded = await seedEntry(title: '旧标题');
        final controller = buildController();
        await controller.load();

        await controller.updateEntry(
          seeded.id,
          buildLorebookDraft(
            title: '新标题',
            keys: const ['新键'],
            content: '新内容',
            constant: true,
            order: '7',
            probability: '50',
            groupName: '禁书区',
            groupWeight: '60',
            matchMode: 'or',
            position: 'after_char',
            depth: '2',
            enabled: false,
          ),
        );

        expect(controller.snackMessage, '已保存修改');
        final row = (await repo.listEntries(characterId)).single;
        expect(row.title, '新标题');
        expect(row.keys, ['新键']);
        expect(row.constant, isTrue);
        expect(row.order, 7);
        expect(row.probability, 50);
        expect(row.groupName, '禁书区');
        expect(row.groupWeight, 60);
        expect(row.position, 'after_char');
        expect(row.depth, 2);
        expect(row.enabled, isFalse);
      });

      test('deleteEntry 移除 + snackMessage', () async {
        final seeded = await seedEntry();
        final controller = buildController();
        await controller.load();

        await controller.deleteEntry(seeded.id);

        expect(controller.snackMessage, '已删除条目');
        expect(controller.entries, isEmpty);
        expect(await repo.listEntries(characterId), isEmpty);
      });

      test('toggleEnabled 部分更新开关（桌面 toggle 语义）', () async {
        await seedEntry(enabled: true);
        final controller = buildController();
        await controller.load();

        await controller.toggleEnabled(controller.entries.single);

        expect((await repo.listEntries(characterId)).single.enabled, isFalse);
        expect(controller.entries.single.enabled, isFalse);
      });

      test('仓库抛错 → notice 降级，不抛到调用方（验收 7）', () async {
        final seeded = await seedEntry();
        final controller = buildController();
        await controller.load();

        await db.close();

        await controller.updateEntry(
          seeded.id,
          buildLorebookDraft(
            title: 'x',
            keys: const ['k'],
            content: 'c',
            constant: false,
            order: '1',
            probability: '100',
            groupName: '',
            groupWeight: '100',
            matchMode: 'or',
            position: 'world',
            depth: '20',
            enabled: true,
          ),
        );
        expect(controller.notice, contains('保存失败'));

        controller.dismissNotice();
        expect(controller.notice, isNull);

        await controller.deleteEntry(seeded.id);
        expect(controller.notice, contains('删除失败'));
      });
    });

    group('snack 消费', () {
      test('consumeSnackMessage 置 null（view 弹出后调用）', () async {
        final controller = buildController();
        await controller.load();
        await controller.createEntry(
          buildLorebookDraft(
            title: 't',
            keys: const ['k'],
            content: 'c',
            constant: false,
            order: '1',
            probability: '100',
            groupName: '',
            groupWeight: '100',
            matchMode: 'or',
            position: 'world',
            depth: '20',
            enabled: true,
          ),
        );
        expect(controller.snackMessage, isNotNull);
        controller.consumeSnackMessage();
        expect(controller.snackMessage, isNull);
      });
    });
  });

  group('LorebookEditorView · widget 行为（验收 1~8 + F-113 窄屏）', () {
    late AppDatabase db;
    late LorebookRepository repo;
    late int characterId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = LorebookRepository(db);
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(
              name: '艾莉亚',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      characterId = character.id;
    });

    tearDown(() async {
      await db.close();
    });

    LorebookEditorController buildController() =>
        LorebookEditorController(
          lorebookRepository: repo,
          characterId: characterId,
        );

    Future<LorebookEntry> seedEntry({
      String title = '图书馆',
      List<String> keys = const ['猫', '书'],
      int order = 10,
      bool constant = false,
      bool enabled = true,
      String source = 'manual',
      String position = 'world',
      String matchMode = 'or',
    }) {
      return repo.createEntry(
        characterId,
        LorebookEntryDraft(
          title: title,
          keys: keys,
          content: '内容',
          constant: constant,
          order: order,
          enabled: enabled,
          source: source,
          position: position,
          matchMode: matchMode,
        ),
      );
    }

    Future<void> pumpView(
      WidgetTester tester,
      LorebookEditorController controller,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ConverTheme.dark(),
          home: LorebookEditorView(controller: controller),
        ),
      );
      for (var i = 0; i < 100 && controller.loading; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      await tester.pump();
    }

    group('列表渲染（验收 1）', () {
      testWidgets('标题/前3关键词+计数/常驻标记/order/开关状态/记忆来源', (tester) async {
        await seedEntry(
          title: '皇家图书馆',
          keys: const ['猫', '书', '档案馆', '禁书'],
          order: 5,
          constant: true,
          enabled: false,
          source: 'auto',
        );
        await seedEntry(title: '墓地', keys: const ['亡灵'], order: 20);
        final controller = buildController();

        await pumpView(tester, controller);

        expect(find.text('皇家图书馆'), findsOneWidget);
        expect(find.text('墓地'), findsOneWidget);
        // 前 3 关键词 + 计数：keys.length(4) - 3 = +1。
        expect(find.textContaining('猫、书、档案馆'), findsOneWidget);
        expect(find.text('+1'), findsOneWidget, reason: '超出 3 个关键词计数');
        expect(find.text('亡灵'), findsOneWidget);
        // 常驻标记 + 记忆来源 badge（source=auto）。
        expect(find.text('常驻'), findsOneWidget);
        expect(find.text('记忆'), findsOneWidget, reason: 'auto 来源 badge');
        // order 徽标。
        expect(find.text('5'), findsOneWidget);
        expect(find.text('20'), findsOneWidget);
        // enabled 开关状态：第一条禁用、第二条启用。
        final switches = tester.widgetList<Switch>(find.byType(Switch));
        expect(switches.length, 2);
        expect(switches.first.value, isFalse);
        expect(switches.last.value, isTrue);
      });

      testWidgets('标题为空 → 未命名占位', (tester) async {
        await seedEntry(title: '');
        final controller = buildController();

        await pumpView(tester, controller);

        expect(find.text('（未命名）'), findsOneWidget);
      });

      testWidgets('空态：无条目 → EmptyState 文案；有条目搜索无匹配 → 无匹配', (tester) async {
        final controller = buildController();
        await pumpView(tester, controller);
        expect(find.text('暂无世界书条目'), findsOneWidget);

        await seedEntry(title: '皇家图书馆');
        await controller.load();
        await tester.pump();
        expect(find.text('皇家图书馆'), findsOneWidget);

        await tester.enterText(find.byKey(const Key('lorebook-search')), '不存在');
        await tester.pump();
        expect(find.text('无匹配条目'), findsOneWidget);
        await tester.enterText(find.byKey(const Key('lorebook-search')), '');
        await tester.pump();
        expect(find.text('皇家图书馆'), findsOneWidget, reason: '清空搜索恢复全量');
      });
    });

    group('搜索过滤 + 开关 + 删除（验收 1/2/7）', () {
      testWidgets('关键词搜索过滤结果正确（标题/关键词子串）', (tester) async {
        await seedEntry(title: '皇家图书馆', keys: const ['猫']);
        await seedEntry(title: '墓地', keys: const ['亡灵', 'Night']);
        final controller = buildController();
        await pumpView(tester, controller);

        await tester.enterText(find.byKey(const Key('lorebook-search')), '图书馆');
        await tester.pump();
        expect(find.text('皇家图书馆'), findsOneWidget);
        expect(find.text('墓地'), findsNothing);

        await tester.enterText(find.byKey(const Key('lorebook-search')), 'night');
        await tester.pump();
        expect(find.text('墓地'), findsOneWidget);
        expect(find.text('皇家图书馆'), findsNothing);
      });

      testWidgets('行内开关切换落库（部分更新 enabled）', (tester) async {
        await seedEntry(enabled: true);
        final controller = buildController();
        await pumpView(tester, controller);

        await tester.tap(find.byType(Switch));
        for (var i = 0; i < 100 && controller.loading; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump();

        expect((await repo.listEntries(characterId)).single.enabled, isFalse);
      });

      testWidgets('删除确认：确认删除 / 取消保留（验收 7）', (tester) async {
        final seeded = await seedEntry();
        final controller = buildController();
        await pumpView(tester, controller);

        // 取消路径。
        await tester.tap(find.byTooltip('删除'));
        await tester.pumpAndSettle();
        expect(find.text('删除这条世界书条目？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await repo.listEntries(characterId), hasLength(1));

        // 确认路径。
        await tester.tap(find.byTooltip('删除'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除'));
        for (var i = 0; i < 100 && controller.loading; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump();
        expect(await repo.listEntries(characterId), isEmpty);
        expect(find.text('已删除条目'), findsOneWidget,
            reason: 'SnackBar 由 view listener 消费展示');
        expect(seeded.id, isPositive);
      });

      testWidgets('仓库抛错 → NoticeBanner 降级不崩溃（验收 8）', (tester) async {
        await seedEntry();
        final controller = buildController();
        await pumpView(tester, controller);

        await db.close();
        await tester.tap(find.byType(Switch));
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump();

        expect(find.textContaining('切换失败'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    group('编辑表单（验收 3/4/5/6）', () {
      /// 编辑表单字段多，拉高测试视口避免 ListView 懒加载下底部字段 offstage。
      void useTallViewport(WidgetTester tester) {
        tester.view.physicalSize = const Size(900, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
      }

      testWidgets('新增：填入字段保存 → 落库逐字段 + snack', (tester) async {
        useTallViewport(tester);
        final controller = buildController();
        await pumpView(tester, controller);

        await tester.tap(find.byTooltip('新增条目'));
        await tester.pumpAndSettle();
        expect(find.text('新增条目'), findsWidgets, reason: 'AppBar 标题');

        await tester.enterText(
            find.byKey(const Key('lorebook-title')), '档案馆');
        await tester.enterText(
            find.byKey(const Key('lorebook-keys-input')), '卷宗, 档案');
        await tester.tap(find.byKey(const Key('lorebook-keys-add')));
        await tester.pump();
        await tester.enterText(
            find.byKey(const Key('lorebook-content')), '历史记录');
        await tester.enterText(find.byKey(const Key('lorebook-order')), '3');
        await tester.enterText(
            find.byKey(const Key('lorebook-probability')), '90');
        await tester.enterText(
            find.byKey(const Key('lorebook-group-name')), '禁书区');
        await tester.enterText(
            find.byKey(const Key('lorebook-group-weight')), '60');
        await tester.enterText(find.byKey(const Key('lorebook-depth')), '10');
        // 下拉先展开菜单再选选项（未展开时选项不在树上）。
        await tester
            .tap(find.byKey(const Key('lorebook-match-mode')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('与（全部命中）').last);
        await tester.pumpAndSettle();
        await tester
            .ensureVisible(find.byKey(const Key('lorebook-position')));
        await tester.tap(find.byKey(const Key('lorebook-position')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('角色设定前').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('保存'));
        for (var i = 0; i < 100 && controller.loading; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        final row = (await repo.listEntries(characterId)).single;
        expect(row.title, '档案馆');
        expect(row.keys, ['卷宗', '档案']);
        expect(row.content, '历史记录');
        expect(row.order, 3);
        expect(row.probability, 90);
        expect(row.groupName, '禁书区');
        expect(row.groupWeight, 60);
        expect(row.matchMode, 'and');
        expect(row.position, 'before_char');
        expect(row.depth, 10);
        expect(row.enabled, isTrue);
        expect(find.text('档案馆'), findsOneWidget, reason: '保存后回到列表');
      });

      testWidgets('编辑回显：重开面板字段还原（验收 6）', (tester) async {
        useTallViewport(tester);
        await seedEntry(
          title: '旧标题',
          keys: const ['旧键'],
          order: 7,
          constant: true,
          position: 'after_char',
          matchMode: 'and',
          enabled: false,
        );
        final controller = buildController();
        await pumpView(tester, controller);

        await tester.tap(find.byTooltip('编辑'));
        await tester.pumpAndSettle();

        expect(find.text('编辑条目'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('lorebook-title')))
              .controller
              ?.text,
          '旧标题',
        );
        expect(find.text('旧键'), findsOneWidget, reason: 'chips 回显');
        expect(
          tester
              .widget<SwitchListTile>(
                  find.byKey(const Key('lorebook-constant')))
              .value,
          isTrue,
        );
        expect(
          tester
              .widget<SwitchListTile>(find.byKey(const Key('lorebook-enabled')))
              .value,
          isFalse,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('lorebook-order')))
              .controller
              ?.text,
          '7',
        );
        expect(find.text('场景设定后'), findsOneWidget, reason: 'position 回显');
      });

      testWidgets('校验：内容超限/关键词空/数值越界 → 内联错误阻止提交（验收 3）',
          (tester) async {
        useTallViewport(tester);
        final controller = buildController();
        await pumpView(tester, controller);
        await tester.tap(find.byTooltip('新增条目'));
        await tester.pumpAndSettle();

        // 关键词空 + 数值越界 + 内容超限同时触发。
        await tester.enterText(find.byKey(const Key('lorebook-content')),
            '长' * (contentMaxLength + 1));
        await tester.enterText(find.byKey(const Key('lorebook-order')), '10000');
        await tester.enterText(
            find.byKey(const Key('lorebook-probability')), '0');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();

        expect(find.textContaining('至少填写一个触发关键词'), findsOneWidget);
        expect(find.textContaining('内容过长'), findsOneWidget);
        expect(find.textContaining('排序需在 0-9999 之间'), findsOneWidget);
        expect(find.textContaining('命中概率需在 1-100 之间'), findsOneWidget);
        expect(await repo.listEntries(characterId), isEmpty,
            reason: '校验失败零落库');
      });

      testWidgets('泛词告警契约锁：单字符/高频词 chips → 告警文案（验收 4）',
          (tester) async {
        useTallViewport(tester);
        final controller = buildController();
        await pumpView(tester, controller);
        await tester.tap(find.byTooltip('新增条目'));
        await tester.pumpAndSettle();

        // 录入单字符 → 告警。
        await tester.enterText(
            find.byKey(const Key('lorebook-keys-input')), '猫');
        await tester.tap(find.byKey(const Key('lorebook-keys-add')));
        await tester.pump();
        expect(find.text('关键词过泛，会显著增加注入量'), findsOneWidget);

        // 补录多字符词 → 仍有泛词（告警保留）。
        await tester.enterText(
            find.byKey(const Key('lorebook-keys-input')), '图书馆');
        await tester.tap(find.byKey(const Key('lorebook-keys-add')));
        await tester.pump();
        expect(find.text('关键词过泛，会显著增加注入量'), findsOneWidget);

        // 删除泛词 chip → 告警消失。
        await tester.tap(find.byIcon(Icons.cancel).first);
        await tester.pump();
        expect(find.text('关键词过泛，会显著增加注入量'), findsNothing);
      });

      testWidgets('chips 录入/去重/删除交互（验收 5）', (tester) async {
        useTallViewport(tester);
        final controller = buildController();
        await pumpView(tester, controller);
        await tester.tap(find.byTooltip('新增条目'));
        await tester.pumpAndSettle();

        await tester.enterText(
            find.byKey(const Key('lorebook-keys-input')), '猫, 狗, 猫');
        await tester.tap(find.byKey(const Key('lorebook-keys-add')));
        await tester.pump();

        expect(find.text('猫'), findsOneWidget);
        expect(find.text('狗'), findsOneWidget);
        expect(
          find.text('猫'),
          findsOneWidget,
          reason: '逗号解析 + 去重：重复键只留一个',
        );

        await tester.tap(find.byIcon(Icons.cancel).last);
        await tester.pump();
        expect(find.text('狗'), findsNothing, reason: '删除 chip 移除该键');
        expect(find.text('猫'), findsOneWidget);
      });

      testWidgets('取消保存：零副作用返回列表', (tester) async {
        useTallViewport(tester);
        final controller = buildController();
        await pumpView(tester, controller);
        await tester.tap(find.byTooltip('新增条目'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('lorebook-title')), '未保存');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        expect(await repo.listEntries(characterId), isEmpty);
        expect(find.text('暂无世界书条目'), findsOneWidget);
      });
    });

    group('窄屏契约（F-113 先例：360dp 无溢出）', () {
      testWidgets('列表 + 编辑表单在 360×800 下无 RenderFlex overflow', (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await seedEntry(
          title: '超长标题'.padRight(20, '长'),
          keys: List.generate(8, (i) => '键$i'),
          constant: true,
        );
        final controller = buildController();
        await pumpView(tester, controller);
        expect(tester.takeException(), isNull, reason: '列表 360dp 无溢出');

        await tester.tap(find.byTooltip('编辑'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '编辑页 360dp 无溢出');
      });
    });
  });
}