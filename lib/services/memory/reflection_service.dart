/// ReflectionService — 后台反思提取（人机恋板块阶段 1.5，ADR-0004）。
///
/// 深模块：协议表面仅 [reflectAfterTurn] 一个编排入口，实现内聚「节流判定 →
/// 对话历史组装 → LLM 反思 → JSON 数组解析 → 去重落库」的完整闭环，复用纯函数
/// （[buildReflectionMessages] / [parseReflectionFacts]）与既有仓储。
///
/// 语义锚点：ADR-0004（每 N 回合反思 + 默认关闭 + 仅人格事实 + 去重 + 异步
/// 降级）。与阶段 1 prompt 指令驱动**互补**：两链路写入同一 `persona_fact`，
/// 注入端（MemoryService.buildInjection）零改动即自动受益——本服务补 LLM 主动
/// `<persona:>` 标签遗漏的稳定事实。
///
/// - 节流：以对话 user 消息数 `% interval == 0` 幂等判定（无新状态/新列，跨
///   重启安全），不满足直接返回 0；
/// - 反思输入：角色名 + 最近 [historyLimit] 条对话历史（user/assistant 各自
///   署名）+ 已有人格事实（prompt 内标注「勿重复」，减少冗余输出）；
/// - 产出：JSON 字符串数组（三级容错解析），逐条去重后落 `persona_fact`。
library;

import 'dart:convert';

import '../../data/database/tables.dart' show MemoryKind, Role;
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../utils/llm_json_candidates.dart';
import '../llm/llm_provider.dart' show LlmMessage, LLMProvider;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 document_parse_service 惯例）。
// ignore_for_file: prefer_initializing_formals

/// 反思 seam：输入角色名 + 对话历史行 + 已有人格事实，产出新提炼的人格事实
/// 列表。生产装配用 [extractPersonaFactsWithProvider] 包装
/// [LLMProvider.generate]，测试注入 fake。
typedef PersonaFactExtractor = Future<List<String>> Function({
  required String charName,
  required List<String> dialogueLines,
  required List<String> existingFacts,
});

/// 组装反思 prompt 消息（纯函数，可单测）。
///
/// system 教导 LLM 只输出 JSON 字符串数组（无解释/前缀/Markdown 代码块）、不
/// 编造、不重复已有事实；user 附已有人格事实 + 对话历史 + 输出请求。
List<LlmMessage> buildReflectionMessages({
  required String charName,
  required List<String> dialogueLines,
  required List<String> existingFacts,
}) {
  final factsBlock = existingFacts.isEmpty
      ? '（暂无）'
      : existingFacts.map((f) => '- $f').join('\n');
  final dialogueBlock = dialogueLines.isEmpty
      ? '（暂无对话记录）'
      : dialogueLines.join('\n');
  return [
    LlmMessage(
      role: 'system',
      content: '你是「$charName」的记忆提炼助手。阅读下面的对话记录，提炼出关于'
          '对话对象（用户）的稳定人格事实——身份、喜好、厌恶、性格、习惯、与角色'
          '的关系等。每条事实用一句简洁的第三人称陈述（例如「用户喜欢喝咖啡」）。'
          '只输出 JSON 字符串数组，不要任何解释、前缀或 Markdown 代码块。'
          '不要编造对话中未出现的信息，不要重复「已有记忆」中已列出的事实。',
    ),
    LlmMessage(
      role: 'user',
      content: '已有记忆（勿重复）：\n$factsBlock\n\n'
          '对话记录：\n$dialogueBlock\n\n'
          '请输出新提炼的人格事实（JSON 字符串数组）：',
    ),
  ];
}

/// 解析 LLM 输出的 JSON 字符串数组（三级容错：直接 → ```json 代码块 → 方括号
/// 范围；全部失败 → 空列表）。
///
/// 对齐 `document_parse_service.extractJsonFromLlm` 的三级提取思路，但目标为
/// **数组**（反思产出为事实列表）。仅保留字符串且 trim 后非空的条目，其余
/// （非字符串 / 空串）丢弃。
List<String> parseReflectionFacts(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const <String>[];
  }

  // 候选段枚举（直接 trim 原文 → fenced 段 → 方括号范围段）由
  // [llmJsonCandidates] 单源承载；本函数只保留 array 解码 + 字符串过滤。
  for (final candidate in llmJsonCandidates(text, open: '[', close: ']')) {
    final decoded = _decodeStringList(candidate);
    if (decoded != null) {
      return decoded;
    }
  }

  return const <String>[];
}

