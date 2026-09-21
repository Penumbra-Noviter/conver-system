# Conver System — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TO-TICKETS.md](TO-TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）

## 滚动机制（2026-09-21 固化）

- **排序**：一律按日期倒序（最新在前）；同日多批次按时间序
- **保留**：最近 10 个批次节保留完整细节；更早的折叠为「历史归档索引」表格（每节一行：日期/批次名/一句话摘要）
- **溯源**：被折叠的批次节原文由 git 历史承担——`git log -p -- DEV_LOG.md` 可追溯任意节
- **防膨胀**：完整节超过 10 节时最旧的折叠入索引；索引行数上限 100，超限删最旧行

---

## 桌面打包新程序 + preset_dialogues 存量 NULL 500 修复（2026-09-21 — 用户指令直接交付，无工单）

- **来源**：用户指令「打包新程序」。两处现状核对：(1) dist/conver_backend/conver_backend.exe 为 2026-08-28 构建，**不含九月全部后端功能**（五批对标 WL/MS/BR/CG/MD、mod-cg-wiring、消息编辑/重发、arch-deepening、F-152~155）；v1.1.0 GitHub Release 挂载的 exe（11075584B，与 dist 同字节）同样跑 8-28 后端；(2) `Assert-Or-Build-BackendExe` 只认「缺失」不认「过期」（Test-Path 即返回），旧后端包被静默复用——本次先重建后端 exe 再走全链。
- **打包**：build-backend.ps1 重建 dist/conver_backend/conver_backend.exe（16.3MB，onedir 含随包前端运行子集）→ build-desktop.ps1 -SkipInstaller 全链（cargo test 70 → pytest 1355+1skip → vitest 1472 → tauri build --no-bundle 53.7s → dist 壳 10.6MB → 冒烟）。
- **冒烟暴露缺陷**：验收 5 GET /api/characters 500 —— `ResponseValidationError: preset_dialogues Input should be a valid list, input: None`。根因：存量库字符行 preset_dialogues 为 SQL NULL（自愈迁移 `_ensure_character_preset_dialogue_column` 补 JSON 可空列无回填；`default=list` 仅字段缺席生效，ORM 读回显式 None）；响应 schema `CharacterBase.preset_dialogues: list[PresetDialogue]`（default_factory）对显式 None 验不过 → FastAPI serialize_response 500。**真实升级路径缺陷**：旧数据目录用户升级新包即角色列表全挂。
- **修复**（ea3c515）：`CharacterBase.preset_dialogues` 增 `mode="before"` 验证器 `_coerce_none_preset_dialogues`（None→[]）。实证三态：响应序列化（list/get，from_attributes 读 NULL→[]）、create 显式 null→[]、update 显式 null→[]（Pydantic v2 子类重声明字段继承基类验证器，此前显式 null 会 NULL 写库制造同类隐患）；update 省略字段→None 不触发（exclude_unset 跳过），partial update 语义零变更。回归测试 test_character_schema.py（API 层 TestClient 全路径 + SQL 强制列 NULL 模拟存量行 + expire_all 防 identity map 掩盖，先红后绿）。
- **验证链**：pytest 1355+1skip→1356+1skip（+1 回归零回归）+ doc_sync 零漂移（CODE_WIKI §5.1 登记新测试文件 + 计数刷新 2899/1357=passed+skip 口径）+ 重建后端 exe 后重跑冒烟：验收 4a/4b/5/6 + 阻断 2 全 PASS（原 500 的验收 5 现 HTTP 200）。cargo/vitest 本轮零改动不重跑（变更仅后端 Python）。
- **落债**：F-156（后端 exe 过期复用缺口，Worth exploring）+ F-157（CharacterUpdate 其余 list/dict 字段 tags/alternate_greetings/creator_notes/extensions 显式 null 同类缺口，Speculative）入 TECH_DEBT 候选区。

---

## 技术债消费批次 F-152~F-155（2026-09-15 — 3 做 1 关，轻量档 4 项主会话直做）

- **来源**：用户指令「消费候选区技术债」（arch-deepening 期末四轴落债 4 项：F-152/F-153/F-155 Speculative + F-154 Worth exploring）。逐项 git grep 复核现状均成立后拍板 3 做 1 关——补契约锁 + 文档注记，零行为变更。
- **3 做**：F-152 build_world_injection 契约锁 ×2（test_lorebook_engine.py 补 `test_build_world_injection_empty_activated` 三空键 + `test_build_world_injection_source_by_id_unknown_value` 未知标签回落 SOURCE_WORLD）；F-153 build_message_list `preset_dialogue=None` 直传零注入契约锁 ×1（test_preset_dialogue_injection.py 补 `test_none_preset_zero_injection`——falsy 短路与空串/纯空白同语义，生产调用方恒 `or ""` 归一）；F-154 `CharacterData.from_orm` docstring 注记（`object` 而非 `Character` 是有意保持 prompt.py 零 ORM 依赖，勿改回破坏纯函数层契约）。
- **1 关（F-155）**：世界书注入 `logger.debug` 可观测性扩展——开发级日志非在线 prompt 契约，spec「输出逐字节不变」不覆盖，无 spec 追认载体；本批证据文件与 arch-deepening DEV_LOG 节已记录。
- **验证链**：pytest 1352+1skip→1355+1skip（+3 契约锁）+ 受影响模块 44 passed | doc_sync + pool_cleanup_check 全合规 | 技术债候选区 4→0 清零（F-155 入复核关闭表）。
- **非阻断落债**：无（候选区清零）。

