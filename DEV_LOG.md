# Conver System 移动端 — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TO-TICKETS.md](TO-TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）

## 滚动机制（2026-09-21 固化）

- **排序**：一律按日期倒序（最新在前）；同日多批次按时间序
- **保留**：最近 10 个批次节保留完整细节；更早的折叠为「历史归档索引」表格（每节一行：日期/批次名/一句话摘要）
- **溯源**：被折叠的批次节原文由 git 历史承担——`git log -p -- DEV_LOG.md` 可追溯任意节
- **防膨胀**：完整节超过 10 节时最旧的折叠入索引；索引行数上限 100，超限删最旧行

---

## 模拟器简介自动生成批次（2026-09-22 — 用户「卡片简介太模板化，能否自动从游戏文件识别内容并总结成介绍」拍板混合方案）

- **批次源**：用户截图反馈模拟器卡片简介呆板（8 张卡片 5 张被省略号截断，句式统一「AI 驱动的X（kw1/kw2/kw3），需配置 AI 接口；存档走 localStorage」——后半句是开发技术细节混入用户文案）。探索实证：22 款种子简介全部硬编码于 `assets/simulators/manifest.json`（人工模板句）；导入游戏 description 为空（manifest_parser 宽容降级空串，卡片空白）；游戏内容载体在 JS 内 prompt 设定段（蛛网之影「世界观」13 处）而非可见 UI（每款仅 400~500 字符按钮词）。基线 `d2a1c9c`。
- **方案拍板**：AskUserQuestion 三选一 → **混合方案**（规则提取即时兜底恒开 + LLM 精修可选开关 + 结果写回 manifest 缓存；种子 22 款一次性生成固化）。备选被否：纯规则（无文采）/ 纯人工（不满足「自动」）。
- **落地五块**：① `game_summary_extractor.dart` 纯函数提取器（`<title>` + 可见文本 + JS prompt 段关键词窗口抽取，容错逐级降级不抛，`maxFallbackChars=60` 码点截断不劈代理对）；② `game_description_generator.dart` LLM 精修（仿 GameGenerator 链：LLMFactory + `_resolveGenerationCredentials` S4 装配单点第六处，`callRefine` seam，prompt 显式禁「AI 驱动/模拟器/localStorage」技术词 + 反虚构约束，`maxSummaryTokens=100`）；③ `game_summary_service.dart` 编排（导入成功 → 规则简介同步写回 onlyIfEmpty → 开关开启时异步精修替换 → 落盘后 `onDescriptionRefined` 刷新列表，无「生成中」UI 态）；④ 写回单源化——`_updateManifestEntryDescription` 上提 `import_service.updateManifestEntryDescription`（含 onlyIfEmpty 模式，F-47 与本品共用一条读-改-写原子路径）；⑤ 设置键 `simulator_llm_description_enabled`（默认关，成本敏感 opt-in）+ 对话设置页「模拟器简介」区开关。
- **接线**：import_flow 新增 `OnGameImported` 成功挂点（typedef + 构造注入 + handleImport 成功路径调用）；simulators_view 缺省流接线 `GameSummaryService`；app.dart 两个新 provider（GameDescriptionGenerator 于 GameGenerator 后、GameSummaryService 于 SimulatorsController 后——refresh 回调依赖 controller 装配）。
- **证伪抓出 2 真 bug（先红后绿实锤）**：① 仿微.html fallback 残留孤立 `<div`——snippet 窗口截断把 `</textarea>` 切走，`_stripTagsAndFragments` 补清截断残留尖括号；② 规则提取全空（纯 CSS 页面）时精修仍被触发——LLM 无内容依据会凭空编造，服务层改「fallback 为空 → 不写回也不调度精修」。
- **种子 22 款固化**：以提取的 title + prompt 段为依据逐款核写（本环境无 API key，由主模型承担「LLM 生成 + 人工审校」角色，约束与功能内 prompt 逐字一致：≤60 字 / 无技术词 / 只写实际内容）；Python 只改 description 字段重写 manifest（diff 22 行全为 description）；样例：蛛网之影「在纽约高楼间荡起蛛丝，背负『能力越大责任越大』的英雄宿命」、仿微「在仿真的微信界面里经营社交关系——聊天、朋友圈，还可导入文档定制角色」。
- **期末全量**：**2897 测**绿（新增 30 用例：extractor 10 / generator 7 / service 8 / 设置键 1 / 开关 1 / 挂点 3）/ analyze 0 / 波及文件覆盖率全 ≥90%（两新服务 100%，import_service 95.6%）。
- **存量失败记录（非本批引入）**：`manual_pages_test` 版本防漂移失败——pubspec 已是 `1.1.0+2`，AboutPage.appVersion 仍报 `1.0.0+1`（发布批 7f20557 改版本号漏改 About 页），`git stash` 回基线复现确认 → **落债 F-157**（Strong，发布卫生）。
- **批次收尾**：TO-TICKETS 归档「模拟器简介自动生成批次」（GS-01~03，commit `45fe7f5`）；TECH_DEBT 候选区录 F-157；AGENTS 状态行追加；手册 §8/§9 补「卡片简介」「模拟器简介」两行。

---

## 技术债消费批次 F-154~156 — 全部处置（2026-09-21 — 用户「继续处理 F-154~156」拍板，project-kickoff 全自动档）

- **批次源**：用户「继续处理 F-154~156」（架构审查批次 C1~C8 波末/波末审核落债三条：relationship 构造死参 💭 / palace 字符口径漂移 💭 / _buildAssembleContext 双跑 CPU 🟡）；基线 `0066e0b`（2869 测）。项目完整模式 + 全自动档，高风险面②（F-156 触碰核心聊天链路）→ 标准档波 1 双并行。
- **Grilling 增量审（四决策点定案）**：F-154 做·删死参（实证编辑面 9 构造行 + 3 连带：_GateRelationshipService 超参转发漏删即编译断裂 / 工厂签名 / unused import+late 字段——analyze 0 门禁三易漏点；app.dart provider 保留 4 其他消费者）；F-155 **复核关闭**·零代码（漂移双处显式文档化 + 病态边界输入 + 无真实触发证据 + 修复属过度工程；**票面阈值修正 10000 非 6000**——6000 为窗口截断预算；💭 双查询非快照单写模型可忽略）；F-156 做·`_buildAssembleContext` 返私有结果类（built 立即 + segments `late final` 惰性，send 腿永不触碰，上游 IO 单次保持）。三判定：自建零新依赖。
- **plan-tickets**：spec + 2 票（T-01/F-154、T-02/F-156）+ F-155 关闭 spec Further Notes；行号 grep 实证修正（T-01 测试文件 5 个非 6——app_stage2 用 implements 桩无 super 转发；proactive :903/end_of_turn_hooks :334/characters_view :166/:446）；T-02 关键陷阱 = 惰性闭包捕获本调用参数集 + 闭包内零上游 IO。
- **波 1 双并行（零重开）**：T-01/F-154（`7430023`，7 文件 +0/−25 纯删）——9 构造点 + 6 连带全清，**agent 发现票面外易漏点**（relationship_service_test late conversations 字段 + 3 unused import 连带清理），analyze 0 两轮 / 5 测试 133 用例全绿 / relationship_service 覆盖率 98.5%；T-02/F-156（`5014e6c`，单文件 +55/−16）——`_AssembleContext` 惰性记忆化（record 不可行论证：需 late 字段承载「至多组装一次」状态），chat_service_test **零改动**（零行号漂移），**极端突变**（segments→const []）4 个 PD-04 行为锚红实证灵敏度，chat_service 覆盖率 92.5%。
- **波末**：文件范围两票全合规；双分支 --no-ff 零冲突合并；受影响 285 用例全绿。增量审核（固定点 0066e0b）**0 阻断**：F-154 零悬挂引用全仓 grep 实证 / F-156 send 腿零 segments 支付静态求证（.segments 消费唯一 :1904 debug 腿）+ 构造命名疑似项（私有 field formal 参数名剥离下划线）最小 Dart 片段实证排除 + 行为等价实跑复证（10 负结果具名）；_AssembleContext 非过度封装（record 不可行）；mutant 静态确认锚真实性。
- **期末全量**：**2869 测**绿（与基线等数——F-154 纯删传参未删用例、F-156 零测试改动）/ analyze 0。
- **期末四轴**（固定点 `0066e0b`）：**通过（0 阻断，1 💭）**——四轴 0 Critical/0 Recommended；Standards 1 💭 = `_AssembleContext` 构造跨 4 行应折叠单行（本批引入格式漂移，按 R-S1 先例收尾捎带修复 `f688b1b`）；Spec 0 违例（验收锚全实跑 + F-155 阈值修正实证成立）；Falsify 0（惰性闭包两腿捕获正确 + segments 异常同步上抛不吞 + send 腿永不上抛）；Architecture 0（死参退出构造面 / 惰性+记忆化最小正确形状）；覆盖 8/8 0 UNREVIEWED。
- **批次避坑（蒸馏候选）**：① 波级审核「横向确证被 Implementer 例外」形态——F-156 的 send 腿零支付无法直接运行时断言（惰性字段不触发即无观测），靠「静态求证 + 突变验证行为锚」双保险是等价证据组合；② 锁「无观测影响的中间态/N+1 优化」类债时在验收线里写断言可能锁死实现细节（F-156 未写、以行为锚兜底——与 F-145「勿锁无影响中间态」同构）。
- **批次收尾**：TO-TICKETS 归档「技术债消费批次 F-154~156」（T-01~02 + F-155 关闭注记）；TECH_DEBD 处置记录新节（F-154 ✅ / F-155 ❌ 复核关闭入表 / F-156 ✅，**候选区清零**）；AGENTS 状态行追加；`.scratch/techdebt-f154f156/` 待 Neat 清场（2 worktree + 2 kickoff 分支 + 一次性产物，删除清单经用户确认）。

