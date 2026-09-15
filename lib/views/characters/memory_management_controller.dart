/// MemoryManagementController — 角色记忆管理页的状态机（AC-05）。
///
/// 职责：加载指定角色的记忆条目与人设演化版本；记忆条目增/改/删经
/// [MemoryRepository] 后重载；演化历史只读（listRevisions）。纯编排，不触碰
/// 具体 UI 与平台存储。
///
/// 层级：ChangeNotifier 视图模型，依赖 [MemoryRepository]（数据层）。
library;

import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart'
    show MemoryEntry, PersonaRevision;
import '../../data/database/tables.dart' show MemoryKind;
import '../../data/repositories/memory_repository.dart';

/// 角色记忆管理控制器。
class MemoryManagementController extends ChangeNotifier {
  /// [memoryRepository] 记忆数据源；[characterId] 目标角色。
  MemoryManagementController({
    required this._memoryRepository,
    required this._characterId,
  });

  final MemoryRepository _memoryRepository;
  final int _characterId;

  bool _loading = false;
  List<MemoryEntry> _entries = const [];
  List<PersonaRevision> _revisions = const [];
  String? _notice;

  /// 加载中（首次加载 spinner）。
  bool get loading => _loading;

  /// 记忆条目列表（importance 降序、createdAt 倒序，仓储契约）。
  List<MemoryEntry> get entries => _entries;

  /// 人设演化版本列表（createdAt 倒序，仓储契约）。
  List<PersonaRevision> get revisions => _revisions;

  /// 非阻塞提示（加载失败等）；null 无。
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
}
