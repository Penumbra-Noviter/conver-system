/// 主动消息深链接 · 启动编排业务域（F-123：从装配文件 app.dart 下沉）。
///
/// 归属声明：主动消息完整接线圈（payload 读取 → 冷启动/热态消费 → 归属校验
/// → 送达收口 → 导航；启动排程恢复与初始化）只允许存在于本模块。装配文件
/// （app.dart）只保留 Provider 闭包接线与 ScaffoldMessenger 桥接基础设施
/// （rootScaffoldMessengerKey / showScheduleFailedNotice），不再承载业务。
///
/// 模块为深模块：协议表面 = [ProactiveDeepLinkNavigator] /
/// [AppDeepLinkNavigator] / [readProactiveLaunchPayload] /
/// [consumeProactiveLaunchDeepLink] / [consumeProactiveNotificationResponse] /
/// [handleProactiveDeepLink] / [restoreProactiveSchedules] /
/// [startProactiveNotifications] 八个符号。
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show
        DidReceiveNotificationResponseCallback,
        FlutterLocalNotificationsPlugin;

import '../../data/database/tables.dart' show ProactivePlanStatus;
import '../../data/repositories/companion_repository.dart';
import '../../data/repositories/message_repository.dart';
import '../../view_models/shell_navigation.dart';
import '../../views/chat/chat_controller.dart';
import '../notifications/notification_service.dart'
    show FlutterLocalNotificationsScheduler, ProactiveDeepLink;
import 'proactive_message_service.dart'
    show ProactiveMessageService, ProactiveNotificationScheduler;
import 'relationship_service.dart';

/// 深链导航意图 seam（PS2-08，可测注入；生产实现包 ShellNavigation +
/// ChatController，测试注入 fake recorder 断言两动作）。
abstract interface class ProactiveDeepLinkNavigator {
  /// 切换到聊天 tab（对话列表）。
  void selectChatTab();

  /// 打开 [conversationId] 对话并（可选）高亮 [highlightMessageId] 消息。
  Future<void> openConversation(int conversationId, {int? highlightMessageId});
}

/// 深链导航生产实现（PS2-10）：包 [ShellNavigation] + [ChatController]——
/// select chat = 切聊天 tab；openConversation = 打开会话（可高亮消息）。
class AppDeepLinkNavigator implements ProactiveDeepLinkNavigator {
  /// [navigation] tab 状态；[chatController] 会话打开/高亮入口。
  AppDeepLinkNavigator({
    required this.navigation,
    required this.chatController,
  });

  final ShellNavigation navigation;
  final ChatController chatController;

  @override
  void selectChatTab() => navigation.select(ShellTab.chat);

  @override
  Future<void> openConversation(int conversationId, {int? highlightMessageId}) {
    return chatController.openConversation(
      conversationId,
      highlightMessageId: highlightMessageId,
    );
  }
}