---

## 架构深化批次 arch-deepening（2026-09-15 — 2 工单标准档串行链，prompt 组装链重构）

- **来源**：用户继架构全库扫描（/improve-codebase-architecture 产出 7 候选 F-145~F-151 + Top recommendation）后走 project-kickoff 全自动档续接（handoff-arch-deepening-20260914）。Grilling 增量审拍板 4 做 3 关。核心结论：`_assemble` 是真深模块（deletion test 通过），参数膨胀只是症状，病根在上游注入链编排重复；`narrative_style` 显式透传 vs `preset_dialogue` 隐式读 ORM 快照的两参数数据流不对称（预设不是 build_message_list 形参，内部隐式读 conversation.preset_dialogue）。
- **工单 01 注入链 seam 归位（ab587ed，F-145+F-146）**：新增 `chat._build_tagged_injection(db, character, history, current_input, user_name)` 单一编排 seam 收编「_lorebook_world_injection → _mod_prompt_injection → _merge_injections」三步；assemble_chat_context 与 build_prompt_debug 均改调，删两处内联复制；`lorebook_engine.build_world_injection` 返回类型改 `dict[str, list[InjectedSegment]]` + 新增可选 `source_by_id: dict[int, str] | None = None`（None/缺省键→SOURCE_WORLD，值=="auto"→SOURCE_MEMORY）；`LorebookEntryData` 零 source 契约保持（来源经 entry.id 反查注入）；删 `chat._build_tagged_world_injection` / `_WORLD_POSITION_KEYS`；`_WORLD_BLOCK_KEYS` 保留；`mods._REGION_KEYS` 不收敛。
- **工单 02 组装入口收口（a807363，F-147+F-148）**：`CharacterData.from_orm(character)` 类方法成为唯一 ORM→纯数据投影入口（PROMPT_FIELDS 通配 + prompt_mode/expert_prompt 补位 + None→`CharacterData(name="")` 空角色），删 `chat._character_data` 与 message 内联构造；`build_message_list` 增 `preset_dialogue: str = ""` 显式形参（置于 narrative_style 后），不再隐式读 ORM，快照读取责任上移 chat 层统一（普通/重生成/调试三路径显式传 `conv.preset_dialogue or ""`）。
- **验证链**：pytest 1349+1skip→1352+1skip（+3：from_orm 3 例 + chat 层快照语义 1 例 − message 层删 1 例）+ cargo 70 零改动 | 期末四轴「通过」0 Critical 0 High（Standards 0 / Spec 2 警告：from_orm 签名 `object|None` 字面漂移（有意保持 prompt.py 零 ORM 依赖）+ debug 日志可观测性扩展 / Falsify 3 弱覆盖缺口：空激活集、未知 source 值、None 直传契约锁 / Architecture 0——两 seam 均真深化无伪深化）| 运行态冒烟：uvicorn + 隔离数据（DATABASE_URL/CONVER_DATA_DIR 指向 .scratch 目录）走 GET /api/conversations/1/prompt-debug，segments 全序 persona→scenario→narrative→[世界知识]→mes_example→预设 few-shot(source=character)→历史→user 正确，world+preset 注入零变更 | 全量 1352 passed 主会话独立复现（46.6s）| merge 43bb61f | doc_sync 12 标记刷新零漂移 | pool_cleanup_check 全合规。
- **过程遥测**：全自动档串行链（链长 2 ≤ 3 不主动重启）；工单 01 派遣「启动即失败」2 次（网关/模型层异常，无 usage 无内容、provider 多次切换），探路子智能体确认通道恢复后第 3 次（末次）派遣成功——重开预算 3 次用尽前命中，未升级人工裁决；「前次现场核查」未触发（前次无 worktree/分支残留，现场干净）；覆盖率口径修正（`--cov=backend.app.services.*`，工单原文 `app.services.*` 匹配不到——backend 是隐式命名空间包、PYTHONPATH 须指向项目根而非 backend 目录）；基线数字 1225 过时（实际 1352+1skip，doc_sync 已刷新）；编排文件 STATUS token 与 check-complete.py 契约格式不一致（表格单元格 vs 行首独立行）——按脚本契约修正编排文件（token 须行首）；冒烟种子脚本依次排掉四坑：exFAT write EISDIR（pwsh WriteAllText 降级）、PYTHONPATH 指向（命名空间包）、DATABASE_URL 须指向隔离库（默认相对 cwd 会污染开发库）、init_db() 前置（建表 + 自愈迁移）。
- **非阻断落债**：F-152~F-155（4 项，期末四轴，见 TECH_DEBT 候选区）。