---

## 架构审查候选 C1~C8 按强度交付（2026-09-21 — 用户「/improve-codebase-architecture 架构审查优化候选按强度交付 + /project-kickoff 全自动」）

- **批次源**：用户「架构审查优化候选按强度交付 + kickoff 全自动」（persona 先例：先 Strong 后剩余，ARC-1~10 三次实证）；基线 `9aceed4`（2836 测）。项目完整模式 + 全自动档（persona 偏好），高风险面②（C2/C3/C4/C7 触碰核心聊天链路与数据层）→ 标准档两波。
- **架构审查**：探查代理全库扫描（热点 = 聊天链路/数据层/companion 域/装配层）→ 8 候选（C1~C4 Strong / C5~C7 Worth exploring / C8 Speculative）+ HTML 报告（离线自适应内联 CSS，Top recommendation = C1）；候选落盘 TECH_DEBD F-146~153（来源=架构报告，防重提闭环）。
- **Grilling 增量审（8 问采纳定案）**：C1 做·整批一键降级（单 SQL 无部分失败，降级单元升为整批；docstring 过时让步改写）；C2 做·`lib/services/llm/temperature.dart` 纯函数（常量自 SettingsRepository 导入，两服务各改一行，防御测试收敛值域表）；C3 做·`recentMessages` 定位读（等价序取尾 N）+ 窗口 builder，**署名保留三套语义逐字不变**（三语义非三复制），reflection 可注入 limit 透传；C4 做·**保守**（共享段止于 built/segments，注入段留 send 腿本就单源，promptDebug 豁免 + docstring 声明，PD-04 不重开）；C5 关闭即删除（ADR-0006 无 UI 展示强制 + 生产全收敛 latestMessageAt → 删 activeDays/_allMessagesFor + 测试 + ADR 退役注记）；C6 做·谓词单源进 SQL（listOverdueScheduled 含端点 + listScheduledWithNullMessage，sent 归集记共识备注不在票）；C7 做·**全额**（WL-03「app.dart 装配零改动」实证为波级约束无跨波效力，churn 按实测 45 构造点非候选称 16）；C8 轻做（_endOfTurnHook 归一 + 开关读取收敛单位置=服务内）。三判定：全部自建零新依赖。
- **plan-tickets**：spec + 8 票（01-C1 ~ 08-C7）+ 元数据表；**实测校正**：C7 真构造点 45（app 1 + test 44，共识 46 误计 chat_round_test 桩类）、已传 repo 仅 1 处（chat_service_test:3557）、测试文件 19 个非 8；波结构定案 = 波 1 四并行（C1/C8/C5/C6）+ 波 2~5 合并**单串行链 lane**（C3→C2→C4→C7，阻塞边首尾相接，冲突图驱动 chat_service 串行独占）。
- **波 1 四并行（零重开）**：C1（`bfb9e98`，listSwipesBatch 批量 + 整批降级，突变改回逐条 3/3 红）/ C8（`9c46f71`，EOT hook 归一 + 开关收敛服务内，发现修复 1 伪测试——palace 开关缺省关闭原消息量未达归纳阈值零灵敏度，预置 12 条使门唯一拦截 + 删门突变红实锤）/ C5（`1b87e6f`，activeDays 死面删除 + ADR 退役注记，连带 _conversations 字段清理，conversationRepository 构造死参留 F-154）/ C6（`8c2a473`，listOverdueScheduled 含端点 + dropped 独立定位，突变 ≤→> 三处端点测试红）。四票合并点 fcd09f4/cd687c5/3db1f0a/ff9a057；共享文件 app_stage2_assembly_test C5×C6 双方存活；受影响模块 295 用例全绿；增量审核（固定点 9aceed4）**0 阻断**（负结果全具名 + mutant 静态验证 C1 删 catch/C6 端点被测试圈住；非阻断落债 F-154）。
- **波 2 串行链**：C3（`6f3026a`，recentMessages + dialogue_window builder，署名逐字测试断言捕获，**链上新增 messageStats O(1) 聚合面**——票面外但满足验收线的必要件，波 2 审核裁定记录警告放行）/ C2（`d78ed37`，temperature.dart 单源 + 值域表 10 值域，grep _resolveTemperature 零命中）/ C4（`fd41251`，_buildAssembleContext 共享段，PD-04 断言零改动，CharacterData 构造点两处并一处）/ C7（`7525f68`，构造净化 45 构造点 + app.dart wiring，LorebookRepository( 构造仅 app.dart 一处达成装配单点）；链 merge `b074885`；受影响模块 377 用例全绿；增量审核（固定点 ff9a057）**0 阻断**（messageStats 裁定 = 必要件成立记录警告放行，C3 验收线「×3 收敛」实为 5 次 O(1) 读 + chars 码点口径漂移记入开发日志；2🟡 2💭 判断性；mutant 2 处真实执行被击杀——dialogue_window >→>= 3 用例红、limit≤0 短路删除 1 用例红〔SQLite 负 LIMIT=无限制陷阱如实触发〕；非阻断落债 F-155/156）。
- **期末全量**：**2869 测**绿（基线 2836 → +33 = C1+3 C6+8 C3+C2+C4+C7 链带测试净增）/ analyze 0。
- **期末四轴**（code-review 子智能体，固定点 `9aceed4`）：**通过（无需继续修改）**——四轴 0 阻断、全 💭 判断性；Standards（新公开 API 注解+docstring 全齐 / 安全红线仅测试夹具 / pubspec 零变更；开关读取在服务 try 外的字面缺口与基线传播边界相同）；Spec（8 票验收锚逐条 grep 全过 / messageStats 与 conversationRepository 死参两处申报偏差核实一致）；Falsify（三个风险区 C3×C2/C6×C1/C8×C7×C4 全部未击穿；唯一边角 = C1 整批降级在 >32,766 条助手消息病态会话下全量降 0，F-143 caller-duty 字面违反窄且已声明）；Architecture（C3 对话窗口单源/C2 温度单源/C4 组装落点单源/C7 数据层类型退出协议面/C8 守卫单点 + 开关三服务统一约定，均达成深模块形态）；覆盖 22/22 全 reviewed 0 UNREVIEWED。
- **批次避坑（蒸馏候选）**：① 「TICKETS→TO-TICKETS 更名」为并发维护动作（批次运行期间由外部提交 58e9f8f + 41fdd54 + fa6024b 落库，含我的未提交 F-155/156 录入）——多 session 同仓并行时文档同步须以磁盘事实（git status + HEAD）为准续作，不假设自己持有唯一写权；② 架构候选的强度校准会系统性低估 churn（C7 候选称 16 构造点、实测 45——「票面修复建议须实证复核」惯例的 churn 侧版本）；③ 波级增量审核对「为实现验收线而新增的票面外 API」要给明确裁定通道（messageStats 记录警告放行 vs 回退补票），不能静默吞。
- **批次收尾**：TO-TICKETS 归档「架构审查候选 C1~C8 按强度交付」（01~08 八票）；TECH_DEBD 处置记录新节（F-146~153 ✅ 已修移出候选区，候选区留 F-154~156）；AGENTS 状态行追加；`.scratch/arch-review-20260921/` 待 Neat 清场（5 worktree + 5 kickoff 分支 + 一次性产物，删除清单经用户确认）。

---

## 技术债消费批次 F-143~145 — 三条全部处置（2026-09-21 — 用户「按技术债消费决策点折回」拍板，project-kickoff 全自动档）

- **批次源**：用户「按「技術債消費決策點」折回 F-143~145」（chat-polish-aigs 期末落债三条：isIn 无分块上限声明 🟡 / 归属校验同构重复 💭 / seedCharacter 死求值 💭）；基线 `bba4e31`（2836 测）。项目完整模式 + 全自动档（persona 偏好），高风险面②（T-01/T-03 触碰既有核心模块）→ 标准档单波 3 并行。
- **Grilling 共识（技术债条目为审查共识产物，只审增量）**：F-143 做·方案 A（docstring 声明 bound：SQLITE_MAX_VARIABLE_NUMBER ≥3.32 默认 32766 + 超限「too many SQL variables」硬失败 + 调用方职责「须 ≤ 上限、超规模自行分块」；chunking 属 YAGNI——触发规模 = 单对话消息数，距上限三数量级；零新增测试，bound 系引擎常量非本仓行为）；F-144 做·抽提 `_requireMessageOwnership` 私有 helper（**桌面前提实证修正**：桌面 `message.py:259` 早有 `_require_message`（6 调用点、delete_message/switch_swipe 均调用），移动端抽提 = 对齐桌面既有结构而非「有意偏离」，helper docstring 以对齐说明 + 注明 id-only vs conversation 过滤差异；deleteMessage 接返回值用 target.role、switchSwipe 只 await 不接值、`_resolveContinueTarget` 明确不纳入；零新增测试）；F-145 做·单次 `_now()` 求值（createdAt/updatedAt 必填命名参数不可省，只收敛值）＋ docstring 从「逐值等价」改述「值恒被 createCharacter 覆写／占位」；零新增测试（步进时钟锁「两值可能不同」= 锁无观测影响中间态；覆写契约已锚定）。三分：三条均自建零新依赖。
- **plan-tickets**：spec + 3 票（T-01 bound 声明 / T-02 归属校验抽提 / T-03 夹具单次时钟），三票零互依赖、文件范围零交集、出口四检全过（引用文件真实存在 / 无环 / 粒度全 ≤500 行 / 验收 ≤8 条）。三票共享 TECH_DEBD.md 行级并发写风险 → 剥离文档改动，**收口批次末主会话统一执行**（工单文件修订 + 验收标注，规避三 worktree 并发写同一文档的合并摩擦）。
- **波 1 三并行（全部一次成功，零重开）**：每票独立 worktree（`F:\Craft\conver system\.worktrees\f143-bound|f144-ownership|f145-single-now`）+ kickoff 分支。
- **逐票交付**：
  - T-01/F-143（commit `d1c755f`，merge def3a4b）：listSwipesBatch docstring +6 行纯注释 bound 条款（锚文本 SQLITE_MAX_VARIABLE_NUMBER/32766/too many SQL variables/须 ≤/分块 5/5 命中），方法体与两消费方（branch_service.dart:125 / conversation_export_service.dart:260 `_listSwipeContentsBatch` 内——原候选区 `:114` 行号漂移顺带修正）零改动；analyze 0 / message_swipes_test 25 用例全过；零新增测试。
  - T-02/F-144（commit `9094f12`，merge 32071f0）：`_requireMessageOwnership`（L1419-1439，docstring 锚文本跨对话同 id 视为不存在 / 对齐桌面 message.py::_require_message）+ deleteMessage 接值走 target.role 两分支 / switchSwipe 只 await 越界原样上抛 / `_resolveContinueTarget` 零改动；analyze 0 / chat_service_test 155 用例全过；**极端突变抽查**（删 null→throw 后双归属路径恰红、爆炸半径精确、恢复零残留）实证测试灵敏度。
  - T-03/F-145（commit `f5d9104`，merge a885886）：seedCharacter 单次 now 求值（6 插入/4 删除单 hunk 落 seedCharacter）、方法体内 `_now()` 字面命中 1、「逐值等价」残留 0；analyze 0 / chat_service_test + character_repository_test 164 用例全过（覆写契约锚定用例零改动通过）。
- **环境避坑注记**：3 个新 worktree 首次跑测试均遇 sqlite3 native asset 从 GitHub 下载超时（无公网）——复制主仓库已验证缓存（`.dart_tool/`/`build/`，gitignored）后 hook 哈希命中离线复用，全绿；环境缓存问题与改动无关。
- **波末**：文件范围核验三档 = 全合规（T-01 仅 message_repository.dart / T-02 仅 chat_service.dart / T-03 仅 chat_test_env.dart，零共享文件触碰）；证据三文件落盘；三分支 --no-ff 合并（def3a4b / 32071f0 / a885886）；受影响模块 189 用例全绿。增量审核（固定点 bba4e31）**0 阻断**：Falsify findings 0（超限/重复/Set/空输入/跨对话/越界/返回值误用/隐蔽改调/helper 绕过 + T-03 递增时钟极端装置全被如实预言；32766 口径/消费方规模声称/打包引擎前提逐项实证）+ 负结果具名记录；mutant 抽查 T-02 null→throw 双归属路径红、爆炸半径精确、恢复零残留；文件范围合规；过度工程 0 项。
- **期末全量**：2836 测绿（与基线等数——本批零新增测试，Grilling 共识）+ analyze 0。
- **期末四轴**（code-review 子智能体，固定点 `bba4e31`）：**通过（无需继续修改）**——四轴 0 findings、0 阻断、0 警告；Standards（红线 grep 零命中 / 无 try/catch / 无过度工程）、Spec（三票验收锚文本逐条字面命中 / T-02 桌面前提亲验成立 / 无孤儿代码零依赖零绕契约）、Falsify（bound 契约诚实性 + 抽提逐字等价 + 单次求值无观测影响全实证）、Architecture（T-01 深模块契约面增强 / T-02 Locality 提升对齐桌面 / T-03 属地正确）；覆盖 3/3 manifest 全 reviewed、0 UNREVIEWED。
- **批次教训/避坑（蒸馏候选）**：① 技术债共享文档（TECH_DEBD.md）跨工单行级并发写 = 合并摩擦源——批次内将文档改动剥离收口主会话统一执行，工单只交代码（本批实证零冲突）；② 「对齐桌面逐字惯例」类债面归因须对桌面源码实证复核——F-144 票面「桌面逐字内联」被证伪（桌面 message.py:259 早有 helper），审计快照复核惯例再次命中（与「技术债票面修复建议须实证复核」同构）；③ 新 worktree 首次跑 flutter test 的 sqlite3 native asset 离线下载失败可用主仓库已验证缓存复制解决（hook 哈希命中即离线复用）。
- **批次收尾**：TICKETS 归档「技术债消费批次 F-143~145」（T-01~03，候选区清零）；TECH_DEBD 处置记录新节（F-143/144/145 ✅ 已修移出候选区，候选区清零、无新落债）；AGENTS 状态行追加；`.scratch/techdebt-f143f145/` 待 Neat 清场（3 个 worktree 与 kickoff 分支清理，删除清单经用户确认）。

---

## 技术债消费批次 F-140/F-141/F-142 — 三条全部处置（2026-09-21 — 用户「待立项消费」拍板，project-kickoff 全自动档）

- **批次源**：用户「F-140/141/142 待立项消费」（chat-polish-aigs 期末落债三条：SPEC-1 契约缺口 Worth / chat_entry flaky Strong / branch N+1 Worth）；基线 `5b64def`（2829 测）。项目完整模式 + 全自动档（persona 偏好），高風險面②（T-01/T-03 触碰既有核心模块）→ 标准档单波 3 并行。
- **Grilling 共识（技术债条目为审查共识产物，只审增量）**：F-140 做·方向 A（服务层落地与 deleteMessage 同构、spec §4.8 实现补位免修订，理由：契约表 1:1 成真 + ChatRound 消除补偿 + 四姊妹方法全部服务层、switchSwipe 是唯一缺位者）；F-141 做·测试侧修正（**控制器侧无真实竞态实证**——loadEntry 单次赋值 + 单线程事件循环；根因 = seedCharacter 的 `DateTime.now()` 被 createCharacter 的 `_now()` 覆写致测试无法控序 + drift 秒级存储 + 两 seed 跨秒边界 → `updated_at DESC` 后种者排首 → `_resolveSelectedCharacterId` 取 first.id=2；F-136 pumpUntil 对其无效——排序错时条件永不满足）；F-142 做·R2（batch 原语 + 两消费方，桌面 list_swipes_batch 语义参考、移动端自建 drift `isIn`；`_loadSwipeCounts` 因逐条 try/catch 降级语义冲突明确不动）；三分：三条均自建零新依赖。
- **plan-tickets**：spec + 3 票（T-01 switchSwipe 落地 / T-02 ChatTestEnv 可控时钟 / T-03 swipes batch），三票零互依赖、文件范围零交集、出口四检全过（23 引用文件真实存在 / 无环 / 粒度 ≤500 行 / 验收 ≤8 条）。
- **波 1 三并行（首次派发全部被 kill——「Background agent task stopped」→ 重开路径）**：重开前现场核查——T-01 4 文件未提交（含只读 chat_round_test 越界待核）、T-02 先红后绿已落地（a6132fd 红 + d107291 绿）、T-03 4 文件未提交 + cov_report.py 临时产物。重开 prompt 带现场核查指令续作。
- **逐票交付**：
  - T-01/F-140（commit `6b5ba9a`，merge d85ff5a）：ChatService.switchSwipe 落地 + ChatRound 改调（守卫/notice/reload 保留）；范围测试全绿；覆盖率 chat_service 92.3% / chat_round 96.9%；**范围偏差**：只读 chat_round_test 13 行接口顺应存根（`_ScriptedChatService implements ChatService`，Dart 接口增方法编译必需；行为中性 UnimplementedError 被触即炸；无零 diff 替代）——子代理上报 → 主会话批准归「记录警告」+ 证据文件落盘偏差节；票文「回归组 5 用例」实测 4 用例（以实测为准）。
  - T-02/F-141（commits `a6132fd`+`d107291`，merge 97e556b）：ChatTestEnv 注入可控时钟（`create({DateTime Function()? now})` 默认参数，8 消费文件零实参调用源码兼容；直抄 chat_controller_test fakeNow 先例）；先红复现 `Expected: <1> / Actual: <2>` → 修复恒绿；契约锁双口径（仓库层三 seed 同刻 id 升序 + widget 层 pumpUntil）；**突击抽查**：反转 id DESC 双口径均红（非伪测试），仅删 id ASC 未红系 SQLite 单列排序回落 rowid 序（契约锁锁行为非实现细节，证据注明）；全量 4 遍首跑零复现（3× +2829 + 1× --coverage）。
  - T-03/F-142（commit `d617564`，merge 007776c）：listSwipesBatch（`isIn` 单查询 + 空输入短路 + index 升序 + 无候选不在 map）+ branch/export 两消费方改调；输出逐字节等价（既有断言零改动全绿）；覆盖率三文件 96.6~100%；Falsify 突变抽查 3 项全捕获（空短路移除→runSelect 计数暴露 / 候选恒空→branch 断言失败）；cov_report.py 临时产物已删。
- **波末**：范围核验三档 = 合规×2 + 记录警告×1（T-01 存根，有权依据）；完成门 3 DONE；合并回 mobile（HEAD `007776c`）；受影响模块 289 测全绿。增量审核（固定点 5b64def）**0 阻断**：Falsify 3 条非阻断（listSwipesBatch isIn 无分块上限声明 🟡 / switchSwipe 与 deleteMessage 归属校验同构重复 💭 / seedCharacter 双 `_now()` 死求值 💭）+ 负结果具名记录（T-01→仓库层契约衔接 TOCTOU 由 `_requireMessage` 关闭、T-03 空输入短路/absent-key 兜底语义正确、T-02 时钟注入 8 消费文件无同刻 flakiness、ChatRound 状态机 `_isMutatingMessage=false` 恒可达、存根响亮失败非静默）；remove pass 10→3（7 条证据裁定删除）。
- **期末全量**：2836 测绿（基线 2829 → +7 = chat_service_test +3 + message_swipes_test +4）/ analyze 0。
- **期末四轴**（code-review 子智能体，固定点 `5b64def`）：**通过（无需继续修改）**——四轴 0 阻断、0 硬违规；Standards 1 🟡（F-144 归属校验同构重复——spec §4.1 明确「与 deleteMessage 同构」为 spec 强制重复，抑制为基线 smell，F-144 已登记评估合理）；Spec 0 缺失 0 偏差（§4.1/4.2/4.3 全命中，F-141「同刻两 seed」以三 seed 实现为超集非偏差）；Falsify 1 💭（listSwipesBatch 单查未分块规模边界，非缺陷，与波末 F-143 同源 → 去重复证标注）；Architecture 0 阻断（listSwipesBatch seam 深增量高 Leverage / chat_round 归纯编排 / 夹具修复属地正确 / F-144 落债判定合理）。
- **批次教训/避坑（蒸馏候选）**：① **子代理后台任务被 kill（Background agent task stopped）后 worktree 保留现场**——重开路径 = 现场核查（git worktree list + 各 worktree `git status`/`git log` 分辨已完成/半成品）+ 复用 worktree/分支续作，不重建；本批 T-02 已完成先红后绿两 commit 只需收尾，T-01/T-03 半成品续作，避免重做（0 损耗）；② 波中只读文件因接口演化被编译必需修改（Dart implements 增方法）——子代理上报、主会话批准归记录警告、证据落盘偏差节，不静默越界也不机械回退；③ 测试夹具时钟失控是 flaky 根因可实证的常见形态（createCharacter 覆写显式时间戳）——夹具即修复属地。
- **批次收尾**：TICKETS 归档「技术债消费批次 F-140/F-141/F-142」（T-01~03）；TECH_DEBT 处置记录新节（F-140/141/142 ✅ 已修移出候选区）+ 新落债 F-143/144/145（波末增量审核 3 条非阻断；F-143 期末复证标注）；AGENTS 状态行追加；`.scratch/techdebt-f140f142/` 待 Neat 清场（含 3 个 worktree 与 kickoff 分支清理，删除清单经用户确认）。

---

## 移动端角色对话打磨批次 chat-polish-aigs（2026-09-19/20 — handoff 交接指令 + /project-kickoff 全自动接续）

- **批次源**：handoff-conver-mobile-chat-polish-aigs-20260919（用户「/project-kickoff 全自动接续」两段式）；Grilling 共识已确认（10 项开放决策采纳），威胁建模 SR-23~31；19 票 / 10 功能族，基线 `88003fc`（2274 测）。
- **编排**：`.scratch/chat-polish-aigs/orchestration.md` 15 波全收口——R1 并行 01+07 → R2 并行 02+06 → R3 并行 03+09 → R4 04 → R5 05 → R6 08 → R7 10 → R8 11 → R9 12 → R10 13 → R11 14 → R12 15 → **R13 并行 16+18**（文件范围零重叠核验）→ R14 17 → R15 19。每票独立 worktree `F:\Craft\conver system\.worktrees\<slug>` + 分支 `kickoff/<编号>-<slug>`；每波主会话收口（全量验证 + lcov 覆盖核对 + 增量审核 0 阻断 + concerns 落盘）；批次末统一 TICKETS 归档。
- **日期分界**：CPA-01~07/09（swipes/世界书表+引擎/编辑器 UI）2026-09-19 于交接文档前已合入；本会话收口 CPA-08/10~19（注入链/记忆宫殿/叙述风格/预设对话×2/专家模式/采样×2/Prompt Debug/分支×2）2026-09-20。
- **逐波门禁（主会话独立核验）**：19 票全部「全量测试 + analyze 0 + 波及文件覆盖率 ≥90%（lcov 解析）+ 残留零命中 + 文件范围核验」通过；主分支各波 merge 后全量逐次累加：2484 → 2503 → 2553 → 2582 → 2613 → 2637 → 2672 → 2694 → 2784（R13 并行 +90）→ 2808 → **2829**（基线 2274 → +555）；每波增量审核 0 阻断（Standards/Spec/Falsify/Architecture 四维主会话审阅）。
- **关键实证与决策（concerns/01~19 全文落盘）**：注入锚实证修正（NPD-01 票面「scenario 后」为 WL-03 前旧文 → after_char 后/[世界知识] 前，桌面 `_assemble` 2.7 逐字）；`Value(null)` 落库实证（drift Companion 忽略 nullToAbsent 只检 present → Repo 零改动）；Dart valid-override 签名 ripple（加基类可选参数强制 17 类 × 19 覆写面同步，含 15 票 + 14 票 drift 必填字段 ripple 同类）；迁移幂等 PRAGMA+ALTER 同构 6 块（schemaVersion 5→11）；`_assemble` 单一组装核心抽核零变化契约（PD-04）；删源置空 D2 桌面对照（BR-01）；世界书复制独立行 D1 桌面有意偏差。
- **Falsify 对抗**：子代理突变抽查 30+ 全红 + 主会话逐波对抗审阅；期末四轴 Falsify 轴构造失败输入无崩溃面（守卫矩阵全过）。
- **期末四轴**（code-review 子智能体，固定点 `88003fc`）：**通过（0 Critical）**——Standards 3 Info（S1 database 参数签名稳定遗留 / S2 sourceMod spec 背书占位 / S3 记忆宫殿全捕获契约降级）；Spec 1 Recommended + 2 Info（**SPEC-1** `ChatService.switchSwipe` 契约缺口已申报补偿 → 落债 F-140；SPEC-2/3 spec 内联形态差异 → spec 修订日志批尾统一）；Falsify 5 Info；Architecture 3 Info（switchSwipe Locality 与 SPEC-1 同源）。修订日志已折回 spec.md。
- **批次教训/避坑（蒸馏候选）**：① 子代理慢速完成型（30-60 分钟无间歇输出但实际推进，中途 worktree git status 采样判断）——多次「误判中断」后主会话接管收尾（01/04/05 先例）；② 突变检查残留会留生产代码——波末/接手半成品第一件事 grep `MUTATION`/`PROBE`/`TEMP`（01/05 先例）；③ flutter test 被 kill 残留 flutter_tester 进程锁 sqlite3.dll → 重跑前 `Get-Process flutter_tester | Stop-Process -Force`（本批多次）；④ job/interrupt 后子代理可能继续写完并提交——kill 后检查 worktree 新 commit；⑤ 气泡内显式 label Semantics 必须 `container: true` 隔离（05，F-66 语义吞并实证）；⑥ ListView 懒构建消息行高变化 `_scrollToBottom` 需 post-frame 补跳（05，差 19.33px）；⑦ **编排文件波记录编辑须插入而非替换**（本会话两次误删前波记录已修复，教训固化）；⑧ **勿全库 `dart format`**（14/15 票：仓库非 format-clean，全库/多文件格式引入 1700-3000 行噪音，须逐文件核对还原）；⑨ **禁 serena 写类工具**（15 票 replace_in_files 误写主工作区 6 测试文件，已回滚核验，后续票禁用）；⑩ **禁 `grep pattern file > file` 同文件重定向**（15 票覆盖 chat_service_test 850 行）；⑪ 票面注入锚/前置假设写于前置票落地前后会过时——派发时实证修正（NPD-01 锚、15 票子类零改动）；⑫ **chat_entry「默认选中首角色」flaky 批次内 4 次复用**（05/11/13/17 波首跑，单文件重跑恒绿）——F-106（排序）/F-122（publish 等待族）/F-136（加载等待）修复后仍复发 → 落债 F-141（Strong，需根因深挖）；⑬ shell `>` 重定向在主工作区 vs worktree 的路径解析陷阱（后续票统一用 worktree 绝对路径）。
- **批次收尾**：TICKETS 归档「移动端角色对话打磨批次 chat-polish-aigs」（CPA-01~19）；TECH_DEBT 新落债 F-140/141/142（SPEC-1 契约缺口 Worth / chat_entry flaky Strong / branch N+1 Worth）；spec 修订日志批尾统一（SPEC-1/2/3）；AGENTS 状态行追加；`.scratch/chat-polish-aigs/` 待 Neat 清场（删除清单经用户确认）。

---

## 技术债消费批次 F-123~139 — 十七条全部处置（2026-09-19 — handoff 交接指令，候选区 17 条全处置）

- **Grilling 共识（16 做 1 关）**：交接文档建议「先 F-136/137 flaky 复核 + F-138/139 收敛点，再评估 W1~W6/P1~P3」（用户拍板消费候选区）；逐条现状实证后共识 = 14 做 + 3 复核关闭（F-131 role 宽类型唯一调用方只传 Role / F-134 planner hook 已直测 / F-137 chars_view 5 遍全量零复现）。F-136 有明确加固点（pumpUntil 等加载）做；F-137 无可见盲区按证据关闭。
- **flaky 复现循环（先跑证据）**：后台 6 遍全量循环——run 1-5 干净基线全绿（F-136/137 本批零复现），run 6 两文件 loading 失败 = 实施期间编辑测试文件的中间态误伤（非 flaky，全量终验兜底）。结论：F-136 静态加固（加载完成显式等待，消除单帧 pump 残余窗口）；F-137 零复现 + 双终态等待在位 → 复核关闭。
- **五波交付（主会话直行，无子代理派发）**：波 1 F-132（persistThought 服务侧 1 MiB 截断 + 超长用例——**漏改落库参数被测试捕获**先红后绿）/F-133（开关读抛错专测 ×2：服务层上抛契约 + 端到端降级）/F-138（`_resolveGenerationCredentials` 抽共享，GameGenerator + `_resolveLlm` 双侧复用，S4 收敛第五处）/F-139（`_autoInsertGreeting` 改 `lastMessage` 定位读）→ 波 2 F-126（`float32_codec` git mv 至 utils + 4 处 import）/F-129（`CompanionTimeWindows.localDayOf/isSameLocalDay` 单源，双消费点改调）/F-130（索引对账机械测试——**三段正则踩坑**：跨行字面量捕获 IF → `[^...]*` 吃注释中文捕获 user_version → `IF NOT EXISTS` 设必需前缀终局）/F-125（`getActivePlan` limit(1) 双在途不抛 + `_hasInFlightPlan` 去全表绕路，注释同步）→ 波 3 F-124（`chatErrorMessage` 单源 7 处改调）/F-127（view timer 三处删除，controller 单归属）/F-128（`_interruptedNoticeId` noticeId 配对替代文案身份）/F-135（`reflectAndBackfillPending` 函数 seam 编排 added>0 才补嵌）→ 波 4 F-136（chat_entry 断言前置 pumpUntil）→ 波 5 F-123（新建 `lib/services/companion/proactive_deep_link.dart` 深模块八符号，app.dart 摘除约 210 行业务接线圈，剩 ScaffoldMessenger 桥接 + Provider 闭包；装配测试 import 迁移）。
- **测试工程教训**：① `isNotNull` 与 drift query builder 同名 import 冲突 → 换 `isA`；② SettingsRepository super 参数 positional 不匹配命名构造 → 显式构造；③ 对账正则在「注释含 CREATE INDEX + 中文」下回溯捕获假名，必需前缀 + 白名单消耗是最稳形态。
- **门禁**：全量 **2274 测**绿（基线 2264 → +10 = F-132 1 + F-133 2 + F-125 1 + F-129 3 + F-135 2 + 对账 1）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90%（新增 proactive_deep_link、companion_time_windows 测试直测）。
- **批次收尾**：TICKETS 归档「技术债消费批次 F-123~139」（5 波 5 Ticket）；TECH_DEBT 处置记录新节（14 ✅ + 3 ❌ 复核关闭入表）+ **候选区清零**（空表头状态，禁写叙述）；AGENTS 状态行追加。

---

## 架构深化批次 S1~S6 — 六条 Strong 全交付（2026-09-18 — /improve-codebase-architecture + /project-kickoff 全自动档）

- **架构评审**：双探索子智能体（伴侣/向量域 + 聊天/核心域）独立走库，15 候选合并为 13 条按强度交付（6 Strong / 6 Worth / 3 Speculative，含双命中提级 S1）；HTML 报告 `D:\tmp\architecture-review-20260918-203548.html`（Tailwind+Mermaid before/after 图 + 删除测试结论 + Top recommendation）。用户拍板**全部 Strong 立项**；未选中 9 条落债 F-123~131（防候选泄漏）。
- **Grilling 增量**：审增量不重开——S1 降级契约 = 服务内吞错 + 装配层构造注入有序闭包列表 + `_persistThought` 排除（代码事实修正报告图：它是落库链内 await 步骤非 fire-and-forget）；S5 重开 ADR-0007 第 32 行排布句（决策实质不动，追加修订节不建新 ADR）；S6 补 `messageById` 第五查询面；现成方案三分全自建（项目内部协议面收敛）。
- **plan-tickets**：6 票出口预检通过（引用文件真实存在 / 依赖无环 / 粒度全达标：验收 5-8 条、+15~+697 行 ≤1000、seam ≤1）；S4 锚点校准（GameGenerator 段为范围外，随批落债 F-138）；S6 `_autoInsertGreeting` 范围外落债 F-139。
- **三波执行（标准档全自动）**：波 1 AD-01/03/04（并行 3，merge c7425d3 零冲突）→ 波 2 AD-02/05（merge fa895b2，AD-02 Blocked by AD-01）→ 波 3 AD-06（merge f5652f8）。每票独立 worktree + TDD 先红后绿 + 突变抽查全过；六票全量自跑绿（2222/2242/2226/2247/2243/2264）。
- **遥测**：波时长 = 每波约 8-12 分钟（worktree pub get + 全量/范围测试主导）；并行 3/2/1；回退/冲突 0 次；重开 0 次；空返回 0 次；切票粒度对照——AD-02 实际 +697 vs 预估 +180（差量 = 370 行 hooks 专项测试 + 三测试文件构造迁移，源文件 4 文件与预估一致，判定合理解释）；波末增量审核每轴 findings = 波 1: 4 非阻断（Falsify 3 + Overengineering 1）/ 波 2: 4 非阻断；门禁命中 = 波末文件范围核验拦下 0（三票合规，AD-02 两文件属「工单内已申报编排表漏记」复核纠正）、复核 flaky 识别 2 次（chat_entry ×2 + chars_view ×1 独立重跑全绿，零误伤）。
- **考察**：① 嵌套子代理聚合层通知丢失（四路内部审核 ready 但结果未达聚合层，聚合层 continuation state 丢失不可续接）——期末四轴降级为主会话复核合成（波末两轮增量审核 + 锚文本抽查：`_maybe*`/`stripAndPersist` 清零、`streamGenerate` 仅基类单点、chat_round 零全量读、planner 段无凭据调用）如实标注，非阻断；② final-review 缺失由本 DEV_LOG 节 + wave1/2 报告 + 主会话复核记录共同承担。
- **门禁**：全量 **2264 测**绿（基线 2225 → +39）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90%（多文件 100%）/ pre-commit 池检查通过（TICKETS 活跃表归档后清空）。
- **批次收尾**：TICKETS 归档「架构深化批次 S1~S6」（AD-01~06 + commit/merege 行）；TECH_DEBT 处置记录新节（6 票 ✅）+ 新落债 F-132~139（波末审核非阻断 4 + flaky 观察 2 + spec 范围外 2）；AGENTS 状态行追加。

---

## 技术债消费批次 F-113~120 八条全部处置（2026-09-17 — 用户「消费 F-113~120」指示，候选区 8 条 Weak 全处置）

- **票面实证复核（先立票后动手）**：8 条逐条读源码复核现状——全部仍成立、无 F-105 式失实票面；F-114/F-115 同为「快照截断」问题判定合并处置（单源 helper 一并解决），F-120 判定「同构面 = resolve+create 两行」抽顶层 helper 收敛（非全文复制抽象，避免浅模块）。
- **交付（4 工单 3 lane 单 commit `84fcdac`）**：主会话 F113F120-03（`lib/utils/utf16_truncate.dart` 新建：`maxSnapshotLength = 2000` 单常量 + `truncateUtf16` 防劈代理对〔substring 末尾高代理 0xD800..0xDBFF 再截 1 code unit〕，persona_evolution_service `_clampPersonalitySnapshot` + memory_repository `upsertEmbedding` 两处接入，docstring 对账句改单源；helper 单测 7 测含代理对 3 边界 + 零上限边界〔**测试暴露真 bug**：`truncateUtf16('abc', 0)` → `codeUnitAt(-1)` RangeError，先红后绿修复〕）/ F113F120-04（`app.dart` 顶层 `_resolveLlm` 抽共享，两处装配闭包同构段收敛，删 2 处冗余局部变量）。
- **子代理双 lane（并行预算，用户批准）**：A = F113F120-01（persona_evolution_service_test + memory_management_controller_test 契约锁补测 4 用例：clamp 后恰等交叉边界 / Q7 reapply 幂等 / apply+discard 异常吞并〔`_ThrowingEvolutionService` super parameters〕；**常量改名 8 处同步**〔F-115 删除旧常量后既有 7 处 + 新增 1 处统一 `maxSnapshotLength`，语义等价，A 自动处理〕；33 测绿 / 两文件 analyze 0）/ B = F113F120-02（memory_management_view_test 契约锁补测 3 用例：窄屏 360dp 无溢出〔**F-113 票面证伪**：直接绿，未改生产〕/ propose 异常 NoticeBanner SR-16 摘要 / `_PromptDialog` 取消路径无 dispose 异常；16 测绿 / 生产零改动）。
- **协调事件**：① 主会话导入路径笔误（`../utils/` 从 services/memory 解析到不存在目录）被 B 捕获上报，立即修 `../../utils/`；② A 的常量引用与 F-115 删除冲突，send_message 同步后 A 自动改名收敛——并行 lane 跨文件依赖靠「派发前划清文件边界 + 运行中消息同步」化解，零冲突合并。
- **门禁**：全量 **2224 测**绿（基线 2210 → +14 = helper 7 + A 4 + B 3）/ `flutter analyze` 0 / 波及文件覆盖率全 ≥90%（utf16_truncate 100% / persona_evolution_service 100% / memory_repository 100% / controller 100% / view 175/178 = 98.3%）/ pre-commit 池检查通过（TICKETS 活跃表 4 条 🔄 立项随代码 commit，归档后清空）。
- **处置汇总**：F-113 契约锁证伪（未改生产）/ F-114 ✅（防劈代理对）/ F-115 ✅（单源收敛）/ F-116~119 ✅（契约锁补测）/ F-120 ✅（装配同构段收敛）；**无复核关闭项**；候选区仅剩 F-122（既有 flaky 观察，非本批产生）。
- **知识库召回轨迹（kb-search）**：写测前检索 `widget|dialog|空态|pump|flutter|按钮` 无新增相关命中（与 F-121 批同结论）；`use_super_parameters` / `prefer_interpolation_to_compose_strings` 由子代理按 lint 内建规则修正，无需外部经验；无漏招。
- **批次收尾**：TICKETS 归档批次「技术债消费批次 F-113~120 八条全部处置」（F113F120-01~04 同 commit `84fcdac`）；TECH_DEBT 处置记录新节（8 条全 ✅）+ 候选区 F-113~120 移出（剩 F-122）；AGENTS 状态行追加。

---

## 技术债消费批次 F-121 空态入口（2026-09-17 — handoff-techdebt-f109-evolution-done 交接指令，用户拍板折回首选候选）

- **预检记录**：完整模式（AGENTS/DEV_LOG/TICKETS/TECH_DEBT 齐备）；档位 = 交接文档建议的 kickoff 全自动档（单票小改主会话直行，无子代理分发）；交付形态 = 源码跑通（flutter test + analyze 全绿即交付验证）。
- **知识库召回轨迹（kb-search）**：demo vault · Conver System 注册命中（KNOWLEDGE_BASE.md 登记）；persona 精读（先红后绿硬验收 / 票面建议实证复核 / 覆盖率达 90% 带口径）；写测前检索 `widget|dialog|空态|pump|flutter|按钮`——标题/全文命中 1 条《Flutter测试碰平台依赖必须超时兜底》（NativeDatabase.memory() 纯内存非平台依赖，与本次场景不相关，跳过精读），通用 17 条均方法论类无空态/按钮专项——**无直接相关命中，无漏招**（本批未踩库内已有笔记覆盖的坑）。
- **F-121 阐明**：票面「记忆管理页空态无『新增记忆』入口」= `_MemoryList` empty 分支直接 `EmptyState`（无操作入口）；非空态有 section header IconButton（tooltip「新增记忆」→ `_showAddDialog` 选类型→输入→保存全链路）。修复边界：`EmptyState` 组件 TP-4 全局定案「操作入口由调用方提供，不预建参数槽」（F-53/F-54 曾有 action 槽、被 AR-6 按授权删除的先例佐证）——**不改共享组件**，入口做在调用方。
- **边界态补强**：entries 空但 revisions 非空（有演化历史无记忆条目）走 ListView 分支同样无入口——一并覆盖（ListView 顶部 Align 左齐 `_AddEntryButton`），三态（空态/边界态/非空态）新增入口语义统一。
- **交付（单票直行）**：F121-01 `688a406`（lib 1 文件 + test 1 文件，+86/-4）——`_AddEntryButton`（FilledButton.tonalIcon，Icons.add 18px，深模块单点 onPressed 走 `_showAddDialog`）；空态 Column（EmptyState + space3 + 按钮）；边界态 ListView 顶部入口；非空态 header action 不动。
- **先红后绿**：新增 2 widget 用例（空态「暂无记忆」+ 入口可见 → 全链路新增「空态直接新增」落库 / 边界态仅 revisions → 入口可见 → 情景记忆新增落库）先红（2 失败，断言缺失即票面缺陷）后绿（全文件 13 测过）。
- **门禁**：全量 **2210 测**绿（基线 2208 → +2）/ `flutter analyze` 0 / 覆盖率 controller **100%**（58/58）+ view **97.75%**（174/178，新增行全覆）/ pre-commit pool-cleanup 通过。
- **全量首跑 1 失败（与本批零关联）**：`characters_view_stage2_test`「升级提议 · publish 驱动确认/拒绝」（验收 3）瞬时失败——单文件复跑 2/2 通过、全量重跑 2210 全绿；grep 证该测试文件零 `memory_management` 引用（无 import/无调用）→ publish → UI 等待族残余 flaky（F-104 曾修复同类窗口，本次为同族复发观察）→ 落债 **F-122**（Weak，防 review 重复提出 + 下批可复核）。
- **批次收尾**：TICKETS 归档批次「技术债消费批次 F-121 空态入口」（F121-01 `688a406`）；TECH_DEBT 处置记录新节（F-121 ✅ 已修）+ 候选区 F-121 移出、F-122 落债（清零 1 < 净增 1，持平）；AGENTS 状态行追加。推送仍循既有用户指示「先不推送」。

---

## 技术债消费批次 F-122 publish 等待族收口（2026-09-17 — F-121 批次观察落债，用户「消费 F-122」指示）

- **票面归因实证**：定向重复抽样前 3 轮全绿（瞬时 flaky 无法靠轮次稳定复现），代码审读实锤双缺陷——① 生产真缺陷：`CharactersView._maybeBroker` 走 `Provider.of(context)`（listen 默认 **false**），`publish` 只同步改 `_lastProposal` 不建立 UI 依赖，UI 更新依赖无关帧/轮询兜底（F-104 曾收敛 helper，本次为同族复发根因实证）；② 测试等待语义缺陷：确认后置等待 `find.text('亲密')` 在 broker 清除前即被「升级建议：亲密」提前满足；③ 拒绝/F1 固定 20ms pump 在负载/调度下不足。
- **交付（F122-01 `19e0192`，主会话直行无子代理）**：生产 1 文件（`characters_view.dart._maybeBroker` 改 `listen: true`，publish 后一帧重建）；测试 1 文件——publish 用例改单帧断言（订阅语义即证明，去轮询）、确认/拒绝/F1 后置等待改「`broker.lastProposal == null` ∧ 确认按钮消失」双终态、新增 `_GateRelationshipService` Completer 门闩 seam（tap → `confirmStarted` → 断言提议/按钮仍在 → release → 双终态放行），确定性复现「提议文本已存在但服务未完成」场景。
- **先红后绿**：门闩用例 + 双终态改造后首跑 2 失败（拒绝/F1 在 broker 清除后、UI 未重建前读到旧帧「确认」——pumpUntil 先判条件后 pump 的窗口）→ 等待条件补 UI 终态后全绿；定向文件 11 测（基线 10 → +1）。
- **门禁**：全量 **2225 测**绿（基线 2224 → +1）/ `flutter analyze` 0 / pre-commit pool-cleanup 通过（候选区清零）。验证期另处理孤儿 `flutter_tester` 占用 `build/native_assets/windows/sqlite3.dll` 的环境坑（kill 后恢复），与代码改动无关。
- **批次收尾**：TICKETS 归档批次「技术债消费批次 F-122 publish 等待族收口」（F122-01 `19e0192`）；TECH_DEBT 处置记录新节（F-122 ✅ 已修）+ 候选区 F-122 移出（**候选区清零，无新落债**）；AGENTS 状态行追加。

---

## 技术债消费批次 F-109 演化入口补全（2026-09-17 — handoff-stage3-vector-recall-a8-local 交接指令，/project-kickoff 全自动档）

- **预检记录**：完整模式（AGENTS/DEV_LOG/TICKETS/TECH_DEBT 齐备）；确认档全自动档（用户拍板）；交付形态 = 源码跑通（flutter test + analyze 全绿即交付验证）。
- **preflight**：HEAD `dea7ac0`（领先 origin/mobile 1 commit——handoff 明示验收 8 补验未推送，本批不推）；flutter test 基线 2185 测；git worktree 可用；主分支 mobile 存在。全绿无降级。
- **知识库召回轨迹**：demo vault · Conver System 注册命中；persona 精读（全自动档偏好 / 票面建议实证复核 / 后台子代理 AskUserQuestion 不转达主会话 / 覆盖率必带口径 / 哑 Provider 挂启动副作用须 lazy:false）；经验摘要扫描 168 条，精读 4 条：哑Provider无消费者default-lazy永不执行 / 后台子代理AskUserQuestion不转达主会话 / 技术债票面修复建议须实证复核 / 覆盖率数字必须带口径声明。
- **技术债预检**：活跃工单空；候选区 4 条——F-109（Worth exploring，伴侣域，**本批立项**：PersonaEvolutionService 零装配零调用，VR-08 seam 已交付仅缺 UI/装配入口）+ F-110~112（Weak/Worth exploring，随批复核：F-110 余弦有限性守卫 / F-111 normalizeBaseUrl 直构健壮性 / F-112 upsert 两步非原子）。
- **F-109 票面实证**：grep 确认 `PersonaEvolutionService(` / `proposeEvolution(` / `buildClusteredReflector(` 在 lib 内零装配、仅测试引用——「零装配零调用、端到端触发不可达」成立；票面方向（补 UI/装配入口）合理。现成方案判定：自建（服务与聚类 seam 全在，仅缺装配入口，无开源可比）。
- **Grilling 共识（用户全票批准）**：F-109 立项——演化闭环经记忆管理页补全端到端可达（Q1 自建 / Q4 并入记忆管理页 / Q5 AppBar 手动按钮 / Q6 列表内联应用拒绝 / Q7 待确认=快照≠当前人格启发式，**用户拍板不升 schemaVersion 5** / E1 服务 `_reflector` 改 `CharacterScopedReflector` + propose 透传 characterId / F1 app.dart Provider 照 ReflectionService 装配先例 + wireCredentialsResolver 闭包 + 装配三件套验证）；**F-110~112 逐条复核全部关闭**（F-110 per-element isFinite 已存在 + float32 截断双防线 / F-111 SR-20 装配链单一落点已拦截 / F-112 唯一索引 `idx_embedding_entries_character_id_content_hash` 实锤存在 + 服务层串行无竞争窗口）；威胁建模命中「外部输入持久化」——**SR-22 纳入本批验收**（propose 对 LLM 产出长度 clamp 2000，用户拍板）；F-111 残余（`normalizeBaseUrl('https://')` 畸形值）用户拍板不立票；不做集冻结（无 schema 迁移/无自动演化/无冷却）；验收底线 5 条见 `.scratch/f109-evolution/grilling-consensus.md`。
- **交付（3 工单串行 lane 1 波）**：01 E1+SR-22 `2d580ca`（服务签名改造：`PersonaReflector`→`CharacterScopedReflector` 构造/字段 + propose 透传 characterId；SR-22 常量 `maxPersonalitySnapshotLength=2000` 新建（embedding 截断原为内联字面量，实测无既有命名常量按「以实测为准」新建），trim→clamp→空/相等判定→落库，debugPrint 摘要不含原文；测试 16 测含 +3 SR-22，服务范围覆盖率 100%（LF=45/45），clamp 突变抽查红实锤）→ 02 装配腿 `a532e93`（`Provider<PersonaEvolutionService>` 默认 lazy，buildClusteredReflector + wireCredentialsResolver + factory.create + reflectPersonaWithProvider 闭包与 ReflectionService 先例同构；装配冒烟 30 测「七实例可读」；diff 最小化 +46/-1，formatter 漂移已按 F-103 结论回滚）→ 03 确认闸门 UI `4ef0977`（controller 演化三操作 + proposing/appliedRevisionIds/snackMessage + Q7 启发式 load 判定 + SR-16 固定摘要断言不含 key 原文；记忆页 AppBar「提出人设演化」+ tile 双形态 + SnackBar 三态；`characters_view._openMemory` 改 context.read 注入；**顺带修复既有 `_PromptDialog` dispose 时机 bug**（widget CRUD 测试暴露：dialog 退场动画期间 dispose controller → 重构 StatefulWidget）；controller 覆盖率 100%（58/58）、view 97%（163/168））。
- **波末核验**：三档文件范围核验 **合规 9/9**（全部落在三票申报范围，零越界零未申报共享改动）；声称核对证据 01/02/03 落盘；完成门 3 STATUS 全 DONE；merge `--no-ff` → `9b642d8`（零冲突）；波内复核测试 207 测绿；**共享文件改动存活核验**（app.dart/characters_view.dart 两处已申报改动，diff 抽查存活）。
- **波末增量审核（fixed dea7ac0）**：**0 阻断**；Falsify 2 非阻断落债（W-1 窄屏 ≤360dp tile 溢出未验证 → F-113；W-2 SR-22 substring 代理对切分 U+FFFD 无崩溃与 embedding 同口径 → F-114）；过度工程零；文件范围合规。
- **期末门禁**：全量 **2208 测**绿（基线 2185 → +23）/ analyze 0；期末四轴 **通过**（0 Critical；7 条 Weak 落债 F-115~121——S-2 2000 双源 / SP-1 clamp 后相等交叉边界无直接单测 / SP-2 apply 后手动编辑幂等链路无测试证据 / F-1 apply/discard 异常吞并分支 + propose 异常 banner 无断言 / F-2 `_PromptDialog` 取消路径无 widget 测试 / S-1+A-1 同源 LLM 注入链两份同构闭包未收敛；安全红线通过——唯一 `sk-` 命中为测试 fake 异常文本）。
- **concern 裁决（波末）**：02 app.dart 全文件覆盖率 70.4% vs 新增块安装面 100%——按「装配冒烟只 read 不执行闭包、不触真实凭据」验收语义认定非阻断；03 四项——① 既有 `_PromptDialog` bug 修复并入本票（测试暴露合理）② 空态无「新增记忆」入口 = 既有交互非本批引入 → 落债 F-121 ③ formatter 漂移已最小化 ④ propose 异常固定文案符合 SR-16。
- **过程遥测**：Implement 子智能体 1（串行 lane 3 票连续完成，零空返回零重开）；worktree 1 个（`.worktrees/f109-lane`，分支 kickoff/f109-01-03 已并入主树）；合并冲突 0；切票粒度对照——预估 01 +55/02 +50/03 +470 = +575 vs 实际 `git diff --stat` +875/-52（03 实际 +721 超预估 +470，主因 widget 测试新建 331 行 + `_PromptDialog` 重构，仍在 1000 硬上限内）；门禁命中——文件范围核验/声称核对/完成门/波末审核均零命中（无越界无伪造），期末四轴拦下 0 阻断（7 Weak 落债 = 审核收益）。
- **批次收尾**：TICKETS 归档批次「技术债消费批次 F-109 演化入口补全」（F109-01/02/03）；TECH_DEBT 处置记录新节（F-109 ✅ 已修 / F-110~112 ❌ 复核关闭）+ 复核关闭表加 F-110~112 行 + 候选区净增 F-113~121（9 条 Weak/Worth exploring，清零量 4 < 净增 9——审核产出 > 修复容量，已随汇报显式提示用户）；AGENTS 状态行更新；交接建议 skills 同前批。

---


## 历史归档索引

| 日期 | 批次 | 摘要 |
|------|------|------|
| 2026-09-17 | 人机恋阶段 3 批次 | 用户「阶段 3 人机恋深化」+ kickoff 全流程 |
| 2026-09-17 | 权限弹窗真机补验批次 — F-84 权限链路三场景（2026-09-17 — 用户「接续（权限弹窗真机补验）」指令） | 用户「接续（权限弹窗真机补验）」指令） |
| 2026-09-17 | 技术债消费批次 techdebt-f106f108 | handoff-techdebt-f104f105-done-2026-09-17 交接指令，/project-kickoff 全自动档 |
| 2026-09-17 | 技术债消费批次 techdebt-f104f105 | handoff-techdebt-f101f103-done-2026-09-17 交接指令，/project-kickoff 全自动档 |
| 2026-09-17 | 技术债消费批次 techdebt-f101f103 | handoff-techdebt-f98f100-done-2026-09-17 交接指令，/project-kickoff 全自动档 |
| 2026-09-17 | 技术债消费批次 techdebt-f98f100 | handoff-techdebt-f91f97-done-2026-09-17 交接指令，/project-kickoff 全自动档 |
| 2026-09-17 | 文档清出机制执行 | Neat 遗留裁决 |
| 2026-09-17 | 技术债消费批次 techdebt-f91f97 | handoff-techdebt-f78f90-done-2026-09-17 交接指令，/project-kickoff 全自动档 |
| 2026-09-17 | 技术债消费批次 techdebt-f78f90 | handoff-techdebt-f84f88-done-2026-09-16 交接指令，/project-kickoff 全自动档 |
| 2026-09-16 | 技术债消费批次 F-84/F-85/F-88 + F-83 | handoff 交接指令，/project-kickoff 全自动档 |
| 2026-09-16 | 真机冒烟补验批次 | 用户「真机/模拟器冒烟补验」指令 |
| 2026-09-15 | 人机恋阶段 2 批次 | /project-kickoff 全自动档 |
| 2026-09-15 | 人机恋阶段 1.5 批次 | 用户「阶段 1.5 可选增强」指令 |
| 2026-09-15 | 人机恋阶段 1 MVP 批次 | 用户「继续」handoff |
| 2026-09-14 | 技术债消费批次 F-75/F-76/F-77 | 用户「消费技术债」指令 |
| 2026-09-14 | U-UX 补全批次 | 用户 APK/模拟器实测反馈 |
| 2026-09-10 | 技术债折回批次 F-73/F-74 | 用户「消费技术债区」指令 |
| 2026-09-10 | 真机问题批次 CORS 反代 + 测试连接 | 用户真机验证反馈 |
| 2026-09-10 | 技术债折回批次 F-68~72 | 用户「消费技术债 F-68~72」指令 |
| 2026-09-10 | 架构审查批次 C1~C4 | improve-codebase-architecture 报告直落全自动档 |
| 2026-09-09 | M7 批次 | project-kickoff 全自动档，source 交接书 handoff-M7 |
| 2026-09-09 | 架构深化批次 AR-4 | improve-codebase-architecture 候选 4 直落 |
| 2026-09-09 | 技术债折回批次 F-56/F-65/F-67 | 用户「全部折回」指令 |
| 2026-09-09 | 技术债折回批次 F-66 | 技术债折回直落，最小闭口 |
| 2026-09-09 | 技术债折回批次 F-63 | 技术债折回直落 |
| 2026-09-09 | 技术债折回批次 F-59 | 技术债折回直落 |
| 2026-09-09 | 架构深化批次 AR-4/5/6 | improve-codebase-architecture 候选 4/5/6 直落 |
| 2026-09-09 | 架构深化批次 AR-3 | improve-codebase-architecture 候选 3 直落 |
| 2026-09-09 | 架构深化批次 AR-2 | improve-codebase-architecture 候选 2 直落 |
| 2026-09-09 | 架构深化批次 AR-1 | improve-codebase-architecture 候选 1 直落 |
| 2026-09-08 | M6 kickoff 批次 | project-kickoff 全自动档交付：去 AI 味打磨 |
| 2026-09-08 | M6 kickoff 预检 | project-kickoff 全自动档，工程目标 = M6 去 AI 味打磨 |
| 2026-09-07 | 技术债消费批次 TD-1~TD-4 | 用户「消费 F-25~F-51」显式立项，27 条候选全处置 |
| 2026-09-07 | M5 kickoff 批次 | project-kickoff 全自动档交付：模拟器里程碑 |
| 2026-09-07 | M5 kickoff 预检 | project-kickoff 全自动档，工程目标 = M5 模拟器里程碑 |
| 2026-09-07 | 架构深化批次 | improve-codebase-architecture 候选 4/5 收官 |
| 2026-09-07 | 技术债消费 F-24 | 用户「先消费技术债」指令立项：SettingsReader 契约语义收敛 |
| 2026-09-07 | 架构深化批次 | improve-codebase-architecture 候选 2/3 |
| 2026-09-07 | 架构深化批次 | improve-codebase-architecture 候选 1 |
| 2026-09-07 | 技术债消费批次 F-18/F-23 | 用户指令显式立项，2 项并行交付 |
| 2026-09-06 | M4 kickoff 批次 | project-kickoff 全自动档交付：导出 / 文档解析里程碑 |
| 2026-08-30 | M3 kickoff 批次 | project-kickoff 全自动档交付：角色 + 搜索里程碑 |
| 2026-08-30 | 技术债消费批次 F-10~F-17 | project-kickoff 全自动档交付：技术债八候选消费 |
| 2026-08-29 | M2 kickoff 批次 | project-kickoff 全自动档交付：聊天核心 |
| 2026-08-29 | 技术债消费批次 F-7/F-8/F-9 | project-kickoff 全自动档交付：技术债三候选消费 |
| 2026-08-29 | M1 kickoff 批次 | project-kickoff 全自动档交付：数据层 + 设置 |
| 2026-08-29 | M0 kickoff 批次 | project-kickoff 全自动档交付：脚手架与空壳 |
| 2026-08-28 | M0 kickoff 预检 | project-kickoff 全自动档，工程目标 = M0 里程碑 |
| 2026-08-28 | Flutter SDK 装载 | D 盘，M0 前置条件达成 |
| 2026-08-28 | 移动端库文档体系规范化 | 镜像桌面库结构建齐标准档 |
| 2026-08-28 | 设计文档迁入移动端仓库 | 从桌面库迁移 |
| 2026-08-28 | Android 工具链装载 + 插件管道冒烟 | D 盘，用户要求不装 C |
| 2026-08-28 | 移动端库初始化 | 独立 git 库，与桌面库分离 |
