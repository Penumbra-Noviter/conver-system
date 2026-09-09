/// 底部半屏存档管理 sheet（F-M5-06，Q12 定案）——一次管全部游戏：每行 = 游戏名
/// + `{N} 个存档 · {M} 字符` + 导出 / 导入 / 删除（零键时导出删除禁用）；无
/// saveKeys 游戏「无存档管理」降级行；wg_ 族（小马宝莉 / 高中生模拟器）会话内
/// 注记；面板固定导出提示。语义逐字锚桌面 `save-manager.js`。
///
/// U2（最大风险，spec §6 登记）：Flutter 主进程与游戏非同源，localStorage 访问
/// 须建立 server origin —— sheet 内持一个**低占位 WebView** 指向
/// `http://127.0.0.1:<port>/`（F-M5-02 `/` index 路由），页面就绪后经
/// [JsBridgeLocalStorageAccess]（evaluate 枚举/写回）读取存档。[WebViewCapability]
/// 统一能力 seam 支持求值返回（生产 = webview_flutter 带返回值求值薄适配，平台
/// 薄层收口 `services/simulator/webview_capability.dart`；真通道行为归 F-M5-09
/// AVD 冒烟）。**时序契约（W5 B1）**：WebView `onPageFinished` 只
/// 派发给挂载时已存在的导航委托、不回放挂载前事件——装配 = create(挂委托) →
/// navigate 一步（委托由工厂构造期注入），杜绝事件丢失导致的恒/偶发超时降级。
/// navigate 错误在消费点吞掉，面板只走 loaded 超时降级口径。WebView 不可用 /
/// 挂起 → 超时兜底降级文案，不崩。
///
/// 平台 seam 全部注入（测试假件）：[webViewFactory]（WebView 能力工厂）、
/// [saveBridge]（测试注入 fake 桥直接跳过 WebView 建立）；导出/导入平台腿由
/// 桥内建（M4 `platform_file_exchange` 复用，不新增平台通道代码）。
///
/// 层级：呈现层。存档键收集/校验/应用/删除语义全部经 [SaveBridge] 编排消费
/// F-M5-05 契约纯函数，本文件只做展示编排与确认弹窗。
///
/// 协议表面：`SaveSheet` / `saveSheetTitle` / `saveSheetExportHint` /
/// `saveSheetNoSaveText` / `saveSheetWgNote` / `saveSheetBootingText` /
/// `saveSheetDegradedText` / `saveSheetTimeoutText`。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/simulator/save_bridge.dart'
    show GameSaveSummary, JsBridgeLocalStorageAccess, SaveBridge, SaveGame;
import '../../services/simulator/save_key_meta.dart' show wgSessionOnlyIds;
import '../../services/simulator/simulator_contracts.dart'
    show SimulatorContracts;
import '../../services/simulator/webview_capability.dart'
    show WebViewCapability, WebViewCapabilityFactory, createWebViewCapability;
import '../../theme/conver_palette.dart' show ConverPalette;

/// 面板标题。
const String saveSheetTitle = '存档管理';

/// 导出固定提示（桌面 EXPORT_HINT 逐字：仿微 wxai_state_v1 单键混装含 API Key）。
const String saveSheetExportHint =
    '导出文件可能包含游戏内配置数据（如 API Key），请妥善保管';

/// 无 saveKeys 游戏降级文案（桌面 NO_SAVE_TEXT 逐字）。
const String saveSheetNoSaveText = '无存档管理';

/// wg_ 族（仅会话内生效）注记（桌面 WG_NOTE 逐字）。
const String saveSheetWgNote = '仅会话内生效，重进需重注';

/// 打开中（WebView 建立 / 枚举）提示。
const String saveSheetBootingText = '正在读取存档…';

/// WebView 不可用降级文案。
const String saveSheetDegradedText = '存档读取不可用';

/// WebView 建立/页面 load 超时降级文案。
const String saveSheetTimeoutText = '读取存档超时，WebView 未就绪';

/// 无游戏数据空态文案。
const String saveSheetEmptyText = '暂无游戏数据';

/// sheet 相位：booting（建立 origin + 枚举）→ ready（行列表）| degraded（文案）。
enum _SheetPhase { booting, ready, degraded }

