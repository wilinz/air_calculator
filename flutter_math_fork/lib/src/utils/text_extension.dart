import 'package:flutter/widgets.dart';
import 'num_extension.dart';

extension TextSelectionExt on TextSelection {
  bool within(TextRange range) => start >= range.start && end <= range.end;
  TextSelection constrainedBy(TextRange range) => TextSelection(
        baseOffset: baseOffset.clampInt(range.start, range.end),
        extentOffset: extentOffset.clampInt(range.start, range.end),
      );
}
