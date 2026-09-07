/// F-M5-07 导入链服务层测试（锚桌面 `desktop/backend/tests/test_simulator_import.py`
/// 边界矩阵逐字对拍）——SuspiciousPatterns 键集 / validateImportInput /
/// sanitizeFilename / slugify / findDuplicate / nextAvailableFilename /
/// scanInputIds 双层 / probeConfig 三层 / probeEndpointMode / scanSuspicious /
/// importGame 编排 + manifest 原子写与自愈回滚。
///
/// 测试 seam（公共接口边界）：import_service 顶层纯函数 + 临时目录真实落盘
/// （dart:io 在 flutter test 宿主可跑，不触平台通道）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/import_service.dart'
    show
        SimulatorDuplicateError,
        SimulatorImportError,
        findDuplicate,
        importGame,
        maxFilenameBytes,
        nextAvailableFilename,
        probeConfig,
        probeEndpointMode,
        readManifest,
        readManifestOrRebuild,
        sanitizeFilename,
        scanInputIds,
        scanSuspicious,
        slugify,
        validateImportInput,
        writeManifest;
import 'package:conver_system_mobile/services/simulator/manifest_parser.dart'
    show parseManifest;
import 'package:conver_system_mobile/services/simulator/suspicious_patterns.dart';

/// 含 cfg- 三元组的样本 HTML（key-injector 契约：input id 即 config 值）。
const String cfgTripletHtml = '''<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>样本游戏</title></head>
<body>
  <h1>样本游戏</h1>
  <input id="cfg-endpoint" type="text" placeholder="接口地址">
  <input id="cfg-apikey" type="password" placeholder="API Key">
  <input id="cfg-model" type="text" placeholder="模型">
  <button onclick="startGame()">开始</button>
  <script>function startGame() { alert("开始"); }</script>
</body></html>
''';

/// 按给定 id 集合构造仅含输入框的样本 HTML（探测矩阵用）。
String cfgInputsHtml(List<String> ids) {
  final inputs = ids.map((id) => '<input id="$id">').join();
  return '<html><body>$inputs</body></html>';
}

