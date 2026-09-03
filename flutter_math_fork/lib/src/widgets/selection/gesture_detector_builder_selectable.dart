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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'gesture_detector_builder.dart';

class SelectableMathSelectionGestureDetectorBuilder
    extends MathSelectionGestureDetectorBuilder {
  SelectableMathSelectionGestureDetectorBuilder({
    required super.delegate,
  });

  @override
  void onForcePressStart(ForcePressDetails details) {
    super.onForcePressStart(details);
    if (delegate.selectionEnabled && shouldShowSelectionToolbar) {
      delegate.showToolbar();
    }
  }

  @override
  void onForcePressEnd(ForcePressDetails details) {
    // Not required.
  }

  @override
  void onSingleLongTapMoveUpdate(LongPressMoveUpdateDetails details) {
    if (delegate.selectionEnabled) {
      delegate.handleSelectionChanged(
        delegate.getWordsRangeInRange(
            from: details.globalPosition - details.offsetFromOrigin,
            to: details.globalPosition),
        SelectionChangedCause.longPress,
      );
    }
  }

  @override
  void onSingleTapUp(TapDragUpDetails details) {
    delegate.hide();
    if (delegate.selectionEnabled) {
      switch (Theme.of(delegate.context).platform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          delegate.selectPositionAt(
            from: lastTapDownPosition!,
            cause: SelectionChangedCause.tap,
          );
          // Should select word edge here, but not supporting now
          break;
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          delegate.selectPositionAt(
            from: lastTapDownPosition!,
            cause: SelectionChangedCause.tap,
          );
          break;
      }
    }
    // if (_state.widget.onTap != null)
    //   _state.widget.onTap();
  }

  @override
  void onSingleLongTapStart(LongPressStartDetails details) {
    if (delegate.selectionEnabled) {
      delegate.selectWordAt(
        offset: details.globalPosition,
        cause: SelectionChangedCause.longPress,
      );

      Feedback.forLongPress(delegate.context);

      // renderEditable.selectWord(cause: SelectionChangedCause.longPress);
      // Feedback.forLongPress(_state.context);
    }
  }
}
