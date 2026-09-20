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
import 'package:conver_system_mobile/services/lorebook/lorebook_engine.dart'
    show InjectedSegment, sourceMemory, sourceWorld;
import 'package:conver_system_mobile/services/template_vars.dart';

export 'package:conver_system_mobile/services/lorebook/lorebook_engine.dart'
    show sourceMemory, sourceWorld;

/// 组装出的单条 LLM 消息 — role 恒为纯字符串 `system`/`user`/`assistant`。
typedef PromptMessage = ({String role, String content});

/// 带来源标注的组装分段（PD-04 debug 追溯）。
///
/// 与 [PromptMessage] 同构的 role/content 之上附加 [source]（来源枚举，取值见
/// [sourceCharacter] / [sourceWorld] / [sourceMemory] / [sourceMod] /
/// [sourceHistory] / [sourceUser] / [sourceNarrative]）。debug 路径消费；
/// 在线路径经 [buildMessages] 去掉 source 逐字节不变（零回归硬约束）。
typedef PromptSegment = ({String role, String content, String source});

/// 来源标注：角色静态字段注入段（system/scenario/PHI/expert_prompt/
/// mes_example/preset_dialogue）。
///
/// 桌面对应 `SOURCE_CHARACTER`（llm/prompt.py）；命名随仓库惯例 camelCase
/// 本地化（concerns/11 §3：`constant_identifier_names` lint）。
const String sourceCharacter = 'character';

// 说明：`sourceWorld` / `sourceMemory` 网络值（'world'/'memory'）的单一
// 定义在 `lorebook/lorebook_engine.dart`（InjectedSegment.source 契约），
// 本文件经 import + export 透出，避免双份字面量漂移。

/// 来源标注：prompt 区 Mod 注入（桌面 `SOURCE_MOD`）；**移动端本批仅占位
/// 常量、零产出**（Mod 挂载层 MD 未落地，组装产物绝不产生 mod 来源）。
const String sourceMod = 'mod';

/// 来源标注：历史消息。
const String sourceHistory = 'history';

/// 来源标注：当前用户输入。
const String sourceUser = 'user';

/// 来源标注：[叙述风格] 注入段。
const String sourceNarrative = 'narrative';

/// 角色纯数据容器（不含 DB 依赖），供 Prompt 组装使用。
///
/// 对齐桌面 `prompt.py::CharacterData`：
/// - [name]: 角色名称（`{{char}}` 模板变量来源）
/// - [systemPrompt]: 覆盖式系统提示词（优先于 [personality]）
/// - [personality]: 人格设定（[systemPrompt] 为空时回退）
/// - [scenario]: 场景设定（组装为 `[场景设定]\n...` 的 system 消息）
/// - [mesExample]: 对话范例（few-shot，`<START>` 分隔多轮）
/// - [postHistoryInstructions]: 历史后指令（历史之后、当前输入之前）
/// - [promptMode]: 组装模式（`simple`=结构化组装；`expert`=整段
///   [expertPrompt] 替代 system_prompt/personality、scenario、
///   post_history_instructions 三处——桌面 PD-5，NPD-04）
/// - [expertPrompt]: 专家模式整段 system prompt（仅 `promptMode == 'expert'`
///   且非空时生效）
class CharacterData {
  /// [name] 必填，其余字段默认空串（与桌面 dataclass 默认对齐）。
  const CharacterData({
    required this.name,
    this.systemPrompt = '',
    this.personality = '',
    this.scenario = '',
    this.mesExample = '',
    this.postHistoryInstructions = '',
    this.promptMode = 'simple',
    this.expertPrompt = '',
  });

  final String name;
  final String systemPrompt;
  final String personality;
  final String scenario;
  final String mesExample;
  final String postHistoryInstructions;

  /// 组装模式（`simple`/`expert`，缺省 `simple`）。
  final String promptMode;

