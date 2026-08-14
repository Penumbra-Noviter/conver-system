# Conver System — 世界模拟扩展 · 探索记录（大版本方向草案）

> **定位**：大版本「角色对话 → 世界模拟平台」的方向探索记录（2026-08-13 首轮探讨存档）。
> **非正式规格**：本文件只记录讨论过程与已确认方向；正式立项时决策进 `CONSENSUS.md`、工单进 `TICKETS.md`、技术事实进 `docs/architecture.md` 等对应文档。后续继续探讨时从本文件「未决事项」续。
> **状态**：探索中（用户要求先存档，后续再续谈）。

---

## 一、背景与目标

用户提出大版本更新：在现有角色对话功能之外加入其他玩法的模块（如修仙设定模拟、人生模拟等），核心诉求：

1. 可以自己添加世界设定、玩法
2. 可以导入这种世界玩法，包括整合 UI 的功能

产品现状（2026-08-14）：本地优先角色对话应用（FastAPI + SQLAlchemy 同步 + SQLite + Vanilla JS ESM + Tauri 桌面壳），已支持 SillyTavern Character Card V2 导入/导出与 22 款模拟器集成模块（U7 批次交付 + U8/U9 二期完成：凭证注入/存档管理 + TD-57 信任边界文档化），测试基线 pytest 433+1skip + Vitest 714 + cargo test 58 全绿，无活跃待办。

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
| D7 | **模拟器集成模块（用户原始想法，原型已验证）** | 独立于角色对话的「模拟器」模块：静态托管单文件 HTML 模拟器 + manifest 元数据 + iframe 运行容器，供用户选择使用。2026-08-13 最小原型验证：网页版 + Tauri 桌面版全链路跑通（见 4.5） |

> 注：D2「大世界」与 D7「模拟器集成」是两条并行方向：D7 集成现成完整玩法（用户最初想法），D2 是用户自定义玩法（后续续谈，见未决事项 U1）。

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

### 4.5 模拟器集成最小原型（2026-08-13 验证完成，throwaway 分支 prototype/simulators-integration）

**形态**：用户下载的 22 个单文件 HTML 模拟器（50~330KB，`C:\Users\Administrator\Downloads\最新版本游戏本体\`）——100% 自包含（唯一外部引用是 data: favicon），两类驱动：
- **AI 驱动**（约半数）：游戏内置 `endpoint/apiKey/model` 配置面板（DOM id 模式 `*-endpoint`/`*-apikey`/`*-model`，如蛛网之影 `set-*`、人生模拟器 `cfg-*`），直连 OpenAI 兼容接口，key 用户自填
- **纯本地**：数值驱动，存档走 localStorage（游戏前缀隔离，如 `ls_`/`god_`/`urban_`）

**验证链路（全部实测通过）**：
1. 静态托管：游戏 HTML + manifest.json 放 `frontend/simulators/`，被现有根静态挂载（main.py:64）自动覆盖，后端**零改动**
2. 前端：`frontend/prototype-simulators.html`（throwaway 原型页）——列表（读 manifest）+ iframe 运行容器 + 验证状态面板
3. 网页版（Playwright）：列表渲染 ✓ / iframe 加载游戏 ✓ / **同源 DOM 直读**（游戏内部控件可探测）✓ / **同源 localStorage 读写**（游戏存档可用）✓ / AI 配置面板控件探测 ✓
4. **Tauri 桌面版**（tauri dev + WebView2 CDP 自动化）：完整链路重跑全通过——boot.html → 动态端口后端 → 同一套静态托管；**WebView2 无 CSP 拦截**（tauri.conf.json 未配 csp，内联脚本 + iframe 正常）

**桌面版 dev 模式坑（已实测，正式开发时注意）**：
- `CONVER_BACKEND_CMD` 覆盖后端命令时，**路径含空格必须用双引号包裹**（`set "CONVER_BACKEND_CMD="D:\...\python.exe" -m uvicorn ..."`，cmd 的 set 保留内部引号）；反斜杠转义 `\"` 会被 cmd 当字面量 → parse_command_line 拆出坏路径（os error 2 / "program path has no file name"）
- dev 模式壳的 cwd 是 src-tauri → 需 `CONVER_BACKEND_CWD` 指向仓库根；`python` 需解析到 venv（PATH 或 CONVER_BACKEND_CMD 显式指定）
- 壳用**动态端口**拉起后端（非固定 8000）；`WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--remote-debugging-port=9222` 可开 WebView2 CDP 调试口（playwright-core connectOverCDP 可自动化驱动窗口）

**原型产物**：`frontend/simulators/`（2 个示例游戏 + manifest.json）、`frontend/prototype-simulators.html`、`.scratch/` 下启动/验证脚本——提交在 throwaway 分支，主分支不含。

## 五、未决事项（后续讨论入口）

| # | 事项 | 说明 |
|---|------|------|
| U1 | **用户想法 vs 大世界方案** | 已澄清（2026-08-13）：用户最初想法 = 集成现成完整模拟器（D7，原型已验证）；「大世界/世界书」是用户认可的另一条方向，待后续展开 |
| U2 | probability 与 group 交互语义 | 建议对齐 SillyTavern 原版（group=权重抽选互斥事件池 / probability=独立概率随机事件），未拍板 |
| U3 | 玩法层（rules）架构 | 事件表格式、境界/属性系统的通用建模（D1 混合驱动的落地形态） |
| U4 | 玩家视角 | 修仙/人生模拟需要「玩家状态」（用户作为主角），World 数据层已预留，具体形态待玩法层讨论 |
| U5 | 玩法包生态 | 玩法包导入的 UI 整合形态（「整合 UI」诉求的落地方案） |
| U6 | 世界书字段全集 | 后置字段（正则/递归/定时/向量）在玩法层阶段的补入顺序 |
| U7 | 模拟器模块正式形态 | ✅ **已完成**（2026-08-14 U7 kickoff 交付：5 工单 3 波——侧栏入口/22 游戏入包/列表页/运行视图/冒烟脚本，见 [TICKETS.md](TICKETS.md) 归档） |
| U8 | 模拟器 LLM key 整合 | ✅ **已完成**（2026-08-14 U8+U9 二期交付：只读凭证端点 GET /api/settings/credentials + 运行视图「使用主应用 Key」一键注入） |
| U9 | 模拟器存档管理 | ✅ **已完成**（2026-08-14 U8+U9 二期交付：存档管理面板——列表/导出/导入/删除） |
| U10 | 内容授权 | ✅ **已完成（2026-08-14）**：作者已找到并确认——**授权二次转发与分享，不可商用**（22 个游戏）；授权记录见 README「第三方模拟器授权」 |
| U11 | 跨源沙箱 / postMessage 探索 | 模拟器同源信任边界的未来加固方向（TD-57 已文档化评估，见 [architecture.md](architecture.md)「模拟器信任边界（TD-57）」小节）——仅探索不立项 |

## 六、下一步

- 续谈时从「五、未决事项」开始，优先 U1（对齐用户想法）。
- 正式立项后：决策进 CONSENSUS、工单进 TICKETS、技术事实进 docs/architecture.md 与 docs/llm-integration.md。
