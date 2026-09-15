# ADR-0003：人机恋板块（角色对话增强）——记忆与人设演化架构

## 决策背景

用户拍板新增「人机恋」板块，定位为**角色对话增强**（复用现有 V2 角色卡 + 聊天链 + drift），给角色加「独立记忆 + 抗 OOC + 可演化人设」。调研结论（[docs/ai-companion-research.md](ai-companion-research.md)）与动态脱壳源码级证据（`.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md`）已锁定方向。阶段 1 MVP 不含主动消息循环（留阶段 2）。

## 前提拆解（第一性原理）

- **不可变事实**：Flutter + drift + 本地优先 + 无自建后端 + `dart:io` 直连 HTTPS LLM（SSE）；现有 V2 卡导入、`buildMessages` 单点组装、drift 4 表 `schemaVersion=1`；记忆注入唯一挂点 = `ChatService._assembleMessages`；复用 `LLMProvider.generate`、`applyTemplateVars`、仓储 seam。
- **习得惯例**：Conver 用 drift（不模仿爱语的 JSON + SharedPreferences）；分阶段渐进交付。

## 可选方案

### 记忆机制
1. 方案A「prompt 指令驱动」：system prompt 教 LLM 用 `<add:>` / `<search:>` 自行存取记忆，客户端解析标签落库/检索。零额外 LLM 调用。
2. 方案B「后台反思提取」：每回合后异步调 LLM 提炼人格事实落库。需额外 LLM 调用。

### 记忆数据模型
1. 方案A「单表 + kind」：`MemoryEntries(kind, content, importance, ...)` 单表区分人格事实/情景记忆。
2. 方案B「多表」：persona_facts / episodic_memories / relationship_state / persona_revisions 四表。

## 最终选择

✅ 记忆机制 = **方案A prompt 指令驱动**（对齐爱语，零额外调用）
✅ 记忆模型 = **方案A 单表 `MemoryEntries`（kind 区分）+ `PersonaRevisions`（人设演化版本）**；relationship_state 留阶段 2

## 理由

- 爱语实证：`<add:>` / `<search:>` 指令驱动是有效记忆范式，用户为其付费（25 元/月记忆增强）。
- 零额外 LLM 调用 → 不增加主对话延迟/成本，符合移动端弱网/计费敏感。
- 单表 + kind 最简，MVP 阶段人格事实与情景记忆都是文本条目；关系状态表与主动消息/情感演化绑定，阶段 2 一起做。
- 抗 OOC 靠「每轮重注入人格事实（Profile 语义）」，不依赖一次性塞 system prompt。

## 影响

- 正面：复用现有角色/聊天链，增量小；记忆即时生效；抗 OOC 每轮生效。
- 代价：`schemaVersion` 1→2 migration；记忆由 LLM 在对话内自管，结构化程度低于后台反思（阶段 1.5 可补后台反思增强）。
