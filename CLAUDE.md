# Conver System — 项目规则

## 项目定位

本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。

## 技术栈

详见 [CONSENSUS.md](CONSENSUS.md) §技术选型。桌面端（Tauri）环境详见 [docs/tauri-setup.md](docs/tauri-setup.md)。

## 目录与约定

详见 [docs/architecture.md](docs/architecture.md) §目录结构

**关键约定**：
- 路由不直接操作 ORM，走 service 层
- 所有包 `__init__.py` 必须有 `__all__`
- 模块要"深"：协议表面小但实现丰富
- 新增 Provider：创建文件实现 BaseLLM → 在 `llm/__init__.py` 注册
- 公开函数必须有 type hints + docstring

## 怎么跑起来

```bash
source .venv/Scripts/activate   # Git Bash
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

访问 http://localhost:8000（Swagger：http://localhost:8000/docs）

## 当前状态（2026-08-06）

- ✅ Phase 1-5 + P6.1/6.2/6.3 + P2.5 全部完成
- ✅ 代码质量 CR.1-CR.7 清零
- ✅ 测试 157 用例通过（后端）+ 32 用例通过（前端）
- ✅ Rust 工具链已装（Tauri 前置就绪）
- ✅ UI 重设计：Warm Stone 暖灰 + 琥珀金 accent（温暖叙事风格）
- ✅ 新增用户手册视图（导航栏「手册」入口）

## 待办管理

唯一待办事实来源：`TICKETS.md`。DEV_LOG 只记"已做"，不存储待办。
