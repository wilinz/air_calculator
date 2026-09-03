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

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 空中悬停点击交互。
///
/// 使用方式：
///   1. 顶层放 [AirClickOverlay]，传入指针位置 ValueNotifier
///   2. 想可点的按钮包一层 [AirClickable]
///   3. 绘制中要禁止点击：通过 [AirClickController.setEnabled] 切换
///
/// 状态机：
///   IDLE → HOVERING(600ms 蓄力) → CLICKED(冷却 500ms) → IDLE
///   离开按钮（含 8px 死区）→ IDLE，倒计时取消
class AirClickController {
  AirClickController({
    this.dwellDuration = const Duration(milliseconds: 600),
    this.cooldownDuration = const Duration(milliseconds: 500),
    this.deadZonePx = 8.0,
    this.expandHitboxPx = 12.0,
  });

  final Duration dwellDuration;
  final Duration cooldownDuration;
  final double deadZonePx;
  final double expandHitboxPx;

  // 注册的所有可点区域（按钮 id → 矩形 + 回调）
  final Map<String, _AirTarget> _targets = {};

  // 当前正在悬停的按钮 id；null 表示未在任何按钮上
  String? _currentId;
  // 蓄力开始时间（用于计算 progress）
  DateTime? _dwellStart;
  // 冷却结束时间
  DateTime? _cooldownUntil;

  // 全局开关（绘制中关掉）
  bool _enabled = true;

  // 白名单：非空时只允许命中其中的 id；null 表示不限制
  Set<String>? _allowedIds;

  void setAllowedIds(Set<String>? ids) {
    if (_allowedIds == ids) return;
    _allowedIds = ids;
    _cancel();
  }

  /// 已注册的可点目标数量（调试用）
  int get targetCount => _targets.length;

  // 当前 hover 状态（含 progress），UI 用于绘制进度环
  final ValueNotifier<AirHoverState?> hoverVN = ValueNotifier(null);

  Timer? _tick;

  void register(String id, Rect rect, VoidCallback onTap) {
    final old = _targets[id];
    if (old == null || old.rect != rect) {
      // ignore: avoid_print
      print('[AirClick] register $id rect=$rect');
    }
    _targets[id] = _AirTarget(rect, onTap);
  }

  void unregister(String id) {
    _targets.remove(id);
    if (_currentId == id) _cancel();
  }

  void setEnabled(bool v) {
    if (_enabled == v) return;
    _enabled = v;
    if (!v) _cancel();
  }

  /// 每帧（30Hz）由手势 callback 调用，传入屏幕空间指针位置（null 表示无指针）。
  void update(Offset? pointer) {
    if (!_enabled || pointer == null) {
      _cancel();
      return;
    }
    final now = DateTime.now();
    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) return;

    final hit = _hitTest(pointer);
    if (hit == null) {
      _cancel();
      return;
    }

