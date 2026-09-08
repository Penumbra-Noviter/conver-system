# Conver System 移动端 — 可执行任务清单 (TICKETS)

> 规则：本文件是**仓库内唯一的待办事实来源**。活跃表只保留「未完成」工单；每完成一项 → 移入「已完成归档」并记完成日期（+提交哈希）→ 同步 [DEV_LOG.md](DEV_LOG.md) → 与本提交一起 commit。
>
> 维护节奏（绑定现有流程节点，不新增习惯）：
> 1. 开始实现某工单前：📝 已录入 → 🔄 进行中（认领）
> 2. 每会话结束、commit 之前：完成 → ✅/❌ → 移入归档；新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入 [TECH_DEBT.md](TECH_DEBT.md) 候选池（带 编号/来源/强度/状态/归属方向）
> 3. 待办**不得写在 memory / DEV_LOG / 个人笔记里**——不落 TICKETS 就不算数
>
> **归档清出机制（与桌面库同构，2026-08-28 建库即启用）**：已完成归档最近 6 个批次完整保留；更早折叠为「历史归档索引」单行（细节由 git 历史承担：`git log -p -- TICKETS.md`）；叙述（来源/验证链/过程遥测）只写 DEV_LOG.md。
>
> **机械检查**：`scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md --candidate-section "## 候选区"`（挂 pre-commit，失败拒提交）核对活跃工单无 ✅/❌ 滞留与候选区结构；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制，规则见 TECH_DEBT.md「清出机制」）。
>
> 状态：📝 已录入 | 🔄 进行中 | ✅ 完成 | ❌ 关闭

---

## 活跃工单

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| M7 | 发布准备：双端图标、Android AAB/iOS 签名、隐私清单 | 📝 | 上架/侧载包 |

---

## 技术债区

> 技术债候选池与处置记录统一见 [TECH_DEBT.md](TECH_DEBT.md)。

---

## 已完成归档

### M6 批次 — 去 AI 味打磨（2026-09-08 收口）

> 来源：project-kickoff 全自动档（Grilling 共识 5 真拍点全按推荐 A 定案：克制动效子集 8 项 / 聊天链路弱网重连自建不引 connectivity_plus / 实用层无障碍含 F-73 授权 / 空态不加操作入口 / 视觉评审走查清单+基线对照）。11 票 7 波次 DAG（W1 01‖04‖06 / W2 02‖09 / W3 03 / W4 05 / W5 07‖10 / W6 08 / W7 11 验收），Lane U 串行链 01→02→03→05→07（第 5 票后链中重启点换新 agent 接 08）+ Lane W 06→09；网关 TLS 断连 W1 三连重开（半成品接续）+ 暂停/恢复一次（TaskStop 后新 agent 接续，半成品零丢失）。合并链 f2391b3→0772c80→df25274→6b03d2c→(债 6046cb7)→80512e3→14a49a7→3226a4b→b115c3a→(债 a9bd412)→48a31b9→f32db5f→c70ae8b→(B1 0118b6a)→(B1 06673bf)→(hygiene 9221a9f)→(债 4ba0635)。波末增量审核 ×6（W1~W6）：W5 B1（NoticeBanner 消失过渡缺失）+ W6 B1（重试双路径死按钮）均派回修复 + 回归断言红→绿；期末四轴**阻断 0** / 非阻断 12（落债 F-64~66 + 复证标注 F-52/56/59/63）。全量 **1460 测**全绿（基线 1360 → +100）/ analyze 0 / MUTATION 0 / 全局覆盖率 **96.78%**（剔除 drift 生成物）。**M6 门视觉评审 PASS**（2026-09-08 AVD medium_phone）：§5.2×5tab×双主题像素采样全过（浅色 accent 实测 7.32:1 ≥4.5:1）/ 动效代码级验收（8 处 / ConverDurations fast140·mid220·slow300+tabFade160 对齐桌面 / 零动画库）/ 空态 7 处 + 错误态 4 型 + 断流「回复中断」vs「已停止」两标互斥运行时实证 / 弱网单测复核（06/09 148 + 08 53 全绿）/ a11y 语义树 + 15 断言全绿（TalkBack 可选未做）/ logcat FATAL=0；**B1 核心路径模拟器实测**（断流→图标 regenerate 清标清横幅 replace 完整回复 user 行不重复）。详见 DEV_LOG〈M6 kickoff 批次〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| M6 | 去 AI 味打磨：动效/空态/错误态/无障碍/弱网断线重连 | 2026-09-08 | 见合并链（11 票 7 波 + B1 ×2） |