  /// 专家模式整段 system prompt（缺省空串；仅 expert 且非空时生效）。
  final String expertPrompt;
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
/// [extraVars] 为用户自定义注入变量（工单 04 / spec §U-3，mobile 新增），
/// 消息内容中的 `{{key}}` 一并替换。
List<PromptMessage> parseMesExample(
  String mesExample, {
  String userName = 'User',
  String charName = 'Character',
  Map<String, String> extraVars = const {},
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
                userName: userName, charName: charName, extraVars: extraVars),
          ));
        }
      } else if (line.startsWith('{{char}}')) {
        final content = _contentAfter(line, '{{char}}');
        if (content.isNotEmpty) {
          messages.add((
            role: 'assistant',
            content: applyTemplateVars(content,
                userName: userName, charName: charName, extraVars: extraVars),
          ));
        }
      }
    }
  }

  return messages;
}

/// 组装发送给 LLM 的消息列表（纯函数，无 DB 依赖）。
///
/// 对齐桌面 `prompt.py::build_messages` 的组装顺序（WL-03 起含世界书注入，
/// NPD-02 起含预设对话注入，NPD-04 起含专家模式分流；PD-04 起组装核心抽为
/// 共享私有 `_assemble`，本函数与 [buildMessagesWithSource] 同核）：
/// 0. world["before_char"] 注入块（逐条 system，最高优先级——system 首条之前；
///    移动端无 before_char 概念，对齐桌面 `_assemble` 步骤 0）
/// 1. system prompt（[CharacterData.systemPrompt] 优先，否则 personality）；
///    expert 模式以 [CharacterData.expertPrompt] 单条替代 1/2/5 三处结构化注入
/// 2. scenario（作为 `[场景设定]\n...` 的 system 消息）；expert 模式不产出
/// 2.5 world["after_char"] 注入块（scenario 之后）
/// 2.75 world["system"] 合并单条 `[世界知识]`（多条以空行连接、按给定序——
///    调用方 [LorebookEngine.buildWorldInjection] 已按 (order, id) 升序）
/// 3. mes_example（few-shot 示例）
/// 3.5 presetDialogue（非空时）经 parseMesExample 注入 user/assistant few-shot
/// 4. 历史消息（正序，滑窗截断：超过 `maxRounds * 2` 条取最后 `maxRounds * 2`
///    条；默认 `maxRounds = 30` → 窗口 60 条）
/// 5. post_history_instructions（system 消息；expert 模式跳过）
/// 6. 当前 user 输入（[appendCurrentInput] 为 true 时）
///
/// [promptMode] / [expertPrompt]（NPD-04，桌面 PD-5 逐字）：expert 且
/// expertPrompt 非空 → system 段仅一条 `applyTemplateVars(expertPrompt)`，
/// 无 scenario / PHI 独立 system；expert 且空 / 纯空白 → 回退 simple 结构化
/// 组装（安全兜底，不产出空 system）；非 expert 值一律走 simple。expert 分流
/// 只替代角色静态字段：before/after/world 世界书注入、[叙述风格]、mes_example、
/// 预设对话、history、user 全部照旧（注入段与模式分流正交）。
///
/// [appendCurrentInput] 为 false（重生成路径）的契约：
/// 不追加当前 user 输入；末条恢复为历史末条 user（待回复触发源）；因无 user
/// 末尾兜底而残留的尾随 PHI system 一并剥离（循环剥除末尾所有 system），
/// 保证末端无 system、触发 user 在列表中仅出现一次。世界书注入块全部位于
/// 头部（history 之前），尾随剥离不受影响。expert 模式无 PHI（步骤 5 跳过），
/// 剥离天然安全。
///
/// [world]（WL-03）：世界书注入块 `{before_char/after_char/system: [内容]}`，
/// 内容为引擎层做过模板变量替换的纯字符串；null / 空 map / 空列表 / 空或
/// 纯空白项均零注入——输出与改动前**逐字节一致**（零回归硬约束，验收 1）。
/// 空注入项过滤不产生空 system 消息（验收 3，不污染上下文）。
///
/// [narrativeStyle]（NPD-01）：叙述风格规则文本（桌面 `narrative_style`）。
/// 空 / 纯空白零注入——输出与不传 narrativeStyle 逐字节一致（零回归硬约束，
/// 验收 4）；非空时注入 `[叙述风格]\n...` system 段于 **after_char 之后、
/// [世界知识] 之前**（对齐桌面 `_assemble` 步骤 2.7，expert/simple 皆注入，
/// 因 after_char 不在 expert 替代范围）。
///
/// [presetDialogue]（NPD-02）：预设对话快照文本（桌面 `preset_dialogue`）。
/// 空 / 纯空白零注入——输出与不传 presetDialogue 逐字节一致（零回归硬约束，
/// 验收 3）；非空时经 [parseMesExample] 复用 few-shot 解析注入 user/assistant
/// 消息于 **mes_example 之后、history 之前**（对齐桌面 `_assemble` 步骤 3.5；
/// source=character——预设对话是角色提供的示范，与 mes_example 同源。
/// PD-04 起该来源语义落于 [buildMessagesWithSource] 的 source 标注）。
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
  Map<String, String> extraVars = const {},
  Map<String, List<String>>? world,
  String? narrativeStyle,
  String? presetDialogue,
}) {
  // PD-04：与 buildMessagesWithSource 共享同一 `_assemble` 组装核心（单一组装
  // 实现，不复制顺序）；纯字符串 world 项在核心内经 `_splitInjection` 归一为
  // sourceWorld 标注，此处丢弃 source 返回——content/role 序列逐字节不变。
  final segments = _assemble(
    character,
    history: history,
    userContent: userContent,
    maxRounds: maxRounds,
    userName: userName,
    appendCurrentInput: appendCurrentInput,
    extraVars: extraVars,
    world: world,
    narrativeStyle: narrativeStyle,
    presetDialogue: presetDialogue,
  );
  return [
    for (final s in segments) (role: s.role, content: s.content),
  ];
}

