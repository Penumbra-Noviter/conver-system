/// PS2-04 ThoughtService 测试 — 内心独白剥离 / 落库 / 指令。
///
/// 语义锚点（工单验收 1-5 + threat-model SR-05 / SR-13）：
/// - `extractThought` 纯函数：成对闭合 `<thought>...</thought>`（大小写不敏感）
///   首段剥离 + thought 非空；无标签 → 原样 + null；开标签无闭合 →
///   displayContent 不含 thought 块残留 + thoughtContent null（工单验收 2）；
///   空/纯空白独白 → 丢弃不落库；多块 → 提取第一块、其余按无闭合处理
///   （工单验收 5）；1 MiB 长度封顶 + 线性处理不抛（SR-13）。
/// - `persistThought`：服务只接收已剥离的 `thoughtContent`（S5 全链路单点剥离，
///   服务不再对原文重跑）；开关开启 → 落 InnerThoughts 可查回；关闭 →
///   debugPrint + 不落库（工单验收 4）；空串 → 防御不落库。
/// - `buildThoughtInstruction`：system 指令语义「`<thought>` 包裹且不直接输出」
///   （工单验收 5）。
library;

import 'dart:math';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/database/tables.dart';
import 'package:conver_system_mobile/data/repositories/companion_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/companion/thought_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 开关读抛错替身：`innerThoughtEnabled` getter 抛错（F-133 服务层契约——
/// persistThought 不吞、上抛给调用方按降级语义处理）。
class _ThrowingSettingsRepository extends SettingsRepository {
  _ThrowingSettingsRepository(AppDatabase database)
      : super(database: database, secretStore: InMemorySecretStore());

  @override
  Future<bool> get innerThoughtEnabled async =>
      throw StateError('boom settings');
}

