# TECH_DEBT: conver system

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 `TICKETS.md`（任务池，本项目任务文件名为 `TICKETS.md` 而非 `TO-TICKETS.md`）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 project-kickoff 步骤 0 预检（`AGENTS.md` §3 任务清单生命周期）。
>
> 本文件由 `TICKETS.md` 技术债区独立化迁移而来（2026-08-24，对齐 AGENTS.md §3 规范），原文完整保留审计追溯。

---

## 规范说明

### 条目格式

候选区每行对应一条技术债，含 6 个字段：

| 字段 | 含义 |
|------|------|
| **编号** | `F-N` 递增唯一 |
| **遗留项** | 什么问题、在哪个文件、当前影响 |
| **来源** | 产生此条目的审核/讨论/评审（如「波 1 增量审核」「期末四轴 Architecture」） |
| **强度** | `Strong` / `Worth exploring` / `Speculative`（见下方消费规则） |
| **状态** | `📝 待立项` / `🔄 进行中` / `✅ 已修` / `❌ 复核关闭` |
| **归属方向** | 此条目的业务方向（如 `前端渲染` / `流式链路` / `架构`），session 只认领匹配方向的条目 |

> 注：本项目历史条目使用旧强度词汇（「中」≈ `Worth exploring`、「低」/「低（信息性）」≈ `Speculative`）；历史条目保留原词，新条目按上方三档录入。

### 强度消费规则

| 强度 | 消费规则 |
|------|----------|
| **Strong** | 必入工单清单（下一轮 kickoff 的 plan-tickets 必须包含） |
| **Worth exploring** | 入候选由 Grilling 拍板（做/关闭），无默认方向 |
| **Speculative** | 可关闭，关闭须「`git grep` 复核现状仍成立」一句话理由 |

### 清出机制（防膨胀）

1. 候选区只留开放条目（📝 待立项 / 🔄 进行中）；条目处置后整行移出候选区，处置详情写入「技术债处置记录」
2. ❌ 关闭条目压缩：具复核价值的关闭项（防 review 重复提出的 Speculative 类）保留单行摘要于「复核关闭」表，其余直接删除
3. 处置记录按日期分节，滚动保留最近 **2 节**（同日多批次合并计为一节）；更早归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）
4. 清出动作绑定既有维护节点：每会话结束、commit 之前同步执行，不新增仪式

### 多 session 防污染

1. **任务所有权分离**：`TICKETS.md` 是唯一任务池（preflight 只读它）；本文件是候选池（只写不认领）
2. **条目归属标注**：每条目必填「来源」与「归属方向」，session 只认领自己方向匹配的条目
3. **消费显式化**：从候选区转工单必须带一句话理由（强度 + 方向匹配），禁止静默批量认领
4. **写冲突隔离**：候选人落盘写本文件（评审 session 独占），任务状态变更写 `TICKETS.md`（认领 session 独占），不同 session 写不同文件，不互踩

---

## 技术债候选区

> 当前 1 项待立项（F-90，来源：期末四轴 Standards/Architecture 非阻断发现）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-90 | syncGameCredentials 同时存在 doc 参数与 getDoc 参数（双通道轻度冗余，外部直调用契约 + 观察者惰性取用刻意保留；未来若 doc 仅剩外部直调用可收编为 getDoc-only 并迁移 5 个直调用例）；另 CLAUDE.md 测试基线散文句由主会话手工维护（doc_sync 不覆盖） | 期末四轴 Architecture/Standards | Speculative | 📝 待立项 | 架构 |

### 复核关闭（Speculative 类，防重复提议）

