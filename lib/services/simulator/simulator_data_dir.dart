/// 模拟器数据目录解析 seam（F-M5-01 数据底座）。
///
/// 数据目录 = 应用文档目录下 `simulators/`——与桌面 `%APPDATA%/ConverSystem/
/// simulators` 语义同构（spec §9 范围外复述：不引入桌面路径常量）。解析经
/// 注入回调（生产 path_provider `getApplicationDocumentsDirectory`，测试临时
/// 目录）——本模块是平台 seam，业务逻辑（种子/服务器/列表）以注入方式消费
/// 解析结果，不直接触碰平台通道。
///
/// 协议表面（深模块）：`SimulatorDataDir`（唯一入口 [resolve]）/
/// `defaultResolveDocumentsDir`（缺省文档目录解析）。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 文档目录解析回调（生产 path_provider，测试注入临时目录）。
typedef ResolveDocumentsDir = Future<Directory> Function();

/// 模拟器数据目录（应用文档目录下 [subdirectory] 子目录）。
///
/// [resolve] 只做路径解析、不创建目录——建目录职责归消费方（首启种子
/// `ensureSeeded` 按需建目录），解析失败路径（文档目录不可得）由 platform
/// 通道异常向上抛出，不吞不换端口绕过。
class SimulatorDataDir {
  /// 构造可注入 [resolveDocumentsDir]；缺省走 path_provider。
  SimulatorDataDir({ResolveDocumentsDir? resolveDocumentsDir})
      : _resolveDocumentsDir = resolveDocumentsDir ?? defaultResolveDocumentsDir;

  final ResolveDocumentsDir _resolveDocumentsDir;

  /// 模拟器数据目录子目录名（单一归属；种子目标目录与服务器 serve 根共用）。
  static const String subdirectory = 'simulators';

  /// 解析应用文档目录下模拟器数据目录（不创建；消费方按需建目录）。
  Future<Directory> resolve() async {
    final documents = await _resolveDocumentsDir();
    return Directory('${documents.path}${Platform.pathSeparator}$subdirectory');
  }
}

/// 缺省文档目录：path_provider `getApplicationDocumentsDirectory`。
Future<Directory> defaultResolveDocumentsDir() => getApplicationDocumentsDirectory();