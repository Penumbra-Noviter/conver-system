/// SSE 双协议行级解析器 — 纯函数，无任何 I/O。
///
/// 原始行 → 归一化 (event, data) 帧；Anthropic 事件型（`event:` + `data:`）
/// 与 OpenAI 纯 data 型（仅 `data:`）共用同一帧模型。锚：research-A
/// `research/sse-wire/findings.md`（官方一手来源：anthropics/anthropic-sdk-python
/// `_streaming.py`、openai/openai-openapi `openapi.yaml`）。
///
/// 容错清单（锚 research findings）：`data:` 前缀后可选无空格；多行 data 以
/// `\n` 拼合；注释行（`: ping` / `: keep-alive`）与空行忽略；CRLF 行尾 `\r`
/// 剥离；未知事件静默忽略；OpenAI `delta.content` 可为 null 须跳过。
library;

import 'dart:convert';

/// 归一化 SSE 帧：原始行序列中的一段（以空行结束）。
class SseFrame {
  const SseFrame({this.event = '', required this.data});

  /// 事件名（Anthropic 事件型；OpenAI 纯 data 型为空串）。
  final String event;

  /// 帧负载（data 行以 `\n` 拼合；OpenAI 下为 chunk JSON 或 `[DONE]`）。
  final String data;
}

/// 流式 SSE 行解析器（有状态缓冲，无 I/O；逐行喂入）。
///
/// [feed] 处理一行原始 SSE 文本，当该行结束一个帧（空行）时返回该帧；
/// 其余行返回空列表。
class SseParser {
  final StringBuffer _data = StringBuffer();
  String? _event;

  List<SseFrame> feed(String line) {
    // CRLF 行尾（\r\n）剥离，避免污染 event 名与 data 载荷。
    final l = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

    if (l.isEmpty) {
      return _emitFrame();
    }
    if (l.startsWith(':')) {
      // SSE 注释行（如 ": ping"），忽略。
      return const [];
    }
    if (l.startsWith('event:')) {
      _event = l.substring('event:'.length).trim();
      return const [];
    }
    if (l.startsWith('data:')) {
      var value = l.substring('data:'.length);
      // 规范允许 "data:" 后省略空格，也允许恰好一个空格（多余空格保留）。
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
      if (_data.isNotEmpty) {
        _data.write('\n');
      }
      _data.write(value);
      return const [];
    }
    // 其余字段（id: / retry: / 未知前缀）静默忽略。
    return const [];
  }

  List<SseFrame> _emitFrame() {
    if (_event == null && _data.isEmpty) {
      return const [];
    }
    final frame = SseFrame(event: _event ?? '', data: _data.toString());
    _event = null;
    _data.clear();
    return [frame];
  }
}

/// Anthropic 终态：`message_stop` 事件。
bool isAnthropicMessageStop(SseFrame frame) => frame.event == 'message_stop';

/// 从 Anthropic 帧提取文本 token。
///
/// 仅 `content_block_delta` 事件中 `delta.type == "text_delta"` 的负载携带
/// 文本（其余 delta 类型：thinking_delta / signature_delta / input_json_delta /
/// citations_delta，非文本丢弃）；其余事件（ping / message_start / message_delta
/// / message_stop 等）返回 null。
String? extractAnthropicText(SseFrame frame) {
  if (frame.event != 'content_block_delta') {
    return null;
  }
  final decoded = _decodeData(frame.data);
  if (decoded == null) {
    return null;
  }
  final delta = decoded['delta'];
  if (delta is! Map<String, dynamic> || delta['type'] != 'text_delta') {
    return null;
  }
  final text = delta['text'];
  return (text is String && text.isNotEmpty) ? text : null;
}

/// OpenAI 终态：`data: [DONE]` 行。
bool isOpenAiDone(SseFrame frame) => frame.data == '[DONE]';

/// 从 OpenAI 帧提取文本 token：`choices[0].delta.content`（string|null）。
///
/// 容错（锚 research findings）：`delta.content` 可为 null（role/tool_calls
/// chunk）、`delta:{}` 缺 content（收尾 chunk）、`choices` 空数组（include_usage
/// 的 usage chunk）——一律静默跳过返回 null；空串不作为 token 产出。
String? extractOpenAiText(SseFrame frame) {
  final decoded = _decodeData(frame.data);
  if (decoded == null) {
    return null;
  }
  final choices = decoded['choices'];
  if (choices is! List || choices.isEmpty) {
    return null;
  }
  final choice = choices.first;
  if (choice is! Map<String, dynamic>) {
    return null;
  }
  final delta = choice['delta'];
  if (delta is! Map<String, dynamic>) {
    return null;
  }
  final content = delta['content'];
  return (content is String && content.isNotEmpty) ? content : null;
}

/// 解码帧 data 为 JSON 对象；任何解析/结构失败返回 null（静默跳过）。
Map<String, dynamic>? _decodeData(String data) {
  final Object? decoded;
  try {
    decoded = jsonDecode(data);
  } on FormatException {
    return null;
  }
  return decoded is Map<String, dynamic> ? decoded : null;
}