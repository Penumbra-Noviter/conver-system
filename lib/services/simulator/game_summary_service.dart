/// 模拟器游戏简介编排服务（本批次，混合方案）——导入挂点的单一编排落点。
///
/// 职责：导入成功（[SimulatorImportFlow] `onImported`）后——
/// 1. **规则提取同步写回**（零 LLM 零成本，恒执行）：[extractGameSummary] +
///    [buildFallbackSummary] 拼兜底简介，经 `updateManifestEntryDescription`
///    （`onlyIfEmpty: true`）仅填充缺失描述（导入条目 description 为空，
///    卡片不再空白）；既有描述不覆盖。
/// 2. **LLM 精修异步替换**（开关开启且有 Key 时）：规则简介质量中等，开关
///    （`simulator_llm_description_enabled`，默认关，成本敏感 opt-in）开启时
///    经 [GameDescriptionGenerator] 生成一句有特点的简介替换写回；失败（LLM
///    错误 / 空回复 / 凭据缺失）静默降级保留规则简介，不阻断、不抛（项目
///    约定：失败至少打日志）。精修落盘后回调 [onDescriptionRefined]（装配层
///    接线列表刷新，新简介自动上屏）。
///
/// 纯 Dart 深模块：依赖全部构造注入；消费方只调 [summarizeOnImport] 一个入口。
/// 协议表面：`GameSummaryService`。
// ignore_for_file: prefer_initializing_formals — 构造为公开命名参数（装配点
// 语义）+ 私有 `_` 字段，initializing formal 无法同时满足两者（对齐
// game_generator.dart 同款惯例）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import 'game_description_generator.dart' show GameDescriptionGenerator;
import 'game_summary_extractor.dart'
    show buildFallbackSummary, extractGameSummary;
import 'import_service.dart' show updateManifestEntryDescription;

/// 模拟器游戏简介编排服务（见文件头注释）。
class GameSummaryService {
  /// [generator] LLM 精修服务（失败内部降级，不向调用方传播）；[llmRefinementEnabled]
  /// 精修开关读取（设置键 `simulator_llm_description_enabled`）；[onDescriptionRefined]
  /// 精修写回成功后的回调（装配层接线列表刷新；null = 不接线）。
  GameSummaryService({
    required GameDescriptionGenerator generator,
    required Future<bool> Function() llmRefinementEnabled,
    void Function()? onDescriptionRefined,
  }) : _generator = generator,
       _llmRefinementEnabled = llmRefinementEnabled,
       _onDescriptionRefined = onDescriptionRefined;

  final GameDescriptionGenerator _generator;
  final Future<bool> Function() _llmRefinementEnabled;
  final void Function()? _onDescriptionRefined;

  /// 导入挂点：规则简介同步写回（仅填充缺失描述）+ 精修异步调度。
  ///
  /// [game] 为导入后的 manifest 条目（须含 String id）；[html] 为游戏文件
  /// 解码文本。同步部分零网络零等待（提取 + 读-改-写）；精修为 fire-and-forget
  /// （内部异常全捕获降级）。id 缺失 → 直接返回（无副作用）；规则提取全空
  /// （fallback 为空，如纯 CSS 页面）→ 不写回也不调度精修——LLM 无内容可
  /// 依据时会凭空编造简介，宁可让卡片保持空白。
  void summarizeOnImport({
    required Directory simDir,
    required Map<String, dynamic> game,
    required String html,
  }) {
    final Object? id = game['id'];
    if (id is! String) {
      return;
    }
    final candidate = extractGameSummary(html);
    final fallback = buildFallbackSummary(candidate);
    if (fallback.isEmpty) {
      return;
    }
    updateManifestEntryDescription(simDir, id, fallback, onlyIfEmpty: true);
    unawaited(_maybeRefine(simDir, id, html));
  }

  /// 精修调度：开关开启 → 生成 → 替换写回 → 刷新回调；全程异常捕获降级
  /// （保留规则简介，不阻断导入流程）。
  Future<void> _maybeRefine(Directory simDir, String id, String html) async {
    try {
      if (!await _llmRefinementEnabled()) {
        return;
      }
      final candidate = extractGameSummary(html);
      final refined = await _generator.refine(candidate);
      if (refined.isEmpty) {
        debugPrint('简介精修跳过: LLM 返回空简介，保留规则简介');
        return;
      }
      updateManifestEntryDescription(simDir, id, refined);
      _onDescriptionRefined?.call();
    } catch (error) {
      // 失败降级：保留规则简介（卡片仍有内容），不阻断导入。
      debugPrint('简介 LLM 精修失败，保留规则简介: $error');
    }
  }
}
