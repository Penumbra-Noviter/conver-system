import 'package:conver_system_mobile/models/model_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

// G4 contract lock — mirrors the desktop `tests/test_provider_registry.py`
// derivation invariants so the static catalog and its derived views cannot
// drift apart (or from the desktop source) in future edits.
void main() {
  const expectedOrder = <String>[
    'claude',
    'openai',
    'deepseek',
    'qwen',
    'kimi',
    'glm',
    'minimax',
    'step',
  ];

  group('G4 provider catalog data (desktop model_data.py AVAILABLE_MODELS)', () {
    test('provider keys follow the desktop declaration order', () {
      expect(ModelCatalog.providerKeys, expectedOrder);
      expect(ModelCatalog.providers.map((p) => p.key).toList(), expectedOrder);
    });

    test('catalog holds 60 models across 8 providers with desktop counts', () {
      const expectedCounts = <String, int>{
        'claude': 11,
        'openai': 22,
        'deepseek': 4,
        'qwen': 3,
        'kimi': 5,
        'glm': 6,
        'minimax': 5,
        'step': 4,
      };
      expect(ModelCatalog.providers.length, 8);
      expect(ModelCatalog.providerKeys, expectedOrder);
      for (final entry in expectedCounts.entries) {
        final provider = ModelCatalog.providers.firstWhere(
          (p) => p.key == entry.key,
        );
        expect(provider.models.length, entry.value,
            reason: '${entry.key} model count drifted');
      }
      final total = ModelCatalog.providers.fold<int>(
        0,
        (sum, p) => sum + p.models.length,
      );
      expect(total, 60);
    });

    test('desktop spot anchors live in their own provider', () {
      expect(ModelCatalog.providers[0].models, contains('claude-sonnet-5'));
      expect(ModelCatalog.providers[1].models, contains('gpt-5.6-sol'));
      expect(ModelCatalog.providers[6].models, contains('MiniMax-M3'));
      expect(ModelCatalog.providers[7].models, contains('step-2'));
    });

    test('every model belongs to exactly one provider (disjoint, unique)', () {
      final all = <String>{
        for (final p in ModelCatalog.providers) ...p.models,
      };
      expect(all.length, 60, reason: 'duplicate model id across providers');
      for (var i = 0; i < ModelCatalog.providers.length; i++) {
        for (var j = i + 1; j < ModelCatalog.providers.length; j++) {
          final overlap = ModelCatalog.providers[i].models
              .toSet()
              .intersection(ModelCatalog.providers[j].models.toSet());
          expect(overlap, isEmpty,
              reason:
                  '${ModelCatalog.providers[i].key} overlaps ${ModelCatalog.providers[j].key}');
        }
      }
    });

    test('protocol ids are restricted to the claude/openai domain', () {
      expect(
        ModelCatalog.providers.map((p) => p.id),
        everyElement(isIn(<String>['claude', 'openai'])),
      );
      expect(ModelCatalog.providers[0].id, 'claude');
      expect(ModelCatalog.providers[1].id, 'openai');
    });
  });

  group('G4 apiProviderMap (desktop API_PROVIDER_MAP)', () {
    test('equals the six known third-party entries exactly', () {
      expect(ModelCatalog.apiProviderMap, <String, String>{
        'deepseek': 'openai',
        'qwen': 'openai',
        'kimi': 'openai',
        'glm': 'openai',
        'minimax': 'openai',
        'step': 'openai',
      });
    });

    test('excludes providers whose protocol id equals their own key', () {
      expect(ModelCatalog.apiProviderMap.containsKey('claude'), isFalse);
      expect(ModelCatalog.apiProviderMap.containsKey('openai'), isFalse);
    });

    test('matches the desktop derivation rule (key != id) recomputed', () {
      final expected = <String, String>{
        for (final p in ModelCatalog.providers)
          if (p.id != p.key) p.key: p.id,
      };
      expect(ModelCatalog.apiProviderMap, expected);
    });

    test('map key order follows the declaration order', () {
      expect(ModelCatalog.apiProviderMap.keys.toList(), <String>[
        'deepseek',
        'qwen',
        'kimi',
        'glm',
        'minimax',
        'step',
      ]);
    });
  });

  group('G4 openaiProtocolModels (desktop OPENAI_PROTOCOL_MODELS)', () {
    test('equals the union over id==openai providers recomputed', () {
      final expected = <String>{
        for (final p in ModelCatalog.providers)
          if (p.id == 'openai') ...p.models,
      };
      expect(ModelCatalog.openaiProtocolModels, expected);
    });

    test('non-empty, over ten members, carries anchors, no claude models', () {
      expect(ModelCatalog.openaiProtocolModels, isNotEmpty);
      expect(ModelCatalog.openaiProtocolModels.length, greaterThan(10));
      expect(
        ModelCatalog.openaiProtocolModels,
        containsAll(<String>['deepseek-v4-flash', 'qwen-max', 'gpt-5.6-sol']),
      );
      expect(
        ModelCatalog.openaiProtocolModels.where((m) => m.startsWith('claude')),
        isEmpty,
      );
    });
  });

  group('G4 resolveApiProvider (desktop resolve_api_provider)', () {
    test('maps shared-protocol providers; claude/openai/unknown pass through',
        () {
      expect(ModelCatalog.resolveApiProvider('deepseek'), 'openai');
      expect(ModelCatalog.resolveApiProvider('claude'), 'claude');
      expect(ModelCatalog.resolveApiProvider('openai'), 'openai');
      expect(ModelCatalog.resolveApiProvider('unknown'), 'unknown');
    });
  });

  group('G4 derived-view fixation (desktop import-time consistency lock)', () {
    test('repeated reads return the same fixed instance (no lazy fork)', () {
      expect(identical(ModelCatalog.providerKeys, ModelCatalog.providerKeys),
          isTrue);
      expect(
          identical(ModelCatalog.apiProviderMap, ModelCatalog.apiProviderMap),
          isTrue);
      expect(
          identical(
              ModelCatalog.openaiProtocolModels, ModelCatalog.openaiProtocolModels),
          isTrue);
    });

    test('keys start at claude and end at step', () {
      expect(ModelCatalog.providerKeys.first, 'claude');
      expect(ModelCatalog.providerKeys.last, 'step');
    });
  });
}
