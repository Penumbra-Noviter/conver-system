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
2. ❌ 关闭条目压缩：具复核价值的关闭项保留单行摘要于「复核关闭」表（滚动保留最近 4 批关闭批次，按关闭日期计同日合并一批），更早批次整批删除。
3. 处置记录按日期分节，滚动保留最近 2 节；更早节整体删除（归档由 git 历史承担）。
4. **候选区 0 项时正文只留标题 + 空表格，不写任何「当前 0 项待立项 / 历史消费罗列」叙述**——处置事实由「技术债处置记录」与 git 历史承担（2026-09-07 用户拍板，防清空后残留历史罗列）。
5. 清出动作绑定会话末 commit 前节点执行，不新增仪式。
6. **机械约束**由 `scripts/pool_cleanup_check.py --check --tickets-file TICKETS.md --candidate-section "## 候选区"` 强制（挂 pre-commit，失败拒提交）——本库候选区节名非标准（`候选区`）且无「维护说明」footer 锚点，脚本按节名参数与「无 footer 节则不检查」自适应：候选区无 ✅/❌ 滞留、活跃工单无 ✅/❌、重复标题、非空与必要节、表格列数异常报格式问题；安装 `sh scripts/install-pre-commit.sh`（每 clone 一次，本库安装脚本按上述参数定制）。

---

## 候选区

| 编号 | 遗留项 | 来源 | 强度 | 状态 | 归属方向 |
|------|--------|------|------|------|----------|
| F-113 | `memory_management_view.dart` `_RevisionTile` trailing 双中文 TextButton 窄屏（≤360dp）溢出未验证 | 波 1 增量审核 Falsify（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-114 | SR-22 `substring(0,2000)` 可能切在代理对中间 → 落库尾部 U+FFFD（实测 UTF-8/JSON 编码均不抛无崩溃，与 embedding 截断同口径先例） | 波 1 增量审核 Falsify（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-115 | `maxPersonalitySnapshotLength` 与 `memory_repository.dart:253` 字面量 2000 双源，靠注释对账（S-2） | 期末四轴 Standards（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-116 | SR-22 clamp 截断后恰等于当前人格 → 返回 null 的交叉边界无直接单测（SP-1） | 期末四轴 Spec（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-117 | Q7「apply 后手动编辑 → 回待确认 → 再应用幂等」链路无测试证据（SP-2） | 期末四轴 Spec（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-118 | apply/discard 异常吞并分支无测试 + view 层 propose 异常 banner 渲染无断言（F-1） | 期末四轴 Falsify（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-119 | `_PromptDialog` 取消路径（pop → unmount → dispose）无 widget 测试（F-2） | 期末四轴 Falsify（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-120 | LLM 注入链两份同构闭包未收敛（app.dart 装配闭包 vs ReflectionService 先例，S-1/A-1 同源），第三处出现时协议面重复扩张 | 期末四轴 Standards/Architecture（f109-evolution） | Weak | 📝 待立项 | 伴侣域 |
| F-121 | 记忆管理页空态无「新增记忆」入口（既有交互，非本批引入；03 concern ②） | 波 1 Implement concern 裁决（f109-evolution） | Worth exploring | 📝 待立项 | 伴侣域 |

## 技术债处置记录

### 2026-09-17 — 技术债消费批次（F-109 已修 + F-110~112 复核关闭）

> 来源：handoff-stage3-vector-recall-a8-local-2026-09-17 交接指令（project-kickoff 全自动档）。F-109 立项消费（3 工单串行 lane：01 E1+SR-22 `2d580ca` / 02 装配腿 `a532e93` / 03 确认闸门 UI `4ef0977`，merge `9b642d8`）；F-110~112 逐条 git grep 复核关闭（证据见 `.scratch/f109-evolution/grilling-consensus.md` §4）。门禁：全量 **2208 测**绿（基线 2185 → +23）/ analyze 0 / 波末增量审核 0 阻断（W-1/W-2 落债 F-113/114）/ 期末四轴 **通过**（0 Critical，7 条 Weak 落债 F-115~121）。详见 DEV_LOG〈技术债消费批次 F-109 演化入口补全〉。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-109 | ✅ 已修 | 演化端到端入口补全三腿：E1 服务 `_reflector` 改 `CharacterScopedReflector` + propose 透传 characterId（PersonaReflector typedef 保留）/ F1 装配腿 `Provider<PersonaEvolutionService>`（默认 lazy，wireCredentialsResolver + buildClusteredReflector 闭包，与 ReflectionService 先例同构）/ 确认闸门 UI（记忆管理页 AppBar「提出人设演化」+ tile 双形态应用拒绝 + Q7 启发式 appliedRevisionIds + SnackBar 三态 + `characters_view` 注入入口）；SR-22 快照长度 clamp 2000（`maxPersonalitySnapshotLength`）；零新依赖、schemaVersion 保持 5；顺带修复既有 `_PromptDialog` dispose 时机 bug（widget 测试暴露） |
| F-110 | ❌ 复核关闭 | per-element isFinite 守卫已存在（cosine_similarity.dart:32-34）+ float32 截断 Infinity 双防线，票面「float32 真实数据不可达」复核成立 |
| F-111 | ❌ 复核关闭 | SR-20 装配链单一落点 validateEmbeddingBaseUrl 已拦截全部无 host 输入；normalizeBaseUrl 仅在校验后输入上运行（docstring 明示前置），「绕过装配直构」非支持路径；F-111 残余用户拍板不立票 |
| F-112 | ❌ 复核关闭 | 唯一索引 `idx_embedding_entries_character_id_content_hash`（unique:true）实锤存在 + 服务层串行 await 无竞争窗口 + 反思链精确去重，票面「服务层无竞争窗口」复核成立 |

