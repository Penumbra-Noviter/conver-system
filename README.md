# Conver System — 角色对话系统

一个**本地优先、多模型可切换**的角色对话应用。创建带设定的虚拟角色，与不同角色进行 AI 驱动的对话。

**当前版本：1.1.0**

---

## 功能概览

### 角色与对话

- **角色管理** — 创建/编辑/删除角色，自定义人设（personality）、开场白、语气风格；六步创建向导 + SillyTavern V2 角色卡导入/导出
- **多轮对话** — 与不同角色进行连续对话，保留完整历史；多 tab 会话工作区，后台流式继续生成，刷新后恢复
- **消息操作** — 对话内模型切换、重生成、继续生成（追加续写）；消息编辑重发与单条删除（删除用户消息连带截断其后，删除 AI 消息仅删该条）
- **候选回复（swipes）** — 一条 AI 回复可保留多个候选版本，随时切换查看；重生成与续写均以候选形式追加，不丢历史
- **分支会话** — 从任意消息处派生新分支；会话快照导出/导入（JSON），可离线备份或迁移会话
- **模板变量** — 角色设定中使用 `{{user}}`/`{{char}}` 动态替换用户昵称和角色名称
- **搜索历史消息** — 跨对话关键词搜索，点击结果自动跳转到命中消息并短暂高亮定位

### 上下文与增强

- **世界书（Lorebook）** — 角色级世界设定条目，按关键词/深度自动激活注入上下文；内置记忆宫殿，对话过程中自动沉淀重要信息
- **Mod 挂载** — 按角色挂载提示词（prompt）/记忆（memory）/样式（css）三类 Mod；prompt Mod 叠加进注入链，memory Mod 增强归纳指令，css Mod 注入会话内样式
- **叙述风格与预设对话** — 角色可配置叙述风格（人设/场景双键）与预设对话样例（few-shot），对话开头自动带入，提升角色一致性
- **采样参数** — 每对话可调 top_p / presence_penalty / frequency_penalty / max_tokens，随对话持久化
- **Prompt Debug 面板** — 查看当前对话实际组装给模型的完整消息链，便于调教提示词

### 图像生成（CG）

- **对话内出图** — 会话中直接生成角色图像（支持 A1111 兼容 API；未配置时可用内置本地占位生成器）
- **CG 画廊** — 每角色独立的 CG 资产库与剧情回顾时间线；未解锁条目灰态占位
- **自动出图** — 回合结束时可按概率自动触发出图（设置内开关）

### 基础能力

- **多模型支持** — 可切换 LLM Provider（Claude / OpenAI / 兼容 API），设置面板管理 Key（存本地数据库）
- **流式输出** — 打字机效果逐字显示回复，支持停止生成
- **首启引导与错误提示** — 未配置 AI 接口时显示引导卡直达设置页；操作失败以可关闭的错误条提示
- **本地存储** — 所有数据存于本地 SQLite，无需联网依赖
- **模拟器** — 22 款文字模拟器浏览/类型筛选/一键 iframe 运行；AI 驱动游戏自动同步主应用接口 Key；导入第三方 `.html` 文件时自动识别类型（AI 驱动/纯本地），误判可重新识别；存档管理面板（导出/导入/删除）；导入游戏存外置数据目录（仅本地文件 ≤5MB，SHA-256 去重、冲突自动改名，风险与适配见程序内「导入游戏与安全须知」）

## 快速开始

```bash
# 1. 克隆项目
git clone https://github.com/Penumbra-Noviter/conver-system.git
cd conver-system

# 2. 创建虚拟环境
python -m venv .venv
source .venv/Scripts/activate   # Windows (Git Bash)
# 或 .venv\Scripts\activate     # Windows (PowerShell)

# 3. 安装依赖
pip install -r backend/requirements.txt

# 4. 配置环境变量
cp backend/.env.example .env    # 复制到项目根目录（config 相对 CWD 读取）
# 编辑 .env，填入基础配置；API Key 通过 UI 设置面板填写（存本地数据库）

# 5. 启动服务
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

打开浏览器访问 **http://localhost:8000**（Swagger 接口文档：http://localhost:8000/docs）

> **桌面版**：Windows 桌面应用（Tauri 壳 + 打包后端）已交付，一键构建与冒烟见 [桌面版文档](docs/tauri-desktop.md)。

## 测试

```bash
cd backend && python -m pytest        # 后端：pytest 1356（含 1 skip）
cd frontend && npm test               # 前端：Vitest 1472
cd src-tauri && cargo test            # Tauri 壳：70
```

## 开发文档

- [项目介绍](PROJECT_REFERENCE.md) — 背景、关键决策、常碰坑点
- [架构设计](docs/architecture.md) — 目录结构、数据流、数据库设计
- [API 接口设计](docs/api-design.md) — 所有 REST API 定义
- [LLM 集成设计](docs/llm-integration.md) — 多模型接入层架构
- [对话/模拟器升级规格](docs/chat-simulator-upgrade-spec.md) — 世界书/swipes/分支/CG/Mod 五批对标规格
- [Prompt 打磨规格](docs/prompt-polish-spec.md) — 预设开场白/Prompt Debug/专家模式规格
- [桌面版构建与冒烟](docs/tauri-desktop.md) — Tauri 桌面版构建链、数据目录、已知限制
- [Tauri 环境搭建](docs/tauri-setup.md) — Rust 工具链安装与构建注意事项
- [文档规范](docs/documentation-standards.md) — 文档架构与单一事实来源规则

## 许可

本程序采用 **MIT 许可协议**，详见 [LICENSE](LICENSE) 文件。

内置的 22 款文字模拟器为第三方作者作品，其授权范围见 [NOTICE.md](NOTICE.md)。

## 设计原则

- **本地优先** — 所有数据存本地，不依赖云端服务
- **Provider 透明** — LLM 接入层抽象化，切换模型不改业务代码
- **渐进增强** — 网页版为先，桌面端已交付（Tauri 壳 + PyInstaller 打包后端，前端零改动）
- **配置内聚** — API Keys 通过 settings 接口管理，不硬编码

## 第三方模拟器授权

模拟器模块内置的 22 款文字模拟器为第三方作者作品（来源：作者公开分享的单文件 HTML 游戏）。**作者已确认授权（2026-08-14）：允许二次转发与分享，不可商用**。本应用不修改游戏本体内容（仅静态托管 + iframe 运行），分发时请保留本条授权说明；商用用途请联系原作者另行授权。
