/// F-M5-06 SaveSheet 底部半屏存档管理 widget 行为契约——bootstrap 相位（打开中/
/// WebView 不可用降级/超时）/ 游戏行渲染（键数·字符·wg 注记·无存档管理降级）/
/// 导出·导入·删除交互（确认弹窗 / toast / 操作后刷新）。
///
/// 测试 seam：注入 fake [SaveBridge]（extends 覆盖四方法，记录调用）+ 共享
/// 假件 `FakeWebViewCapabilityFactory`（生产 bootstrap 路径以假能力承载
/// evaluate 往返），永不触 webview_flutter 平台通道（U2 隔离）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/save_bridge.dart';
import 'package:conver_system_mobile/services/simulator/webview_capability.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/simulators/save_sheet.dart';

import '../../support/fake_local_storage_access.dart';
import '../../support/fake_web_view_capability.dart';

/// 行 fixture：存档游戏 / 无存档管理 / wg_ 族注记 / 正则多键。
final List<GameSaveSummary> _rows = const [
  GameSaveSummary(
    gameId: 'life-sim',
    name: '人生模拟器',
    keyCount: 1,
    totalChars: 3,
    saveKeysDeclared: true,
  ),
  GameSaveSummary(
    gameId: 'local-x',
    name: '本地示例',
    keyCount: 0,
    totalChars: 0,
    saveKeysDeclared: false,
  ),
  GameSaveSummary(
    gameId: 'my-little-pony',
    name: '小马宝莉',
    keyCount: 2,
    totalChars: 5,
    saveKeysDeclared: true,
  ),
  GameSaveSummary(
    gameId: 'twilight-witch',
    name: '暮色女巫',
    keyCount: 0,
    totalChars: 0,
    saveKeysDeclared: true,
  ),
];

/// 记录调用链的 fake 桥（断言导出/导入/删除派发 + 刷新）。
class _RecordingBridge extends SaveBridge {
  _RecordingBridge({List<GameSaveSummary>? rows})
      : rows = rows ?? _rows,
        super(access: FakeLocalStorageAccess(), games: const []);

  List<GameSaveSummary> rows;
  int loadCalls = 0;
  final List<String> exported = [];
  final List<String> imported = [];
  final List<String> deleted = [];
  SaveActionResult exportResult =
      const SaveActionResult.success('已导出 life-sim-saves.json（分享面板已打开）');
  SaveActionResult? importResult =
      const SaveActionResult.success('已恢复 2 个存档键');
  SaveActionResult deleteResult =
      const SaveActionResult.success('已删除 2 个存档键');

  @override
  Future<List<GameSaveSummary>> loadPanel() async {
    loadCalls++;
    return rows;
  }

  @override
  Future<SaveActionResult> exportGame(String gameId) async {
    exported.add(gameId);
    return exportResult;
  }

  @override
  Future<SaveActionResult?> importGame(String gameId) async {
    imported.add(gameId);
    return importResult;
  }

  @override
  Future<SaveActionResult> deleteGame(String gameId) async {
    deleted.add(gameId);
    return deleteResult;
  }
}

/// 立即抛错的假工厂（WebView 不可用降级路径）。
Future<WebViewCapability> _throwingFactory(
  void Function(WebViewCapability source) onPageFinished,
) async =>
    throw StateError('WebView 平台不可用');