| 编号 | 遗留项（压缩摘要） | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-25 | `error_mapping.py:117` provider 前导空格——docstring 已声明「由调用方负责」，设计意图非缺陷 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-27 | `test_error_mapping_export.py` 文件末尾无换行符 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-28 | simulator_store/manifest/import 三个文件末尾缺失换行符 | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-32 | `simulator_import.py` `__all__` 含 read_manifest/write_manifest re-export | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-34 | `game_generator.py:286` 函数对象身份比较（`if check is _check_security`） | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-35 | `scan_generated_html` 被导出到 `__all__` 扩展公共 API 表面 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-36 | 校验失败时 scan 结果被丢弃，每次重试重新扫描 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭 |
| F-40 | game_generator `_build_suggestion` 六分支级联 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭 |
| F-46 | 空串 token-only 流的前端占位残留（空气泡） | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-48 | Scroll handler Feature Envy，建议提取 ScrollSpy 类 | 2026-08-26 期末四轴（Architecture A6） | Speculative | ❌ 复核关闭 |
| F-49 | `error-bar.js:67` `String(message)` 对可抛 `toString()` 的 message 会抛 TypeError | W1 增量审核 | Speculative | ❌ 复核关闭 |
| F-75 | String(null/undefined) 坍缩字面量参与 id 比较 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-76 | #b45309 对 --page 4.26:1 余量 0.11 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-79 | locateAndHighlight 顶层 children 遍历注记 | 期末四轴 Falsify | Speculative | ❌ 复核关闭 |
| F-87 | 文档区分「去重契约模块」与「深模块」标签 | 架构报告 2026-08-27 | Speculative | ❌ 复核关闭 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-08-27（技术债消费批次：F-82~F-89 全自动档 kickoff，3 做 5 关）

> 处置详情：3 项消费（F-83 对应工单 G1、F-88 对应工单 G2、F-89 对应工单 G3，见 TICKETS 归档）；5 项复核关闭——F-82 settleTurn refresh 收口边界不可行（onError/流中断路径绕过 settleTurn，注入刷新回调即扩参数面=同 F-65 被关闭项；stream-session.js:203 docstring 是对现状的诚实描述）；F-84 双并发守卫为有意分工（流式 isStreaming+停止态 UX vs 非流式 Set+禁用态，互斥闭环无缝、关 tab 自愈防锁死，chat.js:111 注释属实）；F-85 compareCoverage 归一化唯一消费方入参恒规整、防御分支生产不可达且行为被 simulator-adapt.test.js:264-279 契约锁定；F-86 avatarImgHtml 三层转义已单点化（唯一 avatarImgHtml 纯函数）且 format.test.js:205-241 契约锁定、未发现注入面，替代方案破坏纯函数契约且违反零行为变化；F-87 深模块标签通胀 git grep 复核现状成立但修复=10+ 文件头+两文档大面积美容性重标，头文件用法内部自洽（=具备 `__all__` 密封协议面））。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-82 | settleTurn refresh 收口（三处重复 → 注入回调统一） | 架构报告 2026-08-27 | Worth exploring | ❌ 复核关闭（2026-08-27：onError:414 与流中断分支绕过 settleTurn，收口留不一致契约；注入刷新回调即扩参数面=同 F-65 被关闭项，边界不可行） |
| F-83 | tabs.js DISPLAY_KEYS 与 getTabDisplay 双清单收敛 | 架构报告 2026-08-27 | Worth exploring | ✅ 已修（2026-08-27：工单 G1 单一展示字段表派生 DISPLAY_KEYS） |
| F-84 | chat.js 双并发守卫收敛 | 架构报告 2026-08-27 | Worth exploring | ❌ 复核关闭（2026-08-27：两守卫为有意分工——流式 isStreaming+停止态 vs 非流式 Set+禁用态，互斥闭环无缝、chat.js:111 注释属实） |
| F-85 | compareCoverage 防御归一放回调用边界 | 架构报告 2026-08-27 | Worth exploring | ❌ 复核关闭（2026-08-27：唯一消费方入参恒规整，防御分支生产不可达且被测试契约锁定） |
| F-86 | avatarImgHtml onerror 三层转义注入面 | 架构报告 2026-08-27 | Worth exploring | ❌ 复核关闭（2026-08-27：转义已单点化（唯一 avatarImgHtml）且格式测试契约锁定，无注入面，替代方案破坏纯函数契约） |
| F-87 | 文档区分「去重契约模块」与「深模块」标签 | 架构报告 2026-08-27 | Speculative | ❌ 复核关闭（2026-08-27：git grep 复核现状成立，但修复=大面积美容性重标无功能价值，头文件用法内部自洽） |
| F-88 | 停止路径三跳导航链补时序/职责表 docstring | 架构报告 2026-08-27 | Speculative | ✅ 已修（2026-08-27：工单 G2 stream-session.js 模块 docstring 补停止路径时序/职责表） |
| F-89 | flushObserverSync await 窗口写已分离 doc 窄竞态 | 期末四轴 Falsify | Speculative | ✅ 已修（2026-08-27：工单 G3 flushObserverSync getDoc 闭包失效守卫，断连后不写不计数，+1 测试） |

