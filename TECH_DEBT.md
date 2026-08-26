# TECH_DEBT: conver system

> 技术债候选池与处置记录。**本文件不是任务池**：条目不自动进入任何 session 的 preflight 认领；
> 消费 = 显式「立项」（转入 `TICKETS.md` 活跃工单，或标记 ❌ 不立项附理由）。
> 条目格式：编号 / 来源 / 强度 / 状态。
>
> 本文件由 `TICKETS.md` 技术债区独立化迁移而来（2026-08-24，对齐 AGENTS.md §3 规范），
> 原文完整保留审计追溯。注：本项目任务文件名为 `TICKETS.md`（非 TO-TICKETS.md）。

## 清出机制（防膨胀）

1. **候选区只留开放条目**（📝 待立项 / 🔄 进行中）；条目处置后移出候选区，处置详情写入下方处置记录。
2. **❌ 条目压缩**：具复核价值的关闭项（防 review 重复提出）保留单行摘要；其余直接删除。
3. **处置记录滚动保留最近 2 个日期节**，更早的节整体删除——归档由 git 历史承担
   （`git log -p -- TECH_DEBT.md`）。
4. 清出动作绑定既有维护节点：每会话结束、commit 之前同步执行，不新增仪式。

## 技术债候选区

> 当前 8 项待立项（W1/W2/W3/W4 增量审核与实现发现）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-49 | `error-bar.js:67` `String(message)` 对可抛 `toString()` 的 message 会抛 TypeError（上游现实不可达，仅防御性） | W1 增量审核 | Speculative | 📝 待立项 |
| F-50 | 流式多 tab 并发出错时错误条渲染到共享 `.chat-main` 区域，互相替换造成 UX 轻微误导 | W1 增量审核 | Worth exploring | 📝 待立项 |
| F-51 | `stream-session.js:349-353` `surfaceError` 置于 `render()` 之后，render 抛错会吞掉错误条（防御缺口） | W1 增量审核 | Worth exploring | 📝 待立项 |
| F-52 | 搜索跳转携带陈旧 messageId（目标消息已被删）时落地在对话顶部、不落 scrollToBottom（`chat.js` locateAndHighlight 无匹配早退），UX 降级且测试已锁定该行为——需产品决策降级语义 | W2 增量审核 | Worth exploring | 📝 待立项 |
| F-53 | `chat.js:432` 模型切换 `refreshConversations` 网络失败被 catch 记为「切换模型失败」，但 state/头部已更新——日志语义误导，列表可能滞留旧模型与头部不一致 | W3 增量审核 | Worth exploring | 📝 待立项 |
| F-54 | `credentialWarnReason` 凭证确认不对称：openai 态（仅有 OpenAI key）切到 claude 模型同样不可用却无提示（none 恒提示 / claude 切非 claude 提示） | W3 增量审核 | Worth exploring | 📝 待立项 |
| F-55 | `game-generator.js` 凭证预检 `.then` 无提交态守卫——提示可能在用户已提交生成后才注入，或显示过期「需配置」提示（竞态） | W3 增量审核 | Worth exploring | 📝 待立项 |
| F-56 | `backend/requirements.txt` `anthropic>=0.40.0` 无上界：anthropic SDK 1.0.0 已移除 `messages.create` 的 `temperature` 参数（当前环境 0.116.0 支持，`claude.py:51/76` 传 `temperature=`），升级到 1.x 将全量破坏 claude 调用——需锁上界或适配 | T6 实现发现（T6 agent 误报为当前阻断，实测为潜在风险） | Worth exploring | 📝 待立项 |
| F-57 | `chat.js:699-704` regenerate 在途守卫只查 `nonStreamingInFlight`，未阻断并发**流式**发送（`tab.isStreaming` 重生成期间未置位）——互斥注释「同对话互斥」对流式路径失效，构造：重生成在途 + 流式发送 → 并行双请求 | W4 增量审核 | Worth exploring | 📝 待立项 |
| F-58 | `chat.js:721-725`+`stream-session.js:179` regenerate 成功但 `settleTurn` 重载失败时 `anchor=null` 走 append 兜底，后端已删旧回复残留本地 + 新回复追加，破坏「顶替」语义（瞬时数据不一致，切 tab 自愈） | W4 增量审核 | Worth exploring | 📝 待立项 |
| F-59 | `chat.js:733` thinking-indicator finally 无条件移除 + `showThinkingIndicator` 不按 convId 隔离——对 A 重生成显示 thinking、切 B 发送、A 完成会移除 B 的 thinking 指示器（纯 UI 污染） | W4 增量审核 | Worth exploring | 📝 待立项 |
| F-60 | 重生成成功 + `settleTurn` stale revision（并发外部长度变更）→ `mergeFreshList` 静默丢弃、不渲染不提示（竞态边角） | W4 增量审核 | Worth exploring | 📝 待立项 |
| F-61 | 重生成 re-render 不清 T2 高亮定时器（`highlightTimer`/`highlightEl` 引用残留分离节点，约 3s 后 no-op；自愈于下次 locate） | W4 增量审核 | Worth exploring | 📝 待立项 |
| F-62 | `backend/app/services/chat.py:328-339` regenerate `except LLMError` 分支重复死代码（第二分支不可达；与 F-27/F-28 同族的文件尾无换行项已复核关闭） | 期末四轴 | Worth exploring | 📝 待立项 |
| F-63 | `game-generator.js` 复用 `key-injector.js` 的 `SEL_NAV_SETTINGS='.sim-key-nav-settings'`（模拟器专属选择器名）用于生成器模态框——语义名与用途错位（Mysterious Name 倾向），建议抽中性共享命名 | 期末四轴 | Worth exploring | 📝 待立项 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-08-26（技术债消费批次：F-23~F-46 全自动档 kickoff，8 做 15 关 1 跳）

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-23 | CODE_WIKI.md `tests_total:total` 标记漂移（pytest 714 + Vitest 979 + cargo 70 = 1763，doc_sync 全渠道重算） | 波 1 增量审核（Falsify 轴） | Strong | ✅ 已修（2026-08-26：全渠道环境运行 doc_sync，total 聚合为 1763，doc_sync --check 通过） |
| F-24 | CODE_WIKI.md §4.14 chat.py 职责叙述陈旧（仍含 llm_error_response 引用） | 波 1 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：§4.14 职责行更新，删除 llm_error_response 引用，改为指向 §4.19 error_mapping.py） |
| F-26 | `test_error_handler.py:146` 类 docstring 误导（写经 chat_error_response 映射，实际直调 llm_error_handler） | 波 1 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：docstring 更新为「直调 llm_error_handler，handler 委托 error_mapping」，测试全绿） |
| F-29 | `simulator_store.py:21` docstring G4 依赖清单「os/pathlib/shutil」与实际 import「logging/shutil/pathlib」不一致 | 波 2 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：docstring 修正为「logging/shutil/pathlib」，pytest 全绿） |
| F-30 | `simulator_import.py:28,30` json/os import 后全模块零使用，docstring 清单同步 | 波 2 增量审核（Falsify 轴） | Worth exploring | ✅ 已修（2026-08-26：删除 import json 和 import os，docstring 同步；grep 零命中，pytest 全绿） |
| F-41 | `game_generator.py:64` 自定义 `ValidationError` 命名遮蔽 pydantic 同名类型 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：重命名为 GenValidationError，测试 import 同步，pytest 62 passed） |
| F-43 | 前端 11 模块缺 `__all__` 导出声明 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：api.js/app.js/state.js/utils.js/modal.js/model-selector.js/confirm-dialog.js/export-dialog.js/character-form.js/character-wizard.js/character-templates.js 补齐 __all__，Vitest 979 全绿） |
| F-44 | game_generator docstring 协议表面(3) 与 `__all__`(5) 不一致 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：docstring 协议表面列表更新为 5 符号（含 ScanResult / scan_generated_html）） |
| F-25 | `error_mapping.py:117` provider 前导空格——docstring 已声明「由调用方负责」，设计意图非缺陷 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：prefix 构造明确写入 docstring，调用方负责，非缺陷） |
| F-27 | `test_error_mapping_export.py` 文件末尾无换行符 | 波 1 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：纯文件风格，零功能影响） |
| F-28 | simulator_store/manifest/import 三个文件末尾缺失换行符 | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：纯文件风格，零功能影响，与 F-27 同族） |
| F-31 | `_filename_limit()` 函数级 re-import 测试耦合设计 | 波 2 增量审核（Falsify 轴） | Worth exploring | ❌ 复核关闭（2026-08-26：函数级延迟导入是规避循环引用的故意手段，消除需解耦模块结构，成本高收益低） |
| F-32 | `simulator_import.py` `__all__` 含 read_manifest/write_manifest re-export | 波 2 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：属设计意图，公共 API 表面，功能正确） |
| F-33 | `import_game` precomputed 路径对 ScanResult 字段无校验 | 波 3 增量审核（Falsify 轴） | Worth exploring | ❌ 复核关闭（2026-08-26：frozen dataclass 已保证字段类型结构有效，运行时校验无增值） |
| F-34 | `game_generator.py:286` 函数对象身份比较（`if check is _check_security`） | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：Python 合法惯用写法，sentinel 模式） |
| F-35 | `scan_generated_html` 被导出到 `__all__` 扩展公共 API 表面 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：刻意的 API 表面扩展，当前无外部调用方） |
| F-36 | 校验失败时 scan 结果被丢弃，每次重试重新扫描 | 波 3 增量审核（Falsify 轴） | Speculative | ❌ 复核关闭（2026-08-26：重试重新扫描确保每次结果新鲜，属设计权衡） |
| F-37 | 双向模块级循环 import（conversation ↔ message） | 期末四轴三联 | Worth exploring | ❌ 复核关闭（2026-08-26：T-07 已知副作用，函数级延迟导入正确运作，消除需架构重构收益有限） |
| F-38 | simulator_store 兼容 shim 私有名跨模块 + 循环 import 函数级补丁（与 F-31 同族） | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：三向循环引用已有补丁管理，重构开销大） |
| F-39 | `_current_write_manifest()` 测试耦合间接层（与 F-31/F-38 同族） | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：故意的测试 seam，回归锚 monkeypatch 入口） |
| F-40 | game_generator `_build_suggestion` 六分支级联 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭（2026-08-26：分支简单明确，新增检查项自然扩展） |
| F-42 | setting.py `_CRED_SLOTS` provider 键知识外泄 | 2026-08-25 全量审查 | Worth exploring | ❌ 复核关闭（2026-08-26：消除需注册层抽象，开销与收益不成比例，当前仅两协议槽位） |
| F-46 | 空串 token-only 流的前端占位残留（空气泡） | 期末四轴 Falsify | Speculative | ❌ 复核关闭（2026-08-26：纯前端化妆级问题，后端零污染） |
| F-47 | `initGuideSidebarScroll` 缺 type hints（`app.js:377`） | 2026-08-26 期末四轴（Standards ST-1） | Worth exploring | ✅ 已修（2026-08-26：补 `@returns {void}` 类型标注到 JSDoc） |
| F-48 | Scroll handler Feature Envy，建议提取 ScrollSpy 类 | 2026-08-26 期末四轴（Architecture A6） | Speculative | ❌ 复核关闭（2026-08-26：git grep 零命中 ScrollSpy，当前唯一滚动高亮逻辑在 55 行深模块内，无第二消费方 → Speculative Generality） |
| F-45 | O2 一致性缺口：chat 流式中途出错时 DB 落库 partial content 与 UI 错误气泡不一致 | 2026-08-25 全量审查 | Worth exploring | ✅ 已修（2026-08-26：error 路径设 saved=True 阻止 finally 保存幽灵内容，测试 713 全绿） |

### 2026-08-25（全量审查批次）

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| B2 | manifest 条目级字段不做校验（条目非 dict / 字段缺失等形态）复核维持关闭 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭（2026-08-25：系 simulator_manifest.py `_read_manifest_or_rebuild` docstring 文档化定版——损坏口径经 F-8/F-15 两次范围决策收敛，「条目级字段不做校验，范围收敛」（simulator_manifest.py:89-96）；原子写保证正常运行不产生此类损坏，需手工损坏 manifest 才触发；复核维持关闭） |