/// 尝试把 [text] 解析为 JSON 字符串数组；失败或非数组返回 null。
List<String>? _decodeStringList(String text) {
  try {
    final data = jsonDecode(text);
    if (data is! List) {
      return null;
    }
    final result = <String>[
      for (final item in data)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
    return List<String>.unmodifiable(result);
  } on FormatException {
    return null;
  }
}

/// 生产装配用的反思实现：组装 prompt 并经 [llm].generate 产出事实列表。
///
/// [model] 为调用模型名（透传 provider）；返回 [Future<List<String>>] 与
/// [PersonaFactExtractor] 签名同形（装配层闭包绑定 llm/model 后传入服务）。
Future<List<String>> extractPersonaFactsWithProvider({
  required LLMProvider llm,
  required String model,
  required String charName,
  required List<String> dialogueLines,
  required List<String> existingFacts,
}) async {
  final messages = buildReflectionMessages(
    charName: charName,
    dialogueLines: dialogueLines,
    existingFacts: existingFacts,
  );
  final raw = await llm.generate(messages: messages, model: model);
  return parseReflectionFacts(raw);
}

/// 后台反思服务 — 每 N 回合异步提炼人格事实并落库。
class ReflectionService {
  /// [interval] 为反思节流间隔（每 N 回合一次，缺省 6）；[historyLimit] 为
  /// 送入反思的最近对话消息条数上限（缺省 20）。
  ReflectionService({
    required CharacterRepository characterRepository,
    required MemoryRepository memoryRepository,
    required MessageRepository messageRepository,
    required PersonaFactExtractor extractor,
    int interval = 6,
    int historyLimit = 20,
  })  : _characterRepository = characterRepository,
        _memoryRepository = memoryRepository,
        _messageRepository = messageRepository,
        _extractor = extractor,
        _interval = interval,
        _historyLimit = historyLimit;

  final CharacterRepository _characterRepository;
  final MemoryRepository _memoryRepository;
  final MessageRepository _messageRepository;
  final PersonaFactExtractor _extractor;
  final int _interval;
  final int _historyLimit;

  /// 回合落库后触发一次反思（异步 fire-and-forget，失败上抛由调用方降级）。
  ///
  /// 编排：
  /// 1. 节流——该对话 user 消息数须 > 0 且 `% interval == 0`，否则返回 0；
  /// 2. 读角色（不存在 → 0）与已有人格事实（去重基准）；
  /// 3. 取最近 [historyLimit] 条消息组装对话行（user 署名「用户」、assistant
  ///    署名角色名）；
  /// 4. [extractor] 反思产出事实 → 逐条 trim 去重后落 `persona_fact`；
  /// 5. 返回实际落库条数（0 = 无新事实）。
  Future<int> reflectAfterTurn({
    required int characterId,
    required int conversationId,
  }) async {
    final messages = await _messageRepository.getMessages(conversationId);
    final userCount = messages.where((m) => m.role == Role.user).length;
    if (userCount == 0 || userCount % _interval != 0) {
      return 0;
    }

    final character = await _characterRepository.getCharacter(characterId);
    if (character == null) {
      return 0;
    }

    final existing = await _memoryRepository.listPersonaFacts(characterId);
    final existingSet = <String>{for (final f in existing) f.content.trim()};

    final recent = messages.length > _historyLimit
        ? messages.sublist(messages.length - _historyLimit)
        : messages;
    final dialogueLines = <String>[
      for (final m in recent)
        m.role == Role.user ? '用户：${m.content}' : '${character.name}：${m.content}',
    ];

    final extracted = await _extractor(
      charName: character.name,
      dialogueLines: dialogueLines,
      existingFacts: existingSet.toList(),
    );

    var added = 0;
    for (final fact in extracted) {
      final trimmed = fact.trim();
      if (trimmed.isEmpty || existingSet.contains(trimmed)) {
        continue;
      }
      await _memoryRepository.createEntry(
        characterId: characterId,
        kind: MemoryKind.personaFact,
        content: trimmed,
      );
      existingSet.add(trimmed); // 防单次提取内的重复事实。
      added++;
    }
    return added;
  }
}
