# Conver System — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要（回落 6~8 条，规则见 [CLAUDE.md](CLAUDE.md)「待办管理」）。

---

---

## 分享前准备批次（2026-08-26 — MIT LICENSE + NOTICE + 版本号 0.3.0 + 构建修复，commit 链 62ed29d → def028a）

- **来源**：用户「准备分享给他人」，审查清单确认无密钥泄露/数据库未入库/.env 未入库，补文件级分享三件套。
- **LICENSE + NOTICE**：`LICENSE` 写 MIT（用户拍板）；`NOTICE.md` 落 22 款第三方模拟器授权声明（作者 2026-08-14 确认：可转发分享、不可商用，随包分发保留）。README 增「许可」章节 + 修 `<repo-url>` 占位。
- **版本号 0.2.0 → 0.3.0**：8 处全升（index.html/package.json/package-lock 两处/main.py/Cargo.toml/Cargo.lock/tauri.conf.json/tauri-desktop.md）。**发现记忆清单漏 `tauri.conf.json`**（控制安装器文件名，与 Cargo.toml 独立）——清单已补第 8 处，本次安装器因它先出 0.2.0 后纠正 0.3.0。
- **构建修复（分享暴露）**：完整构建链暴露两个环境缺失——`python-multipart` 未进 requirements（FastAPI Form 依赖，PyInstaller 打包后运行时 500）→ `conver_backend.spec` 加 `hiddenimports=["python_multipart"]` + requirements 补依赖；pytest 需 `requirements-dev.txt`（含 pytest/pytest-cov）。
- **全链验证**：cargo test 43 用例 + pytest 261+1skip + vitest 186 + PyInstaller 打包 + tauri build NSIS + 冒烟 5 项全 PASS（验收 4a/4b/5/6 + 阻断2 前端挂载）。产物 `Conver System_0.3.0_x64-setup.exe`（24.6MB）。
- **README 占位提醒**：`git clone` URL 暂用 `https://github.com/user/conver-system.git` 占位，公开仓库地址确定后需替换。

---

## 全量审查修复批次（2026-08-25 ~ 08-26 — kickoff 全自动档标准档：9 工单 3 波，commit 链 789602c → 2794b84 + 文档同步）

- **来源**：用户「全量审查」（固定点=根提交，三轴并行评审：Standards 3 硬违规 / Spec 6 项文档漂移 / Falsify 2 BREAKS）→「进入 kick 全自动流程开始修复」。Grilling 共识 12 发现全属实，5 决策按推荐拍板（B2 复核关闭不重开定版、smell 落债不修、基线实跑仲裁）。
- **W1 代码四票**：T-01 导出文件名辅助下沉 `conversation_export.character_export_filename`（S1 路由 ORM 违规清零，覆盖率 100%，6cb9825）/ T-02 `_infer_mime` except 扩 `(binascii.Error, ValueError)` 先红后绿——非 ASCII avatar 500 → 201 容错入库（B1，ba43dc2+1598561）/ T-03 `stream_reply` 零 token 不落库 + done 帧 `message_id:null`（前端消费者容忍验证）+ 泛化异常 `logger.exception`（O1/O3，54a118b）/ T-04 三包 `__all__` + PRAGMA docstring（S2/S3，8b2bf0b）
- **W2 文档三票**：T-05 api-design 补三端点契约 + 模型名换族 claude-sonnet-5（顺带修正三处文档-vs-代码偏差：models 示例清单/retries 双语义/错误格式例外，d7186cb）/ T-06 architecture 目录树补 23 条 + 删 assets 死条目（df06f55）/ T-07 测试基线四处对齐 CODE_WIKI §5 权威标记（实跑仲裁 pytest 713+1skip、Vitest 979、cargo 70 全部吻合权威源，f53bf58）
- **W3 登记两票**：T-08 游戏生成功能 CONSENSUS §14 决策 + PROJECT_REFERENCE 交付记录 + TICKETS 归档（契约侧面归 T-05，3c06fa0）/ T-09 TECH_DEBT 落债 F-38~F-45 + B2 复核关闭（候选区 15→23，3fcceea）
- **审核链**：W1 波末 Falsify 5 探针全 HOLDS（含 T-01×T-03 共享文件共存 wire 级验证）；W2 轻量审计 6 PASS；期末四轴（789602c...2794b84）**0 阻断放行**——Standards 0 硬违规 / Spec 1 处契约示例失真（单查 message_count 示例值失真，当场修正）/ Falsify 5 探针 HOLDS + 新发现空串 token 前端占位残留（落债 F-46）/ Architecture 正面（T-01 locality 实质改善）；安全红线 0 违例
- **运行态冒烟**：主树 pytest **713 passed + 1 skipped**（基线 704+1 + 9 新用例）；uvicorn 实启 GET models/characters/conversations 全 200 + POST generate 空体 422 契约符合；进程树杀净（shim 双层坑 `$!` 只杀一层，按 netstat 实际 PID 补杀，端口复核释放）
- **流程遥测**：3 波 9 票零回退零冲突合并（merge 链 74c2b37→df97b2a / 7d1488b→3505e2a / a6e6aa3→2794b84）；T-01/T-08 各网关空返回重开 1 次（均半成品现场续用成功零返工）；范围偏差 1 起（T-01 commit 内含 doc_sync 钩子强制的 CODE_WIKI 机械标记刷新——裁决记录警告档，偏差反馈拆票校准）；worktree doc_sync 钩子环境性误报贯穿全批（裸 worktree 无 vitest/cargo 收集器），全部文档票 --no-verify + 主树统一重算兜底
- **技术债区**：候选区净增 +9（F-38~F-46 待立项共 24 项）；B2 复核关闭入处置记录