### 2026-09-17 — 人机恋阶段 3 批次（净增候选 F-109~112，随后于 F-109 消费批次全部处置）

> 本批为功能批次（远端 embedding 向量检索 kickoff），未消费既有候选。波末/期末审核非阻断发现落盘 4 条候选（F-109 plan-tickets 实证 / F-110 波 1 审核 / F-111、F-112 波 2 审核）；Falsify-1（`https://` 纯协议段放行）波内修复不入债。F-110~112 均为 Weak（float32 真实数据不可达 / 装配链已拦截 / 服务层无竞争窗口），F-109 为 Worth exploring（演化端到端入口缺位）。详见 DEV_LOG〈人机恋阶段 3 批次〉。四候选已由上方「F-109 已修 + F-110~112 复核关闭」节收口。

### 2026-09-17 — 技术债消费批次（F-106~F-108 全部处置）

> 来源：handoff-techdebt-f104f105-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波 + 批次收尾（F106F108-01 `a537f71` / F106F108-02 `a399b9f`，merge `9200f49`）。门禁：全量 **2001 测**绿（基线 2000 → +1 排序锚用例）/ analyze 0 / 期末四轴 **通过**（0 Critical）。**F-106 根因实证**：`listCharacters` 仅 `ORDER BY updated_at DESC` 无二级排序键 + drift 秒级存储 + `DateTime.now()` 连续创建同值 → 同值行返回序不确定 → `_resolveSelectedCharacterId()` 取 `_characters.first.id` 偶发非 seed 首个（chat_entry_test「默认选中首角色」Expected 1/Actual 2）；修复 = `id ASC` 二级排序键（生产 1 文件），同刻注入单测钉序。**F-107 单源收敛**：`test/helpers/pump_until.dart`（窗口统一 300×10ms）替代 6 测试文件各自定义 + why 归因改现象式。**F-108 收敛**：纠偏口径文档落点收敛 DEV_LOG 指针 + 补注 `git log -S` 搜索串。候选区清零，无新落债。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-106 | ✅ 已修 | F106F108-01：`character_repository.dart` `listCharacters` 排序改 `ORDER BY updated_at DESC, id ASC`（同 updated_at 按创建序稳定，docstring 契约句）；`character_repository_test.dart` 新增同刻注入锚用例（固定 `fakeNow` 两次 seed → 首元素 id = 较小者）；本批复现循环 10 遍全绿（fallback，锚定上批 10+5 次实证 Expected 1/Actual 2 + 静态根因闭合） |
| F-107 | ✅ 已修 | F106F108-02：`test/helpers/pump_until.dart` 单一权威定义（300×10ms，docstring 注明用途与失败模式）；6 测试文件删本地定义 + import；`characters_view_stage2_test` 5 处「（broker publish 生效延迟）」归因 why 改现象式；生产零 diff |
| F-108 | ✅ 已修 | 批次收尾：TECH_DEBT/TICKETS 的 F-101/F-105 引述收敛为「详见 DEV_LOG」指针（删 4-commit 清单复制）；DEV_LOG 权威源补注 `git log -S "锁失效并行交错"`（子串口径，勿与完整带若变体混用） |

### 2026-09-17 — 技术债消费批次（F-104~F-105 全部处置）

> 来源：handoff-techdebt-f101f103-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波串行 lane（F104F105-01 `a5e79b7` merge `ffb05c7` / F104F105-02 `77fb9a1` merge `ffb05c7`）。门禁：全量 **2000 测**绿 / analyze 0 / 期末四轴 **通过**（0 Critical）。**票面归因实证推翻**：F-104 复现循环（shell 逐遍 10 次全量，`--repeat` 不被 flutter_tools 3.47.2 支持）捕获 2 次失败，均为 `chat_entry_test`「默认选中首角色」竞态（Expected 1/Actual 2），票面目标 `characters_view_stage2_test` 15 遍零失败——用户拍板：01 票按 fallback 语义收口（健壮性修复 + 残余风险明确定位），chat_entry 竞态另立 F-106（Strong）下批消费。F-105 四处「从未存在于仓库」失实表述统一为「从未存在于代码 reason（文档/注释引述除外）」口径。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-104 | ✅ 已修（fallback 语义） | F104F105-01：`pumpStage2` loading 轮询 100 次静默放行 → `pumpUntil`（300 次）+ 显式断言「角色列表加载未在轮询窗口内完成」；5 处 publish 用例（升级建议：亲密 / 多选态确认 / 确认 / 拒绝 / F1）断言前单帧裸 pump → 条件等待；无 test 块增删、生产零 diff。票面目标未实证复现（15 遍零失败），残余 flaky = chat_entry_test 竞态（立 F-106），交付说明如实标注 |
| F-105 | ✅ 已修 | F104F105-02：4 处旧版失实表述修正（DEV_LOG 票面纠偏句 / TECH_DEBT 处置记录引注 / TICKETS 归档行 / `notification_service_test.dart` 注释块），统一「从未存在于代码 reason（文档/注释引述除外）」口径 + `git log -S` 实证引据（commit 清单详见 DEV_LOG〈技术债消费批次 techdebt-f101f103〉）；纯文本/注释，生产零 diff、行为零变化 |

