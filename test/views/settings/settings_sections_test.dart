// 纯逻辑单测（工单 06 A7）：模型选择「清单项 vs 自定义输入」归一规则。
// widget 层只做编排，不设为门（spec 测试口径）。
import 'package:conver_system_mobile/views/settings/default_model_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveModelToSave（清单项 vs 自定义输入归一）', () {
    test('自定义输入非空 → 原样采用（trim）', () {
      expect(
        resolveModelToSave(
          customInput: '  my-custom-model  ',
          catalogSelection: 'claude-sonnet-5',
          fallbackModel: 'old-model',
        ),
        'my-custom-model',
      );
    });

    test('自定义输入为纯空白 → 视作空，落清单选择', () {
      expect(
        resolveModelToSave(
          customInput: '   ',
          catalogSelection: 'claude-sonnet-5',
          fallbackModel: 'old-model',
        ),
        'claude-sonnet-5',
      );
    });

    test('自定义空 + 清单选择非空 → 采用清单项', () {
      expect(
        resolveModelToSave(
          customInput: '',
          catalogSelection: 'deepseek-chat',
          fallbackModel: 'old-model',
        ),
        'deepseek-chat',
      );
    });

    test('两者皆空 → 回退当前持久化值（防"没动就保存"清配置）', () {
      expect(
        resolveModelToSave(
          customInput: '',
          catalogSelection: '',
          fallbackModel: 'claude-sonnet-5',
        ),
        'claude-sonnet-5',
      );
    });
  });

  group('resetModelOnProviderSwitch（切 provider 重置）', () {
    test('清单非空 → 选中首个模型', () {
      expect(
        resetModelOnProviderSwitch(['m-a', 'm-b', 'm-c']),
        'm-a',
      );
    });

    test('空清单 → null（清空选择，自定义输入接管）', () {
      expect(resetModelOnProviderSwitch([]), isNull);
    });
  });
}
