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

> 当前 24 项待立项（F-23~F-46：架构深化批次波 1/2/3 增量审核 + 期末四轴发现 + 全量审查，2026-08-25~26）。

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-23 | CODE_WIKI.md 的 `tests_total:total` 标记漂移 691→1740（pytest 691 + Vitest 979 + cargo 70 三项之和），波 1 doc_sync 在纯 pytest 环境更新，缺少 vitest/cargo 渠道导致 grand_total 仅算 pytest；下个全渠道环境跑 doc_sync 即自动修复 | 波 1 增量审核（Falsify 轴） | Strong | 📝 待立项 |
| F-24 | CODE_WIKI.md §4.14（chat.py 职责行）仍写「错误响应统一通道（`chat_error_response` / `llm_error_response`，ARC10 T-03 收口）」，迁移后 `llm_error_response` 实体在 error_mapping.py §4.19 已更新，但 §4.14 职责叙述陈旧 | 波 1 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-25 | `error_mapping.py:117` `llm_error_response` provider 含前导空格时输出文案带前导空格（`"  OpenAI  "` → `"  OpenAI   API Key 无效…"`）；迁移前后行为逐字一致（非回归），docstring 已声明「按构造消除前导空格」由调用方负责，但函数现已成为 api/errors.py 与 chat.py 共用入口，未来若有调用方传入未清理 provider 会破坏「无前导空格」契约 | 波 1 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-26 | `test_error_handler.py:146` 类 docstring「LLM 异常族：经 services/chat.py::chat_error_response 映射」——实际测试直调 `llm_error_handler`，handler 现已直接委托 error_mapping；注释陈旧但测试逻辑正确 | 波 1 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-27 | `test_error_mapping_export.py` 文件末尾无换行符（末行 `assert "def llm_error_response" not in self._chat_source()` 缺 `\n`），不符合 PEP 8 换行约定 | 波 1 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-28 | simulator_store.py / simulator_manifest.py / simulator_import.py 三个文件 git blob 末尾缺失换行符（拆分前单体以 `))\n` 结尾、拆分后 `simulator_store.py` 以 `return True` 无换行、两新文件同样缺） | 波 2 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-29 | `simulator_store.py:21` docstring G4 约束 stdlib 依赖清单写「os/pathlib/shutil」，模块实际 import 为 `logging/shutil/pathlib`（`os` 未导入，docstring 与代码不一致） | 波 2 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-30 | `simulator_import.py:28,30` `json` 与 `os` import 后全模块零使用（AST 扫描确认），docstring G4 清单却把 json/os 列为依赖——拆分时整体拷贝遗留，import 表面与行为不符 | 波 2 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-31 | `simulator_import.py:109-116` `_filename_limit()` 每次调用函数级重新 import `simulator_store` 读取 `_MAX_FILENAME_BYTES`——常量归属（store）与消费方（import）跨模块，绑定至测试 monkeypatch 命名空间；当前正确且锚三线有效，但属「测试耦合驱动代码组织」的软约束 | 波 2 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-32 | `simulator_import.py:60-61` `__all__` 含 `read_manifest`/`write_manifest`（模块级 import 仅作 re-export，模块内零使用）——simulator_import 公开面携带它不实现的 manifest 写函数，形成第二网关；功能正确（与 simulator_manifest 双源可达同一对象），仅表面设计冗余 | 波 2 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-33 | `simulator_import.py:366-369` `import_game` 的 precomputed 路径对 `ScanResult` 字段无校验：`game_type` 可为任意字符串（非 "ai"/"local"）、`config` 可与 `game_type` 矛盾、`warnings` 可为 `None` 或非 `list`。当前生成路径不会产生这些值（`scan_generated_html` 保证有效），但 `import_game` 是公共 API，`precomputed_scan` 参数信任调用方提供正确值 | 波 3 增量审核（Falsify 轴） | Worth exploring | 📝 待立项 |
| F-34 | `game_generator.py:286` `validate_generated_html` 循环中通过函数对象身份比较（`if check is _check_security`）特殊处理检查 5；若重构（重命名/提取列表到变量/动态顺序）则静默失效，`_check_security` 将收到 `html` 单参数而非 `(html, precomputed_warnings)`，导致退化为回扫（双重扫描再现） | 波 3 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-35 | `game_generator.py:302-312` `scan_generated_html`（含 `ScanResult`）被导出到 `__all__`，扩展了模块公共 API 表面。该函数仅被 `generate_game` 内部调用（1 处），外部调用方依赖此函数后未来重构时有兼容成本 | 波 3 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-36 | `game_generator.py:522-528` `generate_game` 中 `scan_generated_html` 的扫描结果在 `validate_generated_html` 和 `_persist_generated_game` 之间以 `precomputed_scan` 参数传递；若校验失败（`errors` 非空），`scan` 结果被丢弃但不落盘，每次重试（上限 3 次）都重新扫描，但 LLM 回复 HTML 较大时影响可忽略 | 波 3 增量审核（Falsify 轴） | Speculative | 📝 待立项 |
| F-37 | `conversation.py:16` + `message.py:15` 双向模块级循环 import（T-07 方案 D 副作用）——conversation 模块级 import message，message 模块级 import conversation。Python 属性访问延迟到函数体执行实测通过，但任一模块添加模块级属性访问会触发 `AttributeError: partially initialized module`；静态分析器会报告双向循环依赖 | 期末四轴（Standards / Falsify / Architecture 三联） | Worth exploring | 📝 待立项 |
| F-38 | simulator_store 兼容 shim 私有名跨模块 + 循环 import 函数级补丁（T-02 拆分遗留双软约束）：①`simulator_store.py:38,52` 顶层 re-export shim 携带 `_existing_ids` / `_read_manifest_or_rebuild` 私有名（注释声明「回归锚测试直接访问，非 `__all__` 但保持模块属性」，测试 monkeypatch 命名空间绑定 store）；②循环 import 函数级补丁三处——`simulator_manifest.py:49,119` / `simulator_import.py:130` 函数体内延迟 import 规避模块级循环引用（store↔manifest、manifest↔import 双向边仍在）。当前正确但属「测试耦合驱动代码组织」的软约束（与 F-31 同族） | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-39 | `_current_write_manifest()` 测试耦合间接层：`simulator_manifest.py:42` 定义、`:83/:108` 调用点按调用期从 simulator_store 重新解析 write_manifest——仅为让回归锚 monkeypatch `simulator_store.write_manifest` 生效；功能正确但属测试耦合驱动代码组织的软约束（与 F-31/F-38 同族） | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-40 | game_generator `err.field` if/elif 级联：`game_generator.py:581-591` `_build_suggestion` 按 field 六分支级联（structure/template/cfg/syntax/data/security）——新增检查项须同步扩展级联，未知 field 静默跳过不产出建议、全部未知时落通用兜底文案，无编译期/测试期防漏信号 | 2026-08-25 全量审查 | Speculative | 📝 待立项 |
| F-41 | 局部 `ValidationError` 命名遮蔽 pydantic：`game_generator.py:64` 自定义 `ValidationError` dataclass 与 pydantic 同名类型生态冲突（本模块未 import pydantic 无运行时遮蔽，但阅读者对 ValidationError 的第一联想是 pydantic 校验异常，存在语义误读风险） | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-42 | setting.py `_CRED_SLOTS` provider 键知识外泄：`setting.py:64` `_CRED_SLOTS = ("claude", "openai")` 将协议槽位键名单硬编码在本模块，同文件 :58 注释声明 provider 知识已收敛于 provider_registry.py「本模块仅消费不派生」——该常量构成第二事实源，新增协议槽位需两处同步 | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-43 | 前端 11 模块缺 `__all__` 导出声明清单（api.js / app.js / state.js / utils.js / components/modal.js / components/model-selector.js / components/confirm-dialog.js / components/export-dialog.js / components/character-form.js / components/character-wizard.js / data/character-templates.js）——兄弟模块（cascade.js / chat.js / list-views.js 等）已用 `__all__` 声明导出面，此 11 文件导出面为 ESM 具名 export 隐式形态，grep 无单一权威清单可机械校验 | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-44 | game_generator docstring 协议表面(3) 与 `__all__`(5) 不一致：`game_generator.py:12` 列 3 符号（MAX_RETRIES / generate_game / validate_generated_html），`:38` `__all__` 实为 5 符号（另含 ScanResult / scan_generated_html，后者即 F-35 所述公共面扩张）——文档与代码表面漂移 | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-45 | O2 一致性缺口（**明确不在本批修复范围**）：chat 流式中途出错时 DB 已落库部分生成内容而 UI 渲染错误气泡——`chat.py:184` `stream_reply` 错误帧产出后 finally 兜底仍保存 partial content（:247-249 错误帧、:254 起兜底落库；docstring「兜底……尽力保存已生成部分」背书行为），前端 stream-session.js 普通错误写回 phase 'error' 并渲染错误气泡（:308-317）；下次加载历史时已存内容重现，与错误气泡呈现不一致 | 2026-08-25 全量审查 | Worth exploring | 📝 待立项 |
| F-46 | 空串 token-only 流的前端占位残留：provider 只产空串 token 时后端守卫正确不落库（按 full_content 判空），但仍发 `content:""` token 帧——前端 stream-session.js:258-270 onToken("") 在 tab 缓存建 `{content:'', streaming:true}` 占位，done(null) 空内容路径不清该占位，空气泡残留至下次重载/结算；纯前端化妆级问题，后端零污染 | 期末四轴 Falsify（2026-08-26） | Speculative | 📝 待立项 |

