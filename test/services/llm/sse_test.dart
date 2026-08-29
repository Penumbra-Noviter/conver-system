/// SSE 双协议行级解析器（工单 01b 验收 R1：纯函数解析器面）。
///
/// 归一化为 (event, data) 帧；Anthropic 事件型（content_block_delta 的
/// text_delta 提取 / message_stop 终态）与 OpenAI 纯 data 型
/// （choices[0].delta.content 提取，可为 null / [DONE] 终态）共用同一帧模型。
/// 锚：research-A `research/sse-wire/findings.md`。
library;

import 'dart:convert';

import 'package:conver_system_mobile/services/llm/sse.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐行喂入解析器，返回全部归一化帧（等价于流式消费的完整回放）。
List<SseFrame> _parseLines(Iterable<String> lines) {
  final parser = SseParser();
  final frames = <SseFrame>[];
  for (final line in lines) {
    frames.addAll(parser.feed(line));
  }
  return frames;
}

void main() {
  group('SseParser — 行归一化为 (event, data) 帧', () {
    test('Anthropic 事件帧：event + data + 空行 → 单帧', () {
      final frames = _parseLines([
        'event: message_start',
        'data: {"type":"message_start"}',
        '',
      ]);
      expect(frames, hasLength(1));
      expect(frames.single.event, 'message_start');
      expect(frames.single.data, '{"type":"message_start"}');
    });

    test('OpenAI 纯 data 帧：data + 空行 → 单帧（event 为空串）', () {
      final frames = _parseLines([
        'data: {"choices":[{"delta":{"content":"Hello"}}]}',
        '',
      ]);
      expect(frames, hasLength(1));
      expect(frames.single.event, isEmpty);
      expect(frames.single.data, '{"choices":[{"delta":{"content":"Hello"}}]}');
    });

    test('多行 data 以 \\n 拼合', () {
      final frames = _parseLines([
        'event: content_block_delta',
        'data: {"dst":',
        'data: 1}',
        '',
      ]);
      expect(frames, hasLength(1));
      expect(frames.single.data, '{"dst":\n1}');
    });

    test('data: 无空格前缀容错', () {
      final frames = _parseLines([
        'data:{"x":1}',
        '',
      ]);
      expect(frames.single.data, '{"x":1}');
    });

    test('data: 前缀后恰一个空格被剥离', () {
      final frames = _parseLines([
        'data: {"x":1}',
        '',
      ]);
      expect(frames.single.data, '{"x":1}');
    });

    test('注释行 (: …) 被忽略，不产出帧', () {
      final parser = SseParser();
      expect(parser.feed(': ping'), isEmpty);
      expect(parser.feed(': keep-alive'), isEmpty);
      expect(parser.feed(':'), isEmpty);
      expect(parser.feed(''), isEmpty);
    });

    test('空行无待发帧时不产出', () {
      final parser = SseParser();
      expect(parser.feed(''), isEmpty);
      expect(parser.feed(''), isEmpty);
    });

    test('帧结束前已累积的 data 不产出（流中断的尾帧滞留）', () {
      final parser = SseParser();
      expect(parser.feed('data: {"x":1}'), isEmpty);
      // 流在终态前中断：无空行终止，尾帧不产出（符合 wire：完整帧必以空行结束）
    });

    test('CRLF 行尾 \\r 剥离', () {
      final frames = _parseLines([
        'event: ping\r',
        'data: {"type":"ping"}\r',
        '\r',
      ]);
      expect(frames.single.event, 'ping');
      expect(frames.single.data, '{"type":"ping"}');
    });

    test('event 行在帧内任意位置设定当前事件', () {
      final frames = _parseLines([
        'data: {"x":1}',
        'event: abc',
        '',
      ]);
      expect(frames.single.event, 'abc');
      expect(frames.single.data, '{"x":1}');
    });

    test('未知前缀行（id:/retry:）静默忽略', () {
      final frames = _parseLines([
        'id: 42',
        'retry: 5000',
        'data: {"x":1}',
        '',
      ]);
      expect(frames, hasLength(1));
      expect(frames.single.data, '{"x":1}');
    });
  });

  group('Anthropic token 提取（content_block_delta）', () {
    SseFrame frame(Map<String, dynamic> data,
            {String event = 'content_block_delta'}) =>
        SseFrame(event: event, data: _json(data));

    test('text_delta → delta.text', () {
      final f = frame({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'Hello'},
      });
      expect(extractAnthropicText(f), 'Hello');
    });

    test('非 text_delta（thinking_delta 等）→ null', () {
      final f = frame({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': 'x'},
      });
      expect(extractAnthropicText(f), isNull);
    });

    test('非 content_block_delta 事件（ping / message_start / message_stop）→ null', () {
      for (final event in ['ping', 'message_start', 'message_delta', 'message_stop']) {
        expect(
          extractAnthropicText(frame({'type': event}, event: event)),
          isNull,
          reason: 'event=$event 不应携带文本',
        );
      }
    });

    test('仅 content_block_delta 事件产文本：非该事件携带 text_delta 结构亦不产出', () {
      const f = SseFrame(
        event: 'message_delta',
        data: '{"delta":{"type":"text_delta","text":"X"}}',
      );
      expect(extractAnthropicText(f), isNull);
    });

    test('缺 delta 键 → null', () {
      expect(extractAnthropicText(frame({'type': 'content_block_delta'})), isNull);
    });

    test('data 非法 JSON → null', () {
      const f = SseFrame(event: 'content_block_delta', data: 'not-json');
      expect(extractAnthropicText(f), isNull);
    });

    test('delta.text 空串 → null（空 token 不产出）', () {
      final f = frame({
        'delta': {'type': 'text_delta', 'text': ''},
      });
      expect(extractAnthropicText(f), isNull);
    });

    test('delta.text 非字符串 → null', () {
      final f = frame({
        'delta': {'type': 'text_delta', 'text': 42},
      });
      expect(extractAnthropicText(f), isNull);
    });
  });

  group('Anthropic 终态（message_stop）', () {
    test('message_stop → isAnthropicMessageStop true', () {
      const frame = SseFrame(event: 'message_stop', data: '{"type":"message_stop"}');
      expect(isAnthropicMessageStop(frame), isTrue);
    });

    test('其余事件 → false', () {
      for (final event in ['ping', 'message_start', 'content_block_delta']) {
        expect(
          isAnthropicMessageStop(SseFrame(event: event, data: '{}')),
          isFalse,
          reason: 'event=$event 不是终态',
        );
      }
    });
  });

  group('OpenAI token 提取（choices[0].delta.content）', () {
    SseFrame dataFrame(String data) => SseFrame(data: data);

    test('delta.content 字符串 → 提取', () {
      final f = dataFrame('{"choices":[{"delta":{"content":"Hello"}}]}');
      expect(extractOpenAiText(f), 'Hello');
    });

    test('delta.content 为 null（role 初始化 chunk）→ null', () {
      final f = dataFrame(
        '{"choices":[{"delta":{"role":"assistant","content":null}}]}',
      );
      expect(extractOpenAiText(f), isNull);
    });

    test('delta 缺 content（收尾 chunk delta:{}）→ null', () {
      final f = dataFrame('{"choices":[{"delta":{}}]}');
      expect(extractOpenAiText(f), isNull);
    });

    test('choices 空数组（include_usage usage chunk）→ null', () {
      final f = dataFrame('{"choices":[]}');
      expect(extractOpenAiText(f), isNull);
    });

    test('content 空串 → null（空 token 不产出）', () {
      final f = dataFrame('{"choices":[{"delta":{"content":""}}]}');
      expect(extractOpenAiText(f), isNull);
    });

    test('data 非法 JSON（如 [DONE]）→ null', () {
      const f = SseFrame(data: '[DONE]');
      expect(extractOpenAiText(f), isNull);
    });

    test('顶层/choices 结构异常 → null', () {
      expect(extractOpenAiText(dataFrame('not-json')), isNull);
      expect(extractOpenAiText(dataFrame('[1,2]')), isNull);
      expect(extractOpenAiText(dataFrame('{"choices":{}}')), isNull);
      expect(extractOpenAiText(dataFrame('{"choices":[42]}')), isNull);
      expect(extractOpenAiText(dataFrame('{"choices":[{"x":1}]}')), isNull);
      expect(extractOpenAiText(dataFrame('{"no_choices":[1]}')), isNull);
    });
  });

  group('OpenAI 终态（[DONE]）', () {
    test('data: [DONE] → isOpenAiDone true', () {
      final frames = _parseLines(['data: [DONE]', '']);
      expect(frames.single.data, '[DONE]');
      expect(isOpenAiDone(frames.single), isTrue);
    });

    test('无空格 data:[DONE] → true', () {
      final frames = _parseLines(['data:[DONE]', '']);
      expect(isOpenAiDone(frames.single), isTrue);
    });

    test('非 [DONE] 负载 → false', () {
      expect(isOpenAiDone(const SseFrame(data: '{"choices":[]}')), isFalse);
    });
  });

  group('端到端会话流（canned wire 回放）', () {
    test('Anthropic 会话：逐帧提取 token，message_stop 终止', () {
      final frames = _parseLines([
        'event: message_start',
        'data: {"type":"message_start","message":{"id":"msg_1","role":"assistant","content":[],"stop_reason":null}}',
        '',
        'event: content_block_start',
        'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}',
        '',
        'event: ping',
        'data: {"type":"ping"}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}',
        '',
        'event: content_block_delta',
        'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", world"}}',
        '',
        'event: content_block_stop',
        'data: {"type":"content_block_stop","index":0}',
        '',
        'event: message_delta',
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}',
        '',
        'event: message_stop',
        'data: {"type":"message_stop"}',
        '',
      ]);

      final tokens = <String>[];
      for (final frame in frames) {
        if (isAnthropicMessageStop(frame)) {
          break;
        }
        final token = extractAnthropicText(frame);
        if (token != null) {
          tokens.add(token);
        }
      }
      expect(tokens, ['Hello', ', world']);
    });

    test('OpenAI 会话：逐帧提取 token，[DONE] 终止', () {
      final frames = _parseLines([
        'data: {"id":"chatcmpl-1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}',
        '',
        'data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}',
        '',
        'data: {"choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}',
        '',
        'data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}',
        '',
        'data: [DONE]',
        '',
      ]);

      final tokens = <String>[];
      for (final frame in frames) {
        if (isOpenAiDone(frame)) {
          break;
        }
        final token = extractOpenAiText(frame);
        if (token != null) {
          tokens.add(token);
        }
      }
      expect(tokens, ['Hello', ' world']);
    });

    test('[DONE] 前中断：已消费帧全部产出，终态不触发', () {
      final frames = _parseLines([
        'data: {"choices":[{"delta":{"content":"partial"}}]}',
        '',
        'data: {"choices":[{"delta":{"content":" reply"}}]}',
        '', // 流在此中断：无 [DONE]
      ]);
      expect(frames, hasLength(2));
      expect(frames.any(isOpenAiDone), isFalse);
    });
  });
}

/// 将 map 编码为单行 JSON（canned data 载荷）。
String _json(Map<String, dynamic> map) => jsonEncode(map);