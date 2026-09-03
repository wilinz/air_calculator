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

import 'size.dart';
import 'style.dart';

import 'syntax_tree.dart';

const thinspace = Measurement(value: 3, unit: Unit.mu);
const mediumspace = Measurement(value: 4, unit: Unit.mu);
const thickspace = Measurement(value: 5, unit: Unit.mu);

const Map<AtomType, Map<AtomType, Measurement>> _spacings = {
  AtomType.ord: {
    AtomType.op: thinspace,
    AtomType.bin: mediumspace,
    AtomType.rel: thickspace,
    AtomType.inner: thinspace,
  },
  AtomType.op: {
    AtomType.ord: thinspace,
    AtomType.op: thinspace,
    AtomType.rel: thickspace,
    AtomType.inner: thinspace,
  },
  AtomType.bin: {
    AtomType.ord: mediumspace,
    AtomType.op: mediumspace,
    AtomType.open: mediumspace,
    AtomType.inner: mediumspace,
  },
  AtomType.rel: {
    AtomType.ord: thickspace,
    AtomType.op: thickspace,
    AtomType.open: thickspace,
    AtomType.inner: thickspace,
  },
  AtomType.open: {},
  AtomType.close: {
    AtomType.op: thinspace,
    AtomType.bin: mediumspace,
    AtomType.rel: thickspace,
    AtomType.inner: thinspace,
  },
  AtomType.punct: {
    AtomType.ord: thinspace,
    AtomType.op: thinspace,
    AtomType.rel: thickspace,
    AtomType.open: thinspace,
    AtomType.close: thinspace,
    AtomType.punct: thinspace,
    AtomType.inner: thinspace,
  },
  AtomType.inner: {
    AtomType.ord: thinspace,
    AtomType.op: thinspace,
    AtomType.bin: mediumspace,
    AtomType.rel: thickspace,
    AtomType.open: thinspace,
    AtomType.punct: thinspace,
    AtomType.inner: thinspace,
  },
  AtomType.spacing: {},
};

const Map<AtomType, Map<AtomType, Measurement>> _tightSpacings = {
  AtomType.ord: {
    AtomType.op: thinspace,
  },
  AtomType.op: {
    AtomType.ord: thinspace,
    AtomType.op: thinspace,
  },
  AtomType.bin: {},
  AtomType.rel: {},
  AtomType.open: {},
  AtomType.close: {
    AtomType.op: thinspace,
  },
  AtomType.punct: {},
  AtomType.inner: {
    AtomType.op: thinspace,
  },
  AtomType.spacing: {},
};

Measurement getSpacingSize(AtomType left, AtomType right, MathStyle style) =>
    (style <= MathStyle.script
        ? (_tightSpacings[left]?[right])
        : _spacings[left]?[right]) ??
    Measurement.zero;
