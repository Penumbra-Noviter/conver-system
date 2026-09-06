/// 6 步角色创建向导控制器（M3-02a 切片：状态机 + 手动创建路径）。
///
/// 语义锚点（spec §Implementation Decisions 6 步向导 + 桌面
/// character-wizard.js：validateStep / _applyCharacterData / handleSave）：
/// - 单一 [ChangeNotifier] 状态机，非 PageView / Material Stepper：持有
///   创建方式 / 当前步 / 表单字段 / 选中模板 / 温度；
/// - 导航：next（分步校验门）/ prev（AppBar 返回 = 上一步）/ cancel（零
///   副作用，不落库）；manual 选中直接跳步骤③（步骤②不出现）；
/// - 校验门：步骤①未选方式拦「请选择一种创建方式」；步骤② template 未选
///   模板拦「请选择一个模板」（import 模式放行）；步骤③ name 空 /
///   纯空白拦「角色名称不能为空」；其余字段可选；
/// - 模板应用：selectTemplate 填充（对齐桌面 `_applyCharacterData`），已
///   手动编辑的字段不被模板回填覆盖；
/// - 保存：组装 payload → `CharacterRepository.createCharacter`（creator
///   恒空，created_at / updated_at 由仓储层赋值）→ 成功 `saved=true`；
///   失败复位 saving 可重试且零副作用。
///
/// 层级：ChangeNotifier 视图模型。唯一依赖 [CharacterRepository]（抽象
/// 仓储），不触碰数据库具体实现 / 平台存储（layer_boundary_test 契约）。
library;

import 'package:flutter/foundation.dart';

import '../../../data/character_templates.dart';
import '../../../data/database/app_database.dart' show CharactersCompanion;
import '../../../data/repositories/character_repository.dart';
import '../../../services/character_card.dart' show CharacterDraft;
import '../../../services/document_parse_service.dart'
    show DocParseResult, DocumentParseService;
import '../../../services/llm/errors.dart' show DocParseError;
import 'package:drift/drift.dart' show Value;

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 characters_controller.dart 惯例）。
// ignore_for_file: prefer_initializing_formals

/// 向导创建方式（对齐桌面 state.mode：import / template / manual）。
enum WizardCreationMode {
  /// 智能导入（步骤②占位；AI 解析随 M4）。
  import,

  /// 从模板开始（步骤②模板网格随 M3-02b）。
  template,

  /// 手动创建（选中直接跳步骤③）。
  manual,
}

/// 温度滑块配置（对齐桌面 `TEMP_SLIDER`：0–2 / step 0.05 / 默认 0.7）。
const double temperatureMin = 0;
const double temperatureMax = 2;
const double temperatureDefault = 0.7;

/// 温度两位小数显示（对齐桌面 `formatTemperature` 的 toFixed(2) 语义）。
String formatTemperature(double value) => value.toStringAsFixed(2);

/// import 文本长度上限（B10：超出拒绝解析）。
const int maxImportTextLength = 50000;

/// import 文本过长拒绝文案（B10 逐字）。
const String importTextTooLongError = '文本过长，最多 50000 字符';

/// 逗号分隔标签文本 → 标签数组（中英文逗号、trim、空项过滤；对齐桌面
/// `splitTags`）。
List<String> splitTags(String text) => text
    .split(RegExp(r'[,，]'))
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .toList();

/// 向导状态机：当前步 / 表单字段 / 选中模板 / 温度 / 保存状态。
///
/// 装配：入口（角色页「新建角色」）构造并注入 [CharacterRepository]；
/// 测试注入内存库仓储。保存走 [save]，cancel / 校验失败均零副作用。
class WizardController extends ChangeNotifier {
  /// [characterRepository] 保存落库数据源；[parseService] AI 智能解析依赖
  /// （M4-05 可选注入：null 时 [parse] 降级返回 false，不破坏既有装配语义）。
  WizardController({
    required CharacterRepository characterRepository,
    DocumentParseService? parseService,
  })  : _characterRepository = characterRepository,
        _parseService = parseService;

  final CharacterRepository _characterRepository;
  final DocumentParseService? _parseService;

