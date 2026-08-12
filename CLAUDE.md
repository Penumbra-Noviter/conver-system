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
- 新增 Provider：在 `services/model_data.py` 的 `AVAILABLE_MODELS` 登记（唯一声明源，factory 注册与 setting API map 自动派生）；独立实现类时在 `services/llm/factory.py::_CLASS_OVERRIDES` 挂覆盖（注册在 `register_builtin_providers()`，`main.py` on_startup 调用，懒加载兜底；Provider 类不从 `llm/__init__.py` 包路径导入——包级导入零 SDK 副作用契约）
- 前端动态模板/状态图标一律走 `js/icons.js` 的 `iconHtml()` seam（不手写 emoji/SVG 碎片）
- 公开函数必须有 type hints + docstring

## 怎么跑起来

```bash
source .venv/Scripts/activate   # Git Bash
uvicorn backend.app.main:app --reload --host 127.0.0.1 --port 8000
```

访问 http://localhost:8000（Swagger：http://localhost:8000/docs）

测试：`cd backend && python -m pytest`（pytest 360+1skip）；`cd frontend && npm test`（Vitest 371，覆盖率 `npm run test:coverage`）；`cd src-tauri && cargo test`（52）。

## 当前状态（2026-08-12）

- ✅ Phase 1-5 + P6.1/6.2/6.3 + P2.5/3.5 + P4.3 + P6.4 全部完成
- ✅ 架构深化两波（ARC-1~8：StreamSession/级联/标题/export/api seam/展示契约/app 拆分/__init__）+ 架构摩擦 11 候选（前端模块化 + 服务层解耦）
- ✅ P6.5 多 tab 会话管理（tabs 工作区深模块 + 防悬挂写回 + sessionStorage 恢复）
- ✅ OPT-1 UI 克制化与图标协议收口（icons.js seam + emoji 清除 + 主题 token 单一来源），GUI 黑盒回归全过
- ✅ P6.4 Tauri 桌面版已交付（8 工单归档，2026-08-11）：Tauri v2 壳 + PyInstaller 打包后端 + NSIS 安装器；期末 2 阻断（后端随包定位、前端随包挂载）已修复，安装器形态冒烟 5 项全过。详见 [docs/tauri-desktop.md](docs/tauri-desktop.md)
- ✅ **ARC9 架构深化批次（6 Strong 候选，2026-08-12）**：T-01 搜索视图/级联删除收口 + T-02 settleTurn 统一结算 + T-03 complete_chat/chat_error_response + T-04 数据目录契约表 v2（期末 1 阻断修复）+ T-05 冒烟清理收口 + T-06 编排区测试挂网；期末四轴 1 阻断修复放行
- ✅ **ARC10 架构深化批次（剩余 8 候选，2026-08-12）**：T-11 modal 骨架收口（C3-DEFER 兑现）+ T-12 character-submit 提交收敛 + T-13 微重复收口（resize/空态/onerror）+ T-14 Provider 清单单一来源（AVAILABLE_MODELS 派生 + 包导出收缩零 SDK 副作用）+ T-15 统一 exception handler（api/errors.py）+ T-16 style.css 覆盖区归位 + --on-danger token + T-17 schema 快照漂移检测 + T-18 聚焦序列收口；期末四轴 0 阻断放行；GUI 冒烟（modal 骨架/错误气泡深浅主题/输入框复位/级联）全过
- ✅ **技术债区 TD-13~14 批次（2026-08-12 全自动 kickoff）**：2 做 + TD-9 顺带闭环——TD-13 save 回调入口统一守卫（11 元素收集 + :339 收口；+2 用例先红后绿）/ TD-14 契约措辞 pathlib 规范化注记 + 契约锁用例；TD-9 维持→做（入口守卫覆盖其调用点，本体零改动）；期末四轴 0 阻断；10 项新遗留（TD-15~24）入技术债区
- ✅ 测试：pytest 360+1skip（后端）+ Vitest 371（前端）+ cargo test 52（壳）全绿

## 待办管理

唯一待办事实来源：`TICKETS.md`。DEV_LOG 只记"已做"，不存储待办。
