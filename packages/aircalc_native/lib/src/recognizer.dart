/// 识别器：C ABI 之上的一层 Dart 封装。
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.dart' as b;
import 'stroke.dart';
import 'worker.dart';

/// 推理后端。默认按平台自动选择。
enum MwhBackend {
  /// 平台默认：iOS/macOS 走裸 Core ML，Android 走 LiteRT。
  auto(0),
  litert(1),
  /// 2 曾是 ExecuTorch，已整体移除；号不复用。
  coreml(3);

  const MwhBackend(this.value);
  final int value;
}

/// 识别失败。`code` 是 C ABI 的错误码（AIRCALC_ERR_*）。
class AircalcException implements Exception {
  AircalcException(this.message, this.code);

  final String message;
  final int code;

  @override
  String toString() => 'AircalcException($code): $message';
}

/// 一次识别的结果与逐阶段耗时。
class RecognitionResult {
  const RecognitionResult({
    required this.latex,
    required this.tokenIds,
    required this.encMs,
    required this.prefillMs,
    required this.decodeMs,
    required this.totalMs,
  });

  final String latex;
  final List<int> tokenIds;

  /// 前缀编码耗时，毫秒。
  final double encMs;

  /// KV Cache 预填充耗时，毫秒。
  final double prefillMs;

  /// 逐 token 解码总耗时，毫秒。
  final double decodeMs;

  final double totalMs;
}

/// 识别器。用完请调 [dispose]。
///
/// 句柄在 Rust 侧是不透明整数，配对一张带锁的注册表：Dart、Swift 与 JNI
/// 三条调用路径共享同一把锁，天然串行化；句柄失效后查表落空返回错误码，
/// 不会像悬垂指针那样直接崩。
class Recognizer {
  Recognizer._(this._handle, this._worker);

  /// 从已有句柄构造一个轻量包装，不持有 worker。
  ///
  /// 供 worker isolate 内部使用：底层识别器是同一个，句柄只是注册表的键。
  /// 句柄跨 isolate 传递安全——它是整数，Rust 侧按它查表并加锁，失效句柄
  /// 返回错误码而不是悬垂指针。
  Recognizer.fromHandle(this._handle) : _worker = null;

  int _handle;
  final RecognizeWorker? _worker;

  /// 打开一个识别器。
  ///
  /// [modelDir] 模型目录，各后端按自己的命名约定在其中找文件。
  /// [vocabJson] `vocab.json` 的完整内容。
  /// [numThreads] CPU 线程数；0 用后端默认。Android 走 XNNPACK 时建议
  /// 显式设 4，避开大小核架构的调度拖累。
  /// 打开一个识别器，并起一个常驻 worker isolate 承载推理。
  ///
  /// 识别是同步 FFI 调用，跑在 UI isolate 上会卡顿，所以默认走 worker；
  /// 需要在当前 isolate 上同步执行时用 [recognizeSync]。
  static Future<Recognizer> open({
    required String modelDir,
    required String vocabJson,
    MwhBackend backend = MwhBackend.auto,
    int numThreads = 0,
  }) async {
    final handle = _create(modelDir, vocabJson, backend, numThreads);
    try {
      return Recognizer._(handle, await RecognizeWorker.spawn());
    } catch (_) {
      b.ink_hmer_engine_destroy(handle);
      rethrow;
    }
  }

  static int _create(
    String modelDir,
    String vocabJson,
    MwhBackend backend,
    int numThreads,
  ) {
    final dirPtr = modelDir.toNativeUtf8();
    final vocabPtr = vocabJson.toNativeUtf8();
    final errPtr = calloc<ffi.Int32>();
    try {
      final h = b.ink_hmer_engine_create(
        dirPtr.cast(),
        vocabPtr.cast(),
        backend.value,
        numThreads,
        errPtr,
      );
      if (h == 0) {
        throw AircalcException('识别器创建失败（模型目录 $modelDir）', errPtr.value);
      }
      return h;
    } finally {
      calloc.free(dirPtr);
      calloc.free(vocabPtr);
      calloc.free(errPtr);
    }
  }

  /// 后端名，用于日志与基准报告。
  String get backendName {
    _ensureOpen();
    final p = b.ink_hmer_engine_backend_name(_handle);
    return p == ffi.nullptr ? 'unknown' : p.cast<Utf8>().toDartString();
  }

  /// 识别一组笔画。在 worker isolate 上执行，不阻塞调用方。
  Future<RecognitionResult> recognize(List<Stroke> strokes) {
    _ensureOpen();
    final w = _worker;
    if (w == null) {
      // fromHandle 构造出来的包装没有 worker（它本身就在 worker 里）。
      return Future.value(recognizeSync(strokes));
    }
    return w.run(_handle, strokes);
  }

  /// 在当前 isolate 上同步识别。会阻塞调用方，UI 线程上慎用。
  RecognitionResult recognizeSync(List<Stroke> strokes) {
    _ensureOpen();

    final live = strokes.where((s) => !s.isEmpty).toList(growable: false);
    final strokeArr = calloc<b.InkHmerStroke>(live.isEmpty ? 1 : live.length);
    final pointBufs = <ffi.Pointer<b.InkHmerPoint>>[];
    final out = calloc<b.InkHmerResult>();

    try {
      for (var i = 0; i < live.length; i++) {
        final pts = live[i].points;
        final buf = calloc<b.InkHmerPoint>(pts.length);
        pointBufs.add(buf);
        for (var j = 0; j < pts.length; j++) {
          buf[j]
            ..x = pts[j].x
            ..y = pts[j].y
            ..t = pts[j].t;
        }
        strokeArr[i]
          ..points = buf
          ..count = pts.length;
      }

      final rc = b.ink_hmer_recognize(_handle, strokeArr, live.length, out);
      if (rc != 0) {
        throw AircalcException('识别失败', rc);
      }

      final r = out.ref;
      final latex =
          r.latex == ffi.nullptr ? '' : r.latex.cast<Utf8>().toDartString();
      final ids = <int>[
        for (var i = 0; i < r.token_count; i++) r.token_ids[i],
      ];
      return RecognitionResult(
        latex: latex,
        tokenIds: ids,
        encMs: r.enc_ms,
        prefillMs: r.prefill_ms,
        decodeMs: r.decode_ms,
        totalMs: r.total_ms,
      );
    } finally {
      b.ink_hmer_result_free(out);
      calloc.free(out);
      for (final p in pointBufs) {
        calloc.free(p);
      }
      calloc.free(strokeArr);
    }
  }

  /// 释放识别器。重复调用安全。
  ///
  /// 先等 worker 把手上的请求做完再销毁——那些请求正拿着这个句柄，
  /// 中途释放就是 use-after-free。
  Future<void> dispose() async {
    if (_handle == 0) return;
    await _worker?.close();
    b.ink_hmer_engine_destroy(_handle);
    _handle = 0;
  }

  void _ensureOpen() {
    if (_handle == 0) {
      throw AircalcException('识别器已释放', -1);
    }
  }
}

