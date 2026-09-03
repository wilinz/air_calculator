/// 常驻 worker isolate。
///
/// 识别是同步 FFI 调用：编码一次加几十步解码，跑在 UI isolate 上会明显
/// 卡顿。放到独立 isolate 上执行，UI 只等一个 Future。
///
/// 每次识别都 `Isolate.run` 也能达到目的，但那样每次都要新建并销毁一个
/// isolate；识别是连续触发的，常驻一个再排队更合适。
library;

import 'dart:async';
import 'dart:isolate';

import 'bindings.dart' as b;
import 'recognizer.dart';
import 'stroke.dart';

/// 一次识别请求。句柄跨 isolate 传的是整数——Rust 侧按它查表并加锁，
/// 失效句柄返回错误码而不是悬垂指针，这正是不用裸指针的原因。
class _Request {
  const _Request(this.handle, this.strokes);
  final int handle;
  final List<Stroke> strokes;
}

class _WorkerError {
  const _WorkerError(this.message, this.stack);
  final String message;
  final StackTrace stack;
}

class RecognizeWorker {
  RecognizeWorker._(this._isolate, this._commands, this._responses, this._exit) {
    _responses.listen(_onResponse);
    // isolate 若在没有回复的情况下死掉，每个调用方都会永远等下去；
    // close() 又要等这些 Future，于是连销毁都卡住。
    _exit.listen((_) => _failAll('识别 isolate 意外停止'));
  }

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _responses;

  /// isolate 因任何原因停止时收到通知，包括未捕获异常与内存不足。
  final ReceivePort _exit;

  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;
  var _closed = false;
  var _cleaned = false;

  static Future<RecognizeWorker> spawn() async {
    final setup = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      _entry,
      setup.sendPort,
      onExit: exit.sendPort,
      onError: exit.sendPort,
    );
    final responses = ReceivePort();
    final commands = await setup.first as SendPort;
    setup.close();
    commands.send(responses.sendPort);
    return RecognizeWorker._(isolate, commands, responses, exit);
  }

  bool get hasPending => _pending.isNotEmpty;

  Future<RecognitionResult> run(int handle, List<Stroke> strokes) {
    if (_closed) {
      throw StateError('aircalc: 识别器已释放');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commands.send((id, _Request(handle, strokes)));
    return completer.future.then((v) => v as RecognitionResult);
  }

  void _onResponse(dynamic message) {
    final (int id, Object? value) = message as (int, Object?);
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (value is _WorkerError) {
      completer.completeError(StateError(value.message), value.stack);
    } else {
      completer.complete(value);
    }
  }

  /// 把还没有答案的请求全部判错。
  ///
  /// 顺带关闭：已经停下的 isolate 也不会回应下一个请求，否则 run 会继续
  /// 派发没人完成的 Future，把这里要防的挂起原样搬到下一次。
  void _failAll(String why) {
    _closed = true;
    if (_pending.isEmpty) return;
    final waiting = _pending.values.toList(growable: false);
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.completeError(StateError('aircalc: $why'));
    }
  }

  /// 停止接活并等待正在执行的请求。
  ///
  /// 不立刻杀 isolate：它可能正处在一次原生调用里，此时释放识别器就是
  /// use-after-free；而那种调用也无法被打断。
  Future<void> close() async {
    if (_cleaned) return;
    _cleaned = true;
    _closed = true;
    if (_pending.isNotEmpty) {
      await Future.wait(
        _pending.values.map((c) => c.future.catchError((_) => null)),
      );
    }
    _responses.close();
    _exit.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _entry(SendPort setup) {
    final commands = ReceivePort();
    setup.send(commands.sendPort);
    late SendPort responses;
    var haveResponsePort = false;

    commands.listen((message) {
      if (!haveResponsePort) {
        responses = message as SendPort;
        haveResponsePort = true;
        return;
      }
      final (int id, _Request req) = message as (int, _Request);
      try {
        // 用句柄重建一个轻量包装：底层识别器是同一个，注册表按句柄查表。
        final r = Recognizer.fromHandle(req.handle);
        responses.send((id, r.recognizeSync(req.strokes)));
      } catch (e, st) {
        responses.send((id, _WorkerError('$e', st)));
      }
    });
  }
}

// 让 bindings 的符号在 worker isolate 里也被解析——native assets 是进程级的，
// 这行只是防止 tree shaking 把它裁掉。
// ignore: unused_element
final _keepBindings = b.ink_hmer_engine_backend_name;
