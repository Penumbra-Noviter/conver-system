# 聊天/模拟器功能升级 — 工单规格（WL / MS / BR / CG / MD 五批）

> 来源：AI风月（aigirlfriendstudio.com）对标调研（证据链与本批三份规格笔记在仓库外 `D:\tmp\fetchflow-aigs\`：aigs-chat-sim-benchmark.md / aigs-lorebook-memory-palace-spec.md / aigs-mod-msg-branch-cg-spec.md）
> 定位：纯本地、不盈利、不建社交体系；只做聊天与模拟器功能体验
> 规则：本文件是五批工单的**规格依据**；工单本体登记在 TO-TICKETS.md 活跃表，完成时按既有归档机制入档

## 0. 全局约束（五批共用）

1. 落点约定（现有代码实测）：
   - 组装入口：backend/app/services/llm/prompt.py::build_messages（line 108，纯函数，无 DB 依赖）
   - 历史装配：backend/app/services/message.py::build_message_list（line 141）
   - 回合编排：backend/app/services/chat.py::assemble_chat_context / prepare_chat / complete_chat / regenerate_chat
   - 路由：backend/app/api/routes/{chat,messages,conversations,characters}.py
   - 建表：backend/app/database.py::init_db → Base.metadata.create_all（**无 alembic**）
   - 前端：frontend/js/chat.js（.btn-regenerate / regenerateLastReply）；save-manager.js / save-key-meta.js（存档）
2. 迁移约束（重要）：create_all 只建新表、**不会给已存在表加列**。因此：
   - 优先「新增表 + 外键关联」形态；
   - 必须加列时，工单内需附自愈迁移步骤（启动时 PRAGMA table_info 探测缺列 → ALTER TABLE ADD COLUMN），并加契约锁用例锁住幂等。
3. 不可越界（明确不做）：积分/充值/订阅、邀请返利、装扮/勋章、评论/论坛/关注、Mod 付费与评分、内容 age_rating 前台门禁。
4. 命名与规范：所有包 __init__.py 补 __all__；公开函数 type hints + docstring；模块要深（协议表面小、实现丰富）；前端动态图标走 js/icons.js 的 iconHtml() seam。

---

## 批次 WL — 世界书引擎（角色级世界书，AI 风月对标）

### WL-1 世界书数据模型 + 仓库层
目标：落地 Lorebook 条目表与仓库函数，字段语义对齐 SillyTavern World Info（D4 七件套先行）。

字段规格（新表 lorebook_entries，SQLite）：
| 列 | 类型 | 约束/默认 | 说明 |
|---|---|---|---|
| id | INTEGER PK autoincrement | — | — |
| character_id | INTEGER FK characters.id ondelete CASCADE | index | 归属角色（世界书挂在角色卡下，与 character_book 对齐） |
| title | VARCHAR(200) | default '' | 条目标题（可空） |
| keys | TEXT | NOT NULL, default '[]' | JSON 数组：触发关键词（1..N） |
| content | TEXT | NOT NULL, default '' | 命中后注入内容 |
| constant | BOOLEAN | default false | 常驻（不判命中，直接注入） |
| order | INTEGER | default 100, CHECK 0..9999 | 命中条目排序（升序注入） |
| probability | INTEGER | default 100, CHECK 1..100 | 独立命中概率 |
| group_name | VARCHAR(100) | default '' | 互斥组名（空=不分组） |
| group_weight | INTEGER | default 100, CHECK 1..100 | 组内权重（同组随机抽一） |
| match_mode | VARCHAR(8) | default 'or' | or / and |
| position | VARCHAR(16) | default 'world' | world=合并为 [世界知识] system；before_char=角色 system 前；after_char=场景设定后 |
| depth | INTEGER | default 20, CHECK 0..20 | 参与命中的最近轮数（0=只看当前输入） |
| source | VARCHAR(16) | default 'manual' | manual / auto（记忆宫殿产出） |
| enabled | BOOLEAN | default true | 单条开关 |
| created_at / updated_at | DATETIME | server_default now | — |

公开函数（backend/app/services/lorebook.py，__all__ 列全）：
- list_entries(db: Session, character_id: int) -> list[LorebookEntry]
- create_entry(db: Session, character_id: int, payload: LorebookEntryCreate) -> LorebookEntry
- update_entry(db: Session, entry_id: int, payload: LorebookEntryUpdate) -> LorebookEntry
- delete_entry(db: Session, entry_id: int) -> None
- replace_entries(db: Session, character_id: int, entries: list[LorebookEntryCreate]) -> int
- parse_character_book(book: dict) -> list[LorebookEntryCreate]（消费 character_book → 条目草案，字段语义对齐 ST）

契约锁用例（backend/tests/test_lorebook_store.py）：
1. keys 为 JSON 数组且非 list 输入被拒；空 keys 允许（constant 场景）
2. order/probability/depth/group_weight 越界值被裁剪或拒（二选一，测试锁定所选语义）
3. character_id 级联删除条目
4. replace_entries 幂等（连续两次调用结果一致）
5. parse_character_book：ST character_book 结构 → 条目字段一一对应（keys/content/constant/order/probability/group）
6. 现有 imports：character_card.py 的 extensions.conver_system.character_book 仍保真（零回归）

验收：pytest 全绿 + 新用例通过；character_book 从「仅保真」升级为「可解析入库」（可编辑）。

### WL-2 激活引擎纯函数
目标：纯函数实现命中判定与排序（零 DB、零 IO、可独立单测、RNG 注入可复现）。

签名（backend/app/services/lorebook_engine.py）：
- activate_lorebook_entries(entries: Sequence[LorebookEntryData], scan_text: str, *, current_input: str = "", rng: random.Random | None = None) -> list[LorebookEntryData]
- build_world_injection(activated: Sequence[LorebookEntryData], *, user_name: str = "User", char_name: str = "Character") -> dict[str, list[str]]
  返回 {"system": [...], "before_char": [...], "after_char": [...]}（按 position 分组，组内按 order 升序）
- collect_scan_text(history: Sequence[object], current_input: str, depth: int, *, role_of: Callable[[object], str]) -> str
  （depth=0 → 仅 current_input；depth=N → 最近 N 轮 = 2N 条消息 + current_input）

语义（对齐 ST 与对标站实测）：
- constant=true 直接入选（不判命中）
- match_mode='or'：任一 key 作为子串出现在 scan_text 即命中；'and'：全部出现才命中
- depth 决定 scan_text 的窗口（0..20）
- probability：独立随机（默认 100 = 必中）；group_name 非空时同组按 group_weight 加权抽一篇（返回顺序仍按 order）
- 禁用条目（enabled=false）不参与

契约锁用例（backend/tests/test_lorebook_engine.py）：
1. 空 entries / 空 scan_text → 空结果（零异常）
2. constant 直进且不受 depth 影响
3. or / and 命中矩阵（含大小写敏感为**不敏感**的显式断言或反之，须锁定一种）
4. depth 边界：0（只看输入）/ 1（最近 1 轮）/ 20（上限）/ 超限裁剪
5. order 升序输出稳定（同 order 时以 id 稳定排序，锁定确定性）
6. probability=0 不入选、=100 必选；rng 注入下同种子结果可复现
7. group 内加权抽一：同组只出一条；不同组互不影响
8. 泛词防护：keys 含单字符/标点时**不报错**但可被上层告警（见 WL-4）

验收：纯函数用例全绿；同种子 RNG 复现；无 DB 依赖（import 检查）。

### WL-3 注入链集成
目标：把激活结果接进现有组装链，不改动既有行为（默认关）。

签名改动（保持向后兼容）：
- prompt.py::build_messages(..., world: dict[str, list[str]] | None = None) -> list[dict[str, str]]
  · world=None 时逐字保持现行输出（零变化硬约束，由既有用例锁定）
  · position='before_char' 的块插入 system prompt 之前；'after_char' 插入 [场景设定] 之后；'world' 合并为单条 system（形如 [世界知识]\n...，多条以空行连接，按 order 升序）
- message.py::build_message_list(..., world_injection: dict | None = None)
- chat.py::assemble_chat_context：查角色 → list_entries(enabled) → collect_scan_text(history, current_input, max(depth)) → activate → build_world_injection → 传入 build_message_list

契约锁用例（backend/tests/test_prompt_world_injection.py + test_chat_world_injection.py）：
1. world=None：输出与改动前逐字节一致（用既有基线断言）
2. before_char / after_char / world 三种位置的消息序列顺序断言
3. 多条 [世界知识] 合并为一条 system，且按 order 升序
4. 与 append_current_input=False（重生成路径）组合：末条仍为历史末条 user，尾随 system 剥离逻辑不被世界书注入破坏（含 world 注入时的尾随剥离）
5. 世界书为空时不产生空 system 消息（不污染上下文）
6. 滑窗与 depth 解耦：max_rounds 改动不影响激活窗口
7. 重生成路径同样吃到世界书注入（两路径一致性）

验收：pytest 全绿；world=None 零回归；端到端发一条消息可在提示词调试（若实现）或日志中确认注入块。

### WL-4 世界书编辑器前端
目标：角色详情内新增世界书面板（CRUD），字段与 WL-1 对齐。

UI 规格：
- 入口：角色详情面板新增「世界书」标签（复用现有 modal 骨架 seam，不新造骨架）
- 列表：标题 / 关键词（前 3 个 + 计数）/ 开关 / order / 常驻标记；支持关键词搜索过滤
- 编辑：关键词 chips（回车或点「添加」录入，与对标站一致）、内容 textarea、match_mode 或/与、position 三选、order 数字、probability 数字、group + weight、depth（0-20 步进）、enabled 开关
- 校验与提示（对标站实测约束，本地版可取其中合理项）：
  · 单条内容长度上限（建议 20000 字符，可配）
  · keys 含 1 字符或高频泛词（你/我/他/。/，等）→ 内联告警「关键词过泛，会显著增加注入量」
  · 概率模式下同组权重和提示（不强制 100，本地版按权重归一）
- 图标统一走 icons.js 的 iconHtml()；不新增 emoji 字面量

契约锁用例（frontend/tests/lorebook-editor.test.js，Vitest）：
1. 关键词 chips 录入/去重/删除
2. 表单校验：内容超限/关键词为空/数值越界 → 阻止提交并给内联错误
3. 泛词告警触发条件
4. 保存 payload 字段与后端 schema 逐字段一致（字段名映射表单一来源）
5. 列表渲染：开关状态、常驻标记、搜索过滤结果

验收：Vitest 用例通过；Playwright 冒烟：新增条目 → 保存 → 重开面板字段还原 → 发消息可见注入生效。

### WL-5 记忆宫殿（自动条目生成层）
目标：在引擎之上加「AI 归纳 → 生成条目」层，引擎零改动（调用方形态）。

设计（对齐对标站实测语义）：
- 位置：对话页「记忆增强」开关（会话级开关落 settings 或 conversations 扩展字段）
- 触发：每 N 轮（默认 1）或记忆内容达到阈值（可配，参考对标站 10000 字符）→ 调本地/已配置 LLM 归纳本轮/本段要点
- 产出：lorebook_entries 行，source='auto'，position='world'，depth=20（固定，可配），keys 由归纳结果给出（无 keys 时不落库）
- 管理：面板内与手动条目同列表展示（可按 source 过滤）、可编辑/删除
- 互斥：与「自动总结」（不实现或后置）二选一，避免双重压缩

服务签名（backend/app/services/memory_palace.py）：
- summarize_turn(history: Sequence[object], *, provider: BaseLLM, model: str | None, user_name: str, char_name: str) -> MemoryDraft
- persist_drafts(db: Session, character_id: int, drafts: Sequence[MemoryDraft]) -> int
- should_summarize(message_count: int, char_count: int, *, every_rounds: int, char_threshold: int) -> bool
- MEMORY_DRAFT_SCHEMA：归纳输出 JSON schema（title/keys/content），解析失败降级为不落库并记日志

契约锁用例（backend/tests/test_memory_palace.py）：
1. should_summarize 阈值矩阵（轮数达标 / 字符数达标 / 均不达标）
2. summarize_turn 对 LLM 输出做严格 JSON 解析；非法 JSON → 降级且不抛（错误日志）
3. persist_drafts：keys 空 → 跳过；重复条目去重策略（同 keys+同 content 不重复入库）
4. 归纳失败时对话主流程不受影响（异常隔离断言）
5. 生成的条目 position/depth 固定为配置值

验收：核心链路「发 N 轮 → 生成条目 → 命中注入」端到端可复现；LLM 失败不阻断对话。

---

## 批次 MS — 消息操作（继续 + swipes 多候选）

### MS-1 swipes 数据模型与服务
问题：Message 表当前只有 id/conversation_id/role/content/created_at，重生成是**覆盖**语义（末条 assistant 被替换），无法保留候选。

字段规格（新表 message_swipes）：
| 列 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | — |
| message_id | INTEGER FK messages.id ondelete CASCADE, index | 归属消息 |
| index | INTEGER | 候选序号（0 起，唯一约束 (message_id, index)） |
| content | TEXT | 候选内容 |
| created_at | DATETIME | — |

配套：messages 表增列 active_swipe_index（INTEGER, default 0）——若坚持不改列，可退化为「message_swipes 表 + 取 max(created_at) 为当前」但会丢失切换状态，**推荐加列并附自愈迁移**（PRAGMA table_info 探测 → ALTER TABLE）。

服务签名（backend/app/services/message.py 扩展，__all__ 更新）：
- add_swipe(db: Session, message_id: int, content: str, *, make_active: bool = True) -> int
- list_swipes(db: Session, message_id: int) -> list[MessageSwipe]
- switch_swipe(db: Session, message_id: int, index: int) -> Message
- delete_swipe(db: Session, message_id: int, index: int) -> Message（删除当前候选后回落到相邻候选；候选清空则删消息或拒绝，二选一并锁定）

契约锁用例（backend/tests/test_message_swipes.py）：
1. add_swipe 序号自增且唯一约束生效
2. switch_swipe 越界 → 明确领域异常；合法切换更新 active_swipe_index 且 content 与候选一致
3. 重生成改为 add_swipe 后：历史消息数不变（1 条 assistant + N 候选），旧行为用例需同步修订并锁定新语义
4. delete_swipe 边界：删中间/删当前/删最后一条
5. 级联：删消息 → 候选全删
6. 导出（conversation_export）含候选集与 active 索引，往返一致

### MS-2 swipes 前端（左右切换 + 计数）
- 落点：frontend/js/chat.js 渲染 assistant 气泡时，若 swipes.length > 1 显示「‹ 2/3 ›」控制条
- 交互：左右切 → 立即以本地候选切换渲染（乐观）→ 调 switch_swipe 落库；失败回滚
- 与重生成共存：重生成 = 追加新候选并切到最新（不是覆盖）
- 契约锁（frontend/tests/chat-swipes.test.js）：候选计数渲染、切换调用参数、失败回滚、单选时不渲染控制条

### MS-3 「继续」生成（append 续写）
- 语义：不产生新 user 消息，直接在末条 assistant 之后续写；后端新增 continue 模式
- 签名：chat.py 新增 continue_chat(db, conversation_id, *, ...) -> str（复用 assemble_chat_context + 以「续写」系统提示或原消息末段为触发）
- 契约锁（backend/tests/test_chat_continue.py）：
  1. 续写前后消息条数不变、内容为「原内容 + 续写片段」
  2. 不追加 user 消息（与正常发送区分）
  3. 失败时原内容不被破坏（原消息零改动断言）
- 前端：末条 assistant 气泡增「继续」按钮（与重生成同组渲染，走同一事件绑定 seam）

---

## 批次 BR — 存档升级为分支点

### BR-1 分支元数据与快照导出
字段规格（conversations 表增列，附自愈迁移）：
- parent_conversation_id INTEGER NULL（派生来源）
- branch_from_message_id INTEGER NULL（分叉锚：该消息为快照末条）
- branch_title VARCHAR(200) NULL（分支显示名）

导出契约（复用 backend/app/services/conversation_export.py）：
- build_branch_snapshot(db: Session, conversation_id: int, upto_message_id: int | None) -> BranchSnapshot
  · 载荷：{version, character_id, model_provider, model_name, title, messages:[{role, content, created_at}], lorebook_entries:[...], swipes:[...]}
  · upto_message_id=None → 全量；否则截断到该消息（含）
- 快照 JSON 为**版本化**结构（version 字段），未知版本拒绝导入并给明确错误

契约锁用例（backend/tests/test_branch_snapshot.py）：
1. 截断锚正确性：含锚、不含锚后消息
2. 快照含世界书条目与 swipes（记忆随存档走，对齐对标站语义）
3. 版本号缺失/不支持 → 明确异常
4. 导出 → 导入往返一致（消息顺序、创建时间、候选）

### BR-2 从快照/分支派生会话
服务签名（backend/app/services/conversation.py 扩展）：
- clone_conversation(db: Session, snapshot: BranchSnapshot, *, title: str | None = None) -> Conversation
- branch_from_message(db: Session, conversation_id: int, message_id: int, *, title: str | None = None) -> Conversation

语义：新会话 = 新 character 关联不变、消息按快照重建、世界书条目复制（新会话独立可改）、parent_conversation_id 指向源会话、branch_from_message_id 记录锚。

路由（backend/app/api/routes/conversations.py）：
- POST /api/conversations/{id}/branch         body {message_id, title?}
- POST /api/conversations/import-branch        body {snapshot}
- GET  /api/conversations/{id}/snapshot        → 快照下载（导出）

契约锁用例（backend/tests/test_conversation_branch.py）：
1. branch 生成的新会话消息序列与源（截断后）逐条一致
2. 源会话零改动（消息数与内容断言）
3. 世界书条目被复制且互不影响（改新会话条目不污染源）
4. 级联：删源会话不影响已派生分支（parent 引用置空策略需明示并锁定）
5. 路由层：不存在 message_id → 404 明确错误体

前端：消息级「分支」操作（与重生成同 seam）+ 会话列表显示分支来源标记（父标题 + 锚消息预览）；模拟器存档面板可「以此存档开新对话」。

---

## 批次 CG — CG 沉淀与剧情回顾

### CG-1 text2img Provider 抽象
- 形态与 LLM Provider 同构：backend/app/services/image/base.py（BaseImageGen：generate(params) -> ImageResult / 或异步任务 submit+poll）
- 登记在单一来源：available image providers 清单（对齐 model_data.py 的 AVAILABLE_MODELS 模式），factory 自动派生
- 本地优先：先支持「本地文件/HTTP 端点」两类最小后端（如 A1111 兼容 / 自定义 HTTP），Key 缺失时明确报错且不影响对话
- 契约锁（backend/tests/test_image_provider.py）：注册表派生、缺 Key 错误映射、响应畸形 → 明确错误、超时（复用 15s 守卫语义 + 长任务轮询上限）

### CG-2 CG 资产库 + 画廊
字段规格（新表 cg_images）：
| 列 | 类型 | 说明 |
|---|---|---|
| id | INTEGER PK | — |
| character_id | INTEGER FK characters.id CASCADE | 归属作品 |
| conversation_id | INTEGER FK conversations.id SET NULL | 产出会话（会话删除后图保留） |
| message_id | INTEGER FK messages.id SET NULL | 产出自哪条消息 |
| url | TEXT NOT NULL | 图片地址（本地文件路径或 URL） |
| group_name | VARCHAR(100) | 分组（默认「默认分组」） |
| is_special | BOOLEAN | 特殊 CG |
| unlocked | BOOLEAN | 是否已解锁 |
| unlock_hint | TEXT | 未解锁时提示 |
| created_at | DATETIME | — |

服务签名（backend/app/services/gallery.py）：
- add_cg(db, character_id, url, *, conversation_id=None, message_id=None, group_name="", unlock_hint="") -> CgImage
- list_cg(db, character_id, *, group_name=None, unlocked_only=False) -> list[CgImage]
- unlock_cg(db, cg_id) -> CgImage
- pick_cg_by_weight(candidates: Sequence[CgImage], *, rng=None) -> CgImage | None（触发时加权抽一张，对齐对标站概率池语义）

契约锁（backend/tests/test_gallery.py）：入库去重（同 url 同作品）、解锁幂等、加权抽选分布（同种子可复现）、分组过滤、会话删除后图保留（SET NULL）

### CG-3 对话内出图 + 剧情回顾
- 出图：对话页「生成图片」入口（输入描述 → 任务提交 → 轮询 → 完成后以消息附件形式插入气泡下方）
  · 任务表或复用内存 task 注册表（推荐新表 image_tasks：id/status/params/result_url/error/created_at），轮询端点 GET /api/images/tasks/{id}
- 剧情回顾：前端页面，把「已解锁 CG + 对应消息片段」按时间线拼接（只读视图，可直接复用 search-view.js 的时间线渲染范式）
- 契约锁：
  1. 生成中/成功/失败三态渲染（含「生成需 10-30 秒」提示文案）
  2. 失败不破坏对话（错误条复用现有 error-bar seam）
  3. 回顾时间线顺序 = 消息 created_at 升序；同一条消息多图保持入库序

---

## 批次 MD — Mod 挂载层

### MD-1 Mod 数据模型与注入叠加
字段规格（新表 mods + 新表 mod_bindings）：
mods：id / name / description / target_area(prompt|memory|css) / payload TEXT / version / source(manual|imported) / created_at
mod_bindings：id / character_id FK CASCADE / mod_id FK CASCADE / enabled BOOLEAN / sort_order INTEGER / 唯一约束 (character_id, mod_id)

服务签名（backend/app/services/mods.py）：
- list_mods(db) / create_mod(db, payload) / update_mod(db, mod_id, payload) / delete_mod(db, mod_id)
- bind_mod(db, character_id, mod_id, *, enabled=True, sort_order=None) -> ModBinding
- set_binding_enabled(db, binding_id, enabled: bool) -> ModBinding
- apply_prompt_mods(base_blocks: dict[str, list[str]], mods: Sequence[ModPayload]) -> dict[str, list[str]]
  （按 sort_order 叠加到 world/before_char/after_char 三个区域；memory 与 css 区域由各自消费方读取）

契约锁（backend/tests/test_mods.py）：
1. 绑定唯一性（同角色同 Mod 不重复）
2. 禁用绑定不参与叠加（零影响断言）
3. sort_order 决定叠加顺序（含同序稳定排序）
4. 解绑 / 删角色级联
5. apply_prompt_mods 空 Mod 列表 → 输入原样返回（零变化）

前端：Mod 管理面板（列表 / 启用开关 / 排序 / 目标区域选择 / 导入导出 JSON）；目标区域 css 的 Mod 复用现有 per-game CSS 后载序注入通道（同 seam，不新造）。

---

## 建议实施顺序与依赖

| 顺序 | 批次 | 依赖 | 风险 |
|---|---|---|---|
| 1 | WL-1 → WL-2 → WL-3 | 无（纯新增 + 组装层可选参数） | 低（world=None 零回归由既有用例锁死） |
| 2 | MS-1 → MS-2 → MS-3 | 无 | 中（重生成语义变化会触及既有用例，需同步修订并锁定） |
| 3 | BR-1 → BR-2 | 建议在世界书之后（快照需含世界书条目） | 中（加列 + 自愈迁移；级联语义需明示） |
| 4 | CG-1 → CG-2 → CG-3 | 独立；依赖本地生图后端可用性 | 高（外部后端 + 异步任务 + 长耗时） |
| 5 | MD-1 → +MD-2 | 复用 CSS 注入 seam 与注入链 | 低-中 |

## 每批统一验收口径（对齐项目既有流程）
- 先红后绿：新用例先失败再加实现（契约锁用例必须能在「实现被破坏」时失败）
- 全量测试基线不回退：pytest（当前 823+1skip）/ Vitest（当前 1189）/ cargo 70
- 覆盖率不放宽：新增模块单文件覆盖率口径按批次记录
- 冒烟：uvicorn + 关键端点 200 + Playwright 端到端主链路
- 文档同步：新增字段/端点进 docs/architecture.md 与 docs/api-design.md；批次完成进 DEV_LOG + TICKETS 归档