---

## 叙述风格与预设对话批次 NPD（2026-09-14 — 7 工单标准档，角色对话降 AI 味）

- **来源**：用户对标 AI 风月「角色对话降 AI 味」，立项「叙述风格指令 Mod」+「预设对话」两项。两项 ADR 拍板：叙述风格=全局 settings 两键（非 built-in Mod，因 prompt Mod payload 锁 world 三块无法 emit 前缀 system 段）+ 默认启用 opt-out + `[叙述风格]` system 段注入 after_char 后（expert 亦注入）；预设对话=角色卡 `preset_dialogues: list[PresetDialogue]`（≤10，project-own 字段 conver_system 往返）+ 会话 `conversation.preset_dialogue` Text 快照列（创建时固化）+ 开局弹窗双选。
- **NPD-01 设置键**（e4404f5）：ALLOWED_KEYS 加 narrative_style_enabled/rules + NARRATIVE_STYLE_DEFAULT_RULES 反 AI 味清单 + 两访问器。
- **NPD-02 注入**（c960c6c）：prompt.py SOURCE_NARRATIVE + build_messages/build_messages_with_source 加 narrative_style 参数 + _assemble after_char 后注入 `[叙述风格]` system 段（空/纯空白零注入）；message/chat 接线。
- **NPD-03 设置 UI**（30bcdf2）：设置页叙述风格开关 + 规则编辑框（空占位提示，不复制后端默认常量）。
- **NPD-04 角色字段**（daa0981）：character.preset_dialogues JSON 列 + PresetDialogue 模型 + 归一化（None→[]/空字段过滤/超10截断/同名去重）+ conver_system 往返。
- **NPD-05 快照列**（3b225f0）：conversation.preset_dialogue Text 可空列 + 迁移 + ConversationCreate 固化 `data.preset_dialogue or None`（空串→null 不落伪值）。
- **NPD-06 few-shot 注入**（59d625a）：build_messages 加 preset_dialogue 参数 + _assemble mes_example 后、history 前经 parse_mes_example 注入（source=character）；message 读 conversation.preset_dialogue 快照（改卡不影响已建会话）+ chat 接线。
- **NPD-07 前端**（a766fdf）：character-submit buildCharacterPayload 加 preset_dialogues + 角色编辑列表 + 开局弹窗「开场白+预设对话」双选。
- **验证链**：pytest 1273+1skip→1348+1skip（+75）+ Vitest 1448→1472（+24）+ cargo 70 零改动 | 期末四轴 0 Critical/0 High | doc_sync 零漂移。
- **过程遥测**：标准档 3 波（波1 01+04+05 / 波2 02+03+07 / 波3 06）；波1 04 迁移缺口（character.preset_dialogues 迁移 + schema.sql 补列）波末修复 5c22d86；波2 spec 矛盾（ADR-1 默认启用 vs 01 工单缺省 False）波末修复 9493993——narrative_style_enabled 缺省改 True + build_message_list 改纯透传（查 setting 收拢到 chat._narrative_style）；波3 06 子代理电脑卡死中断（改动落盘但 `if False` 死代码致注入失效）主会话直修；code-review 子智能体 provider 配置故障（deepseek-v4-flash 未配置）连续失败，波末增量审核 + 期末四轴均主会话直做。
- **非阻断落债**：无（期末四轴 0 阻断，候选区维持清零）。

---

## 技术债消费批次 F-139~F-144（2026-09-14 — 1 做 4 关，轻量档 5 项主会话直做）

