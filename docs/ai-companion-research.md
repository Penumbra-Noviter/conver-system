# 人机恋 / AI 陪伴方向调研与设计建议

> 日期：2026-09-15
> 目标：为 Conver System 移动端新增「人机恋」模块（独立记忆 + 思维链 + 可演化人设）做方向调研与落地设计。
> 方法：四线并行——离线逆向「爱语」APK、全网技术调研、社媒需求调研、现有代码 gap 分析。
> 相关产物：静态逆向报告 `.scratch/aiyun-reverse/REPORT.md` + 动态脱壳源码级报告 `.scratch/aiyun-unpack/DYNAMIC_UNPACK_REPORT.md`（样本已动态脱壳 dump 出 4964 类业务 dex）。

## 一句话结论

「人机恋」方向成立，但**必须把三要素拆开押注**：独立记忆 + 抗 OOC 人设是刚需（已被用户真金白银验证），应作为产品主轴；「思维链/内心戏」证据最弱、伪需求风险最高，只能作为差异化功能小步灰度，不能当核心卖点。技术落点**不是向量库**，而是「SQLite 分层结构化记忆 + LLM 后台反思提取 + 每轮重注入人格事实 + 主动消息循环」。

## 一、四线交叉洞察

### 1. 逆向「爱语」证实：真正的人机恋产品不靠向量库，也不做本地 CoT

「爱语」= `com.shuoshuo.aiyu`，原生 Android（Java/Kotlin，非 Flutter），腾讯 SecShell 加固（业务 dex 被抽取，静态只能拿 manifest + 明码 JS 模块 + 协议文本 + so 符号）。

其记忆与情感实现，逆向证据显示：

- **记忆 = 短期滑窗（context_size 200K）+ 用户可编辑长期记忆条目 + 可选范围摘要**，由 prompt 指令 `<add:>`/`<search:>` 驱动，无向量库/RAG/embedding；业务数据存储为 **JSON 文件 + SharedPreferences，非 SQLite**。
- **情感/思维链 = 全部委托 LLM，但确有 CoT**：无本地状态机，但有 `DEFAULT_FIRST_PERSON_THINKING_PROMPT`（第一人称意识流思维链）并消费 DeepSeek R1 `reasoning_content`；CoT 是内部回复质量手段、非用户可见卖点。所谓「病娇」通过**主动消息循环**编排：定时触发 → LLM 决策「是否发 + 等待时长」→ 到点再触发生成主动消息。
- **具身性**才是它区别于普通角色聊天的地方：Live2D 形象、本地 sherpa-onnx 流式 ASR、OCR 截屏感知、使用时长统计、锁屏/震动/悬浮/主动消息等行为执行。
- **LLM 接入**：不自营模型，用户自配 OpenAI 兼容 API 直连，SSE 流式，支持 prompt caching，TTS 默认 SiliconFlow。与 Conver 现有 M2/M5「SSE 直连 + key 注入 + 模型清单」架构同构。

复刻启示：先做「分层记忆 + 主动消息循环 + 人设 system prompt 模板 + 指令系统」四项（纯 Dart/协议层）；语音/Live2D/QuickJS 沙箱是自研壁垒，后续可选高成本项。

### 2. 技术调研：记忆落点是「SQLite 分层 + 后台反思」，不是向量 RAG

LangChain LangMem 的三类记忆模型是核心锚点：语义记忆（事实，Collection 无界知识库 / Profile 单文档最新状态）、情景记忆（经历，含 thoughts，做 few-shot）、程序记忆（人格/指令，可演化）。

针对「Flutter 双端 + 本地优先 + 无自建后端」约束：

- **不上向量检索**。AI 陪伴记忆是「单角色几百条人格事实 + 若干情景摘要 + 关系状态」，不是海量文档库，LLM 提取 + SQLite 结构化存储 + 时间/关键词/全文检索足够。
- 本地向量对双端 Flutter 不可行（`ai_edge_rag` 明确 Android-only，需打包数十~数百 MB 模型）；向量 RAG 只列为阶段 3 可选的远端 embedding 增强。
- **抗 OOC 的关键是每轮（或每 N 轮）重注入人格事实**，而非一次性塞 system prompt（Character.AI 的 Standard Persona Syndrome 是公开痛点）。
- 内心独白两种实现：同一次调用内嵌 `<thought>` 标记（零额外延迟，需客户端剥离）/ 独立调用（可驱动状态更新，双倍成本）。

