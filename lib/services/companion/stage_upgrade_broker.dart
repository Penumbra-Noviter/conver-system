/// StageUpgradeBroker — 亲密/挚爱升级提议的装配层广播（PS2-08）。
///
/// 职责：承接 [RelationshipService.evaluateAfterTurn] 产生的升级提议
/// （经 ChatService 的 `onStageUpgradeProposal` 回调上行），向 UI 层广播。
/// UI（PS2-10 确认闸门）消费 [lastProposal] 展示「当前阶段 → 目标阶段」，
/// 确认/拒绝经 RelationshipService 落库——broker 本身**零写库**（SR-10：
/// 提议不落库，确认才落库）。
library;

import 'package:flutter/foundation.dart';

import 'relationship_service.dart';

/// 升级提议广播器（ChangeNotifier，装配层单例）。
class StageUpgradeBroker extends ChangeNotifier {
  StageUpgradeProposal? _lastProposal;
  final Set<int> _rejected = <int>{};

  /// 最近一次发布的升级提议；消费方展示后可用 [clear] 清态。
  StageUpgradeProposal? get lastProposal => _lastProposal;

  /// 本会话内已拒绝过升级提议的角色 id 集合（W6-F2：从视图 State 字段
  /// 上提，切 tab 重建视图后「本会话不重弹」语义仍成立，spec 判定⑤）。
  Set<int> get rejectedCharacterIds => _rejected;

  /// 是否已拒绝过 [characterId] 的升级提议（UI 据此隐藏操作行）。
  bool isRejected(int characterId) => _rejected.contains(characterId);

  /// 发布 [proposal] 并通知监听者（PS2-07 回合结束链回调入口）。
  void publish(StageUpgradeProposal proposal) {
    _lastProposal = proposal;
    notifyListeners();
  }

  /// 记录 [characterId] 的拒绝（零写库，仅会话内记忆）。
  void reject(int characterId) {
    _rejected.add(characterId);
    notifyListeners();
  }

  /// 清空当前提议与拒绝记录（UI 确认/拒绝/关闭后调用，防残留误导）。
  void clear() {
    _lastProposal = null;
    notifyListeners();
  }
}