- **来源**：用户指令「消费技术债 F-139/F-140/F-142/F-143/F-144」（PD 批次期末四轴落债 6 项中除已关 F-141 外 5 项，均 Speculative）。逐项 git grep 复核现状后拍板 1 做 4 关。
- **1 做（commit 47b2eef）**：F-139 CharacterUpdate.prompt_mode/expert_prompt Optional[str]=None 但 ORM 列 nullable=False——`update_character` 的 `exclude_unset=True` 会把显式 null setattr 到 nullable=False 列触发 IntegrityError(500)（Falsify 红灯实证：`{"prompt_mode": null}` 返回 500）。修法：CharacterUpdate 加 `field_validator("name", "prompt_mode", "expert_prompt", mode="before")` 拒绝显式 null（省略字段走 validate_default=False 不触发，partial update 语义保持）；防复发断言 test_update_rejects_null_for_not_null_columns（三字段 422，先红后绿）。附带修复 name 同构缺口（name 同为 nullable=False 列，F-139 票面只报 prompt_mode/expert_prompt 漏了 name）。
- **4 关（复核关闭，理由见 TECH_DEBT.md 复核关闭表）**：F-140（row 经 btn.closest 定位且事件委托在 altList 上，row 必在 DOM 内，indexOf 不可能 -1，单线程无并发不可达）；F-142（build_messages 仅 ==expert 走 expert 分支、其余任意值安全回退 simple，改 Literal 需破坏 CharacterBase 单一来源或冒 CharacterResponse 序列化风险，纵深防御收益 < 成本）；F-143（有意识镜像——_character_data docstring 已声明同口径单一语义镜像，仅 2 实例提取 helper 收益 < 成本）；F-144（wizard state 跨步骤向导真源 vs form DOM 单表单真源，语境不同强行统一收益 < 成本）。
- **验证链**：pytest 1272+1skip→1273+1skip（+1 防复发断言）+ Vitest 1448 + cargo 70 零改动全绿 | doc_sync 刷新 5 标记（测试总数 +1 漂移修复）+ pool_cleanup_check 全合规 | 技术债候选区 5→0 清零 | 处置记录滚动到最近 2 节（删 09-10 节，git 历史兜底）。
- **非阻断落债**：无（候选区清零）。

---

## Prompt 打磨批次 PD（2026-09-14 — 6 工单标准档，预设开场白/Prompt Debug/专家模式）

- **来源**：用户对标 AI 风月「对话质量 / Prompt 工程」第二轮，选定三功能——预设开场白选择、Prompt Debug 面板、专家模式自由编辑 PROMPT。三 ADR 拍板：专家模式=新增 prompt_mode/expert_prompt 可逆字段；预设对话=复用 alternate_greetings 做开场白选择不加表；Prompt Debug=只读预览+来源标注。
- **PD-1 预设开场白后端**（7f9b849）：ConversationCreate.greeting + create_conversation 按 model_fields_set 四态分流（None/空串/显式/未传），未传零回归。
- **PD-5 专家模式后端**（0b85c4d）：prompt_mode/expert_prompt 两列 + _ensure_column 自愈迁移 + build_messages 专家分流（expert 单条替代 personality/scenario/post_history，世界书/mes_example/history/user 照旧）+ character_card conver_system 往返 + PROMPT_FIELDS ⊆ CHARACTER_V2_FIELDS 断言维持。
- **PD-2 预设开场白前端**（e2d4118）：备用开场白列表编辑（上限 10/去重）+ 新建对话开场白下拉（默认/备选/无开场白映射 greeting）。
- **PD-3 Prompt Debug 后端**（b90df29）：GET /api/conversations/{id}/prompt-debug + prompt.py 抽 _assemble 共享核心（build_messages 与 build_messages_with_source 共用，零变化契约成立）+ chat.py 注入链来源保留（character/world/memory/mod/history/user）。
- **PD-4/PD-6 前端**（3d55076/e03eefc）：Prompt Debug 只读面板（SOURCE_CLASS 单一映射表 + escapeHtml）+ 专家模式两态编辑（可逆切换/从当前字段生成/保存 payload）。
- **验证链**：pytest 1234+1skip→1272+1skip（+38）+ Vitest 1379→1448（+69）+ cargo 70 零改动 | 期末四轴 0 Critical/0 High（1 Medium F-141 + 3 Low F-142~144 落债）| doc_sync 零漂移 | 运行态冒烟（prompt-debug 端点 + expert 单条分流 + greeting override）全通。
- **过程遥测**：标准档 3 波（波1 PD-1+PD-5 / 波2 PD-2+PD-3 / 波3 PD-4+PD-6 各并行 2）；波2 两子代理空返回失败 1 次（并行峰值网关限流，重开成功）；「前次现场核查」重开机制实证有效；worktree 并行无冲突（6 工单文件范围互不相交）。
- **非阻断落债**：F-139~F-144（6 项，波末/期末审核，见 TECH_DEBT 候选区）。

---

## 采样参数扩展批次 SP（2026-09-14 — 3 工单小档，AI 风月对话质量对标）

