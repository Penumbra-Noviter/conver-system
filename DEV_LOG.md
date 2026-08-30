# Conver System 移动端 — 开发日志 (DEV_LOG)

> 只记「已做」与决策/避坑；待办一律进 [TICKETS.md](TICKETS.md)（唯一待办事实来源）。
> 格式：`YYYY-MM-DD | <操作> | <描述>`（倒序，最新在前）
> 滚动摘要窗口上限 12 条，超限在文档同步时折叠为阶段摘要。

---

## M3 kickoff 批次（2026-08-30 — project-kickoff 全自动档交付：角色 + 搜索里程碑）

- **交付**：Grilling 共识 5 面拍板（零真拍点 + 3 best-judgment 非拍板：导入占位保留 UI / 批量删除含可裁 / 开始对话默认模型）。8 票 4 波 DAG（W1 M3-01‖M3-04a / W2 M3-02a‖M3-04b / W3 M3-02b‖M3-03‖M3-04c / W4 M3-05，基线 f477e2d → merge 70bc094）。角色列表卡片+四按钮+下拉刷新+长按批量删除 / 6 步全屏向导+5 模板逐字移植（senpai/wanderer/tsundere/butler/nekomimi）/ V2 卡导入导出纯 Dart 服务（四格式识别+V1 兼容+temperature 裁剪）+ seam 收口（file_picker ^12.1.2/share_plus ^13.3.0/path_provider ^2.1.6 转正）/ 跨对话搜索防抖五态+跳转定位 3s 高亮（GlobalObjectKey+ensureVisible）。证据 `.scratch/m3-kickoff/evidence/`（M3-01~05 + W3 独立复核 + smoke-gate + 冒烟 PNG）。
- **门禁链**：全量 **729 测**全绿（M3 交付后 726 + 期末修复 3 新用例）/ analyze 0；覆盖率剔除 drift **98.06%**；四轮波末增量审核（W3 用户要求独立复核轮，0 阻断独立复现 179 测绿）+ **期末四轴零阻断**（Spec 8/8 票满足、F-7 token 契约全库绿、安全红线 0、架构无阻断）；**冒烟 PASS**（角色列表→向导模板建「知性学姐」→保存落库→搜索 hihello→跳转定位高亮全真机实证，UI 树确定性证据）。
- **主会话修复（期末发现低成本真缺）**：
  1. **F-7 契约回归 x2**：M3-04b search_view（d76e85e）+ M3-04c chat_view（ff24612）直接引用 ConverColors 违反视图层 token 契约 → 改经 `colorScheme.primary.withValues(alpha:0.13)` / `palette.border`，静态不变量 `view_theme_tokens_test` 真实绿
  2. **期末四项**（0057d9e）：NaN 温度绕过 [0,2] 裁剪（`_clampTemperature` 补 isNaN 回退 0.7，期末 Falsify 对抗发现）/ manual 回退后 next 误入步骤②（`next()` 补 manual 从①跳③）/ Escape 清空不递增 `_requestSeq` 致在途查询回填空态 / 删除角色后聊天入口陈旧 `_firstCharacter` 缓存（`invalidateEntryCache` 接入 deleteCharacter）
  3. **构建配置**（9cfc4aa）：`android/gradle.properties` 追加 `kotlin.incremental=false` + `org.gradle.parallel=false` 绕开 Kotlin daemon Windows 并行编译 storage 注册冲突（file_picker/share_plus 多模块触发）
