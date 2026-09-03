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

/// 端到端：真实模型 + 真实笔画，走完 open → recognize。
///
/// 需要先编好运行时并指过来：
///   cd air_calculator-rs && scripts/build_executorch.sh macos-arm64
///   export MWH_RUNTIME_DIR=$PWD/third_party/build/macos-arm64/install
///   dart test
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:aircalc_native/aircalc_native.dart';
import 'package:test/test.dart';

/// 模型目录：纯轨迹多签名导出产物。
final _modelDir = Directory(
  '${Directory.current.parent.parent.path}'
  '/experiments/2026-09-01_stroke_only_full_pipeline/export_ios_merged',
);

void main() {
  setUpAll(() {
    if (!_modelDir.existsSync()) {
      throw StateError('缺模型目录 ${_modelDir.path}');
    }
  });

  test('打开识别器并读出后端名', () async {
    final r = await _open();
    addTearDown(r.dispose);
    expect(r.backendName, 'executorch-coreml');
  });

  test('识别一条合成笔画', () async {
    final r = await _open();
    addTearDown(r.dispose);

    final out = await r.recognize([_syntheticStroke()]);

    // 合成笔画不是真实手写，不断言具体内容；这里验证的是整条链路能跑通、
    // 且各阶段耗时都被填上了。
    expect(out.tokenIds, isNotEmpty, reason: '至少应有 BOS');
    expect(out.encMs, greaterThan(0));
    expect(out.prefillMs, greaterThan(0));
    expect(out.totalMs, greaterThanOrEqualTo(out.encMs));
    printOnFailure('latex=${out.latex} tokens=${out.tokenIds.length}');
  });

  test('空输入不崩', () async {
    final r = await _open();
    addTearDown(r.dispose);
    final out = await r.recognize(const []);
    expect(out.tokenIds, isNotEmpty);
  });

  test('释放后再用会抛异常', () async {
    final r = await _open();
    await r.dispose();
    expect(() => r.recognize(const []), throwsA(isA<AircalcException>()));
  });

  test('重复释放安全', () async {
    final r = await _open();
    await r.dispose();
    await r.dispose();
    expect(r, isNotNull);
  });
}

Future<Recognizer> _open() => Recognizer.open(
      modelDir: _modelDir.path,
      vocabJson: File('${_modelDir.path}/vocab.json').readAsStringSync(),
      numThreads: 4,
    );

/// 画一段正弦曲线当笔画，点距与采样率接近真实书写。
Stroke _syntheticStroke() {
  const n = 64;
  return Stroke([
    for (var i = 0; i < n; i++)
      StrokePoint(
        i * 4.0,
        50 + 20 * math.sin(i * 0.2),
        i * 0.012,
      ),
  ]);
}
