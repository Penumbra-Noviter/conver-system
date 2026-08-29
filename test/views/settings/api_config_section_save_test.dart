// T1 — API 配置保存事务化（快照 + 失败回滚）验收测试（工单 T1 / spec §T1）。
//
// 核心语义契约（spec §T1 + T1.md 验收）：
// - 写前快照四键现值（claude_api_key / openai_api_key 两槽位 +
//   claude_base_url / openai_base_url）；逐 provider 写/删（claude → openai），
//   任一失败即停止后续写入
// - 失败后已写项回滚为保存前值：旧非空 write 回旧值；旧空则 Key 槽位 delete、
//   base_url 写回空串（读回语义等价未配置）
// - 回滚自身失败仅 debugPrint，不重抛、不吞成功路径
// - 文案逐字：「API 配置已保存」/「保存失败，请重试」
//
// 注入 seam（与装配链一致，均经构造参数）：SecretStore 经 [ApiConfigSection.secretStore]
// 注入可编排失败 fake；base_url 经 [ApiConfigSection.settingsRepository] 注入
// 可抛错仓储子类。本文件不修改 settings_sections_widget_test.dart（T3 独占）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/secure_store.dart';
import 'package:conver_system_mobile/theme/conver_theme.dart';
import 'package:conver_system_mobile/views/settings/api_config_section.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

/// 可编排失败的内存 SecretStore fake——命中键的 write 可按剩余次数抛错。
///
/// 语义：[failOnKeys] 含该键时，write 抛 [StateError]；[failWritesRemaining]
/// > 0 表示「再失败 N 次后放行」（用于重试幂等），-1（默认）= 命中键总是失败。
/// read/delete/containsKey 透传 delegate（默认 [InMemorySecretStore]）。
class _FailOnWriteSecretStore implements SecretStore {
  _FailOnWriteSecretStore({
    required this.failOnKeys,
    this.failWritesRemaining = -1,
    SecretStore? delegate,
  }) : _delegate = delegate ?? InMemorySecretStore();

  final Set<String> failOnKeys;

  /// 剩余失败次数；-1 = 命中键总是失败，N >= 0 = 再失败 N 次后放行。
  int failWritesRemaining;

  final SecretStore _delegate;

  @override
  Future<void> write({required String key, required String value}) async {
    if (failOnKeys.contains(key)) {
      if (failWritesRemaining != 0) {
        if (failWritesRemaining > 0) {
          failWritesRemaining--;
        }
        throw StateError('write failed: $key');
      }
    }
    await _delegate.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _delegate.delete(key);

  @override
  Future<String> read(String key) => _delegate.read(key);

  @override
  Future<bool> containsKey(String key) => _delegate.containsKey(key);
}

/// 保存按钮是否可点（_saving 复位 = onPressed 非空）。
bool _saveButtonEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, '保存 API 配置'),
  );
  return button.onPressed != null;
}

/// 命中键的 write 在值等于 [failOnValue] 时抛错的 fake——用于让「回滚写回旧值」
/// 失败（正向写入新值放行，回滚写旧值抛错），验证回滚失败仅 debugPrint 不重抛。
///
/// 预置旧值应直写 [delegate]（不经本 fake，避免预置值与 [failOnValue] 相同
/// 时误抛）；本 fake 只拦截经 _save 回滚通道写回的旧值。
class _FailOnOldValueSecretStore implements SecretStore {
  _FailOnOldValueSecretStore({required this.failOnValue, SecretStore? delegate})
    : _delegate = delegate ?? InMemorySecretStore();

  final String failOnValue;
  final SecretStore _delegate;

  @override
  Future<void> write({required String key, required String value}) async {
    if (value == failOnValue) {
      throw StateError('rollback write failed: $key=$value');
    }
    await _delegate.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) => _delegate.delete(key);

  @override
  Future<String> read(String key) => _delegate.read(key);

  @override
  Future<bool> containsKey(String key) => _delegate.containsKey(key);
}

/// setMany 对指定 base_url 键必抛的 [SettingsRepository] 子类——命中
/// 「Key 写成功、base_url 落设置表失败」路径，验证已写 Key 项回滚、
/// base_url 未写入（written 不含该键）故无需回滚。
class _FailOnBaseUrlSettingsRepository extends SettingsRepository {
  _FailOnBaseUrlSettingsRepository({
    required super.database,
    required this.failKey,
  });

  final String failKey;

