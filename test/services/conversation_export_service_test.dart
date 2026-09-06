/// M4-01：ConversationExportService 导出纯逻辑（JSON + Markdown + 文件名）。
///
/// 测试 seam（公共接口边界）：[ConversationExportService] 公开 API（exportJson /
/// exportMarkdown）+ [ConversationExportResult] 值对象。
/// 通过内存 drift + 三真实仓储 + [FakeSettingsReader] 驱动（服务层不 mock 内部）；
/// 输出契约逐字段/逐行断言，不测内部私有函数与遍历顺序。
///
/// 契约锚（桌面权威源只读）：`conversation_export.py` 三函数 +
/// `schemas/conversation.py::ConversationExportCharacter`（9 字段投影）。
///
/// 时间戳口径（spec A4）：JSON 机读 = `.toUtc().toIso8601String()`（drift 存 unix
/// 秒、读回本地时区 DateTime，`toUtc()` 得正确 UTC 时刻——本文件以 UTC 种子断言
/// 精确 `Z` 字面量）；MD 人类展示 = 本地时间（本地 DateTime 字段直接格式化）。
library;

import 'dart:convert';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/conversation_repository.dart';
import 'package:conver_system_mobile/data/repositories/message_repository.dart';
import 'package:conver_system_mobile/services/conversation_export_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/chat_test_env.dart' show FakeSettingsReader;

/// 角色缺失路径专用假仓储：getCharacter 恒返回 null（FK CASCADE 使「对话存在、
/// 角色缺失」状态无法经真实库构造，故以假仓储注入命中该契约分支）。
class _NullCharacterRepository extends CharacterRepository {
  _NullCharacterRepository(super.db);

  @override
  Future<Character?> getCharacter(int characterId) async => null;
}