- **过程遥测**：票 8、波 4（并行 2+2+3+1）、merge 8；子智能体 20+（含网关故障重开 M3-05 x3——两次静默死亡半成品 +849 行接续、W3 审核重开、W3 独立复核轮）；空返回/静默死亡 3（M3-05 x2 + W3 审核 x1）；回退 0；审核 findings：W1 增量 4、W2 增量 7（含 2 真缺）、W3 增量 18 + 独立复核 12、期末四轴 14 全非阻断。**技术债净增**：期末四轴非阻断观察按契约落盘 TECH_DEBT——F-18 校验门分置（Worth exploring，📝 待立项）+ F-23 平台真通道冒烟未深度触达（Worth exploring，📝 待立项）；F-19~F-22（CharacterDraft docstring / 双 timer / light alpha / searchPreview 边界）git grep 复核现状仍成立后 ❌ 复核关闭（处置记录留痕）。
- **避坑（勿重蹈）**：
  1. **子代理静默死亡**：M3-05 两次 agent 无通知死亡（任务记录消失），半成品在盘（controller/view/测试已改）——「无完成通知」时立即查磁盘 worktree 状态，半成品接续而非重写（第 3 次派发接续后 DONE）
  2. **F-7 契约回归进主分支**：M3-04b/04c 视图直接引用 ConverColors 违例被合并（全量测试未跑 view_theme_tokens_test 静态不变量）——波末合并后必须跑全量（或至少静态不变量组），不能只跑受影响模块
  3. **期末四轴对抗发现 NaN 温度**：JSON 字面量 NaN 被 jsonDecode 宽容接受、double.tryParse 返回 NaN 非 null——「非法值回退」类契约必须显式 isNaN 守卫（Falsify 用恶意输入打数据通路价值再证）
  4. **Kotlin daemon Windows storage 冲突**：`Could not close incremental caches ... already registered` 在新增多 Kotlin 模块（file_picker/share_plus）后触发——in-process 策略不覆盖此路径，需 `kotlin.incremental=false` + `org.gradle.parallel=false`
  5. **M3-05 半成品含残留脚本**：`cov_miss.py`/`cov_report.py` 覆盖率统计脚本留在 worktree——半成品接续时须清理临时脚本
- **知识库蒸馏**：候选教训（子代理静默死亡磁盘核验 / F-7 契约回归合并后全量测试 / NaN 温度 Falsify）——完成段经 distill-lesson 处理。

## 技术债消费批次 F-10~F-17（2026-08-30 — project-kickoff 全自动档交付：技术债八候选消费）

- **交付**：Grilling 共识 8 候选 **7 做 1 关闭**（F-15 关闭：桌面 ChatResponse 契约镜像 + F-6 先例 + 测试锁定，零真拍点）。6 工单 2 波 DAG：波1 T2‖T4‖T5（T2 `7d86628` ConverPalette of/maybeOf + 41 处迁移 / T4 `c040c06` 翻译栈共享 / T5 `353a857` CharacterNotFoundError 404 归类）merge `14bf479`；波2 T1‖T3‖T6（T1 `57c3db8` 保存事务化 / T3 `fe98671` 主题异步面 catchError+重入守卫 / T6 `e4ece9c` cancel 加界）merge `b9dc9bc`。证据 `.scratch/techdebt-f10-f17/evidence/`（T1~T6 + smoke-gate + 5 张冒烟 PNG）。
- **门禁链**：全量 497 测全绿 + analyze 0；覆盖率手写口径（剔除 drift 生成物 3 文件）**97.96%** ≥ 90%；波1/波2 增量审核 Falsify 16 项构造验证**全非阻断** + 文件范围 6 票全合规；**期末四轴零阻断**（Spec 6 工单验收语义全满足、token 契约/文案锚/errors.dart 零 dio 契约三约束保持、安全红线 0、架构无阻断）；运行态冒烟 PASS（设置页渲染 / 主题深 `#171512`↔浅 `#F0ECE5` 像素精确 / logcat 零异常）。
- **过程遥测**：票 6、波 2（并行 3+3）、merge 6；子智能体 13 个（Grilling/plan-tickets/Implement×6 含重开×2/code-review×3/主会话接续×1）；**空返回重开 2**（T5/T6 首派均零产出：T5 空 worktree、T6 半成品测试 +93 接续），重开后均 DONE（半成品接续优于重写复证）；回退/冲突 0；审核 findings：波1 增量 8 非阻断、波2 增量 8 非阻断、期末 5 非阻断（命名通用 ×2 / Data Clumps / snapshot+written 成对 / T6 测试上界 6s 慢 CI flaky 观察）。**技术债净增**：清零 8 → 追溯补录 3（F-24~F-26 Speculative 复核关闭，处置记录留痕；原「不入债」为交付偏差，2026-08-30 按契约纠正）。
- **避坑（勿重蹈）**：
  1. **子代理「声称无任务」型假完成**：T5/T6 首派均返回与任务无关内容（浏览器话题/「我没有任务」）且磁盘零产出——完成通知不可信，**必须以磁盘事实核验**（worktree commit + evidence 文件），核验零产出即重开复用 worktree（本轮两票重开后均 DONE）。重开 prompt 必附「前次现场核查指令」。
  2. **check-complete.py 的 STATUS token 格式**：脚本认 `STATUS: <状态>`（票号须放行尾注释 `# T`），且**未派发工单不放 STATUS 行**——首写把票号塞进 token 值导致「未找到 token」，修正后通过。
  3. **模拟器截图像素采样**：screencap PNG 为 colortype=6（RGBA）且每行带 filter 字节，裸解析得到全零；须用 PIL `Image.convert('RGB')` + getpixel（同 M1 教训：像素采样是确定性证据，命名/假设不是）。
  4. **plan-tickets 首派「未收到输入」**：子代理持有 prompt 但声称无输入——重开时把共识全文内联进 prompt（不依赖它读文件），二次调用即产出完整工单。
  5. **期末全局覆盖率口径**：`flutter test --coverage` 全量产 lcov，drift 生成物 `app_database.g.dart`（468 行 29.9%）拉低全局到 66.31%——按 M2 同口径剔除 3 个生成文件后 97.96% 达标（生成物不经测试覆盖是预期，此前批次已固化此口径）。
