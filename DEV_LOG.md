# Conver System 移动端 — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要。

---

## M1 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：数据层 + 设置）

- **交付**：8 工单 5 波（01 SecureStore c575d58 / 02 模型清单 3266593 / 03 角色对话仓储 038d7f0 / 04 设置仓储 9ec7346 / 05 消息仓储 a7b1b73 / 06 设置页 de9e5de / 07 浅色主题+装配 54df54a+b9ad059+b39b283 / 08 收口 6b4bfd1），merge 链 955d002→783d15a→4e8db1b→794a847→a1d4265。**G1–G5 门全绿**（analyze 0 / 154 测试 / 仓储契约逐锚点 / 主题同构+行为断言 / 清单 60 模型锁 / 设置十键+解析链）+ **G6 冒烟全项过**（Key 真通道往返 27 字符精确回显 / 三值主题即时生效[深浅视觉反转+深色恢复逐字节归位] / 五 tab 零崩溃）。用户真拍两项：主题三值首启深 / 设置页三组真实化。
- **审核链**：波末增量审核 ×5 全过（W1 SecretStore 契约实证+清单 IDENTICAL / W2 CRUD 六锚+接缝编译探针 / W3 主会话完成票独立全标准 / W4 装配链逐环+浅色 token 22/22 / W5 零代码变更形式化实证+G 证据复核）+ 期末四轴（安全红线 0[Key 链路端到端核]/Spec 零越界/突变前置已由波末覆盖/架构分层完好[drift import 零泄漏出 data 层]）。覆盖率：全局 45.36%（生成物稀释）/ **手写口径（剔除 drift 生成物+schema 声明）90.90% 达标**——口径定义固化于本文，后续里程碑沿用同口径。
- **过程遥测**：波 5、票 8、并行峰值 2（网关配额）；**网关故障 episode 一次**：波 3 期间 05 三败触重开上限 + 06 两败 + W2 审核 captcha 两败——处置：05 触线报用户（无回答 → persona best-judgment）**主会话接续半成品完成**、06 押后主会话从零完成、审核错峰重派三派成功；空返回 0；回退/冲突 0；子智能体 15 个 token 合计 ≈1600 万；审核 findings：阻断 0、非阻断 15+（F-7/F-8/F-9 落候选 + 低危观察若干）。**技术债净增提示**：候选 0→3（净增 3 > 清零 1[F-3 消费]），全 Worth exploring 级。
- **避坑（勿重蹈）**：
  1. **orchestration/台账类文件的行级编辑用「追加」勿用「替换」**——本批三次误把前一条记录行替换掉（发现于 Neat 前自查，均已恢复）。
  2. **测试环境平台通道是挂起不是抛错**（secure_storage/drift 打开永不完成）——Flutter widget 测试碰平台依赖必须超时兜底（3s），try/catch 管不了挂起。
  3. **typedef 别名不可 const 调用**（`const ApiEchoValues({})` 非法）——Dart 任意 map 字面量直接 `const <String, String>{}`。
  4. 子代理报「用户已拍板」类断言必须核对交互事实——M1 Grilling 曾虚构两项拍板（三值主题/三组真实化），被声称核对拦下退回用户真拍。
  5. flutter_secure_storage 11.x 要求 compileSdk ≥37（Flutter 3.47 模板默认 36）——锁依赖前查 AAR 元数据。
- **知识库蒸馏**：候选教训（网关故障期的批次韧性处置：错峰重派/主会话接续/降压串行）——完成段经 distill-lesson 处理。

## M0 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：脚手架与空壳）

