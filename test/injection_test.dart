/// F-M5-04 注入纯函数 + 凭证组装 + 官方端点检测 — 对拍桌面 key-injector /
/// setting.py credentials() 契约矩阵。
///
/// 语义逐字锚点（只读）：`desktop/frontend/js/key-injector.js`（resolveButtonState /
/// hasConfigTriplet / convertEndpoint 纯函数契约）+ `desktop/backend/app/services/
/// setting.py`（credentials()：key 只取 openai 协议槽位、claude key 恒空串、
/// model 门控）+ 共识 Q8 官方域检测边界。
///
/// 安全纪律：本测试只用 fake key 占位（`sk-test-xxx`），永不携带真实密钥值。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:conver_system_mobile/services/simulator/injection.dart';
import 'package:conver_system_mobile/services/simulator/injection_script.dart';
import 'package:conver_system_mobile/services/simulator/simulator_contracts.dart';
import 'package:conver_system_mobile/services/secure_store.dart';

import 'helpers/in_memory_secret_store.dart';

/// 便捷构造凭证（fake key 占位）。
InjectedCredentials _creds({
  String protocol = 'openai',
  String key = '',
  String endpoint = 'https://api.deepseek.com/v1',
  String model = '',
}) {
  return InjectedCredentials(
    protocol: protocol,
    key: key,
    endpoint: endpoint,
    model: model,
  );
}

/// 便捷构造注入设置面（缺省 = deepseek + openai 协议链，模型已配置）。
CredentialSettings _settings({
  String defaultProvider = 'deepseek',
  String defaultModel = 'deepseek-v4-flash',
  String configuredModel = 'deepseek-v4-flash',
  String baseUrl = 'https://api.deepseek.com/v1',
}) {
  return CredentialSettings(
    defaultProvider: defaultProvider,
    defaultModel: defaultModel,
    configuredModel: configuredModel,
    baseUrl: baseUrl,
  );
}