### 技术债消费批次 TD-1~TD-4（2026-09-07）

> 来源：用户「消费 F-25~F-51」显式立项（27 条候选：19 待修 + 8 复核关闭）。4 工单 2 波（波1 398d610：TD-1 异常链 9e8f696 + TD-2 契约层 1f64ef4；波2 027bcd3：TD-3 hooks/注入 4677597 + TD-4 生成链路 ed8dfbd）；全量 **1360 测**全绿 / analyze 0 / MUTATION 零残留；波内复核修正 3 条（F-27 桌面等价 / F-29 迭代解析器不可复现 / F-39 SDK 已剥离）。8 条复核关闭（F-26/42 已修、F-28/30/37 桌面同构或契约边界、F-41/50/51 设计意图）。详见 DEV_LOG〈技术债消费批次 TD-1~TD-4〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| TD-1 | 技术债 F-25/31/32/33：种子单游戏缺失降级 + refresh in-flight 守卫 + 种子错误路径文案 + timeout 取消 | 2026-09-07 | 9e8f696 |
| TD-2 | 技术债 F-27/29/34/38/39：导入整包拒对齐 + manifest 深度兜底 + import 超时取消 + 枚举分片 + BOM 容错 | 2026-09-07 | 1f64ef4 |
| TD-3 | 技术债 F-35/36/43/44：合成器对齐/死面清理 + 注入占位符碰撞熔断 + run view 委托先挂 | 2026-09-07 | 4677597 |
| TD-4 | 技术债 F-40/45/46/47/48/49：校验大小写统一 + 409 终止重试 + 取消拦在途 + 空描述兜底 + 标题净化 + 死分支 | 2026-09-07 | ed8dfbd |

### M5 批次 — 模拟器（2026-09-07 收口）

