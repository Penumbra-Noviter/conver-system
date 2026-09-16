/// 通知平台薄层（人机恋阶段 2 PS2-06，spec §2 P3 + 判定⑦）。
///
/// 深模块：协议表面 = [ProactiveDeepLink]（payload 编解码纯函数）/
/// [FlutterLocalNotificationsChannel]（插件调用面，测试可注入 fake）/
/// [FlutterLocalNotificationsScheduler]（PS2-05 声明的
/// `ProactiveNotificationScheduler` 接口实现）+ [cancel] 扩展。实现内聚
/// 「深链参数严格类型化（SR-02）→ payload 零内容（SR-03）→ inexact 排程
/// （判定⑦）→ 锁屏摘要与 private visibility（SR-11）→ 失败摘要日志
/// （SR-12）」。
///
/// 平台薄层约定（对齐 M7 先例）：本文件只做编排与降级；真实 zonedSchedule
/// 排程归模拟器/真机冒烟验证，不进单测。iOS：Windows 无 macOS 路径，
/// `Platform.isAndroid` 分支守卫 + iOS 延后（初始化与 delegate 待 macOS）。
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/database/app_database.dart' show ProactivePlan;
import '../companion/proactive_message_service.dart'
    show ProactiveNotificationScheduler;

/// 主动消息深链 payload 编解码纯函数（SR-02 严格类型化 / SR-03 零内容）。
///
/// 格式：`conver://proactive?conversationId=<int>&messageId=<int>`。字段
/// 仅接受**十进制无符号正整数**（形态校验 + `int.tryParse`，SR-02 严格
/// 类型化），**无任何 `as int` 强转**；非法/缺失/非数字/非正值域 →
/// null（不抛）。payload 绝不携带 `ProactivePlans.content` 文本，仅两个
/// id（深链定位会话内消息；planId 由 OS 通知 id 承载，不重复进 payload）。
class ProactiveDeepLink {
  const ProactiveDeepLink._();

  /// 深链 scheme（`conver://`）。
  static const String scheme = 'conver';

  /// 深链 host（主动消息导航目标）。
  static const String host = 'proactive';

  /// 正值域形态：十进制无符号正整数（首字符非 0，拒绝 0x/+/-/空白/前导 0）。
  static final RegExp _positiveIntPattern = RegExp(r'^[1-9][0-9]*$');

  /// 严格正值域解析：仅接受十进制无符号正整数，否则返回 null（SR-02）。
  ///
  /// Dart `int.tryParse` 接受 `0x`/`+`/`-` 前缀与空白形态，仅靠 `> 0`
  /// 检查会漏网；故先对**原始字符串形态**做正则校验，合法后再 `int.tryParse`
  /// （形态合法但超 int64 上限 → 溢出返回 null）。纯函数，不抛。
  static int? _tryParsePositiveId(String raw) {
    if (!_positiveIntPattern.hasMatch(raw)) {
      return null;
    }
    return int.tryParse(raw);
  }

  /// 编码深链 payload。
  static String encode({
    required int conversationId,
    required int messageId,
  }) =>
      '$scheme://$host?conversationId=$conversationId&messageId=$messageId';

  /// 解析深链 payload；非法返回 null（不抛）。
  ///
  /// 校验链：可解析 URI（FormatException 兜底 → null）→ scheme/host 匹配
  /// → 两参数正值域校验（仅**十进制无符号正整数**：形态正则拒绝
  /// `0x`/`+`/`-`/空白/前导 0 → 再 `int.tryParse`，溢出 → null）。多余
  /// query 参数宽容忽略；重复参数取首个（`Uri.queryParameters` 语义）。
  static ({int conversationId, int messageId})? tryParse(String raw) {
    final Uri uri;
    try {
      uri = Uri.parse(raw);
    } on FormatException {
      return null;
    }
    if (uri.scheme != scheme || uri.host != host) {
      return null;
    }
    final conversationId =
        _tryParsePositiveId(uri.queryParameters['conversationId'] ?? '');
    final messageId =
        _tryParsePositiveId(uri.queryParameters['messageId'] ?? '');
    if (conversationId == null || messageId == null) {
      return null;
    }
    return (conversationId: conversationId, messageId: messageId);
  }
}

/// flutter_local_notifications 插件调用面（scheduler 的依赖注入点）。
///
/// 插件类本身是单例工厂（无公开构造，不可 extends），故抽象出本接口：
/// 生产默认经 [_PluginAdapter] 包真插件单例；测试注入 fake 覆写平台方法，
/// 对齐「平台薄层经 seam 隔离」约定。签名与插件 22.3.1 对应方法同形
/// （裁剪至本票用到的参数）。
abstract interface class FlutterLocalNotificationsChannel {
  /// 初始化（Android 通道创建等）；返回 true 表示成功。
  Future<bool?> initialize({required InitializationSettings settings});

  /// 按 TZDateTime 排程一次通知（inexact 模式由调用方指定）。
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  });

  /// 取消指定 id 的通知。
  Future<void> cancel({required int id, String? tag});
}

