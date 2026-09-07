/// 模拟器导入流程（F-M5-07）——file_picker 单 .html → 校验链预检 → 恶意命中
/// 拒绝 + 中文清单 + 强制二次确认（知情放行）→ 落盘 + manifest 原子注册 →
/// toast / 失败文案。
///
/// 职责边界（spec §3.6 Q13/Q14 逐字）：校验/去重/改名/探测/粗筛/落盘全部经
/// `import_service.dart` 单源（[validateImportInput] 预检 + [importGame] 编排
/// + [scanSuspicious] 粗筛）；本文件只做「选文件 → 预检 → 确认门禁 → 触发落盘
/// → 用户反馈」的薄编排，不复制任何校验规则。恶意命中交互比桌面「提示不拦截」
/// 更紧：拒绝导入 + 命中关键词中文清单 + 强制二次确认，取消 → 不落盘。
///
/// 平台 seam（测试注入 fake，永不触真平台通道）：[SimulatorImportFlow] 四依赖
/// 可注入——[pickHtmlFile]（缺省 file_picker 单 .html）、[resolveSimDir]（缺省
/// [SimulatorDataDir.resolve]）、[runImportGame]（缺省 [importGame]）、
/// [platformTimeout]（全部平台/IO 调用点超时兜底，缺省 10s——复用 M4
/// `pickJsonWithTimeout` 超时兜底模式，挂起不挂死）。
///
/// 协议表面（深模块）：[PickHtmlFile] / [RunImportGame] / [SimulatorImportFlow] /
/// `defaultPickHtmlFile`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/simulator/import_service.dart'
    show
        ImportResult,
        SimulatorDuplicateError,
        SimulatorImportError,
        importGame,
        scanSuspicious,
        validateImportInput;
import '../../services/simulator/simulator_data_dir.dart'
    show SimulatorDataDir;
import '../../services/simulator/suspicious_patterns.dart'
    show SuspiciousPatterns;

/// 选中文件（文件名 + 字节；name 为原始文件名——校验/净化均在服务层进行）。
typedef PickedHtmlFile = ({String name, List<int> bytes});

/// 平台 pick 回调：返回选中 .html 文件；`null` = 用户取消 / 超时降级。
typedef PickHtmlFile = Future<PickedHtmlFile?> Function();

/// 导入运行回调（测试注入 fake；生产默认 [importGame]）。
typedef RunImportGame =
    Future<ImportResult> Function(Directory simDir, String filename, List<int> content);

/// 缺省 pick：file_picker 选单个 `.html`（FileType.custom +
/// allowedExtensions ['html']）并读取字节；用户取消 → null。
// coverage:ignore-start
Future<PickedHtmlFile?> defaultPickHtmlFile() async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['html'],
  );
  if (picked == null) {
    return null;
  }
  return (name: picked.name, bytes: await picked.readAsBytes());
}
// coverage:ignore-end

/// 缺省数据目录解析：应用文档目录下 `simulators/`（生产 path_provider 平台
/// 通道，宿主测试不可达——M4 `defaultPickJsonFile` 同先例标 ignore）。
// coverage:ignore-start
Future<Directory> _defaultResolveSimDir() => SimulatorDataDir().resolve();
// coverage:ignore-end

/// 模拟器导入流（AppBar「导入」入口的实现载体）。
class SimulatorImportFlow {
  /// [pickHtmlFile] 缺省 file_picker 单 .html；[resolveSimDir] 缺省数据目录
  /// 解析；[runImportGame] 缺省 [importGame]（tear-off）；[platformTimeout]
  /// 全部平台/IO 调用点超时兜底（缺省 10s，测试注入短值）。
  SimulatorImportFlow({
    Future<Directory> Function()? resolveSimDir,
    PickHtmlFile? pickHtmlFile,
    RunImportGame? runImportGame,
    this.platformTimeout = const Duration(seconds: 10),
  })  : _resolveSimDir = resolveSimDir ?? _defaultResolveSimDir,
        _pickHtmlFile = pickHtmlFile ?? defaultPickHtmlFile,
        _runImportGame = runImportGame ?? importGame;

  final Future<Directory> Function() _resolveSimDir;
  final PickHtmlFile _pickHtmlFile;
  final RunImportGame _runImportGame;