## 技术债处置记录

> 按处置日期分节，滚动保留最近 2 节；更早的节由 git 历史归档（`git log -p -- TECH_DEBT.md`）。

### 2026-08-25（全量审查批次）

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| B2 | manifest 条目级字段不做校验（条目非 dict / 字段缺失等形态）复核维持关闭 | 2026-08-25 全量审查 | Speculative | ❌ 复核关闭（2026-08-25：系 simulator_manifest.py `_read_manifest_or_rebuild` docstring 文档化定版——损坏口径经 F-8/F-15 两次范围决策收敛，「条目级字段不做校验，范围收敛」（simulator_manifest.py:89-96）；原子写保证正常运行不产生此类损坏，需手工损坏 manifest 才触发；复核维持关闭） |

### 2026-08-19（技术债批次 2/3 + 期末四轴）

| 编号 | 遗留项 | 来源 | 强度 | 状态 |
|------|--------|------|------|------|
| F-5 | 仙途/暮色女巫v2 移动断点（≤768px）下 `#right-panel` 原 `88vw/max-width:340px`（非 important，同特异性）被覆盖层 `300px` 压过——与游戏移动意图约 300 vs 330px 轻微偏离，桌面 ≥1280 视口不受影响，明确接受 | 期末四轴 Falsify F4 | Speculative | ❌ 复核关闭（2026-08-19：simulator-pc.css:120 分区 4 `#right-panel,#side-panel{width:300px}` 现状仍成立；期末四轴已明确接受） |
| F-6 | 模拟器配置面板功能细节（vision 终检）：API Key 无明文/隐藏切换图标、部分按钮无禁用态/间距过近易误触——游戏自身设计/功能范畴，覆盖层全局干预会破坏各游戏设计，维持现状 | 用户反馈批次 vision 终检 | Speculative | ❌ 复核关闭（2026-08-19：覆盖层 simulator-pc.css 仅排版/可读性干预，无按钮禁用态/间距/API Key 可见性等功能类规则，游戏自身设计范畴，维持现状） |
| F-7 | `VARS_FAMILY`（simulator-adapt.js:57）漏 B 类组 5 成员 `--text2/--text3`（神明v3 体系） | 期末四轴 Falsify F1 | Worth exploring | ✅ 已修（2026-08-19：VARS_FAMILY 补两成员 + 成员完整性回归断言，22 款核对复跑全绿） |
| F-8 | `_read_manifest_or_rebuild` 自愈未覆盖 `simulators` 非 list → TypeError/AttributeError 500 | 期末四轴 Falsify F2 | Speculative | ✅ 已修（2026-08-19：isinstance 结构校验并入自愈，先红后绿，commit 412b2d7 merge 500b1d3） |
| F-9 | `sanitize_filename` 未剔除 Windows 保留设备名与 >255 字节文件名 → 落盘 OSError 500 | 期末四轴 Falsify F3 | Speculative | ✅ 已修（2026-08-19：保留设备名 stem 加 `_` 前缀 + UTF-8 255 字节整字符截断，先红后绿；F-17 修订：上限 255→120 字节——Windows MAX_PATH 实测，commit 987ddeb） |
| F-10 | `docs/architecture.md` 信任边界小节未同步用户导入功能 | 期末四轴 Spec S1 | Speculative | ✅ 已修（2026-08-19 Neat 收尾：架构文档同步） |
| F-11 | simulator-adapt.js docstring 协议表面 6 符号 vs `__all__` 8 符号 + TICKETS 归档 HEAD stale | 期末四轴 Standards N1/N2 | Speculative | ✅ 已修（2026-08-19 Neat 收尾） |
| F-12 | `src-tauri/src/lib.rs` readiness_loop 就绪终态发布顺序竞态（先置标志后写文件） | T-01/T-02 批次遥测 | Worth exploring | ✅ 已修（2026-08-19：先落盘再置标志，复现循环 30 次归零，commit 7f93af2 merge 66001a8） |
| F-13 | `sanitize_filename` 设备名判定整串精确匹配，双扩展形态绕过（`con.txt.html`） | 期末四轴 Falsify 1 | Speculative | ✅ 已修（2026-08-19：判定改首点前组件，先红后绿 +5 用例，commit d295c76 merge 3111036） |
| F-14 | `next_available_filename` 拼 `-N` 后缀顶破 NAME_MAX（250 字节 stem + `-2` = 257 > 255） | 期末四轴 Falsify 2 | Speculative | ✅ 已修（2026-08-19：拼后缀前按余量字节截断，提取 `_truncate_utf8_bytes` 复用，先红后绿 +2 用例，commit 56e7454 merge 3111036） |
| F-15 | manifest 损坏形态补集：OSError 族未入 except 元组（目录/不可读形态） | 期末四轴 Falsify 3/4 | Speculative | ✅ 已修（2026-08-19：except 并入 OSError 族，先红后绿 +1 用例，commit b431974 merge 3111036；条目非 dict 维持 F-8 收敛声明 ❌ 不修） |
| F-16 | `simulators: []` 空 list 合法不重建——磁盘有 .html 但清单空时条目永不出现 | 期末四轴 Falsify 5 | Speculative | ❌ 复核关闭（2026-08-19：F-8 验收锚「空 list 合法不重建」已审结，克制原则维持） |
| F-17 | Windows MAX_PATH 实测：255 字节组件名在深路径数据目录下仍落盘失败 | F-9 批次实测 | Speculative | ✅ 已修（2026-08-19：`_MAX_FILENAME_BYTES` 255→120，先红后绿 +3 用例，commit 987ddeb merge 3111036） |
| F-18 | 批次归档流程项——F-13/F-14/F-15/F-17 移入已完成、F-9 注记补修订说明 | 期末四轴 Spec | Speculative | ✅ 已修（2026-08-19：随批次归档 commit 处理） |
| F-19 | `_WINDOWS_RESERVED_NAMES` 常量注释仍标「F-9 定版——精确匹配才拦截」，F-13 已改首点前组件语义 | 期末四轴 Standards | Speculative | ✅ 已修（2026-08-19：注释补 F-13 修订注记） |
| F-20 | F-13 票面实证基础 Win11 26100 不复现（子目录设备名可正常落盘） | 期末四轴 Falsify 信息性 | Speculative | ❌ 复核关闭（2026-08-19 批次 3：实测注记三处闭环，F-13 修复仍正确防住裸 nul 静默丢弃，零代码合理） |
| F-21 | `next_available_filename` 直调空 stem（`.html`）冲突时产 `-2.html` 畸形名 | 期末四轴 Falsify 提示级 | Speculative | ✅ 已修（2026-08-19 批次 3：docstring 补入参契约声明，零行为变化，commit 08e860f merge 2fb25df） |
| F-22 | 批次 3 归档流程项——F-20/F-21 状态流转、头部计数清零、DEV_LOG 滚动摘要 | 期末四轴 Standards N2 | Speculative | ✅ 已修（2026-08-19：随批次 3 归档 commit 处理，技术债区清零） |
