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

/// Base class for exceptions.
abstract class FlutterMathException implements Exception {
  String get message;

  String get messageWithType;
}

/// Exceptions occured during build.
class BuildException implements FlutterMathException {
  @override
  final String message;
  final StackTrace? trace;

  const BuildException(this.message, {this.trace});

  @override
  String get messageWithType => 'Build Exception: $message';
}