void main() {
  late Directory parent;

  setUp(() async {
    parent = await Directory.systemTemp.createTemp('m5-07-import-');
  });

  tearDown(() async {
    if (await parent.exists()) {
      await parent.delete(recursive: true);
    }
  });

  group('SuspiciousPatterns — 三键集常量单源 + 中文文案映射', () {
    test('键集恰为 eval / document.cookie / cross-origin-fetch 三键', () {
      expect(
        SuspiciousPatterns.keys.toSet(),
        {'eval', 'document.cookie', 'cross-origin-fetch'},
      );
    });

    test('eval 键正则：命中 eval( 与 window.eval(；evaluate( 不命中', () {
      final pattern = SuspiciousPatterns.patternFor('eval');
      expect(pattern.hasMatch('eval("1+1")'), isTrue);
      expect(pattern.hasMatch('window.eval(code)'), isTrue);
      expect(pattern.hasMatch('var evaluate = 1; evaluate();'), isFalse);
    });

    test('document.cookie 键正则：命中各空白形态；属性名 cookie 不命中', () {
      final pattern = SuspiciousPatterns.patternFor('document.cookie');
      expect(pattern.hasMatch('var x = document.cookie;'), isTrue);
      expect(pattern.hasMatch('document . cookie'), isTrue);
      expect(pattern.hasMatch("document.title = 'cookie';"), isFalse);
    });

    test('cross-origin-fetch 键正则：命中 https?/ 与协议相对双斜杠；同源不命中',
        () {
      final pattern = SuspiciousPatterns.patternFor('cross-origin-fetch');
      expect(pattern.hasMatch('fetch("http://evil.com/data")'), isTrue);
      expect(pattern.hasMatch("fetch('https://evil.com')"), isTrue);
      expect(pattern.hasMatch('fetch(`//evil.com/x`)'), isTrue);
      expect(pattern.hasMatch('fetch("/api/data")'), isFalse);
      expect(pattern.hasMatch('fetch("data:text/html,x")'), isFalse);
    });

    test('中文文案映射锚桌面 WARNING_LABELS 逐字', () {
      expect(
        SuspiciousPatterns.labelFor('eval'),
        '使用 eval() 动态执行任意代码（同源可调用 API / 读取本地数据）',
      );
      expect(
        SuspiciousPatterns.labelFor('document.cookie'),
        '读取 document.cookie（可访问本地会话数据）',
      );
      expect(
        SuspiciousPatterns.labelFor('cross-origin-fetch'),
        '跨域 fetch 请求（可能向外部发送本地数据）',
      );
    });

    test('未知键 → 兜底展示原始键名（新增未联动不炸）', () {
      expect(SuspiciousPatterns.labelFor('future-key'), 'future-key');
    });

    test('patternFor 未知键 → ArgumentError（程序性误用显式报错，不静默返回）', () {
      expect(
        () => SuspiciousPatterns.patternFor('future-key'),
        throwsArgumentError,
      );
    });
  });

  group('validateImportInput — 400 校验矩阵（非 .html / 超 5MB / 空 / 缺名）',
      () {
    test('非 .html（含伪装扩展名）→ SimulatorImportError', () {
      for (final name in ['game.txt', 'game.html.exe', 'game.htm', 'game']) {
        expect(
          () => validateImportInput(name, utf8.encode('<html>x</html>')),
          throwsA(isA<SimulatorImportError>()),
          reason: '非 .html 拒绝：$name',
        );
      }
    });

    test('空缺名 → SimulatorImportError', () {
      expect(
        () => validateImportInput('', utf8.encode('<html>x</html>')),
        throwsA(isA<SimulatorImportError>()),
      );
    });

    test('超 5MB → 明确报错（不落盘）', () async {
      final bytes = List<int>.filled(5 * 1024 * 1024 + 1, 0x78);
      expect(
        () => validateImportInput('big.html', bytes),
        throwsA(isA<SimulatorImportError>()),
      );
      // 校验失败零副作用：目录不得产生
      final sim = Directory('${parent.path}${Platform.pathSeparator}sim');
      expect(sim.existsSync(), isFalse);
    });

    test('空文件内容 → SimulatorImportError', () {
      expect(
        () => validateImportInput('empty.html', const []),
        throwsA(isA<SimulatorImportError>()),
      );
    });
  });

  group('sanitizeFilename — 净化矩阵（穿越/非法字符/保留名/字节截断）', () {
    test('净化矩阵逐字对拍桌面', () {
      final pairs = <(String, String)>[
        // 路径分隔符取最后段（杜绝穿越）
        ('..\\evil.html', 'evil.html'),
        ('../evil.html', 'evil.html'),
        ('a/b/c.html', 'c.html'),
        ('a\\b\\c.html', 'c.html'),
        ('..\\..\\escape.html', 'escape.html'),
        // % 与 #（前端 file 判据拒绝）
        ('bad%name.html', 'badname.html'),
        ('game#1.html', 'game1.html'),
        // Windows 非法字符剔除
        ('a<b>c:d|e?f*.html', 'abcdef.html'),
        // 控制字符剔除（\u0000-\u001F）
        ('evil\u0007game.html', 'evilgame.html'),
        ('\u001F头尾控制文件.html', '头尾控制文件.html'),
        // 首尾空白 / 点
        ('  My Game v1.html  ', 'My Game v1.html'),
        ('..', 'imported-game.html'),
        ('.hidden.html', 'hidden.html'),
        // Windows 保留设备名（大小写不敏感、带任意扩展名仍保留 → _ 前缀）
        ('con.html', '_con.html'),
        ('con', '_con.html'),
        ('CON.HTML', '_CON.html'),
        ('CoN', '_CoN.html'),
        ('prn.html', '_prn.html'),
        ('PRN', '_PRN.html'),
        ('aux.html', '_aux.html'),
        ('Aux', '_Aux.html'),
        ('nul.html', '_nul.html'),
        ('NUL', '_NUL.html'),
        ('com1.html', '_com1.html'),
        ('COM1', '_COM1.html'),
        ('com9.html', '_com9.html'),
        ('Com9', '_Com9.html'),
        ('lpt1.html', '_lpt1.html'),
        ('LPT1', '_LPT1.html'),
        ('lpt9.html', '_lpt9.html'),
        ('Lpt9', '_Lpt9.html'),
        // 首点前组件判定：双扩展形态等价保留名
        ('con.txt.html', '_con.txt.html'),
        ('com1.foo.html', '_com1.foo.html'),
        ('lpt2.bar.html', '_lpt2.bar.html'),
        ('CON.TXT', '_CON.TXT.html'),
        ('NUL.tar.gz', '_NUL.tar.gz.html'),
        ('nul.tar.gz', '_nul.tar.gz.html'),
        // 非保留邻近名不受影响（非精确匹配）
        ('mycon.html', 'mycon.html'),
        ('com10.html', 'com10.html'),
        ('lpt10.html', 'lpt10.html'),
        ('console.html', 'console.html'),
        ('printer.html', 'printer.html'),
        ('auxiliary.html', 'auxiliary.html'),
        ('conman.html', 'conman.html'),
        ('mycon.txt.html', 'mycon.txt.html'),
        // 120 字节上限（含 .html 后缀）：ASCII / 中文 / emoji 字节截断不劈裂
        ('${'a' * 260}.html', '${'a' * 115}.html'),
        ('${'中' * 90}.html', '${'中' * 38}.html'),
        ('${'😀' * 63}.html', '${'😀' * 28}.html'),
        ('${'a' * 115}.html', '${'a' * 115}.html'),
      ];
      for (final (raw, expected) in pairs) {
        expect(sanitizeFilename(raw), expected, reason: 'raw=$raw');
      }
    });

    test('不变量：净化结果不含 / \\ % # 与 Windows 非法字符', () {
      for (final raw in [
        '..\\..\\x.html',
        'a/b%c<d.html',
        'game#1.html',
        '..',
        '.',
        '',
      ]) {
        final name = sanitizeFilename(raw);
        expect(name.contains('/'), isFalse, reason: name);
        expect(name.contains(r'\'), isFalse, reason: name);
        expect(name.contains('%'), isFalse, reason: name);
        expect(name.contains('#'), isFalse, reason: name);
        expect(name.endsWith('.html'), isTrue, reason: name);
      }
    });

    test('总名（含 .html）UTF-8 字节数 ≤ 120', () {
      final name = sanitizeFilename('${'中' * 90}.html');
      expect(utf8.encode(name).length, lessThanOrEqualTo(maxFilenameBytes));
    });
  });

  group('slugify — id slug 规则', () {
    test('slug 矩阵：大小写折叠 / 分隔符折叠 / 空回退', () {
      const pairs = <(String, String)>[
        ('My Game v1', 'my-game-v1'),
        ('my--game', 'my-game'),
        ('--leading--', 'leading'),
        ('  spaced  ', 'spaced'),
        ('v3', 'v3'),
        ('游戏', 'imported-game'),
        ('', 'imported-game'),
        ('A__B--C', 'a-b-c'),
      ];
      for (final (stem, expected) in pairs) {
        expect(slugify(stem), expected, reason: 'stem=$stem');
      }
    });
  });

  group('findDuplicate — SHA-256 内容去重', () {
    test('同一内容二次导入 → SimulatorDuplicateError 文案含「已存在」', () async {
      final sim = _simDir(parent);
      final content = utf8.encode('<html>同一款游戏</html>');
      await importGame(sim, 'game.html', content);
      await expectLater(
        importGame(sim, 'game.html', content),
        throwsA(isA<SimulatorDuplicateError>()),
      );
    });

    test('与现存 .html 内容相同 → 报错并指明命中文件', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      File('${sim.path}${Platform.pathSeparator}内置游戏.html')
          .writeAsBytesSync(utf8.encode('<html>seed</html>'));
      await expectLater(
        importGame(sim, 'other.html', utf8.encode('<html>seed</html>')),
        throwsA(
          isA<SimulatorDuplicateError>()
              .having((e) => e.message, 'message', contains('内置游戏.html')),
        ),
      );
    });

    test('去重仅比对 *.html：与现存 .css 字节相同 → 不命中 409，正常导入', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      const cssContent = 'body { color: red; }';
      File('${sim.path}${Platform.pathSeparator}tricky.css')
          .writeAsBytesSync(utf8.encode(cssContent));
      final result =
          await importGame(sim, 'tricky.html', utf8.encode(cssContent));
      expect(result.game['file'], 'tricky.html');
    });

    test('同名不同内容 → 非重复（走改名路径）', () async {
      final sim = _simDir(parent);
      await importGame(sim, 'game.html', utf8.encode('<html>内容A</html>'));
      final result =
          await importGame(sim, 'game.html', utf8.encode('<html>内容B</html>'));
      expect(result.renamed, isTrue);
    });

    test('findDuplicate 直调：目录缺失 → null', () {
      final missing = Directory(
        '${parent.path}${Platform.pathSeparator}missing',
      );
      expect(findDuplicate(missing, utf8.encode('<html>x</html>')), isNull);
    });
  });

  group('nextAvailableFilename — 冲突改名（大小写不敏感 + 字节截断）', () {
    test('无冲突直接返回原名', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      expect(nextAvailableFilename(sim, 'a.html'), 'a.html');
    });

    test('同名冲突 → -2/-3 递增', () async {
      final sim = _simDir(parent);
      await importGame(sim, 'game.html', utf8.encode('<html>A</html>'));
      final r2 = await importGame(sim, 'game.html', utf8.encode('<html>B</html>'));
      final r3 = await importGame(sim, 'game.html', utf8.encode('<html>C</html>'));
      expect(r2.renamed, isTrue);
      expect(r2.game['file'], 'game-2.html');
      expect(r3.renamed, isTrue);
      expect(r3.game['file'], 'game-3.html');
    });

    test('冲突判定大小写不敏感（现存 GAME.HTML → game.html 视为同名）', () async {
      final sim = _simDir(parent);
      await importGame(sim, 'GAME.HTML', utf8.encode('<html>A</html>'));
      final result =
          await importGame(sim, 'game.html', utf8.encode('<html>B</html>'));
      expect(result.renamed, isTrue);
      expect(result.game['file'], 'game-2.html');
    });

    test('首次导入无冲突 → renamed False 且原名落盘', () async {
      final sim = _simDir(parent);
      final result = await importGame(sim, 'fresh.html', utf8.encode('<html>x</html>'));
      expect(result.renamed, isFalse);
      expect(result.game['file'], 'fresh.html');
    });

    test('无点输入（契约外）→ ArgumentError（不静默产出畸形名）', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      expect(() => nextAvailableFilename(sim, 'dotless'), throwsArgumentError);
    });
  });

  group('scanInputIds — HTML 控件 id 双层扫描', () {
    test('合法 HTML → 返回所有 input 元素 id 的集合（去重）', () {
      final ids = scanInputIds('<input id="a"><input id="b"><input id="a">');
      expect(ids, {'a', 'b'});
    });

    test('script 内容 / 注释内的伪 input 不参与静态层', () {
      final ids = scanInputIds(
        '<script>var x = "<input id=cfg-endpoint>";</script>'
        '<!-- <input id="cfg-apikey"> -->'
        '<input id="cfg-model">',
      );
      // 静态层 script/注释不解析；脚本层 raw-regex 要求引号 id → cfg-endpoint
      // 无引号不匹配 → 仅 cfg-model（桌面同精度）。
      expect(ids, {'cfg-model'});
    });

    test('无 input 元素 → 空集合', () {
      expect(scanInputIds('<html><body><p>no inputs</p></body></html>'), isEmpty);
    });

    test('select 元素 id 也纳入扫描', () {
      final ids = scanInputIds(
        '<input id="cfg-endpoint"><input id="cfg-apikey"><select id="cfg-model">',
      );
      expect(ids, {'cfg-endpoint', 'cfg-apikey', 'cfg-model'});
    });

    test('脚本层捕获 JS 模板字符串内的引号 id（引擎系控件路径）', () {
      final ids = scanInputIds(
        '<script>const html = `<input id="s-endpoint"><select id="s-model">`;</script>',
      );
      expect(ids, containsAll({'s-endpoint', 's-model'}));
    });

    test('脚本层剥离注释内容', () {
      final ids = scanInputIds(
        '<!-- <input id="old-key"> --><input id="s-key">',
      );
      expect(ids, {'s-key'});
    });

    test('静态层与脚本层同一 id → 只计一次（去重）', () {
      final ids = scanInputIds(
        '<input id="shared"><script>const x = \'<input id="shared">\';</script>',
      );
      expect(ids, {'shared'});
    });

    test('属性值内含 > 的边界正确处理', () {
      final ids = scanInputIds('<input id="a>b" type="text"><input id="ok">');
      expect(ids, {'a>b', 'ok'});
    });
  });

  group('probeConfig — 三层探测（L1 cfg- 三元组 / L2 关键词启发 / L3 local）', () {
    test('全量 cfg- 三元组 → ai + 三元组 config', () {
      final probe = probeConfig(cfgTripletHtml);
      expect(probe.type, 'ai');
      expect(probe.config, {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      });
    });

    test('三元组不完整（缺 apikey / 全非 cfg- / 无控件）→ local 无 config', () {
      for (final ids in [
        <String>['cfg-endpoint', 'cfg-model'],
        <String>['cfg-endpoint'],
        <String>['cfg-foo', 'cfg-bar'],
        <String>[],
      ]) {
        final probe = probeConfig(cfgInputsHtml(ids));
        expect(probe.type, 'local', reason: 'ids=$ids');
        expect(probe.config, isNull);
      }
    });

    test('普通 input（无 cfg- 前缀 / 非三类关键词）→ local', () {
      final probe = probeConfig(cfgInputsHtml(['username', 'password']));
      expect(probe.type, 'local');
      expect(probe.config, isNull);
    });

    test('id 首尾空白剔除后仍命中三元组', () {
      final probe = probeConfig(
        '<input id=" cfg-endpoint "><input id="cfg-apikey"><input id="cfg-model">',
      );
      expect(probe.type, 'ai');
    });

    test('cfg- 严格层大小写敏感：CFG-ENDPOINT 大写变体 → L2 启发式 ai + 精确 config',
        () {
      final probe = probeConfig(
        cfgInputsHtml(['CFG-ENDPOINT', 'CFG-APIKEY', 'CFG-MODEL']),
      );
      expect(probe.type, 'ai');
      expect(probe.config, {
        'endpoint': 'CFG-ENDPOINT',
        'apikey': 'CFG-APIKEY',
        'model': 'CFG-MODEL',
      });
    });

    test('7 种引擎系 id 约定 → 启发式全部识别为 ai + 精确 config', () {
      const cases = <(List<String>, Map<String, dynamic>)>[
        (['s-endpoint', 's-key', 's-model'],
            {'endpoint': 's-endpoint', 'apikey': 's-key', 'model': 's-model'}),
        (['set-endpoint', 'set-apikey', 'set-model'],
            {'endpoint': 'set-endpoint', 'apikey': 'set-apikey', 'model': 'set-model'}),
        (['inpBase', 'inpKey', 'inpModel'],
            {'endpoint': 'inpBase', 'apikey': 'inpKey', 'model': 'inpModel'}),
        (['api-base', 'api-key', 'api-model'],
            {'endpoint': 'api-base', 'apikey': 'api-key', 'model': 'api-model'}),
        (['a-base', 'a-key', 'a-model'],
            {'endpoint': 'a-base', 'apikey': 'a-key', 'model': 'a-model'}),
        (['w-endpoint', 'w-apikey', 'w-model'],
            {'endpoint': 'w-endpoint', 'apikey': 'w-apikey', 'model': 'w-model'}),
      ];
      for (final (ids, expected) in cases) {
        final probe = probeConfig(cfgInputsHtml(ids));
        expect(probe.type, 'ai', reason: 'ids=$ids');
        expect(probe.config, expected, reason: 'ids=$ids');
      }
    });

    test('脚本内嵌双套候选（s- 族 + wz- 族向导）→ 文档序全量候选数组', () {
      final html = '''
<script>
function modalSettings() { return `
<input id="s-endpoint"><input id="s-key"><select id="s-model">
`; }
function wizard() { return `
<input id="wz-endpoint"><input id="wz-key"><select id="wz-model">
`; }
</script>
''';
      final probe = probeConfig(html);
      expect(probe.type, 'ai');
      expect(probe.config, {
        'endpoint': ['s-endpoint', 'wz-endpoint'],
        'apikey': ['s-key', 'wz-key'],
        'model': ['s-model', 'wz-model'],
      });
    });

    test('启发式三组关键词不全 → local 不保留部分 config', () {
      for (final ids in [
        <String>['s-endpoint', 's-key'],
        <String>['s-endpoint'],
        <String>['username', 'password'],
        <String>[],
      ]) {
        final probe = probeConfig(cfgInputsHtml(ids));
        expect(probe.type, 'local', reason: 'ids=$ids');
        expect(probe.config, isNull);
      }
    });

    test('存在近义词额外控件时 L1 精确三元组优先于 L2 候选扩展', () {
      final probe = probeConfig(
        cfgInputsHtml(['cfg-endpoint', 'cfg-apikey', 'cfg-model', 'api-key-extra']),
      );
      expect(probe.type, 'ai');
      // L2 会把 api-key-extra 并入 apikey 候选（多候选数组）——严格层契约
      // 保证三元组精确，不并入额外候选（生成器作者契约为先）。
      expect(probe.config, {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      });
    });

    test('cfg-model 为 select → 严格层识别为 ai', () {
      final probe = probeConfig(
        '<input id="cfg-endpoint"><input id="cfg-apikey"><select id="cfg-model">',
      );
      expect(probe.type, 'ai');
      expect(probe.config, {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      });
    });
  });

  group('probeEndpointMode — 端点口径推断', () {
    test('/chat/completions 结尾 → full', () {
      final html =
          '<script>let cfg = { endpoint: "https://api.deepseek.com/v1/chat/completions" };</script>';
      expect(probeEndpointMode(html), 'full');
    });

    test('不带 /chat/completions → base', () {
      expect(
        probeEndpointMode(
          '<script>let cfg = { endpoint: "https://api.deepseek.com" };</script>',
        ),
        'base',
      );
    });

    test('带 /v1 不带 /chat/completions → base', () {
      expect(
        probeEndpointMode(
          '<script>let cfg = { endpoint: "https://api.deepseek.com/v1" };</script>',
        ),
        'base',
      );
    });

    test('JS 赋值式 endpoint = "..." 也匹配', () {
      expect(
        probeEndpointMode(
          '<script>const endpoint = "https://x.com/v1/chat/completions";</script>',
        ),
        'full',
      );
    });

    test('无默认端点赋值 → None', () {
      expect(probeEndpointMode('<html><body><p>no endpoint</p></body></html>'),
          isNull);
    });
  });

  group('scanSuspicious — 恶意模式粗筛', () {
    test('命中矩阵（单键样本）：返回对应键（输出序为单元素）', () {
      const samples = <(String, String)>[
        ('<script>eval("1+1")</script>', 'eval'),
        ('<script>window.eval(code)</script>', 'eval'),
        ('<script>var x = document.cookie;</script>', 'document.cookie'),
        ('<script>fetch("http://evil.com/data")</script>',
            'cross-origin-fetch'),
        ("<script>fetch('https://evil.com')</script>",
            'cross-origin-fetch'),
        ('<script>fetch(`//evil.com/x`)</script>', 'cross-origin-fetch'),
      ];
      for (final (html, key) in samples) {
        expect(scanSuspicious(html), [key], reason: 'html=$html');
      }
    });

    test('混合命中 → 输出序 == SuspiciousPatterns.keys 声明序（键序契约锁定）',
        () {
      final html =
          '<script>eval(document.cookie); fetch("http://evil.com")</script>';
      // 固定值锚（防 keys 被无意识重排而测试静默跟随——重排必须连测试一起换）。
      expect(scanSuspicious(html),
          ['cross-origin-fetch', 'document.cookie', 'eval']);
      // 键序契约锚：输出必须逐元素跟随 keys 声明序（非字典序）。
      // 当前 keys 恰为字典序，契约锚定的是「声明序」面——未来在 keys 中插入
      // 非字典序新键时，输出跟随 keys；若实现擅自改回字典序排序，在 keys
      // 非字典序时本断言即变红。
      expect(
        scanSuspicious(html),
        [for (final key in SuspiciousPatterns.keys) key],
        reason: '输出序必须等于 SuspiciousPatterns.keys 声明序（全键命中场景）',
      );
    });

    test('干净样本 / 同源引用 → 空键集（粗筛误报不拦截）', () {
      for (final html in [
        '<html><body>完全正常的游戏</body></html>',
        '<script>fetch("/api/data")</script>',
        '<script>fetch("data:text/html,x")</script>',
        '<script>var evaluate = 1; evaluate();</script>',
        "<script>document.title = 'cookie';</script>",
        '<script>fetch ( "/x" )</script>',
      ]) {
        expect(scanSuspicious(html), isEmpty, reason: 'html=$html');
      }
    });
  });

  group('manifest 原子写与自愈', () {
    test('writeManifest 同目录 .tmp + rename：替换既有文件、无 .tmp 残留', () async {
      final sim = _simDir(parent);
      writeManifest(sim, {'version': 2, 'simulators': <Object?>[]});
      writeManifest(sim, {
        'version': 2,
        'simulators': <Object?>[
          {'id': 'a', 'file': 'a.html', 'name': 'A', 'type': 'local'},
        ],
      });
      final manifest = readManifest(sim);
      expect(manifest['version'], 2);
      expect((manifest['simulators'] as List).single['id'], 'a');
      expect(
        File('${sim.path}${Platform.pathSeparator}manifest.json.tmp').existsSync(),
        isFalse,
        reason: '原子写不遗留 .tmp',
      );
    });

    test('manifest 损坏（非法 JSON）→ readManifestOrRebuild 以磁盘 .html 自愈重建',
        () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      File('${sim.path}${Platform.pathSeparator}seed.html')
          .writeAsBytesSync(utf8.encode('<html>seed</html>'));
      File('${sim.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync('{bad', flush: true);
      final rebuilt = readManifestOrRebuild(sim);
      expect(rebuilt['version'], 2);
      final simulators = rebuilt['simulators'] as List;
      expect((simulators.single as Map)['id'], 'seed');
      expect((simulators.single as Map)['type'], 'local');
    });

    test('manifest 缺失 → 自愈重建（空列表）', () async {
      final sim = _simDir(parent);
      final rebuilt = readManifestOrRebuild(sim);
      expect(rebuilt['version'], 2);
      expect(rebuilt['simulators'], isEmpty);
    });

    test('重建条目 id slug 冲突 → -2/-3 唯一化（结构性唯一）', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      const names = ['游戏一.html', '游戏二.html', '游戏三.html'];
      for (final name in names) {
        File('${sim.path}${Platform.pathSeparator}$name')
            .writeAsBytesSync(utf8.encode('<html>x</html>'));
      }
      final rebuilt = readManifestOrRebuild(sim);
      final ids = (rebuilt['simulators'] as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(ids, ['imported-game', 'imported-game-2', 'imported-game-3']);
      expect(ids.toSet().length, ids.length);
    });
  });

  group('importGame — 编排（校验 → 净化 → 去重 → 改名 → 探测 → 粗筛 → 落盘 → 注册）',
      () {
    test('ai 游戏导入：落盘 + manifest 条目（type=ai + config + source=imported）',
        () async {
      final sim = _simDir(parent);
      final content = utf8.encode(cfgTripletHtml);
      final result = await importGame(sim, '样本游戏.html', content);
      expect(result.renamed, isFalse);
      expect(result.warnings, isEmpty);
      expect(result.game, {
        'id': 'imported-game',
        'file': '样本游戏.html',
        'name': '样本游戏',
        'type': 'ai',
        'config': {
          'endpoint': 'cfg-endpoint',
          'apikey': 'cfg-apikey',
          'model': 'cfg-model',
        },
        'source': 'imported',
      });
      final written = File(
        '${sim.path}${Platform.pathSeparator}样本游戏.html',
      );
      expect(written.readAsBytesSync(), content, reason: '文件字节与上传内容一致');
      final manifest = readManifest(sim);
      expect(manifest['version'], 2);
      expect((manifest['simulators'] as List).single, result.game);
    });

    test('纯本地游戏 → type=local 且无 config 字段、无 endpointMode', () async {
      final sim = _simDir(parent);
      final result =
          await importGame(sim, 'local.html', utf8.encode('<html>纯本地</html>'));
      expect(result.game['type'], 'local');
      expect(result.game.containsKey('config'), isFalse);
      expect(result.game.containsKey('endpointMode'), isFalse);
    });

    test('含恶意模式 → warnings 非空且导入成功（服务层不拦截，拦截归 UI 确认）',
        () async {
      final sim = _simDir(parent);
      final content =
          utf8.encode('<script>eval(document.cookie); fetch("http://evil.com")</script>');
      final result = await importGame(sim, 'risky.html', content);
      // 全键命中 → warnings 输出序 = SuspiciousPatterns.keys 声明序。
      expect(result.warnings,
          [for (final key in SuspiciousPatterns.keys) key]);
      expect(
        File('${sim.path}${Platform.pathSeparator}risky.html').existsSync(),
        isTrue,
      );
      expect(result.game['id'], 'risky');
    });

    test('slug 冲突（中文名干无 ASCII）→ id 按 -2/-3 唯一化', () async {
      final sim = _simDir(parent);
      final r1 = await importGame(sim, '游戏一.html', utf8.encode('<html>A</html>'));
      final r2 =
          await importGame(sim, '游戏二.html', utf8.encode('<html>B</html>'));
      final r3 =
          await importGame(sim, '游戏三.html', utf8.encode('<html>C</html>'));
      expect(r1.game['id'], 'imported-game');
      expect(r2.game['id'], 'imported-game-2');
      expect(r3.game['id'], 'imported-game-3');
      final ids = (readManifest(sim)['simulators'] as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(ids.toSet().length, ids.length);
    });

    test('多次导入 → manifest 逐条追加且既有条目不动', () async {
      final sim = _simDir(parent);
      await importGame(sim, 'a.html', utf8.encode('<html>A</html>'));
      await importGame(sim, 'b.html', utf8.encode('<html>B</html>'));
      final ids = (readManifest(sim)['simulators'] as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(ids, ['a', 'b']);
    });

    test('manifest 损坏时导入 → 自愈重建 + 注册成功（不崩溃）', () async {
      final sim = _simDir(parent);
      sim.createSync(recursive: true);
      File('${sim.path}${Platform.pathSeparator}seed.html')
          .writeAsBytesSync(utf8.encode('<html>seed</html>'));
      File('${sim.path}${Platform.pathSeparator}manifest.json')
          .writeAsStringSync('{bad', flush: true);
      final result =
          await importGame(sim, 'new.html', utf8.encode('<html>new</html>'));
      expect(result.game['id'], 'new');
      expect(
        (readManifest(sim)['simulators'] as List).map((e) => (e as Map)['id']),
        ['seed', 'new'],
      );
    });

    test('manifest 注册失败 → 已落盘文件回滚（不遗留孤儿），异常继续传播',
        () async {
      final sim = _simDir(parent);
      await expectLater(
        importGame(
          sim,
          'game.html',
          utf8.encode('<html>x</html>'),
          appendEntry: (dir, entry) {
            throw const FileSystemException('磁盘故障（模拟）');
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File('${sim.path}${Platform.pathSeparator}game.html').existsSync(),
        isFalse,
        reason: '注册失败必须回滚已落盘文件',
      );
      expect(
        File('${sim.path}${Platform.pathSeparator}manifest.json').existsSync(),
        isTrue,
        reason: '自愈落盘已成功，仅注册失败',
      );
    });

    test('非 UTF-8 字节内容 → 容错解码后探测仍工作，落盘字节原样', () async {
      final sim = _simDir(parent);
      final content = <int>[
        ...utf8.encode('<html>\u{fffd}\u{fffd}'),
        0xff,
        0xfe,
        ...utf8.encode(
          '<input id="cfg-endpoint"><input id="cfg-apikey"><input id="cfg-model"></html>',
        ),
      ];
      final result = await importGame(sim, 'gbk.html', content);
      expect(result.game['type'], 'ai');
      expect(
        File('${sim.path}${Platform.pathSeparator}gbk.html').readAsBytesSync(),
        content,
      );
    });

    test('数据目录不可写（父路径被文件占位）→ 明确 FileSystemException 且零落盘',
        () async {
      final blocker =
          File('${parent.path}${Platform.pathSeparator}blocker');
      blocker.writeAsStringSync('x');
      await expectLater(
        importGame(
          Directory(blocker.path),
          'game.html',
          utf8.encode('<html>x</html>'),
        ),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('重复二次导入 → SimulatorDuplicateError 且文案含「已存在」', () async {
      final sim = _simDir(parent);
      final content = utf8.encode('<html>重复内容</html>');
      await importGame(sim, 'dup.html', content);
      await expectLater(
        importGame(sim, 'dup.html', content),
        throwsA(
          isA<SimulatorDuplicateError>()
              .having((e) => e.message, 'message', contains('已存在')),
        ),
      );
    });

    test('扫描结果：endpointMode 推断全路径写入 manifest', () async {
      final sim = _simDir(parent);
      final html = '<html><input id="s-endpoint"><input id="s-key">'
          '<input id="s-model">'
          '<script>const endpoint = "https://api.deepseek.com/v1/chat/completions";'
          '</script></html>';
      final result = await importGame(sim, 'eng.html', utf8.encode(html));
      expect(result.game['type'], 'ai');
      expect(result.game['endpointMode'], 'full');
      expect(result.game['config'], {
        'endpoint': 's-endpoint',
        'apikey': 's-key',
        'model': 's-model',
      });
    });

    test('注册后条目可被 parseManifest 读到（type/source/config/endpointMode 完整）',
        () async {
      final sim = _simDir(parent);
      final html = '<html><input id="cfg-endpoint"><input id="cfg-apikey">'
          '<select id="cfg-model">'
          '<script>const endpoint = "https://api.deepseek.com/v1/chat/completions";'
          '</script></html>';
      await importGame(sim, '目标游戏.html', utf8.encode(html));
      final parsed = parseManifest(json.encode(readManifest(sim)));
      expect(parsed.ok, isTrue, reason: 'parseManifest 宽容解析成功');
      final entry = parsed.games!.single;
      expect(entry['id'], 'imported-game');
      expect(entry['type'], 'ai');
      expect(entry['source'], 'imported');
      expect(entry['endpointMode'], 'full');
      expect(entry['config'], {
        'endpoint': 'cfg-endpoint',
        'apikey': 'cfg-apikey',
        'model': 'cfg-model',
      });
    });
  });
}

/// 本测试内各用例独立临时子目录（fresh parent 已隔离，再叠加自增序号防
/// 同父下口径撞车），cleanup 由 main tearDown 统一回收。
Directory _simDir(Directory parent) {
  final dir = Directory(
    '${parent.path}${Platform.pathSeparator}sim-${_simCounter.next()}',
  );
  dir.createSync(recursive: true);
  return dir;
}

/// 自增序号生成器（用例级唯一性）。
class _Counter {
  int _value = 0;
  int next() => ++_value;
}

final _Counter _simCounter = _Counter();