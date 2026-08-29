# TECH_DEBT: conver system mobile

> **技术债候选池**（未立项子集）与**处置记录**。本文件与 [TICKETS.md](TICKETS.md)（任务池）分离——候选不等于任务，不自动进入任何 session 的 preflight 认领；消费 = 显式「立项」（从候选区取出 → 转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 读取契约与强度消费规则见 AGENTS.md §3 任务清单生命周期（项目级，与桌面库同构）。

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

> 当前 8 项待立项：F-10（设置保存顺序写部分持久化）/ F-11（ConverPalette 注册耦合）/ F-12（load 缺 catchError）/ F-13（主题连点竞态）/ F-14（双 provider 翻译栈重复）/ F-15（RegenerateResult 零消费者）/ F-16（角色缺失文案泛化）/ F-17（停止 cancel 无上界）——全部非阻断（Worth exploring/Speculative），M2 批次后候选区净增 4。历史消费（2026-08-29 技术债批次 F-7/F-8/F-9 处置，见下方处置记录；更早历史由 git 历史承担）：F-1/F-2/F-4/F-5 ✅ 已修、F-6 ❌ 复核关闭（`open()` 无调用方系设计意图）、F-3 ✅ 方案 a 处置（2026-08-28）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-10 | **设置保存顺序写部分持久化**：`api_config_section._save` 逐 provider 依次写/删 Key → `setMany` base_url，非事务——后半段失败时显示「保存失败，请重试」，但前半段 Key 已落库（跨 provider 同理）。重试幂等无损坏，但失败文案与真实持久化状态不一致，用户对落库状态产生认知偏差（F-8 失败 UI 使其首次显性化） | 波末增量审核 N1 + 期末四轴 Falsify 复证 | Worth exploring | 📝 待立项 | 设置页/前端 |
| F-11 | **ConverPalette 未注册 fail-fast 不透明 + 测试面耦合涟漪**：5 视图 25 处 `extension<ConverPalette>()!`，任何不经 ConverTheme 的 MaterialApp 下 build 期 null 崩溃（错误信息泛化「null check operator used on a null value」）；`settings_sections_widget_test` pumpSection 被迫注册 ConverTheme.dark——每个未来渲染 section 的测试/调用方都必须知晓注册扩展 | 波末增量审核 N2 + 期末四轴 Falsify 复证（A） | Worth exploring | 📝 待立项 | 前端主题 |
| F-12 | **`_themeController.load()` 无 catchError（既有债）**：settings_view initState 中 `.timeout(...)` 无 catch——DB 读失败抛错 → 未处理 async 异常（debug 打屏 / release 静默）；F-8「不静默吞错」精神未达此处 | 期末四轴 Falsify（C，批次范围外既有） | Worth exploring | 📝 待立项 | 设置页/前端 |
| F-13 | **主题快速连点竞态**：`onSelectionChanged` 改 async 后，连点浅/深色产生并发 `setThemeMode`；`mode != themeMode` 守卫在 in-flight 时 `_themeMode` 未提交，吞掉第二次反向 tap（用户已点深色实际停在浅色）。轻微 UX 竞态，非崩溃 | 期末四轴 Falsify（B） | Speculative | 📝 待立项 | 设置页/前端 |
| F-14 | **双 provider 翻译栈重复（Divergent Change 风险）**：`claude_provider.dart` 与 `openai_provider.dart` 的 `translateError`/`_translateDio`/`_translateStatus`/`_responseText`/`_errorMessageFromMap`/`_decodeJson` 约 120 行逐字重复（仅端点/请求体不同）——未来改 401 语义/超时类别须改两处 | M2 期末四轴（Architecture） | Worth exploring | 📝 待立项 | 聊天链路 |
| F-15 | **RegenerateResult 零消费者（Speculative Generality）**：`chat_service.dart` `regenerate` 返回富结果对象（reply/messageId/conversationId），但 `chat_controller` 直接丢弃、lib 全库无人读取——接口表面 > 行为收益 | M2 期末四轴（Standards/Architecture） | Speculative | 📝 待立项 | 聊天链路 |
| F-16 | **角色缺失文案泛化**：`chat_service.dart` 角色不存在抛 `StateError('角色不存在: ...')` → 兜底「生成回复失败: StateError...」；桌面 `exceptions.py` 有 `CharacterNotFoundError` → 404 领域语义，移动端未迁移 | M2 期末四轴（Spec） | Worth exploring | 📝 待立项 | 聊天链路 |
| F-17 | **停止 cancel 无上界**：`_stopStreamReply` `await state.providerSub?.cancel()` 在真实网络停滞（socket read 无数据）时等待下一块数据/EOF，「点停止立即中止」即时性不成立（非崩溃，UI 已同步复位）；测试恒定 chunk 间隔掩盖此面 | M2 波4增量审核 concern 复验 | Worth exploring | 📝 待立项 | 聊天链路 |

