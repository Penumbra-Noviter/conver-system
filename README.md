# Conver System — 角色对话系统

一个**本地优先、多模型可切换**的角色对话应用。创建带设定的虚拟角色，与不同角色进行 AI 驱动的对话。

---

## 功能概览

- **角色管理** — 创建/编辑/删除角色，自定义人设（personality）、开场白、语气风格
- **多轮对话** — 与不同角色进行连续对话，保留完整历史
- **模板变量** — 角色设定中使用 `{{user}}`/`{{char}}` 动态替换用户昵称和角色名称
- **多模型支持** — 可切换 LLM Provider（Claude / OpenAI / 兼容 API）
- **流式输出** — 打字机效果逐字显示回复
- **本地存储** — 所有数据存于本地 SQLite，无需联网依赖
- **API Key 管理** — 内置设置面板管理密钥

## 技术栈

| 层次 | 技术 |
|------|------|
| 后端框架 | FastAPI (Python) |
| 数据库 | SQLite + SQLAlchemy 2.0 |
| LLM 接入 | Claude / OpenAI（抽象层，可扩展） |
| 前端 | HTML + CSS + Vanilla JS (ESM) |
| 服务端 | uvicorn |

## 快速开始

```bash
# 1. 克隆项目
git clone <repo-url>
cd conver-system

# 2. 创建虚拟环境
python -m venv .venv
source .venv/Scripts/activate   # Windows (Git Bash)
# 或 .venv\Scripts\activate     # Windows (PowerShell)

# 3. 安装依赖
pip install -r backend/requirements.txt

# 4. 配置环境变量
cp backend/.env.example backend/.env
# 编辑 .env，填入你的 API Key

# 5. 启动服务
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

打开浏览器访问 **http://localhost:8000**

## 开发文档

- [架构设计](docs/architecture.md) — 目录结构、数据流、数据库设计
- [API 接口设计](docs/api-design.md) — 所有 REST API 定义
- [LLM 集成设计](docs/llm-integration.md) — 多模型接入层架构
- [开发路线图](docs/development-plan.md) — Phase 划分与详细任务

## 项目路线

```
Phase 1 ▸ 骨架搭建     → 可运行的空壳
Phase 2 ▸ 角色管理     → 能管理角色人设
Phase 3 ▸ 对话核心     → 能聊天 🎉
Phase 4 ▸ 多模型支持   → 自由切换模型
Phase 5 ▸ 体验完善     → 好用
Phase 6 ▸ 增强功能     → 导出/搜索/模板变量已完成，桌面版/其他待开发
```

## 设计原则

- **本地优先** — 所有数据存本地，不依赖云端服务
- **Provider 透明** — LLM 接入层抽象化，切换模型不改业务代码
- **渐进增强** — 网页版做扎实后再考虑桌面端
- **配置内聚** — API Keys 通过 settings 接口管理，不硬编码
