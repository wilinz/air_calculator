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

/// Basic utilities to render math equations.
///
/// Please refer to README for usage.
library;

export 'src/ast/options.dart' show MathOptions, FontOptions;
export 'src/ast/size.dart' show MathSize;
export 'src/ast/style.dart' show MathStyle;
export 'src/encoder/exception.dart';
export 'src/parser/tex/parse_error.dart';
export 'src/parser/tex/settings.dart';
export 'src/widgets/controller.dart' show MathController;
export 'src/widgets/exception.dart';
export 'src/widgets/math.dart';
export 'src/widgets/selectable.dart' show SelectableMath;