## 技术债处置记录

### 2026-08-29 — techdebt-f7-f9 批次收口：F-7/F-8/F-9 全部消费

> 来源：project-kickoff 全自动档技术债消费批次（Grilling 共识三候选全做、零真拍点；3 工单单串行链）。交付见 [DEV_LOG.md](DEV_LOG.md)〈技术债消费批次 F-7/F-8/F-9〉，证据 `.scratch/techdebt-f7-f9/evidence/`，commit 68e8d19（基线 78b8a94）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-7 | ✅ 已修 | 新增 `ConverPalette` ThemeExtension（ink1-ink4/border 5 枚，dark/light 注册于 ConverTheme）替代视图层硬编码深色 token；5 视图 25 处消费改经 `extension<ConverPalette>()!`；M1 同构契约（token 值/名/名集）零改动；浅色/深色 widget 断言 + 静态不变量测试锁定 |
| F-8 | ✅ 已修 | api_config/default_model 保存与主题切换失败路径统一「失败 SnackBar + debugPrint」，`_saving` 必复位；theme onSelectionChanged async + await（失败不改控制器态，UI 保持旧值）；settings_view 去 `catch (_) {}` 与空 onTimeout（`_loadEcho` 空回显契约保留）；控制器/仓储零改动 |
| F-9 | ✅ 已修 | `SettingsView`/`ApiConfigSection` 构造 required 注入化，删 `AppDatabase.open()`/`FlutterSecretStore()` 视图层缺省分支与 app_database import；装配链收编 home_shell（SecretStore ← app.dart provider）；`settings_repository.dart:49` 数据层 seam 保留（边界） |

### 2026-08-28 — M1-T08（波 5）收口：F-3 方案 a 处置

| 编号 | 处置 | 详情 |
|------|------|------|
| F-3 | ✅ 已按方案 a 处置（用户此前拍板） | 时间存储维持 drift INTEGER（unix 秒）不变，零代码与 schema 变更（schemaVersion 恒 1）；tables.dart 头注释悬置表述已改写为处置声明。**M4 移交注记**：双端互迁 / ISO 口径契约归 M4 导出 JSON 层；亚秒精度损失由消息排序 `created_at, id` 兜底（同秒按 id 正序），亚秒精度移交 M4 导出层处理 |

### 2026-08-28 — M1-T07（波 4）装配收口

| 编号 | 处置 | 详情 |
|------|------|------|
| F-4 | ✅ 已按预期升级 | 契约锁已按注释退役（`test/app_contract_test.dart` 删除），行为断言迁入主题测试：`test/theme/app_theme_binding_test.dart`（pump 真实 ConverApp → 改 ThemeController → 断言 MaterialApp 实际生效对应 ThemeData；首启 dark / 双向切换判别 / 重启恢复三用例）+ `test/theme/theme_tokens_test.dart` 浅色锚定与深浅同构断言（G3） |