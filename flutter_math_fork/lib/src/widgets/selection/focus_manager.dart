// Copyright the flutter_math authors (https://github.com/znjameswu/flutter_math)
// and the flutter_math_fork maintainers (https://github.com/simpleclub/flutter_math).
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

import 'package:flutter/widgets.dart';

mixin FocusManagerMixin<T extends StatefulWidget> on State<T> {
  FocusNode get focusNode;

  late FocusNode _oldFocusNode;

  late FocusAttachment _focusAttachment;

  @override
  void initState() {
    super.initState();

    _focusAttachment = focusNode.attach(context);
    _oldFocusNode = focusNode;
  }

  @override
  void didUpdateWidget(T oldWidget) {
    if (focusNode != _oldFocusNode) {
      _focusAttachment.detach();
      _focusAttachment = focusNode.attach(context);
      _oldFocusNode = focusNode;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _focusAttachment.detach();
    super.dispose();
  }

  @mustCallSuper
  @override
  Widget build(BuildContext context) {
    super.build(context);
    _focusAttachment.reparent();
    return _NullWidget();
  }
}

class _NullWidget extends StatelessWidget {
  const _NullWidget();

  @override
  Widget build(BuildContext context) {
    throw FlutterError(
        'Widgets that mix FocusManagerMixin into their State must call'
        'super.build() but must ignore the return value of the superclass.');
  }
}
