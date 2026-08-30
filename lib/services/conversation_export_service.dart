/// 对话导出纯逻辑服务（JSON + Markdown + 文件名）— M4-01。
///
/// 桌面权威源（只读，语义锚点）：
/// `desktop/backend/app/services/conversation_export.py`（export_conversation_json /
/// export_conversation_markdown / character_export_filename 三函数逐行）+ `schemas/
/// conversation.py::ConversationExportCharacter`（character 段 9 字段投影）。
///
/// 本服务为纯逻辑（无平台依赖）：构造注入会话 / 角色 / 消息三仓储 +
/// [SettingsReader]（userName），表面方法产出 `(fileName, content)` 值对象；
/// 对话不存在返回 `null`（UI 转「对话不存在」提示）。平台书写分享不在此——
/// 归 [ConversationExportFileExchange]（M4-02 seam）。
///
/// 有意偏差（spec A4/A7，契约注释）：
/// - 时间戳口径：JSON 机读 = `.toUtc().toIso8601String()`（带 Z、毫秒 `.000` 后缀
///   形态——drift 存 unix 秒、读回本地时区 DateTime，`toUtc()` 得正确 UTC 时刻，
///   秒精度；与桌面 naive-local 带微秒的差异以「均可被 ISO 解析」承保）；
///   MD 人类展示 = 本地时间（drift 读回即本地时区 DateTime，`YYYY-MM-DD HH:MM` 与
///   `### YYYY-MM-DD`）。
/// - 控制字符净化：MD 中把除 `\n`/`\t` 外的 `\x00-\x1F` 替换为空格（桌面无此
///   净化，移动端有意偏差；JSON 由 jsonEncode 天然转义安全）。
/// - 模板变量差异：JSON 保留 `{{char}}`/`{{user}}` 字面量（往返保真），MD 角色
///   信息段替换为真实角色名/昵称——与桌面行为一致的有意设计。
library;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（构造语义由下方 docstring 说明）。
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import '../data/database/app_database.dart' show Character, Conversation;
import '../data/repositories/character_repository.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/settings_reader.dart';
import 'character_file_exchange.dart' show safeFileName;
import 'template_vars.dart';

/// 对话导出结果值对象：[fileName] 为净化后的文件名（含扩展名），[content] 为
/// 完整导出内容（JSON 或 Markdown 字符串）。
class ConversationExportResult {
  const ConversationExportResult({
    required this.fileName,
    required this.content,
  });

  /// 平台安全文件名（`{safeName}.json` / `{safeName}.md`）。
  final String fileName;

  /// 导出内容（JSON 序列化字符串 / Markdown 文本）。
  final String content;
}

/// 对话导出服务 — 从仓库读取对话/角色/消息，产出桌面契约的导出产物。
///
/// 无平台依赖（layer_boundary：数据层 → 服务层，drift 不泄漏到 UI）；
/// 表面两个入口 + 文件名基公开方法，测试经内存 drift + 假仓储断言输出契约。
class ConversationExportService {
  /// [conversationRepository] / [characterRepository] / [messageRepository] 为
  /// 三仓储读取面；[settingsReader] 提供 user_name（MD 模板变量 {{user}} 昵称）。
  ConversationExportService({
    required ConversationRepository conversationRepository,
    required CharacterRepository characterRepository,
    required MessageRepository messageRepository,
    required SettingsReader settingsReader,
  })  : _conversationRepository = conversationRepository,
        _characterRepository = characterRepository,
        _messageRepository = messageRepository,
        _settingsReader = settingsReader;

  final ConversationRepository _conversationRepository;
  final CharacterRepository _characterRepository;
  final MessageRepository _messageRepository;
  final SettingsReader _settingsReader;

  /// `{{user}}` 昵称兜底（桌面 setting `user_name` 缺省 'User'）。
  static const _fallbackUserName = 'User';

  /// 角色缺失时 MD 标题占位名（桌面 `or '未知角色'`）。
  static const _unknownCharacterName = '未知角色';

  /// 角色信息段全空时的占位（桌面 `or '无'`）。
  static const _noCharacterInfo = '无';

