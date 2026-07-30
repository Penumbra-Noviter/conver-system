# Conver System — 项目介绍书

## 一句话

一个**本地优先、多模型可切换**的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。

## 目标用户

- **首要**：自己用
- **次要**：开源后供感兴趣的个人用户部署使用

## 核心能力

- **角色管理**：创建/编辑/删除角色，自定义人设、开场白、语气风格。支持 SillyTavern Character Card V2 格式导入/导出。
- **多轮对话**：与不同角色连续对话，历史消息完整保留，支持滑动窗口上下文联控。
- **多模型支持**：统一 LLM 接入层，支持 Claude / OpenAI（含兼容 API），未来可扩展。
- **流式/非流式输出**：用户可切换打字机效果或完整回复。
- **本地存储**：所有数据（含 API Key）存本地 SQLite，不依赖任何云端服务。
- **API Key 管理**：内置设置面板管理密钥，运行时修改即时生效。

## 技术栈

| 层 | 技术 |
|----|------|
| 后端框架 | FastAPI (Python) |
| ORM | SQLAlchemy 2.0 (async) |
| 数据库 | SQLite + aiosqlite |
| LLM SDK | anthropic + openai |
| 配置管理 | pydantic-settings |
| 前端 | HTML + CSS + Vanilla JS (ESM) |
| 服务 | uvicorn |

## 设计原则

- **本地优先** — 不依赖任何云端服务
- **Provider 透明** — LLM 接入层抽象化，切换模型不改业务代码
- **渐进增强** — 网页版做扎实后再考虑桌面端
- **配置内聚** — API Keys 通过 UI 管理，不硬编码

## 当前阶段

✅ **全部 Phase 1-5 + P6.1/6.2/6.3 已完成** (`mem:features` 查看完整功能清单)

当前代码处于 **Phase 6 增强功能阶段**，剩余待开发模块：Ollama 本地模型支持、多 tab 会话管理、Tauri 桌面版。

## 路线图

```
Phase 1 ▸ 骨架搭建     → ✅ 可运行的全栈 SPA
Phase 2 ▸ 角色管理     → ✅ 角色 CRUD + 前端表单 + 删除确认
Phase 3 ▸ 对话核心     → ✅ LLM 接入 + 流式/非流式 + 上下文管理
Phase 4 ▸ 多模型支持   → ✅ OpenAI + 模型选择 UI + Provider 工厂
Phase 5 ▸ 体验完善     → ✅ 主题/响应式/快捷键/Markdown/导出按钮
Phase 6 ▸ 增强功能     → ✅ 对话导出/消息搜索/模板变量已完成，桌面端/其他待开发
```

## 相关文档

- [共识文档](CONSENSUS.md) — 所有设计决策
- [开发日志](DEV_LOG.md) — 进度和踩坑记录
- [架构设计](docs/architecture.md)
- [API 接口设计](docs/api-design.md)
- [LLM 集成设计](docs/llm-integration.md)
- [开发路线图](docs/development-plan.md)

## 快速开始

```bash
python -m venv .venv
source .venv/Scripts/activate
pip install -r backend/requirements.txt
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

打开 http://localhost:8000