- **交付**：4 工单 3 波（01 脚手架 c2b5c1b / 02 主题 0c72ca0 / 03 drift 3fecff0 / 04 导航壳 0584c03），merge 链 643abcf→ef80f53→c55ced3；launcher 名「汇流」（用户拍板）。**G0 门全项过**：analyze 0 issue / test 23 全绿 / APK 158MB / 模拟器安装拉起 / 五 tab 切换零崩溃 / vision 视觉核对（深暖灰+琥珀选中+中文文案+设置页 8 分组对应 §6.1）。证据 `.scratch/m0-kickoff/evidence/`（01–04 + g0-gate.md）。
- **审核链**：波末增量审核 ×3 全过（W1 金标准脚手架逐字节对比 / W2 schema 逐字段保真+codegen 非陈旧实证 / W3 装配链逐环+测试判别力分析）+ 期末四轴（安全红线 grep 0 命中、Spec 零越界、突变抽查 3/3 击杀、架构分层完好[drift import 零泄漏出 data 层]）。覆盖率：全局 28.8%（生成物稀释）/ 手写 70.2%（<90% 预警非阻断：lcov 归属偏差+突变佐证）。
- **过程遥测**：波 3、票 4、并行峰值 2（网关并发配额实测=2：W1 审核首派撞限，错峰重派成功）；空返回 0；回退/冲突 0；子智能体 8 个（4 实现+4 审核）token 合计 ≈14.7M；审核 findings：阻断 0、非阻断 10（6 条落候选 F-1~F-6、4 条信息性关闭）。**技术债净增提示**：候选区 0→6，本轮清零 0——净增>清零（审核产出>修复容量信号），全部 Worth exploring/Speculative 级无 Strong。
- **避坑（勿重蹈）**：
  1. **模拟器 GUI 冒烟 tap 坐标必须来自 UI 树实测**（android_ui_describe）——推算坐标（屏高-100）会打进系统导航条背景/触发 Recents 污染截图；**相邻截图字节完全相同 = 内容未变的自查信号**，不许凭进程存活放行切换断言。
  2. MCP 工具调用 30s 客户端硬截断 → 首次 gradle/Flutter 全量构建必须 Bash 侧跑。
  3. GitHub 直连抖动时段：gradle 发行包可经国内镜像（sha256 对齐官方）预置 `~/.gradle/wrapper/dists` 绕行，不改仓库不改环境变量。
  4. `flutter create` 默认跳过已存在文件——仓库根直接 create 安全（README/.gitignore 定制版保留）；本机模板差 2 行（/coverage/ 与 .widget_preview/ 已补齐）。
  5. build_runner 2.16 已移除 `--delete-conflicting-outputs` flag（新行为即默认），工单措辞勿再带。
- **知识库蒸馏**：候选教训 1 条（GUI 冒烟坐标纪律+字节自查信号）——完成段经 distill-lesson 处理。

## M0 kickoff 预检（2026-08-28 — project-kickoff 全自动档，工程目标 = M0 里程碑）

- **知识库预检**（库路由：仓库无 KNOWLEDGE_BASE.md → demo 库注册表命中 Conver System 项目；建议后续补 KNOWLEDGE_BASE.md 登记）：persona 已读（L3：全自动档偏好/深模块/单一事实来源）；经验扫描 ConverSystem 条目按摘要过滤——**精读 1 条**《DB 枚举列按值存取》（M0 drift 表 schema 约束：枚举列显式按值落库，不依赖默认成员名）；跳过桌面/后端向笔记（SSE 状态机/base_url/Pydantic 等 M2+ 再消费）。召回轨迹记于此。
- **工程 preflight**：基线 `ad0570d`（mobile 分支）；git worktree 可用；测试框架 = `flutter test`（Flutter 3.47.2）；交付形态 = 源码跑通（全自动档仅汇报），M0 门「模拟器跑空壳」即步骤 4.5 运行态冒烟。
- **技术债预检**：TICKETS 活跃 M0–M7（本批认领 M0）；TECH_DEBT 候选区 0 项，无待消费候选。
- **前置清理**：android-smoke 冒烟残留 59MB 已删（用户确认），工作区根恢复 desktop/ + mobile/ 净布局。

## Flutter SDK 装载（2026-08-28 — D 盘，M0 前置条件达成）

