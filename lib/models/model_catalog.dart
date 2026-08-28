import 'dart:collection' show UnmodifiableSetView;

// Model catalog — static single source of available providers and models.
//
// Verbatim transcription of the desktop authoritative source
// `desktop/backend/app/services/model_data.py` (`AVAILABLE_MODELS`: 8
// providers, 60 models), with derived read-only views mirroring
// `desktop/backend/app/services/provider_registry.py` (`PROVIDER_KEYS`,
// `API_PROVIDER_MAP`, `OPENAI_PROTOCOL_MODELS`, `resolve_api_provider`).
//
// Pure Dart constants and set algebra: no IO, no network requests. The
// credential resolution chain (ticket 04) and the model picker (ticket 06)
// both consume this single source. Anti-drift contract lock:
// `test/models/model_catalog_test.dart` mirrors the desktop
// `tests/test_provider_registry.py` derivation invariants.
//
// Protocol semantics (desktop TD-66): third-party providers share one of the
// two protocols (claude / openai). `apiProviderMap` only records providers
// whose protocol id differs from their own key (claude / openai resolve to
// themselves via the `resolveApiProvider` fallback);
// `openaiProtocolModels` is the union of models over every provider whose
// protocol id equals "openai" (including openai itself).
//
// The desktop registry raises an explicit ValueError at import time when a
// provider entry is missing `key` or `id`; in Dart that malformed-data class
// is structurally impossible — both are required non-nullable constructor
// parameters of [ModelProvider].

/// Immutable catalog entry for one provider.
///
/// `key` is the registration name, `id` is the API protocol family
/// (`claude` or `openai`), `name` is the display name, and `models` lists
/// model ids in the desktop declaration order.
class ModelProvider {
  /// Creates a const provider entry; all fields are required.
  const ModelProvider({
    required this.key,
    required this.id,
    required this.name,
    required this.models,
  });

  /// Provider registration key (unique across the catalog).
  final String key;

  /// API protocol family id: `claude` or `openai`.
  final String id;

  /// Human-readable display name (verbatim from the desktop source).
  final String name;

  /// Model ids offered by this provider, in declaration order.
  final List<String> models;
}

/// Static single source for providers/models and its derived read-only views.
///
/// Derived views are computed once from the deeply-const [providers] data on
/// first access and are exposed unmodifiable, so repeated reads always return
/// the same fixed instance (no lazy-loading fork between views and source —
/// the Dart analogue of the desktop import-time derivation).
abstract final class ModelCatalog {
  /// All providers in the desktop declaration order (claude, openai,
  /// deepseek, qwen, kimi, glm, minimax, step) with their models verbatim
  /// from `model_data.py` `AVAILABLE_MODELS`.
  static const List<ModelProvider> providers = [
    ModelProvider(
      key: 'claude',
      id: 'claude',
      name: 'Claude (Anthropic)',
      models: [
        'claude-sonnet-5',
        'claude-fable-5',
        'claude-mythos-5',
        'claude-opus-4-8',
        'claude-opus-4-7',
        'claude-mythos-preview',
        'claude-opus-4-6',
        'claude-sonnet-4-6',
        'claude-haiku-4-5',
        'claude-opus-4-5',
        'claude-sonnet-4-5',
      ],
    ),
    ModelProvider(
      key: 'openai',
      id: 'openai',
      name: 'OpenAI',
      models: [
        'gpt-5.6-sol',
        'gpt-5.6-terra',
        'gpt-5.6-luna',
        'gpt-5.4',
        'gpt-5.4-mini',
        'gpt-5.4-nano',
        'gpt-5.2',
        'gpt-5.2-pro',
        'gpt-5.1',
        'gpt-5.1-mini',
        'gpt-5.1-codex',
        'gpt-5',
        'gpt-5-mini',
        'gpt-5-nano',
        'gpt-4.1',
        'gpt-4.1-mini',
        'gpt-4.1-nano',
        'o4-mini',
        'o3',
        'o3-mini',
        'gpt-4o',
        'gpt-4o-mini',
      ],
    ),
    ModelProvider(
      key: 'deepseek',
      id: 'openai',
      name: 'DeepSeek',
      models: [
        'deepseek-v4-flash',
        'deepseek-v4-pro',
        'deepseek-chat',
        'deepseek-reasoner',
      ],
    ),
    ModelProvider(
      key: 'qwen',
      id: 'openai',
      name: '通义千问 (Qwen)',
      models: ['qwen-max', 'qwen-plus', 'qwen-turbo'],
    ),
    ModelProvider(
      key: 'kimi',
      id: 'openai',
      name: '月之暗面 (Kimi)',
      models: [
        'kimi-k3',
        'kimi-k2.5',
        'kimi-k2',
        'kimi-k2-lite',
        'kimi-k2-thinking-turbo',
      ],
    ),
    ModelProvider(
      key: 'glm',
      id: 'openai',
      name: '智谱 (GLM / Zhipu)',
      models: [
        'glm-4-plus',
        'glm-4',
        'glm-4v',
        'glm-4-flash',
        'glm-4-air',
        'glm-3-turbo',
      ],
    ),
    ModelProvider(
      key: 'minimax',
      id: 'openai',
      name: 'MiniMax',
      models: [
        'MiniMax-M3',
        'MiniMax-M2.7',
        'MiniMax-M2.5',
        'MiniMax-M2.1',
        'MiniMax-M2',
      ],
    ),
    ModelProvider(
      key: 'step',
      id: 'openai',
      name: '阶跃星辰 (Step)',
      models: ['step-2', 'step-2v', 'step-1', 'step-1v'],
    ),
  ];

  /// Provider keys in declaration order (desktop `PROVIDER_KEYS`).
  ///
  /// Registration-order contract: entries keep the [providers] sequence.
  static final List<String> providerKeys = List.unmodifiable(
    providers.map((p) => p.key),
  );

  /// Provider key to API protocol id mapping, restricted to protocol
  /// sharing providers where `key != id` (desktop `API_PROVIDER_MAP`).
  ///
  /// Note: the key set of this map is not a data source for
  /// [openaiProtocolModels] — openai itself is not in the map.
  static final Map<String, String> apiProviderMap = Map.unmodifiable(<String, String>{
    for (final p in providers)
      if (p.id != p.key) p.key: p.id,
  });

  /// Union of models over every provider whose protocol id is `openai`
  /// (desktop `OPENAI_PROTOCOL_MODELS`, a frozenset there).
  static final Set<String> openaiProtocolModels = UnmodifiableSetView(<String>{
    for (final p in providers)
      if (p.id == 'openai') ...p.models,
  });

  /// Resolves a provider key to the same-protocol credential slot
  /// (`claude` / `openai`); mirrors desktop `resolve_api_provider`.
  ///
  /// Returns the protocol id from [apiProviderMap] when present, otherwise
  /// the input itself (claude / openai and unknown keys pass through, so
  /// they act directly as credential slot names).
  static String resolveApiProvider(String provider) =>
      apiProviderMap[provider] ?? provider;
}
