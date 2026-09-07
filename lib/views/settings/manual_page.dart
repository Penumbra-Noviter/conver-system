/// 用户手册长文页（F-M5-10）— 桌面 `index.html` #view-guide 13 节全改写为
/// 移动端视角。
///
/// 改写纪律（票面验收 2 + 共识 ⚑5/Q14）：
/// - 13 节标题逐节对应桌面蓝本；每节保留桌面语义；
/// - 删桌面专属项：Enter 快捷键（对话节）、关闭窗口/托盘行为（设置节）、
///   拖拽导入（模拟器节/导入节）、每游戏 per-game CSS 覆盖层文件（导入节）；
/// - 增移动端差异项：底部 5 tab 导航（快速开始节）、模拟器官方端点需桌面版
///   （模拟器节）、游戏目录位置 = 应用文档目录 simulators/（模拟器节）、
///   导入仅文件选择（模拟器节/导入节）；
/// - 「桌面版功能」节与「桌面版说明」页互文不冲突。
///
/// UI 形态：章节折叠（ExpansionTile 手风琴），静态文本组件，零新依赖，
/// 跑在既有 Warm Stone 暖灰 + 琥珀强调主题（design doc §5.1/§5.2）。
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/conver_palette.dart';

/// 手册章节数据模型：标题 + 有序内容块（段落 / 条目）。
class _ManualSection {
  const _ManualSection(this.title, this.blocks);

  /// 章节标题（逐节对应桌面 #view-guide）。
  final String title;

  /// 章节内容块（段落 / 条目，按书写顺序排列）。
  final List<_GuideBlock> blocks;
}

/// 手册内容块基类（段落 / 条目两种形态）。
sealed class _GuideBlock {
  const _GuideBlock();
}

/// 整段正文（[warning] 段落以危险色呈现，用于安全警告）。
class _GuideParagraph extends _GuideBlock {
  const _GuideParagraph(this.text, {this.warning = false});

  final String text;

  final bool warning;
}

/// 条目：加粗引导语 [lead] + 正文 [rest]（对齐桌面 `<strong>lead</strong>：rest`）。
class _GuideItem extends _GuideBlock {
  const _GuideItem(this.lead, this.rest);

  final String lead;

  final String rest;
}