/// 冷启动通知 payload 读取薄封装（PS2-10 验收 8）：notification_service 标
/// 只读（PS2-06 未提供取参通道），真通道在此封装——flutter_local_notifications
/// 插件单例调 [FlutterLocalNotificationsPlugin.getNotificationAppLaunchDetails]，
/// 取 `notificationResponse.payload`（SR-03 零 content：payload 仅两 id）。
///
/// 插件缺位（测试环境 MissingPluginException）/ 平台异常 → null 静默返回
/// （验收 8：取参失败静默跳过，不阻塞 App 启动）。
Future<String?> readProactiveLaunchPayload({
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  try {
    final details = await (plugin ?? FlutterLocalNotificationsPlugin())
        .getNotificationAppLaunchDetails();
    return details?.notificationResponse?.payload;
  } catch (e) {
    debugPrint('读取冷启动通知 payload 失败: $e');
    return null;
  }
}

/// 冷启动深链消费（PS2-10 装配层接线）：取参 → 无 payload / 取参失败静默
/// 跳过（验收 8）→ 否则交 [handleProactiveDeepLink]（归属校验 + 导航）。
Future<void> consumeProactiveLaunchDeepLink({
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
  Future<String?> Function()? readPayload,
}) async {
  final String? payload;
  try {
    payload = await (readPayload ?? readProactiveLaunchPayload)();
  } catch (e) {
    debugPrint('读取冷启动通知 payload 失败: $e');
    return;
  }
  if (payload == null || payload.isEmpty) {
    return;
  }
  await handleProactiveDeepLink(
    payload: payload,
    navigator: navigator,
    messageRepository: messageRepository,
    proactiveMessageService: proactiveMessageService,
    relationshipService: relationshipService,
  );
}

/// 热态通知点按深链消费（F-84 桥接，PS2-10 装配层接线）：与
/// [consumeProactiveLaunchDeepLink] 同构，payload 来源为
/// `NotificationResponse.payload`（同步取值，非 Future 读取）。
///
/// payload null/空 → 静默（零导航）；非空 → [handleProactiveDeepLink]（归属
/// 校验 → markDelivered → recordProactiveMessageOpened +5 → 导航高亮，异常
/// 降级内建）。热态（App 存活）与冷启动（getNotificationAppLaunchDetails）
/// 互斥，共享同一消费函数与装配组件（导航/仓储/两服务）。
Future<void> consumeProactiveNotificationResponse({
  required String? payload,
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
}) async {
  if (payload == null || payload.isEmpty) {
    return;
  }
  await handleProactiveDeepLink(
    payload: payload,
    navigator: navigator,
    messageRepository: messageRepository,
    proactiveMessageService: proactiveMessageService,
    relationshipService: relationshipService,
  );
}

/// 处理主动消息通知深链（PS2-08 验收 3 + SR-03 归属校验）。
///
/// payload 解析成功且 messageId 属于 payload.conversationId 的对话（经
/// [messageRepository] 既有查询，不直接写库、不发送）→ select chat +
/// openConversation(conversationId, highlightMessageId: messageId)；
/// payload 非法或归属校验失败 → 回落普通导航（仅 select chat 打开对话列表）。
/// 消费端不读任何 content 参数（SR-03 零内容；payload 仅两 id）。
///
/// W5 F2（P3）：openConversation 纳入异常保护——导航抛错 debugPrint 降级，
/// 不崩溃、不回退（tab 已切到聊天列表，用户可自行选择会话）。
Future<void> handleProactiveDeepLink({
  required String payload,
  required ProactiveDeepLinkNavigator navigator,
  required MessageRepository messageRepository,
  ProactiveMessageService? proactiveMessageService,
  RelationshipService? relationshipService,
}) async {
  final parsed = ProactiveDeepLink.tryParse(payload);
  if (parsed == null) {
    navigator.selectChatTab();
    return;
  }
  try {
    final messages = await messageRepository.getMessages(parsed.conversationId);
    final belongs = messages.any((m) => m.id == parsed.messageId);
    if (!belongs) {
      navigator.selectChatTab();
      return;
    }
    // C1 送达收口（SR-07）：归属校验通过 = 通知已被用户点按触达 → 置 sent +
    // sentAt（节流计数/冷却口径生产可达），并记录「点开主动消息 +5」
    // （P4 启发式，PS2-03 recordProactiveMessageOpened 消费）。失败仅
    // debugPrint 不阻断导航；缺省 null（测试形态）跳过。
    if (proactiveMessageService != null) {
      try {
        final delivered = await proactiveMessageService
            .markDeliveredByMessageId(parsed.messageId);
        if (delivered != null && relationshipService != null) {
          await relationshipService.recordProactiveMessageOpened(
            delivered.characterId,
          );
        }
      } catch (e) {
        debugPrint('主动消息送达收口失败（不阻断导航）: $e');
      }
    }
  } catch (e) {
    debugPrint('主动消息深链归属校验失败，回落对话列表: $e');
    navigator.selectChatTab();
    return;
  }
  navigator.selectChatTab();
  try {
    await navigator.openConversation(
      parsed.conversationId,
      highlightMessageId: parsed.messageId,
    );
  } catch (e) {
    debugPrint('主动消息深链打开会话失败（已切聊天 tab）: $e');
  }
}

/// 启动排程恢复（SR-08 P0）：只重建「pending 且未过期」的 OS 排程。
///
/// - pending 且 scheduledAt ≤ [now] → 置 expired（不排不发送）；
/// - pending 且未过期 → [scheduler].schedule 重建一次；
/// - sent/expired/dropped 不在 scheduled 列表 → 天然不重排（零触碰）。
/// 单计划排程抛错或置 expired 抛错 → 降级 log 跳过，其余计划继续恢复，
/// 不整体上抛（SR-08：抛错计划保持原状态 scheduled，不重排不置位）。
///
/// F-151：过期判定改由 [CompanionRepository.listOverdueScheduled] 单源
/// （谓词进 SQL，`scheduledAt <= now` 含端点 = 现状 `!isAfter(now)` 语义），
/// 与回合入口 `_reconcileOverdue` 日期口径自动一致；不再 Dart 侧逐计划重写
/// 同一过期规则（全表拉入内存再过滤形态退出，对齐 F-125 先例）。
Future<void> restoreProactiveSchedules({
  required CompanionRepository companion,
  required ProactiveNotificationScheduler scheduler,
  required DateTime now,
}) async {
  final pending = await companion.listPlansByStatus(
    ProactivePlanStatus.scheduled,
  );
  final overdueIds = {
    for (final plan in await companion.listOverdueScheduled(now)) plan.id,
  };
  for (final plan in pending) {
    if (overdueIds.contains(plan.id)) {
      try {
        await companion.updatePlanStatus(plan.id, ProactivePlanStatus.expired);
      } catch (e) {
        debugPrint('启动排程恢复置 expired 失败（计划 ${plan.id} 保持 scheduled）: $e');
      }
      continue;
    }
    try {
      await scheduler.schedule(plan);
    } catch (e) {
      debugPrint('启动排程恢复失败（计划 ${plan.id} 保持 scheduled）: $e');
    }
  }
}

/// 启动路径主动通知初始化（PS2-08 验收 4 + F-84 热态接线 + F-92 告警接线）：
/// scheduler 初始化（幂等；首次调用即透传热态回调，晚到装配经重挂生效）
/// + SR-08 排程恢复；任一失败 debugPrint 降级，不阻断 App 启动。恢复路径
/// 不接失败回调（SR-08 保持静默）。
///
/// F-92：热态回调丢失告警 seam 在此接线消费——不可补救路径（重挂失败）经
/// [FlutterLocalNotificationsScheduler.initialize] 的 onHotCallbackLost
/// 上达装配方并 debugPrint 记录（不得静默）；reason 为失败摘要，不含
/// payload 内容（SR-12）。
Future<void> startProactiveNotifications(
  FlutterLocalNotificationsScheduler scheduler,
  CompanionRepository companion, {
  DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
}) async {
  try {
    await scheduler.initialize(
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onHotCallbackLost: (reason) => debugPrint('主动通知热态回调丢失（不可补救）: $reason'),
    );
    await restoreProactiveSchedules(
      companion: companion,
      scheduler: scheduler,
      now: DateTime.now(),
    );
  } catch (e) {
    debugPrint('主动通知启动初始化失败: $e');
  }
}
