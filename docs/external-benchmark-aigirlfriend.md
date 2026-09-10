# 外部对标档案：AI风月（aigirlfriendstudio.com）

> **角色**：本文件是该外部站点的**调研档案 + 方法论沉淀**（对方是什么、怎么查出来的、证据在哪）。
> **不承载**：本项目要实现什么 → 见 [chat-simulator-upgrade-spec.md](chat-simulator-upgrade-spec.md)；待办 → 见 [TICKETS.md](../TICKETS.md)。
> **维护约定**：本文件是**只读历史档案**，后续如需补充对方事实，续写在本文件；不要把这些事实复制进其他文档。
> **调研轮次**：2026-09-10（单会话完成，FetchFlow 流程）

---

## 一、调研动因与边界

**动因**：本项目（纯本地、不盈利、不做社交/积分体系）的「聊天 + 模拟器」功能体验需对标该站：记忆宫殿、世界书编辑器、MOD 挂载层、消息级操作、存档分支、CG/剧情回顾沉淀。

**授权与边界**（用户约定 + FetchFlow 契约）：
- 目标 robots.txt 为 `User-Agent: * / Disallow: /`（整站），预检判 CHECKPOINT → 用户确认授权学习后继续。
- 网络画像 `authorized_target_only`：同源只读 GET、低频串行、不爆破接口。
- 登录态阶段只做**观察式**只读请求：未发送聊天消息、未触发计费/支付路径、未遍历列表（分页 limit 仅取 2-3 条探结构）。
- 不采集登录墙后的他人私有内容；报告剔除账号标识与凭证。

---

## 二、目标站技术画像（含证据）

| 维度 | 事实 | 证据 |
|---|---|---|
| 前端框架 | Next.js + Turbopack SPA（App Router，RSC payload 内嵌服务端渲染壳） | `_next/static/chunks/*` 命名 + HTML 内 `self.__next_f.push` |
| 聊天应用层 | **Dify 定制版**（复用 Dify webapp 骨架：i18n 资源、docs.dify.ai 链接、`/console/api` 前缀、provider 管理页文案） | 业务 bundle 内 Dify 多语言资源 |
| 后端语言 | **Go**（世界书正则要求 Go 语法，正则限 600 字节） | 编辑器 i18n `regexRulesHint` / `regexRulesLimitHint` |
| API 分层 | `/go/api/*`（业务自研层）+ `/console/api/*`（Dify 派生层） | 登录后网络瀑布 |
| 认证 | Firebase Auth（Google OAuth）+ 账号密码 + Telegram；`authDomain` 与 bot 信息打进公开 bundle | Google OAuth 跳转 URL、bundle 内环境配置表 |
| 多端 | Windows 安装器 / Android APK（含版本表）/ iOS 版本表 | `/go/api/workspaces/current` 字段 |
| 内容分级 | R18 与全年龄**双短链分流** | `/go/api/account/profile` 的 `nav_r18_short_link` / `nav_all_age_short_link` |
| 流式协议 | Dify SSE 事件全集（message_start / agent_message / agent_thought / message_end / message_replace / message_file / error / ping / workflow_* / node_*） | 全库事件名字面量统计 |
| 计费粒度 | **消息级**（`/installed-apps/{id}/messages/{mid}/points`）+ 退款 + 免费额度 | 端点字面量 |
| 生图链路 | providers → task → task/status 轮询（10-30 秒）→ 结果插入聊天框下方 | text2img 端点族 + i18n 文案 |

---

## 三、五套机制的对方事实（本档案只记「对方是什么」）

### 3.1 世界书（Lorebook）
- 条目字段：关键词（可多个，回车/「添加」录入）、内容、触发源、触发模式、影响位置、插入顺序 0-9999、扫描深度 0-20、触发概率 1-100、单条开关。
- 触发源三类：**System**（角色卡或配置里已写的 prompt/前缀/后缀）、**User**（用户输入）、**AI**（AI 回复）；**AI 触发时在触发轮的下一轮才读取**。
- 触发模式：AND（全部关键词出现）/ OR（任一出现）；另有正则键模式。
- 影响位置：Prompt / 前缀词 suffix / 后缀词 prefix 三段。
- 限额与校验：2000 条上限；单条内容 ≤ 40000 字符；prompt ≤ 30000、≥ 120 字符；含 script/iframe/object 判 XSS 拒绝；概率模式下同组概率和须为 100。
- 反滥用条款：禁止选用「。」「，」「你」「我」「他」等泛词，被举报判为「积分刺客」→ 下架/清热度/封号（**说明其匹配是子串/正则级、非语义级**）。
- 作者端帮助文档原文**内嵌在业务 bundle 里**（含「## Lorebook Introduction」整段教学），是本档案最硬的一手证据。