/// 永不完成的假工厂（超时降级路径）。
Future<WebViewCapability> _hangingFactory(
  void Function(WebViewCapability source) onPageFinished,
) =>
    Completer<WebViewCapability>().future;

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required List<SaveGame> games,
    SaveBridge? bridge,
    WebViewCapabilityFactory? webViewFactory,
    Duration pageLoadTimeout = const Duration(milliseconds: 500),
  }) async {
    // 加高测试表面，保证 4 行游戏列表全量可见（ListView 懒构建不依赖视口）。
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => SaveSheet(
                      games: games,
                      saveBridge: bridge,
                      webViewFactory: webViewFactory ?? _throwingFactory,
                      pageLoadTimeout: pageLoadTimeout,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // 弹窗入场（动画时长由各测试自行 pump/ settle）
  }

  /// 目标行 key（行容器 ValueKey，见 save_sheet.dart）。
  Finder rowOf(String gameId) => find.byKey(ValueKey('save-row-$gameId'));

  group('渲染 · 游戏行 / 降级 / 注记 / 导出提示', () {
    testWidgets('注入 fake 桥 → 全部游戏行渲染（键数/字符/wg 注记/无存档管理）',
        (tester) async {
      await pumpSheet(
        tester,
        games: const [
          SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save']),
          SaveGame(id: 'local-x', name: '本地示例'),
        ],
        bridge: _RecordingBridge(),
      );
      await tester.pumpAndSettle();

      expect(find.text('存档管理'), findsOneWidget);
      // 导出固定提示（桌面 EXPORT_HINT 逐字）。
      expect(
        find.text('导出文件可能包含游戏内配置数据（如 API Key），请妥善保管'),
        findsOneWidget,
      );
      expect(find.text('人生模拟器'), findsOneWidget);
      expect(find.text('1 个存档 · 3 字符'), findsOneWidget);
      expect(find.text('无存档管理'), findsOneWidget, reason: '无 saveKeys 降级行');
      // wg_ 族注记（小马宝莉）。
      expect(find.text('仅会话内生效，重进需重注'), findsOneWidget);
      // 正则多键游戏。
      expect(find.text('2 个存档 · 5 字符'), findsOneWidget);
      // 零键但有 saveKeys → 常规行（导出/删除禁用）。
      expect(find.text('0 个存档 · 0 字符'), findsOneWidget);
    });

    testWidgets('零键游戏：导出/删除禁用、导入可用', (tester) async {
      await pumpSheet(
        tester,
        games: const [
          SaveGame(id: 'twilight-witch', name: '暮色女巫', saveKeys: ['x']),
        ],
        bridge: _RecordingBridge(),
      );
      await tester.pumpAndSettle();

      final row = rowOf('twilight-witch');
      final exportBtn = tester.widget<OutlinedButton>(
        find.descendant(of: row, matching: find.widgetWithText(OutlinedButton, '导出')),
      );
      final deleteBtn = tester.widget<OutlinedButton>(
        find.descendant(of: row, matching: find.widgetWithText(OutlinedButton, '删除')),
      );
      final importBtn = tester.widget<OutlinedButton>(
        find.descendant(of: row, matching: find.widgetWithText(OutlinedButton, '导入')),
      );
      expect(exportBtn.onPressed, isNull, reason: '零键导出禁用');
      expect(deleteBtn.onPressed, isNull, reason: '零键删除禁用');
      expect(importBtn.onPressed, isNotNull, reason: '导入恒可用');
    });

    testWidgets('生产 bootstrap：WebView 不可用 → 降级文案不崩', (tester) async {
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: 'x', saveKeys: ['s'])],
        bridge: null,
        webViewFactory: _throwingFactory,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.textContaining('存档读取不可用'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('生产 bootstrap：WebView 建立挂起 → 超时降级文案', (tester) async {
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: 'x', saveKeys: ['s'])],
        bridge: null,
        webViewFactory: _hangingFactory,
        pageLoadTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump(const Duration(milliseconds: 10)); // 挂起中（< 100ms）
      expect(find.text('正在读取存档…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100)); // 超时到期
      await tester.pump();
      expect(find.text('读取存档超时，WebView 未就绪'), findsOneWidget);
    });

    testWidgets('生产 bootstrap：navigate 抛错 → 消费点吞错，只走超时降级口径',
        (tester) async {
      // navigate 错误策略差异面（差异在消费点）：统一适配器上抛 → sheet 侧
      // 消费点吞错（loaded 永不完成）→ 只走超时降级文案；不出现「存档读取
      // 不可用」的 navigate 错误面、零未捕获异常。
      final factory = FakeWebViewCapabilityFactory()..throwOnNavigate = true;
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: 'x', saveKeys: ['life_save'])],
        bridge: null,
        webViewFactory: factory.create,
        pageLoadTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // 超时到期
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'navigate 错误被吞，零未捕获');
      expect(find.text('读取存档超时，WebView 未就绪'), findsOneWidget,
          reason: '只走超时降级口径（不弹 navigate 错误面）');
    });

    testWidgets('生产 bootstrap happy path：evaluate 往返解析渲染真实行',
        (tester) async {
      final factory = FakeWebViewCapabilityFactory()
        ..instantFinish = true
        ..store['life_save'] = '{"hp":10}';
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: null,
        webViewFactory: factory.create,
      );
      await tester.pumpAndSettle();

      expect(find.text('人生模拟器'), findsOneWidget);
      expect(find.text('1 个存档 · 9 字符'), findsOneWidget);
    });

    testWidgets('降级 → 重试重建 → 成功就绪', (tester) async {
      var factoryCalls = 0;
      final factory = FakeWebViewCapabilityFactory()
        ..instantFinish = true
        ..store['life_save'] = '数据';
      await pumpSheet(
        tester,
        games: const [
          SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save']),
        ],
        bridge: null,
        webViewFactory: (onPageFinished) async {
          factoryCalls++;
          if (factoryCalls == 1) {
            throw StateError('首次不可用');
          }
          return factory.create(onPageFinished);
        },
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('存档读取不可用'), findsOneWidget);
      await tester.pumpAndSettle(); // 弹窗入场动画完成（否则按钮仍在屏下）

      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('人生模拟器'), findsOneWidget);
      expect(find.text('1 个存档 · 2 字符'), findsOneWidget);
      expect(factoryCalls, 2, reason: '重试重建 WebView 并重新枚举');
    });

    testWidgets('关闭按钮 → 关闭 sheet 返回列表', (tester) async {
      await pumpSheet(
        tester,
        games: const [
          SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save']),
        ],
        bridge: _RecordingBridge(),
      );
      await tester.pumpAndSettle();
      expect(find.text('存档管理'), findsOneWidget);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('存档管理'), findsNothing);
      expect(find.text('open'), findsOneWidget, reason: '返回列表宿主');
    });

    testWidgets('无游戏数据 → 「暂无游戏数据」空态', (tester) async {
      final bridge = _RecordingBridge()..rows = [];
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'a', name: 'a', saveKeys: ['b'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无游戏数据'), findsOneWidget);
    });
  });

  group('W5 B1 回归 · 页面就绪委托必达（构造期委托注入）', () {
    testWidgets('委托构造期注入 + navigate 派发 → 最严苛窗口事件不丢 → 面板就绪零降级',
        (tester) async {
      // 委托必达（行为断言形态）：统一接口不暴露 setOnPageFinished，页面就绪
      // 委托由工厂构造期注入（假件 onPageFinished 构造必填）——装配 =
      // create(挂委托) → navigate 一步，秒开页事件必达（onPageFinished 只派发
      // 给挂载时已存在的委托，不回放挂载前事件；未先挂载 = 静默丢事件 → 超时
      // 降级，W5 B1）。
      final factory = FakeWebViewCapabilityFactory()
        ..instantFinish = true
        ..store['life_save'] = '数据';
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: null,
        webViewFactory: factory.create,
      );
      await tester.pumpAndSettle();

      // 行为终态：事件在「导航发起即完成」的最严苛时序下仍被送达（委托构造期
      // 已挂载）→ 面板就绪而非超时降级。
      expect(find.text('人生模拟器'), findsOneWidget);
      expect(find.text('读取存档超时，WebView 未就绪'), findsNothing);
    });

    testWidgets('事件必达（navigate 发起即完成）→ loaded 必达，零超时',
        (tester) async {
      // 对抗性：页面加载在导航返回序列内立即完成（真实丢事件窗口最窄形态）
      // ——委托构造期已挂载即必达；断言面板直接就绪，零超时。
      final factory = FakeWebViewCapabilityFactory()
        ..instantFinish = true
        ..store['life_save'] = '数据';
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: 'x', saveKeys: ['life_save'])],
        bridge: null,
        webViewFactory: factory.create,
        pageLoadTimeout: const Duration(milliseconds: 100),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      expect(find.text('1 个存档 · 2 字符'), findsOneWidget);
      expect(find.text('读取存档超时，WebView 未就绪'), findsNothing);
    });
  });

  group('操作交互 · 导出 / 导入 / 删除', () {
    testWidgets('导出：点击 → 桥 exportGame(gameId) + toast 反馈', (tester) async {
      final bridge = _RecordingBridge();
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.descendant(
        of: rowOf('life-sim'),
        matching: find.widgetWithText(OutlinedButton, '导出'),
      ));
      await tester.pump();
      await tester.pump();

      expect(bridge.exported, ['life-sim']);
      expect(find.text('已导出 life-sim-saves.json（分享面板已打开）'), findsOneWidget);
    });

    testWidgets('删除：确认弹窗（游戏名+键数+不可恢复）→ 取消不删除 / 确认删除',
        (tester) async {
      final bridge = _RecordingBridge();
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'my-little-pony', name: '小马宝莉', saveKeys: ['a'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      // 点击删除 → 确认弹窗内容逐字。
      await tester.tap(find.descendant(
        of: rowOf('my-little-pony'),
        matching: find.widgetWithText(OutlinedButton, '删除'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('删除存档'), findsOneWidget);
      expect(
        find.text('确定删除「小马宝莉」的全部存档吗？\n将清除 2 个存档键，此操作不可恢复。'),
        findsOneWidget,
      );

      // 取消 → 不调用桥。
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(bridge.deleted, isEmpty);

      // 再次删除 → 确认 → 调用 + toast + 刷新。
      await tester.tap(find.descendant(
        of: rowOf('my-little-pony'),
        matching: find.widgetWithText(OutlinedButton, '删除'),
      ));
      await tester.pumpAndSettle();
      final before = bridge.loadCalls;
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(bridge.deleted, ['my-little-pony']);
      expect(find.text('已删除 2 个存档键'), findsOneWidget);
      expect(bridge.loadCalls, before + 1, reason: '删除后刷新面板');
    });

    testWidgets('导入：点击 → 桥 importGame(gameId) + 成功 toast + 刷新',
        (tester) async {
      final bridge = _RecordingBridge();
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      final before = bridge.loadCalls;
      await tester.tap(find.descendant(
        of: rowOf('life-sim'),
        matching: find.widgetWithText(OutlinedButton, '导入'),
      ));
      await tester.pumpAndSettle();

      expect(bridge.imported, ['life-sim']);
      expect(find.text('已恢复 2 个存档键'), findsOneWidget);
      expect(bridge.loadCalls, before + 1);
    });

    testWidgets('导入：用户取消（桥返回 null）→ 零 toast 零刷新', (tester) async {
      final bridge = _RecordingBridge()..importResult = null;
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      final before = bridge.loadCalls;
      await tester.tap(find.descendant(
        of: rowOf('life-sim'),
        matching: find.widgetWithText(OutlinedButton, '导入'),
      ));
      await tester.pumpAndSettle();

      expect(bridge.imported, ['life-sim']);
      expect(find.byType(SnackBar), findsNothing);
      expect(bridge.loadCalls, before, reason: '取消不做任何副作用');
    });

    testWidgets('导入失败：失败文案 toast + 刷新面板（不残留半截数据）',
        (tester) async {
      final bridge = _RecordingBridge()
        ..importResult = const SaveActionResult.failure('存档文件校验失败：键「x」不在白名单');
      await pumpSheet(
        tester,
        games: const [SaveGame(id: 'life-sim', name: '人生模拟器', saveKeys: ['life_save'])],
        bridge: bridge,
      );
      await tester.pumpAndSettle();

      final before = bridge.loadCalls;
      await tester.tap(find.descendant(
        of: rowOf('life-sim'),
        matching: find.widgetWithText(OutlinedButton, '导入'),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('存档文件校验失败：键「x」不在白名单'),
        findsOneWidget,
      );
      expect(bridge.loadCalls, before + 1);
    });
  });
}
