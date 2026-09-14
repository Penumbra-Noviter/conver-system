/// OnboardingService 纯逻辑契约（工单 05 / spec §U-4）。
///
/// seam 边界：只测 [OnboardingService.isCompleted] / [OnboardingService.markCompleted]
/// 两个公开接口经真实 [SettingsRepository]（内存 drift）的可观察行为，不测内部实现。
/// 语义锚点：读 `onboarding_completed` 键（缺失/空回退「未完成」）；写该键。
library;

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/data/repositories/settings_repository.dart';
import 'package:conver_system_mobile/services/onboarding.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_secret_store.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late OnboardingService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(
      database: db,
      secretStore: InMemorySecretStore(),
    );
    service = OnboardingService(settings: settings);
  });

  tearDown(() async {
    await db.close();
  });

  test('缺失标记 → isCompleted false（首启展示指引）', () async {
    expect(await service.isCompleted(), isFalse);
  });

  test('markCompleted 写键后 isCompleted true（读回一致）', () async {
    await service.markCompleted();
    expect(await service.isCompleted(), isTrue);
    expect(await settings.getValue(OnboardingService.completedKey), isNotEmpty);
  });

  test('空串值行视同未完成（与缺失同判）', () async {
    await settings.setMany({OnboardingService.completedKey: ''});
    expect(await service.isCompleted(), isFalse);
  });

  test('markCompleted 幂等：重复写不改变结果且仍为完成', () async {
    await service.markCompleted();
    await service.markCompleted();
    expect(await service.isCompleted(), isTrue);
  });
}
