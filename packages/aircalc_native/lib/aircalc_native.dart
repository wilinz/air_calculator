/// 空中手写数学公式识别。
///
/// 笔画序列进，LaTeX 出。特征提取、模型推理与贪心解码全在 Rust 侧完成，
/// 一次识别只跨一次 FFI 边界。
library;

export 'src/recognizer.dart' show Recognizer, RecognitionResult, MwhBackend, AircalcException;
export 'src/stroke.dart' show StrokePoint, Stroke;
export 'src/calculator.dart'
    show evalLatex, evalLatexOrNull, CalcException, CalcErrorKind;
