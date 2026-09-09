/// 共享 WebView 能力假件——统一能力接口 [WebViewCapability] 的可控假实现，
/// 运行页 / 存档 sheet 两消费点测试共同引用（U1/U2 共用一套测试面；收敛目标 =
/// 生产面与测试面同时单一化，避免「两 seam → 两假件」的重复形态）。
///
/// 委托必达（F-43 / W5 B1 结构性形态）：[onPageFinished] **构造必填**——签名级
/// 锁定「页面就绪委托先于导航挂载」时序契约；配合 [FakeWebViewCapabilityFactory.instantFinish]
/// （navigate 发起即派发页面就绪事件）在最严苛竞态时序下验证事件必达。
///
/// evaluate **双编码 JSON 契约复刻**（迁自 save_sheet_test.dart:126-147 既有
/// 逻辑，契约单处书写）：锚 Android `evaluateJavascript` 生产契约（F-M5-09
/// AVD 实证 / 缺陷 #1 教训）——字符串结果带外层引号返回 Flutter（JSON 编码
/// 串），webview_flutter `runJavaScriptReturningResult` **原样透传**；本假件对
/// 枚举脚本产物（**键名 / 键值两个分支**）返回 `jsonEncode(jsonEncode(...))`
/// 复刻该外层引号层（iOS/macOS 裸值形态 = 桥层双解码容错的另一合法输入，非
/// 假件复刻形态；解码容错归桥层 `parseLocalStorageEntries`，与统一接口 / 生产
/// 契约 docstring 同源）。
library;

import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:flutter/widgets.dart' show SizedBox, Widget;

import 'package:conver_system_mobile/services/simulator/save_bridge.dart'
    show enumerateLocalStorageKeysScript;
import 'package:conver_system_mobile/services/simulator/webview_capability.dart'
    show WebViewCapability;

/// 可控假实现：页面就绪委托构造必填 + instantFinish / throwOnNavigate 参数化
/// + evaluate 双编码契约复刻 + runJavaScript / evaluate 与导航脚本记录。
class FakeWebViewCapability implements WebViewCapability {
  /// [onPageFinished] 页面就绪委托（**构造必填**——委托必达的形态保证）；
  /// [instantFinish] navigate 发起即派发页面就绪事件（最严苛竞态窗口）；
  /// [throwOnNavigate] navigate 抛错（跑测 loadRequest 失败路径）。
  FakeWebViewCapability(
    this.onPageFinished, {
    this.instantFinish = false,
    this.throwOnNavigate = false,
  });

  /// 页面就绪委托（生产语义 = factory 构造期注入的 `onPageFinished` 回调；
  /// 测试可直接调用以手动触发页面加载完成）。
  final void Function(WebViewCapability source) onPageFinished;

  /// 最严苛竞态开关：navigate 发起即完成 → 页面就绪事件在挂载后第一时间派发
  /// （委托若未构造期挂载即静默丢事件 → 走超时/错误态）。
  final bool instantFinish;

  /// navigate 抛错开关（loadRequest 失败路径：run 侧即时错误态 / sheet 侧
  /// 吞错走超时降级）。
  final bool throwOnNavigate;

  /// evaluate 背衬的 localStorage store（双编码契约的键值数据源）。
  final Map<String, String> store = {};

  /// runJavaScript 脚本记录（运行页无权返回通道断言）。
  final List<String> runJavaScriptScripts = [];

  /// evaluate 脚本记录（存档 sheet 带返回通道断言）。
  final List<String> evaluateScripts = [];

  /// 导航目标记录（URL 组装断言）。
  final List<Uri> navigatedUrls = [];

  @override
  Future<void> runJavaScript(String script) async {
    runJavaScriptScripts.add(script);
  }

  @override
  Future<String> evaluate(String script) async {
    evaluateScripts.add(script);
    if (script == enumerateLocalStorageKeysScript) {
      // 分片枚举第一步：全量键名（F-38）。**双编码**——`JSON.stringify(...)`
      // 的字符串结果经 Android evaluateJavascript 带外层引号返回（JSON 编码
      // 串，生产契约同 [values 分支]，N-F1 复刻对齐）；iOS/macOS 裸值形态为
      // 桥层双解码容错的另一合法输入（save_bridge `_decodeEnumeratedJson`）。
      return jsonEncode(jsonEncode(store.keys.toList()));
    }
    if (script.startsWith('JSON.stringify(')) {
      // 分片枚举第二步：批键值。锚 Android evaluateJavascript 生产契约
      // （F-M5-09 AVD 实证 / 缺陷 #1）：字符串结果带外层引号返回 Flutter
      // （JSON 编码串），webview_flutter `runJavaScriptReturningResult` 对
      // 字符串**原样透传**——外层 jsonEncode 模拟该引号层。修复前全量枚举
      // 单次返回使 `parseLocalStorageEntries` 一次 jsonDecode 得 String →
      // FormatException → 面板恒 0 键（回归断言见 save_sheet happy path）。
      final inner = script.substring('JSON.stringify('.length);
      final end = inner.indexOf('].map');
      final keys = (jsonDecode(inner.substring(0, end + 1)) as List)
          .cast<String>();
      return jsonEncode(jsonEncode([
        for (final k in keys) [k, store[k]],
      ]));
    }
    return '';
  }

  @override
  Future<void> navigate(Uri url) async {
    navigatedUrls.add(url);
    if (throwOnNavigate) {
      throw StateError('loadRequest 失败');
    }
    if (instantFinish) {
      // 导航发起即完成：事件在「挂载后、任何补救窗口前」立即派发。
      onPageFinished(this);
    }
  }

  @override
  Widget buildView() => const SizedBox(width: 1, height: 1);
}

/// 可控假工厂：记录已创建的控制器 + 参数化竞态/错误注入（对应旧测试工厂
/// `_FakeWebViewFactory` / save_sheet 注入点；[store] 种子在创建时注入每个
/// 控制器，供 evaluate 双编码往返读）。
class FakeWebViewCapabilityFactory {
  /// 已创建的控制器（断言创建次数 / 末次实例 / URL 记录）。
  final List<FakeWebViewCapability> created = [];

  /// evaluate 双编码契约的 store 种子（创建时复制进每个控制器）。
  final Map<String, String> store = {};

  /// navigate 即派发页面就绪事件（透传 [FakeWebViewCapability.instantFinish]）。
  bool instantFinish = false;

  /// navigate 抛错（透传 [FakeWebViewCapability.throwOnNavigate]）。
  bool throwOnNavigate = false;

  /// 工厂创建即抛错（WebView 平台不可用路径）。
  bool throwOnCreate = false;

  /// 创建未导航控制器并挂载页面就绪委托（生产工厂语义的对拍点：[onPageFinished]
  /// 构造期注入，先于任何 navigate——委托必达的形态保证）。
  Future<WebViewCapability> create(
    void Function(WebViewCapability source) onPageFinished,
  ) async {
    if (throwOnCreate) {
      throw StateError('WebView 平台不可用');
    }
    final controller = FakeWebViewCapability(
      onPageFinished,
      instantFinish: instantFinish,
      throwOnNavigate: throwOnNavigate,
    );
    controller.store.addAll(store);
    created.add(controller);
    return controller;
  }
}