/// 自包含注入 JS 常量串（F-M5-04）——单次 `runJavaScript` 注入即完成三元组
/// 填值 + 幂等写入 + 双事件派发 + 就绪轮询（≤5000ms 吸收引擎系动态面板渲染
/// 竞态，等价替代桌面 load 注入一次性竞态）。
///
/// 桌面权威源（只读，语义逐字锚点）：`desktop/frontend/js/key-injector.js`
/// `injectCredentialsIntoGame`（CONFIG_FIELDS 字段序 / FIELD_VALUE_KEYS 映射 /
/// TARGET_TAGS 白名单 / ensureSelectOption 受管 option / convertEndpoint 口径 /
/// 幂等「值已等不写不派发」/ input+change 双事件）。游戏零改动，契约全量保留。
///
/// 就绪轮询上限常量单一归属：[SimulatorContracts.scriptReadyPollMs]（桌面
/// 「就绪轮询 ≤5s」逐字）；本模块经 [InjectionScript.scriptReadyPollMs] 别名
/// 消费，不复制字面量。
///
/// 安全：注入的 openai key 必然进入游戏自身 DOM 与脚本内存（功能本义）；
/// claude key 恒不为空串（凭证层契约），故不可能出现在本脚本中。
library;

import 'dart:convert' show jsonEncode;

import 'injection.dart' as injection;
import 'simulator_contracts.dart' show SimulatorContracts;

/// 自包含注入 JS 常量串模板（金样断言的 marker 载体——桌面 key-injector.js
/// 逐字片段保持原样，不使用则删行禁止改写）。
///
/// 数据占位符（build 时替换，模板本身保持常量单一来源）：
/// - `__CONFIG_JSON__`：manifest config 三元组（F-91 候选 id 数组原样嵌入）；
/// - `__CREDENTIALS_JSON__`：凭证三元组（key/endpoint/model）；
/// - `__ENDPOINT_MODE__`：endpointMode 字面量（`"full"` / `"base"` / `null`）；
/// - `__READY_POLL_MS__`：就绪轮询上限（[InjectionScript.scriptReadyPollMs]）。
const String injectionScriptTemplate = """
(() => {
  const CONFIG_FIELDS = ['apikey', 'endpoint', 'model'];
  const FIELD_VALUE_KEYS = { apikey: 'key', endpoint: 'endpoint', model: 'model' };
  const TARGET_TAGS = new Set(['INPUT', 'SELECT']);
  const ENDPOINT_SUFFIX = '/chat/completions';
  const READY_POLL_MS = __READY_POLL_MS__;
  const POLL_INTERVAL_MS = 250;
  const config = __CONFIG_JSON__;
  const credentials = __CREDENTIALS_JSON__;
  const endpointMode = __ENDPOINT_MODE__;

  function configIdCandidates(id) {
    if (typeof id === 'string') return id === '' ? [] : [id];
    if (Array.isArray(id)) return id.filter((x) => typeof x === 'string' && x !== '');
    return [];
  }

  function convertEndpoint(endpoint, mode) {
    if (typeof endpoint !== 'string' || endpoint === '') return endpoint;
    const trimmed = endpoint.replace(/\\/+\$/, '');
    if (mode === 'full') {
      return trimmed.endsWith(ENDPOINT_SUFFIX) ? trimmed : trimmed + ENDPOINT_SUFFIX;
    }
    if (mode === 'base') {
      return trimmed.endsWith(ENDPOINT_SUFFIX) ? trimmed.slice(0, -ENDPOINT_SUFFIX.length) : trimmed;
    }
    return endpoint;
  }

  function hasSelectOption(selectEl, value) {
    for (const opt of selectEl.options) {
      if (opt.value === value) return true;
    }
    return false;
  }

  function ensureSelectOption(selectEl, value) {
    if (hasSelectOption(selectEl, value)) return false;
    const opt = selectEl.ownerDocument.createElement('option');
    opt.value = value;
    opt.textContent = value;
    selectEl.add(opt);
    return true;
  }

  function injectIntoGame(doc) {
    const filled = [];
    const skipped = [];
    const written = [];
    for (const field of CONFIG_FIELDS) {
      const candidates = configIdCandidates(config[field]);
      if (candidates.length === 0) { skipped.push(field); continue; }
      const rawValue = credentials[FIELD_VALUE_KEYS[field]];
      const value = field === 'endpoint' ? convertEndpoint(rawValue, endpointMode) : rawValue;
      if (typeof value !== 'string' || value === '') { skipped.push(field); continue; }
      let el = null;
      for (const id of candidates) {
        const found = doc.getElementById(id);
        if (found && TARGET_TAGS.has(found.tagName)) { el = found; break; }
      }
      if (!el) { skipped.push(field); continue; }
      const added = el.tagName === 'SELECT' ? ensureSelectOption(el, value) : false;
      // 幂等守卫：值已等不写不派发（重复注入不触发游戏 change 处理 — 写回环守卫）
      if (!added && el.value === value) { filled.push(field); continue; }
      el.value = value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      filled.push(field);
      written.push(field);
    }
    return { filled, skipped, written };
  }

  // 就绪轮询 ≤ READY_POLL_MS：目标控件动态渲染延迟吸收（引擎系动态面板）；
  // 任一字段填值即停，或达 attemptsMax（5000ms / 250ms）轮询上限为止。
  const attemptsMax = Math.max(1, Math.ceil(READY_POLL_MS / POLL_INTERVAL_MS));
  let attempt = 0;
  (function poll() {
    attempt++;
    const result = injectIntoGame(document);
    if (result.filled.length > 0 || attempt >= attemptsMax) return result;
    setTimeout(poll, POLL_INTERVAL_MS);
  })();
})();
""";