### 3.2 记忆宫殿（Memory Palace）
- 位置：对话页「记忆增强」面板，与「自动总结」**互斥**（官方明示不建议同开）。
- 机制：每轮对话要点自动总结为**世界书条目**并持久化；生成条目的参数**固定**：影响范围=提示词、扫描深度=20。
- 召回：除当前对话与上下文外，还会把记忆宫殿中**所有条目的关键词与内容**提供给 AI，辅助更新整个记忆宫殿。
- 管理：条目可手动修改/删除；面板内可关键词搜索。
- 与存档关系：**可跟随存档一起创建分支或分享**。
- 成本语义：开启后自动生效、少量消耗；活动期生成免费但**触发注入仍计费**。
- 自动总结（另一路线）：开启后「记忆设定」参数失效，仅完整加载上一条消息，更久远的精炼后拼进系统提示词；**记忆内容达 10000 字符自动触发**；总结结果含 sorry/对不起 视为命中过滤。

### 3.3 MOD 挂载层
- 挂载粒度：**作品级**（`/console/api/apps/{appId}/setappmods`）。
- 分区：Available / Selected / Purchased / Created + 公开 Mod / 专属 Mod（dedicated）。
- 操作：Use / Remove / Select versions（**版本选择**）/ Mod Settings；排序按 Order / Purchase Count / Created At。
- 具备付费与评分（points / purchase / ratingCount / averageRating / usageCount / lastUsedAt）——本项目明确不做。
- 可注入上下文：提示词调试来源维度含 `mod`（与 app / user 并列）。
- 上传入口：对话页「自定义配置 → 上传为 Mod」。
- 官方警告：Mod 会增加消耗、让 AI 更难理解、装太多会与作者设定或其他 Mod 冲突。
- 典型用途：给「没有记忆区的作品」加载「记忆区 Mod」。

### 3.4 消息级操作
- 面板词汇：send / resend / copy / more / lineBreak / continue（继续）/ reload=Regenerate（重新生成）/ download / delete / settings。
- 编辑重发可勾选「同时删除本次对话信息」；删除有不可恢复二次确认。
- 服务端任务模型：生成可停止（`POST /apps/chat-stop` body `{task_id}`），另有 `/apps/chat-refund`（退款）与 `/apps/chat-regex-replaces`（会话级 + 作品级正则清洗）。
- **语义澄清**：`fold / unfold` 与 pin / hide 同组，是**作者折叠内容**与评论/存档条目操作（`foldedContent: 作者已将内容折叠`），**不是**折叠 AI 长回复。
- 列表级：置顶/取消置顶、隐藏/取消隐藏、按时间/点赞排序。

### 3.5 存档 → 分支点
- 端点契约：`POST /messages/branch/create`（建分支）、`POST /messages/branch/create-branch-conversation` body `{branch_id}`（用存档/分支开新会话）、`GET /messages/branch/share/{id}/list`、`POST /messages/branch/share/{id}`、分支评论 `GET /comments/branches/{id}`。
- 存档 = 会话快照，三重角色：分支点 / 分享单位（他人可用你的存档开新会话）/ 讨论单位（存档评论，不支持评分；作品才可评分）。
- 记忆宫殿条目随存档一起分支/分享。

### 3.6 CG / 剧情回顾
- 生图链：`GET /llm/text2img/providers` → `GET /llm/text2img/preset-roles` → `POST /generation/extract-role-names`（**从消息抽角色名决定画谁**）→ `POST /llm/text2img/task` → `POST /llm/text2img/task/status {task_ids}` 轮询 → `GET /llm/text2img`。
- 交互文案：生成中 / 需 10-30 秒 / 完成后自动出现在聊天框下方 / 失败提示；提交前显示 UTF-8 长度与预计消耗。
- 沉淀：`POST /apps/{id}/cg_images/create {image_url}`（图片库→CG）、会话级 `GET /apps/{appId}/chat-conversations/{cid}/cg_images`、画廊 `GET /apps/{id}/cg_gallery`。
- 画廊 UI：解锁进度 / 查看 / 解锁提示 / **剧情回顾**。
- 作者端 CG 编辑器：默认分组 / 移动分组 / 设为特殊 CG（有上限）/ 解锁后显示名称 / 解锁提示 / **概率加权抽一张**（触发时从加权池随机出一张）/ 各类数量上限 / 建议压到 5MB 以下。
- 旁证：语音沉淀同类链路（`POST /t2v`、`/t2v/apps`、`/t2v/audios`、预设音色清单 AUDIO_MODEL_LIST）。

---

## 四、方法论（可复用于任何同类对标）

1. **授权预检**：FetchFlow `check_target.py` → ALLOW / CHECKPOINT / BLOCK；命中 robots 或登录墙即摆信号给用户确认，不静默放行。
2. **纯静态优先**：现代 SPA 的正文与业务逻辑都在构建产物里，**不碰登录态即可拿到绝大部分实现证据**。串行低频下载 chunk 后本地分析。
3. **分析流水线**（本项目实测有效的顺序）：
   1. 抓 HTML 壳 → 提取资源清单（`_next/static`）
   2. 下载全部 JS/CSS chunk（29 个）
   3. 路径字面量收集（正则提取 `"/xxx"` 字符串）→ 得到完整 API 面
   4. 关键词频次定位业务 bundle（chat / message / SSE / token 计数最高的即主逻辑；注意剔除语言包与第三方库噪音，如 Wolfram / Arma SDK 字符串）
   5. 上下文切片（命中处 ±N 字符）挖字段与语义
   6. **i18n 资源是金矿**：作者端帮助文档、编辑器校验文案、错误提示直接内嵌，能还原产品语义与约束（本例的世界书教学文档就是从 i18n 里整段提取的）
   7. 前端 API 客户端源码（函数名 + 端点 + body 形状）直接给出契约