- **知识库蒸馏**：候选教训 2 条（子代理「假完成」必须磁盘核验 / 模拟器像素采样用 PIL 解码 filter）——完成段经 distill-lesson 处理。

## M2 kickoff 批次（2026-08-29 — project-kickoff 全自动档交付：聊天核心）

- **交付**：7 票 5 波 DAG（T00 工程门 e623268 / T01a Prompt 组装 bfc701d / T01b SSE+LLM 抽象 4f87f3d / T02 双协议 wire 2cc1c5b / T03 ChatService 342ddad / T04 聊天 UI 4b143d2 / T05 test_connection 0f88df7）+ 波3修复（a1bc0cc）/波4修复（a251df3）/期末收尾（0f9c33f），merge 链至 `59e766a`。证据 `.scratch/m2-kickoff/evidence/`（T00~T06 + 09-smoke-gate-a7 + 冒烟 PNG）。**A1~A8 门**：477 测全绿 / analyze 0 / 覆盖率手写口径 95.42%；**A7 冒烟 PASS（窄路径）**——模拟器端到端实证：入口 UI/autoGreeting/发送链/「未配置 claude API Key」逐字错误/测试连接 SnackBar（logcat+像素）；真实打字机流式留待用户 Key（付费账户未擅自调用）。
- **关键架构修正**：移动端无后端中间层，SSE 契约源 = **Anthropic/OpenAI 官方原始协议**（非桌面统一帧）；`temperature` 官方已弃用 → 不透传（research 实证，修正 Grilling 初判）；flutter_markdown 已 discontinued → flutter_markdown_plus（best-judgment，用户未答）；两端真拍点（markdown 包/最小入口）用户未答，按推荐定案并注明非拍板。
- **审核链**：波3增量审核（F1 阻断 regenerate×streamReply 数据丢失 / F3/F4/镜像 seam/F5）+ 波4增量审核（F1 阻断 stop 竞态 UI 丢失 / F3b/F2/F4）——四轮修复全被增量审核或合并核验捕获；期末四轴**零阻断**（Spec A1~A8 全过/安全红线 0/架构翻译栈去重非阻断）。
- **过程遥测**：票 7 + 修复 3 + 收尾 1；网关故障 0（本批未遇）；空返回 1（T05 首次中断，重派接续半成品）、T04 重派接续（ChatController 482 行半成品保留）；子智能体 13 个 token ≈ 1.2 亿；审核 findings：波3 阻断 1/Falsify 5、波4 阻断 1/Falsify 5、期末非阻断 9。**技术债净增**：本轮清零 0 → 净增 4（F-14~F-17）。
- **避坑（勿重蹈）**：
  1. **并行票 seam 契约必须合并后实测**：T02/T03 并行开发，T03 按「基类 LLMError 精确判型」、T02 实现「LLMConnectionInterruptedError 子类」——各自单测全绿、集成断流失效，合并时人工核验捕获。并行票间共享 seam 的契约要写进双方工单并合并后跑集成路径。
  2. **半成品接续优于重写**：T04/T05 两次中断（T05 片段文本早亡、T04 长会话中止），worktree 半成品保留，重派接续（ChatController 482 行/测试骨架 293 行全复用），接续成本远低于重写（M1 教训复证）。
  3. `adb shell input text` 不支持中文（Unicode NPE）——模拟器冒烟输入用 ASCII；adbd 管道 `cat` 会损坏二进制（用 run-as 设备端 sqlite3 直查，勿 pull 后本地解析）。
  4. drift_flutter DB 在 `app_flutter/` 目录（非 databases/），冒烟播种角色走设备端 sqlite3 run-as。
  5. `dart format` 全文件误触会引入无关重排——修复只改目标行（T04 修复教训）。