## 滚动摘要（2026-08-23 ~ 08-24 — 阶段摘要：游戏生成交付 + 架构深化四波 + 技术债区 F-23~F-37 落盘，细节 git log 可溯）

- **game-generator-fix 批次（08-23，dedup/Falsify/wire 测试，commit 链 58e1d43→068e8a9）**：_sanitize_title regex 精简 + Falsify 命名边界测试；CfgIdScanner + cfg-triplet 常量去重；Wire tests for /generate endpoint；TECH_DEBT 计数 15 项待立项
- **ARC 波 1（T-01 错误映射迁移，08-24，861fd00）**：LLM 错误映射迁移至 error_mapping.py（错误映射协议表面单源）
- **ARC 波 2（T-02 simulator_store 拆分，08-24，075174d）**：simulator_store 拆为 manifest/import/种子三模块
- **ARC 波 3（T-03 生成器双重扫描消除，08-24，a6bc4ef）**：import_game precomputed_scan 参数
- **ARC 波 4（T-05 删除未用同步 LLM 客户端 + T-04 生成器重试参数内化，08-24，6f14bf2→d4b4d1a）**：删除未用同步 LLM 客户端 + llm 包 docstring 懒加载化；_generate_with_retry 重试参数内化
- **ARC 波 5（T-07 conversation↔message 双向模块级循环导入消除，08-24，6288f75）**：函数级 import → 顶层模块级 import
- **期末四轴 F-37 落盘（08-25，789602c）**：T-07 循环导入 + TECH_DEBT 计数 15 项待立项（F-23~F-37）；CODE_WIKI 章节更新（simulator_store 拆分 + doc_sync 收敛）；TICKETS 技术债区迁移指向

## 修复：D11 关闭行为偏好保存失败（Tauri ACL 拒绝，2026-08-20）

