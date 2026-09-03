import 'package:flutter/rendering.dart';

extension RenderBoxLayout on RenderBox {
  /// Returns the size of render box given the provided [BoxConstraints].
  ///
  /// The `dry` flag indicates that no real layout pass but only a dry
  /// layout pass should be executed on the render box.
  /// Defaults to true.
  Size getLayoutSize(BoxConstraints constraints, {bool dry = true}) {
    final Size boxSize;
    if (dry) {
      boxSize = getDryLayout(constraints);
    } else {
      layout(constraints, parentUsesSize: true);
      boxSize = size;
    }
    return boxSize;
  }
}
