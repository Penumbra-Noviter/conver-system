# Conver System — 角色对话系统

一个**本地优先、多模型可切换**的角色对话应用。创建带设定的虚拟角色，与不同角色进行 AI 驱动的对话。

---

## 功能概览

- **角色管理** — 创建/编辑/删除角色，自定义人设（personality）、开场白、语气风格
- **多轮对话** — 与不同角色进行连续对话，保留完整历史
- **模板变量** — 角色设定中使用 `{{user}}`/`{{char}}` 动态替换用户昵称和角色名称
- **多模型支持** — 可切换 LLM Provider（Claude / OpenAI / 兼容 API）
- **流式输出** — 打字机效果逐字显示回复，支持停止生成
- **本地存储** — 所有数据存于本地 SQLite，无需联网依赖
- **API Key 管理** — 内置设置面板管理密钥

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
cp backend/.env.example .env    # 复制到项目根目录（config 相对 CWD 读取）
# 编辑 .env，填入基础配置；API Key 通过 UI 设置面板填写（存本地数据库）

# 5. 启动服务
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

打开浏览器访问 **http://localhost:8000**（Swagger 接口文档：http://localhost:8000/docs）

## 开发文档

- [文档规范](docs/documentation-standards.md) — 文档架构与单一事实来源规则
- [项目介绍](PROJECT_REFERENCE.md) — 背景、关键决策、常碰坑点
- [架构设计](docs/architecture.md) — 目录结构、数据流、数据库设计
- [API 接口设计](docs/api-design.md) — 所有 REST API 定义
- [LLM 集成设计](docs/llm-integration.md) — 多模型接入层架构

## 设计原则

- **本地优先** — 所有数据存本地，不依赖云端服务
- **Provider 透明** — LLM 接入层抽象化，切换模型不改业务代码
- **渐进增强** — 网页版做扎实后再考虑桌面端
- **配置内聚** — API Keys 通过 settings 接口管理，不硬编码
