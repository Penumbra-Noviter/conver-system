# ADR-0005：人机恋板块——主动消息（阶段 2）

## 决策背景

阶段 1（ADR-0003）聚焦对话内记忆增强，阶段 2 补「角色主动找用户」的陪伴闭环：回合末异步规划一条「稍后送达」的主动消息（预生成内容 + OS 本地通知排程），用户点通知深链定位会话与消息。核心矛盾：移动端通知是平台能力（需插件排程、冷启动取参），但 LLM 内容生成与节流策略必须保持纯 Dart 可测。

## 前提拆解（第一性原理）

- **不可变事实**：Flutter + 本地优先 + `dart:io` 直连 HTTPS LLM；通知排程需 `flutter_local_notifications`（已随 PS2-06 引入钉版）；主动消息必须**先落库真实 assistant 消息**（进会话历史、深链可定位、重生成可回滚）；「LLM 失败不阻断回合收尾」是既有硬约束。
- **习得惯例**：`PersonaEvolutionService` / 反思的 seam 模式（typedef + 生产闭包包装 `generate` + 测试注入 fake）已证有效；`wireCredentialsResolver` 装配腿单一落点（C2 收敛）继续复用。

## 可选方案

### 内容生成时机
1. 方案A「回合内同步生成」：体验即时，但回合阻塞额外一次 LLM 调用。
2. 方案B「回合末异步规划」：fire-and-forget，失败降级返回 0，不阻断 `ChatDone`。

### 排程实现
1. 平台薄层独立服务（`notification_service.dart` 编排 + 插件调用面 seam）：纯 Dart 编排可单测，真插件只在 seam 之后。
2. ChatService 直调插件：耦合平台，不可无头测试。

### 内容存储
1. 落真实 assistant 消息 + `ProactivePlans` 计划行（messageId 回填）：进历史、可定位。
2. 只存计划行不落消息：点通知无会话内高亮锚点。

## 最终选择

✅ 生成时机 = **方案B 回合末异步规划**（挂 `ChatService._onProviderStreamDone`，与反思同构三路并列 fire-and-forget）
✅ 排程 = **平台薄层独立服务**（`FlutterLocalNotificationsScheduler` 实现 `ProactiveNotificationScheduler` seam；channel 注入点测试可 fake）
✅ 存储 = **落真实 assistant 消息 + scheduled 计划行 + messageId 回填**（PS2-05 实测语义：消息在规划时落库）
✅ 节流 = 三重守卫（每日上限 6 / 角色冷却 6h / 活跃窗口 7d，常量集中 `ProactiveThresholds`）
✅ 深链 = payload 仅 conversationId+messageId（SR-02 严格类型化、SR-03 零内容），消费端归属校验后导航（SR-03）
✅ 启动恢复 = 装配层 `restoreProactiveSchedules`：pending 未过期重建排程、已过期置 expired（SR-08）

## 理由

- 异步规划把「额外 LLM 成本」移出回合关键路径，与反思/计费敏感（ADR-0003）一致；失败降级 0 不产生未处理异常。
- 平台薄层隔离插件依赖，核心编排（节流/解析/落库/降级）在无头测试全绿（PS2-05/06 实测）。
- 深链只带两 id + 消费端归属校验：即使 payload 被篡改也只能定位到已存在的会话内消息，无法外带内容。
- 落真实消息让主动内容与普通回合内容同构（搜索/导出/重生成天然覆盖），notificationId = plan.id 提供取消映射。

## 影响

- 正面：会话历史完整、深链闭环、平台依赖收口到单文件薄层。
- 代价：OS 通知在 scheduledAt 由系统触发（inexact 模式，宽容性排程）；iOS 排程留待 macOS 路径（当前 `_isAndroid` 守卫降级）；通知正文固定摘要（SR-11 防锁屏内容泄漏），不做富文本。
