/// 控制器「异步操作 → 超时兜底 → 失败 notice」编排运行器（2026-09-07
/// 架构深化——候选 2 收拢）。
///
/// chat / characters 两控制器此前各自复制「try / await / `.timeout` /
/// catch 错误折叠 / 先错者胜 notice」骨架（`.timeout(3s)` 6 处 + notice
/// 12 处）；收敛于本运行器：超时阈值与错误折叠策略各有一个归属点。
///
/// 语义（对齐各控制器既有行为，不改变任何可见文案）：
/// - [guard]：执行 [op]（带 [timeout] 兜底），失败 / 超时经 [onError]
///   折叠为 notice（**先错者胜**——已有 notice 不被覆盖）；成功返回产物，
///   失败 / 超时返回 `null`（调用方按需处理）；
/// - 成功路径由调用方声明 [set]（覆盖式，如「已导入角色…」）或 [clear]
///   （清空，如刷新成功）；[setFirst] 供非超时操作的失败分支使用
///   （如「角色不存在或已删除」）；
/// - 每次 notice 变化（set / setFirst 首次置位 / clear）触发 [onChanged]——
///   controller 以 `onChanged: notifyListeners` 接入，失败 notice 无需
///   调用方额外 notify。
// 构造为公开命名参数（onChanged）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 conversation_export_service 同款）。
// ignore_for_file: prefer_initializing_formals
class NoticeRunner {
  NoticeRunner({void Function()? onChanged}) : _onChanged = onChanged;

  final void Function()? _onChanged;

  void _notify() => _onChanged?.call();

  String? _notice;

  /// 当前待展示 notice（null = 无）。
  String? get notice => _notice;

  bool get hasNotice => _notice != null;

  /// 清空（操作成功 / 新操作开始时用）。
  void clear() {
    _notice = null;
    _notify();
  }

  /// 覆盖式设置（成功文案 / 状态引导提示用）。
  void set(String message) {
    _notice = message;
    _notify();
  }

  /// 先错者胜（失败分支用）：已有 notice 不覆盖；仅首次置位触发 [onChanged]
  /// （被忽略的 setFirst 不打扰监听者）。
  void setFirst(String message) {
    if (_notice != null) {
      return;
    }
    _notice = message;
    _notify();
  }

  /// 执行 [op]（带 [timeout] 兜底），失败 / 超时经 [onError] 折叠为
  /// notice（先错者胜）并返回 `null`；成功返回 [op] 产物。
  ///
  /// 平台通道挂起**不抛错**（Flutter 特性），[timeout] 兜底保证不挂死；
  /// [TimeoutException] 与其它异常统一走 [onError] 折叠（对齐既有
  /// `catch (error) { _notice ?? '…: $error' }` 的行为）。
  Future<T?> guard<T>({
    required Future<T> Function() op,
    required String Function(Object error) onError,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      return await op().timeout(timeout);
    } catch (error) {
      setFirst(onError(error));
      return null;
    }
  }
}