4. **证据分级**（写结论时标注）：运行时实测 > 客户端源码契约 > i18n 文案 > 结构推断。
5. **登录态使用纪律**：只做只读 GET 观察，不发消息、不触发计费、不遍历列表。
6. **视觉与设计 token**：用 `getComputedStyle` 批量提取字体/色板/圆角/字号/阴影，比截图更可量化（截图受沙箱写入路径限制）。

---

## 五、复现路径（想重做或复核时照此执行）

```bash
# 1) 授权预检
python <fetchflow>/scripts/check_target.py https://<target>/

# 2) 抓壳与资源清单
python -c "..."   # curl_cffi impersonate=chrome 抓 HTML 存盘

# 3) 下载静态资产（串行 + sleep 0.25s，参考 D:\tmp\fetchflow-aigs\download.py）
# 4) 端点收集（参考 paths*.py）
# 5) 关键词定位（参考 analyze.py / dig*.py）
# 6) i18n 语义提取（参考 ui-terms.py / wb-doc.py）
# 7) 登录态只读观察（Playwright：network_requests + page.evaluate 里的 fetch 探结构）
```

原始证据目录（**仓库外**，可能被清理）：`D:\tmp\fetchflow-aigs\`
- `assets/`：29 个 JS/CSS chunk（含主业务 bundle）
- `html/`：首页与中文页壳
- 三份对标笔记：`aigs-chat-sim-benchmark.md` / `aigs-lorebook-memory-palace-spec.md` / `aigs-mod-msg-branch-cg-spec.md`
- 提取脚本：`download.py` / `paths*.py` / `dig*.py` / `analyze.py` / `ui-terms.py` / `wb-doc.py` / `st-fields.py`
- `analysis-keywords.txt`：关键词频次与端点汇总

---

## 六、可复用轮子（对方机制的既有标准）

| 需求 | 成熟轮子 | 关系 |
|---|---|---|
| 世界书 / 记忆 | **SillyTavern World Info / Lorebook**（键/内容/常驻/顺序/概率/分组/正则/位置/深度） | 对方即此规范的产品化变体；本项目 D4 已选定该规范 |
| 消息操作面 | SillyTavern 消息操作面板 + **swipes**（同一消息多备选回复、左右切换） | 比「改写」更实用的候选模型 |
| 会话存储 / 分支 | SillyTavern chat 文件（每会话一 JSON，含 swipes / extra） | 与本项目导出契约同构 |
| 剧情自动配图 | 社区扩展（自动按剧情出图）/ Stable Diffusion 扩展（多后端、本地部署友好） | 对应 CG 沉淀 |
| 存档 / 检查点 | 同类产品的 chat checkpoint / branch 思路 | 与本项目模拟器存档面板合并为「分支点」 |

> 许可提示：SillyTavern 及其扩展的许可证以各仓库 LICENSE 为准。本项目纯本地不盈利，仍需按实际许可决定「参考实现」还是「直接复用代码」。本轮调研网络受限（本机 DNS 将 github / raw.githubusercontent / deepwiki / docs.sillytavern.app 解析到非公网 IP），未能核到许可证原文。

---

## 七、环境坑（本次实测，勿重踩）

1. **DNS 拦截**：上述域名 `web_fetch` 全部失败（返回非公网 IP），只能靠 `web_search` 摘要；要 ST 规范原文需换网络环境。
2. **采集脚手架不要留在仓库内**：`scripts/doc_sync.py` 的 files 校验会把仓库内 .py/.js/.rs 与 CODE_WIKI.md 引用做双向覆盖，临时脚本入仓会立刻报漂移。正确落点是仓库外（如 `D:\tmp\`）。
3. **src-tauri 构建缓存残留旧盘符**：仓库从 D 盘迁到 F 盘后，`src-tauri/target` 内 tauri-build 缓存仍记录 `D:\...` 绝对路径 → 编译失败（读不到 permissions 文件）→ doc_sync cargo 渠道降级、tests_total 少 70。修法：`cargo clean` 后重建。
4. **Playwright 输出目录受限**：截图只能写入其 allowed roots；改用 `getComputedStyle` 提取设计 token 更稳妥。

---

## 八、与本项目的关系（一句话总览）

对方是我们功能体验的对标物，但其记忆/内容机制的**标准血统是 SillyTavern 世界书**，且本项目角色卡 V2 已带 `character_book` 往返保真、`docs/world-simulation-exploration.md` 已选定该规范路线 —— 因此本项目**不需要逆向对方**，只需按 `chat-simulator-upgrade-spec.md` 实现引擎与生成层。