void main() {
  group('extractThought（SR-05 剥离契约，失败路径优先）', () {
    test('空输入 → 空 display + null', () {
      final result = extractThought('');
      expect(result.displayContent, '');
      expect(result.thoughtContent, isNull);
    });

    test('无标签 → 原样 + null（工单验收 1）', () {
      const raw = '这是一段普通正文，没有标签。';
      final result = extractThought(raw);
      expect(result.displayContent, raw);
      expect(result.thoughtContent, isNull);
    });

    test('开标签无闭合 → displayContent 不含 thought 块残留 + null（工单验收 2）', () {
      final result = extractThought('正文开始了 <thought>模型输出被截断');
      expect(result.displayContent, '正文开始了 ');
      expect(result.thoughtContent, isNull);
    });

    test('纯开标签 → 全部剥离 + null', () {
      final result = extractThought('<thought>');
      expect(result.displayContent, '');
      expect(result.thoughtContent, isNull);
    });

    test('成对闭合 → 剥离 + thought 非空（工单验收 1）', () {
      final result = extractThought('前置<thought>她今天看起来很开心</thought>后置');
      expect(result.displayContent, '前置后置');
      expect(result.thoughtContent, '她今天看起来很开心');
    });

    test('剥离后正文为空串边界 → 空 display + thought 非空（验收核心 2）', () {
      final result = extractThought('<thought>只是独白</thought>');
      expect(result.displayContent, '');
      expect(result.thoughtContent, '只是独白');
    });

    test('尾部 thought 块 → 剥净', () {
      final result = extractThought('正文<thought>x</thought>');
      expect(result.displayContent, '正文');
      expect(result.thoughtContent, 'x');
    });

    test('空标签 → 空独白丢弃 + 标签仍剥离（SR-05）', () {
      final result = extractThought('A<thought></thought>B');
      expect(result.displayContent, 'AB');
      expect(result.thoughtContent, isNull);
    });

    test('纯空白独白 → 丢弃 + 标签仍剥离（SR-05）', () {
      final result = extractThought('<thought>   \n </thought>正文');
      expect(result.displayContent, '正文');
      expect(result.thoughtContent, isNull);
    });

    test('大小写变体 → 视为有效剥离（SR-05 固化决策）', () {
      expect(extractThought('<THOUGHT>x</THOUGHT>').thoughtContent, 'x');
      expect(extractThought('<Thought>y</Thought>').thoughtContent, 'y');
      expect(extractThought('<thought>z</THOUGHT>').thoughtContent, 'z');
    });

    test('多块（两个闭合块）→ 提取第一块、其余按无闭合处理（工单验收 5）', () {
      final result = extractThought(
        'A <thought>一</thought> B <thought>二</thought> C',
      );
      expect(result.displayContent, 'A  B ');
      expect(result.thoughtContent, '一');
    });

    test('嵌套标签 → 首开+首闭线性配对（不配栈），thought 内原样保留', () {
      final result = extractThought('A <thought>残 <thought>二</thought> C');
      expect(result.displayContent, 'A  C');
      expect(result.thoughtContent, '残 <thought>二');
    });

    test('thought 标签带空格/属性 → 非精确标签，不剥离（SR-05 用户手工输入无闭合对）', () {
      const raw = '用户写了 <thought >一个词</thought> 原样显示';
      final result = extractThought(raw);
      expect(result.displayContent, raw);
      expect(result.thoughtContent, isNull);
    });

    test('孤立闭合标签（无开标签）→ 不剥离原样保留', () {
      const raw = '正文末尾</thought>';
      final result = extractThought(raw);
      expect(result.displayContent, raw);
      expect(result.thoughtContent, isNull);
    });

    test('独白内容恰好 1 MiB → 不截断（SR-13 上限边界）', () {
      final longThought = List.filled(1 << 20, 'x').join();
      final result = extractThought('<thought>$longThought</thought>');
      expect(result.thoughtContent, hasLength(1 << 20));
      expect(result.displayContent, '');
    });

    test('独白内容超 1 MiB → 截断到上限，不抛（SR-13）', () {
      final overThought = List.filled((1 << 20) + 1, 'y').join();
      final result = extractThought('<thought>$overThought</thought>');
      expect(result.thoughtContent, hasLength(1 << 20));
      expect(result.displayContent, '');
    });

    test('10 MiB 无标签随机串 → 原样返回不抛（SR-13 线性有界）', () {
      final random = Random(42);
      final big = String.fromCharCodes(
        List<int>.generate(10 << 20, (_) => 0x61 + random.nextInt(3)),
      );
      final result = extractThought(big);
      expect(result.displayContent, big);
      expect(result.thoughtContent, isNull);
    });
  });

  group('ThoughtService.persistThought（工单验收 4，S5 已剥离输入）', () {
    late AppDatabase db;
    late CompanionRepository companion;
    late SettingsRepository settings;
    late ThoughtService service;
    late DateTime fixedNow;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
      companion = CompanionRepository(db, now: () => fixedNow);
      settings = SettingsRepository(
        database: db,
        secretStore: InMemorySecretStore(),
      );
      service = ThoughtService(
        companionRepository: companion,
        settingsRepository: settings,
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<({int characterId, int messageId})> seedChain() async {
      final now = DateTime(2026, 9, 1);
      final character = await db
          .into(db.characters)
          .insertReturning(
            CharactersCompanion.insert(
              name: '链主',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final conversation = await db
          .into(db.conversations)
          .insertReturning(
            ConversationsCompanion.insert(
              characterId: character.id,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final message = await db
          .into(db.messages)
          .insertReturning(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: Role.assistant,
              content: '已剥离正文（S5：服务不再接收原文）',
              createdAt: now,
            ),
          );
      return (characterId: character.id, messageId: message.id);
    }

    test('开关开启 + 已剥离 thoughtContent → 落 InnerThoughts 可查回（验收核心 4）', () async {
      final ids = await seedChain();
      await settings.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });

      await service.persistThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        thoughtContent: '她动摇了',
      );

      final thoughts = await companion.listThoughtsByMessage(ids.messageId);
      expect(thoughts, hasLength(1));
      expect(thoughts.single.content, '她动摇了');
      expect(thoughts.single.characterId, ids.characterId);
      expect(thoughts.single.messageId, ids.messageId);
      expect(thoughts.single.createdAt, fixedNow);
    });

    test('开关关闭 + thoughtContent → debugPrint 不落库（判定①）', () async {
      final ids = await seedChain();

      await service.persistThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        thoughtContent: '内心',
      );

      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
    });

    test('开关开启但 thoughtContent 空串 → 防御不落库', () async {
      final ids = await seedChain();
      await settings.setMany({
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });

      await service.persistThought(
        characterId: ids.characterId,
        messageId: ids.messageId,
        thoughtContent: '',
      );

      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
    });

    test(
      '超长 thoughtContent 服务侧截断到 1 MiB（F-132：与 extractThought 同上限）',
      () async {
        final ids = await seedChain();
        await settings.setMany({
          SettingsRepository.innerThoughtEnabledKey: 'true',
        });
        final maxLength = 1 << 20;
        final overlong = '${'x' * maxLength}y';

        await service.persistThought(
          characterId: ids.characterId,
          messageId: ids.messageId,
          thoughtContent: overlong,
        );

        final thoughts = await companion.listThoughtsByMessage(ids.messageId);
        expect(thoughts.single.content.length, maxLength);
        expect(thoughts.single.content, endsWith('x'));
      },
    );

    test('开关读抛错 → persistThought 上抛（服务不吞，调用方负责降级）F-133', () async {
      final ids = await seedChain();
      final throwingService = ThoughtService(
        companionRepository: companion,
        settingsRepository: _ThrowingSettingsRepository(db),
      );

      await expectLater(
        throwingService.persistThought(
          characterId: ids.characterId,
          messageId: ids.messageId,
          thoughtContent: '心',
        ),
        throwsStateError,
      );
    });
  });

  group('buildThoughtInstruction（工单验收 5）', () {
    test('返回 system 指令：thought 包裹 + 不直接输出', () {
      final instruction = buildThoughtInstruction();
      expect(instruction, isNotEmpty);
      expect(instruction, contains('<thought>'));
      expect(instruction, contains('</thought>'));
      expect(instruction, contains('不要直接输出'));
    });
  });
}
