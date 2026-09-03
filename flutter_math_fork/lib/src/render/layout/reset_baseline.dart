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

class ResetBaseline extends SingleChildRenderObjectWidget {
  final double height;
  const ResetBaseline({
    super.key,
    required this.height,
    required Widget super.child,
  });

  @override
  RenderResetBaseline createRenderObject(BuildContext context) =>
      RenderResetBaseline(height: height);

  @override
  void updateRenderObject(
          BuildContext context, RenderResetBaseline renderObject) =>
      renderObject..height = height;
}

class RenderResetBaseline extends RenderProxyBox {
  RenderResetBaseline({required double height, RenderBox? child})
      : _height = height,
        super(child);

  double get height => _height;
  double _height;
  set height(double value) {
    if (_height != value) {
      _height = value;
      markNeedsLayout();
    }
  }

  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => height;
}