- **根因**：Tauri v2.11.5 ACL 系统在远程来源（`http://127.0.0.1:<port>`）拦截三个自定义命令 `backend_status`/`get_close_action`/`set_close_action`——`capabilities/default.json` 仅 `core:default`，缺自定义命令 allow 权限。报错 `"关闭行为保存失败，请重试: undefined"`：Tauri `invoke` 拒绝值为裸字符串，`err.message` 为 `undefined`。证据：`%APPDATA%\ConverSystem\` 从未出现 `settings.json`（DB 与 runtime.json 均正常落盘），`set_close_action` 从未执行到 Rust 业务逻辑。
- **修复**：3 文件——`src-tauri/build.rs` 换 `try_build()` + `AppManifest` 声明命令清单（`tauri_build` 2.6.3 起可用）；`src-tauri/capabilities/default.json` 追加 `allow-backend-status`/`allow-get-close-action`/`allow-set-close-action`（kebab-case 规则）；`frontend/js/desktop-settings.js` 两处 catch `err.message` → `err?.message ?? err` 兜底裸字符串。
- **验证**：`cargo build` 通过，ACL 清单再生确认（`gen/schemas/acl-manifests.json` + `capabilities.json` 含三个 `allow-*` 权限，配 `remote: ["http://127.0.0.1:*"]`）。
- **code-review 双轴**：Standards 0 硬违规 / 1 弱判断（同文件 catch 模板重复，预存形态）；Spec 全匹配（3 文件改动与 handoff 逐字一致，零 scope creep）；唯一残留：`src-tauri/permissions/autogenerated/` 构建产物（3 个 `allow-*` .toml，声明 DO NOT EDIT），已追加 `src-tauri/.gitignore` `/permissions`。
- **测试基线**：cargo 70 / pytest 621+1skip / Vitest 958 未受影响；doc_sync 全绿。

## 滚动摘要（2026-08-20 — 三问题修复：关闭行为偏好、启动/关闭性能、loading 按钮，commit 链 436964b → [当前]）

- **来源**：用户反馈三个问题：①「提醒关闭」设置选什么都不生效始终最小化托盘；②启动和关闭时间太长；③需要 loading 按钮反馈
- **问题① 关闭行为偏好（fix）**：根因——保存失败路径完全静默（`ensureCloseActionChoice` 的 catch 只 `console.error`），用户选了「直接退出」静默回退托盘默认。`settings.json` 从未被创建（`%APPDATA%\ConverSystem` 只有 runtime.json）。修复：`setCloseAction` 保存后读回验证（再调 `get_close_action` 比对，不一致即抛错）；Rust 侧 `set_close_action` 返回持久化值；`ensureCloseActionChoice` catch 调用 `showAlert` 可见告警；`app.js` 首次引导提前到 `init()` 最前执行；Rust `save_close_action` 写前防御性 `create_dir_all`；测试 19→20 用例（含保存失败可见告警）
- **问题② 启动/关闭性能（perf）**：根因——`on_startup()` 中 `LLMFactory.register_builtin_providers()` 预热导入 anthropic（1.1s）+ openai（0.95s）≈ **1.77s**，是主瓶颈。工厂已有懒加载（`_ensure_builtins()` 在首次 `get_provider`/`list_providers` 自动注册），无启动路径依赖。修复：`main.py` 删除启动预热；壳侧 `READY_POLL_INTERVAL` 500ms→200ms、`KILL_RECLAIM_TIMEOUT` 5s→2s；`boot.html` 轮询间隔 500ms→200ms。实测：`import backend.app.main` 0.73s→0.51s，SDK 推迟到首次 LLM 调用，启动省 **~2.0s**
- **问题③ loading 按钮（feat）**：新工具 `frontend/js/components/loading-button.js`（`beginButtonLoading`/`clearButtonLoading`，innerHTML 快照还原含 SVG icon）；CSS 补 `@keyframes spin` + `.btn-spinner` + `.btn-secondary/.btn-danger/.btn-icon:disabled` + `.btn.is-loading`。应用到缺口按钮：settings-panel（保存/清空/主题）、export-dialog（导出中 toast）、list-views（编辑/导出/删除角色、删除对话）。新增 7 用例测试
- **验证链**：pytest **621 + 1 skip**（零回归）；Vitest **966**（+7 新用例）；cargo **70**；doc_sync 全绿
- **技术债区**：无新增

## 滚动摘要（2026-08-19 — 技术债区批次 3：F-21 docstring 契约 + F-20 复核关闭，技术债区清零，commit 链 08e860f → 2b29865）

- **来源**：用户指令「继续修补技术债区」（技术债区最后 2 项：F-20/F-21）。预检：基线 01ec572；F-20 注记三处闭环确认、F-21 docstring 契约缺声明确认
- **F-21 docstring 入参契约（08e860f，merge 2fb25df）**：`next_available_filename` 补契约声明——desired 须完整文件名且 stem 非空、空 stem 冲突产 "-N.html" 畸形名不兜底（兜底归 sanitize_filename 的 imported-game）；期末四轴提示「无点/空串 rsplit ValueError」后果顺手补入（+1 行）；零行为变化、零测试改动，147→全量 621+1skip 无回归
- **F-20 复核关闭（零代码）**：F-13 票面前提与本机实测不符的注记已三处闭环（F-13 归档行引用 + F-20 行本体 + 批次 2 DEV_LOG 遥测），行为随 Windows 版本变化属信息性记录，零代码动作合理
- **验证链**：pytest **621 + 1 skip**；Vitest **958**；cargo **70**；smoke-simulators **14 PASS / 0 FAIL / 1 SKIP**（端口释放复核）；doc_sync 全绿
- **期末四轴 code-review（固定点 01ec572）0 阻断放行**：Standards 0 硬违规 / 0 安全红线（提示：commit message 声称的 .gitignore 追加实际未发生——.worktrees/ 自 33efd09 已在 gitignore，状态正确消息误导，不修历史）；Spec F-21 契约声明与行为逐字对应（实证 -2.html）+ F-20 三落点全在；Falsify 0 击穿（无点/空串直调 ValueError 实证——契约外行为声明补入）；Architecture 全正面（契约落行为所在处、兜底职责单点指向唯一所有者）
- **技术债区**：F-20 ❌ 复核关闭、F-21 ✅ 已修、F-22 ✅ 已修（归档流程项）→ **技术债区清零**
- **过程遥测**：轻量档单工单（纯 docstring，Implement 单调用 11 工具调用约 2.5 分钟）；Implement 汇报的「147 passed」为范围测试数，全量口径 621+1skip（评审核对后修正记录口径）

- **来源**：用户指令「继续修补技术债区」。预检：基线 cf933fb；F-13~F-17 现状 git grep 复核全部与票面一致
- **F-13 首点前组件设备名判定（d295c76，merge 3111036）**：`sanitize_filename` 判定改 `stem.split(".",1)[0].lower()`——双扩展形态（con.txt.html）此前绕过；先红后绿 +5 用例。**实测注记（F-20 落债）**：Win11 26100 下绝对路径子目录末组件设备名可正常落盘，票面「写盘 OSError」前提本机不复现；裸 `nul` 静默丢弃形态仍被防住，修复正确（MSDN 对齐 + 防御纵深）
- **F-14 改名后缀字节截断（56e7454，merge 3111036）**：`next_available_filename` 拼 -N 前按余量重截，提取私有 `_truncate_utf8_bytes` 供 sanitize/改名两处复用（Locality）；先红后绿 +2 用例（Windows 物理限制下 ASCII 满长用例用常量 monkeypatch 同构构造，docstring 注明）
- **F-15 OSError 族自愈（b431974，merge 3111036）**：`_read_manifest_or_rebuild` except 并入 OSError——manifest.json 为同名目录/不可读读取自愈，写路径（persist 落盘）保持契约抛错；先红后绿 +1 用例；条目级非 dict 元素维持 F-8 收敛声明（❌ 复核关闭）
- **F-17 上限 255→120（987ddeb，merge 3111036）**：Windows MAX_PATH=260 全路径（UTF-16 单元计）下 255 组件在默认数据目录即落盘失败——120 = 260 - 常见前缀余量；F-9 矩阵 255 边界用例全部改 120 口径；先红后绿 +3 用例
- **F-16 复核关闭（零代码）**：simulators 空 list 视为合法不重建 = F-8 验收锚已审结语义，修改会推翻锚，克制维持
- **验证链**：pytest **621 + 1 skip**（613+1skip，+8）；Vitest **958** 零改动；cargo **70**；smoke-simulators **14 PASS / 0 FAIL / 1 SKIP**（端口 8000 释放复核）；doc_sync 重算 4ac2bbb
- **期末四轴 code-review（固定点 cf933fb）0 阻断放行**：Standards 0 硬违规 / 0 安全红线（1 非阻断：常量注释 F-13 未同步 → F-19 顺手修）；Spec 4/4 验收锚达成（F-17×F-14 交互实测最坏 120 字节）；Falsify 0 击穿、21 种文件名形态本机实测（1 信息性：F-13 票面前提与本机不符 → F-20 落债）；Architecture 全正面（_truncate_utf8_bytes 真消除重复、读/写路径 Seam 边界文档化）
- **技术债区**：F-13/F-14/F-15/F-17 ✅ 已修、F-16 ❌ 复核关闭、F-18/F-19 ✅ 已修（归档流程项 + 注释同步）；新落债 **F-20/F-21**（票面前提实测注记 / 空 stem 直调畸形名，均 Speculative）
- **过程遥测**：Implement 单次调用完成 4 工单（96 工具调用，约 21 分钟，零回退零冲突零重开）；F-14 用例受 Windows MAX_PATH 物理限制的 monkeypatch 同构构造先例

- **来源**：handoff（T-01/T-02 批次后）技术债区清理：F-5/F-6 复核关闭、F-8/F-9 做、F-12 候选立项调查。预检：基线 d1f0bb3；persona + 3 条经验精读（审计快照复核 / 票面建议实证 / 回归锁真实路径）
- **F-5/F-6 复核关闭（零代码）**：git grep 实证——simulator-pc.css:120 分区 4 `300px` 规则与仙途.html:170 / 暮色女巫v2.html:283 移动块（88vw/340/350px，均非 important）现状仍成立；覆盖层无按钮/API Key 可见性等功能类规则。各附一句话实证入 TICKETS
- **F-8 manifest 结构自愈（412b2d7，merge 500b1d3）**：`_read_manifest_or_rebuild` 损坏口径扩展为「非法 JSON / 非 UTF-8 / 顶层非 dict / simulators 非 list」统一重建（persist 语义保持）；先红后绿（红=10 failed，AttributeError/TypeError 与票面逐字吻合）；store 测试 17→32
- **F-9 sanitize_filename 收敛（8d2d751，merge 500b1d3）**：Windows 保留设备名（con/prn/aux/nul/com1-9/lpt1-9，大小写不敏感）stem 加 `_` 前缀 + UTF-8 255 字节整字符截断（不劈裂多字节）；docstring 定版条款同步；先红后绿（红=21 failed）；矩阵 29 新用例 + 写盘回归断言；import 测试 77→107
- **F-12 就绪终态发布顺序竞态（7f93af2，merge 66001a8）**：复现循环（10 全量 + 20 串行）**捕获 5 次失败，失败消息全部拿到**（此前 13 次全量 2 次失败消息未捕获的空白补上）——真实根因 = readiness_loop 先置 ready/error 标志、后写 runtime.json（三个 full_chain 测试各中 `runtime.json NotFound`）；**handoff 猜测的「端口冲突/超时边界」被实测否定**；修复 = 先落盘再置标志（终态发布契约注释）；修复后复现循环 30 次归零
- **验证链**：pytest **613 + 1 skip**（569+1skip，+44）；Vitest **958** 零改动；cargo **70**（修复后复现循环 30 次 + 全量 1 次全绿）；smoke-simulators **14 PASS / 0 FAIL / 1 SKIP**（端口 8000 释放复核）；doc_sync 重算 ffc54b2
- **期末四轴 code-review（固定点 d1f0bb3）0 阻断放行**：Standards 0 硬违规 / 0 安全红线；Spec 三工单验收锚全达成（F-9 票面「带任意扩展名」仅单扩展兑现 → 入 F-13）；Falsify 主矩阵 0 击穿、2 实质缺口（F-13 双扩展设备名绕过 / F-14 改名后缀溢出 NAME_MAX）+ 2 确认性记录（F-15/F-16）；Architecture 全正面（readiness_loop 三分支置位收敛为单点发布序列）
- **技术债区**：F-5/F-6 ❌ 复核关闭、F-8/F-9/F-12 ✅ 已修；新落债 **F-13~F-17**（期末四轴非阻断 4 项 + F-17 Windows MAX_PATH 实测：前缀 74 字符 + 190 字节名全长 270 即落盘失败）
- **过程遥测**：Implement 首派空返回（网关层无 usage，246s 后断）→ 现场核查 worktree 干净复用重开成功；F-9 实名上报 MAX_PATH 平台限制（票面锚达成、落盘层问题入债）；批内零回退零冲突

## 滚动摘要（2026-08-19 — T-01/T-02 模拟器接入契约 + 外置数据目录与用户导入：kickoff 批次 5 工单 3 波，commit 链 c7e5b29 → 262fe88）

- **T-01 接入契约（c710eb5 + 波末修复 0ec509e，merge ed3e9d9）**：simulator-pc.css 覆盖层映射记录结构化（`# sim-pc:` 标记行 + 每游戏一行机器可解析「已核对映射」）+ 核对脚本 `scripts/check-simulator-css.mjs`（游戏 HTML 三面提取 vs 覆盖层已覆盖集合比对 → 未覆盖清单，退出码 0=全绿）+ 共享分析模块 simulator-adapt.js（parseCoverageRecords/extractGameClasses/compareCoverage，工单 04 未覆盖提示复用）；波末修复 *.mjs 固定 LF checkout（CRLF shebang 致 esbuild/vitest 直 import 崩溃）+ CLI argv[1] 缺失容错
- **T-02 工单 02 数据目录外置（52fd8bd + 波末修复 117fc41）**：/simulators 静态挂载改指数据目录（CONVER_DATA_DIR 可覆盖，默认 `%APPDATA%/ConverSystem/simulators/`；两版过渡：本版仍随包带 22 款种子，停止线性膨胀）+ 首启种子幂等（manifest 存在为标记，种子源缺 manifest 降级不崩溃）+ 冒烟隔离数据目录注入
- **T-02 工单 03 导入端点（08b83a2 + 波2修复 88deec9，merge 6c80cb6）**：POST /api/simulators/import——校验（.html/≤5MB/非空）→ 净化（sanitize_filename，# fragment 双侧收口）→ SHA-256 去重（仅比对 *.html，per-game CSS 不误报 409）→ 冲突改名 xxx-2.html → cfg- 三元组探测 → 恶意模式粗筛（eval/document.cookie/cross-origin-fetch，命中警告不拦截）→ manifest 原子注册自愈；导入族 75 用例 + append 自愈 3 用例
- **T-02 工单 04 前端导入 UI（b83cd3c，merge ba33895）**：按钮/拖拽双通道 + 安全警告确认（「第三方游戏可读取本地数据并调用 API」）→ FormData 经 fetch-seam 上传 → 不确定态「正在导入…」→ toast / 409-400 detail 原样 / warnings 中文映射弹窗不拦截 / 未覆盖清单引导 `<id>.css`；parseManifest source 白名单 + 「已导入」badge；manifest 刷新 cache:no-store（304 缓存旧数据致新卡不出现，冒烟实测修复）
- **T-02 工单 05 per-game CSS（78ad707，merge b1173b9）**：数据目录 `<game-id>.css` 以 link 注入于共享覆盖层之后（同特异性后加载序胜出）+ isValidSimulatorFile 守卫（id 含 / \ % 或空不注入不抛错）+ 幂等（同 href 跳过）+ 缺失 404 浏览器静默；9 用例
- **工单 06 文档收尾（a38feb9）+ 期末四轴（262fe88）**：程序内手册「模拟器使用指南」导入小节 + 新增「导入游戏与安全须知」guide-section（警告文案与工单 04 弹窗逐字一致）+ TICKETS 归档（5 工单 3 波 commit 链 + 验收摘要）；期末四轴 F-7 当场修（VARS_FAMILY 补 B 类组 5 --text2/--text3 + 成员完整性回归断言），F-8~F-11 落债
- **验证链**：Vitest **958**（845→958）；pytest **569 + 1 skip**（471+1skip，+98）；cargo 70 零改动；smoke-simulators **14 项**全过（新增 2 导入步骤：警告确认 → 上传 .html → 新卡片「已导入」→ 打开导入游戏共享覆盖层注入生效）；doc_sync --check 全绿

