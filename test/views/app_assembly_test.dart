/// app.dart 装配图 seam 测试（C2 装配收敛）— DocumentParseService / GameGenerator
/// 由应用级装配图单一持有，HomeShell context 下可经 [Provider.of] 解析。
///
/// 语义锚点（工单 C2 验收）：视图层不再现造任何服务实例（layer_boundary 静态
/// 断言 + 本测试运行时实证），两服务装配点迁入 app.dart provider 图——装配
/// 图测试经 HomeShell context 按公共接口（Provider.of）消费，不测内部实现。
/// 复刻 app_theme_binding_test 的 ConverApp(database: db) 注入形态（内存执行器）。
///
/// T3 追加：SimulatorsController 装配点同样经公共装配图解析——构造闭包含
/// `proxyConfigReader` 反代凭据 seam 接线（与注入链同源）；createServer 工厂
/// 签名（`SimulatorServer Function(Directory)`）保持不变，控制器零改动。
library;

import 'package:conver_system_mobile/app.dart';
import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/services/document_parse_service.dart';
import 'package:conver_system_mobile/services/simulator/game_generator.dart';
import 'package:conver_system_mobile/view_models/simulators_controller.dart';
import 'package:conver_system_mobile/views/home_shell.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('装配图单一持有 DocumentParseService 与 GameGenerator（C2 收敛）',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pump();
    await tester.pump();

    // HomeShell 在 MultiProvider 之下：装配图两服务实例可解析（惰性创建被
    // Provider.of 触发，覆盖 app.dart 新增装配分支）。
    final context = tester.element(find.byType(HomeShell));
    expect(
      Provider.of<DocumentParseService>(context, listen: false),
      isA<DocumentParseService>(),
      reason: 'DocumentParseService 装配点迁入 app.dart，可经公共装配图解析',
    );
    expect(
      Provider.of<GameGenerator>(context, listen: false),
      isA<GameGenerator>(),
      reason: 'GameGenerator 装配点迁入 app.dart，可经公共装配图解析',
    );
  });

  testWidgets('装配图持有 SimulatorsController（T3 proxyConfigReader 接线可构造）',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(ConverApp(database: db));
    await tester.pump();
    await tester.pump();

    // 触发 SimulatorsController provider create 闭包——含 /proxy 反代凭据
    // seam 接线（SecretStore openai 槽 + SettingsRepository.baseUrl('openai')，
    // 与注入链同源）；闭包构造失败（装配断裂）即本测试失败。
    final context = tester.element(find.byType(HomeShell));
    expect(
      Provider.of<SimulatorsController>(context, listen: false),
      isA<SimulatorsController>(),
      reason: 'SimulatorsController 装配点含 proxyConfigReader 接线，可经装配图构造',
    );
  });
}