void main() {
  late AppDatabase db;
  late CharacterRepository charRepo;
  late ConversationRepository convRepo;
  late MessageRepository msgRepo;
  late FakeSettingsReader settings;
  late ConversationExportService service;

  // 可变时刻：会话/角色/消息种子经 `now:` 注入逐条控制（drift 存 unix 秒）。
  late DateTime fakeNow;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    fakeNow = DateTime(2023, 11, 14, 22, 13, 20); // 本地种子（MD 本地显示确定）
    charRepo = CharacterRepository(db, now: () => fakeNow);
    convRepo = ConversationRepository(db, const FakeSettingsReader(),
        now: () => fakeNow);
    msgRepo = MessageRepository(db, now: () => fakeNow);
    settings = FakeSettingsReader({'user_name': '小明'});
    service = ConversationExportService(
      conversationRepository: convRepo,
      characterRepository: charRepo,
      messageRepository: msgRepo,
      settingsReader: settings,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 种子全字段角色（firstMes 空 → 不预插开场白，消息列表精确可控）。
  Future<Character> seedCharacter({
    String name = '艾莉亚',
    String description = '温柔',
    String personality = '安静',
    String scenario = '咖啡馆',
    String firstMes = '',
    String systemPrompt = '系统提示。',
    String? avatar = 'avatar.png',
    double temperature = 0.7,
  }) {
    return charRepo.createCharacter(CharactersCompanion.insert(
      name: name,
      description: Value(description),
      personality: Value(personality),
      scenario: Value(scenario),
      firstMes: Value(firstMes),
      systemPrompt: Value(systemPrompt),
      avatar: Value(avatar),
      temperature: Value(temperature),
      createdAt: fakeNow,
      updatedAt: fakeNow,
    ));
  }

  Future<Conversation> seedConversation(int characterId, {String? title}) =>
      convRepo.createConversation(characterId: characterId, title: title);

  /// 以当前 [fakeNow] 时刻插消息（调用前可改 fakeNow 控制时间戳）。
  Future<Message> seedMessage({
    required int conversationId,
    required Role role,
    required String content,
  }) {
    return msgRepo.createMessage(
      conversationId: conversationId,
      role: role,
      content: content,
    );
  }

  Map<String, dynamic> decodeJson(String content) =>
      jsonDecode(content) as Map<String, dynamic>;

  group('exportJson · JSON 三层契约（字段序 + 值）', () {
    test('三层结构与字段顺序逐项正确（照搬桌面 export_conversation_json）', () async {
      final char = await seedCharacter(
        description: '温柔少女，含 {{char}} 与 {{user}} 字面量。',
      );
      fakeNow = DateTime.utc(2023, 11, 14, 22, 13, 20);
      // 显式非占位标题：避免首条 user 消息触发 auto-title 改写（此断言锚对话
      // 标题字段的落库值）。
      final conv = await seedConversation(char.id, title: '结构化导出测试对话');

      // 三消息乱序插入：C(t0) < A(t1) < B(t2) —— 断言输出按 created_at 升序。
      fakeNow = DateTime.utc(2023, 11, 14, 22, 13, 20);
      await seedMessage(
          conversationId: conv.id, role: Role.user, content: 'U1');
      fakeNow = DateTime.utc(2023, 11, 14, 23, 0, 0);
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: 'A1');
      fakeNow = DateTime.utc(2023, 11, 14, 21, 0, 0);
      await seedMessage(
          conversationId: conv.id, role: Role.system, content: 'S1');

      final result = await service.exportJson(conv.id);
      expect(result, isNotNull);
      final json = decodeJson(result!.content);

      // 顶层键序（桌面 dict 构造顺序）。
      expect(json.keys.toList(), ['conversation', 'character', 'messages']);

      // conversation 段字段序 + 值。
      final conversation = json['conversation']! as Map<String, dynamic>;
      expect(conversation.keys.toList(), [
        'id',
        'title',
        'model_provider',
        'model_name',
        'created_at',
        'updated_at',
      ]);
      expect(conversation['id'], conv.id);
      expect(conversation['title'], '结构化导出测试对话');
      expect(conversation['model_provider'], 'claude');
      expect(conversation['model_name'], 'claude-sonnet-5');
      expect(conversation['created_at'], '2023-11-14T22:13:20.000Z');
      // updated_at 随最后一条消息（fakeNow 已被改到 21:00:00 的 UTC 种子）。
      expect(conversation['updated_at'], '2023-11-14T21:00:00.000Z');

      // character 段 9 字段投影（ConversationExportCharacter 字段序）+ 值。
      final character = json['character']! as Map<String, dynamic>;
      expect(character.keys.toList(), [
        'id',
        'name',
        'description',
        'personality',
        'scenario',
        'first_mes',
        'system_prompt',
        'avatar',
        'temperature',
      ]);
      expect(character['id'], char.id);
      expect(character['name'], '艾莉亚');
      expect(character['description'], '温柔少女，含 {{char}} 与 {{user}} 字面量。');
      expect(character['personality'], '安静');
      expect(character['scenario'], '咖啡馆');
      expect(character['first_mes'], '');
      expect(character['system_prompt'], '系统提示。');
      expect(character['avatar'], 'avatar.png');
      expect(character['temperature'], 0.7);

      // messages 段：字段序 + 按 created_at 升序 + Role.value 落库值。
      final messages = (json['messages']! as List).cast<Map<String, dynamic>>();
      expect(messages, hasLength(3));
      for (final m in messages) {
        expect(m.keys.toList(), ['id', 'role', 'content', 'created_at']);
      }
      expect(messages.map((m) => m['role']).toList(),
          ['system', 'user', 'assistant']);
      expect(messages.map((m) => m['content']).toList(), ['S1', 'U1', 'A1']);
      expect(messages.map((m) => m['created_at']).toList(), [
        '2023-11-14T21:00:00.000Z',
        '2023-11-14T22:13:20.000Z',
        '2023-11-14T23:00:00.000Z',
      ]);
    });

    test('同秒消息以 id 升序兜底（F-3 同秒排序语义）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      fakeNow = DateTime.utc(2023, 11, 14, 22, 13, 20);
      await seedMessage(
          conversationId: conv.id, role: Role.user, content: '第一条');
      await seedMessage(
          conversationId: conv.id, role: Role.user, content: '第二条');

      final result = await service.exportJson(conv.id);
      final messages =
          (decodeJson(result!.content)['messages']! as List).cast<Map>();
      expect(messages.map((m) => m['content']).toList(),
          ['第一条', '第二条'], reason: '同秒以 id 升序兜底');
    });

    test('无消息 → messages 为 []（对话仍正常导出）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);

      final result = await service.exportJson(conv.id);

      final json = decodeJson(result!.content);
      expect(json['messages'], isEmpty);
      expect(json['conversation'], isNotNull);
      expect(json['character'], isNotNull);
    });

    test('对话不存在 → null', () async {
      expect(await service.exportJson(999999), isNull);
    });

    test('角色缺失 → character 段为 null（JSON 契约）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final nullCharService = ConversationExportService(
        conversationRepository: convRepo,
        characterRepository: _NullCharacterRepository(db),
        messageRepository: msgRepo,
        settingsReader: settings,
      );

      final result = await nullCharService.exportJson(conv.id);

      final json = decodeJson(result!.content);
      expect(json['character'], isNull);
      expect(json['conversation'], isNotNull);
    });

    test('JSON 保留模板变量字面量（往返保真，与 MD 替换形成有意差异）', () async {
      final char = await seedCharacter(
        description: '你是 {{char}}，我是 {{user}}。',
      );
      final conv = await seedConversation(char.id);

      final result = await service.exportJson(conv.id);

      final character =
          (decodeJson(result!.content)['character']! as Map<String, dynamic>);
      expect(character['description'], '你是 {{char}}，我是 {{user}}。');
    });
  });

  group('exportMarkdown · MD 逐行契约', () {
    test('标题/角色信息/模型/时间/分隔/按日期分组/消息行 逐行精确', () async {
      final char = await seedCharacter(
        description: '温柔',
        personality: '安静',
        scenario: '咖啡馆',
      );
      final conv = await seedConversation(char.id);
      // 跨本地日期：M1 在 11-14，M2 在 11-15 → 中间以 `---` 分隔。
      fakeNow = DateTime(2023, 11, 14, 22, 15, 0);
      await seedMessage(conversationId: conv.id, role: Role.user, content: '你好');
      fakeNow = DateTime(2023, 11, 15, 8, 0, 0);
      await seedMessage(
          conversationId: conv.id, role: Role.assistant, content: '嗨！');

      final result = await service.exportMarkdown(conv.id);

      expect(result!.content,
          '# 与 艾莉亚 的对话\n'
          '\n'
          '**角色信息**: 温柔；人格: 安静；场景: 咖啡馆\n'
          '**模型**: claude/claude-sonnet-5\n'
          '**时间**: 2023-11-14 22:13\n'
          '\n'
          '---\n'
          '\n'
          '### 2023-11-14\n'
          '\n'
          '**user**: 你好\n'
          '\n'
          '---\n'
          '\n'
          '### 2023-11-15\n'
          '\n'
          '**assistant**: 嗨！\n');
    });

    test('角色信息段：仅非空片段、description 无前缀、人格/场景带前缀、全空→无', () async {
      final char = await seedCharacter(
        description: '',
        personality: '',
        scenario: '',
      );
      final conv = await seedConversation(char.id);

      final result = await service.exportMarkdown(conv.id);

      expect(result!.content, contains('**角色信息**: 无'));

      // 仅 description 非空 → 无前缀。
      await charRepo.updateCharacter(
        char.id,
        CharactersCompanion(
          description: Value('只有描述'),
          personality: const Value(''),
          scenario: const Value(''),
        ),
      );
      final result2 = await service.exportMarkdown(conv.id);
      expect(result2!.content, contains('**角色信息**: 只有描述'));

      // 仅 personality / scenario 非空 → 各自带前缀。
      await charRepo.updateCharacter(
        char.id,
        CharactersCompanion(
          description: const Value(''),
          personality: Value('安静'),
          scenario: Value('咖啡馆'),
        ),
      );
      final result3 = await service.exportMarkdown(conv.id);
      expect(result3!.content, contains('**角色信息**: 人格: 安静；场景: 咖啡馆'));
    });

    test('角色缺失 → 标题「未知角色」+ 角色信息「无」', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final nullCharService = ConversationExportService(
        conversationRepository: convRepo,
        characterRepository: _NullCharacterRepository(db),
        messageRepository: msgRepo,
        settingsReader: settings,
      );

      final result = await nullCharService.exportMarkdown(conv.id);

      expect(result!.content, contains('# 与 未知角色 的对话'));
      expect(result.content, contains('**角色信息**: 无'));
    });

    test('角色信息段模板变量替换（{{char}}/{{user}} → 角色名/设置昵称）', () async {
      final char = await seedCharacter(
        description: '你是 {{char}}，我是 {{user}}。',
      );
      final conv = await seedConversation(char.id);

      final result = await service.exportMarkdown(conv.id);

      expect(result!.content,
          contains('**角色信息**: 你是 艾莉亚，我是 小明。'));
    });

    test('昵称未配置 → 缺省 User', () async {
      final unsetService = ConversationExportService(
        conversationRepository: convRepo,
        characterRepository: charRepo,
        messageRepository: msgRepo,
        settingsReader: const FakeSettingsReader(),
      );
      final char = await seedCharacter(
        description: '我是 {{user}}。',
      );
      final conv = await seedConversation(char.id);

      final result = await unsetService.exportMarkdown(conv.id);

      expect(result!.content, contains('**角色信息**: 我是 User。'));
    });

    test('对话不存在 → null', () async {
      expect(await service.exportMarkdown(999999), isNull);
    });

    test('MD 控制字符净化：除 \\n/\\t 外 \\x00-\\x1F 替换为空格（A7）', () async {
      final char = await seedCharacter(
        description: '描述\x01带控制字符\x02',
      );
      final conv = await seedConversation(char.id);
      await seedMessage(
        conversationId: conv.id,
        role: Role.assistant,
        content: 'a\x00b\x01c\x1fd\ne\tf',
      );

      final result = await service.exportMarkdown(conv.id);

      // 角色信息段：\x01/\x02 → 空格；\n/\t 保留（消息行内）。
      expect(result!.content, contains('**角色信息**: 描述 带控制字符 '));
      expect(result.content,
          contains('**assistant**: a b c d\ne\tf'));
      // JSON 侧天然安全（jsonEncode 转义），MD 侧净化——有意差异（A7）。
    });
  });

  group('导出文件名 · safeFileName 净化 + 扩展名', () {
    test('JSON / Markdown 文件名 = {safe}.json / {safe}.md', () async {
      final char = await seedCharacter(name: '艾莉亚');
      final conv = await seedConversation(char.id);

      final json = await service.exportJson(conv.id);
      final md = await service.exportMarkdown(conv.id);

      expect(json!.fileName, '艾莉亚.json');
      expect(md!.fileName, '艾莉亚.md');
    });

    test('非法字符文件名经 safeFileName 净化（非法/控制→_、首尾点剔除、100 截断）',
        () async {
      final char = await seedCharacter(name: r'a/b\c:d*e?f"g<h>i|j');
      final conv = await seedConversation(char.id);

      final result = await service.exportJson(conv.id);

      expect(result!.fileName, 'a_b_c_d_e_f_g_h_i_j.json');
    });

    test('角色缺失回退对话 id → 文件名为 {id}.json（safeFileName 恒安全）', () async {
      final char = await seedCharacter();
      final conv = await seedConversation(char.id);
      final nullCharService = ConversationExportService(
        conversationRepository: convRepo,
        characterRepository: _NullCharacterRepository(db),
        messageRepository: msgRepo,
        settingsReader: settings,
      );

      final result = await nullCharService.exportJson(conv.id);

      expect(result!.fileName, '${conv.id}.json');
    });
  });
}