- **来源**：用户对标 AI 风月「对话质量 / prompt 工程」维度，选定「采样参数扩展」（top_p / presence_penalty / frequency_penalty / max_tokens）。
- **实证约束**：anthropic 1.0.0 `messages.create` 参数表（inspect.signature）无 temperature/top_p/presence_penalty/frequency_penalty，仅 max_tokens 可用——采样参数仅 OpenAI 系生效，Claude 系保留对外签名但不透传 SDK（同 F-56 temperature 处理）。
- **SP-1 数据层**：Character 加 4 可空列（top_p/presence_penalty/frequency_penalty FLOAT + max_tokens INTEGER，NULL = 不覆盖 provider 默认）+ `_ensure_character_sampling_columns` 自愈迁移 + schema 4 字段（带 ge/le 边界）+ CHARACTER_V2_FIELDS 16→20 + character_card 往返保真（非 None 写 conver_system 命名空间、None 不落卡、非法值 clamp 回 None）。
- **SP-2 透传链**：BaseLLM/Claude/OpenAI 签名加 3 采样参数（默认 None）；OpenAI 经 `_optional_sampling_kwargs` 仅非 None 透传；Claude 不传 SDK；ChatContext 加 4 字段 + `_sampling_kwargs` 从上下文提取非 None 参数 + generate/stream 两路径 `**_sampling_kwargs(ctx)` 透传（None 不传 → 现有 mock 零改动）。
- **SP-3 前端**：character-submit 加 SAMPLING_SLIDERS 常量 + formatSampling + buildCharacterPayload 15 字段（top_p/presence/frequency 用 OpenAI API 默认 1/0/0，max_tokens 空/非法/越界 → null）；character-form + character-wizard 加 4 控件（3 滑块 + 1 数字输入）。
- **Falsify 直修**：max_tokens 原 truthy 判断在输入 'abc'/'0'/负数 时得 NaN/0/负（后端 422）——改 Number.isFinite + >=1 守卫，+1 契约锁。
- **验证链**：pytest 1225+1skip→1234+1skip（+9：test_character_sampling 4 + test_sampling_transmit 5）+ Vitest 1379→1380（+1 Falsify）+ cargo 70 零改动 | doc_sync 刷新 23 标记 + 手补 2 新测试 §5 标记 | pool_cleanup_check 通过 | 技术债候选区无新增。

---

## 大世界方向关闭（2026-09-14 — 文档清理，代码零改动）

- **决策**：用户拍板关闭「角色对话 → 世界模拟平台」大版本设想，落盘 CONSENSUS §1「方向边界」。
- **移除**：删除 `docs/world-simulation-exploration.md`（探索文档，大世界方向唯一载体）；清理 CONSENSUS（U11 引用 + 方向边界）/ TICKETS（批次 WL 表头）/ architecture（模拟器信任边界 U11 引用）/ spec（批次 WL 标题）/ external-benchmark（尾段引用）/ DEV_LOG（427/731 文件名引用）对「大世界方向」的引用。
- **保留**：角色级世界书（lorebook + 记忆宫殿，WL 批次）作为角色对话功能保留——CODE_WIKI / TICKETS 归档 / DEV_LOG 的「世界书」描述与代码（lorebook/lorebook_engine/memory_palace）零改动。
- **代码零改动**：大世界（World 实体/玩法层/玩家状态/玩法包）从未落地代码（models 无 world.py、后端/前端 grep 零命中），无需迁移。

---

## 技术债消费批次 F-130~F-138（2026-09-14 — 7 做 2 关，轻量档 9 项主会话直做）

- **来源**：用户指令「消费技术债 F-130~138」（消息编辑重发期末四轴落债 9 项）。逐项 git grep 复核现状后拍板 7 做 2 关。
- **7 做（commit 45a67aa）**：
  - F-130（Worth exploring）`require_message` 零行为透传别名 + 目标解析三查冗余——`edit_and_resend` 去 conversation_id 参数、`_resolve_edit_target` 简化只传 message_id 派生 conversation_id、删 `require_message` 公开别名 + 路由直调（目标解析知识收口单一入口）；连带删 2 防御测试（跨会话/会话不存在——防御对象「调用方传错 conversation_id」随参数移除消失）。
  - F-131（Worth exploring）级联 Seam 依赖全局 PRAGMA + bulk delete identity map 残留——`delete_message`/`edit_and_resend` 两处 `synchronize_session=False`→`'fetch'` 消除身份映射残留；防复发断言 test_delete_user_syncs_identity_map（db.get 返回 None）；PRAGMA 依赖文档化为 SQLite 连接级固有（非模块可局部化）。
  - F-132（Worth exploring）按钮 css 悬停显示不统一——style.css 操作按钮组（regen/cont/branch/edit/delete）加 opacity 0→hover 0.6→自身 1 统一 hover 显示 + 图标按钮样式对齐 copy。
  - F-134（Speculative）autoflush 分歧——conftest sessionmaker 加 `autoflush=False` 对齐生产 SessionLocal（测试复现生产 flush 时序）。
  - F-135（Speculative）promptMessageEdit/promptImageDescription 同型重复——提取 chat.js 私有 `promptTextarea` helper 收敛，DOM id/行为逐字保持。
  - F-137（Speculative）全空白 content 穿过校验——`EditMessageRequest` 加 field_validator strip 后拒绝全空白；防复发断言 test_edit_blank_content_422。
  - F-138（Speculative）error_mapping 400 行膨胀——提取模块常量 `_HTTP_400_DOMAIN_ERRORS` 多行元组。
