/// 角色文件导入/导出的平台通道 seam（M3-01 定义接口 + Stub 壳）。
///
/// 通道契约（M3-01 工件）：
/// - 视图层/控制器不直接触碰 file_picker / share_plus / path_provider——
///   全部平台调用收口在本接口的实现之后（M3-03 交付真实现）；
/// - 本票 [CharacterFileExchangeStub] 为占位壳：导出按钮经此调用并展示
///   「随后续批次交付」提示，**永不触真平台通道**（测试注入 fake seam
///   断言调用链）；
/// - 实现约定：导出产物文件名由实现方以 `{safeName}.json` 构造（文件名
///   安全净化纯函数归 M3-03），返回值为用户可读的结果提示文案。
library;

import '../data/database/app_database.dart' show Character;

/// 角色 V2 卡文件交换 seam——导入/导出平台薄层。
///
/// 方法返回用户可读结果文案（成功路径由实现构造）；失败路径抛异常，
/// 由控制器兜底转 notice（平台调用点须 `.timeout(3s)` 防挂握 + catch
/// 降级，M3-03 真实现落实，测试断言防御存在）。
abstract interface class CharacterFileExchange {
  /// 导出 [character] 为 V2 JSON 卡文件；返回展示给用户的提示文案。
  Future<String> exportCharacter(Character character);
}

/// 占位提示实现（M3-01）——不触碰任何平台通道。
///
/// 真实现（file_picker / share_plus 分享 / 临时目录写入）随 M3-03 追加，
/// 本类保持串行不动。文案锚「随后续批次交付」（验收 7 语义）。
class CharacterFileExchangeStub implements CharacterFileExchange {
  const CharacterFileExchangeStub();

  @override
  Future<String> exportCharacter(Character character) async {
    return '角色导出（V2 JSON 卡）随后续批次交付';
  }
}