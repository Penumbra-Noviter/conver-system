/// Prompt 组装 — LLM 消息列表的纯函数组装层（T01a 契约）。
///
/// 权威语义锚（只读，逐字对齐）：`desktop/backend/app/services/llm/prompt.py`。
/// 本模块无任何 I/O：角色数据与历史消息由调用方查好传入（纯数据输入，纯函数
/// 输出），因此可独立单测、可复用（多 Provider 上下文共用）。
///
/// 模板变量替换（{{user}} / {{char}}）复用 `services/template_vars.dart` 的
/// [applyTemplateVars]（先 user 后 char、无递归、空文本原样返回），本模块只
/// 组装、不另写第二份替换逻辑。
library;

import 'package:conver_system_mobile/data/database/tables.dart' show Role;
import 'package:conver_system_mobile/services/template_vars.dart';

/// 组装出的单条 LLM 消息 — role 恒为纯字符串 `system`/`user`/`assistant`。
typedef PromptMessage = ({String role, String content});

/// 角色纯数据容器（不含 DB 依赖），供 Prompt 组装使用。
///
/// 对齐桌面 `prompt.py::CharacterData`：
/// - [name]: 角色名称（`{{char}}` 模板变量来源）
/// - [systemPrompt]: 覆盖式系统提示词（优先于 [personality]）
/// - [personality]: 人格设定（[systemPrompt] 为空时回退）
/// - [scenario]: 场景设定（组装为 `[场景设定]\n...` 的 system 消息）
/// - [mesExample]: 对话范例（few-shot，`<START>` 分隔多轮）
/// - [postHistoryInstructions]: 历史后指令（历史之后、当前输入之前）
class CharacterData {
  /// [name] 必填，其余字段默认空串（与桌面 dataclass 默认对齐）。
  const CharacterData({
    required this.name,
    this.systemPrompt = '',
    this.personality = '',
    this.scenario = '',
    this.mesExample = '',
    this.postHistoryInstructions = '',
  });

  final String name;
  final String systemPrompt;
  final String personality;
  final String scenario;
  final String mesExample;
  final String postHistoryInstructions;
}

/// 历史消息条目 — 按桌面 `prompt.py::build_messages` 的历史项契约，每项至少
/// 含 `role` 与 `content` 属性（桌面测试用 SimpleNamespace 的结构化对应物）。
///
/// [role] 接受 [Role] 枚举（组装时归一为 `.value`）或纯字符串；[content] 为
/// 消息文本。
class HistoryMessage {
  const HistoryMessage({
    required this.role,
    required this.content,
  });

  /// 消息角色：可为 [Role]（取 `.value`）或纯字符串。
  final Object role;

  /// 消息内容。
  final String content;
}

/// 解析 mes_example 对话范例为 user/assistant 消息序列。
///
/// 对齐桌面 `prompt.py::parse_mes_example`：
/// - 空串 / 纯空白返回空列表；
/// - 按 `<START>` 分隔多轮范例；
/// - 每行以 `{{user}}:` / `{{char}}:` 开头 → user / assistant（`{{user}}`
///   映射 user，`{{char}}` 映射 assistant，SillyTavern V2 规范）；
/// - `lstrip(":")` 容错无空格 / 连续冒号，再整体 trim；
/// - 空内容行 / 空行 / 无前缀行跳过；
/// - 消息内容中的 `{{user}}` / `{{char}}` 模板变量一并替换。
///
/// [userName] / [charName] 缺省为 `User` / `Character`（与桌面签名一致）。
List<PromptMessage> parseMesExample(
  String mesExample, {
  String userName = 'User',
  String charName = 'Character',
}) {
  if (mesExample.isEmpty || mesExample.trim().isEmpty) {
    return const [];
  }

  final messages = <PromptMessage>[];
  // 按 <START> 分隔多轮范例（不含分隔标记的整段按单轮处理）。
  for (final rawBlock in mesExample.split('<START>')) {
    final block = rawBlock.trim();
    if (block.isEmpty) {
      continue;
    }
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('{{user}}')) {
        final content = _contentAfter(line, '{{user}}');
        if (content.isNotEmpty) {
          messages.add((
            role: 'user',
            content: applyTemplateVars(content,
                userName: userName, charName: charName),
          ));
        }
      } else if (line.startsWith('{{char}}')) {
        final content = _contentAfter(line, '{{char}}');
        if (content.isNotEmpty) {
          messages.add((
            role: 'assistant',
            content: applyTemplateVars(content,
                userName: userName, charName: charName),
          ));
        }
      }
    }
  }

  return messages;
}

