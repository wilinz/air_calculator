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

class LayoutBuilderPreserveBaseline
    extends ConstrainedLayoutBuilder<BoxConstraints> {
  /// Creates a widget that defers its building until layout.
  ///
  /// The [builder] argument must not be null.
  const LayoutBuilderPreserveBaseline({
    super.key,
    required super.builder,
  });

  @override
  _RenderLayoutBuilderPreserveBaseline createRenderObject(
          BuildContext context) =>
      _RenderLayoutBuilderPreserveBaseline();
}

class _RenderLayoutBuilderPreserveBaseline extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderConstrainedLayoutBuilder<BoxConstraints, RenderBox> {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      child?.getDistanceToActualBaseline(baseline);

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      child?.getDryLayout(constraints) ?? Size.zero;

  @override
  void performLayout() {
    final constraints = this.constraints;
    runLayoutCallback();
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child!.size);
    } else {
      size = constraints.biggest;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }

  bool _debugThrowIfNotCheckingIntrinsics() {
    assert(() {
      if (!RenderObject.debugCheckingIntrinsics) {
        throw FlutterError(
            'LayoutBuilder does not support returning intrinsic dimensions.\n'
            'Calculating the intrinsic dimensions would require '
            'running the layout '
            'callback speculatively, which might mutate the live '
            'render object tree.');
      }
      return true;
    }());

    return true;
  }
}