  // ── 状态 ──
  int _step = 1;
  WizardCreationMode? _mode;
  String _name = '';
  String _description = '';
  String _avatar = '';
  String _personality = '';
  String _scenario = '';
  String _systemPrompt = '';
  String _firstMes = '';
  String _mesExample = '';
  List<String> _tags = const [];
  String? _selectedTemplateId;
  double _temperature = temperatureDefault;
  bool _saving = false;
  bool _saved = false;
  String? _error;

  /// import 解析文本（步骤② textarea 绑定）。
  String _parseText = '';

  /// AI 解析进行中标志（防连点 / 视图 loading）。
  bool _parsing = false;

  /// 最近一次 AI 解析错误消息（DocParseError 直出 / 超长拒绝文案）。
  String? _parseError;

  /// 控制器已处置标志：dispose 后异步续体（[parse] await 后）不再 notify /
  /// 不跳步——解析挂起中用户点「取消」触发的 BLOCKING-1 崩溃防护
  /// （ChangeNotifier disposed 后 notifyListeners 触发 debug 断言）。
  bool _disposed = false;

  /// 已手动编辑的字段名集合——selectTemplate 只填充未手动编辑的字段
  /// （验收 5：再次手动编辑不被模板回填覆盖）。
  final Set<String> _manualEdited = <String>{};

  /// 当前步骤（1–6）。
  int get step => _step;

  /// 创建方式（null = 未选）。
  WizardCreationMode? get mode => _mode;

  /// 选中模板 id（未选 null）。
  String? get selectedTemplateId => _selectedTemplateId;

  /// 角色名称（必填，步骤③校验）。
  String get name => _name;

  /// 一句话简介（可选）。
  String get description => _description;

  /// 头像 URL（可选；空 → 落库 null）。
  String get avatar => _avatar;

  /// 人格设定（可选）。
  String get personality => _personality;

  /// 场景设定（可选）。
  String get scenario => _scenario;

  /// 自定义 System Prompt（可选；空 → 使用人格设定）。
  String get systemPrompt => _systemPrompt;

  /// 开场白（可选）。
  String get firstMes => _firstMes;

  /// 对话范例（可选）。
  String get mesExample => _mesExample;

  /// 标签（非空列表可）。
  List<String> get tags => _tags;

  /// 温度（0–2，默认 0.7）。
  double get temperature => _temperature;

  /// 保存中标志（防重复提交）。
  bool get saving => _saving;

  /// 已成功保存（供视图弹回列表）。
  bool get saved => _saved;

  /// 最近一次校验 / 保存错误（null = 无）。
  String? get error => _error;

  /// import 解析文本（步骤② textarea 绑定）。
  String get parseText => _parseText;

  /// AI 解析进行中标志（防连点 / 视图 loading）。
  bool get parsing => _parsing;

  /// 最近一次 AI 解析错误消息（DocParseError 直出 / 超长拒绝文案）。
  String? get parseError => _parseError;

  /// 销毁：置 [ChangeNotifier.dispose] 并打已处置标志（异步续体据此退避）。
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ── 导航 ──

  /// 选择创建方式。
  ///
  /// manual 直接跳步骤③（步骤②不出现）；import / template 停在步骤①
  /// 待 [next] 进入步骤②占位页。
  void selectMode(WizardCreationMode mode) {
    _mode = mode;
    _error = null;
    _step = switch (mode) {
      WizardCreationMode.manual => 3,
      WizardCreationMode.import || WizardCreationMode.template => 1,
    };
    notifyListeners();
  }