### 3. 社媒需求：记忆与抗 OOC 是刚需，思维链是待验证项

（一手 UGC 受限：本机无 mediacrawler，小红书/知乎正文与评论区不可得，结论对「记忆/OOC/付费」有直接正文证据 High，对「内心戏」缺一手证据 Low。）

| 需求 | 判定 | 置信度 | 依据 |
|---|---|---|---|
| 独立记忆（记得我说过的话） | **P0 真刚需** | High | 失忆是全网最高频、情绪最强烈的投诉；用户「为了让我养的 AI 不失忆，每月交 25 元」；C.AI 刚补三层记忆 |
| 抗 OOC（人设不崩） | **P0 真刚需** | High | 换模型「换魂变白开水」是核心痛点；人设被乙女用户定性为角色的「魂」 |
| 连续性/所有权/可迁移 | **P0–P1 真刚需** | High | 星野 Relink、豆包清零「跑路 ptsd」；「永不失联」自配 API 教程高赞 |
| 可演化人设/感情渐进 | P1 真需求但分层 | Medium | 重度用户愿调教，轻度用户要开箱即用；「渐进」缺直接证据 |
| 思维链/内心戏 | **P2 伪需求风险最高** | Low | 无用户点名要「内心独白」的公开诉求；对应真痛点实为「共情空洞/套路化」 |

核心付费逻辑：用户为**确定性/连续性/所有权**付费，而非为功能付费。目标用户以女性（乙女/梦女/国乙玩家）为主，场景为深夜倾诉、恋爱体验、角色扮演。

### 4. 现状 gap：人格静态，但接入面已具备

Conver 现有 drift 仅 4 表（characters/conversations/messages/settings），无任何长期记忆/关系/内心活动表；人格落在 `characters.personality`，创建后仅用户手动编辑或重导入可改，**静态**。

可复用与接入点：

- 记忆注入挂点 = `ChatService._assembleMessages` → `prompt.dart::buildMessages`（system → scenario → mesExample → 滑窗历史 → postHistoryInstructions → user）。
- 复用 `LLMProvider.generate`（非流式，做摘要/反思/内心独白）、`buildMessages`/`CharacterData`、`applyTemplateVars`、drift 转换器与仓储 seam、`CredentialsResolver` 装配链。
- 需新增：记忆表 + 仓储 + `lib/services/memory/`（MemoryService）+ `lib/services/cognition/`（Thought/PersonaEvolution）+ 视图入口。
- 风险：`tables.dart` 声明 schemaVersion=1 冻结，加表需升 schemaVersion + 写 migration（脱离桌面锚点，需 ADR）；每回合额外 LLM 调用带来延迟/成本，需可开关 + 失败降级不阻断主回复；人设演化需版本化 + 用户确认闸门。

## 二、需求验证结论（真 / 伪）

把用户最初设想「人设完善 + 独立记忆 + 思维链」拆开：

1. **独立记忆 = 真需求、可押注**（P0）。失忆投诉 + 25 元/月付费 + 头部产品补记忆，三方印证。
2. **人设完善 = 真需求但拆两层**。「抗 OOC/不崩」是刚需（P0）；「用户主动打磨/可演化」是分层需求（P1）——重度用户要深度定制，轻度用户要开箱即用，**不要逼所有用户手动打磨**。
3. **思维链/内心戏 = 暂不能判真需求，伪需求风险最高**（P2）。无用户点名诉求；它对应的真痛点是「AI 共情空洞/套路化」，内心戏只是候选解法之一。需先用小红书/B 站评论等一手 UGC 验证，再决定是否投入。

## 三、推荐架构（分阶段）

约束：Flutter 双端 + drift/SQLite + 本地优先 + 无自建后端 + `dart:io` 直连 HTTPS LLM + 已有 V2 卡导入与 SSE 流式链。

### 数据模型（drift，schemaVersion 1 → 2 + migration）

