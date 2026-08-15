# Conver System — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要（回落 6~8 条，规则见 [CLAUDE.md](CLAUDE.md)「待办管理」）。

---

## 滚动摘要（2026-08-15 — C2 saveKeys 匹配语义收口：kickoff 全自动档轻量档 1 工单）

- **来源**：/improve-codebase-architecture 架构评审报告候选 C2（Strong），用户挑中 → kickoff 全自动档。病灶：saveKeys 白名单匹配语义（精确键名 === / 正则模式 ^…$ 锚定匹配）三处分散（simulators.js normalizeSaveKeys 模式编译验证 / save-manager.js whitelistHits 键名匹配 / simulator-manifest.test.js saveKeyHits 测试辅助）——匹配语义内部实现行重复，改匹配方式需改 3 文件。
- **Grilling 共识（全自动档按推荐拍板）**：C2 做——`save-key-meta.js` 从常量契约之家扩为完整深模块，新增 `saveKeyIsPattern`（SAVE_KEY_META_RE 判定的具名导出）/ `saveKeyIsValidPattern`（模式编译验证，供 normalizeSaveKeys 条目级剔除）/ `saveKeyMatches`（白名单匹配单一来源），三消费方对标；规模判定：轻量档（1 工单，收敛型内部重构零新行为）。
- **轻量档 1 工单（b60520d，独立 worktree + 分支 kickoff/c2-savekey-matching）**：save-key-meta 新增 3 导出 + `__all__` 3→6；normalizeSaveKeys 对标（SAVE_KEY_META_RE.test + new RegExp try/catch → saveKeyIsValidPattern）；whitelistHits 对标（inline 匹配 → saveKeyMatches）；saveKeyHits/isPattern 测试内联删除改用导入；+18 契约锁用例（三函数全 Falsify 边界）。merge 79d5799；期末非阻断修复随 CODE_WIKI 补录（§4.53 签名表 3 行 + doc_sync tests_total 1219→1277）
- **范围核验**：6 文件 +213/-42 全部合规（5 声明范围内 + CODE_WIKI doc_sync 机械刷新记录警告）；0 回退 0 冲突
- **期末四轴 code-review（固定点 8c6888d）：0 阻断放行**——Spec 9/9 验收全达标 + 行为等价零变化（784 全绿 vs 基线 766 +18）；Falsify 9 组对抗构造全过（非法输入全部优雅 false 不抛；`a$b` 字面 `$` 语义边界由 normalizeSaveKeys 自锚定拒绝兜底，非缺陷）；Architecture 全正面（协议表面 6 导出隐藏 ~60 行实现、三处重复归 Locality 单点、Leverage 高）；1 项非阻断（CODE_WIKI 签名表缺 3 导出）随补录修复
- **运行态冒烟**：smoke-simulators 13 项 12 PASS / 0 FAIL / 1 SKIP 退出码 0（存档面板导出→清档→导入恢复 saveKeys 匹配核心路径 PASS）；端口已释放
- **测试**：Vitest **784**（基线 766，+18）；pytest 434+1skip / cargo 58 未受影响
- **知识库预检召回**：精读「聚合语义字段跨模块复用须核对语义」（前置 TD-75/76 教训——本批 saveKeyMatches 单源化消除跨模块语义漂移面）；本次无新教训蒸馏（收敛型重构，既有教训已覆盖）
- **文档同步**：TICKETS（C2 批次归档 + 技术债区 C2 行移除）；CODE_WIKI（§4.53 签名补录 + tests_total 刷新）；CLAUDE 基线 766→784；DEV_LOG 本段

---

## 滚动摘要（2026-08-15 — C1 写回环状态机收口：kickoff 全自动档串行链 4 工单）

- **来源**：/improve-codebase-architecture 架构评审报告候选 C1（Worth exploring），用户挑中 → kickoff 全自动档。病灶：模拟器配置同步的写回环状态（冷却 `syncCooldownUntil`/熔断 `syncStrikes`）劈在 simulator-view.js，同步执行在 key-injector.js——写回环决策被拆散到两个文件。
- **Grilling 共识（Q1-Q5 全按推荐拍板）**：Q1=A1 一体状态机 API（`autoSyncIntoGame` 加 `path:'load'|'observer'`，一次调用原子完成冷却判定→同步→置冷却→观察者计数→熔断判定）/ Q2=B1 熔断经返回值 `breaker:true` 传达（熔断动作 disconnectObserver 留在拥有观察者的模块）/ Q3=C1 新导出 `resetSyncLoop()`（复位唯一触发点 = destroyFrame）/ Q4=D1 path 限定自动路径（load 不计数 / observer 计数+熔断 / 手动按钮完全不经状态机）/ Q5 不加熔断 UI 提示（范围克制）、`__all__` 10→11、测试迁移、文档同步
- **串行链 4 工单（单 Implement 一次调用连续完成，独立 worktree + 分支 kickoff/c1-sync-state-machine）**：01 key-injector 状态机（18300a1，+96/-20，11 个 TDD 用例先红后绿）/ 02 simulator-view 收口（b45e917，删状态与常量零残留 + breaker 消费）/ 03 测试头注释同步（030b1d4）/ 04 文档同步（922f03d，头注释 + CONTEXT 术语表）；merge b0a2fcc；非阻断修复 b8c1f05（doc_sync 刷新 total 1201→1259）
- **范围核验**：6 文件 +428/-86 全部合规（CODE_WIKI 已申报 doc_sync 机械同步）；0 回退 0 警告
- **期末四轴 code-review（固定点 3c129e1）：0 阻断放行**——Spec 9 条语义约束全达标（written vs filled 判据、冷却判定时机、路径计数、冷却中 cooled:true、复位唯一触发点、runSync 不动、path 默认 load、跨游戏不残留、熔断权优先）；Falsify 8 组对抗构造全过（熔断后按钮仍可注入 / 冷却双路径跳过 / 熔断幂等兜底 / resetSyncLoop 幂等 / written=0 不置冷却 / path 非法值降级 load 语义 / 跨游戏复位 / TD-76+F1/F2 语义仍覆盖）；Architecture 全正面（状态机收口消除劈两模块，key-injector 实现 +60/接口 +1 仍深，simulator-view 减薄到触发时机）。1 项非阻断（CODE_WIKI 计数漂移）随 b8c1f05 修复
- **运行态冒烟**：smoke-simulators 13 项 12 PASS / 0 FAIL / 1 SKIP 退出码 0；端口已释放
- **测试**：Vitest **766**（基线 755，+11）；pytest 434+1skip / cargo 58 未受影响
- **知识库预检召回**：精读「无框架前端 fetch seam」（同族注入 seam 惯例，本批经 initKeyInjector 延续应用）「聚合语义字段跨模块复用须核对语义」（**written vs filled 判据直接本源——TD-75/76 F1/F2 教训的迁移红线**）「Falsify测试要钉住缺陷所在层」（熔断测试用显式 3 轮步数钉住熔断层）；本次无新教训蒸馏（收口重构，既有教训已覆盖）
- **文档同步**：TICKETS（C1 批次归档）；CLAUDE（批次行 + 基线 755→766）；DEV_LOG 本段

---

## 滚动摘要（2026-08-14 — 技术债区 TD-75/76 批次：kickoff 全自动档小档 2 工单 + 期末四轴修复）

- **来源**：SIM-API-1 期末评审非阻断发现（Spec 轴 TD-75 观察者 childList 窄缺口 + Falsify 轴 TD-76 写回环只节流不终止），用户指令「开始修复，全自动」
- **TD-75（18b96ce）**：观察者补 attributes 监听（setAttribute 重建配置控件触发再同步）；期末 F1 修复（829f387）收窄 `attributeFilter: ['value','hidden']`——配置控件自身 class/disabled 等运行期翻转不触发同步
- **TD-76（26b6af6）**：观察者熔断终止病理循环——真写入字段连续 3 次 → disconnectObserver；冷却判定移到防抖到期时（实测：注入续体置冷却晚于自写 mutation 回调，mutation 时判定失真产生幽灵再同步）
- **期末四轴 code-review（固定点 cb21c92）**：0 崩溃 0 安全红线，但 **Falsify F1/F2 实证命中真实缺陷**——熔断计数用 `filled > 0` 误含幂等匹配（filled 语义 = 已处于目标值含匹配），配置控件良性属性翻转 3 次 / 分散重建即可累积至熔断、**静默压制合法重建**（ADR-0001 承诺失效）；Architecture 轴定性为跨模块语义漂移（simulator-view 把 key-injector 的 filled 解读为「实际写入」）
- **修复（829f387，先红后绿 +3 用例）**：key-injector 返回增 `written`（真写入字段，filled 子集——**熔断/反馈类消费方须用真写入信号**，filled 的幂等匹配不计入）；熔断条件改用 written；熔断计数移入观察者回调（autoSyncAfterLoad 去布尔参——Architecture 布尔参耦合消解）；mutationTouchesConfig id 判定去重
- **教训（已蒸馏）**：聚合语义字段（filled 含幂等匹配）跨模块复用作「真写入」信号前须核对语义——两模块对同一字段语义漂移只有 Falsify 实证能暴露（F1 场景：setAttribute class 3 次即熔断）
- **测试**：Vitest 746 → **755**（+9）；pytest 434+1skip 未受影响；冒烟 13 项 12 PASS（两轮复跑全绿）
- **知识库预检召回**：精读「Conver System 高频小坑汇总」（本批不相关，跳过应用）「Falsify测试要钉住缺陷所在层」（TD-76 熔断测试用显式 3 轮步数钉住熔断层）；蒸馏《聚合语义字段跨模块复用须核对语义》（provenance: 本段 + 829f387）
- **文档同步**：TICKETS（TD-75/76 归档 + **技术债区清零**）；CLAUDE（批次行 + 基线 746→755）；DEV_LOG 本段

---

## 滚动摘要（2026-08-14 — SIM-API-1：22 款模拟器 API/模型配置统一由主应用控制）

- **用户需求**：所有模拟器的 API 统一由主应用控制，模型名也来自主应用设置——22 款游戏各自带 API 配置面板、主应用只做手动「使用主应用 Key」注入的现状要改为单一事实来源。方案经 **ADR-0001**（CONSENSUS.md）定稿：**方案 2 宿主 iframe 统一同步**（key-injector 已是注入 choke point 扩展为自动同步；manifest 声明 endpointMode 做端点口径转换；宿主为模型 select 补受管 option；第三方 HTML 零修改）
- **实现（工单 SIM-API-1）**：manifest 22 条增 `endpointMode`（17 full / 5 base：仿微/侦探模拟/灵网飞升/社会/许愿柳——按各游戏端点字段默认形态逐款实测分类，simulator-manifest 加双向口径溯源锁）；key-injector 扩展（`convertEndpoint` 口径转换 / select 缺主应用模型 option 追加受管 option（取代旧 F1 静默跳过）/ **幂等写入**（值已为目标不写不派发——持续同步写回环守卫）/ `syncGameCredentials` + `autoSyncIntoGame` 编排核心 / 按钮改「重新同步」）；simulator-view **load 自动同步**（openai 静默注入 / claude·none 自动禁用 + 文案 + 设置链接）+ **MutationObserver 配置控件重建再同步**（仅 config id 触及变更触发、防抖 500ms、写入后 1s 冷却）；wg_ 会话注记退役（自动同步每次 load 重放）；parseManifest endpointMode 透传；**22 款第三方 HTML 零修改**
- **避坑（冷却设计迭代）**：写回环冷却必须只在「实际写入过字段」后置位——若在每次同步尝试后置冷却，游戏 load 后延迟渲染配置面板（观察者的主场景）会被 1s 冷却误伤，面板重建后永远等不到再同步；未写入（控件未就位）不冷却，观察者及时补同步
- **测试**：先红后绿；Vitest **745**（基线 714，+31）；pytest 434+1skip 未受影响（后端零改动）
- **真实冒烟（smoke-simulators.mjs 重排）**：预置步骤移至打开游戏前（load 自动同步需 openai 凭证在 load 时已就位）+ 断言重写（自动同步填值 / endpoint full 口径转换 / 受管 option / 手动「重新同步」）；13 项 **12 PASS / 0 FAIL / 1 SKIP** 退出码 0，冒烟后端口已释放
- **文档同步（本批次）**：TICKETS（SIM-API-1 归档 + 活跃表清零）；CONSENSUS（ADR-0001）；CLAUDE（批次行 + Vitest 基线 714→745）；DEV_LOG 本段
- **期末三轴 code-review（固定点 9141035）**：Standards 1 硬违规（docs/architecture.md 收缩措施与模块职责两处未同步——漏改权威文档，随 fix 提交修复）；Spec 0 阻断（4 条微小偏差观察：手动「重新同步」/load 首同步各一次幂等冗余再同步、childList 窄缺口、disabled 早退边界）；**Falsify 1 真实缺口已修复（先红后绿）**——空 select 追加受管 option 后浏览器自动选中 → `el.value === value` 幂等分支成立导致**零事件派发**（依赖 change 保存状态的游戏存旧值）；修复：`ensureSelectOption` 返回 added，本次追加的选中强制走写+派发路径，幂等跳过仅限「option 已存在且值匹配」；+1 用例净增（Vitest 745→746）；2 项低强度理论发现落技术债区（TD-75 属性变更重建不触发观察者 / TD-76 写回环冷却只节流不终止）；冒烟 13 项 12 PASS 复跑全绿