  /// 校验当前步骤并前进到下一步；返回是否放行。
  ///
  /// 校验门：步骤①未选方式 / 步骤② template 未选模板 / 步骤③ name 空、
  /// 纯空白被拦；import 模式步骤②放行（不受内容影响）；步骤⑥为末步
  /// （next 返回 false）。
  bool next() {
    switch (_step) {
      case 1:
        if (_mode == null) {
          _error = '请选择一种创建方式';
          notifyListeners();
          return false;
        }
        break;
      case 2:
        if (_mode == WizardCreationMode.template &&
            _selectedTemplateId == null) {
          _error = '请选择一个模板';
          notifyListeners();
          return false;
        }
        break;
      case 3:
        if (_name.trim().isEmpty) {
          _error = '角色名称不能为空';
          notifyListeners();
          return false;
        }
        break;
      case 6:
        // 末步：无下一步（视图在⑥显示「保存角色」）。
        return false;
      default:
        break;
    }
    _error = null;
    // manual 模式步骤②不出现：从①前进（回退后再前进）直接跳③，
    // 与 prev() 从③回退到①的跳步语义对称（W2 增量审核真缺修复）。
    _step = (_mode == WizardCreationMode.manual && _step == 1) ? 3 : _step + 1;
    notifyListeners();
    return true;
  }

  /// 上一步（AppBar 返回 = 上一步）。manual 模式步骤②不出现，从③回退到①；
  /// step=1 时零动作。
  void prev() {
    if (_step <= 1) {
      return;
    }
    _step = (_mode == WizardCreationMode.manual && _step == 3) ? 1 : _step - 1;
    _error = null;
    notifyListeners();
  }

  /// 取消：零副作用（不落库），复位全部状态。
  void cancel() {
    _step = 1;
    _mode = null;
    _name = '';
    _description = '';
    _avatar = '';
    _personality = '';
    _scenario = '';
    _systemPrompt = '';
    _firstMes = '';
    _mesExample = '';
    _tags = const [];
    _selectedTemplateId = null;
    _temperature = temperatureDefault;
    _saving = false;
    _saved = false;
    _error = null;
    _parseText = '';
    _parsing = false;
    _parseError = null;
    _manualEdited.clear();
    notifyListeners();
  }

  // ── 表单字段（手动编辑标记 dirty，模板不再回填） ──

  void setName(String value) {
    _name = value;
    _manualEdited.add('name');
    notifyListeners();
  }

  void setDescription(String value) {
    _description = value;
    _manualEdited.add('description');
    notifyListeners();
  }

  void setAvatar(String value) {
    _avatar = value;
    _manualEdited.add('avatar');
    notifyListeners();
  }

  void setPersonality(String value) {
    _personality = value;
    _manualEdited.add('personality');
    notifyListeners();
  }

  void setScenario(String value) {
    _scenario = value;
    _manualEdited.add('scenario');
    notifyListeners();
  }

  void setSystemPrompt(String value) {
    _systemPrompt = value;
    _manualEdited.add('systemPrompt');
    notifyListeners();
  }

  void setFirstMes(String value) {
    _firstMes = value;
    _manualEdited.add('firstMes');
    notifyListeners();
  }

  void setMesExample(String value) {
    _mesExample = value;
    _manualEdited.add('mesExample');
    notifyListeners();
  }

  void setTags(List<String> value) {
    _tags = List<String>.unmodifiable(value);
    _manualEdited.add('tags');
    notifyListeners();
  }

  /// 温度设定（裁剪到 [0, 2]）。
  void setTemperature(double value) {
    _temperature = value.clamp(temperatureMin, temperatureMax).toDouble();
    notifyListeners();
  }

  // ── AI 智能解析（M4-05）──

  /// 更新 import 解析文本（步骤② textarea 绑定；不触发解析）。
  void setParseText(String value) {
    _parseText = value;
    notifyListeners();
  }

  /// AI 智能解析编排：`DocumentParseService.parse(parseText)` → 成功应用
  /// [DocParseResult] 预填草稿并跳步骤③；失败 / 超长留在步骤②并记录
  /// [parseError]（DocParseError 消息直出）。
  ///
  /// 边界（B10）：文本超 [maxImportTextLength] → 拒绝并提示，不触 parse 服务。
  /// 返回是否解析成功；[parseService] 未注入时降级返回 false（不抛）。
  Future<bool> parse() async {
    final service = _parseService;
    if (service == null) {
      _parseError = '解析服务不可用';
      notifyListeners();
      return false;
    }
    if (_parsing) {
      return false; // 防连点。
    }
    final text = _parseText.trim();
    if (text.isEmpty) {
      return false; // 空文本：视图已禁用按钮，防御。
    }
    if (text.length > maxImportTextLength) {
      _parseError = importTextTooLongError;
      notifyListeners();
      return false;
    }
    _parsing = true;
    _parseError = null;
    notifyListeners();
    try {
      final result = await service.parse(text);
      if (_disposed) {
        // 解析挂起中控制器已 dispose（用户取消）：续体退避，不 notify、
        // 不跳步、不写状态（BLOCKING-1 崩遗防护）。
        return false;
      }
      _applyParseResult(result);
      _parsing = false;
      _step = 3;
      notifyListeners();
      return true;
    } on DocParseError catch (e) {
      if (_disposed) {
        return false;
      }
      _parsing = false;
      _parseError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      if (_disposed) {
        return false;
      }
      _parsing = false;
      _parseError = '解析失败: $e';
      notifyListeners();
      return false;
    }
  }