- **2 关（复核关闭，理由见 TECH_DEBT.md 复核关闭表）**：F-133（乐观 UI 既有模式 + 服务端 404 兜底）、F-136（三解析函数独立领域语义，仅 3 实例抽象收益 < 成本）。
- **验证链**：pytest 1225+1skip（净 0：+2 防复发断言 −2 归属/会话防御测试）+ Vitest 1379 + cargo 70 零回退全绿 | doc_sync 刷新 8 标记 + pool_cleanup_check 全合规 | 技术债候选区 9→0 清零 | 复核关闭表滚动保留最近 4 批（08 月 15 条整批删除）。
- **非阻断落债**：无（候选区清零）。

---

## 消息编辑重发 + 删除单条消息批次（2026-09-14 — 3 工单小档，对标 AI 风月消息级操作）

- **来源**：用户对标 AI 风月「把角色对话打磨更精细」（放弃世界模拟大版本——World 实体 + 多角色 token 成本顾虑），gap 分析后选定「消息编辑重发 + 删除单条消息」（对标档案 §3.4 消息级操作）。
- **Grilling 共识**：编辑重发仅 user 消息（就地替换 content + 物理截断后续 + 重新生成，复用 regenerate 生成逻辑）；删除单条消息角色感知（删 user 截断后续 / 删 assistant 仅删该条 + swipes 级联）；破坏性操作前端二次确认；编辑 assistant 后置。
- **交付**（3 工单小档，串行 lane + 前端独立 worktree）：
  - T1（a365b81）：service 层三 seam——`update_message`（就地替换，commit=False 供原子）/ `delete_message`（USER id>=目标截断 / ASSISTANT 仅删该条 + bump）/ `edit_and_resend`（_resolve_edit_target → update_message → assemble_chat_context → 生成 → 截断后续 → create_message 单 commit 结算，LLM 失败 session close 回滚零落库）+ `InvalidEditTargetError` 挂 400。
  - T2（3bcd80f）：`EditMessageRequest`（min_length=1）+ PUT/DELETE 端点；范围偏差——spec 跨工单不一致（edit_and_resend 需 conversation_id 但端点无此参数），加 `require_message` 公开别名（_require_message 转发，命名对齐 require_conversation）让路由保持纯 HTTP 映射，接受（记录警告）。
  - T3（8269f1e）：api.js messages.edit/delete + messageBubbleHtml 按钮（edit 仅 user / delete user+assistant / streaming 不渲染）+ editMessage（settleTurn 重载）/ deleteMessage（简单重载）+ promptMessageEdit。
- **验证链**：pytest 1200+1skip→1223+1skip（+23：17 service + 6 端点）+ Vitest 1351→1378（+27）+ cargo 70 零改动 | doc_sync 零漂移 | 期末四轴 0 Critical/0 HIGH（13 发现：2 MEDIUM + 11 LOW）。
- **期末四轴 MEDIUM 主会话直修**（80f4880，先红后绿）：①Falsify「bulk-delete 路径 FK 级联零测试锁定」——补 `test_delete_user_cascades_following_swipes` + `test_happy_path_cascades_following_swipes`（开 FK + 构造 swipes + 断言 orphan 零）；②Falsify「editMessage/deleteMessage 绕过 nonStreamingInFlight 互斥」——两函数加 `cleanupStaleInFlight` + `nonStreamingInFlight.has/add/delete` 守卫（与 regenerate/continue/branch 同纪律）+ 防复发断言（挂起 DELETE + 双触发 no-op）。pytest 1225+1skip / Vitest 1379。
- **避坑（勿重踩）**：①spec 跨工单不一致（service 签名 vs 端点契约参数不匹配）是本期唯一「范围偏差」根因——plan-tickets 拆票时 service 签名与端点契约须交叉核对，避免实现时才需加解析 seam；②后台派发的 Implement 子智能体用 AskUserQuestion 不会转达主会话（agent 报告「未获答复」按 best judgment 继续）——后台派发 prompt 须明示「不要用 AskUserQuestion，best judgment + 如实上报 concern」。
- **非阻断落债**：F-130~F-138（9 项，见 TECH_DEBT 候选区——require_message 空心别名+三查冗余 / 级联 Seam 环境依赖+StaleData / 按钮 css 悬停不统一 / 角色判定缓存漂移 / autoflush 分歧 / promptMessageEdit 重复 / _resolve_* 家族萌芽 / 全空白 content / error_mapping 行膨胀）。

---

## 技术债消费批次 F-127~F-129（2026-09-14 — 2 做 1 关，轻量档 3 项主会话直做）

