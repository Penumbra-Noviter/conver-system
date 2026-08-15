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

测试：`cd backend && python -m pytest`（pytest 469+1skip）；`cd frontend && npm test`（Vitest 807，覆盖率 `npm run test:coverage`）；`cd src-tauri && cargo test`（58）。

## 当前状态（2026-08-14）

- ✅ Phase 1-5 + P6.1/6.2/6.3 + P2.5/3.5 + P4.3 + P6.4 全部完成
- ✅ 架构深化两波（ARC-1~8：StreamSession/级联/标题/export/api seam/展示契约/app 拆分/__init__）+ 架构摩擦 11 候选（前端模块化 + 服务层解耦）
- ✅ P6.5 多 tab 会话管理（tabs 工作区深模块 + 防悬挂写回 + sessionStorage 恢复）
- ✅ OPT-1 UI 克制化与图标协议收口（icons.js seam + emoji 清除 + 主题 token 单一来源），GUI 黑盒回归全过
- ✅ P6.4 Tauri 桌面版已交付（8 工单归档，2026-08-11）：Tauri v2 壳 + PyInstaller 打包后端 + NSIS 安装器；期末 2 阻断（后端随包定位、前端随包挂载）已修复，安装器形态冒烟 5 项全过。详见 [docs/tauri-desktop.md](docs/tauri-desktop.md)
- ✅ **ARC9 架构深化批次（6 Strong 候选，2026-08-12）**：T-01 搜索视图/级联删除收口 + T-02 settleTurn 统一结算 + T-03 complete_chat/chat_error_response + T-04 数据目录契约表 v2（期末 1 阻断修复）+ T-05 冒烟清理收口 + T-06 编排区测试挂网；期末四轴 1 阻断修复放行
- ✅ **ARC10 架构深化批次（剩余 8 候选，2026-08-12）**：T-11 modal 骨架收口（C3-DEFER 兑现）+ T-12 character-submit 提交收敛 + T-13 微重复收口（resize/空态/onerror）+ T-14 Provider 清单单一来源（AVAILABLE_MODELS 派生 + 包导出收缩零 SDK 副作用）+ T-15 统一 exception handler（api/errors.py）+ T-16 style.css 覆盖区归位 + --on-danger token + T-17 schema 快照漂移检测 + T-18 聚焦序列收口；期末四轴 0 阻断放行；GUI 冒烟（modal 骨架/错误气泡深浅主题/输入框复位/级联）全过
- ✅ **技术债区 TD-13~14 批次（2026-08-12 全自动 kickoff）**：2 做 + TD-9 顺带闭环——TD-13 save 回调入口统一守卫（11 元素收集 + :339 收口；+2 用例先红后绿）/ TD-14 契约措辞 pathlib 规范化注记 + 契约锁用例；TD-9 维持→做（入口守卫覆盖其调用点，本体零改动）；期末四轴 0 阻断；10 项新遗留（TD-15~24）入技术债区
- ✅ **技术债区 TD-15~24 批次（2026-08-12 全自动 kickoff）**：10 项全做清零（小档 2 工单，merge 0010f1b）——TD-A 守卫收窄与卫生（TD-15 守卫条件化 `modelSelect.value === '__custom__'`，票面 providerSelect 条件实证否定；+2 用例 A 先红后绿 + B 基线绿）+ TD-B 契约注记与锁补强（UNC 特例注记 / 尾分隔符+UNC 锁断言 / 「路径形态」限定 / Rust 透传注释）；期末四轴 0 阻断；3 项新遗留（TD-25~27）入技术债区
- ✅ **技术债区 TD-25~27 批次（2026-08-13 全自动 kickoff）**：1 做 + 2 维持关闭（merge 8ae3801）——TD-25 UNC 锁断言平台隔离（拆独立用例 + 函数级 skipif，票面断言级形态实证不可表达；Windows 锁照跑 + POSIX 可见 skip）；TD-26/TD-27 复核确认维持关闭（现状即设计意图）；期末四轴 0 阻断（该批次后技术债区余 17 项，见 TD-29~45 批次）
- ✅ **U7 模拟器模块批次（2026-08-14 全自动 kickoff）**：5 工单标准档 3 波完成——入口/22 游戏数据/列表页/运行视图/冒烟；期末四轴 0 阻断；技术债区 +12 项待立项（TD-48~62）
- ✅ **U8+U9 模拟器二期批次（2026-08-14 全自动 kickoff）**：4 工单 2 波完成——U8-T1 凭证端点/U9-T1 manifest v2/U8-T2 注入按钮/U9-T2 存档面板（merge 链 9aa6cfd/3df82d8/455b308/a918067/79598c2 + 波末修复 4a38400）；期末四轴 0 阻断；技术债区 21 项待立项（TD-48~71）
- ✅ **技术债区 TD-57/66/67/68 批次（2026-08-14 全自动 kickoff）**：3 工单小档完成——TD-66 credentials model 门控收紧（`_OPENAI_PROTOCOL_MODELS` 单源派生，先红后绿）/ TD-67+68 存档键契约单一来源（save-key-meta.js 深模块，五处消费点迁移）/ TD-57 同源 iframe 信任边界文档化（architecture.md 五要素小节）（commit 链 75d9d5c/6665dff/7d803d0，merge 1a7270b + 非阻断修复 37a3b5e）；期末四轴 0 阻断；技术债区 21→17 项待立项
- ✅ **技术债区 TD-48~71 余项批次（2026-08-14 全自动 kickoff）**：4 工单 2 波完成——fetch-seam 单源 + 15s 超时守卫 + seq 守卫（TD-51/55/60）/ 运行中再点导航回列表 + file 百分号拒绝 + none 态设置链接（TD-53/56/71）/ 存档管理健壮性五连（TD-63/64/65/69/70）/ 图标单源一致性（TD-58/59）；4 票复核关闭（TD-48/49/52/62）；期末四轴 0 阻断；技术债区 17→3 项待立项
- ✅ **技术债区 TD-72/73/74 批次（2026-08-14 全自动 kickoff）**：轻量档 1 工单 3 提交完成——超时守卫延展覆盖响应体读取（TD-72，await race 两阶段）/ 导入回滚尽力而为（TD-73，per-key try/catch 错误同一性）/ 一致性锁数量断言放宽（TD-74，票面修正）；期末四轴 0 阻断；**技术债区清零（TD-1~74 全部处置完毕）**
- ✅ **SIM-API-1 批次（2026-08-14 用户需求，ADR-0001 方案 2）**：22 款模拟器 API/模型配置统一由主应用控制——manifest 增 endpointMode（17 full / 5 base，HTML 口径溯源锁）；key-injector 扩展（convertEndpoint 端点口径转换 / 受管 model option / 幂等写入 / syncGameCredentials + autoSyncIntoGame 编排核心 / 按钮改「重新同步」）；simulator-view load 自动同步 + MutationObserver 配置控件重建再同步（防抖 500ms + 写入后 1s 写回环冷却）；wg_ 会话注记退役（自动同步每次 load 重放）；parseManifest endpointMode 透传；第三方 HTML 零修改；真实冒烟 13 项 12 PASS/0 FAIL/1 SKIP
- ✅ **技术债区 TD-75/76 批次（2026-08-14 kickoff 全自动档）**：观察者 attributes 监听（TD-75，attributeFilter 收窄 value/hidden）+ 写回环熔断（TD-76，SYNC_MAX_STRIKES=3 真写入信号 written）；期末四轴 F1/F2 实证修复（filled 含幂等匹配误当真写入 → 返回增 written 字段）；先红后绿 +9 用例（Vitest 746→755）；冒烟 13 项 12 PASS；**技术债区清零**
- ✅ **C1 写回环状态机收口（2026-08-15 kickoff 全自动档：串行链 4 工单）**：模拟器配置同步写回环状态（冷却/熔断）从 simulator-view 收进 key-injector 单一状态机——`autoSyncIntoGame` 加 path:'load'|'observer'（一次调用原子完成冷却判定→同步→置冷却→观察者计数→熔断判定；熔断权优先于冷却、幂等兜底）+ 新导出 `resetSyncLoop()`（复位唯一触发点 destroyFrame）+ `__all__` 10→11；simulator-view 只留触发时机（load/观察者防抖/按钮）与观察者生命周期；期末四轴 0 阻断放行；冒烟 13 项 12 PASS；Vitest 746→766
- ✅ **C2 saveKeys 匹配语义收口（2026-08-15 kickoff 全自动档：轻量档 1 工单）**：saveKeys 白名单匹配语义（精确键名 === / 正则模式 ^…$ 锚定匹配）从三处分散实现收进 save-key-meta 完整深模块——新增 `saveKeyIsPattern`/`saveKeyIsValidPattern`/`saveKeyMatches` 三导出（`__all__` 3→6）；normalizeSaveKeys/whitelistHits/saveKeyHits 三消费方对标；期末四轴 0 阻断放行；冒烟 13 项 12 PASS；Vitest 766→784
- ✅ **C5 角色字段知识收敛（2026-08-15 kickoff 全自动档：标准档 2 工单串行链）**：后端角色字段清单（16 个 V2 内容字段）从 8 处重复硬编码收敛为 character_fields.py 单一映射深模块（CHARACTER_V2_FIELDS 全集 + PROMPT/PARSE/EXPORT 投影 + V2_KEY_MAP/V1_TO_V2_MAP）+ schemas CharacterBase 继承体系；character_card/document_parser/prompt/message 四消费者对标；附带 doc_sync 子编号支持；期末四轴 0 阻断；连带复核 C7 关闭；pytest 434→460+1skip（+26 契约锁）
- ✅ **C3/C4/C8 技术债批次（2026-08-15 kickoff 全自动档：标准档 2 波 3 工单）**：C3 注入钩子方言统一——chat.js 两单函数 setter 合并 `setChatHooks({refreshConversations,syncConversationListTitle})` options-object + setActivationHooks 从 init() 内移模块级注入区（时序迟到修复）；C8 simulator-contracts 契约深模块——SIM_DIR/MANIFEST_URL（派生）/TIMEOUT_MS/TIMEOUT_REASON（秒数派生）/isValidSimulatorFile 单一来源，simulator-view/simulators 对标消费；C4 列表视图下沉——角色/对话列表下沉 list-views.js 深模块（6 DOM + 5 导出，app.js 585→274 纯编排），utils.js 增 showError/showSuccess；波末增量审核 0 阻断 + 期末四轴 0 阻断；冒烟 13 项 12 PASS；技术债区 C3/C4/C8 归档 + 4 项待立项（F-1~F-4）；Vitest 784→807（+23）
- ✅ 测试：pytest 469+1skip（后端）+ Vitest 807（前端）+ cargo test 58（壳）全绿

## 待办管理

唯一待办事实来源：`TICKETS.md`。DEV_LOG 只记"已做"，不存储待办。

- DEV_LOG 滚动摘要窗口上限 **12 条**：文档同步时若超限，把最旧一批折叠为一条「阶段摘要」（日期范围 + 每批次一行，置于日志正文顶部），窗口回落至 6~8 条；不拆 docs/——避坑细节已蒸馏 persona/经验笔记，批次细节 git log 可溯
