/// LLM 双协议流式 wire 共享骨架（2026-09-07 架构深化——候选 3 收拢）。
///
/// claude / openai 两 provider 的 `_streamRequest` 此前逐行同构（POST +
/// SSE 消费 + 断连兜底 + 未终态兜底 + 强制关连接，~50 行 ×2）；收敛为
/// [streamSse]：断连 / 超时 / 未终态判定契约单一归属。provider 只提供
/// 差异面（端点 / 请求体 / 头 / 终态判定 / 帧提取 / 流内错误帧工厂）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'errors.dart';
import 'sse.dart';
import 'translate_helpers.dart' show HttpStatusError;

/// POST + SSE 消费的共享流式骨架，逐 token 产出。
///
/// - [uri] / [body] / [headers]：请求差异面（provider 组装）；
/// - [isTerminated]：终态帧判定（未收到 → 流结束抛
///   [LLMConnectionInterruptedError]，区分「连接中断」而非正常完成）；
/// - [extractToken]：帧 → token（`null` = 该帧无内容）；
/// - [errorFrameException]：流内错误帧工厂（claude 的 `event=='error'`
///   → 抛 provider 私有异常；openai 无此语义传 `null`）；
/// - [connectTimeout]：连接超时（缺省 10s）；
/// - [idleTimeout]：流消费期的帧间隔守卫（缺省 60s，弱网假活连接终态化保障）。
///
/// 骨架统一兜底：连接建立段（connect 相位）的传输失败（DNS / 拒连 / 连接
/// 超时 / 响应头前断）确定未产生服务端生成，统一收敛为
/// [LLMConnectionInterruptedError]（与流中途断连判型同构，服务层据此对
/// 「首 token 前」失败编排连接阶段自动重试）；已收到状态码非 200 →
/// [HttpStatusError]（携原文交状态码翻译）；流中段 `SocketException` /
/// `HttpException` → [LLMConnectionInterruptedError]；**idle timeout**：
/// 流消费期超过 [idleTimeout] 无任何字节行到达 → 强制关闭连接使 await-for
/// 自然收束 → 复用断连判型抛断线（任何行——含 `: ping` 注释帧——到达即重置
/// 计时器，保守不误杀；收到终态帧后守卫失效；正常 / 异常 / 消费方取消一律
/// 在 `finally` 取消计时器防泄漏）；无论正常 / 异常 / 消费方取消，`finally`
/// 强制关闭连接避免泄漏。
Stream<String> streamSse({
  required Uri uri,
  required String body,
  required Map<String, String> headers,
  required bool Function(SseFrame frame) isTerminated,
  required String? Function(SseFrame frame) extractToken,
  Exception? Function(SseFrame frame)? errorFrameException,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 60),
}) async* {
  final client = HttpClient()..connectionTimeout = connectTimeout;
  try {
    // 连接建立段（connect 相位）：postUrl → 写请求体 → close 等到响应头。
    // 本段任一传输失败均为连接建立阶段失败（未收到状态码、无生成副作用），
    // 统一收敛为 LLMConnectionInterruptedError。已收到状态码则走下方
    // HttpStatusError 分支（服务端已处理请求 → 不重试）。
    final HttpClientResponse response;
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(body);
      response = await request.close();
    } on SocketException catch (e) {
      throw LLMConnectionInterruptedError(originalError: e);
    } on HttpException catch (e) {
      throw LLMConnectionInterruptedError(originalError: e);
    }

    if (response.statusCode != HttpStatus.ok) {
      // 非 SSE 错误体（HTTP 状态码 + 原文），交状态码翻译。
      final errorBody = await utf8.decoder.bind(response).join();
      throw HttpStatusError(response.statusCode, errorBody);
    }

    var reachedTerminated = false;
    final parser = SseParser();
    // M6-09 idle timeout：流消费期帧间隔守卫。任何行到达（含注释帧）即重启
    // 计时器（dart:async Timer 无 reset，取消后重建）；到期强制关闭连接使
    // await-for 自然收束（EOF / 读异常均走下方断连判型收敛）；终态帧后守卫
    // 失效（防计时器误杀正常完成）；正常 / 异常 / 消费方取消一律 finally
    // 取消，避免泄漏 Timer。
    Timer? idleTimer;
    void armIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout, () {
        client.close(force: true);
      });
    }

    try {
      armIdleTimer();
      await for (final line
          in const LineSplitter().bind(utf8.decoder.bind(response))) {
        armIdleTimer();
        for (final frame in parser.feed(line)) {
          final error = errorFrameException?.call(frame);
          if (error != null) {
            throw error;
          }
          if (isTerminated(frame)) {
            reachedTerminated = true;
            idleTimer?.cancel();
            idleTimer = null; // 终态后守卫失效：后续行不再重启/触发计时器。
          }
          final token = extractToken(frame);
          if (token != null) {
            yield token;
          }
        }
      }
    } on SocketException catch (e) {
      throw LLMConnectionInterruptedError(originalError: e);
    } on HttpException catch (e) {
      throw LLMConnectionInterruptedError(originalError: e);
    } finally {
      idleTimer?.cancel();
    }
    // 流结束但未收到终态帧：可区分「连接中断」而非正常完成。
    if (!reachedTerminated) {
      throw LLMConnectionInterruptedError();
    }
  } finally {
    // 无论正常 / 异常 / 消费方取消，都强制关闭连接避免泄漏。
    client.close(force: true);
  }
}