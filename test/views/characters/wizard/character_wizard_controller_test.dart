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

import 'package:conver_system_mobile/data/database/app_database.dart'
    show AppDatabase, Character, CharactersCompanion;
import 'package:conver_system_mobile/data/repositories/character_repository.dart';
import 'package:conver_system_mobile/views/characters/wizard/character_wizard_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// createCharacter 必抛的仓储子类——命中「保存失败 → 可重试」路径。
class _ThrowingCreateRepository extends CharacterRepository {
  _ThrowingCreateRepository(super.db);

  @override
  Future<Character> createCharacter(CharactersCompanion data) {
    throw StateError('create failed');
  }
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

    test('import / template 选中 → 步骤①停留，next 进入步骤②占位页并放行',
        () {
      for (final mode in [
        WizardCreationMode.import,
        WizardCreationMode.template,
      ]) {
        final c = WizardController(characterRepository: repository);
        c.selectMode(mode);

        expect(c.mode, mode);
        expect(c.step, 1, reason: 'import/template 先在①停留（未跳步）');

        final ok = c.next();

        expect(ok, isTrue);
        expect(c.step, 2, reason: '进入步骤②（本票占位页，放行）');

        final ok2 = c.next();
        expect(ok2, isTrue);
        expect(c.step, 3, reason: '步骤②占位放行 → 步骤③');
      }
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
}