/// 13 节手册内容（桌面 #view-guide 改写蓝本，静态常量）。
const _guideSections = <_ManualSection>[
  _ManualSection('快速开始', [
    _GuideParagraph(
      '汇流是一个本地优先的 AI 角色对话与模拟器应用：创建角色、开启对话、'
      '玩 AI 模拟器，所有数据保存在本机。整体流程：配置 AI 接口 → 创建角色 '
      '→ 开始聊天（或打开模拟器）。',
    ),
    _GuideParagraph('底部共 5 个标签：聊天 / 角色 / 搜索 / 模拟器 / 设置，下文沿这套导航说明。'),
    _GuideItem(
      '配置 AI 接口',
      '首次使用，先点底部「设置」标签，在「API 配置」区填入 Claude 或 '
      'OpenAI 兼容密钥（详细见「配置你的 AI 接口」）。尚未配置时，聊天页会'
      '显示「先配置 AI 接口」引导卡，点「前往设置」直达。',
    ),
    _GuideItem(
      '创建角色',
      '点底部「角色」标签的「创建角色」按钮，跟随 6 步引导向导创建（也可选'
      '内置模板，或用文档导入由 AI 自动解析）。',
    ),
    _GuideItem(
      '开始对话',
      '在角色卡片上点「对话」，系统自动创建新对话并立即显示角色开场白，输入'
      '文字发送即可。',
    ),
    _GuideItem(
      '玩模拟器',
      '点底部「模拟器」标签，选择一款内置 AI 游戏开始体验，或点「AI 生成」'
      '用世界观描述生成专属游戏（AI 游戏需先完成第 1 步配置，见「模拟器使用'
      '指南」）。',
    ),
  ]),
  _ManualSection('配置你的 AI 接口（新手必读）', [
    _GuideParagraph('所有 AI 功能（角色对话、AI 模拟器）共用同一套接口配置，只需配置一次，全局生效。'),
    _GuideItem(
      '准备密钥',
      '在模型服务商官网注册并创建密钥，任选一个服务即可：Anthropic Claude，'
      '或 OpenAI 兼容服务（OpenAI、DeepSeek、通义千问、Kimi、智谱 GLM 等）。',
    ),
    _GuideItem(
      '填入设置页',
      '进「设置」→「API 配置」区，把密钥填入 Claude 或 OpenAI 兼容任一栏。'
      '系统按所选模型的协议自动匹配，未匹配时使用另一栏——只填一栏就能用，'
      '两栏都填也行。',
    ),
    _GuideItem(
      '兼容服务地址（可选）',
      '使用官方服务时地址留空即可；第三方兼容服务在对应的 Base URL 填入地址'
      '（例如 DeepSeek 填 https://api.deepseek.com/v1）。',
    ),
    _GuideItem(
      '选择默认模型',
      '在「默认模型」区选择 Provider 和模型；列表里没有想要的，选「自定义'
      '模型」手动输入名称（如 deepseek-chat、qwen-plus）。',
    ),
    _GuideItem('保存', '点「保存 API 配置」。密钥仅存储于系统安全存储，不会上传。'),
    _GuideParagraph(
      '怎么判断配置成功：尚未配置时聊天页空态显示「先配置 AI 接口」引导卡；'
      '配置好后引导卡自动消失，给任意角色发一条消息即可验证。模拟器游戏则在'
      '运行页点「重新同步」让新配置生效。',
    ),
  ]),
  _ManualSection('角色管理', [
    _GuideParagraph('角色是对话的核心，每个角色拥有独立的人设、语气和知识设定。'),
    _GuideItem(
      '创建角色（引导向导）',
      '6 步引导完成：选择创建方式（文档导入 / 模板 / 手动）→ 导入文档或选模板'
      '→ 基本信息（姓名 / 头像 / 描述 / 标签）→ 人格设定 → 对话风格（开场白 '
      '/ 示例对话）→ 预览保存。带 * 的为必填项。',
    ),
    _GuideItem(
      '内置模板',
      '向导内置 5 个通用角色模板（知性学姐、神秘旅人等），选择后可直接使用，'
      '也可以在其基础上修改。',
    ),
    _GuideItem(
      '文档导入',
      '在向导第一步选「文档导入」，把角色设定文档、小说片段或简介粘贴进去，'
      '点解析，AI 会自动提取角色信息填入后续表单（此功能需已配置 AI 接口）。',
    ),
    _GuideItem('编辑角色', '点角色卡片上的「编辑」修改已有角色（使用简洁表单）。'),
    _GuideItem(
      '删除角色',
      '点角色卡片上的「删除」。如果有进行中的对话，系统会提示关联对话数量。',
    ),
    _GuideItem(
      '导入角色卡',
      '点「导入角色」，选择 SillyTavern V2 格式的角色卡 JSON 文件（兼容 V1 '
      '旧卡与裸 data 格式）。',
    ),
    _GuideItem(
      '导出角色卡',
      '点角色卡片上的「导出」，导出为 V2 格式的角色卡 JSON，方便备份或分享。',
    ),
  ]),
  _ManualSection('对话功能', [
    _GuideItem(
      '多会话标签页',
      '可以同时打开多个对话，聊天区顶部的标签条随时切换。每个标签独立记忆输入'
      '草稿、滚动位置和生成状态——切到别的对话后，原对话的 AI 回复会继续在后'
      '台生成。',
    ),
    _GuideItem(
      '发送消息',
      '在输入框输入文字，点右侧「发送」按钮发送；需要换行时点输入框的换行键。',
    ),
    _GuideItem(
      '流式输出',
      '默认开启，AI 回复会逐字显示（打字机效果）。可在输入框下方取消勾选'
      '「流式输出」切换为一次性输出。',
    ),
    _GuideItem(
      '停止生成',
      '流式输出时，「发送」按钮会切换为红色「停止生成」按钮，点按即可中断 AI '
      '回复，已生成的内容会保留。',
    ),
    _GuideItem(
      '复制消息',
      '点消息气泡上的复制图标即可复制该条消息内容。',
    ),
    _GuideItem(
      '对话标题',
      '创建对话时默认标题为「与 {角色名} 的对话」，角色开场白立即显示；发送'
      '首条消息后，标题自动替换为以该消息内容截断的版本（约 20 字）；你也可以'
      '点头部标题直接编辑。',
    ),
    _GuideItem(
      '切换模型',
      '聊天头部显示的模型徽标可直接点按，弹出模型选择器更换当前对话的 Provider '
      '与模型。切换只影响之后发送的消息，不影响历史记录；在途的流式回复也不会'
      '被打断。',
    ),
    _GuideItem(
      '重生成回复',
      '对最后一条 AI 回复不满意时，点该气泡上的「重生成」按钮即可让 AI 重新生成'
      '一条回复（顶替原回复）。重生成期间按钮会禁用并显示思考指示，不会重复触发。',
    ),
    _GuideItem('删除对话', '在对话列表中，点「删除」按钮即可删除。'),
    _GuideItem(
      '导出对话',
      '在聊天头部点「导出」按钮，可选择 JSON 或 Markdown 格式导出完整对话记录。',
    ),
  ]),
  _ManualSection('模拟器使用指南', [
    _GuideParagraph(
      '「模拟器」板块提供多款 AI 驱动的沉浸式游戏（人生模拟器、仙途、仿微、'
      '克苏鲁跑团、侦探模拟等），游戏在应用内部打开，存档保存在本机。',
    ),
    _GuideItem(
      '游戏列表',
      '进「模拟器」标签即显示全部游戏卡片，顶部可按「全部 / AI 驱动 / 纯本地」'
      '筛选。卡片右下角「AI 生成」徽标为通过 AI 生成功能创建的游戏；点顶部'
      'Sparkles 图标可打开生成对话框（详见「AI 生成游戏」）。',
    ),
    _GuideItem(
      '导入游戏',
      '点列表右上角「导入游戏」按钮，经文件选择器选取 .html 文件加入列表（仅'
      '支持本地 .html 文件，≤5MB，一次一个；移动端不支持拖拽导入）。内容与已有'
      '游戏相同的文件会自动识别并提示（SHA-256 去重）；文件名冲突时自动改名为 '
      'xxx-2.html 等递增后缀。',
    ),
    _GuideItem(
      'AI / 纯本地识别',
      '导入后系统自动判断游戏类型（AI 驱动需配置接口 / 纯本地无需配置）。若'
      'AI 驱动游戏被误判为「纯本地」，可点卡片上的「重新识别」按钮修正——系统'
      '会重新分析 HTML 中的配置控件并更新分类。',
    ),
    _GuideItem(
      '开始与退出游戏',
      '点任意卡片即可进入游戏；点左上角「返回」回到列表，进度不会丢失（存档'
      '自动保存，重进自动恢复）。',
    ),
    _GuideItem(
      'AI 游戏需要配置接口',
      'AI 驱动游戏会提示「此游戏需自行配置 AI 接口」。先在「设置」页配置好密钥'
      '（见「配置你的 AI 接口」），再回到游戏点「重新同步」，配置会自动写入游戏；'
      '也可以先配好设置再打开游戏，加载后会自动同步。',
    ),
    _GuideItem(
      '存档管理',
      '列表右上角「存档管理」按钮可查看每款游戏的存档情况（存档键数 / 总大小），'
      '并支持：导出（把某游戏的全部存档导出为 JSON 备份——注意导出文件可能包含'
      '游戏内配置数据，请妥善保管）；导入（把之前导出的 JSON 存档恢复，仅接受该'
      '游戏的合法存档键，其他内容会被拒绝）；删除（清除该游戏的全部存档，删除前'
      '需要确认，且不可恢复）。',
    ),
    _GuideItem(
      '存档位置',
      '存档保存在游戏页面的本地存储中，按游戏前缀隔离。清理应用数据会导致存档'
      '丢失，重要进度建议用「存档管理」导出备份。',
    ),
    _GuideItem(
      '游戏目录位置',
      '内置与导入的游戏文件存放在应用文档目录下的 simulators/ 文件夹（移动端'
      '以应用文档目录为数据目录）。',
    ),
    _GuideItem(
      '特别说明',
      '小马宝莉、高中生模拟器两款游戏的存档仅会话内生效，重进需要重新注入；'
      '个别游戏没有存档管理功能，属正常现象。',
    ),
    _GuideItem(
      '官方端点限制（移动端差异）',
      'Anthropic / OpenAI 官方端点不支持游戏直连（浏览器 CORS 限制），游戏将'
      '无法使用官方端点运行；请改用 DeepSeek / Kimi / GLM / Qwen 等国产兼容'
      '端点，或改用桌面版运行（见「桌面版说明」）。',
    ),
  ]),
  _ManualSection('AI 生成游戏', [
    _GuideParagraph(
      '输入世界观描述，AI 自动生成完整的 HTML 模拟器游戏。生成的游戏与其他'
      '模拟器游戏一样运行，支持存档与 AI 配置同步。',
    ),
    _GuideItem(
      '进入方式',
      '在模拟器列表页，点顶部「AI 生成」按钮（Sparkles 图标）打开生成对话框。',
    ),
    _GuideItem(
      '编写世界观',
      '在对话框中填写「世界观设定」（必填），描述你的世界背景、氛围、核心冲突'
      '等。越详细，生成的游戏越丰富。可选填「游戏名称」。',
    ),
    _GuideItem(
      '生成流程',
      '点「生成游戏」后，AI 会根据你的描述填充种子模板，生成完整的 HTML 游戏'
      '文件，并通过六项校验闸门（结构完整性 / 模板标记 / 配置契约 / HTML 可'
      '解析性 / 安全性 / 游戏数据完整性）。校验失败时自动重试打磨（最多 3 次），'
      '并显示具体错误和建议。',
    ),
    _GuideItem(
      '生成完成',
      '成功生成的游戏会出现在模拟器列表中，卡片右下角标注「AI 生成」徽标。与'
      '导入的游戏一样，打开后自动注入配置并支持存档与同步。',
    ),
    _GuideItem(
      '需先配置 AI 接口',
      '游戏生成功能依赖 AI 推理，需要先在「设置」页配置好密钥（见「配置你的 '
      'AI 接口」）。',
    ),
    _GuideItem(
      '生成限制',
      '世界观描述最多 10000 字符；上传文件最大 10MB；生成请求超时 2 分钟。',
    ),
  ]),
  _ManualSection('导入游戏与安全须知', [
    _GuideParagraph(
      '安全警告：第三方游戏可读取本地数据并调用接口。导入的游戏与内置游戏同处'
      '本地同源区域运行，可读取本应用本地数据（含你配置的接口凭证）并调用本'
      '应用接口——请仅导入你信任的文件。导入前程序会弹出同样的警告并需要你确认。',
      warning: true,
    ),
    _GuideItem(
      '恶意模式扫描',
      '导入时程序会扫描明显恶意模式——eval 动态执行、读取 cookie、跨域请求等，'
      '命中会弹出「安全警告」提示，移动端会拒绝导入并列出命中关键词清单；如需'
      '强行导入须二次确认（静态审查不承诺防住一切，仅作知情提示）。',
    ),
    _GuideItem(
      '重复导入',
      '内容与已有游戏相同的文件（SHA-256 校验）会被识别并提示已存在，不会重复'
      '导入。',
    ),
    _GuideItem(
      '自动改名',
      '文件名与已有游戏冲突时自动改名为 xxx-2.html 等递增后缀，导入成功后提示'
      '新文件名。',
    ),
    _GuideItem(
      '导入方式（移动端差异）',
      '仅支持文件选择器选单个 .html 文件，不支持桌面端的拖拽导入。',
    ),
  ]),
  _ManualSection('搜索消息', [
    _GuideParagraph(
      '在「搜索」标签输入关键词，系统会跨所有对话搜索匹配消息。搜索结果会显示'
      '消息内容预览、角色归属和对话名称；点结果可跳转到对应对话，并自动定位到'
      '命中那条消息且短暂高亮（约 3 秒后自动消失），方便你立刻查看上下文。',
    ),
  ]),
  _ManualSection('设置说明', [
    _GuideItem(
      'API 配置',
      'Claude 与 OpenAI 兼容两栏，填任一栏即全局生效（系统按所选模型的协议'
      '自动匹配，未匹配时使用另一栏）。第三方服务需同时填写对应「兼容地址」。',
    ),
    _GuideItem(
      '默认模型',
      '选择默认的 Provider 和模型；列表底部可选「自定义模型」手动输入名称。',
    ),
    _GuideItem(
      '上下文轮数',
      '控制 AI 能记住的对话轮数（默认 30 轮，可调范围 5–100）。轮数越多，AI '
      '对上下文的记忆越好，但消耗也越大。',
    ),
    _GuideItem(
      '模板变量',
      '在角色设定中使用 {{user}}（自动替换为用户昵称）和 {{char}}（自动替换'
      '为角色名），让角色设定更生动自然。',
    ),
    _GuideItem('主题模式', '支持跟随系统、浅色、深色三种选择。'),
    _GuideItem(
      '清空所有对话（危险操作）',
      '将删除所有对话和消息记录，此操作不可撤销，请谨慎使用。',
    ),
  ]),
  _ManualSection('桌面版功能（Tauri）', [
    _GuideParagraph(
      '汇流提供基于 Tauri 的 Windows 桌面应用，功能与移动端一致，并额外提供'
      '以下特性。若你需要在移动端无法覆盖的场景（如官方端点游戏直连）运行，'
      '见设置页「桌面版说明」。',
    ),
    _GuideItem(
      '随包运行',
      '桌面版内置后端，启动时自动拉起服务，关闭时自动清理，无需手动维护服务'
      '进程或额外窗口。',
    ),
    _GuideItem(
      '关闭窗口行为',
      '首次运行会询问关闭主窗口时的行为——「最小化到托盘（后台继续运行）」或'
      '「直接退出」。选择最小化后，可从系统托盘图标恢复或退出程序。',
    ),
    _GuideItem(
      '系统托盘',
      '最小化到托盘后，应用在后台继续运行（对话中的 AI 回复不受影响），右键'
      '托盘图标可选「显示窗口」或「退出」。',
    ),
    _GuideItem(
      '数据目录',
      '所有数据（角色、对话、模拟器游戏、manifest）保存在本机数据目录。',
    ),
    _GuideItem(
      '安装器',
      'Windows 安装包支持自定义安装路径与开始菜单快捷方式；「卸载」可从系统'
      '程序列表执行。',
    ),
  ]),
  _ManualSection('支持的模型', [
    _GuideParagraph('系统通过统一的 Provider 抽象层支持多种模型服务，当前已内置：'),
    _GuideItem('Claude（Anthropic）', 'Claude Sonnet 5、Claude Opus 4.8 等'),
    _GuideItem('OpenAI', 'GPT-4o、GPT-5 系列等'),
    _GuideItem('DeepSeek', 'deepseek-v4-flash、deepseek-v4-pro 等'),
    _GuideItem(
      '国产模型',
      '通义千问（Qwen）、Kimi（Moonshot）、智谱（GLM）、MiniMax、阶跃星辰'
      '（Step）等',
    ),
    _GuideParagraph(
      '所有兼容 OpenAI 接口的服务均可通过在设置页填入对应兼容地址使用；列表里'
      '没有的模型可选「自定义模型」手动输入。',
    ),
  ]),
  _ManualSection('常见问题', [
    _GuideItem(
      'AI 不回复或报错？',
      '先到「设置」确认密钥已保存且格式正确；模拟器游戏请在运行页点「重新同步」'
      '让配置生效。使用第三方服务时，还需确认兼容地址与模型名称填写正确。',
    ),
    _GuideItem(
      '模拟器提示「游戏加载失败」？',
      '通常是页面加载超时（15 秒）或参数异常，点「重试」即可；游戏文件就在'
      '本机，不会丢失。',
    ),
    _GuideItem(
      '游戏存档会丢吗？',
      '正常使用不会丢（保存在游戏页面本地存储）。清理应用数据或更换设备前，'
      '建议先用「存档管理」导出备份。',
    ),
    _GuideItem(
      '数据安全吗？',
      '角色、对话、密钥全部保存在本机，只有聊天内容会发送给你自己配置的模型'
      '服务商。',
    ),
  ]),
  _ManualSection('小贴士', [
    _GuideItem(
      '人格设定',
      '角色的人格设定越详细，AI 的角色扮演效果越好。建议包含：性格特征、说话'
      '风格、背景故事、知识范围。',
    ),
    _GuideItem(
      '开场白',
      '开场白是角色与用户的第一句话，好的开场白能立刻建立角色氛围。',
    ),
    _GuideItem(
      '模板变量',
      '使用 {{user}} 和 {{char}} 模板变量时，确保已在设置中填写了用户昵称。',
    ),
    _GuideItem(
      '多会话',
      '聊天标签页支持多会话同时打开，切换标签后原对话的 AI 回复继续在后台生成，'
      '切换回来时内容已自动更新。',
    ),
    _GuideItem(
      '生成 AI 游戏',
      '世界观描述越具体（氛围、时代、核心冲突、角色关系），生成的游戏越丰富'
      '有趣。同一描述可以多次生成，每次结果不同。',
    ),
    _GuideItem(
      '官方端点受限',
      '若官方端点游戏直连受限，可改用国产兼容端点或桌面版运行（见「桌面版'
      '说明」）。',
    ),
  ]),
];

