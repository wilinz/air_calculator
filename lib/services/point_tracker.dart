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

import 'dart:ui';
import 'dart:math' as math;

/// 速度自适应平滑器（含死区抖动过滤）
class PointTracker {
  Offset? _lastPoint;
  Offset? _lastRawPoint;

  // 平滑系数范围（smoothFactor = old权重，越大越平滑但有滞后）
  final double _minSmooth; // 慢速时（高值=抑制抖动）
  final double _maxSmooth; // 快速时（低值=跟随灵敏）

  // 死区：移动距离小于此值时不更新位置，消除微抖动
  final double _deadZone;

  // 速度阈值
  static const double _speedLow = 5.0;
  static const double _speedHigh = 50.0;

  PointTracker({
    double minSmooth = 0.1,
    double maxSmooth = 0.5,
    double deadZone = 2.0,
  }) : _minSmooth = minSmooth,
       _maxSmooth = maxSmooth,
       _deadZone = deadZone;

  /// 更新并返回平滑后的点
  Offset update(Offset newPoint) {
    if (_lastPoint == null) {
      _lastPoint = newPoint;
      _lastRawPoint = newPoint;
      return newPoint;
    }

    // 计算原始速度（相对于上一帧原始点）
    final rawDx = newPoint.dx - _lastRawPoint!.dx;
    final rawDy = newPoint.dy - _lastRawPoint!.dy;
    final speed = math.sqrt(rawDx * rawDx + rawDy * rawDy);
    _lastRawPoint = newPoint;

    // 死区过滤：与上次平滑点距离过近则不更新
    final smoothDx = newPoint.dx - _lastPoint!.dx;
    final smoothDy = newPoint.dy - _lastPoint!.dy;
    final distToLast = math.sqrt(smoothDx * smoothDx + smoothDy * smoothDy);
    if (distToLast < _deadZone) return _lastPoint!;

    // 根据速度插值平滑系数
    double smoothFactor;
    if (speed <= _speedLow) {
      smoothFactor = _minSmooth;
    } else if (speed >= _speedHigh) {
      smoothFactor = _maxSmooth;
    } else {
      final t = (speed - _speedLow) / (_speedHigh - _speedLow);
      smoothFactor = _minSmooth + t * (_maxSmooth - _minSmooth);
    }

    // 指数移动平均：smoothed = smoothFactor*old + (1-smoothFactor)*new
    final smoothed = Offset(
      _lastPoint!.dx * smoothFactor + newPoint.dx * (1 - smoothFactor),
      _lastPoint!.dy * smoothFactor + newPoint.dy * (1 - smoothFactor),
    );

    _lastPoint = smoothed;
    return smoothed;
  }

  /// 重置
  void reset() {
    _lastPoint = null;
    _lastRawPoint = null;
  }

  /// 当前位置
  Offset? get position => _lastPoint;

  bool get isTracking => _lastPoint != null;
}