  /// 导出对话为 JSON（结构照搬桌面 `export_conversation_json` 逐字段逐序）。
  ///
  /// 三层：`{conversation:{id,title,model_provider,model_name,created_at,
  /// updated_at}, character:{...}|null, messages:[{id,role,content,created_at}]}`；
  /// character 段为 9 字段投影（ConversationExportCharacter）；消息按
  /// `created_at` 升序 + id 兜底（对齐 MessageRepository.getMessages 既有排序）。
  /// 对话不存在 → `null`；无消息 → `messages: []`。
  ///
  /// 时间戳：`.toUtc().toIso8601String()`（UTC、带 Z、秒精度 `.000` 后缀）。
  /// 内容保留模板变量字面量（往返保真）。
  Future<ConversationExportResult?> exportJson(int conversationId) async {
    final conversation = await _loadConversationOrNull(conversationId);
    if (conversation == null) {
      return null;
    }
    final base = conversation.$1;
    final character = conversation.$2;

    final characterData = character == null ? null : _characterJson(character);
    final messages = await _messageRepository.getMessages(base.id);

    final content = jsonEncode({
      'conversation': {
        'id': base.id,
        'title': base.title,
        'model_provider': base.modelProvider,
        'model_name': base.modelName,
        'created_at': base.createdAt.toUtc().toIso8601String(),
        'updated_at': base.updatedAt.toUtc().toIso8601String(),
      },
      'character': characterData,
      'messages': [
        for (final message in messages)
          {
            'id': message.id,
            'role': message.role.value,
            'content': message.content,
            'created_at': message.createdAt.toUtc().toIso8601String(),
          },
      ],
    });

    return ConversationExportResult(
      fileName: _fileName(conversationId, character, 'json'),
      content: content,
    );
  }

  /// 导出对话为 Markdown（逐行照搬桌面 `export_conversation_markdown`）。
  ///
  /// 行序：`# 与 {角色名} 的对话` → `**角色信息**: {非空片段用 `；` 拼接}` →
  /// `**模型**: {provider}/{model}` → `**时间**: {本地 YYYY-MM-DD HH:MM}` →
  /// 空行 + `---` + 空行 → 按本地日期分组 `### YYYY-MM-DD`（跨日 `---` 分隔）→
  /// 每条 `**{role.value}**: {content}`。
  ///
  /// 角色信息段仅非空片段：description 无前缀、`人格: `/`场景: ` 带前缀；
  /// 模板变量 {{char}}/{{user}} 替换（昵称读设置缺省 'User'）；全空 → `无`。
  /// 控制字符（除 `\n`/`\t` 外 `\x00-\x1F`）替换为空格（A7 有意偏差）。
  Future<ConversationExportResult?> exportMarkdown(int conversationId) async {
    final conversation = await _loadConversationOrNull(conversationId);
    if (conversation == null) {
      return null;
    }
    final base = conversation.$1;
    final character = conversation.$2;

    final userNickname = await _userNickname();
    final characterName =
        character?.name ?? _unknownCharacterName;

    final infoParts = <String>[];
    if (character != null) {
      if (character.description.isNotEmpty) {
        infoParts.add(_sanitizeMarkdownText(applyTemplateVars(
          character.description,
          charName: character.name,
          userName: userNickname,
        )));
      }
      if (character.personality.isNotEmpty) {
        infoParts.add(
            '人格: ${_sanitizeMarkdownText(applyTemplateVars(character.personality, charName: character.name, userName: userNickname))}');
      }
      if (character.scenario.isNotEmpty) {
        infoParts.add(
            '场景: ${_sanitizeMarkdownText(applyTemplateVars(character.scenario, charName: character.name, userName: userNickname))}');
      }
    }
    final characterInfo =
        infoParts.isEmpty ? _noCharacterInfo : infoParts.join('；');

    final messages = await _messageRepository.getMessages(base.id);

    final lines = <String>[
      '# 与 ${_sanitizeMarkdownText(characterName)} 的对话',
      '',
      '**角色信息**: $characterInfo',
      '**模型**: ${base.modelProvider}/${base.modelName}',
      '**时间**: ${_formatLocalDateTime(base.createdAt)}',
      '',
      '---',
      '',
    ];

    String? currentDate;
    for (final message in messages) {
      final messageDate = _formatLocalDate(message.createdAt);
      if (messageDate != currentDate) {
        if (currentDate != null) {
          lines.add('---');
          lines.add('');
        }
        lines.add('### $messageDate');
        lines.add('');
        currentDate = messageDate;
      }
      lines.add(
          '**${message.role.value}**: ${_sanitizeMarkdownText(message.content)}');
      lines.add('');
    }

    return ConversationExportResult(
      fileName: _fileName(conversationId, character, 'md'),
      content: lines.join('\n'),
    );
  }