/// 组装发送给 LLM 的消息列表，逐条标注来源（PD-04 debug 追溯专用，只读见证）。
///
/// 与 [buildMessages] 共用同一组装核心 `_assemble`（单一组装实现，不复制顺序），
/// 仅多返回每条 [source]。世界书注入块额外接受带来源注入项（world/manual /
/// memory/auto，承载于 [InjectedSegment] 或其纯字符串等价），纯字符串项回退
/// 来源 [sourceWorld]（与 [buildMessages] 等价）。
///
/// 来源枚举见 [sourceCharacter] / [sourceWorld] / [sourceMemory] / [sourceMod] /
/// [sourceHistory] / [sourceUser] / [sourceNarrative]。
///
/// 参数契约逐字对齐 [buildMessages]：[world] 为 null / 空 map / 空列表 / 空或
/// 纯空白项均零注入；expert 分流、重生成路径剥离尾随 system、[叙述风格] 与
/// 预设对话注入位置全部同 [buildMessages]（content/role 序列逐条一致，验收 1）。
List<PromptSegment> buildMessagesWithSource(
  CharacterData character, {
  Iterable<HistoryMessage> history = const [],
  String userContent = '',
  int maxRounds = 30,
  String userName = 'User',
  bool appendCurrentInput = true,
  Map<String, String> extraVars = const {},
  Map<String, List<Object>>? world,
  String? narrativeStyle,
  String? presetDialogue,
}) {
  return _assemble(
    character,
    history: history,
    userContent: userContent,
    maxRounds: maxRounds,
    userName: userName,
    appendCurrentInput: appendCurrentInput,
    extraVars: extraVars,
    world: world,
    narrativeStyle: narrativeStyle,
    presetDialogue: presetDialogue,
  );
}

