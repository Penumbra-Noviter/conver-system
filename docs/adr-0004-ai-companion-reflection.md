# ADR-0004：人机恋板块——后台反思提取（阶段 1.5）

## 决策背景

ADR-0003 阶段 1 的记忆机制选了「prompt 指令驱动」（零额外 LLM 调用），并把「后台反思提取」列为阶段 1.5 可选项。阶段 1 的代价已在 ADR-0003 注明：记忆由 LLM 在对话内自管，结构化程度低于后台反思——LLM 可能遗漏关键人格事实（未主动写 `<persona:>`），尤其当角色回复聚焦当下情绪而非沉淀稳定事实时。阶段 1.5 叠加后台反思，补强人格事实的结构化程度。

## 前提拆解（第一性原理）

- **不可变事实**：Flutter + drift + 本地优先 + `dart:io` 直连 HTTPS LLM；`MemoryEntries` 单表（persona_fact / episodic）已冻结 `schemaVersion=2`，反思产物直接落现有 `persona_fact`，零 schema 变更；`LLMProvider.generate`（非流式）可复用做反思调用；「记忆失败不阻断主回复」是既有硬约束。
- **习得惯例**：阶段 1 prompt 指令驱动零额外调用（ADR-0003 计费敏感理由）；`PersonaEvolutionService` 的 seam 模式（typedef + 生产闭包包装 `generate` + 测试注入 fake）已证有效，反思沿用同构 seam。

## 可选方案

### 触发时机
1. 方案A「每回合反思」：记忆即时，但每回合多 1 次 LLM 调用，成本约翻倍。
2. 方案B「每 N 回合反思」：成本可控、跨重启安全（幂等判定），记忆渐进更新。
3. 方案C「仅手动触发」：零自动成本，但记忆增强依赖用户主动操作，体验断档。

### 默认开关
1. 默认开启：开箱即用，但用户可能意外产生额外 LLM 费用。
2. 默认关闭：成本可控，用户显式开启。

### 产出范围
1. 仅人格事实（persona_fact）：聚焦抗 OOC 刚需，产出少、成本低。
2. 人格事实 + 情景记忆（episodic）：更完整，但反思输出更多、成本更高。

## 最终选择

✅ 触发 = **方案B 每 N 回合反思（N=6）**，以对话 user 消息数 `% 6 == 0` 幂等判定（无需新状态、无需新列、跨重启安全）
✅ 默认 = **关闭**（settings 键 `memory_reflection_enabled`，用户显式开启）
✅ 产出 = **仅人格事实**（落 `MemoryKind.personaFact`）
✅ 去重 = 与已有 `persona_fact` 内容完全匹配过滤，不落重复
✅ 异步 = 挂点 `ChatService._onProviderStreamDone` 落库后 `unawaited` fire-and-forget，失败降级 `debugPrint` 不阻断主回复
✅ 输出格式 = JSON 字符串数组，三级容错解析（对齐 `document_parse_service.extractJsonFromLlm` 的「直接 → ```json 块 → 方括号范围」思路，目标为数组）

## 理由

- 每 N 回合 + 默认关闭，把「额外 LLM 成本」交回用户控制，与 ADR-0003「移动端弱网/计费敏感」一致。
- 仅人格事实聚焦 P0 抗 OOC 刚需（调研 §二结论），情景记忆提炼留待需要时再扩，不一次性放大成本面。
- 反思 = 补 LLM 主动 `<persona:>` 标签的遗漏，与阶段 1 互补而非替代：两链路写入同一 `persona_fact`，注入端（`MemoryService.buildInjection`）零改动即自动受益。
- seam 化让反思纯 Dart 可单测，生产 LLM 调用与测试 fake 隔离，不触碰 wire。

## 影响

- 正面：补强人格事实结构化程度，抗 OOC 更稳；复用现有表/注入链/仓储/seam，增量小。
- 代价：用户开启后每 6 回合多 1 次后台 LLM 调用（成本/延迟均在后台异步，不阻塞主回复）；反思失败静默降级（log 不告警 UI）。
