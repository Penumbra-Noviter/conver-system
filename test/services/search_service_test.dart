/// 搜索服务行为契约（M3-04a 搜索数据通路）。
///
/// 语义锚点：桌面 `desktop/backend/app/services/message.py::search_messages`
/// 内联预览（189–244 行）与 `desktop/backend/app/schemas/message.py::SearchResult`。
///
/// - `searchPreview`：±50 字窗口 + 首尾省略号 + 无命中回退前 120 字
///   （桌面逐字语义，回退截断含「恰好 120 字不加省略号」边界）；
/// - `SearchService.search`：trim 后转交仓储；空查询短路空列表；结果映射
///   `SearchResult`（含 `.value` role / 全文 content / join 上下文）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_reader.dart';
import 'package:conver_system_mobile/services/search_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SettingsReader] 的内存假实现（与 message_repository_test 同形）。
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

/// 仓储替身 — [searchMessages] 恒抛错，验证 SearchService 不吞错（验收 6
/// 异常上抛契约，UI 五态「搜索失败」消费）。
class _FailingMessageRepository extends MessageRepository {
  _FailingMessageRepository(super.db);

  @override
  Future<List<MessageSearchHit>> searchMessages(
    String query, {
    int limit = 50,
  }) async {
    throw StateError('simulated repository failure');
  }
}

void main() {
  late AppDatabase db;
  late ConversationRepository convRepo;
  late MessageRepository messageRepo;
  late SearchService service;

  var fakeNow = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    convRepo = ConversationRepository(db, const FakeSettingsReader());
    messageRepo = MessageRepository(db, now: () => fakeNow);
    service = SearchService(messageRepo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String firstMes = '',
  }) async {
    return db.into(db.characters).insertReturning(
          CharactersCompanion.insert(
            name: name,
            firstMes: Value(firstMes),
            createdAt: fakeNow,
            updatedAt: fakeNow,
          ),
        );
  }

  Future<Conversation> seedConversation(int characterId) {
    return convRepo.createConversation(characterId: characterId);
  }

  Future<Message> sendUserMessage(int conversationId, String content) {
    return messageRepo.createMessage(
      conversationId: conversationId,
      role: Role.user,
      content: content,
    );
  }

  group('searchPreview（±50 窗口 + 回退截断，桌面逐字）', () {
    test('命中中置：左 50 字 + 命中 + 右 50 字，两端省略号', () {
      final content = '${'甲' * 100}目标词${'乙' * 100}';
      final preview = searchPreview(content, '目标词');

      expect(preview, '…${'甲' * 50}目标词${'乙' * 50}…');
    });

    test('命中靠前（idx ≤ 50）：仅后置省略号', () {
      final content = '${'甲' * 30}目标词${'乙' * 100}';
      final preview = searchPreview(content, '目标词');

      expect(preview, '${'甲' * 30}目标词${'乙' * 50}…');
    });

    test('命中靠后（idx + len + 50 ≥ 全文长）：仅前置省略号', () {
      final content = '${'甲' * 100}目标词${'乙' * 20}';
      final preview = searchPreview(content, '目标词');

      expect(preview, '…${'甲' * 50}目标词${'乙' * 20}');
    });

    test('恰好左边界：idx == 50 时无前置省略号', () {
      final content = '${'甲' * 50}目标词${'乙' * 100}';
      final preview = searchPreview(content, '目标词');

      expect(preview, '${'甲' * 50}目标词${'乙' * 50}…');
    });

    test('大小写不敏感命中第一处（桌面 lower 语义）', () {
      final content = '先导内容Hello World${'后段内容' * 10}';
      final preview = searchPreview(content, 'hello');

      expect(preview, contains('Hello World'));
      expect(preview.startsWith('先导内容'), isTrue); // idx 靠前 → 无前置省略
      expect(preview, isNot(contains('HELLO')));
    });

    test('无命中且 ≤120 字 → 原样返回（不加省略号）', () {
      final content = '甲' * 120;
      expect(searchPreview(content, '不存在'), content);
    });

    test('无命中且 >120 字 → 前 120 字加「…」', () {
      final content = '甲' * 150;
      expect(searchPreview(content, '不存在'), '${'甲' * 120}…');
    });
  });

  group('SearchService.search（编排 + 结果映射）', () {
    test('命中 → 映射为 SearchResult 契约字段（.value role / 全文 / join 上下文）',
        () async {
      final char = await seedCharacter(name: '星野');
      final conv = await convRepo.createConversation(
        characterId: char.id,
        title: '夜话',
      );
      final msg = await sendUserMessage(conv.id, '今晚的星空很美');

      final results = await service.search('星空');

      expect(results, hasLength(1));
      final r = results.single;
      expect(r.messageId, msg.id);
      expect(r.conversationId, conv.id);
      expect(r.conversationTitle, '夜话');
      expect(r.characterId, char.id);
      expect(r.characterName, '星野');
      expect(r.characterAvatar, isNull); // 种子角色未设头像
      expect(r.role, 'user'); // Role.user.value 语义
      expect(r.content, '今晚的星空很美'); // 全文
      expect(r.createdAt, msg.createdAt);
    });

    test('assistant 消息 → role 映射为 .value "assistant"', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final msg = await messageRepo.createMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: '星空下的回应',
      );

      final results = await service.search('回应');

      expect(results.single.role, 'assistant');
      expect(results.single.messageId, msg.id);
    });

    test('trim 后转交仓储：带首尾空格的查询仍命中', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '关于天气的讨论');

      final results = await service.search('  天气  ');

      expect(results, hasLength(1));
    });

    test('空串/纯空白 → 空列表（短路，不抛错）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '有点内容');

      expect(await service.search(''), isEmpty);
      expect(await service.search('   '), isEmpty);
    });

    test('<2 字符不设服务层阈值：单字符查询直达仓储（<2 拦截归 UI 五态）',
        () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '风');

      final results = await service.search('风');

      expect(results, hasLength(1));
    });

    test('仓储异常原样上抛（不吞错；UI 层五态「搜索失败」消费契约）', () async {
      final failing = SearchService(_FailingMessageRepository(db));

      await expectLater(failing.search('关键词'), throwsA(isA<StateError>()));
    });

    test('排序透传：仓储 createdAt 倒序结果原样保留', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      await sendUserMessage(conv.id, '第一段星空');
      fakeNow = fakeNow.add(const Duration(seconds: 10));
      await sendUserMessage(conv.id, '第二段星空');

      final results = await service.search('星空');

      expect(results.map((r) => r.content), ['第二段星空', '第一段星空']);
    });
  });
}