- **来源**：用户指令「消费 F-127~129」（架构批次期末四轴观察级落债）。逐项 git grep 复核现状后拍板 2 做 1 关。
- **2 做（commit 5ed88f5）**：
  - F-127（Worth exploring）`append_swipe_and_bump` 两段提交非原子——`add_swipe` 加 `commit: bool = True` 参数（默认向后兼容），append 调 `commit=False` 后单 commit（候选 + content 跟随 + updated_at bump 原子落库），消除「候选已落库但 updated_at 未 bump」崩溃窗口；防复发断言 test_append_swipe_and_bump_single_commit_atomic（spy commit 计数 == 1）。
  - F-129（Speculative）`_ensure_conversation_branch_columns` Engine 形态三连接/三 commit——改单连接循环补三列（Connection 形态直接循环），消除每次 `_ensure_column` 各开新连接。
- **1 关（F-128，Speculative）**：`append_swipe_and_bump` 冗余重取——F-127 改 commit=False 后 msg 未 expire，`_require_message` 命中 identity map 不再发 SQL；剩余「再取一次」是 append 需 msg.conversation_id 而 add_swipe 返回 next_index 的合理结构（非冗余开销）。复核关闭。
- **验证链**：pytest 1199+1skip→1200+1skip（+1 防复发断言）+ Vitest 1351 + cargo 70 零回退全绿 | doc_sync 刷新 8 标记 + pool_cleanup_check 全合规 | 技术债候选区 3→0 清零。
- **非阻断落债**：无（候选区清零）。

---


## 历史归档索引

