/// MemoryManagementController — 角色记忆管理页的状态机（AC-05）。
///
/// 职责：加载指定角色的记忆条目与人设演化版本；记忆条目增/改/删经
/// [MemoryRepository] 后重载；人设演化提出 / 应用 / 拒绝经
/// [PersonaEvolutionService]（确认闸门，ADR-0003）后重载，并维护
/// 「已应用版本」判定（快照 == 当前人格，Q7 启发式）。纯编排，不触碰
/// 具体 UI 与平台存储。
///
/// 层级：ChangeNotifier 视图模型，依赖 [MemoryRepository]（数据层）+
/// [PersonaEvolutionService]（演化 seam）+ [CharacterRepository]（当前人格
/// 读取，参与 Q7 判定）。
library;

import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart'
    show MemoryEntry, PersonaRevision;
import '../../data/database/tables.dart' show MemoryKind;
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/memory_repository.dart';
import '../../services/memory/persona_evolution_service.dart';

/// 角色记忆管理控制器。
class MemoryManagementController extends ChangeNotifier {
  /// [memoryRepository] 记忆数据源；[characterId] 目标角色；
  /// [evolutionService] 人设演化服务（提出/应用/拒绝）；[characterRepository]
  /// 角色仓储（load 时读当前人格参与已应用版本判定）。
  MemoryManagementController({
    required this._memoryRepository,
    required this._characterId,
    required this._evolutionService,
    required this._characterRepository,
  });

  final MemoryRepository _memoryRepository;
  final int _characterId;
  final PersonaEvolutionService _evolutionService;
  final CharacterRepository _characterRepository;

  bool _loading = false;
  List<MemoryEntry> _entries = const [];
  List<PersonaRevision> _revisions = const [];
  Set<int> _appliedRevisionIds = const {};
  bool _proposing = false;
  String? _snackMessage;
  String? _notice;

  /// 加载中（首次加载 spinner）。
  bool get loading => _loading;

  /// 记忆条目列表（importance 降序、createdAt 倒序，仓储契约）。
  List<MemoryEntry> get entries => _entries;

  /// 人设演化版本列表（createdAt 倒序，仓储契约）。
  List<PersonaRevision> get revisions => _revisions;

  /// 已应用版本 id 集合（Q7 启发式：快照 == 当前人格 ⇔ 已应用只读）。
  Set<int> get appliedRevisionIds => _appliedRevisionIds;

  /// 演化提出进行中（AppBar action loading + 防重复触发）。
  bool get proposing => _proposing;

  /// 一次性 SnackBar 消息（propose 成功/无变化、apply 成功）；view 经
  /// [consumeSnackMessage] 取后消费。
  String? get snackMessage => _snackMessage;

  /// 非阻塞提示（加载失败、演化异常等）；null 无。
  String? get notice => _notice;

  /// 拉取记忆条目与人设演化版本（首次进入 / 增改删后刷新）。
  ///
  /// 失败 → [notice] 且保留既有列表。
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _entries = await _memoryRepository.listEntries(_characterId);
      _revisions = await _memoryRepository.listRevisions(_characterId);
      final character = await _characterRepository.getCharacter(_characterId);
      final currentPersonality = character?.personality;
      _appliedRevisionIds = {
        for (final r in _revisions)
          if (r.personalitySnapshot == currentPersonality) r.id,
      };
      _notice = null;
    } catch (e) {
      _notice = '加载记忆失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 手动新增一条记忆条目（[kind] 类型 + [content] 正文）。
  Future<void> createEntry(MemoryKind kind, String content) async {
    await _memoryRepository.createEntry(
      characterId: _characterId,
      kind: kind,
      content: content,
    );
    await load();
  }

  /// 更新记忆条目（[content] / [importance] 部分更新，仓储契约）。
  Future<void> updateEntry(
    int entryId, {
    String? content,
    int? importance,
  }) async {
    await _memoryRepository.updateEntry(
      entryId,
      content: content,
      importance: importance,
    );
    await load();
  }

  /// 删除记忆条目。
  Future<void> deleteEntry(int entryId) async {
    await _memoryRepository.deleteEntry(entryId);
    await load();
  }

  /// 关闭当前非阻塞提示。
  void dismissNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    notifyListeners();
  }

  /// 消费一次性 SnackBar 消息（view 弹出后调用，置 null）。
  void consumeSnackMessage() {
    if (_snackMessage == null) {
      return;
    }
    _snackMessage = null;
    notifyListeners();
  }

  /// 提出一次人设演化：经 [PersonaEvolutionService.proposeEvolution] 落快照并
  /// 刷新；期间 [proposing] 置位（防重复触发）。非 null → 消息「已提出演化，
  /// 待确认」；null（无变化）→ 消息「人设无变化」；异常 → [notice] 固定摘要
  /// （SR-16：不含 key/异常原文）。
  Future<void> proposeEvolution() async {
    if (_proposing) {
      return;
    }
    _proposing = true;
    _snackMessage = null;
    notifyListeners();
    try {
      final revision = await _evolutionService.proposeEvolution(_characterId);
      await load();
      _snackMessage = revision == null ? '人设无变化' : '已提出演化，待确认';
    } catch (_) {
      _notice = '人设演化失败，请稍后重试';
    } finally {
      _proposing = false;
      notifyListeners();
    }
  }

  /// 应用（确认）一条人设演化：回写 personality 后刷新；成功 → 消息「人设已
  /// 更新」；版本不存在 / 异常 → 不抛到 UI（语义 = 状态一致，静默）。
  Future<void> applyRevision(int revisionId) async {
    try {
      final ok = await _evolutionService.applyRevision(revisionId);
      if (ok) {
        _snackMessage = '人设已更新';
        await load();
      }
    } catch (_) {
      // 不抛到 UI：刷新保持状态一致。
    }
  }

  /// 拒绝一条人设演化：删除快照后刷新；版本不存在 / 异常 → 不抛到 UI。
  Future<void> discardRevision(int revisionId) async {
    try {
      final ok = await _evolutionService.discardRevision(revisionId);
      if (ok) {
        await load();
      }
    } catch (_) {
      // 不抛到 UI：保留既有列表，状态一致。
    }
  }
}