> 来源：project-kickoff 全自动档（Grilling 共识 16 增量决策 + 5 真拍点按推荐 A 定案）。11 票 7 波次 DAG（W1 01‖05 / W2 02‖10 / W3 03 / W4 04‖07 / W5 06‖08a / W6 08b / W7 09），合并链 90064ca→ebdea6d→843de68→ed5d738→(B1 b7e61a2)→7f4a4bf→(B1 41db74a)→87e83c7→(B1 6ecf19e)→(缺陷#1 9237bbf)；波末增量审核 ×6 全零阻断（W4/W5/W6 各 1 条 B1 均派回修复）；期末四轴阻断 0 / 非阻断 18（落债 F-43~F-51）。全量 **1315 测**全绿 / analyze 0。**M5 门冒烟 PASS**（2026-09-07 AVD medium_phone API 35）：Q11 CORS 复验（DeepSeek 放行 401 vs Anthropic 拦截 TypeError 双侧对照 + 提示条 + claude key 不进 WebView）；Q12 force-stop 重启存档持久化；Q10 五游戏 25/25 轮零崩溃 + 注入三元组/受管 option 追加实证 + 15s 超时守卫 + 导入恶意拒绝二次确认 + 生成失败路径；缺陷#1（SaveSheet Android 恒 0 键）真机复验 PASS。详见 DEV_LOG〈M5 kickoff 批次〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| F-M5-01 | 数据底座：assets 随包 + 首启种子 + manifest 解析 | 2026-09-07 | ad2934d |
| F-M5-02 | 本地 HTTP 托管 + 契约常量 + 双端明文 | 2026-09-07 | a44f239 |
| F-M5-03 | 列表页 + 懒启动编排 | 2026-09-07 | a3a6a3f |
| F-M5-04 | Key 注入桥（运行页+注入脚本+官方端点提示）+ F-26 收口 | 2026-09-07 | 745350d |
| F-M5-05 | 存档契约层（纯 Dart） | 2026-09-07 | 2a089a9 |
| F-M5-06 | 存档读写层 + 底部 sheet（+ W5 B1 8e630d1 + 缺陷#1 de38f60） | 2026-09-07 | 87252d8 |
| F-M5-07 | 导入链（校验+恶意确认+原子注册）（+ W4 B1 be7fe49） | 2026-09-07 | 1133db1 |
| F-M5-08a | 生成校验闸门 + 种子模板 | 2026-09-07 | a118475 |
| F-M5-08b | 生成编排 + 对话框（+ W6 B1 9630423） | 2026-09-07 | 4cf7459 |
| F-M5-09 | CORS 复验 + 持久化 + 五游戏冒烟收口 | 2026-09-07 | 零代码（证据 .scratch/m5-kickoff/evidence/） |
| F-M5-10 | 「我」页收口（手册/关于/桌面版说明） | 2026-09-07 | a0fe004 |

### 架构深化批次 — 角色字段装配收敛 + ChatRound 分离（2026-09-07）— 候选 4/5 收官

> 来源：improve-codebase-architecture 探索报告候选 4（Worth exploring）+ 候选 5（Worth exploring）——最后两个未探索候选，本案收官。grilling AskUserQuestion 三问全按推荐 A 拍板（parse 链丢失处置 = 解耦+修复 / 装配收敛形态 = 收敛全量装配 / ChatCtrl 分离方向 = 抽回合机）。**候选 4 角色字段装配收敛 + 解耦 parse 链**：删 `CharacterDraft.fromParseResult`（`character_card.dart` 不再依赖 `document_parse_service`，纯转换层解耦）；向导 `_applyParseResult` 从 DocParseResult 直拷 8 表单字段；**修复数据丢失**——解析出的 postHistoryInstructions 此前在 save 路径静默丢弃（注释声称「保留于草稿可落库」与实现不符；chat_service 对话消费该字段），现随保存落库（新测试断言，creator 维持 spec 恒空）；`save()` 改经 CharacterDraft（6 个缺省字段下沉为构造器默认值）→ `toCompanion()`，drift 列名映射单一归属 `character_card.dart`（对齐桌面 CharacterBase 16 字段基类语义）。**候选 5 ChatController 回合状态机与杂项职责分离**：新建 `views/chat/chat_round.dart` ChatRound 深模块（协议表面 = send/stop/regenerate + 合成消息只读状态面 + resetForNavigation/applyBackgroundStoppedMark/isStopped；实现含流订阅/合成 id/F1 停止竞态/F3b 后台补标 ~250 行），**纯搬迁不动行为**（公开 API 零变化，`chat_controller_test` 1260 行原样绿）；ChatController 836→~500 行编排器（入口/导航/高亮/导出/消息组装保留，回合面委托 + reloadMessages 回调注入）；新增 `chat_round_test.dart` 9 独立契约测试。门禁：全量 **827 测**全绿（819 基线 + 修复测试 1 + round 9 − 删旧测 2）/ analyze 0；code-review 四轴 **PASS**（Falsify 8 类对抗场景等价或守卫拦截；Spec 搬迁逐字对照 + grep 零残留）；非阻断 3 条全处理（postHistory 落库前 trim / 删 `_reloadMessages` null 分支冗余 clearInFlight〔双向引用→单向回调〕/ CharacterDraft 缺省字段下沉构造器默认值）。详见 DEV_LOG〈架构深化批次 — 角色字段装配收敛 + ChatRound 分离〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 候选 4 | 角色字段 → CharactersCompanion 装配收敛 + 解耦 parse 链（含 postHistoryInstructions 落库修复） | 2026-09-07 | （见收口提交） |
| 候选 5 | ChatController 回合状态机分离（ChatRound 深模块，纯搬迁） | 2026-09-07 | （见收口提交） |

### 技术债消费批次 F-24（2026-09-07）

> 来源：improve-codebase-architecture 探索报告备选 B（Speculative）+ 用户指令「先消费技术债」显式立项（候选区当时为 0，从备选源落债后消费）。交付：**SettingsReader 契约语义收敛**——兜底常量单一归属 `SettingsDefaults`（`settings_reader.dart` 新增 `abstract final class`：provider/model/userName），`SettingsRepository` 三 getter 填充与 `ConversationRepository._fallback*` 兜底改为引用同一常量（原为各自字面量碰巧相等，任一侧改动即静默破约）；契约文档对齐「实现方填充」现状（原声明「返回空串由消费方回退」与实现矛盾）；消费方 `_resolveValue` 逻辑不动（测试 fake 返回空串的兜底语义保留）。门禁：全量 **819 测**全绿 / analyze 0（行为零变化的重构型收敛，数据层 88 测原样绿）。详见 DEV_LOG〈技术债消费 F-24〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| F-24 | 技术债消费：SettingsReader 契约语义收敛 | 2026-09-07 | （见收口提交） |

### 架构深化批次 — 控制器编排收敛 + LLM 流式骨架收敛（2026-09-07）

> 来源：improve-codebase-architecture 候选 2（Strong）+ 候选 3（Strong），grilling 共识 4 问全 A（NoticeRunner 形态 / onError 折叠 / streamSse 函数参数 / errorFrameException 工厂）。**候选 2 控制器超时/notice 编排去重**：新建 `services/notice_runner.dart`（guard 统一「超时兜底 + onError 错误折叠 + 先错者胜 notice + onChanged 通知」，替换两控制器 `.timeout(3s)` 6 处 + notice 编排 12 处；专项 CardFormat/Validation 折叠进 guard.onError switch；loading 标志各自保留）；**候选 3 LLM 流式 wire 骨架收敛**：新建 `services/llm/stream_wire.dart`（streamSse 共享骨架：POST + SSE 消费 + 非200→HttpStatusError + 消费阶段断连→LLMConnectionInterruptedError + 未终态兜底 + 强制关连接；差异面参数化：uri/body/headers/isTerminated/extractToken/errorFrameException），claude/openai `_streamRequest` 只留差异面（~20 行/provider，原 ~50 行 ×2 骨架消除），claude 流内 error 帧经 errorFrameException 工厂保持私有类型（M2 双协议决策）。**行为变更点（有意统一，审核确认）**：regenerate/_export 失败 notice 从「直接覆盖」统一为「先错者胜」；loadEntry 第二查询失败保留已加载对话列表（对齐 refresh 哲学，测试钉死）。门禁：全量 **819 测**全绿 / analyze 0；code-review 四轴 **PASS**（792 测实名；非阻断 6 条处理 4 条〔unused import / 200 空体未终态测试 / 连接拒绝分层契约测试 / loadEntry 二查语义测试〕，2 条知悉〔双重 notify 冗余为既有模式 / 7 参函数偏浅为合理权衡〕）。报告 `D:\tmp\architecture-review-20260907.html`。详见 DEV_LOG〈架构深化批次 — 控制器编排收敛 + LLM 流式骨架收敛〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 深化-2/3 | 控制器超时/notice 编排去重 + LLM 流式 wire 骨架收敛 | 2026-09-07 | （见收口提交） |

### 架构深化批次 — 文件交换平台腿收敛（2026-09-07）

> 来源：improve-codebase-architecture 扫描候选 1（Strong）+ grilling 共识（Q1=共享腿 / Q2=safeFileName 挪纯逻辑 / Q3=删死面 / Q4=新建模块 / Q5=组合级，用户拍板前三项，后两项按推荐）。交付：新建 `services/file_name.dart`（safeFileName 纯函数自平台 seam 迁出）+ `services/platform_file_exchange.dart`（typedef 收敛 + `writeTempAndShare`/`pickJsonWithTimeout` 组合级共享腿 + 缺省平台腿，超时阈值/降级文案单一归属）；两个消费 seam（角色卡 / 对话导出）删本地 typedef / `_shareViaPlus` / 平台 import，变薄为业务组装 + 注入契约；删 `ConversationExportService.characterExportBaseName` 死公开面（规则收敛私有 `_extractCharacterName`），`conversation_export_service` 不再 import 平台 seam（反向依赖消除）。门禁：全量 **804 测**全绿 / analyze 0；code-review 四轴 **PASS**（Spec 契约锚零残留、Falsify 行为逐位等价；非阻断 4 条处理 3 条〔docstring 残留 / seam 超时接线微测试 ×2 / 测试文件头〕，1 条跳过〔装配工厂，成本收益边缘〕）。报告 `D:\tmp\architecture-review-20260907.html`（另 4 候选待探索）。详见 DEV_LOG〈架构深化批次 — 文件交换平台腿收敛〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| 深化-1 | 文件交换 seam 合并：平台腿收敛为深模块 | 2026-09-07 | （见收口提交） |

### 技术债消费批次 F-18/F-23（2026-09-07）

> 来源：用户指令「消费技术债 F-18 F-23」显式立项（两候选均 Worth exploring，非 Grilling 拍板项）。2 项并行交付：**F-18 向导校验门收拢**（架构类）——步骤②模板门从视图 `_handleNext`（`_step2Error`）移入 `WizardController.next()` case 2（template 未选 → error + 拦截；import 放行），`selectTemplate` 补清错，视图删除 `_step2Error` 字段统一读 `controller.error`（Locality 达成：分步校验单一载体 = next() 的 case 1/2/3 switch）；测试拆分「import 放行」+「template 未选拦截/已选放行」新契约 + 视图文案锚保持；**F-23 平台真通道冒烟**（验证类，零代码改动）——file_picker 导入选择器弹出（`com.android.documentsui`）+ 批量删除长按多选手势（长按进多选/自动勾选/加选计数/退出恢复）模拟器实证，share_plus 分面已于 M4-06 关闭，本票关闭剩余两分面 → **F-23 整条闭环**。门禁：全量 **803 测**全绿 / analyze 0；code-review 四轴 **PASS**（Standards/Spec/Falsify/Architecture 零阻断，1 条非阻断 stale doc 已修）。证据 `.scratch/techdebt-f18-f23/evidence/`（F-23.md + smoke-file-picker.png + smoke-batch-select.png）。详见 DEV_LOG〈技术债消费批次 F-18/F-23〉。

| Ticket | 标题 | 完成日期 | 提交 |
|--------|------|----------|------|
| F-18/F-23 | 技术债消费：向导校验门收拢 + 平台真通道冒烟 | 2026-09-07 | （见收口提交） |

### M4 批次 — 导出 / 文档解析（2026-09-06 收口）

> 来源：project-kickoff 全自动档（Grilling 共识零真拍点；6 票两条并行依赖链：链A 导出 M4-01→02→03→06 / 链B 解析 M4-04→05，文件范围互不相交）。波1 merge 42099eb（M4-01~03）+ 25c7696（M4-04~05）+ 修复 1feddd7（m4-05 解析挂起中 dispose 崩溃，回归断言锁定）。门禁：全量 **802 测**（M3 729 → +73）/analyze 0；**M4-06 冒烟 PASS**（2026-09-06：hihello 对话顶栏 ⋯ → 导出 JSON/MD → ShareSheet 弹出 ×2 + `测试助手.json`/`.md` 临时文件生成且文件名=角色名净化 + 导出内容语义逐项核对（JSON UTC ISO 8601/升序；MD 日期分组/角色标记）+ **platformTimeout 超时兜底实测**（模拟器无分享接收 app → share_plus Future 不 resolve → 3s 超时 → 非阻塞 SnackBar，app 零崩溃）。交付内容：对话顶栏 ⋯ 菜单导出 JSON/MD（ConversationExportService 组卷 + 文件交换 seam 写临时目录 + share_plus 面板）/ 向导步骤②「AI 智能解析」启用（DocumentParseService 三级提取 + 白名单 + 错误折叠，失败文案与桌面一致）。F-23 重定界：share_plus 分面并入 M4 验收关闭，file_picker 与批量多选手势分面归 M5（TECH_DEBT 处置记录留痕）。证据 `.scratch/m4-kickoff/evidence/`（M4-01~05 + M4-05-fix + M4-06 + smoke-share-sheet.png）。详见 DEV_LOG〈M4 kickoff 批次〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| M4 | 导出/文档解析：对话导出(JSON/MD)+分享；LLM 文档解析角色字段 | M4-01~M4-06（kickoff/m4-export·m4-parse 分支） | 2026-09-06 | 42099eb + 25c7696（+修复 1feddd7） |

### M3 批次 — 角色 + 搜索（2026-08-30）

> 来源：project-kickoff 全自动档（Grilling 共识零真拍点 + 3 best-judgment 非拍板项：导入占位保留 UI、批量删除含可裁、开始对话默认模型）。8 票 4 波 DAG（W1 M3-01‖M3-04a / W2 M3-02a‖M3-04b / W3 M3-02b‖M3-03‖M3-04c / W4 M3-05）+ 四轮波末增量审核（W3 用户要求独立复核轮） + 期末四轴，全零阻断。全量 **729 测**/analyze 0/覆盖率剔除 drift **98.06%**；**冒烟 PASS**（角色列表→6步向导模板建角色→保存落库→跨对话搜索 hihello→跳转定位高亮全真机实证）。交付内容：角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板逐字移植 / V2 卡导入导出（file_picker ^12.1.2/share_plus ^13.3.0/path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮。主会话修复 F-7 契约回归（M3-04b/04c 直接引用 ConverColors → colorScheme）+ 期末四项低成本真缺（NaN 温度守卫/manual 跳步②/Escape 序号作废/删除角色入口缓存失效）。构建修复：gradle 绕开 Kotlin daemon Windows storage 冲突。详见 DEV_LOG〈M3 kickoff 批次〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| M3 | 角色 + 搜索：列表/6步向导/V2卡导入导出/级联删除；跨对话搜索定位高亮 | M3-01~M3-05（kickoff/m3-* 分支） | 2026-08-30 | 70bc094（+修复 0057d9e/9cfc4aa） |

> 来源：project-kickoff 全自动档（Grilling 共识 2026-08-30：8 候选 7 做 1 关闭，零真拍点；F-15 关闭——lib 生产零消费系设计意图，桌面 ChatResponse 契约镜像 + F-6 先例 + 4 组测试锁定）。6 工单 2 波 DAG（波1 T2‖T4‖T5 / 波2 T1‖T3‖T6，波1 merge 14bf479 波2 merge b9dc9bc）+ 两轮波末增量审核 + 期末四轴，全零阻断。全量 497 测/analyze 0/覆盖率手写口径 97.96%（剔除 drift 生成物）；冒烟 PASS（设置页渲染/主题深↔浅像素精确/logcat 零异常）。T5/T6 各重开 1 次（首派零产出，半成品/空 worktree 接续后 DONE）。新落债 0（波末/期末非阻断 5 项可读性判断不入债；SnackBar 模式差异遗留观察）。详见 DEV_LOG〈技术债消费批次 F-10~F-17〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| F-10~F-17 | 技术债消费：保存事务化 / ConverPalette 安全访问 / 主题异步面 / 翻译栈共享 / 角色 404 语义 / 停止加界 | T1~T6（kickoff/t* 分支） | 2026-08-30 | b9dc9bc |

### M2 批次 — 聊天核心（2026-08-29）

> 来源：project-kickoff 全自动档（Grilling 共识零真拍点；两处用户真拍点未答 → best-judgment 定案：flutter_markdown_plus ^1.0.12 + 最小临时会话入口，非用户拍板已在 spec 修订日志注明）。7 票 5 波 DAG（T00→T01a‖T01b→T02‖T03→T04→T05）+ 波3/波4 增量审核修复 + 期末收尾。全量 477 测/analyze 0/覆盖率手写口径 95.42%；A7 冒烟 PASS（窄路径：入口/autoGreeting/发送链/错误文案逐字/测试连接全真机实证，真实打字机流式留待用户 Key 复跑）。波3 seam 缺陷（T03 精确基类判型 vs T02 子类异常）与波4 F1 竞态均在合并时增量审核捕获修复。新落债 F-14~F-17（非阻断，见 TECH_DEBT.md）。详见 DEV_LOG〈M2 kickoff 批次〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| M2 | 聊天核心：ChatService + 双协议 SSE wire + 打字机 UI + test_connection | T00~T06（kickoff/m2-* 分支） | 2026-08-29 | 59e766a |

### 技术债消费批次 F-7/F-8/F-9（2026-08-29）

> 来源：project-kickoff 全自动档（Grilling 共识 2026-08-29：三候选全做，零用户真拍点；F-7 提前于原标注 M6 消费，依据用户「全自动消费技术债」指令）。3 工单单串行链（F-9→F-8→F-7，同 lane 三连 commit）→ merge 68e8d19 → 波末增量审核（Falsify 阻断 0）+ 期末四轴零阻断（Spec 24/24 验收全过）。全量 171 测/analyze 0/覆盖率手写口径 90.63%；G 冒烟通过（模拟器浅/深色双向切换像素精确，F-7 浅色主文字可读实证）。新落债 F-10~F-13（非阻断，见 TECH_DEBT.md 候选区）。详见 DEV_LOG〈技术债消费批次 F-7/F-8/F-9〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| F-7/F-8/F-9 | 技术债消费：视图 token 主题化 / 设置页错误面 / 双构造点收编 | 三工单（kickoff/f9-f8-f7 分支） | 2026-08-29 | 68e8d19 |

### M1 批次 — 数据层 + 设置（2026-08-29）

> 来源：project-kickoff 全自动档（Grilling 共识 2026-08-29 用户确认，含两项真拍：主题三值首启深/设置页三组真实化；8 工单 5 波 + 五轮波末增量审核 + 期末四轴，全零阻断）。验收门 G1–G5 全绿（154 测试/analyze 0）+ G6 模拟器冒烟全项通过（Key 真通道往返/三值主题即时生效/五 tab 零崩溃），证据 `.scratch/m1-kickoff/evidence/`。波 3 遭网关故障，05/06 由主会话接续完成（用户裁决授权，全程记录 DEV_LOG）。覆盖率：手写口径（剔除 drift 生成物+schema 声明）90.90% 达标。详见 DEV_LOG〈M1 kickoff 批次〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| M1 | 数据层 + 设置：CRUD 全语义 + SecureStorage 两槽位 + 模型清单单源 + 主题三值切换 | 01–08 八工单（kickoff/01~08 分支） | 2026-08-29 | a1d4265 |

### M0 批次 — 脚手架与空壳（2026-08-29）

> 来源：project-kickoff 全自动档（Grilling 共识 2026-08-28 用户确认；4 工单 3 波 + 三轮波末增量审核 + 期末四轴零阻断）。验收门 G0 全项通过：模拟器空壳（安装/拉起/五 tab 切换零崩溃/截图 vision 视觉核对），证据 `.scratch/m0-kickoff/evidence/g0-gate.md`。过程遥测与避坑详见 DEV_LOG〈M0 kickoff 批次〉。

| Ticket | 标题 | F 项 | 完成日期 | 提交 |
|--------|------|------|----------|------|
| M0 | 脚手架：Flutter 工程 + drift 4 表 + 主题 token + 底部导航壳 | 01–04 四工单（kickoff/01~04 分支） | 2026-08-29 | c55ced3 |