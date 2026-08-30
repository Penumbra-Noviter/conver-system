# TECH_DEBT: conver system mobile

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 [TICKETS.md](TICKETS.md)（任务池）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 [CLAUDE.md](CLAUDE.md) §3 任务清单生命周期（项目级，与桌面库同构）。

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

---

## 候选区

> 当前 2 项待立项（F-18 校验门分置 / F-23 平台真通道冒烟未深度触达，见下表）。历史消费（2026-08-29 技术债批次 F-7/F-8/F-9 处置、2026-08-30 批次 F-10~F-17 处置，见下方处置记录；更早历史由 git 历史承担）：F-1/F-2/F-4/F-5 ✅ 已修、F-6 ❌ 复核关闭（`open()` 无调用方系设计意图）、F-3 ✅ 方案 a 处置（2026-08-28）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-18 | **向导校验门分置两处（Locality 折损）**：步骤①③⑥ 校验在 `WizardController.next()/save()`，步骤②模板门在视图 `_handleNext`（`_step2Error`）——同属「分步校验」概念，改校验逻辑须两处维护；触发面：template 模式未选模板时视图拦截、controller 直调 `next()` 于步骤②放行 | M3 期末四轴（Architecture） | Worth exploring | 📝 待立项 | 前端向导 |
| F-23 | **V2 卡平台真通道冒烟未深度触达**：file_picker 文件选择器 / share_plus 分享面板 / 批量删除长按多选手势在 M3 模拟器冒烟未实测（避免污染真机数据），由 126 测（card+seam fake）+ 26 测（batch）锁定——平台通道挂起型失败与手势交互的真机面待真机/后续里程碑验证 | M3 冒烟 4.5 覆盖说明 | Worth exploring | 📝 待立项 | 平台验证 |

## 技术债处置记录

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