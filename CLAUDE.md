# Conver System — 项目规则

## 项目定位

本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。

## 怎么跑起来

```bash
# 激活虚拟环境
source .venv/Scripts/activate   # Git Bash
# 或 .venv\Scripts\activate     # PowerShell

# 启动服务
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

访问 **http://localhost:8000**（Swagger：http://localhost:8000/docs）

## 技术栈

- **后端**：FastAPI + SQLAlchemy 2.0（同步 ORM）+ SQLite + Pydantic v2
- **前端**：HTML + Vanilla JS (ESM)，无框架
- **LLM**：anthropic + openai SDK，自定义 Provider 抽象层
- **桌面端**：Tauri（Rust 工具链已装，见 `PROJECT_REFERENCE.md` 第五章）

## 目录与约定

```
backend/app/
├── api/routes/     # 路由层（HTTP 映射，不含业务逻辑）
├── models/         # SQLAlchemy ORM 模型
├── schemas/        # Pydantic 请求/响应模型
├── services/       # 业务逻辑（ORM 操作）
│   └── llm/        # LLM Provider 抽象 + 工厂
└── config.py       # pydantic-settings
```

**关键约定**：
- 路由不直接操作 ORM，走 service 层
- 所有包 `__init__.py` 必须有 `__all__`
- 模块要"深"：协议表面小但实现丰富
- 新增 Provider：创建文件实现 BaseLLM → 在 `llm/__init__.py` 注册
- 公开函数必须有 type hints + docstring

## 当前状态（2026-08-03）

- ✅ Phase 1-5 + P6.1/6.2/6.3 + P2.5 全部完成
- ✅ 代码质量 CR.1-CR.7 清零
- ✅ 测试 117 用例通过
- ✅ Rust 工具链已装（Tauri 前置就绪）
- ⏳ 下一步：P6.4 Tauri 桌面端 / P6.5 多 tab 会话

## 待办管理

唯一待办事实来源：`TICKETS.md`。DEV_LOG 只记"已做"，不存储待办。