/// 底部半屏存档管理 sheet：一次管全部游戏（Q12）。
///
/// 构造入参：[games] 面板管理的游戏集（视图从列表模型映射为最小数据面）；
/// [saveBridge] 测试注入 fake 桥（缺省 = 生产建立低占位 WebView 后自建）；
/// [webViewFactory] WebView 能力工厂（缺省生产平台薄层；构造期注入页面就绪
/// 委托）；[port] 本地托管端口（生产固定 [SimulatorContracts.defaultPort]）；
/// [pageLoadTimeout] WebView 建立 + 页面 load 超时守卫；[platformTimeout] 桥内
/// 平台调用点超时。
class SaveSheet extends StatefulWidget {
  /// 构造底部半屏存档 sheet。
  const SaveSheet({
    super.key,
    required this.games,
    this.saveBridge,
    this.webViewFactory = createWebViewCapability,
    this.port = SimulatorContracts.defaultPort,
    this.pageLoadTimeout = const Duration(milliseconds: 8000),
    this.platformTimeout = const Duration(seconds: 10),
  });

  /// 面板管理的游戏集（最小数据面）。
  final List<SaveGame> games;

  /// 存档编排桥（测试注入 fake；缺省 = 生产自建，含 WebView 建立）。
  final SaveBridge? saveBridge;

  /// WebView 能力工厂（统一 U2 seam；构造期注入页面就绪委托；测试注入共享
  /// 假件不触平台通道）。
  final WebViewCapabilityFactory webViewFactory;

  /// 本地托管端口（生产 8642）。
  final int port;

  /// WebView 建立 + 页面 load 超时守卫（sheet 专用口径）。
  final Duration pageLoadTimeout;

  /// 桥内平台调用点超时（导出分享 / 导入选择 / 写回 flush）。
  final Duration platformTimeout;

  @override
  State<SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<SaveSheet> {
  _SheetPhase _phase = _SheetPhase.booting;

  /// 当前面板行数据（ready 相位非空；操作后重枚举刷新）。
  final List<GameSaveSummary> _rows = [];

  /// 降级原因（degraded 相位非空）。
  String? _degradedReason;

  /// 当前编排桥（生产自建 / 注入共用）。
  SaveBridge? _bridge;

  /// 低占位 WebView 能力（origin 建立用；生产路径非空）。
  WebViewCapability? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  /// 编排入口：注入桥直接读行；生产路径建立 origin WebView → 页面 load 完成 →
  /// 自建桥 → 读行。任何一步挂起/失败 → 降级文案，不崩。
  Future<void> _bootstrap() async {
    final injected = widget.saveBridge;
    if (injected != null) {
      _bridge = injected;
      await _loadRows();
      return;
    }
    setState(() {
      _phase = _SheetPhase.booting;
      _degradedReason = null;
    });
    try {
      final url = Uri.parse('http://127.0.0.1:${widget.port}/');
      final loaded = Completer<void>();
      // 构造期委托注入（W5 B1 结构化形态）：页面就绪委托由工厂构造期挂载、先于
      // 任何 navigate——onPageFinished 只派发给挂载时已存在的委托（不回放挂载前
      // 事件），先导航后挂委托即丢失事件 → 恒/偶发超时降级。装配 = create(挂
      // 委托) → navigate 一步。
      final controller = await widget
          .webViewFactory((source) {
            if (!loaded.isCompleted) {
              loaded.complete();
            }
          })
          .timeout(widget.pageLoadTimeout);
      if (!mounted) {
        return;
      }
      _controller = controller;
      // navigate 错误在消费点吞掉：面板只走 loaded 超时降级口径（差异策略在
      // 消费点；旧适配器 unawaited(onError) 同语义上移本处）。
      unawaited(
        controller.navigate(url).then<void>((_) {}, onError: (Object _) {}),
      );
      await loaded.future.timeout(widget.pageLoadTimeout);
      if (!mounted) {
        return;
      }
      _bridge = SaveBridge(
        access: JsBridgeLocalStorageAccess(
          (script) => controller.evaluate(script),
          timeout: widget.pageLoadTimeout,
        ),
        games: widget.games,
        platformTimeout: widget.platformTimeout,
      );
      await _loadRows();
    } on TimeoutException {
      _degrade(saveSheetTimeoutText);
    } catch (error) {
      _degrade('$saveSheetDegradedText（$error）');
    }
  }

  /// 枚举刷新行（面板读 / 操作后重枚举共用；枚举降级空 Map 时全部 0 键）。
  Future<void> _loadRows() async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    final rows = await bridge.loadPanel();
    if (!mounted) {
      return;
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _phase = _SheetPhase.ready;
    });
  }

  void _degrade(String reason) {
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = _SheetPhase.degraded;
      _degradedReason = reason;
    });
  }

  /// 降级重试：复位后重新编排（生产路径重建 WebView）。
  void _handleRetry() {
    _controller = null;
    _bridge = null;
    setState(() {
      _phase = _SheetPhase.booting;
      _degradedReason = null;
      _rows.clear();
    });
    unawaited(_bootstrap());
  }

  // ══════════════════════════════════════════════════
  // 操作交互（导出 / 导入 / 删除）
  // ══════════════════════════════════════════════════

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleExport(GameSaveSummary row) async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    final result = await bridge.exportGame(row.gameId);
    _toast(result.message);
  }

  Future<void> _handleImport(GameSaveSummary row) async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    final result = await bridge.importGame(row.gameId);
    if (result == null) {
      return; // 用户取消 / 选择超时——静默零副作用
    }
    _toast(result.message);
    await _loadRows(); // 刷新面板（失败「不残留半截数据」亦重枚举）
  }

  Future<void> _handleDelete(GameSaveSummary row) async {
    final bridge = _bridge;
    if (bridge == null) {
      return;
    }
    final confirmed = await _confirmDelete(row);
    if (!confirmed) {
      return;
    }
    final result = await bridge.deleteGame(row.gameId);
    _toast(result.message);
    await _loadRows();
  }

  /// 删除确认弹窗（游戏名 + 键数 + 不可恢复，桌面 showConfirm 语义逐字）。
  Future<bool> _confirmDelete(GameSaveSummary row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除存档'),
        content: Text(
          '确定删除「${row.name}」的全部存档吗？\n'
          '将清除 ${row.keyCount} 个存档键，此操作不可恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // ══════════════════════════════════════════════════
  // 渲染
  // ══════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final height = MediaQuery.of(context).size.height * 0.62; // 底部半屏
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(palette),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    saveSheetExportHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.ink3),
                  ),
                ),
                Divider(height: 1, color: palette.border),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
          // 低占位 WebView：1×1 不透明度 0 锚定 container，建立且维持 server
          // origin（U2；AVD 冒烟实证在 F-M5-09）。
          if (_controller != null)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0,
                child: _controller!.buildView(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(ConverPalette palette) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              saveSheetTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: palette.ink1),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _SheetPhase.booting:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 12),
              Text('正在读取存档…'),
            ],
          ),
        );
      case _SheetPhase.degraded:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 36, color: ConverPalette.of(context).ink4),
              const SizedBox(height: 12),
              Text(_degradedReason ?? saveSheetDegradedText),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _handleRetry,
                child: const Text('重试'),
              ),
            ],
          ),
        );
      case _SheetPhase.ready:
        return _buildRows();
    }
  }

  Widget _buildRows() {
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          saveSheetEmptyText,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: ConverPalette.of(context).ink3,
              ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _rows.length,
      itemBuilder: (context, index) => _GameSaveRow(
        key: ValueKey('save-row-${_rows[index].gameId}'),
        row: _rows[index],
        onExport: () => unawaited(_handleExport(_rows[index])),
        onImport: () => unawaited(_handleImport(_rows[index])),
        onDelete: () => unawaited(_handleDelete(_rows[index])),
      ),
    );
  }
}

