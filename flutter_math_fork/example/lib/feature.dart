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

import 'package:flutter/material.dart';

import 'display.dart';
import 'supported_data.dart';

const largeSections = {
  'Delimiter Sizing',
  'Environment',
  'Unicode Mathematical Alphanumeric Symbols',
};

class FeaturePage extends StatelessWidget {
  const FeaturePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final entries = supportedData.entries.toList();
    return ListView.builder(
      itemCount: supportedData.length,
      itemBuilder: (context, i) => Column(
        children: <Widget>[
          Text(
            entries[i].key,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: entries[i].value.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent:
                  largeSections.contains(entries[i].key) ? 250 : 125,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1,
            ),
            itemBuilder: (BuildContext context, int j) =>
                DisplayMath(expression: entries[i].value[j]),
          ),
        ],
      ),
    );
  }
}
