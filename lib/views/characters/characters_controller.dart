/// CharactersController — 角色 tab 的列表 / 加载 / 编辑 / 单删 / 导出占位
/// 状态机（M3-01 切片）。
///
/// 语义锚点（spec §Implementation Decisions 角色列表面）：
/// - 列表语义对齐桌面 `characterCardHtml`：随 [CharacterRepository.listCharacters]
///   契约（updated_at 倒序 + conversation_count），本层只透传不重排；
/// - 下拉刷新 / 切回 tab 自动刷新经 [refresh]（幂等：加载中并发调用合并，
///   不重复闪烁）；
/// - 单删经仓储 [CharacterRepository.deleteCharacter]，对话/消息 FK CASCADE
///   由数据层兜底（本层零显式级联代码）；删除后若当前聊天 tab 打开的对话
///   归属该角色 → [ChatController.backToEntry] 回入口（共识 A4）；
/// - 导出经 [CharacterFileExchange] seam（平台通道收口；本票 Stub 占位，
///   fake seam 注入测试断言调用链，永不触真平台通道）。
///
/// 层级：ChangeNotifier 视图模型。唯一依赖仓储抽象 + seam + [ShellNavigation]
/// + [ChatController]，不触碰数据库具体实现 / 平台存储（`layer_boundary_test`
/// 契约）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/database/app_database.dart' show Character, CharactersCompanion;
import '../../data/repositories/character_repository.dart';
import '../../services/character_card.dart';
import '../../services/character_file_exchange.dart';
import '../../view_models/shell_navigation.dart';
import '../chat/chat_controller.dart';

// 构造为公开命名参数（装配点语义）+ 私有 `_` 字段：initializing formal 无法
// 同时满足两者，整文件抑制该 lint（对齐 chat_controller.dart 既有惯例）。
// ignore_for_file: prefer_initializing_formals

/// 角色 tab 列表控制器。
///
/// 装配：app 层注入真实仓储 / seam / 导航 / 聊天控制器；测试注入内存库
/// 仓储 + seam fake。切回 tab 时由 CharactersView 幂等触发 [refresh]。
class CharactersController extends ChangeNotifier {
  /// [characterRepository] 列表 / 单删 / 编辑数据源；
  /// [fileExchange] 导出平台通道 seam（本票 Stub）；
  /// [navigation] 开始对话切换底部 tab；[chatController] 建会话 / 回入口。
  CharactersController({
    required CharacterRepository characterRepository,
    required CharacterFileExchange fileExchange,
    required ShellNavigation navigation,
    required ChatController chatController,
  })  : _characterRepository = characterRepository,
        _fileExchange = fileExchange,
        _navigation = navigation,
        _chatController = chatController;

  final CharacterRepository _characterRepository;
  final CharacterFileExchange _fileExchange;
  final ShellNavigation _navigation;
  final ChatController _chatController;

  bool _loading = false;
  bool _hasLoaded = false;
  List<CharacterWithCount> _characters = const [];
  String? _notice;

  /// 列表加载中（空态首次加载显示 spinner）。
  bool get loading => _loading;

  /// 至少完成过一次 [refresh]（成功或失败均记入，幂等可重试）。
  bool get hasLoaded => _hasLoaded;

  /// 角色 + 对话数列表（updated_at 倒序，仓储契约）。
  List<CharacterWithCount> get characters => _characters;

  /// 非阻塞提示（加载失败 / 导出占位 / 删除反馈）；null 无。
  String? get notice => _notice;

  /// 关闭当前非阻塞提示。
  void dismissNotice() {
    if (_notice == null) {
      return;
    }
    _notice = null;
    notifyListeners();
  }

