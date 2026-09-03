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

/// 笔画输入类型。
library;

/// 一个采样点。
class StrokePoint {
  const StrokePoint(this.x, this.y, this.t);

  final double x;
  final double y;

  /// 时间戳，单位秒。特征里的速度与曲率依赖它，缺失时按 0 处理。
  final double t;
}

/// 一条笔画，即一次落笔到抬笔之间的点序列。
class Stroke {
  const Stroke(this.points);

  final List<StrokePoint> points;

  bool get isEmpty => points.isEmpty;
}
