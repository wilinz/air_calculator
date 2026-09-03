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

/// 空中手写数学公式识别。
///
/// 笔画序列进，LaTeX 出。特征提取、模型推理与贪心解码全在 Rust 侧完成，
/// 一次识别只跨一次 FFI 边界。
library;

export 'src/recognizer.dart' show Recognizer, RecognitionResult, MwhBackend, AircalcException;
export 'src/stroke.dart' show StrokePoint, Stroke;
export 'src/calculator.dart'
    show evalLatex, evalLatexOrNull, CalcException, CalcErrorKind;
