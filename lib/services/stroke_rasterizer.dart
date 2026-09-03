import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// PIL ImageDraw.line(width=2) 的逐行翻译（src/libImaging/Draw.c）。
///
/// 与 Python `renderer.py` 像素级一致（100/100 样本验证通过）。
class StrokeRasterizer {
  static const int imgH = 64;
  static const int imgW = 256;
  static const double lineWidth = 2.0;
  static const double stretchLimit = 2.5;

  /// 渲染笔画列表为灰度图像 [Float32List]，shape (imgH * imgW)，0=背景 1=笔迹。
  static Float32List render(List<ui.Offset> points) {
    final output = Float32List(imgH * imgW);

    if (points.isEmpty) return output;

    double xMin = double.infinity, xMax = double.negativeInfinity;
    double yMin = double.infinity, yMax = double.negativeInfinity;
    for (final p in points) {
      if (p.dx < xMin) xMin = p.dx;
      if (p.dx > xMax) xMax = p.dx;
      if (p.dy < yMin) yMin = p.dy;
      if (p.dy > yMax) yMax = p.dy;
    }

    const margin = lineWidth + 3;
    final xRange = max(xMax - xMin, 1e-6);
    final yRange = max(yMax - yMin, 1e-6);

    final baseScale = min(
      (imgW - 2 * margin) / xRange,
      (imgH - 2 * margin) / yRange,
    );
    final xScale = min((imgW - 2 * margin) / xRange, baseScale * stretchLimit);
    final yScale = min((imgH - 2 * margin) / yRange, baseScale * stretchLimit);
    final xOff = (imgW - xRange * xScale) / 2;
    final yOff = (imgH - yRange * yScale) / 2;

    int mapX(double x) => ((x - xMin) * xScale + xOff).truncate();
    int mapY(double y) => ((y - yMin) * yScale + yOff).truncate();

    _rasterize(output, points, mapX, mapY);

    return output;
  }

  // ── PIL Draw.c 核心光栅化 ────────────────────────────────────────

  static int _roundUp(double f) =>
      (f >= 0 ? (f + 0.5).floor() : -(f.abs() + 0.5).floor());
  static int _roundDown(double f) =>
      (f >= 0 ? (f - 0.5).ceil() : -(f.abs() - 0.5).ceil());
  static int _roundf(double f) => f.round();

  static void _hline(Float32List buf, int x0, int y, int x1) {
    if (y < 0 || y >= imgH) return;
    if (x0 > x1) { final t = x0; x0 = x1; x1 = t; }
    if (x1 < 0 || x0 >= imgW) return;
    if (x0 < 0) x0 = 0;
    if (x1 >= imgW) x1 = imgW - 1;
    final base = y * imgW;
    for (int x = x0; x <= x1; x++) {
      buf[base + x] = 1.0;
    }
  }

  static void _point(Float32List buf, int x, int y) {
    if (x >= 0 && x < imgW && y >= 0 && y < imgH) {
      buf[y * imgW + x] = 1.0;
    }
  }

  // ── polygon_generic（Draw.c 逐行翻译） ────────────────────────────

  static final _eYmin = Int32List(16), _eYmax = Int32List(16);
  static final _eXmin = Int32List(16), _eXmax = Int32List(16);
  static final _eX0 = Float64List(16), _eY0 = Int32List(16);
  static final _eD = Int32List(16), _eDx = Float64List(16);