  /// 导出文件名中的角色名基（桌面 `character_export_filename` 语义）。
  ///
  /// 对话不存在 / 角色缺失 / 角色名为空 → 回退会话 id 字符串；否则返回角色名
  /// 并将空格折叠为下划线（下载文件名友好；另叠加 safeFileName 平台净化在
  /// 最终文件名上）。
  Future<String> characterExportBaseName(int conversationId) async {
    final conversation = await _loadConversationOrNull(conversationId);
    final character = conversation?.$2;
    if (conversation == null || character == null || character.name.isEmpty) {
      return conversationId.toString();
    }
    return character.name.replaceAll(' ', '_');
  }

  // ── 内部 ──

  /// 读取对话 + 其角色；对话不存在 → null。返回记录（对话必在，角色可为 null）。
  Future<(Conversation, Character?)?> _loadConversationOrNull(
      int conversationId) async {
    final conversation =
        await _conversationRepository.getConversation(conversationId);
    if (conversation == null) {
      return null;
    }
    final character = await _characterRepository
        .getCharacter(conversation.characterId);
    return (conversation, character);
  }

  /// character 段 9 字段投影（ConversationExportCharacter 字段序）。
  Map<String, dynamic> _characterJson(Character character) {
    return {
      'id': character.id,
      'name': character.name,
      'description': character.description,
      'personality': character.personality,
      'scenario': character.scenario,
      'first_mes': character.firstMes,
      'system_prompt': character.systemPrompt,
      'avatar': character.avatar,
      'temperature': character.temperature,
    };
  }

  /// 最终文件名：`{safeFileName(baseName)}.{extension}`。
  String _fileName(int conversationId, Character? character, String ext) {
    final characterName = _extractCharacterName(conversationId, character);
    return '${safeFileName(characterName)}.$ext';
  }

  /// 会话 id 兜底 / 角色名（供 safeFileName 净化前的语义源）。
  static String _extractCharacterName(int conversationId, Character? character) {
    if (character == null || character.name.isEmpty) {
      return conversationId.toString();
    }
    return character.name.replaceAll(' ', '_');
  }

  /// `{{user}}` 昵称：设置值非空优先，否则 'User'（SettingsReader 契约缺失返回
  /// 空串，兜底由消费方对齐 ConversationRepository._fallbackUserName）。
  Future<String> _userNickname() async {
    final raw = await _settingsReader.userName;
    return raw.isEmpty ? _fallbackUserName : raw;
  }

  /// 本地日期 `YYYY-MM-DD`（MD 分组头）。
  static String _formatLocalDate(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$month-$day';
  }

  /// 本地时间 `YYYY-MM-DD HH:MM`（MD 时间行）。
  static String _formatLocalDateTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${_formatLocalDate(dt)} $hour:$minute';
  }

  /// MD 控制字符净化：除 `\n`(0x0A)/`\t`(0x09) 外 `\x00-\x1F` 替换为空格
  /// （A7 有意偏差——桌面不净化；JSON 由 jsonEncode 天然转义安全）。
  static String _sanitizeMarkdownText(String text) {
    if (text.isEmpty) {
      return text;
    }
    return text.replaceAll(
      RegExp(r'[\x00-\x08\x0B-\x1F]'),
      ' ',
    );
  }
}