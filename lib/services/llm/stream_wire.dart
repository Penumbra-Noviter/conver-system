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
///   [ReadPhaseInterruptedError]，区分「连接中断」而非正常完成）；
/// - [extractToken]：帧 → token（`null` = 该帧无内容）；
/// - [errorFrameException]：流内错误帧工厂（claude 的 `event=='error'`
///   → 抛 provider 私有异常；openai 无此语义传 `null`）；
/// - [connectTimeout]：连接超时（缺省 10s）；
/// - [idleTimeout]：流消费期（终态前）的帧间隔守卫（缺省 60s，弱网假活连接
///   断线保障）；
/// - [terminalTimeout]：终态守卫（缺省 2s）——终态帧已收但连接未关且无新帧
///   （假活连接）时强制关闭使 await-for 自然收束，见下「**终态守卫**」。
///
/// 骨架统一兜底按**相位**编码（AR-1 相位契约，errors.dart 两叶子）：
/// - **连接相位 (connect phase)**：连接建立段的传输失败（DNS / 拒连 / 连接
///   超时 / 响应头前断）未收到状态码、确定未产生服务端生成 → 收敛为
///   [ConnectPhaseInterruptedError]（服务层聊链条链据此编排连接阶段自动重试，
///   与流中途断连判型同构）；已收到状态码非 200 → [HttpStatusError]（携原文
///   交状态码翻译，不重试）；
/// - **读取相位 (read phase)**：已收响应头后读 SSE 段期间的失败——流中段
///   `SocketException` / `HttpException` / EOF 未收终态帧 → 收敛为
///   [ReadPhaseInterruptedError]（不可重试）。
///
/// **idle timeout**：流消费期（终态前）超过 [idleTimeout] 无任何字节行到达 →
/// 强制关闭连接使 await-for 自然收束 → 抛 [ReadPhaseInterruptedError]（此时状态码
/// 必已收到，属读取相位、不可重试）。机制：任何行——含 `: ping` 注释帧——到达即
/// 重置计时器，保守不误杀；终态帧后该守卫**不再参与**（见下「**终态守卫**」分工），
/// 正常 / 异常 / 消费方取消一律在 `finally` 取消计时器防泄漏。
///
/// **终态守卫（F-56 假活终态化）**：终态帧已到（[isTerminated] 命中）但服务端
/// 不关连接、后续也无任何帧（假活）时，await-for 将永不 EOF、流永不收束 → 回合
/// 永不终态化。守卫在收到终态帧时启动 [terminalTimeout] 计时器；终态后任何新帧
/// （尾随事件帧）到达即复位（不误杀仍活跃的上游）；到期无新帧 → 强制关闭连接
/// 使 await-for 自然收束——此时 [reachedTerminated] 已置位 → **正常完成**（不抛
/// 断流、不触发重试路径，仅补「终态后连接不关」的假活缺口）。服务端自然关闭
/// （正常路径）→ EOF 先于守卫到期，守卫在 `finally` 取消、不触发。
///
/// **两机制分工**：idle timeout 只跑在终态前（读阶段静默断线）；终态守卫只跑在
/// 终态后（终态后无新帧收束）——不重叠、各自计时器独立防泄漏。无论正常 / 异常 /
/// 消费方取消，`finally` 强制关闭连接避免泄漏。
Stream<String> streamSse({
  required Uri uri,
  required String body,
  required Map<String, String> headers,
  required bool Function(SseFrame frame) isTerminated,
  required String? Function(SseFrame frame) extractToken,
  Exception? Function(SseFrame frame)? errorFrameException,
  Duration connectTimeout = const Duration(seconds: 10),
  Duration idleTimeout = const Duration(seconds: 60),
  Duration terminalTimeout = const Duration(seconds: 2),
}) async* {
  final client = HttpClient()..connectionTimeout = connectTimeout;
  try {
    // 连接建立段（连接相位 connect phase）：postUrl → 写请求体 → close 等到
    // 响应头。本段任一传输失败均为连接建立阶段失败（未收到状态码、确定无生成
    // 副作用），统一收敛为 [ConnectPhaseInterruptedError]（服务层自动重试的
    // 唯一可重试面）。已收到状态码则走下方 HttpStatusError 分支（服务端已处理
    // 请求 → 不重试）。
    final HttpClientResponse response;
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.write(body);
      response = await request.close();
    } on SocketException catch (e) {
      throw ConnectPhaseInterruptedError(originalError: e);
    } on HttpException catch (e) {
      throw ConnectPhaseInterruptedError(originalError: e);
    }

    if (response.statusCode != HttpStatus.ok) {
      // 非 SSE 错误体（HTTP 状态码 + 原文），交状态码翻译。
      final errorBody = await utf8.decoder.bind(response).join();
      throw HttpStatusError(response.statusCode, errorBody);
    }

    var reachedTerminated = false;
    final parser = SseParser();
    // M6-09 idle timeout（终态前）：流消费期帧间隔守卫。任何行到达（含注释帧）
    // 即重启计时器（dart:async Timer 无 reset，取消后重建）；到期强制关闭连接使
    // await-for 自然收束（EOF / 读异常均走下方读取相位断连判型收敛）；正常 / 异常 /
    // 消费方取消一律 finally 取消，避免泄漏 Timer。
    Timer? idleTimer;
    void armIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(idleTimeout, () {
        client.close(force: true);
      });
    }

    // F-56 终态守卫（终态后）：收到终态帧后启动短守卫，任何尾随行到达即复位；
    // 到期无新帧 → force-close 使 await-for 自然收束（reachedTerminated 已置位 →
    // 正常完成，不抛断流、不触发重试）。只跑在终态后——与 idle timeout（终态前）
    // 分工不重叠；同一 finally 防泄漏。
    Timer? terminalGuard;
    void armTerminalGuard() {
      terminalGuard?.cancel();
      terminalGuard = Timer(terminalTimeout, () {
        client.close(force: true);
      });
    }

    try {
      armIdleTimer();
      await for (final line
          in const LineSplitter().bind(utf8.decoder.bind(response))) {
        if (reachedTerminated) {
          // 终态后：只复位终态守卫（idle 不再参与——两机制分工不重叠）。
          armTerminalGuard();
        } else {
          // 终态前：每行迭代顶部无条件重建 idle 计时器（任何行即活跃）。
          armIdleTimer();
        }
        for (final frame in parser.feed(line)) {
          final error = errorFrameException?.call(frame);
          if (error != null) {
            throw error;
          }
          if (isTerminated(frame)) {
            reachedTerminated = true;
            // idle 收尾（终态前守卫使命结束），终态守卫接力（F-56）。
            idleTimer?.cancel();
            idleTimer = null;
            armTerminalGuard();
          }
          final token = extractToken(frame);
          if (token != null) {
            yield token;
          }
        }
      }
    } on SocketException catch (e) {
      // 读取相位（read phase）：已收响应头后读 SSE 段传输失败。
      throw ReadPhaseInterruptedError(originalError: e);
    } on HttpException catch (e) {
      throw ReadPhaseInterruptedError(originalError: e);
    } finally {
      idleTimer?.cancel();
      terminalGuard?.cancel();
    }
    // 流结束但未收到终态帧：读取相位（read phase）的「非终态 EOF」——
    // 可区分「连接中断」而非正常完成（不可重试）。
    if (!reachedTerminated) {
      throw ReadPhaseInterruptedError();
    }
  } finally {
    // 无论正常 / 异常 / 消费方取消，都强制关闭连接避免泄漏。
    client.close(force: true);
  }
}