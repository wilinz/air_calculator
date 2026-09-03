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

import '../ast/syntax_tree.dart';
import '../parser/tex/settings.dart';
import '../utils/log.dart';
import 'exception.dart';

abstract class EncodeResult {
  const EncodeResult();
  String stringify(covariant EncodeConf conf);
}

class StaticEncodeResult extends EncodeResult {
  const StaticEncodeResult(this.string);

  final String string;

  @override
  String stringify(EncodeConf conf) => string;
}

class NonStrictEncodeResult extends EncodeResult {
  final String errorCode;
  final String errorMsg;
  final EncodeResult placeHolder;

  const NonStrictEncodeResult(
    this.errorCode,
    this.errorMsg, [
    this.placeHolder = const StaticEncodeResult(''),
  ]);

  NonStrictEncodeResult.string(
    this.errorCode,
    this.errorMsg, [
    String placeHolder = '',
  ]) : placeHolder = StaticEncodeResult(placeHolder);

  @override
  String stringify(EncodeConf conf) {
    conf.reportNonstrict(errorCode, errorMsg);
    return placeHolder.stringify(conf);
  }
}

typedef EncoderFun<T extends GreenNode> = EncodeResult Function(T node);

typedef StrictFun = Strict Function(String errorCode, String errorMsg,
    [dynamic token]);

abstract class EncodeConf {
  final Strict strict;

  final StrictFun? strictFun;

  const EncodeConf({
    this.strict = Strict.warn,
    this.strictFun,
  });

  void reportNonstrict(String errorCode, String errorMsg, [dynamic token]) {
    final strict = this.strict != Strict.function
        ? this.strict
        : (strictFun?.call(errorCode, errorMsg, token) ?? Strict.warn);
    switch (strict) {
      case Strict.ignore:
        return;
      case Strict.error:
        throw EncoderException(
            "Nonstrict Tex encoding and strict mode is set to 'error': "
            '$errorMsg [$errorCode]',
            token);
      case Strict.warn:
        warn("Nonstrict Tex encoding and strict mode is set to 'warn': "
            '$errorMsg [$errorCode]');
        break;
      default:
        warn('Nonstrict Tex encoding and strict mode is set to '
            "unrecognized '$strict': $errorMsg [$errorCode]");
    }
  }
}
