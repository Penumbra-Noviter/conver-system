# TECH_DEBT: conver system mobile

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 [TICKETS.md](TICKETS.md)（任务池）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 [AGENTS.md](AGENTS.md) §3 任务清单生命周期（项目级，与桌面库同构）。

---

## 规范说明

### 条目格式

候选区每行对应一条技术债，含 6 个字段：

| 字段 | 含义 |
|------|------|
| **编号** | `F-N` 递增唯一（与桌面库编号体系独立，本库从 F-1 起） |
| **遗留项** | 什么问题、在哪个文件、当前影响 |
| **来源** | 产生此条目的审核/讨论/评审 |
| **强度** | `Strong` / `Worth exploring` / `Speculative`（见下方消费规则） |
| **状态** | `📝 待立项` / `🔄 进行中` / `✅ 已修` / `❌ 复核关闭` |
| **归属方向** | 业务方向（如 `聊天链路` / `模拟器桥` / `数据层`），session 只认领匹配方向的条目 |

### 强度消费规则

| 强度 | 消费规则 |
|------|----------|
| **Strong** | 必入工单清单（下一轮 kickoff 的 plan-tickets 必须包含） |
| **Worth exploring** | 入候选由 Grilling 拍板（做/关闭），无默认方向 |
| **Speculative** | 可关闭，关闭须「`git grep` 复核现状仍成立」一句话理由 |

### 清出机制（防膨胀）

