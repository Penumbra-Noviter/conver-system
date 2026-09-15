/// PS2-04 ThoughtService 测试 — 内心独白剥离 / 落库 / 指令。
///
/// 语义锚点（工单验收 1-5 + threat-model SR-05 / SR-13）：
/// - `extractThought` 纯函数：成对闭合 `<thought>...</thought>`（大小写不敏感）
///   首段剥离 + thought 非空；无标签 → 原样 + null；开标签无闭合 →
///   displayContent 不含 thought 块残留 + thoughtContent null（工单验收 2）；
///   空/纯空白独白 → 丢弃不落库；多块 → 提取第一块、其余按无闭合处理
///   （工单验收 5）；1 MiB 长度封顶 + 线性处理不抛（SR-13）。
/// - `stripAndPersist`：剥离恒启用（判定①）；开关开启且检出 → 落
///   InnerThoughts 可查回；关闭 → 剥离 + debugPrint + 不落库（工单验收 4）。
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
      final result = extractThought('A <thought>一</thought> B <thought>二</thought> C');
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

  group('ThoughtService.stripAndPersist（工单验收 4）', () {
    late AppDatabase db;
    late CompanionRepository companion;
    late SettingsRepository settings;
    late ThoughtService service;
    late DateTime fixedNow;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      fixedNow = DateTime(2026, 9, 15, 12, 0, 0);
      companion = CompanionRepository(db, now: () => fixedNow);
      settings = SettingsRepository(database: db, secretStore: InMemorySecretStore());
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
      final character = await db.into(db.characters).insertReturning(
            CharactersCompanion.insert(name: '链主', createdAt: now, updatedAt: now),
          );
      final conversation = await db.into(db.conversations).insertReturning(
            ConversationsCompanion.insert(
              characterId: character.id,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final message = await db.into(db.messages).insertReturning(
            MessagesCompanion.insert(
              conversationId: conversation.id,
              role: Role.assistant,
              content: '含独白原文',
              createdAt: now,
            ),
          );
      return (characterId: character.id, messageId: message.id);
    }

    test('开关开启 + 检出 thought → 落 InnerThoughts 可查回（验收核心 4）', () async {
      final ids = await seedChain();
      await settings.setMany({SettingsRepository.innerThoughtEnabledKey: 'true'});

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '正文<thought>她动摇了</thought>尾注',
      );

      expect(display, '正文尾注');
      final thoughts = await companion.listThoughtsByMessage(ids.messageId);
      expect(thoughts, hasLength(1));
      expect(thoughts.single.content, '她动摇了');
      expect(thoughts.single.characterId, ids.characterId);
      expect(thoughts.single.messageId, ids.messageId);
      expect(thoughts.single.createdAt, fixedNow);
    });

    test('开关关闭 + 检出 thought → 仍剥离 + 不落库（判定①）', () async {
      final ids = await seedChain();

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: 'A<thought>内心</thought>B',
      );

      expect(display, 'AB');
      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
    });

    test('开关开启但无 thought → 不落库 + 原样返回', () async {
      final ids = await seedChain();
      await settings.setMany({SettingsRepository.innerThoughtEnabledKey: 'true'});

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '普通正文',
      );

      expect(display, '普通正文');
      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
    });

    test('开关开启但空独白 → 不落库 + 标签剥离（SR-05 空独白丢弃）', () async {
      final ids = await seedChain();
      await settings.setMany({SettingsRepository.innerThoughtEnabledKey: 'true'});

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: 'A<thought>   </thought>B',
      );

      expect(display, 'AB');
      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
    });

    test('多块 → 仅落第一块 + display 剥离（工单验收 5）', () async {
      final ids = await seedChain();
      await settings.setMany({SettingsRepository.innerThoughtEnabledKey: 'true'});

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: 'A <thought>一</thought> B <thought>二</thought> C',
      );

      expect(display, 'A  B ');
      final thoughts = await companion.listThoughtsByMessage(ids.messageId);
      expect(thoughts, hasLength(1));
      expect(thoughts.single.content, '一');
    });

    test('开关关闭 + 开标签无闭合 → 剥离残留 + 不落库', () async {
      final ids = await seedChain();

      final display = await service.stripAndPersist(
        characterId: ids.characterId,
        messageId: ids.messageId,
        content: '正文<thought>截断',
      );

      expect(display, '正文');
      expect(await companion.listThoughtsByMessage(ids.messageId), isEmpty);
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