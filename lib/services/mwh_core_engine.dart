// Copyright 2026 wilinz.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aircalc_native/aircalc_native.dart' as mwh;

import '../models/gesture.dart';
import '../utils/latex_text.dart';

/// 引擎单次推理的原始结果（未后处理）。
class EngineInferenceResult {
  /// token id 序列（含 BOS 作为首 token）
  final List<int> tokenIds;
  final int encMs;
  final int prefillMs;
  final int decMs;

  const EngineInferenceResult({
    required this.tokenIds,
    required this.encMs,
    required this.prefillMs,
    required this.decMs,
  });

  /// 将 token id 转为原始字符串（skip BOS + special tokens）。
  String toRawString(List<String> vocab, int specialN) {
    final sb = StringBuffer();
    // 上一个写进去的 token。token 首尾相接时，`\pi` 后面跟 `e` 会粘成
    // `\pie` 这个不存在的命令，渲染和求值一起失败——按需补空格。
    String prev = '';
    for (int i = 1; i < tokenIds.length; i++) {
      final id = tokenIds[i];
      if (id < specialN || id >= vocab.length) continue;
      final tok = vocab[id];
      if (latexNeedsSeparator(prev, tok)) sb.write(' ');
      sb.write(tok);
      prev = tok;
    }
    return sb.toString();
  }
}

/// 走 aircalc 原生核心的推理引擎。
///
/// 替代原先的 MwhLiteRtEngine 与 MwhExecuTorchEngine：那两份 Dart 实现里
/// 各有一套几乎相同的特征提取与解码循环，现在都下沉到 Rust，两端差异由
/// 核心库内部的 Engine 抽象抹平。
///
/// 一次识别只跨一次 FFI 边界——解码的每一步不再往返 Dart。
class MwhCoreEngine {
  mwh.Recognizer? _recognizer;
  List<String> _vocab = const [];
  int _bos = 1;
  int _eos = 2;
  Int32List _varBias = Int32List(0);

  /// 模型目录。各后端按自己的命名约定在其中找文件。
  final String modelDir;

  /// CPU 线程数；0 用后端默认。Android 走 XNNPACK 时建议设 4，
  /// 避开大小核架构的调度拖累——这是原插件不暴露、因而拿不到的开关。
  final int numThreads;

  MwhCoreEngine({required this.modelDir, this.numThreads = 4});

  /// 核心库实际选中的后端（`coreml` / `litert-xnnpack`）。
  /// 由 Rust 侧的 Engine::backend_name 报上来，不是这边猜的。
  String get backendName => _recognizer?.backendName ?? 'uninitialized';

  /// 需要落到磁盘的模型 asset：prefix_enc 单方法，decoder 多方法
  /// （prefill + step 共享权重，比拆成两个文件省一份副本）。
  ///
  /// 后缀按平台分：Android 走 LiteRT 要 `.tflite`；iOS/macOS 走裸 Core ML，
  /// 要 `.pte`。文件由 tool/copy_platform_models.sh 从 platform_models/<平台>
  /// 拷进 assets/models/，同一时刻只有一套在那儿。
  static List<String> get modelAssets {
    final ext = Platform.isAndroid ? 'tflite' : 'pte';
    return ['assets/models/prefix_enc.$ext', 'assets/models/decoder.$ext'];
  }

  static const vocabAsset = 'assets/models/vocab.json';

  @override
  List<String> get vocab => _vocab;

  @override
  int get bosIdx => _bos;

  @override
  int get eosIdx => _eos;

  @override
  Int32List get varBiasArr => _varBias;

  @override
  bool get isReady => _recognizer != null;

  @override
  Future<bool> init({
    required String vocabJson,
    String? encoderPath,
    String? decoderPath,
    int? backendIndex,
  }) async {
    try {
      _parseVocab(vocabJson);
      _recognizer = await mwh.Recognizer.open(
        modelDir: modelDir,
        vocabJson: vocabJson,
        numThreads: numThreads,
      );
      return true;
    } catch (e) {
      // 打开失败不抛给调用方——上层据 isReady 判断，与原实现一致。
      // ignore: avoid_print
      print('[mwh] 引擎初始化失败: $e');
      return false;
    }
  }

  void _parseVocab(String json) {
    // 词表结构固定，沿用原实现的解析方式。
    final meta = jsonDecode(json) as Map<String, dynamic>;
    _vocab = List<String>.from(meta['tokens'] as List);
    _bos = meta['bos_idx'] as int;
    _eos = meta['eos_idx'] as int;

    const algebraicVars = {
      'b', 'd', 'f', 'h', 'j', 'k', 'm', 'q', 'r', 'u', 'v', 'w', 'y', 'z',
      'B', 'D', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R',
      'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
    };
    _varBias = Int32List.fromList([
      for (int i = 0; i < _vocab.length; i++)
        if (algebraicVars.contains(_vocab[i])) i,
    ]);
  }

  @override
  Future<EngineInferenceResult?> recognize(
    List<Stroke> strokes,
    Size canvasSize,
  ) =>
      benchmark(strokes, canvasSize);

  @override
  Future<EngineInferenceResult?> benchmark(
    List<Stroke> strokes,
    Size canvasSize, {
    bool applyVarBias = true,
  }) async {
    final r = _recognizer;
    if (r == null) return null;

    final out = await r.recognize([
      for (final s in strokes)
        mwh.Stroke([
          for (int i = 0; i < s.points.length; i++)
            mwh.StrokePoint(
              s.points[i].dx,
              s.points[i].dy,
              // 时间戳在 Rust 侧按秒使用；这里的原始值是微秒。
              i < s.timestamps.length ? s.timestamps[i] / 1e6 : 0.0,
            ),
        ]),
    ]);

    return EngineInferenceResult(
      tokenIds: out.tokenIds,
      encMs: out.encMs.round(),
      prefillMs: out.prefillMs.round(),
      decMs: out.decodeMs.round(),
    );
  }

  @override
  Future<void> warmUp() async {
    final r = _recognizer;
    if (r == null || _warmedUp) return;
    _warmedUp = true;

    // Core ML 的模型编译发生在首次执行、而非加载时：第一次跑会有几百毫秒
    // 的编译开销，编译结果随后进系统缓存。不预热的话这笔开销会落在用户
    // 写完第一个公式的时候。
    //
    // 用一条合成笔画跑一次完整流程，把 prefix_enc / prefill / step 三个
    // 方法都触发到——它们各自对应一个 Core ML 模型，只跑其中一个不够。
    try {
      final sw = Stopwatch()..start();
      await r.recognize([
        mwh.Stroke([
          for (var i = 0; i < 32; i++)
            mwh.StrokePoint(i * 4.0, 50 + 20 * math.sin(i * 0.2), i * 0.012),
        ]),
      ]);
      // ignore: avoid_print
      print('[mwh] 预热完成 ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      // 预热失败不影响正常使用，下次识别会自己编译。
      // ignore: avoid_print
      print('[mwh] 预热失败: $e');
    }
  }

  bool _warmedUp = false;

  @override
  void dispose() {
    // 释放要等 worker 把手上的请求做完，这里不阻塞调用方。
    _recognizer?.dispose();
    _recognizer = null;
  }
}
