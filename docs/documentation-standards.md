# Conver System — 文档规范 (Documentation Standards)

> 本项目文档架构规范，依据 Profit Calculator 项目经验与个人知识库沉淀（`经验/文档漂移`、`经验/审计快照过期需复核`、`学习/项目驱动知识库模式`）制定。
> 核心原则：**同一信息只允许存在于一个文档，其他文档引用而非复制**——凡在两处出现即漂移信号，须立即合并或改为引用。

---

## 一、文档清单与单一事实来源分配

| 文档 | 角色 | 唯一来源（什么信息只归它管） |
|------|------|------------------------------|
| `CONSENSUS.md` | 需求 + 决策 | 产品决策、技术选型、规格定义。**改设计前先更新这里** |
| `TICKETS.md` | **唯一待办事实来源** | 所有未完成/已归档工单（含完成日期 + 提交哈希）。待办**绝不落** DEV_LOG / memory / 个人笔记 |
| `DEV_LOG.md` | 已做 + 避坑 | 完成记录、bug 根因、优化/重构进展。只记「已做」，不记待办 |
| `PROJECT_REFERENCE.md` | 项目介绍 | 一句话、项目概述、关键决策、常碰坑点。**不复制技术细节**（技术细节指向 docs/） |
| `README.md` | 用户视角 | 安装、使用、快速开始、贡献入口。不维护技术栈表/路线图副本 |
| `docs/architecture.md` | 技术事实 | 系统架构图、目录结构、数据流、数据库设计 |
| `docs/api-design.md` | 技术事实 | API 契约（路径/请求/响应/错误），改路由必须同步 |
| `docs/llm-integration.md` | 技术事实 | LLM Provider 抽象层、Factory 注册、消息组装 |
| `docs/p2.5-character-import-export.md` | 专项设计 | 角色卡 V2 导入/导出规格与决策（D1-D6） |
| `docs/tauri-setup.md` | 技术事实 | Tauri 桌面端工具链安装、路径、环境注意事项 |
| `docs/development-plan.md` | 历史 | **已被 TICKETS.md 取代**，仅作历史保留，不再维护 |
| `.claude/` 记忆 + Serena memory | 会话上下文 | 项目状态、规范速记；**不持待办** |

> 参照项目经验：技术细节统一以 docs/ 为准（对标 Profit Calculator 的 CODE_WIKI.md 角色），PROJECT_REFERENCE 与 README 只写各自角色该有的内容。

## 二、格式约定

### DEV_LOG.md
- 格式：`YYYY-MM-DD | <操作> | <描述>`，**倒序，最新在前**。
- 顶部「滚动摘要」：当前阶段、测试/质量状态、活跃工单指针，每次会话结束更新。
- 只记「已做」与决策/避坑；待办一律进 TICKETS。
- Bug 修复保留「根因 + 修复方案」细节（这是日志最值钱的部分），其余条目一行浓缩。

### TICKETS.md
- 状态流转：📝 已录入 → 🔄 进行中（开始实现前认领）→ ✅/❌ 完成 → **移入「已完成归档」区**并记完成日期 + 提交哈希。
- **活跃表只保留未完成工单**；已完成项不在原位打勾，一律归档。
- 新评审候选（含未拍板的 `Worth exploring` / `Speculative`）立即录入活跃表。

## 三、测试规范（Testing Standards）

> 依据 2026-08-03 文档/测试专项审查沉淀（共享 fixture 重复、覆盖率声明不可复现等教训）。测试基础设施：`pytest.ini`（`pythonpath=.` + `testpaths=backend/tests`）+ `backend/requirements-dev.txt`，运行根目录 `pytest` 即可。

### 测试文件组织

- 测试统一放 `backend/tests/`，文件命名 `test_<功能域>.py`（如 `test_character_card.py`），被测模块同名（`character_card`）。
- 每个测试文件顶部 docstring 说明覆盖范围与依赖（内存 SQLite / 纯函数）。
- **共享 fixture 一律入 `conftest.py`**，禁止跨文件复制 fixture（2026-08-03 教训：`db_session` 在 test_p35 / test_settings_connection 各复制一份）。
- `db_session` fixture 用内存 SQLite + `StaticPool`（`check_same_thread=False`），每个测试独立建库/删库；纯函数测试（如转换层）不建库。

### 测试纪律

- 新功能 / 重构必须带测试；**bug fix 先写复现测试再修**。
- 测试不发起真实网络请求：Provider 一律 stub / monkeypatch `LLMFactory.get_provider`。
- 端点测试同步驱动异步函数（`asyncio.run`），不依赖 TestClient 亦可。

### 覆盖率与测试数声明

- **覆盖率声明必须可复现**：声称的百分比须有可复现命令（`pytest --cov=<模块>`）+ 产物（`.coverage` / cov 报告）背书；无产物即不写「100% 覆盖」（2026-08-03 教训：`character_card.py 100% 行覆盖` 无 .coverage 佐证）。
- **测试数同步**：DEV_LOG / TICKETS 记录的用例数与 `pytest --co` 实际一致；每增删测试后同步更新。

## 四、维护节奏（绑定现有流程节点，不新增习惯）

1. **开始实现某工单前**：TICKETS 状态 📝 → 🔄（认领）。
2. **每会话结束、commit 之前**：
   - TICKETS：完成的 → ✅ → 移入归档并记日期/哈希；新候选 → 录入活跃表。
   - DEV_LOG：记本次「已做」条目，更新滚动摘要。
   - 漂移检查：本次改动涉及测试数 / 方法名 / API 路径 / 技术栈的，grep 相关文档是否残留旧值。
3. **阶段完成时**：code-review → 符合条件才打包 → 有教训才向知识库蒸馏（见下）。

## 五、知识库闭环（预检读 / 蒸馏写）

- **预检（读）**：开工或进入新阶段前，按 `知识库/模板/项目预检模板.md` 执行——只读 `经验/` 中本项目 tag 的原子笔记与相关 ADR，不整库读。
- **蒸馏（写）**：阶段完成时，**有教训才写** `经验/` 原子笔记（五段式：症状→根因→代价→教训→防复发）；复盘大文件仅在重大里程碑更新。蒸馏不是 KPI。
- **相关已登记经验**：
  - `[[文档漂移]]` — 信息单点化，重复即欠债。
  - `[[审计快照过期需复核]]` — 执行 CR/审计工单前先 `git grep` 复核当前代码，发现已就绪标「复核确认」而非重改。

## 六、防漂移速查（写文档前对照）

- [ ] 这条信息**是不是已经在别处写过**？（是 → 改为引用，不复制）
- [ ] DEV_LOG 里有没有 `- [ ]` 待办？（有 → 移到 TICKETS）
- [ ] 测试数 / 方法签名 / API 路径 / 技术栈 是否与代码一致？（改代码后 grep 复核）
- [ ] **API 契约完整性**：新增/修改路由端点后是否同步 `api-design.md`？（含非 CRUD 端点：import/export/test-connection/search，2026-08-03 教训：6 个端点缺失）
- [ ] **字段名以 schema/model 为准**：文档中出现 `greeting` 等旧字段即漂移（2026-08-03 教训：实际为 `first_mes`）
- [ ] **规格偏差闭环**：实现与规格不符并记入 DEV_LOG 后，规格文档本身也必须同步修正（2026-08-03 教训：P2.5.2 只记日志未改 SPEC §4.2）
- [ ] **覆盖率声明有产物**：声称的覆盖率可当场 `pytest --cov` 复现（见 §三 测试规范）
- [ ] 审计/评审产出是否先复核当前代码再执行？（见 `[[审计快照过期需复核]]`）
