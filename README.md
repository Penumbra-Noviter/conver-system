# Conver System · 移动端（mobile）

Conver System 的移动端应用（Flutter，Android + iOS 独立运行，无桌面后端依赖）。

## 状态

- **M5 已交付**（2026-09-07）：模拟器全量——22 款游戏随包种子 + 本地 HTTP 托管（127.0.0.1:8642 固定端口 + 路径穿越守卫 + Android/iOS 明文回环）+ 列表页四态/懒启动 + Key 自动注入（自包含 JS 脚本，桌面 key-injector 契约逐字 + claude key 恒不进游戏）+ 官方端点提示条 + 存档管理（底部 sheet 一次管全部 + 导出分享/导入/删除对齐桌面格式）+ 导入链（净化/去重/恶意拒绝二次确认）+ AI 生成（六项校验重试≤3）+「我」页收口（手册/关于/桌面版说明）；1315 测试全绿/analyze 0；M5 门冒烟 PASS（CORS 直连复验 + 杀进程存档持久化 + 五游戏 25 轮零崩溃 + 注入幂等 + 超时守卫）
- **M4 已交付**（2026-09-06）：导出/文档解析——聊天顶栏 ⋯ 菜单导出 JSON/MD（文件名角色名净化 + share_plus 分享面板 + 平台超时兜底）/ 向导「AI 智能解析」LLM 文档解析（三级提取+白名单+错误折叠）；802 测试全绿/analyze 0/冒烟 PASS（ShareSheet 弹出 ×2 + 临时文件生成 + 内容语义 + 超时兜底实测）
- **M3 已交付**（2026-08-30）：角色+搜索——角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板 / V2 卡导入导出（file_picker ^12.1.2 / share_plus ^13.3.0 / path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮；729 测试全绿/analyze 0/覆盖率剔除 drift 98.06%，冒烟 PASS（建角色→落库→搜索→跳转高亮真机实证）
- **M2 已交付**（2026-08-29）：聊天核心——LLM Provider 双协议 SSE wire（Claude/OpenAI 直连官方协议）+ ChatService 回合编排（滑窗/模板变量/重生成/停止/断流）+ 打字机 UI（两级降频）+ 最小临时会话入口 + 设置页测试连接；477 测试全绿/analyze 0/覆盖率手写口径 95.42%，模拟器冒烟窄路径 PASS（真实流式待配置 Key）。M5–M7 待办见 [TICKETS.md](TICKETS.md)
- **M1 已交付**（2026-08-29）：数据层 + 设置——4 仓储 CRUD 全语义（天然级联/聚合计数/自动命名副作用）、SecureStorage 双协议槽位（真实 Keystore 通道验证）、模型清单静态单源（8 provider/60 模型）、主题三值切换（auto/浅/深 + 浅色 token 全套），模拟器验收通过（Key 真通道往返/切主题即时生效/154 测试全绿）
- **M0 已交付**（2026-08-29）：Flutter 工程脚手架 + drift 4 表 + Warm Stone 深色主题 token + 5 tab 底部导航壳；应用 launcher 名「汇流」
- 权威设计文档：`docs/mobile-design.md`（架构 / 7 项功能全量 / 依赖清单 / M0–M7 里程碑）
- 技术调研：`docs/mobile-adaptation-research.md`
- 模拟器决策（ADR-0002）与桌面环境装载/验证记录见桌面端仓库：`desktop/CONSENSUS.md`、`desktop/DEV_LOG.md`

## 开发文档

- [项目规则](AGENTS.md) — 技术栈、目录约定、测试规范、档位制
- [项目介绍](PROJECT_REFERENCE.md) — 背景、关键决策、常碰坑点
- [设计文档](docs/mobile-design.md) — 架构、7 项功能、模拟器专题、里程碑 M0–M7（单一事实来源）
- [任务清单](TICKETS.md) — 唯一待办事实来源（M0–M7 已录入）
- [开发日志](DEV_LOG.md) — 已做与避坑
- [共识文档](CONSENSUS.md) — 决策登记与 ADR 索引
- [文档规范](docs/documentation-standards.md) — 单一事实来源分配与跨端引用约定

## 版本控制约定

本库为独立 git 历史（有别于桌面端 `main` 历史），托管于同源仓库

https://github.com/Penumbra-Noviter/conver-system.git

的 **`mobile` 分支**。推送即 `git push -u origin mobile`。

## 快速开始

前置：本机已装载 Flutter SDK（stable）与 Android SDK（环境变量 `JAVA_HOME` / `ANDROID_HOME`）。

```bash
# 1. 拉取依赖
flutter pub get

# 2. 运行测试（全绿为每票底线）
flutter test

# 3. 连接设备或启动模拟器后运行
flutter run

# 4. 构建 debug APK（产物在 build/app/outputs/flutter-apk/）
flutter build apk --debug
```