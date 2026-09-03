// Copyright the flutter_math authors (https://github.com/znjameswu/flutter_math)
// and the flutter_math_fork maintainers (https://github.com/simpleclub/flutter_math).
// Modifications copyright 2026 wilinz.
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

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class ShiftBaseline extends SingleChildRenderObjectWidget {
  const ShiftBaseline({
    super.key,
    this.relativePos,
    this.offset = 0,
    required Widget super.child,
  });

  final double? relativePos;

  final double offset;

  @override
  RenderShiftBaseline createRenderObject(BuildContext context) =>
      RenderShiftBaseline(relativePos: relativePos, offset: offset);

  @override
  void updateRenderObject(
      BuildContext context, RenderShiftBaseline renderObject) {
    renderObject
      ..relativePos = relativePos
      ..offset = offset;
  }
}

class RenderShiftBaseline extends RenderProxyBox {
  RenderShiftBaseline({
    RenderBox? child,
    double? relativePos,
    double offset = 0,
  })  : _relativePos = relativePos,
        _offset = offset,
        super(child);

  double? get relativePos => _relativePos;
  double? _relativePos;
  set relativePos(double? value) {
    if (_relativePos != value) {
      _relativePos = value;
      markNeedsLayout();
    }
  }

  double get offset => _offset;
  double _offset;
  set offset(double value) {
    if (_offset != value) {
      _offset = value;
      markNeedsLayout();
    }
  }

  var _height = 0.0;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(constraints) ?? Size.zero;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    if (relativePos != null) {
      return relativePos! * _height + offset;
    }
    if (child != null) {
      // assert(!debugNeedsLayout);
      final childBaselineDistance =
          child!.getDistanceToActualBaseline(baseline) ?? _height;
      //ignore: avoid_returning_null
      // if (childBaselineDistance == null) return null;
      return childBaselineDistance + offset;
    } else {
      return super.computeDistanceToActualBaseline(baseline);
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    // We have to hack like this to know the height of this object!!!
    _height = size.height;
  }
}