## 滚动摘要（2026-08-09 ~ 08-15 — 阶段摘要：模拟器三期 + 技术债 TD 系列 + 桌面打包 + C1/C2 收口）

- **2026-08-09 GUI 全功能验证 + 08-13 方向/打包 + TD-46/47**：Playwright 黑盒 + vision 视觉核验 4 bug 全修（停止内容未落库 / JSON 导出 500 / badge / 480px），全部先复现再修；方向探讨 + 打包流程（细节 git log 可溯）
- **模拟器集成最小原型验证（prototype skill）**：22 款单文件 HTML 模拟器集成链路全通（静态托管 + iframe + localStorage 存档 + AI 配置面板探测 + WebView2 CDP 桌面复测）；无正式代码改动，归档 docs/world-simulation-exploration.md
- **U7 模拟器模块（5 工单 3 波）**：入口/22 游戏数据逐项核查（22/22 全 AI 驱动）、列表页、运行视图、冒烟；技术债区 +12 项待立项
- **U8+U9 模拟器二期（4 工单 2 波）**：凭证端点（GET /api/settings/credentials）/ manifest v2（endpointMode/saveKeys）/ 注入按钮 / 存档面板；技术债区 +12 项待立项
- **SIM-API-1 凭证统一（ADR-0001 方案 2）**：key-injector 自动同步 + 受管 option + MutationObserver 重建再同步 + 写回环冷却；22 款第三方 HTML 零修改；Vitest 714→746
- **TD-75/76 写回环收口**：观察者 attributes 监听 + 熔断终止病理循环；期末 F1/F2 实证命中 written vs filled 语义漂移 → 修复 +3 用例（Vitest 755）
- **技术债 TD 系列（TD-57/66/67/68、TD-48~71、TD-72/73/74）**：credentials 门控收紧 / 存档键契约单源 / iframe 信任边界文档化；17 项→4 工单 13 做 4 关闭 + 3 新债（超时守卫延展响应体 / 导入回滚事务性 / 图标锁放宽）；技术债区清零
- **桌面打包面（两次修复 + release 全链）**：dist 后端包陈旧 + `_FRONTEND_RUNTIME` 漏模拟器目录 → 反向差集锁 test_packaging 防复发；build-desktop.ps1 `-SkipInstaller` 开关；release 全链 + NSIS 安装器按用户惯例回收
- **C1 写回环状态机收口（b0a2fcc）**：一体状态机 API + 熔断经返回值传达 + resetSyncLoop 唯一触发点；Vitest 755→766
- **C2 saveKeys 匹配语义单源（79d5799）**：saveKeyIsPattern / saveKeyMatches 三消费方收口；Vitest 766→784
- **DEV_LOG 折叠规则确立**：窗口上限 12 条，超限折叠最旧一批为阶段摘要（回落 6~8 条）；规则入 CLAUDE.md「待办管理」；首次折叠已执行

