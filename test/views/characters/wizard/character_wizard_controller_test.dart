/// WizardController 状态机契约（工单 M3-02a 验收 1/2/3/5/6/7）。
///
/// 语义锚点（spec §Implementation Decisions 6 步向导 + 桌面
/// character-wizard.js：validateStep / _applyCharacterData / handleSave）：
/// - 六步 next / prev（AppBar 返回 = 上一步）/ cancel 零副作用；步骤①未选
///   方式 next 被拦「请选择一种创建方式」；
/// - manual 选中直接跳步骤③（步骤②不出现）；import / template 进入步骤②
///   占位页（本票放行，M3-02b 交付模板网格 / 导入真 UI）；
/// - 校验门：步骤③ name 空 / 纯空白 → 「角色名称不能为空」；其余字段可选；
/// - selectTemplate 填充（对齐桌面 `_applyCharacterData`），手动编辑不被
///   模板回填覆盖；温度默认 0.7 / 0–2 / step 0.05 / toFixed(2) 显示；
/// - save：组装 payload → `CharacterRepository.createCharacter`（creator 恒空）
///   → 成功 true；失败可重试零副作用。
///
/// 测试 seam（spec Testing Decisions）：真实「控制器 + 内存 drift 库」，
/// 不 mock 仓储内部。
library;

import 'dart:async';

import 'package:conver_system_mobile/data/database/app_database.dart'
    show AppDatabase, Character, CharactersCompanion;
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/document_parse_service.dart';
import 'package:conver_system_mobile/services/llm/errors.dart'
    show DocParseError, LLMError;
import 'package:conver_system_mobile/services/llm/llm_provider.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/views/characters/wizard/character_wizard_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_llm_provider.dart';
import '../../../helpers/in_memory_secret_store.dart';

/// createCharacter 必抛的仓储子类——命中「保存失败 → 可重试」路径。
class _ThrowingCreateRepository extends CharacterRepository {
  _ThrowingCreateRepository(super.db);

  @override
  Future<Character> createCharacter(CharactersCompanion data) {
    throw StateError('create failed');
  }
}

/// 受控挂起 LLM：`generate()` 挂起在 [gate] 上，由测试手动 `complete` 补全——
/// 模拟真实 LLM 网络调用挂起数秒（BLOCKING-1 回归：解析挂起中 dispose）。
class _GateLLMProvider extends LLMProvider {
  _GateLLMProvider(this.gate) : super(apiKey: 'test-key');

  /// 手动补全的返回 gate（补全值即 generate 返回值）。
  final Completer<String> gate;

  @override
  LLMError translateError(Object error) =>
      error is LLMError ? error : LLMError('fake API 调用失败: $error');

  @override
  Future<String> generate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) =>
      gate.future;

  @override
  Stream<String> streamGenerate({
    required List<LlmMessage> messages,
    int maxTokens = 2048,
    String? model,
  }) async* {}

  @override
  Future<void> testConnection({String? model}) async {}
}

/// 用内存 drift + 假 LLM 装配真实 [DocumentParseService]（真实 service + 假 LLM，
/// 锚 M4-04 装配先例）。
DocumentParseService _parseService(
  AppDatabase db,
  LLMProvider provider, {
  bool writeKey = true,
}) {
  final store = InMemorySecretStore();
  if (writeKey) {
    // 写 Key 走 SecretStore 槽位（不落库，测试假值）。
    store.write(key: SecretStore.claudeApiKeySlot, value: 'sk-test');
  }
  return DocumentParseService(
    settings: SettingsRepository(database: db, secretStore: store),
    providerFactory: FixedLLMProviderFactory(provider),
  );
}