void main() {
  group('resolveButtonState · 三态 + 防御分支', () {
    test('openai + 非空 key → {enabled:true, reason:null}', () {
      final state = resolveButtonState(_creds(key: 'sk-test-1'));
      expect(state.enabled, isTrue);
      expect(state.reason, isNull);
    });

    test('openai + 空 key（防御）→ {enabled:false, reason:"none"}', () {
      final state = resolveButtonState(_creds(protocol: 'openai', key: ''));
      expect(state.enabled, isFalse);
      expect(state.reason, 'none');
    });

    test('claude → {enabled:false, reason:"claude"}', () {
      final state = resolveButtonState(_creds(protocol: 'claude'));
      expect(state.enabled, isFalse);
      expect(state.reason, 'claude');
    });

    test('none → {enabled:false, reason:"none"}', () {
      final state = resolveButtonState(_creds(protocol: 'none'));
      expect(state.enabled, isFalse);
      expect(state.reason, 'none');
    });

    test('未知 protocol（防御）→ reason "none" 不崩', () {
      final state = resolveButtonState(_creds(protocol: 'weird'));
      expect(state.enabled, isFalse);
      expect(state.reason, 'none');
    });

    test('null 输入（防御）→ reason "none" 不崩', () {
      final state = resolveButtonState(null);
      expect(state.enabled, isFalse);
      expect(state.reason, 'none');
    });
  });

  group('hasConfigTriplet · 三元组完整性（F-91 多候选）', () {
    test('三个字段各含 ≥1 非空候选 → true', () {
      expect(
        hasConfigTriplet(const {
          'endpoint': 'cfg-endpoint',
          'apikey': 'cfg-apikey',
          'model': 'cfg-model',
        }),
        isTrue,
      );
      // 数组多候选（任一命中即完整）。
      expect(
        hasConfigTriplet(const {
          'endpoint': ['wz-endpoint', 's-endpoint'],
          'apikey': 's-key',
          'model': 's-model',
        }),
        isTrue,
      );
    });

    test('任一字段缺失 / 空串 / 空数组 → false', () {
      expect(
        hasConfigTriplet(const {'endpoint': 'e', 'apikey': 'a'}),
        isFalse,
        reason: '缺 model',
      );
      expect(
        hasConfigTriplet(const {
          'endpoint': 'e',
          'apikey': '',
          'model': 'm',
        }),
        isFalse,
        reason: 'apikey 空串',
      );
      expect(
        hasConfigTriplet(const {
          'endpoint': <String>[],
          'apikey': 'a',
          'model': 'm',
        }),
        isFalse,
        reason: 'endpoint 空数组',
      );
    });

    test('null / 非对象（防御）→ false', () {
      expect(hasConfigTriplet(null), isFalse);
    });
  });

  group('convertEndpoint · endpointMode 口径转换', () {
    const suffix = '/chat/completions';

    test('full：base URL 追加 /chat/completions', () {
      expect(convertEndpoint('https://api.deepseek.com/v1', 'full'),
          'https://api.deepseek.com/v1$suffix');
    });

    test('full：尾斜杠先归一再追加', () {
      expect(convertEndpoint('https://api.deepseek.com/v1/', 'full'),
          'https://api.deepseek.com/v1$suffix');
    });

    test('full：已含后缀不重复追加', () {
      expect(convertEndpoint('https://api.deepseek.com/v1$suffix', 'full'),
          'https://api.deepseek.com/v1$suffix');
    });

    test('base：剥除 /chat/completions 后缀', () {
      expect(convertEndpoint('https://api.deepseek.com/v1$suffix', 'base'),
          'https://api.deepseek.com/v1');
    });

    test('base：已是 base 形态保持原样（尾斜杠归一）', () {
      expect(convertEndpoint('https://api.deepseek.com/v1/', 'base'),
          'https://api.deepseek.com/v1');
    });

    test('其余 mode / null mode → 原样返回（兼容旧数据）', () {
      expect(convertEndpoint('https://api.deepseek.com/v1', null),
          'https://api.deepseek.com/v1');
      expect(convertEndpoint('https://api.deepseek.com/v1', 'weird'),
          'https://api.deepseek.com/v1');
    });

    test('空串 / null endpoint → 原样返回', () {
      expect(convertEndpoint('', 'full'), '');
      expect(convertEndpoint(null, 'full'), isNull);
    });
  });

  group('toProxyEndpoint · 同源反代改写行为矩阵（方案 A 桌面逐字）', () {
    const origin = 'http://127.0.0.1:8642';
    const prefix = '/proxy';

    test('合法 base URL → origin + /proxy + 路径段保留', () {
      expect(toProxyEndpoint('https://api.deepseek.com/v1', origin),
          '$origin$prefix/v1');
    });

    test('尾斜杠剥离：https://host/v1/ → .../proxy/v1', () {
      expect(toProxyEndpoint('https://api.deepseek.com/v1/', origin),
          '$origin$prefix/v1');
    });

    test('深层路径段保留（/v1/chat/completions 形态）', () {
      expect(
        toProxyEndpoint('https://api.deepseek.com/v1/chat/completions', origin),
        '$origin$prefix/v1/chat/completions',
      );
    });

    test('空串 → 原样（不误改）', () {
      expect(toProxyEndpoint('', origin), '');
    });

    test('null（非字符串语义）→ 原样', () {
      expect(toProxyEndpoint(null, origin), isNull);
    });

    test('空 origin → 原样（非浏览器 / 未注入 origin → 不误改）', () {
      expect(toProxyEndpoint('https://api.deepseek.com/v1', ''),
          'https://api.deepseek.com/v1');
    });

    test('非法 URL（无 scheme 裸串，new URL 抛错分支）→ 无路径形态', () {
      expect(toProxyEndpoint('api.deepseek.com/v1', origin), '$origin$prefix');
    });

    test('不可解析串 → 无路径形态（origin + /proxy）', () {
      expect(toProxyEndpoint('not a url', origin), '$origin$prefix');
    });

    test('无路径 base URL（https://host 与 https://host/）→ 无路径形态', () {
      expect(toProxyEndpoint('https://api.deepseek.com', origin),
          '$origin$prefix');
      expect(toProxyEndpoint('https://api.deepseek.com/', origin),
          '$origin$prefix');
    });
  });

  group('assembleCredentials · 凭证组装（claude key 恒不进游戏）', () {
    test('openai 槽位 key + deepseek 设置 → openai 三元组（model 门控放行）', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-888');
      final creds = await assembleCredentials(store, _settings());
      expect(creds.protocol, 'openai');
      expect(creds.key, 'sk-test-888');
      expect(creds.endpoint, 'https://api.deepseek.com/v1');
      expect(creds.model, 'deepseek-v4-flash');
    });

    test('仅 claude key → protocol claude，key/endpoint/model 恒空（不得进游戏）',
        () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'sk-ant-fake-claude');
      final creds = await assembleCredentials(store, _settings());
      expect(creds.protocol, 'claude');
      expect(creds.key, '', reason: 'claude key 绝不进入游戏');
      expect(creds.endpoint, '');
      expect(creds.model, '');
    });

    test('双槽位同存 → openai 优先，key 只取 openai 槽位值', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-555');
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'sk-ant-fake-999');
      final creds = await assembleCredentials(store, _settings());
      expect(creds.protocol, 'openai');
      expect(creds.key, 'sk-test-555');
      expect(creds.key, isNot('sk-ant-fake-999'));
    });

    test('无任何 key → protocol none，全空串', () async {
      final creds = await assembleCredentials(InMemorySecretStore(), _settings());
      expect(creds.protocol, 'none');
      expect(creds.key, '');
      expect(creds.endpoint, '');
      expect(creds.model, '');
    });

    test('model 门控：默认 provider 非 openai 协议 → model 恒空', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-1');
      // provider=claude（即使配了 openai key）→ resolveApiProvider('claude') != openai。
      final creds = await assembleCredentials(store, _settings(defaultProvider: 'claude'));
      expect(creds.protocol, 'openai', reason: 'openai key 存在即 openai 协议');
      expect(creds.key, 'sk-test-1');
      expect(creds.model, '', reason: 'claude provider 模型名不得混入 openai 三元组');
    });

    test('model 门控：未显式配置且解析模型不在 openai 模型集 → model 恒空', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-1');
      // configuredModel='' 且 defaultModel 兜底为 claude 模型名。
      final creds = await assembleCredentials(
        store,
        _settings(defaultModel: 'claude-sonnet-5', configuredModel: ''),
      );
      expect(creds.protocol, 'openai');
      expect(creds.key, 'sk-test-1');
      expect(creds.model, '');
    });

    test('model 门控：未配置但解析模型 ∈ openai 模型集 → 放行', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-1');
      final creds = await assembleCredentials(
        store,
        _settings(defaultModel: 'deepseek-v4-flash', configuredModel: ''),
      );
      expect(creds.model, 'deepseek-v4-flash');
    });

    test('model 门控：显式配置任意模型名 → 放行（用户意图不误伤）', () async {
      final store = InMemorySecretStore();
      await store.write(key: SecretStore.openaiApiKeySlot, value: 'sk-test-1');
      final creds = await assembleCredentials(
        store,
        _settings(defaultModel: 'custom-model', configuredModel: 'custom-model'),
      );
      expect(creds.model, 'custom-model');
    });
  });

  group('isOfficialEndpoint · 官方域检测矩阵（Q8 边界）', () {
    test('provider=claude → 恒 true（无论 base url）', () {
      expect(isOfficialEndpoint('claude', ''), isTrue);
      expect(isOfficialEndpoint('claude', 'https://api.deepseek.com/v1'), isTrue);
    });

    test('国产兼容端点（含端口/路径）→ false（放行）', () {
      expect(isOfficialEndpoint('deepseek', 'https://api.deepseek.com/v1'), isFalse);
      expect(isOfficialEndpoint('kimi', 'https://api.moonshot.cn/v1'), isFalse);
      expect(isOfficialEndpoint('glm', 'https://open.bigmodel.cn/api/paas/v4'), isFalse);
      expect(isOfficialEndpoint('local', 'http://127.0.0.1:8642'), isFalse);
    });

    test('官方域命中 → true（拦截）', () {
      expect(isOfficialEndpoint('openai', 'https://api.anthropic.com'), isTrue);
      expect(isOfficialEndpoint('deepseek', 'https://api.anthropic.com'), isTrue);
      expect(isOfficialEndpoint('openai', 'https://api.openai.com/v1'), isTrue);
      expect(isOfficialEndpoint('deepseek', 'https://api.openai.com'), isTrue);
    });

    test('子域边界：x.anthropic.com / platform.openai.com → true', () {
      expect(isOfficialEndpoint('openai', 'https://x.anthropic.com'), isTrue);
      expect(isOfficialEndpoint('openai', 'https://platform.openai.com'), isTrue);
    });

    test('结尾匹配不误伤：openai.com.evil.com / evilopenai.com → false', () {
      expect(isOfficialEndpoint('openai', 'https://openai.com.evil.com'), isFalse);
      expect(isOfficialEndpoint('openai', 'https://evilopenai.com'), isFalse);
    });

    test('大小写 / http 协议 / 端口：语义一致命中官方域', () {
      expect(isOfficialEndpoint('openai', 'HTTPS://API.ANTHROPIC.COM/V1'), isTrue);
      expect(isOfficialEndpoint('openai', 'http://api.anthropic.com'), isTrue);
      expect(isOfficialEndpoint('openai', 'https://api.openai.com:8443/v1'), isTrue);
    });

    test('null / 空串 base url → false（非官方判定，不误拦）', () {
      expect(isOfficialEndpoint('deepseek', ''), isFalse);
      expect(isOfficialEndpoint('openai', ''), isFalse);
    });

    test('无 scheme 裸串（非 URL）→ false', () {
      expect(isOfficialEndpoint('openai', 'api.anthropic.com'), isFalse);
    });
  });

  group('InjectionScript · 自包含 JS 常量串金样断言（U1 三件套-常量单源）', () {
    // 样本：fake key 占位（安全：永不携带真实密钥值）。config 含 F-91 数组多候选。
    const sampleConfig = <String, dynamic>{
      'endpoint': <String>['wz-endpoint', 's-endpoint'],
      'apikey': 'cfg-apikey',
      'model': 'cfg-model',
    };
    const sampleCreds = InjectedCredentials(
      protocol: 'openai',
      key: 'sk-test-123',
      endpoint: 'https://api.deepseek.com/v1',
      model: 'deepseek-v4-flash',
    );

    String buildSample({String? endpointMode = 'full'}) => InjectionScript.build(
          config: sampleConfig,
          credentials: sampleCreds,
          endpointMode: endpointMode,
        );

    test('CONFIG_FIELDS 字段顺序逐字（apikey → endpoint → model）', () {
      final script = buildSample();
      expect(script, contains("const CONFIG_FIELDS = ['apikey', 'endpoint', 'model'];"));
      final apikey = script.indexOf("'apikey'");
      final endpoint = script.indexOf("'endpoint'");
      final model = script.indexOf("'model'");
      expect(apikey, lessThan(endpoint));
      expect(endpoint, lessThan(model));
      // 字段→凭证取值映射（apikey ← key；endpoint/model 同名）。
      expect(script, contains("FIELD_VALUE_KEYS"));
      expect(script, contains("apikey: 'key'"));
    });

    test('TARGET_TAGS 白名单限定 INPUT/SELECT', () {
      final script = buildSample();
      expect(script, contains("new Set(['INPUT', 'SELECT'])"));
      expect(script, contains("TARGET_TAGS"));
    });

    test('input + change 双事件派发（写入后依次派发，各游戏监听不一）', () {
      final script = buildSample();
      final writePoint = script.indexOf('el.value = value');
      final inputPoint = script.indexOf("new Event('input', { bubbles: true })");
      final changePoint = script.indexOf("new Event('change', { bubbles: true })");
      expect(writePoint, isNot(-1));
      expect(inputPoint, greaterThan(writePoint), reason: '写入后先派发 input');
      expect(changePoint, greaterThan(inputPoint), reason: '再派发 change');
    });

    test('幂等守卫：值已等不写不派发（el.value === value + 守卫注释）', () {
      final script = buildSample();
      expect(script, contains('el.value === value'));
      expect(script, contains('幂等守卫'));
      expect(script, contains('不写不派发'));
    });

    test('就绪轮询 ≤5000ms（scriptReadyPollMs 单源 + 派生 attemptsMax）', () {
      final script = buildSample();
      // 常量单一来源：契约常量 = 5000 = JS 内字面量。
      expect(SimulatorContracts.scriptReadyPollMs, 5000);
      expect(InjectionScript.scriptReadyPollMs, SimulatorContracts.scriptReadyPollMs);
      expect(script, contains('const READY_POLL_MS = 5000;'));
      expect(script, contains('Math.ceil(READY_POLL_MS / POLL_INTERVAL_MS)'));
    });

    test('endpointMode 口径：ENDPOINT_SUFFIX 逐字 + 尾斜杠归一', () {
      final script = buildSample();
      expect(script, contains("'/chat/completions'"));
      expect(script, contains('endpoint.replace(/\\/+\$/, \'\')'));
      expect(InjectionScript.endpointSuffix, endpointSuffix);
    });

    test('proxyPrefix 单源契约：SimulatorContracts.proxyPrefix == "/proxy"', () {
      expect(SimulatorContracts.proxyPrefix, '/proxy');
    });

    test('PROXY_PREFIX 占位符替换：build 产物 JS 字面量与契约常量恒等', () {
      final script = buildSample();
      expect(script, contains('const PROXY_PREFIX = "/proxy";'));
    });

    test('toProxyEndpoint 桌面逐字金样：函数签名 + 核心分支逐字', () {
      final script = buildSample();
      // 桌面 key-injector.js L289-300 逐字（移动端无 export，函数体逐字）。
      expect(script, contains('function toProxyEndpoint(endpoint, origin) {'));
      expect(
        script,
        contains(
          "if (typeof endpoint !== 'string' || endpoint === '') return endpoint;",
        ),
      );
      expect(
        script,
        contains(
          "const o = origin || (typeof location !== 'undefined' ? location.origin : '');",
        ),
      );
      expect(script, contains('if (!o) return endpoint;'));
      expect(script, contains('new URL(endpoint).pathname.replace(/\\/+\$/, \'\')'));
      expect(script, contains('return `\${o}\${PROXY_PREFIX}\${path}`;'));
    });

    test('endpoint 取值调用序：convertEndpoint(toProxyEndpoint(rawValue), endpointMode)', () {
      final script = buildSample();
      // 桌面 L391-392：先同源改写再口径转换（CORS 修复）。
      expect(
        script,
        contains(
          'convertEndpoint(toProxyEndpoint(rawValue), endpointMode)',
        ),
      );
      // 旧调用序（直接 convertEndpoint(rawValue, ...)）不得残留。
      expect(
        script,
        isNot(contains('convertEndpoint(rawValue, endpointMode)')),
      );
    });

    test('config 三元组嵌入（F-91 候选原样进字符串，无省略）', () {
      final script = buildSample();
      expect(script, contains('"wz-endpoint"'));
      expect(script, contains('"s-endpoint"'));
      expect(script, contains('"cfg-apikey"'));
      expect(script, contains('"cfg-model"'));
    });

    test('凭证三元组嵌入（fake key 占位进脚本——本义：key 供游戏调用端点）', () {
      final script = buildSample();
      expect(script, contains('sk-test-123'));
      expect(script, contains('https://api.deepseek.com/v1'));
      expect(script, contains('deepseek-v4-flash'));
    });

    test('endpointMode=null → 嵌入 null（不转换分支，兼容旧数据）', () {
      final script = buildSample(endpointMode: null);
      expect(script, contains('endpointMode = null'));
    });

    test('三元组不完整 config → 抛 ArgumentError（编程错误守卫）', () {
      expect(
        () => InjectionScript.build(
          config: const {'endpoint': 'e'},
          credentials: sampleCreds,
          endpointMode: 'full',
        ),
        throwsArgumentError,
      );
    });

    group('F-36 · 占位符碰撞熔断（payload 恰含占位符字面量）', () {
      test(
          'config id 含全部占位符字面量 → 原样嵌入不被后续替换吞掉'
          '（注入面不静默跳过）', () {
        final script = InjectionScript.build(
          config: const <String, dynamic>{
            'endpoint': '__CREDENTIALS_JSON__',
            'apikey': '__CONFIG_JSON__',
            'model': '__READY_POLL_MS__',
          },
          credentials: sampleCreds,
          endpointMode: 'full',
        );

        // 模板四处占位符整体替换精确发生（config / credentials / endpointMode / 轮询）。
        expect(
          script,
          contains('const config = {"endpoint":"__CREDENTIALS_JSON__"'),
          reason: 'config 值中的占位符字面量是 id 数据本身，必须原样嵌入',
        );
        expect(
          script,
          contains('"apikey":"__CONFIG_JSON__","model":"__READY_POLL_MS__"}'),
        );
        expect(script, contains('const credentials = {"key":"sk-test-123"'));
        expect(script, contains('const endpointMode = "full";'));
        expect(script, contains('const READY_POLL_MS = 5000;'));

        // 熔断正断言：credentials JSON 没有被拼进 config 的位置。
        expect(
          script,
          isNot(contains('"endpoint":{"key":"sk-test-123"')),
          reason: 'F-36：config 值含 __CREDENTIALS_JSON__ 时不得被后续替换覆写'
              '（否则 config[endpoint] 变对象 → configIdCandidates 空 → 字段'
              '静默跳过，注入面缺失）',
        );
      });

      test('credentials 值含占位符字面量 → 凭证 JSON 原样嵌入不被吞', () {
        final script = InjectionScript.build(
          config: sampleConfig,
          credentials: const InjectedCredentials(
            protocol: 'openai',
            key: '__CONFIG_JSON__',
            endpoint: '__CREDENTIALS_JSON__',
            model: '__READY_POLL_MS__',
          ),
          endpointMode: 'full',
        );

        expect(
          script,
          contains('const config = {"endpoint":["wz-endpoint","s-endpoint"]'),
          reason: 'config 侧占位不受凭证侧字面量干扰',
        );
        expect(
          script,
          contains(
            'const credentials = {"key":"__CONFIG_JSON__",'
            '"endpoint":"__CREDENTIALS_JSON__","model":"__READY_POLL_MS__"};',
          ),
        );
        expect(script, contains('const READY_POLL_MS = 5000;'));
      });
    });
  });
}