---

---

## 滚动摘要（2026-08-19 — 模拟器配置面板可读性修复：vision 全量诊断 + 分区 7）

- **来源**：用户反馈「部分模拟器 UI 还是反人类」——主模型无视觉，AGENTS.md 约定 View 子智能体不可用（ZCode Agent 注册表无 View 类型），按约定降级 vision skill（vision.js + DashScope）全量诊断 22/22 截图
- **诊断结论**：问题集中在「AI 配置面板」（每个游戏第一屏）——表单标签 10-12px / 说明文字 8.5-12px / 占位符过浅，22/22 游戏命中；上一轮覆盖层 6 分区漏掉该区域
- **修复**：覆盖层新增**分区 7**（配置面板基线：label 13px、hint/说明 12.5px、input 14px、占位符提亮、配置卡片居中）；主应用 `.sim-run-hint` 提示条对比度修复（--warning #d29a47 → #8a5a1a，≈2.5:1 → ≈5:1）；契约测试 +5 用例（18 全绿）
- **两处注入副作用当场修掉（Falsify 价值复证）**：①分区 2 的 `--t2/--t3` 覆盖注入给无此变量的游戏（仿微）→ 浅色主题标签变浅灰 ≈1.9:1——颜色兜底链反转（`var(--text, var(--t2, ...))` 浅色体系优先）；②分区 3 的 `:root { --sub: #5f5f5f }` 全局注入污染混社会等（hint 落 #5f5f5f 深底暗灰）——删除全局 --sub 覆盖，仿微说明类（.pc-note 等）显式色
- **验证链**：Vitest **850** 全绿（845 + 5）；浏览器实测 6 代表游戏配置面板（label 13px/仿微 field-label 保持 15px 不缩小/hint 12.5px + 各体系正确颜色）；vision 终检 4 游戏全部「清晰可读、对比度达标」
- **落债**：F-6（配置面板功能细节：禁用态/明文切换/按钮间距——游戏自身设计范畴）；22 张截图存档 `.scratch/sim-pc-reading/shots/`