  /// 平台/IO 调用点的超时兜底时长（挂起降级为明确文案，不挂死）。
  final Duration platformTimeout;

  /// 导入入口（AppBar「导入」接线）：选择 → 校验预检 → 恶意确认门禁 → 落盘/
  /// 注册 → toast；全程失败不崩、取消不做任何副作用。
  Future<void> handleImport(BuildContext context) async {
    // 捕获跨 async gap 稳定句柄（lint 纪律）：toast 走 messenger、进度弹窗/
    // 关闭走 navigator——BuildContext 仅在 mounted 守卫下用于确认弹窗。
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.maybeOf(context, rootNavigator: true);

    void toast(String message) {
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    final PickedHtmlFile? picked;
    try {
      picked = await _pickHtmlFile().timeout(platformTimeout);
    } on TimeoutException {
      toast('选择文件超时，请重试');
      return;
    } catch (error) {
      // 平台故障以 Error/Exception 双形态出现（StateError / FileSystemException
      // 等），一律转明确文案不崩。
      toast('选择文件失败：$error');
      return;
    }
    if (picked == null) {
      return; // 用户取消 → 零提示零副作用（不崩）。
    }

    try {
      validateImportInput(picked.name, picked.bytes);
    } on SimulatorImportError catch (error) {
      toast(error.message);
      return;
    }

    // 恶意模式粗筛（纯函数，零副作用）→ 命中拒绝 + 中文清单 + 强制二次确认。
    final text = utf8.decode(picked.bytes, allowMalformed: true);
    final warnings = scanSuspicious(text);
    if (warnings.isNotEmpty) {
      if (!context.mounted) {
        return;
      }
      final confirmed = await _confirmSuspicious(context, warnings);
      if (!confirmed) {
        toast('已取消导入（未确认恶意内容）');
        return;
      }
    }

    if (navigator == null) {
      return; // 无 Navigator（视图已卸载/非路由上下文）→ 不执行导入。
    }
    // 导入中不确定态（模态进度，push 同步注册路由；完成后关闭）。
    unawaited(_showImporting(navigator));
    try {
      final Directory simDir;
      try {
        simDir = await _resolveSimDir().timeout(platformTimeout);
      } on TimeoutException {
        toast('解析数据目录超时，请重试');
        return;
      }
      final result =
          await _runImportGame(simDir, picked.name, picked.bytes)
              .timeout(platformTimeout);
      final file = result.game['file'] as String? ?? picked.name;
      toast(
        result.renamed ? '导入成功（已改名为 $file）' : '导入成功',
      );
    } on SimulatorDuplicateError catch (error) {
      toast(error.message);
    } on SimulatorImportError catch (error) {
      toast(error.message);
    } on TimeoutException {
      toast('导入超时，请重试');
    } catch (error) {
      toast('导入失败：$error');
    } finally {
      _dismissImporting(navigator);
    }
  }

  /// 恶意命中二次确认弹窗：拒绝 + 中文清单 + 知情放行按钮。
  Future<bool> _confirmSuspicious(BuildContext context, List<String> warnings) async {
    final labels =
        warnings.map((key) => '· ${SuspiciousPatterns.labelFor(key)}').join('\n');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入安全警告'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('检测到以下可疑模式，拒绝导入。仅当你了解风险并信任该'
                  '文件时，可二次确认继续导入：'),
              const SizedBox(height: 12),
              Text(labels),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('我了解风险，继续导入'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 模态导入中进度（不确定态；完成后由 [_dismissImporting] 关闭）。
  ///
  /// [navigator] 为 handleImport 入口捕获的 rootNavigator（跨 async gap 稳定
  /// 句柄，替代裸 BuildContext——lint 纪律）。
  Future<void> _showImporting(NavigatorState navigator) {
    return showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Text('正在导入…'),
          ],
        ),
      ),
    );
  }

  /// 关闭导入中进度（progress 路由始终在本 Navigator 栈顶；pop 语义安全——
  /// 不使用 maybePop：弹窗尚未首帧 build（PopScope 未注册）时 maybePop 会
  /// 断言，普通 pop 只移除路由无需 PopScope）。
  void _dismissImporting(NavigatorState navigator) {
    navigator.pop();
  }
}