### 2026-08-27（技术债消费批次：F-80~F-81 全自动档 kickoff，轻量档 1 做 1 关）

> 处置详情：1 项消费（F-80 对应工单 01，见 TICKETS 归档）；1 项复核关闭（F-81：chat.js 3 处 `state.conversations.find(c => c.id === ...)` 严格 `===`——会话 id 全库惯例为严格 `===`（chat.js:655/797、conversation-activation.js:134、app.js:218、list-views.js:317、tabs.js 全套），两侧同源 JSON number（state id 经 parseInt/后端 JSON 均 number）无跨边界风险，严格比对是正确守卫——契约破裂会响亮失败而非被 String() 静默掩盖）。工单纯可读性重构零行为变化（Falsify 突变抽查还原 `a===b` 5 例转红证明测试敏感）。期末四轴 0 阻断放行；技术债候选区清零。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-80 | stream-session String() 字面比较重复 4×，可提 sameId helper | 期末四轴 Architecture | 低 | ✅ 已修（2026-08-27：工单提取模块私有 `sameId(a,b)` helper 替换 4 处调用点，不导出，测试零改动 73 例全绿） |
| F-81 | chat.js 3 处 state 同源严格 === 残留 | 期末四轴 Architecture | 低 | ❌ 复核关闭（2026-08-27：会话 id 全库严格 === 惯例，两侧同源 number 无跨边界风险，严格比对是正确守卫） |

### 2026-08-27（技术债消费批次：F-74~F-79 全自动档 kickoff，2 做 3 关）

> 处置详情：2 项消费（F-74+F-78 对应工单 A、F-77 对应工单 B，见 TICKETS 归档）；3 项复核关闭（F-75：`String(null/undefined)` 坍缩字面量——`replaceId != null` 与 `chat.js:224` `messageId !== undefined/null` 前置守卫使 null 不可达，且后端 int PK 数值 id 不可能等于 'null'/'undefined' 字面量，无假阳性碰撞；F-76：`.gg-config-warning-nav` 当前唯一渲染语境 `.modal`(bg=--bg) #b45309 对 --bg=4.61:1 达标、加深会改用户可见色而当前无合规问题，余量风险已在 style.css:2110-2111 F-73 注释记录；F-79：locateAndHighlight 顶层 children 遍历为 F-69 现状、format.js:114 气泡为直接子节点行为等价，未来嵌套包装时才需回退选择器）。工单 A 跨边界幂等早退激活为预期内正确性修复，工单 B 纯重构文案逐字。期末四轴 0 阻断放行；非阻断落债 F-80/F-81。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-74 | settleByPosition/mergeFreshList 幂等 id 比较严格 === | 期末四轴 Falsify | 低 | ✅ 已修（2026-08-27：工单 A :73/:173 改 String() 归一，跨边界幂等早退激活/定位命中，+6 用例含反向端与无假阳性） |
| F-75 | String(null/undefined) 坍缩字面量参与 id 比较 | 期末四轴 Falsify | 低 | ❌ 复核关闭（2026-08-27：replaceId/messageId 均前置守卫不可达，后端 int PK 不可能等于字面量，无假阳性） |
| F-76 | #b45309 对 --page 4.26:1 余量 0.11 | 期末四轴 Falsify | 低 | ❌ 复核关闭（2026-08-27：唯一渲染语境 .modal=--bg 4.61:1 达标，加深改可见色，注释已记录语境） |
| F-77 | warnReason 两处分支 Repeated Switches | 期末四轴 Standards/Architecture | 低 | ✅ 已修（2026-08-27：工单 B openModelSwitch 文案提取 WARN_REASON_MESSAGE 映射表，credentialWarnReason 不动，+4 逐字断言） |
| F-78 | id 归一策略三文件分叉 | 期末四轴 Architecture | 低 | ✅ 已修（2026-08-27：工单 A stream-session 侧 4 处全 String() 归一，error-bar/chat 已归一） |
| F-79 | locateAndHighlight 顶层 children 遍历注记 | 期末四轴 Falsify | 低（信息性） | ❌ 复核关闭（2026-08-27：F-69 已实现，当前气泡直接子节点行为等价，未来嵌套才回退） |

### 2026-08-27（技术债消费批次：F-64~F-73 全自动档 kickoff，8 做 2 关，4 工单 2 波）