  static void _fillPolygon(
      Float32List buf, List<List<int>> verts) {
    final n = verts.length;
    int ec = 0;
    for (int i = 0; i < n; i++) {
      final ax = verts[i][0], ay = verts[i][1];
      final bx = verts[(i + 1) % n][0], by = verts[(i + 1) % n][1];
      if (ay <= by) { _eYmin[ec] = ay; _eYmax[ec] = by; }
      else          { _eYmin[ec] = by; _eYmax[ec] = ay; }
      if (ax <= bx) { _eXmin[ec] = ax; _eXmax[ec] = bx; }
      else          { _eXmin[ec] = bx; _eXmax[ec] = ax; }
      if (_eYmin[ec] == _eYmax[ec]) {
        _hline(buf, _eXmin[ec], _eYmin[ec], _eXmax[ec]);
        continue;
      }
      _eX0[ec] = ax.toDouble();
      _eY0[ec] = ay;
      _eD[ec] = ay < by ? 1 : -1;
      _eDx[ec] = (bx - ax) / (by - ay).toDouble();
      ec++;
    }
    if (ec == 0) return;

    int pYMin = 1000000, pYMax = -1000000;
    for (int i = 0; i < ec; i++) {
      if (_eYmin[i] < pYMin) pYMin = _eYmin[i];
      if (_eYmax[i] > pYMax) pYMax = _eYmax[i];
    }
    if (pYMin < 0) pYMin = 0;
    if (pYMax >= imgH) pYMax = imgH - 1;

    final xx = <double>[];
    for (int y = pYMin; y <= pYMax; y++) {
      xx.clear();
      for (int i = 0; i < ec; i++) {
        if (y < _eYmin[i] || y > _eYmax[i]) continue;
        xx.add((y - _eY0[i]) * _eDx[i] + _eX0[i]);

        if (y == _eYmax[i] && y < pYMax) {
          xx.add(xx.last);
        } else if ((y == _eYmin[i] || y == _eYmax[i]) && _eDx[i] != 0) {
          for (int k = 0; k < i; k++) {
            if ((y != _eYmin[k] && y != _eYmax[k]) || _eDx[k] == 0) continue;
            if (_roundf(xx.last) !=
                _roundf((y - _eY0[k]) * _eDx[k] + _eX0[k])) continue;
            int offset = (y == _eYmax[i]) ? -1 : 1;
            double adjXi = (y + offset - _eY0[i]) * _eDx[i] + _eX0[i];
            if (y + offset >= _eYmin[k] && y + offset <= _eYmax[k]) {
              double adjXk = (y + offset - _eY0[k]) * _eDx[k] + _eX0[k];
              if (xx.last > adjXi + 1 && xx.last > adjXk + 1) {
                xx.last =
                    _roundf(adjXi > adjXk ? adjXi : adjXk).toDouble() + 1;
              } else if (xx.last < adjXi - 1 && xx.last < adjXk - 1) {
                xx.last =
                    _roundf(adjXi < adjXk ? adjXi : adjXk).toDouble() - 1;
              }
              break;
            }
          }
        }
      }
      xx.sort();
      for (int i = 1; i < xx.length; i += 2) {
        final xa = _roundUp(xx[i - 1]);
        final xb = _roundDown(xx[i]);
        if (xa <= xb) _hline(buf, xa, y, xb);
      }
    }
  }

  static void _wideLine(
      Float32List buf, int x0, int y0, int x1, int y1) {
    final dx = x1 - x0;
    final dy = y1 - y0;
    if (dx == 0 && dy == 0) {
      _point(buf, x0, y0);
      return;
    }
    final hyp = sqrt((dx * dx + dy * dy).toDouble());
    final dxmax = _roundDown(dy / hyp);
    final dymax = _roundDown(dx / hyp);
    _fillPolygon(buf, [
      [x0, y0 + dymax],
      [x1, y1 + dymax],
      [x1 + dxmax, y1],
      [x0 + dxmax, y0],
    ]);
  }

  static void _drawDot(Float32List buf, int cx, int cy) {
    _point(buf, cx, cy);
    _point(buf, cx - 1, cy);
    _point(buf, cx + 1, cy);
    _point(buf, cx, cy - 1);
    _point(buf, cx, cy + 1);
  }

  static void _rasterize(
    Float32List buf,
    List<ui.Offset> points,
    int Function(double) mapX,
    int Function(double) mapY,
  ) {
    int prevX = mapX(points[0].dx);
    int prevY = mapY(points[0].dy);
    if (points.length == 1) {
      _drawDot(buf, prevX, prevY);
      return;
    }
    for (int i = 1; i < points.length; i++) {
      final cx = mapX(points[i].dx);
      final cy = mapY(points[i].dy);
      _wideLine(buf, prevX, prevY, cx, cy);
      prevX = cx;
      prevY = cy;
    }
  }
}