/// 用户手册页 — 13 节折叠手风琴（ExpansionTile）。
class ManualPage extends StatelessWidget {
  const ManualPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户手册')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: ConverSpacing.space2),
          children: [
            for (final section in _guideSections)
              _GuideSectionTile(section: section),
          ],
        ),
      ),
    );
  }
}

/// 单章节折叠项：折叠态只显示标题，展开显示内容块列表。
class _GuideSectionTile extends StatelessWidget {
  const _GuideSectionTile({required this.section});

  final _ManualSection section;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(
        horizontal: ConverSpacing.space4,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(
        ConverSpacing.space4,
        0,
        ConverSpacing.space4,
        ConverSpacing.space3,
      ),
      // 去 M3 默认圆角边框，仅保留 1px 暖白分割（design doc §5.2 克制圆角）。
      shape: const Border(),
      collapsedShape: const Border(),
      backgroundColor: Colors.transparent,
      collapsedBackgroundColor: Colors.transparent,
      iconColor: accent,
      collapsedIconColor: palette.ink4,
      title: Text(
        section.title,
        style: textTheme.bodyLarge?.copyWith(
          color: palette.ink1,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        for (final block in section.blocks)
          switch (block) {
            _GuideParagraph() => _paragraph(context, block),
            _GuideItem() => _item(context, block),
          },
      ],
    );
  }

  /// 段落块：正文 / 警告（危险色）。
  Widget _paragraph(BuildContext context, _GuideParagraph paragraph) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    final color = paragraph.warning
        ? Theme.of(context).colorScheme.error
        : palette.ink3;
    return Padding(
      padding: const EdgeInsets.only(bottom: ConverSpacing.space3),
      child: Text(
        paragraph.text,
        style: textTheme.bodyMedium?.copyWith(color: color, height: 1.5),
      ),
    );
  }

  /// 条目块：加粗引导语 + 正文，前置圆点缩进。
  Widget _item(BuildContext context, _GuideItem item) {
    final textTheme = Theme.of(context).textTheme;
    final palette = ConverPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ConverSpacing.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              right: ConverSpacing.space2,
              top: 2,
            ),
            child: Text(
              '·',
              style: textTheme.bodyMedium?.copyWith(color: palette.ink4),
            ),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${item.lead}：',
                    style: textTheme.bodyMedium?.copyWith(
                      color: palette.ink1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: item.rest,
                    style: textTheme.bodyMedium?.copyWith(color: palette.ink2),
                  ),
                ],
              ),
              style: const TextStyle(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