/// 自包含注入 JS 常量串的类型入口——[template] 承载桌面逐字 marker，[build]
/// 只做数据占位符替换（JSON 编码嵌入，无字符串拼接 / 无脚本注入面）。
class InjectionScript {
  /// 就绪轮询上限（毫秒）——单一来源 [SimulatorContracts.scriptReadyPollMs]
  /// （桌面「就绪轮询 ≤5s」逐字；测试断言金样 marker 与契约常量恒等）。
  static const int scriptReadyPollMs = SimulatorContracts.scriptReadyPollMs;

  /// 就绪轮询间隔（毫秒）；轮询次数 = [scriptReadyPollMs] / 本间隔向上取整，
  /// 由上限派生（改上限必联动改动次数，wheel 不分裂）。
  static const int pollIntervalMs = 250;

  /// 端点后缀（`/chat/completions`）——别名消费 [injection.dart] 顶部常量
  /// [injection.endpointSuffix]，单一来源不复制字面量。
  static const String endpointSuffix = injection.endpointSuffix;

  /// 构造最终注入脚本：替换模板数据占位符。
  ///
  /// [config] 须为完整三元组（[hasConfigTriplet]），否则抛 [ArgumentError]
  /// （编程错误守卫——三元组不完整时调用方应跳过注入而非构脚本）。
  /// [endpointMode] 为 manifest 条目值（`base` / `full` / null 不转换）。
  static String build({
    required Map<String, dynamic> config,
    required injection.InjectedCredentials credentials,
    required String? endpointMode,
  }) {
    if (!injection.hasConfigTriplet(config)) {
      throw ArgumentError.value(config, 'config', '注入脚本仅对完整 config 三元组构造');
    }
    final credentialsJson = jsonEncode(<String, String>{
      'key': credentials.key,
      'endpoint': credentials.endpoint,
      'model': credentials.model,
    });
    return injectionScriptTemplate
        .replaceAll('__CONFIG_JSON__', jsonEncode(config))
        .replaceAll('__CREDENTIALS_JSON__', credentialsJson)
        .replaceAll(
          '__ENDPOINT_MODE__',
          endpointMode == null ? 'null' : jsonEncode(endpointMode),
        )
        .replaceAll('__READY_POLL_MS__', '$scriptReadyPollMs');
  }
}