- **知识库蒸馏**：候选教训（并行 seam 契约合并在即实测 / 半成品接续复用 / 模拟器冒烟设备端数据操作）——完成段经 distill-lesson 处理。

## 技术债消费批次 F-7/F-8/F-9（2026-08-29 — project-kickoff 全自动档交付：技术债三候选消费）

- **交付**：3 工单单串行链（01 F-9 eb51b99 / 02 F-8 a7064fb / 03 F-7 ea1b724），merge 68e8d19（基线 78b8a94）。**F-7** ConverPalette ThemeExtension（ink1-4/border 5 枚，dark/light 注册 ConverTheme）+ 5 视图 25 处消费改经 `extension<ConverPalette>()!`（M1 同构契约零改动）；**F-8** 设置页三处失败路径统一失败 SnackBar + debugPrint、theme onSelectionChanged async await、settings_view 去静默吞错；**F-9** 视图层装配 required 化（删 AppDatabase.open/FlutterSecretStore 缺省分支 + app_database import），home_shell 单一装配链。
- **门禁链**：全量 171 测全绿 + analyze 0；覆盖率手写口径（剔除 drift 生成物）90.63% ≥ 90%；波末增量审核（Falsify 阻断 0、文件范围合规）；**期末四轴零阻断**（Spec 24/24 验收全过、Standards 0 硬违规安全红线 0、Architecture 无阻断、Falsify 6 非阻断）；运行态冒烟 PASS（模拟器浅色 #F0ECE5 / 深色 #171512 像素精确，主题双向切换成立，F-7 浅色主文字可读 vision 实证）。
- **过程遥测**：票 3、波 1（串行链）、并行 1（单 lane）；空返回 0、回退/冲突 0；子智能体 5 个（Grilling/plan-tickets/Implement/code-review×2）；波末审核 findings 非阻断 2（N1/N2）、期末 findings 非阻断 11（Falsify 6 + Standards/Arch 判断 5）。**技术债净增提示**：清零 3（F-7/8/9）→ 净增 4（F-10~F-13），净增 > 清零——审核产出仍大于修复容量，下一轮预检可继续消费。
- **避坑（勿重蹈）**：
  1. **截图主题状态先采样确认再下结论**：冒烟首张「深色基准」截图实际是浅色（应用持久化主题为浅色，前会话收尾态）——像素采样（背景 == token 精确值）是主题状态的确定性证据，vision 描述与命名假设都不可作为基线（来源：本批冒烟 4.5，教训已入冒烟证据 08-smoke-gate.md）。
  2. Flutter widget 测试碰 ThemeExtension：消费 `extension<ConverPalette>()!` 的组件在未注册扩展的测试环境 null 崩溃（fail-fast 契约）——测试泵 section 必须用 ConverTheme.dark() 包裹（F-7 涟漪，已申报记录警告档）。
  3. F-8 的 async 错误面改动暴露既有顺序写非事务性（N1）——失败 UI 把「部分持久化」首次显性化，落债 F-10；改错误面需顺带审视持久化原子性。
- **知识库蒸馏**：候选教训 1 条（运行态验证先确认基线状态：像素采样 vs 命名假设）——完成段经 distill-lesson 处理。

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