| 日期 | 批次 | 摘要 |
|------|------|------|
| 2026-09-14 | 架构深化候选消费批次 F-123~F-126 | 4 做，标准档 4 工单串行 |
| 2026-09-14 | 技术债消费批次 F-115~F-122 | 3 做 5 关，轻量档 8 项主会话直做 |
| 2026-09-14 | mod-cg-wiring 批次 | Mod memory/css 消费 + CG 解锁/画廊/加权自动出图，标准档 7 工单 |
| 2026-09-13 | 技术债候选区消费批次 F-109~F-111 | F-110 做 + F-109/F-111 复核关闭，轻量档 1 工单 |
| 2026-09-12 | MD-2 Mod 管理 UI + 注入链集成 | AI风月对标五批工单 MD 批收官 |
| 2026-09-12 | MD-1 Mod 数据模型与注入叠加 | AI风月对标五批工单 MD 首批，承接 MD-3 |
| 2026-09-11 | MS-3 继续生成 | AI风月对标五批工单 MS 收官，承接 MS-2 |
| 2026-09-11 | BR-1 分支元数据与快照导出 | AI风月对标五批工单 BR 首张，承接 MS 批收官 |
| 2026-09-11 | BR-2 从快照/分支派生会话 | AI风月对标五批工单 BR 收官，承接 BR-1 快照 |
| 2026-09-11 | CG-1 text2img Provider 抽象 | AI风月对标五批工单 CG 首张，承接 BR 批收官 |
| 2026-09-11 | CG-2 CG 资产库 + 画廊 | AI风月对标五批工单 CG 第二张，承接 CG-1 Provider |
| 2026-09-11 | CG-3 对话内出图 + 剧情回顾 | AI风月对标五批工单 CG 收官，承接 CG-2 资产库 |
| 2026-09-11 | MD-3 出图能力门控 + 图片 Provider 设置 | CG 批后用户指出的产品缺口，独立 follow-up |
| 2026-09-10 | WL-1 世界书数据模型 + 仓库层 | AI风月对标五批工单 WL 首批，承接 handoff |
| 2026-09-10 | WL-2 世界书激活引擎纯函数 | AI风月对标五批工单 WL 第二张，承接 WL-1 |
| 2026-09-10 | 技术债消费批次 F-93：text_utils 共享单点收敛 | 用户「消费技术债后继续推进 WL-3」 |
| 2026-09-10 | WL-3 世界书注入链集成 | AI风月对标五批工单 WL 第三张，承接 WL-2 |
| 2026-09-10 | 技术债消费批次 F-94 + F-95：role_str 收敛 + 消除双查历史 | 用户「继续消费技术债」 |
| 2026-09-10 | WL-4 世界书编辑器前端 | AI风月对标五批工单 WL 第四张，承接 WL-3 注入链 |
| 2026-09-10 | 技术债消费批次 F-96：escapeHtml 引号转义升级 | 用户「继续消费技术债」 |
| 2026-09-10 | WL-5 记忆宫殿 AI 归纳层 | AI风月对标五批工单 WL 收官，承接 WL-4 编辑器 |
| 2026-09-10 | MS-1 swipes 数据模型与服务 | AI风月对标五批工单 MS 首张，承接 WL 批收官 |
| 2026-09-10 | MS-2 swipes 前端候选控制条 | AI风月对标五批工单 MS 第二张，承接 MS-1 |
| 2026-09-10 | 外部对标调研 AI风月 + 五批工单立项 | 用户需求：聊天/模拟器功能体验对标 |
| 2026-08-28 | 版本号升级 v0.6.1 发布批次 | CORS 反代 + UI 收口修复版发布 |
| 2026-08-28 | 模拟器 API CORS 反代 + 重新识别按钮 UI 收口 | 用户报告，CORS 连接失败 + 列表违和 |
| 2026-08-28 | 版本号升级 v0.6.0 | 9 处清单 + SECURITY 支持表，基线 v0.5.0 → HEAD |
| 2026-08-27 | 技术债消费批次 F-92 | kickoff 全自动档轻量档 1 工单，基线 647d720 → HEAD |
| 2026-08-27 | 用户 bug 修复 F-91：模拟器 config 多候选 id | 用户报告，斗罗大陆同步失效 |
| 2026-08-27 | 版本号升级 v0.5.0 | 8+1 处清单，基线 56339e7 → HEAD |
| 2026-08-27 | 技术债消费批次 F-90 | kickoff 全自动档轻量档 1 工单，基线 c1b665d → HEAD |
| 2026-08-27 | 技术债消费批次 F-82~F-89 | kickoff 全自动档小档 3 工单后台 lane，基线 0a5af97 → HEAD |
| 2026-08-27 | 架构深化批次 S1~S3 | kickoff 全自动档标准档 3 工单单波并行，基线 9a1385b → HEAD |
| 2026-08-27 | 版本号升级 v0.4.0 | 8 处清单，基线 3458679 → HEAD |
| 2026-08-27 | 技术债消费批次 F-80~F-81 | kickoff 全自动档轻量档 1 工单，基线 7089845 → HEAD |
| 2026-08-27 | 技术债消费批次 F-74~F-79 | kickoff 全自动档小档 2 工单后台 lane，基线 701322a → HEAD |
| 2026-08-27 | 技术债消费批次 F-64~F-73 | kickoff 全自动档标准档 4 工单 2 波，基线 880aa24 → HEAD |
| 2026-08-26 | 技术债消费批次 F-49~F-63 | kickoff 全自动档标准档 10 工单 5 波，基线 8ebdce1 → HEAD |
| 2026-08-26 | UX 体验改进批次 | kickoff 全自动档标准档 8 工单 5 波，merge 链 15d7c8b→a79c692 |
| 2026-08-26 | 模拟器导入「AI/本地」识别补强 + 重新识别入口 | 模拟器导入「AI/本地」识别补强 + 重新识别入口（2026-08-26，用户需求单工单） |
| 2026-08-26 | 分享前准备批次 | MIT LICENSE + NOTICE + 版本号 0.3.0 + 构建修复，commit 链 62ed29d → def028a |
| 2026-08-25 | 全量审查修复批次 | kickoff 全自动档标准档：9 工单 3 波，commit 链 789602c → 2794b84 + 文档同步 |
| 2026-08-23 | 滚动摘要 | 阶段摘要：游戏生成交付 + 架构深化四波 + 技术债区 F-23~F-37 落盘，细节 git log 可溯 |
| 2026-08-20 | 修复：D11 关闭行为偏好保存失败 | 修复：D11 关闭行为偏好保存失败（Tauri ACL 拒绝，2026-08-20） |
| 2026-08-20 | 滚动摘要 | 三问题修复：关闭行为偏好、启动/关闭性能、loading 按钮，commit 链 436964b → [当前] |
| 2026-08-19 | 滚动摘要 | 技术债区批次 3：F-21 docstring 契约 + F-20 复核关闭，技术债区清零，commit 链 08e860f → 2b29865 |
| 2026-08-19 | 滚动摘要 | T-01/T-02 模拟器接入契约 + 外置数据目录与用户导入：kickoff 批次 5 工单 3 波，commit 链 c7e5b29 → 262fe88 |
| 2026-08-19 | 滚动摘要 | 模拟器配置面板可读性修复：vision 全量诊断 + 分区 7 |
| 2026-08-19 | 滚动摘要 | 模拟器 PC 阅读优化：kickoff 小档 2 工单 |
| 2026-08-15 | 滚动摘要 | 关闭行为偏好 D11：首次运行选择关窗行为 + 设置页可改 |
| 2026-08-15 | 滚动摘要 | 阶段摘要：C5/C6/C3-C4-C8 架构收敛 + F-1 技术债小批 + 模拟器交付修复，细节 git log 可溯 |
| 2026-08-09 | 滚动摘要 | 阶段摘要：模拟器三期 + 技术债 TD 系列 + 桌面打包 + C1/C2 收口 |
