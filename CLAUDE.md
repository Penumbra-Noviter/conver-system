# Conver System — 项目规则

## 项目定位

本地优先、多模型可切换的角色对话应用。创建带人设的虚拟角色，与不同角色进行 AI 驱动的对话。

## 技术栈

详见 [CONSENSUS.md](CONSENSUS.md) §技术选型。桌面端（Tauri）环境详见 [docs/tauri-setup.md](docs/tauri-setup.md)。

## 目录与约定

详见 [docs/architecture.md](docs/architecture.md) §目录结构；领域术语见 [CONTEXT.md](CONTEXT.md)。

**关键约定**：
- 路由不直接操作 ORM，走 service 层
- 所有包 `__init__.py` 必须有 `__all__`
- 模块要"深"：协议表面小但实现丰富
- 新增 Provider：创建文件实现 BaseLLM → 在 `services/llm/factory.py` 的 `register_builtin_providers()` 显式注册（`main.py` on_startup 调用，`get_provider` 懒加载兜底）
- 前端动态模板/状态图标一律走 `js/icons.js` 的 `iconHtml()` seam（不手写 emoji/SVG 碎片）
- 公开函数必须有 type hints + docstring

## 怎么跑起来

```bash
source .venv/Scripts/activate   # Git Bash
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

访问 http://localhost:8000（Swagger：http://localhost:8000/docs）

测试：`cd backend && python -m pytest`（pytest 310+1skip）；`cd frontend && npm test`（Vitest 297，覆盖率 `npm run test:coverage`）；`cd src-tauri && cargo test`（46）。

## 当前状态（2026-08-12）

- ✅ Phase 1-5 + P6.1/6.2/6.3 + P2.5/3.5 + P4.3 + P6.4 全部完成
- ✅ 架构深化两波（ARC-1~8：StreamSession/级联/标题/export/api seam/展示契约/app 拆分/__init__）+ 架构摩擦 11 候选（前端模块化 + 服务层解耦）
- ✅ P6.5 多 tab 会话管理（tabs 工作区深模块 + 防悬挂写回 + sessionStorage 恢复）
- ✅ OPT-1 UI 克制化与图标协议收口（icons.js seam + emoji 清除 + 主题 token 单一来源），GUI 黑盒回归全过
- ✅ P6.4 Tauri 桌面版已交付（8 工单归档，2026-08-11）：Tauri v2 壳 + PyInstaller 打包后端 + NSIS 安装器；期末 2 阻断（后端随包定位、前端随包挂载）已修复，安装器形态冒烟 5 项全过。详见 [docs/tauri-desktop.md](docs/tauri-desktop.md)
- ✅ **ARC9 架构深化批次（6 Strong 候选，2026-08-12）**：T-01 搜索视图/级联删除收口（search-view.js/cascade.js 深模块，app.js 735→610 行）+ T-02 流式/非流式统一结算 settleTurn + T-03 非流式收进 service（complete_chat/chat_error_response 单一错误源）+ T-04 数据目录四套统一（契约表 v2，期末审核 1 阻断修复：URL 编码收窄至仅 `?` + 连接级测试）+ T-05 冒烟清理收口（desktop-common.ps1 端口限定）+ T-06 编排区测试挂网（+73 用例，coverage 接线）；期末四轴审核 1 阻断修复放行
- ✅ 测试：pytest 310+1skip（后端）+ Vitest 297（前端）+ cargo test 46（壳）全绿

## 待办管理

唯一待办事实来源：`TICKETS.md`。DEV_LOG 只记"已做"，不存储待办。