  /// 应用 [DocParseResult] 预填草稿（经 [CharacterDraft.fromParseResult] 落位
  /// 16 字段；本控制器只承载向导表单字段，postHistoryInstructions 经
  /// fromParseResult 保留于草稿可落库）。
  void _applyParseResult(DocParseResult result) {
    final draft = CharacterDraft.fromParseResult(result);
    _name = draft.name;
    _description = draft.description;
    _personality = draft.personality;
    _scenario = draft.scenario;
    _systemPrompt = draft.systemPrompt;
    _firstMes = draft.firstMes;
    _mesExample = draft.mesExample;
    _tags = List<String>.unmodifiable(draft.tags);
    _selectedTemplateId = null;
    _manualEdited.clear();
  }

  // ── 模板应用 ──

  /// 应用 [CharacterTemplate]（对齐桌面 `_applyCharacterData`）。
  ///
  /// 只填充未被用户手动编辑过的字段（验收 5）；未知 id 零变化。
  void selectTemplate(String id) {
    CharacterTemplate? template;
    for (final t in characterTemplates) {
      if (t.id == id) {
        template = t;
        break;
      }
    }
    if (template == null) {
      return;
    }
    _selectedTemplateId = id;
    _error = null;
    _applyTemplate(template);
    notifyListeners();
  }

  void _applyTemplate(CharacterTemplate template) {
    if (!_manualEdited.contains('name')) {
      _name = template.name;
    }
    if (!_manualEdited.contains('description')) {
      _description = template.description;
    }
    if (!_manualEdited.contains('personality')) {
      _personality = template.personality;
    }
    if (!_manualEdited.contains('scenario')) {
      _scenario = template.scenario;
    }
    if (!_manualEdited.contains('firstMes')) {
      _firstMes = template.firstMes;
    }
    if (!_manualEdited.contains('mesExample')) {
      _mesExample = template.mesExample;
    }
    if (!_manualEdited.contains('systemPrompt')) {
      _systemPrompt = template.systemPrompt;
    }
    if (!_manualEdited.contains('tags')) {
      _tags = List<String>.unmodifiable(template.tags);
    }
  }

  // ── 保存 ──

  /// 组装 payload 落库（creator 恒空；created_at / updated_at 由仓储层
  /// 赋值）。最终校验 name 非空；成功 `saved=true` 返回 true；失败复位
  /// saving 返回 false（可重试且零副作用）。
  Future<bool> save() async {
    if (_name.trim().isEmpty) {
      _error = '角色名称不能为空';
      notifyListeners();
      return false;
    }
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await _characterRepository.createCharacter(
        CharactersCompanion(
          name: Value(_name.trim()),
          description: Value(_description.trim()),
          personality: Value(_personality.trim()),
          scenario: Value(_scenario.trim()),
          firstMes: Value(_firstMes.trim()),
          mesExample: Value(_mesExample.trim()),
          systemPrompt: Value(_systemPrompt.trim()),
          tags: Value(_tags),
          avatar: Value(_avatar.trim().isEmpty ? null : _avatar.trim()),
          creator: Value(''),
          temperature: Value(_temperature),
        ),
      );
      _saving = false;
      _saved = true;
      notifyListeners();
      return true;
    } catch (error) {
      _saving = false;
      _error = '保存失败: $error';
      notifyListeners();
      return false;
    }
  }
}