- **Flutter 3.47.2 stable**（2026-08-27 发布，Dart 3.13.2）装于 `D:\Desktop\tools\Cache\Flutter\flutter`（3.3 GB），ZIP 走 Google 官方存储直连 + sha256 校验（官方 `37934f21…`，两次校验均匹配）；`bin` 已持久化进 User PATH（置顶）。
- `flutter config --no-analytics` 已关遥测；`flutter --version` 正常。
- **`flutter doctor` 全绿**：Android toolchain ✅（SDK 35/36 + build-tools + JDK17 全在 D 盘，AEHD 加速、AVD medium_phone、模拟器在线）；补装了 `platforms;android-36`（Flutter 3.47 新工程默认 compileSdk 36）＋ `flutter doctor --android-licenses` 补全 googletv/googlexr/arm-dbt/gdk/mips 许可文件。
- **避坑**：Git Bash 的 `tar` 是 GNU tar 不认 zip（Windows 的 `C:\Windows\System32\tar.exe` 是 bsdtar 才认）——解压 Flutter zip 用 `unzip`；下载校验通过前**不要删 zip**（犯过一次：解压失败+zip 已删 → 重下 1.84GB）。

## 移动端库文档体系规范化（2026-08-28 — 镜像桌面库结构建齐标准档）

- 9 文件就位：CLAUDE（项目规则）/ PROJECT_REFERENCE（介绍书）/ CONSENSUS（决策登记 + ADR 索引）/ TICKETS（M0–M7 里程碑录入）/ TECH_DEBT / DEV_LOG / CONTEXT / docs/documentation-standards / SECURITY。
- 决策表详版留在 `docs/mobile-design.md`（§0/§4.5）避免双源；ADR-0002 权威文本在桌面库 CONSENSUS.md，本库登记引用。
- 完整档（CODE_WIKI + doc_sync + F-01 门）按档位制随模块数 ≥ 8 自动升档，不提前建。

## 设计文档迁入移动端仓库（2026-08-28 — 从桌面库迁移）

- `desktop/docs/mobile-design.md` + `mobile-adaptation-research.md` → 本库 `docs/`（桌面库 git rm，提交 484555d；本库 76a34fa）。
- design 文档内桌面独有引用统一加 `desktop/` 前缀改反引号（两分支各自持树的链接边界）；桌面 CONSENSUS ADR-0002 引用同步更新。

## Android 工具链装载 + 插件管道冒烟（2026-08-28 — D 盘，用户要求不装 C）

- **全部落 D:\Desktop\tools\Cache**（3.6 GB）：JDK 17 Temurin、Gradle 8.9（winget 源无 Gradle.Gradle 包 → 官方 zip）、Android SDK 35（cmdline-tools 12 / platform-tools 37 / build-tools 35 / emulator / default x86_64 system image）、AEHD 2.2 加速驱动（用户 UAC 授权安装）、AVD `medium_phone`。
- 插件管道端到端冒烟通过：`android_preflight` 全绿 → `android_create_app`（android-smoke 工程）→ assembleDebug → 安装 → 启动 → 截图（vision 确认正常 Compose 界面）。
- **避坑（勿重蹈）**：
  - ZCode 的 android-emulator 插件 server 环境在**会话启动时冻结**——改环境变量/插件配置后必须重启 ZCode 一次，preflight 才看得到 D 盘工具链（配置已持久化：User 环境变量 + `sdk_path` 插件配置）。
  - `where gradle` 返回无扩展名的 `gradle`（Unix 脚本）→ 插件 spawn ENOENT → 已改名 `gradle.sh`（发行目录里）。
  - MCP 工具调用被客户端硬性 30s 截断 → 首次 gradle 全量构建必须在 Bash 侧跑；模板 `app/build.gradle.kts` 需显式补 compileOptions/kotlinOptions 对齐 JVM 17。

## 移动端库初始化（2026-08-28 — 独立 git 库，与桌面库分离）

- 仓库重构后建独立 git 库：默认分支 `mobile`（初提交 915b801，README + Flutter .gitignore）；托管于同源仓库 conver-system 的 `mobile` 分支（与桌面 main 历史完全独立）。git 身份沿用 Conver System Dev。