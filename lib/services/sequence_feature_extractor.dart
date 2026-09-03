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

import 'dart:math';

import '../models/gesture.dart';

/// 13 维特征向量（每个点）：
///   [0] x        归一化横坐标 [0,1]
///   [1] y        归一化纵坐标 [0,1]
///   [2] dx       横向位移增量
///   [3] dy       纵向位移增量
///   [4] dt       时间增量（秒）
///   [5] speed    瞬时速度 = |Δpos|/Δt
///   [6] sinθ     方向角正弦
///   [7] cosθ     方向角余弦
///   [8] κ        曲率 = Δθ/弧长
///   [9] arc_frac 累积弧长/总弧长 ∈ [0,1]
///  [10] pen_up   笔画切换标志（0=绘制中，1=抬笔过渡帧）
///  [11] h_ratio  笔画高度 / max(整体H, 整体W)
///  [12] w_ratio  笔画宽度 / max(整体H, 整体W)
const int featureDim = 13;

const double _penUpDt = 0.05; // 虚拟抬笔间隔（秒）

// 各特征的裁剪范围
const List<List<double>> _clipRanges = [
  [0.0, 1.0], // x
  [0.0, 1.0], // y
  [-1.0, 1.0], // dx
  [-1.0, 1.0], // dy
  [0.0, 2.0], // dt
  [0.0, 20.0], // speed
  [-1.0, 1.0], // sinθ
  [-1.0, 1.0], // cosθ
  [-50.0, 50.0], // κ
  [0.0, 1.0], // arc_frac
  [0.0, 1.0], // pen_up
  [0.0, 1.0], // h_ratio
  [0.0, 1.0], // w_ratio
];

/// 将 Stroke 列表转换为 (T, 13) 特征矩阵，port 自 air_calculator_py_v3/features.py
class SequenceFeatureExtractor {
  final int maxLen;

  const SequenceFeatureExtractor({this.maxLen = 256});

  /// 提取特征，返回形状 (T, 13) 的矩阵（List of List），T ≤ maxLen。
  List<List<double>> extract(List<Stroke> strokes) {
    if (strokes.isEmpty || strokes.every((s) => s.points.isEmpty)) {
      return [List.filled(featureDim, 0.0)];
    }

    // 1. 收集坐标与时间戳（时间戳从微秒转为秒）
    final rawCoords = [
      for (final s in strokes)
        [
          for (final p in s.points) [p.dx, p.dy],
        ],
    ];
    final rawTs = [
      for (final s in strokes) [for (final t in s.timestamps) t / 1e6],
    ];

    // 2. 整体归一化坐标，同时获取全局大小比例
    final (normalized, hRatio, wRatio) = _normalize(rawCoords);

    // 3. 展平为单一序列，插入 pen_up 过渡帧
    final (pts, ts, penUp) = _flatten(normalized, rawTs);

    // 4. 逐点计算前 11 维特征
    final feats = _computeFeatures(pts, ts, penUp);

    // 5. 填入全局大小特征（每个点相同）
    for (final row in feats) {
      row[11] = hRatio;
      row[12] = wRatio;
    }

    // 6. 裁剪数值范围
    for (int fi = 0; fi < featureDim; fi++) {
      final lo = _clipRanges[fi][0];
      final hi = _clipRanges[fi][1];
      for (final row in feats) {
        row[fi] = row[fi].clamp(lo, hi);
      }
    }

    // 7. 超长时等间隔下采样
    if (feats.length > maxLen) {
      final result = <List<double>>[];
      for (int i = 0; i < maxLen; i++) {
        final idx = ((feats.length - 1) * i / (maxLen - 1)).round();
        result.add(feats[idx]);
      }
      return result;
    }

    return feats;
  }

  // ---------------------------------------------------------------------------