  @override
  Future<void> setMany(Map<String, String> data) async {
    if (data.containsKey(failKey)) {
      throw StateError('setMany failed: $failKey');
    }
    await super.setMany(data);
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SettingsRepository(database: db, secretStore: InMemorySecretStore());
  });

  tearDown(() async {
    await db.close();
  });

  /// 包一层 MaterialApp + Scaffold，使 SnackBar（ScaffoldMessenger）可呈现；
  /// 主题用 [ConverTheme.dark]（真实应用由 ConverApp 装配同一主题注册）。
  Future<void> pumpSection(WidgetTester tester, Widget section) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ConverTheme.dark(),
        home: Scaffold(body: section),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('api_config 保存事务化（快照 + 失败回滚）', () {
    testWidgets(
      'openai 槽位写失败 → claude key/base_url 回滚为保存前旧值 + 失败 SnackBar + 按钮复位',
      (tester) async {
        final store = _FailOnWriteSecretStore(
          failOnKeys: {SecretStore.openaiApiKeySlot},
        );
        // 预置 claude 槽位旧值（保存前状态）。
        await store.write(key: SecretStore.claudeApiKeySlot, value: 'old-key');
        await repo.setMany({'claude_base_url': 'old-base'});

        await pumpSection(
          tester,
          ApiConfigSection(
            settingsRepository: repo,
            secretStore: store,
            initialValues: const {
              'claude_api_key': 'new-key',
              'claude_base_url': 'new-base',
              'openai_api_key': 'new-openai-key',
              'openai_base_url': 'new-openai-base',
            },
          ),
        );

        await tester.tap(find.text('保存 API 配置'));
        await tester.pump();
        await tester.pumpAndSettle();

        // 失败 SnackBar（文案逐字）。
        expect(find.text('保存失败，请重试'), findsOneWidget);

        // claude 槽位已写值被回滚为保存前旧值（而非残留新值）。
        expect(
          await store.read(SecretStore.claudeApiKeySlot),
          'old-key',
          reason: '回滚锚：claude key 应读回保存前旧值，而非残留新值 new-key',
        );
        expect(
          await repo.getValue('claude_base_url'),
          'old-base',
          reason: '回滚锚：claude base_url 应读回保存前旧值，而非残留新值 new-base',
        );

        // openai 槽位写失败即停止，不再写后续键（openai base_url 未触达）。
        expect(
          await store.read(SecretStore.openaiApiKeySlot),
          '',
          reason: 'openai key 写失败，槽位保持保存前（空）',
        );
        expect(
          await repo.getValue('openai_base_url'),
          '',
          reason: 'openai base_url 未写（第二槽位失败即停止后续写入）',
        );

        // _saving 必然复位：失败后按钮 onPressed 恢复非空。
        expect(
          _saveButtonEnabled(tester),
          isTrue,
          reason: '_saving 在失败路径也必须复位（按钮恢复可用）',
        );
      },
    );

    testWidgets(
      'claude 旧值全空：openai 写失败 → claude key delete + base_url 写回空串（读回等价未配置）',
      (tester) async {
        final store = _FailOnWriteSecretStore(
          failOnKeys: {SecretStore.openaiApiKeySlot},
        );
        // claude 槽位旧值全空（未配置），openai 槽位同样未配置。
        await pumpSection(
          tester,
          ApiConfigSection(
            settingsRepository: repo,
            secretStore: store,
            initialValues: const {
              'claude_api_key': 'new-key',
              'claude_base_url': 'new-base',
              'openai_api_key': 'new-openai-key',
              'openai_base_url': 'new-openai-base',
            },
          ),
        );

        await tester.tap(find.text('保存 API 配置'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('保存失败，请重试'), findsOneWidget);

        // 旧值为空 → claude key 槽位 delete（回滚锚：读回空串且槽位不存在）。
        expect(
          await store.read(SecretStore.claudeApiKeySlot),
          '',
          reason: '旧空 Key 槽位回滚为 delete，读回空串而非残留 new-key',
        );
        expect(
          await store.containsKey(SecretStore.claudeApiKeySlot),
          isFalse,
          reason: '旧空 Key 槽位回滚为 delete，槽位应不存在',
        );
        // 旧值为空 → base_url 写回空串（读回语义等价未配置）。
        expect(
          await repo.getValue('claude_base_url'),
          '',
          reason: '旧空 base_url 回滚写回空串，读回空串而非残留 new-base',
        );
      },
    );

    testWidgets('第一槽位（claude）即失败 → 无已写项无需回滚，仍报失败 SnackBar + 按钮复位', (
      tester,
    ) async {
      final store = _FailOnWriteSecretStore(
        failOnKeys: {SecretStore.claudeApiKeySlot},
      );
      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: store,
          initialValues: const {
            'claude_api_key': 'new-key',
            'claude_base_url': 'new-base',
            'openai_api_key': 'new-openai-key',
            'openai_base_url': 'new-openai-base',
          },
        ),
      );

      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请重试'), findsOneWidget);
      // 第一槽位写失败即停止：claude 未写成功，openai 两键从未触达。
      expect(
        await store.read(SecretStore.claudeApiKeySlot),
        '',
        reason: 'claude key 写失败即停止，槽位保持保存前（空）',
      );
      expect(await repo.getValue('claude_base_url'), '');
      expect(
        await store.read(SecretStore.openaiApiKeySlot),
        '',
        reason: 'openai key 未被写（第一槽位失败即停止）',
      );
      expect(await repo.getValue('openai_base_url'), '');
      // 无已写项无需回滚，仍复位按钮。
      expect(_saveButtonEnabled(tester), isTrue);
    });

    testWidgets('重试幂等：首次失败回滚后，再次保存成功全部生效 + 「API 配置已保存」逐字', (tester) async {
      // openai 槽位只失败一次，之后放行——模拟「失败后重试成功」。
      final store = _FailOnWriteSecretStore(
        failOnKeys: {SecretStore.openaiApiKeySlot},
        failWritesRemaining: 1,
      );
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'old-key');
      await repo.setMany({'claude_base_url': 'old-base'});

      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: store,
          initialValues: const {
            'claude_api_key': 'new-key',
            'claude_base_url': 'new-base',
            'openai_api_key': 'new-openai-key',
            'openai_base_url': 'new-openai-base',
          },
        ),
      );

      // 第一次保存：openai 失败 → 回滚 claude，快照重新读取无残留半写。
      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(
        await store.read(SecretStore.claudeApiKeySlot),
        'old-key',
        reason: '首次失败后 claude 回滚为旧值，无残留半写',
      );

      // 第二次保存：全部成功，文案逐字「API 配置已保存」。
      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('API 配置已保存'), findsOneWidget);
      expect(await store.read(SecretStore.claudeApiKeySlot), 'new-key');
      expect(await store.read(SecretStore.openaiApiKeySlot), 'new-openai-key');
      expect(await repo.getValue('claude_base_url'), 'new-base');
      expect(await repo.getValue('openai_base_url'), 'new-openai-base');
      expect(_saveButtonEnabled(tester), isTrue);
    });

    testWidgets('回滚自身失败仅 debugPrint，不重抛、不吞失败 SnackBar（claude 旧值写回抛错）', (
      tester,
    ) async {
      // claude key 旧值 'old-key'：正向写 'new-key' 放行，回滚写回 'old-key' 抛错。
      final backing = InMemorySecretStore();
      await backing.write(key: SecretStore.claudeApiKeySlot, value: 'old-key');
      await repo.setMany({'claude_base_url': 'old-base'});
      final store = _FailOnOldValueSecretStore(
        failOnValue: 'old-key',
        delegate: backing,
      );

      // openai 槽位写失败触发回滚（claude 已写项需回滚写回旧值）。
      final failingStore = _FailOnWriteSecretStore(
        failOnKeys: {SecretStore.openaiApiKeySlot},
        delegate: store,
      );

      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: repo,
          secretStore: failingStore,
          initialValues: const {
            'claude_api_key': 'new-key',
            'claude_base_url': 'new-base',
            'openai_api_key': 'new-openai-key',
          },
        ),
      );

      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();

      // 回滚失败仅 debugPrint（文案自定），不重抛（未造成测试异常）、
      // 不吞失败路径——仍报「保存失败，请重试」且按钮复位。
      expect(find.text('保存失败，请重试'), findsOneWidget);
      expect(
        _saveButtonEnabled(tester),
        isTrue,
        reason: '回滚自身失败后 _saving 仍复位，按钮恢复可用',
      );
      // 回滚失败项不阻断后续：base_url 回滚（未抛错）应已写回旧值。
      expect(await repo.getValue('claude_base_url'), 'old-base');
    });

    testWidgets('base_url 落设置表失败（Key 已写）→ 已写 Key 项回滚为旧值、base_url 未写无需回滚', (
      tester,
    ) async {
      final store = _FailOnWriteSecretStore(failOnKeys: const {});
      await store.write(key: SecretStore.claudeApiKeySlot, value: 'old-key');
      final failingRepo = _FailOnBaseUrlSettingsRepository(
        database: db,
        failKey: 'claude_base_url',
      );

      await pumpSection(
        tester,
        ApiConfigSection(
          settingsRepository: failingRepo,
          secretStore: store,
          initialValues: const {
            'claude_api_key': 'new-key',
            'claude_base_url': 'new-base',
            'openai_api_key': 'new-openai-key',
            'openai_base_url': 'new-openai-base',
          },
        ),
      );

      await tester.tap(find.text('保存 API 配置'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('保存失败，请重试'), findsOneWidget);
      // claude key 已写 'new-key'，随后 base_url setMany 抛错 → key 回滚为旧值。
      expect(
        await store.read(SecretStore.claudeApiKeySlot),
        'old-key',
        reason: 'base_url 失败后已写 claude key 回滚为保存前旧值',
      );
      // base_url 写入失败（written 不含该键），未写成功无需回滚；
      // openai 两键因「base_url 失败即停止」从未触达。
      expect(await store.read(SecretStore.openaiApiKeySlot), '');
      expect(await failingRepo.getValue('openai_base_url'), '');
      expect(_saveButtonEnabled(tester), isTrue);
    });
  });
}
