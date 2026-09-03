// Copyright 2026 wilinz.
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

/// LaTeX 表达式求值。
///
/// 纯计算，不需要模型，也不持有句柄；直接调 Rust 侧的 latex-calc。
/// 原先这一段是 Flutter 里约 400 行 Dart（正则改写成中缀串 + math_expressions），
/// 结构信息在改写时就丢了，错误也一律塌成 null。
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

import 'bindings.dart' as bindings;

/// 求值失败的原因。与 C 侧的 AIRCALC_CALC_* 一一对应。
enum CalcErrorKind {
  /// 输入为空或只有空白
  empty,

  /// 语法错误：括号不匹配、缺操作数
  syntax,

  /// 不认识的字符或命令
  unknownToken,

  /// 结构合法但语义不支持：未绑定变量、非方阵行列式等
  unsupported,

  /// 数学上无定义：除零、负数开偶次方、ln 非正数、溢出
  notFinite,

  /// 阶乘参数非法或过大
  factorial,

  /// 嵌套过深
  tooDeep,

  /// 未知错误码（C 侧新增了码而 Dart 没跟上时的兜底）
  unknown;

  static CalcErrorKind fromCode(int code) => switch (code) {
        -100 => CalcErrorKind.empty,
        -101 => CalcErrorKind.syntax,
        -102 => CalcErrorKind.unknownToken,
        -103 => CalcErrorKind.unsupported,
        -104 => CalcErrorKind.notFinite,
        -105 => CalcErrorKind.factorial,
        -106 => CalcErrorKind.tooDeep,
        _ => CalcErrorKind.unknown,
      };
}

class CalcException implements Exception {
  final CalcErrorKind kind;
  final String expression;

  const CalcException(this.kind, this.expression);

  @override
  String toString() => 'CalcException($kind): $expression';
}

/// 求值 [expr]，返回可直接显示的结果字符串。
///
/// 失败抛 [CalcException]；调用方想要"失败即 null"的旧行为，用
/// [evalLatexOrNull]。
String evalLatex(String expr) {
  final cExpr = expr.toNativeUtf8();
  final errPtr = calloc<ffi.Int32>();
  try {
    final out = bindings.aircalc_eval_latex(cExpr.cast(), errPtr);
    if (out == ffi.nullptr) {
      throw CalcException(CalcErrorKind.fromCode(errPtr.value), expr);
    }
    try {
      return out.cast<Utf8>().toDartString();
    } finally {
      // 结果字符串归 Rust 的分配器所有，必须还回去
      bindings.aircalc_string_free(out);
    }
  } finally {
    calloc.free(cExpr);
    calloc.free(errPtr);
  }
}

/// 求值 [expr]，失败返回 null。
String? evalLatexOrNull(String expr) {
  try {
    return evalLatex(expr);
  } on CalcException {
    return null;
  }
}
