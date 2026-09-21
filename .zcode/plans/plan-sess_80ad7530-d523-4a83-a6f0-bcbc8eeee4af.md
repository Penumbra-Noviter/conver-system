## 模拟器卡片简介自动生成（混合方案）实现计划

### 目标
1. **种子 22 款**：描述不再模板化——一次性 LLM 生成有特点的简介，逐条人工审校后固化进 `assets/simulators/manifest.json`（随包，用户无感）。
2. **导入/自定义游戏**：导入后自动生成简介写回数据目录 manifest（当前导入条目 description 为空、卡片空白）。

### 新模块（`lib/services/simulator/`，纯 Dart 深模块）
1. **`game_summary_extractor.dart`** — 规则提取器（零 LLM 零成本）：
   - `SummaryCandidate extract(String html)`：提 `<title>` + 去 CSS/JS 后的可见文本 + JS 内 prompt 设定段（关键词「世界观/你扮演/系统设定/背景/玩法」上下文抽取，AI 驱动游戏的内容真正载体）
   - `buildFallbackSummary(SummaryCandidate)`：规则拼兜底简介（永远可用）
   - 容错：坏 HTML / 废 title（2 款 title 是「AI 角色扮演游戏」）/ 纯本地游戏无 prompt 段 → 逐级降级不抛
2. **`game_description_generator.dart`** — LLM 精修（仿 game_generator 链）：
   - 构造注入 `LLMProviderFactory` + `resolveCredentials`（复用 app.dart `_resolveGenerationCredentials`，第六处）
   - `Future<String> generateDescription(SummaryCandidate)`：非流式 `provider.generate`，生成 ≤60 字中文简介；LLMError/超时/空回复 → 回退规则简介，不抛

### 写回落点（复用既有路径）
- 新 `updateManifestEntryDescription(simDir, id, description)`（读-改-写，`.tmp`+renameSync 原子替换，与 `game_generator._updateManifestEntryDescription` 同构）
- 触发点：`import_flow.dart` 导入成功路径——description 为空时先规则提取写回（同步，零成本）→ 开关开启且有 Key 时异步 LLM 精修替换 → 完成后刷新控制器（`SimulatorsController` 加公开 `refreshManifest()`），卡片自动更新，无「生成中」UI 态

### 设置开关（对齐 embedding_enabled 模式，默认关=成本敏感 opt-in）
- `SettingsRepository`：键 `simulator_llm_description_enabled` + allowedKeys 白名单 + `simulatorLlmDescriptionEnabled` getter
- `conversation_settings_page.dart`：第 7 个 SwitchListTile「简介 LLM 精修（模拟器）」+ 写失败回滚
- 规则提取**默认恒开无开关**（纯本地、零隐私/成本问题）

### 种子固化（人工审校环节）
实现后跑一次 LLM 批量生成 22 条 → 逐条人工审校（去幻觉/夸张/与题材不符）→ 写回 `assets/simulators/manifest.json`（保持 JSON 格式与字段结构不变）

### 测试计划（先红后绿）
- `game_summary_extractor_test.dart`：真实 assets HTML fixture（含废 title 款）+ 合成 fixture（空正文/无 title/英文 title/无 prompt 段）证伪
- `game_description_generator_test.dart`：`ScriptedFakeLLMProvider` 脚本化 + 失败回退 fallback
- `import_flow_test.dart` 扩展：导入后 description 非空 + manifest 原子写
- `settings_repository_test.dart`：白名单断言 + getter 往返；`conversation_settings_widget_test.dart`：新开关 toggle
- 种子固化后相关 manifest/seed 测试全绿

### 验证
`flutter analyze` 0 + 全量 `flutter test` 绿 + 波及文件覆盖率 ≥90% + 期末四轴复核（含证伪：废 title、无 prompt 段、LLM 失败、description 已存在幂等）

### 不做（范围收敛）
- 卡片 UI 大改（无「生成中」态，异步精修后台完成刷新）
- 新建模拟器设置页（开关先放对话子页）
- AI 生成游戏描述改造（F-47 已有 `deriveGeneratedDescription`）