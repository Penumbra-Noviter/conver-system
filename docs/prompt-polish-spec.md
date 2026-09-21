# Prompt 打磨 — 工单规格（PD 批次：预设开场白 / Prompt Debug / 专家模式）

> 来源：AI风月对标调研「对话质量 / Prompt 工程」维度第二轮（见 [external-benchmark-aigirlfriend.md](external-benchmark-aigirlfriend.md) §3.7）。SP 采样参数批次已先行落地，本批承接同一维度的三个剩余机制。
> 定位：纯本地、不盈利、不建社交体系；只做聊天与模拟器功能体验。
> 规则：本文件是 PD 批次工单的**规格依据**；工单本体登记在 TO-TICKETS.md 活跃表，完成时按既有归档机制入档。

## 0. 全局约束（沿用既有五批约定，已实测）

1. 落点约定（现有代码实测）：
   - 组装入口：`backend/app/services/llm/prompt.py::build_messages`（纯函数，无 DB 依赖）
   - 历史装配：`backend/app/services/message.py::build_message_list`
   - 回合编排：`backend/app/services/chat.py::assemble_chat_context / prepare_chat / complete_chat`
   - 开场白预插：`backend/app/services/conversation.py::create_conversation`（line 184-188，硬用 `character.first_mes`）
   - 注入链：`chat.py::_lorebook_world_injection`（世界书）+ `_mod_prompt_injection`（prompt 区 Mod 叠加进 world_injection）
   - 路由：`backend/app/api/routes/{chat,messages,conversations,characters}.py`
   - 建表：`backend/app/database.py::init_db → Base.metadata.create_all`（**无 alembic**）
2. 迁移约束：create_all 只建新表、不给已存在表加列。必须加列时走 `_ensure_column` 自愈迁移原语（F-125 已落地：PRAGMA table_info 探测缺列 → ALTER TABLE ADD COLUMN），并加契约锁锁幂等。
3. 零变化硬约束：`build_messages` 的既有契约（`world=None` 或全空时输出与改动前逐字节一致）不得破坏；既有 pytest/Vitest 基线不回退。
4. 字段边界：专家模式新增字段是**项目自有字段**（对齐 temperature/top_p 等），不进 `CHARACTER_V2_FIELDS`（V2 规范清单）；不破坏 `PROMPT_FIELDS ⊆ CHARACTER_V2_FIELDS` 断言。
5. 命名规范：所有包 `__init__.py` 补 `__all__`；公开函数 type hints + docstring；前端动态图标走 `icons.js::iconHtml()`。

## 1. 决策记录（用户拍板，2026-09-14）

| 决策 | 选择 | 理由 |
|------|------|------|
| 专家模式数据模型 | 新增 `prompt_mode`(simple/expert) + 整段 `expert_prompt` 字段，可逆 | 真正实现「整个 PROMPT 自由编辑」，保留基础模式结构化引导；对标站「不可逆」是其产品限制，本地免费无此必要，做可逆 |
| 预设对话范围 | 复用 `alternate_greetings` 做开场白选择，不加新表 | 字段已存在（V2 往返保真），成本最低、即时可用；成对 Q&A 预设对话后置 |
| Prompt Debug 形态 | 只读预览 + 分段来源标注 | 对标站即作者可见只读；可编辑调试引入「调试态/持久态分离」复杂度，后置 |

## 2. 批次 PD — 预设开场白选择

### PD-1 后端：指定开场白 override

目标：新建对话时可选开场白（`first_mes` 或 `alternate_greetings` 之一，或显式无开场白）。

Schema 改动（`backend/app/schemas/conversation.py`）：
- `ConversationCreate` 增字段 `greeting: Optional[str] = None`（`model_fields_set` 判定显式传入）。

服务改动（`backend/app/services/conversation.py::create_conversation`）：
- 开场白预插逻辑：`model_fields_set` 含 `greeting` 时以其值为准——`None`/空串 → 不预插；非空串 → `apply_template_vars(greeting, ...)` 后预插；未含 `greeting` → 维持现状用 `character.first_mes`（零回归）。

契约锁用例（`backend/tests/test_conversation_greeting.py`）：
1. 未传 `greeting` → 预插 `first_mes`（模板变量替换，零回归断言）
2. 传 `greeting="自定义"` → 预插该内容
3. 传 `greeting=None`（显式）→ 不预插，消息表为空
4. 传 `greeting=""`（显式空）→ 不预插
5. `greeting` 内容含 `{{user}}`/`{{char}}` → 正确替换
6. `character.first_mes` 为空 + 未传 `greeting` → 不预插（既有语义不变）

验收：pytest 全绿 + 新用例通过；既有 `create_conversation` 调用方零回归。

### PD-2 前端：备用开场白编辑 + 开场白选择

目标：角色可编辑多个备用开场白；新建对话时可从开场白池选择。