/// 组装发送给 LLM 的消息列表（纯函数，无 DB 依赖）。
///
/// 对齐桌面 `prompt.py::build_messages` 的组装顺序：
/// 1. system prompt（[CharacterData.systemPrompt] 优先，否则 personality）
/// 2. scenario（作为 `[场景设定]\n...` 的 system 消息）
/// 3. mes_example（few-shot 示例）
/// 4. 历史消息（正序，滑窗截断：超过 `maxRounds * 2` 条取最后 `maxRounds * 2`
///    条；默认 `maxRounds = 30` → 窗口 60 条）
/// 5. post_history_instructions（system 消息）
/// 6. 当前 user 输入（[appendCurrentInput] 为 true 时）
///
/// [appendCurrentInput] 为 false（重生成路径）的契约：
/// 不追加当前 user 输入；末条恢复为历史末条 user（待回复触发源）；因无 user
/// 末尾兜底而残留的尾随 PHI system 一并剥离（循环剥除末尾所有 system），
/// 保证末端无 system、触发 user 在列表中仅出现一次。
///
/// [history] 每项至少含 `role` 与 `content`（[HistoryMessage]）；role 经
/// [_roleStr] 归一为纯字符串（[Role] 取 `.value`，纯字符串原样）。
List<PromptMessage> buildMessages(
  CharacterData character, {
  Iterable<HistoryMessage> history = const [],
  String userContent = '',
  int maxRounds = 30,
  String userName = 'User',
  bool appendCurrentInput = true,
}) {
  // 空角色名回退 'Character'。
  final charName = character.name.isEmpty ? 'Character' : character.name;

  // 1. system prompt（优先 system_prompt 字段，其次 personality）。
  final systemContent = character.systemPrompt.isNotEmpty
      ? character.systemPrompt
      : character.personality;
  final messages = <PromptMessage>[
    (
      role: 'system',
      content: applyTemplateVars(
        systemContent,
        userName: userName,
        charName: charName,
      ),
    ),
  ];

  // 2. 场景设定 — 附加在 system prompt 后，作为补充上下文。
  if (character.scenario.isNotEmpty) {
    final scenario = applyTemplateVars(
      character.scenario,
      userName: userName,
      charName: charName,
    );
    messages.add((role: 'system', content: '[场景设定]\n$scenario'));
  }

  // 3. 对话范例（mes_example）— few-shot 示例。
  if (character.mesExample.isNotEmpty) {
    messages.addAll(
      parseMesExample(
        character.mesExample,
        userName: userName,
        charName: charName,
      ),
    );
  }

  // 4. 历史消息（滑窗截断，保留最近 max_rounds 轮对话 = max_rounds*2 条）。
  final historyList = history.toList(growable: false);
  final window = maxRounds * 2;
  final windowed = historyList.length > window
      ? historyList.sublist(historyList.length - window)
      : historyList;
  for (final msg in windowed) {
    messages.add((role: _roleStr(msg.role), content: msg.content));
  }

  // 5. 历史后指令 — 附加在历史消息之后、当前输入之前。
  if (character.postHistoryInstructions.isNotEmpty) {
    final phi = applyTemplateVars(
      character.postHistoryInstructions,
      userName: userName,
      charName: charName,
    );
    messages.add((role: 'system', content: phi));
  }

  // 6. 当前输入（False 时不追加，并剥离全部尾随 system／PHI）。
  if (appendCurrentInput) {
    final content = applyTemplateVars(
      userContent,
      userName: userName,
      charName: charName,
    );
    messages.add((role: 'user', content: content));
  } else {
    // 重生成路径：末条须为历史末条 user（触发源）。无当前 user 末尾兜底时，
    // 步骤 5 的 PHI（system）会成为末条，故先剥离全部尾随 system。
    while (messages.isNotEmpty && messages.last.role == 'system') {
      messages.removeLast();
    }
  }

  return messages;
}

/// 取 `{{token}}:` 前缀之后的内容：先按 token 长度切片，再剥离开头全部冒号
///（对齐桌面 `lstrip(":")` 语义，容错无空格 / 连续冒号），最后整体 trim。
String _contentAfter(String line, String token) => line
    .substring(token.length)
    .replaceFirst(RegExp(r'^:*'), '')
    .trim();

/// 归一化消息角色：兼容 [Role] 枚举（取 `.value`）与纯字符串。
///
/// 对齐桌面 `prompt.py::_role_str`：优先 `.value`（枚举），否则按字符串
/// 输出。其他未知对象回退 `Object.toString()`。
String _roleStr(Object role) {
  if (role is Role) {
    return role.value;
  }
  if (role is String) {
    return role;
  }
  return role.toString();
}