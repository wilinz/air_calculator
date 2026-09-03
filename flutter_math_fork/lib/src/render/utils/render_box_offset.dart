import 'package:flutter/rendering.dart';

extension RenderBoxOffsetExt on RenderBox {
  Offset get offset => (parentData as BoxParentData).offset;
  set offset(Offset value) {
    (parentData as BoxParentData).offset = value;
  }

  double get layoutHeight => getDistanceToBaseline(TextBaseline.alphabetic)!;

  double get layoutDepth =>
      size.height - getDistanceToBaseline(TextBaseline.alphabetic)!;
}
