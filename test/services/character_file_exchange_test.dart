/// CharacterFileExchange 真实现 seam 测试（M3-03）。
///
/// 测试 seam（公共接口边界）：[FilePickerShareFileExchange] 构造注入
/// [PickJsonBytes] / [ResolveTempDirectory] / [ShareFile] 类型化 fake +
/// 短 [FilePickerShareFileExchange] `platformTimeout`——断言平台调用点
/// `.timeout(3s)` 双层防御存在（fake「挂起不抛错」→ 超时降级不挂死）；
/// [safeFileName] 验收 6 语义测试已随纯函数迁至 `file_name_test.dart`
/// （2026-09-07 架构深化）。永不触真平台通道。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conver_system_mobile/data/database/app_database.dart';
import 'package:conver_system_mobile/services/character_card.dart';
import 'package:conver_system_mobile/services/character_file_exchange.dart';
import 'package:flutter_test/flutter_test.dart';

/// 完整 Character 行（导出侧输入）。
Character _character({
  String name = '导出角色',
  String description = '描述',
  String personality = '人格',
  String scenario = '场景',
  String firstMes = '你好。',
  String mesExample = '例。',
  String systemPrompt = '系统提示。',
  String postHistoryInstructions = '后记。',
  List<String> alternateGreetings = const ['备选'],
  List<String> tags = const ['标签'],
  String creator = '作者',
  String version = '1.0',
  Map<String, dynamic> creatorNotes = const {'a': 1},
  Map<String, dynamic> extensions = const {},
  String? avatar,
  double temperature = 0.7,
}) {
  return Character(
    id: 1,
    name: name,
    description: description,
    personality: personality,
    scenario: scenario,
    firstMes: firstMes,
    mesExample: mesExample,
    systemPrompt: systemPrompt,
    postHistoryInstructions: postHistoryInstructions,
    alternateGreetings: alternateGreetings,
    tags: tags,
    creator: creator,
    version: version,
    creatorNotes: creatorNotes,
    extensions: extensions,
    avatar: avatar,
    temperature: temperature,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );
}

Uint8List _v2CardBytes() {
  final card = <String, dynamic>{
    'spec': 'chara_card_v2',
    'spec_version': '2.0',
    'data': <String, dynamic>{
      'name': '导入角色',
      'personality': '导入人格',
      'character_version': '1.2',
      'avatar': null,
      'extensions': <String, dynamic>{},
    },
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(card)));
}

void main() {
  group('CharacterFileExchangeStub · 占位壳（M3-01 语义不回归）', () {
    test('导出 → 占位文案「随后续批次交付」', () async {
      const stub = CharacterFileExchangeStub();
      expect(
        await stub.exportCharacter(_character(name: '壳')),
        '角色导出（V2 JSON 卡）随后续批次交付',
      );
    });

    test('导入 → null（视为未选择，零副作用，不触通道）', () async {
      const stub = CharacterFileExchangeStub();
      expect(await stub.importCharacter(), isNull);
    });
  });

  group('parseCharacterCardBytes · 文件级解析边界', () {
    test('非法 UTF-8 字节 → 格式错', () {
      expect(
        () => parseCharacterCardBytes(Uint8List.fromList([0xff, 0xfe, 0x80])),
        throwsA(isA<CardFormatException>()),
      );
    });

    test('合法 UTF-8 但 JSON 语法错 → 格式错', () {
      expect(
        () => parseCharacterCardBytes(Uint8List.fromList(utf8.encode('{oops'))),
        throwsA(isA<CardFormatException>()),
      );
    });

    test('合法 JSON 但非对象（数组）→ 格式错「必须是 JSON 对象」', () {
      expect(
        () => parseCharacterCardBytes(
            Uint8List.fromList(utf8.encode('[1, 2, 3]'))),
        throwsA(isA<CardFormatException>().having(
          (e) => e.message, 'message', contains('必须是 JSON 对象'),
        )),
      );
    });
  });

  group('importCharacter · pick → 解析（fake picker 注入）', () {
    test('选中合法 V2 卡字节 → 返回归一化 draft', () async {
      final seam = FilePickerShareFileExchange(
        pickJsonBytes: () async => _v2CardBytes(),
      );

      final draft = await seam.importCharacter();

      expect(draft, isNotNull);
      expect(draft!.name, '导入角色');
      expect(draft.personality, '导入人格');
      expect(draft.version, '1.2');
    });

    test('用户取消（pick 返回 null）→ 返回 null 零副作用', () async {
      final seam = FilePickerShareFileExchange(
        pickJsonBytes: () async => null,
      );

      expect(await seam.importCharacter(), isNull);
    });

    test('非法 JSON 字节 → 格式错（文件非合法 JSON）', () async {
      final seam = FilePickerShareFileExchange(
        pickJsonBytes: () async => Uint8List.fromList(utf8.encode('{oops')),
      );

      expect(
        seam.importCharacter,
        throwsA(isA<CardFormatException>()),
      );
    });

    test('V1 旧卡 / 裸 data 均可经 seam 导入（纯函数语义贯通）', () async {
      final v1Bytes = Uint8List.fromList(utf8.encode(jsonEncode({
        'char_name': '旧卡',
        'char_greeting': '开场',
      })));
      final seam = FilePickerShareFileExchange(
        pickJsonBytes: () async => v1Bytes,
      );
      final draft = await seam.importCharacter();
      expect(draft!.name, '旧卡');
      expect(draft.firstMes, '开场');
    });
  });

  group('exportCharacter · 临时目录 + 分享（fake 注入）', () {
    test('导出 → share 收到 {safeName}.json 字节与正确 V2 信封', () async {
      late File sharedFile;
      late String sharedName;
      final tempDir = await Directory.systemTemp.createTemp('seam-test');
      addTearDown(() => tempDir.delete(recursive: true));
      final seam = FilePickerShareFileExchange(
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async {
          sharedFile = file;
          sharedName = name;
        },
      );

      final message = await seam.exportCharacter(_character(name: '导出我'));

      expect(sharedName, '导出我.json');
      expect(sharedFile.path, endsWith('导出我.json'));
      expect(message, contains('导出我.json'));
      final card = jsonDecode(await sharedFile.readAsString())
          as Map<String, dynamic>;
      expect(card['spec'], 'chara_card_v2');
      expect((card['data']! as Map<String, dynamic>)['name'], '导出我');
      expect((card['data']! as Map<String, dynamic>)['character_version'], '1.0');
    });

    test('非法字符文件名 → share 收到净化后的 safeName.json', () async {
      late String sharedName;
      final tempDir = await Directory.systemTemp.createTemp('seam-test');
      addTearDown(() => tempDir.delete(recursive: true));
      final seam = FilePickerShareFileExchange(
        resolveTempDirectory: () async => tempDir,
        shareFile: (file, name) async {
          sharedName = name;
        },
      );

      await seam.exportCharacter(_character(name: 'a/b\\c:d*e?f"g<h>i|j'));

      expect(sharedName, 'a_b_c_d_e_f_g_h_i_j.json');
    });

    test('tempDir 挂起 + 短超时 → StateError（platformTimeout 接线到共享腿）',
        () async {
      // 共享腿超时防御已收敛至 platform_file_exchange_test；此处保留一条
      // seam 级接线断言，兜住未来 seam 忘记透传 platformTimeout 的回归。
      final hanging = Completer<Directory>().future;
      final seam = FilePickerShareFileExchange(
        resolveTempDirectory: () => hanging,
        shareFile: (file, name) async {},
        platformTimeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        seam.exportCharacter(_character()),
        throwsA(isA<StateError>()),
      );
    });
  });
}