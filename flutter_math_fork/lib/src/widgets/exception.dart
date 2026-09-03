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
