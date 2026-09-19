/// LorebookRepository 契约锁（WL-01）— 桌面 `test_lorebook_store.py` 逐字移植。
///
/// 锁定语义（spec §4.4 + chat-polish-spec 验收 2~6，二选一处取「裁剪」）：
/// - listEntries 按 (order, id) 升序（确定性排序契约）；keys 落库/读回 JSON 数组
/// - createEntry 角色缺失抛 CharacterNotFoundError（桌面 404 语义，防 FK 违例）
/// - updateEntry 部分更新仅写显式字段 + updatedAt 前移；显式 null 视为未提供
///   （NOT NULL 防炸 / 值不中毒，Falsify 修复锁）
/// - deleteEntry 返回受影响（bool；不存在 false 零副作用）
/// - replaceEntries 幂等（连续两次结果一致，先删后插语义；空列表 = 清空）
/// - character_id 级联删除（FK CASCADE 实测，表内无残留行）
/// - parseCharacterBook：ST character_book 结构 → 字段一一对应；畸形降级不抛；
///   数值越界裁剪（解析层裁剪、API 层拒绝的分界与桌面一致）
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/lorebook_repository.dart';
import 'package:conver_system_mobile/services/llm/errors.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late LorebookRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = LorebookRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedCharacter({String name = '测试角色'}) async {
    final now = DateTime.now();
    final character = await db
        .into(db.characters)
        .insertReturning(
          CharactersCompanion.insert(
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return character.id;
  }

  group('一、listEntries 排序与 keys JSON 往返', () {
    test('order 升序、同 order 按 id 升序（桌面 test_create_and_list_sorted）',
        () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: 'B', order: 200),
      );
      final a = await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: 'A', order: 100),
      );
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: 'C', order: 100),
      );

      final entries = await repo.listEntries(characterId);
      expect([for (final e in entries) e.title], ['A', 'C', 'B']);
      expect(entries[0].id, a.id);
      expect(entries[1].id, greaterThan(a.id));
      expect(entries[2].title, 'B');
      expect(entries[2].keys, isEmpty, reason: 'keys 落库/读回为 JSON 数组');
    });

    test('不同角色条目互不串扰', () async {
      final c1 = await seedCharacter(name: '甲');
      final c2 = await seedCharacter(name: '乙');
      await repo.createEntry(c1, const LorebookEntryDraft(title: '只属甲'));
      expect(await repo.listEntries(c1), hasLength(1));
      expect(await repo.listEntries(c2), isEmpty);
    });
  });

  group('二、createEntry', () {
    test('全字段落库读回一致（keys JSON 数组往返）', () async {
      final characterId = await seedCharacter();
      final created = await repo.createEntry(
        characterId,
        const LorebookEntryDraft(
          title: '酒馆',
          keys: ['酒馆', 'tavern'],
          content: '酒馆的老板是莉莉。',
          constant: true,
          order: 55,
          probability: 80,
          groupName: '地点',
          groupWeight: 30,
          matchMode: 'and',
          position: 'before_char',
          depth: 4,
          source: 'manual',
          enabled: false,
        ),
      );
      expect(created.title, '酒馆');
      expect(created.keys, ['酒馆', 'tavern']);
      expect(created.content, '酒馆的老板是莉莉。');
      expect(created.constant, isTrue);
      expect(created.order, 55);
      expect(created.probability, 80);
      expect(created.groupName, '地点');
      expect(created.groupWeight, 30);
      expect(created.matchMode, 'and');
      expect(created.position, 'before_char');
      expect(created.depth, 4);
      expect(created.source, 'manual');
      expect(created.enabled, isFalse);
    });

    test('角色不存在 → CharacterNotFoundError（防 FK 违例，桌面对齐）', () async {
      await expectLater(
        repo.createEntry(99999, const LorebookEntryDraft()),
        throwsA(isA<CharacterNotFoundError>()),
      );
    });

    test('默认字段（桌面 LorebookEntryCreate() 默认形态）', () async {
      final characterId = await seedCharacter();
      final created = await repo.createEntry(
        characterId,
        const LorebookEntryDraft(),
      );
      expect(created.title, '');
      expect(created.keys, isEmpty);
      expect(created.constant, isFalse);
      expect(created.order, 100);
      expect(created.probability, 100);
      expect(created.groupName, '');
      expect(created.groupWeight, 100);
      expect(created.matchMode, 'or');
      expect(created.position, 'world');
      expect(created.depth, 20);
      expect(created.source, 'manual');
      expect(created.enabled, isTrue);
    });
  });

  group('三、updateEntry 部分更新', () {
    test('仅提交显式字段，其余原样保留 + updatedAt 前移', () async {
      final characterId = await seedCharacter();
      // F-3 秒精度：drift 落库截断到秒，跨秒注入时钟使前移可辨。
      var now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final tickRepo = LorebookRepository(db, now: () => now);
      final entry = await tickRepo.createEntry(
        characterId,
        const LorebookEntryDraft(title: '旧', content: 'c', order: 5),
      );
      now = DateTime.fromMillisecondsSinceEpoch(1700000001000);
      final updated = await tickRepo.updateEntry(
        entry.id,
        LorebookEntriesCompanion(
          content: const Value('新内容'),
          enabled: const Value(false),
        ),
      );
      expect(updated!.content, '新内容');
      expect(updated.enabled, isFalse);
      expect(updated.title, '旧');
      expect(updated.order, 5);
      expect(
        updated.updatedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000001000),
        reason: 'updatedAt 随更新前移（F-3 秒精度，跨秒可辨）',
      );
    });

    test('条目不存在 → null', () async {
      expect(
        await repo.updateEntry(
          99999,
          LorebookEntriesCompanion(title: const Value('x')),
        ),
        isNull,
      );
    });

    test('空 companion（无显式字段）→ no-op 返回原行', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: 't'),
      );
      final updated = await repo.updateEntry(entry.id, const LorebookEntriesCompanion());
      expect(updated!.title, 't');
    });
  });

  group('四、deleteEntry 返回受影响', () {
    test('删除后列表为空；重复删返回 false 零副作用', () async {
      final characterId = await seedCharacter();
      final entry = await repo.createEntry(
        characterId,
        const LorebookEntryDraft(),
      );
      expect(await repo.deleteEntry(entry.id), isTrue);
      expect(await repo.listEntries(characterId), isEmpty);
      expect(await repo.deleteEntry(entry.id), isFalse);
    });
  });

  group('五、replaceEntries 幂等', () {
    test('连续两次调用结果一致（先删后插语义）', () async {
      final characterId = await seedCharacter();
      const drafts = [
        LorebookEntryDraft(title: 'A', keys: ['x'], content: 'a'),
        LorebookEntryDraft(title: 'B', keys: ['y'], content: 'b'),
      ];
      final n1 = await repo.replaceEntries(characterId, drafts);
      final first = await repo.listEntries(characterId);
      final n2 = await repo.replaceEntries(characterId, drafts);
      final second = await repo.listEntries(characterId);

      expect(n1, 2);
      expect(n2, 2);
      // keys 经 StringListConverter 读回为 CastList——Dart List 无值相等，
      // record 比较不可行；逐元素用 matcher 深比较（内容相等即幂等）。
      expect(first.length, second.length);
      for (var i = 0; i < first.length; i++) {
        expect(first[i].title, second[i].title);
        expect(first[i].keys, second[i].keys);
        expect(first[i].content, second[i].content);
      }
      expect({for (final e in first) e.title}, {'A', 'B'});
    });

    test('首次调用清空既有条目（先删后插语义）', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: '旧条目'),
      );
      await repo.replaceEntries(
        characterId,
        const [LorebookEntryDraft(title: '新条目')],
      );
      final entries = await repo.listEntries(characterId);
      expect([for (final e in entries) e.title], ['新条目']);
    });

    test('空列表 = 清空该角色全部条目', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: '将被清'),
      );
      expect(await repo.replaceEntries(characterId, const []), 0);
      expect(await repo.listEntries(characterId), isEmpty);
    });

    test('角色不存在 → CharacterNotFoundError', () async {
      await expectLater(
        repo.replaceEntries(99999, const []),
        throwsA(isA<CharacterNotFoundError>()),
      );
    });
  });

  group('六、character_id 级联删除', () {
    test('删角色 → 世界书全清（FK CASCADE 实测，表内无残留）', () async {
      final characterId = await seedCharacter();
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: '条目1'),
      );
      await repo.createEntry(
        characterId,
        const LorebookEntryDraft(title: '条目2'),
      );
      expect(await repo.listEntries(characterId), hasLength(2));

      final affected = await (db.delete(
        db.characters,
      )..where((t) => t.id.equals(characterId))).go();
      expect(affected, 1);

      final count = await db
          .customSelect('SELECT COUNT(*) AS c FROM lorebook_entries')
          .getSingle();
      expect(count.data['c'], 0, reason: '表内无残留行');
    });
  });

  group('七、parseCharacterBook（ST 结构 → 条目草案，桌面逐字）', () {
    test('字段一一对应（桌面 test_parse_character_book_structure）', () {
      final drafts = parseCharacterBook({
        'name': '测试世界书',
        'description': '用于契约锁的 ST 结构',
        'entries': [
          {
            'keys': ['酒馆', 'tavern'],
            'content': '酒馆的老板是莉莉，她认识每一个常客。',
            'constant': false,
            'insertion_order': 55,
            'probability': 80,
            'group': '地点',
            'group_weight': 30,
            'position': 'before_char',
            'depth': 4,
            'enabled': true,
            'name': '酒馆',
          },
        ],
      });
      expect(drafts, hasLength(1));
      final d = drafts[0];
      expect(d.keys, ['酒馆', 'tavern']);
      expect(d.content, '酒馆的老板是莉莉，她认识每一个常客。');
      expect(d.constant, isFalse);
      expect(d.order, 55);
      expect(d.probability, 80);
      expect(d.groupName, '地点');
      expect(d.groupWeight, 30);
      expect(d.position, 'before_char');
      expect(d.depth, 4);
      expect(d.source, 'manual');
      expect(d.enabled, isTrue);
      expect(d.matchMode, 'or');
      expect(d.title, '酒馆');
    });

    test('selective + secondary_keys → and；否则 or（桌面对齐）', () {
      final andDrafts = parseCharacterBook({
        'entries': [
          {'keys': ['a'], 'secondary_keys': ['b'], 'selective': true},
        ],
      });
      expect(andDrafts[0].matchMode, 'and');

      final orDrafts = parseCharacterBook({
        'entries': [
          {'keys': ['a'], 'selective': false},
        ],
      });
      expect(orDrafts[0].matchMode, 'or');
    });

    test('脏数据容错：非 dict/非 list → 空、非 dict entry 跳过、越界裁剪、position 回落',
        () {
      expect(parseCharacterBook(null), isEmpty);
      expect(parseCharacterBook('oops'), isEmpty);
      expect(parseCharacterBook({'entries': 'oops'}), isEmpty);

      final drafts = parseCharacterBook({
        'entries': [
          42,
          {
            'keys': '单串',
            'insertion_order': 99999,
            'probability': 0,
            'depth': 99,
            'group_weight': 0,
            'position': 'in_chat',
          },
        ],
      });
      expect(drafts, hasLength(1));
      final d = drafts[0];
      expect(d.keys, ['单串']);
      expect(d.order, 9999);
      expect(d.probability, 1);
      expect(d.depth, 20);
      expect(d.groupWeight, 1);
      expect(d.position, 'world');
    });

    test('数值越界裁剪矩阵（验收 6）：order>9999 / probability>100 / depth>20 / group_weight<1',
        () {
      final drafts = parseCharacterBook({
        'entries': [
          {
            'insertion_order': 12345,
            'probability': 200,
            'depth': 30,
            'group_weight': -5,
          },
        ],
      });
      final d = drafts[0];
      expect(d.order, 9999);
      expect(d.probability, 100);
      expect(d.depth, 20);
      expect(d.groupWeight, 1);
    });

    test('布尔字符串按字面求值（false/true 不反转语义；Falsify 修复锁）', () {
      final drafts = parseCharacterBook({
        'entries': [
          {
            'keys': ['a'],
            'constant': 'false',
            'enabled': 'false',
            'selective': 'false',
            'secondary_keys': ['b'],
          },
        ],
      });
      final d = drafts[0];
      expect(d.constant, isFalse);
      expect(d.enabled, isFalse);
      expect(
        d.matchMode,
        'or',
        reason: 'selective=false 时不因存在 secondary_keys 反转为 and',
      );

      final draftsTrue = parseCharacterBook({
        'entries': [
          {'constant': 'true', 'enabled': 'true'},
        ],
      });
      expect(draftsTrue[0].constant, isTrue);
      expect(draftsTrue[0].enabled, isTrue);
    });

    test('insertion_order 缺失回落 order；存在但为 null 回落默认 100（桌面 get 语义）',
        () {
      final fromOrder = parseCharacterBook({
        'entries': [
          {'order': 7},
        ],
      });
      expect(fromOrder[0].order, 7);

      final nullInsertion = parseCharacterBook({
        'entries': [
          {'insertion_order': null, 'order': 7},
        ],
      });
      expect(
        nullInsertion[0].order,
        100,
        reason: '桌面 raw.get(insertion_order) 返回 null → clamp 默认',
      );
    });

    test('真实分布样本：ST 混合形态 character_book 提取非空 + 抽样可读', () {
      // 样本形态源自真实 SillyTavern 角色卡 character_book 字段分布：字符串
      // keys / 列表 keys / 布尔字符串 / in_chat position / group /
      // selective+secondary_keys / 空条目混合（concerns/06.md §4）。
      final drafts = parseCharacterBook({
        'name': '艾莉亚的旅行见闻',
        'description': '来自 V2 卡的 ST 世界书',
        'entries': [
          {
            'keys': '王都',
            'content': '王都的城门高三十丈，守军佩白羽。',
            'insertion_order': 5,
            'enabled': 'true',
          },
          {
            'keys': ['精灵森林', '精灵', 'forest'],
            'content': '精灵森林的树会唱歌，精灵一族避世而居。',
            'insertion_order': 12,
            'probability': '90',
            'position': 'before_char',
            'group': '地理',
            'group_weight': 2,
            'selective': 'true',
            'secondary_keys': ['森林', '木精灵'],
          },
          {
            'keys': ['地窖', '酒桶'],
            'content': '旅店地窖藏着三桶陈年麦酒。',
            'constant': 'false',
            'position': 'in_chat',
            'depth': 3,
          },
          {'name': '占位空条目', 'content': ''},
        ],
      });

      expect(drafts, hasLength(4), reason: '提取非空且逐条可读');
      final first = drafts[0];
      expect(first.keys, ['王都'], reason: '字符串 keys 单值包裹');
      expect(first.content, contains('城门'));
      expect(first.enabled, isTrue, reason: '布尔字符串 true');
      final second = drafts[1];
      expect(second.keys, ['精灵森林', '精灵', 'forest']);
      expect(second.matchMode, 'and', reason: 'selective=true + secondary_keys');
      expect(second.position, 'before_char');
      expect(second.groupName, '地理');
      expect(second.probability, 90, reason: '字符串数字可解析');
      final third = drafts[2];
      expect(third.position, 'world', reason: 'in_chat 回落 world');
      expect(third.depth, 3);
      final fourth = drafts[3];
      expect(fourth.title, '占位空条目');
      expect(fourth.content, '');
      expect(fourth.keys, isEmpty, reason: '缺失 keys → 空列表');
    });
  });
}
