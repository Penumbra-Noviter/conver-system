# ADR-0007：人机恋板块——内心独白（阶段 2）

## 决策背景

阶段 2 补角色「内心戏」：回复正文外带一段角色心理活动（`<thought>...</thought>` 标签包裹），提升角色立体度。核心矛盾：独白是「角色给自己看的」——绝不能泄漏进 UI/搜索/导出/记忆链路（spec 判定①/②），但 LLM 牌面不可控，必须**恒剥离**（开关只控制是否落库与是否要求产出）。

## 前提拆解（第一性原理）

- **不可变事实**：Flutter + 本地优先；`InnerThoughts` 表（PS2-01 冻结）字段 = characterId + messageId（FK Messages）+ content + createdAt；剥离必须零抛错路径（SR-05：剥离器抛不出异常）；切换开关 `inner_thought_enabled`（SR-09 白名单键，'true' 才开启）。
- **习得惯例**：顶层纯函数 + 服务编排（`extractThought` / `buildThoughtInstruction` 顶层 + `ThoughtService.stripAndPersist` 服务）——沿 `extractPersonaFactsWithProvider` 顶层 seam 先例；正则固定字面量（SR-13 线性复杂度，无嵌套量词）。

## 可选方案

### 剥离时机
1. 方案A 恒剥离（开关只控落库/指令）：防泄漏永远生效，成本恒定。
2. 方案B 开关关时不剥：省一次解析但泄漏面不可控（LLM 牌面不受开关约束）。

### 落库编排
1. 方案A `ThoughtService.stripAndPersist({characterId, messageId, content})` 单点编排（开关读 + 落库 + 降级）。
2. 方案B ChatService 直落 InnerThoughts：跨层污染，装配不单源。

### 与记忆链路的顺序
1. thought 剥离先于记忆标签解析（spec 判定②）：thought 内容中的 `<add>` 等永不被记忆误解析。
2. 记忆先于 thought：thought 内容可能污染记忆表。

## 最终选择

✅ 剥离 = **方案A 恒启用**（`extractThought` 顶层纯函数：成对闭合/开无闭合/多块截断/空独白丢弃，SR-05 契约全分支）
✅ 落库 = **方案A 服务单点**（`stripAndPersist`：检出 + 开关开 → 落 InnerThoughts；开关关 → debugPrint 不落库；无/空独白不落库）
✅ 顺序 = **thought 先于记忆**（ChatService `_persistAssistant`：`extractThought` 先行，记忆只吃剥离后正文）
✅ 指令 = `buildThoughtInstruction` system 块，`innerThoughtEnabled` 开才注入（PS2-07 注入链）
✅ 集成 = ChatService 顶层纯函数剥离 + 落库后以 `msg.id` 对原文重跑 `stripAndPersist` 取其落库副作用（stripAndPersist 签名需已存在消息 id——InnerThoughts.messageId FK 约束）

## 理由

- 恒剥离把「防泄漏」从开关语义中解耦：即使开关忘开/误关，正文/搜索/导出/记忆链路永不见 thought 块。
- thought 先于记忆保证独白内嵌文本（哪怕内容长得像记忆指令）不产生记忆副作用，两条链路零污染。
- 服务单点落库让「开关读取 + FK 约束 + 降级」内聚；ChatService 只编排顺序，不直接触碰 InnerThoughts 表。
- SR-05「剥离器抛不出异常」由纯字符串实现性质满足；1 MiB 上限（SR-13）防极端输出拖垮解析。

## 影响

- 正面：正文净化恒定、记忆链路零污染、开关语义清晰（默认关，用户显式开启才落库/要求产出）。
- 代价：剥离对回复走一次额外 O(n) 扫描（幂等纯函数，代价常数级）；空剥离结果落库为空串消息（守卫在剥离前，单测锁定预期）。