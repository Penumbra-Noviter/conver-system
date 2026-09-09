/// 模拟器 WebView 能力面（AR-4）——两张平行 WebView seam（运行页 F-M5-04 /
/// 存档 sheet F-M5-06）收敛为统一能力接口 + 单一平台薄层。
///
/// 组合形态：能力接口 [WebViewCapability]（页面就绪握手 + 无返回
/// [runJavaScript] / 带返回 [evaluate] + [navigate] + [buildView]）+ 工厂
/// typedef [WebViewCapabilityFactory]（**构造期委托注入**）+ 生产工厂
/// [createWebViewCapability] + 生产适配器 `_FlutterWebViewCapability`
/// （webview_flutter **唯一引用点**）。
///
/// 时序契约（页面就绪握手，F-43 TD-3 / W5 B1 结构化形态）：webview 的
/// `onPageFinished` 只派发给**挂载时已存在的**导航委托、不回放挂载前事件。
/// 本接口**不暴露 `setOnPageFinished`** ——页面就绪委托由工厂构造期注入、生产
/// 适配器构造时 `setNavigationDelegate` 挂载，先于任何 `navigate` 成为形态必然，
/// 消费点无「做错」的可能（挂委托后导航的两步序收敛为 create(挂委托) →
/// navigate 一步）。无参化意图保持：创建**未导航**控制器、回调注入不导航，
/// 导航仍经独立 [WebViewCapability.navigate] 发起。
///
/// 求值契约（缺陷 #1 语义）：`evaluate` 返回**生产原样串**——webview_flutter
/// `runJavaScriptReturningResult(...)` Android 契约 = 编码 JSON 串（字符串结果
/// 带外层引号）经 `toString()` 原样透传；**JSON 解码容错归桥层**
/// `parseLocalStorageEntries`（save_bridge.dart），本接口不解码。
///
/// 两消费点差异面（本接口统一、差异留消费点状态机）：运行页 = 无返回
/// `runJavaScript` + `navigate` 错误上抛 → 即时错误态「加载模拟器页面失败」；
/// 存档 sheet = 带返回 `evaluate` + `navigate` 吞错走超时降级口径。
///
/// 真通道契约归属：生产适配器不可在测试宿主运行（平台通道），真通道行为唯一
/// 直接证据 = **F-M5-09 AVD 冒烟**；widget 测试注入共享假件
/// `test/support/fake_web_view_capability.dart`（复刻 evaluate 双编码契约）。
///
/// 层级归位：AGENTS.md 平台薄层（WebView 桥）集中隔离于 `services/` 不散落进
/// views——本模块是 `services/` 首个 import `flutter/widgets` 的平台薄层
/// carve-out（对齐 r3 自建 seam + 平台隔离一贯形态）。
///
/// 协议表面（深模块，五公开名）：`WebViewCapability`（接口四方法：握手为工厂
/// 构造期注入不入接口）+ `WebViewCapabilityFactory` / `createWebViewCapability`
/// （构造期委托注入装配）。
library;

import 'package:flutter/widgets.dart' show Color, Widget;
import 'package:webview_flutter/webview_flutter.dart';

/// WebView 能力接口（统一 seam）——两消费点（运行页 / 存档 sheet）只依赖本窄
/// 接口 + 工厂注入点。
///
/// 不暴露 `setOnPageFinished`：页面就绪委托经 [WebViewCapabilityFactory]
/// **构造期注入**、生产适配器构造时 `setNavigationDelegate` 挂载（先于任何
/// `navigate` 的时序契约结构性成立）。求值差异面 = 无返回 [runJavaScript] /
/// 带返回 [evaluate]（返回原样串，解码归桥层，见库 docstring）。
abstract interface class WebViewCapability {
  /// 页内执行 [script]（无返回通道：运行页 InjectionScript 注入序列走此，
  /// 生产 = webview_flutter `runJavaScript`）。
  Future<void> runJavaScript(String script);

  /// 页内执行 [script] 并返回其结果**原样串**（生产 =
  /// `runJavaScriptReturningResult(...).toString()`；Android 契约 = 编码 JSON
  /// 串，字符串结果带外层引号原样透传）。JSON 解码容错归桥层
  /// `parseLocalStorageEntries`（save_bridge.dart），本接口不解码。
  Future<String> evaluate(String script);

  /// 发起导航到 [url]（生产 = `loadRequest`；返回即完成请求发出，页面就绪以
  /// 构造期注入的委托回调为准）。错误**上抛**——错误策略差异面由消费点承担：
  /// 运行页即时错误态 / 存档 sheet 吞错走超时降级。
  Future<void> navigate(Uri url);

  /// 渲染平台视图主体（生产 WebViewWidget / 测试占位组件）。
  Widget buildView();
}

/// WebView 能力工厂注入点（统一 seam）——创建**未导航**的控制器，**[onPageFinished]
/// 构造期委托注入**：生产适配器构造时挂载导航委托（先于任何 `navigate`，时序
/// 契约结构性成立）。无参化意图保持：创建未导航控制器、回调注入不导航，导航
/// 仍经 [WebViewCapability.navigate] 独立发起（F-43 对齐 save_sheet W5 B1）。
typedef WebViewCapabilityFactory =
    Future<WebViewCapability> Function(
      void Function(WebViewCapability source) onPageFinished,
    );

// 平台薄层收口本文件：真实 WebView 控制器不可在测试宿主运行（平台通道），
// 真通道行为归 F-M5-09 AVD 冒烟（U1/U2 实证）；与 M4 `defaultPickJsonFile` /
// `defaultShareViaPlus`（save_bridge 装配腿）同先例标 ignore。
// coverage:ignore-start

/// 生产 WebView 能力工厂：仅创建 webview_flutter 控制器，**[onPageFinished]
/// 构造期挂载导航委托**（挂载先于任何 navigate 为形态必然；不发起导航——回调
/// 注入不导航，导航经 [WebViewCapability.navigate] 独立发起，杜绝 onPageFinished
/// 错过，F-43 对齐 save_sheet W5 B1）。
Future<WebViewCapability> createWebViewCapability(
  void Function(WebViewCapability source) onPageFinished,
) async {
  final inner = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(const Color(0xFF000000));
  return _FlutterWebViewCapability(inner, onPageFinished);
}

/// webview_flutter 薄适配：仅参数转发与回调注册，零业务逻辑。
class _FlutterWebViewCapability implements WebViewCapability {
  _FlutterWebViewCapability(
    this._inner,
    void Function(WebViewCapability source) onPageFinished,
  ) {
    // 构造期挂载：委托先于任何 navigate 存在（时序契约结构性成立）。
    _inner.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => onPageFinished(this)),
    );
  }

  final WebViewController _inner;

  @override
  Future<void> runJavaScript(String script) => _inner.runJavaScript(script);

  @override
  Future<String> evaluate(String script) async =>
      (await _inner.runJavaScriptReturningResult(script)).toString();

  @override
  Future<void> navigate(Uri url) => _inner.loadRequest(url);

  @override
  Widget buildView() => WebViewWidget(controller: _inner);
}
// coverage:ignore-end