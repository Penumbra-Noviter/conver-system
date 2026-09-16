# Conver System 移动端 — 项目规则

## 项目定位

Conver System 的**移动端独立应用**（Flutter，Android + iOS 一套 Dart 代码）。手机独立运行：无桌面 FastAPI 后端依赖，App 内 `dart:io` 直连公网 HTTPS LLM API，复刻桌面版全部 7 项功能（不阉割）：聊天 SSE / 角色 / 搜索 / 设置 / 文档解析 / AI 生成游戏 / 模拟器。

## 技术栈

Flutter + Dart（详见 [CONSENSUS.md](CONSENSUS.md) 与设计文档 [docs/mobile-design.md](docs/mobile-design.md) §0/§2.2）：`drift`（SQLite ORM）、`provider`（状态管理）、`flutter_secure_storage`（Key）、`dio`（REST，非流式）、`flutter_markdown_plus`（聊天 Markdown 渲染）已落地；`file_picker`（^12.1.2）/ `share_plus`（^13.3.0）/ `path_provider`（^2.1.6）已随 M3-03 转正入 pubspec（V2 卡导入导出）；`webview_flutter`（^4.14.1）与 `crypto`（^3.0.7，SHA-256）已随 M5-01 落地（模拟器 WebView 桥 + 导入去重）。模拟器业务逻辑集中在 `lib/services/simulator/`（data_dir / seed / manifest_parser / contracts / server / injection / save / import / generate，纯 Dart 可单测），平台薄层（WebView 桥、本地 HTTP 服务器）经 seam 隔离。

## 目录与约定

按 [docs/mobile-design.md](docs/mobile-design.md) §2.1 的 `lib/` 分层：`theme` / `models` / `data` / `services` / `view_models` / `views` / `widgets`。

**关键约定**：
- 模块要"深"：协议表面小、实现丰富；`services/` 承载纯 Dart 业务逻辑（可单测），`views/` 只做展示编排
- 公开函数必须有类型注解 + docstring（Dart 写法）；私有成员 `_` 前缀
- 业务逻辑用英文命名，UI 层枚举可用中文（沿用全局惯例）
- 平台薄层（WebView 桥、SecureStorage、本地 HTTP 服务器）集中隔离在 `services/simulator_bridge.dart` 等 seam 之后，不散落进 views
- UI 复刻桌面 "Warm Stone 暖灰 + 琥珀金" 设计系统（§5 token 表），禁"AI 味"（见 §5.2 清单）

## 怎么跑起来

```bash
flutter pub get
flutter test                 # 宿主无头跑，无需模拟器（验证分层见 §7.1）
flutter run -d <serial>      # Android 模拟器/真机（adb）
flutter build apk            # 产物（需 Android SDK/JDK，本机已装于 D:\Desktop\tools\Cache）
```

iOS 需 macOS + Xcode（Windows 开发机不可行，走 CI/借 Mac）。

## 测试规范

- `flutter test`（纯 Dart 单测 + 无头 widget 测试），覆盖率目标 ≥ 90%
- 业务逻辑（chat/llm/数据层/导入链/生成校验）占比最大且是纯 Dart → 可靠性主要由单测兜底；平台薄层做真机/模拟器验证

## 当前状态（2026-09-15）