1. 候选区只留开放条目（📝 待立项 / 🔄 进行中）；条目处置后整行移出候选区，处置详情写入「技术债处置记录」。
2. ❌ 关闭条目压缩：具复核价值的关闭项保留单行摘要，其余删除。
3. 处置记录按日期分节，滚动保留最近 2 节；更早节整体删除（归档由 git 历史承担）。
4. 清出动作绑定会话末 commit 前节点执行，不新增仪式。
5. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md --candidate-section "## 候选区"` 强制（挂 pre-commit，失败拒提交）——本库候选区节名非标准（`候选区`）且无「维护说明」footer 锚点，脚本按节名参数与「无 footer 节则不检查」自适应：候选区无 ✅/❌ 滞留、活跃工单无 ✅/❌、重复标题、非空与必要节、表格列数异常报格式问题；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制）。

---

## 候选区

> 当前 **0 项待立项**（F-24 已于 2026-09-07 消费完毕，处置见下方处置记录）。历史消费（2026-09-06 M4 收口 F-23 share_plus 分面关闭、2026-09-07 批次 F-18/F-23 全部处置、2026-09-07 批次 F-24、2026-08-29 技术债批次 F-7/F-8/F-9 处置、2026-08-30 批次 F-10~F-17 处置，见下方处置记录；更早历史由 git 历史承担）：F-1/F-2/F-4/F-5 ✅ 已修、F-6 ❌ 复核关闭（`open()` 无调用方系设计意图）、F-3 ✅ 方案 a 处置（2026-08-28）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|

## 技术债处置记录

### 2026-09-07 — 技术债消费批次 F-24（1 项全部处置）

> 来源：improve-codebase-architecture 探索报告备选 B（Speculative）+ 用户指令「先消费技术债」显式立项。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费 F-24〉；全量 819 测全绿 / analyze 0（行为零变化，重构型收敛）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-24 | SettingsReader 契约语义与实现语义收敛靠碰巧 | improve-codebase-architecture 探索报告备选 B | Speculative | ✅ 已修：兜底常量**单一归属** `SettingsDefaults`（`settings_reader.dart` 新增 `abstract final class`：provider/model/userName 三常量）；`SettingsRepository` 三 getter 填充与 `ConversationRepository._fallback*` 兜底均改为引用同一常量（原为各自字面量、碰巧相等）；契约文档对齐「实现方填充」现状（原声明「返回空串由消费方回退」与实现矛盾）；消费方 `_resolveValue` 逻辑不动（测试 fake 返回空串的兜底语义保留）——任一侧常量改动全局生效，静默破约风险消除；数据层 88 测原样绿（行为零变化实证） |

### 2026-09-07 — 技术债消费批次 F-18/F-23（2 项全部处置）

> 来源：用户指令「消费技术债 F-18 F-23」显式立项（非 Grilling 拍板，两候选均 Worth exploring 由用户拍板做）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-18/F-23〉；F-23 证据 `.scratch/techdebt-f18-f23/evidence/F-23.md`；F-18 全量 803 测全绿 / analyze 0 / code-review 四轴 PASS。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-18 | 向导校验门分置两处（Locality） | M3 期末四轴（Architecture） | Worth exploring | ✅ 已修：步骤②模板门移入 `WizardController.next()` case 2（template 未选 → 拦「请选择一个模板」+ 不前进；import 放行），`selectTemplate` 补 `_error = null`；视图删 `_step2Error` 字段与视图层拦截，统一读 `controller.error`——分步校验单一载体 = next() 的 case 1/2/3 switch；测试拆分新契约 + 文案锚保持（controller_test +17 行 / step2 测试原样绿） |
| F-23 | file_picker / 批量删除手势真机面未触达（share_plus 分面已关闭） | M3 冒烟 4.5 覆盖说明 | Worth exploring | ✅ 已闭合：file_picker 导入系统选择器弹出（`com.android.documentsui` 前台实证）+ 批量删除长按多选手势（长按进多选/自动勾选/加选计数「已选 2 个角色」/退出恢复）模拟器冒烟 PASS，零代码改动；share_plus 分面已于 2026-09-06 M4-06 关闭 → F-23 整条三分面全部闭环 |

### 2026-09-06 — M4 里程碑收口：F-23 share_plus 分面并入 M4 验收关闭

> 来源：M4-06 模拟器真通道冒烟（spec 修订：share_plus 分面并入 M4 验收，file_picker 与批量多选手势归 M5）。证据 `.scratch/m4-kickoff/evidence/M4-06.md` + `smoke-share-sheet.png`；代码 merge 42099eb + 25c7696（2026-08-30），冒烟 2026-09-06 PASS。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-23 | V2 卡平台真通道冒烟（share_plus 分享面板分面） | M3 冒烟 4.5 覆盖说明 | Worth exploring | ✅ 分面关闭（非整条关闭）：share_plus 分享面板真通道已由 M4-06 冒烟实证（ShareSheet 弹出 ×2 / 临时文件生成且文件名=角色名净化 / 导出内容语义 / **platformTimeout 超时兜底实测**——模拟器无分享接收 app → Future 不 resolve → 3s 超时 → 非阻塞 SnackBar，app 零崩溃）；剩余 file_picker 与批量多选手势两分面在候选区重定界保留，归 M5/真机验证 |

### 2026-08-30 — F-10~F-17 批次期末非阻断观察追溯补录（3 项复核关闭）

> 来源：F-10~F-17 批次期末四轴非阻断观察——原批次交付时误标「不入债」，2026-08-30 按契约追溯补录；Speculative 项 git grep 复核现状仍成立后关闭。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-24 | `translate_helpers.dart` 公开函数命名偏通用（`decodeJson` / `responseText` / `errorMessageFromMap`） | F-10~F-17 批次期末四轴（Standards/Architecture） | Speculative | ❌ 复核关闭：git grep 复核三函数在位且均有完整 docstring 消解歧义（`responseText` L92 / `errorMessageFromMap` L121 / `decodeJson` L135），共享模块命名由工单明确，后续新增 provider 时如需统一可随改随重命名 |
| F-25 | `api_config_section._save` `snapshot`（Map）+ `_apiKeySlots` 旁置集合 + `_rollback(snapshot, written)` 成对参数（Primitive Obsession / Data Clumps） | F-10~F-17 批次期末四轴（Architecture） | Speculative | ❌ 复核关闭：git grep 复核 `_apiKeySlots` L76 / `snapshot` L120-127 / `_rollback` L161 均在位，doc 注释已解释槽位类型区分，私有内部实现零公共 API 影响，捆类型纯美容性 |
| F-26 | `chat_service_test.dart` A3 停滞流用例以 6s 上界断言（慢 CI 机理论 flaky） | F-10~F-17 批次期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核用例 L1081 存在，flutter_test fake clock 推进可控（测试内显式 pump 时间），无实际 flaky 记录，改为等待模式属过度防御 |

### 2026-08-30 — M3 期末四轴非阻断观察处置（4 项复核关闭 + 1 项待立项）

> 来源：M3 期末四轴 code-review（Standards/Falsify/Architecture 非阻断判断）——按「非阻断发现落盘 TECH_DEBT」契约入账，Speculative 项 git grep 复核现状仍成立后关闭（清出机制：关闭项移出候选区，留单行摘要）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-18 | 向导校验门分置两处（Locality） | M3 期末四轴（Architecture） | Worth exploring | 📝 待立项（候选区保留，供下轮 Grilling 拍板做/关闭） |
| F-19 | `CharacterDraft` 13 个公开字段无独立 docstring | M3 期末四轴（Standards） | Speculative | ❌ 复核关闭：git grep 复核字段不在「公开函数必须 docstring」字面范围，`toCompanion()` 单一映射源兜底语义，补写纯美容性、零行为价值 |
| F-20 | 高亮清除双 timer 冗余 | M3 期末四轴（Architecture） | Speculative | ❌ 复核关闭：git grep 复核 controller 与 view 各自为 dispose 独立取消（跨层生命周期），握手幂等无正确性问题，收敛引入跨层耦合 |
| F-21 | F-7 修复后 light 主题高亮 alpha 0.13 vs 原 0.12（位级不等） | M3 期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核 `withValues(alpha:0.13)` 为统一常量，感知不可辨（差 2/255），dark 位级相等已确认，为 colorScheme 消费的固有近似 |
| F-22 | `searchPreview('', q)` 空内容取首命中分支而非 120 字回退 | M3 期末四轴（Falsify） | Speculative | ❌ 复核关闭：git grep 复核 UI 五态门禁保证实际不空串调用，纯函数层防御分支冗余 |

### 2026-08-30 — techdebt-f10-f17 批次收口：F-10~F-17 全部处置（7 做 + 1 关闭）

> 来源：project-kickoff 全自动档技术债消费批次（Grilling 共识 8 候选 7 做 1 关闭、零真拍点；6 工单 2 波 DAG 全零阻断）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-10~F-17〉，证据 `.scratch/techdebt-f10-f17/evidence/`，merge b9dc9bc（基线 5334075）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-10 | ✅ 已修 | T1 `_save` 事务化：写前快照四键（两 Key 槽位 + 两 base_url）→ 逐 provider 写/删 → 任一失败即止 + 回滚已写项（旧非空 write 旧值 / 旧空 delete 或写回空串），回滚失败仅 debugPrint；`_saving` finally 复位；文案逐字不变；重试幂等（+6 新测试 442 行，回滚核心用例 red→green） |
| F-11 | ✅ 已修 | T2 `ConverPalette.of/maybeOf` + 未注册描述性 FlutterError（消息含「未注册」+ ConverTheme/MaterialApp 装配指引）；41 处（7 文件）`extension<ConverPalette>()!` 机械迁移；token 名/值/深浅零改动（theme_tokens + view_theme_tokens 只读全绿）；grep 零残留 |
| F-12 | ✅ 已修 | T3 `_themeController.load().timeout(3s)` 补 `.catchError` → debugPrint，DB 读失败保持缺省 dark、无 zone 未处理异常；`theme_controller.dart` 零改动 |
| F-13 | ✅ 已修 | T3 ThemeSection Stateless→Stateful 持 `_switching` 重入守卫（首行 return + in-flight 禁用 SegmentedButton 双保险），反向连点不再被陈旧守卫吞掉；守卫复位可再切 |
| F-14 | ✅ 已修 | T4 新增 `translate_helpers.dart`（DioException 分类/408/504 特判/文本提取/JSON 解析/HttpStatusError 单实例 6 成员），双 provider 删除 ~120 行私有重复改调共享；claude 独有 `_StreamApiError`/`_errorEventMessage` 保留原位；errors.dart 零 dio 契约保持 |
| F-15 | ❌ 复核关闭 | git grep 复核 lib 生产零消费成立，但为桌面 ChatResponse 契约对齐 + F-6 先例（零消费者系设计意图）+ 4 组测试锁定（chat_service_test 断言 reply/messageId/conversationId），删除拉大双端契约距离——保留不立项 |
| F-16 | ✅ 已修 | T5 新增 `CharacterNotFoundError extends DomainError`（消息「角色不存在: <id>」），streamReply/regenerate 两抛点 StateError→替换，`domainErrorResponse` 404 一族归类（对齐桌面 error_mapping.py）；断言更新 + 404 用例 |
| F-17 | ✅ 已修 | T6 `_stopStreamReply` cancel 包 `.timeout(3s)` + onTimeout 兜底（不抛错、继续回合收尾：部分落库 + 关流）；`_StalledProvider` 停滞流用例锁有界完成 |

### 2026-08-29 — techdebt-f7-f9 批次收口：F-7/F-8/F-9 全部消费

> 来源：project-kickoff 全自动档技术债消费批次（Grilling 共识三候选全做、零真拍点；3 工单单串行链）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-7/F-8/F-9〉，证据 `.scratch/techdebt-f7-f9/evidence/`，commit 68e8d19（基线 78b8a94）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-7 | ✅ 已修 | 新增 `ConverPalette` ThemeExtension（ink1-ink4/border 5 枚，dark/light 注册于 ConverTheme）替代视图层硬编码深色 token；5 视图 25 处消费改经 `extension<ConverPalette>()!`；M1 同构契约（token 值/名/名集）零改动；浅色/深色 widget 断言 + 静态不变量测试锁定 |
| F-8 | ✅ 已修 | api_config/default_model 保存与主题切换失败路径统一「失败 SnackBar + debugPrint」，`_saving` 必复位；theme onSelectionChanged async + await（失败不改控制器态，UI 保持旧值）；settings_view 去 `catch (_) {}` 与空 onTimeout（`_loadEcho` 空回显契约保留）；控制器/仓储零改动 |
| F-9 | ✅ 已修 | `SettingsView`/`ApiConfigSection` 构造 required 注入化，删 `AppDatabase.open()`/`FlutterSecretStore()` 视图层缺省分支与 app_database import；装配链收编 home_shell（SecretStore ← app.dart provider）；`settings_repository.dart:49` 数据层 seam 保留（边界） |

### 2026-08-28 — M1-T08/T07 批次收口（已归档，折叠为一行摘要）

> F-3 按方案 a 处置（时间存储维持 drift INTEGER、schemaVersion 恒 1；ISO 口径契约与亚秒精度移交 M4 导出 JSON 层）；F-4 装配收口（契约锁 `test/app_contract_test.dart` 退役，行为断言迁入主题测试 `app_theme_binding_test.dart` + `theme_tokens_test.dart`）。细节由 git 历史承担。