void main() {
  late AppDatabase db;
  late CharacterRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CharacterRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('状态机 · 六步 + 回退 + manual 跳③（验收 1/2）', () {
    test('初始：step=1、mode=null、温度 0.7、字段空、未保存', () {
      final c = WizardController(characterRepository: repository);

      expect(c.step, 1);
      expect(c.mode, isNull);
      expect(c.temperature, 0.7);
      expect(c.name, isEmpty);
      expect(c.description, isEmpty);
      expect(c.personality, isEmpty);
      expect(c.tags, isEmpty);
      expect(c.saved, isFalse);
      expect(c.saving, isFalse);
      expect(c.error, isNull);
    });

    test('步骤①未选方式 next 被拦：「请选择一种创建方式」且 step 不动', () {
      final c = WizardController(characterRepository: repository);

      final ok = c.next();

      expect(ok, isFalse);
      expect(c.error, '请选择一种创建方式');
      expect(c.step, 1, reason: '校验失败 step 不动');
    });

    test('manual 选中直接跳步骤③（步骤②不出现）', () {
      final c = WizardController(characterRepository: repository);

      c.selectMode(WizardCreationMode.manual);

      expect(c.mode, WizardCreationMode.manual);
      expect(c.step, 3, reason: 'manual 直接跳③');
    });

    test('manual 回退从③直接回①（跳过②）', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      expect(c.step, 3);

      c.prev();

      expect(c.step, 1, reason: 'manual 步骤②不出现，回退跳过②');
    });

    test('manual 回退①后再次 next 直接跳③（不误入②，W2 真缺回归）', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.prev(); // ③ → ①
      expect(c.step, 1);

      final ok = c.next();

      expect(ok, isTrue);
      expect(c.step, 3,
          reason: 'manual 步骤②不出现——回退后再前进必须跳过②直达③');
    });

    test('import 选中 → 步骤①停留，next 进入步骤②并放行到③（步骤②无门）',
        () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.import);

      expect(c.mode, WizardCreationMode.import);
      expect(c.step, 1, reason: 'import 先在①停留（未跳步）');

      final ok = c.next();

      expect(ok, isTrue);
      expect(c.step, 2, reason: '进入步骤②');

      final ok2 = c.next();
      expect(ok2, isTrue);
      expect(c.step, 3, reason: 'import 步骤②放行（不受内容影响）→ 步骤③');
    });

    test('template 步骤②未选模板 → next 拦截 + error；已选 → 放行', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.template);
      c.next();

      expect(c.step, 2, reason: '进入步骤②');

      expect(c.next(), isFalse, reason: 'template 未选模板被拦');
      expect(c.step, 2, reason: '拦截不前进');
      expect(c.error, '请选择一个模板', reason: '拦截文案由 controller 承载');

      c.selectTemplate('senpai');
      expect(c.error, isNull, reason: '选中模板清错（F-18 收拢后 controller 持有）');
      expect(c.next(), isTrue, reason: '已选模板放行');
      expect(c.step, 3);
    });

    test('六步 next 推进到⑥；prev 逐级回退（AppBar 返回 = 上一步）', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('测试角色');

      expect(c.next(), isTrue); // ③→④
      expect(c.step, 4);
      expect(c.next(), isTrue); // ④→⑤
      expect(c.step, 5);
      expect(c.next(), isTrue); // ⑤→⑥
      expect(c.step, 6);
      expect(c.next(), isFalse, reason: '⑥无下一步（到末步）');
      expect(c.step, 6);

      c.prev(); // ⑥→⑤
      expect(c.step, 5);
      c.prev(); // ⑤→④
      expect(c.step, 4);
    });

    test('step=1 时 prev 零动作', () {
      final c = WizardController(characterRepository: repository);
      c.prev();
      expect(c.step, 1);
    });
  });

  group('校验门 · 步骤③ name（验收 3）', () {
    test('步骤③ name 空 → next 拦「角色名称不能为空」', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      expect(c.step, 3);

      final ok = c.next();

      expect(ok, isFalse);
      expect(c.error, '角色名称不能为空');
      expect(c.step, 3);
    });

    test('步骤③ name 纯空白 → 拦截', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('   ');

      final ok = c.next();

      expect(ok, isFalse);
      expect(c.error, '角色名称不能为空');
      expect(c.step, 3);
    });

    test('填 name 后通过校验进入④；description/personality 等均可选', () {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('测试角色');

      final ok = c.next();

      expect(ok, isTrue);
      expect(c.step, 4);
      expect(c.error, isNull, reason: 'description/personality 等可选字段不拦');
    });
  });

  group('温度 · 默认 0.7 / 0–2 / 两位小数（验收 6）', () {
    test('setTemperature 更新；越界裁剪到 [0, 2]', () {
      final c = WizardController(characterRepository: repository);

      c.setTemperature(1.25);
      expect(c.temperature, 1.25);

      c.setTemperature(9.0);
      expect(c.temperature, 2.0, reason: '上界裁剪 2.0');

      c.setTemperature(-3.0);
      expect(c.temperature, 0.0, reason: '下界裁剪 0.0');
    });

    test('formatTemperature 语义 = 两位小数（toFixed(2)）', () {
      expect(formatTemperature(0.7), '0.70');
      expect(formatTemperature(1.25), '1.25');
      expect(formatTemperature(2.0), '2.00');
      expect(formatTemperature(0), '0.00');
    });
  });

  group('splitTags · 中英文逗号（验收 3 标签语义）', () {
    test('中英逗号分隔 + trim + 空项过滤', () {
      expect(splitTags('冒险, 奇幻，可爱'), ['冒险', '奇幻', '可爱']);
      expect(splitTags('甲,,乙，'), ['甲', '乙']);
      expect(splitTags(''), isEmpty);
      expect(splitTags('  ,  ,  '), isEmpty);
    });
  });

  group('模板应用 · selectTemplate（验收 5）', () {
    test('selectTemplate 填充 name/description/personality/scenario/first_mes/tags',
        () {
      final c = WizardController(characterRepository: repository);

      c.selectTemplate('senpai');

      expect(c.selectedTemplateId, 'senpai');
      expect(c.name, '知性学姐');
      expect(c.description, '温柔体贴、学识渊博的学姐');
      expect(c.personality, contains('{{char}}'));
      expect(c.scenario, contains('{{char}}'));
      expect(c.firstMes, contains('你也在找这本书吗'));
      expect(c.tags, ['校园', '温柔', '学姐', '文学']);
    });

    test('模板应用后手动编辑不被模板回填覆盖', () {
      final c = WizardController(characterRepository: repository);
      c.selectTemplate('senpai');

      c.setName('自定义角色');
      c.selectTemplate('senpai'); // 再次应用同一模板不覆盖手动编辑

      expect(c.name, '自定义角色', reason: '手动编辑优先，模板不覆盖');
      expect(c.description, '温柔体贴、学识渊博的学姐');
    });

    test('未知模板 id → 零变化', () {
      final c = WizardController(characterRepository: repository);

      c.selectTemplate('nope');

      expect(c.selectedTemplateId, isNull);
      expect(c.name, isEmpty);
    });
  });

  group('逐字段 setter · 头像/场景/系统提示/开场白/范例（可选字段）', () {
    test('各 setter 写入并保留值（视图层输入透传语义）', () {
      final c = WizardController(characterRepository: repository);

      c.setAvatar('https://example.com/a.png');
      c.setScenario('场景描述');
      c.setSystemPrompt('系统提示');
      c.setFirstMes('你好，{{user}}');
      c.setMesExample('<START> 示例');

      expect(c.avatar, 'https://example.com/a.png');
      expect(c.scenario, '场景描述');
      expect(c.systemPrompt, '系统提示');
      expect(c.firstMes, '你好，{{user}}');
      expect(c.mesExample, '<START> 示例');
    });

    test('再次手动编辑不被模板回填覆盖（各可选字段）', () {
      final c = WizardController(characterRepository: repository);
      c.selectTemplate('wanderer');
      c.setScenario('我改的场景');
      c.setSystemPrompt('我改的提示');
      c.setFirstMes('我改的开场白');
      c.setMesExample('我改的范例');
      c.setAvatar('ex');

      c.selectTemplate('wanderer'); // 再次应用不覆盖手动编辑

      expect(c.scenario, '我改的场景');
      expect(c.systemPrompt, '我改的提示');
      expect(c.firstMes, '我改的开场白');
      expect(c.mesExample, '我改的范例');
      expect(c.avatar, 'ex');
    });
  });

  group('保存 · createCharacter（验收 7）', () {
    test('组装 payload 落库：creator 恒空，created_at/updated_at 由仓储赋值',
        () async {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('保存我');
      c.setDescription('一句话简介');
      c.setPersonality('性格描述');
      c.setTags(['标签1', '标签2']);
      c.setTemperature(0.8);
      expect(c.next(), isTrue); // ③→④
      expect(c.next(), isTrue); // ④→⑤
      expect(c.next(), isTrue); // ⑤→⑥

      final ok = await c.save();

      expect(ok, isTrue);
      expect(c.saved, isTrue);
      expect(c.error, isNull);
      final rows = await repository.listCharacters();
      expect(rows, hasLength(1));
      final char = rows.single.character;
      expect(char.name, '保存我');
      expect(char.creator, '', reason: 'creator 恒空');
      expect(char.createdAt, isNotNull, reason: 'created_at 由仓储层赋值');
      expect(char.updatedAt, isNotNull, reason: 'updated_at 由仓储层赋值');
    });

    test('保存时 name 空（最终校验）→ 拦且不落库', () async {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);

      final ok = await c.save();

      expect(ok, isFalse);
      expect(c.error, '角色名称不能为空');
      expect(c.saved, isFalse);
      expect(await repository.listCharacters(), isEmpty);
    });

    test('失败可重试且零副作用', () async {
      final failing = WizardController(
        characterRepository: _ThrowingCreateRepository(db),
      );
      failing.selectMode(WizardCreationMode.manual);
      failing.setName('重试我');

      final ok = await failing.save();

      expect(ok, isFalse);
      expect(failing.saving, isFalse, reason: '失败后复位 saving，可重试');
      expect(failing.error, contains('保存失败'));
      expect(await repository.listCharacters(), isEmpty,
          reason: '失败零副作用（未落库）');

      // 换正常仓储后重试成功。
      final retry = WizardController(characterRepository: repository);
      retry.selectMode(WizardCreationMode.manual);
      retry.setName('重试我');
      expect(await retry.save(), isTrue);
      expect((await repository.listCharacters()).single.character.name,
          '重试我');
    });
  });

  group('取消 · 零副作用（验收 1）', () {
    test('cancel 后不落库，状态复位', () async {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.manual);
      c.setName('取消我');
      c.setTemperature(1.1);

      c.cancel();

      expect(await repository.listCharacters(), isEmpty, reason: '取消不落库');
      expect(c.step, 1);
      expect(c.mode, isNull);
      expect(c.name, isEmpty, reason: '表单复位');
      expect(c.saved, isFalse);
    });
  });

  group('AI 智能解析 · parse()（工单 M4-05 验收 3/4/5）', () {
    test('成功：跳步骤③ + 解析结果预填表单（8 字段落位）', () async {
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, FakeLLMProvider(tokens: [
          '{"name": "艾莉亚", "description": "森林小狐狸", "personality": "活泼", '
          '"scenario": "森林", "first_mes": "你好，{{user}}", '
          '"mes_example": "<START> 示例", "system_prompt": "你是小狐狸", '
          '"post_history_instructions": "保持人设", "tags": ["冒险", "奇幻"], '
          '"creator": "作者"}',
        ])),
      );
      c.selectMode(WizardCreationMode.import);
      expect(c.step, 1);
      c.next(); // ①→②
      expect(c.step, 2);
      c.setParseText('角色设定文档……');

      final ok = await c.parse();

      expect(ok, isTrue);
      expect(c.step, 3, reason: '解析成功自动跳步骤③');
      expect(c.parsing, isFalse);
      expect(c.parseError, isNull);
      // parse 结果 8 个表单字段落位（postHistoryInstructions / creator 不预填表单）。
      expect(c.name, '艾莉亚');
      expect(c.description, '森林小狐狸');
      expect(c.personality, '活泼');
      expect(c.scenario, '森林');
      expect(c.firstMes, '你好，{{user}}');
      expect(c.mesExample, '<START> 示例');
      expect(c.systemPrompt, '你是小狐狸');
      expect(c.tags, ['冒险', '奇幻']);
      // temperature 保持向导默认 0.7（其余缺省于 save 时经 CharacterDraft 补全）。
      expect(c.temperature, 0.7);
    });

    test('成功：解析后再手动编辑（步骤③可微调）', () async {
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, FakeLLMProvider(tokens: [
          '{"name": "艾莉亚", "personality": "解析的人格"}',
        ])),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');
      expect(await c.parse(), isTrue);

      c.setName('微调后名称');

      expect(c.name, '微调后名称');
      expect(c.personality, '解析的人格', reason: '未手动编辑字段保留解析值');
    });

    test('解析后保存：postHistoryInstructions 随保存落库（parse 链解耦后修复）',
        () async {
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, FakeLLMProvider(tokens: [
          '{"name": "艾莉亚", "personality": "活泼", '
          '"post_history_instructions": "保持人设"}',
        ])),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      expect(await c.parse(), isTrue);
      final ok = await c.save();

      expect(ok, isTrue);
      final rows = await repository.listCharacters();
      expect(rows, hasLength(1));
      expect(rows.single.character.postHistoryInstructions, '保持人设',
          reason: '解析出的历史后指令随保存落库（chat_service 对话时消费）');
    });

    test('解析成功但 name 空 → 跳③，步骤③必填校验兜底（B8）', () async {
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, FakeLLMProvider(tokens: [
          '{"description": "无名称解析", "personality": "p"}',
        ])),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');
      expect(await c.parse(), isTrue);
      expect(c.step, 3, reason: '解析成功跳步骤③');
      expect(c.name, isEmpty, reason: 'LLM 未提取 name → 草稿 name 空');

      // 步骤③ next 被「角色名称不能为空」门兜底。
      final ok = c.next();
      expect(ok, isFalse);
      expect(c.error, '角色名称不能为空');
      expect(c.step, 3);
    });

    test('失败：DocParseError 留步骤② + parseError 直出（不跳步）', () async {
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, FakeLLMProvider(tokens: ['这不是 JSON'])),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      final ok = await c.parse();

      expect(ok, isFalse);
      expect(c.step, 2, reason: '失败留步骤②');
      expect(c.parseError, 'LLM 返回了无法解析的响应，请重试或手动创建',
          reason: 'DocParseError 消息直出');
      expect(c.parsing, isFalse, reason: '失败后复位 parsing');
    });

    test('失败：未配置 API Key → 留步骤② + 文案直出', () async {
      final c = WizardController(
        characterRepository: repository,
        parseService:
            _parseService(db, FakeLLMProvider(tokens: const []), writeKey: false),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      final ok = await c.parse();

      expect(ok, isFalse);
      expect(c.step, 2);
      expect(c.parseError, '未配置 API Key，请先在设置中填写');
    });

    test('防连点：解析中再次 parse 返回 false 且只调一次服务', () async {
      final provider = FakeLLMProvider(
        tokens: ['{"name": "艾莉亚"}'],
        generateDelay: const Duration(milliseconds: 50),
      );
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, provider),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      final first = c.parse();
      // parsing 标志在 await 前同步置位——第二次调用应被防连点拦截。
      expect(c.parsing, isTrue, reason: '解析中 parsing 标志置位');
      final second = c.parse();

      expect(await second, isFalse, reason: '解析中再次 parse 被拦');
      expect(await first, isTrue);
      expect(provider.generateCallCount, 1, reason: '只调一次 LLM');
      expect(c.step, 3);
    });

    test('空文本 parse → false 不触服务（视图已禁用，防御）', () async {
      final provider = FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']);
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, provider),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();

      final ok = await c.parse();

      expect(ok, isFalse);
      expect(provider.generateCallCount, 0);
      expect(c.step, 2);
    });

    test('文本超 50000 → false + 文案，不触服务', () async {
      final provider = FakeLLMProvider(tokens: ['{"name": "艾莉亚"}']);
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, provider),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文' * (maxImportTextLength + 1));

      final ok = await c.parse();

      expect(ok, isFalse);
      expect(c.parseError, importTextTooLongError);
      expect(provider.generateCallCount, 0, reason: '超长不触 parse 服务');
      expect(c.step, 2);
    });

    test('未注入 parseService → parse 降级返回 false（不破坏既有装配）', () async {
      final c = WizardController(characterRepository: repository);
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      final ok = await c.parse();

      expect(ok, isFalse);
      expect(c.step, 2, reason: '降级留步骤②');
    });

    test('解析挂起中 dispose 不崩：续体不再 notify / 不跳步（BLOCKING-1 回归）',
        () async {
      final gate = Completer<String>();
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, _GateLLMProvider(gate)),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      // 解析挂起中（LLM 未返回）：防连点标志已置位。
      final future = c.parse();
      expect(c.parsing, isTrue, reason: '挂起中 parsing 置位');

      // 用户点 AppBar「取消」→ view dispose → 控制器 dispose。
      c.dispose();

      // LLM 返回后，已处置控制器的异步续体不得再 notifyListeners
      // （ChangeNotifier disposed 后 notify 触发 debug 断言崩溃）——await
      // 完成且不抛 FlutterError 即证明安全。
      gate.complete('{"name": "艾莉亚"}');

      final ok = await future;
      expect(ok, isFalse, reason: '已处置：续体放弃，不返回成功');
      expect(c.step, 2, reason: '已处置：不跳步骤③');
    });

    test('解析挂起中 dispose + 服务抛 DocParseError → 续体不 notify（BLOCKING-1 回归）',
        () async {
      final gate = Completer<String>();
      final c = WizardController(
        characterRepository: repository,
        parseService: _parseService(db, _GateLLMProvider(gate)),
      );
      c.selectMode(WizardCreationMode.import);
      c.next();
      c.setParseText('文档');

      final future = c.parse();
      expect(c.parsing, isTrue, reason: '挂起中 parsing 置位');

      c.dispose();

      // 预挂错误消费：completeError 时真实 await（service.parse 内部微任务链）
      // 尚未注册监听，否则 zone 会判为「未处理错误」误报——futures 支持多个
      // 监听，真实 await 仍会收到该错误。
      unawaited(gate.future.then<void>((_) {}, onError: (Object _) {}));

      // LLM 以解析错误返回：已处置控制器不得再 notify / 写 parseError。
      gate.completeError(
        DocParseError('LLM 返回了无法解析的响应，请重试或手动创建'),
      );

      final ok = await future;
      expect(ok, isFalse, reason: '已处置：错误续体放弃');
      expect(c.step, 2, reason: '已处置：不跳步骤③');
    });
  });
}