UI 规格：
- 角色表单（`character-form.js`）+ 向导（`character-wizard.js`）增「备用开场白」列表编辑：每行一个 textarea/input + 删除按钮，可增删，上限 10 条（对齐对标站 ≤10）。
- 新建对话入口增「开场白」下拉：列出 `first_mes`（标记「默认」）+ `alternate_greetings` 各项；选默认 → 不传 `greeting`（走 first_mes 现状）；选某备选 → 传该文本；可加「无开场白」选项 → 传空。
- 图标统一走 `iconHtml()`；复用既有 modal 骨架 seam，不新造骨架。

契约锁用例（`frontend/tests/greeting-editor.test.js`，Vitest）：
1. 备用开场白增删上限 10、空项去重
2. 保存 payload 含 `alternate_greetings`（list，逐字段一致）
3. 新建对话「开场白」下拉选项 = first_mes + alternate_greetings + 无开场白；选项 → `greeting` 字段映射正确（默认/备选/无）
4. 编辑角色重开面板字段还原

验收：Vitest 通过；Playwright 冒烟：编辑备用开场白 → 保存 → 新建对话选备选 → 首条消息为所选开场白。

## 3. 批次 PD — Prompt Debug 面板（只读）

### PD-3 后端：prompt-debug 端点 + 带来源组装追溯

目标：暴露最终组装后的消息列表，逐条标注来源，不改动线上组装行为。

端点：`GET /api/conversations/{conversation_id}/prompt-debug`
响应（只读，不落库、不触发 LLM）：

```json
{
  "conversation_id": 1,
  "character_name": "…",
  "model": "provider/model_name",
  "prompt_mode": "simple",
  "segments": [
    {"role": "system", "content": "…", "source": "character"},
    {"role": "user", "content": "…", "source": "history"},
    {"role": "assistant", "content": "…", "source": "history"},
    {"role": "user", "content": "…", "source": "user"}
  ]
}
```

来源枚举（对标 app/user/mod 三层 → 本地六类映射）：
- `character`：角色静态字段（system_prompt/personality/scenario/mes_example/post_history_instructions/expert_prompt）
- `world`：世界书手动条目注入（before_char/after_char/[世界知识]）
- `memory`：记忆宫殿产出条目注入（world 内 source='auto'，与 `world` 区分）
- `mod`：prompt 区 Mod 注入
- `history`：历史消息
- `user`：当前输入（重生成路径下无 user，末条为 history 末条 user）

实现约束（关键，防漂移）：
1. **单一组装实现**：不得复制 `build_messages` 的组装顺序；在 `prompt.py` 内部抽共享组装核心，`build_messages`（纯 messages）与 debug 追溯（带 source）共用同一核心。
2. **零变化契约**：`build_messages` 签名与输出保持不变，既有 `world=None` 逐字节一致用例不回退。
3. **来源保真**：`_lorebook_world_injection` / `_mod_prompt_injection` 需产出带来源（world/memory/mod）的分段，或在 debug 路径分别取得世界书与 mod 增量；不靠 `apply_prompt_mods` 叠加后的合并 dict 反推来源。
4. 组装追溯与 `assemble_chat_context` 走同一上游（history_limit、世界书扫描窗、mod 叠加），保证 debug 所见即线上所发。

契约锁用例（`backend/tests/test_prompt_debug.py`）：
1. simple 模式角色：segments 顺序 = before_char → system → scenario → after_char → world → mes_example → history → post_history → user，来源标注逐段正确
2. expert 模式角色：system 段为单条 expert_prompt，来源 `character`
3. 世界书条目（manual）→ 来源 `world`；记忆宫殿条目（auto）→ 来源 `memory`
4. prompt 区 Mod → 来源 `mod`（与 world 分开标注）
5. 空对话（无历史）+ 无注入 → 仅 system（来源 character）+ user（来源 user）
6. 与 `assemble_chat_context` 产出 messages 逐条 content 一致（debug 只见证、不改线上）

验收：pytest 全绿；`build_messages` 零变化；debug 端点只读（GET 无副作用）。

### PD-4 前端：只读预览面板

目标：对话页/角色页可打开 Prompt Debug 面板，展示分段 messages 与来源标签。

UI 规格：
- 入口：聊天头部或角色详情新增「Prompt Debug」按钮（`iconHtml` 调试图标，不新增 emoji）。
- 面板：只读列表，每条显示 role 徽标 + 来源色标（character/world/memory/mod/history/user 各一色）+ content 等宽字体预排版（保留换行）；顶部显示角色名 / 模型 / prompt_mode。
- 复用 openModal 骨架；不提供编辑；关闭即弃。

契约锁用例（`frontend/tests/prompt-debug.test.js`，Vitest）：
1. segments 渲染：来源 → 色标类名映射单一来源（单一映射表，不散落 if/else）
2. role 徽标与 content 转义（content 内 HTML 不注入）
3. 空 segments → 空态提示
4. 来源枚举非法值 → 落入默认样式不抛错

验收：Vitest 通过；Playwright 冒烟：打开面板 → 分段可见 → 关闭无副作用。

## 4. 批次 PD — 专家模式 PROMPT

### PD-5 后端：prompt_mode + expert_prompt 字段 + 组装分流

目标：角色可切专家模式，直编整段 system prompt，替代结构化组装，可逆。