/// 单个游戏行：游戏名 / `N 个存档 · M 字符` / wg_ 族注记 / 导出·导入·删除三按钮
/// （零键时导出删除禁用）。无 saveKeys → 「无存档管理」降级行（无按钮）。
class _GameSaveRow extends StatelessWidget {
  const _GameSaveRow({
    super.key,
    required this.row,
    required this.onExport,
    required this.onImport,
    required this.onDelete,
  });

  final GameSaveSummary row;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = ConverPalette.of(context);
    final textTheme = Theme.of(context).textTheme;
    final isWg = wgSessionOnlyIds.contains(row.gameId);
    if (!row.saveKeysDeclared) {
      // 无存档管理降级行（桌面 sim-save-degraded 语义）。
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                row.name,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: palette.ink1),
              ),
            ),
            Text(
              saveSheetNoSaveText,
              style: textTheme.bodySmall?.copyWith(color: palette.ink3),
            ),
          ],
        ),
      );
    }
    final hasKeys = row.keyCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.name,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(color: palette.ink1),
          ),
          const SizedBox(height: 2),
          Text(
            '${row.keyCount} 个存档 · ${row.totalChars} 字符',
            style: textTheme.bodySmall?.copyWith(color: palette.ink3),
          ),
          if (isWg)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                saveSheetWgNote,
                style: textTheme.labelSmall?.copyWith(color: palette.ink4),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: hasKeys ? onExport : null,
                  child: const Text('导出'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onImport,
                  child: const Text('导入'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: hasKeys ? onDelete : null,
                  child: const Text('删除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}