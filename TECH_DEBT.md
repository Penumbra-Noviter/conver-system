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

> 当前 10 项待立项（F-49~F-63 批次的波末增量审核与期末四轴非阻断发现；原 F-49~F-63 已 2026-08-26 全量消费并移出候选区，见处置记录）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-64 | `regenerateLastReply` 在流式在途（`tab.isStreaming`）时无互斥守卫，仅查 `nonStreamingInFlight`——UI 不可达（流式占位无重生成按钮）、编程可入；与 Spec「同对话互斥收口」泛化措辞未全兑现（与期末 Spec 发现 1 同源） | 期末四轴 | 中 | 📝 待立项 |
| F-65 | `mergeFreshList`/`settleTurn` 参数面膨胀（settleTurn 11 字段），重生成顶替语义复用通用结算路径（id 匹配 / anchor 定位 / 位置式三策略叠加 + replaceId），Repeated Switches / Data Clumps 候选 | 期末四轴 | 中 | 📝 待立项 |
| F-66 | `mergeFreshList` 中 `messageId === replaceId`（服务端复用旧回复 id）时幂等检查先于原位替换，新内容被吞掉、旧回复残留（后端当前每次重生成签发新 message_id，不触发） | 波5 增量审核（Falsify 轴） | 中 | 📝 待立项 |
| F-67 | `renderErrorBar` 的 `data-conv` 选择器对 conversationId 裸插值——含引号/`]` id 抛 SyntaxError 抑制错误条（属性写入侧 `String()` 归一、选择器侧未归一，不对称；当前 id 为 DB 数值不可达） | 波1 增量审核（期末复证） | 低 | 📝 待立项 |
| F-68 | F-60 分支 guard `messageId != null && content` 在 `content===''` 时短路，stale 空回复被静默丢弃（与 fresh 分支渲染空回复行为不一致） | 波5 增量审核（Falsify 轴） | 低 | 📝 待立项 |
| F-69 | `locateAndHighlight` 无匹配前 `querySelector` 拼接 messageId 未转义（含引号/畸形 id 抛 SyntaxError；id 为 DB 数值不可达，波前既有） | 波2 增量审核（Falsify 轴） | 低 | 📝 待立项 |
| F-70 | `openModelSwitch` 的 state 就地更新 + `renderChatHeader` 仍在 save try 内，二者抛错会误标「切换模型失败」并跳过列表刷新（波前既有结构；F-53 已把 refresh 移出 try，残余为保存侧） | 波3 增量审核（Falsify 轴） | 低 | 📝 待立项 |
| F-71 | `credentialWarnReason` 对未知 `credentialsProtocol` 值 fail-open（静默保存不提示；spec 声明三态为唯一事实来源，违反不变式） | 波3 增量审核（Falsify 轴） | 低 | 📝 待立项 |
| F-72 | `cleanupStaleInFlight` 在 `for...of` 迭代中删除 Set 元素（ECMAScript 对纯删除安全，未来并发 re-add 行为未定义，防御性注释） | 期末四轴 | 低 | 📝 待立项 |
| F-73 | `.gg-config-warning-nav` 琥珀链接在 light 主题对比度约 3:1（< WCAG AA 4.5:1；视觉超出 F-63「中性命名」票据意图，warning 色语义合理） | 波2 增量审核（Falsify 轴） | 低 | 📝 待立项 |

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

#### F-49~F-63 消费子批（2026-08-26，全自动档 13 做 2 关，10 工单 5 波，期末四轴 0 阻断）

> 处置详情：13 项消费（F-50/51/52/53/54/55/56/57/58/59/60/62/63 各对应 TICKETS 归档工单 01-10）；2 项复核关闭（F-49：`error-bar.js:67 String(message)` 上游唯一调用方 `chat.js:renderSendError` 恒传字符串，Speculative 不可达；F-61：highlightTimer 定时器触发即自置 null、约 3s 自愈，零用户可见影响）。

| 编号 | 遗留项 | 来源 | 强度 | 处置 |
|------|--------|------|------|------|
| F-49 | `error-bar.js:67` `String(message)` 对可抛 `toString()` 的 message 会抛 TypeError | W1 增量审核 | Speculative | ❌ 复核关闭（2026-08-26：git grep 复核唯一调用方恒传字符串，上游不可达） |
| F-50 | 流式多 tab 并发出错时错误条渲染到共享 `.chat-main` 区域互相覆盖 | W1 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-05 错误条会话隔离 `data-conv`，跨会话并存） |
| F-51 | `surfaceError` 置于 `render()` 之后，渲染抛错吞错误条 | W1 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-03 surfaceError 前置 render） |
| F-52 | 搜索跳转陈旧 messageId 无匹配早退不滚动 | W2 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-06 无匹配回落 scrollToBottom，产品决策） |
| F-53 | 模型切换刷新失败被误记「切换模型失败」 | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-07 保存/刷新语义分离独立日志） |
| F-54 | 凭证确认不对称（openai 态切 claude 无提示） | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-07 credentialWarnReason 对称化，产品决策） |
| F-55 | 生成器凭证预检 `.then` 无提交态守卫（竞态） | W3 增量审核 | Worth exploring | ✅ 已修（2026-08-26：P-04 `if (generating) return` 守卫） |
| F-56 | `anthropic>=0.40.0` 无上界，1.x 移除 temperature 参数 | T6 实现发现 | Worth exploring | ✅ 已修（2026-08-26：P-01 SDK 调用不再传 temperature + 契约锁；运行时 .venv 实测 anthropic 1.0.0 创 create/stream 均无 temperature，适配为当前阻断修复；系统 python 0.116.0 测量属另一环境） |
| F-57 | regenerate 在途未阻并发流式发送（双请求） | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-08 handleSend 统一补查 nonStreamingInFlight） |
| F-58 | regenerate settleTurn 失败 anchor=null 尾部追加破坏顶替语义 | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-09 replaceId 原位替换） |
| F-59 | thinking 指示器未按 convId 隔离（finally 无条件移除） | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-08 `data-conv-id` + removeThinkingIndicator 定向移除） |
| F-60 | 重生成 stale revision 时 mergeFreshList 静默丢弃 | W4 增量审核 | Worth exploring | ✅ 已修（2026-08-26：S-09 stale+anchor null 按 messageId 写回或 render:true） |
| F-61 | 重生成 re-render 不清 T2 高亮定时器（自愈） | W4 增量审核 | Worth exploring | ❌ 复核关闭（2026-08-26：定时器触发即自置 null，约 3s 自愈，零用户可见影响） |
| F-62 | `chat.py:328-339` regenerate 重复 `except LLMError` 死代码 | 期末四轴 | Worth exploring | ✅ 已修（2026-08-26：P-02 删除不可达分支，行为零变化） |
| F-63 | 生成器复用模拟器专属 `SEL_NAV_SETTINGS` 选择器（命名错位） | 期末四轴 | Worth exploring | ✅ 已修（2026-08-26：S-10 生成器自有 `SEL_GG_WARNING_NAV`，key-injector 侧不动） |

### 2026-08-25（全量审查批次）

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| B2 | manifest 条目级字段不做校验（条目非 dict / 字段缺失等形态）复核维持关闭 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭（2026-08-25：系 simulator_manifest.py `_read_manifest_or_rebuild` docstring 文档化定版——损坏口径经 F-8/F-15 两次范围决策收敛，「条目级字段不做校验，范围收敛」（simulator_manifest.py:89-96）；原子写保证正常运行不产生此类损坏，需手工损坏 manifest 才触发；复核维持关闭） |
