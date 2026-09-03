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

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

class DisplayMath extends StatelessWidget {
  final String expression;

  const DisplayMath({
    Key? key,
    required this.expression,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(expression, softWrap: true),
            ),
            Divider(
              thickness: 1.0,
              height: 1.0,
            ),
            Expanded(
              child: Center(child: Math.tex(expression)),
            )
          ],
        ),
      );
}