- ✅ 设计已落盘：`docs/mobile-design.md`（单一事实来源）+ `docs/mobile-adaptation-research.md`（决策背景）；决策集 Q0~Q14 已拍板，ADR-0002 见桌面库 `desktop/CONSENSUS.md`
- ✅ 工具链就绪（D:\Desktop\tools\Cache：JDK17/Gradle8.9/SDK35+36+37/AEHD + Flutter 3.47.2；AVD medium_phone 数据已迁至 F:\tools\android\avd，2026-09-04；MCP 插件 preflight 全绿）
- ✅ **M0 已交付**（2026-08-29）：脚手架 + drift 4 表 + 深色主题 token + 5 tab 壳（应用名「汇流」），G0 模拟器空壳验收全项通过
- ✅ **M1 已交付**（2026-08-29）：4 仓储 CRUD 全语义 + SecureStorage 双槽位 + 模型清单单源 + 主题三值切换（auto/浅/深），G1–G5 门 + G6 模拟器冒烟全项通过；merge 收口 a1d4265
- ✅ **技术债批次 F-7/F-8/F-9 已交付**（2026-08-29）：视图 token 主题化（ConverPalette ThemeExtension）+ 设置页错误面 + 装配 required 化，全量 171 测 / 覆盖率手写口径 90.63% / 四轴零阻断 / 冒烟 PASS；merge 68e8d19
- ✅ **M2 已交付**（2026-08-29）：聊天核心——LLM Provider 双协议 SSE wire（Claude/OpenAI 直连）+ ChatService 回合编排（滑窗/模板变量/重生成/停止/断流）+ 打字机 UI + 最小临时会话入口 + test_connection；全量 477 测 / 覆盖率手写口径 95.42% / 四轴零阻断 / A7 冒烟窄路径 PASS（真实流式留待 Key）；merge 59e766a
- ✅ **技术债批次 F-10~F-17 已交付**（2026-08-30）：7 做 1 关闭 / 6 工单 2 波 merge b9dc9bc / 全量 497 测 / analyze 0 / 覆盖率剔除 drift 97.96% / 四轴零阻断 / 冒烟 PASS / TICKETS 已归档 / 技术债候选区清零
- ✅ **M3 已交付**（2026-08-30）：角色 + 搜索——角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板 / V2 卡导入导出（file_picker ^12.1.2 / share_plus ^13.3.0 / path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮；全量 729 测 / analyze 0 / 覆盖率剔除 drift 98.06% / 四轴零阻断 / 冒烟 PASS（建角色→落库→搜索→跳转高亮真机实证）；merge 70bc094 + 期末修复 0057d9e/9cfc4aa；TICKETS 已归档
- ✅ **M4 已交付**（2026-09-06）：导出/文档解析——对话导出 JSON/MD（share_plus 分享面板 + 平台超时兜底）/ LLM 文档解析（三级提取+白名单+错误折叠）；全量 802 测 / analyze 0 / M4-06 冒烟 PASS；merge 42099eb + 25c7696 + 修复 1feddd7
- ✅ **M5 已交付**（2026-09-07）：模拟器全量——22 款随包种子 + 本地 HTTP 托管（127.0.0.1:8642 + 目录墙 + 双端明文工）+ 列表四态/懒启动 + Key 注入（桌面契约逐字 + claude key 不进 + 官方端点提示）+ 存档管理 + 导入链 + AI 生成 + 「我」页收口；全量 1315 测 / analyze 0 / M5 门冒烟 PASS（CORS 复验 + 持久化 + 五游戏 25 轮零崩溃）；11 票 7 波合入收口 3d34ed2；TICKETS 11 票已归档
- ✅ **M6 已交付**（2026-09-08）：去 AI 味打磨——动效克制子集 8 项（ConverDurations 对齐桌面、零动画库）+ 空态/错误态/弱网断线重连（连接重试 2 次退避 1s/2s + 断流「回复中断」标记 + NoticeBanner 重试=regenerate replace + idle 60s）+ 实用层无障碍（F-73 浅色 accent #784E14 对比度 ≥4.5:1 + a11y 语义 15 断言）；全量 1460 测 / analyze 0 / 覆盖率 96.78% / 期末四轴阻断 0 / M6 门视觉评审 8/8 PASS（含 B1 核心路径模拟器实测）；11 票 7 波 + B1×2 合入收口（收官 5e7bd33）；TICKETS M6 已归档
- ✅ **M7 已交付**（2026-09-09，Android 范围收窄、iOS 延后）：自适应启动图标（PIL 管线程序化生成「汇」字形占位稿 + flutter_launcher_icons adaptive/monochrome/legacy，确定性可再生）+ release 签名（仓库外 keystore「F:\Craft\conver system\keys\」+ gitignored key.properties，AAB/APK 同证书）+ 隐私清单（docs/privacy-android.md 三节式 + 零第三方 SDK 实证审计）+ 发布验证门禁（docs/release-android.md 版本策略 1.0.0+1 / versionCode=1 + 双产物命令链 + AVD 冒烟 PASS）；发布构建见 `flutter build appbundle|apk --release`；全量 1518 测绿 / analyze 0 / pytest 57 / 期末四轴 0 阻断。iOS 全部延后（Windows 无 macOS 路径，design §7.1），仅 TICKETS 注记（iOS 图标/签名/隐私/上架未建产物）
- ✅ **真机问题批次已收口**（2026-09-10）：测试连接传 default_model + 注入 toProxyEndpoint 同源改写 + server /proxy 流式反代（全相位超时 60s + key App 侧注入 + SSE 透传）；全量 1612 测绿 / analyze 0 / 真实端点链路 200 PASS / 期末四轴 0 阻断；merge 265e305/8ead524/6cb3885 + 超时修复 fd3820b
- ✅ **技术债折回 F-68~74 已全部处置**（2026-09-10）：F-68/69/70 消费（release 签名守卫 + 图标色值双向守卫 + privacy_audit 删 Speculative 分支）+ F-71/72/74 复核关闭 + F-73 交叉校验测试；候选区清零；全量 1613 测绿 / analyze 0 / pytest 66
- ✅ **架构审查批次 C1~C4 已收口**（2026-09-10）：translateError 下沉 LLMProvider 基类默认实现 / 装配腿收敛（wireCredentialsResolver 单一落点）/ 双文件名净化器参数化合并 / 删 PlaceholderGroup + settings 行收敛；全量 1579 测绿（+61）/ analyze 0 / 期末四轴 0 阻断；落债 F-72
- ✅ **U-UX 补全批次已收口**（2026-09-14）：聊天首页角色选择条 + 会话重命名/删除 / LLMProvider 补 temperature 参数（15 子类）+ 全局 temperature/max_tokens（角色级为主、全局兜底）/ 模板变量 extraVars 全局替换管线 + 编辑页 / 首次启动分页新手指引（启动门 + 跳过持久化）；全量 1681 测绿 / analyze 0 / 期末四轴 0 阻断（修复 F-73 色彩契约回归 eb7b119）；commit b302fb3 / 6abcb6d+126e09d / ced8253 / e6cf008+1dbd0ef
- ✅ **技术债消费批次 F-75/F-76/F-77 已全部处置**（2026-09-14）：F-76 消费（_resolveTemperature 加 NaN/Infinity 回退全局 + 越界 clamp [0,2]）+ F-75/77 复核关闭（种子 HTML 内容资产 CSS / SettingsReader implements 成本）；候选区清零；全量 1684 测绿（+3）/ analyze 0
- ✅ **人机恋阶段 1 MVP 已交付**（2026-09-15，角色对话增强）：记忆 prompt 指令驱动（`<add>`/`<persona>`/`<search>`）+ 每轮重注入人格事实抗 OOC + 人设演化（PersonaRevisions 版本化 + 用户确认闸门）+ 角色卡「记忆」管理页；AC-01~AC-05 全落地（schemaVersion 1→2 + MemoryEntries/PersonaRevisions + MemoryService + PersonaEvolutionService）；全量 1725 测绿 / analyze 0；主动消息/关系状态/内心独白留阶段 2；ADR-0003 见 docs/adr-0003-ai-companion.md；调研见 docs/ai-companion-research.md
- ✅ **人机恋阶段 1.5 已交付**（2026-09-15，后台反思提取）：每 6 回合异步 LLM 提炼人格事实落 `persona_fact`（默认关闭、仅人格事实、去重、失败降级）；ReflectionService（seam 化）+ ChatService 挂点 + settings 开关 `memory_reflection_enabled` + 设置页 UI；全量 1740 测绿 / analyze 0；ADR-0004 见 docs/adr-0004-ai-companion-reflection.md
- ✅ **人机恋阶段 2 已交付**（2026-09-15，主动消息/关系状态机/内心独白）：主动消息循环（回合末异步规划单次产出 + OS 本地通知排程 + 深链进对话 + 启动排程恢复，后台零 LLM）、关系状态机（五段枚举 + 启发式零 LLM + 亲密/挚爱服务层确认闸门 + 角色卡进度展示与拒绝记忆 Broker 上提）、内心独白（`<thought>` 恒剥离落独立表 + 开关）；三新表 schemaVersion 3 迁移 + CompanionRepository + companion 三服务 + notifications 平台薄层（flutter_local_notifications 22.3.1 / timezone 0.11.1 钉版）+ 三份 ADR；威胁建模 SR-01~15 P0 全落地（深链 payload 零内容/归属校验/发送幂等/排程恢复——装配启动副作用经 W6-F1 修复 lazy:false 实跑）；ADR-0005/0006/0007 见 docs/adr-0005/0006/0007-ai-companion-*.md
- ✅ **技术债消费批次已交付**（2026-09-16，F-84/F-85/F-88 + F-83 并批）：通知域收尾——F-88 送达收口放宽（markDeliveredByMessageId 白名单 scheduled∪expired，冷启动点按已过期通知不再吞收口）+ F-84 三件套（热态点按经 onDidReceiveNotificationResponse → consumeProactiveNotificationResponse 复用 handleProactiveDeepLink 共享路径；Android 13+ 权限开关启用时请求；schedule 契约 Future<bool> + onScheduleFailed → 「通知排程失败」SnackBar，恢复路径静默）+ F-85 深链 id 正值域 + F-83 restore expired 分支 per-plan 降级（SR-08 完整）；F-86/F-87 复核关闭，期末四轴落债 F-89/F-90；全量 **1974 测**绿 / analyze 0；详见 DEV_LOG〈技术债消费批次 F-84/F-85/F-88 + F-83〉
- ✅ **技术债消费批次已交付**（2026-09-17，F-78/F-79/F-80/F-81/F-82/F-90 并批）：数据层/设置 UI/伴侣域六债收口——F-78 迁移注释纠偏（drift onUpgrade 非事务 + 幂等自愈三机制实证语义）+ F-79 迁移中断残留重开自愈用例（表/索引/版本/旧行四要素）+ F-80 后台反思写失败回滚 UI 契约（生产零 diff）+ F-81 活跃时间查询单源 `MessageRepository.latestMessageAt`（join 单查询 + 两服务改调 + 乱序证伪增强，零装配）+ F-82 confirm 档位下限 clamp 消除 stage/affinity 中间态（floorForStage + 先红后绿 58→59/78→79 实锤 + 反向自洽断言）+ F-90 通知热态回调契约防御（_hotCallbackRegistered OR 置位 + 早退告警 + 插件覆盖赋值实证纠偏注释）；F-89 复核关闭；期末四轴 0 阻断落债 F-91~97；全量 **1987 测**绿（+13）/ analyze 0；详见 DEV_LOG〈技术债消费批次 techdebt-f78f90〉

## 文档体系

标准档：CLAUDE（本文件）/ [PROJECT_REFERENCE.md](PROJECT_REFERENCE.md)（项目事实）/ [TICKETS.md](TICKETS.md)（唯一待办来源）/ [DEV_LOG.md](DEV_LOG.md)（已做）/ [CONSENSUS.md](CONSENSUS.md)（决策）/ [CONTEXT.md](CONTEXT.md)（领域词汇）。规则见 [docs/documentation-standards.md](docs/documentation-standards.md)。

**档位制**：模块数 ≥ 8 且文档 > 1 页时自动升完整档（新增 CODE_WIKI.md + `scripts/doc_sync.py` 机械防漂移 + F-01 pre-commit 门），对标桌面库。