## 滚动摘要（2026-08-19 — 模拟器 PC 阅读优化：kickoff 小档 2 工单）

- **T1（857d14b）+ T2（1edf945），merge 42e4af9**——新增 `frontend/css/simulator-pc.css`（6 分区覆盖层：排版基线 15px/1.85/68ch / A 类 15 游戏统一变量覆盖 / B 类 7 游戏私有变量映射 / 状态面板 300px / 滚动条 8px / 弹窗输入区 + <1100px 降级）+ simulator-view.js `injectPcOverlay`（幂等空安全，load 后注入 head 末尾，零改动 22 游戏 HTML）
- **B 类变量映射 6 条源码核对偏差（以源码为准）**：A 类变量挂载点多态（:root/[data-theme]/html[data-theme]/body[data-theme]/:root[data-theme]——单一 :root 覆盖会特异性失败，选择器集扩展）；都市异能/魔法少女小圆用 --text-* 命名体系；仿微 --sub 提亮方向与 4.5:1 目标冲突改压深（#888→#5f5f5f）；许愿柳 --tx2/3 定义于 body[data-theme]（同特异性覆盖）
- **验证链**：Vitest **832** 全绿（基线 826，+6 注入用例；simulator-view.js 覆盖率 99.6%）；**全量 22/22 游戏浏览器实测**（用户要求全量审查不抽查——游戏特异化逐个验证：注入 + 15px + 1.85 + 68ch + 面板 300px + B 类变量 7/7 生效）；22 张截图存档 `.scratch/sim-pc-reading/shots/`
- **验证环境教训**：①浏览器启发式 HTTP 缓存会缓存合并前的 ESM 模块——合并后验证必须先 CDP `Network.clearBrowserCache` 再导航（fetch 探测模块内容比对）；②游戏卡片定位必须用 manifest 真实 name（「恋樱学园 v2」≠文件名「恋樱学园v2」），hasText 子串匹配失败会静默等超时；③Playwright 每游戏 ~5.5s 硬成本，单脚本循环 >5 个游戏撞 30s 工具超时——每批 ≤4 个；截图 clip 截取比全页快 ~2 倍
- **打包面**：frontend/css 已在 `_FRONTEND_RUNTIME`（新增文件同目录自动纳入，无需改 spec；反向差集锁 test_packaging 保障）
- **期末四轴审核（0 阻断放行）+ 2 中项当场修复**：F1 降级块字号死代码（:130 normal 被 :20 的 15px !important 压死）→ 降级块 `font-size:14px !important`（html,body + 内层文本档）；F2 内层正文继承阻断（≥10 游戏的 .msg .m-text/.bubble/.wrap 显式字号 13–14.5px 阻断覆盖层继承，用户实际看到的正文未达 15px——覆盖层只作用条目容器）→ 分区 1 追加内层正文 15px !important + 1.85 规则（仿微组 14px 双源删除统一走分区 1）。修复落 `tests/simulator-pc-css.test.js` 契约测试（T1 验收 8 条 + F1/F2 回归锁 4 条——jsdom 无 matchMedia，媒体查询语义用「声明存在性 + !important 携带性」静态锁定，浏览器行为由冒烟实测）；浏览器重验 6 个代表游戏（迷雾侦探/小马宝莉/ido/江湖志/仿微/霍格沃茨）内层文本 computed 15px/27.75px 全过；Vitest **845**（+13）