> 处置详情：8 项消费（F-66/F-67 对应 T1、F-66/F-68 对应 T2、F-69~F-72 对应 T3、F-73 对应 T4，见 TICKETS 归档）；2 项复核关闭（F-64：`regenerateLastReply` 入口已查 `tab.isStreaming`，期末审核基于过时行号误报「流式在途无守卫」，git grep 复核现状守卫已存在；F-65：settleTurn 参数面膨胀架构重构——单文件深模块内聚未越界、重构承重重生成核心链路，与 F-37/F-38/F-42 先例同族成本收益不成比例）。波 1 审核两中危 Falsify 缺陷主会话直修（F-66 类型归一 String() 比对 + F-73 dark 语境回退）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-64 | regenerate 流式在途无互斥守卫（期末审核误报） | 期末四轴 | 中 | ❌ 复核关闭（2026-08-27：chat.js:760 入口已查 `tab.isStreaming`，守卫存在，git grep 复核现状） |
| F-65 | settleTurn/mergeFreshList 参数面膨胀架构重构候选 | 期末四轴 | 中 | ❌ 复核关闭（2026-08-27：单文件深模块内聚未越界，重构承重重生成核心链路，与 F-37/F-38/F-42 同族成本收益不成比例） |
| F-66 | mergeFreshList messageId===replaceId 幂等先于原位替换，新内容被吞 | 波5 增量审核 | 中 | ✅ 已修（2026-08-27：T2 顶替场景跳过幂等早退 + W1 直修 String() 类型归一，双回归测试） |
| F-67 | renderErrorBar data-conv 选择器裸插值抛 SyntaxError | 波1 增量审核 | 低 | ✅ 已修（2026-08-27：T1 遍历 + getAttribute 精确比对，error-bar 100% 覆盖） |
| F-68 | F-60 空回复 content==='' 短路被静默丢弃 | 波5 增量审核 | 低 | ✅ 已修（2026-08-27：T2 守卫放宽 messageId != null，stale 空回复写回/渲染） |
| F-69 | locateAndHighlight messageId 裸插值抛 SyntaxError | 波2 增量审核 | 低 | ✅ 已修（2026-08-27：T3 遍历 + dataset.messageId 比对） |
| F-70 | openModelSwitch state 更新未移出 save try（误标保存失败） | 波3 增量审核 | 低 | ✅ 已修（2026-08-27：T3 PUT 唯一保存 + 更新侧独立 try 记「更新失败」） |
| F-71 | credentialWarnReason 未知 protocol fail-open | 波3 增量审核 | 低 | ✅ 已修（2026-08-27：T3 switch default fail-closed 返回 'unknown'） |
| F-72 | cleanupStaleInFlight for...of 迭代删 Set | 期末四轴 | 低 | ✅ 已修（2026-08-27：T3 Array.from 快照迭代） |
| F-73 | .gg-config-warning-nav light 对比度 <4.5:1 | 波2 增量审核 | 低 | ✅ 已修（2026-08-27：T4 #b45309 对 --bg 4.61:1 + W1 直修 dark 语境回退 var(--warning) 6.98:1，style-css.test.js 静态断言） |

### 2026-08-26（增量审核 / 全量审查 / 期末四轴批次：F-23~F-63 存档）

