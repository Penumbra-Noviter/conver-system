/// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
/// 同时满足两者，整文件抑制该 lint（对齐 reflection_service /
/// document_parse_service 惯例）。
// ignore_for_file: prefer_initializing_formals

/// ThoughtService — 内心独白（P5）提取 / 落库 / prompt 指令。
///
/// 深模块：协议表面 = [extractThought]（纯函数剥离契约，SR-05）+
/// [buildThoughtInstruction]（system 指令文案）+ [ThoughtService.persistThought]
/// （按开关编排落库）。剥离**恒启用**（spec 判定①）：无论开关状态，检出
/// `<thought>...</thought>` 一律剥离（防泄漏进 UI/搜索/导出）；开关只控制
/// 「prompt 是否要求 thought」与「是否落 InnerThoughts 表」。
///
/// S5 分工（架构深化）：[extractThought] 为全链路唯一剥离点，由调用方
/// （ChatService._persistAssistant）执行并持有已剥离的 `thoughtContent`；
/// 服务只接收已剥离内容做「开关读 + FK 落库 + 降级」，不再对原文重跑。
///
/// 剥离契约（SR-05，按工单 PS2-04 验收 1-3、5 落地）：
/// - 成对闭合 `<thought>...</thought>`（大小写不敏感）首段 → 剥离 + thought 非空；
/// - 开标签无闭合 → displayContent 不含 thought 块残留（隐藏保正文），
///   thoughtContent 为 null（不落库）；
/// - 无标签 → 原样 + null；
/// - 空 / 纯空白独白 → 丢弃（thoughtContent null），标签仍剥离；
/// - 多块 → 提取第一块，其余按「开标签无闭合」处理（后续 thought 块不再泄漏）。
/// 复杂度与上限（SR-13）：固定字面量正则（无嵌套量词，线性），独白内容
/// 超过 [_maxThoughtLength]（1 MiB）截断；纯字符串操作无可抛路径（SR-05
/// 「剥离器抛不出异常」由实现性质满足）。
library;

import 'package:flutter/foundation.dart';

import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/settings_repository.dart';

/// 独白内容长度上限（SR-13；按 UTF-16 code units 计，ASCII 下恰为 1 MiB）。
const int _maxThoughtLength = 1 << 20;

/// 开标签精确字面量（大小写不敏感；不带属性/空格变体——SR-05「精确成对」）。
final RegExp _openThought = RegExp(r'<thought>', caseSensitive: false);

/// 闭合标签精确字面量（大小写不敏感）。
final RegExp _closeThought = RegExp(r'</thought>', caseSensitive: false);

/// 从 [raw] 中提取首段内心独白（纯函数，SR-05 剥离契约）。
///
/// 返回 `displayContent`（剥离后的展示正文，恒启用）+ `thoughtContent`（独白
/// 内容；无独白 / 解析失败 / 空独白为 null）。契约细节见文件头注释。
({String displayContent, String? thoughtContent}) extractThought(String raw) {
  final open = _openThought.firstMatch(raw);
  if (open == null) {
    return (displayContent: raw, thoughtContent: null);
  }

  final openEnd = open.end;
  final closeMatches = _closeThought.allMatches(raw, openEnd);
  final close = closeMatches.isEmpty ? null : closeMatches.first;
  if (close == null) {
    // 开标签无闭合：隐藏 thought 块残留（自开标签起剥到文本末尾），不落库。
    return (displayContent: raw.substring(0, open.start), thoughtContent: null);
  }

  var thought = raw.substring(openEnd, close.start).trim();
  if (thought.length > _maxThoughtLength) {
    thought = thought.substring(0, _maxThoughtLength);
  }

  final after = raw.substring(close.end);
  final nextOpen = _openThought.firstMatch(after);
  if (nextOpen == null) {
    return (
      displayContent: raw.substring(0, open.start) + after,
      thoughtContent: thought.isEmpty ? null : thought,
    );
  }
  // 多块：提取第一块；其余块按「开标签无闭合」处理（剥到下一个开标签为止，
  // 后续 thought 内容与标签不再进入 displayContent）。
  return (
    displayContent:
        raw.substring(0, open.start) + after.substring(0, nextOpen.start),
    thoughtContent: thought.isEmpty ? null : thought,
  );
}

/// 返回内心独白 system 指令文案（工单验收 5，PS2-07 按开关拼装）。
///
/// 语义：内心独白用 `<thought>...</thought>` 标签包裹且**不直接输出**到正文；
/// 正文只写角色对用户说的话。
String buildThoughtInstruction() {
  return '你的内心独白必须用 <thought>...</thought> 标签包裹并置于正文之前，'
      '并且不要直接输出独白内容到正文；正文只写角色对用户说的话。';
}

/// 内心独白服务 — 剥离 + 按开关落库编排（判定①）。
class ThoughtService {
  /// [companionRepository] 提供 InnerThoughts 落库查询面；[settingsRepository]
  /// 提供 `innerThoughtEnabled` 开关读取。
  ThoughtService({
    required CompanionRepository companionRepository,
    required SettingsRepository settingsRepository,
  })  : _companionRepository = companionRepository,
        _settingsRepository = settingsRepository;

  final CompanionRepository _companionRepository;
  final SettingsRepository _settingsRepository;

  /// 按开关落库已剥离的 [thoughtContent]（S5：服务不再对原文剥离）。
  ///
  /// 输入契约：调用方（ChatService）已经 [extractThought] 剥离并把非空独白
  /// 传入——服务只做「开关读 + FK 落库 + 降级」。`innerThoughtEnabled` 开启 →
  /// 落 InnerThoughts（characterId / messageId 随参透传）；关闭 → debugPrint
  /// 记录且不落库。空串 → 防御性直接返回不落库（顶层剥离已丢弃空独白，
  /// 服务侧不重复判定）。
  Future<void> persistThought({
    required int characterId,
    required int messageId,
    required String thoughtContent,
  }) async {
    if (thoughtContent.isEmpty) {
      return;
    }
    final enabled = await _settingsRepository.innerThoughtEnabled;
    if (enabled) {
      await _companionRepository.createThought(
        characterId: characterId,
        messageId: messageId,
        content: thoughtContent,
      );
    } else {
      debugPrint('ThoughtService: thought content received but '
          'inner_thought_enabled is off; not persisted.');
    }
  }
}