字段规格（`backend/app/models/character.py` 加两列，项目自有字段）：
| 列 | 类型 | 约束/默认 | 说明 |
|---|---|---|---|
| prompt_mode | VARCHAR(8) | NOT NULL, default 'simple' | simple / expert |
| expert_prompt | Text | NOT NULL, default '' | 专家模式整段 system prompt |

- 自愈迁移：`_ensure_column` 原语探测两列缺列 → ALTER TABLE ADD COLUMN（幂等契约锁）。
- Schema：`CharacterBase` 增 `prompt_mode: str = "simple"` + `expert_prompt: str = ""`（`CharacterCreate` 继承，`CharacterUpdate` 显式 Optional 覆盖）。
- 往返保真：`prompt_mode` / `expert_prompt` 走 `extensions.conver_system` 命名空间（对齐 temperature 既有模式），导出/导入不丢；**不进** `CHARACTER_V2_FIELDS`。

组装分流（`prompt.py`）：
- `CharacterData` 增 `prompt_mode: str = "simple"`、`expert_prompt: str = ""`。
- `build_messages` 内：`prompt_mode == 'expert'` 且 `expert_prompt` 非空 → system 区 = 单条 `apply_template_vars(expert_prompt)`，**替代** system_prompt/personality（步骤 1）、scenario（步骤 2）、post_history_instructions（步骤 5）三处结构化注入；`mes_example`、世界书注入（before_char/after_char/world）、mod、history、user 照旧按序注入。
- `prompt_mode == 'expert'` 但 `expert_prompt` 空 → 回退 simple 结构化组装（安全兜底，不产出空 system）。
- `prompt_mode == 'simple'` → 行为与改动前逐字节一致（零变化契约）。
- `build_message_list` 的 `CharacterData` 构造：`PROMPT_FIELDS` 循环 + 显式补 `prompt_mode` / `expert_prompt`（两者不进 PROMPT_FIELDS，保持 `PROMPT_FIELDS ⊆ CHARACTER_V2_FIELDS` 断言）。

契约锁用例（`backend/tests/test_expert_prompt.py`）：
1. simple 模式 → 输出与改动前逐字节一致（零回归）
2. expert + expert_prompt 非空 → system 段仅一条，content = expert_prompt（模板变量替换后）；无 scenario / post_history 独立 system
3. expert + expert_prompt 空 → 回退 simple 结构化（与 simple 一致）
4. expert 模式下 mes_example 仍注入；before_char/after_char/world 世界书注入仍按序（expert_prompt 只替代角色静态字段，动态注入保留）
5. expert 模式下 history/user 仍按序；重生成路径 append_current_input=False 尾随 system 剥离不破坏
6. 迁移幂等：连续两次 init_db 两列不重复、不报错

验收：pytest 全绿；simple 零回归；自愈迁移契约锁通过。

### PD-6 前端：基础/专家两态编辑

目标：角色表单提供「基础 / 专家」编辑模式切换，专家态直编整段 PROMPT，可逆。

UI 规格：
- 角色表单（`character-form.js`）人格区顶部增「基础模式 / 专家模式」切换。
- 基础态：现有 personality/scenario/system_prompt/post_history 字段（现状不变）。
- 专家态：单个大 textarea 直编 `expert_prompt`，隐藏（或灰显）上述结构化字段；提示「专家模式将用此段替换人格/场景/历史后指令的结构化组装；世界书与 Mod 注入仍生效」。
- 切换可逆：expert → simple 时保留 expert_prompt（不丢失，可再切回）；simple → expert 时可选「从当前字段生成」或「空白开始」（推荐提供「从当前字段生成」一键，减少迁移成本）。
- 保存 payload 同时携带 `prompt_mode` + `expert_prompt`（及未改动的结构化字段，避免切换丢失）。

契约锁用例（`frontend/tests/expert-mode.test.js`，Vitest）：
1. 两态切换：字段显隐与 textarea 绑定正确；可逆切换不丢 expert_prompt
2. 「从当前字段生成」→ expert_prompt 预填（拼接顺序固定）；「空白开始」→ 清空
3. 保存 payload 含 prompt_mode + expert_prompt，与后端 schema 字段名一致
4. 编辑已有 expert 角色 → 重开面板还原 expert 态与文本

验收：Vitest 通过；Playwright 冒烟：切专家 → 直编 → 保存 → 发消息 → Prompt Debug 面板确认 system 段为 expert_prompt 单条。

## 5. 实施顺序与依赖

- 批次内依赖：PD-5（专家模式后端）先于 PD-3（Prompt Debug 后端，因 debug 需感知 expert 分流）与 PD-6（前端两态）。
- 建议顺序：PD-1 → PD-2（预设开场白，独立）→ PD-5 → PD-6（专家模式）→ PD-3 → PD-4（Prompt Debug 依赖前两者语义）。
- 每批统一验收：先红后绿 + 全量基线不回退（pytest 1234+1skip / Vitest 1380 / cargo 70）+ 覆盖率不放宽 + 冒烟 + 文档同步。
