import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../request_scheduler_config.dart';

/// 请求优先级
enum _Priority {
  high(0), // 用户写操作（POST/PUT/DELETE/PATCH）
  normal(1), // 普通 GET 请求
  low(2); // 静默请求（心跳、后台刷新）

  const _Priority(this.value);
  final int value;
}

/// 排队条目
class _RequestEntry {
  final RequestOptions options;
  final RequestInterceptorHandler handler;
  final _Priority priority;
  final int sequence; // 同优先级 FIFO
  final Completer<void> completer = Completer<void>();
  bool isCancelled = false;

  _RequestEntry({
    required this.options,
    required this.handler,
    required this.priority,
    required this.sequence,
  });
}

/// 基于 HeapPriorityQueue 的优先级队列
class _PriorityQueue {
  final _queue = HeapPriorityQueue<_RequestEntry>((a, b) {
    final cmp = a.priority.value.compareTo(b.priority.value);
    if (cmp != 0) return cmp;
    return a.sequence.compareTo(b.sequence);
  });

  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  int get length => _queue.length;

  void add(_RequestEntry entry) => _queue.add(entry);

  _RequestEntry removeFirst() => _queue.removeFirst();
}

/// 滑动窗口速率限制器
///
/// 动态读取 [RequestSchedulerConfig] 的配置值，
/// 用户修改设置后立即生效。
class _RateLimiter {
  final _timestamps = Queue<DateTime>();

  /// 驱逐过期时间戳
  void _evict(DateTime now) {
    final cutoff = now.subtract(
      Duration(seconds: RequestSchedulerConfig.windowSeconds),
    );
    while (_timestamps.isNotEmpty && _timestamps.first.isBefore(cutoff)) {
      _timestamps.removeFirst();
    }
  }

  /// 是否可以发出请求
  bool canProceed() {
    _evict(DateTime.now());
    return _timestamps.length < RequestSchedulerConfig.maxPerWindow;
  }

  /// 需要等待的时间（队列未满时返回 Duration.zero）
  Duration get waitDuration {
    final now = DateTime.now();
    _evict(now);
    if (_timestamps.length < RequestSchedulerConfig.maxPerWindow) {
      return Duration.zero;
    }
    // 最早的时间戳 + 窗口大小 - 当前时间
    return _timestamps.first
        .add(Duration(seconds: RequestSchedulerConfig.windowSeconds))
        .difference(now);
  }

  /// 记录一个请求发出
  void record() {
    _timestamps.add(DateTime.now());
  }
}

/// 请求调度拦截器
///
/// 替代 ConcurrencyInterceptor，增加：
/// - 优先级调度：用户操作 > 普通 GET > 后台静默请求
/// - 取消过时请求：排队中的请求被 cancelToken 取消时自动跳过
/// - 滑动窗口速率限制：防止密集请求触发服务端 429
///
/// 并发数和速率限制从 [RequestSchedulerConfig] 动态读取。
class RequestSchedulerInterceptor extends Interceptor {
  int _running = 0;
  int _sequence = 0;
  Timer? _pendingTimer;

  late final _PriorityQueue _queue = _PriorityQueue();
  late final _RateLimiter _rateLimiter = _RateLimiter();

  /// 推断请求优先级
  _Priority _inferPriority(RequestOptions options) {
    // 显式指定优先级
    final explicit = options.extra['priority'];
    if (explicit is String) {
      switch (explicit) {
        case 'high':
          return _Priority.high;
        case 'low':
          return _Priority.low;
        default:
          return _Priority.normal;
      }
    }

    // isSilent 标记 → low
    if (options.extra['isSilent'] == true) {
      return _Priority.low;
    }

    // 写操作 → high
    final method = options.method.toUpperCase();
    if (method == 'POST' ||
        method == 'PUT' ||
        method == 'DELETE' ||
        method == 'PATCH') {
      return _Priority.high;
    }

    // 其他 GET → normal
    return _Priority.normal;
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 内部请求（如 CSRF 刷新）跳过调度，避免与调用方死锁
    if (options.extra['skipScheduler'] == true) {
      handler.next(options);
      return;
    }

    final priority = _inferPriority(options);
    final maxConcurrent = RequestSchedulerConfig.maxConcurrent;

    // cancelToken 已取消，直接拒绝
    if (options.cancelToken?.isCancelled ?? false) {
      handler.reject(
        DioException.requestCancelled(
          requestOptions: options,
          reason: '请求在排队前已被取消',
        ),
        true,
      );
      return;
    }

    // 有空闲槽位且速率限制允许 → 直接放行
    if (_running < maxConcurrent && _rateLimiter.canProceed()) {
      _running++;
      _rateLimiter.record();
      options.extra['_schedulerCounted'] = true;
      handler.next(options);
      return;
    }

    // 排队等待
    final entry = _RequestEntry(
      options: options,
      handler: handler,
      priority: priority,
      sequence: _sequence++,
    );
    _queue.add(entry);

    // 注册 cancelToken 取消回调
    options.cancelToken?.whenCancel.then((_) {
      if (!entry.completer.isCompleted) {
        entry.isCancelled = true;
        entry.completer.complete();
      }
    });

    debugPrint(
      '[Scheduler] 排队: ${options.method} ${options.path} '
      '优先级=${priority.name} 队列长度=${_queue.length} 并发=$_running',
    );

    await entry.completer.future;

    // 被唤醒后检查是否已取消
    if (entry.isCancelled) {
      handler.reject(
        DioException.requestCancelled(
          requestOptions: options,
          reason: '请求在排队中被取消',
        ),
        true,
      );
      return;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.extra.remove('_schedulerCounted') == true) {
      _release();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.extra.remove('_schedulerCounted') == true) {
      _release();
    }
    handler.next(err);
  }

  void _release() {
    _running--;
    _scheduleNext();
  }

  void _scheduleNext() {
    final maxConcurrent = RequestSchedulerConfig.maxConcurrent;
    while (_queue.isNotEmpty && _running < maxConcurrent) {
      final entry = _queue.removeFirst();

      // 跳过已取消的 entry
      if (entry.isCancelled || entry.completer.isCompleted) {
        continue;
      }

      // 检查速率限制
      if (!_rateLimiter.canProceed()) {
        // 放回队列等速率窗口，设置 Timer 延迟重调度
        _queue.add(entry);
        _scheduleDelayed();
        return;
      }

      _running++;
      _rateLimiter.record();
      entry.options.extra['_schedulerCounted'] = true;
      entry.completer.complete();
    }
  }

  /// 用 Timer 延迟重调度，避免多个 Timer 同时存在
  void _scheduleDelayed() {
    if (_pendingTimer?.isActive ?? false) return;
    final wait = _rateLimiter.waitDuration;
    if (wait <= Duration.zero) {
      _scheduleNext();
      return;
    }
    _pendingTimer = Timer(wait, () {
      _pendingTimer = null;
      _scheduleNext();
    });
  }
}
