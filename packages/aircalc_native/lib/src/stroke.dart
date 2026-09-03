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
