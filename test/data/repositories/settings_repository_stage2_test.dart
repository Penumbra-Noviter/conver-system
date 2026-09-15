/// PS2-02 设置仓储阶段 2 契约测试 — 两开关键（SR-09）白名单 + 布尔 getter。
///
/// 沿既有 settings_repository_test 装配（内存库 + InMemorySecretStore）。
/// 语义：存储值 'true' 才开启，缺失/空/其他一律 false（对齐
/// `memoryReflectionEnabled`）；白名单外键忽略的既有语义不回归。
/// 注意：不设 relationship 开关键（Grilling 共识校正，关系状态默认启用）。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/in_memory_secret_store.dart';

void main() {
  late AppDatabase db;
  late InMemorySecretStore secretStore;
  late SettingsRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secretStore = InMemorySecretStore();
    repository = SettingsRepository(database: db, secretStore: secretStore);
  });

  tearDown(() async {
    await db.close();
  });

  group('SR-09 白名单（阶段 2 两开关键）', () {
    test('allowedKeys 含两键常量（锚：proactiveMessageEnabledKey / innerThoughtEnabledKey）', () {
      expect(SettingsRepository.allowedKeys, contains(SettingsRepository.proactiveMessageEnabledKey));
      expect(SettingsRepository.allowedKeys, contains(SettingsRepository.innerThoughtEnabledKey));
      expect(SettingsRepository.proactiveMessageEnabledKey, 'proactive_message_enabled');
      expect(SettingsRepository.innerThoughtEnabledKey, 'inner_thought_enabled');
    });

    test('不设 relationship 开关键（Grilling 共识校正）', () {
      expect(SettingsRepository.allowedKeys, isNot(contains('relationship_state_enabled')));
      expect(SettingsRepository.allowedKeys, isNot(contains('relationship_enabled')));
    });

    test('两开关可经 setMany/getValue 往返（白名单内可写）', () async {
      await repository.setMany({
        SettingsRepository.proactiveMessageEnabledKey: 'true',
        SettingsRepository.innerThoughtEnabledKey: 'true',
      });
      expect(await repository.getValue(SettingsRepository.proactiveMessageEnabledKey), 'true');
      expect(await repository.getValue(SettingsRepository.innerThoughtEnabledKey), 'true');
    });

    test('白名单外键仍被忽略（既有语义不回归，含新增两键附近键名）', () async {
      await repository.setMany({
        'proactive_message_enabled_extra': 'true',
        'inner_thought': 'true',
        'evil_key': 'boom',
      });
      final rows = await db.select(db.settings).get();
      expect(rows, isEmpty);
      expect(await repository.getAll(), isEmpty);
    });
  });

  group('布尔 getter（缺省关闭，存储值 true 才开启）', () {
    test('proactiveMessageEnabled 缺省 false（无键 / 空串 / 其他值）', () async {
      expect(await repository.proactiveMessageEnabled, isFalse);

      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: ''});
      expect(await repository.proactiveMessageEnabled, isFalse);

      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: '1'});
      expect(await repository.proactiveMessageEnabled, isFalse);

      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: 'TRUE'});
      expect(await repository.proactiveMessageEnabled, isFalse);
    });

    test('proactiveMessageEnabled 存储值 true 即开启', () async {
      expect(await repository.proactiveMessageEnabled, isFalse);
      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: 'true'});
      expect(await repository.proactiveMessageEnabled, isTrue);

      // 关闭（写空串清态）→ 恢复缺省 false。
      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: ''});
      expect(await repository.proactiveMessageEnabled, isFalse);
    });

    test('innerThoughtEnabled 缺省 false 且 true 才开启', () async {
      expect(await repository.innerThoughtEnabled, isFalse);

      await repository.setMany({SettingsRepository.innerThoughtEnabledKey: 'yes'});
      expect(await repository.innerThoughtEnabled, isFalse);

      await repository.setMany({SettingsRepository.innerThoughtEnabledKey: 'true'});
      expect(await repository.innerThoughtEnabled, isTrue);
    });

    test('两开关互不干扰（各自键独立判定）', () async {
      await repository.setMany({SettingsRepository.proactiveMessageEnabledKey: 'true'});
      expect(await repository.proactiveMessageEnabled, isTrue);
      expect(await repository.innerThoughtEnabled, isFalse);
    });
  });
}