> 处置详情：F-49~F-63 消费子批（2026-08-26，全自动档 13 做 2 关，10 工单 5 波，期末四轴 0 阻断）——13 项消费（F-50/51/52/53/54/55/56/57/58/59/60/62/63 各对应 TICKETS 归档工单 01-10）；2 项复核关闭（F-49：`error-bar.js:67 String(message)` 上游唯一调用方 `chat.js:renderSendError` 恒传字符串，Speculative 不可达；F-61：highlightTimer 定时器触发即自置 null、约 3s 自愈，零用户可见影响）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-23 | CODE_WIKI.md `tests_total:total` 标记漂移（pytest 714 + Vitest 979 + cargo 70 = 1763，doc_sync 全渠道重算） | 波 1 增量审核（Falsify 轴） | Strong | ✅ 已修（2026-08-26：全渠道环境运行 doc_sync，total 聚合为 1763，doc_sync --check 通过） |
| F-24 | CODE_WIKI.md §4.14 chat.py 职责叙述陈旧（仍含 llm_error_response 引用） | 波 1 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：§4.14 职责行更新，删除 llm_error_response 引用，改为指向 §4.19 error_mapping.py） |
| F-26 | `test_error_handler.py:146` 类 docstring 误导（写经 chat_error_response 映射，实际直调 llm_error_handler） | 波 1 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：docstring 更新为「直调 llm_error_handler，handler 委托 error_mapping」，测试全绿） |
| F-29 | `simulator_store.py:21` docstring G4 依赖清单「os/pathlib/shutil」与实际 import「logging/shutil/pathlib」不一致 | 波 2 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：docstring 修正为「logging/shutil/pathlib」，pytest 全绿） |
| F-30 | `simulator_import.py:28,30` json/os import 后全模块零使用，docstring 清单同步 | 波 2 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：删除 import json 和 import os，docstring 同步；grep 零命中，pytest 全绿） |
| F-41 | `game_generator.py:64` 自定义 `ValidationError` 命名遮蔽 pydantic 同名类型 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：重命名为 GenValidationError，测试 import 同步，pytest 62 passed） |
| F-43 | 前端 11 模块缺 `__all__` 导出声明 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：api.js/app.js/state.js/utils.js/modal.js/model-selector.js/confirm-dialog.js/export-dialog.js/character-form.js/character-wizard.js/character-templates.js 补齐 __all__，Vitest 979 全绿） |
| F-44 | game_generator docstring 协议表面(3) 与 `__all__`(5) 不一致 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：docstring 协议表面列表更新为 5 符号（含 ScanResult / scan_generated_html）） |
| F-25 | `error_mapping.py:117` provider 前导空格——docstring 已声明「由调用方负责」，设计意图非缺陷 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：prefix 构造明确写入 docstring，调用方负责，非缺陷） |
| F-27 | `test_error_mapping_export.py` 文件末尾无换行符 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：纯文件风格，零功能影响） |
| F-28 | simulator_store/manifest/import 三个文件末尾缺失换行符 | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：纯文件风格，零功能影响，与 F-27 同族） |
| F-31 | `_filename_limit()` 函数级 re-import 测试耦合设计 | 波 2 增量审核（Falsify 轴） | Worth exploring | ❌ 复核关闭（2026-08-26：函数级延迟导入是规避循环引用的故意手段，消除需解耦模块结构，成本高收益低） |
| F-32 | `simulator_import.py` `__all__` 含 read_manifest/write_manifest re-export | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：属设计意图，公共 API 表面，功能正确） |
| F-33 | `import_game` precomputed 路径对 ScanResult 字段无校验 | 波 3 增量审核（Falsify 轴） | Worth exploring | ❌ 复核关闭（2026-08-26：frozen dataclass 已保证字段类型结构有效，运行时校验无增值） |
| F-34 | `game_generator.py:286` 函数对象身份比较（`if check is _check_security`） | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：Python 合法惯用写法，sentinel 模式） |
| F-35 | `scan_generated_html` 被导出到 `__all__` 扩展公共 API 表面 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：刻意的 API 表面扩展，当前无外部调用方） |
| F-36 | 校验失败时 scan 结果被丢弃，每次重试重新扫描 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：重试重新扫描确保每次结果新鲜，属设计权衡） |
| F-37 | 双向模块级循环 import（conversation ↔ message） | 期末四轴三联 | Worth exploring | ❌ 复核关闭（2026-08-26：T-07 已知副作用，函数级延迟导入正确运作，消除需架构重构收益有限） |
| F-38 | simulator_store 兼容 shim 私有名跨模块 + 循环 import 函数级补丁（与 F-31 同族） | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：三向循环引用已有补丁管理，重构开销大） |
| F-39 | `_current_write_manifest()` 测试耦合间接层（与 F-31/F-38 同族） | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：故意的测试 seam，回归锚 monkeypatch 入口） |
| F-40 | game_generator `_build_suggestion` 六分支级联 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭（2026-08-26：分支简单明确，新增检查项自然扩展） |
| F-42 | setting.py `_CRED_SLOTS` provider 键知识外泄 | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：消除需注册层抽象，开销与收益不成比例，当前仅两协议槽位） |
| F-46 | 空串 token-only 流的前端占位残留（空气泡） | 期末四轴 Falsify | Speculative | ❌ 复核关闭（2026-08-26：纯前端化妆级问题，后端零污染） |
| F-47 | `initGuideSidebarScroll` 缺 type hints（`app.js:377`） | 2026-08-26 期末四轴（Standards ST-1） | Worth exploring | ✅ 已修（2026-08-26：补 `@returns {void}` 类型标注到 JSDoc） |
| F-48 | Scroll handler Feature Envy，建议提取 ScrollSpy 类 | 2026-08-26 期末四轴（Architecture A6） | Speculative | ❌ 复核关闭（2026-08-26：git grep 零命中 ScrollSpy，当前唯一滚动高亮逻辑在 55 行深模块内，无第二消费方 → Speculative Generality） |
| F-45 | O2 一致性缺口：chat 流式中途出错时 DB 落库 partial content 与 UI 错误气泡不一致 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：error 路径设 saved=True 阻止 finally 保存幽灵内容，测试 713 全绿） |
| F-49 | `error-bar.js:67` `String(message)` 对可抛 `toString()` 的 message 会抛 TypeError | W1 增量审核 | Speculative | ❌ 复核关闭（2026-08-26：git grep 复核唯一调用方恒传字符串，上游不可达） |
| F-50 | 流式多 tab 并发出错时错误条渲染到共享 `.chat-main` 区域互相覆盖 | W1 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-05 错误条会话隔离 `data-conv`，跨会话并存） |
| F-51 | `surfaceError` 置于 `render()` 之后，渲染抛错吞错误条 | W1 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-03 surfaceError 前置 render） |
| F-52 | 搜索跳转陈旧 messageId 无匹配早退不滚动 | W2 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-06 无匹配回落 scrollToBottom，产品决策） |
| F-53 | 模型切换刷新失败被误记「切换模型失败」 | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-07 保存/刷新语义分离独立日志） |
| F-54 | 凭证确认不对称（openai 态切 claude 无提示） | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-07 credentialWarnReason 对称化，产品决策） |
| F-55 | 生成器凭证预检 `.then` 无提交态守卫（竞态） | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-04 `if (generating) return` 守卫） |
| F-56 | `anthropic>=0.40.0` 无上界，1.x 移除 temperature 参数 | T6 实现发现 | Worth exploring | ✅ 已修（2026-08-26：P-01 SDK 调用不再传 temperature + 契约锁；运行时 .venv 实测 anthropic 1.0.0 创 create/stream 均无 temperature，适配为当前阻断修复；系统 python 0.116.0 测量属另一环境） |
| F-57 | regenerate 在途未阻并发流式发送（双请求） | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-08 handleSend 统一补查 nonStreamingInFlight） |
| F-58 | regenerate settleTurn 失败 anchor=null 尾部追加破坏顶替语义 | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-09 replaceId 原位替换） |
| F-59 | thinking 指示器未按 convId 隔离（finally 无条件移除） | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-08 `data-conv-id` + removeThinkingIndicator 定向移除） |
| F-60 | 重生成 stale revision 时 mergeFreshList 静默丢弃 | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-09 stale+anchor null 按 messageId 写回或 render:true） |
| F-61 | 重生成 re-render 不清 T2 高亮定时器（自愈） | W4 增量审核 | Worth exploring | ❌ 复核关闭（2026-08-26：定时器触发即自置 null，约 3s 自愈，零用户可见影响） |
| F-62 | `chat.py:328-339` regenerate 重复 `except LLMError` 死代码 | 期末四轴 | Worth exploring | ✅ 已修（2026-08-26：P-02 删除不可达分支，行为零变化） |
| F-63 | 生成器复用模拟器专属 `SEL_NAV_SETTINGS` 选择器（命名错位） | 期末四轴 | Worth exploring | ✅ 已修（2026-08-26：S-10 生成器自有 `SEL_GG_WARNING_NAV`，key-injector 侧不动） |

---

## 处置记录说明

- 候选区只保留开放条目（📝 待立项 / 🔄 进行中），处置后条目移入「技术债处置记录」按日期分节。
- ❌ 复核关闭的 Speculative 类条目在候选区「复核关闭」表中保留单行压缩摘要防重复提议（Worth exploring 类关闭理由完整保留于处置记录）。
- 处置记录滚动保留最近 2 节；更早的归档由 git 历史承担（`git log -p -- TECH_DEBT.md`）。
- 新条目从最大编号 +1 递增（当前最大 F-90），避免编号冲突。