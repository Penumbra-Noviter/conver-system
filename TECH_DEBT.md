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

> 当前 6 项待立项（M0 kickoff 批次审核落盘：W2 审核 F-1~F-3、W3 审核 F-4、期末四轴 F-5~F-6；全部非阻断，2026-08-29）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-1 | `lib/data/database/tables.dart:13` 头注释称桌面时间戳为「ORM 层客户端默认」，实际 character.py 还有 `server_default=func.now()`（SQL 层默认）——注释对权威源描述不完整 | M0 W2 增量审核 | Worth exploring | 📝 待立项 | 数据层 |
| F-2 | 仓库无 `.gitattributes`，Windows checkout CRLF / 仓库 LF 造成行尾搅动（重跑 build_runner 后 git status 短暂显示 M，内容零差异）；桌面库有 `.gitattributes` 可参照 | M0 W2 增量审核 | Worth exploring | 📝 待立项 | 工程卫生 |
| F-3 | DateTime 存储表示差异：drift 默认落 INTEGER（unix 秒），桌面 SQLAlchemy DateTime 落 TEXT（ISO 字符串）——M0 无迁移需求（工单 03 已显式声明），但 **M1 迁移基线 / M4 导出 / 双端数据互迁**设计时必须处理该表示差 | M0 W2 增量审核（工单 03 高不确定点显式声明） | Worth exploring | 📝 待立项 | 数据层 |
| F-4 | `themeMode: ThemeMode.dark` 装配无测试判别力：`darkTheme` 为 null 时无论 ThemeMode 取值均回退 `theme`，删掉该行全部测试仍绿——需测试加固（如注入假 lightTheme 断言不被采用）或接受文本锚核验 | M0 W3 增量审核 | Worth exploring | 📝 待立项 | 测试 |
| F-5 | `.scratch/`（含 G0 门证据截图）未被 `.gitignore` 覆盖——`git add -A` 会把门证据扫入提交，与「存档 .scratch 不入库」约定相悖 | M0 期末四轴审核（Falsify 轴） | Worth exploring | 📝 待立项 | 工程卫生 |
| F-6 | `AppDatabase.open()`（lib/data/database/app_database.dart:31）零调用零覆盖——drift_flutter 惰性打开路径 M0 无验证（spec 显式 M0 不调用，M1 工单自会覆盖；可关闭候选） | M0 期末四轴审核（Falsify/Architecture 轴） | Speculative | 📝 待立项 | 数据层 |

## 技术债处置记录

> 暂无处置（2026-08-28 建库）。