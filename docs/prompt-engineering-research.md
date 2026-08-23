# Prompt Engineering Research — 模板填充式游戏生成

## 调研结论

采用**结构化系统提示 + 模板标记 + 低温度 + 验证重试循环**的组合方案。

## 核心发现

### 1. 系统提示应使用 XML 分隔标记

来源：Anthropic 官方教程 — 04_Separating_Data_and_Instructions
- 将指令与数据分离，用 XML 标签包裹用户输入（如 `<world_building>`）
- 在系统提示中明确定义 JSON schema 和填充规则

### 2. 预填充助手消息（Prefilling）确保 JSON 输出

来源：Anthropic 官方教程 — 05_Formatting_Output_and_Speaking_for_Claude
- 在 assistant 消息中填入 `{` 引导 Claude 直接输出 JSON
- 使用 XML 标签包裹输出（`<game_config>...</game_config>`）便于提取
- 通过 stop_sequences 参数防止多余结尾文本

### 3. Few-shot 示例嵌入系统提示

来源：Anthropic 官方教程 — 07_Using_Examples_Few-Shot_Prompting
- 2-3 个示例足够，必须在系统提示中展示完整的 JSON 结构
- 示例精确展示期望的格式，包括 config 和 scenes 的完整结构

### 4. 验证失败后的重试策略

来源：Anthropic Cookbook — building_evals
- 代码式评分（validation gate）最快最可靠
- 重试提示应将原始描述 + 验证错误消息一起反馈给 LLM
- 使用模型自身作为评估器（model-graded eval）是可靠的自动评分方法

### 5. 温度设置

来源：Anthropic Cookbook / OpenAI 官方文档
- 结构化数据生成（JSON 填充）：温度 0.0-0.3
- 叙事创作（场景内容）：温度 0.5-0.7
- 分阶段使用不同温度效果最佳
- Prefilling 技术比降低温度对格式可靠性的影响更大

### 6. 防止模板标记未填充

来源：Anthropic 官方教程 — 02_Being_Clear_and_Direct
- 明确指令："必须替换所有标记，不得残留任何 <!-- GEN: -->"
- 配合 validation gate 在重试提示中引用未替换的标记名称

### 7. 提取结构化输出

来源：Anthropic Cookbook — how_to_enable_json_mode
- 三种方法：字符串搜索、XML 标签包裹、Markdown 代码块提取
- 推荐使用 XML 标签包裹（`<cfg>...</cfg>` 和 `<scenes>...</scenes>`）
- 通过正则提取标签内容

## 对当前实现的建议

当前实现已采用核心模式（seed template + validation gate + retry loop），后续可按需：
1. 在系统提示中使用 XML 标签包裹用户描述
2. 添加 prefilling 引导 JSON 输出起手
3. 考虑分阶段温度：首次生成 0.3，重试 0.1