    if (_currentId != hit.id) {
      // 进入新按钮：重置蓄力
      _currentId = hit.id;
      _dwellStart = now;
      _startTicker();
      _emit(hit, 0.0);
    }
    // 否则继续蓄力，由 ticker 驱动 progress
  }

  // 命中测试：先精确命中，再带死区扩展（指针抖出 ≤8px 不算离开当前按钮）
  // cursor: 前缀的停靠点密集重叠，单独走"最近中心点"逻辑
  _HitResult? _hitTest(Offset p) {
    // 1) 非 cursor 目标：严格命中（含 hitbox 放大），取第一个
    _HitResult? cursorCandidate;
    double cursorMinDist = double.infinity;

    for (final e in _targets.entries) {
      if (_allowedIds != null && !_allowedIds!.contains(e.key)) continue;
      final r = e.value.rect.inflate(expandHitboxPx);
      if (!r.contains(p)) continue;

      if (e.key.startsWith('cursor:')) {
        // cursor 停靠点：记录最近的
        final d = (e.value.rect.center - p).distance;
        if (d < cursorMinDist) {
          cursorMinDist = d;
          cursorCandidate = _HitResult(e.key, e.value);
        }
      } else {
        // 普通按钮：直接返回
        return _HitResult(e.key, e.value);
      }
    }
    if (cursorCandidate != null) return cursorCandidate;

    // 2) 已有蓄力目标的死区
    if (_currentId != null &&
        (_allowedIds == null || _allowedIds!.contains(_currentId))) {
      final cur = _targets[_currentId];
      if (cur != null) {
        final r = cur.rect.inflate(expandHitboxPx + deadZonePx);
        if (r.contains(p)) return _HitResult(_currentId!, cur);
      }
    }
    return null;
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_currentId == null || _dwellStart == null) {
        _tick?.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(_dwellStart!).inMilliseconds;
      final progress = (elapsed / dwellDuration.inMilliseconds).clamp(0.0, 1.0);
      final target = _targets[_currentId];
      if (target == null) {
        _cancel();
        return;
      }
      _emit(_HitResult(_currentId!, target), progress);

      if (progress >= 1.0) {
        _trigger(target);
      }
    });
  }

  void _trigger(_AirTarget target) {
    HapticFeedback.selectionClick();
    target.onTap();
    _cooldownUntil = DateTime.now().add(cooldownDuration);
    _currentId = null;
    _dwellStart = null;
    _tick?.cancel();
    hoverVN.value = null;
  }

  void _cancel() {
    if (_currentId == null) return;
    _currentId = null;
    _dwellStart = null;
    _tick?.cancel();
    hoverVN.value = null;
  }

  void _emit(_HitResult hit, double progress) {
    hoverVN.value = AirHoverState(
      buttonId: hit.id,
      rect: hit.target.rect,
      progress: progress,
    );
  }

  void dispose() {
    _tick?.cancel();
    hoverVN.dispose();
  }
}

class _AirTarget {
  _AirTarget(this.rect, this.onTap);
  final Rect rect;
  final VoidCallback onTap;
}

class _HitResult {
  _HitResult(this.id, this.target);
  final String id;
  final _AirTarget target;
}

class AirHoverState {
  const AirHoverState({
    required this.buttonId,
    required this.rect,
    required this.progress,
  });
  final String buttonId;
  final Rect rect;
  final double progress;
}

/// 把子 widget 注册成空中可点目标。注册的矩形 = widget 在屏幕坐标系下的 bounds。
///
/// 仅在 air 模式下需要时把按钮包一层；其他模式下可直接当透明容器用。
class AirClickable extends StatefulWidget {
  const AirClickable({
    super.key,
    required this.id,
    required this.controller,
    required this.onTap,
    required this.child,
  });

  final String id;
  final AirClickController controller;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<AirClickable> createState() => _AirClickableState();
}

class _AirClickableState extends State<AirClickable> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportRect());
  }

  @override
  void didUpdateWidget(AirClickable old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportRect());
  }

  void _reportRect() {
    final ctx = _key.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    // 每次都用最新的 onTap 重注册（widget update 时按钮启用状态可能变了）
    widget.controller.register(widget.id, rect, widget.onTap);
  }

  @override
  void dispose() {
    widget.controller.unregister(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// 顶层 overlay：绘制 hover 进度环 + hover 高亮。挂在最顶层 Positioned.fill 即可。
class AirClickOverlay extends StatelessWidget {
  const AirClickOverlay({
    super.key,
    required this.controller,
    this.color = const Color(0xFF39FF14),
    this.thickness = 4.0,
  });

  final AirClickController controller;
  final Color color;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<AirHoverState?>(
        valueListenable: controller.hoverVN,
        builder: (_, state, __) {
          if (state == null) return const SizedBox.shrink();
          return CustomPaint(
            painter: _AirHoverPainter(
              state: state,
              color: color,
              thickness: thickness,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _AirHoverPainter extends CustomPainter {
  _AirHoverPainter({
    required this.state,
    required this.color,
    required this.thickness,
  });

  final AirHoverState state;
  final Color color;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = state.rect;
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    // 进度环半径：比按钮长边略大
    final r = math.max(rect.width, rect.height) / 2 + thickness * 1.5;

    // 背景圈（暗）
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = color.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness,
    );

    // 进度弧（亮）：从顶部 -π/2 顺时针
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      -math.pi / 2,
      2 * math.pi * state.progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round,
    );

    // hover 时按钮内填一层淡色，提示选中
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(2),
        const Radius.circular(12),
      ),
      Paint()..color = color.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_AirHoverPainter old) =>
      old.state.buttonId != state.buttonId ||
      old.state.progress != state.progress ||
      old.state.rect != state.rect;
}