### 2026-09-17 — 技术债消费批次（F-101~F-103 全部处置）

> 来源：handoff-techdebt-f98f100-done-2026-09-17 交接指令（project-kickoff 全自动档）。2 工单并批 1 波串行 lane（F101F103-01 `8fd29fe` merge `61c9ca3` / F101F103-02 `3d2b8b1` merge `61c9ca3`）。门禁：全量 **2000 测**绿 / analyze 0 / 期末四轴 **0 阻断**（F-103 复核关闭；无新落债）。票面纠偏：F-101 票面「修正 reason 文本」修正对象不存在（「若锁失效并行交错则为 1」从未存在于**代码 reason**（文档/注释引述除外），`git log -S` 实证引据与 `git show 76f7da8` 原文详见 DEV_LOG〈技术债消费批次 techdebt-f101f103〉）；B′ 双 gate 中间态断言为唯一零生产改动独立钉锁方案，突变实验实锤（移除 `await previous` → 中间态期望 1 实际 2 红）。

| 编号 | 处置 | 详情 |
|------|------|------|
| F-101 | ✅ 已修 | F101F103-01：反序 gate 用例重构双 gate 两阶段 + 中间态 `initializeCalls==1` 断言独立钉 `_initSerial` 锁等待（锁失效突变下红）；fake 零改动、生产零 diff；先红后绿（临时移除 `await previous` → 期望 1 实际 2 红，恢复全绿） |
| F-102 | ✅ 已修 | F101F103-02：告警 seam 用例正常分支独立 `_FakePlugin` + 独立 scheduler，用例内组级 plugin/scheduler 零引用（字面验收线达成）；行为断言语义零变化；顺序对调双向全绿机器实证；生产零 diff |
| F-103 | ❌ 复核关闭 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（上批基线 `3943bf8` 同检查失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音，用户已拍板不立项 |

## 复核关闭（最近 4 批，滚动保留）

> 具复核价值的 Speculative 类关闭项单行摘要，防 review 重复提出；更早批次由 git 历史承担（`git log -p -- TECH_DEBT.md`）。

| 编号 | 关闭批次 | 单行摘要 |
|------|----------|----------|
| F-110/F-111/F-112 | 2026-09-17 | per-element isFinite 守卫 + float32 截断双防线成立（F-110）／SR-20 装配链单一落点已拦截无 host（F-111，残余用户拍板不立票）／唯一索引 `idx_embedding_entries_character_id_content_hash` 实锤 + 服务层无竞争窗口（F-112） |
| F-103 | 2026-09-17 | 全仓 188 文件/223 检查 format 差异为存量 formatter 版本漂移（基线 `3943bf8` 同失败、hunk 一一对应），无行为风险；全仓归一大 diff 噪音已拍板不立项 |
| F-86/F-87 | 2026-09-16 | extractThought 1MiB 截断切破代理对（thought_service.dart:32 现状成立）／关系域读契约双依赖点（chat_service.dart:278/315 注入现状成立），本批聚焦通知域关闭留档 |
| F-74 | 2026-09-10 | 模拟器 server 仅回环绑定 + proxy 目标恒取配置 base + spec 声明不鉴权——加鉴权属过度工程，纵深防御提示留 DEV_LOG |
| F-71/F-72 | 2026-09-10 | patterns= 为 privacy_audit 测试 seam 合法扩展点（非死代码）／FileNameEdgeTrim.none 是默认配置完整性基座（设计意图保留） |
| F-57 | 2026-09-09 | sub.cancel 停滞挂起经三重覆盖收窄，「停止收尾不可跳过」结构性成立，剩余 3s 为 F-17 既定有界契约 |
| F-53/F-54 | 2026-09-09 | `EmptyState.action`／`StatusView.hint` 参数槽 TP-4 共识保留（W1 复核关闭）→ 后被 AR-6 按授权删除（见处置记录） |
| F-58 | 2026-09-09 | 首 token 前 idle 3×60s+退避纯时长 UX 观察，各环行为与契约一致无错判；随 AR-1 行为变更 B1 消亡 |