  /// 重新拉取角色列表（下拉刷新 / 切回 tab 自动刷新共用）。
  ///
  /// 幂等：加载中并发调用直接合并（不重复发起 / 不闪烁）；失败 → [notice]
  /// 且保留既有列表（不因刷新失败清空已展示数据）。
  Future<void> refresh() async {
    if (_loading) {
      return;
    }
    _loading = true;
    notifyListeners();
    try {
      _characters =
          await _characterRepository.listCharacters().timeout(const Duration(seconds: 3));
      _notice = null;
    } catch (error) {
      _notice = _notice ?? '加载角色失败: $error';
    } finally {
      // 成功 / 失败都算完成一次刷新（幂等可重试，对齐 ChatController.loadEntry）。
      _hasLoaded = true;
      _loading = false;
      notifyListeners();
    }
  }

  /// 删除 [characterId] 角色；成功返回 true 并刷新列表。
  ///
  /// 删除后若当前聊天 tab 打开的对话归属该角色 → 回聊天入口（共识 A4
  /// backToEntry 语义）；其对话/消息由 FK CASCADE 随之消失（数据层实证）。
  /// 角色不存在 → false 且零副作用（notice「角色不存在或已删除」）。
  Future<bool> deleteCharacter(int characterId) async {
    final deleted =
        await _characterRepository.deleteCharacter(characterId);
    if (!deleted) {
      _notice = _notice ?? '角色不存在或已删除';
      notifyListeners();
      return false;
    }
    final active = _chatController.activeConversation;
    if (active != null && active.characterId == characterId) {
      await _chatController.backToEntry();
    }
    await refresh();
    return true;
  }

  /// 从角色卡「开始对话」：切到聊天 tab 并以 [characterId] 直达新会话
  /// （[ChatController.createConversationFor]，默认模型）。
  Future<void> startConversation(int characterId) {
    _navigation.select(ShellTab.chat);
    return _chatController.createConversationFor(characterId);
  }

  /// 导入一张角色卡（M3-03）：经 [CharacterFileExchange] seam 调平台文件
  /// 选择器选单个 `.json` → 解析归一化 → 落库 + 刷新列表 + 成功 notice。
  ///
  /// 语义分级（验收 2）：
  /// - 用户取消 / 平台挂起超时降级（seam 返回 null）→ 零副作用；
  /// - 格式错（[CardFormatException]，文案含格式引导「无法识别的角色卡
  ///   格式」等）与校验错（[CardValidationException]，纯原因「角色名称不能
  ///   为空」）分级转 notice；
  /// - 其它异常 / 超时兜底「导入角色失败: $error」。
  Future<void> importCharacter() async {
    try {
      final draft = await _fileExchange
          .importCharacter()
          .timeout(const Duration(seconds: 3));
      if (draft == null) {
        return; // 用户取消 / 挂起降级，零副作用。
      }
      await _characterRepository.createCharacter(draft.toCompanion());
      await refresh();
      _notice = '已导入角色「${draft.name}」';
    } on CardFormatException catch (error) {
      _notice = error.message;
    } on CardValidationException catch (error) {
      _notice = error.message;
    } catch (error) {
      _notice = _notice ?? '导入角色失败: $error';
    }
    notifyListeners();
  }

  /// 导出一张角色卡（本票占位）：经 [CharacterFileExchange] seam 调用，
  /// 返回文案展示为 [notice]；异常 / 超时兜底转 notice。
  Future<void> exportCharacter(Character character) async {
    try {
      final message = await _fileExchange
          .exportCharacter(character)
          .timeout(const Duration(seconds: 3));
      _notice = message;
    } catch (error) {
      _notice = _notice ?? '导出失败: $error';
    }
    notifyListeners();
  }

  /// 编辑保存：[CharacterRepository.updateCharacter] 部分更新（仅显式提供
  /// 字段，updated_at 前移由仓储契约保证）；成功后刷新列表。角色不存在 →
  /// notice 且列表保持。
  Future<void> saveCharacter(int characterId, CharactersCompanion data) async {
    final updated =
        await _characterRepository.updateCharacter(characterId, data);
    if (updated == null) {
      _notice = _notice ?? '角色不存在或已删除';
      notifyListeners();
      return;
    }
    await refresh();
  }
}