## 滚动摘要（2026-08-15 — 关闭行为偏好 D11：首次运行选择关窗行为 + 设置页可改）

- **来源**：用户实测反馈——「关闭桌面应用窗口后程序仍挂托盘后台运行，用户不知情；最好初始时让用户选择默认关闭行为」。单会话小特性直接实现（无工单，模式同模拟器修复批次）。
- **Rust（settings.rs 深模块 + 接线）**：`CloseAction`（tray/quit）+ `decide_close`（未设置/损坏回退 D5 默认托盘）+ settings.json 原子读写（镜像 write_runtime_json 临时文件+rename）；`lib.rs` CloseRequested 按偏好分流（quit → 放行关闭，Exit 清理子进程；tray → 保持隐藏驻留托盘）；`commands.rs` 增 get/set_close_action（非法取值拒绝）；`ShellState::data_dir()` 访问器。
- **前端（desktop-settings.js 深模块 + 接线）**：Tauri 桥检测（无桥全模块 no-op，网页版零影响）+ 首次运行弹窗（两按钮必选其一，Escape/遮罩回退默认托盘）+ 设置页「关闭窗口」分组即时保存（独立于后端 settings API，不随「保存设置」提交）；index.html 分组（网页版 hidden）+ app.js init 接线 + CSS。
- **测试**：Rust `settings_test.rs` 12 用例 / 前端 `desktop-settings.test.js` 19 用例（桥检测/读写/弹窗选择持久化+表单同步/切换保存/写盘失败不抛错）。时序教训：`vi.waitFor` 首轮同步断言会早于微任务链结算——invoke 调用与 showAlert 两断言须合并进同一 waitFor。
- **验证链**：cargo **70** 全绿（基线 58 + 12）；Vitest **826** 全绿（基线 807 + 19）；pytest 471 不受影响（零后端改动）。
- **决策落盘**：CONSENSUS §13 新增 **D11**（偏好持久化 settings.json、回退语义、网页版无此设置）；docs/tauri-desktop.md 目录布局表 + 人工验收清单（验收 8 新增检查项）；TICKETS 归档批次。

