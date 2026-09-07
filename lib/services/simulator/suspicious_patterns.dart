/// 模拟器恶意模式粗筛常量单源（F-M5-07 导入 / F-M5-08a 生成共享）——
/// SUSPICIOUS_PATTERNS 三键集 + 中文文案映射。
///
/// 桌面权威源（只读，语义逐字锚点）：
/// - `desktop/backend/app/services/simulator_import.py` SUSPICIOUS_PATTERNS
///   （键 + 正则，常量单源——scan_suspicious 键集锚点）；
/// - `desktop/frontend/js/simulator-contracts.js` WARNING_LABELS（中文文案，
///   逐字三句）。
///
/// 定位（spec D13/Q13）：静态粗筛不承诺防住，命中仅收集返回；移动端比桌面
/// 「提示不拦截」更紧——命中即拒绝导入 + 展示清单 + 强制二次确认（Q14 已定），
/// 确认放行才落盘。
library;

/// 恶意模式粗筛键集 + 文案映射——单源常量，导入/生成共享。
///
/// [keys] 为三键清单（排序见 [scanSuspicious] 字典序产出）；[patternFor] /
/// [labelFor] 按键取正则与中文文案；未知键文案兜底原始键名（桌面未知键
/// 直出键名语义，防新增未联动不炸）。
abstract final class SuspiciousPatterns {
  /// 三键清单（常量单源；命中收集后排序确定）。
  static const List<String> keys = <String>[
    'cross-origin-fetch',
    'document.cookie',
    'eval',
  ];

  /// 键 → 正则（逐一对应桌面 SUSPICIOUS_PATTERNS）：
  /// - eval: `eval\s*\(`；
  /// - document.cookie: `document\s*\.\s*cookie`；
  /// - cross-origin-fetch: `fetch(…guoted…)` 内以 `https?://` 或 `//` 起头
  ///   （协议相对双斜杠）→ 跨源；同源相对路径 / data: 不命中。
  static final Map<String, RegExp> _patterns = <String, RegExp>{
    'eval': RegExp(r'eval\s*\('),
    'document.cookie': RegExp(r'document\s*\.\s*cookie'),
    'cross-origin-fetch':
        RegExp(r'''fetch\s*\(\s*["'`]\s*(?:https?://|//)'''),
  };

  /// 键 → 恶意模式正则（搜索语义同桌面）。
  static RegExp patternFor(String key) {
    final pattern = _patterns[key];
    if (pattern == null) {
      throw ArgumentError.value(key, 'key', '未知恶意模式键');
    }
    return pattern;
  }

  /// 键 → 面向用户的中文警告文案（锚桌面 WARNING_LABELS 逐字三句）；
  /// 未知键兜底返回原始键名。
  static String labelFor(String key) => switch (key) {
        'eval' => '使用 eval() 动态执行任意代码（同源可调用 API / 读取本地数据）',
        'document.cookie' => '读取 document.cookie（可访问本地会话数据）',
        'cross-origin-fetch' => '跨域 fetch 请求（可能向外部发送本地数据）',
        _ => key,
      };
}