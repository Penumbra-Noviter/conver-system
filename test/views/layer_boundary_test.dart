// F-9 分层边界静态不变量：视图层不得引用数据层/平台存储的具体实现。
//
// 源码文本断言（引用面约束，不锁实现行）：`lib/views/**` 全部 .dart 源文件
// 不含 `AppDatabase` / `FlutterSecretStore` 标识符（词边界正则）——确保视图层
// 不再现造数据库或平台安全存储实例，装配链单一收编于 home_shell（spec F-9
// 验收 1/2）。`settings_repository.dart`（数据层，含 `?? FlutterSecretStore()`
// seam）不在本断言扫描范围内。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 递归收集 [dir] 下全部 `.dart` 文件（按路径排序保证确定性输出）。
List<File> _dartFilesUnder(Directory dir) {
  final files = <File>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

void main() {
  final dartFiles = _dartFilesUnder(Directory('lib/views'));

  test('扫描面非空（防空目录下断言恒真）', () {
    expect(dartFiles, isNotEmpty, reason: 'lib/views 应存在 .dart 源文件');
    expect(
      dartFiles.map((f) => f.path.replaceAll('\\', '/')),
      contains('lib/views/home_shell.dart'),
      reason: '扫描面应包含已知视图文件（路径解析自包根目录）',
    );
  });

  test('lib/views/** 不引用 AppDatabase（无数据层缺省构造）', () {
    final offending = <String>[
      for (final file in dartFiles)
        if (RegExp(r'\bAppDatabase\b').hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offending, isEmpty,
        reason: '视图层不得出现 AppDatabase 标识符（隐式第二装配点）');
  });

  test('lib/views/** 不引用 FlutterSecretStore（无平台存储缺省构造）', () {
    final offending = <String>[
      for (final file in dartFiles)
        if (RegExp(r'\bFlutterSecretStore\b')
            .hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offending, isEmpty,
        reason: '视图层不得出现 FlutterSecretStore 标识符（隐式第二装配点）');
  });
}