  /// 坐标整体归一化到 [0,1]（等比缩放，居中），返回 (归一化坐标, h_ratio, w_ratio)
  static (List<List<List<double>>>, double, double) _normalize(
    List<List<List<double>>> strokes,
  ) {
    double xMin = double.infinity, xMax = double.negativeInfinity;
    double yMin = double.infinity, yMax = double.negativeInfinity;
    for (final s in strokes) {
      for (final p in s) {
        if (p[0] < xMin) xMin = p[0];
        if (p[0] > xMax) xMax = p[0];
        if (p[1] < yMin) yMin = p[1];
        if (p[1] > yMax) yMax = p[1];
      }
    }
    if (xMin.isInfinite) return (strokes, 0.0, 0.0);

    final span = max(max(xMax - xMin, yMax - yMin), 1e-9);
    final hRatio = (yMax - yMin) / span;
    final wRatio = (xMax - xMin) / span;
    final cx = (xMin + xMax) / 2;
    final cy = (yMin + yMax) / 2;

    final normed = [
      for (final s in strokes)
        [
          for (final p in s)
            [(p[0] - cx) / span + 0.5, (p[1] - cy) / span + 0.5],
        ],
    ];
    return (normed, hRatio, wRatio);
  }

  /// 展平多笔画，在非末尾笔画后插入 pen_up 过渡帧
  static (List<List<double>>, List<double>, List<int>) _flatten(
    List<List<List<double>>> strokes,
    List<List<double>> timestamps,
  ) {
    final pts = <List<double>>[];
    final ts = <double>[];
    final penUp = <int>[];

    for (int si = 0; si < strokes.length; si++) {
      final s = strokes[si];
      final tList = si < timestamps.length ? timestamps[si] : <double>[];
      if (s.isEmpty) continue;

      for (int i = 0; i < s.length; i++) {
        pts.add(s[i]);
        ts.add(i < tList.length ? tList[i] : 0.0);
        penUp.add(0);
      }

      if (si < strokes.length - 1) {
        pts.add(s.last);
        ts.add((tList.isNotEmpty ? tList.last : 0.0) + _penUpDt);
        penUp.add(1);
      }
    }

    return (pts, ts, penUp);
  }

  /// 逐点计算前 11 维特征（dims 11/12 由调用方填入）
  static List<List<double>> _computeFeatures(
    List<List<double>> pts,
    List<double> ts,
    List<int> penUp,
  ) {
    final n = pts.length;
    final feat = List.generate(n, (_) => List.filled(featureDim, 0.0));

    // 预计算累积弧长
    final arcs = List.filled(n, 0.0);
    for (int i = 1; i < n; i++) {
      final ddx = pts[i][0] - pts[i - 1][0];
      final ddy = pts[i][1] - pts[i - 1][1];
      arcs[i] = arcs[i - 1] + sqrt(ddx * ddx + ddy * ddy);
    }
    final totalArc = max(arcs[n - 1], 1e-9);

    double prevDir = 0.0;
    for (int i = 0; i < n; i++) {
      final x = pts[i][0];
      final y = pts[i][1];
      final t = ts[i];

      double dx = 0, dy = 0, dt = 0;
      if (i > 0) {
        dx = x - pts[i - 1][0];
        dy = y - pts[i - 1][1];
        dt = max(t - ts[i - 1], 1e-6);
      }

      final dist = sqrt(dx * dx + dy * dy);
      final speed = dt > 1e-6 ? dist / dt : 0.0;
      final curDir = dist > 1e-6 ? atan2(dy, dx) : prevDir;

      double curv = 0.0;
      if (i > 0 && dist > 1e-6) {
        var ddir = (curDir - prevDir + pi) % (2 * pi) - pi;
        curv = ddir / dist;
      }

      prevDir = curDir;

      feat[i][0] = x;
      feat[i][1] = y;
      feat[i][2] = dx;
      feat[i][3] = dy;
      feat[i][4] = dt;
      feat[i][5] = speed;
      feat[i][6] = sin(curDir);
      feat[i][7] = cos(curDir);
      feat[i][8] = curv;
      feat[i][9] = arcs[i] / totalArc;
      feat[i][10] = penUp[i].toDouble();
      // [11] h_ratio, [12] w_ratio 由 extract() 填入
    }

    return feat;
  }
}