/// 消息列表组装核心（私有；[buildMessages] / [buildMessagesWithSource] 共用——
/// 单一组装实现，桌面 `prompt.py::_assemble` 逐字）。
///
/// 组装顺序与来源标注（对齐桌面 `_assemble`）：
/// 0. world["before_char"] 逐条 system（source 取自注入项）
/// 1. system prompt（expert：单条 expert_prompt；simple：system_prompt 或
///    personality）——source=character
/// 2. scenario `[场景设定]`——source=character
/// 2.5 world["after_char"] 逐条 system（source 取自注入项）
/// 2.7 [叙述风格]——source=narrative
/// 2.75 world["system"] 合并单条 `[世界知识]`——source 经
///    [_worldKnowledgeSource]（单一来源取之；混合回落 world）
/// 3. mes_example——source=character
/// 3.5 预设对话 few-shot——source=character
/// 4. 历史消息——source=history
/// 5. PHI——source=character（expert 跳过）
/// 6. 当前 user 输入——source=user（False 时剥离尾随 system）
List<PromptSegment> _assemble(
  CharacterData character, {
  Iterable<HistoryMessage> history = const [],
  String userContent = '',
  int maxRounds = 30,
  String userName = 'User',
  bool appendCurrentInput = true,
  Map<String, String> extraVars = const {},
  Map<String, List<Object>>? world,
  String? narrativeStyle,
  String? presetDialogue,
}) {
  // 空角色名回退 'Character'。
  final charName = character.name.isEmpty ? 'Character' : character.name;

  // WL-03 世界书注入块：null / 全空 → 空块零注入（输出与改动前逐字节一致）。
  final worldBlocks = world ?? const <String, List<Object>>{};
  final beforeChar = _filterInjection(worldBlocks['before_char']);
  final afterChar = _filterInjection(worldBlocks['after_char']);
  final knowledge = _filterInjection(worldBlocks['system']);

  final messages = <PromptSegment>[];

  // 0. before_char 注入块 — 逐条 system，位于 system prompt 首条之前
  //   （移动端无 before_char 概念，对齐桌面 _assemble 步骤 0）。
  for (final item in beforeChar) {
    messages.add((role: 'system', content: item.content, source: item.source));
  }

  // NPD-04 专家模式分流：expert 且 expertPrompt strip 后非空 → 以单条
  // expertPrompt（模板变量替换后）替代 1/2/5 三处结构化注入（system_prompt/
  // personality、scenario、post_history_instructions）——对齐桌面 `_assemble`
  // (character.prompt_mode == "expert" and bool(expert_prompt.strip())) 逐字；
  // expert + 空/纯空白 → 回退 simple 结构化组装（安全兜底，不产出空 system）。
  final expert =
      character.promptMode == 'expert' &&
      character.expertPrompt.trim().isNotEmpty;

  // 1. system prompt 区 — expert：单条替代；simple：system_prompt 优先，否则
  //    personality，scenario 作为补充 system 追加。
  if (expert) {
    messages.add((
      role: 'system',
      content: applyTemplateVars(
        character.expertPrompt,
        userName: userName,
        charName: charName,
        extraVars: extraVars,
      ),
      source: sourceCharacter,
    ));
  } else {
    // 1. system prompt（优先 system_prompt 字段，其次 personality）。
    final systemContent = character.systemPrompt.isNotEmpty
        ? character.systemPrompt
        : character.personality;
    messages.add((
      role: 'system',
      content: applyTemplateVars(
        systemContent,
        userName: userName,
        charName: charName,
        extraVars: extraVars,
      ),
      source: sourceCharacter,
    ));

    // 2. 场景设定 — 附加在 system prompt 后，作为补充上下文。
    if (character.scenario.isNotEmpty) {
      final scenario = applyTemplateVars(
        character.scenario,
        userName: userName,
        charName: charName,
        extraVars: extraVars,
      );
      messages.add((
        role: 'system',
        content: '[场景设定]\n$scenario',
        source: sourceCharacter,
      ));
    }
  }

  // 2.5 after_char 注入块 — scenario 之后（无 scenario 时紧随 system prompt）。
  for (final item in afterChar) {
    messages.add((role: 'system', content: item.content, source: item.source));
  }

  // 2.7 [叙述风格] system 段 — after_char 之后、[世界知识] 之前（NPD-01）。
  // 对齐桌面 `_assemble` 步骤 2.7：空/纯空白零注入（与不传 narrativeStyle
  // 输出逐字节一致）；内容原样保留（桌面 f-string 不做 trim，仅门控检查
  // strip）。expert/simple 皆注入（after_char 不在 expert 替代范围）。
  if (narrativeStyle != null && narrativeStyle.trim().isNotEmpty) {
    messages.add((
      role: 'system',
      content: '[叙述风格]\n$narrativeStyle',
      source: sourceNarrative,
    ));
  }

  // 2.75 [世界知识] 合并单条 system — 多条以空行连接（调用方已按 (order, id)
  // 升序；空注入项过滤后不产生空 system 消息）。来源：单一来源取之，混合
  // world/memory 回落 world（桌面 `_world_knowledge_source` 逐字）。
  if (knowledge.isNotEmpty) {
    messages.add((
      role: 'system',
      content: '[世界知识]\n'
          '${[for (final k in knowledge) k.content].join('\n\n')}',
      source: _worldKnowledgeSource([for (final k in knowledge) k.source]),
    ));
  }

  // 3. 对话范例（mes_example）— few-shot 示例。
  if (character.mesExample.isNotEmpty) {
    messages.addAll(
      parseMesExample(
        character.mesExample,
        userName: userName,
        charName: charName,
        extraVars: extraVars,
      ).map(
        (m) => (role: m.role, content: m.content, source: sourceCharacter),
      ),
    );
  }

  // 3.5 预设对话 few-shot 注入（NPD-02）— mes_example 之后、history 之前。
  // 对齐桌面 `_assemble` 步骤 3.5：空/纯空白零注入（与不传 presetDialogue
  // 输出逐字节一致——验收 3 零回归）；非空时经 parseMesExample 复用 few-shot
  // 解析（模板变量替换、<START> 多轮分隔），source=character（预设对话是角色
  // 提供的示范，与 mes_example 同源，沿用 SOURCE_CHARACTER）。
  if (presetDialogue != null && presetDialogue.trim().isNotEmpty) {
    messages.addAll(
      parseMesExample(
        presetDialogue,
        userName: userName,
        charName: charName,
        extraVars: extraVars,
      ).map(
        (m) => (role: m.role, content: m.content, source: sourceCharacter),
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
    messages.add((
      role: _roleStr(msg.role),
      content: msg.content,
      source: sourceHistory,
    ));
  }

  // 5. 历史后指令 — 附加在历史消息之后、当前输入之前。expert 模式跳过
  //（PHI 在替代面之内——桌面 `_assemble` `if not expert and ...` 逐字）。
  if (!expert && character.postHistoryInstructions.isNotEmpty) {
    final phi = applyTemplateVars(
      character.postHistoryInstructions,
      userName: userName,
      charName: charName,
      extraVars: extraVars,
    );
    messages.add((role: 'system', content: phi, source: sourceCharacter));
  }

  // 6. 当前输入（False 时不追加，并剥离全部尾随 system／PHI）。
  if (appendCurrentInput) {
    final content = applyTemplateVars(
      userContent,
      userName: userName,
      charName: charName,
      extraVars: extraVars,
    );
    messages.add((role: 'user', content: content, source: sourceUser));
  } else {
    // 重生成路径：末条须为历史末条 user（触发源）。无当前 user 末尾兜底时，
    // 步骤 5 的 PHI（system）会成为末条，故先剥离全部尾随 system。
    while (messages.isNotEmpty && messages.last.role == 'system') {
      messages.removeLast();
    }
  }

  return messages;
}

/// 过滤注入块中的空 / 纯空白内容（对齐桌面 `_filter_injection`：`content and
/// content.strip()`）——空注入项不产生空 system 消息，不污染上下文。
///
/// 注入项可为纯字符串（来源回退 [sourceWorld]）或携带来源的
/// [InjectedSegment]（`world`/`memory`）；返回 `(content, source)` 记录列表，
/// 保持给定序。
List<({String content, String source})> _filterInjection(List<Object>? items) {
  final result = <({String content, String source})>[];
  for (final item in items ?? const <Object>[]) {
    final split = _splitInjection(item);
    if (split.content.trim().isNotEmpty) {
      result.add(split);
    }
  }
  return result;
}

/// 注入项 → `(content, source)`：纯字符串回退来源 world（桌面
/// `_split_injection` 逐字）；[InjectedSegment] 携带自身来源。
({String content, String source}) _splitInjection(Object item) {
  if (item is InjectedSegment) {
    return (content: item.content, source: item.source);
  }
  return (content: item as String, source: sourceWorld);
}

/// `[世界知识]` 合并块的来源判定（桌面 `_world_knowledge_source` 逐字）：
/// 单一来源取其之；world/memory 混合（或其它多源）回落 world（文档化兜底——
/// 内容一致性不受来源标注影响，debug 只见证不改线上）。
String _worldKnowledgeSource(List<String> sources) {
  final distinct = sources.toSet();
  if (distinct.length == 1) {
    return sources.first;
  }
  return sourceWorld;
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