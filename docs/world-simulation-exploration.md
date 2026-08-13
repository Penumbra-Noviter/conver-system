# Conver System — 世界模拟扩展 · 探索记录（大版本方向草案）

> **定位**：大版本「角色对话 → 世界模拟平台」的方向探索记录（2026-08-13 首轮探讨存档）。
> **非正式规格**：本文件只记录讨论过程与已确认方向；正式立项时决策进 `CONSENSUS.md`、工单进 `TICKETS.md`、技术事实进 `docs/architecture.md` 等对应文档。后续继续探讨时从本文件「未决事项」续。
> **状态**：探索中（用户要求先存档，后续再续谈）。

---

## 一、背景与目标

用户提出大版本更新：在现有角色对话功能之外加入其他玩法的模块（如修仙设定模拟、人生模拟等），核心诉求：

1. 可以自己添加世界设定、玩法
2. 可以导入这种世界玩法，包括整合 UI 的功能

产品现状（2026-08-13）：本地优先角色对话应用（FastAPI + SQLAlchemy 同步 + SQLite + Vanilla JS ESM + Tauri 桌面壳），已支持 SillyTavern Character Card V2 导入/导出，测试基线 pytest 413+1skip + Vitest 466 + cargo test 58 全绿，无活跃待办。

## 二、调研结论（2026-08-13，子智能体网络调研）

**类型命名**：无统一品类名，按「题材词 + 模拟器」组合——中文「文字修仙/修仙模拟器」（万界道友、VibeSims、仙途）、「人生模拟」（BitLife、人生重开模拟器）；英文 life sim / cultivation simulator / text adventure（NovelAI 官方定位 "Interactive AI Story Game & Life Simulator"）。

**三个最值得借鉴的成熟系统**（已逐字段验证）：
1. **SillyTavern 世界书（World Info/Lorebook）**——AI RP 圈十年沉淀的「世界设定标准」：条目 = 触发关键词 + 注入内容，支持正则、四态过滤、概率、互斥组、递归扫描、定时效果；纯 JSON 导入导出，可内嵌进角色卡。是「用户自己添加世界设定」的最低成本实现。
2. **角色卡 v2 / AI Dungeon 场景包**——「一个文件 = 一个完整世界玩法包」的打包范式。本项目已支持角色卡 V2 导入导出（含 `extensions.conver_system` 命名空间），角色卡 V2 自带 `character_book` 字段——有天然衔接点。
3. **lifeRestart / 万界道友**——证明「玩法 = 数据表（事件 = 条件 + 概率 + 效果 + 文本） + 少量状态机」在人生模拟与修仙模拟两个题材都成立；LLM 只生成文本，数值结算与规则留在确定性代码层。

**市场空白**：「可视化世界设定编辑器 + 玩法包市场」的完整形态目前无人占位，各产品只覆盖其中一块。

## 三、已确认决策（用户拍板，2026-08-13）

| # | 决策 | 内容 |
|---|------|------|
| D1 | **驱动核心** | 混合驱动：数值/规则在数据层（境界、属性、事件表=条件+概率+效果），叙事文本由 LLM 生成（对标万界道友/人生重开 AI 版） |
| D2 | **世界与角色** | 世界为一等公民，角色归入世界；数据模型新增 World 实体 |
| D3 | **首个里程碑** | 世界书 + 导入导出闭环（先验证「添加世界设定」与「导入玩法」两条数据管道，玩法层后置） |
| D4 | **世界书 MVP 字段** | 七件套先行：key / content / constant / order / probability / group(+groupWeight) / disable；正则、keysecondary 四态、递归扫描、定时效果、向量、characterFilter 等后置到玩法层阶段 |
| D5 | **玩家状态** | 数据层预留（World 实体上留 JSON 状态字段），里程碑一不实现玩法逻辑 |
| D6 | **存量兼容** | 角色可选挂世界；没挂世界的角色行为与现在完全一致；对话仍属于角色，不新建「世界对话」类型 |

> 注：用户对「大世界」方案（D2 形态）表示「与我的想法有出入，但也是一个很好的点」——出入点未展开，见未决事项 U1。

## 四、设计草案（待后续确认，非正式规格）

### 4.1 玩法包格式（草案）

```jsonc
{
  "format": "conver-world-pack/1",   // 版本化
  "world": {
    "name": "青云界·凡人修仙",
    "description": "灵气复苏的修仙世界……",
    "lorebook": {
      "entries": [
        { "key": "灵根", "content": "……", "constant": true },
        { "key": "筑基", "content": "……", "probability": 0.3 }
      ]
    }
  },
  "characters": [ /* 角色卡 V2 格式复用，世界内角色 */ ],
  "rules": { /* 后续里程碑：境界/属性/事件表 */ }
}
```

### 4.2 数据模型（草案）

```
World（世界：设定文本 + 世界书条目表 + 预留玩家状态 JSON）
  └─ 1:N Character（角色归入世界，角色卡 V2 格式复用）
       └─ 1:N Conversation（对话发生在世界内）
```

### 4.3 注入链（草案）

```
1. system prompt（角色）            ← 现有
2. [世界设定] world.description      ← 新增①（{{user}}/{{char}} 模板变量可用）
3. [世界知识] 激活的世界书条目        ← 新增②（按 order 排序，合并为一条 system 消息）
4. [场景设定] character.scenario    ← 现有
5. mes_example → 历史滑窗 → post_history_instructions → 当前输入
```

激活算法（每轮生成前）：扫描最近 N 轮消息 + 当前输入 → constant 直进 → 其余按 key 子串匹配命中 → 同 group 按权重抽选 / 无 group 按 probability 抽 → 按 order 排序 → token 预算截断（建议上下文 15% 或固定值，从低 order 截断）。

代码形态：`prompt.py` 新增纯函数 `build_world_injection(world_data, history)` 与 `activate_lorebook_entries(entries, scan_text)`；`build_messages` 增加可选参数 `world_injection`（默认 None，现有调用零改动）；`chat.py::prepare_chat` 负责查世界 → 组装注入块。

### 4.4 现状衔接点（已代码确认）

- 现有 `character_card.py` 把 `character_book` 作为非 V2 标准字段存 `extensions.conver_system` 命名空间**往返保真**（导入保留/导出带回，有测试锁定）——但**无任何代码消费**（不能编辑、不注入）。做 World 实体时条目字段语义直接对齐 SillyTavern lorebook，角色卡带的世界书可原样解析进世界书编辑器。

## 五、未决事项（后续讨论入口）

| # | 事项 | 说明 |
|---|------|------|
| U1 | **用户想法出入点** | 用户表示「大世界」方案与自己的想法有出入（未展开）——下次续谈首先对齐此处 |
| U2 | probability 与 group 交互语义 | 建议对齐 SillyTavern 原版（group=权重抽选互斥事件池 / probability=独立概率随机事件），未拍板 |
| U3 | 玩法层（rules）架构 | 事件表格式、境界/属性系统的通用建模（D1 混合驱动的落地形态） |
| U4 | 玩家视角 | 修仙/人生模拟需要「玩家状态」（用户作为主角），World 数据层已预留，具体形态待玩法层讨论 |
| U5 | 玩法包生态 | 玩法包导入的 UI 整合形态（「整合 UI」诉求的落地方案） |
| U6 | 世界书字段全集 | 后置字段（正则/递归/定时/向量）在玩法层阶段的补入顺序 |

## 六、下一步

- 续谈时从「五、未决事项」开始，优先 U1（对齐用户想法）。
- 正式立项后：决策进 CONSENSUS、工单进 TICKETS、技术事实进 docs/architecture.md 与 docs/llm-integration.md。