- `PersonaFacts`：`id, characterId(FK), content, source, importance, createdAt, updatedAt`——人格事实/Profile（单条可编辑，LangMem Profile 语义）。
- `EpisodicMemories`：`id, characterId(FK), content, thoughts, importance, createdAt`——情景记忆（关键事件 + 当时内心想法），做 few-shot。
- `RelationshipState`：`id, characterId(FK) 唯一, stateJson(TEXT), updatedAt`——关系/情感标量（陌生→熟悉→亲密 + 好感/信任）。
- `PersonaRevisions`：`id, characterId(FK), personalitySnapshot, reason, createdAt`——人设演化版本历史（可审阅/回滚）。

（内心活动建议独立表 `InnerThoughts`，不塞进 messages 三角色契约，避免污染搜索/导出语义。）

### 服务层（`lib/services/`，纯 Dart 深模块，可单测）

- `MemoryService`：协议表面小（`summarizeTurn` / `retrieveMemories` / `consolidate`），内部做「每回合后异步抽取 → 落库 → 检索注入」。
- `PersonaEvolutionService`：触发演化 → `generate` 产出新人格事实 → 写 `PersonaRevisions`，需用户确认闸门。
- `ThoughtService`：内心独白（可选，MVP 用内嵌 `<thought>` 而非独立调用）。
- 挂点：`ChatService._assembleMessages` 在 buildMessages 前 `await memoryService.retrieve(...)`，把记忆/人格事实拼进 system 块。

### 分阶段落地

- **阶段 0（现状）**：静态卡 + 滑窗。已验证。
- **阶段 1 MVP（对标 P0 刚需）**：新增 drift 记忆表 + 后台异步反思提取（会话结束/空闲时调 LLM 提炼人格事实与情景记忆）+ prompt 注入（V2 卡 + Profile + 摘要 + 滑窗）。依赖现有 LLM + drift，主对话零延迟影响，每会话多 1 次后台 LLM 调用。
- **阶段 2（人机恋灵魂 + 差异化）**：主动消息循环（定时触发 → LLM 决策 → 主动消息 + 通知）+ 关系状态机 + 日记/回忆（Episodic few-shot）+ 内心独白内嵌（作为小步灰度，不押注）。依赖阶段 1 记忆表。
- **阶段 3（可选高成本）**：远端 embedding 向量检索（跨会话语义召回 + 跨会话人格演化）+ 语音 ASR/TTS + Live2D（爱语的自研壁垒，需权衡包体积与授权成本）。

## 四、风险与待补证据

- 已动态脱壳还原业务 dex（4964 类），拿到 endpoint / system prompt 片段 / 存储机制源码级证据；「SQLite 表结构」假设被推翻（实为 JSON 文件 + SharedPreferences）。报告仅供自研参考，不复制/二次分发/破解该商业软件。
- 社媒一手 UGC 缺口：小红书/B 站评论需 mediacrawler（本机未装，需登录 cookie）或发帖做需求探针，用于验证「内心戏/思维链」是否值得投入。
- 每回合额外 LLM 调用（提取/摘要/内心独白）带来延迟与成本，移动端需可开关 + 失败降级（记忆/CoT 失败不阻断主回复）。
- 人设演化有漂移/失控风险，必须版本化 + 用户确认闸门，不能无条件回写 `personality`。

## 五、引用来源

- LangMem 概念：https://langchain-ai.github.io/langmem/concepts/conceptual_guide/
- Character Card V2 规范：https://raw.githubusercontent.com/malfoyslastname/character-card-spec-v2/main/spec_v2.md
- SillyTavern World Info：https://docs.sillytavern.app/usage/core-concepts/worldinfo/
- 小冰系统设计论文：https://arxiv.org/pdf/1812.08989v1.pdf
- Character.AI 人格漂移：https://www.memorylake.ai/en/blogs/character-ai-forgets-persona
- MemGPT 论文：https://arxiv.org/abs/2310.08560
- Inner Thought 内心推理 benchmark：https://arxiv.org/html/2503.08193v1
- Flutter 本地 RAG（Android-only）：https://pub.dev/packages/ai_edge_rag
- 用户需求证据（失忆/OOC/付费/所有权）：https://www.163.com/dy/article/JOTFFI5O055040N3.html 、https://post.smzdm.com/p/a5rdz37l/ 、https://www.tmtpost.com/7995188.html 、https://www.163.com/dy/article/KR7L8TOH0530WJIN.html