/// 真插件单例的生产适配（插件 22.3.1 无公开构造，经 factory 取单例）。
class _PluginAdapter implements FlutterLocalNotificationsChannel {
  _PluginAdapter(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  @override
  Future<bool?> initialize({required InitializationSettings settings}) =>
      _plugin.initialize(settings: settings);

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? payload,
  }) =>
      _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        androidScheduleMode: androidScheduleMode,
        payload: payload,
      );

  @override
  Future<void> cancel({required int id, String? tag}) =>
      _plugin.cancel(id: id, tag: tag);
}

/// 通知排程平台实现（PS2-05 `ProactiveNotificationScheduler` 接口落地）。
///
/// [schedule] 返回 bool：true = OS 排程已注册；false = 失败（平台/权限/
/// 初始化异常、非 Android、messageId 缺失）——调用方依据返回值走站内气泡
/// 兜底（P3），本方法**永不抛出**。失败与跳过路径只 debugPrint 摘要
/// （SR-12：不 print `ProactivePlans.content` 原文）。
class FlutterLocalNotificationsScheduler
    implements ProactiveNotificationScheduler {
  /// [channel] 注入点（测试用 fake；生产缺省包真插件单例）；[isAndroid]
  /// 平台守卫注入点（测试可锁 Android 路径；生产缺省 [Platform.isAndroid]）。
  FlutterLocalNotificationsScheduler({
    FlutterLocalNotificationsChannel? channel,
    bool Function()? isAndroid,
  })  : _channel = channel ?? _PluginAdapter(FlutterLocalNotificationsPlugin()),
        _isAndroid = isAndroid ?? (() => Platform.isAndroid);

  final FlutterLocalNotificationsChannel _channel;
  final bool Function() _isAndroid;

  /// 通知 channel id（主动消息专用；visibility private 防锁屏泄漏）。
  static const String _channelId = 'proactive_messages';
  static const String _channelName = '主动消息';
  static const String _channelDescription = '角色主动发来的消息提醒';

  /// 通知正文摘要（SR-11：不把 content 全文放入锁屏可见字段）。
  static const String _notificationTitle = '主动消息';
  static const String _notificationBody = '角色发来一条消息';

  /// 本地时区（zonedSchedule 必需；产品中文向固定 Asia/Shanghai，
  /// 全球设备时区适配留 PS2-08/后续——flutter_timezone 需新依赖）。
  static const String _localTimeZone = 'Asia/Shanghai';

  bool _initialized = false;

  /// 初始化通知通道与 timezone（单例幂等：重复调用不重复初始化）。
  ///
  /// 成功 true；平台通道缺失/初始化异常 → false 不抛（SR-12 摘要日志）。
  /// PS2-08 装配时显式调用一次；[schedule] 内部亦会按需懒初始化。
  Future<bool> initialize() async {
    if (_initialized) {
      return true;
    }
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(_localTimeZone));
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _channel.initialize(settings: settings);
      _initialized = true;
      return true;
    } catch (e) {
      debugPrint('proactive notify init failed: $e');
      return false;
    }
  }

  /// 排程 [plan] 的一次 OS 本地通知（判定⑦ inexact 模式）：
  ///
  /// - notificationId = plan.id（取消映射见 [cancel]）；
  /// - title/body 用固定摘要（SR-11），payload 仅 conversationId+messageId
  ///   （SR-03），绝不携带 `plan.content`；
  /// - `androidScheduleMode: inexactAllowWhileIdle`（宽容模式，不申请
  ///   SCHEDULE_EXACT_ALARM 权限面）；
  /// - channel `visibility = private`（锁屏只显摘要）；
  /// - 成功返回 true；任何异常（平台/权限/占位等）→ false 不抛出
  ///   （P3 站内兜底信号）。
  @override
  Future<bool> schedule(ProactivePlan plan) async {
    try {
      if (!_isAndroid()) {
        debugPrint('proactive notify skipped: iOS pending (macOS path)');
        return false;
      }
      final messageId = plan.messageId;
      if (messageId == null) {
        debugPrint('proactive notify skipped: missing message id');
        return false;
      }
      if (!await initialize()) {
        return false;
      }
      final scheduledDate = tz.TZDateTime.from(plan.scheduledAt, tz.local);
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
        ),
      );
      await _channel.zonedSchedule(
        id: plan.id,
        title: _notificationTitle,
        body: _notificationBody,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: ProactiveDeepLink.encode(
          conversationId: plan.conversationId,
          messageId: messageId,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('proactive notify schedule failed: $e');
      return false;
    }
  }

  /// 按 planId 取消已排程通知（notificationId == planId 映射）。
  ///
  /// 成功 true；平台异常 → false 不抛。供 SR-04 废弃/替换排程场景调用。
  Future<bool> cancel(int planId) async {
    try {
      await _channel.cancel(id: planId);
      return true;
    } catch (e) {
      debugPrint('proactive notify cancel failed: $e');
      return false;
    }
  }
}