---

## 滚动摘要（2026-08-14 — 桌面版游戏列表为空：打包面漏同步修复 + 教训闭环）

- **用户反馈**：桌面版应用内看不到集成的 22 款游戏（网页版正常）。根因双重：①dist/conver_backend/ 后端包陈旧（08-13 构建，早于模拟器模块加入）；②**backend/conver_backend.spec 的 _FRONTEND_RUNTIME 从未包含 frontend/simulators/**——模拟器模块加入时未同步打包清单，即使重建后端包仍缺游戏。
- **修复（commit 71f34b7）**：spec 增补 `(frontend/simulators, frontend/simulators)` + 注释（漏打包则游戏列表为空）+ test_packaging token 断言同步；重建后端包（包内 22 款游戏 + manifest 22 条）；桌面冒烟 5 项全过；孤儿后端进程清理（ForceKillStale 强杀壳后后端子进程残留，taskkill 树杀后 PyInstaller 才可清旧包）
- **教训闭环（commit 5e29f89 + 知识库 + persona）**：新增前端运行目录必须同步打包面——单向「spec 声明的都存在」拦不住「新增未声明」方向；防复发 = **反向差集锁**（test_packaging.py::test_frontend_runtime_dirs_all_shipped：枚举 frontend/ 实际目录与 spec datas 差集，新增目录未打包即红——探针目录证伪实验已验红）；「网页版能跑不证明打包态能跑」——桌面端变更必跑 smoke-desktop 打包态冒烟；经验笔记《新增前端运行目录必须同步打包面》+ persona 稳定模式更新
- **build-desktop.ps1 加 -SkipInstaller 开关（commit 2f3dc7e）**：常规打包 --no-bundle 仅编译壳，不产 NSIS 安装器（用户惯例：安装包仅在明确提需求时打包）；实跑验证：开关生效/无 NSIS/测试全绿/冒烟 5 项全过

---

- **release 打包（build-desktop.ps1 全链）**：cargo test 全绿 + pytest 433+1skip + Vitest 714 + tauri build（NSIS 安装器 23.7MB）+ dist 测试包（conver-system.exe 10.5MB）+ 冒烟 5 项全过（runtime.json 就绪 / /api/models 200 / 前端挂载 200 / 表结构 / 退出无残留）
- **安装器产物回收（用户明确指令）**：NSIS 安装器（`Conver System_0.1.0_x64-setup.exe`）已删除——用户重申「安装包只在明确提需求时才打包」；**dist/ 根「双击即用」测试包（conver-system.exe + conver_backend/）为常规打包产物**，保留。后续已实现 `-SkipInstaller` 开关（commit 2f3dc7e，见上段）承接此需求，此后常规打包不再产安装器。

---

## 滚动摘要（2026-08-14 — 技术债区 TD-72/73/74 批次：轻量档 1 工单 3 提交全自动 kickoff）

- **TD-72/73/74 批次完成（commit 链 942ffb9 → b49deae → 5435ea5，merge 6ab4cb5，N1 措辞修复 e6a18a9）**：技术债区最后 3 项清理（用户指令「补技术债区」全自动档）——**3 做 0 关闭，TD-74 票面修正**。TD-72 超时守卫延展覆盖响应体读取（`await Promise.race([res.text(), timeoutPromise])`，await 语义载重：finally 等第二 race 结算才清计时器，headers 与响应体共享 15s 总预算；+2 用例先红后绿）/ TD-73 导入回滚 per-key try/catch 尽力而为（单键还原失败不中断继续逆序尝试，循环结束统一抛原始 err 错误同一性；+1 用例先红后绿）/ TD-74 图标一致性锁数量断言放宽（`toBe(2)` → `≥2` 下限防误删 + 逐字节比对承担防漂移，票面修正：数量锁边际价值≈0 且让合法新增误红）
- **期末四轴 code-review（固定点 6196990）：0 阻断放行，3/3 达成**——Falsify 13 组对抗构造全过（TD-72 exp2 反向实证 await 语义载重：无 await 形态守卫失效、测试锁住该语义；TD-73 错误同一性引用相等；TD-74 删一副本仍红/新增漂移副本仍红）；3 项非阻断：N1 docstring 措辞歧义随 e6a18a9 顺手修复、N2 回滚失败可观测性（增强非缺陷）观察不落债、N3 锁正则单引号盲区（基线既有）不落债
- **4.5 运行态冒烟**：smoke-simulators.mjs 真实运行 12 项 11 PASS/0 FAIL/1 SKIP 退出码 0（前端改动零后端影响）；冒烟后端口已释放
- **文档同步（本批次）**：TICKETS（TD-72/73/74 归档 + **技术债区清零 3→0 项**）；DEV_LOG 本段
- **测试**：Vitest **714**（基线 711，+3）；pytest 433+1skip / cargo 58 未受影响

---

## 滚动摘要（2026-08-14 — 技术债区 TD-48~71 余项批次：标准档 4 工单 2 波全自动 kickoff）

- **TD-48~71 余项批次完成（commit 链 dbcc15c → 9c70f13 → f068417 → bad8006，merge 链 bcd582c → 4fd123f → 78071e2 → 543f67a）**：技术债区剩余 17 项清理（用户指令「继续补技术债区」全自动档）——**13 做 + 4 关闭 + 0 票面修正**。工单 01 fetch seam 单源 + 15s 超时守卫 + seq 守卫（TD-51/55/60，新深模块 fetch-seam.js 消除双 seam 副本）/ 工单 02 运行中再点导航回列表 + file 百分号拒绝 + none 态设置链接（TD-53/56/71，冒烟新增步骤真实运行 PASS）/ 工单 03 导入回滚事务性 + pendingGameId 清理 + 文件名净化 + 存储降级 + 无原型累积器（TD-63/64/65/69/70，TD-63 裁定修法=回滚非容量预检）/ 工单 04 play 图标下架 + gamepad 一致性锁（TD-58/59，index.html 零修改）；关闭 4 票复核确认维持（TD-48 manifest v2 无 saveKeyPrefix / TD-49 四态已实现 / TD-52 空态正确 / TD-62 唯一调用点）
- **期末四轴 code-review（固定点 86c3991）：0 阻断放行**——Spec 13 票 + 4 关闭全达成；Falsify 0 击穿（波末增量审核 F1 超时不覆盖响应体读取 / F2 回滚双重失败遮蔽复核成立 → 落债 TD-72/73；AR-2 一致性锁钉死双副本 → 落债 TD-74；F3/ST-1/ST-2 维持现状）；Architecture 全正面（fetch-seam 消除 Duplicated Code）
- **4.5 运行态冒烟**：后端 GET / 200 + smoke-simulators.mjs 真实运行 12 项 11 PASS/0 FAIL/1 SKIP 退出码 0（含 TD-53 运行中再点导航步骤）；冒烟后端口已释放
- **文档同步（本批次）**：TICKETS（17 项→4 工单归档 + 4 关闭 + 3 新债 TD-72/73/74）；CONSENSUS §2（nav 再点语义收敛 + none 态设置链接两行决策）；DEV_LOG 本段
- **测试**：Vitest **711**（基线 690，+21）；pytest 433+1skip / cargo 58 未受影响

---

## 滚动摘要（2026-08-14 — 技术债区 TD-57/66/67/68 批次：3 工单小档全自动 kickoff）

- **TD-57/66/67/68 批次完成（commit 链 75d9d5c → 6665dff → 7d803d0，merge 1a7270b，非阻断修复 37a3b5e）**：技术债区 4 项中强度清理（用户点名全自动档）——TD-66 credentials model 门控盲区（setting.py 新增 `_OPENAI_PROTOCOL_MODELS` 由 AVAILABLE_MODELS 派生 + 门控收紧为「显式配置或解析值 ∈ 集」，先红后绿 4 用例；票面措辞修正：示例模型名以 .env 实际值 claude-sonnet-4-20250514 为准）/ TD-67+68 存档键契约单一来源（新建 frontend/js/save-key-meta.js 深模块三件套单源，五处消费点迁移含 smoke 脚本，vitest.config.js coverage.include 唯一共享改动；契约锁基线绿 6 用例）/ TD-57 同源 iframe 信任边界文档化（architecture.md 五要素小节 + CONSENSUS §2 两行 + 探索文档 U11 + key-injector 指针）
- **期末四轴 code-review：0 阻断放行**——Spec 三工单验收全达成；Falsify 0 击穿（TD-66 红态基线复现、TD-67/68 fuzz 5000 轮逐字节等价、markdown.js:109 同字符类判定不落债=语义域不同合并即伪单源）；Architecture 全正面；3 项非阻断随 37a3b5e 顺手修复（credentials docstring 新门控语义 / 派生 `p.get("models", [])` KeyError 防御 / save-key-meta 例外注记）
- **4.5 运行态冒烟**：后端 GET / 200 + credentials 端点 + smoke-simulators.mjs 真实运行 11 PASS/0 FAIL/1 SKIP 退出码 0（存档面板导出→清档→导入恢复路径）；冒烟后端口已释放
- **文档同步（本批次）**：TICKETS（TD-57/66/67/68 归档 + 技术债区 21→17 项待立项）；DEV_LOG 本段
- **测试**：pytest **433 + 1 skip**（基线 429+1skip，+4）；Vitest **690**（基线 683，+7）；cargo 58 未受影响

---

## 滚动摘要（2026-08-14 — U8+U9 模拟器二期批次：4 工单 2 波全自动 kickoff）

- **U8+U9 批次完成（merge 链 9aa6cfd → 3df82d8 → 455b308 → a918067 → 79598c2，波末修复 4a38400）**：模拟器二期 4 工单 2 波——波 1：U8-T1 只读凭证端点 GET /api/settings/credentials（openai 协议槽位解析、claude key 绝不回传，merge 9aa6cfd）+ U9-T1 manifest v2（22 游戏 saveKeys：精确键/正则锚定 + parseManifest 兼容，merge 3df82d8）；波 2：U8-T2「使用主应用 Key」一键注入按钮（merge 455b308）+ U9-T2 存档管理面板（列表/导出/导入/删除，merge a918067，人工仲裁 5 冲突块）；波末审核修复 F1/F2/F3（4a38400，merge 79598c2——select 注入匹配校验 + smoke 步骤间视图恢复 + 冒烟阻塞点）
- **期末四轴 code-review：0 阻断**；9 项非阻断观察落技术债区（TD-63~71 待立项，技术债区累计 21 项 TD-48~71）
- **4.5 运行态冒烟**：模拟器冒烟 11 PASS/1 SKIP + 桌面 WebView2 CDP 4 PASS
- **文档同步（本批次）**：TICKETS（U8+U9 归档 + TD-63~71 落区）；CLAUDE.md / PROJECT_REFERENCE.md（pytest 413→429+1skip / Vitest 551→683 + 状态更新）；README / docs/architecture.md（注入与存档管理入册）；docs/api-design.md（credentials 端点）；docs/world-simulation-exploration.md（U8/U9 标已完成）
- **测试**：pytest **429 + 1 skip**（+16）；Vitest **683**（+132）；cargo 58 未受影响

---

## 滚动摘要（2026-08-14 — U7 模拟器模块批次：5 工单标准档 3 波全自动 kickoff）

- **U7 批次完成（merge 链 37affb8 → 48e6e6c → 3ab60e6 → e4b6129 → 7e5ea15）**：模拟器模块正式落地（2026-08-13 原型验证 → 2026-08-14 正式立项，来源 docs/world-simulation-exploration.md U7 未决事项）。标准档 3 波——波 1：T1 模拟器入口（侧栏/移动端导航按钮 + view-simulators 骨架 + gamepad/play 图标，零接线切换，merge 37affb8）+ T2 22 款模拟器全量入包 + manifest v1 元数据补全（数据工单，merge 48e6e6c）；波 2：T3 列表页（manifest 解析 + 卡片网格 + 类型筛选 + 四态，8d7a52a）+ T4 运行视图（iframe 状态机 + AI 提示条 + 返回，7b81172），merge 3ab60e6；波 2 审核 2 修复（8d266f9，merge e4b6129）——**属性注入面关闭**（data-id/title 走 DOM 通道）+ **iframe load 竞态守卫**；波 3：T5 端到端冒烟脚本（Playwright，72af4f4，merge 7e5ea15）
- **数据判定**：manifest 22/22 全 ai（实测无 local 条目——「纯本地」筛选档为空态属现状张力，落 TD-52）
- **期末四轴 code-review：0 阻断**；12 项非阻断观察落技术债区（TD-48~62 待立项，TD-50 复核关闭，见 TICKETS 技术债区）
- **4.5 运行态冒烟**：网页端模拟器冒烟 7 PASS/1 SKIP（SKIP：manifest 无 local 条目 → 纯本地路径按设计跳过并报偏离说明）+ 桌面 WebView2 CDP 5 PASS
- **文档同步（本批次）**：TICKETS（U7 归档 + TD-48~62 落区）；CLAUDE.md / PROJECT_REFERENCE.md（Vitest 466→551 + 状态更新）；README / docs/architecture.md（模拟器模块入册）；docs/world-simulation-exploration.md（U7 未决事项标已完成）；DEV_LOG 本段 + 首次滚动摘要折叠
- **测试**：Vitest **551**（+85）；pytest 413+1skip / cargo 58 未受影响

---

## 滚动摘要（2026-08-14 — DEV_LOG 滚动摘要折叠规则确立）

- **规则确立（用户确认 N=12）**：滚动摘要窗口上限 12 条，超限在文档同步时把最旧一批折叠为一条「阶段摘要」（日期范围 + 每批次一行，置于日志正文顶部），窗口回落 6~8 条；不拆 docs/——避坑已蒸馏 persona/经验笔记、批次细节 git log 可溯。落点：CLAUDE.md「待办管理」+ DEV_LOG 头注
- **已执行**：2026-08-14 文档同步完成首次折叠（最旧 15 批 → 阶段摘要，见日志正文顶部；摘要区回落至 7 条，含本段与 U7 批次）

---

## 滚动摘要（2026-08-14 — 模拟器集成最小原型验证（prototype skill））

- **背景（用户原始想法澄清）**：用户最初想法 = 新加独立于角色对话的「模拟器」模块，集成下载的 22 个成熟单文件 HTML 模拟器（`C:\Users\Administrator\Downloads\最新版本游戏本体\`）供选择使用——与 D2「大世界/世界书」是并行方向（U1 已澄清）
- **原型验证（网页版 + Tauri 桌面版全链路跑通）**：静态托管（游戏 HTML + manifest.json 放 `frontend/simulators/`，被根静态挂载 main.py:64 覆盖，**后端零改动**）+ 原型页（列表 + iframe 容器 + 验证状态面板）+ 同源 DOM 直读/localStorage 读写（游戏存档可用）+ AI 配置面板控件探测（`*-endpoint/apikey/model` 模式）；桌面版经 tauri dev + WebView2 CDP（playwright-core connectOverCDP）自动化重跑全过——boot.html → 动态端口后端 → 同一套静态托管，**WebView2 无 CSP 拦截**
- **实测坑（正式开发注意）**：CONVER_BACKEND_CMD 路径含空格须双引号包裹（`set "VAR="D:\...\python.exe" -m ..."`，cmd set 保留内部引号；`\"` 是字面量 → parse_command_line 坏路径 os error 2）；dev 模式壳 cwd=src-tauri 须 CONVER_BACKEND_CWD 指仓库根 + python 解析到 venv；壳用动态端口拉起后端；`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` 开 WebView2 CDP 调试口；MSYS_NO_PATHCONV=1 会禁用 `//c` 转换（cmd 进交互模式）
- **发现**：人生模拟器v3 实测为 AI 驱动（内置 deepseek 配置面板，非纯本地）；22 个游戏 ≈ 半数 AI 驱动（游戏内自填 key）+ 半数纯本地（localStorage 前缀存档）
- **归档**：探索文档 `docs/world-simulation-exploration.md` §4.5 + D7 + U7-U10；原型产物提交 throwaway 分支 `prototype/simulators-integration`（主分支不含）
- **无正式代码改动、无待办录入**（原型验证非工单；正式模块立项待用户决定）

## 滚动摘要（2026-08-13 — 阶段摘要：方向探讨 + 打包流程 + TD-46/47）

> 折叠说明：2026-08-15 按滚动摘要折叠规则执行（超 12 条上限）——最旧 4 批折叠为一条阶段摘要。

- **大版本方向探讨：世界模拟扩展 · 存档待续**（非工单，用户要求存档后续续谈）：角色对话→世界模拟平台首轮探讨，用户拍板 6 项决策（D1-D6）；存档 `docs/world-simulation-exploration.md`（未决事项 U1-U6）；无代码改动
- **打包流程：dist 测试包步骤固化**（用户要求，非工单）：build-desktop.ps1 固化 dist 测试包步骤（release 壳复制到 `dist\conver-system.exe`，`-SkipTests -SkipSmoke -SkipBackendBuild` 端到端两跑）；R5 容错实测（占用时 IOException 不中断构建）
- **TD-46 markdown 还原性能**（merge 868dd32）：占位符还原 O(K·N)→O(N) 优化；Vitest 460→463
- **TD-47 占位符碰撞作用域扩展**（merge ffe185a）：碰撞循环 3 形态检查；Vitest 463→466，技术债区清零

---

## 日志正文

### 阶段摘要（2026-08-10 ~ 2026-08-13）

> 折叠说明：2026-08-14 文档同步按 [CLAUDE.md](CLAUDE.md)「待办管理」滚动摘要折叠规则执行（摘要区超 12 条上限）——最旧 15 批折叠为一条阶段摘要；逐批次明细 git log 可溯。

- **2026-08-10** | 架构深化 8 候选 + P6.5 多 tab 会话管理（独立 worktree `.worktrees/p65-tabs`）
- **2026-08-11** | OPT-1 UI 克制化与图标协议收口（icons.js seam + emoji 清除 + 主题 token 单源）
- **2026-08-11** | P6.4 Tauri 桌面版波次收官（8 工单归档，merge 链 3823e76/97a2923/635104b/87ab288/a881d95）
- **2026-08-12** | ARC-9 架构深化批次：6 Strong 候选（T-01~T-06，merge 链 4e48750/dcff674 + 修复 2430bc6/d3a833b）
- **2026-08-12** | ARC-10 架构深化批次：剩余 8 候选（T-11~T-18，merge 链 4ffc1d2/241a7b6）
- **2026-08-12** | 技术债区批次：16 项遗留清零（6 工单归档，merge 链 bd0eb81/ed7a3ac）
- **2026-08-12** | TD-1~7 批次：7 项清零（merge 链 053f949/3cae11d）
- **2026-08-12** | TD-8~12 批次：3 做 + 2 维持关闭（merge a12d48e）
- **2026-08-12** | TD-13~14 批次：2 做 + TD-9 闭环（merge 61f1721）
- **2026-08-12** | TD-15~24 批次：10 项全做清零（merge 0010f1b）
- **2026-08-13** | TD-25~27 批次：1 做 + 2 维持关闭（merge 8ae3801）
- **2026-08-13** | td-arch-health 批次：8 工单 3 波（merge 链 b4b0a31→48447e6）
- **2026-08-13** | TD-28 批次：sanitizeUrl 控制字符绕过修复（merge 890aa97）
- **2026-08-13** | TD-42 批次：链接属性注入面修复（merge a6fba3b）
- **2026-08-13** | TD-29~41/43~45 批次：17 项标准档（11 做 + 5 关闭 + 1 票面修正，merge 链 b835210/615aba8/a5fe7b9 + cef3fea + 342382e + 960c9c4/93b51ab/649910c/d96b4ce + 归档 de09509）

---

### 2026-08-11 | 修复 | P6.4-6 期末审核阻断 1：壳 prod 模式定位随包后端 + 干净环境冒烟

- **阻断**：`DEFAULT_DEV_BACKEND_CMD`（python uvicorn）经 lib.rs 无条件使用 + tauri.conf.json 无 resources → 干净用户机（无 python）安装后双击必然 spawn 失败；此前冒烟 `-UseInstaller` 全绿是因为冒烟自己注入了 CONVER_BACKEND_CMD（真实用户路径无此通道）→ US-1 不成立
- **修复**：① `tauri.conf.json` `bundle.resources: ["../dist/conver_backend"]`（PyInstaller onedir 产物随安装器分发——安装器 2.2MB → 24MB）；② `server.rs::backend_config_from_env(dev_mode, resource_dir)` 选择分支——CONVER_BACKEND_CMD 覆盖 > **生产态（release 构建）随包 exe**（候选探测 `prod_backend_exe_candidates`：**实测 Tauri Windows 把 resources 置于安装目录 `_up_` 子目录且保留相对路径结构** → `_up_/dist/conver_backend/conver_backend.exe`，平铺 `conver_backend/` 布局兜底；`find_prod_backend_exe` 找第一个存在的文件，全无则回退开发态命令）> 开发态 python 命令；`dev_mode` 由 lib.rs 注入 `cfg!(debug_assertions)`，两个分支均可单测；③ lib.rs setup 经 `app.path().resource_dir()` 传入
- **防复发回归**：① cargo test +3（候选顺序断言；`_up_`/平铺/无布局三分支探测断言；env 变体断言并入单测试函数——**跨测试并行修改 CONVER_BACKEND_CMD 会互踩**，与既有惯例一致）；② 冒烟新增**干净环境用例**：`-UseInstaller` 且不注入 CONVER_BACKEND_CMD 启动已安装应用 → 壳 prod 随包定位 → ready + /api/models 200（`-BackendEnv` 可显式注入）；③ 冒烟新增 `GET /` 200 + `<title>Conver System` 标记断言（阻断 2 冒烟部分，依赖 PyInstaller datas 随包前端，另一 agent 修复合并前预期 FAIL；已在 `_internal/frontend` 模拟 datas 分发实证断言变 PASS）
- **验证**：cargo test 43 全绿（28+7+8）；pytest 259+1skip / Vitest 186 基线保持；tauri build 重构建（增量 31s，安装器含后端资源 24MB）；干净安装冒烟 ready+200 实证 + GET / 标记 PASS（模拟分发）；安装目录 `%LOCALAPPDATA%\Conver System\_up_\dist\conver_backend\conver_backend.exe` 确认

### 2026-08-11 | 实现 | P6.4-6 安装器 + 一键构建冒烟 + 文档归档（波 3 收官）

- **NSIS 配置**（tauri.conf.json）：`bundle.active: true` + `targets: ["nsis"]` + `bundle.windows.nsis`（`installMode: currentUser`；实测安装到 **`%LOCALAPPDATA%\Conver System\`**——tauri 2.11 NSIS 模板路径，非 `Programs\` 子目录；`languages: ["SimpChinese", "English"]`；卸载不动 %APPDATA% 数据——数据在安装目录之外，数据分离铁律已实证：静默卸载后 `%APPDATA%\ConverSystem` 完好）
- **build-desktop.ps1**：cargo test（src-tauri，41 用例）→ pytest（.venv，259+1skip）→ vitest（frontend，186）→ tauri build（NSIS）→ 冒烟（-SkipSmoke 可关）；tauri CLI 经 `frontend/node_modules/.bin/tauri`（只搜 cwd 及子目录，从仓库根调）；**R4**：build 失败自动重试 1 次 → 仍失败回退 `--no-bundle` 验证编译并记录；后端 exe 缺失自动调 build-backend.ps1 补齐；脚本头注释 Git Bash link.exe 遮蔽警告（必须在 cmd/PowerShell 运行）
- **smoke-desktop.ps1**（Seam 2，验收 1-7）：环境变量通道 `CONVER_BACKEND_CMD` 指向打包后端 exe + `CONVER_EXIT_AFTER_SECS` 钩子优雅退出；轮询 runtime.json（容忍解析失败重试，**启动前删除陈旧 runtime.json 防假阳性**）；`GET /api/models` 200；DB 存在 + `GET /api/characters`（首启断言 `[]`，既有数据降级验结构并告警）；退出后**查端口释放而非 pid**（P6.4-1 遗留：venv python 重定向器孙进程）+ 无 conver_backend.exe/uvicorn 残留；异常路径 finally 兜底 force-kill + 按端口清后端；**守卫：数据目录落在项目根内直接拒绝**（绝不触碰项目根 DB）；`-UseInstaller` 静默安装路径 / `-RunMigrationCheck` 验收 7 轻量复跑 / `-CleanAppData` 显式清理
- **真实运行验证**：完整跑通 build-desktop.ps1 等价命令链（cargo test / pytest / vitest / tauri build）+ smoke-desktop.ps1 全过；安装器产物路径/大小记录
- **清理**：删除 frontend/conver_system.db 残留（36KB，SQLite 格式，无任何代码引用，.gitignore 已兜底；删除前确认无 SQLite 独占打开——网页版服务 8000 端口与项目根 DB 均未受影响）
- **避坑**：① worktree 无 node_modules/.venv → node_modules 用 Junction 指向 p64-1（PS `New-Item -ItemType Junction`），.venv 直接调用主仓库绝对路径；② PowerShell 5.1 无 `??`/三元表达式，脚本须 PS 5.1 兼容；③ `Stop-Process` 是 TerminateProcess，不会走 Rust Drop/Exit 清理——**退出应用必须走壳的 CONVER_EXIT_AFTER_SECS 钩子**，force-kill 只作异常兜底；④ 残留检查查端口（TcpClient BeginConnect 探测）而非进程 pid

### 2026-08-11 | 验证+修复 | OPT-1 GUI 黑盒回归（375px / 侧栏折叠 / 多 tab 流式）+ 错误气泡 CSS 回归修复

- **流程**：IAB webview 本会话未就绪（browser guest not attached 连续 4 次）→ 切换 Playwright MCP 通道（上会话既有通道）；验证方法采用**本地 mock SSE**（一次性 `page.route` 网络层拦截 `/api/chats/stream` → `mock-stream` 慢速 token / `mock-error` HTTP 422 / `mock-stream-error` 流中 error 帧三端点），**未触发真实外部 API**（安全项约束）
- **T1 375px**：`docScrollWidth==clientWidth==375`，全元素扫描无横向溢出；底部 5 图标导航 + 对话列表默认收起 + 空态 + 单列角色卡片（vision 核验 SVG 线条图标、长文本省略号截断、头像字母完整无裁剪）
- **T2 主导航侧栏折叠/展开**：折叠 `aside` 208→0px（几何 + 按钮变「展开侧栏」+ 浮动展开按钮）、展开回 208px 主区 721px 还原；全程无横向滚动无重叠
- **T3 多 tab 流式回归（mock SSE）**：① 复制反馈 `clipboard→check(+copied)→1.5s 还原`，连点无残留；② 流式停止：按钮 stop↔send 两态 + tab 脉冲点 + 部分内容保留 +「（已停止）」+ tab-warn warning 图标；③ 后台流式：流式中开第二会话后台 tab 保持脉冲点、活动 tab 按钮 send、切回内容完整累积；④ 错误路径：HTTP 422（错误气泡 + 按钮还原）+ 流中 error 帧（error 气泡稳定 6 采样无重载，streamSettled 守卫生效）
- **❌ 回归实锤 + 修复（OPT-1-FIX）**：CSS 顶层新增 `.message.assistant .message-content`（`background:transparent;border:none`，style.css:2945）位于 `.message.message-error`（:922）之后，同特异性 (0,3,0) 覆盖错误气泡警示样式（`git show 63542ca` 对比确认 OPT-1 新增该规则；计算样式 + CSSOM 双证）。修复：错误规则改 `.message.assistant.message-error .message-content` 特异性 (0,4,0)，浅色/深色 GUI 复验均恢复 danger 底色/红边/警示色（vision 确认）
- **浏览器缓存避坑**：浏览器加载到旧版 style.css（含已删 `4px 0px` 顶层规则）导致桌面误判错误样式丢失 → `page.route` 强制 no-cache 重取后按真实文件复验；初判「内容重置」为 mock 服务器 URL 分支 bug（`/mock-stream-error`.startsWith(`/mock-stream`) 命中慢速分支）非产品缺陷
- **测试**：Vitest **186** 全绿（CSS 修复无回归）；pytest **188** 不变；截图存 `gui-test-screenshots/`（t1_375px、t2_before/collapsed/expanded、t3_copy_check、t3_streaming、t3_error、t3_multitab_background、t3_stream_error_frame、t3_error_fixed_light）

### 2026-08-11 | 实现 | OPT-1 UI 克制化与图标协议收口（进行中，未 commit）

- **图标 seam**：新增 `frontend/js/icons.js`（协议表面 `iconHtml(name, options)`，`__all__` 声明为仓库协议元数据）；26 个注册图标（currentColor 线框 / data-icon / aria-hidden / viewBox 16）；评审后入口收口：`Object.hasOwn` 查注册表（防原型链 `constructor`/`__proto__`）、`size` 1–128 有限数字、`className` CSS 标识符白名单（防属性注入），全部非法输入显式抛错
- **emoji 清除范围**：动态模板/状态（复制/温度/对话数/删除/搜索角色与会话标识/头像）→ SVG；复制反馈 `clipboard/check/x`；发送/停止 `send/stop`（活动 tab `isStreaming` 单一来源不变）；tab 关闭/警示 `x/warning`；模态框/确认框 `x/warning/info`；导出 `fileText/fileJson`；向导模式/章节/模板/解析状态全 SVG；主题 `sun/moon`、侧栏 `chevronLeft/Right`；指南页标题与操作说明去除 emoji 并改真实按钮名；`model-utils` 自定义模型选项与 `model-selector` 提示改纯文字。用户消息/角色设定中的 emoji 保留（有测试）
- **行为契约**：`EMPTY_STATE_HTML`、DOM ID、事件委托 class、多 tab/防悬挂/流式结算、`data-streaming-live`、tab phase 全部保持；jsdom 集成 68 项含新语义断言全绿
- **复制反馈竞态修复（评审实锤）**：每按钮独立恢复定时器（`WeakMap`），失败立即取消旧恢复并保持 `x`，防“先成功再失败被旧定时器覆盖”
- **CSS 收口**：主题 token 单一来源（删除文件尾两套覆盖补丁，浅色仅系统+强制两处）；修复 `--panel-1`/`--radius-md`/`--accent-contrast` 未定义；深色/浅色收敛 Warm Stone 低饱和；负字距清零；`color-mix` 仅用于 surface 混合；`:focus-visible`/reduced-motion/hover 精细指针
- **评审**：四轴 code-review（固定点 HEAD）实锤 3 条已修（图标注入、复制竞态、token 双源）+ 测试数同步；低优先建议（`__all__` 属协议元数据、DEV_LOG 同步）已处理
- **GUI 黑盒（Playwright）**：桌面深浅主题、角色卡、向导 1-6 步（含用户 emoji 保留）、清空确认框取消、设置分组、768px 底部导航；375px 与主导航侧栏折叠被 IAB 运行时截图/点击超时阻断，**标记未验证**
- **测试**：Vitest 183 → **186**；pytest **188** 不变；`git diff --check` 干净
- **避坑**：① IAB 截图超时后同 tab 后续截图持续失败 → 关 tab 重建；② `getByRole` 名称不唯一时先查 DOM 快照再收缩作用域，不得 force；③ GUI DOM 输出会暴露本地库中的真实 API Key，设置页只验证结构不截图/不复述

### 2026-08-10 | 实现 | 架构深化 8 候选（improve-codebase-architecture 全自动 kickoff，merge 链 83bb9bf/3af9b61/1f2fdcc）

- **流程**：Explore 扫描产出 8 候选（2 Strong/4 Worth/2 Speculative）→ 用户授权全自动 → Grilling/plan-tickets 子智能体多次空返回 → 主会话降级自调研设计 + 拆票（spec + 8 工单）→ 两波并行（每波 4 worktree 文件互斥）→ 期末三轴 code-review 放行 + 修复
- **波 1**（ARC-1/2/3/4）：StreamSession 流式回合结算深模块（createStreamSession + mergeFreshList 三分支：fresh 整体替换/stale 位置结算/失败 anchor 写回；anchor = 本流 user 消息对象引用——索引会漂移但引用永不移位，根治 R2 并发流占位清除）；closeTabs + closeConversationsAndResettle 级联收口（仅 wasActive 重激活）；标题策略收口 conversation.py；requestBlob + 超时（关 R1）
- **波 2**（ARC-5/6/7/8）：getTabDisplay 展示契约（关 R3）；app.js 拆分（format.js 模板纯函数 + conversation-activation.js 激活编排深模块，setActivationHooks 注入）；resolveCredentialTarget 纯函数；services/schemas __init__ 导出
- **期末审核 findings**：Falsify 实锤 1 条——stale 失配 no-op 导致前流最终消息缓存丢失（非回归、双故障边缘）→ 修复：stale 守卫失败回退 settleByPosition（幂等保证不重复），FIX-A 测试断言同步适配；Standards 2 条（app.js 死导入清理、settings-panel 补 __all__）一并修；Spec 1 条（ARC-6 签名漂移为良性，功能等价）
- **测试**：Vitest 91 → **177**（+86：stream-session 41/conversation-activation 12/format 模板 7/tabs 联动 10/api 9/settings 5/恢复等）；pytest 181 → **188**（ARC-3 +5、ARC-8 +2）
- **覆盖率**：stream-session 100/97.9（stmts/branch）、conversation-activation 100/79.4、tabs 99.46
- **避坑**：① 子智能体「空返回」= 可能实际执行了（核验 worktree 后补 commit）或完全没干（重派），不可假设；② worktree 缺 node_modules → PowerShell `New-Item -ItemType Junction`（cmd mklink 的 `\D:` 前导反斜杠会指向错误位置）；③ vitest 缓存损坏（.vite-temp）时删除后重跑

### 2026-08-10 | 修复+验证 | P6.5 遗留修复（FIX-A/B/C）+ VERIFY-D 黑盒验证

- **FIX-A**（`6e0489a`）：finalizeStream settle 改按消息位置匹配（settleIndex = 发起时刻尾消息位置，幂等：该位置仍 streaming 才结算），替代 `m.content === fullContent` 内容等值匹配——两连发回复字节相同时不再误结算新流消息；+1 复现测试
- **FIX-B**（`2f26a85`）：非流式在途守卫 `nonStreamingInFlight` Set（per-tab 作用域）——Enter/按钮双击只发一次真实请求；守卫在清空输入之前（草稿保留）、finally 双路径清除、流式提交不受影响；+6 用例
- **FIX-C**（`b16c097`）：通知分类节流——tabs.js `DISPLAY_KEYS=['title','phase']`，updateTab 仅 patch 含展示字段才 notifyChanged；结构性变更（open/close/activate/restore）仍走 commit() 通知；onToken 逐 token 的 messages patch 不再触发 tab 条全量 innerHTML 重建；tab-bar.js 无需改动（唯一订阅方）；用例同步更新
- **误删测试恢复**（`acb144d`）：核验发现 b16c097 误删「流式 error 帧 → handleStreamError 错误分支」Falsify 测试（无等价替代），恢复（+1 用例）；该测试同时隐式覆盖 streamSettled 守卫（error 帧后流关闭补发 onDone(null) 若守卫失效 phase 被改 done 断言即失败）；同 commit 固化 @vitest/coverage-v8
- **VERIFY-D 黑盒验证**（Playwright MCP + mock SSE 注入）：① 双流并发——tab A 流式中切 tab B 再发，两 tab 同时 dot=true、活动 tab ⏹、后台流继续累积、完成后 dot 消失按钮复位 ➤；② 生成中脉冲点 .tab-dot 渲染正常（FIX-C 后 phase 通知仍工作）；③ <768px——tab 条 display:none、tab 状态保留 DOM、侧栏切换会话正常加载；④ 全程无 JS 错误（mock 注入失误导致的递归已排查，非产品缺陷）
- **轻量复审**（固定点 a252158）：可放行。Falsify 2 非阻断——P1 非流式无 fetch 超时（请求永不 settle 时发送无限期阻塞，罕见）；P3 FIX-A 失败路径洞（list 失败 catch 的 filter(!streaming) 清并发流占位，改动前既有行为）；Standards 3 非阻断（DISPLAY_KEYS 与 tab-bar render 隐式耦合最重）→ 录入 TICKETS P6.5-R1~R3
- **测试**：Vitest 85 → **91**（+6：FIX-B 6 用例含恢复 1 的净增——FIX-A +1、FIX-B +6、恢复 +1、FIX-C 净 -2）；pytest 181 不变；后端零改动

### 2026-08-10 | 修复 | P6.5 code-review 三轴审核修复（commit 链 1b64b9f → 1332b1c）

- **F-1 阻断**：`finalizeStream`（chat.js）消息重载在途时用户连发新消息——旧 `messages.list` 响应返回后 `updateTab` 全量替换，新 user 消息从缓存+DOM 消失（`isActiveStream` 同 tab 为 true 还把陈旧快照渲染上屏）。修复：list 前捕获缓存 revision（messages.length），返回后仅当当前长度 === revision 才整体替换；refreshSendButton 提前到 done 写回后（消除 ⏹→发送 UX 窗口）。复现测试 2（流式/非流式）+ Falsify 对抗（空 fullContent no-op、tab 已关 revision=0、多连发 interleaving 只结算本流）
- **F-2 阻断**：`activateConversation` 的 `await conversations.get`（仅会话不在已加载列表时命中）期间切走/关闭 tab → 续体无条件执行：关闭时 `restoreTabViewState(undefined)` TypeError；未关但已非活动则 DOM 显示 A、activeId 是 B（发送以 B 身份发 A 草稿）。修复：双 await 后活动校验 + restoreTabViewState undefined 防御 + 缓存分支渲染前活动校验。复现测试 2 + get 404+关 tab 对抗
- **低成本项**（refactor `999e7e5`）：abort 流式三连（停止按钮/✕/删会话）收进 tabs.js 协议 `abortStream(convId)`；清空所有对话补 abort 遍历（与删会话路径一致）；删角色级联删会话补 closeTab（决策 6 语义完整）；删会话前 `saveActiveTabViewState` 无效写移除（写入即将销毁的 tab 缓存）；空态 HTML 双份 → chat.js 导出 `EMPTY_STATE_HTML` 共享；`chat.js:95` stale 注释修正
- **文档**：TICKETS P6.5-1 归档用例数 27→32；spec.md 同步「Playwright GUI 回归 → jsdom 集成冒烟（不提交）+ <768px 人工核验」声明
- **复审**（705d62f..82f5bb6）：F-1/F-2 已关闭、低成本项无回归、非阻断 4 项按指示保留；Falsify 新构造 8 项全部安全；唯一新发现 = 同内容双流误结算边缘（settle 按 `m.content === fullContent` 匹配，两连发字节相同时可能误结算，被新流 replace 自愈，概率极低）→ 建议后续 settle 改按消息位置匹配
- **测试**：Vitest 69 → **85**（+16 复现/对抗）；pytest 181 不变；覆盖率 tabs.js 99.33/97.18（stmts/branch）

### 2026-08-10 | 实现 | P6.5 多 tab 会话管理（5 票串行链）

- **P6.5-1** `frontend/js/tabs.js` 纯逻辑深模块（零 DOM，jsdom 可测）：tab 集 + 每 tab 会话级状态（消息缓存/草稿/滚动/流式阶段/流式句柄）；结构性变更写 sessionStorage（只存 ids+activeId）并通知，updateTab 内容更新仅通知不写盘（避免逐 token 写存储）；`updateTab` 对不存在 id 幂等 no-op（关流式中的 tab 后异步写回兜底）；restore 经 isValidId 过滤失效 id，activeId 失效回退首个
- **P6.5-2** state.js 退役 5 个会话级字段（currentConversationId/currentCharacterId/messages/isStreaming/activeStream），只留全局配置；三入口（侧栏点击/角色开始对话/搜索跳转）收敛为 app.js 单一激活流程 `activateConversation`（openTab 去重 + 补全 title/characterId + 懒加载消息 + 草稿/滚动保存恢复 + 刷新发送按钮两态 + 列表高亮）；发送按钮状态 = 活动 tab isStreaming 单一来源
- **P6.5-3** tab 条 presentational 组件：订阅 onTabsChanged 重渲染；点击激活经 app.js 注入处理器（复用 setConversationsRefresher 式注入模式）；✕ 直接 closeTab（先 abort 流式）；thinking/streaming 脉冲点、error 警示标记、done 无提示；<768px 媒体查询隐藏（行为不变）
- **P6.5-4** `restoreFromStorage` 集成辅助 + init 恢复时序（conversations 加载后恢复、过滤已删会话、恢复非流式、激活懒加载）；双击重命名与首条消息自动标题（syncChatHeaderTitle）两条路径同步 tab 标题
- **防悬挂细节**：停止（AbortError）写回 phase 'error'（警示标记）且气泡保持「已停止」语义；正常完成 phase 'done'；非流式完成同样写回发起 tab 缓存
- **冒烟**：`frontend/smoke-integration.mjs`（jsdom 黑盒，不提交）覆盖双 tab 草稿/滚动互切、后台流完成写回发起 tab、停止/错误、关 tab/删会话/清空三联动、F5 恢复（含已删过滤/非流式）、tab 条交互、重命名联动，81 项全过
- **环境备注**：pytest 需 `pytest-asyncio`（requirements-dev.txt 未列，属既有遗漏）；后端零改动

---

## 滚动摘要（2026-08-09）

- **GUI 全功能验证**：Playwright 黑盒测试（角色/向导/对话/搜索/导出/设置/手册/响应式）+ vision 模型视觉核验，发现 4 个 bug 全部修复
- **BUG-2 停止内容未落库**：`stream_reply` 增加 finally 兜底保存（GeneratorExit/CancelledError 是 Starlette 取消 SSE 生成器的真实路径，原 except 捕获不到）+ saved 防重标志；+1 复现测试（aclose 模拟）
- **BUG-3 JSON 导出 500**：Content-Disposition 中文文件名 latin-1 编码失败 → RFC 5987（filename ASCII 兜底 + filename*=UTF-8''）；+2 复现测试
- **BUG-1 badge 显示错误**：`providerDisplayName()` 纯函数（model_data key→name 映射）替代硬编码 `'openai' ? 'OpenAI' : 'Claude'`；+5 vitest 用例
- **BUG-4 移动端 480px 错乱**：对话列表默认收起（display:none + .mobile-expanded 类），☰/toggleConvList 统一走类切换，.chat-messages min-height:0 防撑高，隐藏冗余「收起侧栏」按钮，删除 convListVisible 死代码
- **观察项 ①-④ 修复**（子代理并行）：① greeting 首轮显示（chat.js 发送完成后重载消息列表）；② 错误气泡红字红框（--danger 变量 + .message-error 类，深浅主题）；③ MD 导出 {{char}}/{{user}} 替换（复用 apply_template_vars，JSON/角色卡保留原始设定）；④ 角色卡片 4 按钮 emoji→SVG（作用域 CSS 16px）
- **导入路径错误引导（IMP-1）**：角色卡导入失败时，后端 422 错误消息附带支持格式说明（V2/data 信封/裸 data/V1 + 向导指引）；前端失败后弹「是否改用创建向导？」确认框；+3 路由层测试
- **测试**：pytest **181**（+6）+ 前端 Vitest **37**，全部通过

---

## 日志正文

### 2026-08-10 | 预检 | P6.5 多 tab 会话管理开工预检
- **知识库召回**：persona 已读（CLI 优先 / Vanilla JS / 深模块 / 评审驱动）；精读 3 条——SSE 流式前端状态陷阱、前端模块化拆分中的循环依赖处理、Conver System 高频小坑汇总；摘要带入——无框架前端 fetch seam、worktree 膨胀/CRLF 教训；守卫反查通过（无缺 summary）
- **preflight**：基线 d228fa8、worktree 可用、main 分支、pytest + Vitest 双框架齐备

### 2026-08-09 | 修复 | 导入路径错误引导（IMP-1）
- **背景**：GUI 验证时发现角色卡导入失败只有原因提示（如「无法识别的角色卡格式」），无修正引导；LLM 解析路径已有「请重试或手动创建」指引，导入路径引导程度不一致
- **后端**（`api/routes/characters.py`）：`_IMPORT_FORMAT_HINT` 常量（支持格式：V2 spec=chara_card_v2 / data 信封 / 裸 data（name）/ V1 旧卡（char_name）+ 向导指引）；`CardFormatError` 的 422 detail 追加说明；`CardValidationError`（名称空）保持纯原因（内容问题与格式无关）
- **前端**（`app.js`）：`promptUseWizardAfterImportFail()` 引导函数——失败后弹 showConfirm「是否改用创建向导？（智能导入/模板/手动）」→ 确认则 `showCharacterWizard()`；JSON 解析失败与后端 422 两条路径均触发
- **测试**：+3 路由层测试（格式错误含说明 / 不支持 spec 含说明 / 校验错误不含说明）
- **GUI 回归**：导入 `{"foo":"bar"}` → 后端 detail 完整（含格式说明与向导指引）→ 引导弹窗 →「打开向导」→ 向导第 1 步正常打开
- **测试**：pytest **181 passed**（+3）；Vitest 37 不变


### 2026-08-09 | 修复 | 观察项 ①-④（子代理并行 + GUI 回归）

- **① greeting 首轮显示**（代理 A）：`chat.js::handleSend` 流式 onDone 与非流式完成路径改为 `messages.list` 重载 + `renderMessages()`（失败退化本地 push），停止路径保持现状（保留「已停止」标记）。GUI 验证：Testbot 空对话首条消息后立即显示 greeting「1」+ 用户消息 + LLM 回复
- **② 错误气泡样式**（代理 A）：错误气泡加 `.message-error` 类；CSS 变量 `--danger-bg/--danger-text`（深色半透明暗红底，浅色 #fdf0ef 底 + #c0392b 字）+ 红边框。GUI 验证：无效 key 触发错误气泡显示红字红框，与正常气泡明显区分
- **③ MD 导出模板变量**（代理 B，TDD）：`conversation_export.py::export_conversation_markdown` 对 description/personality/scenario 调用 `apply_template_vars`（`char_name` 参数，user_name 一次读取）；JSON 导出与角色卡导出保留原始设定（防回归测试标注有意行为）。复现测试 2 failed→修复后全量 178 通过。GUI 验证：导出 MD 中 `{{char}}` 已替换为角色名
- **④ 卡片按钮 SVG**（代理 A）：`app.js::renderCharacters` 4 个操作按钮 emoji→inline SVG（气泡/铅笔/导出/垃圾桶，stroke currentColor 风格）；`.character-card-actions .btn-icon svg` 作用域 16px 规则（避免影响其他按钮）。GUI 验证：卡片按钮单色线条图标与导航统一
- **经验**：子代理修改后端代码后必须重启 uvicorn（无 --reload）才生效——首次 MD 导出验证因服务未重启误报失败


### 2026-08-09 | 修复 | GUI 全功能验证发现的 4 个 bug（复现测试先行）

- **背景**：Playwright 黑盒测试 + vision 模型逐图核验（当前模型不支持直接读图），覆盖 P0 主流程/P1 交互/P2 输入边界/P3 响应式
- **BUG-2**（停止内容未落库）：`services/chat.py::stream_reply` 原有 is_disconnected 轮询与 ClientDisconnect 两条保存路径，但前端 abort 时 Starlette 取消 async generator 抛 GeneratorExit（BaseException），`except Exception` 捕获不到 → 竞态丢失。修复：`finally` 兜底保存 + `saved` 标志防重复；`logger.exception` 兜底失败日志。复现测试 `test_stream_generator_exit_saves_partial`（aclose 模拟取消）
- **BUG-3**（JSON 导出 500）：`api/routes/conversations.py` 导出 header 的 `filename` 含中文角色名 → latin-1 编码失败。修复：RFC 5987 `filename`（ASCII）+ `filename*=UTF-8''`（urlencode）；浏览器优先中文名，兼容不支持 filename* 的客户端
- **BUG-1**（badge 显示 Claude）：`app.js` 硬编码 `model_provider === 'openai' ? 'OpenAI' : 'Claude'`，deepseek 被误显示。修复：`utils.js::providerDisplayName()` 从 `/api/models` providers 元数据解析 key→name，未匹配回退原始 key
- **BUG-4**（480px 布局错乱）：768px 断点下对话列表默认展开占 35vh 并挤压聊天区。修复：CSS 默认 `display:none` + `.mobile-expanded` 展开类；`.chat-messages { min-height: 0 }`；`btn-collapse-chat` 移动端隐藏；JS 两处 toggle 改类切换；删除 `convListVisible` 死代码
- **GUI 回归**：badge 显示 DeepSeek ✅；JSON 导出下载成功 ✅；停止生成部分内容落库（DB id=17 截断内容）✅；480px 列表收起/☰ 展开/消息可见/切换对话自动滚底 ✅
- **测试**：pytest **174 passed**（+3）；Vitest **37 passed**（+5）

---

## 日志正文

- **阶段**：架构摩擦分析 11 候选全部收官；P6.4 Tauri / P6.5 多 tab 待办（→ TICKETS）
- **前端模块化**：设置面板提取 `settings-panel.js`；模型选择统一 `model-utils.js`；SSE 解析器 `sse-reader.js`；state.js 收缩
- **Provider 标识符**：key/id 分离，data-index 退役，模型数据迁移 `services/model_data.py`
- **服务层解耦**：领域异常 `services/exceptions.py` + 角色卡异常层次
- **测试**：pytest **141** 用例 + 前端 Vitest **32** 用例，全部通过
- **数据**：清理测试数据（TestBot + 3 对话 + 6 消息）；`default_provider` 修正 openai→deepseek 对齐新 key 方案

---

## 日志正文

### 2026-08-06 | 重设计 | 温暖叙事 UI 全面升级
- **色板更换**：Linear 冷灰（lavender）→ Warm Stone 暖灰 + 琥珀金 accent（`#E8A33D`）；深色 `#0d0b08` 暖墨色基底，浅色 `#f4f0e9` 暖米白基底
- **SVG 图标**：导航栏/按钮全部 emoji 替换为 inline SVG（对话气泡、人物、放大镜、齿轮、＋、↓、垃圾桶等）
- **对话气泡**：圆角 8px→16px Telegram 风格；user 气泡琥珀填充 + 左下小圆角，assistant 气泡暖卡底色 + 细边框 + 右下小圆角；间距加大；头像缩小带边框
- **输入区**：包裹在 `border-radius:20px` 圆角容器内，聚焦琥珀发光，发送按钮 hover 辉光
- **角色卡片**：头像 44→52px 带边框阴影，hover 上移 2px，新增 accent 标签
- **空状态**：新增 SVG 图标 + 三段式布局 + 有温度文案「你的故事从这里开始」
- **思考指示器**：脉冲点灰色→琥珀色，匹配气泡样式
- **测试**：pytest 157 + 前端 32 全绿

### 2026-08-06 | 修复 | 流式对话空气泡问题
- **chat.js `handleSend`**：流式路径先创建空气泡→用户看到空白消息 → 改为先显示 thinking 指示器，第一个 token 到达时再创建 assistant 气泡
- **onError 保护**：错误发生在第一个 token 前时，移除 thinking 指示器并兜底创建气泡显示错误信息，防止 `assistantDiv` null 引用

### 2026-08-06 | 实现 | 用户手册视图
- 导航栏新增「手册」按钮（📄 文档图标），移动端同步
- `#view-guide` 7 章节完整内容：快速开始、角色管理、对话功能、搜索消息、设置说明、支持模型、小贴士
- 路由通过通用 `switchView` 模式自动生效，零 JS 改动
- 卡片式布局，`max-width:1000px` 居中展示

### 2026-08-05 | 重构 | 架构摩擦分析 11 候选全部落地
- **① 设置面板提取**（`a69c53e`）：app.js ~320 行设置逻辑（Provider/模型下拉、主题、侧栏、保存/清空/API Key 测试）迁入 `components/settings-panel.js`，协议表面 `initSettingsPanel`/`loadSettings`/`initProviderDropdown`；app.js 1050→~700 行
- **② 模型选择统一**（`a69c53e`）：`utils/model-utils.js` 暴露 `fillModelSelect`/`createCustomModelHandler`，settings-panel 与 model-selector 共享，消除重复
- **③ Provider 标识符重构**（`429b075`）：8 provider 各配唯一 `key`，`id` 保留为 API 协议标识符；前端下拉 value 用 key，`data-index` 匹配逻辑退役；factory 注册第三方 OpenAI 兼容 Provider；`setting.api_key`/`base_url` 经 `_PROVIDER_API_MAP` 将 key 映射到协议存储键（如 deepseek→openai_api_key）
- **④ 服务层异常解耦**（`abd8920`）：`services/exceptions.py` 定义领域异常（ConversationNotFound/ApiKeyMissing/ProviderNotSupported），`prepare_chat` 不再抛 HTTPException，路由层 `_prepare_or_raise` 捕获转 HTTP 状态码
- **⑤ 模型数据迁移**（`429b075`）：`AVAILABLE_MODELS` 移至 `services/model_data.py`，models 路由 131→18 行纯化
- **⑥ state.js 职责收缩**（`a69c53e`）：`convListVisible`/`searchTimeout` 移至 app.js 模块级，state.js 仅留应用级数据
- **⑦ BaseLLM 死代码清理**（`29da016`）：移除无调用方引用的 `provider_name` 抽象属性
- **⑧ 角色卡异常层次**（`abd8920`）：`CardFormatError`/`CardValidationError` 精确区分格式与校验错误，路由统一转 422；测试断言同步迁移
- **⑨ SSE 流解析器提取**（`a69c53e`）：`utils/sse-reader.js` `parseSSEStream` 纯函数，api.js 解析逻辑收敛为 1 行调用；新增 4 用例
- **⑩ 查询逻辑 DRY**（`29da016`）：`_base_character_query` + `_attach_count` 消除 list/get 重复 outerjoin/group_by
- **⑪ 静态文件路由冲突**（`29da016`）：`/` 挂载点添加注册顺序契约注释（API 路由须 /api 前缀且在挂载前注册）
- **数据清理**：删除测试角色 TestBot 及其 3 对话 6 消息（备份 `conver_system.backup-20260805-233559.db`）；`default_provider` 修正 `openai`→`deepseek` 对齐新 key 方案（default_provider_name=DeepSeek）
- **测试**：pytest **141 passed**；前端 Vitest **32 passed**（4 文件，新增 sse-reader 4 用例）

### 2026-08-05 | 重构 | API 凭证通用解析 — 填任一字段即可全局使用
- **需求**：通用系统，key/url 填 claude 或 openai 任一字段，选择任意模型即可直接用（聚合平台场景：一个 key + 一个平台 url 全协议通吃）
- **setting.py 解析链重构**：`_slot_value` 统一凭证解析「provider 特定键 → 同协议槽位 → 跨协议兜底」；`api_key` 再叠 .env 兜底（同协议 → 另一协议）；`base_url` 同链
- **效果**：用户只填 `claude_api_key`+`claude_base_url` 时，claude/openai/deepseek/qwen/kimi 全部解析到同一 key+url，协议由所选 provider 的 id 决定（SDK 自动加 /v1/chat/completions 或 /v1/messages）
- **前端**：设置页 API 密钥 group 加通用提示文案
- **测试**：+8 用例（同协议回退 / 跨协议兜底 / 同协议优先 / provider 特定优先 / base_url 同链）；pytest **149 passed**
- **ADR 取舍**：不做 key/url 强制配对（多平台双字段场景少见）；跨协议兜底是默认行为，同协议槽位优先保证双字段场景仍正确路由

### 2026-08-05 | 重构 | 连接测试通用化 + OpenAI base_url 自动补 /v1
- **需求澄清**：relay 能力由用户自控，系统只需保证「填对 key + url + 模型名 → 能对话」，不做模型假设
- **test-connection 回退链**（settings.py）：未显式传 Key/URL/模型时，全部回退通用解析（key/url → setting_service；model → 默认模型），避免用硬编码模型（claude-sonnet-5）导致用户 key 无权限而误报
- **前端 testApiKeys 重写**：只测「默认 Provider + 默认模型」（用户实际将使用的配置），Key/URL 取表单同协议优先 → 跨协议兜底；未填 Key 则跳过测试
- **OpenAI base_url 规范化**（openai.py `_normalize_base_url`）：用户只填面板根地址（`https://api.kukuit.com`）时，SDK 拼接 `/chat/completions` 会打到 HTML 面板 → 自动补 `/v1` 版本段（已含 v1/v1beta 不误改）
- **实测**：用户配置（default=deepseek, model=deepseek-v4-flash, base_url 根地址）规范化后 `/v1/chat/completions` 连接成功
- **测试**：+8 用例（model 回退 / base_url 回退 / normalize 5 例）；pytest **157 passed**

### 2026-08-04 | 实现 | Linear 设计语言 UI 重设计（`f83ec2f`）
- **设计系统**：CSS 全面重写为 Linear 风格（near-black `#010102` canvas + 薰衣草蓝 `#5e6ad2` accent）；4 层 surface 阶梯（page → bg → panel-2 → panel-3 → panel-4）+ hairline 半透明边框
- **Token 化**：全部颜色、间距、圆角、字号通过 CSS 自定义属性管理；深色模式优先，浅色模式从同一色板推导
- **组件**：新增 SVG logo 图标 + 发送按钮箭头；skeleton 骨架屏加载状态类（`.skeleton` / `.skeleton-line` / `.skeleton-card` / `.skeleton-circle`）
- **合规**：Inter 字体使用系统栈替代（无云依赖）；移除 backdrop-filter glassmorphism、纯黑/纯白、accent 色超范围使用
- **遗留**：是非 Ticket 驱动的一次性视觉改进，不影响已有功能
- **② 导出收拢**：新 `services/conversation_export.py` 深模块（`__all__` 仅 `export_conversation_json`/`export_conversation_markdown`）收纳导出逻辑；`conversation.py` 257→134 行；角色字段提取由新增 `ConversationExportCharacter` Schema（`from_attributes=True`，9 字段）唯一驱动，service 层零手写字段映射（弃用初稿「手写 frozenset + model_dump(include=) 混合方案」，字段清单单点化）
- **④ 搜索结果 Schema**：`search_messages` 返回 `list[SearchResult]`（9 字段与旧 dict 契约逐字段一致：role `.value` / created_at isoformat / 空 query `[]`）；路由 `GET /api/messages/search` 声明 `response_model=list[SearchResult]`；与 ④ 序列化主线（response_model 驱动）汇合
- **③ 前端模态框抽象**：`components/modal.js` 通用工厂 `openModal`（遮罩/标题转义/body/actions/关闭三路径/结果回传）；`showConfirm`/`showAlert` 对外 API 不变、内部复用工厂；`showModelSelector`/`createExportDialog` 迁入 `model-selector.js`/`export-dialog.js`，函数体从 app.js 删除；`downloadBlob`/`showToast` 移入 utils.js（`showError`/`showSuccess` 1 行委托，解 app.js↔组件循环依赖）；app.js 1080→864 行；Playwright 冒烟三弹窗开合 + 消息渲染无 JS 错误
- **⑤ 前端测试基建**：Vitest ^3 + jsdom ^26（`frontend/package.json` + `vitest.config.js`）；纯函数模块 `format.js`（`highlightText`/`buildMessagesHtml`/头像 HTML）数据→HTML 映射与 DOM 分离；`renderMessages` 改 `container.innerHTML = buildMessagesHtml(...)`；api.js 注入 `setFetch(fn)` seam（`doFetch` 默认 `globalThis.fetch`，浏览器行为不变）；`.gitignore` 补 `node_modules/`
- **测试**：pytest **141 passed**；前端 `npm test` **28 passed**（3 文件：format 15 / utils 8 / api 5，mock fetch 测字符列表/创建/search URL 编码/422 错误/204 空）
- **ADR 取舍**：导出角色段用专用 Schema 而非 `to_v2_card`——后者输出 SillyTavern V2 信封（spec 包裹 + 字段改名 + 头像去 data-URI 前缀）会破坏既有导出契约；Schema 放 `schemas/conversation.py`（唯一消费方是对话导出，保 locality）
- **遗留**：`schemas/__init__.py` / `services/__init__.py` 空导出（与 `models/`、`services/llm/` 不一致，属存量问题），留待统一清理

### 2026-08-03 | 实现 | 架构深化 ④：response_model 统一驱动序列化，退役手写 dict（character + conversation）
- **character.py**：删除 `_char_to_dict()`（23 行手写字段映射，与 `CharacterResponse` 完全重复）；`list_characters` / `get_character_with_count` 返回 ORM `Character` 对象 + 瞬态属性 `conversation_count`
- **conversation.py**（第二轮架构评审候选 ①）：`list_conversations` 返回 `list[dict]` → `list[Conversation]` + 瞬态属性 `message_count`，删除 13 行手写字段映射；`ConversationResponse` 已有 `message_count` + `from_attributes`，schema/路由零改动
- FastAPI `response_model=*(from_attributes=True)` 统一驱动序列化，后端所有 list 端点不再有手写 dict 落在 service 层
- 新增字段只需改 ORM model + Schema，不再需要同步改手写 dict
- 测试：117 项全过；端到端冒烟 `GET /api/conversations` 返回正确（`message_count` 正确填充：有消息=3 / 空对话=0）

### 2026-08-03 | 基础设施 | Rust 工具链安装（Tauri 桌面端前置）
- **Rust 工具链**：rustup 1.29.0 + rustc/cargo 1.97.1（stable-x86_64-pc-windows-msvc）安装完成
  - 工具链目录：`C:\Users\Administrator\.rustup`
  - Cargo 目录：`C:\Users\Administrator\.cargo\bin\`（已加 PATH）
  - 组件：clippy、rustfmt
- **MSVC 工具**：14.50.35717（link.exe）已就位
- **Windows SDK**：10.0.22621.0 已安装（`C:\Program Files (x86)\Windows Kits\10\`）
- **验证**：`cargo build` 冒烟测试通过 ✅
- **文档**：`PROJECT_REFERENCE.md` 新增「五、桌面端准备」章节；memory 新增 `rust-toolchain.md`
- **避坑**：Git Bash 的 `/usr/bin/link.exe`（GNU coreutils）会遮蔽真正的 MSVC `link.exe`，需在 **cmd.exe** 或 **PowerShell** 中运行 `cargo build`

### 2026-08-03 | 实现 | 架构深化 ③⑤：Prompt 纯函数化 + 前端 app.js 拆分
- **③ Prompt 纯函数化**：新建 `services/llm/prompt.py`，把模板变量替换（`apply_template_vars`）、mes_example 解析（`parse_mes_example`）、完整消息列表组装（`build_messages`）从 `message.py` 迁移为纯函数；`CharacterData` frozen dataclass 作为角色纯数据容器（去 db Session 依赖）；`message.py::build_message_list` 签名与行为不变（查角色+查历史→委托纯函数）；26 项单测，新模块 100% 行覆盖（62 stmts 0 miss）
- **⑤ 前端 app.js 拆分**：1380 行 → `chat.js`（328 行，聊天域渲染+交互+chatDom）+ `state.js`（54 行，全局状态+模块级状态）+ `app.js`（1080 行，视图/角色/对话/设置/搜索/init）；`setConversationsRefresher` 钩子解决 handleSend 对 loadConversations 的反向依赖（避免循环 import）；`index.html` 无变更（ESM 内部 import）；Playwright 冒烟通过（流式/非流式/主题/设置/搜索），无 JS 错误
- **测试**：pytest **117 passed**（原 91 + prompt 26）

### 2026-08-03 | 实现 | 架构深化 ①②⑥：聊天回合 + 运行时设置深模块 + Provider 注册显式化
- **① 聊天回合深模块**：`services/chat.py` 收拢一次聊天回合全生命周期（插开场白 → 存用户消息 → 组装上下文 → 取 Key / Provider → 生成 → 保存 / 断开保存部分）；`ChatContext` / `prepare_chat` / `llm_error_response` / `stream_reply` 四接口，`api/routes/chat.py` 仅留 HTTP 映射 + SSE `data:` 帧包装（-199 行）
- **② 运行时设置深模块**：`services/setting.py` 收口三处手写点（chat 路由 `_get_api_key` 等 / settings 路由 `ALLOWED_KEYS` / conversation `_get_setting_value`）；白名单 + DB→config 默认回退链 + 整型容错（防 500）；`ALLOWED_KEYS` 主位移至 service（`docs/llm-integration.md` step 3 路径同步）
- **⑥ Provider 注册显式化**：`main.py` on_startup 调 `LLMFactory.register_builtin_providers()`，`factory.py` `_ensure_builtins` 懒加载兜底（`get_provider` / `list_providers` 首次调用自动注册）；`llm/__init__.py` 导出 `register_builtin_providers`，去 import 副作用
- **取舍（架构评审已接受，不重构）**：`services/chat.py` 仍抛 `HTTPException` 并 import fastapi / starlette 类型——service 层未做到 HTTP-agnostic，按「原样上移」设计保留，文档化不重构
- **测试**：test_p35 改用 service 层 patch（`setting_service.api_key` / `chat_service.LLMFactory`）；test_settings_connection 新增 `services/setting.py` 深模块语义 8 用例（整型回退防 500 / 默认回退链 / api_key 未配置空串）；pytest **91 passed**

### 2026-08-03 | 审计 | 文档/测试专项审查（Standards + Spec 双轴）
- **范围**：`b5fe037..HEAD` 全部文档与测试。双轴 = Standards（对照《文档规范》/CLAUDE.md 惯例/嗅探基线）+ Spec（文档/测试 vs 实际代码一致性）
- **Spec 轴修复**：`api-design.md`（`greeting`→`first_mes` + V2 字段、conversation 误含 `character_name`、模型列表缺 `claude-opus-4-8`/`gpt-4-turbo`、补 6 个缺失端点：角色 import/export、对话 export json/markdown、`DELETE /api/conversations`、消息 search、settings test-connection、settings 键补全、错误码补 401/429/504）；`architecture.md`（`/api/convs`→`/api/conversations`、角色表 V2 全列、目录树补 `setting.py`/`settings.py`/`character_card.py`/前端组件/`tests`、数据流同步 `build_message_list`）；`llm-integration.md`（`generate_reply` 函数不存在→`build_message_list`、BaseLLM 签名 + `test_connection`、Factory 带 `base_url`、Prompt 构建/滑窗策略对齐代码、新 Provider 添加步骤）；`p2.5` SPEC §4.2 偏差只记 DEV_LOG 未改规格文档（闭环修正）
- **Standards 轴修复**：`db_session` fixture 在 test_p35 / test_settings_connection 各复制一份 → 移入 `conftest.py`（删重复 + 清理失效 import）；`character_card` 100% 覆盖声明原无 `.coverage` 产物 → 补可复现命令实测（101 stmts 0 miss）；TICKETS P0 手动项（P4.3 完成后过时）归档；CONSENSUS 更新记录过期
- **规范强化**：`docs/documentation-standards.md` 新增 §三 测试规范（共享 fixture 入 conftest / 覆盖率声明可复现 / 测试数同步）+ §六 防漂移新增 4 检查项（API 契约完整性 / 字段名以 schema 为准 / 规格偏差闭环 / 覆盖率有产物）
- 新增 CR-D1~D7 全部修复归档；83 用例通过

### 2026-08-03 | 实现 | P4.3 API Key 保存时测试连接
- **后端**：`BaseLLM.test_connection()` 默认实现（发起最小生成请求 max_tokens=1，连接无效抛出 Provider `_translate_error` 映射的 LLMError，Provider 可覆写）；`POST /api/settings/test-connection` 端点（请求 Key 为空回退 DB 已存 Key；不支持的 provider / 未提供 Key / LLMError / 通用异常均 400 + 可读原因）
- **前端**：`api.js:settings.testConnection()`；`app.js:testApiKeys()` 保存设置前对每个非空 Key 并发测试，任一失败弹 `showConfirm`「仍然保存？」由用户决定（Key 无误但网络不可达可继续保存），取消则不落库
- 单测 11 项（`tests/test_settings_connection.py`：BaseLLM 默认实现参数断言 / 端点成功 / 鉴权失败 / 不支持 provider / 空 Key 回退已存 Key / base_url 透传 / 通用异常 / GET+PUT 设置 CRUD）；settings 路由 + schemas.settings + llm.base **100% 行覆盖**
- Playwright 前端验证：无效 Claude Key 保存 → 确认框「API Key 连接测试未通过」→「仍然保存」→「设置已保存」；验证后清理临时 DB 写入（dev 库还原至 `default_provider/user_name` 两行）
- 避坑：schema 类名带 `Test` 前缀会被 pytest 误认为测试类告警，命名 `ConnectionTestRequest/Response` 规避；Playwright 需显式 `executablePath` 指向 ms-playwright 已装 chromium（MCP 默认 channel=chrome 未装系统 Chrome）

### 2026-08-03 | 实现 | P3.5 停止生成按钮 + 对话标题自动生成
- **停止生成（仅流式）**：后端 `chat.py:stream_chat` 的 `event_generator` 每 token 轮询 `request.is_disconnected()`，客户端断开即停止 LLM 调用并**保存已生成部分**为 assistant 消息（另 `except ClientDisconnect` 兜底）；前端 `api.js:chatStream()` 重构为返回 `{abort, done}`（内部 AbortController），发送按钮流式生成中两态变身 `➤` ⇄ `⏹ 停止`，停止的气泡追加「（已停止）」标记（非错误语义）
- **标题自动生成**：`create_conversation` 未传 title 时默认「与 {角色名} 的对话」；新增 `truncate_title` 纯函数（折叠空白 + 截 20 字 + 「…」，不剥离 Markdown）；`create_message` 保存首条 user 消息且标题仍为占位默认值时同步替换；前端移除 `startChatWithCharacter` 的 `title:'新对话'` 硬编码，并新增 `syncChatHeaderTitle()` 让头部标题跟随后端替换
- 后端 19 项单测（`tests/test_p35.py`：truncate_title 纯函数 / 默认标题 / 首条替换 / 流式断开保存部分内容 / ClientDisconnect / LLM 错误）；Playwright 前端验证：停止按钮两态 + 「已停止」标记 + 标题联动（头部/侧栏同步截断标题）
- 避坑：Playwright stub 伪造 SSE 流需显式 `controller.close()`，否则 `reader.read()` 永不返回 done、`stream.done` 悬挂，正常完成路径无法验证（停止路径因 abort error 仍可达）

### 2026-08-03 | 验证 | P2.5.8 打包验证 + 文档同步
- Playwright 前端全流程手测（临时 DB，验证后清理）：V2 卡导入（base64 头像 / temperature / lorebook / custom_ext 全保真）、导出为合法 V2 信封（data 15 键）、导出→导入往返不丢数据、V1 旧卡导入（含 description 直通）、裸 data 导入（temperature 0.5 兜底生效）、非法卡 → 422、非 JSON 文件前端拦截不发请求
- 文档同步：TICKETS P2.5 全部归档、DEV_LOG、PROJECT_REFERENCE、SPEC 状态 ✅、memory project-status

### 2026-08-03 | 测试 | P2.5.7 转换层单元测试
- 新建 pytest 基础设施：`pytest.ini`（`pythonpath=.` 使 `backend.app.*` 可导入）+ `backend/requirements-dev.txt` + `backend/tests/`（conftest `make_character` 工厂 + test_character_card.py）
- 53 用例覆盖：V2 往返 / V1 归一化 / 裸 data / 非法卡 ValueError（路由转 422）/ 头像三形态 + MIME 魔数推断 / temperature 默认与裁剪 / extensions 保真 / 脏数据容错；character_card.py **100% 行覆盖**
- 测试驱动发现并修复 2 个 bug：V1 卡 `description` 字段被归一化丢弃（`_V1_TO_V2` 缺 `description` 映射，违反 spec §3.4）；裸 data 顶层 `temperature` 被忽略（`_build_create` 补 data 兜底读取，命名空间仍优先）

### 2026-08-03 | 实现 | P2.5.6 手动创建完整性引导
- character-form.js 软提示：姓名/人格设定/开场白缺项时 label 旁「建议填写」badge + 汇总 field-hint「完整角色建议包含：人格设定 + 开场白」，输入实时刷新
- 保存时缺项 → `showConfirm` 软确认「设定不完整…仍要保存吗？」（仍要保存/返回修改），软提示不拦截；仅手动表单，导入路径不参与（D6）
- `confirm-dialog.js` 修复：只清已有确认弹窗（`.modal-overlay .confirm-modal`），不再误删其它模态框，角色表单与确认弹窗可叠放
- Playwright E2E 验证：空名硬校验、软提示文案、返回修改后表单保留、填齐保存无确认、badge/hint 实时状态
- 避坑：测试时发现 Playwright 浏览器配置文件缓存旧模块，需用 `newContext()` 全新上下文验证（非代码问题）

### 2026-08-03 | 文档 | 文档规范改造
- 依据 Profit Calculator 经验 + 知识库沉淀《文档规范》（`docs/documentation-standards.md`）
- PROJECT_REFERENCE 修正「同步 ORM」错误（原误写 async/aiosqlite）、删除与 README/CONSENSUS 重复的技术栈/路线图
- README 修正 `.env` 复制路径（应为根目录）、删除重复内容
- DEV_LOG 瘦身 579 → ~100 行：待办项移 TICKETS、审计快照压缩为一行、历史改倒序滚动条目
- TICKETS 新增「已完成归档」区，CR 项按生命周期归档（记日期 + 提交哈希）
- `database.py` docstring 同步化；`.serena` tech_stack 记忆修正 aiosqlite → 同步

### 2026-08-03 | 实现 | P2.5.5 前端导出 UI
- 角色卡片操作区新增 📤 导出按钮（`.export-char`，置于编辑与删除之间，D4）
- 抽取通用 `downloadBlob(url, filename, errorPrefix)`；对话导出 `downloadExport()` 重构复用，消除两处 Blob 下载重复（与 CR.6.2 去重思路一致）
- Playwright E2E：中文文件名正确、V2 信封完整（data 15 键）、temperature 入 `extensions.conver_system` 命名空间

### 2026-08-03 | 实现 | P2.5.4 前端导入 UI
- 角色视图「导入角色」按钮 + 隐藏文件输入 + `characters.import()` + toast 反馈（D4/D6）
- Playwright E2E：V2 卡导入、非法 JSON 前端拦截（不发请求）、后端 422 单前缀展示

### 2026-08-03 | 实现 | P2.5.3 角色导入 API
- `POST /api/characters/import`：`from_v2_card` 归一化 → create_character 落库（D3 重名直接新建）
- `ValueError` → 422 友好 detail；非 dict body 自动 422；路由零业务逻辑（复用 character_card 深模块）
- 验证：V2/裸 data/V1 旧卡导入 201、非法卡 422、导出→导入往返保真

### 2026-08-03 | 实现 | P2.5.2 角色导出 API
- `GET /api/characters/{id}/export`：`to_v2_card` → JSONResponse + `Content-Disposition` 附件头（中文名 URL 编码）
- 规格偏差：SPEC §4.2 用 `get_character_with_count` 校验，实际需 ORM 对象 → 改用 `get_character`（同源校验，语义等价）

### 2026-08-03 | 实现 | P2.5.1 后端转换层
- `services/character_card.py`：`to_v2_card` / `from_v2_card`（V2 信封 + 裸 data + V1 归一化 + `extensions.conver_system` 往返保真）

### 2026-08-03 | 实现 | CR.6.5 messages.py 职责分离
- 聊天端点拆出 `api/routes/chat.py`（POST /api/chats + /api/chats/stream + LLM 辅助），`messages.py` 仅留消息检索；路由 tags 拆「聊天」/「消息」

### 2026-08-03 | 实现 | CR.5.3 + CR.5.4 + CR.6.3 命名规范 + Primitive Obsession
- 决策：允许 `stream_*` 特殊动词前缀（SSE 流式端点）；`save_message` → `create_message`，`auto_insert_greeting` 保留原名
- Character JSON 字段（tags/alternate_greetings/creator_notes/extensions）→ SQLAlchemy JSON 列，存量 TEXT 兼容
- Message.role → `Role` 枚举（`Enum` 列 `values_callable` 按值存取，存量 VARCHAR 兼容），LLM 消息/导出输出 `.value` 纯字符串

### 2026-08-03 | 实现 | CR.5.5 + CR.7 默认模型回退链重构
- 移除硬编码 `"claude"`/`"claude-sonnet-4-20250514"` → 引用 config 默认；删除靠字符串比较判断「是否覆盖」的脆弱逻辑
- 改用 Pydantic v2 `model_fields_set`：显式传参 → settings 默认 → config 默认；修复「显式选择=默认值时被静默覆盖」边界

### 2026-08-03 | 实现 | CR.6.2 前端头像/复制按钮构造去重
- 新增 `createAvatarElement(role)` + `attachCopyButton(btn, content)`，renderMessages/appendMessage/流模式复用；最小 DOM shim 测试 12 用例通过

### 2026-08-03 | 实现 | CR.5.1 + CR.5.2 类型注解 + API 路径重命名
- 全部路由/服务函数补返回类型注解（27+ 处）；`/api/chat` → `/api/chats`（前端 api.js + 4 份文档同步）

### 2026-08-03 | 实现 | CR.6.1 + CR.3.2 + CR.4.1 代码质量收尾
- `_prepare_chat()` + `_ChatContext` 收敛 ~90 行共同前置逻辑；Provider 新增 `_translate_error()` 共用 SDK 异常映射；ChatRequest.stream 复核无死代码

### 2026-08-03 | 实现 | CR.3.1 + CR.6.4 deps.py 清理
- 删除纯转发浅模块 `api/deps.py`，4 个路由直连 `database.get_db`

### 2026-08-03 | 实现 | CR.2 代码质量硬性违规清理
- 复核确认 3/4 子项在现行代码已就绪（类型注解/命名/typing 语法），仅补齐冗余局部导入清理（见 `经验/审计快照过期需复核`）

### 2026-07-30 | 实现 | P6.3 Prompt 模板变量
- `_apply_template_vars()`：`{{user}}` → 用户昵称、`{{char}}` → 角色名，作用于 greeting/scenario/mes_example/系统提示/用户输入
- 前端设置面板「模板变量」分组 + 表单字段提示

### 2026-07-30 | 实现 | P6.2 搜索历史消息
- `search_messages()`：SQL LIKE 跨对话搜索 + JOIN 上下文 + 关键词前后 50 字截取；`GET /api/messages/search?q=&limit=50`
- 前端搜索视图（防抖 300ms、关键词高亮、结果跳转）

### 2026-07-30 | 修复 | CR.4.3 theme_mode 设置不生效
- 根因：值保存/加载但从未应用 DOM，CSS 只认 `@media` 不认强制模式
- 修复：`applyTheme(mode)` 设置/移除 `<html data-theme>` + `:root[data-theme="dark"/"light"]` 选择器

### 2026-07-30 | 修复 | CR.4.2 V2 字段未用于 prompt 组装
- 根因：`build_message_list()` 忽略 scenario/mes_example/post_history_instructions
- 修复：scenario → `[场景设定]` 系统消息；mes_example 解析 `<START>` 对话为 few-shot；post_history_instructions 置于历史后；空字段跳过

### 2026-07-30 | 修复 | CR.4.1 SSE 流中断 → 按钮永久禁用
- 根因：`reader.read()` 返回 done 时直接 break，从不触发 onDone/onError，`isStreaming`/`btnSend.disabled` 永不重置
- 修复：`completed` 标记，流结束未收 done → `onDone(null)` 重置状态，有部分内容仍保存

### 2026-07-30 | 实现 | P6.1 对话导出
- `export_conversation_json/markdown`；`GET /{id}/export/json|markdown`（附件头）+ 前端导出弹窗 + Blob 下载
- CR.9 toast 通知（showError/showSuccess），数据加载失败用户可见

### 2026-07-30 | 实现 | Phase 5 体验完善
- 对话历史/重命名/删除确认/清空、Markdown 渲染、复制按钮、Toast、快捷键、主题切换（auto/light/dark）、响应式、设置面板（滑窗/默认模型/base_url）

### 2026-07-30 | 实现 | Phase 4 多模型支持
- OpenAIProvider（generate/stream_generate、base_url 可配、异常映射）+ Factory 注册；前端模型选择器 + model badge + 设置集成

### 2026-07-30 | 实现 | Phase 3 对话核心
- ClaudeProvider generate/stream_generate + LLM 异常映射；POST /api/chats + /api/chats/stream（SSE）
- 上下文管理：system prompt + 滑窗（轮数从 settings 读）+ greeting 自动插入；Key 动态读取；temperature 生效；前端流式渲染 + 思考指示器

### 2026-07-30 | 实现 | Phase 2 角色管理前端
- character-form.js（完整字段）、编辑预填、删除确认（关联对话数）、角色卡片增强

### 2026-07-30 | 实现 | Phase 1 项目骨架
- config / database（同步 ORM + PRAGMA FK）/ models（V2 完整字段）/ schemas / LLM 层（BaseLLM+Factory+桩）/ API Routes / main.py
- 前端 index.html 三栏 + style.css 主题 + api.js（fetch+SSE）+ app.js

### 2026-07-30 | 审计 | 全量代码审查（Phase 5 后）
- 发现 27 处缺类型注解、/api/chat 命名、头像/复制按钮重复、JSON 字段、Message.role、deps.py、messages.py 职责混杂 → CR 项已入 TICKETS（CR.1-CR.10）

### 2026-07-30 | 审计 | 全量代码审查（初轮）
- Standards + Spec 双轴：滑窗不生效、SSE 错误静默丢弃、类型注解缺失、异常映射重复 → CR 项已入 TICKETS
- 决策：Git 延迟初始化（项目完善后再 `git init`）

### 2026-07-30 | 立项 | to-tickets 阶段
- grill → to-spec（CONSENSUS + 4 份设计文档）→ to-tickets（TICKETS 全量任务分解）→ implement
