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

> 里程碑 M5–M7 待推进（M0/M1/M2/F-7~F-9/M3/M4 已交付归档，见下）。M5 模拟器单里程碑偏大，开工前用 /to-tickets 再细分（本地服务器 → 注入 → 存档桥 → 导入/生成），拆出的子项按 F 编号展开。

| Ticket | 标题 | 状态 | 验收摘要 |
|--------|------|------|----------|
| M5 | 模拟器：WebView 加载 + Key 注入 + localStorage 存档验证 + CORS 直连复验；「我」页收口 | 📝 | WebView 桥稳定，主流游戏可运行（开工前拆子项） |
| M6 | 去 AI 味打磨：动效/空态/错误态/无障碍/弱网断线重连 | 📝 | 视觉评审 |
| M7 | 发布准备：双端图标、Android AAB/iOS 签名、隐私清单 | 📝 | 上架/侧载包 |

---

## 技术债区

> 已迁移至独立文件 [TECH_DEBT.md](TECH_DEBT.md)——当前 **0 项待立项**（F-10~F-17 已于 2026-08-30 消费完毕，7 修 1 关闭，处置见 [TECH_DEBT.md](TECH_DEBT.md) 处置记录）。

---

## 已完成归档

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