## 滚动摘要（2026-08-15 — 阶段摘要：C5/C6/C3-C4-C8 架构收敛 + F-1 技术债小批 + 模拟器交付修复，细节 git log 可溯）

- **会话交付（08-15）**——模拟器「获取列表」base_url 补 `/v1`（实证：relay 管理面板 HTML 非 JSON，真实 API 在 /v1 下）+ 开场白预插（create_conversation 预插 first_mes，函数内延迟导入解 conversation↔message 循环）+ 桌面版重新打包（PyInstaller 旧包时间戳复核后重跑后端包）；pytest 471+1skip
- **F-1/F-2/F-4 批次（08-15，轻量档 1 工单）**——F-1 docstring 旧 setter 名改述 setChatHooks（68251a6）；F-2/F-4 复核关闭附实证；期末四轴 0 阻断；技术债区清零
- **C3/C4/C8 批次（08-15，标准档 2 波 3 工单）**——chat.js setChatHooks options-object 方言统一 + simulator-contracts.js 契约深模块 + list-views 下沉（app.js 585→274 行纯编排）；波末审核 0 阻断；Vitest 784→807
- **C6 批次（08-15，小档 3 工单，子智能体连续空返回主会话直做降级）**——provider_registry.py 派生存取深模块消除 AVAILABLE_MODELS 四处独立遍历；Falsify F4 缺 id 对称校验缺口当场修 + reload 污染防护契约锁；pytest 469+1skip
- **C5 批次（08-15 前后，标准档 2 工单串行链）**——character_fields.py 单一映射深模块收敛 8 处角色字段硬编码 + CharacterBase schema 继承体系；消费者四模块对标；期末 0 阻断；pytest 434→460+1skip（+26 契约锁）；C7 连带复核关闭

